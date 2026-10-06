#!/usr/bin/env python3
"""Generate NetColors/Resources/AppIcon.icon — the Icon Composer document for the app icon.

The icon is a signal symbol: a dot with three arcs in the app's status colours.
Icon Composer (Xcode 26+) adds the background gradient, Liquid Glass, shadows and the
dark / tinted / clear appearances, so the artwork here is flat filled geometry.

Run from the repository root:  python3 tools/make_app_icon.py
"""
import json
import math
import shutil
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "NetColors/Resources/AppIcon.icon"

# Geometry on a 1024 × 1024 canvas
CX, CY = 512, 715            # signal origin (dot centre)
DOT_R = 62
HALF_W = 38                  # half thickness of each arc
SPAN = (225, 315)            # arc span in degrees, y-down: a 90° opening upwards
ARCS = [                     # radius, colour — iOS system red / orange / green, as on the status screen
    (170, "#FF3B30"),
    (300, "#FF9500"),
    (430, "#34C759"),
]

BACKGROUND = "#E9EEF4"       # cool light grey; Icon Composer turns it into a soft gradient
TRANSLUCENCY = 0.2           # 0.5 is Icon Composer's default and washes the colours out
DOT_LIGHT = "#1C1C1E"        # dot on the light background
DOT_DARK = "#FFFFFF"         # dot in dark and tinted appearances


def point(r, angle):
    a = math.radians(angle)
    return CX + r * math.cos(a), CY + r * math.sin(a)


def arc_path(r):
    """A thick arc with round caps as one filled outline."""
    ro, ri = r + HALF_W, r - HALF_W
    o1, o2 = point(ro, SPAN[0]), point(ro, SPAN[1])
    i1, i2 = point(ri, SPAN[0]), point(ri, SPAN[1])
    p = lambda xy: f"{xy[0]:.2f} {xy[1]:.2f}"
    return (f"M {p(o1)} A {ro} {ro} 0 0 1 {p(o2)} "
            f"A {HALF_W} {HALF_W} 0 0 1 {p(i2)} "
            f"A {ri} {ri} 0 0 0 {p(i1)} "
            f"A {HALF_W} {HALF_W} 0 0 1 {p(o1)} Z")


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
            f"{body}\n</svg>\n")


def colour(hex_value):
    h = hex_value.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return "extended-srgb:" + ",".join(f"{c:.5f}" for c in [*rgb, 1])


def manifest():
    dot_fill = [
        {"value": {"solid": colour(DOT_LIGHT)}},
        {"appearance": "dark", "value": {"solid": colour(DOT_DARK)}},
        {"appearance": "tinted", "value": {"solid": colour(DOT_DARK)}},
    ]
    return {
        "fill": {"automatic-gradient": colour(BACKGROUND)},
        "groups": [{
            "layers": [
                {"image-name": "dot.svg", "name": "Dot", "fill-specializations": dot_fill},
                {"image-name": "arcs.svg", "name": "Arcs"},
            ],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": TRANSLUCENCY},
        }],
        "supported-platforms": {"squares": "shared"},
    }


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "Assets").mkdir(parents=True)
    arcs = "\n".join(f'  <path fill="{c}" d="{arc_path(r)}"/>' for r, c in ARCS)
    (OUT / "Assets/arcs.svg").write_text(svg(arcs))
    (OUT / "Assets/dot.svg").write_text(svg(f'  <circle cx="{CX}" cy="{CY}" r="{DOT_R}" fill="#000000"/>'))
    (OUT / "icon.json").write_text(json.dumps(manifest(), indent=2) + "\n")
    print(f"wrote {OUT.relative_to(Path.cwd()) if OUT.is_relative_to(Path.cwd()) else OUT}")


if __name__ == "__main__":
    main()
