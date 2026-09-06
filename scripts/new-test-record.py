#!/usr/bin/env python3
"""Generate a blank manual-test record from TESTING.md section 4.

    python scripts/new-test-record.py                 # -> .claude/testing/<date>_e2e_manual_test.md
    python scripts/new-test-record.py --stdout        # print instead of writing
    python scripts/new-test-record.py -o somewhere.md

WHY THIS EXISTS

The 2026-09-06 run was recorded by hand-editing a copy of the checklist. VS Code renumbers a nested
ordered list as you edit it, so items silently changed number mid-run, and the result was hard to
read back. Worse, the copy and the checklist drifted: neither was clearly the source of truth.

So the checklist lives in exactly one place - TESTING.md section 4 - and the record is generated
from it as a flat table with a Result column. Nothing is nested, nothing renumbers, and a diff of
two runs lines up row for row.

Re-run it whenever the checklist changes; a record already in progress is never overwritten
(the script refuses if the file exists).
"""
import argparse
import datetime
import pathlib
import re
import sys

TESTING = pathlib.Path('TESTING.md')
SECTION = '## 4. Full end-end-to-end manual test'
OUT_DIR = pathlib.Path('.claude/testing')

# "  1. Home screen" / "     1. all five buttons navigate" - indentation gives the level.
ITEM = re.compile(r'^(\s*)(\d+)\.\s+(.*\S)\s*$')


def checklist(text):
    """Yields (ref, area, check) from the section's nested ordered list.

    `ref` is a dotted path built from position, not from the numbers in the file - those are what
    renumber. `area` carries the nearest top-level heading so the table still reads as grouped
    once it is flat.
    """
    start = text.index(SECTION) + len(SECTION)
    rest = text[start:]
    end = rest.find('\n## ')
    body = rest if end < 0 else rest[:end]

    counters, area = [], ''
    for line in body.split('\n'):
        m = ITEM.match(line)
        if not m:
            continue
        depth = len(m.group(1)) // 3          # the file indents nested items by three spaces
        text_ = m.group(3)
        counters[depth:] = [counters[depth] + 1 if depth < len(counters) else 1]
        ref = '.'.join(str(c) for c in counters)
        if depth == 0:
            area = text_
            continue                          # the area is a heading, not a check
        yield ref, area, text_


def render(rows, when):
    out = [
        '# End-to-end manual test - %s' % when,
        '',
        'Generated from `TESTING.md` section 4 by `scripts/new-test-record.py`. Do not add or renumber',
        'rows by hand - change the checklist and regenerate, or the two will drift.',
        '',
        'Fill in **Result** with PASS / FAIL / SKIP and the firmware, e.g. `PASS stock`. Put anything',
        'worth keeping in **Notes** - a log excerpt, a command, what you actually saw.',
        '',
        '| Ref | Area | Check | Result | Notes |',
        '| --- | --- | --- | --- | --- |',
    ]
    for ref, area, check in rows:
        # A pipe inside a cell would split it; escape rather than lose the text.
        cells = [c.replace('|', r'\|') for c in (ref, area, check)]
        out.append('| %s | %s | %s |  |  |' % tuple(cells))
    out += ['', '## Notes', '', '_Anything that does not belong against a single row._', '']
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--output')
    ap.add_argument('--stdout', action='store_true')
    args = ap.parse_args()

    if not TESTING.is_file():
        sys.exit('ERROR: run this from the repository root - %s not found.' % TESTING)
    text = TESTING.read_text(encoding='utf-8').replace('\r\n', '\n')
    if SECTION not in text:
        sys.exit('ERROR: %s has no section "%s".' % (TESTING, SECTION))

    rows = list(checklist(text))
    if not rows:
        sys.exit('ERROR: found no numbered checks under "%s".' % SECTION)

    when = datetime.date.today().isoformat()
    doc = render(rows, when)

    if args.stdout:
        print(doc)
        return

    path = pathlib.Path(args.output) if args.output else OUT_DIR / ('%s_e2e_manual_test.md' % when)
    if path.exists():
        sys.exit('ERROR: %s already exists - refusing to overwrite a run in progress.' % path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(doc, encoding='utf-8', newline='\n')
    print('%d checks -> %s' % (len(rows), path))


if __name__ == '__main__':
    main()
