#!/usr/bin/env python3
"""Turns article.md into what WordPress needs: image files to upload, and plain HTML for the code
editor, with no styles, fonts or embedded images, so the blog's own theme does the styling.

Usage:  python promotion/blog/make_wordpress.py [upload URL folder]
        The folder defaults to /wp-content/uploads/, where exponentiallydigital.com keeps uploads (no
        year and month folders). Every image is a JPEG, as the site converts uploads to JPEG anyway.
        Run make_diagrams.py first.
Writes: promotion/blog/wordpress/article.html and wordpress/images/*
"""
import html
import os
import re
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'wordpress')
IMAGES = os.path.join(OUT, 'images')
SCREENSHOTS = {'03.png': 'cfg-pia-wg-screen-devices.jpg', '04.png': 'cfg-pia-wg-screen-watchdog.jpg',
               '06.png': 'cfg-pia-wg-screen-dns.jpg'}
DIAGRAM_WIDTH, SHOT_WIDTH = 800, 320


def upload_name(src):
    """Copies or shrinks the image at [src] into wordpress/images, and returns its file name and display size."""
    path = os.path.normpath(os.path.join(HERE, src))
    if 'app-store' in path:
        name = SCREENSHOTS[os.path.basename(path)]
        im = Image.open(path).convert('RGB')
        im.thumbnail((SHOT_WIDTH * 2, 4000))
        im.save(os.path.join(IMAGES, name), 'JPEG', quality=86)
        return name, SHOT_WIDTH, round(SHOT_WIDTH * im.height / im.width)
    name = 'cfg-pia-wg-' + os.path.splitext(os.path.basename(path))[0] + '.jpg'
    with Image.open(path) as im:
        im.convert('RGB').save(os.path.join(IMAGES, name), 'JPEG', quality=92)
        return name, DIAGRAM_WIDTH, round(DIAGRAM_WIDTH * im.height / im.width)


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'<em>\1</em>', s)
    return re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', s)


def figure(line, base):
    alt, src = re.match(r'!\[([^\]]*)\]\(([^)]+)\)', line).groups()
    name, w, h = upload_name(src)
    a = html.escape(alt)
    # Inline styles, because the blog's theme doesn't style <figure>: centred, with room before what follows.
    return (f'<figure class="wp-block-image aligncenter" style="text-align: center; margin: 1.5em auto 2.5em;">'
            f'<img src="{base}{name}" alt="{a}" width="{w}" height="{h}" '
            f'style="display: block; margin: 0 auto; max-width: 100%; height: auto;" />'
            f'<figcaption style="text-align: center; margin-top: 0.6em;">{a}</figcaption></figure>')


def items(body, i, pattern):
    found = []
    while i < len(body) and re.match(pattern, body[i]):
        found.append(re.sub(pattern, '', body[i]))
        i += 1
    return found, i


def table(body, i):
    rows = []
    while i < len(body) and body[i].startswith('|'):
        rows.append([c.strip() for c in body[i].strip('|').split('|')])
        i += 1
    head = ''.join(f'<th>{inline(c)}</th>' for c in rows[0])
    data = ''.join('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>' for r in rows[2:])
    return f'<table><thead><tr>{head}</tr></thead><tbody>{data}</tbody></table>', i


def convert(md, base):
    lines = md.split('\n')
    body = lines[lines.index('---') + 1:]  # the title and editor's notes go in WordPress's own fields
    out, i = [], 0
    while i < len(body):
        line = body[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith('## '):
            out.append(f'<h2>{inline(line[3:])}</h2>')
        elif line == '---':
            out.append('<hr />')
        elif line.startswith('!['):
            out.append(figure(line, base))
        elif line.startswith('|'):
            block, i = table(body, i)
            out.append(block)
            continue
        elif re.match(r'\d+\. ', line):
            found, i = items(body, i, r'^\d+\. ')
            out.append('<ol>' + ''.join(f'<li>{inline(x)}</li>' for x in found) + '</ol>')
            continue
        elif line.startswith('- '):
            found, i = items(body, i, r'^- ')
            out.append('<ul>' + ''.join(f'<li>{inline(x)}</li>' for x in found) + '</ul>')
            continue
        elif line == 'Tunnel or nothing.':
            out.append('<p><strong>Tunnel or nothing.</strong></p>')
        else:
            out.append(f'<p>{inline(line)}</p>')
        i += 1
    # One block per line with a blank line between, so WordPress's automatic paragraphs leave them alone.
    return '\n\n'.join(out) + '\n'


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else '/wp-content/uploads/'
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(IMAGES)
    md = open(os.path.join(HERE, 'article.md'), encoding='utf-8').read()
    html_text = convert(md, base)
    with open(os.path.join(OUT, 'article.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(html_text)
    with Image.open(os.path.join(HERE, 'images', '00-featured.png')) as im:
        im.convert('RGB').save(os.path.join(IMAGES, 'cfg-pia-wg-featured.jpg'), 'JPEG', quality=92)
    for name in sorted(os.listdir(IMAGES)):
        print(f'{name:40} {os.path.getsize(os.path.join(IMAGES, name)) // 1024:5} KB')
    print(f'article.html: {len(html_text):,} characters, images at {base}')


if __name__ == '__main__':
    sys.exit(main())
