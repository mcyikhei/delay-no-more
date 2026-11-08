#!/usr/bin/env python3
"""Check the documented native palette against Swift tokens and text contrast."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
doc = (root / 'docs' / 'DESIGN.md').read_text()
theme = (root / 'Sources/DelayNoMore/Theme.swift').read_text()
colors = dict(re.findall(r'^  (\w+): "#([0-9A-Fa-f]{6})"$', doc, re.M))
runtime = dict(re.findall(r'static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)', theme))
assert colors == runtime, f'Document/runtime palette drift: {colors} != {runtime}'
def luminance(value):
    rgb = [int(value[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in rgb]
    return sum(c * w for c, w in zip(linear, (.2126, .7152, .0722)))
pairs = [('ink', surface) for surface in ('pink', 'lemon', 'mint', 'blue', 'lilac')]
for foreground, background in pairs:
    a, b = sorted((luminance(colors[foreground]), luminance(colors[background])))
    ratio = (b + .05) / (a + .05)
    assert ratio >= 4.5, f'{foreground}/{background}: {ratio:.2f} fails AA text contrast'
    print(f'{foreground}/{background}: {ratio:.2f}:1')
a = luminance(colors['accent'])
assert 1.05 / (a + .05) >= 4.5
print(f'Palette: {len(colors)} tokens match; all checked text pairs pass 4.5:1')
