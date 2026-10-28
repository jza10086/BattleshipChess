#!/usr/bin/env python3
"""Original deterministic, seamless water data texture. Python 3 + Pillow only.
No photographs, downloaded artwork or third-party shader code. Project MIT.
R: broad current fields, G: medium breakup, B: small ripple variation.
"""
from pathlib import Path
from random import Random
from PIL import Image

SIZE = 256
rng = Random(41027)

def layer(cells):
    lattice = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    values = []
    for y in range(SIZE):
        gy = y * cells / SIZE
        iy, fy = int(gy), gy % 1
        fy = fy * fy * (3 - 2 * fy)
        for x in range(SIZE):
            gx = x * cells / SIZE
            ix, fx = int(gx), gx % 1
            fx = fx * fx * (3 - 2 * fx)
            a = lattice[iy][ix] * (1 - fx) + lattice[iy][(ix + 1) % cells] * fx
            b = lattice[(iy + 1) % cells][ix] * (1 - fx) + lattice[(iy + 1) % cells][(ix + 1) % cells] * fx
            values.append(round((a * (1 - fy) + b * fy) * 255))
    return values

channels = [layer(c) for c in (5, 13, 29)]
image = Image.new('RGB', (SIZE, SIZE))
image.putdata(list(zip(*channels)))
path = Path(__file__).resolve().parents[1] / 'assets/textures/ocean_fields.png'
image.save(path)
print(path)
