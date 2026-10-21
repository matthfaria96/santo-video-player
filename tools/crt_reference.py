"""Software reference render of the filter_crt.c shader (numpy/Pillow).

This mirrors the GLSL in vlc/modules/video_output/opengl/filter_crt.c exactly,
so it can be used to (a) verify the algorithm produces a visible CRT effect and
(b) preview the result without building VLC. The scanline/mask math here is a
line-for-line port of the fragment shader's main() body.
"""
import numpy as np
from PIL import Image


def crt_apply(img, *, gamma_in=2.0, gamma_out=1.8, bright_boost=1.2,
              scanline_strength=0.7, scanline_period=2.0, scanline_beam=1.5,
              mask_strength=0.3, mask_size=1.0):
    """img: float32/float64 HxWx3 in [0,1]. Returns HxWx3 in [0,1]."""
    h, w, _ = img.shape
    col = np.asarray(img, dtype=np.float64)
    col = np.clip(col, 0.0, 1.0)

    # gamma input: work in linear space
    col = np.power(col, gamma_in)

    # horizontal scanlines (fixed pitch, screen space)
    y = np.arange(h, dtype=np.float64)  # gl_FragCoord.y
    scan = 1.0 - np.power(
        np.cos(y * 2.0 * np.pi / scanline_period) * 0.5 + 0.5,
        scanline_beam) * scanline_strength
    col = col * scan[:, None, None]

    # RGB aperture-grille mask (vertical stripes, R/G/B cycling)
    x = np.arange(w, dtype=np.float64)  # gl_FragCoord.x
    pitch = mask_size * 3.0
    m = np.mod(x, pitch)
    mask = 1.0 - mask_strength
    r = np.where(m < mask_size, 1.0, mask)
    g = np.where((m >= mask_size) & (m < 2.0 * mask_size), 1.0, mask)
    b = np.where(m >= 2.0 * mask_size, 1.0, mask)
    col = col * np.stack([r, g, b], axis=-1)[None, :, :]

    # gamma output + brightness boost
    col = np.power(col, 1.0 / gamma_out) * bright_boost
    return np.clip(col, 0.0, 1.0)


def make_test_image(w, h):
    """Bright rainbow gradient (hue sweeps horizontally) — shows both the
    scanlines (dark horizontal lines) and the RGB mask (vertical stripes)."""
    x = np.linspace(0.0, 1.0, w, dtype=np.float64)
    y = np.linspace(0.0, 1.0, h, dtype=np.float64)
    xx, yy = np.meshgrid(x, y)
    hue = xx * 6.0
    r = np.clip(np.abs(hue - 3.0) - 1.0, 0.0, 1.0)
    g = np.clip(2.0 - np.abs(hue - 2.0), 0.0, 1.0)
    b = np.clip(2.0 - np.abs(hue - 4.0), 0.0, 1.0)
    # add a bright horizontal band in the middle so scanlines are obvious
    band = (np.abs(yy - 0.5) < 0.15).astype(np.float64)
    img = np.stack([r, g, b], axis=-1)
    img = img * (1.0 - band)[:, :, None] + band[:, :, None] * 1.0
    return np.clip(img, 0.0, 1.0)


def save(img_01, path):
    Image.fromarray((np.clip(img_01, 0, 1) * 255).astype(np.uint8)).save(path)


if __name__ == "__main__":
    W, H = 640, 360
    src = make_test_image(W, H)
    save(src, "crt_before.png")

    after = crt_apply(src)  # default params = shader defaults
    save(after, "crt_after.png")

    # zoomed crop (center) so the mask/scanline detail is easy to see
    zoom = after[H // 2 - 40:H // 2 + 40, W // 2 - 80:W // 2 + 80, :]
    Image.fromarray((zoom * 255).astype(np.uint8)).resize(
        (zoom.shape[1] * 6, zoom.shape[0] * 6), Image.NEAREST).save(
        "crt_after_zoom.png")

    # a stronger mask + thicker scanlines variant
    strong = crt_apply(src, scanline_period=3.0, mask_strength=0.6,
                       mask_size=2.0)
    save(strong, "crt_after_strong.png")

    print("wrote crt_before.png, crt_after.png, crt_after_zoom.png, "
          "crt_after_strong.png")
