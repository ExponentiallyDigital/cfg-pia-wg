#!/usr/bin/env python3
"""Cuts the README's cropped screenshots out of the full screens test/release/readme_screenshots_test.dart
draws (ID-517), the size and framing the originals had, so the README's layout doesn't move.

Usage:  python scripts/readme-crops.py   (after the README test, which writes build/readme_crops.json)

Each crop keeps the original's size and puts its anchor (the dialog's title, or ABOUT's heading) where the
original had it. 99.01 is the main menu's header with the original's hand-drawn arrow copied back on.
Needs Pillow.
"""
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, 'images')

# name: (width, height, how far below the crop's top the anchor's top sat in the original)
CROPS = {
    '02.03-slot-created.png': (1440, 1221, 335),
    '02.04-ping-targets.png': (1440, 1204, 245),
    '07.02-about-update-watchdog.png': (1440, 1259, 50),
}

# 99.01: the header, as the original's 596 pixels, and where its arrow is.
HEADER_HEIGHT = 596
ARROW_BOX = (20, 280, 170, 565)


def crop_all():
    with open(os.path.join(ROOT, 'build', 'readme_crops.json'), encoding='utf-8') as f:
        anchors = json.load(f)
    for name, (width, height, above) in CROPS.items():
        path = os.path.join(IMAGES, name)
        full = Image.open(path)
        if full.size == (width, height):
            print(f'  {name}: already cropped, left as it is')
            continue
        top = max(0, min(int(anchors[name][1]) - above, full.height - height))
        full.crop((0, top, width, top + height)).save(path)
        print(f'  {name}: {width} x {height} from y {top}')


def header_with_arrow():
    path = os.path.join(IMAGES, '99.01-hamburger-off-main.png')
    original = Image.open(path).convert('RGBA')
    header = Image.open(os.path.join(IMAGES, '00.0-main-menu.png')).convert('RGBA').crop((0, 0, 1440, HEADER_HEIGHT))
    header.paste(original.crop(ARROW_BOX), ARROW_BOX[:2])
    header.convert('RGB').save(path)
    print(f'  99.01-hamburger-off-main.png: 00.0\'s header with the arrow')


if __name__ == '__main__':
    crop_all()
    header_with_arrow()
