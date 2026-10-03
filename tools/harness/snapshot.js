// Turns MOCK.Snapshot() draw ops into an HTML page (one absolutely positioned
// element per texture / text), so the options window can be looked at
// without the game. Generated media are tinted with CSS masks.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(__dirname, 'out');
const mediaCache = {};

function crc32(buf) {
  let c, t = [];
  for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  let r = 0xffffffff; for (const x of buf) r = t[(r ^ x) & 255] ^ (r >>> 8); return (r ^ 0xffffffff) >>> 0;
}
function png(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, c]);
  };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
function mediaURI(texPath) {
  if (mediaCache[texPath] !== undefined) return mediaCache[texPath];
  const m = texPath.match(/AddOns[\\/]XerionUI[\\/]Media[\\/](\w+)/i);
  let uri = null;
  if (m) {
    const f = path.join(ROOT, 'XerionUI', 'Media', m[1] + '.tga');
    if (fs.existsSync(f)) {
      const b = fs.readFileSync(f); const n = b.readUInt16LE(12);
      const rgba = Buffer.alloc(n * n * 4);
      for (let i = 0; i < n * n; i++) { rgba[i * 4] = b[18 + i * 4 + 2]; rgba[i * 4 + 1] = b[18 + i * 4 + 1]; rgba[i * 4 + 2] = b[18 + i * 4]; rgba[i * 4 + 3] = b[18 + i * 4 + 3]; }
      uri = 'data:image/png;base64,' + png(n, n, rgba).toString('base64');
    }
  }
  mediaCache[texPath] = uri;
  return uri;
}
const css = (c, a) => { c = c || [1, 1, 1, 1]; return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] * a).toFixed(3)})`; };
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
function wowText(s) {
  // |cAARRGGBB ... |r colour codes
  let out = '', open = false;
  const re = /\|c([0-9a-fA-F]{8})|\|r|\|T[^|]*\|t/g; let last = 0, m;
  while ((m = re.exec(s))) {
    out += esc(s.slice(last, m.index));
    if (m[0].startsWith('|c')) { if (open) out += '</span>'; out += `<span style="color:#${m[1].slice(2)}">`; open = true; }
    else if (m[0] === '|r') { if (open) out += '</span>'; open = false; }
    last = re.lastIndex;
  }
  out += esc(s.slice(last)); if (open) out += '</span>';
  return out.replace(/\n/g, '<br>');
}

module.exports = function emit(name, json, W, H, crop) {
  fs.mkdirSync(OUT, { recursive: true });
  const ops = JSON.parse(json);
  const S = 1;
  const [cl, cb, cr, ct] = crop || [0, 0, W, H];
  const VW = cr - cl, VH = ct - cb;
  let html = `<!doctype html><meta charset="utf-8"><title>${name}</title><style>
body{margin:0;background:#2a2f36}#v{position:relative;width:${VW * S}px;height:${VH * S}px;overflow:hidden;
background:radial-gradient(circle at 30% 20%,#4b5563,#1f2328)}#v div{position:absolute;box-sizing:border-box}
.t{white-space:pre;overflow:visible;line-height:1.15;display:flex;align-items:center}
</style><div id="v">`;
  for (const op of ops) {
    const [l, b, r, t] = op.r;
    const pos = `left:${((l - cl) * S).toFixed(1)}px;top:${((ct - t) * S).toFixed(1)}px;width:${((r - l) * S).toFixed(1)}px;height:${((t - b) * S).toFixed(1)}px;`;
    if (op.t === 'text') {
      const just = op.justify === 'LEFT' ? 'flex-start' : op.justify === 'RIGHT' ? 'flex-end' : 'center';
      const fam = /ARIALN/i.test(op.font) ? "'Arial Narrow',Arial" : /Gotham/i.test(op.font) ? "'Gotham Narrow','Arial Black'" : 'Arial';
      html += `<div class="t" style="${pos}justify-content:${just};font:${(op.size * S).toFixed(1)}px ${fam};color:${css(op.color, op.a)}">${wowText(op.text)}</div>`;
    } else if (op.t === 'outline') {
      html += `<div style="${pos}border:1px solid ${css(op.color, op.a)}"></div>`;
    } else {
      const uri = mediaURI(op.tex);
      if (uri) {
        html += `<div style="${pos}background:${css(op.color, op.a)};-webkit-mask:url(${uri}) center/100% 100% no-repeat;mask:url(${uri}) center/100% 100% no-repeat"></div>`;
      } else if (/^\d+$/.test(op.tex)) {
        html += `<div style="${pos}background:linear-gradient(135deg,#8a6d3b,#3b2f1e);opacity:${op.a};${op.desat ? 'filter:grayscale(1)' : ''}"></div>`;
      } else {
        html += `<div style="${pos}background:${css(op.color, op.a)}"></div>`;
      }
    }
  }
  html += '</div>';
  const file = path.join(OUT, name + '.html');
  fs.writeFileSync(file, html);
  return file;
};
