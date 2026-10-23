#!/usr/bin/env python3
"""Paint vendored Orchis frame surfaces in the KDE colour scheme's background.

Orchis hard-codes grey and black fills on its panel, popup, tooltip and
widget frames. Each dark fill on a frame part (center/top/.../bottomright,
any prefix except shadow-, mask- and hint-) becomes the scheme's Window
background, or its Tooltip background in tooltip frames; opacity is kept so
translucency survives. The colour is written literally, and fills Orchis
already paints with currentColor in the ColorScheme-Background class get the
same treatment: Plasma resolves that class to light grey for notifications
and tooltips, which left white text on a pale card.

Switch handles are moved from the button background to the button text
colour: on the black scheme a navy knob on the faint off-state track was
nearly invisible.

Usage: recolor-orchis.py THEME_DIR --scheme FILE.colors [--write]
Prints each file that needs a change; rewrites it only with --write.
"""
import configparser
import gzip
import pathlib
import re
import sys

PART = r'(?:[a-z0-9-]*?-)?(?:center|top|bottom|left|right|topleft|topright|bottomleft|bottomright)'
SKIP = ('shadow-', 'mask-', 'hint-')
FILL = re.compile(r'fill:\s*(#[0-9a-fA-F]{6})')
CURRENT = re.compile(r'fill:\s*currentColor')
TAG = re.compile(r'<(/?)([\w:]+)([^>]*?)(/?)>', re.S)


def background(scheme, group):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(scheme)
    r, g, b = (int(v) for v in parser.get('Colors:' + group, 'BackgroundNormal').split(',')[:3])
    return f'#{r:02x}{g:02x}{b:02x}'


def dark(colour):
    return max(int(colour[i:i + 2], 16) for i in (1, 3, 5)) <= 0x40


def recolour(svg, target, report):
    out, inside_stack, pos = [], [], 0
    for m in TAG.finditer(svg):
        out.append(svg[pos:m.start()])
        pos = m.end()
        closing, name, attrs, selfclose = m.groups()
        if closing:
            if inside_stack:
                inside_stack.pop()
            out.append(m.group(0))
            continue
        ident = re.search(r'\bid="([^"]+)"', attrs)
        ident = ident.group(1) if ident else ''
        is_part = bool(re.fullmatch(PART, ident)) and not ident.startswith(SKIP)
        inside = is_part or (inside_stack and inside_stack[-1])
        if inside and name in ('rect', 'path', 'circle', 'ellipse', 'polygon'):
            style = re.search(r'style="([^"]*)"', attrs)
            fill = FILL.search(style.group(1)) if style else None
            if fill and dark(fill.group(1)) and fill.group(1).lower() != target:
                new_style = FILL.sub('fill:' + target, style.group(1), count=1)
                attrs = attrs.replace(style.group(0), f'style="{new_style}"')
                report.append(fill.group(1).lower())
            elif (style and CURRENT.search(style.group(1))
                  and re.search(r'class="[^"]*ColorScheme-Background\b', attrs)):
                new_style = CURRENT.sub('fill:' + target, style.group(1), count=1)
                attrs = attrs.replace(style.group(0), f'style="{new_style}"')
                report.append('currentColor')
        out.append(f'<{name}{attrs}{selfclose}>')
        if not selfclose:
            inside_stack.append(inside)
    out.append(svg[pos:])
    return ''.join(out)


HANDLES = ('handle', 'handle-hover', 'handle-pressed')


def light_handles(svg, report):
    def group(match):
        new = match.group(0).replace('ColorScheme-ButtonBackground', 'ColorScheme-ButtonText')
        if new != match.group(0):
            report.append('handle')
        return new
    pattern = r'<g\b[^>]*\bid="(?:%s)"[^>]*>.*?</g>' % '|'.join(HANDLES)
    return re.sub(pattern, group, svg, flags=re.S)


def main(arguments):
    if not arguments or '--scheme' not in arguments[:-1]:
        print(__doc__.split('\n\n')[-1].strip(), file=sys.stderr)
        return 2
    theme = pathlib.Path(arguments[0])
    scheme = arguments[arguments.index('--scheme') + 1]
    write = '--write' in arguments
    for path in sorted(theme.rglob('*.svg*')):
        surface = any(key in path.name for key in ('background', 'tooltip', 'panel'))
        if not surface and not path.name.startswith('switch.'):
            continue
        raw = path.read_bytes()
        svg = gzip.decompress(raw).decode() if path.suffix == '.svgz' else raw.decode()
        report = []
        target = background(scheme, 'Tooltip' if 'tooltip' in path.name else 'Window')
        new = recolour(svg, target, report) if surface else light_handles(svg, report)
        if report:
            print(path.relative_to(theme), len(report), sorted(set(report)), *(('->', target) if surface else ()))
            if write:
                data = new.encode()
                path.write_bytes(gzip.compress(data, mtime=0) if path.suffix == '.svgz' else data)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
