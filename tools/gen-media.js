// Generates XerionUI's small UI textures as 32-bit uncompressed TGA files.
// White shapes with anti-aliased alpha; the addon tints them at runtime.
//   node tools/gen-media.js
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', 'XerionUI', 'Media');
fs.mkdirSync(OUT, { recursive: true });

function canvas(size) {
  return { size, a: new Float32Array(size * size), rgb: null };
}

// Signed-distance helpers (pixel units). Coverage = clamp(0.5 - d, 0, 1).
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
function segDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1);
  const x = ax + t * dx - px, y = ay + t * dy - py;
  return Math.sqrt(x * x + y * y);
}

// Draws with 4x4 supersampling: fn(x, y) returns true when the sample is inside.
function fill(c, inside) {
  const S = 4;
  for (let y = 0; y < c.size; y++) {
    for (let x = 0; x < c.size; x++) {
      let hit = 0;
      for (let sy = 0; sy < S; sy++) for (let sx = 0; sx < S; sx++) {
        if (inside(x + (sx + 0.5) / S, y + (sy + 0.5) / S)) hit++;
      }
      const v = hit / (S * S);
      const i = y * c.size + x;
      c.a[i] = Math.max(c.a[i], v);
    }
  }
}

function cut(c, inside) {
  const S = 4;
  for (let y = 0; y < c.size; y++) {
    for (let x = 0; x < c.size; x++) {
      let hit = 0;
      for (let sy = 0; sy < S; sy++) for (let sx = 0; sx < S; sx++) {
        if (inside(x + (sx + 0.5) / S, y + (sy + 0.5) / S)) hit++;
      }
      const i = y * c.size + x;
      c.a[i] = Math.min(c.a[i], 1 - hit / (S * S));
    }
  }
}

const line = (ax, ay, bx, by, w) => (x, y) => segDist(x, y, ax, ay, bx, by) <= w / 2;
const disc = (cx, cy, r) => (x, y) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
const ring = (cx, cy, r, w) => (x, y) => Math.abs(Math.hypot(x - cx, y - cy) - r) <= w / 2;
function tri(ax, ay, bx, by, cx, cy) {
  const s = (px, py, qx, qy, rx, ry) => (px - rx) * (qy - ry) - (qx - rx) * (py - ry);
  return (x, y) => {
    const d1 = s(x, y, ax, ay, bx, by), d2 = s(x, y, bx, by, cx, cy), d3 = s(x, y, cx, cy, ax, ay);
    const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(neg && pos);
  };
}
function roundRect(x0, y0, x1, y1, r) {
  return (x, y) => {
    const cx = clamp(x, x0 + r, x1 - r), cy = clamp(y, y0 + r, y1 - r);
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r && x >= x0 && x <= x1 && y >= y0 && y <= y1;
  };
}

function writeTGA(name, c, color) {
  const n = c.size;
  const header = Buffer.alloc(18);
  header[2] = 2;               // uncompressed true-colour
  header.writeUInt16LE(n, 12);
  header.writeUInt16LE(n, 14);
  header[16] = 32;             // bits per pixel
  header[17] = 0x28;           // top-left origin, 8 alpha bits
  const px = Buffer.alloc(n * n * 4);
  for (let i = 0; i < n * n; i++) {
    let r = 255, g = 255, b = 255;
    if (c.rgb) [r, g, b] = c.rgb(i % n, Math.floor(i / n));
    else if (color) [r, g, b] = color;
    px[i * 4] = b; px[i * 4 + 1] = g; px[i * 4 + 2] = r;
    px[i * 4 + 3] = Math.round(clamp(c.a[i], 0, 1) * 255);
  }
  fs.writeFileSync(path.join(OUT, name + '.tga'), Buffer.concat([header, px]));
  console.log('wrote', name + '.tga');
}

// circle: knobs, switch caps, status dots
{ const c = canvas(64); fill(c, disc(32, 32, 31)); writeTGA('circle', c); }

// chevron (pointing down)
{ const c = canvas(32); fill(c, line(9, 12.5, 16, 19.5, 3)); fill(c, line(16, 19.5, 23, 12.5, 3)); writeTGA('chevron', c); }

// close
{ const c = canvas(32); fill(c, line(9, 9, 23, 23, 2.6)); fill(c, line(23, 9, 9, 23, 2.6)); writeTGA('close', c); }

// move: a cross with four arrow heads
{
  const c = canvas(32);
  fill(c, line(16, 5, 16, 27, 2.4)); fill(c, line(5, 16, 27, 16, 2.4));
  fill(c, tri(16, 2.5, 11.5, 8, 20.5, 8)); fill(c, tri(16, 29.5, 11.5, 24, 20.5, 24));
  fill(c, tri(2.5, 16, 8, 11.5, 8, 20.5)); fill(c, tri(29.5, 16, 24, 11.5, 24, 20.5));
  writeTGA('move', c);
}

// search: magnifier
{ const c = canvas(32); fill(c, ring(13.5, 13.5, 7.5, 2.6)); fill(c, line(19, 19, 26, 26, 3)); writeTGA('search', c); }

// reset: circular arrow
{
  const c = canvas(32);
  fill(c, (x, y) => {
    const d = Math.hypot(x - 16, y - 16);
    if (Math.abs(d - 9) > 1.3) return false;
    const ang = Math.atan2(y - 16, x - 16); // -pi..pi, 0 = right, y down
    return !(ang > -Math.PI / 2 && ang < -0.15); // gap in the upper right
  });
  fill(c, tri(16, 2.5, 16, 11.5, 22, 7));
  writeTGA('reset', c);
}

// play
{ const c = canvas(32); fill(c, tri(11, 8, 11, 24, 24, 16)); writeTGA('play', c); }

// eye (preview)
{
  const c = canvas(32);
  fill(c, (x, y) => {
    const dx = (x - 16) / 13, dy = (y - 16) / 7.5;
    const d = Math.sqrt(dx * dx + dy * dy);
    return d <= 1 && d >= 0.78;
  });
  fill(c, disc(16, 16, 4.2));
  writeTGA('eye', c);
}

// check
{ const c = canvas(32); fill(c, line(8, 16.5, 13.5, 22, 3)); fill(c, line(13.5, 22, 24, 10, 3)); writeTGA('check', c); }

// logo: dark rounded square with an orange X
{
  const c = canvas(64);
  fill(c, roundRect(2, 2, 62, 62, 12));
  const xMask = canvas(64);
  fill(xMask, line(19, 18, 45, 46, 8)); fill(xMask, line(45, 18, 19, 46, 8));
  c.rgb = (x, y) => {
    const a = xMask.a[y * 64 + x];
    const bg = [20, 20, 20], fg = [255, 125, 10];
    return bg.map((v, i) => Math.round(v + (fg[i] - v) * a));
  };
  writeTGA('logo', c);
}

// drop (global style)
{
  const c = canvas(32);
  fill(c, disc(16, 19.5, 7.5));
  fill(c, tri(16, 4, 9.3, 16.5, 22.7, 16.5));
  writeTGA('drop', c);
}

// sliders (general settings)
{
  const c = canvas(32);
  for (const [y, k] of [[9, 20], [16, 11], [23, 17]]) {
    fill(c, line(5, y, 27, y, 2));
    fill(c, disc(k, y, 3.6));
  }
  writeTGA('sliders', c);
}

// layers (profiles)
{
  const c = canvas(32);
  const diamond = (cy) => (x, y) => Math.abs(x - 16) / 11 + Math.abs(y - cy) / 5.5 <= 1;
  const outline = (cy) => (x, y) => { const d = Math.abs(x - 16) / 11 + Math.abs(y - cy) / 5.5; return d <= 1 && d >= 0.8; };
  fill(c, outline(21.5));
  fill(c, outline(16));
  cut(c, diamond(10.5));
  fill(c, diamond(10.5));
  writeTGA('layers', c);
}
