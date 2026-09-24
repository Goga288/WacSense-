// Ржавый остров — выживание в браузере. Главный модуль: игрок, ввод, бой, сохранения, цикл игры.
import * as THREE from './three.module.min.js';
import { World, HALF, NODE } from './world.js';
import { Building, PIECE_ORDER, PIECES, TIERS, DEPLOY } from './building.js';
import { Entities } from './entities.js';
import { UI } from './ui.js';
import { ITEMS, Inventory, FIST, costText, rollLoot } from './items.js';
import { initAudio, sfx as playSfx, setMuted, updateAmbient } from './audio.js';
import { Y } from './ysdk.js';
import { clamp, lerp, smoothstep, rand, randi } from './util.js';
import { buildViewModel } from './viewmodel.js';
import { Gfx, QUALITY, QUALITY_ORDER, wind } from './gfx.js';

const SAVE_KEY = 'rusty_island_save_v1';
const DAY_LENGTH = 16 * 60; // секунд на полные сутки
const PR = 0.32, PH = 1.75, STEP_H = 0.55, EYE = 1.6;

const $ = (id) => document.getElementById(id);

class Game {
  constructor() {
    this.mobile = Y.isMobile();
    this.state = 'loading';
    this.canvas = $('game');
    let qs = null;
    try { qs = JSON.parse(localStorage.getItem(SAVE_KEY + '_settings') || '{}').quality; } catch (e) { /* ignore */ }
    this.qualityKey = QUALITY[qs] ? qs : this.mobile ? 'low' : 'high';
    const Q = QUALITY[this.qualityKey];
    this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, Q.pr));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.shadowMap.enabled = Q.shadows > 0;
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.toneMappingExposure = 1.0;
    this.renderer.autoClear = false;

    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(0xb4cde4, 90, 650);
    this.camera = new THREE.PerspectiveCamera(72, window.innerWidth / window.innerHeight, 0.08, 1500);
    this.camera.rotation.order = 'YXZ';
    this.scene.add(this.camera);

    this.hemi = new THREE.HemisphereLight(0xc8d8e8, 0x4a4632, 0.6);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xfff1d6, 3);
    this.sun.castShadow = Q.shadows > 0;
    if (Q.shadows) this.sun.shadow.mapSize.set(Q.shadows, Q.shadows);
    const sc = this.sun.shadow.camera;
    sc.left = -45; sc.right = 45; sc.top = 45; sc.bottom = -45; sc.near = 1; sc.far = 300;
    this.sun.shadow.bias = -0.0003;
    this.sun.shadow.normalBias = 0.03;
    this.scene.add(this.sun, this.sun.target);
    this.fireLight = new THREE.PointLight(0xff8a30, 0, 18, 1.6);
    this.scene.add(this.fireLight);
    this.waterFog = new THREE.Color(0x0d3a4a);
    this.hurtFx = 0;

    // отдельная сцена для предмета в руках (не проваливается в стены)
    this.vmScene = new THREE.Scene();
    this.vmCamera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.01, 10);
    this.vmHemi = new THREE.HemisphereLight(0xffffff, 0x555555, 1.6);
    this.vmScene.add(this.vmHemi);
    this.vmDir = new THREE.DirectionalLight(0xffffff, 1.2);
    this.vmDir.position.set(1, 2, 1);
    this.vmScene.add(this.vmDir);
    this.vm = null;
    this.vmId = undefined;

    // игровое состояние
    this.player = {
      pos: new THREE.Vector3(), vel: new THREE.Vector3(), yaw: 0, pitch: 0,
      hp: 100, food: 60, water: 60, alive: true, onGround: false, moveSpeed: 0, inWater: false,
    };
    this.inv = new Inventory(30);
    this.inv.onChange = () => { this.invDirty = true; };
    this.slot = 0;
    this.craftQueue = [];
    this.timers = [];
    this.dayTime = 0.3;
    this.spawnBag = null;
    this.keys = {};
    this.lmb = false;
    this.lmbEdge = false;
    this.cool = 0;
    this.swingT = 1;
    this.swingDur = 0.5;
    this.recoilT = 1;
    this.reloadT = 0;
    this.eatT = 1;
    this.pendingHit = null;
    this.bob = 0;
    this.shake = 0;
    this.lookDX = 0;
    this.lookDY = 0;
    this.sway = { x: 0, y: 0 };
    this.stepT = 0;
    this.sens = 1;
    this.soundOn = true;
    this.touchMove = { x: 0, z: 0, sprint: false };
    this.target = null;
    this.saveT = 0;
    this.cloudT = 0;
    this.tmpO = new THREE.Vector3();
    this.tmpD = new THREE.Vector3();
  }

  async init() {
    await Y.init();
    this.gfx = new Gfx(this, this.qualityKey);
    this.gfx.initSky(this.scene);
    this.gfx.initPost(window.innerWidth, window.innerHeight);
    this.world = new World(this.scene, this.gfx);
    this.building = new Building(this);
    this.ents = new Entities(this);
    this.ui = new UI(this);
    this.bindInput();
    this.bindMenus();
    Y.onPause = () => { if (this.state === 'play') this.pause(); setMuted(true); };
    Y.onResume = () => { if (this.soundOn) setMuted(false); };

    let saved = null;
    try { saved = localStorage.getItem(SAVE_KEY); } catch (e) { /* приватный режим */ }
    const cloud = await Y.loadCloud();
    if (cloud) {
      try {
        const a = saved ? JSON.parse(saved).t || 0 : 0;
        if (JSON.parse(cloud).t > a) saved = cloud;
      } catch (e) { /* ignore */ }
    }
    if (saved && this.load(saved)) this.hasSave = true;
    else this.newGame();

    $('btnPlay').textContent = this.hasSave ? 'Продолжить' : 'Играть';
    $('btnNew').style.display = this.hasSave ? '' : 'none';
    $('loading').classList.add('hidden');
    $('menu').classList.remove('hidden');
    this.state = 'menu';
    this.updateCamera();
    Y.ready();
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  // ---------- Жизненный цикл ----------
  newGame() {
    this.building.load(null);
    this.ents.loadBags([]);
    this.spawnBag = null;
    this.craftQueue = [];
    this.dayTime = 0.3;
    this.inv.load([]);
    this.respawn(false);
    this.player.food = 60;
    this.player.water = 60;
  }

  giveStarter(kit) {
    this.inv.slots.fill(null);
    this.inv.add('rock', 1);
    this.inv.add('bandage', 1);
    if (kit) {
      this.inv.add('stone_hatchet', 1);
      this.inv.add('stone_pickaxe', 1);
      this.inv.add('spear', 1);
      this.inv.add('bandage', 4);
      this.inv.add('cooked_meat', 3);
      this.inv.add('wood', 300);
    }
    this.slot = 0;
  }

  respawn(atBag, kit = false) {
    const p = this.player;
    let pt;
    if (atBag && this.spawnBag) pt = { x: this.spawnBag.x + 0.8, z: this.spawnBag.z + 0.8, y: this.spawnBag.y + 0.3 };
    else {
      // пляж без камней и деревьев вплотную
      for (let i = 0; i < 20; i++) {
        pt = this.world.randomBeachPoint();
        const near = this.world.nodes.query(pt.x - 3, pt.z - 3, pt.x + 3, pt.z + 3).some((n) => n.alive && n.col);
        if (!near) break;
      }
    }
    p.pos.set(pt.x, pt.y !== undefined ? pt.y : this.world.getHeight(pt.x, pt.z) + 0.1, pt.z);
    p.vel.set(0, 0, 0);
    p.yaw = Math.atan2(pt.x, pt.z);
    p.pitch = 0;
    p.hp = kit ? 100 : 60;
    p.food = Math.max(p.food, 40);
    p.water = Math.max(p.water, 40);
    p.alive = true;
    this.giveStarter(kit);
    this.ui && this.ui.refresh();
  }

  start() {
    initAudio();
    setMuted(!this.soundOn);
    $('menu').classList.add('hidden');
    $('pause').classList.add('hidden');
    this.state = 'play';
    $('hud').classList.remove('hidden');
    if (this.mobile) { $('touch').classList.remove('hidden'); document.body.classList.add('touch'); }
    this.lock();
    Y.gameplayStart();
    this.ui.refresh();
    if (!this.hasSave && !this.shownHelp) {
      this.shownHelp = true;
      this.ui.notify('Добывайте ресурсы, крафтите инструменты и стройте дом!');
    }
  }

  pause() {
    if (this.state !== 'play') return;
    this.state = 'paused';
    if (this.ui.open) this.closeInventory(true);
    this.ui.toggleMap(false);
    this.lmb = false;
    this.keys = {};
    $('pause').classList.remove('hidden');
    Y.gameplayStop();
    this.save();
  }

  resume() {
    if (this.state !== 'paused') return;
    $('pause').classList.add('hidden');
    this.state = 'play';
    initAudio();
    this.lock();
    Y.gameplayStart();
  }

  die(reason) {
    const p = this.player;
    if (!p.alive) return;
    p.alive = false;
    p.hp = 0;
    this.state = 'dead';
    if (this.ui.open) this.closeInventory(true);
    this.ui.toggleMap(false);
    this.lmb = false;
    this.keys = {};
    const items = this.inv.slots.filter(Boolean);
    if (items.length) this.dropBag(p.pos.x, p.pos.y, p.pos.z, items, 1200);
    this.inv.load([]);
    this.craftQueue = [];
    this.building.hideGhost();
    $('deathReason').textContent = reason ? `Причина: ${reason}` : '';
    $('btnRespawnBag').style.display = this.spawnBag ? '' : 'none';
    $('death').classList.remove('hidden');
    this.unlockQuiet();
    Y.gameplayStop();
    this.save();
  }

  doRespawn(atBag, kit) {
    $('death').classList.add('hidden');
    this.respawn(atBag, kit);
    this.state = 'play';
    this.lock();
    Y.gameplayStart();
    this.save();
  }

  lock() {
    if (this.mobile) return;
    try {
      const r = this.canvas.requestPointerLock && this.canvas.requestPointerLock();
      if (r && r.catch) r.catch(() => {});
    } catch (e) { /* ignore */ }
  }

  unlockQuiet() {
    this.expectUnlock = true;
    if (document.pointerLockElement) document.exitPointerLock();
    setTimeout(() => { this.expectUnlock = false; }, 300);
  }

  // ---------- Ввод ----------
  bindInput() {
    window.addEventListener('resize', () => {
      const w = window.innerWidth, h = window.innerHeight;
      this.renderer.setSize(w, h);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
      this.vmCamera.aspect = w / h;
      this.vmCamera.updateProjectionMatrix();
      this.gfx.resize(w, h);
    });
    document.addEventListener('pointerlockchange', () => {
      if (!document.pointerLockElement && this.state === 'play' && !this.ui.open && !this.mapOpen && !this.expectUnlock) this.pause();
    });
    this.canvas.addEventListener('click', () => {
      if (this.state === 'play' && !this.ui.open && !document.pointerLockElement) this.lock();
    });
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Tab' || e.code === 'Space') e.preventDefault();
      if (this.state !== 'play') {
        if (e.code === 'Escape' && this.state === 'paused') this.resume();
        return;
      }
      if (e.repeat && e.code !== 'KeyW') return;
      this.keys[e.code] = true;
      switch (e.code) {
        case 'Tab':
        case 'KeyI':
          this.toggleInventory();
          break;
        case 'KeyE':
          if (this.ui.open && this.ui.container) this.closeInventory();
          else if (!this.ui.open) this.interact();
          break;
        case 'Escape':
          if (this.ui.open) this.closeInventory();
          else if (this.mapOpen) this.toggleMap();
          break;
        case 'KeyR': this.pressR(); break;
        case 'KeyM': this.toggleMap(); break;
        case 'KeyQ': this.secondary(); break;
        default:
          if (e.code.startsWith('Digit')) {
            const n = +e.code.slice(5);
            if (n >= 1 && n <= 6) this.selectSlot(n - 1);
          }
      }
    });
    window.addEventListener('keyup', (e) => { this.keys[e.code] = false; });
    window.addEventListener('blur', () => { this.keys = {}; this.lmb = false; });
    document.addEventListener('mousemove', (e) => {
      if (document.pointerLockElement !== this.canvas || this.state !== 'play') return;
      this.look(e.movementX, e.movementY, 0.0022);
    });
    this.canvas.addEventListener('mousedown', (e) => {
      if (this.state !== 'play' || this.ui.open || this.mobile) return;
      if (!document.pointerLockElement) return;
      if (e.button === 0) { this.lmb = true; this.lmbEdge = true; }
      if (e.button === 2) this.secondary();
    });
    window.addEventListener('mouseup', (e) => { if (e.button === 0) this.lmb = false; });
    window.addEventListener('wheel', (e) => {
      if (this.state !== 'play' || this.ui.open) return;
      this.selectSlot((this.slot + (e.deltaY > 0 ? 1 : 5)) % 6);
    }, { passive: true });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    document.addEventListener('selectstart', (e) => e.preventDefault());
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        setMuted(true);
        if (this.state === 'play') this.pause();
        this.save();
      } else if (this.soundOn) {
        setMuted(false);
      }
    });
    window.addEventListener('pagehide', () => this.save());
    $('mapScreen').addEventListener('pointerdown', () => { if (this.mapOpen) this.toggleMap(); });
    this.bindTouch();
  }

  look(dx, dy, s) {
    const p = this.player;
    this.lookDX += dx * s * this.sens;
    this.lookDY += dy * s * this.sens;
    p.yaw -= dx * s * this.sens;
    p.pitch = clamp(p.pitch - dy * s * this.sens, -1.55, 1.55);
  }

  bindTouch() {
    const zone = $('touch');
    const joy = $('joy'), knob = $('joyKnob');
    const roles = new Map();
    const btn = (id, down, up) => {
      const el = $(id);
      el.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); initAudio(); down(); el.classList.add('on'); }, { passive: false });
      el.addEventListener('touchend', (e) => { e.preventDefault(); e.stopPropagation(); up && up(); el.classList.remove('on'); }, { passive: false });
      el.addEventListener('touchcancel', () => { up && up(); el.classList.remove('on'); });
    };
    btn('tAttack', () => { this.lmb = true; this.lmbEdge = true; }, () => { this.lmb = false; });
    btn('tAlt', () => this.secondary());
    btn('tJump', () => { this.keys.Space = true; }, () => { this.keys.Space = false; });
    btn('tUse', () => this.interact());
    btn('tReload', () => this.pressR());
    btn('tInv', () => this.toggleInventory());
    btn('tMap', () => this.toggleMap());
    btn('tSprint', () => { this.touchMove.sprint = !this.touchMove.sprint; $('tSprint').classList.toggle('lock', this.touchMove.sprint); });
    zone.addEventListener('touchstart', (e) => {
      if (this.state !== 'play') return;
      e.preventDefault();
      for (const t of e.changedTouches) {
        if (t.clientX < window.innerWidth * 0.4 && !roles.has('joy')) {
          roles.set(t.identifier, { role: 'joy', x0: t.clientX, y0: t.clientY });
          roles.set('joy', t.identifier);
          joy.style.left = t.clientX + 'px';
          joy.style.top = t.clientY + 'px';
          joy.classList.add('on');
        } else {
          roles.set(t.identifier, { role: 'look', x: t.clientX, y: t.clientY });
        }
      }
    }, { passive: false });
    zone.addEventListener('touchmove', (e) => {
      e.preventDefault();
      for (const t of e.changedTouches) {
        const r = roles.get(t.identifier);
        if (!r) continue;
        if (r.role === 'joy') {
          let dx = t.clientX - r.x0, dy = t.clientY - r.y0;
          const len = Math.hypot(dx, dy), max = 55;
          if (len > max) { dx *= max / len; dy *= max / len; }
          knob.style.transform = `translate(${dx}px, ${dy}px)`;
          this.touchMove.x = dx / max;
          this.touchMove.z = dy / max;
        } else {
          this.look(t.clientX - r.x, t.clientY - r.y, 0.005);
          r.x = t.clientX;
          r.y = t.clientY;
        }
      }
    }, { passive: false });
    const end = (e) => {
      for (const t of e.changedTouches) {
        const r = roles.get(t.identifier);
        if (r && r.role === 'joy') {
          roles.delete('joy');
          this.touchMove.x = 0;
          this.touchMove.z = 0;
          knob.style.transform = '';
          joy.classList.remove('on');
        }
        roles.delete(t.identifier);
      }
    };
    zone.addEventListener('touchend', end);
    zone.addEventListener('touchcancel', end);
    $('quickBtn').addEventListener('click', () => {
      this.ui.quickMove = !this.ui.quickMove;
      $('quickBtn').classList.toggle('on', this.ui.quickMove);
    });
  }

  bindMenus() {
    $('btnPlay').onclick = () => this.start();
    $('btnNew').onclick = () => {
      if (!confirm('Начать заново? Весь прогресс будет потерян.')) return;
      this.newGame();
      this.hasSave = false;
      this.save();
      this.start();
    };
    $('btnResume').onclick = () => this.resume();
    $('btnPauseNew').onclick = () => {
      if (!confirm('Начать заново? Весь прогресс будет потерян.')) return;
      this.newGame();
      this.save();
      $('pause').classList.add('hidden');
      this.state = 'paused';
      this.resume();
    };
    const snd = $('btnSound');
    const updSnd = () => { snd.textContent = this.soundOn ? '🔊 Звук: вкл' : '🔇 Звук: выкл'; };
    snd.onclick = () => { this.soundOn = !this.soundOn; setMuted(!this.soundOn); updSnd(); this.saveSettings(); };
    const qb = $('btnQuality');
    qb.textContent = `🖥️ Графика: ${QUALITY[this.qualityKey].name}`;
    qb.onclick = () => {
      const i = QUALITY_ORDER.indexOf(this.qualityKey);
      this.qualityKey = QUALITY_ORDER[(i + 1) % QUALITY_ORDER.length];
      this.saveSettings();
      this.save();
      location.reload();
    };
    const sens = $('sens');
    sens.oninput = () => { this.sens = +sens.value; this.saveSettings(); };
    try {
      const s = JSON.parse(localStorage.getItem(SAVE_KEY + '_settings') || '{}');
      if (s.sens) { this.sens = s.sens; sens.value = s.sens; }
      if (s.soundOn === false) this.soundOn = false;
    } catch (e) { /* ignore */ }
    updSnd();
    $('btnRespawnBeach').onclick = () => Y.showFullscreen(() => this.doRespawn(false, false));
    $('btnRespawnBag').onclick = () => Y.showFullscreen(() => this.doRespawn(true, false));
    $('btnRespawnKit').onclick = () => {
      let got = false;
      Y.showRewarded(() => { got = true; }, () => this.doRespawn(false, got));
    };
  }

  saveSettings() {
    try { localStorage.setItem(SAVE_KEY + '_settings', JSON.stringify({ sens: this.sens, soundOn: this.soundOn, quality: this.qualityKey })); } catch (e) { /* ignore */ }
  }

  // ---------- Инвентарь / UI ----------
  toggleInventory() {
    if (this.ui.open) this.closeInventory();
    else this.openInventory(null);
  }

  openInventory(container) {
    if (this.mapOpen) this.toggleMap();
    this.lmb = false;
    this.building.hideGhost();
    this.unlockQuiet();
    this.ui.showInventory(container);
    if (container) this.sfx('pickup', null, 0.5);
  }

  closeInventory(noLock) {
    const c = this.ui.container;
    this.ui.hideInventory();
    if (c) {
      if (c.kind === 'crate') this.world.closeCrate(c);
      if (c.kind === 'bag' && c.inv.isEmpty()) this.ents.removeBag(c);
    }
    if (!noLock) this.lock();
  }

  toggleMap() {
    this.mapOpen = this.ui.toggleMap();
    if (this.mapOpen && this.ui.open) this.closeInventory(true);
  }

  selectSlot(i) {
    if (this.slot === i) return;
    this.slot = i;
    this.reloadT = 0;
    this.building.hideGhost();
    this.ui.refresh();
  }

  held() {
    return this.inv.slots[this.slot];
  }

  giveItem(id, n) {
    if (n <= 0) return;
    const left = this.inv.add(id, n);
    if (n - left > 0) this.ui.feed(id, n - left);
    if (left > 0) {
      this.dropItems([{ id, n: left }]);
      this.ui.notify('Инвентарь полон — предметы выброшены');
    }
  }

  dropItems(stacks) {
    const p = this.player;
    const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw);
    const x = p.pos.x + fx * 1.2, z = p.pos.z + fz * 1.2;
    this.dropBag(x, Math.max(this.world.getHeight(x, z), p.pos.y), z, stacks);
  }

  dropBag(x, y, z, items, life) {
    return this.ents.addBag(x, y, z, items, life);
  }

  craft(r, times) {
    let n = 0;
    for (let i = 0; i < times; i++) {
      if (!this.inv.take(r.cost)) break;
      this.craftQueue.push({ r, t: r.time });
      n++;
    }
    if (n) this.sfx('craft', null, 0.7);
    else this.ui.notify('Не хватает ресурсов');
    this.ui.refresh();
  }

  sfx(name, pos, vol = 1) {
    if (pos) {
      const d = Math.hypot(pos.x - this.player.pos.x, pos.y - this.player.pos.y, pos.z - this.player.pos.z);
      vol *= clamp(1 - d / 70, 0, 1);
    }
    playSfx(name, vol);
  }

  // ---------- Луч по миру ----------
  raycast(o, d, maxT, opts = {}) {
    const best = { t: maxT, kind: null, obj: null, normal: null };
    const tt = this.world.raycastTerrain(o, d, maxT);
    if (tt >= 0 && tt < best.t) { best.t = tt; best.kind = 'terrain'; best.obj = null; }
    this.world.raycastNodes(o, d, best.t, best);
    this.building.raycast(o, d, best);
    this.raycastStatic(o, d, best);
    if (!opts.noMobs) this.ents.raycast(o, d, best);
    if (!best.kind) return null;
    best.point = new THREE.Vector3().copy(o).addScaledVector(d, best.t);
    return best;
  }

  raycastStatic(o, d, best) {
    const seg = 10;
    for (let s = 0; s < best.t; s += seg) {
      const e = Math.min(s + seg, best.t);
      const ax = o.x + d.x * s, az = o.z + d.z * s, bx = o.x + d.x * e, bz = o.z + d.z * e;
      const list = this.world.colliders.query(Math.min(ax, bx) - 0.5, Math.min(az, bz) - 0.5, Math.max(ax, bx) + 0.5, Math.max(az, bz) + 0.5);
      for (const c of list) {
        if (!c.ref || c.ref.kind !== 'static') continue;
        const h = rayBoxC(o, d, c, best.t);
        if (h && h.t < best.t) { best.t = h.t; best.kind = 'static'; best.obj = c; best.normal = { x: h.nx, y: h.ny, z: h.nz }; }
      }
    }
  }

  hasLineOfSight(p1, h1, p2, h2) {
    const o = new THREE.Vector3(p1.x, p1.y + h1, p1.z);
    const d = new THREE.Vector3(p2.x, p2.y + h2, p2.z).sub(o);
    const len = d.length();
    if (len < 0.5) return true;
    d.divideScalar(len);
    return !this.raycast(o, d, len - 0.4, { noMobs: true });
  }

  eyeRay() {
    const p = this.player;
    this.tmpO.set(p.pos.x, p.pos.y + EYE, p.pos.z);
    this.tmpD.set(0, 0, -1).applyEuler(this.camera.rotation);
    return [this.tmpO, this.tmpD];
  }

  // ---------- Урон игроку ----------
  damagePlayer(dmg, src) {
    const p = this.player;
    if (!p.alive || this.state === 'menu') return;
    p.hp -= dmg;
    if (dmg > 1) this.shake = Math.max(this.shake, Math.min(1, dmg / 12));
    this.hurtFx = Math.min(1, this.hurtFx + dmg / 25);
    this.ui.hurt();
    this.sfx('hurt');
    if (p.hp <= 0) this.die(src);
  }

  // ---------- Действия ----------
  handlePrimary() {
    const edge = this.lmbEdge;
    this.lmbEdge = false;
    if (this.ui.open || this.state !== 'play' || !this.player.alive) return;
    if (this.cool > 0 || this.reloadT > 0) return;
    const s = this.held();
    const it = s ? ITEMS[s.id] : null;
    if (!it || it.melee) {
      if (this.lmb) this.swing(it ? it.melee : FIST);
    } else if (it.gun) {
      if (edge) this.fireGun(s, it.gun);
    } else if (it.ranged) {
      if (edge) this.fireBow(it.ranged);
    } else if (it.eat || it.heal) {
      if (edge) this.consume(s, it);
    } else if (it.special === 'plan') {
      if (edge) {
        const err = this.building.place();
        if (err) this.ui.notify(err);
        else { this.sfx('build'); this.cool = 0.25; }
      }
    } else if (it.special === 'hammer') {
      if (edge) this.hammerHit();
    } else if (it.deploy) {
      if (edge) this.deploy(s, it);
    } else if (edge) {
      this.ui.notify('Этот предмет нельзя использовать в руках');
    }
  }

  swing(tool) {
    this.cool = tool.rate;
    this.swingT = 0;
    this.swingDur = tool.rate * 0.9;
    this.pendingHit = { t: tool.rate * 0.3, tool };
    this.sfx('swing', null, 0.6);
  }

  resolveMelee(tool) {
    const [o, d] = this.eyeRay();
    const hit = this.raycast(o, d, tool.range);
    if (!hit) return;
    const pt = hit.point;
    switch (hit.kind) {
      case 'node': this.gather(hit.obj, tool, pt); break;
      case 'mob': {
        const m = hit.obj;
        if (m.dead) {
          if (m.animal) { this.ents.harvest(m, tool.flesh); this.sfx('flesh'); }
        } else {
          this.ents.damage(m, tool.dmg);
          this.ui.hitmarker();
          this.sfx('flesh');
        }
        break;
      }
      case 'piece':
      case 'deploy': {
        const tier = hit.obj.tier || 0;
        this.ents.impact(pt.x, pt.y, pt.z, tier >= 3 ? 'metal' : tier === 2 ? 'stone' : 'wood');
        this.sfx(tier >= 3 ? 'metal' : tier === 2 ? 'stone' : 'wood', null, 0.6);
        break;
      }
      case 'terrain':
        this.ents.impact(pt.x, pt.y, pt.z, 'dirt');
        this.sfx('step', null, 2);
        break;
      default:
        this.ents.impact(pt.x, pt.y, pt.z, 'stone');
        this.sfx('stone', null, 0.6);
    }
    this.shake = Math.max(this.shake, 0.15);
  }

  gather(n, tool, pt) {
    const def = NODE[n.kind];
    if (n.kind === 'barrel') {
      n.hp -= tool.dmg;
      this.sfx('metal');
      this.ents.impact(pt.x, pt.y, pt.z, 'metal');
      if (n.hp <= 0) {
        for (const it of rollLoot('barrel')) this.giveItem(it.id, it.n);
        this.world.killNode(n, 240);
      }
      return;
    }
    if (def.pickup) { this.pickupNode(n); return; }
    if (!def.give) {
      this.sfx('stone');
      this.ents.impact(pt.x, pt.y, pt.z, 'stone');
      return;
    }
    const mult = tool[def.gather] || 0.2;
    const want = Math.max(1, Math.round(5 * mult));
    const got = Math.min(want, n.amount);
    n.amount -= got;
    this.giveItem(def.give, got);
    if (def.bonus) this.giveItem(def.bonus, Math.ceil(got * 0.5));
    this.sfx(def.snd);
    if (n.kind === 'tree') {
      this.ents.impact(pt.x, pt.y, pt.z, 'wood');
      if (n.sub !== 'birch' || Math.random() < 0.8) this.ents.impact(n.x, n.y + 4 + Math.random() * 3, n.z, 'leaves');
    } else {
      this.ents.impact(pt.x, pt.y, pt.z, 'stone');
      if (n.kind === 'sulfur') this.ents.burst(pt.x, pt.y, pt.z, 0xd8c23a, 5, 2.5);
      if (n.kind === 'metal') this.ents.burst(pt.x, pt.y, pt.z, 0x9a5a38, 5, 2.5);
    }
    if (n.amount <= 0) {
      if (n.kind === 'tree') {
        n.fall = 0;
        this.world.animNodes.add(n);
        this.giveItem('wood', 20);
        this.sfx('crack', n);
        const pos = { x: n.x, y: n.y, z: n.z };
        this.timers.push({ t: 1.2, fn: () => {
          this.sfx('thud', pos);
          if (Math.hypot(pos.x - this.player.pos.x, pos.z - this.player.pos.z) < 20) this.shake = Math.max(this.shake, 0.5);
          for (let k = 0; k < 3; k++) this.ents.impact(pos.x + (Math.random() - 0.5) * 3, pos.y + 1 + Math.random() * 4, pos.z + (Math.random() - 0.5) * 3, 'leaves');
        } });
      }
      this.world.killNode(n, n.kind === 'tree' ? 300 : 400);
    } else if (n.kind === 'tree') {
      n.shake = 0.5;
      this.world.animNodes.add(n);
    } else {
      this.world.setNodeMatrix(n);
    }
  }

  pickupNode(n) {
    const def = NODE[n.kind];
    this.giveItem(def.pickup, randi(def.n[0], def.n[1]));
    this.world.killNode(n, 300);
    this.sfx('pickup');
  }

  fireGun(s, g) {
    if (s.ammo <= 0) {
      this.sfx('empty');
      this.cool = 0.3;
      if (this.inv.count(g.ammo) > 0) this.pressR();
      else this.ui.notify('Нет патронов');
      return;
    }
    s.ammo--;
    this.cool = g.rate;
    this.recoilT = 0;
    this.sfx('shot');
    this.shake = Math.max(this.shake, 0.6);
    this.muzzleT = 0.06;
    const [o, d] = this.eyeRay();
    d.x += rand(-g.spread, g.spread);
    d.y += rand(-g.spread, g.spread);
    d.z += rand(-g.spread, g.spread);
    d.normalize();
    this.player.pitch = Math.min(1.55, this.player.pitch + 0.025);
    const hit = this.raycast(o, d, g.range);
    const end = hit ? hit.point : o.clone().addScaledVector(d, g.range);
    const from = o.clone().addScaledVector(d, 0.8);
    from.y -= 0.15;
    this.ents.tracer(from, end);
    if (hit) {
      if (hit.kind === 'mob' && !hit.obj.dead) {
        const m = hit.obj;
        const head = end.y > m.pos.y + m.h * 0.82;
        this.ents.damage(m, g.dmg * (head ? 1.6 : 1));
        this.ui.hitmarker();
      } else if (hit.kind === 'node' && hit.obj.kind === 'barrel') {
        this.gather(hit.obj, { dmg: g.dmg }, end);
      } else {
        const k = hit.kind === 'terrain' ? 'dirt' : hit.kind === 'node' && hit.obj.kind === 'tree' ? 'wood' : 'stone';
        this.ents.impact(end.x, end.y, end.z, k);
      }
    }
    this.invDirty = true;
  }

  fireBow(r) {
    if (this.inv.count(r.ammo) <= 0) { this.ui.notify('Нет стрел'); this.cool = 0.4; return; }
    this.inv.remove(r.ammo, 1);
    this.cool = r.rate;
    this.recoilT = 0;
    this.sfx('bow');
    this.shake = Math.max(this.shake, 0.15);
    const [o, d] = this.eyeRay();
    const dir = d.clone();
    dir.x += rand(-r.spread, r.spread);
    dir.y += rand(-r.spread, r.spread) + 0.02;
    dir.normalize();
    this.ents.shootArrow(o.clone().addScaledVector(d, 0.6), dir, r.speed, r.dmg);
  }

  consume(s, it) {
    const p = this.player;
    if (it.heal && p.hp >= 100) { this.ui.notify('Вы здоровы'); return; }
    if (it.eat && p.food >= 99) { this.ui.notify('Вы сыты'); return; }
    if (it.eat) {
      p.food = Math.min(100, p.food + it.eat.food);
      p.water = Math.min(100, p.water + it.eat.water);
      p.hp = clamp(p.hp + it.eat.hp, 1, 100);
      this.sfx('eat');
    }
    if (it.heal) {
      p.hp = Math.min(100, p.hp + it.heal);
      this.sfx('pickup');
    }
    this.inv.remove(s.id, 1);
    this.eatT = 0;
    this.cool = 0.8;
  }

  hammerHit() {
    const [o, d] = this.eyeRay();
    const hit = this.raycast(o, d, 4, { noMobs: true });
    this.swingT = 0;
    this.swingDur = 0.4;
    this.cool = 0.4;
    if (!hit || hit.kind !== 'piece') return;
    const err = this.building.upgrade(hit.obj);
    if (err) this.ui.notify(err);
    else {
      this.sfx('build');
      this.ui.notify(`Улучшено: ${TIERS[hit.obj.tier].name}`);
      this.ents.burst(hit.point.x, hit.point.y, hit.point.z, TIERS[hit.obj.tier].color, 10, 3);
    }
  }

  secondary() {
    if (this.state !== 'play' || this.ui.open || !this.player.alive) return;
    const s = this.held();
    const it = s ? ITEMS[s.id] : null;
    if (!it) return;
    if (it.special === 'plan') {
      const b = this.building;
      b.pieceType = PIECE_ORDER[(PIECE_ORDER.indexOf(b.pieceType) + 1) % PIECE_ORDER.length];
      b.ghostKey = '';
      this.ui.notify(PIECES[b.pieceType].name);
    } else if (it.special === 'hammer') {
      const [o, d] = this.eyeRay();
      const hit = this.raycast(o, d, 4, { noMobs: true });
      if (!hit) return;
      if (hit.kind === 'piece') {
        const p = hit.obj;
        if (p.type === 'door') {
          this.building.demolish(p);
          this.giveItem('door', 1);
        } else {
          this.building.demolish(p);
          this.ui.notify(`Разобрано: ${PIECES[p.type].name}`);
        }
        this.sfx('build');
      } else if (hit.kind === 'deploy') {
        const dd = hit.obj;
        if (!dd.inv.isEmpty()) { this.ui.notify('Сначала опустошите'); return; }
        this.building.removeDeploy(dd, false);
        this.giveItem(DEPLOY[dd.type].item, 1);
        this.sfx('pickup');
      }
    } else if (it.gun || it.ranged) {
      this.aim = !this.aim;
    }
  }

  pressR() {
    if (this.state !== 'play' || !this.player.alive) return;
    const s = this.held();
    const it = s ? ITEMS[s.id] : null;
    if (!it) return;
    if (it.gun) {
      if (this.reloadT > 0 || s.ammo >= it.gun.mag) return;
      if (this.inv.count(it.gun.ammo) <= 0) { this.ui.notify('Нет патронов'); return; }
      this.reloadT = it.gun.reload;
      this.reloadSlot = s;
      this.sfx('reload');
    } else if (it.special === 'plan' || it.deploy) {
      this.building.rot = (this.building.rot + 1) % 4;
      this.deployRot = ((this.deployRot || 0) + 1) % 4;
      this.building.ghostKey = '';
    }
  }

  finishReload() {
    const s = this.reloadSlot;
    if (!s || this.held() !== s) return;
    const g = ITEMS[s.id].gun;
    const n = Math.min(g.mag - s.ammo, this.inv.count(g.ammo));
    this.inv.remove(g.ammo, n);
    s.ammo += n;
    this.invDirty = true;
  }

  deploy(s, it) {
    const [o, d] = this.eyeRay();
    if (it.deploy === 'door') {
      const hit = this.raycast(o, d, 4, { noMobs: true });
      if (!hit || hit.kind !== 'piece' || hit.obj.type !== 'doorway') { this.ui.notify('Наведитесь на дверной проём'); return; }
      const err = this.building.placeDoor(hit.obj);
      if (err) { this.ui.notify(err); return; }
      this.inv.remove(s.id, 1);
      this.sfx('build');
      return;
    }
    const c = this.deployCand;
    if (!c || c.err) { this.ui.notify(c ? c.err : 'Нельзя поставить'); return; }
    const dd = this.building.addDeploy({ type: it.deploy, x: c.x, y: c.y, z: c.z, rot: c.rot });
    this.inv.remove(s.id, 1);
    this.sfx('build');
    this.cool = 0.3;
    if (it.deploy === 'sleeping_bag') {
      this.spawnBag = dd;
      this.ui.notify('Точка возрождения установлена');
    }
  }

  interact() {
    if (this.state !== 'play' || !this.player.alive) return;
    const t = this.target;
    if (!t) return;
    switch (t.kind) {
      case 'node': this.pickupNode(t.obj); break;
      case 'crate':
      case 'bag':
        this.openInventory(t.obj);
        break;
      case 'deploy':
        if (t.obj.type === 'sleeping_bag') {
          this.spawnBag = t.obj;
          this.ui.notify('Точка возрождения установлена');
        } else this.openInventory(t.obj);
        break;
      case 'door':
        this.building.toggleDoor(t.obj);
        this.sfx('door');
        break;
      case 'water':
        if (this.player.water >= 99) { this.ui.notify('Вы не хотите пить'); return; }
        this.player.water = Math.min(100, this.player.water + 20);
        this.sfx('drink');
        break;
    }
  }

  findTarget() {
    const [o, d] = this.eyeRay();
    const hit = this.raycast(o, d, 3.2);
    let t = null;
    if (hit) {
      const obj = hit.obj;
      if (hit.kind === 'node' && NODE[obj.kind].pickup) t = { kind: 'node', obj, text: NODE[obj.kind].label };
      else if (hit.kind === 'crate') t = { kind: 'crate', obj, text: `Открыть: ${obj.name}` };
      else if (hit.kind === 'bag') t = { kind: 'bag', obj, text: 'Обыскать мешок' };
      else if (hit.kind === 'deploy') t = { kind: 'deploy', obj, text: obj.type === 'sleeping_bag' ? 'Сделать точкой возрождения' : `Открыть: ${obj.name}` };
      else if (hit.kind === 'piece' && obj.type === 'door') t = { kind: 'door', obj, text: obj.open ? 'Закрыть дверь' : 'Открыть дверь' };
      else if (hit.kind === 'mob' && obj.dead && obj.animal) this.corpseHint = true;
    }
    if (!t && o.y > 0 && d.y < 0) {
      const tw = -o.y / d.y;
      if (tw < 3.2 && (!hit || tw < hit.t)) t = { kind: 'water', text: 'Пить воду' };
    }
    if (!t && this.player.inWater) t = { kind: 'water', text: 'Пить воду' };
    this.target = t;
    this.aimHit = hit;
    const key = this.mobile ? '' : '[E] ';
    let text = t ? key + t.text : '';
    if (!t && hit && hit.kind === 'mob' && hit.obj.dead && hit.obj.animal) text = 'Бейте тушу, чтобы разделать';
    this.ui.setPrompt(text);
  }

  // ---------- Физика игрока ----------
  movePlayer(dt) {
    const p = this.player;
    const k = this.keys;
    let ix = (k.KeyD ? 1 : 0) - (k.KeyA ? 1 : 0) + this.touchMove.x;
    let iz = (k.KeyS ? 1 : 0) - (k.KeyW ? 1 : 0) + this.touchMove.z;
    const il = Math.hypot(ix, iz);
    if (il > 1) { ix /= il; iz /= il; }
    const ground = this.world.getHeight(p.pos.x, p.pos.z);
    p.inWater = ground < -1.1 && p.pos.y < -0.8;
    const sprint = (k.ShiftLeft || k.ShiftRight || this.touchMove.sprint) && iz < -0.3 && !p.inWater;
    const speed = p.inWater ? 2.6 : sprint ? 7 : 4.3;
    const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw);
    const rx = Math.cos(p.yaw), rz = -Math.sin(p.yaw);
    const wx = (rx * ix - fx * iz) * speed, wz = (rz * ix - fz * iz) * speed;
    const acc = p.onGround || p.inWater ? 1 - Math.exp(-12 * dt) : 1 - Math.exp(-2.5 * dt);
    p.vel.x = lerp(p.vel.x, wx, acc);
    p.vel.z = lerp(p.vel.z, wz, acc);
    if (p.inWater) {
      const surf = -1.35;
      const want = k.Space ? 2.5 : (surf - p.pos.y) * 3;
      p.vel.y = lerp(p.vel.y, want, 1 - Math.exp(-5 * dt));
      p.onGround = false;
    } else {
      p.vel.y -= 20 * dt;
      if (k.Space && p.onGround) { p.vel.y = 7; p.onGround = false; }
    }
    p.moveSpeed = Math.hypot(p.vel.x, p.vel.z);
    p.sprinting = sprint && p.moveSpeed > 5;

    const maxD = Math.max(Math.abs(p.vel.x), Math.abs(p.vel.y), Math.abs(p.vel.z)) * dt;
    const n = Math.max(1, Math.ceil(maxD / 0.2));
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      p.pos.x += p.vel.x * h;
      p.pos.z += p.vel.z * h;
      this.resolveXZ();
      p.pos.y += p.vel.y * h;
      this.resolveY(h);
    }
    const lim = HALF - 3;
    p.pos.x = clamp(p.pos.x, -lim, lim);
    p.pos.z = clamp(p.pos.z, -lim, lim);
    if (p.pos.y < -30) p.pos.y = this.world.getHeight(p.pos.x, p.pos.z) + 1;

    // шаги
    if (p.onGround && p.moveSpeed > 1) {
      this.bob += dt * p.moveSpeed * 1.8;
      this.stepT -= dt * p.moveSpeed;
      if (this.stepT <= 0) { this.stepT = 2.4; this.sfx('step', null, 0.8); }
    }
  }

  resolveXZ() {
    const p = this.player.pos;
    const feet = p.y;
    for (let iter = 0; iter < 2; iter++) {
      const list = this.world.colliders.query(p.x - PR - 0.5, p.z - PR - 0.5, p.x + PR + 0.5, p.z + PR + 0.5);
      for (const c of list) {
        if (c.maxY <= feet + STEP_H || c.minY >= feet + PH) continue;
        if (p.x + PR <= c.minX || p.x - PR >= c.maxX || p.z + PR <= c.minZ || p.z - PR >= c.maxZ) continue;
        const a = p.x + PR - c.minX, b = c.maxX - (p.x - PR), cc = p.z + PR - c.minZ, dd = c.maxZ - (p.z - PR);
        const m = Math.min(a, b, cc, dd);
        if (m === a) p.x -= a;
        else if (m === b) p.x += b;
        else if (m === cc) p.z -= cc;
        else p.z += dd;
      }
    }
    const nodes = this.world.nodes.query(p.x - 2, p.z - 2, p.x + 2, p.z + 2);
    for (const n of nodes) {
      if (!n.alive || !n.col) continue;
      if (feet > n.y + (n.colH || (n.kind === 'tree' ? 5 : 1.1))) continue;
      const dx = p.x - n.x, dz = p.z - n.z;
      const d = Math.hypot(dx, dz), min = PR + n.col;
      if (d < min && d > 1e-4) {
        p.x = n.x + (dx / d) * min;
        p.z = n.z + (dz / d) * min;
      }
    }
  }

  resolveY(h) {
    const pl = this.player;
    const p = pl.pos;
    let ground = this.world.getHeight(p.x, p.z);
    const r = PR * 0.8;
    const reach = Math.max(STEP_H, -pl.vel.y * h + 0.05);
    const list = this.world.colliders.query(p.x - r, p.z - r, p.x + r, p.z + r);
    for (const c of list) {
      if (p.x + r <= c.minX || p.x - r >= c.maxX || p.z + r <= c.minZ || p.z - r >= c.maxZ) continue;
      if (c.maxY <= p.y + reach && c.maxY > ground) ground = c.maxY;
      if (pl.vel.y > 0 && c.minY >= p.y + 0.5 && c.minY < p.y + PH) {
        p.y = c.minY - PH;
        pl.vel.y = 0;
      }
    }
    const was = pl.onGround;
    if (p.y <= ground) {
      if (pl.vel.y < -13 && !pl.inWater) this.damagePlayer((-pl.vel.y - 13) * 6, 'Падение');
      p.y = ground;
      pl.vel.y = Math.max(0, pl.vel.y);
      pl.onGround = true;
    } else if (was && pl.vel.y <= 0 && p.y - ground < 0.35) {
      p.y = ground;
      pl.vel.y = 0;
      pl.onGround = true;
    } else {
      pl.onGround = false;
    }
  }

  updateCamera() {
    const p = this.player;
    this.camera.position.set(p.pos.x, p.pos.y + EYE, p.pos.z);
    this.camera.rotation.set(p.pitch, p.yaw, 0);
    if (this.shake > 0.01) {
      const k = this.shake * this.shake * 0.035;
      this.camera.rotation.x += (Math.random() - 0.5) * k;
      this.camera.rotation.y += (Math.random() - 0.5) * k;
      this.camera.rotation.z += (Math.random() - 0.5) * k * 0.5;
    }
    const fov = this.aim ? 50 : 72;
    if (Math.abs(this.camera.fov - fov) > 0.1) {
      this.camera.fov = lerp(this.camera.fov, fov, 0.25);
      this.camera.updateProjectionMatrix();
    }
  }

  // ---------- Выживание ----------
  updateSurvival(dt) {
    const p = this.player;
    const drain = p.sprinting ? 2 : 1;
    p.food = Math.max(0, p.food - dt * 0.045 * drain);
    p.water = Math.max(0, p.water - dt * 0.07 * drain);
    if (p.food <= 0) this.damagePlayer(dt * 0.6, 'Голод');
    if (p.water <= 0) this.damagePlayer(dt * 0.8, 'Жажда');
    if (p.alive && p.food > 40 && p.water > 40 && p.hp < 100) p.hp = Math.min(100, p.hp + dt * 0.25);
    this.ui.updateStats(p);
  }

  // ---------- Модель в руках ----------
  updateViewModel(dt) {
    const s = this.player.alive ? this.held() : null;
    const id = s ? s.id : null;
    if (id !== this.vmId) {
      this.vmId = id;
      if (this.vm) this.vmScene.remove(this.vm);
      this.vm = buildViewModel(s ? ITEMS[s.id] : null, this.gfx.M);
      this.vmScene.add(this.vm);
      this.swingT = 1;
    }
    const vm = this.vm;
    const pv = vm.userData.pivot;
    const it = s ? ITEMS[s.id] : null;
    vm.visible = !this.ui.open && this.player.alive;
    const aim = this.aim && it && (it.gun || it.ranged);
    let x = aim ? 0.02 : 0.3, y = aim ? -0.2 : -0.33, z = -0.62;
    if (it && it.model === 'spear') { x = 0.25; y = -0.27; z = -0.35; }
    vm.scale.setScalar(0.8);
    const bobAmt = this.player.onGround ? Math.min(1, this.player.moveSpeed / 5) : 0;
    x += Math.cos(this.bob) * 0.012 * bobAmt;
    y += Math.abs(Math.sin(this.bob)) * 0.02 * bobAmt;
    vm.position.set(x, y, z);
    let rx = it && (it.gun || it.model === 'bow') ? 0 : 0.15, rz = 0, ry = it && it.model === 'bow' ? 0 : -0.2;
    if (it && it.model === 'spear') ry = 0;
    // удар
    if (this.swingT < 1) {
      this.swingT = Math.min(1, this.swingT + dt / this.swingDur);
      const t = this.swingT;
      let a;
      if (t < 0.25) a = (t / 0.25) * 0.7;
      else if (t < 0.5) a = 0.7 - ((t - 0.25) / 0.25) * 2.0;
      else a = -1.3 * (1 - (t - 0.5) / 0.5);
      if (it && it.model === 'spear') vm.position.z += a < 0 ? a * 0.35 : a * 0.1;
      else { rx += a; rz += a * 0.3; }
    }
    if (this.recoilT < 1) {
      this.recoilT = Math.min(1, this.recoilT + dt * 5);
      const k = 1 - this.recoilT;
      rx += k * 0.35;
      vm.position.z += k * 0.08;
    }
    if (this.reloadT > 0) rx -= 0.8;
    if (this.eatT < 1) {
      this.eatT = Math.min(1, this.eatT + dt * 1.5);
      const k = Math.sin(this.eatT * Math.PI);
      vm.position.x -= k * 0.2;
      vm.position.y += k * 0.1;
      rx += k * 0.6;
    }
    // рука запаздывает за движением мыши
    const sk = 1 - Math.exp(-10 * dt);
    this.sway.x = lerp(this.sway.x, clamp(-this.lookDX * 1.2, -0.07, 0.07), sk);
    this.sway.y = lerp(this.sway.y, clamp(this.lookDY * 1.2, -0.05, 0.05), sk);
    this.lookDX = 0;
    this.lookDY = 0;
    vm.position.x += this.sway.x;
    vm.position.y += this.sway.y;
    rz += this.sway.x * 2.5;
    ry += this.sway.x * 1.5;
    pv.rotation.set(rx, ry, rz);
    if (vm.userData.flash) {
      this.muzzleT = (this.muzzleT || 0) - dt;
      vm.userData.flash.visible = this.muzzleT > 0;
      vm.userData.flash.material.rotation = Math.random() * 6;
    }
  }

  // ---------- Небо и свет ----------
  updateSky(dt = 0) {
    const L = this.gfx.updateSky(this.dayTime, this.camera, dt);
    const { elev, sd, day, set } = L;
    const cam = this.camera.position;
    const under = cam.y < -0.05;
    this.underwater = under;
    this.gfx.sky.visible = !under;
    if (under) {
      this.scene.fog.color.copy(this.waterFog).multiplyScalar(0.25 + day * 0.75);
      this.scene.fog.near = 0.5;
      this.scene.fog.far = 26;
      this.scene.background = this.scene.fog.color;
    } else {
      this.scene.fog.color.copy(L.fog);
      this.scene.fog.near = 90;
      this.scene.fog.far = 650;
      this.scene.background = null;
    }
    const p = this.player.pos;
    const lightDir = elev > -0.05 ? sd : sd.clone().negate();
    this.sun.position.set(p.x + lightDir.x * 120, p.y + Math.max(0.12, lightDir.y) * 120, p.z + lightDir.z * 120);
    this.sun.target.position.set(p.x, p.y, p.z);
    if (elev > -0.05) {
      this.sun.color.setHex(0xfff4e2).lerp(new THREE.Color(0xff9a50), set * 0.8);
      this.sun.intensity = 0.2 + 2.6 * day;
    } else {
      this.sun.color.setHex(0x8fa4d8);
      this.sun.intensity = 0.5;
    }
    const env = this.gfx.q.env;
    this.hemi.intensity = env ? 0.2 + 0.4 * day : 0.5 + 1.1 * day;
    this.hemi.color.setHex(0xc8d8e8).lerp(new THREE.Color(0x4a5a90), 1 - day);
    this.vmHemi.intensity = 0.35 + 1.25 * day;
    this.vmDir.intensity = 0.2 + 1.0 * day;
    const wn = this.world.waterNormal;
    wn.offset.x += dt * 0.012;
    wn.offset.y += dt * 0.007;
    // огонь
    const f = this.building.nearestFire(p);
    if (f) {
      this.fireLight.position.set(f.x, f.y + 0.8, f.z);
      this.fireLight.intensity = (14 + Math.sin(performance.now() * 0.02) * 2 + Math.sin(performance.now() * 0.047) * 1.5) * (1.25 - day);
    } else {
      this.fireLight.intensity = 0;
    }
  }

  // ---------- Цикл ----------
  frame(now) {
    requestAnimationFrame((t) => this.frame(t));
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    if (this.state === 'play' || this.state === 'dead') this.update(dt);
    else if (this.state === 'menu') {
      // медленный облёт в меню
      this.player.yaw += dt * 0.05;
      wind.value += dt;
      this.updateCamera();
      this.updateSky(dt);
      if (this.world.grass) this.world.grass.update(this.player.pos);
    }
    this.render();
  }

  update(dt) {
    const p = this.player;
    for (let i = this.timers.length - 1; i >= 0; i--) {
      const t = this.timers[i];
      t.t -= dt;
      if (t.t <= 0) { this.timers.splice(i, 1); t.fn(); }
    }
    this.dayTime = (this.dayTime + dt / DAY_LENGTH) % 1;
    wind.value += dt;
    this.hurtFx = Math.max(0, this.hurtFx - dt * 2.5);
    this.shake = Math.max(0, this.shake - dt * 3);
    this.ambT = (this.ambT || 0) - dt;
    if (this.ambT <= 0) {
      this.ambT = 0.5;
      let wet = 0;
      for (let k = 0; k < 8; k++) {
        const a = (k / 8) * Math.PI * 2;
        if (this.world.getHeight(p.pos.x + Math.cos(a) * 14, p.pos.z + Math.sin(a) * 14) < 0) wet++;
      }
      const day = smoothstep(-0.1, 0.2, Math.sin((this.dayTime - 0.25) * Math.PI * 2));
      this.ambParams = { day, shore: p.inWater ? 1 : wet / 8, height: p.pos.y };
    }
    if (this.ambParams && this.soundOn) updateAmbient(dt, this.ambParams);

    if (p.alive) {
      this.movePlayer(dt);
      this.cool -= dt;
      if (this.pendingHit) {
        this.pendingHit.t -= dt;
        if (this.pendingHit.t <= 0) {
          const tool = this.pendingHit.tool;
          this.pendingHit = null;
          this.resolveMelee(tool);
        }
      }
      if (this.reloadT > 0) {
        this.reloadT -= dt;
        if (this.reloadT <= 0) { this.reloadT = 0; this.finishReload(); }
      }
      this.handlePrimary();
      this.updateSurvival(dt);
      // очередь крафта
      if (this.craftQueue.length) {
        const q = this.craftQueue[0];
        q.t -= dt;
        if (q.t <= 0) {
          this.craftQueue.shift();
          this.giveItem(q.r.out, q.r.n);
          this.sfx('craft', null, 0.5);
        }
      }
      this.updateCamera();
      this.findTarget();
      this.updateHeldUI();
      // контейнер слишком далеко
      const c = this.ui.container;
      if (c && Math.hypot(c.x - p.pos.x, c.z - p.pos.z) > 4.5) this.closeInventory(true);
    }

    this.world.update(dt, p.pos);
    this.building.update(dt, performance.now() / 1000);
    this.ents.update(dt);
    this.ents.updateFx(dt);
    this.updateViewModel(dt);
    this.updateSky(dt);
    if (this.invDirty) { this.invDirty = false; this.ui.refresh(); }
    this.ui.update(dt);

    this.saveT += dt;
    if (this.saveT > 20) { this.saveT = 0; this.save(); }
  }

  updateHeldUI() {
    const s = this.held();
    const it = s ? ITEMS[s.id] : null;
    const b = this.building;
    // план постройки
    if (it && it.special === 'plan' && !this.ui.open) {
      const [o, d] = this.eyeRay();
      const hit = this.aimHit && this.aimHit.t <= 3.2 ? this.aimHit : this.raycast(o, d, 6, { noMobs: true });
      const aim = hit && hit.t < 6 ? hit.point : o.clone().addScaledVector(d, 4);
      const err = b.updatePlan(hit, aim);
      this.ui.setBuildInfo(this.ui.planInfo(b) + (err ? `<br><span class="err">${err}</span>` : ''));
    } else if (it && it.deploy && it.deploy !== 'door' && !this.ui.open) {
      const [o, d] = this.eyeRay();
      const hit = this.raycast(o, d, 5, { noMobs: true });
      const c = b.deployCandidate(it.deploy, hit, this.player.yaw + (this.deployRot || 0) * Math.PI / 2);
      this.deployCand = c;
      if (c.x !== undefined) b.showGhost(c, !c.err);
      else b.showGhost(null);
      this.ui.setBuildInfo(`<b>${it.name}</b> · ЛКМ — поставить, R — повернуть${c.err ? `<br><span class="err">${c.err}</span>` : ''}`);
    } else if (it && it.special === 'hammer' && !this.ui.open) {
      b.hideGhost();
      const hit = this.aimHit;
      if (hit && hit.kind === 'piece' && hit.t < 4) {
        const pc = hit.obj;
        let txt = `<b>${pc.type === 'door' ? 'Дверь' : PIECES[pc.type].name}</b> (${pc.type === 'door' ? 'дерево' : TIERS[pc.tier].name})`;
        if (pc.type !== 'door' && pc.tier < TIERS.length - 1) {
          const nt = TIERS[pc.tier + 1];
          txt += `<br>ЛКМ — улучшить до «${nt.name}»: ${costText(nt.cost, PIECES[pc.type].mult)}`;
        }
        txt += '<br>ПКМ — разобрать';
        this.ui.setBuildInfo(txt);
      } else if (hit && hit.kind === 'deploy' && hit.t < 4) {
        this.ui.setBuildInfo(`<b>${hit.obj.name}</b><br>ПКМ — подобрать`);
      } else {
        this.ui.setBuildInfo('<b>Киянка</b><br>Наведитесь на постройку');
      }
    } else if (it && it.deploy === 'door' && !this.ui.open) {
      b.hideGhost();
      this.ui.setBuildInfo('<b>Дверь</b><br>Наведитесь на дверной проём и нажмите ЛКМ');
    } else {
      if (b.ghost.visible) b.hideGhost();
      this.ui.setBuildInfo('');
    }
    if (it && it.gun) this.ui.setAmmo(`${s.ammo} / ${this.inv.count(it.gun.ammo)}${this.reloadT > 0 ? ' · перезарядка' : ''}`);
    else if (it && it.ranged) this.ui.setAmmo(`➶ ${this.inv.count(it.ranged.ammo)}`);
    else this.ui.setAmmo('');
    if (!(it && (it.gun || it.ranged))) this.aim = false;
  }

  render() {
    const drawVm = this.state === 'play' && this.vm && this.vm.visible;
    this.gfx.render(this.scene, this.camera, this.vmScene, this.vmCamera, drawVm, performance.now() / 1000, this.hurtFx, this.underwater);
  }

  // ---------- Сохранение ----------
  serialize() {
    const p = this.player;
    return {
      v: 1, t: Date.now(), day: this.dayTime,
      p: { x: p.pos.x, y: p.pos.y, z: p.pos.z, yaw: p.yaw, pitch: p.pitch, hp: p.hp, food: p.food, water: p.water, alive: p.alive },
      inv: this.inv.serialize(), slot: this.slot,
      b: this.building.serialize(),
      bags: this.ents.serializeBags(),
      bag: this.spawnBag ? { x: this.spawnBag.x, z: this.spawnBag.z } : null,
    };
  }

  save() {
    if (this.state === 'loading') return;
    let json;
    try {
      json = JSON.stringify(this.serialize());
      localStorage.setItem(SAVE_KEY, json);
    } catch (e) { /* ignore */ }
    const now = Date.now();
    if (json && now - this.cloudT > 60000) {
      this.cloudT = now;
      Y.saveCloud(json);
    }
  }

  load(json) {
    try {
      const s = typeof json === 'string' ? JSON.parse(json) : json;
      if (!s || s.v !== 1) return false;
      this.dayTime = s.day || 0.3;
      this.building.load(s.b);
      this.ents.loadBags(s.bags);
      this.inv.load(s.inv);
      this.slot = s.slot || 0;
      const p = this.player;
      p.pos.set(s.p.x, s.p.y, s.p.z);
      p.yaw = s.p.yaw; p.pitch = s.p.pitch;
      p.hp = s.p.hp; p.food = s.p.food; p.water = s.p.water;
      p.alive = true;
      this.spawnBag = null;
      if (s.bag) {
        this.spawnBag = this.building.deploys.find((d) => d.type === 'sleeping_bag' && Math.abs(d.x - s.bag.x) < 0.01 && Math.abs(d.z - s.bag.z) < 0.01) || null;
      }
      if (!s.p.alive || p.hp <= 0) this.respawn(!!this.spawnBag);
      return true;
    } catch (e) {
      console.warn('Save load failed', e);
      return false;
    }
  }
}

function rayBoxC(o, d, c, maxT) {
  let t0 = 0, t1 = maxT, nx = 0, ny = 0, nz = 0;
  const axes = [['x', c.minX, c.maxX], ['y', c.minY, c.maxY], ['z', c.minZ, c.maxZ]];
  for (let i = 0; i < 3; i++) {
    const [k, mn, mx] = axes[i];
    const oo = o[k], dd = d[k];
    if (Math.abs(dd) < 1e-9) {
      if (oo < mn || oo > mx) return null;
      continue;
    }
    let a = (mn - oo) / dd, b = (mx - oo) / dd;
    if (a > b) { const t = a; a = b; b = t; }
    if (a > t0) { t0 = a; nx = i === 0 ? -Math.sign(dd) : 0; ny = i === 1 ? -Math.sign(dd) : 0; nz = i === 2 ? -Math.sign(dd) : 0; }
    if (b < t1) t1 = b;
    if (t0 > t1) return null;
  }
  return { t: t0, nx, ny, nz };
}

const game = new Game();
window.game = game;
game.init().catch((e) => {
  console.error(e);
  const l = $('loading');
  if (l) l.textContent = 'Ошибка загрузки: ' + e.message;
});
