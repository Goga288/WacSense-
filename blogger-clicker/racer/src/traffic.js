// Поток машин: попутное движение, перестроения с поворотниками, дистанция.
import * as THREE from './three.module.min.js';
import { buildCar } from './car.js';
import { LANES } from './city.js';

const COLORS = [0xd9dcdf, 0x1c1f24, 0x8a1e1e, 0x1d3f7a, 0x6b7076, 0x2f5d3a, 0xe8e2d2, 0x5a3a24, 0x9aa5b0];
const TYPES = [
  ['sedan', 5], ['hatch', 3], ['suv', 3], ['van', 1.2], ['bus', 0.7], ['taxi', 1.2],
];

// Склейка всех деталей машины трафика в несколько мешей по материалам:
// ~90 деталей → ~20 вызовов отрисовки на машину.
function flatten(root) {
  root.updateMatrixWorld(true);
  const inv = root.matrixWorld.clone().invert();
  const byMat = new Map();
  root.traverse((o) => {
    if (!o.isMesh) return;
    let a = byMat.get(o.material);
    if (!a) byMat.set(o.material, (a = []));
    a.push({ geo: o.geometry, m: new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld) });
  });
  const out = new THREE.Group();
  for (const [mat, arr] of byMat) {
    let n = 0;
    const parts = arr.map((p) => {
      const g = (p.geo.index ? p.geo.toNonIndexed() : p.geo.clone()).applyMatrix4(p.m);
      n += g.attributes.position.count;
      return g;
    });
    const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3), uv = new Float32Array(n * 2);
    let o = 0;
    for (const g of parts) {
      const c = g.attributes.position.count;
      pos.set(g.attributes.position.array, o * 3);
      nor.set(g.attributes.normal.array, o * 3);
      if (g.attributes.uv) uv.set(g.attributes.uv.array, o * 2);
      o += c;
      g.dispose();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    geo.computeBoundingSphere();
    const m = new THREE.Mesh(geo, mat);
    m.castShadow = !mat.transparent;
    m.receiveShadow = true;
    out.add(m);
  }
  return out;
}

export class Traffic {
  constructor(scene, M) {
    this.scene = scene;
    this.M = M;
    this.cars = [];
    this.templates = [];
    let seed = 1;
    for (const [kind, w] of TYPES) {
      const n = kind === 'sedan' ? 4 : kind === 'hatch' || kind === 'suv' ? 3 : 1;
      for (let k = 0; k < n; k++) {
        const real = kind === 'taxi' ? 'sedan' : kind;
        const color = kind === 'taxi' ? 0xf2c21b : kind === 'bus' ? 0xe8d34a : kind === 'van' ? 0xf0f0ee : COLORS[(seed * 3) % COLORS.length];
        const car = buildCar(real, color, M, { plateSeed: seed++ });
        if (kind === 'taxi') {
          const sign = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.16, 0.22), new THREE.MeshStandardMaterial({ color: 0xffe066, emissive: 0xffc400, emissiveIntensity: 0.6 }));
          sign.position.set(0, car.spec.H + 0.1, 0.2);
          car.root.add(sign);
        }
        car.root = flatten(car.root);
        this.templates.push({ car, kind: real, weight: w / n });
      }
    }
    this.totalW = this.templates.reduce((a, t) => a + t.weight, 0);
  }

  pickTemplate() {
    let r = Math.random() * this.totalW;
    for (const t of this.templates) { r -= t.weight; if (r <= 0) return t; }
    return this.templates[0];
  }

  spawn(z, lane) {
    const t = this.pickTemplate();
    const obj = t.car.root.clone(true);
    // у каждой машины свои поворотники
    const blinkL = [], blinkR = [];
    const matL = t.car.lights.blinkL[0].material.clone(), matR = t.car.lights.blinkR[0].material.clone();
    obj.traverse((o) => {
      if (!o.isMesh) return;
      if (o.material === t.car.lights.blinkL[0].material) { o.material = matL; blinkL.push(o); }
      else if (o.material === t.car.lights.blinkR[0].material) { o.material = matR; blinkR.push(o); }
    });
    const spd = t.kind === 'bus' ? 11 + Math.random() * 4 : 13 + Math.random() * 14;
    const c = {
      obj, kind: t.kind, x: LANES[lane], z, lane, target: lane, speed: spd, want: spd,
      len: t.car.spec.L, width: t.car.spec.W, matL, matR, blinkT: 0, changeT: 6 + Math.random() * 12, passed: false,
    };
    obj.position.set(c.x, 0, z);
    this.scene.add(obj);
    this.cars.push(c);
    return c;
  }

  gapInLane(lane, z, ignore) {
    let best = Infinity;
    for (const c of this.cars) {
      if (c === ignore) continue;
      if (c.lane !== lane && c.target !== lane) continue;
      best = Math.min(best, Math.abs(c.z - z) - c.len / 2);
    }
    return best;
  }

  update(dt, player, dist) {
    const pz = player.z;
    // появление впереди
    const want = Math.min(34, 14 + Math.floor(dist / 400));
    let tries = 0;
    while (this.cars.length < want && tries++ < 6) {
      const lane = Math.floor(Math.random() * LANES.length);
      const z = pz - 160 - Math.random() * 260;
      if (this.gapInLane(lane, z) > 16) this.spawn(z, lane);
    }
    const t = performance.now() / 1000;
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i];
      // дистанция до машины впереди в своей полосе (включая игрока)
      let ahead = Infinity, aheadSpeed = c.want;
      for (const o of this.cars) {
        if (o === c || (o.lane !== c.lane && o.target !== c.lane)) continue;
        const d = c.z - o.z - (c.len + o.len) / 2;
        if (d > 0 && d < ahead) { ahead = d; aheadSpeed = o.speed; }
      }
      if (Math.abs(player.x - c.x) < 2.2) {
        const d = c.z - pz - (c.len + player.len) / 2;
        if (d > 0 && d < ahead) { ahead = d; aheadSpeed = player.speed; }
      }
      let target = c.want;
      if (ahead < 25) target = Math.min(target, aheadSpeed * (ahead < 8 ? 0.8 : 1));
      c.speed += Math.max(-8 * dt, Math.min(3 * dt, target - c.speed));
      c.speed = Math.max(0, c.speed);
      c.z -= c.speed * dt;
      // перестроения
      c.changeT -= dt;
      if (c.changeT <= 0 && c.lane === c.target && c.kind !== 'bus') {
        c.changeT = 7 + Math.random() * 14;
        const dir = Math.random() < 0.5 ? -1 : 1;
        const nl = c.lane + dir;
        const safeFromPlayer = Math.abs(c.z - pz) > 30 || Math.abs(LANES[Math.max(0, Math.min(3, nl))] - player.x) > 2.5;
        if (nl >= 0 && nl < LANES.length && this.gapInLane(nl, c.z, c) > 14 && safeFromPlayer) {
          c.target = nl;
          c.blinkT = 1.4;
        }
      }
      if (c.target !== c.lane) {
        if (c.blinkT > 0) c.blinkT -= dt;
        else {
          const tx = LANES[c.target];
          c.x += Math.sign(tx - c.x) * Math.min(Math.abs(tx - c.x), 1.6 * dt);
          if (Math.abs(tx - c.x) < 0.01) { c.lane = c.target; }
        }
      }
      const blinking = c.target !== c.lane;
      const on = blinking && Math.floor(t * 3) % 2 === 0;
      const left = c.target < c.lane;
      c.matL.emissiveIntensity = on && left ? 3 : 0;
      c.matR.emissiveIntensity = on && !left ? 3 : 0;
      const yaw = c.target !== c.lane && c.blinkT <= 0 ? -Math.sign(LANES[c.target] - c.x) * 0.06 : 0;
      c.obj.position.set(c.x, 0, c.z);
      c.obj.rotation.y = yaw;
      // удаление позади/слишком далеко
      if (c.z > pz + 45 || c.z < pz - 700) {
        this.scene.remove(c.obj);
        this.cars.splice(i, 1);
      }
    }
  }

  shift(dz) {
    for (const c of this.cars) { c.z += dz; c.obj.position.z = c.z; }
  }

  clear() {
    for (const c of this.cars) this.scene.remove(c.obj);
    this.cars = [];
  }
}
