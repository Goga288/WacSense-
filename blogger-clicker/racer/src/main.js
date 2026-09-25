// «Шашки по городу» — гонка в потоке. Запускается из кликера: Racer.startRace({...}).
import * as THREE from './three.module.min.js';
import { Sky } from './Sky.js';
import * as TX from './textures.js';
import { buildCar, carMaterials, SPECS } from './car.js';
import { City, LANES, ROAD_HALF } from './city.js';
import { Traffic } from './traffic.js';
import * as SND from './audio.js';

const TIMES = {
  day: { sun: [0.45, 0.8, -0.35], sunI: 2.9, hemi: 0.55, fog: 0xc4d6e8, turb: 2.5, ray: 1.1, exposure: 1.0, sunColor: 0xfff4e6 },
  sunset: { sun: [0.95, 0.07, -0.35], sunI: 2.2, hemi: 0.35, fog: 0xe0a67c, turb: 6, ray: 2.6, exposure: 1.0, sunColor: 0xffae6a },
  night: { sun: [0.3, 0.6, -0.4], sunI: 0.25, hemi: 0.14, fog: 0x0b111c, exposure: 1.15, sunColor: 0x9fb6ff },
};
const GEARS = [0, 30, 55, 85, 120, 165, 400];

const CSS = `
#raceLayer{position:fixed;inset:0;z-index:100;background:#000;font-family:'Segoe UI',Roboto,Arial,sans-serif;color:#fff;user-select:none;touch-action:none}
#raceLayer canvas{position:absolute;inset:0;width:100%;height:100%;display:block}
#raceLayer .hidden{display:none!important}
.rc-top{position:absolute;left:12px;top:10px;display:flex;flex-direction:column;gap:6px;font-size:16px}
.rc-top div{background:rgba(0,0,0,.45);padding:4px 12px;border-radius:10px}
.rc-btns{position:absolute;right:10px;top:10px;display:flex;gap:8px}
.rc-btns button{width:46px;height:46px;border-radius:50%;border:none;background:rgba(0,0,0,.5);color:#fff;font-size:20px;cursor:pointer}
#rcPop{position:absolute;left:50%;top:18%;transform:translateX(-50%);font-size:30px;font-weight:900;color:#ffe066;text-shadow:0 3px 0 #7a3a00,0 0 12px rgba(0,0,0,.6);pointer-events:none;white-space:nowrap}
#rcPop.show{animation:rcpop .9s ease-out forwards}
@keyframes rcpop{0%{transform:translateX(-50%) scale(.6);opacity:0}15%{transform:translateX(-50%) scale(1.15);opacity:1}100%{transform:translateX(-50%) translateY(-40px) scale(1);opacity:0}}
.rc-speed{position:absolute;left:50%;bottom:14px;transform:translateX(-50%);text-align:center;background:rgba(0,0,0,.45);padding:4px 18px;border-radius:14px;min-width:150px}
.rc-speed b{font-size:44px;font-weight:900;font-variant-numeric:tabular-nums}
.rc-speed span{font-size:14px;margin-left:4px;opacity:.8}
.rc-speed i{display:block;font-style:normal;font-size:13px;opacity:.85}
#raceLayer.cockpit .rc-speed{left:auto;right:12px;top:66px;bottom:auto;transform:none;min-width:0;padding:2px 12px}
#raceLayer.cockpit .rc-speed b{font-size:30px}
#rcCount{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:110px;font-weight:900;text-shadow:0 6px 0 rgba(0,0,0,.4);pointer-events:none}
.rc-touch button{position:absolute;bottom:20px;width:84px;height:84px;border-radius:50%;border:3px solid rgba(255,255,255,.35);background:rgba(0,0,0,.35);color:#fff;font-size:34px;touch-action:none}
.rc-touch button.on{background:rgba(255,255,255,.3)}
#rcL{left:18px}#rcR{left:114px}#rcBrake{right:114px}#rcGas{right:18px;height:110px;border-radius:40px}
#rcResult{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.55)}
#rcResult .box{background:linear-gradient(180deg,#5b2bb5,#3a1d8a);border:3px solid #ffd23f;border-radius:18px;padding:20px 24px;text-align:center;min-width:280px;max-width:92vw}
#rcResult h2{font-size:28px;margin-bottom:10px}
#rcResult p{font-size:16px;margin:4px 0}
#rcResult .coins{font-size:30px;font-weight:900;color:#ffe066;margin:10px 0}
#rcResult button{display:block;position:static;transform:none;box-shadow:none;width:100%;margin-top:8px;padding:12px;border:none;border-radius:12px;font-weight:900;font-size:16px;cursor:pointer;background:#ffd23f;color:#3a1d8a}
#rcResult button.ad{background:#22c55e;color:#fff}
#rcResult button.alt{background:rgba(255,255,255,.15);color:#fff}
`;

function fmt(n) {
  n = Math.floor(n);
  const u = [[1e12, ' трлн'], [1e9, ' млрд'], [1e6, ' млн'], [1e3, ' тыс']];
  for (const [v, s] of u) if (n >= v) return (n / v).toFixed(n / v < 10 ? 2 : 1).replace('.', ',') + s;
  return String(n);
}

class Race {
  constructor(o) {
    this.o = o;
    this.time = TIMES[o.time] ? o.time : 'day';
    this.T = TIMES[this.time];
    this.night = this.time === 'night';
    this.mobile = !!o.mobile;
    this.buildDom();
    const R = this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance' });
    R.setPixelRatio(Math.min(window.devicePixelRatio || 1, this.mobile ? 1.5 : 2));
    R.setSize(innerWidth, innerHeight);
    R.toneMapping = THREE.NeutralToneMapping;
    R.toneMappingExposure = this.T.exposure;
    R.shadowMap.enabled = true;
    R.shadowMap.type = THREE.PCFShadowMap;
    TX.setAniso(R.capabilities.getMaxAnisotropy());

    const S = this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.05, 900);
    S.fog = new THREE.Fog(this.T.fog, this.night ? 30 : 70, this.night ? 260 : 430);
    this.sunDir = new THREE.Vector3(...this.T.sun).normalize();
    this.envMap = this.makeSky();
    this.hemi = new THREE.HemisphereLight(this.night ? 0x3a4a70 : 0xcfe2ff, 0x3a3630, this.T.hemi);
    S.add(this.hemi);
    const sun = this.sun = new THREE.DirectionalLight(this.T.sunColor, this.T.sunI);
    sun.castShadow = true;
    const ss = this.mobile ? 1024 : 2048;
    sun.shadow.mapSize.set(ss, ss);
    Object.assign(sun.shadow.camera, { left: -32, right: 32, top: 32, bottom: -32, near: 1, far: 250 });
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.03;
    S.add(sun, sun.target);

    const T = {
      tire: TX.tireTex(), leather: TX.leatherTex(o.interior === 'red' ? '#5a1614' : '#2a2320'), soft: TX.softTouchTex(), carbon: TX.carbonTex(),
      fabric: TX.fabricTex(), dials: TX.dialsTex(), nav: TX.navTex(), plate: TX.plateTex,
    };
    this.M = carMaterials(T, this.envMap);
    this.M.head.emissiveIntensity = this.night ? 3 : 0.35;
    this.M.tail.emissiveIntensity = this.night ? 1.6 : 0.6;
    this.city = new City(S, this.envMap, this.night);
    if (!this.night) this.city.M.pool.visible = false;
    this.traffic = new Traffic(S, this.M);

    const kind = SPECS[o.car] ? o.car : 'sedan';
    this.car = buildCar(kind, o.color || 0xc0392b, this.M, { interiorFull: true, plateSeed: 777 });
    this.car.root.rotation.order = 'YXZ';
    // собственные материалы стоп-сигналов и фар игрока
    this.myTail = this.M.tail.clone();
    this.myHead = this.M.head.clone();
    for (const m of this.car.lights.tail) m.material = this.myTail;
    for (const m of this.car.lights.head) m.material = this.myHead;
    S.add(this.car.root);
    if (this.night) {
      for (const sx of [-0.6, 0.6]) {
        const sp = new THREE.SpotLight(0xfff2dc, 80, 90, 0.42, 0.55, 1.4);
        sp.position.set(sx, 0.75, -this.car.spec.L / 2);
        sp.target.position.set(sx * 1.5, 0, -this.car.spec.L / 2 - 25);
        this.car.root.add(sp, sp.target);
      }
    }
    this.reset();
    this.bindInput();
    this.onResize = () => {
      R.setSize(innerWidth, innerHeight);
      this.camera.aspect = innerWidth / innerHeight;
      this.camera.updateProjectionMatrix();
    };
    addEventListener('resize', this.onResize);
    this.onVis = () => { this.paused = document.hidden; SND.suspend(document.hidden); };
    document.addEventListener('visibilitychange', this.onVis);
    SND.initAudio(o.sound !== false);
    this.last = performance.now();
    this.raf = requestAnimationFrame((t) => this.frame(t));
  }

  makeSky() {
    const pm = new THREE.PMREMGenerator(this.renderer);
    const envScene = new THREE.Scene();
    if (this.night) {
      this.scene.background = new THREE.Color(0x05080f);
      const N = 1200, p = new Float32Array(N * 3);
      for (let i = 0; i < N; i++) {
        const a = Math.random() * Math.PI * 2, y = 0.08 + Math.random() * 0.9, r = Math.sqrt(1 - y * y);
        p.set([Math.cos(a) * r * 600, y * 600, Math.sin(a) * r * 600], i * 3);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(p, 3));
      this.stars = new THREE.Points(g, new THREE.PointsMaterial({ color: 0xffffff, size: 1.5, sizeAttenuation: false, fog: false }));
      this.scene.add(this.stars);
      envScene.background = new THREE.Color(0x1a2438);
    } else {
      const sky = new Sky();
      sky.scale.setScalar(800);
      const u = sky.material.uniforms;
      u.turbidity.value = this.T.turb;
      u.rayleigh.value = this.T.ray;
      u.mieCoefficient.value = 0.004;
      u.mieDirectionalG.value = 0.8;
      u.sunPosition.value.copy(this.sunDir);
      this.sky = sky;
      this.scene.add(sky);
      const es = new Sky();
      es.scale.setScalar(100);
      for (const k of ['turbidity', 'rayleigh', 'mieCoefficient', 'mieDirectionalG']) es.material.uniforms[k].value = u[k].value;
      es.material.uniforms.sunPosition.value.copy(this.sunDir);
      envScene.add(es);
      const ground = new THREE.Mesh(new THREE.PlaneGeometry(400, 400).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x4a4844 }));
      ground.position.y = -3;
      envScene.add(ground);
    }
    const rt = pm.fromScene(envScene, 0, 0.1, 500);
    this.scene.environment = rt.texture;
    this.scene.environmentIntensity = this.night ? 0.35 : 1;
    return rt.texture;
  }

  buildDom() {
    if (!document.getElementById('raceCss')) {
      const st = document.createElement('style');
      st.id = 'raceCss';
      st.textContent = CSS;
      document.head.appendChild(st);
    }
    const L = this.layer = document.createElement('div');
    L.id = 'raceLayer';
    L.innerHTML = `<canvas></canvas>
      <div class="rc-top"><div>📏 <b id="rcDist">0 м</b></div><div>🪙 <b id="rcCoins">0</b></div><div>⚡ <b id="rcNear">0</b> впритирку</div></div>
      <div class="rc-btns"><button id="rcCam" title="Камера (C)">🎥</button><button id="rcHorn" title="Сигнал (H)">📯</button><button id="rcExit" title="Выход">✕</button></div>
      <div id="rcPop"></div>
      <div class="rc-speed"><b id="rcSpd">0</b><span>км/ч</span><i id="rcGear">Передача N</i></div>
      <div id="rcCount"></div>
      <div class="rc-touch ${this.mobile ? '' : 'hidden'}"><button id="rcL">◀</button><button id="rcR">▶</button><button id="rcBrake">⏹</button><button id="rcGas">⏫</button></div>
      <div id="rcResult" class="hidden"><div class="box"></div></div>`;
    document.body.appendChild(L);
    this.canvas = L.querySelector('canvas');
    this.el = (id) => L.querySelector('#' + id);
  }

  reset() {
    this.p = { x: LANES[1], z: 0, v: 0, vx: 0, steer: 0, dist: 0, points: 0, near: 0, combo: 1, comboT: 0, maxV: 0, rpm: 900, gear: 1, len: this.car.spec.L, width: this.car.spec.W, speed: 0 };
    this.crashed = false;
    this.done = false;
    this.count = 3.2;
    this.camMode = this.camMode || 0;
    this.shake = 0;
    this.traffic.clear();
    this.city.update(0);
    this.el('rcResult').classList.add('hidden');
  }

  bindInput() {
    this.keys = {};
    this.kd = (e) => {
      this.keys[e.code] = true;
      if (e.code === 'KeyC') this.camMode = (this.camMode + 1) % 3;
      if (e.code === 'KeyH') SND.horn(true);
      if (e.code === 'Escape') this.finish(false);
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
    };
    this.ku = (e) => { this.keys[e.code] = false; if (e.code === 'KeyH') SND.horn(false); };
    addEventListener('keydown', this.kd);
    addEventListener('keyup', this.ku);
    this.touch = { l: false, r: false, gas: false, brake: false };
    const hold = (id, key) => {
      const b = this.el(id);
      const on = (e) => { e.preventDefault(); this.touch[key] = true; b.classList.add('on'); };
      const off = (e) => { e.preventDefault(); this.touch[key] = false; b.classList.remove('on'); };
      b.addEventListener('pointerdown', on);
      b.addEventListener('pointerup', off);
      b.addEventListener('pointerleave', off);
      b.addEventListener('pointercancel', off);
    };
    hold('rcL', 'l'); hold('rcR', 'r'); hold('rcGas', 'gas'); hold('rcBrake', 'brake');
    this.el('rcCam').onclick = () => { this.camMode = (this.camMode + 1) % 3; };
    this.el('rcHorn').onpointerdown = () => SND.horn(true);
    this.el('rcHorn').onpointerup = () => SND.horn(false);
    this.el('rcExit').onclick = () => this.finish(false);
  }

  popup(text) {
    const p = this.el('rcPop');
    p.textContent = text;
    p.classList.remove('show');
    void p.offsetWidth;
    p.classList.add('show');
  }

  frame(now) {
    this.raf = requestAnimationFrame((t) => this.frame(t));
    const dt = Math.max(0, Math.min(0.05, (now - this.last) / 1000));
    this.last = now;
    if (!this.paused && dt > 0) this.update(dt);
    this.renderer.render(this.scene, this.camera);
  }

  update(dt) {
    const p = this.p, k = this.keys, t = this.touch, s = this.car.spec;
    // отсчёт
    if (this.count > 0) {
      this.count -= dt;
      const c = this.el('rcCount');
      c.textContent = this.count > 0.2 ? String(Math.ceil(this.count - 0.2)) : 'ПОЕХАЛИ!';
      if (this.count <= 0) c.textContent = '';
    }
    const racing = this.count <= 0 && !this.crashed && !this.done;
    const gas = racing && (k.KeyW || k.ArrowUp || t.gas);
    const brake = racing && (k.KeyS || k.ArrowDown || k.Space || t.brake);
    const steerIn = racing ? ((k.KeyD || k.ArrowRight || t.r) ? 1 : 0) - ((k.KeyA || k.ArrowLeft || t.l) ? 1 : 0) : 0;
    p.steer += (steerIn - p.steer) * Math.min(1, dt * 7);
    // скорость
    if (gas) p.v += s.acc * (1 - p.v / s.maxV) * dt;
    else p.v -= (0.8 + p.v * 0.01) * dt;
    if (brake) p.v -= 16 * dt;
    if (this.crashed) p.v *= Math.max(0, 1 - dt * 5);
    p.v = Math.max(0, Math.min(s.maxV, p.v));
    p.speed = p.v;
    // руление: боковая скорость зависит от скорости
    const tvx = p.steer * (2.5 + p.v * 0.13);
    p.vx += (tvx - p.vx) * Math.min(1, dt * 6);
    p.x += p.vx * dt;
    const lim = ROAD_HALF - p.width / 2 - 0.1;
    if (Math.abs(p.x) > lim) {
      p.x = Math.sign(p.x) * lim;
      p.vx *= -0.3;
      p.v *= 1 - dt * 2;
      this.shake = Math.max(this.shake, 0.25);
      SND.tires(0.2);
    }
    p.z -= p.v * dt;
    p.dist += p.v * dt;
    const kmh = p.v * 3.6;
    p.maxV = Math.max(p.maxV, kmh);
    if (racing) p.points += p.v * dt * 0.1 * (1 + Math.max(0, (kmh - 100) / 100));
    // передачи и обороты
    let g = 1;
    while (g < GEARS.length - 1 && kmh > GEARS[g]) g++;
    const lo = GEARS[g - 1], hi = GEARS[g];
    const targetRpm = 900 + ((kmh - lo) / (hi - lo)) * 5600 * (gas ? 1 : 0.85);
    p.rpm += (Math.max(800, targetRpm) - p.rpm) * Math.min(1, dt * 8);
    p.gear = kmh < 1 ? 'N' : g;
    SND.engine(p.rpm, gas ? 1 : 0, !this.crashed);
    SND.tires(brake && p.v > 10 ? 0.18 : Math.abs(p.steer) * p.v > 30 ? 0.06 : 0);

    // машина игрока
    const car = this.car, root = car.root;
    root.position.set(p.x, 0, p.z);
    const yaw = -Math.atan2(p.vx, Math.max(p.v, 4));
    root.rotation.set(brake ? 0.012 : gas ? -0.008 : 0, yaw, -p.steer * Math.min(1, p.v / 30) * 0.035);
    for (const w of car.wheels) {
      w.spin.rotation.z -= (p.v * dt) / s.R;
      if (w.front) w.pivot.rotation.y = -p.steer * 0.38;
    }
    if (car.steerWheel) car.steerWheel.rotation.x = p.steer * 2.4;
    const a0 = Math.PI * 0.75, a1 = Math.PI * 2.25;
    if (car.speedNeedle) car.speedNeedle.rotation.z = -(a0 + Math.min(1, kmh / 260) * (a1 - a0));
    if (car.rpmNeedle) car.rpmNeedle.rotation.z = -(a0 + Math.min(1, p.rpm / 8000) * (a1 - a0));
    this.myTail.emissiveIntensity = brake ? 4 : this.night ? 1.6 : 0.6;
    this.myHead.emissiveIntensity = this.night ? 3 : 0.35;

    // трафик, столкновения, «впритирку»
    this.traffic.update(dt, p, p.dist);
    if (racing) {
      for (const c of this.traffic.cars) {
        const dz = c.z - p.z, dx = c.x - p.x;
        if (Math.abs(dz) < (c.len + p.len) / 2 - 0.15 && Math.abs(dx) < (c.width + p.width) / 2 - 0.12) {
          this.crash();
          break;
        }
        if (!c.passed && dz > (c.len + p.len) / 2) {
          c.passed = true;
          const gap = Math.abs(dx) - (c.width + p.width) / 2;
          if (gap < 1.1 && p.v > 22) {
            p.near++;
            p.combo = Math.min(10, p.comboT > 0 ? p.combo + 1 : 1);
            p.comboT = 3;
            const pts = Math.round(50 * p.combo * (gap < 0.5 ? 2 : 1));
            p.points += pts;
            this.popup(`${gap < 0.5 ? 'НА ВОЛОСКЕ!' : 'ВПРИТИРКУ!'} +${pts}${p.combo > 1 ? ' ×' + p.combo : ''}`);
            SND.whoosh();
          }
        }
      }
    }
    p.comboT -= dt;
    this.city.update(p.z);

    // солнце и тени следуют за машиной
    this.sun.position.set(p.x + this.sunDir.x * 80, this.sunDir.y * 80 + 10, p.z + this.sunDir.z * 80);
    this.sun.target.position.set(p.x, 0, p.z - 10);
    if (this.sky) this.sky.position.copy(this.camera.position);
    if (this.stars) this.stars.position.copy(this.camera.position);

    this.updateCamera(dt, kmh);
    // HUD
    this.el('rcSpd').textContent = Math.round(kmh);
    this.el('rcGear').textContent = `Передача ${p.gear}`;
    this.el('rcDist').textContent = p.dist < 1000 ? `${Math.round(p.dist)} м` : `${(p.dist / 1000).toFixed(2).replace('.', ',')} км`;
    this.el('rcCoins').textContent = fmt(this.coins());
    this.el('rcNear').textContent = p.near;
  }

  coins() {
    return Math.round(this.p.points * (this.o.coinScale || 1));
  }

  updateCamera(dt, kmh) {
    const cam = this.camera, root = this.car.root, s = this.car.spec;
    this.shake = Math.max(0, this.shake - dt * 2);
    this.layer.classList.toggle('cockpit', this.camMode === 2);
    let fov = 72;
    if (this.camMode === 0) {
      // камера жёстко привязана к машине, сглаживается только поворот
      const yaw = root.rotation.y;
      this.camYaw = this.camYaw === undefined ? yaw : this.camYaw + (yaw - this.camYaw) * Math.min(1, dt * 5);
      const off = new THREE.Vector3(0, 1.0 + s.H * 0.5, s.L / 2 + 3.3).applyAxisAngle(new THREE.Vector3(0, 1, 0), this.camYaw);
      cam.position.copy(root.position).add(off);
      const look = new THREE.Vector3(0, 0.95, -10).applyAxisAngle(new THREE.Vector3(0, 1, 0), this.camYaw).add(root.position);
      cam.lookAt(look);
      fov = 64 + Math.min(20, kmh * 0.09);
    } else {
      const eye = this.camMode === 2 && this.car.eye ? this.car.eye.clone() : new THREE.Vector3(0, s.belt + 0.3, -(s.L / 2 - s.hood * 0.55));
      cam.position.copy(eye.applyQuaternion(root.quaternion).add(root.position));
      cam.quaternion.copy(root.quaternion);
      cam.rotateX(this.camMode === 2 ? -0.03 : -0.06);
      fov = this.camMode === 2 ? 64 : 70 + Math.min(12, kmh * 0.05);
    }
    const sh = this.shake + (kmh > 150 ? (kmh - 150) / 1500 : 0);
    if (sh > 0) {
      cam.rotation.x += (Math.random() - 0.5) * sh * 0.03;
      cam.rotation.y += (Math.random() - 0.5) * sh * 0.03;
    }
    if (Math.abs(cam.fov - fov) > 0.05) { cam.fov += (fov - cam.fov) * Math.min(1, dt * 4); cam.updateProjectionMatrix(); }
  }

  crash() {
    if (this.crashed) return;
    this.crashed = true;
    this.shake = 1.2;
    SND.crash();
    SND.horn(false);
    this.popup('💥 АВАРИЯ!');
    setTimeout(() => this.finish(true), 1500);
  }

  finish(crashed) {
    if (this.done) return;
    this.done = true;
    const p = this.p, coins = this.coins();
    if (this.o.onReward && coins > 0) this.o.onReward(coins);
    const box = this.el('rcResult').querySelector('.box');
    box.innerHTML = `<h2>${crashed ? '💥 Авария!' : '🏁 Заезд окончен'}</h2>
      <p>Проехано: <b>${(p.dist / 1000).toFixed(2).replace('.', ',')} км</b></p>
      <p>Впритирку: <b>${p.near}</b> · Макс. скорость: <b>${Math.round(p.maxV)} км/ч</b></p>
      <div class="coins">🪙 +${fmt(coins)}</div>
      ${coins > 0 && this.o.rewarded ? '<button class="ad" id="rcAd">📺 Ещё ×2 за рекламу</button>' : ''}
      <button id="rcAgain">🔁 Ещё раз</button>
      <button class="alt" id="rcHome">🏠 В гараж</button>`;
    this.el('rcResult').classList.remove('hidden');
    const ad = box.querySelector('#rcAd');
    if (ad) ad.onclick = () => { ad.disabled = true; this.o.rewarded(() => { this.o.onReward(coins); ad.textContent = '✅ Получено!'; }); };
    box.querySelector('#rcAgain').onclick = () => { this.camInit = false; this.reset(); };
    box.querySelector('#rcHome').onclick = () => this.close({ dist: p.dist, near: p.near, maxKmh: p.maxV, coins });
  }

  close(result) {
    cancelAnimationFrame(this.raf);
    removeEventListener('resize', this.onResize);
    removeEventListener('keydown', this.kd);
    removeEventListener('keyup', this.ku);
    document.removeEventListener('visibilitychange', this.onVis);
    SND.horn(false);
    SND.close();
    this.traffic.clear();
    this.city.dispose();
    this.renderer.dispose();
    this.layer.remove();
    if (this.o.onClose) this.o.onClose(result);
  }
}

export function startRace(opts) {
  const r = new Race(opts);
  startRace.current = r;
  return r;
}
