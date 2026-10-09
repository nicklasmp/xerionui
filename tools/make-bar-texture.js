// Generates XerionUI/Media/bar-gloss.tga: a tintable grey statusbar texture
// (bright top edge, soft vertical gradient, darker bottom edge).
const fs = require("fs");
const path = require("path");
const W = 256, H = 32;
const buf = Buffer.alloc(18 + W * H * 4);
buf[2] = 2;
buf.writeUInt16LE(W, 12);
buf.writeUInt16LE(H, 14);
buf[16] = 32;
buf[17] = 0x28; // top-left origin, 8 alpha bits
for (let y = 0; y < H; y++) {
	let v = 1 - 0.3 * Math.pow(y / (H - 1), 0.9);
	if (y === 0) v = 1;
	else if (y === 1) v = Math.min(1, v + 0.06);
	if (y >= H - 2) v -= 0.14;
	const g = Math.max(0, Math.min(255, Math.round(v * 255)));
	for (let x = 0; x < W; x++) {
		const o = 18 + (y * W + x) * 4;
		buf[o] = buf[o + 1] = buf[o + 2] = g;
		buf[o + 3] = 255;
	}
}
fs.writeFileSync(path.join(__dirname, "..", "XerionUI", "Media", "bar-gloss.tga"), buf);
