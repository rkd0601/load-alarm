#!/usr/bin/env python3
"""Generate web, Android and iOS launcher/splash assets from a square-ish source image.
Usage: python3 tools/apply_branding.py path/to/source.png
Requires Pillow: python3 -m pip install pillow
"""
from pathlib import Path
import sys
from PIL import Image, ImageOps

src = Path(sys.argv[1]) if len(sys.argv) > 1 else None
if not src or not src.exists():
    raise SystemExit('Usage: python3 tools/apply_branding.py path/to/source.png')
root = Path(__file__).resolve().parents[1]
img = Image.open(src).convert('RGBA')
# Center-crop to square for icons.
size = min(img.size)
left = (img.width - size) // 2
top = (img.height - size) // 2
icon = img.crop((left, top, left + size, top + size))

def save_png(path, image, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)

# Web PWA icons.
for px in (192, 512):
    save_png(root / 'web' / f'icons/Icon-{px}.png', icon, px)
# Android launcher icons.
for folder, px in {'mipmap-mdpi': 48, 'mipmap-hdpi': 72, 'mipmap-xhdpi': 96, 'mipmap-xxhdpi': 144, 'mipmap-xxxhdpi': 192}.items():
    save_png(root / 'android/app/src/main/res' / folder / 'ic_launcher.png', icon, px)
# iOS icons.
ios_icons = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167, 'Icon-App-1024x1024@1x.png': 1024,
}
for name, px in ios_icons.items():
    save_png(root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset' / name, icon, px)
# Splash/launch images use contain fit on dark background.
for name, px in {'LaunchImage.png': 320, 'LaunchImage@2x.png': 640, 'LaunchImage@3x.png': 960}.items():
    canvas = Image.new('RGBA', (px, px), (18, 24, 31, 255))
    fitted = ImageOps.contain(img, (int(px * 0.82), int(px * 0.82)), Image.Resampling.LANCZOS)
    canvas.alpha_composite(fitted, ((px - fitted.width) // 2, (px - fitted.height) // 2))
    canvas.save(root / 'ios/Runner/Assets.xcassets/LaunchImage.imageset' / name)
print(f'Branding assets generated from {src}')
