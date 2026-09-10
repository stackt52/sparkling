#!/usr/bin/env python3
"""Decode South African licence-disc PDF417 barcodes from photos (offline).

Usage: python3 decode_discs.py photo1.jpeg [photo2.jpeg ...]
Requires: pip install zxing-cpp pillow
Tries several pre-processing variants (grayscale, contrast, sharpening, crops,
upscaling, binarisers) because compressed phone photos are often below the
~3 px/module a PDF417 decoder needs. Prints the raw payload and the parsed
fields using the same layout as sparkling_core / backend pdf417 parsers.
"""
import itertools
import sys

import zxingcpp
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

FIELDS = {5: 'licence_disc_no', 6: 'registration_no', 7: 'vehicle_register_no', 8: 'description',
          9: 'make', 10: 'model', 11: 'colour', 12: 'vin', 13: 'engine_no', 14: 'disc_expiry'}


def variants(img):
    g = ImageOps.grayscale(img)
    yield 'gray', g
    yield 'autocontrast', ImageOps.autocontrast(g, cutoff=1)
    yield 'unsharp', g.filter(ImageFilter.UnsharpMask(radius=3, percent=250, threshold=1))
    yield 'median+ac', ImageOps.autocontrast(g.filter(ImageFilter.MedianFilter(3)), cutoff=1)
    yield 'contrast4', ImageEnhance.Contrast(g).enhance(4.0)


def crops(im):
    w, h = im.size
    yield 'full', im
    yield 'center', im.crop((int(w * 0.15), int(h * 0.2), int(w * 0.85), int(h * 0.8)))
    yield 'wide', im.crop((int(w * 0.05), int(h * 0.15), int(w * 0.95), int(h * 0.85)))


def looks_like_disc(text):
    parts = text.split('%')
    return len(parts) >= 15 and parts[6].replace(' ', '').isalnum() and len(parts[14]) == 10


def decode(path):
    img = ImageOps.exif_transpose(Image.open(path))
    for (vname, v), scale in itertools.product(list(variants(img)), (1.0, 2.0, 3.0, 4.0, 5.0)):
        for cname, c in crops(v):
            im = c if scale == 1.0 else c.resize((int(c.width * scale), int(c.height * scale)), Image.LANCZOS)
            for binz in (zxingcpp.Binarizer.LocalAverage, zxingcpp.Binarizer.GlobalHistogram):
                for r in zxingcpp.read_barcodes(im, formats=zxingcpp.BarcodeFormat.PDF417, try_rotate=True,
                                                try_downscale=True, binarizer=binz):
                    if r.valid and looks_like_disc(r.text):
                        return f'{vname}/{cname} x{scale} {binz}', r.text
    return None, None


def main(paths):
    for p in paths:
        how, text = decode(p)
        print(f'=== {p}')
        if not text:
            print('  NOT DECODED (too blurry / low resolution / glare)')
            continue
        print(f'  decoded via {how}')
        print(f'  raw: {text!r}')
        parts = text.split('%')
        for i, name in FIELDS.items():
            print(f'  {name:>20}: {parts[i] if i < len(parts) else ""}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
