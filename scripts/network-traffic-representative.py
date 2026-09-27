#!/usr/bin/env python3
"""network-traffic-representative.py - draws images/network-traffic-(representative).svg (ID-239): which path each connection takes: LAN only, inside a tunnel, or straight out.

    python scripts/network-traffic-representative.py
    python scripts/svg-dark-variant.py "images/network-traffic-(representative).svg"

The SVG is generated: change this script, not the file, then run both lines above so the dark
version follows. The flows in it come from the code - lib/pia_service.dart, lib/router_watchdog.dart
(the watchdog script), lib/binary_installer.dart, lib/entitlement.dart - so a new connection in
any of those belongs here too.
"""
import sys
from html import escape

OUT = sys.argv[1] if len(sys.argv) > 1 else 'images/network-traffic-(representative).svg'
W = 1240
o = []
def add(s): o.append(s)
def text(x, y, s, cls='ns', anchor=None, style=None, fill=None):
    a = f' text-anchor="{anchor}"' if anchor else ''
    st = f' style="{style}"' if style else ''
    f = f' fill="{fill}"' if fill else ''
    add(f'  <text x="{x}" y="{y}" class="{cls}"{a}{st}{f}>{s}</text>')

def pill(x, y, n, c):
    """A number badge, the same as the logical diagram's, with its left edge at x and baseline y."""
    w = 16 + 7 * len(n)
    add(f'  <rect x="{x}" y="{y-12}" width="{w}" height="17" rx="8" fill="{c}"/>')
    add(f'  <text x="{x + w/2:.0f}" y="{y+1}" text-anchor="middle" class="bn">{n}</text>')
    return w

add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1240 HEIGHT" width="100%" preserveAspectRatio="xMidYMid meet" style="max-width:1200px;height:auto;font-family:\'Segoe UI\',Arial,sans-serif;background:#ffffff" role="img" aria-labelledby="t d">')
add('  <title id="t">Representative network traffic flow</title>')
add('  <desc id="d">Where each connection travels. SSH stays on the home network. The WireGuard tunnel runs from the router to a PIA server over the internet connection, encrypted, and PIA decrypts it and sends it on from its public IP pool. The phone\'s own connections follow the phone\'s route: through a slot\'s tunnel if the phone is pinned to it or the default connection is a slot, otherwise straight out. The router\'s own connections - the watchdog\'s calls to PIA, its encrypted DNS, alert email, check-target pings and helper downloads - go straight out the internet connection, except the watchdog\'s DNS name check, which goes through the tunnel on purpose. All IP addresses illustrative.</desc>')
add('''  <defs>
    <style>
      .zt{font:700 13px 'Segoe UI',Arial,sans-serif}
      .nt{font:700 13px 'Segoe UI',Arial,sans-serif;fill:#102027}
      .ns{font:12px 'Segoe UI',Arial,sans-serif;fill:#37474F}
      .nss{font:10.5px 'Segoe UI',Arial,sans-serif;fill:#546E7A}
      .lb{font:12px 'Segoe UI',Arial,sans-serif;fill:#37474F}
      .bn{font:700 11px 'Segoe UI',Arial,sans-serif;fill:#FEFEFE}
      .lbg{fill:#ffffff;fill-opacity:.85}
      .flow{fill:none;stroke-width:2.6}
    </style>
    <marker id="asl" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#455A64"/></marker>
    <marker id="ag" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2E7D32"/></marker>
    <marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#F44336"/></marker>
    <marker id="ab" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="11" markerHeight="11" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#1E88E5"/></marker>
  </defs>''')

text(620, 30, 'Representative network traffic flow', anchor='middle', style="font:700 21px 'Segoe UI',Arial,sans-serif;fill:#102027", cls='')
text(620, 53, 'Where each connection travels: only on your home network, inside a WireGuard tunnel, or straight out your internet connection.', anchor='middle', style="font:12px 'Segoe UI',Arial,sans-serif;fill:#607D8B", cls='')
text(620, 72, '<tspan font-weight="700">Note:</tspan> all IP addresses shown are for illustration only. The numbers match the logical diagram.', anchor='middle', style="font:12px 'Segoe UI',Arial,sans-serif;fill:#455A64", cls='')

# tunnel overlay
add('  <rect x="300" y="100" width="755" height="80" rx="40" fill="#4CAF50" fill-opacity="0.10" stroke="#2E7D32" stroke-width="2" stroke-dasharray="9 5"/>')
pill(400, 130, '7', '#4CAF50')
text(690, 130, 'WireGuard tunnel: router to a PIA server, encrypted, on the port PIA returns (1337)', anchor='middle', style="font:700 13px 'Segoe UI',Arial,sans-serif;fill:#1B5E20", cls='')
text(677, 150, "carries the phone's traffic when the phone uses this slot, and the watchdog's name check", 'ns', 'middle', 'fill:#2E7D32')
pill(933, 150, '9', '#9E9E9E')
text(677, 167, "does not carry the router's own traffic: the watchdog's calls to PIA, DoH, email and downloads", 'ns', 'middle', 'fill:#2E7D32')
add('  <path class="flow" stroke="#2E7D32" marker-start="url(#ag)" marker-end="url(#ag)" d="M345,180 L345,318"/>')
add('  <g><rect class="lbg" x="350" y="238" width="70" height="17" rx="4"/><text x="354" y="251" class="lb" fill="#2E7D32">encrypt ⇕</text></g>')
add('  <path class="flow" stroke="#2E7D32" marker-start="url(#ag)" marker-end="url(#ag)" d="M1000,180 L1000,298"/>')
add('  <g><rect class="lbg" x="1006" y="235" width="70" height="17" rx="4"/><text x="1010" y="248" class="lb" fill="#2E7D32">decrypt ⇕</text></g>')

# home network
add('  <rect x="25" y="288" width="405" height="178" rx="12" fill="#E3F2FD" fill-opacity="0.35" stroke="#90CAF9" stroke-dasharray="6 5"/>')
text(38, 307, 'Your home network (192.168.1.0/24)', 'zt', fill='#1565C0')
add('  <rect x="40" y="322" width="150" height="130" rx="11" fill="#ffffff" stroke="#1E88E5" stroke-width="2"/>')
add('  <rect x="54" y="336" width="26" height="44" rx="5" fill="#E3F2FD" stroke="#1E88E5" stroke-width="1.4"/>')
add('  <rect x="58" y="343" width="18" height="30" fill="#BBDEFB"/>')
text(92, 350, 'Phone', 'nt', style='font-size:12px')
text(92, 368, 'this app', 'nss')
text(50, 402, '192.168.1.100', 'nss')
text(50, 416, "follows the phone's route:", 'nss')
x = 50
for n, c in [('2-6', '#1E88E5'), ('13', '#1E88E5'), ('14', '#1E88E5'), ('15', '#9E9E9E')]:
    x += pill(x, 438, n, c) + 4
add('  <path d="M255,338 L255,452 L415,452 L415,338 L403,328 L391,338 L379,328 L367,338 L355,328 L343,338 L331,328 L319,338 L307,328 L295,338 L283,328 L271,338 L259,328 Z" fill="#ffffff" stroke="#F44336" stroke-width="2"/>')
text(266, 360, 'ASUS router', 'nt', style='font-size:12px')
text(266, 377, 'stock or Merlin · 192.168.1.1', 'nss')
text(266, 393, 'SSH :22 · slots wgc1-wgc5', 'nss')
text(266, 409, 'watchdog: rebuilds, emails', 'nss')
text(266, 425, 'encrypts the tunnel', 'nss')
text(266, 441, 'sends its own traffic direct', 'nss')
add('  <path class="flow" stroke="#455A64" marker-start="url(#asl)" marker-end="url(#asl)" d="M190,374 L255,374"/>')
add('  <path class="flow" stroke="#F44336" stroke-width="2.2" marker-start="url(#ar)" marker-end="url(#ar)" d="M190,396 L255,396"/>')
add('  <g><rect class="lbg" x="196" y="350" width="34" height="16" rx="3"/><text x="200" y="362" class="lb" fill="#37474F" style="font-size:11px">LAN</text></g>')
add('  <g><rect class="lbg" x="196" y="404" width="30" height="16" rx="3"/><text x="198" y="416" class="lb" fill="#C62828" style="font-size:11px">SSH</text></g>')
pill(228, 417, '1', '#F44336')

# ISP, internet, PIA
add('  <rect x="485" y="337" width="115" height="92" rx="10" fill="#ffffff" stroke="#90A4AE" stroke-width="2"/>')
add('  <path d="M542,352 L535,372 L549,372 Z" fill="#CFD8DC" stroke="#90A4AE" stroke-width="1.2"/>')
add('  <path d="M531,366 A9 9 0 0 1 553 366" fill="none" stroke="#90A4AE" stroke-width="1.2"/>')
text(542, 392, 'ISP', 'nt', 'middle', 'font-size:12px')
text(542, 409, 'your internet', 'nss', 'middle')
text(542, 423, 'connection', 'nss', 'middle')
add('  <g transform="translate(610,300) scale(1.18)"><path d="M 50 100 C 20 100 10 80 28 66 C 18 44 44 28 64 40 C 72 18 110 18 120 40 C 150 30 172 54 156 74 C 178 84 168 100 146 100 Z" fill="#ffffff" stroke="#455A64" stroke-width="1.6"/></g>')
text(721, 376, 'Internet', 'nt', 'middle', 'font-size:12px')
text(721, 394, '(public)', 'nss', 'middle')
add('  <rect x="885" y="300" width="235" height="165" rx="11" fill="#ffffff" stroke="#7B1FA2" stroke-width="2"/>')
add('  <rect x="885" y="300" width="7" height="165" rx="3" fill="#7B1FA2"/>')
text(1002, 324, 'PIA WireGuard server', 'nt', 'middle', 'font-size:12.5px')
text(1002, 343, 'tunnel endpoint, e.g. 143.244.50.40', 'nss', 'middle')
text(1002, 360, ':1337 UDP tunnel (7)', 'nss', 'middle')
text(1002, 376, ':1337 probe and addKey (5, 6)', 'nss', 'middle')
text(1002, 396, 'serverlist.piaservers.net :443 (2)', 'nss', 'middle')
text(1002, 412, 'privateinternetaccess.com :443 (3)', 'nss', 'middle')
text(1002, 440, '↳ the tunnel ends here: decrypt', 'nss', 'middle', 'fill:#2E7D32')

# underlay (encrypted) and direct paths
for d in ['M415,382 L485,382', 'M600,382 L632,380', 'M812,380 L885,382']:
    add(f'  <path class="flow" stroke="#2E7D32" marker-start="url(#ag)" marker-end="url(#ag)" d="{d}"/>')
for d in ['M415,412 L485,412', 'M600,412 L640,410']:
    add(f'  <path class="flow" stroke="#1E88E5" marker-start="url(#ab)" marker-end="url(#ab)" d="{d}"/>')
text(640, 478, 'green: the tunnel, encrypted, over your internet connection', 'nss', anchor='middle', style='fill:#2E7D32')
text(640, 494, "blue: the router's own traffic, straight out (2-6, 8, 10-12)", 'nss', anchor='middle', style='fill:#1565C0')

# exit
add('  <path class="flow" stroke="#2E7D32" marker-start="url(#ag)" marker-end="url(#ag)" d="M1002,465 L1002,525"/>')
add('  <g><rect class="lbg" x="1010" y="487" width="112" height="16" rx="3"/><text x="1014" y="499" class="lb" fill="#2E7D32" style="font-size:11px">decrypt → 172.16.x</text></g>')
add('  <rect x="885" y="525" width="235" height="130" rx="11" fill="#ffffff" stroke="#43A047" stroke-width="2"/>')
add('  <rect x="885" y="525" width="7" height="130" rx="3" fill="#43A047"/>')
text(1002, 550, 'PIA VPN exit', 'nt', 'middle', 'font-size:12.5px')
text(1002, 569, 'internal net 172.16.0.0/16', 'ns', 'middle', 'font-size:11.5px')
text(1002, 586, 'peer interface 172.16.1.50', 'nss', 'middle')
text(1002, 608, 'public IP pool (source NAT)', 'ns', 'middle', 'font-size:11.5px;fill:#1B5E20')
text(1002, 625, '185.230.125.10 - .50', 'nss', 'middle')
text(1002, 645, '↳ out to the public internet', 'nss', 'middle', 'fill:#455A64')
add('  <path class="flow" stroke="#455A64" marker-start="url(#asl)" marker-end="url(#asl)" d="M885,580 Q838,500 806,418"/>')
add('  <path class="flow" stroke="#455A64" marker-start="url(#asl)" marker-end="url(#asl)" d="M790,425 Q790,640 884,720"/>')
add('  <rect x="885" y="690" width="235" height="250" rx="11" fill="#ffffff" stroke="#90A4AE" stroke-width="2"/>')
text(1002, 714, 'Internet services', 'nt', 'middle', 'font-size:12.5px')
svc = [('4', '#1E88E5', 'PIA CA cert, GitHub'), ('8', '#1E88E5', 'DoH resolver, e.g. 1.1.1.2'), ('11', '#795548', 'your mail server'),
       ('10', '#FFC107', 'check targets, e.g. 8.8.8.8'), ('12', '#1E88E5', 'github.com releases'), ('13', '#1E88E5', 'RevenueCat, Google Play'),
       ('14', '#1E88E5', 'README, Play Store listing'), ('9', '#9E9E9E', "a slot's DNS server"), ('15', '#9E9E9E', 'DNS servers')]
for i, (n, c, t) in enumerate(svc):
    y = 736 + i * 21
    pill(900, y, n, c)
    text(936, y, escape(t), 'nss')
text(1002, 928, 'see your home address, or PIA\'s pool', 'nss', 'middle', 'fill:#607D8B')

# flow panel
py = 520
rows = [
    ('1', '#F44336', 'SSH 22', "the app's router commands", 'lan'),
    ('2-6', '#1E88E5', 'PIA, from the phone', 'STANDALONE and CREATE: list, token, CA, probes, addKey', 'phone'),
    ('2-6', '#9C27B0', 'PIA, from the watchdog', 'a rebuild: list, token, CA, pings, addKey', 'wan'),
    ('7', '#4CAF50', 'WireGuard', 'the tunnel itself, router to PIA', 'tun'),
    ('8', '#1E88E5', 'DoH 443', "the watchdog's own lookups, encrypted", 'wan*'),
    ('9', '#9E9E9E', 'DNS 53', "the watchdog's name check, through the slot", 'tun'),
    ('10', '#FFC107', 'ICMP', 'check targets (Merlin also pings through the tunnel)', 'wan'),
    ('11', '#795548', 'SMTP, TLS', 'alert emails and TEST EMAIL', 'wan*'),
    ('12', '#1E88E5', 'HTTPS 443', 'jq and mailsend-go downloads (stock)', 'wan'),
    ('13', '#1E88E5', 'HTTPS 443', 'RevenueCat and Google Play Billing', 'phone'),
    ('14', '#1E88E5', 'HTTPS 443', 'links opened in the browser', 'phone'),
    ('15', '#9E9E9E', 'DNS 53', "the phone's resolver / the router's DNS Server", 'mixed'),
]
chips = {
    'lan': ('LAN only', '#C62828'),
    'phone': ("the phone's route", '#6A1B9A'),
    'wan': ('straight out', '#1565C0'),
    'wan*': ('straight out *', '#1565C0'),
    'tun': ('in the tunnel', '#2E7D32'),
    'mixed': ("phone's route / straight out *", '#455A64'),
}
rh = 27
ph = 62 + len(rows) * rh + 92
add(f'  <rect x="30" y="{py}" width="770" height="{ph}" rx="12" fill="#FAFAFA" stroke="#CFD8DC"/>')
text(46, py + 24, 'Which path each connection takes', 'zt', fill='#37474F')
text(46, py + 42, 'The numbers are the badges in the picture above, and the rows of the logical diagram.', 'nss', style='fill:#90A4AE')
for i, (n, c, proto, what, path) in enumerate(rows):
    y = py + 70 + i * rh
    add(f'  <rect x="46" y="{y-12}" width="{16 + 7*len(n)}" height="17" rx="8" fill="{c}"/>')
    add(f'  <text x="{54 + 3.5*len(n):.0f}" y="{y+1}" text-anchor="middle" class="bn">{n}</text>')
    text(96, y, f'<tspan font-weight="700">{escape(proto)}</tspan>  {escape(what)}', 'lb')
    label, pc = chips[path]
    wdt = 14 + len(label) * 6.6
    add(f'  <rect x="{785 - wdt:.0f}" y="{y-12}" width="{wdt:.0f}" height="18" rx="9" fill="#ffffff" stroke="{pc}" stroke-width="1.4"/>')
    add(f'  <text x="{785 - wdt/2:.0f}" y="{y+1}" text-anchor="middle" class="lb" style="font-size:11.5px;font-weight:700;fill:{pc}">{escape(label)}</text>')
ny = py + 70 + len(rows) * rh + 8
notes = [
    "The phone's route: through a slot's tunnel if the phone is pinned to that slot, or if the default connection is a slot;",
    'otherwise straight out. SSH never leaves the home network.',
    "* The router's own rule: an address that is also a slot's DNS server goes through that slot instead. The WATCHDOG",
    'form warns when its DoH address is one of them; ROUTER-DNS.md explains why it matters.',
]
for i, n in enumerate(notes):
    text(48, ny + i * 17, escape(n), 'nss', style='fill:#607D8B')

H = max(py + ph, 960) + 20
o[0] = o[0].replace('HEIGHT', str(H))
add('</svg>')
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(o) + '\n')
print('height', H)
