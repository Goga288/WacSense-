// Строительство: фундаменты, стены, проёмы, перекрытия, лестницы, двери и размещаемые предметы.
import * as THREE from './three.module.min.js';
import { Inventory, ITEMS } from './items.js';
import { rayBox, boxesOverlap } from './util.js';
import { colorMat, mergeGeos, mat, vertexMat } from './world.js';

export const PIECES = {
  foundation: { name: 'Фундамент', mult: 1 },
  wall: { name: 'Стена', mult: 1 },
  doorway: { name: 'Дверной проём', mult: 0.7 },
  floor: { name: 'Перекрытие', mult: 0.5 },
  stairs: { name: 'Лестница', mult: 1 },
};
export const PIECE_ORDER = ['foundation', 'wall', 'doorway', 'floor', 'stairs'];

export const TIERS = [
  { name: 'Солома', cost: { wood: 50 }, color: 0xc9a872 },
  { name: 'Дерево', cost: { wood: 200 }, color: 0x8b5a2b },
  { name: 'Камень', cost: { stones: 300 }, color: 0xa3a19a },
  { name: 'Металл', cost: { metal_frag: 200 }, color: 0x6a737a },
];

export const DEPLOY = {
  campfire: { name: 'Костёр', size: [1.1, 0.5, 1.1], collide: false, slots: 6, item: 'campfire' },
  furnace: { name: 'Печь', size: [1.2, 1.7, 1.2], collide: true, slots: 6, item: 'furnace' },
  box: { name: 'Ящик для хранения', size: [1.2, 0.8, 0.7], collide: true, slots: 18, item: 'storage_box' },
  sleeping_bag: { name: 'Спальный мешок', size: [0.9, 0.15, 2.0], collide: false, slots: 0, item: 'sleeping_bag' },
};

const STAIR_DIRS = [[0, 1], [1, 0], [0, -1], [-1, 0]];
const WALL_H = 2.8;

// Бокс в локальной системе стены: along — вдоль стены, perp — поперёк.
function ax(rot, x, cy, z, along, perp, sAlong, sy, sPerp) {
  if (rot % 2 === 0) return { cx: x + along, cy, cz: z + perp, sx: sAlong, sy, sz: sPerp };
  return { cx: x + perp, cy, cz: z + along, sx: sPerp, sy, sz: sAlong };
}

export function pieceBoxes(type, x, y, z, rot, open) {
  switch (type) {
    case 'foundation':
      return [{ cx: x, cy: y - 1.5, cz: z, sx: 3, sy: 3, sz: 3 }];
    case 'floor':
      return [{ cx: x, cy: y - 0.1, cz: z, sx: 3, sy: 0.2, sz: 3 }];
    case 'wall':
      return [ax(rot, x, y + WALL_H / 2, z, 0, 0, 3, WALL_H, 0.2)];
    case 'doorway':
      return [
        ax(rot, x, y + WALL_H / 2, z, -1.05, 0, 0.9, WALL_H, 0.2),
        ax(rot, x, y + WALL_H / 2, z, 1.05, 0, 0.9, WALL_H, 0.2),
        ax(rot, x, y + 2.2 + 0.3, z, 0, 0, 1.2, 0.6, 0.2),
      ];
    case 'door':
      if (!open) return [ax(rot, x, y + 1.1, z, 0, 0, 1.2, 2.2, 0.08)];
      return [ax(rot, x, y + 1.1, z, -0.6, 0.6, 0.08, 2.2, 1.2)];
    case 'stairs': {
      const [dx, dz] = STAIR_DIRS[rot];
      const out = [];
      const n = 6, depth = 2.7 / n;
      for (let i = 0; i < n; i++) {
        const off = -1.35 + depth / 2 + i * depth;
        const sy = 0.5 * (i + 1);
        if (dx === 0) out.push({ cx: x, cy: y + sy / 2, cz: z + dz * off, sx: 2.7, sy, sz: depth });
        else out.push({ cx: x + dx * off, cy: y + sy / 2, cz: z, sx: depth, sy, sz: 2.7 });
      }
      return out;
    }
  }
  return [];
}

const toAABB = (b) => ({
  minX: b.cx - b.sx / 2, minY: b.cy - b.sy / 2, minZ: b.cz - b.sz / 2,
  maxX: b.cx + b.sx / 2, maxY: b.cy + b.sy / 2, maxZ: b.cz + b.sz / 2,
});

const cat = (type) => (type === 'foundation' || type === 'floor' ? 'cell' : type === 'wall' || type === 'doorway' ? 'edge' : type);
const key = (c, x, y, z) => `${c}:${Math.round(x * 2)}:${Math.round(y * 2)}:${Math.round(z * 2)}`;

const tierMats = TIERS.map((t, i) => {
  const m = new THREE.MeshLambertMaterial({ color: t.color, flatShading: true });
  if (i === 0) { m.transparent = true; m.opacity = 0.88; }
  return m;
});
const ghostOk = new THREE.MeshBasicMaterial({ color: 0x44ff66, transparent: true, opacity: 0.35, depthWrite: false });
const ghostBad = new THREE.MeshBasicMaterial({ color: 0xff4444, transparent: true, opacity: 0.35, depthWrite: false });
const doorMat = new THREE.MeshLambertMaterial({ color: 0x6b4423, flatShading: true });
const flameMat = new THREE.MeshBasicMaterial({ color: 0xffa030 });
const boxGeoCache = new Map();
function boxGeo(sx, sy, sz) {
  const k = `${sx}|${sy}|${sz}`;
  let g = boxGeoCache.get(k);
  if (!g) { g = new THREE.BoxGeometry(sx, sy, sz); boxGeoCache.set(k, g); }
  return g;
}

export class Building {
  constructor(game) {
    this.game = game;
    this.world = game.world;
    this.scene = game.scene;
    this.pieces = [];
    this.occ = new Map();
    this.deploys = [];
    this.ghost = new THREE.Group();
    this.ghost.visible = false;
    this.scene.add(this.ghost);
    this.ghostKey = '';
    this.pieceType = 'foundation';
    this.rot = 0;
    this.candidate = null;
  }

  // ---------- Проверки ----------
  isOccupied(type, x, y, z) {
    return this.occ.has(key(cat(type), x, y, z));
  }

  overlapsWorld(boxes, ignore) {
    const w = this.world;
    const pl = this.game.player;
    const pbox = { minX: pl.pos.x - 0.3, minY: pl.pos.y, minZ: pl.pos.z - 0.3, maxX: pl.pos.x + 0.3, maxY: pl.pos.y + 1.75, maxZ: pl.pos.z + 0.3 };
    for (const b of boxes) {
      const a = toAABB(b);
      if (this.game.player.alive && boxesOverlap(a, pbox, 0.02)) return 'Мешает игрок';
      const list = w.colliders.query(a.minX, a.minZ, a.maxX, a.maxZ);
      for (const c of list) {
        if (ignore && c.ref === ignore) continue;
        if (boxesOverlap(a, c, 0.12)) return 'Мешает объект';
      }
      const nodes = w.nodes.query(a.minX - 1, a.minZ - 1, a.maxX + 1, a.maxZ + 1);
      for (const n of nodes) {
        if (!n.alive || !n.col) continue;
        const cx = Math.max(a.minX, Math.min(n.x, a.maxX));
        const cz = Math.max(a.minZ, Math.min(n.z, a.maxZ));
        if ((cx - n.x) ** 2 + (cz - n.z) ** 2 < n.col * n.col && a.minY < n.y + 3) return 'Мешает дерево или камень';
      }
    }
    return null;
  }

  validate(c) {
    const { type, x, y, z, rot } = c;
    if (this.isOccupied(type, x, y, z)) return 'Место занято';
    const w = this.world;
    if (type === 'foundation') {
      let mn = Infinity, mx = -Infinity;
      for (const [dx, dz] of [[-1.5, -1.5], [1.5, -1.5], [-1.5, 1.5], [1.5, 1.5], [0, 0]]) {
        const h = w.getHeight(x + dx, z + dz);
        mn = Math.min(mn, h); mx = Math.max(mx, h);
      }
      if (mx > y - 0.02) return 'Слишком высокий рельеф';
      if (y - mn > 3) return 'Слишком высоко над землёй';
      if (w.getHeight(x, z) < -0.3) return 'Нельзя строить в воде';
      if (w.nearMonument(x, z, 4)) return 'Нельзя строить у монумента';
    }
    if (type === 'floor') {
      const edges = [[x, z + 1.5], [x, z - 1.5], [x + 1.5, z], [x - 1.5, z]];
      if (!edges.some(([ex, ez]) => this.isOccupied('wall', ex, y - 3, ez))) return 'Нужна опора из стен';
      if (this.isOccupied('stairs', x, y - 3, z)) return 'Над лестницей нельзя';
    }
    if (type === 'stairs' && this.isOccupied('floor', x, y + 3, z)) return 'Сверху перекрытие';
    if (type === 'door') return null;
    return this.overlapsWorld(pieceBoxes(type, x, y, z, rot));
  }

  // Кандидаты «привязки» к существующим постройкам.
  candidates(type, aim) {
    const out = [];
    for (const p of this.pieces) {
      if (Math.abs(p.x - aim.x) > 7 || Math.abs(p.z - aim.z) > 7 || Math.abs(p.y - aim.y) > 7) continue;
      const floorLike = p.type === 'foundation' || p.type === 'floor';
      if (type === 'foundation' && p.type === 'foundation') {
        for (const [dx, dz] of STAIR_DIRS) out.push({ type, x: p.x + dx * 3, y: p.y, z: p.z + dz * 3, rot: 0 });
      }
      if (type === 'floor') {
        if (floorLike) {
          out.push({ type, x: p.x, y: p.y + 3, z: p.z, rot: 0 });
          if (p.type === 'floor') for (const [dx, dz] of STAIR_DIRS) out.push({ type, x: p.x + dx * 3, y: p.y, z: p.z + dz * 3, rot: 0 });
        }
        if (p.type === 'wall' || p.type === 'doorway') {
          if (p.rot === 0) {
            out.push({ type, x: p.x, y: p.y + 3, z: p.z + 1.5, rot: 0 });
            out.push({ type, x: p.x, y: p.y + 3, z: p.z - 1.5, rot: 0 });
          } else {
            out.push({ type, x: p.x + 1.5, y: p.y + 3, z: p.z, rot: 0 });
            out.push({ type, x: p.x - 1.5, y: p.y + 3, z: p.z, rot: 0 });
          }
        }
      }
      if ((type === 'wall' || type === 'doorway') && floorLike) {
        out.push({ type, x: p.x, y: p.y, z: p.z + 1.5, rot: 0 });
        out.push({ type, x: p.x, y: p.y, z: p.z - 1.5, rot: 0 });
        out.push({ type, x: p.x + 1.5, y: p.y, z: p.z, rot: 1 });
        out.push({ type, x: p.x - 1.5, y: p.y, z: p.z, rot: 1 });
      }
      if (type === 'stairs' && floorLike) out.push({ type, x: p.x, y: p.y, z: p.z, rot: this.rot });
    }
    return out;
  }

  anchorOf(c) {
    if (c.type === 'wall' || c.type === 'doorway') return { x: c.x, y: c.y + 1.4, z: c.z };
    if (c.type === 'stairs') return { x: c.x, y: c.y + 0.8, z: c.z };
    return { x: c.x, y: c.y, z: c.z };
  }

  // Вызывается каждый кадр, пока в руках план постройки.
  updatePlan(hit, aim) {
    const type = this.pieceType;
    let best = null, bestD = 3.2, bestErr = null;
    for (const c of this.candidates(type, aim)) {
      const a = this.anchorOf(c);
      const d = Math.hypot(a.x - aim.x, a.y - aim.y, a.z - aim.z);
      if (d >= bestD) continue;
      if (this.isOccupied(c.type, c.x, c.y, c.z)) continue;
      bestD = d;
      best = c;
    }
    if (best) bestErr = this.validate(best);
    if (!best && type === 'foundation' && hit && hit.kind === 'terrain') {
      let mx = -Infinity;
      for (const [dx, dz] of [[-1.5, -1.5], [1.5, -1.5], [-1.5, 1.5], [1.5, 1.5], [0, 0]]) {
        mx = Math.max(mx, this.world.getHeight(hit.point.x + dx, hit.point.z + dz));
      }
      best = { type, x: hit.point.x, y: mx + 0.25, z: hit.point.z, rot: 0 };
      bestErr = this.validate(best);
    }
    if (!best) {
      this.candidate = null;
      this.showGhost(null);
      return type === 'foundation' ? 'Наведитесь на землю' : 'Нужна опора (фундамент/стена)';
    }
    best.err = bestErr;
    this.candidate = best;
    this.showGhost(best, !bestErr);
    return bestErr;
  }

  showGhost(c, ok) {
    if (!c) { this.ghost.visible = false; this.ghostKey = ''; return; }
    const k = `${c.type}|${c.x.toFixed(2)}|${c.y.toFixed(2)}|${c.z.toFixed(2)}|${c.rot}|${ok}`;
    this.ghost.visible = true;
    if (k === this.ghostKey) return;
    this.ghostKey = k;
    this.ghost.clear();
    let boxes;
    if (c.deploy) {
      const s = DEPLOY[c.deploy].size;
      const sx = c.rot % 2 ? s[2] : s[0], sz = c.rot % 2 ? s[0] : s[2];
      boxes = [{ cx: c.x, cy: c.y + s[1] / 2, cz: c.z, sx, sy: s[1], sz }];
    } else {
      boxes = pieceBoxes(c.type, c.x, c.y, c.z, c.rot, false);
    }
    for (const b of boxes) {
      const m = new THREE.Mesh(boxGeo(b.sx + 0.02, b.sy + 0.02, b.sz + 0.02), ok ? ghostOk : ghostBad);
      m.position.set(b.cx, b.cy, b.cz);
      this.ghost.add(m);
    }
  }

  hideGhost() {
    this.ghost.visible = false;
    this.ghostKey = '';
    this.candidate = null;
  }

  // ---------- Добавление / удаление ----------
  addPiece(data) {
    const p = { kind: 'piece', type: data.type, x: data.x, y: data.y, z: data.z, rot: data.rot || 0, tier: data.tier || 0, open: !!data.open };
    p.key = key(cat(p.type), p.x, p.y, p.z);
    if (this.occ.has(p.key)) return null;
    this.occ.set(p.key, p);
    this.pieces.push(p);
    this.buildPieceMesh(p);
    this.buildPieceCols(p);
    return p;
  }

  buildPieceMesh(p) {
    if (p.mesh) this.scene.remove(p.mesh);
    if (p.type === 'door') {
      const g = new THREE.Group();
      const a = p.rot % 2 === 0 ? [1, 0, 0] : [0, 0, 1];
      g.position.set(p.x - a[0] * 0.6, p.y, p.z - a[2] * 0.6);
      const base = p.rot % 2 === 0 ? 0 : -Math.PI / 2;
      g.rotation.y = p.open ? base - Math.PI / 2 : base;
      const panel = new THREE.Mesh(boxGeo(1.18, 2.18, 0.08), doorMat);
      panel.position.set(0.6, 1.1, 0);
      const handle = new THREE.Mesh(boxGeo(0.06, 0.06, 0.2), colorMat(0x333333));
      handle.position.set(1.0, 1.05, 0);
      g.add(panel, handle);
      panel.castShadow = true;
      p.mesh = g;
    } else {
      const g = new THREE.Group();
      for (const b of pieceBoxes(p.type, p.x, p.y, p.z, p.rot)) {
        const m = new THREE.Mesh(boxGeo(b.sx, b.sy, b.sz), tierMats[p.tier]);
        m.position.set(b.cx, b.cy, b.cz);
        m.castShadow = true;
        m.receiveShadow = true;
        g.add(m);
      }
      p.mesh = g;
    }
    this.scene.add(p.mesh);
  }

  buildPieceCols(p) {
    if (p.cols) for (const c of p.cols) this.world.removeCollider(c);
    p.cols = pieceBoxes(p.type, p.x, p.y, p.z, p.rot, p.open).map((b) => {
      const a = toAABB(b);
      return this.world.addCollider(a.minX, a.minY, a.minZ, a.maxX, a.maxY, a.maxZ, p);
    });
  }

  removePiece(p) {
    this.scene.remove(p.mesh);
    for (const c of p.cols) this.world.removeCollider(c);
    this.occ.delete(p.key);
    const i = this.pieces.indexOf(p);
    if (i >= 0) this.pieces.splice(i, 1);
  }

  supported(p) {
    const { x, y, z } = p;
    switch (p.type) {
      case 'foundation': return true;
      case 'wall':
      case 'doorway':
        return p.rot === 0
          ? this.isOccupied('floor', x, y, z + 1.5) || this.isOccupied('floor', x, y, z - 1.5)
          : this.isOccupied('floor', x + 1.5, y, z) || this.isOccupied('floor', x - 1.5, y, z);
      case 'floor':
        return [[x, z + 1.5], [x, z - 1.5], [x + 1.5, z], [x - 1.5, z]].some(([ex, ez]) => this.isOccupied('wall', ex, y - 3, ez));
      case 'stairs': return this.isOccupied('floor', x, y, z);
      case 'door': {
        const d = this.occ.get(key('edge', x, y, z));
        return !!d && d.type === 'doorway';
      }
    }
    return true;
  }

  demolish(p) {
    this.removePiece(p);
    // каскадно убираем то, что потеряло опору
    let changed = true;
    while (changed) {
      changed = false;
      for (const q of [...this.pieces]) {
        if (!this.supported(q)) { this.removePiece(q); changed = true; }
      }
    }
    for (const d of [...this.deploys]) {
      if (d.y > this.world.getHeight(d.x, d.z) + 0.3) {
        const below = this.world.colliders.query(d.x - 0.2, d.z - 0.2, d.x + 0.2, d.z + 0.2)
          .some((c) => c.ref !== d && Math.abs(c.maxY - d.y) < 0.05);
        if (!below) this.removeDeploy(d, true);
      }
    }
  }

  upgrade(p) {
    if (p.type === 'door') return 'Дверь нельзя улучшить';
    if (p.tier >= TIERS.length - 1) return 'Максимальный уровень';
    const t = TIERS[p.tier + 1];
    const mult = PIECES[p.type].mult;
    if (!this.game.inv.take(t.cost, mult)) return 'Не хватает ресурсов';
    p.tier++;
    this.buildPieceMesh(p);
    return null;
  }

  place() {
    const c = this.candidate;
    if (!c || c.err) return c ? c.err : 'Нельзя построить здесь';
    const cost = TIERS[0].cost;
    const mult = PIECES[c.type].mult;
    if (!this.game.inv.take(cost, mult)) return 'Не хватает дерева';
    this.addPiece(c);
    this.candidate = null;
    this.ghostKey = '';
    return null;
  }

  placeDoor(doorway) {
    if (this.isOccupied('door', doorway.x, doorway.y, doorway.z)) return 'Дверь уже стоит';
    const p = this.addPiece({ type: 'door', x: doorway.x, y: doorway.y, z: doorway.z, rot: doorway.rot });
    return p ? null : 'Нельзя';
  }

  toggleDoor(p) {
    p.open = !p.open;
    if (p.open === false) {
      const err = this.overlapsWorld(pieceBoxes('door', p.x, p.y, p.z, p.rot, false), p);
      if (err === 'Мешает игрок') { p.open = true; return; }
    }
    this.buildPieceMesh(p);
    this.buildPieceCols(p);
  }

  // ---------- Размещаемые предметы ----------
  deployCandidate(type, hit, yaw) {
    if (!hit || hit.t > 5) return { err: 'Слишком далеко' };
    const up = hit.kind === 'terrain' || (hit.normal && hit.normal.y > 0.7);
    if (!up) return { err: 'Нужна ровная поверхность' };
    if (hit.kind === 'terrain' && this.world.slope(hit.point.x, hit.point.z) > 0.6) return { err: 'Слишком круто' };
    const rot = ((Math.round(-yaw / (Math.PI / 2)) % 4) + 4) % 4;
    const c = { deploy: type, x: hit.point.x, y: hit.point.y, z: hit.point.z, rot };
    if (hit.kind === 'terrain' && hit.point.y < 0.1) return { ...c, err: 'Нельзя ставить в воду' };
    const s = DEPLOY[type].size;
    const sx = rot % 2 ? s[2] : s[0], sz = rot % 2 ? s[0] : s[2];
    const box = { cx: c.x, cy: c.y + s[1] / 2 + 0.05, cz: c.z, sx, sy: s[1], sz };
    c.err = this.overlapsWorld([box]);
    return c;
  }

  addDeploy(data) {
    const def = DEPLOY[data.type];
    const d = {
      kind: 'deploy', type: data.type, x: data.x, y: data.y, z: data.z, rot: data.rot || 0,
      on: !!data.on, inv: new Inventory(def.slots || 1), tick: 0, name: def.name,
    };
    if (data.items) d.inv.load(data.items);
    d.mesh = this.deployMesh(d);
    this.scene.add(d.mesh);
    const s = def.size;
    const sx = d.rot % 2 ? s[2] : s[0], sz = d.rot % 2 ? s[0] : s[2];
    d.box = { minX: d.x - sx / 2, minY: d.y, minZ: d.z - sz / 2, maxX: d.x + sx / 2, maxY: d.y + s[1], maxZ: d.z + sz / 2 };
    if (def.collide) d.col = this.world.addCollider(d.box.minX, d.box.minY, d.box.minZ, d.box.maxX, d.box.maxY, d.box.maxZ, d);
    this.deploys.push(d);
    this.setOn(d, d.on);
    return d;
  }

  removeDeploy(d, dropItems) {
    this.scene.remove(d.mesh);
    if (d.col) this.world.removeCollider(d.col);
    const i = this.deploys.indexOf(d);
    if (i >= 0) this.deploys.splice(i, 1);
    if (dropItems) {
      const items = d.inv.slots.filter(Boolean);
      items.push({ id: DEPLOY[d.type].item, n: 1 });
      this.game.dropBag(d.x, this.world.getHeight(d.x, d.z), d.z, items);
    }
    if (this.game.spawnBag === d) this.game.spawnBag = null;
  }

  deployMesh(d) {
    const g = new THREE.Group();
    g.position.set(d.x, d.y, d.z);
    g.rotation.y = d.rot * Math.PI / 2;
    if (d.type === 'campfire') {
      const parts = [];
      for (let i = 0; i < 7; i++) {
        const a = (i / 7) * Math.PI * 2;
        parts.push({ geo: new THREE.IcosahedronGeometry(0.15, 0), color: 0x77736c, matrix: mat([Math.cos(a) * 0.45, 0.08, Math.sin(a) * 0.45]) });
      }
      for (let i = 0; i < 3; i++) {
        parts.push({ geo: new THREE.CylinderGeometry(0.07, 0.07, 0.8, 5), color: 0x5a3d25, matrix: mat([0, 0.12, 0], [Math.PI / 2, (i / 3) * Math.PI, 0]) });
      }
      g.add(new THREE.Mesh(mergeGeos(parts), vertexMat));
      const fl = new THREE.Mesh(new THREE.ConeGeometry(0.25, 0.7, 6), flameMat);
      fl.position.y = 0.45;
      g.add(fl);
      d.flame = fl;
    } else if (d.type === 'furnace') {
      g.add(new THREE.Mesh(mergeGeos([
        { geo: new THREE.CylinderGeometry(0.45, 0.6, 1.3, 8), color: 0x8b8680, matrix: mat([0, 0.65, 0]), jitter: 0.06 },
        { geo: new THREE.CylinderGeometry(0.18, 0.25, 0.5, 6), color: 0x77726c, matrix: mat([0, 1.5, 0]) },
        { geo: new THREE.BoxGeometry(0.4, 0.35, 0.1), color: 0x222222, matrix: mat([0, 0.35, 0.55]) },
      ]), vertexMat));
      const fl = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.28, 0.05), flameMat);
      fl.position.set(0, 0.35, 0.58);
      g.add(fl);
      d.flame = fl;
    } else if (d.type === 'box') {
      g.add(new THREE.Mesh(mergeGeos([
        { geo: new THREE.BoxGeometry(1.2, 0.7, 0.7), color: 0x8a6236, matrix: mat([0, 0.35, 0]) },
        { geo: new THREE.BoxGeometry(1.24, 0.12, 0.74), color: 0x6b4a27, matrix: mat([0, 0.75, 0]) },
        { geo: new THREE.BoxGeometry(0.2, 0.15, 0.05), color: 0x333333, matrix: mat([0, 0.6, 0.37]) },
      ]), vertexMat));
    } else if (d.type === 'sleeping_bag') {
      g.add(new THREE.Mesh(mergeGeos([
        { geo: new THREE.BoxGeometry(0.85, 0.12, 1.7), color: 0x4a6a3a, matrix: mat([0, 0.06, 0.1]) },
        { geo: new THREE.BoxGeometry(0.6, 0.12, 0.3), color: 0xd8d0c0, matrix: mat([0, 0.08, -0.8]) },
      ]), vertexMat));
    }
    g.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    return g;
  }

  setOn(d, on) {
    if (d.type !== 'campfire' && d.type !== 'furnace') return;
    if (on && d.inv.count('wood') <= 0) on = false;
    d.on = on;
    if (d.flame) d.flame.visible = on;
  }

  // Плавка и готовка.
  update(dt, t) {
    for (const d of this.deploys) {
      if (!d.on) continue;
      if (d.flame) d.flame.scale.set(1, 0.8 + Math.sin(t * 20 + d.x) * 0.2, 1);
      d.tick += dt;
      if (d.tick < 1) continue;
      d.tick -= 1;
      const inv = d.inv;
      if (inv.count('wood') <= 0) { this.setOn(d, false); continue; }
      inv.remove('wood', 1);
      if (Math.random() < 0.75) inv.add('charcoal', 1);
      if (d.type === 'furnace') {
        for (const ore of ['metal_ore', 'sulfur_ore']) {
          const n = Math.min(inv.count(ore), 5);
          if (n > 0) {
            const out = ITEMS[ore].smelt;
            inv.remove(ore, n);
            const left = inv.add(out, n);
            if (left) inv.add(ore, left);
            break;
          }
        }
      } else if (d.type === 'campfire') {
        d.cook = (d.cook || 0) + 1;
        if (d.cook >= 3 && inv.count('raw_meat') > 0) {
          d.cook = 0;
          inv.remove('raw_meat', 1);
          if (inv.add('cooked_meat', 1)) inv.add('raw_meat', 1);
        }
      }
      if (inv.count('wood') <= 0) this.setOn(d, false);
      if (this.game.ui.container && this.game.ui.container.inv === inv) this.game.ui.refresh();
    }
  }

  // Ближайший источник огня (для точечного света).
  nearestFire(pos) {
    let best = null, bd = 30;
    for (const d of this.deploys) {
      if (!d.on) continue;
      const dd = Math.hypot(d.x - pos.x, d.z - pos.z);
      if (dd < bd) { bd = dd; best = d; }
    }
    return best;
  }

  // ---------- Луч ----------
  raycast(o, dir, best) {
    for (const p of this.pieces) {
      if (Math.abs(p.x - o.x) > best.t + 4 || Math.abs(p.z - o.z) > best.t + 4) continue;
      for (const c of p.cols) {
        const h = rayBox(o, dir, c.minX, c.minY, c.minZ, c.maxX, c.maxY, c.maxZ, best.t);
        if (h && h.t < best.t) { best.t = h.t; best.kind = 'piece'; best.obj = p; best.normal = { x: h.nx, y: h.ny, z: h.nz }; }
      }
    }
    for (const d of this.deploys) {
      if (Math.abs(d.x - o.x) > best.t + 3 || Math.abs(d.z - o.z) > best.t + 3) continue;
      const b = d.box;
      const h = rayBox(o, dir, b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ, best.t);
      if (h && h.t < best.t) { best.t = h.t; best.kind = 'deploy'; best.obj = d; best.normal = { x: h.nx, y: h.ny, z: h.nz }; }
    }
    return best;
  }

  serialize() {
    return {
      pieces: this.pieces.map((p) => ({ type: p.type, x: p.x, y: p.y, z: p.z, rot: p.rot, tier: p.tier, open: p.open })),
      deploys: this.deploys.map((d) => ({ type: d.type, x: d.x, y: d.y, z: d.z, rot: d.rot, on: d.on, items: d.inv.serialize() })),
    };
  }

  load(data) {
    for (const p of [...this.pieces]) this.removePiece(p);
    for (const d of [...this.deploys]) this.removeDeploy(d, false);
    if (!data) return;
    const order = ['foundation', 'floor', 'wall', 'doorway', 'stairs', 'door'];
    const ps = [...(data.pieces || [])].sort((a, b) => order.indexOf(a.type) - order.indexOf(b.type));
    for (const p of ps) if (PIECES[p.type] || p.type === 'door') this.addPiece(p);
    for (const d of data.deploys || []) if (DEPLOY[d.type]) this.addDeploy(d);
  }
}
