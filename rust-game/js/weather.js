// Погода: ясно, облачно, дождь, гроза с молниями.
import * as THREE from './three.module.min.js';
import { rand } from './util.js';

const STATES = [
  { p: 0.5, cloud: 0.1, rain: 0, storm: false, name: 'ясно' },
  { p: 0.22, cloud: 0.6, rain: 0, storm: false, name: 'облачно' },
  { p: 0.17, cloud: 0.85, rain: 0.7, storm: false, name: 'дождь' },
  { p: 0.11, cloud: 1, rain: 1, storm: true, name: 'гроза' },
];

export class Weather {
  constructor(game) {
    this.game = game;
    this.cloud = 0.1;
    this.rain = 0;
    this.wet = 0;
    this.storm = false;
    this.target = STATES[0];
    this.timer = rand(150, 260);
    this.flash = 0;
    this.nextBolt = 8;

    const N = game.gfx.q.grass > 0 ? 4000 : 1500;
    this.N = N;
    this.drops = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      this.drops[i * 3] = rand(-25, 25);
      this.drops[i * 3 + 1] = rand(-6, 24);
      this.drops[i * 3 + 2] = rand(-25, 25);
    }
    this.geo = new THREE.BufferGeometry();
    this.pos = new Float32Array(N * 6);
    this.geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    this.lines = new THREE.LineSegments(this.geo, new THREE.LineBasicMaterial({
      color: 0xb8c4d0, transparent: true, opacity: 0, depthWrite: false,
    }));
    this.lines.frustumCulled = false;
    this.lines.visible = false;
    game.scene.add(this.lines);
  }

  set(i) {
    this.target = STATES[i];
    this.timer = rand(150, 300);
  }

  pickNext() {
    let r = Math.random();
    for (let i = 0; i < STATES.length; i++) {
      r -= STATES[i].p;
      if (r <= 0) { this.set(i); return; }
    }
    this.set(0);
  }

  update(dt, cam) {
    this.timer -= dt;
    if (this.timer <= 0) this.pickNext();
    const t = this.target;
    this.cloud += (t.cloud - this.cloud) * Math.min(1, dt * 0.06);
    this.rain += (t.rain - this.rain) * Math.min(1, dt * (t.rain > this.rain ? 0.05 : 0.08));
    if (t.rain === 0 && this.rain < 0.005) this.rain = 0;
    this.wet += ((this.rain > 0.2 ? 1 : 0) - this.wet) * Math.min(1, dt * (this.rain > 0.2 ? 0.08 : 0.02));
    this.storm = t.storm && this.rain > 0.6;

    // капли
    const vis = this.rain > 0.02 && cam.y > -0.5;
    this.lines.visible = vis;
    if (vis) {
      this.lines.material.opacity = Math.min(0.5, this.rain * 0.55);
      const d = this.drops, p = this.pos;
      const fall = 24 * dt, wx = 1.5, wz = 0.8;
      for (let i = 0; i < this.N; i++) {
        const k = i * 3;
        d[k + 1] -= fall;
        d[k] += wx * dt;
        d[k + 2] += wz * dt;
        if (d[k + 1] < -6) {
          d[k + 1] += 30;
          d[k] = rand(-25, 25);
          d[k + 2] = rand(-25, 25);
        }
        const x = cam.x + d[k], y = cam.y + d[k + 1], z = cam.z + d[k + 2];
        const j = i * 6;
        p[j] = x; p[j + 1] = y; p[j + 2] = z;
        p[j + 3] = x - wx * 0.03; p[j + 4] = y + 0.55; p[j + 5] = z - wz * 0.03;
      }
      this.geo.attributes.position.needsUpdate = true;
    }

    // молнии
    if (this.storm) {
      this.nextBolt -= dt;
      if (this.nextBolt <= 0) {
        this.nextBolt = rand(6, 16);
        this.flash = 1;
        this.game.timers.push({ t: 0.12, fn: () => { this.flash = 0.8; } });
        const delay = rand(0.3, 2.5);
        this.game.timers.push({ t: delay, fn: () => this.game.sfx('thunder', null, 1 - delay * 0.25) });
      }
    }
    this.flash = Math.max(0, this.flash - dt * 6);
  }

  serialize() {
    return { i: STATES.indexOf(this.target), timer: this.timer };
  }

  load(s) {
    if (!s || !STATES[s.i]) return;
    this.target = STATES[s.i];
    this.timer = s.timer || 200;
    this.cloud = this.target.cloud;
    this.rain = this.target.rain;
  }
}
