// Процедурные текстуры для гонки: высокое разрешение, всё рисуется кодом.
import * as THREE from './three.module.min.js';

let ANISO = 8;
export function setAniso(a) { ANISO = a; }

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function canvas(w, h = w) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

export function tex(cv, { srgb = true, repeat = true } = {}) {
  const t = new THREE.CanvasTexture(cv);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = ANISO;
  return t;
}

// Зерно поверх заливки.
function grain(ctx, w, h, amount, seed, alpha = 0.12) {
  const img = ctx.getImageData(0, 0, w, h);
  const d = img.data;
  const r = rng(seed);
  for (let i = 0; i < d.length; i += 4) {
    const n = (r() - 0.5) * amount;
    d[i] += n; d[i + 1] += n; d[i + 2] += n;
  }
  ctx.putImageData(img, 0, 0);
  void alpha;
}

export function asphaltTex() {
  const s = 1024, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = '#3c3d40';
  ctx.fillRect(0, 0, s, s);
  const r = rng(11);
  for (let i = 0; i < 40; i++) {
    ctx.fillStyle = `rgba(${r() < 0.5 ? '20,20,22' : '80,80,84'},${0.08 + r() * 0.1})`;
    ctx.fillRect(r() * s, r() * s, 60 + r() * 220, 40 + r() * 180);
  }
  for (let i = 0; i < 26000; i++) {
    const v = 40 + r() * 110;
    ctx.fillStyle = `rgba(${v},${v},${v + 4},${0.35 + r() * 0.4})`;
    const sz = r() < 0.9 ? 1.5 : 3;
    ctx.fillRect(r() * s, r() * s, sz, sz);
  }
  ctx.strokeStyle = 'rgba(15,15,16,0.55)';
  for (let k = 0; k < 7; k++) {
    let x = r() * s, y = r() * s;
    ctx.lineWidth = 1 + r() * 1.5;
    ctx.beginPath();
    ctx.moveTo(x, y);
    for (let j = 0; j < 25; j++) { x += (r() - 0.5) * 30; y += (r() - 0.3) * 14; ctx.lineTo(x, y); }
    ctx.stroke();
  }
  grain(ctx, s, s, 18, 12);
  return tex(cv);
}

export function sidewalkTex() {
  const s = 1024, cv = canvas(s), ctx = cv.getContext('2d');
  const r = rng(21), n = 8, t = s / n;
  ctx.fillStyle = '#6d6a64';
  ctx.fillRect(0, 0, s, s);
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const v = 150 + r() * 40;
      ctx.fillStyle = `rgb(${v},${v - 4},${v - 10})`;
      ctx.fillRect(x * t + 4, y * t + 4, t - 8, t - 8);
      ctx.fillStyle = 'rgba(255,255,255,0.08)';
      ctx.fillRect(x * t + 4, y * t + 4, t - 8, 6);
    }
  }
  grain(ctx, s, s, 22, 22);
  return tex(cv);
}

export function concreteTex(base = 150) {
  const s = 512, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = `rgb(${base},${base - 2},${base - 6})`;
  ctx.fillRect(0, 0, s, s);
  grain(ctx, s, s, 26, base);
  return tex(cv);
}

const WALLS = {
  brick: (ctx, w, h, r) => {
    ctx.fillStyle = '#6e3a2a';
    ctx.fillRect(0, 0, w, h);
    const bh = 22, bw = 60;
    for (let y = 0; y < h; y += bh) {
      const off = (y / bh) % 2 ? bw / 2 : 0;
      for (let x = -bw; x < w + bw; x += bw) {
        const v = 0.8 + r() * 0.35;
        ctx.fillStyle = `rgb(${150 * v | 0},${68 * v | 0},${48 * v | 0})`;
        ctx.fillRect(x + off + 2, y + 2, bw - 4, bh - 4);
      }
    }
  },
  plaster: (ctx, w, h, r) => {
    ctx.fillStyle = '#d9c7a1';
    ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 60; i++) {
      ctx.fillStyle = `rgba(${r() < 0.5 ? '120,100,70' : '255,245,220'},0.06)`;
      ctx.fillRect(r() * w, r() * h, 80 + r() * 200, 60 + r() * 200);
    }
  },
  panel: (ctx, w, h) => {
    ctx.fillStyle = '#a7a8a4';
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = 'rgba(40,40,40,0.6)';
    ctx.lineWidth = 3;
    for (let y = 0; y <= h; y += h / 4) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
    for (let x = 0; x <= w; x += w / 3) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke(); }
  },
  glass: (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, w, h);
    g.addColorStop(0, '#2b4f73'); g.addColorStop(0.5, '#6f9cc4'); g.addColorStop(1, '#23405e');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  },
};

// Фасад: секция 12 × 12 м — 3 окна × 4 этажа. Возвращает карту цвета и карту свечения окон (ночь).
export function facadeTex(style, seed) {
  const w = 1024, h = 1024, cv = canvas(w, h), ctx = cv.getContext('2d');
  const em = canvas(512, 512), ex = em.getContext('2d');
  ex.fillStyle = '#000';
  ex.fillRect(0, 0, 512, 512);
  const r = rng(seed);
  WALLS[style](ctx, w, h, r);
  const cols = 3, rows = 4, cw = w / cols, rh = h / rows;
  for (let fy = 0; fy < rows; fy++) {
    for (let fx = 0; fx < cols; fx++) {
      const x = fx * cw + (style === 'glass' ? 6 : cw * 0.2), y = fy * rh + (style === 'glass' ? 6 : rh * 0.2);
      const ww = style === 'glass' ? cw - 12 : cw * 0.6, wh = style === 'glass' ? rh - 12 : rh * 0.58;
      if (style !== 'glass') {
        ctx.fillStyle = style === 'brick' ? '#e8e2d6' : '#f2efe8';
        ctx.fillRect(x - 8, y - 8, ww + 16, wh + 16);
        ctx.fillStyle = 'rgba(0,0,0,0.25)';
        ctx.fillRect(x - 8, y + wh + 8, ww + 16, 10);
      }
      const g = ctx.createLinearGradient(x, y, x + ww, y + wh);
      const tint = r();
      g.addColorStop(0, tint < 0.5 ? '#9cc0dc' : '#7fa2bf');
      g.addColorStop(0.45, '#35536e');
      g.addColorStop(1, '#1d2d3d');
      ctx.fillStyle = g;
      ctx.fillRect(x, y, ww, wh);
      if (r() < 0.35) {
        ctx.fillStyle = r() < 0.5 ? 'rgba(230,220,190,0.55)' : 'rgba(200,120,110,0.45)';
        ctx.fillRect(x, y, ww * (0.2 + r() * 0.3), wh);
      }
      ctx.strokeStyle = style === 'glass' ? '#1b2a38' : '#f5f3ee';
      ctx.lineWidth = style === 'glass' ? 8 : 6;
      ctx.strokeRect(x, y, ww, wh);
      ctx.beginPath(); ctx.moveTo(x + ww / 2, y); ctx.lineTo(x + ww / 2, y + wh); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x, y + wh * 0.3); ctx.lineTo(x + ww, y + wh * 0.3); ctx.stroke();
      if (r() < 0.38) {
        // горящее окно: свет от люстры сверху, шторы по краям, переплёт рамы
        const k = 0.5, X = x * k, Y = y * k, W2 = ww * k, H2 = wh * k;
        const warm = r() < 0.7, gg = 200 + r() * 40 | 0, bb = 120 + r() * 60 | 0;
        const lg = ex.createRadialGradient(X + W2 * (0.3 + r() * 0.4), Y + H2 * 0.25, 2, X + W2 / 2, Y + H2 / 2, H2);
        lg.addColorStop(0, warm ? `rgb(255,${gg + 15},${bb + 40})` : '#e8f4ff');
        lg.addColorStop(1, warm ? `rgb(150,${gg - 110},${bb - 90})` : '#5d7a99');
        ex.fillStyle = lg;
        ex.fillRect(X, Y, W2, H2);
        if (r() < 0.6) {
          ex.fillStyle = warm ? 'rgba(120,40,20,0.55)' : 'rgba(30,50,80,0.5)';
          ex.fillRect(X, Y, W2 * (0.12 + r() * 0.15), H2);
          ex.fillRect(X + W2 * (0.85 - r() * 0.12), Y, W2, H2);
        }
        ex.fillStyle = '#000';
        ex.fillRect(X + W2 / 2 - 1.5, Y, 3, H2);
        ex.fillRect(X, Y + H2 * 0.3 - 1.5, W2, 3);
        ex.strokeStyle = '#000';
        ex.lineWidth = 3;
        ex.strokeRect(X, Y, W2, H2);
      }
    }
  }
  grain(ctx, w, h, 14, seed);
  return { map: tex(cv), emissive: tex(em) };
}

// Первый этаж с витринами: 12 × 4.5 м.
export function shopTex(seed) {
  const w = 1024, h = 384, cv = canvas(w, h), ctx = cv.getContext('2d');
  const em = canvas(512, 192), ex = em.getContext('2d');
  const r = rng(seed);
  ctx.fillStyle = ['#2e2f33', '#4a3a2e', '#e8e3d9', '#23313f'][seed % 4];
  ctx.fillRect(0, 0, w, h);
  ex.fillStyle = '#000';
  ex.fillRect(0, 0, 512, 192);
  const hue = (seed * 67) % 360;
  const panes = 3;
  for (let i = 0; i < panes; i++) {
    const x = 20 + i * (w - 40) / panes, ww = (w - 40) / panes - 20, y = 80, hh = h - 110;
    const door = i === 1;
    // интерьер магазина: задняя стена, потолочные светильники, стеллажи с товаром
    const g = ctx.createLinearGradient(x, y, x, y + hh);
    g.addColorStop(0, '#f3efe6'); g.addColorStop(0.55, '#cfc8bb'); g.addColorStop(1, '#8d8578');
    ctx.fillStyle = g;
    ctx.fillRect(x, y, ww, hh);
    ctx.fillStyle = '#fffdf5';
    for (let k = 0; k < 3; k++) ctx.fillRect(x + 20 + k * (ww - 40) / 3, y + 10, (ww - 40) / 3 - 30, 6);
    if (!door) {
      for (let row = 0; row < 3; row++) {
        const sy = y + 50 + row * 62;
        ctx.fillStyle = '#6d6a66';
        ctx.fillRect(x + 12, sy + 44, ww - 24, 6);
        let px = x + 16;
        while (px < x + ww - 30) {
          const pw = 14 + Math.floor(r() * 3) * 6, ph = 22 + Math.floor(r() * 3) * 7;
          const n = 2 + Math.floor(r() * 4);
          const col = `hsl(${(hue + Math.floor(r() * 4) * 40) % 360},${45 + r() * 25}%,${38 + r() * 22}%)`;
          for (let q = 0; q < n && px < x + ww - 30; q++) {
            ctx.fillStyle = col;
            ctx.fillRect(px, sy + 44 - ph, pw, ph);
            ctx.fillStyle = 'rgba(255,255,255,0.35)';
            ctx.fillRect(px + 2, sy + 44 - ph + 4, pw - 4, 4);
            px += pw + 3;
          }
          px += 6;
        }
      }
    } else {
      // дверь: рамка, ручка, вид в глубину зала
      ctx.fillStyle = '#b8b0a2';
      ctx.fillRect(x + ww * 0.2, y + 30, ww * 0.6, hh - 30);
      ctx.fillStyle = '#5e5850';
      ctx.fillRect(x + ww * 0.25, y + 120, ww * 0.5, 40);
      ctx.strokeStyle = '#2a2a2a';
      ctx.lineWidth = 10;
      ctx.strokeRect(x + ww * 0.18, y + 12, ww * 0.64, hh - 12);
      ctx.fillStyle = '#d8d8d8';
      ctx.fillRect(x + ww * 0.68, y + hh * 0.45, 8, 60);
    }
    // ночью светится сам интерьер (тёплый свет), а не ровная заливка
    ex.drawImage(cv, x, y, ww, hh, x / 2 + 4, y / 2 + 4, ww / 2 - 8, hh / 2 - 8);
    ex.fillStyle = 'rgba(255,200,130,0.28)';
    ex.fillRect(x / 2 + 4, y / 2 + 4, ww / 2 - 8, hh / 2 - 8);
    // стекло: лёгкое отражение неба диагональю
    const rg = ctx.createLinearGradient(x, y, x + ww, y + hh);
    rg.addColorStop(0, 'rgba(190,215,240,0.45)'); rg.addColorStop(0.35, 'rgba(190,215,240,0.12)');
    rg.addColorStop(0.36, 'rgba(255,255,255,0.28)'); rg.addColorStop(0.42, 'rgba(190,215,240,0.08)'); rg.addColorStop(1, 'rgba(20,30,40,0.25)');
    ctx.fillStyle = rg;
    ctx.fillRect(x, y, ww, hh);
    ctx.strokeStyle = '#1a1a1a';
    ctx.lineWidth = 8;
    ctx.strokeRect(x, y, ww, hh);
  }
  grain(ctx, w, h, 6, seed);
  return { map: tex(cv), emissive: tex(em) };
}

export function signTex(text, bg, fg) {
  const cv = canvas(512, 128), ctx = cv.getContext('2d');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 512, 128);
  ctx.strokeStyle = 'rgba(255,255,255,0.35)';
  ctx.lineWidth = 6;
  ctx.strokeRect(6, 6, 500, 116);
  ctx.fillStyle = fg;
  ctx.font = 'bold 72px Arial, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, 256, 68);
  return tex(cv, { repeat: false });
}

export function roofTex() { return concreteTex(95); }

export function leatherTex(color = '#2a2320', stitch = '#c8a46a') {
  const s = 512, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, s, s);
  grain(ctx, s, s, 20, 31);
  // стёганые ромбы с прострочкой
  ctx.strokeStyle = 'rgba(0,0,0,0.45)';
  ctx.lineWidth = 5;
  const step = 64;
  for (let i = -s; i < s * 2; i += step) {
    ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i + s, s); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(i, s); ctx.lineTo(i + s, 0); ctx.stroke();
  }
  ctx.strokeStyle = stitch;
  ctx.lineWidth = 1.6;
  ctx.setLineDash([6, 5]);
  for (let i = -s; i < s * 2; i += step) {
    ctx.beginPath(); ctx.moveTo(i + 5, 0); ctx.lineTo(i + 5 + s, s); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(i - 5, s); ctx.lineTo(i - 5 + s, 0); ctx.stroke();
  }
  ctx.setLineDash([]);
  return tex(cv);
}

export function softTouchTex(color = '#1f2124') {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, s, s);
  grain(ctx, s, s, 16, 41);
  return tex(cv);
}

export function carbonTex() {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  const n = 16, t = s / n;
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const g = ctx.createLinearGradient(x * t, y * t, x * t + ((x + y) % 2 ? t : 0), y * t + ((x + y) % 2 ? 0 : t));
      g.addColorStop(0, '#15161a'); g.addColorStop(0.5, '#3a3d45'); g.addColorStop(1, '#15161a');
      ctx.fillStyle = g;
      ctx.fillRect(x * t, y * t, t, t);
    }
  }
  return tex(cv);
}

export function fabricTex(color = '#b9b4aa') {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, s, s);
  grain(ctx, s, s, 24, 51);
  return tex(cv);
}

export function leavesTex() {
  const s = 512, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = '#3f6a2a';
  ctx.fillRect(0, 0, s, s);
  const r = rng(61);
  for (let i = 0; i < 2600; i++) {
    const g = 70 + r() * 90;
    ctx.fillStyle = `rgb(${g * 0.55 | 0},${g | 0},${g * 0.35 | 0})`;
    ctx.beginPath();
    ctx.ellipse(r() * s, r() * s, 5 + r() * 7, 3 + r() * 4, r() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  return tex(cv);
}

export function barkTex() {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = '#4a3a2c';
  ctx.fillRect(0, 0, s, s);
  const r = rng(71);
  ctx.strokeStyle = 'rgba(20,14,10,0.6)';
  for (let i = 0; i < 40; i++) {
    const x = r() * s;
    ctx.lineWidth = 1 + r() * 3;
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.bezierCurveTo(x + 10, s / 3, x - 10, s * 2 / 3, x + 4, s); ctx.stroke();
  }
  return tex(cv);
}

export function lightPoolTex() {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  g.addColorStop(0, 'rgba(255,214,150,0.55)');
  g.addColorStop(0.5, 'rgba(255,190,110,0.18)');
  g.addColorStop(1, 'rgba(255,170,90,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  return tex(cv, { repeat: false });
}

// Шкалы приборов: спидометр (0–260) и тахометр (0–8).
export function dialsTex() {
  const w = 1024, h = 512, cv = canvas(w, h), ctx = cv.getContext('2d');
  ctx.fillStyle = '#07080a';
  ctx.fillRect(0, 0, w, h);
  const dial = (cx, cy, R, max, step, label, red) => {
    const g = ctx.createRadialGradient(cx, cy, R * 0.2, cx, cy, R);
    g.addColorStop(0, '#1a1d22'); g.addColorStop(1, '#0b0c0e');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = '#8fa3b8'; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.arc(cx, cy, R - 2, 0, Math.PI * 2); ctx.stroke();
    const a0 = Math.PI * 0.75, a1 = Math.PI * 2.25;
    for (let v = 0; v <= max; v += step / 2) {
      const a = a0 + (v / max) * (a1 - a0);
      const major = v % step === 0;
      const r1 = R * (major ? 0.78 : 0.84), r2 = R * 0.92;
      ctx.strokeStyle = red && v >= red ? '#ff4040' : '#e8eef5';
      ctx.lineWidth = major ? 5 : 2.5;
      ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); ctx.stroke();
      if (major) {
        ctx.fillStyle = red && v >= red ? '#ff5050' : '#f2f5f8';
        ctx.font = `bold ${R * 0.13}px Arial`;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText(String(v), cx + Math.cos(a) * R * 0.63, cy + Math.sin(a) * R * 0.63);
      }
    }
    ctx.fillStyle = '#9fb2c6';
    ctx.font = `${R * 0.11}px Arial`;
    ctx.fillText(label, cx, cy + R * 0.45);
  };
  dial(256, 256, 230, 260, 20, 'км/ч', 0);
  dial(768, 256, 230, 8, 1, '×1000 об/мин', 6.5);
  return tex(cv, { repeat: false });
}

export function navTex() {
  const w = 512, h = 320, cv = canvas(w, h), ctx = cv.getContext('2d');
  ctx.fillStyle = '#10161d';
  ctx.fillRect(0, 0, w, h);
  const r = rng(81);
  ctx.strokeStyle = '#2a3643';
  for (let i = 0; i < 18; i++) {
    ctx.lineWidth = 3 + r() * 8;
    ctx.beginPath();
    ctx.moveTo(r() * w, r() * h);
    ctx.lineTo(r() * w, r() * h);
    ctx.stroke();
  }
  ctx.strokeStyle = '#2f9bff';
  ctx.lineWidth = 12;
  ctx.beginPath(); ctx.moveTo(w / 2, h); ctx.lineTo(w / 2, 90); ctx.lineTo(w * 0.78, 60); ctx.stroke();
  ctx.fillStyle = '#ffffff';
  ctx.beginPath(); ctx.moveTo(w / 2, 230); ctx.lineTo(w / 2 - 20, 270); ctx.lineTo(w / 2 + 20, 270); ctx.fill();
  ctx.fillStyle = 'rgba(0,0,0,0.6)';
  ctx.fillRect(0, 0, w, 44);
  ctx.fillStyle = '#e8eef5';
  ctx.font = 'bold 26px Arial';
  ctx.fillText('↑ 2,4 км   Проспект', 14, 31);
  return tex(cv, { repeat: false });
}

const PLATE_LETTERS = 'АВЕКМНОРСТУХ';
export function plateTex(seed) {
  const r = rng(seed);
  const L = () => PLATE_LETTERS[Math.floor(r() * PLATE_LETTERS.length)];
  const D = () => Math.floor(r() * 10);
  const cv = canvas(512, 112), ctx = cv.getContext('2d');
  ctx.fillStyle = '#f6f6f2';
  ctx.fillRect(0, 0, 512, 112);
  ctx.strokeStyle = '#111';
  ctx.lineWidth = 6;
  ctx.strokeRect(4, 4, 504, 104);
  ctx.beginPath(); ctx.moveTo(390, 4); ctx.lineTo(390, 108); ctx.stroke();
  ctx.fillStyle = '#111';
  ctx.font = 'bold 76px Arial';
  ctx.textBaseline = 'middle';
  ctx.fillText(`${L()}${D()}${D()}${D()}${L()}${L()}`, 22, 60);
  ctx.font = 'bold 44px Arial';
  ctx.textAlign = 'center';
  ctx.fillText(String(10 + Math.floor(r() * 190)), 450, 44);
  ctx.font = 'bold 18px Arial';
  ctx.fillText('RUS', 450, 88);
  return tex(cv, { repeat: false });
}

export function tireTex() {
  const s = 256, cv = canvas(s), ctx = cv.getContext('2d');
  ctx.fillStyle = '#16171a';
  ctx.fillRect(0, 0, s, s);
  ctx.fillStyle = '#0c0c0e';
  for (let i = 0; i < 16; i++) ctx.fillRect(0, i * 16, s, 5);
  grain(ctx, s, s, 10, 91);
  return tex(cv);
}
