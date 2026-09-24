// Мир: остров с ландшафтом, водой, ресурсами, памятниками (монументами) и ящиками.
import * as THREE from './three.module.min.js';
import {
  makePerlin, fbm, smoothstep, lerp, clamp, mulberry32, SpatialGrid, rayBox, rayCylY, raySphere,
} from './util.js';
import { Inventory, rollLoot } from './items.js';

export const WORLD = 440;
export const HALF = WORLD / 2;
export const SEG = 220;
export const STEP = WORLD / SEG;

// ---- Склейка простых геометрий в одну с вертексными цветами ----
const tmpColor = new THREE.Color();
export function mergeGeos(parts) {
  const pos = [], nor = [], col = [];
  for (const p of parts) {
    let g = p.geo.index ? p.geo.toNonIndexed() : p.geo.clone();
    if (p.matrix) g.applyMatrix4(p.matrix);
    g.computeVertexNormals();
    const pa = g.attributes.position.array;
    const na = g.attributes.normal.array;
    tmpColor.set(p.color);
    for (let i = 0; i < pa.length; i += 3) {
      pos.push(pa[i], pa[i + 1], pa[i + 2]);
      nor.push(na[i], na[i + 1], na[i + 2]);
      // лёгкий разброс оттенка по граням для «лоу-поли» вида
      const v = p.jitter ? 1 + (((i / 9) | 0) % 3 - 1) * p.jitter : 1;
      col.push(tmpColor.r * v, tmpColor.g * v, tmpColor.b * v);
    }
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  out.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  return out;
}

export function mat(pos = [0, 0, 0], rot = [0, 0, 0], scale = [1, 1, 1]) {
  const m = new THREE.Matrix4();
  m.compose(
    new THREE.Vector3(...pos),
    new THREE.Quaternion().setFromEuler(new THREE.Euler(...rot)),
    new THREE.Vector3(...scale),
  );
  return m;
}

const NODE = {
  tree: { amount: 150, give: 'wood', gather: 'tree', snd: 'wood' },
  stone: { amount: 200, give: 'stones', gather: 'ore', snd: 'stone' },
  metal: { amount: 120, give: 'metal_ore', bonus: 'stones', gather: 'ore', snd: 'stone' },
  sulfur: { amount: 120, give: 'sulfur_ore', gather: 'ore', snd: 'stone' },
  hemp: { pickup: 'cloth', n: [8, 12], label: 'Собрать коноплю' },
  mushroom: { pickup: 'mushroom', n: [1, 2], label: 'Собрать гриб' },
  barrel: { hp: 30 },
};
export { NODE };

const vertexMat = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
export { vertexMat };
const matCache = new Map();
export function colorMat(color) {
  let m = matCache.get(color);
  if (!m) {
    m = new THREE.MeshLambertMaterial({ color, flatShading: true });
    matCache.set(color, m);
  }
  return m;
}

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler(0, 0, 0, 'YXZ');
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();

export class World {
  constructor(scene, seed = 20240) {
    this.scene = scene;
    this.seed = seed;
    this.rng = mulberry32(seed);
    this.n1 = makePerlin(seed);
    this.n2 = makePerlin(seed + 11);
    this.n3 = makePerlin(seed + 23);
    this.colliders = new SpatialGrid(8);
    this.nodes = new SpatialGrid(10);
    this.nodeList = [];
    this.deadNodes = [];
    this.animNodes = new Set();
    this.crates = [];
    this.monuments = [];
    this.npcSpawns = [];
    this.time = 0;

    this.pickMonuments();
    this.buildHeightmap();
    this.buildTerrainMesh();
    this.buildWater();
    this.buildMonuments();
    this.spawnNodes();
  }

  // ---------- Высоты ----------
  rawHeight(x, z) {
    const d = Math.sqrt(x * x + z * z) / HALF;
    const hills = fbm(this.n1, x * 0.006, z * 0.006, 5) * 0.5 + 0.5;
    const ridge = 1 - Math.abs(fbm(this.n2, x * 0.012, z * 0.012, 3));
    let h = 3 + hills * 26 + ridge * ridge * 8;
    const coast = d + fbm(this.n3, x * 0.01 + 40, z * 0.01 + 40, 3) * 0.14;
    const fall = smoothstep(0.52, 0.93, coast);
    return lerp(h, -12, fall);
  }

  genHeight(x, z) {
    let h = this.rawHeight(x, z);
    for (const m of this.monuments) {
      const d = Math.hypot(x - m.x, z - m.z);
      const w = smoothstep(m.r * 1.7, m.r, d);
      if (w > 0) h = lerp(h, m.h, w);
    }
    return h;
  }

  pickMonuments() {
    const defs = [
      { name: 'Военная база', r: 30, npc: 4, kind: 'base' },
      { name: 'Заправка', r: 18, npc: 0, kind: 'gas' },
      { name: 'Свалка', r: 16, npc: 2, kind: 'junk' },
    ];
    const r = this.rng;
    for (const def of defs) {
      for (let tries = 0; tries < 1500; tries++) {
        const a = r() * Math.PI * 2;
        const dist = 35 + r() * 110;
        const x = Math.cos(a) * dist, z = Math.sin(a) * dist;
        const h = this.rawHeight(x, z);
        if (h < 3 || h > 20) continue;
        if (this.monuments.some((m) => Math.hypot(m.x - x, m.z - z) < m.r + def.r + (tries < 800 ? 40 : 20))) continue;
        // избегаем крутых склонов
        let ok = true;
        for (let i = 0; i < 8 && ok; i++) {
          const b = (i / 8) * Math.PI * 2;
          const hh = this.rawHeight(x + Math.cos(b) * def.r, z + Math.sin(b) * def.r);
          if (Math.abs(hh - h) > 7 || hh < 1.5) ok = false;
        }
        if (!ok) continue;
        this.monuments.push({ ...def, x, z, h });
        break;
      }
    }
  }

  buildHeightmap() {
    const N = SEG + 1;
    this.H = new Float32Array(N * N);
    for (let iz = 0; iz < N; iz++) {
      for (let ix = 0; ix < N; ix++) {
        this.H[iz * N + ix] = this.genHeight(-HALF + ix * STEP, -HALF + iz * STEP);
      }
    }
  }

  getHeight(x, z) {
    const fx = (x + HALF) / STEP, fz = (z + HALF) / STEP;
    const ix = Math.floor(fx), iz = Math.floor(fz);
    if (ix < 0 || iz < 0 || ix >= SEG || iz >= SEG) return -14;
    const tx = fx - ix, tz = fz - iz;
    const N = SEG + 1, H = this.H;
    const a = H[iz * N + ix], b = H[(iz + 1) * N + ix], c = H[(iz + 1) * N + ix + 1], d = H[iz * N + ix + 1];
    if (tx + tz <= 1) return a + (d - a) * tx + (b - a) * tz;
    return c + (b - c) * (1 - tx) + (d - c) * (1 - tz);
  }

  slope(x, z) {
    const e = 1;
    const dx = this.getHeight(x + e, z) - this.getHeight(x - e, z);
    const dz = this.getHeight(x, z + e) - this.getHeight(x, z - e);
    return Math.sqrt(dx * dx + dz * dz) / (2 * e);
  }

  // Марш луча по карте высот.
  raycastTerrain(o, d, maxT) {
    let prevT = 0;
    const step = maxT > 20 ? 0.5 : 0.2;
    for (let t = step; t <= maxT + step; t += step) {
      const tt = Math.min(t, maxT);
      const y = o.y + d.y * tt;
      const h = this.getHeight(o.x + d.x * tt, o.z + d.z * tt);
      if (y <= h) {
        let lo = prevT, hi = tt;
        for (let i = 0; i < 8; i++) {
          const mid = (lo + hi) / 2;
          const my = o.y + d.y * mid;
          if (my <= this.getHeight(o.x + d.x * mid, o.z + d.z * mid)) hi = mid;
          else lo = mid;
        }
        return hi;
      }
      prevT = tt;
      if (tt >= maxT) break;
    }
    return -1;
  }

  terrainColor(x, z, h, s) {
    const v = this.n2(x * 0.05, z * 0.05) * 0.5 + 0.5;
    const c = new THREE.Color();
    if (h < 0) c.setHex(0xb59f73);
    else if (h < 1.6) c.setHex(0xd9c796);
    else if (h < 2.4) c.setHex(0xd9c796).lerp(new THREE.Color(0x6f9a45), (h - 1.6) / 0.8);
    else {
      c.setHex(0x5f8f3c).lerp(new THREE.Color(0x7aa34c), v);
      const dry = smoothstep(14, 24, h);
      c.lerp(new THREE.Color(0x8a8f55), dry * 0.6);
    }
    const rock = Math.max(smoothstep(0.55, 0.85, s), smoothstep(26, 32, h));
    if (rock > 0 && h > 1) c.lerp(new THREE.Color(0x7e7a72), rock);
    for (const m of this.monuments) {
      const d = Math.hypot(x - m.x, z - m.z);
      const w = smoothstep(m.r * 1.1, m.r * 0.8, d);
      if (w > 0) c.lerp(new THREE.Color(m.kind === 'junk' ? 0x7a6a55 : 0x8a877e), w * 0.85);
    }
    return c;
  }

  buildTerrainMesh() {
    const N = SEG + 1;
    const pos = new Float32Array(N * N * 3);
    const col = new Float32Array(N * N * 3);
    for (let iz = 0; iz < N; iz++) {
      for (let ix = 0; ix < N; ix++) {
        const i = iz * N + ix;
        const x = -HALF + ix * STEP, z = -HALF + iz * STEP;
        const h = this.H[i];
        pos[i * 3] = x;
        pos[i * 3 + 1] = h;
        pos[i * 3 + 2] = z;
        const c = this.terrainColor(x, z, h, this.slope(x, z));
        col[i * 3] = c.r;
        col[i * 3 + 1] = c.g;
        col[i * 3 + 2] = c.b;
      }
    }
    const idx = [];
    for (let iz = 0; iz < SEG; iz++) {
      for (let ix = 0; ix < SEG; ix++) {
        const a = iz * N + ix, b = (iz + 1) * N + ix, c = (iz + 1) * N + ix + 1, d = iz * N + ix + 1;
        idx.push(a, b, d, b, c, d);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    this.terrain = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
    this.terrain.receiveShadow = true;
    this.scene.add(this.terrain);
  }

  buildWater() {
    const geo = new THREE.PlaneGeometry(3000, 3000, 1, 1);
    geo.rotateX(-Math.PI / 2);
    this.waterMat = new THREE.MeshPhongMaterial({
      color: 0x2a78a0, transparent: true, opacity: 0.8, shininess: 90, specular: 0x6688aa, depthWrite: false,
    });
    this.water = new THREE.Mesh(geo, this.waterMat);
    this.water.renderOrder = 1;
    this.scene.add(this.water);
    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(3000, 3000).rotateX(-Math.PI / 2),
      new THREE.MeshLambertMaterial({ color: 0x9c8a62 }),
    );
    floor.position.y = -14;
    this.scene.add(floor);
  }

  // ---------- Коллайдеры ----------
  addCollider(minX, minY, minZ, maxX, maxY, maxZ, ref = null) {
    const c = { minX, minY, minZ, maxX, maxY, maxZ, ref };
    this.colliders.add(c, minX, minZ, maxX, maxZ);
    return c;
  }

  removeCollider(c) {
    if (c) this.colliders.remove(c);
  }

  addStatic(cx, cy, cz, sx, sy, sz, color, collide = true, rotY = 0) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), colorMat(color));
    mesh.position.set(cx, cy, cz);
    mesh.rotation.y = rotY;
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.scene.add(mesh);
    if (collide) {
      const ex = rotY ? sz : sx, ez = rotY ? sx : sz;
      this.addCollider(cx - ex / 2, cy - sy / 2, cz - ez / 2, cx + ex / 2, cy + sy / 2, cz + ez / 2, { kind: 'static' });
    }
    return mesh;
  }

  // Бетонная коробка с дверным проёмом (side: 0=+z,1=-z,2=+x,3=-x)
  addRoom(x, y, z, w, d, h, color, doorSide = 0) {
    const t = 0.4, dw = 1.6, dh = 2.4;
    const wall = (cx, cz, sx, sz, hasDoor, alongX) => {
      if (!hasDoor) { this.addStatic(cx, y + h / 2, cz, sx, h, sz, color); return; }
      const len = alongX ? sx : sz;
      const side = (len - dw) / 2;
      if (alongX) {
        this.addStatic(cx - dw / 2 - side / 2, y + h / 2, cz, side, h, sz, color);
        this.addStatic(cx + dw / 2 + side / 2, y + h / 2, cz, side, h, sz, color);
        this.addStatic(cx, y + dh + (h - dh) / 2, cz, dw, h - dh, sz, color);
      } else {
        this.addStatic(cx, y + h / 2, cz - dw / 2 - side / 2, sx, h, side, color);
        this.addStatic(cx, y + h / 2, cz + dw / 2 + side / 2, sx, h, side, color);
        this.addStatic(cx, y + dh + (h - dh) / 2, cz, sx, h - dh, dw, color);
      }
    };
    wall(x, z + d / 2 - t / 2, w, t, doorSide === 0, true);
    wall(x, z - d / 2 + t / 2, w, t, doorSide === 1, true);
    wall(x + w / 2 - t / 2, z, t, d - 2 * t, doorSide === 2, false);
    wall(x - w / 2 + t / 2, z, t, d - 2 * t, doorSide === 3, false);
    this.addStatic(x, y + h + 0.15, z, w + 0.2, 0.3, d + 0.2, 0x6f6e68);
  }

  addCrate(x, y, z, loot) {
    const military = loot === 'military';
    const sx = military ? 1.4 : 1.0, sy = military ? 0.6 : 0.8, sz = military ? 0.7 : 0.8;
    const geo = mergeGeos([
      { geo: new THREE.BoxGeometry(sx, sy, sz), color: military ? 0x3f5a2e : 0x8a6236, matrix: mat([0, sy / 2, 0]) },
      { geo: new THREE.BoxGeometry(sx + 0.04, 0.08, sz + 0.04), color: military ? 0x2d3f22 : 0x5b3e21, matrix: mat([0, sy - 0.1, 0]) },
      { geo: new THREE.BoxGeometry(0.08, sy * 0.9, sz + 0.03), color: military ? 0x2d3f22 : 0x5b3e21, matrix: mat([-sx / 3, sy / 2, 0]) },
      { geo: new THREE.BoxGeometry(0.08, sy * 0.9, sz + 0.03), color: military ? 0x2d3f22 : 0x5b3e21, matrix: mat([sx / 3, sy / 2, 0]) },
    ]);
    const mesh = new THREE.Mesh(geo, vertexMat);
    mesh.position.set(x, y, z);
    mesh.rotation.y = Math.floor(this.rng() * 4) * Math.PI / 2;
    mesh.castShadow = true;
    this.scene.add(mesh);
    const crate = {
      kind: 'crate', loot, x, y, z, mesh, inv: new Inventory(12), respawnAt: 0,
      hx: Math.max(sx, sz) / 2, hy: sy,
      name: military ? 'Военный ящик' : 'Ящик',
    };
    crate.col = this.addCollider(x - crate.hx, y, z - crate.hx, x + crate.hx, y + sy, z + crate.hx, crate);
    this.fillCrate(crate);
    this.crates.push(crate);
    return crate;
  }

  fillCrate(c) {
    c.inv.slots.fill(null);
    for (const it of rollLoot(c.loot)) c.inv.add(it.id, it.n);
    c.mesh.visible = true;
    c.active = true;
    if (!c.col) c.col = this.addCollider(c.x - c.hx, c.y, c.z - c.hx, c.x + c.hx, c.y + c.hy, c.z + c.hx, c);
  }

  closeCrate(c) {
    if (c.inv.isEmpty()) {
      c.active = false;
      c.mesh.visible = false;
      this.removeCollider(c.col);
      c.col = null;
      c.respawnAt = this.time + 240;
    }
  }

  buildMonuments() {
    for (const m of this.monuments) {
      const y = m.h;
      if (m.kind === 'base') {
        // периметр с воротами
        const s = 22, c = 0x8f8e86, t = 0.6, hh = 3.2;
        const seg = (x1, z1, x2, z2) => {
          const cx = (x1 + x2) / 2, cz = (z1 + z2) / 2;
          this.addStatic(m.x + cx, y + hh / 2, m.z + cz, Math.abs(x2 - x1) || t, hh, Math.abs(z2 - z1) || t, c);
        };
        seg(-s, -s, -4, -s); seg(4, -s, s, -s);
        seg(-s, s, -4, s); seg(4, s, s, s);
        seg(-s, -s, -s, s);
        seg(s, -s, s, -4); seg(s, 4, s, s);
        // здания
        this.addRoom(m.x - 11, y, m.z - 10, 10, 7, 3.6, 0x9a998f, 0);
        this.addRoom(m.x + 10, y, m.z + 9, 8, 9, 3.6, 0x9a998f, 3);
        // контейнеры
        this.addStatic(m.x - 12, y + 1.3, m.z + 10, 6, 2.6, 2.4, 0x9b3b2b);
        this.addStatic(m.x - 12, y + 3.9, m.z + 10, 6, 2.6, 2.4, 0x2f5d8a);
        this.addStatic(m.x - 3, y + 1.3, m.z + 14, 2.4, 2.6, 6, 0x3f6b3a);
        this.addStatic(m.x + 12, y + 1.3, m.z - 12, 6, 2.6, 2.4, 0x2f5d8a);
        // радарная вышка
        const tx = m.x + 3, tz = m.z - 4;
        for (const [dx, dz] of [[-1.4, -1.4], [1.4, -1.4], [-1.4, 1.4], [1.4, 1.4]]) {
          this.addStatic(tx + dx, y + 5, tz + dz, 0.3, 10, 0.3, 0x5c5a55);
        }
        this.addStatic(tx, y + 10.1, tz, 4, 0.3, 4, 0x5c5a55);
        const dish = new THREE.Mesh(
          new THREE.SphereGeometry(2.2, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2.5),
          new THREE.MeshLambertMaterial({ color: 0xd8d8d0, side: THREE.DoubleSide, flatShading: true }),
        );
        dish.position.set(tx, y + 11.6, tz);
        dish.rotation.x = Math.PI * 0.75;
        this.scene.add(dish);
        this.dish = dish;
        // ящики
        this.addCrate(m.x - 13, y, m.z - 11, 'military');
        this.addCrate(m.x - 9, y, m.z - 12, 'crate');
        this.addCrate(m.x + 11, y, m.z + 11, 'military');
        this.addCrate(m.x + 8.5, y, m.z + 7, 'crate');
        this.addCrate(m.x + 3, y + 10.25, m.z - 4, 'military');
        this.addCrate(m.x - 6, y, m.z + 12, 'crate');
        // лестница на вышку — ступени
        for (let i = 0; i < 20; i++) {
          this.addStatic(tx + 2.2 + (i % 2) * 0.0, y + 0.25 + i * 0.5, tz - 3 + i * 0.3, 1.2, 0.2, 0.3, 0x5c5a55);
        }
      } else if (m.kind === 'gas') {
        for (const [dx, dz] of [[-4, -3], [4, -3], [-4, 3], [4, 3]]) {
          this.addStatic(m.x + dx, y + 2, m.z + dz, 0.4, 4, 0.4, 0xc9c9c0);
        }
        this.addStatic(m.x, y + 4.1, m.z, 10, 0.3, 7.5, 0xb03a2e, false);
        this.addStatic(m.x - 1.5, y + 0.6, m.z, 0.6, 1.2, 0.8, 0xd04030);
        this.addStatic(m.x + 1.5, y + 0.6, m.z, 0.6, 1.2, 0.8, 0xd04030);
        this.addRoom(m.x, y, m.z + 10, 9, 6, 3.4, 0xd8d3c0, 1);
        this.addCrate(m.x - 2.5, y, m.z + 11.5, 'crate');
        this.addCrate(m.x + 2.5, y, m.z + 11.5, 'crate');
        this.addCrate(m.x + 7, y, m.z - 6, 'crate');
      } else if (m.kind === 'junk') {
        const r = this.rng;
        const cols = [0x6d4a35, 0x5a5550, 0x7b3b2b, 0x3f5063, 0x807360];
        for (let i = 0; i < 14; i++) {
          const a = r() * Math.PI * 2, d = 3 + r() * 11;
          const sx = 1.5 + r() * 3, sy = 0.8 + r() * 2.2, sz = 1.5 + r() * 3;
          this.addStatic(m.x + Math.cos(a) * d, y + sy / 2, m.z + Math.sin(a) * d, sx, sy, sz, cols[i % cols.length]);
        }
        this.addCrate(m.x, y, m.z, 'crate');
        this.addCrate(m.x + 12, y, m.z + 2, 'crate');
        this.addCrate(m.x - 4, y, m.z - 12, 'military');
      }
      for (let i = 0; i < m.npc; i++) {
        const a = (i / m.npc) * Math.PI * 2;
        this.npcSpawns.push({ x: m.x + Math.cos(a) * m.r * 0.5, z: m.z + Math.sin(a) * m.r * 0.5, home: m });
      }
    }
    // придорожные ящики
    for (let i = 0; i < 14; i++) {
      const p = this.randomLandPoint(2, 20, 25);
      if (p) this.addCrate(p.x, this.getHeight(p.x, p.z) - 0.05, p.z, 'crate');
    }
  }

  nearMonument(x, z, pad = 6) {
    return this.monuments.some((m) => Math.hypot(x - m.x, z - m.z) < m.r + pad);
  }

  randomLandPoint(minH, maxH, pad = 8, maxSlope = 0.5) {
    const r = this.rng;
    for (let i = 0; i < 200; i++) {
      const x = (r() * 2 - 1) * HALF * 0.9, z = (r() * 2 - 1) * HALF * 0.9;
      const h = this.getHeight(x, z);
      if (h < minH || h > maxH) continue;
      if (this.slope(x, z) > maxSlope) continue;
      if (this.nearMonument(x, z, pad)) continue;
      return { x, z };
    }
    return null;
  }

  randomBeachPoint() {
    for (let i = 0; i < 100; i++) {
      const a = Math.random() * Math.PI * 2;
      const dx = Math.cos(a), dz = Math.sin(a);
      let last = null;
      for (let d = 0; d < HALF; d += 2) {
        const h = this.getHeight(dx * d, dz * d);
        if (h > 1.2) last = { x: dx * d, z: dz * d };
        if (h < 0.3) break;
      }
      if (last && !this.nearMonument(last.x, last.z, 10)) return last;
    }
    return { x: 0, z: 0 };
  }

  // ---------- Ресурсы ----------
  spawnNodes() {
    const r = this.rng;
    const pine = mergeGeos([
      { geo: new THREE.CylinderGeometry(0.18, 0.3, 2.4, 6), color: 0x5a3d25, matrix: mat([0, 1.2, 0]) },
      { geo: new THREE.ConeGeometry(1.7, 2.6, 7), color: 0x2f5a2c, matrix: mat([0, 2.9, 0]), jitter: 0.08 },
      { geo: new THREE.ConeGeometry(1.3, 2.3, 7), color: 0x356331, matrix: mat([0, 4.0, 0]), jitter: 0.08 },
      { geo: new THREE.ConeGeometry(0.85, 1.9, 7), color: 0x3b6b35, matrix: mat([0, 5.0, 0]), jitter: 0.08 },
    ]);
    const oak = mergeGeos([
      { geo: new THREE.CylinderGeometry(0.22, 0.34, 2.8, 6), color: 0x5e4128, matrix: mat([0, 1.4, 0]) },
      { geo: new THREE.IcosahedronGeometry(1.8, 0), color: 0x4f7f33, matrix: mat([0, 3.8, 0], [0.3, 0.5, 0], [1, 0.85, 1]), jitter: 0.1 },
      { geo: new THREE.IcosahedronGeometry(1.2, 0), color: 0x5a8c3a, matrix: mat([0.7, 4.6, 0.3], [0.1, 0.2, 0.4]), jitter: 0.1 },
      { geo: new THREE.IcosahedronGeometry(1.1, 0), color: 0x4a7a30, matrix: mat([-0.8, 4.2, -0.4], [0.5, 0.1, 0.2]), jitter: 0.1 },
    ]);
    const rockGeo = (c1, c2, spots) => {
      const g = new THREE.IcosahedronGeometry(1, 0);
      const parts = [{ geo: g, color: c1, jitter: 0.12 }];
      for (let i = 0; i < spots; i++) {
        const a = (i / spots) * Math.PI * 2;
        parts.push({
          geo: new THREE.IcosahedronGeometry(0.32, 0), color: c2,
          matrix: mat([Math.cos(a) * 0.72, 0.35 + (i % 2) * 0.3, Math.sin(a) * 0.72]),
        });
      }
      return mergeGeos(parts);
    };
    const hempGeo = mergeGeos([
      { geo: new THREE.ConeGeometry(0.25, 1.2, 5), color: 0x5f9a3a, matrix: mat([0, 0.6, 0]) },
      { geo: new THREE.ConeGeometry(0.2, 1.0, 5), color: 0x6fae45, matrix: mat([0.25, 0.5, 0.1], [0, 0, 0.3]) },
      { geo: new THREE.ConeGeometry(0.2, 1.0, 5), color: 0x6fae45, matrix: mat([-0.2, 0.5, -0.15], [0.2, 0, -0.3]) },
      { geo: new THREE.SphereGeometry(0.12, 5, 4), color: 0xb9d06b, matrix: mat([0, 1.25, 0]) },
    ]);
    const mushGeo = mergeGeos([
      { geo: new THREE.CylinderGeometry(0.05, 0.07, 0.25, 5), color: 0xeae2cf, matrix: mat([0, 0.12, 0]) },
      { geo: new THREE.ConeGeometry(0.2, 0.15, 7), color: 0xb8342a, matrix: mat([0, 0.3, 0]) },
      { geo: new THREE.CylinderGeometry(0.04, 0.06, 0.18, 5), color: 0xeae2cf, matrix: mat([0.18, 0.09, 0.1]) },
      { geo: new THREE.ConeGeometry(0.14, 0.11, 7), color: 0xb8342a, matrix: mat([0.18, 0.22, 0.1]) },
    ]);
    const barrelGeo = mergeGeos([
      { geo: new THREE.CylinderGeometry(0.42, 0.42, 1.1, 10), color: 0xffffff, matrix: mat([0, 0.55, 0]) },
      { geo: new THREE.CylinderGeometry(0.44, 0.44, 0.08, 10), color: 0x555555, matrix: mat([0, 0.3, 0]) },
      { geo: new THREE.CylinderGeometry(0.44, 0.44, 0.08, 10), color: 0x555555, matrix: mat([0, 0.8, 0]) },
    ]);
    const bushGeo = mergeGeos([
      { geo: new THREE.IcosahedronGeometry(0.7, 0), color: 0x46702c, matrix: mat([0, 0.4, 0], [0, 0, 0], [1, 0.7, 1]), jitter: 0.12 },
      { geo: new THREE.IcosahedronGeometry(0.5, 0), color: 0x527d33, matrix: mat([0.4, 0.5, 0.2]), jitter: 0.12 },
    ]);

    const plan = [];
    const tryPlace = (kind, count, test) => {
      let placed = 0;
      for (let i = 0; i < count * 8 && placed < count; i++) {
        const x = (r() * 2 - 1) * HALF * 0.92, z = (r() * 2 - 1) * HALF * 0.92;
        const h = this.getHeight(x, z);
        if (!test(x, z, h)) continue;
        if (this.nearMonument(x, z, kind === 'barrel' ? -2 : 5)) continue;
        plan.push({ kind, x, z, y: h });
        placed++;
      }
    };
    const forest = (x, z) => this.n3(x * 0.015 + 7, z * 0.015 + 7);
    tryPlace('pine', 520, (x, z, h) => h > 6 && h < 27 && this.slope(x, z) < 0.7 && forest(x, z) > -0.05);
    tryPlace('oak', 300, (x, z, h) => h > 2.5 && h < 16 && this.slope(x, z) < 0.5 && forest(x, z) > -0.2);
    tryPlace('stone', 140, (x, z, h) => h > 1 && this.slope(x, z) < 0.9);
    tryPlace('metal', 90, (x, z, h) => h > 5 && this.slope(x, z) < 0.9);
    tryPlace('sulfur', 70, (x, z, h) => h > 9 && this.slope(x, z) < 0.9);
    tryPlace('hemp', 170, (x, z, h) => h > 2.2 && h < 18 && this.slope(x, z) < 0.45);
    tryPlace('mushroom', 100, (x, z, h) => h > 3 && h < 20 && forest(x, z) > 0);
    tryPlace('bush', 400, (x, z, h) => h > 2.3 && h < 22 && this.slope(x, z) < 0.6);
    tryPlace('barrel', 45, (x, z, h) => h > 1.5 && h < 18 && this.slope(x, z) < 0.3);
    // бочки у монументов
    for (const m of this.monuments) {
      for (let i = 0; i < 7; i++) {
        const a = r() * Math.PI * 2, d = m.r * (0.3 + r() * 0.6);
        const x = m.x + Math.cos(a) * d, z = m.z + Math.sin(a) * d;
        if (this.colliders.query(x - 0.6, z - 0.6, x + 0.6, z + 0.6).length) continue;
        plan.push({ kind: 'barrel', x, z, y: this.getHeight(x, z) });
      }
    }

    const count = {};
    for (const p of plan) count[p.kind] = (count[p.kind] || 0) + 1;
    const geos = {
      pine, oak, hemp: hempGeo, mushroom: mushGeo, barrel: barrelGeo, bush: bushGeo,
      stone: rockGeo(0x8a8680, 0x6f6b66, 0),
      metal: rockGeo(0x7c7873, 0xa0643a, 5),
      sulfur: rockGeo(0x8a8474, 0xd8c23a, 5),
    };
    this.inst = {};
    for (const k in count) {
      const im = new THREE.InstancedMesh(geos[k], vertexMat, count[k]);
      im.castShadow = k === 'pine' || k === 'oak' || k === 'stone' || k === 'metal' || k === 'sulfur';
      im.receiveShadow = true;
      im.frustumCulled = false;
      im.count = count[k];
      this.inst[k] = im;
      this.scene.add(im);
      count[k] = 0;
    }
    const barrelColors = [new THREE.Color(0x2f5c9a), new THREE.Color(0xa33a2a), new THREE.Color(0x4d6b35)];
    for (const p of plan) {
      const im = this.inst[p.kind];
      const idx = count[p.kind]++;
      const isTree = p.kind === 'pine' || p.kind === 'oak';
      const kind = isTree ? 'tree' : p.kind;
      const node = {
        kind, sub: p.kind, x: p.x, y: p.y, z: p.z, im, idx, rot: r() * Math.PI * 2,
        s: 1, sx: 1, sy: 1, sz: 1, alive: true, amount: 0, max: 0, shake: 0, fall: -1,
      };
      if (isTree) {
        node.s = 0.8 + r() * 0.5;
        node.r = 0.35 * node.s; node.h = 3.2 * node.s; node.col = 0.35 * node.s;
      } else if (kind === 'stone' || kind === 'metal' || kind === 'sulfur') {
        node.s = 1;
        node.sx = 0.9 + r() * 0.5; node.sy = 0.7 + r() * 0.4; node.sz = 0.9 + r() * 0.5;
        node.y -= 0.25;
        node.r = 1.0; node.col = 0.9;
      } else if (kind === 'barrel') {
        node.r = 0.45; node.h = 1.1; node.col = 0.42; node.hp = NODE.barrel.hp;
        im.setColorAt(idx, barrelColors[Math.floor(r() * 3)]);
      } else if (kind === 'hemp') {
        node.r = 0.4; node.h = 1.3;
      } else if (kind === 'mushroom') {
        node.r = 0.35; node.h = 0.4;
      } else if (kind === 'bush') {
        node.s = 0.8 + r() * 0.6;
      }
      if (NODE[kind] && NODE[kind].amount) node.amount = node.max = NODE[kind].amount;
      this.setNodeMatrix(node);
      if (kind !== 'bush') {
        this.nodeList.push(node);
        const rr = Math.max(node.r || 0.5, 1);
        this.nodes.add(node, node.x - rr, node.z - rr, node.x + rr, node.z + rr);
      }
    }
    for (const k in this.inst) {
      this.inst[k].instanceMatrix.needsUpdate = true;
      if (this.inst[k].instanceColor) this.inst[k].instanceColor.needsUpdate = true;
    }
  }

  setNodeMatrix(n) {
    if (!n.alive && n.fall < 0) {
      _s.set(0, 0, 0);
    } else if (n.kind === 'stone' || n.kind === 'metal' || n.kind === 'sulfur') {
      const f = 0.45 + 0.55 * (n.amount / n.max);
      _s.set(n.sx * f, n.sy * f, n.sz * f);
    } else {
      _s.set(n.s, n.s, n.s);
    }
    let tilt = 0;
    if (n.fall >= 0) tilt = Math.min(1, n.fall) ** 2 * 1.5;
    else if (n.shake > 0) tilt = Math.sin(this.time * 45) * n.shake * 0.12;
    _e.set(tilt, n.rot, 0, 'YXZ');
    _q.setFromEuler(_e);
    _p.set(n.x, n.y, n.z);
    _m.compose(_p, _q, _s);
    n.im.setMatrixAt(n.idx, _m);
    n.im.instanceMatrix.needsUpdate = true;
  }

  killNode(n, respawn) {
    n.alive = false;
    n.respawnAt = this.time + respawn;
    this.deadNodes.push(n);
    this.setNodeMatrix(n);
  }

  update(dt, playerPos) {
    this.time += dt;
    for (const n of this.animNodes) {
      if (n.fall >= 0) {
        n.fall += dt * 0.9;
        if (n.fall > 1.3) { n.fall = -1; this.animNodes.delete(n); }
      } else {
        n.shake -= dt * 2;
        if (n.shake <= 0) { n.shake = 0; this.animNodes.delete(n); }
      }
      this.setNodeMatrix(n);
    }
    if (this.deadNodes.length) {
      for (let i = this.deadNodes.length - 1; i >= 0; i--) {
        const n = this.deadNodes[i];
        if (this.time < n.respawnAt) continue;
        if (Math.hypot(n.x - playerPos.x, n.z - playerPos.z) < 25) { n.respawnAt = this.time + 10; continue; }
        n.alive = true;
        n.amount = n.max;
        if (n.kind === 'barrel') n.hp = NODE.barrel.hp;
        this.setNodeMatrix(n);
        this.deadNodes.splice(i, 1);
      }
    }
    for (const c of this.crates) {
      if (!c.active && this.time > c.respawnAt && Math.hypot(c.x - playerPos.x, c.z - playerPos.z) > 25) this.fillCrate(c);
    }
    if (this.dish) this.dish.rotation.z += dt * 0.4;
  }

  // ---------- Запросы ----------
  // Ближайший ресурс/бочка/ящик на луче.
  raycastNodes(o, d, maxT, best) {
    const ex = o.x + d.x * maxT, ez = o.z + d.z * maxT;
    const list = this.nodes.query(Math.min(o.x, ex) - 2, Math.min(o.z, ez) - 2, Math.max(o.x, ex) + 2, Math.max(o.z, ez) + 2);
    for (const n of list) {
      if (!n.alive) continue;
      let t = -1;
      if (n.kind === 'stone' || n.kind === 'metal' || n.kind === 'sulfur') {
        const f = 0.45 + 0.55 * (n.amount / n.max);
        t = raySphere(o, d, n.x, n.y + 0.4 * f, n.z, n.r * f * Math.max(n.sx, n.sz), best.t);
      } else {
        t = rayCylY(o, d, n.x, n.z, n.r, n.y - 0.1, n.y + n.h, best.t);
      }
      if (t >= 0 && t < best.t) { best.t = t; best.kind = 'node'; best.obj = n; }
    }
    for (const c of this.crates) {
      if (!c.active) continue;
      if (Math.abs(c.x - o.x) > maxT + 2 || Math.abs(c.z - o.z) > maxT + 2) continue;
      const h = rayBox(o, d, c.x - c.hx, c.y, c.z - c.hx, c.x + c.hx, c.y + c.hy, c.z + c.hx, best.t);
      if (h && h.t < best.t) { best.t = h.t; best.kind = 'crate'; best.obj = c; }
    }
    return best;
  }

  renderMap(size = 512) {
    const cv = document.createElement('canvas');
    cv.width = cv.height = size;
    const ctx = cv.getContext('2d');
    const img = ctx.createImageData(size, size);
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const wx = -HALF + (x / size) * WORLD, wz = -HALF + (y / size) * WORLD;
        const h = this.getHeight(wx, wz);
        let c;
        if (h < 0) {
          const dpt = clamp(-h / 12, 0, 1);
          c = [lerp(70, 25, dpt), lerp(150, 70, dpt), lerp(180, 120, dpt)];
        } else {
          const col = this.terrainColor(wx, wz, h, this.slope(wx, wz));
          col.convertLinearToSRGB();
          const shade = 0.85 + clamp((this.getHeight(wx - 2, wz - 2) - h) * -0.08, -0.15, 0.25);
          c = [col.r * 255 * shade, col.g * 255 * shade, col.b * 255 * shade];
        }
        const i = (y * size + x) * 4;
        img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2]; img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    return cv;
  }
}
