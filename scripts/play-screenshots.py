#!/usr/bin/env python3
"""Builds the Play Store screenshots: a caption in large type over each app screenshot.

Usage:  python scripts/play-screenshots.py

Writes three sets of eight, all 9:16, with the same captions in the same order:

  play-store/screenshots/phone/phone-01.png ...  1080 x 1920, from the README screenshots in images/
  play-store/screenshots/tablet-7/T7-01.png ...  1080 x 1920, from play-store/screenshots/tablet-source/
  play-store/screenshots/tablet-10/T10-01.png ... 1440 x 2560, from the same tablet screenshots

Play's limits: phone and 7-inch, each side 320 to 3,840 px; 10-inch, each side 1,080 to 7,680 px;
PNG or JPEG up to 8 MB; 16:9 or 9:16. tablet-source/ holds tablet screenshots with every name,
address, MAC and credential already replaced by invented ones. Captions stay clear of Play's rules
for listing graphics: no rankings, no prices or offers, no calls to action.

Needs Pillow and a bold sans font: Noto Sans Bold, from Windows or a Noto install. Set
PLAY_SHOT_FONT to use another.
"""
import os
import sys
import time

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'play-store', 'screenshots')

FONT_CANDIDATES = [
    os.environ.get('PLAY_SHOT_FONT', ''),
    'C:/Windows/Fonts/NotoSans-Bold.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
    '/usr/share/fonts/noto/NotoSans-Bold.ttf',
]

# The app's own colours (lib/app_colors.dart): background, surface, teal.
BG_TOP = (11, 13, 18)
BG_BOTTOM = (18, 20, 26)
TEAL = (0, 212, 170)
WHITE = (240, 242, 245)
BORDER = (42, 47, 58)

# Folder, file prefix (so each file says which Play slot it's for), size, and source.
SETS = [
    ('phone', 'phone', 1080, 1920, 'images'),
    ('tablet-7', 'T7', 1080, 1920, 'tablet-source'),
    ('tablet-10', 'T10', 1440, 2560, 'tablet-source'),
]

# In order: the first two or three show in search results, so they carry the app. Each entry is
# (phone screenshot in images/, tablet screenshot number in tablet-source/, caption).
SHOTS = [
    ('04.0-device-assignment.png', '01.png', 'Every device, its own VPN'),
    ('04.02-assign-device.png', '02.png', 'Tap a device. Pick a VPN. Done.'),
    ('04.031-assign-stopped-tunnel.png', '03.png', 'A kill switch for stock ASUS:\nno tunnel, no internet'),
    ('03.0-watchdog-configuration.png', '04.png', 'Dead tunnels rebuilt, and an email to say so'),
    ('02.0-router-slot-management.png', '05.png', 'Fresh PIA configs,\nstraight into your router'),
    ('06.05-router-dns-routing.png', '06.png', 'See exactly where your DNS goes'),
    ('05.02-router-log-guard.png', '07.png', 'Every check logged: see it working'),
    ('01.0-standalone-config.png', '08.png', 'WireGuard configs for any device'),
]


def font_path():
    for p in FONT_CANDIDATES:
        if p and os.path.exists(p):
            return p
    sys.exit('No bold sans font found: set PLAY_SHOT_FONT to a .ttf file.')


def wrap(draw, text, font, width):
    """The fewest lines that fit, then the most even split across them: no word left on its own."""
    words = text.split()
    n = len(words)

    def fits(line):
        return draw.textlength(line, font=font) <= width

    for count in range(1, n + 1):
        best, best_cost = None, None

        def split(start, left, acc):
            nonlocal best, best_cost
            if left == 1:
                line = ' '.join(words[start:])
                if not fits(line):
                    return
                lines = acc + [line]
                widths = [draw.textlength(l, font=font) for l in lines]
                cost = max(widths) - min(widths)
                if best_cost is None or cost < best_cost:
                    best, best_cost = lines, cost
                return
            for end in range(start + 1, n - left + 2):
                line = ' '.join(words[start:end])
                if not fits(line):
                    break
                split(end, left - 1, acc + [line])

        split(0, count, [])
        if best:
            return best
    return [text]


def background(W, H):
    im = Image.new('RGB', (W, H), BG_TOP)
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)))
    # A soft teal glow behind the phone, so the dark screenshot doesn't sink into the dark page.
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.1, H * 0.35, W * 0.9, H * 1.05], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(160 * W / 1080))
    im.paste(Image.new('RGB', (W, H), TEAL), (0, 0), glow.point(lambda v: v * 0.35))
    return im


def rounded(im, radius):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    return mask


def bezel(shot, pad):
    """A tablet's status bar runs to the screen's corner, so a rounded frame would clip its clock.
    Widen the screenshot by its own edge pixels, and round the corners of that instead."""
    w, h = shot.size
    out = Image.new('RGB', (w + 2 * pad, h + 2 * pad))
    out.paste(shot, (pad, pad))
    out.paste(shot.crop((0, 0, w, 1)).resize((w, pad)), (pad, 0))
    out.paste(shot.crop((0, h - 1, w, h)).resize((w, pad)), (pad, h + pad))
    out.paste(out.crop((pad, 0, pad + 1, h + 2 * pad)).resize((pad, h + 2 * pad)), (0, 0))
    out.paste(out.crop((w + pad - 1, 0, w + pad, h + 2 * pad)).resize((pad, h + 2 * pad)), (w + pad, 0))
    return out


def build(src, caption, font_file, dst, W, H):
    k = W / 1080
    im = background(W, H)
    d = ImageDraw.Draw(im)

    # The caption: large, centred, at most three lines. A caption with its own line breaks keeps
    # them, and the type shrinks until each line fits.
    size = round(76 * k)
    while True:
        font = ImageFont.truetype(font_file, size)
        if '\n' in caption:
            lines = caption.split('\n')
            if all(d.textlength(l, font=font) <= W - 150 * k for l in lines) or size <= round(52 * k):
                break
        else:
            lines = wrap(d, caption, font, W - 150 * k)
            if len(lines) <= 3 or size <= round(52 * k):
                break
        size -= 2
    pitch = round(size * 1.22)
    top = round(120 * k)
    for i, line in enumerate(lines):
        x = (W - d.textlength(line, font=font)) / 2
        d.text((x, top + i * pitch), line, font=font, fill=WHITE)
    caption_bottom = top + len(lines) * pitch
    # A short teal rule under the caption, the app's accent.
    d.rounded_rectangle([W / 2 - 40 * k, caption_bottom + 28 * k, W / 2 + 40 * k, caption_bottom + 36 * k], 4 * k, fill=TEAL)

    # The screenshot, scaled to the space left, with rounded corners, a border and a shadow.
    shot = Image.open(src).convert('RGB')
    if shot.width / shot.height >= 0.55:
        shot = bezel(shot, round(shot.width * 0.03))
    avail_top = caption_bottom + round(90 * k)
    avail_h = H - avail_top - round(70 * k)
    scale = min(avail_h / shot.height, (W - 160 * k) / shot.width)
    sw, sh = round(shot.width * scale), round(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, avail_top
    # A phone's corners are rounder than a tablet's; too round, and they clip the status bar's clock.
    radius = round(sw * (0.06 if shot.width / shot.height < 0.55 else 0.025))

    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + round(18 * k), x + sw, y + sh + round(18 * k)], radius, fill=170)
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * k))
    im.paste(Image.new('RGB', (W, H), (0, 0, 0)), (0, 0), shadow)

    im.paste(shot, (x, y), rounded(shot, radius))
    ImageDraw.Draw(im).rounded_rectangle([x - 2, y - 2, x + sw + 1, y + sh + 1], radius + 2, outline=BORDER, width=max(3, round(3 * k)))

    # Written aside, then moved into place, retrying: on Windows a virus scanner or a sync tool can
    # hold a file it has just seen being written, for a moment.
    tmp = dst + '.tmp.png'
    im.save(tmp, optimize=True)
    for attempt in range(20):
        try:
            os.replace(tmp, dst)
            break
        except OSError:
            if attempt == 19:
                raise
            time.sleep(0.5)
    return os.path.getsize(dst)


def main():
    font_file = font_path()
    for folder, prefix, w, h, source in SETS:
        out = os.path.join(OUT, folder)
        os.makedirs(out, exist_ok=True)
        for n, (phone, tablet, caption) in enumerate(SHOTS, start=1):
            src = os.path.join(ROOT, 'images', phone) if source == 'images' else os.path.join(OUT, source, tablet)
            dst = os.path.join(out, f'{prefix}-{n:02d}.png')
            size = build(src, caption, font_file, dst, w, h)
            print(f'{folder}/{prefix}-{n:02d}.png  {w}x{h}  {size / 1_000_000:.1f} MB  "{caption.replace(chr(10), " / ")}"')


if __name__ == '__main__':
    main()
