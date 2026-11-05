"""Write images as BLP2 textures with DXT1 compression and mipmaps (the format of the game's own map tiles).

Only what this addon needs: opaque images, sizes that are powers of two.
"""
import struct

import numpy as np
from PIL import Image


def _to565(c):
    c = np.clip(np.rint(c), 0, 255).astype(np.uint32)
    return ((c[..., 0] >> 3) << 11) | ((c[..., 1] >> 2) << 5) | (c[..., 2] >> 3)


def _from565(v):
    r = ((v >> 11) & 31) * 255.0 / 31
    g = ((v >> 5) & 63) * 255.0 / 63
    b = (v & 31) * 255.0 / 31
    return np.stack([r, g, b], axis=-1)


def dxt1(rgb):
    """rgb: HxWx3 uint8 array (H, W multiples of 4, or smaller than 4) -> DXT1 bytes."""
    h, w, _ = rgb.shape
    ph, pw = max(4, -(-h // 4) * 4), max(4, -(-w // 4) * 4)
    if (ph, pw) != (h, w):
        rgb = np.pad(rgb, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    by, bx = ph // 4, pw // 4
    blocks = rgb.reshape(by, 4, bx, 4, 3).transpose(0, 2, 1, 3, 4).reshape(by * bx, 16, 3).astype(np.float64)

    # Endpoints: the two pixels furthest apart along the block's main colour direction.
    mean = blocks.mean(axis=1, keepdims=True)
    centred = blocks - mean
    cov = np.einsum("bni,bnj->bij", centred, centred)
    axis = np.ones((len(blocks), 3))
    for _ in range(4):  # power iteration
        axis = np.einsum("bij,bj->bi", cov, axis)
        axis /= np.linalg.norm(axis, axis=1, keepdims=True) + 1e-9
    proj = np.einsum("bni,bi->bn", centred, axis)
    hi = blocks[np.arange(len(blocks)), proj.argmax(axis=1)]
    lo = blocks[np.arange(len(blocks)), proj.argmin(axis=1)]

    c0, c1 = _to565(hi), _to565(lo)
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    p0, p1 = _from565(c0), _from565(c1)
    palette = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)  # b x 4 x 3
    dist = ((blocks[:, :, None, :] - palette[:, None, :, :]) ** 2).sum(-1)  # b x 16 x 4
    idx = dist.argmin(axis=2).astype(np.uint32)
    idx[c0 == c1] = 0  # flat block: c0 == c1 means 3-colour mode; index 0 is safe
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(axis=1).astype(np.uint32)

    out = np.zeros(len(blocks), dtype=[("c0", "<u2"), ("c1", "<u2"), ("bits", "<u4")])
    out["c0"], out["c1"], out["bits"] = c0, c1, bits
    return out.tobytes()


def save_blp(image, path):
    image = image.convert("RGB")
    w, h = image.size
    assert w & (w - 1) == 0 and h & (h - 1) == 0, "BLP sizes must be powers of two"
    mips = []
    level = image
    while True:
        mips.append(dxt1(np.asarray(level)))
        if level.size == (1, 1) or len(mips) == 16:
            break
        level = level.resize((max(1, level.size[0] // 2), max(1, level.size[1] // 2)), Image.LANCZOS)

    header_size = 4 + 4 + 4 + 8 + 16 * 4 * 2 + 256 * 4
    offsets, sizes, pos = [], [], header_size
    for m in mips:
        offsets.append(pos)
        sizes.append(len(m))
        pos += len(m)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))

    with open(path, "wb") as f:
        f.write(b"BLP2")
        f.write(struct.pack("<I", 1))  # type: DirectX/uncompressed
        f.write(struct.pack("<BBBB", 2, 0, 0, 1))  # DXT, no alpha, DXT1, has mipmaps
        f.write(struct.pack("<II", w, h))
        f.write(struct.pack("<16I", *offsets))
        f.write(struct.pack("<16I", *sizes))
        f.write(b"\0" * 1024)  # palette (unused for DXT)
        for m in mips:
            f.write(m)
