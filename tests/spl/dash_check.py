"""Static checks of the hl_data_health Dashboard Studio views (spec §7.8, §8), and query extraction.

Runs inside the Splunk container (tests/spl/run.sh pipes it to /opt/splunk/bin/python3) against
the deployed app, so it needs only the standard library.

  check <app_dir>                       every view: exit 1 and print the problems, if any
  queries <app_dir> <view> [tok=value]  each data source's resolved SPL (chains joined to their
                                        base, tokens substituted from the arguments, else the
                                        inputs' defaults), one "ds_id<TAB>spl" per line; a data
                                        source with an unset token prints "ds_id<TAB>#unset <tok>"
  chains <app_dir> <view> [tok=value]   the same, as "ds_id<TAB>base<TAB>spl" with each chain's own
                                        post-process SPL and the id of its base ("-" for a search),
                                        so a test can run chains through the real post-process path
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

TOKEN = re.compile(r"\$([A-Za-z0-9_.:]+)(\|[a-z])?\$")
MACRO = re.compile(r"`([a-z0-9_]+)(?:\(([^`]*)\))?`")
# The only panels that may read raw indexes (spec §8 "Scale": the host-detail chart, plus three
# single-entity, on-demand exceptions), each with the constraint its base search must carry: the
# host terms subsearch (a token never reaches the SPL, see dh_ui_host_terms), or for Hyper-V the
# Worker-Admin source and the host as a quoted term.
HOST_TERMS = "[| makeresults | eval host=${tok}|s$ | `dh_ui_host_terms`]"
RAW_OK = {
    ("dh_host", "ds_chart"): HOST_TERMS.format(tok="host"),
    ("dh_host", "ds_errors"): HOST_TERMS.format(tok="host"),
    ("dh_host", "ds_hyperv"): 'source="XmlWinEventLog:Microsoft-Windows-Hyper-V-Worker-Admin" $host|s$ ',
    ("dh_manage", "ds_bk_sources"): HOST_TERMS.format(tok="bk_host"),
}
# Raw data anywhere in a query: tstats, or an index other than the summary index data_health.
RAW = re.compile(r'\btstats\b|\bindex\s*(=|!=)\s*"?(?!data_health\b)[A-Za-z0-9_*]|\bindex\s+IN\s*\(', re.I)


def load(path):
    root = ET.parse(path).getroot()
    definition = json.loads(root.find("definition").text)
    return root, definition


def macros(app_dir):
    """macro name -> set of arg counts, from default/macros.conf."""
    found = {}
    with open(os.path.join(app_dir, "default", "macros.conf"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\[([a-z0-9_]+)(?:\((\d+)\))?\]", line)
            if m:
                found.setdefault(m.group(1), set()).add(int(m.group(2) or 0))
    return found


def views(app_dir):
    d = os.path.join(app_dir, "default", "data", "ui", "views")
    return {f[:-4]: os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".xml")}


def input_tokens(definition):
    return {i["options"]["token"]: i for i in definition.get("inputs", {}).values()}


def split_args(s):
    """Macro arguments split on commas outside double quotes."""
    out, cur, q = [], "", False
    for ch in s:
        if ch == '"':
            q = not q
        if ch == "," and not q:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def resolve(ds_id, sources):
    ds = sources[ds_id]
    q = ds["options"]["query"]
    if ds["type"] == "ds.chain":
        return resolve(ds["options"]["extend"], sources) + " " + q
    return q


def check(app_dir):
    problems = []
    known = macros(app_dir)
    all_views = views(app_dir)
    nav = open(os.path.join(app_dir, "default", "data", "ui", "nav", "default.xml"), encoding="utf-8").read()
    for name, path in all_views.items():
        p = lambda msg: problems.append(f"{name}: {msg}")
        root, d = load(path)
        if root.get("version") != "2" or root.get("theme") != "dark":
            p("must be <dashboard version=\"2\" theme=\"dark\"> (Dashboard Studio, dark)")
        if f'name="{name}"' not in nav:
            p("not in the app nav")
        sources, vizs, inputs = d.get("dataSources", {}), d.get("visualizations", {}), d.get("inputs", {})
        layout = d.get("layout", {})
        placed = [s["item"] for s in layout.get("structure", [])]
        for v in vizs:
            if v not in placed:
                p(f"visualization {v} is not in the layout")
        for item in placed:
            if item not in vizs:
                p(f"layout item {item} is not a visualization")
        if sorted(layout.get("globalInputs", [])) != sorted(inputs):
            p("globalInputs must list every input exactly once")
        for k, ds in sources.items():
            if ds["type"] == "ds.chain" and ds["options"].get("extend") not in sources:
                p(f"{k} extends a missing data source")
        for k, obj in list(vizs.items()) + list(inputs.items()):
            for ref in obj.get("dataSources", {}).values():
                if ref not in sources:
                    p(f"{k} uses missing data source {ref}")
            if obj.get("type") == "splunk.table" and obj.get("options", {}).get("count") != 25:
                p(f"{k}: tables paginate at 25 (options.count)")
        used = {ref for obj in list(vizs.values()) + list(inputs.values()) for ref in obj.get("dataSources", {}).values()}
        used |= {sources[r]["options"]["extend"] for r in list(used) if sources.get(r, {}).get("type") == "ds.chain"}
        for k in sources:
            if k not in used:
                p(f"data source {k} is not used")
        toks = input_tokens(d)
        submit = layout.get("options", {}).get("submitButton") is True
        refresh = json.dumps(d.get("defaults", {})) + json.dumps(sources)
        writes = []
        for k, ds in sources.items():
            q = ds["options"]["query"]
            full = resolve(k, sources)
            for t, f in TOKEN.findall(q):
                if f != "|s":
                    p(f"{k} splices token ${t}$ raw: use ${t}|s$ (a quoted, escaped string)")
                if t not in toks:
                    p(f"{k} uses token ${t}$, which no input sets")
                    continue
                opts = toks[t]["options"]
                if "defaultValue" not in opts and not opts.get("selectFirstSearchResult") and not submit:
                    p(f"{k}: token {t} has no default (allowed only behind a submit button)")
            for m, args in MACRO.findall(q):
                n = 0 if not args else len(split_args(args))
                if n not in known.get(m, set()):
                    p(f"{k}: macro {m}({n}) is not defined")
            if re.search(r"\|\s*collect\b", full):
                p(f"{k}: no collect from the UI (spec §7.8)")
            if re.search(r"outputlookup|_write\(", q):
                writes.append(k)
                if not re.search(r"\$[a-z]+_confirm\|s\$", q):
                    p(f"{k} writes without a confirmation token")
            if RAW.search(q):
                need = RAW_OK.get((name, k))
                if need is None:
                    p(f"{k} reads raw data (spec §8: panels read KV or summary data)")
                elif need not in q:
                    p(f"{k} reads raw data without its base-search constraint: {need}")
        if writes:
            if not submit or layout["options"].get("submitOnDashboardLoad") is not False:
                p("writes need submitButton=true and submitOnDashboardLoad=false (spec §7.8)")
            if '"refresh"' in refresh:
                p("a dashboard that writes must not auto-refresh (spec §7.8)")
            for t, i in toks.items():
                if t.endswith("_confirm") and ("defaultValue" in i["options"] or i["options"].get("selectFirstSearchResult")):
                    p(f"confirmation {t} must have no default")
        want_refresh = name == "dh_overview"
        has_refresh = d.get("defaults", {}).get("dataSources", {}).get("ds.search", {}).get("options", {}).get("refresh") == "60s"
        if want_refresh != has_refresh:
            p("only the Overview refreshes, every 60 s")
        for k, v in vizs.items():
            for h in v.get("eventHandlers", []):
                if h["type"] != "drilldown.linkToDashboard":
                    continue
                o = h["options"]
                if o.get("app") != "hl_data_health" or o.get("dashboard") not in all_views:
                    p(f"{k} links to a missing dashboard {o.get('app')}/{o.get('dashboard')}")
                    continue
                _, target = load(all_views[o["dashboard"]])
                for t in o.get("tokens", []):
                    if t["token"] not in input_tokens(target):
                        p(f"{k} sets token {t['token']}, which {o['dashboard']} has no input for")
                    field = re.match(r"row\.([A-Za-z0-9_]+)\.value$", t["value"])
                    if not field:
                        p(f"{k}: drilldown value {t['value']} is not a row field")
                    else:
                        print(f"drilldown {name}.{k} -> {o['dashboard']}?form.{t['token']}=<{field.group(1)}> from {v['dataSources']['primary']}")
    for msg in problems:
        print(msg)
    return 1 if problems else 0


def queries(app_dir, view, pairs, chains=False):
    _, d = load(views(app_dir)[view])
    sources = d.get("dataSources", {})
    toks = input_tokens(d)
    values = {t: i["options"]["defaultValue"] for t, i in toks.items() if "defaultValue" in i["options"]}
    values.update(dict(kv.split("=", 1) for kv in pairs))

    def sub(m):
        v = values[m.group(1)]
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"' if m.group(2) == "|s" else v

    for k, ds in sources.items():
        q = resolve(k, sources)
        head = f"{k}\t" + ((ds["options"]["extend"] if ds["type"] == "ds.chain" else "-") + "\t" if chains else "")
        unset = [t for t, _ in TOKEN.findall(q) if t not in values]
        if unset:
            print(f"{head}#unset {' '.join(sorted(set(unset)))}")
            continue
        print(head + TOKEN.sub(sub, ds["options"]["query"] if chains else q))
    return 0


if __name__ == "__main__":
    mode, app = sys.argv[1], sys.argv[2]
    if mode == "check":
        sys.exit(check(app))
    sys.exit(queries(app, sys.argv[3], sys.argv[4:], chains=(mode == "chains")))
