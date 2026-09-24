// Живность, учёные-NPC, трупы, сумки с лутом, стрелы, трассеры и частицы.
import * as THREE from './three.module.min.js';
import { Inventory, rollLoot } from './items.js';
import { rand, randi, clamp, angleDiff, rayCylY, raySphere } from './util.js';
import { colorMat } from './world.js';

export const ANIMALS = {
  deer: { name: 'Олень', hp: 80, walk: 1.8, run: 8, aggro: 0, flee: 22, dmg: 0, meat: 30, r: 0.6, h: 1.6,
    body: [0.45, 0.55, 1.2], by: 1.0, legH: 0.8, legW: 0.1, head: 0.3, headY: 1.55, headZ: 0.75, color: 0x9a6a3a },
  boar: { name: 'Кабан', hp: 120, walk: 1.5, run: 6, aggro: 0, retaliate: true, dmg: 10, meat: 40, r: 0.6, h: 1.0,
    body: [0.6, 0.6, 1.1], by: 0.6, legH: 0.32, legW: 0.14, head: 0.4, headY: 0.55, headZ: 0.7, color: 0x4a3526 },
  wolf: { name: 'Волк', hp: 100, walk: 2.0, run: 7.3, aggro: 20, dmg: 12, meat: 30, r: 0.55, h: 1.0,
    body: [0.4, 0.45, 1.1], by: 0.75, legH: 0.55, legW: 0.1, head: 0.32, headY: 0.95, headZ: 0.7, color: 0x77746f },
  bear: { name: 'Медведь', hp: 300, walk: 1.6, run: 6.4, aggro: 14, dmg: 25, meat: 80, r: 0.9, h: 1.8,
    body: [0.95, 0.95, 1.7], by: 1.05, legH: 0.6, legW: 0.3, head: 0.55, headY: 1.35, headZ: 1.05, color: 0x4a3322 },
};
const ANIMAL_COUNTS = { deer: 14, boar: 12, wolf: 8, bear: 4 };

const furMats = new Map();
function fur(color) {
  let m = furMats.get(color);
  if (!m) { m = new THREE.MeshStandardMaterial({ color, roughness: 1 }); furMats.set(color, m); }
  return m;
}
function part(geo, color, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
  const m = new THREE.Mesh(geo, typeof color === 'number' ? fur(color) : color);
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  m.scale.set(sx, sy, sz);
  m.castShadow = true;
  return m;
}
const cap = (r, l) => new THREE.CapsuleGeometry(r, l, 4, 10);
const sph = (r) => new THREE.SphereGeometry(r, 12, 10);
const cone = (r, h) => new THREE.ConeGeometry(r, h, 8);

// Четвероногое из капсул: тело, шея, голова, морда, уши, ноги с «шарнирами».
function buildAnimal(type) {
  const d = ANIMALS[type];
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);
  const [bw, bh, bl] = d.body;
  const c = d.color;
  const dark = new THREE.Color(c).multiplyScalar(0.6).getHex();
  const light = new THREE.Color(c).lerp(new THREE.Color(0xd8c8b0), 0.45).getHex();
  // туловище
  body.add(part(cap(bh / 2, bl - bh * 0.6), c, 0, d.by, 0, Math.PI / 2, 0, 0, bw / bh, 1, 1));
  body.add(part(sph(bh * 0.52), c, 0, d.by + bh * 0.05, bl * 0.3, 0, 0, 0, bw / bh, 1.05, 1));
  body.add(part(cap(bh * 0.35, bl * 0.5), light, 0, d.by - bh * 0.25, 0, Math.PI / 2, 0, 0, bw / bh * 0.9, 0.6, 1));
  // шея и голова
  const neckLen = type === 'deer' ? 0.55 : type === 'bear' ? 0.25 : 0.2;
  const hy = d.headY, hz = d.headZ;
  body.add(part(cap(d.head * 0.38, neckLen), c, 0, (d.by + hy) / 2 + 0.05, (bl * 0.4 + hz) / 2, -0.6, 0, 0));
  const head = new THREE.Group();
  head.position.set(0, hy, hz);
  body.add(head);
  head.add(part(sph(d.head * 0.52), c, 0, 0, 0, 0, 0, 0, 0.9, 0.85, 1.1));
  const snoutL = type === 'boar' ? 0.32 : type === 'wolf' ? 0.3 : type === 'deer' ? 0.26 : 0.26;
  head.add(part(cap(d.head * 0.24, snoutL), type === 'deer' ? dark : light, 0, -d.head * 0.12, d.head * 0.5, Math.PI / 2 - 0.15, 0, 0));
  head.add(part(sph(d.head * 0.1), 0x151515, 0, -d.head * 0.05, d.head * 0.5 + snoutL * 0.75));
  for (const sx of [-1, 1]) {
    head.add(part(sph(d.head * 0.06), 0x0c0c0c, sx * d.head * 0.28, d.head * 0.12, d.head * 0.38));
    if (type === 'wolf') head.add(part(cone(d.head * 0.14, d.head * 0.4), dark, sx * d.head * 0.25, d.head * 0.5, -d.head * 0.05, 0, 0, sx * -0.2));
    else if (type === 'bear') head.add(part(sph(d.head * 0.14), dark, sx * d.head * 0.35, d.head * 0.4, -d.head * 0.1));
    else if (type === 'deer') {
      head.add(part(cone(d.head * 0.1, d.head * 0.45), c, sx * d.head * 0.35, d.head * 0.35, -d.head * 0.1, 0, 0, sx * -0.9));
      // рога
      const ant = new THREE.CylinderGeometry(0.018, 0.028, 0.45, 5);
      head.add(part(ant, 0xcdbb98, sx * 0.1, d.head * 0.55, -0.05, -0.2, 0, sx * -0.35));
      head.add(part(ant, 0xcdbb98, sx * 0.2, d.head * 0.8, 0.02, 0.5, 0, sx * -0.8, 0.7, 0.7, 0.7));
      head.add(part(ant, 0xcdbb98, sx * 0.15, d.head * 0.95, -0.12, -0.6, 0, sx * -0.2, 0.6, 0.6, 0.6));
    } else if (type === 'boar') {
      head.add(part(cone(0.025, 0.14), 0xeeeadf, sx * 0.09, -d.head * 0.2, d.head * 0.72, -0.9, 0, 0));
      head.add(part(cone(d.head * 0.12, d.head * 0.3), dark, sx * d.head * 0.3, d.head * 0.4, -d.head * 0.1, 0, 0, sx * -0.5));
    }
  }
  // хвост
  if (type === 'wolf') body.add(part(cap(0.07, 0.45), c, 0, d.by + 0.02, -bl / 2 - 0.15, -0.9, 0, 0));
  if (type === 'deer') body.add(part(sph(0.08), 0xe8e0d0, 0, d.by + 0.1, -bl / 2 + 0.02));
  if (type === 'boar') body.add(part(cap(0.025, 0.2), dark, 0, d.by + 0.1, -bl / 2 - 0.05, -0.5, 0, 0));
  // ноги
  const legs = [];
  for (const [sx, sz] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) {
    const pivot = new THREE.Group();
    pivot.position.set(sx * (bw / 2 - d.legW * 0.6), d.by - bh * 0.15, sz * (bl / 2 - d.legW * 1.2));
    const L = d.by - bh * 0.15;
    pivot.add(part(cap(d.legW * 0.7, L * 0.45), c, 0, -L * 0.3, 0, 0, 0, 0, 1, 1, 1.15));
    pivot.add(part(cap(d.legW * 0.45, L * 0.45), dark, 0, -L * 0.72, 0));
    body.add(pivot);
    legs.push(pivot);
  }
  return { root, body, legs };
}

// Учёный: защитный костюм, противогаз, винтовка. Оригинальный дизайн.
function buildHuman() {
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);
  const suit = 0x3f6e8c, suitDark = 0x2c4a5e, black = 0x1a1c1e;
  const legs = [];
  for (const sx of [-1, 1]) {
    const p = new THREE.Group();
    p.position.set(sx * 0.13, 0.95, 0);
    p.add(part(cap(0.1, 0.5), suit, 0, -0.35, 0));
    p.add(part(cap(0.085, 0.25), suitDark, 0, -0.75, 0.02));
    p.add(part(new THREE.BoxGeometry(0.14, 0.09, 0.26), black, 0, -0.91, 0.05));
    body.add(p);
    legs.push(p);
  }
  body.add(part(cap(0.21, 0.35), suit, 0, 1.28, 0, 0, 0, 0, 1.1, 1, 0.75));
  body.add(part(new THREE.BoxGeometry(0.34, 0.3, 0.12), suitDark, 0, 1.3, -0.17));
  body.add(part(new THREE.CylinderGeometry(0.2, 0.2, 0.06, 12), black, 0, 1.03, 0, 0, 0, 0, 1.15, 1, 0.8));
  const head = new THREE.Group();
  head.position.set(0, 1.74, 0);
  body.add(head);
  head.add(part(sph(0.16), suit, 0, 0.02, 0, 0, 0, 0, 1, 1.1, 1));
  head.add(part(new THREE.SphereGeometry(0.12, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), 0x26313a, 0, 0.01, 0.1, Math.PI / 2, 0, 0, 1, 1, 0.5));
  for (const sx of [-1, 1]) head.add(part(sph(0.045), 0x9ab8c8, sx * 0.06, 0.04, 0.15));
  head.add(part(new THREE.CylinderGeometry(0.05, 0.06, 0.1, 10), black, 0, -0.08, 0.17, Math.PI / 2 - 0.4, 0, 0));
  const arms = new THREE.Group();
  arms.position.set(0, 1.47, 0);
  arms.add(part(cap(0.075, 0.35), suit, -0.25, -0.1, 0.18, -1.2, 0, 0.3));
  arms.add(part(cap(0.075, 0.35), suit, 0.25, -0.1, 0.18, -1.3, 0, -0.35));
  arms.add(part(sph(0.06), black, 0.08, -0.08, 0.4));
  arms.add(part(sph(0.06), black, -0.05, -0.02, 0.55));
  // винтовка
  arms.add(part(new THREE.BoxGeometry(0.07, 0.12, 0.55), black, 0.05, 0.0, 0.5));
  arms.add(part(new THREE.CylinderGeometry(0.018, 0.018, 0.45, 8), black, 0.05, 0.03, 0.98, Math.PI / 2, 0, 0));
  arms.add(part(new THREE.BoxGeometry(0.05, 0.14, 0.06), black, 0.05, -0.1, 0.42, 0.3, 0, 0));
  arms.add(part(new THREE.BoxGeometry(0.06, 0.1, 0.25), 0x3b2f24, 0.05, -0.02, 0.18));
  body.add(arms);
  const flash = new THREE.Sprite(new THREE.SpriteMaterial({ color: 0xffd070, blending: THREE.AdditiveBlending, depthWrite: false }));
  flash.scale.setScalar(0.4);
  flash.position.set(0.05, 1.5, 1.25);
  flash.visible = false;
  body.add(flash);
  return { root, body, legs, flash };
}

const bagGeo = new THREE.CapsuleGeometry(0.22, 0.3, 4, 10).rotateZ(Math.PI / 2);
const bagMat = new THREE.MeshStandardMaterial({ color: 0x6a5a3a, roughness: 1 });
const arrowGeo = new THREE.CylinderGeometry(0.015, 0.015, 0.8, 4).rotateX(Math.PI / 2);
const arrowMat = new THREE.MeshStandardMaterial({ color: 0x8a6a3a, roughness: 0.8 });

export class Entities {
  constructor(game) {
    this.game = game;
    this.world = game.world;
    this.scene = game.scene;
    this.mobs = [];
    this.bags = [];
    this.arrows = [];
    this.tracers = [];
    this.initParticles();
    for (const type in ANIMAL_COUNTS) {
      for (let i = 0; i < ANIMAL_COUNTS[type]; i++) this.spawnAnimal(type);
    }
    for (const s of this.world.npcSpawns) this.spawnNpc(s);
  }

  // ---------- Спавн ----------
  spawnAnimal(type, near) {
    const d = ANIMALS[type];
    let p = null;
    for (let i = 0; i < 30 && !p; i++) {
      const q = this.world.randomLandPoint(type === 'bear' ? 8 : 3, 26, 15, 0.7);
      if (!q) continue;
      if (near && Math.hypot(q.x - near.x, q.z - near.z) < 60) continue;
      p = q;
    }
    if (!p) return;
    const model = buildAnimal(type);
    const m = {
      kind: 'mob', animal: true, type, def: d, name: d.name, hp: d.hp, maxHp: d.hp,
      pos: new THREE.Vector3(p.x, this.world.getHeight(p.x, p.z), p.z), yaw: rand(0, Math.PI * 2),
      state: 'wander', timer: 0, target: null, atk: 0, phase: 0, speed: 0, dead: false,
      r: d.r, h: d.h, ...model,
    };
    this.scene.add(m.root);
    this.mobs.push(m);
    return m;
  }

  spawnNpc(spawn) {
    const model = buildHuman();
    const m = {
      kind: 'mob', npc: true, type: 'scientist', name: 'Учёный', hp: 150, maxHp: 150, spawn,
      pos: new THREE.Vector3(spawn.x, this.world.getHeight(spawn.x, spawn.z), spawn.z), yaw: rand(0, 6.28),
      state: 'patrol', timer: 0, target: null, atk: 1, phase: 0, speed: 0, dead: false, lostT: 0, burst: 0,
      r: 0.4, h: 1.9, ...model,
    };
    this.scene.add(m.root);
    this.mobs.push(m);
    return m;
  }

  // ---------- Урон ----------
  damage(m, dmg, fromPlayer = true) {
    if (m.dead) return;
    m.hp -= dmg;
    this.blood(m.pos.x, m.pos.y + m.h * 0.6, m.pos.z);
    if (m.hp <= 0) {
      this.kill(m);
      if (fromPlayer && m.animal) this.game.ui.notify(`☠ Убит: ${m.def.name}`);
      return;
    }
    if (m.animal) {
      const d = m.def;
      if (d.dmg > 0 && (d.retaliate || d.aggro)) { m.state = 'chase'; m.timer = 15; }
      else { m.state = 'flee'; m.timer = 8; }
      if (m.type === 'boar' || m.type === 'bear') this.game.sfx('growl', m.pos);
    } else if (fromPlayer) {
      m.state = 'combat';
      m.lostT = 0;
    }
  }

  kill(m) {
    m.dead = true;
    m.hp = 0;
    m.deadT = 0;
    // кладём тело на бок и центрируем
    m.body.rotation.z = Math.PI / 2;
    if (m.flash) m.flash.visible = false;
    if (m.animal) {
      m.body.position.set(m.def.by, m.def.body[0] / 2, 0);
      m.amount = m.def.meat;
      m.name = `Туша (${m.def.name})`;
    } else {
      m.body.position.set(0.9, 0.26, 0);
      this.game.dropBag(m.pos.x, m.pos.y, m.pos.z, rollLoot('scientist'));
      this.game.ui.notify('Учёный убит');
    }
  }

  // Разделка туши.
  harvest(m, mult) {
    const n = Math.max(1, Math.round(3 * mult));
    const got = Math.min(n, m.amount);
    m.amount -= got;
    const meat = Math.max(1, Math.round(got / 2));
    this.game.giveItem('raw_meat', meat);
    if (Math.random() < 0.6) this.game.giveItem('cloth', randi(1, 3));
    this.blood(m.pos.x, m.pos.y + 0.3, m.pos.z);
    if (m.amount <= 0) this.removeMob(m, true);
  }

  removeMob(m, respawn) {
    this.scene.remove(m.root);
    const i = this.mobs.indexOf(m);
    if (i >= 0) this.mobs.splice(i, 1);
    if (!respawn) return;
    const game = this.game;
    const delay = m.npc ? 150 : 40;
    setTimeoutGame(game, delay, () => {
      if (m.npc) this.spawnNpc(m.spawn);
      else this.spawnAnimal(m.type, game.player.pos);
    });
  }

  // ---------- ИИ ----------
  update(dt) {
    const game = this.game;
    const pl = game.player;
    const w = this.world;
    for (const m of [...this.mobs]) {
      const dx = pl.pos.x - m.pos.x, dz = pl.pos.z - m.pos.z;
      const dist = Math.hypot(dx, dz);
      if (m.dead) {
        m.deadT += dt;
        if (m.deadT > (m.animal ? 120 : 30)) this.removeMob(m, true);
        continue;
      }
      if (dist > 160) continue;
      m.timer -= dt;
      m.atk -= dt;
      let moveSpeed = 0;
      let targetYaw = m.yaw;
      const alive = pl.alive;
      if (m.animal) {
        const d = m.def;
        if (alive && d.aggro && dist < d.aggro && m.state === 'wander') { m.state = 'chase'; m.timer = 12; game.sfx('growl', m.pos); }
        if (alive && d.flee && dist < d.flee && m.state === 'wander') { m.state = 'flee'; m.timer = 6; }
        if (m.state === 'wander') {
          if (!m.target || m.timer <= 0) {
            m.target = { x: m.pos.x + rand(-20, 20), z: m.pos.z + rand(-20, 20) };
            m.timer = rand(4, 10);
            m.idle = Math.random() < 0.35;
          }
          const tx = m.target.x - m.pos.x, tz = m.target.z - m.pos.z;
          if (!m.idle && Math.hypot(tx, tz) > 1) { targetYaw = Math.atan2(tx, tz); moveSpeed = d.walk; }
        } else if (m.state === 'flee') {
          targetYaw = Math.atan2(-dx, -dz);
          moveSpeed = d.run;
          if (m.timer <= 0) m.state = 'wander';
        } else if (m.state === 'chase') {
          if (!alive || dist > 45 || m.timer <= 0) { m.state = 'wander'; m.target = null; }
          else {
            targetYaw = Math.atan2(dx, dz);
            const reach = m.r + 1.1;
            const dy = Math.abs(pl.pos.y - m.pos.y);
            if (dist > reach) moveSpeed = d.run;
            else if (m.atk <= 0 && dy < 1.6) {
              m.atk = 1.1;
              game.damagePlayer(d.dmg, m.name, m.pos);
              m.timer = 12;
            }
            if (m.hp < m.maxHp * 0.25 && m.type !== 'bear') { m.state = 'flee'; m.timer = 8; }
          }
        }
      } else {
        // учёный
        const eyeDist = Math.hypot(dist, pl.pos.y - m.pos.y);
        const home = m.spawn.home;
        if (alive && eyeDist < 40 && m.state !== 'combat') {
          if (game.hasLineOfSight(m.pos, 1.6, pl.pos, 1.5)) { m.state = 'combat'; m.lostT = 0; m.atk = 0.8; }
        }
        if (m.state === 'patrol') {
          if (!m.target || m.timer <= 0) {
            const a = rand(0, Math.PI * 2), r = rand(3, home.r * 0.8);
            m.target = { x: home.x + Math.cos(a) * r, z: home.z + Math.sin(a) * r };
            m.timer = rand(5, 12);
          }
          const tx = m.target.x - m.pos.x, tz = m.target.z - m.pos.z;
          if (Math.hypot(tx, tz) > 1) { targetYaw = Math.atan2(tx, tz); moveSpeed = 1.6; }
        } else if (m.state === 'combat') {
          targetYaw = Math.atan2(dx, dz);
          const los = alive && game.hasLineOfSight(m.pos, 1.6, pl.pos, 1.5);
          if (!los) m.lostT += dt; else m.lostT = 0;
          if (!alive || m.lostT > 6 || eyeDist > 60) { m.state = 'patrol'; m.target = null; }
          else {
            if (eyeDist > 22) moveSpeed = 2.8;
            else if (eyeDist < 8) { moveSpeed = -1.5; }
            if (los && m.atk <= 0) this.npcShoot(m, eyeDist);
          }
        }
      }
      // поворот
      const turn = clamp(angleDiff(m.yaw, targetYaw), -dt * 5, dt * 5);
      m.yaw += turn;
      // движение с проверкой препятствий
      if (moveSpeed !== 0) {
        const step = moveSpeed * dt;
        const nx = m.pos.x + Math.sin(m.yaw) * step, nz = m.pos.z + Math.cos(m.yaw) * step;
        const nh = w.getHeight(nx, nz);
        const blocked = nh < 0.4 || nh - m.pos.y > 0.8 || this.blockedAt(nx, nz, m.pos.y, m.r * 0.7);
        if (!blocked) {
          m.pos.x = nx;
          m.pos.z = nz;
          m.phase += Math.abs(step) * 3;
        } else {
          m.target = null;
          m.timer = 0;
          if (m.state === 'flee' || m.state === 'chase') m.yaw += (Math.random() < 0.5 ? 1 : -1) * 0.9;
        }
      }
      m.pos.y = this.groundAt(m.pos.x, m.pos.z, m.pos.y);
      m.speed = moveSpeed;
      // анимация
      const sw = moveSpeed !== 0 ? Math.sin(m.phase) * 0.6 : 0;
      m.legs.forEach((l, i) => { l.rotation.x = (i % 2 === 0 ? sw : -sw) * (i < 2 || m.npc ? 1 : -1); });
      m.root.position.copy(m.pos);
      m.root.rotation.y = m.yaw;
      if (m.flash) {
        m.flashT = (m.flashT || 0) - dt;
        m.flash.visible = m.flashT > 0;
      }
    }
  }

  blockedAt(x, z, y, r) {
    const list = this.world.colliders.query(x - r, z - r, x + r, z + r);
    for (const c of list) {
      if (c.maxY <= y + 0.5 || c.minY >= y + 1.5) continue;
      if (x + r > c.minX && x - r < c.maxX && z + r > c.minZ && z - r < c.maxZ) return true;
    }
    return false;
  }

  groundAt(x, z, y) {
    let g = this.world.getHeight(x, z);
    const list = this.world.colliders.query(x - 0.1, z - 0.1, x + 0.1, z + 0.1);
    for (const c of list) {
      if (x < c.minX || x > c.maxX || z < c.minZ || z > c.maxZ) continue;
      if (c.maxY <= y + 0.6 && c.maxY > g) g = c.maxY;
    }
    return g;
  }

  npcShoot(m, dist) {
    const game = this.game;
    const pl = game.player;
    m.burst = (m.burst || 0) + 1;
    m.atk = m.burst % 4 === 0 ? 1.6 : 0.35;
    m.flashT = 0.06;
    game.sfx('npcshot', m.pos);
    const moving = pl.moveSpeed > 1 ? 0.2 : 0;
    const p = clamp(0.72 - dist / 42 - moving, 0.08, 0.65);
    const from = new THREE.Vector3(m.pos.x + Math.sin(m.yaw) * 1.3, m.pos.y + 1.5, m.pos.z + Math.cos(m.yaw) * 1.3);
    const to = new THREE.Vector3(pl.pos.x, pl.pos.y + 1.2, pl.pos.z);
    if (Math.random() < p) {
      game.damagePlayer(randi(5, 8), 'Учёный', m.pos);
    } else {
      to.x += rand(-1.5, 1.5); to.y += rand(-0.5, 1.5); to.z += rand(-1.5, 1.5);
    }
    this.tracer(from, to, 0xffe08a);
  }

  // ---------- Сумки ----------
  addBag(x, y, z, items, life = 600) {
    const b = { kind: 'bag', x, y, z, inv: new Inventory(24), t: life, name: 'Мешок с лутом' };
    for (const it of items) {
      if (it.ammo !== undefined) b.inv.addStack({ ...it });
      else b.inv.add(it.id, it.n);
    }
    b.mesh = new THREE.Mesh(bagGeo, bagMat);
    b.mesh.position.set(x, y + 0.2, z);
    b.mesh.rotation.y = rand(0, 6);
    b.mesh.castShadow = true;
    this.scene.add(b.mesh);
    this.bags.push(b);
    return b;
  }

  removeBag(b) {
    this.scene.remove(b.mesh);
    const i = this.bags.indexOf(b);
    if (i >= 0) this.bags.splice(i, 1);
  }

  // ---------- Стрелы ----------
  shootArrow(o, dir, speed, dmg) {
    const mesh = new THREE.Mesh(arrowGeo, arrowMat);
    mesh.position.copy(o);
    this.scene.add(mesh);
    this.arrows.push({ pos: o.clone(), vel: dir.clone().multiplyScalar(speed), mesh, life: 6, dmg, stuck: false });
  }

  updateArrows(dt) {
    const tmp = new THREE.Vector3();
    for (let i = this.arrows.length - 1; i >= 0; i--) {
      const a = this.arrows[i];
      a.life -= dt;
      if (a.life <= 0) { this.scene.remove(a.mesh); this.arrows.splice(i, 1); continue; }
      if (a.stuck) continue;
      a.vel.y -= 9.8 * dt * 0.6;
      const len = a.vel.length() * dt;
      tmp.copy(a.vel).normalize();
      const hit = this.game.raycast(a.pos, tmp, len, { skipPlayer: true });
      if (hit) {
        a.pos.addScaledVector(tmp, hit.t);
        a.stuck = true;
        a.life = 10;
        if (hit.kind === 'mob') {
          this.damage(hit.obj, a.dmg);
          this.game.ui.hitmarker();
          this.game.sfx('flesh', a.pos);
          this.scene.remove(a.mesh);
          this.arrows.splice(i, 1);
          continue;
        }
        this.game.sfx('wood', a.pos, 0.5);
      } else {
        a.pos.addScaledVector(tmp, len);
      }
      a.mesh.position.copy(a.pos);
      a.mesh.lookAt(tmp.add(a.pos));
    }
  }

  // ---------- Ракеты ----------
  shootRocket(o, dir, speed) {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.5, 10), new THREE.MeshStandardMaterial({ color: 0x5a5a4a, roughness: 0.6 }));
    body.rotation.x = Math.PI / 2;
    const nose = new THREE.Mesh(new THREE.ConeGeometry(0.05, 0.16, 10), body.material);
    nose.rotation.x = -Math.PI / 2;
    nose.position.z = -0.33;
    g.add(body, nose);
    const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.gfx.T.flame, blending: THREE.AdditiveBlending, depthWrite: false }));
    glow.scale.setScalar(0.6);
    glow.position.z = 0.3;
    g.add(glow);
    g.position.copy(o);
    this.scene.add(g);
    this.rockets = this.rockets || [];
    this.rockets.push({ g, pos: o.clone(), vel: dir.clone().multiplyScalar(speed), life: 8, trail: 0 });
  }

  updateRockets(dt) {
    if (!this.rockets) return;
    const tmp = new THREE.Vector3();
    for (let i = this.rockets.length - 1; i >= 0; i--) {
      const r = this.rockets[i];
      r.life -= dt;
      r.vel.y -= 2.5 * dt;
      const len = r.vel.length() * dt;
      tmp.copy(r.vel).normalize();
      const hit = this.game.raycast(r.pos, tmp, len, {});
      if (hit || r.life <= 0 || r.pos.y < -2) {
        const pt = hit ? r.pos.clone().addScaledVector(tmp, hit.t) : r.pos.clone();
        this.scene.remove(r.g);
        this.rockets.splice(i, 1);
        this.game.explode(pt);
        continue;
      }
      r.pos.addScaledVector(tmp, len);
      r.g.position.copy(r.pos);
      r.g.lookAt(tmp.clone().add(r.pos));
      r.g.rotateY(Math.PI);
      r.trail -= dt;
      if (r.trail <= 0) {
        r.trail = 0.02;
        this.burst(r.pos.x, r.pos.y, r.pos.z, 0x8a8680, 2, 0.6, { grav: -1.2, life: 1.6, size: 2.2, up: 0.4 });
        this.burst(r.pos.x, r.pos.y, r.pos.z, 0xffa040, 1, 0.5, { glow: true, size: 0.8, life: 0.15 });
      }
    }
  }

  // Короткая яркая вспышка (взрыв).
  flash(pt, size) {
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.gfx.T.flame, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    sp.position.copy(pt);
    sp.scale.setScalar(size);
    this.scene.add(sp);
    this.flashes = this.flashes || [];
    this.flashes.push({ sp, t: 0.35, size });
  }

  // ---------- Трассеры ----------
  tracer(from, to, color = 0xffffaa) {
    const g = new THREE.BufferGeometry().setFromPoints([from, to]);
    const l = new THREE.Line(g, new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.9 }));
    this.scene.add(l);
    this.tracers.push({ l, t: 0.08 });
  }

  // ---------- Частицы ----------
  initParticles() {
    const make = (mat, N) => {
      const im = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.045, 0), mat, N);
      im.frustumCulled = false;
      const m = new THREE.Matrix4().makeScale(0, 0, 0);
      const c = new THREE.Color(1, 1, 1);
      const parts = [];
      for (let i = 0; i < N; i++) {
        im.setMatrixAt(i, m);
        im.setColorAt(i, c);
        parts.push({ life: 0, max: 1, p: new THREE.Vector3(), v: new THREE.Vector3(), g: 12, size: 1, spin: 0 });
      }
      this.scene.add(im);
      return { im, parts, next: 0, N };
    };
    // обычные частицы (щепки, пыль, кровь, листья) и светящиеся искры
    this.psolid = make(new THREE.MeshStandardMaterial({ roughness: 0.9 }), 360);
    this.pglow = make(new THREE.MeshBasicMaterial({ toneMapped: false }), 160);
  }

  // opts: glow — светящиеся искры, grav — гравитация, size — размер, life — время жизни
  burst(x, y, z, color, n = 8, spd = 3, opts = {}) {
    const sys = opts.glow ? this.pglow : this.psolid;
    const col = new THREE.Color(color);
    if (opts.glow) col.multiplyScalar(3);
    for (let i = 0; i < n; i++) {
      const idx = sys.next = (sys.next + 1) % sys.N;
      const p = sys.parts[idx];
      p.max = p.life = (opts.life || 0.6) * rand(0.6, 1.2);
      p.p.set(x, y, z);
      p.v.set(rand(-1, 1) * spd, rand(0.3, 1.4) * spd * (opts.up ?? 1), rand(-1, 1) * spd);
      p.g = opts.grav ?? 12;
      p.size = (opts.size || 1) * rand(0.6, 1.4);
      sys.im.setColorAt(idx, col);
    }
    sys.im.instanceColor.needsUpdate = true;
  }

  blood(x, y, z) {
    this.burst(x, y, z, 0x7a0a0a, 12, 2.5, { size: 1.1 });
  }

  // Набор эффектов попадания по материалу.
  impact(x, y, z, kind) {
    switch (kind) {
      case 'wood':
        this.burst(x, y, z, 0x8a6238, 8, 3, { size: 1.3 });
        break;
      case 'leaves':
        this.burst(x, y, z, 0x4f7a2e, 6, 1.2, { grav: 1.5, life: 2.2, size: 1.4, up: 0.3 });
        break;
      case 'stone':
        this.burst(x, y, z, 0x8d8a84, 8, 3, { size: 1.1 });
        this.burst(x, y, z, 0xffb050, 5, 5, { glow: true, size: 0.5, life: 0.35 });
        break;
      case 'metal':
        this.burst(x, y, z, 0xffc070, 9, 5.5, { glow: true, size: 0.45, life: 0.4 });
        break;
      case 'dirt':
        this.burst(x, y, z, 0x5e4a30, 7, 2.2, { size: 1.2 });
        break;
      default:
        this.burst(x, y, z, 0x9a9a9a, 5, 2);
    }
  }

  updateParticles(dt) {
    const m = new THREE.Matrix4();
    for (const sys of [this.psolid, this.pglow]) {
      let any = false;
      for (let i = 0; i < sys.N; i++) {
        const p = sys.parts[i];
        if (p.life <= 0) continue;
        any = true;
        p.life -= dt;
        p.v.y -= p.g * dt;
        if (p.g < 3) { p.v.x *= 1 - dt; p.v.z *= 1 - dt; p.p.x += Math.sin(p.life * 5 + i) * dt * 0.4; }
        p.p.addScaledVector(p.v, dt);
        const s = p.life > 0 ? p.size * Math.min(1, (p.life / p.max) * 2.5) : 0;
        m.makeScale(s, s, s).setPosition(p.p);
        sys.im.setMatrixAt(i, m);
      }
      if (any) sys.im.instanceMatrix.needsUpdate = true;
    }
  }

  updateFx(dt) {
    this.updateArrows(dt);
    this.updateRockets(dt);
    if (this.flashes) {
      for (let i = this.flashes.length - 1; i >= 0; i--) {
        const f = this.flashes[i];
        f.t -= dt;
        f.sp.material.opacity = Math.max(0, f.t / 0.35);
        f.sp.scale.setScalar(f.size * (1.4 - f.t));
        if (f.t <= 0) { this.scene.remove(f.sp); f.sp.material.dispose(); this.flashes.splice(i, 1); }
      }
    }
    this.updateParticles(dt);
    for (let i = this.tracers.length - 1; i >= 0; i--) {
      const t = this.tracers[i];
      t.t -= dt;
      if (t.t <= 0) {
        this.scene.remove(t.l);
        t.l.geometry.dispose();
        t.l.material.dispose();
        this.tracers.splice(i, 1);
      }
    }
    for (let i = this.bags.length - 1; i >= 0; i--) {
      const b = this.bags[i];
      b.t -= dt;
      if (b.t <= 0) this.removeBag(b);
    }
  }

  // ---------- Луч ----------
  raycast(o, d, best) {
    for (const m of this.mobs) {
      if (Math.abs(m.pos.x - o.x) > best.t + 3 || Math.abs(m.pos.z - o.z) > best.t + 3) continue;
      let t;
      if (m.dead) t = raySphere(o, d, m.pos.x, m.pos.y + 0.35, m.pos.z, m.animal ? m.r + 0.2 : 0.7, best.t);
      else t = rayCylY(o, d, m.pos.x, m.pos.z, m.r, m.pos.y, m.pos.y + m.h, best.t);
      if (t >= 0 && t < best.t) { best.t = t; best.kind = 'mob'; best.obj = m; }
    }
    for (const b of this.bags) {
      const t = raySphere(o, d, b.x, b.y + 0.2, b.z, 0.4, best.t);
      if (t >= 0 && t < best.t) { best.t = t; best.kind = 'bag'; best.obj = b; }
    }
    return best;
  }

  serializeBags() {
    return this.bags.map((b) => ({ x: b.x, y: b.y, z: b.z, t: b.t, items: b.inv.serialize() }));
  }

  loadBags(arr) {
    for (const b of [...this.bags]) this.removeBag(b);
    for (const b of arr || []) {
      const bag = this.addBag(b.x, b.y, b.z, [], b.t);
      bag.inv.load(b.items);
    }
  }
}

// Таймеры в игровом времени (не тикают на паузе).
function setTimeoutGame(game, sec, fn) {
  game.timers.push({ t: sec, fn });
}
