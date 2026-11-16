"""Capture screenshots of the HL Data Health dashboards (Dashboard Studio) for docs and decks.

For each page it saves a full-view PNG plus one PNG per panel (the element whose data-id is the
panel's viz_* id). Manage is captured once per tab. Studio scrolls inside its own container, so
each page gets a viewport tall enough to show every panel without scrolling.

Run it in its container (tools/capture/Dockerfile) on the Docker network that Splunk is on.
The password is read from a file mounted at run time; it is never written anywhere.

    python3 capture_screens.py --set s0 --pages overview host:wd2l-recv manage soh
"""
import argparse
import os
import sys
import time

from playwright.sync_api import sync_playwright

APP = "hl_data_health"
PAGES = {
    "overview": ("dh_overview", 3000),
    "host": ("dh_host", 3800),
    "manage": ("dh_manage", 4200),
    "soh": ("dh_soh", 2800),
}
MANAGE_TABS = ["Mute & thresholds", "Expected list", "Test blocks (admin)", "Admin log"]


def slug(text):
    return "".join(c if c.isalnum() else "-" for c in text.lower()).strip("-").replace("--", "-")


def login(page, base, user, password):
    page.goto(base + "/en-US/account/login")
    page.fill("input#username", user)
    page.fill("input#password", password)
    page.keyboard.press("Enter")
    page.wait_for_url(lambda u: "account/login" not in u, timeout=60000)


def panels(page, outdir):
    """Save each viz_* panel: of the elements sharing a data-id, the largest one."""
    ids = page.evaluate(
        "() => [...new Set([...document.querySelectorAll('[data-id^=viz_]')]"
        ".map(e => e.getAttribute('data-id')))]"
    )
    saved = 0
    for viz in ids:
        best, area = None, 0
        for el in page.query_selector_all('[data-id="%s"]' % viz):
            box = el.bounding_box()
            if box and box["height"] > 20 and box["width"] * box["height"] > area:
                best, area = el, box["width"] * box["height"]
        if best is not None:
            best.screenshot(path=os.path.join(outdir, viz + ".png"))
            saved += 1
    return saved


def shoot(page, outdir, wait):
    os.makedirs(outdir, exist_ok=True)
    time.sleep(wait)
    page.screenshot(path=os.path.join(outdir, "_full.png"))
    n = panels(page, outdir)
    print("%s: full view + %d panels" % (outdir, n), flush=True)


def apply(page):
    """Open the visible Confirm list of a Manage form and choose its Apply line (writes the change)."""
    box = page.locator('[data-test="input-item"]').filter(has_text="Confirm (writes the change)")
    box = box.locator("visible=true").first
    box.locator('[data-test="select"]').first.click()
    option = page.get_by_role("option").filter(has_text="Apply").first
    print("applying: " + option.inner_text(), flush=True)
    option.click()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", default="http://wd2l-splunk:8000")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password-file", default="/secrets/pw")
    ap.add_argument("--out", default="/out")
    ap.add_argument("--set", required=True, help="scenario name, used as the output folder")
    ap.add_argument("--pages", nargs="+", required=True,
                    help="overview, host:<name>, manage, manage:<tab label>, soh")
    ap.add_argument("--wait", type=int, default=35, help="seconds to let searches finish")
    ap.add_argument("--query", default="", help="URL query for every page, e.g. form.ov_host=pi5&...")
    ap.add_argument("--apply", action="store_true",
                    help="Manage only: after the capture, choose Apply under Confirm and capture again")
    args = ap.parse_args()

    with open(args.password_file) as fh:
        password = fh.read().strip()

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1600, "height": 1000})
        login(page, args.base, args.user, password)
        for spec in args.pages:
            name, _, arg = spec.partition(":")
            if name not in PAGES:
                sys.exit("unknown page: " + spec)
            view, height = PAGES[name]
            page.set_viewport_size({"width": 1600, "height": height})
            url = "%s/en-US/app/%s/%s" % (args.base, APP, view)
            query = [q for q in ("form.host=" + arg if name == "host" else "", args.query) if q]
            if query:
                url += "?" + "&".join(query)
            page.goto(url)
            folder = os.path.join(args.out, args.set, name + ("-" + slug(arg) if arg else ""))
            if name != "manage":
                shoot(page, folder, args.wait)
                continue
            for tab in ([arg] if arg else MANAGE_TABS):
                page.get_by_text(tab, exact=True).first.click()
                folder = os.path.join(args.out, args.set, "manage-" + slug(tab))
                shoot(page, folder, args.wait)
                if args.apply:
                    apply(page)
                    shoot(page, folder + "-applied", args.wait)
        browser.close()


if __name__ == "__main__":
    main()
