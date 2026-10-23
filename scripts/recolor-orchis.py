#!/usr/bin/env python3
"""Make vendored Orchis frame surfaces follow the KDE colour scheme.

Dark hard-coded fills on frame parts (center/top/.../bottomright, any prefix
except shadow-, mask- and hint-) become fill:currentColor with the
ColorScheme-Background class; opacity is kept so translucency survives.
"""
import gzip, re, sys, pathlib

PART = r'(?:[a-z0-9-]*?-)?(?:center|top|bottom|left|right|topleft|topright|bottomleft|bottomright)'
SKIP = ('shadow-', 'mask-', 'hint-')
FILL = re.compile(r'fill:\s*(#[0-9a-fA-F]{6})')

def dark(hexcolour):
    r, g, b = (int(hexcolour[i:i + 2], 16) for i in (1, 3, 5))
    return max(r, g, b) <= 0x40

def recolour(svg, report):
    # Walk tags, tracking which ones sit inside a frame part element.
    out, depth_stack, pos = [], [], 0
    tag = re.compile(r'<(/?)([\w:]+)([^>]*?)(/?)>', re.S)
    for m in tag.finditer(svg):
        out.append(svg[pos:m.start()]); pos = m.end()
        closing, name, attrs, selfclose = m.groups()
        if closing:
            if depth_stack: depth_stack.pop()
            out.append(m.group(0)); continue
        ident = re.search(r'\bid="([^"]+)"', attrs)
        ident = ident.group(1) if ident else ''
        is_part = bool(re.fullmatch(PART, ident)) and not ident.startswith(SKIP)
        inside = is_part or (depth_stack and depth_stack[-1])
        if inside and name in ('rect', 'path', 'circle', 'ellipse', 'polygon'):
            style = re.search(r'style="([^"]*)"', attrs)
            f = FILL.search(style.group(1)) if style else None
            if f and dark(f.group(1)):
                new_style = FILL.sub('fill:currentColor', style.group(1), count=1)
                attrs = attrs.replace(style.group(0), f'style="{new_style}"')
                if 'class="' in attrs:
                    attrs = re.sub(r'class="[^"]*"', 'class="ColorScheme-Background"', attrs)
                else:
                    attrs = ' class="ColorScheme-Background"' + attrs
                report.append((ident or '(child)', f.group(1)))
        out.append(f'<{name}{attrs}{selfclose}>')
        if not selfclose:
            depth_stack.append(inside)
    out.append(svg[pos:])
    return ''.join(out)

def main(theme, write):
    """Print each changed file; rewrite it only with --write."""
    for path in sorted(pathlib.Path(theme).rglob('*.svg*')):
        if not any(k in path.name for k in ('background', 'tooltip', 'panel')):
            continue
        raw = path.read_bytes()
        svg = gzip.decompress(raw).decode() if path.suffix == '.svgz' else raw.decode()
        report = []
        new = recolour(svg, report)
        if report:
            print(path.relative_to(theme), len(report), sorted(set(c for _, c in report)))
            if write:
                data = new.encode()
                path.write_bytes(gzip.compress(data, mtime=0) if path.suffix == '.svgz' else data)

if __name__ == '__main__':
    main(sys.argv[1], '--write' in sys.argv)
