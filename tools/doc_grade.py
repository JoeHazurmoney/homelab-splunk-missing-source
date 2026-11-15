"""Reading grade of the repo's Markdown docs (Flesch-Kincaid grade level), standard library only.

Run it in a container from the repo root, never on the host's Python:
  docker run --rm -v "${PWD}:/w:ro" -w /w python:3.14.10-slim python tools/doc_grade.py

  python tools/doc_grade.py [options] [file.md ...]
    (no files)     README.md and every docs/**/*.md
    --target N     the grade a current doc must not exceed (default 8)
    --max-words N  the average words per sentence it must not exceed (default 15, the style guide)
    --worst N      also print each doc's N hardest sentences (default 0)
    --check        exit 1 when a current doc is over either limit (the default only reports)

Only prose is scored. Fenced code blocks, HTML comments, headings and each table's header row are
dropped (headings and headers are labels). Inline code, a link's URL and Markdown markup are
dropped too; a code span counts as one short word. Each list item and each table cell ends a
sentence, so a table body is read as short sentences, one per cell.
Records and specs (docs/records/, docs/specs/) are design or run records: they are scored but
marked "exempt" and never fail --check.
"""
import argparse
import os
import re
import sys

EXEMPT = ("docs/records/", "docs/specs/")
FENCE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN = re.compile(r"(`+)(.+?)\1")
LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
REF_LINK = re.compile(r"!?\[([^\]]*)\]\[[^\]]*\]")
URL = re.compile(r"https?://\S+")
HTML_TAG = re.compile(r"<[^>]+>")
LIST_MARK = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")
# A sentence ends at . ! or ? followed by a space or the end (so 2.5 and file.md don't end one).
SENT_END = re.compile(r"(?<=[.!?])[\"')\]]*\s+|(?<=[.!?])[\"')\]]*$")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’]*")
CODE_WORD = "code"


def blocks(text):
    """Prose pieces of a Markdown text, each one or more sentences: paragraphs (lines joined),
    list items and table body cells."""
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    out, para, in_fence, in_table = [], [], False, False

    def flush():
        if para:
            out.append(" ".join(para))
            para.clear()

    for raw in text.splitlines():
        if FENCE.match(raw):
            flush()
            in_fence, in_table = not in_fence, False
            continue
        if in_fence:
            continue
        line = CODE_SPAN.sub(" " + CODE_WORD + " ", raw)
        if not line.lstrip().startswith("|"):
            in_table = False
        if not line.strip():
            flush()
        elif re.match(r"\s*#{1,6}\s", line):
            flush()  # a heading is a label, not prose
        elif line.lstrip().startswith("|"):
            flush()
            if in_table and not TABLE_SEP.match(line):
                cells = line.replace("\\|", " ").strip().strip("|").split("|")
                out.extend(c for c in cells if c.strip())
            in_table = True  # the first row of a table is its header: labels, not prose
            continue
        elif LIST_MARK.match(line):
            flush()
            para.append(LIST_MARK.sub("", line))
        else:
            para.append(line.lstrip("> "))
    flush()
    return out


def clean(piece):
    piece = LINK.sub(r"\1", piece)
    piece = REF_LINK.sub(r"\1", piece)
    piece = URL.sub(" ", piece)
    piece = HTML_TAG.sub(" ", piece)
    piece = re.sub(r"[*_~]{1,3}", "", piece)
    return re.sub(r"\s+", " ", piece).strip()


def sentences(text):
    for piece in blocks(text):
        for s in SENT_END.split(clean(piece)):
            if re.search(r"[A-Za-z]", s or ""):
                yield s.strip()


def syllables(word):
    """A common English heuristic: vowel groups, less a silent final e, -ed or -es."""
    w = re.sub(r"[^a-z]", "", word.lower())
    if len(w) <= 3:
        return 1  # also a number: it reads as one short word
    n = len(re.findall(r"[aeiouy]+", w))
    if w.endswith("e") and not re.search(r"[^aeiouy]le$", w):
        n -= 1  # file, role, make (but table, little)
    elif re.search(r"[^aeiouytd]ed$", w):
        n -= 1  # enabled, used, stopped (but added, wanted)
    elif re.search(r"[^aeiouyszxgch]es$", w):
        n -= 1  # files, makes (but changes, uses, boxes, matches)
    return max(1, n)


def score(sents):
    words = syl = 0
    for s in sents:
        ws = WORD.findall(s)
        words += len(ws)
        syl += sum(syllables(w) for w in ws)
    if not sents or not words:
        return None
    return 0.39 * words / len(sents) + 11.8 * syl / words - 15.59, words, len(sents)


def sentence_grade(s):
    r = score([s])
    return r[0] if r else 0


def default_files(root):
    files = [os.path.join(root, "README.md")] if os.path.exists(os.path.join(root, "README.md")) else []
    for d, _, names in sorted(os.walk(os.path.join(root, "docs"))):
        files += [os.path.join(d, n) for n in sorted(names) if n.endswith(".md")]
    return files


def main(argv):
    ap = argparse.ArgumentParser(description="Flesch-Kincaid grade of the repo's Markdown prose.")
    ap.add_argument("files", nargs="*")
    ap.add_argument("--target", type=float, default=8)
    ap.add_argument("--max-words", type=float, default=15)
    ap.add_argument("--worst", type=int, default=0)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    root = os.getcwd()
    files = a.files or default_files(root)
    over = 0
    print(f"{'grade':>6} {'words':>6} {'sent.':>6} {'w/sent':>6}  result  file")
    for f in files:
        rel = os.path.relpath(f, root).replace(os.sep, "/")
        sents = list(sentences(open(f, encoding="utf-8").read()))
        r = score(sents)
        if r is None:
            print(f"{'-':>6} {0:>6} {0:>6} {'-':>6}  empty   {rel}")
            continue
        grade, words, n = r
        if rel.startswith(EXEMPT):
            result = "exempt"
        elif grade <= a.target and words / n <= a.max_words:
            result = "ok"
        else:
            result, over = "OVER", over + 1
        print(f"{grade:6.1f} {words:6d} {n:6d} {words / n:6.1f}  {result:<6}  {rel}")
        for s in sorted(sents, key=sentence_grade, reverse=True)[:a.worst]:
            print(f"{'':>8}{sentence_grade(s):5.1f}  {s[:160]}")
    print(f"target: grade {a.target:g} or below and {a.max_words:g} words a sentence or fewer;"
          f" {over} current doc(s) over")
    return 1 if a.check and over else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
