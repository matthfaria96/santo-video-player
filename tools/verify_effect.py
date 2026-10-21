"""Objective verification that crt_apply() actually produces a CRT effect.

Applies the ported shader math to a constant white image and checks:
  1. scanlines: alternating dark/bright rows (period = crt_scanline_period)
  2. RGB mask : columns cycle R-dominant / G-dominant / B-dominant
"""
import numpy as np
from crt_reference import crt_apply

W, H = 120, 60
white = np.ones((H, W, 3), dtype=np.float64)

out = crt_apply(white)  # defaults: period=2, mask_size=1, strength=1, mask=0.3

# --- scanlines ---
lum = 0.2126 * out[..., 0] + 0.7152 * out[..., 1] + 0.0722 * out[..., 2]
row = lum.mean(axis=1)
even, odd = row[0::2].mean(), row[1::2].mean()
print(f"scanline: even-row mean={even:.4f} odd-row mean={odd:.4f} "
      f"diff={abs(even-odd):.4f}")
scan_ok = abs(even - odd) > 0.1

# --- RGB mask ---
r = out[..., 0].mean(axis=0)
g = out[..., 1].mean(axis=0)
b = out[..., 2].mean(axis=0)
# mean channel value in each of the 3 column phases
phases = {}
for ph in (0, 1, 2):
    idx = np.arange(W) % 3 == ph
    phases[ph] = (r[idx].mean(), g[idx].mean(), b[idx].mean())
    print(f"mask phase x%3=={ph}: R={phases[ph][0]:.4f} "
          f"G={phases[ph][1]:.4f} B={phases[ph][2]:.4f}")

# R should dominate in phase 0, G in phase 1, B in phase 2
mask_ok = (phases[0][0] > phases[0][1] and phases[0][0] > phases[0][2] and
           phases[1][1] > phases[1][0] and phases[1][1] > phases[1][2] and
           phases[2][2] > phases[2][0] and phases[2][2] > phases[2][1])

print()
print("scanline present:", "PASS" if scan_ok else "FAIL")
print("RGB mask present :", "PASS" if mask_ok else "FAIL")
print("RESULT:", "PASS" if (scan_ok and mask_ok) else "FAIL")
