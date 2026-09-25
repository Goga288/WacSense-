// Город: бесконечный проспект из переиспользуемых участков по 60 м.
import * as THREE from './three.module.min.js';
import * as TX from './textures.js';

export const CHUNK = 60;
export const LANES = [-5.25, -1.75, 1.75, 5.25];
export const ROAD_HALF = 7.4;
const SIGNS = [
  ['КАФЕ', '#7a2e1f', '#ffe8c8'], ['АПТЕКА', '#1f7a3a', '#ffffff'], ['ПРОДУКТЫ', '#1d4e89', '#ffffff'],
  ['ЦВЕТЫ', '#b0306a', '#fff0f6'], ['ПЕКАРНЯ', '#8a5a1c', '#fff4dc'], ['СПОРТ', '#111111', '#ffcc00'],
  ['КНИГИ', '#4b2c6f', '#f3e8ff'], ['ОПТИКА', '#0e6b73', '#ffffff'], ['ПИЦЦА', '#c2311f', '#fff6d8'],
  ['ИГРУШКИ', '#e0752d', '#ffffff'], ['ОБУВЬ', '#2d2d2d', '#ffffff'], ['БАНК', '#0f3d6e', '#e8f2ff'],
];

// Склейка частей участка в меши по материалам (меньше вызовов отрисовки).
function mergeParts(parts) {
  const byMat = new Map();
  for (const p of parts) {
    let arr = byMat.get(p.mat);
    if (!arr) { arr = []; byMat.set(p.mat, arr); }
    arr.push(p);
  }
  const out = [];
  for (const [mat, arr] of byMat) {
    const pos = [], nor = [], uv = [];
    for (const p of arr) {
      const g = p.geo.index ? p.geo.toNonIndexed() : p.geo.clone();
      g.applyMatrix4(p.matrix);
      const pa = g.attributes.position.array, na = g.attributes.normal.array, ua = g.attributes.uv.array;
      for (let i = 0; i < pa.length; i++) { pos.push(pa[i]); nor.push(na[i]); }
      const su = p.uv ? p.uv[0] : 1, sv = p.uv ? p.uv[1] : 1;
      for (let i = 0; i < ua.length; i += 2) { uv.push(ua[i] * su, ua[i + 1] * sv); }
      g.dispose();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    const m = new THREE.Mesh(geo, mat);
    m.castShadow = !mat.transparent && !mat.userData.noShadow;
    m.receiveShadow = true;
    out.push(m);
  }
  return out;
}

const M4 = (x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) => new THREE.Matrix4().compose(
  new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz)), new THREE.Vector3(sx, sy, sz),
);

export class City {
  constructor(scene, envMap, night) {
    this.scene = scene;
    this.night = night;
    this.chunks = new Map();
    this.rng = (seed) => { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
    const std = (o) => new THREE.MeshStandardMaterial({ envMap, ...o });
    const ni = night ? 1 : 0;
    this.M = {
      road: std({ map: TX.asphaltTex(), roughness: night ? 0.75 : 0.92, metalness: 0.0 }),
      walk: std({ map: TX.sidewalkTex(), roughness: 0.9 }),
      curb: std({ map: TX.concreteTex(165), roughness: 0.85 }),
      mark: std({ color: 0xf2f2ee, roughness: 0.6, emissive: 0x444444, emissiveIntensity: ni * 0.4 }),
      roof: std({ map: TX.roofTex(), roughness: 0.95 }),
      pole: std({ color: 0x3a3f45, roughness: 0.45, metalness: 0.8 }),
      lampHead: std({ color: 0x222222, emissive: 0xffd9a0, emissiveIntensity: night ? 3 : 0.05, roughness: 0.3 }),
      bark: std({ map: TX.barkTex(), roughness: 1 }),
      leaves: std({ map: TX.leavesTex(), roughness: 0.9 }),
      awning: [0xb3261e, 0x1f6f4a, 0x2a4f8c, 0xd08a1a, 0x6b3a8a].map((c) => std({ color: c, roughness: 0.8 })),
      glassStop: std({ color: 0x9fc4d8, transparent: true, opacity: 0.3, roughness: 0.05, metalness: 0.1 }),
      pool: new THREE.MeshBasicMaterial({ map: TX.lightPoolTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: night ? 1 : 0 }),
    };
    this.M.pool.userData.noShadow = true;
    this.facades = ['brick', 'plaster', 'panel', 'glass', 'brick', 'plaster'].map((st, i) => {
      const t = TX.facadeTex(st, 100 + i);
      return std({ map: t.map, emissiveMap: t.emissive, emissive: 0xffffff, emissiveIntensity: ni * 1.2, roughness: st === 'glass' ? 0.15 : 0.85, metalness: st === 'glass' ? 0.6 : 0 });
    });
    this.shops = [0, 1, 2, 3].map((i) => {
      const t = TX.shopTex(200 + i);
      return std({ map: t.map, emissiveMap: t.emissive, emissive: 0xffffff, emissiveIntensity: ni * 0.95, roughness: 0.35, metalness: 0.2 });
    });
    this.signs = SIGNS.map(([w, bg, fg]) => std({ map: TX.signTex(w, bg, fg), emissive: 0xffffff, emissiveMap: TX.signTex(w, bg, fg), emissiveIntensity: ni * 0.9, roughness: 0.4 }));
    this.dashGeo = new THREE.PlaneGeometry(0.15, 3).rotateX(-Math.PI / 2);
  }

  build(i) {
    const r = this.rng(i * 7919 + 13);
    const z0 = -i * CHUNK, zc = z0 - CHUNK / 2;
    const parts = [];
    const M = this.M;
    const plane = (w, h) => new THREE.PlaneGeometry(w, h);
    const boxG = (x, y, z) => new THREE.BoxGeometry(x, y, z);
    // дорога (плитка асфальта 7.5 м — стыкуется между участками)
    parts.push({ geo: plane(ROAD_HALF * 2 + 0.2, CHUNK), mat: M.road, matrix: M4(0, 0, zc, -Math.PI / 2), uv: [2, 8] });
    // разметка: пунктир 3/9 м и сплошные по краям
    for (const lx of [-3.5, 0, 3.5]) {
      for (let k = 0; k < 5; k++) parts.push({ geo: this.dashGeo, mat: M.mark, matrix: M4(lx, 0.012, z0 - 1.5 - k * 12) });
    }
    for (const lx of [-7.0, 7.0]) parts.push({ geo: plane(0.15, CHUNK), mat: M.mark, matrix: M4(lx, 0.012, zc, -Math.PI / 2) });
    // пешеходный переход и светофоры
    if (i % 4 === 2) {
      for (let k = 0; k < 11; k++) parts.push({ geo: plane(0.6, 4), mat: M.mark, matrix: M4(-6.6 + k * 1.32, 0.013, z0 - 30, -Math.PI / 2) });
    }
    // тротуары и бордюры
    for (const sx of [-1, 1]) {
      parts.push({ geo: boxG(5.2, 0.18, CHUNK), mat: M.walk, matrix: M4(sx * (ROAD_HALF + 0.25 + 2.6), 0.09, zc), uv: [1.3, 15] });
      parts.push({ geo: boxG(0.25, 0.2, CHUNK), mat: M.curb, matrix: M4(sx * (ROAD_HALF + 0.12), 0.1, zc), uv: [1, 12] });
      // фонари каждые 30 м (со световым пятном ночью)
      for (let k = 0; k < 2; k++) {
        const lz = z0 - 15 - k * 30;
        const px = sx * (ROAD_HALF + 0.6);
        parts.push({ geo: new THREE.CylinderGeometry(0.09, 0.13, 8.5, 10), mat: M.pole, matrix: M4(px, 4.25, lz) });
        parts.push({ geo: boxG(2.4, 0.1, 0.12), mat: M.pole, matrix: M4(px - sx * 1.2, 8.4, lz) });
        parts.push({ geo: boxG(0.9, 0.16, 0.35), mat: M.lampHead, matrix: M4(px - sx * 2.3, 8.3, lz) });
        parts.push({ geo: plane(11, 11), mat: M.pool, matrix: M4(px - sx * 2.3, 0.03, lz, -Math.PI / 2) });
      }
      // деревья между фонарями
      for (let k = 0; k < 3; k++) {
        const tz = z0 - 5 - k * 20 + (r() - 0.5) * 2;
        const tx = sx * (ROAD_HALF + 3.6);
        const s = 0.85 + r() * 0.35;
        parts.push({ geo: new THREE.CylinderGeometry(0.12 * s, 0.18 * s, 3.2 * s, 8), mat: M.bark, matrix: M4(tx, 1.6 * s + 0.18, tz), uv: [1, 2] });
        parts.push({ geo: new THREE.IcosahedronGeometry(1.6 * s, 1), mat: M.leaves, matrix: M4(tx, 4.1 * s, tz, r(), r(), r(), 1, 0.9, 1), uv: [2, 2] });
        parts.push({ geo: new THREE.IcosahedronGeometry(1.1 * s, 1), mat: M.leaves, matrix: M4(tx + 0.6, 4.8 * s, tz + 0.4, r(), r(), r()), uv: [2, 2] });
        parts.push({ geo: boxG(1.2, 0.05, 1.2), mat: M.pole, matrix: M4(tx, 0.2, tz) });
      }
      // дома
      let z = z0;
      while (z > z0 - CHUNK + 0.1) {
        const w = Math.min([12, 18, 24][Math.floor(r() * 3)], z - (z0 - CHUNK));
        const h = [12, 15, 18, 24, 30, 36, 45][Math.floor(r() * 7)] + 4.5;
        const d = 16;
        const fx = sx * (ROAD_HALF + 5.45);
        const cx = fx + sx * d / 2, bz = z - w / 2;
        const fm = this.facades[Math.floor(r() * this.facades.length)];
        const up = h - 4.5;
        // фасад (к дороге), торцы и крыша
        parts.push({ geo: plane(w, up), mat: fm, matrix: M4(fx, 4.5 + up / 2, bz, 0, -sx * Math.PI / 2), uv: [w / 12, up / 12] });
        parts.push({ geo: plane(d, up), mat: fm, matrix: M4(cx, 4.5 + up / 2, z, 0, 0), uv: [d / 12, up / 12] });
        parts.push({ geo: plane(d, up), mat: fm, matrix: M4(cx, 4.5 + up / 2, z - w, 0, Math.PI), uv: [d / 12, up / 12] });
        parts.push({ geo: plane(d, w), mat: M.roof, matrix: M4(cx, h, bz, -Math.PI / 2, 0, 0), uv: [d / 8, w / 8] });
        parts.push({ geo: boxG(0.4, 0.8, w), mat: M.curb, matrix: M4(fx + sx * 0.2, h + 0.4, bz), uv: [1, w / 6] });
        // первый этаж: витрины, козырёк, вывеска
        const sm = this.shops[Math.floor(r() * this.shops.length)];
        parts.push({ geo: plane(w, 4.5), mat: sm, matrix: M4(fx - sx * 0.05, 2.25, bz, 0, -sx * Math.PI / 2), uv: [w / 12, 1] });
        parts.push({ geo: plane(d, 4.5), mat: M.curb, matrix: M4(cx, 2.25, z, 0, 0), uv: [2, 1] });
        parts.push({ geo: plane(d, 4.5), mat: M.curb, matrix: M4(cx, 2.25, z - w, 0, Math.PI), uv: [2, 1] });
        const aw = M.awning[Math.floor(r() * M.awning.length)];
        parts.push({ geo: boxG(1.4, 0.12, w - 1), mat: aw, matrix: M4(fx - sx * 0.75, 3.5, bz, 0, 0, sx * 0.25) });
        const sg = this.signs[Math.floor(r() * this.signs.length)];
        parts.push({ geo: plane(Math.min(7, w - 2), 1.6), mat: sg, matrix: M4(fx - sx * 0.12, 4.35, bz, 0, -sx * Math.PI / 2) });
        z -= w;
      }
      // остановка
      if (i % 5 === 3) {
        const bx = sx * (ROAD_HALF + 2.0), bz = z0 - 42;
        parts.push({ geo: boxG(1.6, 0.1, 5), mat: M.pole, matrix: M4(bx, 2.7, bz) });
        parts.push({ geo: boxG(0.05, 2.3, 5), mat: M.glassStop, matrix: M4(bx + sx * 0.75, 1.5, bz) });
        parts.push({ geo: boxG(0.5, 0.1, 3), mat: M.pole, matrix: M4(bx + sx * 0.4, 0.65, bz) });
        for (const dz of [-2.4, 2.4]) parts.push({ geo: new THREE.CylinderGeometry(0.05, 0.05, 2.6, 8), mat: M.pole, matrix: M4(bx + sx * 0.7, 1.4, bz + dz) });
      }
    }
    const g = new THREE.Group();
    for (const m of mergeParts(parts)) g.add(m);
    this.scene.add(g);
    return g;
  }

  update(playerZ) {
    const cur = Math.floor(-playerZ / CHUNK);
    const from = cur - 1, to = cur + 7;
    for (let i = from; i <= to; i++) {
      if (!this.chunks.has(i)) this.chunks.set(i, this.build(i));
    }
    for (const [i, g] of this.chunks) {
      if (i < from || i > to) {
        this.scene.remove(g);
        g.traverse((o) => { if (o.isMesh) o.geometry.dispose(); });
        this.chunks.delete(i);
      }
    }
  }

  dispose() {
    for (const [, g] of this.chunks) {
      this.scene.remove(g);
      g.traverse((o) => { if (o.isMesh) o.geometry.dispose(); });
    }
    this.chunks.clear();
  }
}
