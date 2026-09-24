// События мира: грузовой самолёт сбрасывает ящик на парашюте с сигнальным дымом.
import * as THREE from './three.module.min.js';
import { rand, clamp } from './util.js';
import { HALF } from './world.js';

const PLANE_H = 115, PLANE_SPEED = 55;

export class Events {
  constructor(game) {
    this.game = game;
    this.timer = rand(200, 320);
    this.plane = null;
    this.falling = [];
    this.smokers = [];
    this.engineVol = 0;
    const M = game.gfx.M;
    this.planeMat = M.rustMetal.clone();
    this.planeMat.color.setHex(0x8e969a);
    this.chuteMat = new THREE.MeshStandardMaterial({ color: 0xd8d0c0, side: THREE.DoubleSide, roughness: 1 });
    this.chuteMat2 = new THREE.MeshStandardMaterial({ color: 0xb8402e, side: THREE.DoubleSide, roughness: 1 });
    // пул спрайтов дыма
    this.smoke = [];
    for (let i = 0; i < 70; i++) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({
        map: game.gfx.T.cloud, color: 0xc84a36, transparent: true, depthWrite: false, opacity: 0,
      }));
      sp.visible = false;
      game.scene.add(sp);
      this.smoke.push({ sp, life: 0 });
    }
    this.smokeNext = 0;
    this.emitT = 0;
  }

  buildPlane() {
    const g = new THREE.Group();
    const m = this.planeMat;
    const add = (geo, x, y, z, rx = 0, ry = 0, rz = 0) => {
      const o = new THREE.Mesh(geo, m);
      o.position.set(x, y, z);
      o.rotation.set(rx, ry, rz);
      o.castShadow = true;
      g.add(o);
      return o;
    };
    // корпус вдоль оси X
    add(new THREE.CylinderGeometry(1.5, 1.3, 20, 14), 0, 0, 0, 0, 0, Math.PI / 2);
    add(new THREE.SphereGeometry(1.5, 14, 10, 0, Math.PI * 2, 0, Math.PI / 2), 10, 0, 0, 0, 0, -Math.PI / 2);
    add(new THREE.ConeGeometry(1.3, 5, 14), -12.5, 0.3, 0, 0, 0, Math.PI / 2);
    add(new THREE.BoxGeometry(4.5, 0.35, 32), 1.5, 0.6, 0);
    add(new THREE.BoxGeometry(2.6, 0.25, 10), -13, 0.6, 0);
    add(new THREE.BoxGeometry(3.2, 4, 0.3), -13, 2.4, 0);
    const glass = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.5, 2), new THREE.MeshStandardMaterial({ color: 0x223040, roughness: 0.2, metalness: 0.6 }));
    glass.position.set(9.6, 0.8, 0);
    g.add(glass);
    this.props = [];
    for (const z of [-10, -5, 5, 10]) {
      add(new THREE.CylinderGeometry(0.6, 0.55, 3.2, 10), 2.8, 0.1, z, 0, 0, Math.PI / 2);
      const prop = new THREE.Group();
      prop.position.set(4.5, 0.1, z);
      const blade = new THREE.Mesh(new THREE.BoxGeometry(0.1, 3.4, 0.25), m);
      const blade2 = blade.clone();
      blade2.rotation.x = Math.PI / 2;
      prop.add(blade, blade2);
      g.add(prop);
      this.props.push(prop);
    }
    return g;
  }

  buildChuteCrate() {
    const g = new THREE.Group();
    const crate = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.0, 1.4), this.game.gfx.M.crateMil);
    crate.position.y = 0.5;
    crate.castShadow = true;
    g.add(crate);
    const chute = new THREE.Group();
    chute.position.y = 6;
    for (let i = 0; i < 8; i++) {
      const seg = new THREE.Mesh(
        new THREE.SphereGeometry(3.2, 4, 8, (i / 8) * Math.PI * 2, Math.PI / 4, 0, Math.PI / 2.4),
        i % 2 ? this.chuteMat : this.chuteMat2,
      );
      chute.add(seg);
    }
    const pts = [];
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      pts.push(new THREE.Vector3(Math.cos(a) * 0.6, 1.0, Math.sin(a) * 0.6));
      pts.push(new THREE.Vector3(Math.cos(a) * 2.3, 6.3, Math.sin(a) * 2.3));
    }
    const lines = new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(pts), new THREE.LineBasicMaterial({ color: 0x444444 }));
    g.add(chute, lines);
    g.userData.chute = chute;
    return g;
  }

  spawnPlane() {
    const w = this.game.world;
    const target = w.randomLandPoint(3, 25, 12, 0.5) || { x: 0, z: 0 };
    const a = Math.random() * Math.PI * 2;
    const dir = new THREE.Vector3(Math.cos(a), 0, Math.sin(a));
    const start = new THREE.Vector3(target.x, PLANE_H, target.z).addScaledVector(dir, -(HALF + 350));
    const mesh = this.buildPlane();
    mesh.position.copy(start);
    mesh.rotation.y = -a;
    this.game.scene.add(mesh);
    this.plane = { mesh, dir, target, dropped: false };
    this.game.ui.notify('✈ Грузовой самолёт летит над островом! Следите за красным дымом');
  }

  update(dt) {
    const game = this.game;
    this.timer -= dt;
    if (this.timer <= 0 && !this.plane) {
      this.spawnPlane();
      this.timer = rand(480, 780);
    }
    const cam = game.camera.position;
    this.engineVol = 0;
    if (this.plane) {
      const P = this.plane;
      P.mesh.position.addScaledVector(P.dir, PLANE_SPEED * dt);
      for (const pr of this.props) pr.rotation.x += dt * 30;
      const pos = P.mesh.position;
      if (!P.dropped) {
        const to = new THREE.Vector3(P.target.x - pos.x, 0, P.target.z - pos.z);
        if (to.dot(P.dir) <= 0) {
          P.dropped = true;
          const g = this.buildChuteCrate();
          g.position.set(pos.x, pos.y - 3, pos.z);
          game.scene.add(g);
          this.falling.push({ g, t: 0 });
        }
      }
      const d = cam.distanceTo(pos);
      this.engineVol = clamp(1 - d / 450, 0, 1) * 0.12;
      if (Math.hypot(pos.x, pos.z) > HALF + 400 && P.dropped) {
        game.scene.remove(P.mesh);
        this.plane = null;
      }
    }
    // падение ящика
    for (let i = this.falling.length - 1; i >= 0; i--) {
      const f = this.falling[i];
      f.t += dt;
      const g = f.g;
      g.position.y -= dt * 4.5;
      g.rotation.z = Math.sin(f.t * 0.8) * 0.06;
      g.rotation.x = Math.cos(f.t * 0.6) * 0.06;
      const ground = game.ents.groundAt(g.position.x, g.position.z, g.position.y + 1);
      if (g.position.y <= ground) {
        game.scene.remove(g);
        this.falling.splice(i, 1);
        const c = game.world.addCrate(g.position.x, ground, g.position.z, 'airdrop');
        c.oneshot = true;
        c.expire = game.world.time + 900;
        this.smokers.push({ c, t: 240 });
        game.sfx('thud', c);
      }
    }
    // дым
    this.emitT -= dt;
    for (let i = this.smokers.length - 1; i >= 0; i--) {
      const s = this.smokers[i];
      s.t -= dt;
      if (s.t <= 0 || !game.world.crates.includes(s.c)) { this.smokers.splice(i, 1); continue; }
      if (this.emitT <= 0) {
        const p = this.smoke[this.smokeNext = (this.smokeNext + 1) % this.smoke.length];
        p.life = 7;
        p.sp.visible = true;
        p.sp.position.set(s.c.x + rand(-0.3, 0.3), s.c.y + 1.1, s.c.z + rand(-0.3, 0.3));
        p.vx = rand(0.5, 1.2);
        p.vz = rand(-0.3, 0.3);
      }
    }
    if (this.emitT <= 0) this.emitT = 0.12;
    for (const p of this.smoke) {
      if (p.life <= 0) continue;
      p.life -= dt;
      if (p.life <= 0) { p.sp.visible = false; continue; }
      const k = 1 - p.life / 7;
      p.sp.position.y += dt * (3.2 - k * 1.5);
      p.sp.position.x += dt * p.vx * (0.5 + k * 2);
      p.sp.position.z += dt * p.vz;
      const sc = 1.2 + k * 7;
      p.sp.scale.set(sc, sc, 1);
      p.sp.material.opacity = Math.min(1, (1 - k) * 1.4) * 0.75;
    }
  }

  // Метки для карты и компаса.
  markers() {
    const out = [];
    for (const s of this.smokers) out.push({ x: s.c.x, z: s.c.z, icon: '📦', name: 'Аирдроп' });
    for (const f of this.falling) out.push({ x: f.g.position.x, z: f.g.position.z, icon: '🪂', name: 'Аирдроп' });
    if (this.plane) out.push({ x: this.plane.mesh.position.x, z: this.plane.mesh.position.z, icon: '✈️', name: 'Самолёт' });
    return out;
  }
}
