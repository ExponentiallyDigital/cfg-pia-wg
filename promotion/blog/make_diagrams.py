#!/usr/bin/env python3
"""Draws the blog article's six diagrams as SVG, in the app's own colours (lib/app_colors.dart), so
they sit beside its screenshots. Renders each to a 1600 px wide PNG with headless Chrome, since
WordPress won't take an SVG upload by default.

Usage:  python promotion/blog/make_diagrams.py
Writes: promotion/blog/images/<name>.svg and <name>.png
"""
import datetime
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'images')
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'

# Dark is the app's own palette (lib/app_colors.dart). Light is the same hues darkened to read on a
# white page, for the blog, whose theme is white.
THEMES = {
    'dark': dict(BG='#12141A', SURFACE='#1A1D23', BORDER='#2E3240', TEXT='#E8EAF0', MUTED='#8892A4',
                 HINT='#4A5268', TEAL='#00D4AA', RED='#FF5C5C', AMBER='#EF9F27', LAVENDER='#B69CFF',
                 BLUE='#19B3EE', PERIWINKLE='#8B9CFC'),
    'light': dict(BG='#FFFFFF', SURFACE='#F4F6F9', BORDER='#CDD3DD', TEXT='#1B1F27', MUTED='#5B6474',
                  HINT='#9AA3B2', TEAL='#00856A', RED='#D23A3A', AMBER='#B86A00', LAVENDER='#6E4FD6',
                  BLUE='#0A7FBF', PERIWINKLE='#4659C9'),
}
SANS = "'Segoe UI', Inter, Arial, sans-serif"
MONO = "Consolas, Menlo, monospace"


def use(theme):
    """Sets the palette every drawing function reads."""
    globals().update(THEMES[theme])


use('dark')


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def text(x, y, s, size=14, color=None, anchor='start', weight=400, font=SANS):
    color = color or TEXT
    lines = s.split('\n')
    out = []
    for i, line in enumerate(lines):
        out.append(f'<text x="{x}" y="{y + i * size * 1.3:.1f}" font-family="{font}" font-size="{size}" '
                   f'font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{esc(line)}</text>')
    return '\n'.join(out)


def box(x, y, w, h, title, sub=None, stroke=None, title_color=None, fill=None, size=14):
    stroke, title_color, fill = stroke or BORDER, title_color or TEXT, fill or SURFACE
    lines = title.split('\n')
    sub_lines = sub.split('\n') if sub else []
    total = len(lines) * size * 1.3 + len(sub_lines) * 12 * 1.35 + (4 if sub else 0)
    top = y + (h - total) / 2 + size * 0.95
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>',
           text(x + w / 2, top, title, size, title_color, 'middle', 600)]
    if sub:
        out.append(text(x + w / 2, top + len(lines) * size * 1.3 + 3, sub, 12, MUTED, 'middle'))
    return '\n'.join(out)


def arrow(x1, y1, x2, y2, color=None, dash=False, width=2):
    color = color or MUTED
    d = ' stroke-dasharray="6 5"' if dash else ''
    mid = 'm' + color.lstrip('#')
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"{d} '
            f'marker-end="url(#{mid})"/>')


def svg(w, h, body):
    colors = (MUTED, TEAL, RED, AMBER, LAVENDER, BLUE, PERIWINKLE)
    markers = ''.join(
        f'<marker id="m{c.lstrip("#")}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        f'orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{c}"/></marker>' for c in colors)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
            f'<defs>{markers}</defs><rect width="{w}" height="{h}" fill="{BG}"/>\n{body}\n</svg>')


def heading(s, sub=None):
    out = text(24, 36, s, 18, TEXT, weight=600)
    if sub:
        out += '\n' + text(24, 58, sub, 13, MUTED)
    return out


def tunnel_drops():
    w, h = 800, 470
    b = [heading('When the tunnel is down',
                 'Switched off, restarting, being rebuilt, or the router booting')]
    xs = [24, 220, 416, 612]
    bw = 164
    # Stock firmware: straight out through the ISP.
    b.append(text(24, 106, 'STOCK FIRMWARE', 12, RED, weight=700))
    y = 118
    b.append(box(xs[0], y, bw, 76, 'Laptop', 'pinned to wgc1'))
    b.append(box(xs[1], y, bw, 76, 'ASUS router', 'tunnel down', stroke=BORDER))
    b.append(box(xs[2], y, bw, 76, 'Your ISP', 'no tunnel, no encryption', stroke=RED))
    b.append(box(xs[3], y, bw, 76, 'Every site\nyou visit', None, stroke=RED))
    for i in range(3):
        b.append(arrow(xs[i] + bw + 2, y + 38, xs[i + 1] - 4, y + 38, RED))
    b.append(text(xs[3] + bw / 2, y + 102, 'sees your real IP address', 13, RED, 'middle', 600))
    # cfg-pia-wg: tunnel or nothing.
    b.append(text(24, 276, 'WITH CFG-PIA-WG', 12, TEAL, weight=700))
    y = 288
    b.append(box(xs[0], y, bw, 76, 'Laptop', 'pinned to wgc1'))
    b.append(box(xs[1], y, bw, 76, 'ASUS router', 'kill switch holds', stroke=AMBER, title_color=TEXT))
    b.append(arrow(xs[0] + bw + 2, y + 38, xs[1] - 4, y + 38, MUTED))
    # Blocked path.
    cx, cy = xs[2] + 34, y + 38
    b.append(f'<line x1="{xs[1] + bw + 2}" y1="{cy}" x2="{cx - 20}" y2="{cy}" stroke="{RED}" stroke-width="2" stroke-dasharray="6 5"/>')
    b.append(f'<circle cx="{cx}" cy="{cy}" r="18" fill="{BG}" stroke="{RED}" stroke-width="2"/>')
    b.append(f'<path d="M{cx - 8} {cy - 8} L{cx + 8} {cy + 8} M{cx + 8} {cy - 8} L{cx - 8} {cy + 8}" stroke="{RED}" stroke-width="2.5"/>')
    b.append(text(cx + 30, cy - 4, 'no tunnel, no internet', 14, TEXT, weight=600))
    b.append(text(cx + 30, cy + 15, 'nothing leaves by your ISP', 12, MUTED))
    b.append(box(xs[3], y + 100, bw, 56, 'PIA tunnel', 'rebuilt by the watchdog', stroke=TEAL))
    b.append(f'<path d="M{xs[1] + bw / 2} {y + 78} L{xs[1] + bw / 2} {y + 128} L{xs[3] - 4} {y + 128}" fill="none" '
             f'stroke="{TEAL}" stroke-width="2" stroke-dasharray="6 5" marker-end="url(#m{TEAL.lstrip("#")})"/>')
    b.append(text(xs[1] + bw / 2 + 12, y + 120, 'back through the tunnel once it is up', 12, TEAL))
    return svg(w, h, '\n'.join(b))


def timeline():
    w, h = 800, 450
    start = datetime.date(2026, 5, 23)
    end = datetime.date(2026, 11, 11)
    x0, x1, axis = 50, 750, 250
    span = (end - start).days

    def x(d):
        return x0 + (d - start).days / span * (x1 - x0)

    b = [heading('Five and a half months', '23 May to 11 November 2026, drawn to scale')]
    b.append(f'<line x1="{x0}" y1="{axis}" x2="{x1}" y2="{axis}" stroke="{BORDER}" stroke-width="3"/>')
    for m in range(6, 12):
        d = datetime.date(2026, m, 1)
        b.append(f'<line x1="{x(d):.1f}" y1="{axis - 6}" x2="{x(d):.1f}" y2="{axis + 6}" stroke="{HINT}" stroke-width="1.5"/>')
        b.append(text(x(d), axis + 24, d.strftime('%b'), 12, MUTED, 'middle', font=MONO))
    # Merlin-only band.
    b.append(f'<rect x="{x0}" y="{axis - 3}" width="{x(datetime.date(2026, 9, 5)) - x0:.1f}" height="6" fill="{LAVENDER}" opacity="0.55"/>')
    b.append(text((x0 + x(datetime.date(2026, 9, 5))) / 2, axis + 50, 'built and tested on Merlin firmware', 12, LAVENDER, 'middle'))
    # (date, label row: -2 high, -1 lower, 1 below; anchor, date text, label, colour)
    events = [
        (datetime.date(2026, 5, 23), -2, 'start', '23 May', 'cfg-pia-wg-cmd,\nand the app begins', TEXT),
        (datetime.date(2026, 9, 5), -2, 'end', '5 Sep', 'stock firmware\nsupport, build 403', TEAL),
        (datetime.date(2026, 9, 8), 1, 'end', '8 Sep', 'eleven probes,\nthe first eight wrong', AMBER),
        (datetime.date(2026, 9, 30), -1, 'start', '30 Sep', 'reboot leak and\ncurl DNS bug found', RED),
        (datetime.date(2026, 10, 1), 1, 'start', '1 Oct', 'first public release,\nGoogle Play, build 490', TEAL),
        (datetime.date(2026, 11, 10), -2, 'end', '10 Nov', 'App Store\napproval', TEAL),
    ]
    rows = {-2: 100, -1: 168, 1: 340}
    for d, row, anchor, date, label, color in events:
        px = x(d)
        ty = rows[row]
        if row < 0:
            b.append(f'<line x1="{px:.1f}" y1="{axis - 8}" x2="{px:.1f}" y2="{ty - 12}" stroke="{color}" stroke-width="1" opacity="0.6"/>')
        else:
            b.append(f'<line x1="{px:.1f}" y1="{axis + 8}" x2="{px:.1f}" y2="{ty + 12}" stroke="{color}" stroke-width="1" opacity="0.6"/>')
        tx = px + (6 if anchor == 'start' else -6)
        b.append(text(tx, ty, date, 13, color, anchor, 700, MONO))
        b.append(text(tx, ty + 18, label, 12, TEXT, anchor))
    for d, row, anchor, date, label, color in events:
        px = x(d)
        if date == '30 Sep':
            # A day before 1 Oct: drawn as a ring around it, so both show.
            b.append(f'<circle cx="{px:.1f}" cy="{axis}" r="10" fill="none" stroke="{color}" stroke-width="2.5"/>')
        else:
            b.append(f'<circle cx="{px:.1f}" cy="{axis}" r="6" fill="{color}" stroke="{BG}" stroke-width="2"/>')
    b.append(text(x1, 426, '612 commits  ·  574 builds  ·  2,174 automated tests', 13, MUTED, 'end', font=MONO))
    return svg(w, h, '\n'.join(b))


def watchdog():
    w, h = 800, 600
    b = [heading('What the watchdog does', 'On the router, every few minutes, whether your phone is on or not')]
    cx, bw = 290, 380
    left = cx - bw / 2
    b.append(box(left, 76, bw, 56, 'cron wakes the watchdog', 'every N minutes, your choice', stroke=LAVENDER))
    b.append(arrow(cx, 134, cx, 152, MUTED))
    # Decision diamond.
    dy, dw, dh = 196, 300, 84
    b.append(f'<path d="M{cx} {dy - dh / 2} L{cx + dw / 2} {dy} L{cx} {dy + dh / 2} L{cx - dw / 2} {dy} z" '
             f'fill="{SURFACE}" stroke="{LAVENDER}" stroke-width="1.5"/>')
    b.append(text(cx, dy - 3, 'Is the tunnel passing traffic?', 14, TEXT, 'middle', 600))
    b.append(text(cx, dy + 15, 'a ping through it', 12, MUTED, 'middle'))
    b.append(arrow(cx + dw / 2 + 2, dy, 586, dy, TEAL))
    b.append(text(cx + dw / 2 + 14, dy - 8, 'yes', 13, TEAL, weight=700))
    b.append(box(590, dy - 28, 186, 56, 'Log it, and sleep', 'nothing else changes', stroke=TEAL))
    b.append(arrow(cx, dy + dh / 2 + 2, cx, 262, RED))
    b.append(text(cx + 12, dy + dh / 2 + 18, 'no', 13, RED, weight=700))
    steps = [
        ("Fetch PIA's server list", 'and check its signature, as PIA\'s own app does'),
        ('Ping the region\'s servers', 'and take the fastest'),
        ('Make a new key pair', 'and register it with that server'),
        ('Write the slot', 'and restart that one tunnel'),
        ('Email you', 'how long it was down, and whether the kill switch held'),
    ]
    y = 266
    for i, (t, s) in enumerate(steps):
        stroke = PERIWINKLE if i == len(steps) - 1 else BORDER
        b.append(box(left, y, bw, 50, t, s, stroke=stroke))
        if i < len(steps) - 1:
            b.append(arrow(cx, y + 52, cx, y + 64, MUTED))
        y += 66
    # Kill switch bracket alongside the rebuild.
    top, bottom = 266, 266 + 66 * 3 + 50
    bx = left + bw + 18
    b.append(f'<path d="M{bx} {top} L{bx + 10} {top} L{bx + 10} {bottom} L{bx} {bottom}" fill="none" stroke="{AMBER}" stroke-width="2"/>')
    b.append(text(bx + 24, (top + bottom) / 2 - 18, 'The kill switch holds', 14, AMBER, weight=700))
    b.append(text(bx + 24, (top + bottom) / 2 + 2, 'throughout: pinned devices', 12, TEXT))
    b.append(text(bx + 24, (top + bottom) / 2 + 18, 'stay offline until the new', 12, TEXT))
    b.append(text(bx + 24, (top + bottom) / 2 + 34, 'tunnel is up', 12, TEXT))
    return svg(w, h, '\n'.join(b))


def dns_split():
    w, h = 800, 470
    b = [heading('Traffic and DNS take different roads', 'On stock firmware, the connection decides the traffic, not the lookups')]
    bw = 190
    # Unpinned.
    b.append(text(24, 106, 'NOT PINNED', 12, RED, weight=700))
    b.append(box(24, 140, 150, 64, 'Laptop', 'default connection: wgc1'))
    b.append(box(300, 116, bw, 50, 'wgc1 tunnel', 'encrypted', stroke=TEAL))
    b.append(box(586, 116, bw, 50, 'PIA', 'your browsing', stroke=TEAL))
    b.append(box(300, 186, bw, 50, "Router's resolver", 'its own DNS settings', stroke=BORDER))
    b.append(box(586, 186, bw, 50, 'Your ISP', 'every name you look up', stroke=RED))
    b.append(f'<path d="M176 160 C240 160 240 141 296 141" fill="none" stroke="{TEAL}" stroke-width="2" marker-end="url(#m{TEAL.lstrip("#")})"/>')
    b.append(f'<path d="M176 184 C240 184 240 211 296 211" fill="none" stroke="{RED}" stroke-width="2" marker-end="url(#m{RED.lstrip("#")})"/>')
    b.append(arrow(492, 141, 582, 141, TEAL))
    b.append(arrow(492, 211, 582, 211, RED))
    b.append(text(206, 132, 'traffic', 12, TEAL))
    b.append(text(206, 232, 'lookups', 12, RED))
    b.append(text(537, 256, 'readable, unless you have set up encrypted DNS', 12, RED, 'middle'))
    # Pinned.
    b.append(text(24, 316, 'PINNED WITH CFG-PIA-WG', 12, TEAL, weight=700))
    b.append(box(24, 352, 150, 64, 'Laptop', 'pinned to wgc1'))
    b.append(box(300, 352, bw, 64, 'wgc1 tunnel', 'traffic and lookups,\nboth encrypted', stroke=TEAL))
    b.append(box(586, 352, bw, 64, 'PIA', "and the slot's DNS server", stroke=TEAL))
    b.append(arrow(176, 376, 296, 376, TEAL))
    b.append(arrow(176, 394, 296, 394, TEAL))
    b.append(arrow(492, 384, 582, 384, TEAL))
    b.append(text(206, 370, 'traffic', 12, TEAL))
    b.append(text(206, 412, 'lookups', 12, TEAL))
    b.append(text(24, 450, 'The watchdog does its own lookups, for PIA and your mail server, over encrypted DNS to a server you choose.', 12, MUTED))
    return svg(w, h, '\n'.join(b))


def reboot():
    w, h = 800, 350
    b = [heading('The first minute after a restart', 'Measured from a pinned device, once a second, over six boots. Not to scale.')]
    x0, x1 = 24, 776
    a, c = 430, 560
    y = 140
    b.append(text(24, 116, 'BEFORE: THE GUARD ALONE', 12, RED, weight=700))
    b.append(f'<rect x="{x0}" y="{y}" width="{a - x0}" height="40" rx="6" fill="{SURFACE}" stroke="{BORDER}"/>')
    b.append(f'<rect x="{a}" y="{y}" width="{c - a}" height="40" fill="{RED}" opacity="0.85"/>')
    b.append(f'<rect x="{c}" y="{y}" width="{x1 - c}" height="40" rx="6" fill="{SURFACE}" stroke="{TEAL}"/>')
    b.append(text((x0 + a) / 2, y + 25, 'router starting', 13, MUTED, 'middle'))
    b.append(text((a + c) / 2, y + 25, '3 to 6 s', 14, BG, 'middle', 700, MONO))
    b.append(text((c + x1) / 2, y + 25, 'guard in place', 13, TEAL, 'middle', 600))
    b.append(f'<line x1="{a}" y1="{y + 44}" x2="{a}" y2="{y + 60}" stroke="{MUTED}"/>')
    b.append(text(a, y + 76, 'internet connection up', 12, MUTED, 'end'))
    b.append(f'<line x1="{c}" y1="{y + 44}" x2="{c}" y2="{y + 60}" stroke="{MUTED}"/>')
    b.append(text(c, y + 76, 'add-on code starts', 12, MUTED, 'start'))
    b.append(text((a + c) / 2, y - 10, 'pinned device reaches the internet directly, on 4 boots of 6', 12, RED, 'middle', 600))
    y2 = 280
    b.append(text(24, y2 - 24, "NOW: THE ROUTER'S OWN NETWORK SERVICES FILTER", 12, TEAL, weight=700))
    b.append(f'<rect x="{x0}" y="{y2}" width="{x1 - x0}" height="40" rx="6" fill="{SURFACE}" stroke="{TEAL}"/>')
    b.append(text((x0 + x1) / 2, y2 + 25, 'pinned devices held from the moment the router starts', 14, TEAL, 'middle', 600))
    return svg(w, h, '\n'.join(b))


def captain():
    w, h = 800, 470
    b = [heading('The captain and the engine', 'Neither gets anywhere without the other')]
    bw, bh = 300, 84
    L, R, T, B = 40, 460, 100, 316
    b.append(box(L, T, bw, bh, 'Captain: Andrew', 'the idea, the design, the requirements,\nand the rules', stroke=PERIWINKLE, title_color=PERIWINKLE))
    b.append(box(R, T, bw, bh, 'Engine: Claude', 'the code, and a test\nfor every change', stroke=TEAL, title_color=TEAL))
    b.append(box(R, B, bw, bh, 'Automated tests', '2,174 on every build,\n95.9% of the code covered', stroke=BORDER))
    b.append(box(L, B, bw, bh, 'Measured on a real router', 'findings go back in as\nthe next requirement', stroke=PERIWINKLE, title_color=PERIWINKLE))
    b.append(arrow(L + bw + 4, T + bh / 2, R - 6, T + bh / 2, MUTED))
    b.append(arrow(R + bw / 2, T + bh + 4, R + bw / 2, B - 6, MUTED))
    b.append(arrow(R - 4, B + bh / 2, L + bw + 6, B + bh / 2, MUTED))
    b.append(arrow(L + bw / 2, B - 4, L + bw / 2, T + bh + 6, MUTED))
    mx = (L + bw + R) / 2
    b.append(text(mx, 236, 'Done means seen working', 14, AMBER, 'middle', 700))
    b.append(text(mx, 256, 'on the router', 14, AMBER, 'middle', 700))
    b.append(text(w / 2, 440, 'Every protection is proved by a check that was first seen to fail.', 13, MUTED, 'middle'))
    return svg(w, h, '\n'.join(b))


def featured():
    """The post's featured image, 16:9: the title, and the promise drawn small."""
    w, h = 960, 540
    b = [f'<rect x="0" y="0" width="12" height="{h}" fill="{TEAL}"/>']
    b.append(text(64, 120, 'CFG-PIA-WG', 16, TEAL, weight=700, font=MONO))
    b.append(text(64, 196, 'Tunnel', 64, TEXT, weight=700))
    b.append(text(64, 268, 'or nothing', 64, TEXT, weight=700))
    b.append(text(64, 330, 'A kill switch for PIA WireGuard', 22, MUTED))
    b.append(text(64, 362, 'on stock ASUS firmware', 22, MUTED))
    b.append(text(64, 480, 'exponentiallydigital.com', 15, MUTED, font=MONO))
    # The promise, drawn small: laptop, router holding, tunnel or nothing.
    bw = 200
    lx = 600
    b.append(box(lx, 70, bw, 70, 'Laptop', 'pinned to wgc1', size=18))
    b.append(arrow(lx + bw / 2, 144, lx + bw / 2, 196, MUTED))
    b.append(box(lx, 200, bw, 70, 'ASUS router', 'kill switch holds', stroke=AMBER, size=18))
    b.append(f'<path d="M{lx + 60} 274 L{lx + 60} 330 L{lx - 40} 330 L{lx - 40} 388" fill="none" stroke="{TEAL}" '
             f'stroke-width="3" marker-end="url(#m{TEAL.lstrip("#")})"/>')
    b.append(box(lx - 130, 392, 180, 70, 'PIA tunnel', 'encrypted', stroke=TEAL, title_color=TEAL, size=18))
    b.append(f'<path d="M{lx + 140} 274 L{lx + 140} 330 L{lx + 250} 330 L{lx + 250} 388" fill="none" stroke="{RED}" '
             f'stroke-width="3" stroke-dasharray="7 6"/>')
    cx, cy = lx + 250, 330
    b.append(f'<circle cx="{cx}" cy="{cy}" r="20" fill="{BG}" stroke="{RED}" stroke-width="3"/>')
    b.append(f'<path d="M{cx - 9} {cy - 9} L{cx + 9} {cy + 9} M{cx + 9} {cy - 9} L{cx - 9} {cy + 9}" stroke="{RED}" stroke-width="3"/>')
    b.append(box(lx + 160, 392, 180, 70, 'Your ISP', 'blocked', stroke=RED, size=18))
    return svg(w, h, '\n'.join(b))


DIAGRAMS = {
    '00-featured': featured,
    '01-tunnel-down': tunnel_drops,
    '02-timeline': timeline,
    '03-watchdog': watchdog,
    '04-dns': dns_split,
    '05-reboot': reboot,
    '06-captain-engine': captain,
}


def render(svg_path, png_path, w, h):
    url = 'file:///' + svg_path.replace('\\', '/')
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2',
                    f'--window-size={w},{h}', f'--screenshot={png_path}', url],
                   check=True, capture_output=True, timeout=120)


NETWORK = '07-network-traffic'
# The logical network traffic diagram already in the repo, in each theme, for the article's last image.
NETWORK_SOURCES = {'light': 'network-traffic-(logical).svg', 'dark': 'network-traffic-(logical)-dark.svg'}


def main():
    # Light for the blog, whose theme is white; dark kept for anywhere with a dark background.
    for theme, out in (('light', OUT), ('dark', os.path.join(OUT, 'dark'))):
        use(theme)
        os.makedirs(out, exist_ok=True)
        for name, make in DIAGRAMS.items():
            s = make()
            w, h = (int(v) for v in s.split('viewBox="0 0 ')[1].split('"')[0].split())
            svg_path = os.path.join(out, name + '.svg')
            with open(svg_path, 'w', encoding='utf-8') as f:
                f.write(s)
            render(svg_path, os.path.join(out, name + '.png'), w, h)
        src = os.path.join(HERE, '..', '..', 'images', NETWORK_SOURCES[theme])
        vb = open(src, encoding='utf-8').read().split('viewBox="')[1].split('"')[0].split()
        png = os.path.join(out, NETWORK + '.png')
        render(os.path.abspath(src), png, int(float(vb[2])), int(float(vb[3])))
        trim(png)
        print(f'{theme}: {len(DIAGRAMS) + 1} images in {os.path.relpath(out, HERE)}')


def trim(png, margin=40):
    """Crops a render to its content plus a margin: the SVG's canvas runs past what it draws."""
    from PIL import Image, ImageChops
    im = Image.open(png).convert('RGB')
    bg = Image.new('RGB', im.size, im.getpixel((2, 2)))
    box = ImageChops.difference(im, bg).point(lambda v: 255 if v > 12 else 0).getbbox()
    if box:
        l, t, r, b = box
        im.crop((max(0, l - margin), max(0, t - margin), min(im.width, r + margin), min(im.height, b + margin))).save(png)


if __name__ == '__main__':
    sys.exit(main())
