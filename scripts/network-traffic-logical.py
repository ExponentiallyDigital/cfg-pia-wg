#!/usr/bin/env python3
"""network-traffic-logical.py - draws images/network-traffic-(logical).svg (ID-239): every connection the app and its watchdog make, numbered, with a table of what each is for.

    python scripts/network-traffic-logical.py
    python scripts/svg-dark-variant.py "images/network-traffic-(logical).svg"

The SVG is generated: change this script, not the file, then run both lines above so the dark
version follows. The flows in it come from the code - lib/pia_service.dart, lib/router_watchdog.dart
(the watchdog script), lib/binary_installer.dart, lib/entitlement.dart - so a new connection in
any of those belongs here too.
"""
import sys
from html import escape

OUT = sys.argv[1] if len(sys.argv) > 1 else 'images/network-traffic-(logical).svg'
W = 1300

C = {  # protocol colours: stroke, text
    'https': ('#1E88E5', '#1565C0'),
    'probe': ('#FF9800', '#E65100'),
    'addkey': ('#9C27B0', '#6A1B9A'),
    'wg': ('#4CAF50', '#2E7D32'),
    'ssh': ('#F44336', '#C62828'),
    'dns': ('#9E9E9E', '#616161'),
    'icmp': ('#FFC107', '#8D6E00'),
    'smtp': ('#795548', '#5D4037'),
}

o = []
def add(s): o.append(s)

def text(x, y, s, cls='ns', anchor=None, style=None, fill=None):
    a = f' text-anchor="{anchor}"' if anchor else ''
    st = f' style="{style}"' if style else ''
    f = f' fill="{fill}"' if fill else ''
    add(f'  <text x="{x}" y="{y}" class="{cls}"{a}{st}{f}>{s}</text>')

def cyl(x, y, w, h, stroke, top, title, lines):
    rx = w / 2
    add(f'  <path d="M{x},{y} A{rx},11 0 0 1 {x+w},{y} L{x+w},{y+h} A{rx},11 0 0 1 {x},{y+h} Z" fill="#ffffff" stroke="{stroke}" stroke-width="2"/>')
    add(f'  <ellipse cx="{x+rx}" cy="{y}" rx="{rx}" ry="11" fill="{top}" stroke="{stroke}" stroke-width="2"/>')
    text(x + rx, y + 20, title, 'nt', 'middle', 'font-size:13px')
    for i, l in enumerate(lines):
        text(x + rx, y + 37 + i * 15, l, 'ns', 'middle')

def box(x, y, w, h, stroke, title, lines, fill='#ffffff'):
    add(f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
    text(x + w / 2, y + 19, title, 'nt', 'middle', 'font-size:13px')
    for i, l in enumerate(lines):
        text(x + w / 2, y + 36 + i * 15, l, 'ns', 'middle')

def arrow(n, kind, x1, y1, x2, y2, dashed=False, both=False, t=0.78):
    s = C[kind][0]
    cls = 'ret' if dashed else 'flow'
    ms = f' marker-start="url(#m{kind})"' if both else ''
    c1x, c2x = x1 + (x2 - x1) * 0.45, x2 - (x2 - x1) * 0.45
    add(f'  <path class="{cls}" stroke="{s}"{ms} marker-end="url(#m{kind})" d="M{x1},{y1} C{c1x:.0f},{y1} {c2x:.0f},{y2} {x2},{y2}"/>')
    # badge on the curve at t
    bx = (1-t)**3*x1 + 3*(1-t)**2*t*c1x + 3*(1-t)*t**2*c2x + t**3*x2
    by = (1-t)**3*y1 + 3*(1-t)**2*t*y1 + 3*(1-t)*t**2*y2 + t**3*y2
    badges.append((bx, by, n, s))

badges = []

H = 1450
add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="100%" preserveAspectRatio="xMidYMid meet" style="max-width:1200px;height:auto;font-family:\'Segoe UI\',Arial,sans-serif;background:#ffffff" role="img" aria-labelledby="t d">')
add('  <title id="t">Logical network traffic flow</title>')
add('  <desc id="d">Every connection the app and its router-side watchdog make. From the phone: SSH 22 to the router; HTTPS 443 to PIA for the server list, a token and the CA certificate; TCP 1337 latency probes and CA-pinned HTTPS 1337 key registration to PIA WireGuard servers; HTTPS to RevenueCat and Google Play for purchases; links opened in the browser; DNS through the phone\'s own resolver. From the router: the WireGuard tunnel on the port PIA returns; the watchdog\'s own HTTPS calls to PIA, ICMP latency pings and key registration; its encrypted DNS lookups (DoH) to the chosen resolver; a DNS name check through the tunnel; ICMP pings to the check targets; alert email over SMTP with TLS; helper downloads from github.com; and ordinary DNS through the router\'s DNS Server setting. Egress through PIA\'s internal network and public IP pool. All IP addresses illustrative.</desc>')
add('''  <defs>
    <style>
      .zt{font:700 14px 'Segoe UI',Arial,sans-serif}
      .nt{font:700 14px 'Segoe UI',Arial,sans-serif;fill:#102027}
      .ns{font:12px 'Segoe UI',Arial,sans-serif;fill:#455A64}
      .lb{font:12px 'Segoe UI',Arial,sans-serif;fill:#37474F}
      .bn{font:700 11px 'Segoe UI',Arial,sans-serif;fill:#FEFEFE}
      .flow{fill:none;stroke-width:2.4}
      .ret{fill:none;stroke-width:2;stroke-dasharray:7 5}
    </style>''')
for k, (s, _) in C.items():
    add(f'    <marker id="m{k}" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{s}"/></marker>')
add('  </defs>')

# ---- title
text(650, 34, 'Logical network traffic flow', style="font:700 24px 'Segoe UI',Arial,sans-serif;fill:#102027", anchor='middle', cls='')
text(650, 58, 'Every connection the app and its watchdog make. Each number is a row in the table below. Solid = request, dashed = the tunnel or an optional link.', anchor='middle', style="font:13px 'Segoe UI',Arial,sans-serif;fill:#607D8B", cls='')
text(650, 76, '<tspan font-weight="bold">Note:</tspan> all IP addresses shown are for illustration only.', anchor='middle', style="font:11px 'Segoe UI',Arial,sans-serif;fill:#9E9E9E", cls='')

# ---- zones
add('  <rect x="30" y="92" width="330" height="800" rx="14" fill="#E3F2FD" fill-opacity="0.35" stroke="#90CAF9" stroke-dasharray="6 5"/>')
text(46, 114, 'Your home network (192.168.1.0/24)', 'zt', fill='#1565C0')
add('  <rect x="470" y="92" width="400" height="330" rx="14" fill="#F3E5F5" fill-opacity="0.30" stroke="#CE93D8" stroke-dasharray="6 5"/>')
text(486, 114, 'PIA infrastructure', 'zt', fill='#6A1B9A')
add('  <rect x="470" y="440" width="400" height="452" rx="14" fill="#ECEFF1" fill-opacity="0.55" stroke="#B0BEC5" stroke-dasharray="6 5"/>')
text(486, 462, 'Internet services', 'zt', fill='#455A64')
add('  <rect x="910" y="92" width="360" height="800" rx="14" fill="#E8F5E9" fill-opacity="0.35" stroke="#A5D6A7" stroke-dasharray="6 5"/>')
text(926, 114, 'PIA VPN exit and the internet', 'zt', fill='#2E7D32')

# ---- phone
add('  <rect x="60" y="135" width="270" height="175" rx="12" fill="#ffffff" stroke="#1E88E5" stroke-width="2"/>')
add('  <rect x="76" y="147" width="30" height="52" rx="6" fill="#E3F2FD" stroke="#1E88E5" stroke-width="1.5"/>')
add('  <rect x="80" y="154" width="22" height="37" fill="#BBDEFB"/>')
text(118, 165, 'Phone (this app)', 'nt')
text(118, 183, 'Android, on your Wi-Fi')
text(76, 222, '192.168.1.100')
text(76, 240, 'Dart HttpClient, dartssh2,')
text(76, 256, 'RevenueCat SDK, url_launcher')
text(76, 274, 'STANDALONE builds a config here;')
text(76, 290, 'everything else runs on the router')

# ---- router
add('  <path d="M60,470 L60,720 L330,720 L330,470 L315,460 L300,470 L285,460 L270,470 L255,460 L240,470 L225,460 L210,470 L195,460 L180,470 L165,460 L150,470 L135,460 L120,470 L105,460 L90,470 L75,460 Z" fill="#ffffff" stroke="#F44336" stroke-width="2"/>')
text(76, 494, 'ASUS router, stock or Merlin', 'nt')
text(76, 514, '192.168.1.1 · SSH server :22')
text(76, 532, 'WireGuard client slots wgc1-wgc5')
text(76, 556, 'Watchdog (watchdog_wgcN.sh, cron):', style='font-weight:700')
text(76, 574, 'rebuilds a slot that stops answering,')
text(76, 590, 'emails you about it')
text(76, 614, 'Its curl looks names up over DoH;')
text(76, 630, 'wget and the rest use the router\'s')
text(76, 646, 'DNS Server setting')
text(76, 670, 'Stock: jq and mailsend-go,')
text(76, 686, 'installed by the app')

# SSH phone <-> router
arrow(1, 'ssh', 190, 310, 190, 458, both=True, t=0.5)

# ---- PIA nodes
cyl(500, 140, 340, 44, '#1E88E5', '#E3F2FD', 'serverlist.piaservers.net', ['e.g. 160.79.104.10 : 443 · GET /vpninfo/servers/v6'])
cyl(500, 215, 340, 44, '#1E88E5', '#E3F2FD', 'www.privateinternetaccess.com', ['e.g. 104.18.30.10 : 443 · POST /gtoken/generateToken'])
cyl(500, 292, 340, 110, '#7B1FA2', '#F3E5F5', 'PIA WireGuard servers', [
    'e.g. 143.244.50.40, certificate name pinned',
    ': 1337 TCP latency probe (phone)',
    ': 1337 HTTPS /addKey, CA-pinned',
    ': server_port UDP, the tunnel (1337 on PIA)',
    'ICMP latency ping (watchdog)'])

# ---- internet service nodes
sx, sw = 500, 340
cyl(sx, 490, sw, 30, '#1E88E5', '#E3F2FD', 'raw.githubusercontent.com', ["PIA's CA certificate, ca.rsa.4096.crt"])
box(sx, 540, sw, 40, '#1E88E5', 'github.com releases', ['jq and mailsend-go (stock), fetched with wget'])
box(sx, 592, sw, 40, '#1E88E5', 'DoH resolver, e.g. security.cloudflare-dns.com', ['HTTPS 443 to 1.1.1.2, pinned with --resolve'])
box(sx, 644, sw, 40, '#795548', 'Your mail server', ['SMTP over TLS, the host:port you give'])
box(sx, 696, sw, 40, '#FFC107', 'Check targets, e.g. 8.8.8.8 and 1.1.1.1', ['ICMP ping, to tell a dead WAN from a dead tunnel'])
box(sx, 748, sw, 40, '#1E88E5', 'RevenueCat and Google Play', ['api.revenuecat.com · Play Billing: purchases, unlock'])
box(sx, 800, sw, 40, '#1E88E5', 'Links opened in the browser', ['README on github.com · the Play Store listing'])
box(sx, 852 - 0, sw, 30, '#9E9E9E', 'DNS resolvers (UDP/TCP 53)', [])

# ---- right zone: exit chain
add('  <rect x="935" y="140" width="310" height="120" rx="10" fill="#ffffff" stroke="#43A047" stroke-width="2"/>')
text(1090, 163, 'PIA internal network', 'nt', 'middle', 'font-size:13px')
text(1090, 182, '172.16.0.0/16', 'ns', 'middle')
add('  <rect x="970" y="196" width="240" height="50" rx="8" fill="#E8F5E9" stroke="#43A047" stroke-width="1.5"/>')
text(1090, 216, 'server tunnel interface (peer)', 'ns', 'middle')
text(1090, 235, '172.16.1.50', 'nt', 'middle', 'font-size:13px;fill:#2E7D32')
text(1090, 318, 'PIA public IP pool', 'zt', 'middle', fill='#2E7D32')
add('  <rect x="995" y="332" width="210" height="62" rx="8" fill="#C8E6C9" stroke="#43A047" stroke-width="1.5"/>')
add('  <rect x="982" y="346" width="210" height="62" rx="8" fill="#A5D6A7" stroke="#43A047" stroke-width="1.5"/>')
add('  <rect x="969" y="360" width="210" height="62" rx="8" fill="#81C784" stroke="#2E7D32" stroke-width="1.8"/>')
text(1074, 386, 'source NAT', 'nt', 'middle', 'font-size:13px')
text(1074, 405, '185.230.125.10 - .50', 'ns', 'middle', 'fill:#1B5E20')
add('  <g transform="translate(950,520) scale(1.4)"><path d="M 50 100 C 20 100 10 80 28 66 C 18 44 44 28 64 40 C 72 18 110 18 120 40 C 150 30 172 54 156 74 C 178 84 168 100 146 100 Z" fill="#ffffff" stroke="#2E7D32" stroke-width="1.6"/></g>')
text(1085, 603, 'Internet', 'nt', 'middle')
text(1085, 622, 'any destination, and the', 'ns', 'middle')
text(1085, 638, "slot's DNS server (9)", 'ns', 'middle')
text(1085, 656, 'sees 185.230.125.x', 'ns', 'middle')
text(1090, 720, 'Traffic through a tunnel', 'ns', 'middle', 'font-weight:700')
text(1090, 738, 'leaves PIA from the pool,', 'ns', 'middle')
text(1090, 754, 'not from your home address.', 'ns', 'middle')
text(1090, 780, 'The router\'s own traffic (2-6, 8, 10-12)', 'ns', 'middle', 'font-weight:700')
text(1090, 798, 'goes straight out your internet', 'ns', 'middle')
text(1090, 814, 'connection. See the representative', 'ns', 'middle')
text(1090, 830, 'diagram for which path each takes.', 'ns', 'middle')

# exit chain arrows
add('  <path class="flow" stroke="#4CAF50" marker-end="url(#mwg)" d="M840,360 C890,360 900,210 935,210"/>')
add('  <path class="flow" stroke="#4CAF50" marker-end="url(#mwg)" d="M1090,260 L1090,300"/>')
add('  <path class="ret" stroke="#4CAF50" marker-end="url(#mwg)" d="M1080,422 L1082,538"/>')

# ---- phone flows (right edge x=330); badges near the phone, the router's near their target
px = 330
arrow(2, 'https', px, 160, 500, 162, t=0.22)
arrow(3, 'https', px, 175, 500, 237, t=0.22)
arrow(4, 'https', px, 190, 500, 505, t=0.4)
arrow(5, 'probe', px, 205, 500, 318, t=0.22)
arrow(6, 'addkey', px, 220, 500, 332, t=0.22)
arrow(13, 'https', px, 250, 500, 768, t=0.22)
arrow(14, 'https', px, 268, 500, 820, dashed=True, t=0.22)
arrow(15, 'dns', px, 290, 500, 867, t=0.22)

# ---- router flows (right edge x=330)
rx = 330
arrow(2, 'https', rx, 482, 500, 172, t=0.86)
arrow(3, 'https', rx, 496, 500, 247, t=0.86)
arrow(4, 'https', rx, 512, 500, 514, t=0.86)
arrow(5, 'icmp', rx, 528, 500, 350, t=0.9)
arrow(6, 'addkey', rx, 544, 500, 366, t=0.9)
arrow(7, 'wg', rx, 560, 500, 384, dashed=True, both=True, t=0.9)
arrow(12, 'https', rx, 590, 500, 560, t=0.86)
arrow(8, 'https', rx, 615, 500, 612, t=0.86)
arrow(11, 'smtp', rx, 640, 500, 664, t=0.86)
arrow(10, 'icmp', rx, 665, 500, 716, t=0.86)
arrow(15, 'dns', rx, 700, 500, 874, t=0.86)
# 9: the name check rides the tunnel: a badge on the WireGuard path at the PIA side
badges.append((872, 330, 9, C['dns'][0]))
badges.append((872, 330 + 0, 0, None))

for bx, by, n, s in badges:
    if s is None:
        continue
    add(f'  <circle cx="{bx:.0f}" cy="{by:.0f}" r="10" fill="{s}" stroke="#ffffff" stroke-width="1.5"/>')
    add(f'  <text x="{bx:.0f}" y="{by+4:.0f}" text-anchor="middle" class="bn">{n}</text>')

# ---- table
ty = 915
rows = [
    (1, 'ssh', 'SSH 22 (TCP)', 'Phone to router', 'Every router screen: reads, writes and service calls, as the router login'),
    (2, 'https', 'HTTPS 443', 'Phone and router', "PIA's server list"),
    (3, 'https', 'HTTPS 443', 'Phone and router', 'A PIA token, from your PIA username and password'),
    (4, 'https', 'HTTPS 443', 'Phone and router', "PIA's CA certificate; the router keeps its copy"),
    (5, 'probe', 'TCP 1337 / ICMP', 'Phone / router', 'Latency to each candidate server: the phone times a TCP connect, the watchdog pings'),
    (6, 'addkey', 'HTTPS 1337', 'Phone and router', 'Registers the new public key (addKey), pinned to PIA\'s CA; returns the peer IP, server key and port'),
    (7, 'wg', 'UDP server_port', 'Router and PIA', 'The WireGuard tunnel itself, on the port PIA returns (1337)'),
    (8, 'https', 'HTTPS 443 (DoH)', 'Router', "The watchdog's own lookups, encrypted, to the resolver chosen on the WATCHDOG form"),
    (9, 'dns', 'DNS 53, in the tunnel', 'Router', "The watchdog's name check: the slot's DNS server, asked through the slot's own tunnel"),
    (10, 'icmp', 'ICMP', 'Router', 'Pings to the check targets: the WAN check, and ENABLE\'s check (Merlin also pings through the tunnel)'),
    (11, 'smtp', 'SMTP over TLS', 'Router', 'Alert emails and TEST EMAIL, to the server and port you give'),
    (12, 'https', 'HTTPS 443', 'Router', 'Stock only: jq and mailsend-go from github.com releases, when the app installs them'),
    (13, 'https', 'HTTPS 443', 'Phone', 'RevenueCat and Google Play Billing: buying, restoring and checking the unlock'),
    (14, 'https', 'HTTPS 443', 'Phone browser', 'Links you tap: the README on github.com, the Play Store listing'),
    (15, 'dns', 'DNS 53', 'Phone / router', "Ordinary lookups: the phone's own resolver; the router's DNS Server setting (wget, and the watchdog with DoH off)"),
]
rh = 26
th = 60 + len(rows) * rh + 90
add(f'  <rect x="30" y="{ty}" width="1240" height="{th}" rx="12" fill="#FAFAFA" stroke="#CFD8DC"/>')
text(46, ty + 26, 'The flows, by number', 'zt', fill='#37474F')
hy = ty + 50
for x, h in [(52, '#'), (92, 'Protocol, port'), (262, 'Between'), (412, 'What for')]:
    text(x, hy, h, 'lb', style='font-weight:700')
for i, (n, k, proto, who, what) in enumerate(rows):
    y = hy + 22 + i * rh
    s, tc = C[k]
    add(f'  <circle cx="60" cy="{y-4}" r="10" fill="{s}" stroke="#ffffff" stroke-width="1.5"/>')
    add(f'  <text x="60" y="{y}" text-anchor="middle" class="bn">{n}</text>')
    text(92, y, escape(proto), 'lb', style=f'font-weight:700;fill:{tc}')
    text(262, y, escape(who), 'lb')
    text(412, y, escape(what), 'lb')
ly = hy + 22 + len(rows) * rh + 12
# legend
lx = 52
for k, label in [('https', 'HTTPS'), ('probe', 'latency probe'), ('addkey', 'key registration'), ('wg', 'WireGuard'), ('ssh', 'SSH'), ('dns', 'DNS'), ('icmp', 'ICMP'), ('smtp', 'SMTP')]:
    s = C[k][0]
    add(f'  <line x1="{lx}" y1="{ly}" x2="{lx+34}" y2="{ly}" stroke="{s}" stroke-width="2.6" marker-end="url(#m{k})"/>')
    text(lx + 42, ly + 4, label, 'lb')
    lx += 42 + len(label) * 7 + 40
text(52, ly + 30, 'Solid = a request and its reply. Dashed = the tunnel (7), or a link the phone opens in the browser (14). The phone\'s own flows follow whatever route the phone has; the router\'s go straight out its internet connection.', 'lb', style='fill:#607D8B')

H2 = ty + th + 20
o[0] = o[0].replace(f'viewBox="0 0 {W} {H}"', f'viewBox="0 0 {W} {H2}"')
add('</svg>')
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(o) + '\n')
print('height', H2)
