#!/usr/bin/env python3
"""Generate a .DS_Store that gives the mounted DMG a clean Finder layout.

Sets:
  - window size 540x340 (matches background.png)
  - background image (.background/background.png)
  - icon positions for Meeting Pulse.app and Applications
"""
import os
import sys
from pathlib import Path

from ds_store import DSStore

ROOT = Path(__file__).resolve().parents[2]
STAGE = Path(os.environ.get("MP_DMG_STAGE", str(ROOT / "build" / "dmg-stage")))
TARGET = STAGE / ".DS_Store"

W, H = 540, 340

# App icon on the left, Applications shortcut on the right.
ICON_APP = ("Meeting Pulse.app", 145, 145)
ICON_APPS = ("Applications", 400, 145)


def main() -> int:
    if TARGET.exists():
        TARGET.unlink()
    TARGET.parent.mkdir(parents=True, exist_ok=True)

    # DSStore.open checks mode == "w" / "w+" literally. On Python 3.14 the
    # package's text-mode open path fails with UnsupportedOperation on read,
    # so we open the file in binary w+ ourselves and pass the handle.
    handle = open(str(TARGET), "w+b")
    try:
        with DSStore.open(handle, "w+") as store:
            # Window bounds for the mounted volume's Finder window.
            store["."]["bwsp"] = {
                "DefaultBrowserLanguage": 1,
                "WindowBounds": f"{{{{100, 100, {W + 100}, {H + 100}}}}}",
            }
            # Icon view options (size, label position, grid spacing).
            store["."]["icvp"] = {
                "arrangeBy": "none",
                "gridOffsetX": 0,
                "gridOffsetY": 0,
                "gridSpacingX": 100,
                "gridSpacingY": 100,
                "iconSize": 96,
                "labelOnBottom": True,
                "showIconPreview": True,
                "textSize": 12,
            }
            # View style = icon view (1 = icon, 2 = list, 3 = column).
            store["."]["lsvp"] = {
                "lsvp": 1,
                "lsvtp": 0,
            }

            # Icon positions: ds_store's Iloc codec encodes as a struct.
            for name, x, y in (ICON_APP, ICON_APPS):
                store[name]["Iloc"] = (x, y)
    finally:
        handle.close()

    print(f"write-ds-store: wrote {TARGET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
