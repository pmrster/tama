#!/usr/bin/env python3
"""Generate a deterministic .DS_Store that lays out the Tama DMG window:
Tama.app on the LEFT, the Applications symlink on the RIGHT (natural left->right drag).

Install dependency:
  python3 -m pip install -r Packaging/requirements-dmg.txt

Run:
  python3 Packaging/make-dmg-dsstore.py Packaging/dmg.DS_Store

package.sh copies the result into the DMG staging folder as `.DS_Store`, so the layout is
baked in at `hdiutil create` time — no Finder / AppleScript / Automation permission needed.
"""
import sys

try:
    from ds_store import DSStore
except ImportError:
    print("missing Python package: ds_store", file=sys.stderr)
    print("install it with: python3 -m pip install -r Packaging/requirements-dmg.txt", file=sys.stderr)
    raise SystemExit(1)

OUT = sys.argv[1] if len(sys.argv) > 1 else "Packaging/dmg.DS_Store"

# Content size of the DMG window and icon coordinates (origin = top-left of the content area).
WIN_W, WIN_H = 560, 360
ICON_Y = 170
TAMA_X = 150          # left
APPS_X = 410          # right

with DSStore.open(OUT, "w+") as d:
    d["."]["vSrn"] = ("long", 1)
    d["."]["bwsp"] = {
        "WindowBounds": "{{200, 150}, {%d, %d}}" % (WIN_W, WIN_H),
        "ShowToolbar": False,
        "ShowStatusBar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowTabView": False,
    }
    d["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "backgroundType": 0,
        "arrangeBy": "none",
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": 96.0,
        "textSize": 12.0,
        "labelOnBottom": True,
        "showIconPreview": True,
        "showItemInfo": False,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    d["Tama.app"]["Iloc"] = (TAMA_X, ICON_Y)
    d["Applications"]["Iloc"] = (APPS_X, ICON_Y)

print("wrote", OUT)
