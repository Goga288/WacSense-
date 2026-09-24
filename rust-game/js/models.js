// Процедурные модели растительности и ресурсов.
import * as THREE from './three.module.min.js';
import { mergeUV, mergeVerts } from './gfx.js';
import { makePerlin, smoothstep, lerp } from './util.js';

const mat4 = (pos = [0, 0, 0], rot = [0, 0, 0], scale = [1, 1, 1]) => new THREE.Matrix4().compose(
  new THREE.Vector3(...pos), new THREE.Quaternion().setFromEuler(new THREE.Euler(...rot)), new THREE.Vector3(...scale),
);
export { mat4 };

const norm = (x, y, z) => { const l = Math.hypot(x, y, z) || 1; return [x / l, y / l, z / l]; };

// Ель: ствол + ярусы веток-карточек.
export function pineGeos(rng, H = 12, layers = 12, cards = 7) {
  const trunk = mergeUV([
    { geo: new THREE.CylinderGeometry(0.08, 0.32, H, 9, 1), matrix: mat4([0, H / 2, 0]), uvScale: [2, H / 2.5] },
    { geo: new THREE.ConeGeometry(0.5, 0.8, 9, 1, true), matrix: mat4([0, 0.25, 0]), uvScale: [2, 0.4] },
  ]);
  const parts = [];
  for (let i = 0; i < layers; i++) {
    const t = i / (layers - 1);
    const y = H * (0.2 + t * 0.74);
    const len = lerp(3.1, 0.7, Math.pow(t, 0.9)) * (0.85 + rng() * 0.3);
    const n = Math.max(4, Math.round(cards * (1 - t * 0.45)));
    for (let k = 0; k < n; k++) {
      const a = (k / n) * Math.PI * 2 + i * 0.9 + rng() * 0.4;
      const g = new THREE.PlaneGeometry(len, len * 0.8);
      g.translate(len / 2, 0, 0);
      g.rotateX(-Math.PI / 2 + (rng() - 0.5) * 0.5);
      g.rotateZ(-(0.22 + t * 0.15 + rng() * 0.15));
      g.rotateY(a);
      g.translate(0, y, 0);
      parts.push({ geo: g, shade: (x, yy, z) => 0.5 + 0.5 * Math.min(1, Math.hypot(x, z) / (len * 0.9)) * (0.75 + t * 0.25) });
    }
  }
  for (let k = 0; k < 2; k++) {
    const g = new THREE.PlaneGeometry(1.0, 1.8);
    g.rotateZ(Math.PI / 2);
    g.translate(0, H - 0.2, 0);
    g.rotateY(k * Math.PI / 2);
    parts.push({ geo: g, shade: () => 0.9 });
  }
  const crown = mergeUV(parts, (x, y, z) => norm(x, 0.9 + (y - H * 0.55) * 0.05, z));
  return { trunk, crown };
}

// Лиственное дерево (берёза).
export function birchGeos(rng) {
  const H = 9;
  const trunk = mergeUV([
    { geo: new THREE.CylinderGeometry(0.1, 0.22, H, 8, 1), matrix: mat4([0, H / 2, 0], [0, 0, 0.03]), uvScale: [1, H / 2] },
    { geo: new THREE.CylinderGeometry(0.03, 0.06, 2.4, 5, 1), matrix: mat4([0.6, 5.6, 0], [0, 0, -0.9]), uvScale: [0.5, 1] },
    { geo: new THREE.CylinderGeometry(0.03, 0.06, 2.2, 5, 1), matrix: mat4([-0.5, 6.4, 0.3], [0.3, 0, 0.8]), uvScale: [0.5, 1] },
  ]);
  const parts = [];
  const clusters = [[0, 7.4, 0, 1.6], [0.9, 6.2, 0.3, 1.2], [-0.8, 6.6, -0.4, 1.2], [0.2, 8.6, 0.2, 1.0], [-0.2, 5.6, 0.8, 1.0]];
  for (const [cx, cy, cz, cr] of clusters) {
    const n = Math.round(cr * 12);
    for (let k = 0; k < n; k++) {
      const g = new THREE.PlaneGeometry(1.7, 1.7);
      g.applyMatrix4(mat4([0, 0, 0], [rng() * Math.PI, rng() * Math.PI, rng() * Math.PI]));
      const a = rng() * Math.PI * 2, u = rng() * 2 - 1, rr = Math.cbrt(rng()) * cr;
      const s = Math.sqrt(1 - u * u);
      g.translate(cx + Math.cos(a) * s * rr, cy + u * rr * 0.8, cz + Math.sin(a) * s * rr);
      parts.push({ geo: g, shade: (x, y, z) => 0.45 + 0.55 * Math.min(1, Math.hypot(x, y - 7, z) / 2.2) });
    }
  }
  const crown = mergeUV(parts, (x, y, z) => norm(x, (y - 6.8) + 0.6, z));
  return { trunk, crown };
}

// Камень: искажённая сфера, рудные жилы — вершинным цветом.
export function rockGeo(seed, ore = null) {
  const g = mergeVerts(new THREE.IcosahedronGeometry(1, 3));
  const P = makePerlin(seed), P2 = makePerlin(seed + 5);
  const pos = g.attributes.position;
  const col = [];
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
    const n = (P(x * 1.3 + y * 0.7, z * 1.3 - y * 0.4) + P2(y * 1.5 + z * 0.4, x * 1.5)) * 0.5;
    const n2 = P(x * 4 + 10, z * 4 + y * 3) * 0.5;
    const d = 1 + n * 0.38 + n2 * 0.07;
    let py = y * d * 0.74;
    if (py < -0.22) py = -0.22 + (py + 0.22) * 0.25;
    pos.setXYZ(i, x * d, py, z * d);
    let c = [1, 1, 1];
    const shade = 0.85 + n2 * 0.3;
    if (ore) {
      const v = smoothstep(0.12, 0.32, P2(x * 3.2 + y * 2, z * 3.2 - y * 1.5));
      const oc = ore === 'metal' ? [1.05, 0.62, 0.4] : [1.35, 1.15, 0.35];
      c = [lerp(1, oc[0], v), lerp(1, oc[1], v), lerp(1, oc[2], v)];
    }
    col.push(c[0] * shade, c[1] * shade, c[2] * shade);
  }
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeVertexNormals();
  return g;
}

export function hempGeo(rng) {
  const parts = [];
  for (let tier = 0; tier < 4; tier++) {
    const y = 0.15 + tier * 0.28;
    const sz = 0.62 - tier * 0.08;
    for (let k = 0; k < 3; k++) {
      const g = new THREE.PlaneGeometry(sz, sz);
      g.translate(0, sz * 0.35, 0);
      g.rotateX(-0.95 + tier * 0.12);
      g.rotateY((k / 3) * Math.PI * 2 + tier * 0.8 + rng() * 0.3);
      g.translate(0, y, 0);
      parts.push({ geo: g, shade: () => 0.7 + tier * 0.1 });
    }
  }
  for (let k = 0; k < 2; k++) {
    const g = new THREE.PlaneGeometry(0.4, 0.5);
    g.translate(0, 1.2, 0);
    g.rotateY(k * Math.PI / 2);
    parts.push({ geo: g, shade: () => 1 });
  }
  return mergeUV(parts, (x, y, z) => norm(x, 0.8, z));
}

export function bushGeo(rng) {
  const parts = [];
  for (let k = 0; k < 14; k++) {
    const g = new THREE.PlaneGeometry(1.3, 1.3);
    g.applyMatrix4(mat4([0, 0, 0], [rng() * Math.PI, rng() * Math.PI, 0]));
    g.translate((rng() - 0.5) * 0.9, 0.5 + rng() * 0.5, (rng() - 0.5) * 0.9);
    parts.push({ geo: g, shade: (x, y, z) => 0.5 + 0.5 * Math.min(1, Math.hypot(x, y - 0.6, z) / 0.8) });
  }
  return mergeUV(parts, (x, y, z) => norm(x, y - 0.3, z));
}

export function mushroomGeo() {
  const cap = new THREE.LatheGeometry([
    new THREE.Vector2(0.0, 0.2), new THREE.Vector2(0.17, 0.2), new THREE.Vector2(0.19, 0.24),
    new THREE.Vector2(0.15, 0.31), new THREE.Vector2(0.08, 0.35), new THREE.Vector2(0.0, 0.36),
  ], 12);
  const cap2 = cap.clone();
  return mergeUV([
    { geo: new THREE.CylinderGeometry(0.04, 0.06, 0.22, 8), matrix: mat4([0, 0.11, 0]), color: 0xe6dccb },
    { geo: cap, color: 0x8a5a36 },
    { geo: new THREE.CylinderGeometry(0.03, 0.045, 0.15, 8), matrix: mat4([0.17, 0.075, 0.1]), color: 0xe6dccb },
    { geo: cap2, matrix: mat4([0.17, -0.07, 0.1], [0, 0, 0], [0.7, 0.7, 0.7]), color: 0x7a4a2c },
  ]);
}

export function barrelGeo() {
  return mergeUV([
    { geo: new THREE.CylinderGeometry(0.42, 0.42, 1.1, 16), matrix: mat4([0, 0.55, 0]), uvScale: [1.5, 0.6] },
    { geo: new THREE.TorusGeometry(0.43, 0.025, 6, 20), matrix: mat4([0, 0.32, 0], [Math.PI / 2, 0, 0]), color: 0x999999 },
    { geo: new THREE.TorusGeometry(0.43, 0.025, 6, 20), matrix: mat4([0, 0.78, 0], [Math.PI / 2, 0, 0]), color: 0x999999 },
  ]);
}
