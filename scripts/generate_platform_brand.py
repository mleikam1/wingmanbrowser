#!/usr/bin/env python3
"""Resize the approved Wingman raster only; preserve every original white pixel.

Needs Pillow. No network access. Source files are never modified. Transparent
pixels occur only in newly added splash padding, not in the supplied artwork.
"""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/brand/wingman-mark.png'
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
mark = Image.open(SOURCE).convert('RGB')
written = []

def save(image, relative):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, 'PNG', optimize=True)
    written.append({'path': relative, 'width': image.width, 'height': image.height, 'mode': image.mode})

def contain(canvas, box, fraction):
    width = round(box * fraction)
    height = round(width * mark.height / mark.width)
    if height > width:
        width, height = round(width * width / height), width
    resized = mark.resize((width, height), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((box-width)//2, (box-height)//2))
    return canvas

def square(size, fraction):
    return contain(Image.new('RGB', (size,size), 'white'), size, fraction)

def medallion(size, diameter=1.0):
    # The entire rectangular crop fits inside the new white circle. No source
    # pixels are removed to simulate transparency or a monochrome version.
    big = size * 3
    image = Image.new('RGBA', (big,big), (0,0,0,0))
    margin = round(big*(1-diameter)/2)
    ImageDraw.Draw(image).ellipse((margin,margin,big-margin-1,big-margin-1), fill='white')
    contain(image, big, diameter*.68)
    return image.resize((size,size), Image.Resampling.LANCZOS)

# Existing pre-26 launcher slots, plus proper foreground/background adaptive layers.
for density, scale in [('mdpi',1),('hdpi',1.5),('xhdpi',2),('xxhdpi',3),('xxxhdpi',4)]:
    save(square(round(48*scale), .86), f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
    # 60dp artwork <66dp safe zone in each108dp layer.
    save(square(round(108*scale), 60/108), f'android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png')

save(medallion(288), 'android/app/src/main/res/drawable-nodpi/wingman_launch_mark.png')
# Android12 icon without icon background:288dp canvas with192dp safe circle.
save(medallion(864, 192/288), 'android/app/src/main/res/drawable-nodpi/wingman_splash_android12.png')

icon_dir = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((icon_dir/'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0])*float(item['scale'][:-1]))
    save(square(size,.86), f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{item["filename"]}')
for scale,suffix in [(1,''),(2,'@2x'),(3,'@3x')]:
    save(medallion(96*scale), f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png')

save(square(64,.90), 'web/favicon.png')
save(square(180,.86), 'web/icons/apple-touch-icon.png')
for size in (192,512):
    save(square(size,.86), f'web/icons/Icon-{size}.png')
    # The whole raster rectangle, including its white corners, is inside the
    # centered40%-radius circle. No logo pixel relies on the browser mask.
    assert .56*math.sqrt(2)/2 < .4
    save(square(size,.56), f'web/icons/Icon-maskable-{size}.png')

assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
manifest={'source':'assets/brand/wingman-mark.png','sourceSha256':source_hash,'operations':['proportional Lanczos resize','center on white canvas','add transparent outer splash padding'],'generated':written}
(ROOT/'docs/ui/native_brand_assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Generated {len(written)} platform variants; approved source unchanged.')
