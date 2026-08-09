#!/usr/bin/env python3
"""Render a polished DMG background image and helper assets.

Outputs:
  build/dmg-assets/background.png        540x340 Finder window background
  build/dmg-assets/background@2x.png     1080x680 retina variant
  build/dmg-assets/icon-volume.icns      volume icon for the mounted DMG
  build/dmg-assets/welcome.html          auto-opened installer welcome page
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ.get("MP_DMG_ASSET_DIR", str(ROOT / "build" / "dmg-assets")))
ASSETS = ROOT / "mac-app" / "MeetingPulse" / "Assets.xcassets" / "AppIcon.appiconset"
APP_NAME = "Meeting Pulse"
PRODUCT_LINE = "menu-bar availability for macOS"
APP_PATH = Path(
    os.environ.get(
        "MP_DMG_APP",
        str(ROOT / "build" / "local-arm64-release" / "Build" / "Products" / "Release" / f"{APP_NAME}.app"),
    )
)
VERSION = os.environ.get("MP_DMG_VERSION", "0.0.2")
ARCH_LABEL = os.environ.get("MP_DMG_ARCH_LABEL", "")
ARROW_FROM_X, ARROW_FROM_Y = 200, 195
ARROW_TO_X, ARROW_TO_Y = 410, 195

OUT.mkdir(parents=True, exist_ok=True)


def find_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Locate a system font that ships with macOS."""
    candidates_bold = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Helvetica.ttc",
    ]
    candidates_regular = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Helvetica.ttc",
    ]
    for path in (candidates_bold if bold else candidates_regular):
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def draw_background(size: int) -> Image.Image:
    width, height = size
    img = Image.new("RGB", (width, height), (245, 247, 250))
    draw = ImageDraw.Draw(img)

    # Soft top-to-bottom gradient: light cool gray to near-white
    for y in range(height):
        t = y / max(1, height - 1)
        r = int(238 + (255 - 238) * t)
        g = int(242 + (255 - 242) * t)
        b = int(248 + (255 - 248) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # Subtle accent bar at the top
    draw.rectangle([(0, 0), (width, 4)], fill=(20, 120, 220))

    # Title
    title_font = find_font(int(width * 0.085), bold=True)
    subtitle_font = find_font(int(width * 0.028), bold=False)
    title = APP_NAME
    sub = PRODUCT_LINE
    tb = draw.textbbox((0, 0), title, font=title_font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    draw.text(((width - tw) // 2, int(height * 0.10)), title, fill=(28, 32, 44), font=title_font)
    sb = draw.textbbox((0, 0), sub, font=subtitle_font)
    sw = sb[2] - sb[0]
    draw.text(((width - sw) // 2, int(height * 0.10) + th + 10), sub, fill=(96, 104, 120), font=subtitle_font)

    # Curved arrow from .app position to Applications position
    scale = width / 540.0
    fx = int(ARROW_FROM_X * scale)
    fy = int(ARROW_FROM_Y * scale)
    tx = int(ARROW_TO_X * scale)
    ty = int(ARROW_TO_Y * scale)
    line_color = (140, 152, 170)
    head_color = (140, 152, 170)
    line_w = max(2, int(3 * scale))
    head_w = max(8, int(14 * scale))

    draw.line([(fx, fy), (tx, ty)], fill=line_color, width=line_w)
    # Arrowhead
    draw.polygon(
        [
            (tx, ty),
            (tx - head_w, ty - head_w // 2),
            (tx - head_w, ty + head_w // 2),
        ],
        fill=head_color,
    )

    # Hint labels under the arrow
    hint_font = find_font(int(width * 0.022), bold=False)
    hint_a = "Drag  here"
    hint_b = "to  Applications"
    hb_a = draw.textbbox((0, 0), hint_a, font=hint_font)
    hb_b = draw.textbbox((0, 0), hint_b, font=hint_font)
    label_y = int(height * 0.66)
    draw.text(
        ((fx + tx) // 2 - (hb_a[2] - hb_a[0]) // 2, label_y),
        hint_a,
        fill=(120, 130, 148),
        font=hint_font,
    )
    draw.text(
        ((fx + tx) // 2 - (hb_b[2] - hb_b[0]) // 2, label_y + (hb_a[3] - hb_a[1]) + 4),
        hint_b,
        fill=(120, 130, 148),
        font=hint_font,
    )

    # Very subtle inner border
    draw.rectangle([(0, 0), (width - 1, height - 1)], outline=(225, 230, 238), width=1)
    return img


def write_backgrounds() -> None:
    standard = draw_background((540, 340))
    standard.save(OUT / "background.png", optimize=True)
    retina = draw_background((1080, 680))
    retina.save(OUT / "background@2x.png", optimize=True)
    print(f"render-dmg-assets: wrote {OUT / 'background.png'} (540x340) and @2x (1080x680)")


def write_volume_icon() -> None:
    src = ASSETS / "icon-512.png"
    if not src.exists():
        print(f"render-dmg-assets: missing {src}; skipping volume icon")
        return
    iconset = OUT / "icon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    img = Image.open(src).convert("RGBA")

    # Required PNG sizes for icns
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        resized = img.resize((size, size), Image.LANCZOS)
        resized.save(iconset / name, optimize=True)

    icns_path = OUT / "icon-volume.icns"
    if icns_path.exists():
        icns_path.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)],
        check=True,
    )
    print(f"render-dmg-assets: wrote {icns_path}")


def write_welcome() -> None:
    version = VERSION
    plist = APP_PATH / "Contents" / "Info.plist"
    if plist.exists():
        try:
            out = subprocess.check_output(
                ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", str(plist)],
                text=True,
            ).strip()
            if out:
                version = out
        except subprocess.CalledProcessError:
            pass

    display_name = f"{APP_NAME} {version}"
    if ARCH_LABEL:
        display_name = f"{display_name} ({ARCH_LABEL})"

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{display_name} — Install</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
    margin: 0;
    padding: 48px 56px;
    color: #1d2330;
    background: linear-gradient(180deg, #f5f7fa 0%, #ffffff 240px);
  }}
  .accent {{ height: 4px; background: #1478dc; border-radius: 2px; margin: -8px -8px 28px; }}
  h1 {{ font-size: 28px; margin: 0 0 6px; letter-spacing: -0.01em; }}
  .lede {{ font-size: 14px; color: #5b6577; margin: 0 0 24px; }}
  h2 {{ font-size: 15px; margin: 24px 0 8px; color: #2c3344; }}
  p, li {{ font-size: 13px; line-height: 1.55; color: #2c3344; }}
  ol {{ padding-left: 18px; }}
  code {{ font-family: "SF Mono", Menlo, monospace; font-size: 12px; background: #eef2f7; padding: 1px 6px; border-radius: 4px; }}
  .note {{ background: #fff8e6; border-left: 3px solid #f0a500; padding: 10px 14px; border-radius: 4px; margin-top: 24px; font-size: 12px; }}
  kbd {{ font-family: inherit; background: #eef2f7; border: 1px solid #d4dae3; border-radius: 4px; padding: 1px 6px; font-size: 11px; }}
</style>
</head>
<body>
  <div class="accent"></div>
  <h1>{display_name}</h1>
  <p class="lede">{PRODUCT_LINE}.</p>

  <h2>Install</h2>
  <ol>
    <li>Drag <strong>{APP_NAME}</strong> to the <strong>Applications</strong> folder shortcut in this window.</li>
    <li>Open <strong>Applications</strong> and double-click {APP_NAME}.</li>
    <li>Grant <strong>Accessibility</strong> when prompted (required to read Chrome Meet and Slack Huddle controls).</li>
    <li>Look for the menu-bar icon — green means available, red means on a call.</li>
  </ol>

  <h2>First launch &mdash; Gatekeeper</h2>
  <p>This build is <em>not notarized</em>. macOS will refuse to open it the first time. To unblock:</p>
  <ol>
    <li>Open Finder, go to <strong>Applications</strong>.</li>
    <li><strong>Right-click</strong> {APP_NAME} → <strong>Open</strong>.</li>
    <li>Click <strong>Open</strong> in the dialog. You only need to do this once.</li>
  </ol>
  <p>Or from Terminal: <code>xattr -dr com.apple.quarantine "/Applications/{APP_NAME}.app"</code></p>

  <h2>Uninstall</h2>
  <ol>
    <li>Quit {APP_NAME} from the menu bar.</li>
    <li>Drag <code>{APP_NAME}.app</code> from Applications to the Trash.</li>
    <li>Optional: remove local state with <code>rm -rf ~/Library/Application\\ Support/{APP_NAME}</code>.</li>
  </ol>

  <h2>Privacy</h2>
  <p>{APP_NAME} reads Accessibility to observe Chrome Google Meet controls and Slack Huddle windows. It never records audio, video, screenshots, or screen contents, and never sends meeting details anywhere.</p>

  <div class="note">
    Need help? See <code>docs/</code> in the project repository, or check the README for the support link.
  </div>
</body>
</html>
"""
    (OUT / "welcome.html").write_text(html, encoding="utf-8")
    print(f"render-dmg-assets: wrote {OUT / 'welcome.html'}")


def main() -> int:
    write_backgrounds()
    write_volume_icon()
    write_welcome()
    return 0


if __name__ == "__main__":
    sys.exit(main())
