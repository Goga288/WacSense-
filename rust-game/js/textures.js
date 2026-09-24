// Процедурные текстуры: рисуются на canvas при загрузке, внешних файлов нет.
import * as THREE from './three.module.min.js';
import { mulberry32 } from './util.js';

let SIZE = 512;
let ANISO = 4;
export function setTexQuality(size, aniso) {
  SIZE = size;
  ANISO = aniso;
}

// ---------- шум ----------
// Бесшовный фрактальный value-noise, значения 0..1.
export function tileNoise(size, cells, seed, oct = 5, pers = 0.5, sx = 1, sy = 1) {
  const out = new Float32Array(size * size);
  let amp = 1, tot = 0;
  for (let o = 0; o < oct; o++) {
    const cx = Math.max(1, Math.round(cells * sx)) << o;
    const cy = Math.max(1, Math.round(cells * sy)) << o;
    if (cx > size || cy > size) break;
    const r = mulberry32(seed * 7919 + o * 104729);
    const lat = new Float32Array(cx * cy);
    for (let i = 0; i < lat.length; i++) lat[i] = r();
    for (let y = 0; y < size; y++) {
      const fy = (y / size) * cy, y0 = Math.floor(fy), ty = fy - y0, ky = ty * ty * (3 - 2 * ty);
      const r0 = y0 * cx, r1 = ((y0 + 1) % cy) * cx;
      for (let x = 0; x < size; x++) {
        const fx = (x / size) * cx, x0 = Math.floor(fx), tx = fx - x0, kx = tx * tx * (3 - 2 * tx);
        const x1 = (x0 + 1) % cx;
        const a = lat[r0 + x0], b = lat[r0 + x1], c = lat[r1 + x0], d = lat[r1 + x1];
        const top = a + (b - a) * kx, bot = c + (d - c) * kx;
        out[y * size + x] += amp * (top + (bot - top) * ky);
      }
    }
    tot += amp;
    amp *= pers;
  }
  for (let i = 0; i < out.length; i++) out[i] /= tot;
  return out;
}

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const sstep = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const mixc = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

function canvas(w, h = w) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

function toTex(cv, srgb = true, repeat = true) {
  const t = new THREE.CanvasTexture(cv);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = ANISO;
  return t;
}

// Заливка по функции цвета (r,g,b[,a]) для каждого пикселя.
function paint(size, fn, h = size) {
  const cv = canvas(size, h);
  const ctx = cv.getContext('2d');
  const img = ctx.createImageData(size, h);
  const d = img.data;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < size; x++) {
      const i = y * size + x;
      const c = fn(x, y, i);
      d[i * 4] = c[0];
      d[i * 4 + 1] = c[1];
      d[i * 4 + 2] = c[2];
      d[i * 4 + 3] = c.length > 3 ? c[3] : 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return cv;
}

// Карта нормалей из карты высот.
function normalMap(h, size, strength) {
  const cv = paint(size, (x, y) => {
    const l = h[y * size + ((x - 1 + size) % size)], r = h[y * size + ((x + 1) % size)];
    const u = h[((y - 1 + size) % size) * size + x], d = h[((y + 1) % size) * size + x];
    let nx = (l - r) * strength, ny = (d - u) * strength, nz = 1;
    const len = Math.hypot(nx, ny, nz);
    nx /= len; ny /= len; nz /= len;
    return [(nx * 0.5 + 0.5) * 255, (ny * 0.5 + 0.5) * 255, (nz * 0.5 + 0.5) * 255];
  });
  return toTex(cv, false);
}

// ---------- ландшафт ----------
function grassTex() {
  const s = SIZE;
  const n1 = tileNoise(s, 4, 11, 5, 0.55), n2 = tileNoise(s, 48, 12, 2, 0.5), n3 = tileNoise(s, 2, 13, 3, 0.5);
  const cv = paint(s, (x, y, i) => {
    let c = mixc([52, 82, 26], [96, 132, 46], n1[i]);
    c = mixc(c, [126, 124, 58], sstep(0.58, 0.76, n3[i]) * 0.4);
    const f = (n2[i] - 0.5) * 50;
    return [c[0] + f, c[1] + f, c[2] + f * 0.6];
  });
  const ctx = cv.getContext('2d');
  const r = mulberry32(5);
  for (let i = 0; i < s * 6; i++) {
    const x = r() * s, y = r() * s, a = r() * Math.PI * 2, l = 3 + r() * 7;
    const g = 70 + r() * 70;
    ctx.strokeStyle = `rgba(${g * 0.75},${g},${g * 0.4},${0.25 + r() * 0.3})`;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l);
    ctx.stroke();
  }
  return toTex(cv);
}

function dirtTex() {
  const s = SIZE;
  const n1 = tileNoise(s, 6, 21, 5, 0.55), n2 = tileNoise(s, 64, 22, 2, 0.5);
  const cv = paint(s, (x, y, i) => {
    const c = mixc([86, 62, 38], [132, 100, 64], n1[i]);
    const f = (n2[i] - 0.5) * 40;
    return [c[0] + f, c[1] + f, c[2] + f];
  });
  const ctx = cv.getContext('2d');
  const r = mulberry32(7);
  for (let i = 0; i < s * 0.8; i++) {
    const x = r() * s, y = r() * s, rad = 1 + r() * 3.5;
    const g = 80 + r() * 70;
    ctx.fillStyle = `rgba(${g},${g * 0.92},${g * 0.82},0.8)`;
    ctx.beginPath();
    ctx.ellipse(x, y, rad, rad * (0.6 + r() * 0.4), r() * 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = 'rgba(30,22,14,0.35)';
    ctx.beginPath();
    ctx.ellipse(x + 1, y + 1, rad, rad * 0.6, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  return toTex(cv);
}

let rockHeight = null;
function rockTex() {
  const s = SIZE;
  const n1 = tileNoise(s, 4, 31, 6, 0.55), n2 = tileNoise(s, 8, 32, 4, 0.5), n3 = tileNoise(s, 3, 33, 3, 0.5);
  const h = new Float32Array(s * s);
  const cv = paint(s, (x, y, i) => {
    const crack = Math.pow(1 - Math.abs(n2[i] * 2 - 1), 16);
    h[i] = n1[i] * 0.8 - crack * 0.35;
    let c = mixc([92, 86, 78], [152, 144, 132], n1[i]);
    c = mixc(c, [52, 48, 42], crack * 0.45);
    c = mixc(c, [116, 118, 84], sstep(0.62, 0.75, n3[i]) * 0.35);
    return c;
  });
  rockHeight = h;
  return toTex(cv);
}

function sandTex() {
  const s = SIZE;
  const n1 = tileNoise(s, 5, 41, 4, 0.5), n2 = tileNoise(s, 96, 42, 1, 0.5);
  const cv = paint(s, (x, y, i) => {
    const rip = Math.sin((y / s) * Math.PI * 2 * 18 + n1[i] * 10) * 6;
    const c = mixc([178, 160, 120], [212, 196, 156], n1[i]);
    const f = (n2[i] - 0.5) * 30 + rip;
    return [c[0] + f, c[1] + f, c[2] + f];
  });
  return toTex(cv);
}

function detailTex() {
  const s = 256;
  const n = tileNoise(s, 4, 51, 5, 0.6);
  return toTex(paint(s, (x, y, i) => { const v = n[i] * 255; return [v, v, v]; }), false);
}

// ---------- растительность ----------
function barkTex(birch = false) {
  const s = SIZE / 2;
  const n1 = tileNoise(s, 4, birch ? 61 : 62, 5, 0.55, 3, 0.4), n2 = tileNoise(s, 16, 63, 3, 0.5, 2, 0.25);
  const h = new Float32Array(s * s);
  const cv = paint(s, (x, y, i) => {
    const groove = Math.pow(n2[i], 3);
    h[i] = n1[i] - groove;
    if (birch) {
      const mark = sstep(0.62, 0.7, n1[i]) * sstep(0.3, 0.6, n2[i]);
      return mixc(mixc([204, 200, 190], [232, 228, 218], n2[i]), [36, 32, 28], mark);
    }
    return mixc(mixc([62, 48, 36], [112, 92, 72], n1[i]), [28, 20, 14], groove * 0.8);
  });
  return { map: toTex(cv), normal: normalMap(h, s, 4) };
}

// Ветка ели: хвоя по обе стороны, прозрачный фон. Ветка идёт слева направо.
function needleTex() {
  const s = 256;
  const cv = canvas(s);
  const ctx = cv.getContext('2d');
  const r = mulberry32(71);
  const greens = [[40, 58, 30], [50, 70, 36], [62, 82, 42], [36, 52, 28], [74, 92, 50]];
  const branch = (x0, y0, x1, y1, w, depth) => {
    ctx.strokeStyle = 'rgb(60,44,30)';
    ctx.lineWidth = w;
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();
    const len = Math.hypot(x1 - x0, y1 - y0), a = Math.atan2(y1 - y0, x1 - x0);
    for (let t = 0; t < len; t += 2.2) {
      const px = x0 + Math.cos(a) * t, py = y0 + Math.sin(a) * t;
      const nl = (10 + r() * 7) * (1 - (t / len) * 0.45) * (depth ? 0.75 : 1);
      for (const side of [-1, 1]) {
        const na = a + side * (0.9 + r() * 0.35);
        const g = greens[Math.floor(r() * greens.length)];
        ctx.strokeStyle = `rgb(${g[0]},${g[1]},${g[2]})`;
        ctx.lineWidth = 2.6;
        ctx.beginPath();
        ctx.moveTo(px, py);
        ctx.lineTo(px + Math.cos(na) * nl, py + Math.sin(na) * nl);
        ctx.stroke();
      }
    }
    if (depth < 2) {
      for (let t = depth ? 12 : 26; t < len - 14; t += (depth ? 16 : 20) + r() * 8) {
        const px = x0 + Math.cos(a) * t, py = y0 + Math.sin(a) * t;
        for (const side of [-1, 1]) {
          const sa = a + side * (0.55 + r() * 0.3);
          const sl = (len - t) * (0.35 + r() * 0.2);
          branch(px, py, px + Math.cos(sa) * sl, py + Math.sin(sa) * sl, w * 0.6, depth + 1);
        }
      }
    }
  };
  branch(2, s / 2, s - 6, s / 2 + 4, 3, 0);
  const t = toTex(cv, true, false);
  return t;
}

function leafTex() {
  const s = 256;
  const cv = canvas(s);
  const ctx = cv.getContext('2d');
  const r = mulberry32(81);
  ctx.strokeStyle = 'rgb(70,54,38)';
  ctx.lineWidth = 2;
  for (let i = 0; i < 7; i++) {
    ctx.beginPath();
    ctx.moveTo(s / 2, s / 2);
    const a = (i / 7) * Math.PI * 2;
    ctx.lineTo(s / 2 + Math.cos(a) * s * 0.4, s / 2 + Math.sin(a) * s * 0.4);
    ctx.stroke();
  }
  for (let i = 0; i < 170; i++) {
    const a = r() * Math.PI * 2, d = Math.sqrt(r()) * s * 0.44;
    const x = s / 2 + Math.cos(a) * d, y = s / 2 + Math.sin(a) * d;
    const g = 60 + r() * 60;
    ctx.fillStyle = `rgb(${g * 0.62},${g},${g * 0.36})`;
    ctx.beginPath();
    ctx.ellipse(x, y, 7 + r() * 5, 3.5 + r() * 2.5, r() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  return toTex(cv, true, false);
}

function grassBladeTex() {
  const w = 128, h = 256;
  const cv = canvas(w, h);
  const ctx = cv.getContext('2d');
  const r = mulberry32(91);
  for (let i = 0; i < 34; i++) {
    const x = 8 + r() * (w - 16), top = h * (0.05 + r() * 0.45), bend = (r() - 0.5) * 40, bw = 2 + r() * 3;
    const g = ctx.createLinearGradient(0, h, 0, top);
    const dry = r() < 0.25;
    g.addColorStop(0, 'rgb(62,76,34)');
    g.addColorStop(1, dry ? 'rgb(168,156,92)' : `rgb(${104 + r() * 34},${128 + r() * 30},${56 + r() * 18})`);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(x - bw, h);
    ctx.quadraticCurveTo(x - bw * 0.5 + bend * 0.3, (h + top) / 2, x + bend, top);
    ctx.quadraticCurveTo(x + bw * 0.5 + bend * 0.3, (h + top) / 2, x + bw, h);
    ctx.fill();
  }
  const t = toTex(cv, true, false);
  return t;
}

function hempLeafTex() {
  const s = 256;
  const cv = canvas(s);
  const ctx = cv.getContext('2d');
  const r = mulberry32(95);
  const cx = s / 2, cy = s * 0.85;
  for (let i = 0; i < 7; i++) {
    const a = -Math.PI / 2 + (i - 3) * 0.38;
    const len = s * (0.72 - Math.abs(i - 3) * 0.12);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(a);
    const g = 90 + r() * 30;
    ctx.fillStyle = `rgb(${g * 0.55},${g},${g * 0.38})`;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    // зубчатый лист
    const steps = 14;
    for (let k = 0; k <= steps; k++) {
      const t = k / steps, wdt = Math.sin(t * Math.PI) * len * 0.11 * (k % 2 ? 1 : 0.8);
      ctx.lineTo(t * len, -wdt);
    }
    for (let k = steps; k >= 0; k--) {
      const t = k / steps, wdt = Math.sin(t * Math.PI) * len * 0.11 * (k % 2 ? 1 : 0.8);
      ctx.lineTo(t * len, wdt);
    }
    ctx.fill();
    ctx.strokeStyle = 'rgba(40,60,26,0.8)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(len, 0);
    ctx.stroke();
    ctx.restore();
  }
  return toTex(cv, true, false);
}

// ---------- постройки ----------
function planksTex() {
  const s = SIZE;
  const grain = tileNoise(s, 3, 101, 5, 0.55, 0.5, 6);
  const h = new Float32Array(s * s);
  const planks = 6, pw = s / planks;
  const shades = [];
  const r = mulberry32(102);
  for (let i = 0; i < planks; i++) shades.push(0.82 + r() * 0.3);
  const cv = paint(s, (x, y, i) => {
    const p = Math.floor(x / pw), px = x - p * pw;
    const gap = px < 3 || px > pw - 3;
    const beam = (y > s * 0.12 && y < s * 0.22) || (y > s * 0.78 && y < s * 0.88);
    const g = grain[(i + p * 97) % (s * s)];
    let c = mixc([92, 64, 40], [140, 104, 68], g);
    const sh = beam ? 0.78 : shades[p];
    c = [c[0] * sh, c[1] * sh, c[2] * sh];
    const edge = beam && (Math.abs(y - s * 0.12) < 3 || Math.abs(y - s * 0.22) < 3 || Math.abs(y - s * 0.78) < 3 || Math.abs(y - s * 0.88) < 3);
    h[i] = gap ? 0 : beam ? 1 : 0.6 + g * 0.2;
    if (gap && !beam) return [26, 18, 12];
    if (edge) return [c[0] * 0.55, c[1] * 0.55, c[2] * 0.55];
    return c;
  });
  const ctx = cv.getContext('2d');
  ctx.fillStyle = 'rgb(40,38,36)';
  for (let p = 0; p < planks; p++) {
    for (const yy of [s * 0.17, s * 0.83]) {
      ctx.beginPath();
      ctx.arc(p * pw + pw / 2, yy, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  return { map: toTex(cv), normal: normalMap(h, s, 2.5) };
}

function twigTex() {
  const s = SIZE;
  const cv = canvas(s);
  const ctx = cv.getContext('2d');
  const r = mulberry32(111);
  const stick = (x0, y0, x1, y1, w) => {
    ctx.lineCap = 'round';
    ctx.strokeStyle = 'rgb(58,42,26)';
    ctx.lineWidth = w + 2;
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    const g = 110 + r() * 40;
    ctx.strokeStyle = `rgb(${g},${g * 0.78},${g * 0.52})`;
    ctx.lineWidth = w;
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
  };
  for (let i = 0; i < 26; i++) {
    const a = r() < 0.5 ? 0.7 : -0.7;
    const x = r() * s * 1.4 - s * 0.2;
    stick(x, -10, x + Math.tan(a) * s, s + 10, 5 + r() * 5);
  }
  for (let i = 0; i < 6; i++) {
    const y = (i + 0.5) * (s / 6) + (r() - 0.5) * 20;
    stick(-10, y, s + 10, y + (r() - 0.5) * 30, 6 + r() * 4);
  }
  stick(4, 0, 4, s, 12); stick(s - 4, 0, s - 4, s, 12);
  stick(0, 4, s, 4, 12); stick(0, s - 4, s, s - 4, 12);
  return toTex(cv);
}

function stoneTex() {
  const s = SIZE;
  const n = tileNoise(s, 8, 121, 5, 0.55);
  const h = new Float32Array(s * s);
  const rows = 5, rh = s / rows;
  const r = mulberry32(122);
  const layout = [];
  for (let row = 0; row < rows; row++) {
    const cuts = [0];
    let x = (row % 2) * s * 0.17;
    if (x > 0) cuts.push(x);
    while (x < s) { x += s * (0.24 + r() * 0.16); if (x < s - 30) cuts.push(x); }
    cuts.push(s);
    layout.push({ cuts, shades: cuts.map(() => 0.8 + r() * 0.35) });
  }
  const cv = paint(s, (x, y, i) => {
    const row = Math.floor(y / rh), py = y - row * rh;
    const L = layout[row];
    let k = 0;
    while (k < L.cuts.length - 1 && x >= L.cuts[k + 1]) k++;
    const dx = Math.min(x - L.cuts[k], L.cuts[k + 1] - x), dy = Math.min(py, rh - py);
    const d = Math.min(dx, dy);
    const mortar = d < 4;
    const bevel = sstep(4, 14, d);
    h[i] = mortar ? 0 : 0.5 + bevel * 0.5 + n[i] * 0.3;
    if (mortar) return mixc([70, 68, 62], [96, 94, 88], n[i]);
    const c = mixc([110, 108, 100], [168, 164, 154], n[i]);
    const sh = L.shades[k] * (0.72 + bevel * 0.28);
    return [c[0] * sh, c[1] * sh, c[2] * sh];
  });
  return { map: toTex(cv), normal: normalMap(h, s, 3) };
}

function metalTex() {
  const s = SIZE;
  const rust = tileNoise(s, 5, 131, 6, 0.6), n2 = tileNoise(s, 32, 132, 3, 0.5), streak = tileNoise(s, 16, 133, 3, 0.5, 1, 0.1);
  const h = new Float32Array(s * s);
  const cv = paint(s, (x, y, i) => {
    const rib = Math.sin((x / s) * Math.PI * 2 * 14);
    h[i] = rib * 0.5 + 0.5;
    const seam = Math.abs(y - s / 2) < 3;
    let c = mixc([104, 108, 108], [150, 152, 150], n2[i]);
    const ru = sstep(0.5, 0.7, rust[i] + streak[i] * 0.25 - 0.1);
    c = mixc(c, mixc([112, 60, 30], [150, 90, 48], n2[i]), ru);
    const sh = 0.82 + rib * 0.12;
    if (seam) return [40, 38, 36];
    return [c[0] * sh, c[1] * sh, c[2] * sh];
  });
  const ctx = cv.getContext('2d');
  ctx.fillStyle = 'rgb(60,56,52)';
  for (let i = 0; i < 14; i++) {
    for (const yy of [10, s / 2 - 10, s / 2 + 10, s - 10]) {
      ctx.beginPath();
      ctx.arc(((i + 0.5) / 14) * s, yy, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  return { map: toTex(cv), normal: normalMap(h, s, 1.5) };
}

function concreteTex() {
  const s = SIZE;
  const n1 = tileNoise(s, 4, 141, 6, 0.6), n2 = tileNoise(s, 64, 142, 2, 0.5), streak = tileNoise(s, 24, 143, 3, 0.5, 1, 0.08);
  const cv = paint(s, (x, y, i) => {
    let c = mixc([116, 114, 106], [158, 156, 148], n1[i]);
    c = mixc(c, [66, 64, 58], sstep(0.55, 0.85, streak[i]) * 0.5 * (y / s));
    c = mixc(c, [80, 84, 60], sstep(0.66, 0.8, n1[i]) * 0.3);
    const f = (n2[i] - 0.5) * 26;
    return [c[0] + f, c[1] + f, c[2] + f];
  });
  const ctx = cv.getContext('2d');
  const r = mulberry32(144);
  ctx.strokeStyle = 'rgba(40,38,34,0.6)';
  for (let k = 0; k < 5; k++) {
    let x = r() * s, y = r() * s;
    ctx.lineWidth = 1 + r();
    ctx.beginPath();
    ctx.moveTo(x, y);
    for (let j = 0; j < 30; j++) { x += (r() - 0.5) * 18; y += r() * 10; ctx.lineTo(x, y); }
    ctx.stroke();
  }
  return toTex(cv);
}

function containerTex(paintCol) {
  const s = SIZE / 2;
  const rust = tileNoise(s, 4, 151 + paintCol[0], 5, 0.6), n2 = tileNoise(s, 32, 152, 2, 0.5);
  const cv = paint(s, (x, y, i) => {
    const rib = Math.sin((x / s) * Math.PI * 2 * 10);
    const frame = y < 8 || y > s - 8;
    let c = mixc(paintCol.map((v) => v * 0.8), paintCol, n2[i]);
    c = mixc(c, [96, 56, 30], sstep(0.58, 0.74, rust[i]) * 0.9);
    const sh = frame ? 0.55 : 0.82 + rib * 0.15;
    return [c[0] * sh, c[1] * sh, c[2] * sh];
  });
  return toTex(cv);
}

function clothTex() {
  const s = 256;
  const n = tileNoise(s, 8, 161, 4, 0.5);
  const cv = paint(s, (x, y, i) => {
    const weave = (Math.sin(x * 1.6) * Math.sin(y * 1.6)) * 12;
    const c = mixc([120, 108, 80], [156, 142, 108], n[i]);
    return [c[0] + weave, c[1] + weave, c[2] + weave];
  });
  return toTex(cv);
}

function waterNormal() {
  const s = 256;
  const h = tileNoise(s, 8, 171, 5, 0.5);
  return normalMap(h, s, 6);
}

function flameTex() {
  const s = 64;
  const cv = canvas(s);
  const ctx = cv.getContext('2d');
  const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  g.addColorStop(0, 'rgba(255,240,180,1)');
  g.addColorStop(0.35, 'rgba(255,160,50,0.8)');
  g.addColorStop(1, 'rgba(255,60,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  return toTex(cv, true, false);
}

function cloudTex() {
  const s = 128;
  const n = tileNoise(s, 4, 181, 5, 0.55);
  const cv = paint(s, (x, y, i) => {
    const dx = x / s - 0.5, dy = y / s - 0.5;
    const d = Math.sqrt(dx * dx + dy * dy) * 2;
    const a = clamp01((1 - d) * 1.6) * sstep(0.3, 0.7, n[i] * (1.2 - d * 0.5));
    return [255, 255, 255, a * 255];
  });
  return toTex(cv, true, false);
}

export function buildTextures(size, aniso) {
  setTexQuality(size, aniso);
  const T = {};
  T.grass = grassTex();
  T.dirt = dirtTex();
  T.rock = rockTex();
  T.rockNormal = normalMap(rockHeight, SIZE, 3);
  T.sand = sandTex();
  T.detail = detailTex();
  const bark = barkTex(false);
  T.bark = bark.map; T.barkNormal = bark.normal;
  T.birch = barkTex(true).map;
  T.needles = needleTex();
  T.leaves = leafTex();
  T.grassBlade = grassBladeTex();
  T.hemp = hempLeafTex();
  const pl = planksTex();
  T.planks = pl.map; T.planksNormal = pl.normal;
  T.twig = twigTex();
  const st = stoneTex();
  T.stone = st.map; T.stoneNormal = st.normal;
  const mt = metalTex();
  T.metal = mt.map; T.metalNormal = mt.normal;
  T.concrete = concreteTex();
  T.contRed = containerTex([150, 52, 38]);
  T.contBlue = containerTex([48, 84, 126]);
  T.contGreen = containerTex([64, 96, 58]);
  T.cloth = clothTex();
  T.water = waterNormal();
  T.flame = flameTex();
  T.cloud = cloudTex();
  return T;
}
