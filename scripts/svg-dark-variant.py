#!/usr/bin/env python3
"""svg-dark-variant.py - writes the dark version of a light diagram in images/ (ID-236, ID-239).

    python scripts/svg-dark-variant.py "images/network-traffic-(logical).svg"

writes images/network-traffic-(logical)-dark.svg beside it. ARCHITECTURE.md shows the dark one
through GitHub's <picture> switch when the reader has GitHub's dark theme on. Run it again after
every edit to a light diagram: the dark file is generated, never edited by hand.

The colours are mapped, not inverted. Boxes and panels go dark, text and dark lines go light, and
the protocol colours stay as they are, so a flow is the same colour in both themes. A colour this
map does not know is left alone, so a new one shows up as unchanged in the dark file; add it here.
"""
import re
import sys
from pathlib import Path

# Box and panel fills: light to dark, keeping each one's tint.
FILLS = {
    'FFFFFF': '161B22', 'FAFAFA': '11161D', 'E3F2FD': '0F2438', 'BBDEFB': '1A3A5C', 'F3E5F5': '2A1830',
    'E8F5E9': '11261A', 'C8E6C9': '1B3A24', 'ECEFF1': '1B2128', 'CFD8DC': '3A4652',
}
# Text and dark lines: dark to light.
INKS = {
    '102027': 'E6EDF3', '37474F': 'C9D1D9', '455A64': '9FB0BA', '546E7A': '8FA3AD', '607D8B': '9DB0BA',
    '616161': 'B0B0B0', '1565C0': '64B5F6', '2E7D32': '66BB6A', '1B5E20': '81C784', '6A1B9A': 'CE93D8',
    'C62828': 'EF7A7A', 'E65100': 'FFB74D', '7B1FA2': 'AB47BC', '5D4037': 'BCAAA4', '8D6E00': 'FFD54F',
}
# Pale greens used only as box fills: too light under light text once the text is inverted.
FILL_ONLY = {'A5D6A7': '245A30', '81C784': '2E6B3A'}


def darken(svg: str) -> str:
    # Attribute fills first, so the ink map below cannot catch them.
    svg = re.sub(r'fill="#(A5D6A7|81C784)"', lambda m: f'fill="#{FILL_ONLY[m.group(1).upper()]}"', svg, flags=re.I)
    colours = {**FILLS, **INKS}
    svg = re.sub(r'#([0-9A-Fa-f]{6})\b', lambda m: '#' + colours.get(m.group(1).upper(), m.group(1)), svg)
    svg = svg.replace('background:#161B22', 'background:#0D1117', 1)
    return svg.replace('</title>', ' (dark theme)</title>', 1)


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].endswith('.svg') or sys.argv[1].endswith('-dark.svg'):
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    dst = src.with_name(src.stem + '-dark.svg')
    dst.write_text(darken(src.read_text(encoding='utf-8')), encoding='utf-8', newline='\n')
    print(f'wrote {dst}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
