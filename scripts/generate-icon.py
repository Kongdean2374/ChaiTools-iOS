#!/usr/bin/env python3
"""Original ChaiTools mark: a conversation C and a warm spark. Requires Pillow."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1] / 'ChaiTools' / 'Assets.xcassets'
root.mkdir(parents=True, exist_ok=True)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
size = 1024
im = Image.new('RGB', (size,size))
pixels = im.load()
for y in range(size):
    for x in range(size):
        t = (x+y)/(2*(size-1))
        glow = max(0, 1-((x-150)**2+(y-120)**2)**0.5/950)
        pixels[x,y] = (int(8+8*t+7*glow), int(49+53*t+10*glow), int(57+49*t+11*glow))
# Supersampled vector mark; the icon background stays opaque and square for iOS masking.
scale=3
layer = Image.new('RGBA', (size*scale,size*scale))
d=ImageDraw.Draw(layer)
def box(coords): return tuple(int(v*scale) for v in coords)
white=(240,250,247,255)
d.rounded_rectangle(box((222,258,780,728)), radius=128*scale, fill=white)
d.polygon([tuple(int(v*scale) for v in p) for p in [(264,660),(264,810),(430,695)]],fill=white)
# Letter C doubles as two conversation strokes, with room for the sparkle.
d.rounded_rectangle(box((329,365,658,439)), radius=37*scale, fill=(15,87,91,255))
d.rounded_rectangle(box((329,535,595,609)), radius=37*scale, fill=(15,87,91,255))
d.rounded_rectangle(box((329,365,403,609)), radius=37*scale, fill=(15,87,91,255))
# Compact four-point spark in the upper right.
d.polygon([tuple(int(v*scale) for v in p) for p in [(778,165),(803,239),(877,264),(803,289),(778,363),(753,289),(679,264),(753,239)]],fill=(247,205,117,255))
im = Image.alpha_composite(im.convert('RGBA'), layer.resize((size,size),Image.Resampling.LANCZOS)).convert('RGB')
icon=root/'AppIcon.appiconset'; icon.mkdir(exist_ok=True)
im.save(icon/'AppIcon.png', optimize=True)
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
brand=root/'BrandIcon.imageset'; brand.mkdir(exist_ok=True)
im.resize((192,192), Image.Resampling.LANCZOS).save(brand/'BrandIcon.png',optimize=True)
(brand/'Contents.json').write_text(json.dumps({'images':[{'filename':'BrandIcon.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2))
