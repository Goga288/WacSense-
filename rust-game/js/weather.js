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

    // капли дождя целиком считаются на видеокарте (вершинный шейдер)
    const N = game.gfx.q.grass > 0 ? 6000 : 2000;
    const pos = new Float32Array(N * 6);
    const seed = new Float32Array(N * 6);
    const top = new Float32Array(N * 2);
    for (let i = 0; i < N; i++) {
      const sx = rand(0, 50), sy = rand(0, 30), sz = rand(0, 50);
      for (let k = 0; k < 2; k++) {
        seed.set([sx, sy, sz], i * 6 + k * 3);
        top[i * 2 + k] = k;
      }
    }
    this.geo = new THREE.BufferGeometry();
    this.geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.geo.setAttribute('seed', new THREE.BufferAttribute(seed, 3));
    this.geo.setAttribute('top', new THREE.BufferAttribute(top, 1));
    this.uni = { uTime: { value: 0 }, uCam: { value: new THREE.Vector3() }, uOpacity: { value: 0 } };
    this.lines = new THREE.LineSegments(this.geo, new THREE.ShaderMaterial({
      uniforms: this.uni,
      vertexShader: `
        attribute vec3 seed; attribute float top;
        uniform float uTime; uniform vec3 uCam;
        void main() {
          vec3 l = vec3(mod(seed.x + uTime * 1.5, 50.0) - 25.0, mod(seed.y - uTime * 24.0, 30.0) - 6.0, mod(seed.z + uTime * 0.8, 50.0) - 25.0);
          vec3 p = uCam + l + top * vec3(-0.045, 0.55, -0.024);
          gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
        }`,
      fragmentShader: `
        uniform float uOpacity;
        void main() { gl_FragColor = vec4(0.72, 0.77, 0.82, uOpacity); }`,
      transparent: true,
      depthWrite: false,
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
    this.uni.uTime.value += dt;
    this.uni.uCam.value.copy(cam);
    this.uni.uOpacity.value = Math.min(0.5, this.rain * 0.55);

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
