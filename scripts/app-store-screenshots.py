#!/usr/bin/env python3
"""Builds the App Store screenshots (ID-454), the same way as the Play ones: a caption in large type
over each app screenshot, with play-screenshots.py's layout and captions.

Usage:  python scripts/app-store-screenshots.py

Writes:

  app-store/screenshots/iphone/01.png ...  1290 x 2796, App Store Connect's APP_IPHONE_67 slot
  app-store/screenshots/ipad/01.png ...    2048 x 2732, its APP_IPAD_PRO_3GEN_129 slot

Apple takes these sizes for its largest iPhones and iPads and scales them down for the rest, so
these two sets are all it needs. scripts/app_store_connect.py uploads them.

The sources are the Play sources, with every name, address, MAC and credential already invented,
and Android's status bar and gesture bar cropped off: the app's own screens are the same on iOS,
but App Review refuses screenshots that show another platform (guideline 2.3.10). For the same
reason, any shot showing a device named after another platform's phone ("Pixel-8",
"android-dhcp-17") is left out; see SHOTS. Needs Pillow and the font play-screenshots.py needs.
"""
import importlib.util
import os
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'app-store', 'screenshots')

_spec = importlib.util.spec_from_file_location('play_screenshots', os.path.join(ROOT, 'scripts', 'play-screenshots.py'))
play = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(play)

# (folder, width, height, source folder, crop box removing Android's status and gesture bars,
#  the indexes into play.SHOTS to use). Measured on the 1440 x 3120 phone and 1600 x 2560 tablet
# sources: the status bar ends at about 150 and 60 px, and the HOME button at about 2990 and 2455.
SETS = [
    ('iphone', 1290, 2796, os.path.join(ROOT, 'images'), (0, 150, 1440, 3010),
     # Shot 6, ROUTER DNS ROUTING, lists a device called "Pixel-8".
     [0, 1, 2, 3, 4, 6, 7]),
    ('ipad', 2048, 2732, os.path.join(ROOT, 'play-store', 'screenshots', 'tablet-source'), (0, 60, 1600, 2480),
     # Shots 1 to 3 show "Pixel-8" or "android-dhcp-17" in the device list, and 6 is the DNS screen.
     [3, 4, 6, 7]),
]


def main():
    font = play.font_path()
    with tempfile.TemporaryDirectory() as tmp:
        for folder, W, H, src_dir, box, picks in SETS:
            dst_dir = os.path.join(OUT, folder)
            os.makedirs(dst_dir, exist_ok=True)
            for old in os.listdir(dst_dir):
                if old.endswith('.png'):
                    os.remove(os.path.join(dst_dir, old))
            for n, i in enumerate(picks, 1):
                phone_name, tablet_name, caption = play.SHOTS[i]
                name = phone_name if folder.startswith('iphone') else tablet_name
                cropped = os.path.join(tmp, f'{folder}-{n}.png')
                Image.open(os.path.join(src_dir, name)).convert('RGB').crop(box).save(cropped)
                dst = os.path.join(dst_dir, f'{n:02d}.png')
                play.build(cropped, caption, font, dst, W, H)
                with Image.open(dst) as im:
                    if im.size != (W, H):
                        sys.exit(f'{dst} is {im.size}, not {W} x {H}')
                print(f'{dst}  {caption!r}')


if __name__ == '__main__':
    main()
