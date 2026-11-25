# Tạo ảnh mẫu PNG không cần thư viện ngoài: 3 ảnh trùng, 2 ảnh giống nhau (chụp liên tiếp), 1 ảnh khác
import os, random, struct, zlib

def png(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixel(x, y))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)

os.makedirs("samples", exist_ok=True)
W, H = 480, 360
grad = lambda x, y: (int(13 + 28 * x / W), int(166 - 51 * x / W), int(158 + 87 * y / H))
png("samples/a1.png", W, H, grad)
for n in ("a2", "a3"):
    open(f"samples/{n}.png", "wb").write(open("samples/a1.png", "rb").read())
# Hai ảnh gần giống: cùng bố cục, lệch nhẹ độ sáng
def scene(shift):
    return lambda x, y: (min(255, (x * 255 // W) + shift), (y * 255 // H), 120) if (x - 240) ** 2 + (y - 180) ** 2 > 90 ** 2 else (250, 200, 40)
png("samples/s1.png", W, H, scene(0))
png("samples/s2.png", W, H, scene(6))
random.seed(7)
png("samples/n1.png", 360, 480, lambda x, y: (random.randrange(256), random.randrange(256), random.randrange(256)))
print(sorted(os.listdir("samples")))
