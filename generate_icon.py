#!/usr/bin/env python3
"""Generate AuthenticatorApp icon: blue rounded square + white lock."""
import zlib, struct, math, os, subprocess

def clamp(x): return max(0, min(255, int(round(x))))

def write_png(path, pixels, w, h):
    raw = b''
    for row in pixels:
        raw += b'\x00'
        for r, g, b, a in row:
            raw += bytes([clamp(r), clamp(g), clamp(b), clamp(a)])
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(raw, 6))
    iend = chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(sig + ihdr + idat + iend)

def in_rrect(px, py, x0, y0, x1, y1, r):
    if px < x0 or px > x1 or py < y0 or py > y1:
        return False
    if px < x0+r and py < y0+r: return math.hypot(px-(x0+r), py-(y0+r)) <= r
    if px > x1-r and py < y0+r: return math.hypot(px-(x1-r), py-(y0+r)) <= r
    if px < x0+r and py > y1-r: return math.hypot(px-(x0+r), py-(y1-r)) <= r
    if px > x1-r and py > y1-r: return math.hypot(px-(x1-r), py-(y1-r)) <= r
    return True

def make_icon(s):
    sc = s / 1024.0
    grid = [[(0,0,0,0)] * s for _ in range(s)]

    pad   = 0.05 * s
    bg_r  = 0.22 * s

    # Shackle (U-arc on top)
    shk_cx = 512 * sc
    shk_cy = 377 * sc
    shk_or = 160 * sc   # outer radius
    shk_ir = 98  * sc   # inner radius

    # Arms (straight vertical bars)
    arm_lx0 = shk_cx - shk_or;  arm_lx1 = shk_cx - shk_ir
    arm_rx0 = shk_cx + shk_ir;  arm_rx1 = shk_cx + shk_or
    arm_y0  = shk_cy;            arm_y1  = 504 * sc

    # Body
    bx0 = 302 * sc;  by0 = 504 * sc
    bx1 = 722 * sc;  by1 = 807 * sc
    br  = 50  * sc

    # Keyhole
    kh_cx = 512 * sc;  kh_cy = 625 * sc
    kh_r  = 50  * sc
    ks_w  = 34  * sc;  ks_h  = 76 * sc

    for row in range(s):
        for col in range(s):
            px = col + 0.5
            py = row + 0.5

            if not in_rrect(px, py, pad, pad, s-pad, s-pad, bg_r):
                continue

            t = row / s
            # Gradient: top #3B82F6 → bottom #1E3A8A
            bg = (clamp(59  + (30 -59 )*t),
                  clamp(130 + (58 -130)*t),
                  clamp(246 + (138-246)*t),
                  255)

            # Shackle arc (top half of ring)
            d = math.hypot(px - shk_cx, py - shk_cy)
            in_arc = shk_ir <= d <= shk_or and py <= shk_cy + 0.5

            in_larm = arm_lx0 <= px <= arm_lx1 and arm_y0 <= py <= arm_y1
            in_rarm = arm_rx0 <= px <= arm_rx1 and arm_y0 <= py <= arm_y1
            in_body = in_rrect(px, py, bx0, by0, bx1, by1, br)

            d_kh = math.hypot(px - kh_cx, py - kh_cy)
            in_kh = d_kh <= kh_r or (abs(px - kh_cx) <= ks_w/2 and kh_cy <= py <= kh_cy + ks_h)

            if (in_arc or in_larm or in_rarm or in_body) and not in_kh:
                grid[row][col] = (255, 255, 255, 255)
            else:
                grid[row][col] = bg

    return grid

dest = "AuthenticatorApp/Assets.xcassets/AppIcon.appiconset"
os.makedirs(dest, exist_ok=True)

print("Rendering 1024x1024 master icon…")
master = "icon_master_1024.png"
write_png(master, make_icon(1024), 1024, 1024)
print("Done.")

sizes = [1024, 512, 256, 128, 64, 32, 16]
for sz in sizes:
    out = os.path.join(dest, f"icon_{sz}x{sz}.png")
    if sz == 1024:
        subprocess.run(["cp", master, out], check=True)
    else:
        subprocess.run(["sips", "-z", str(sz), str(sz), master, "--out", out],
                       check=True, capture_output=True)
    print(f"  wrote {out}")

os.remove(master)
print("Icon generation complete.")
