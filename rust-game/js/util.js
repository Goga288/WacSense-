// Общие утилиты: математика, шум, пересечения лучей.

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smoothstep = (a, b, x) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};
export const rand = (a, b) => a + Math.random() * (b - a);
export const randi = (a, b) => Math.floor(a + Math.random() * (b - a + 1));
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
export const angleDiff = (a, b) => {
  let d = (b - a) % (Math.PI * 2);
  if (d > Math.PI) d -= Math.PI * 2;
  if (d < -Math.PI) d += Math.PI * 2;
  return d;
};

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Классический 2D градиентный шум Перлина, результат примерно в [-1, 1].
export function makePerlin(seed) {
  const r = mulberry32(seed);
  const perm = [];
  for (let i = 0; i < 256; i++) perm[i] = i;
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    [perm[i], perm[j]] = [perm[j], perm[i]];
  }
  const p = new Uint8Array(512);
  for (let i = 0; i < 512; i++) p[i] = perm[i & 255];
  const gx = new Float32Array(256);
  const gy = new Float32Array(256);
  for (let i = 0; i < 256; i++) {
    const a = r() * Math.PI * 2;
    gx[i] = Math.cos(a);
    gy[i] = Math.sin(a);
  }
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  const grad = (ix, iy, x, y) => {
    const h = p[p[ix & 255] + (iy & 255)];
    return gx[h] * x + gy[h] * y;
  };
  return function (x, y) {
    const x0 = Math.floor(x);
    const y0 = Math.floor(y);
    const fx = x - x0;
    const fy = y - y0;
    const u = fade(fx);
    const v = fade(fy);
    const n00 = grad(x0, y0, fx, fy);
    const n10 = grad(x0 + 1, y0, fx - 1, fy);
    const n01 = grad(x0, y0 + 1, fx, fy - 1);
    const n11 = grad(x0 + 1, y0 + 1, fx - 1, fy - 1);
    return lerp(lerp(n00, n10, u), lerp(n01, n11, u), v) * 1.41;
  };
}

export function fbm(noise, x, y, oct) {
  let s = 0, a = 1, f = 1, n = 0;
  for (let i = 0; i < oct; i++) {
    s += noise(x * f, y * f) * a;
    n += a;
    a *= 0.5;
    f *= 2;
  }
  return s / n;
}

// ---- Пересечения луча (o — начало, d — нормализованное направление) ----

export function rayBox(o, d, minX, minY, minZ, maxX, maxY, maxZ, maxT) {
  let t0 = 0, t1 = maxT, nx = 0, ny = 0, nz = 0;
  if (Math.abs(d.x) < 1e-9) {
    if (o.x < minX || o.x > maxX) return null;
  } else {
    let a = (minX - o.x) / d.x, b = (maxX - o.x) / d.x;
    if (a > b) { const t = a; a = b; b = t; }
    if (a > t0) { t0 = a; nx = d.x > 0 ? -1 : 1; ny = 0; nz = 0; }
    if (b < t1) t1 = b;
    if (t0 > t1) return null;
  }
  if (Math.abs(d.y) < 1e-9) {
    if (o.y < minY || o.y > maxY) return null;
  } else {
    let a = (minY - o.y) / d.y, b = (maxY - o.y) / d.y;
    if (a > b) { const t = a; a = b; b = t; }
    if (a > t0) { t0 = a; ny = d.y > 0 ? -1 : 1; nx = 0; nz = 0; }
    if (b < t1) t1 = b;
    if (t0 > t1) return null;
  }
  if (Math.abs(d.z) < 1e-9) {
    if (o.z < minZ || o.z > maxZ) return null;
  } else {
    let a = (minZ - o.z) / d.z, b = (maxZ - o.z) / d.z;
    if (a > b) { const t = a; a = b; b = t; }
    if (a > t0) { t0 = a; nz = d.z > 0 ? -1 : 1; nx = 0; ny = 0; }
    if (b < t1) t1 = b;
    if (t0 > t1) return null;
  }
  return { t: t0, nx, ny, nz };
}

export function raySphere(o, d, cx, cy, cz, r, maxT) {
  const ox = o.x - cx, oy = o.y - cy, oz = o.z - cz;
  const b = ox * d.x + oy * d.y + oz * d.z;
  const c = ox * ox + oy * oy + oz * oz - r * r;
  const disc = b * b - c;
  if (disc < 0) return -1;
  let t = -b - Math.sqrt(disc);
  if (t < 0) t = 0;
  return t <= maxT ? t : -1;
}

// Вертикальный цилиндр (ось Y) от y0 до y1.
export function rayCylY(o, d, cx, cz, r, y0, y1, maxT) {
  const ox = o.x - cx, oz = o.z - cz;
  const a = d.x * d.x + d.z * d.z;
  if (a > 1e-9) {
    const b = ox * d.x + oz * d.z;
    const c = ox * ox + oz * oz - r * r;
    const disc = b * b - a * c;
    if (disc >= 0) {
      let t = (-b - Math.sqrt(disc)) / a;
      if (t < 0 && c < 0) t = 0;
      if (t >= 0 && t <= maxT) {
        const y = o.y + d.y * t;
        if (y >= y0 && y <= y1) return t;
      }
    }
  }
  // верхняя крышка
  if (Math.abs(d.y) > 1e-9) {
    const t = (y1 - o.y) / d.y;
    if (t >= 0 && t <= maxT) {
      const x = ox + d.x * t, z = oz + d.z * t;
      if (x * x + z * z <= r * r) return t;
    }
  }
  return -1;
}

export function boxesOverlap(a, b, eps = 0) {
  return (
    a.minX < b.maxX - eps && a.maxX > b.minX + eps &&
    a.minY < b.maxY - eps && a.maxY > b.minY + eps &&
    a.minZ < b.maxZ - eps && a.maxZ > b.minZ + eps
  );
}

// Пространственная сетка для быстрых запросов по XZ.
let gridId = 0;
export class SpatialGrid {
  constructor(cell) {
    this.cell = cell;
    this.cells = new Map();
    this.stamp = 0;
    this.kc = Symbol('cells' + gridId);
    this.ks = Symbol('stamp' + gridId++);
  }
  _k(cx, cz) {
    return (cx + 2000) * 8192 + (cz + 2000);
  }
  add(o, minX, minZ, maxX, maxZ) {
    const c = this.cell;
    const list = [];
    for (let cx = Math.floor(minX / c); cx <= Math.floor(maxX / c); cx++) {
      for (let cz = Math.floor(minZ / c); cz <= Math.floor(maxZ / c); cz++) {
        const k = this._k(cx, cz);
        let a = this.cells.get(k);
        if (!a) { a = []; this.cells.set(k, a); }
        a.push(o);
        list.push(k);
      }
    }
    o[this.kc] = list;
  }
  remove(o) {
    const list = o[this.kc];
    if (!list) return;
    for (const k of list) {
      const a = this.cells.get(k);
      if (!a) continue;
      const i = a.indexOf(o);
      if (i >= 0) a.splice(i, 1);
    }
    o[this.kc] = null;
  }
  query(minX, minZ, maxX, maxZ, out = []) {
    const s = ++this.stamp;
    const c = this.cell;
    for (let cx = Math.floor(minX / c); cx <= Math.floor(maxX / c); cx++) {
      for (let cz = Math.floor(minZ / c); cz <= Math.floor(maxZ / c); cz++) {
        const a = this.cells.get(this._k(cx, cz));
        if (!a) continue;
        for (const o of a) {
          if (o[this.ks] !== s) { o[this.ks] = s; out.push(o); }
        }
      }
    }
    return out;
  }
}
