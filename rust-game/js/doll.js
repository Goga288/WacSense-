// 3D-фигурка персонажа в инвентаре: показывает надетую броню.
import * as THREE from './three.module.min.js';

const std = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.85, ...o });

function part(parent, geo, mat, x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  m.scale.set(sx, sy, sz);
  parent.add(m);
  return m;
}

export class Doll {
  constructor(canvas, M) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.setSize(canvas.clientWidth || 220, canvas.clientHeight || 300, false);
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(30, 220 / 300, 0.1, 20);
    this.camera.position.set(0, 1.05, 4.4);
    this.camera.lookAt(0, 0.95, 0);
    this.scene.add(new THREE.HemisphereLight(0xdde8ff, 0x3a3428, 1.6));
    const key = new THREE.DirectionalLight(0xfff0dc, 2.2);
    key.position.set(2, 3, 3);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x9fc0ff, 1.2);
    rim.position.set(-2, 2, -3);
    this.scene.add(rim);
    this.root = new THREE.Group();
    this.scene.add(this.root);
    this.build(M);
    this.t = 0;
  }

  build(M) {
    const r = this.root;
    const cap = (a, b) => new THREE.CapsuleGeometry(a, b, 4, 12);
    const skin = std(0xc4916e, { roughness: 0.6 });
    const shirt = M.cloth.clone();
    shirt.color.setHex(0x9aa07a);
    const pants = M.cloth.clone();
    pants.color.setHex(0x6a5a44);
    const boots = std(0x3a2e24);
    const hair = std(0x3a2a1c, { roughness: 1 });
    // тело
    part(r, cap(0.2, 0.42), shirt, 0, 1.2, 0, 0, 0, 0, 1.15, 1, 0.75);
    part(r, cap(0.1, 0.12), skin, 0, 1.62, 0);
    part(r, new THREE.SphereGeometry(0.15, 16, 12), skin, 0, 1.78, 0, 0, 0, 0, 0.95, 1.1, 1);
    part(r, new THREE.SphereGeometry(0.155, 16, 12, 0, Math.PI * 2, 0, Math.PI / 2.2), hair, 0, 1.8, -0.01);
    for (const sx of [-1, 1]) {
      part(r, new THREE.SphereGeometry(0.02, 8, 6), std(0x111111), sx * 0.05, 1.8, 0.135);
      part(r, cap(0.065, 0.42), shirt, sx * 0.3, 1.2, 0, 0, 0, sx * 0.12);
      part(r, new THREE.SphereGeometry(0.06, 10, 8), skin, sx * 0.34, 0.9, 0.02);
      part(r, cap(0.09, 0.5), pants, sx * 0.11, 0.55, 0);
      part(r, new THREE.BoxGeometry(0.13, 0.12, 0.24), boots, sx * 0.11, 0.08, 0.03);
    }
    // броня (видимость переключается)
    const wood = M.crate;
    const metal = M.rustMetal.clone();
    metal.color.setHex(0xb8b4ac);
    this.armor = {
      wood_armor: new THREE.Group(),
      metal_chest: new THREE.Group(),
      bucket_helmet: new THREE.Group(),
      metal_helmet: new THREE.Group(),
      armored_pants: new THREE.Group(),
    };
    const A = this.armor;
    for (let i = 0; i < 4; i++) part(A.wood_armor, new THREE.BoxGeometry(0.1, 0.46, 0.05), wood, -0.16 + i * 0.105, 1.22, 0.16);
    for (let i = 0; i < 4; i++) part(A.wood_armor, new THREE.BoxGeometry(0.1, 0.46, 0.05), wood, -0.16 + i * 0.105, 1.22, -0.16);
    part(A.wood_armor, new THREE.BoxGeometry(0.5, 0.04, 0.36), std(0x4a3a2a), 0, 1.36, 0);
    part(A.metal_chest, new THREE.BoxGeometry(0.46, 0.5, 0.08), metal, 0, 1.22, 0.15, -0.05);
    part(A.metal_chest, new THREE.BoxGeometry(0.46, 0.5, 0.06), metal, 0, 1.22, -0.15);
    for (const sx of [-1, 1]) part(A.metal_chest, new THREE.SphereGeometry(0.09, 10, 8), metal, sx * 0.28, 1.45, 0, 0, 0, 0, 1, 0.6, 1);
    for (let i = 0; i < 6; i++) part(A.metal_chest, new THREE.SphereGeometry(0.012, 6, 4), std(0x444444), -0.18 + (i % 3) * 0.18, 1.02 + Math.floor(i / 3) * 0.4, 0.2);
    part(A.bucket_helmet, new THREE.CylinderGeometry(0.19, 0.16, 0.24, 16, 1, true), metal, 0, 1.86, 0);
    part(A.bucket_helmet, new THREE.CircleGeometry(0.19, 16), metal, 0, 1.98, 0, -Math.PI / 2);
    part(A.bucket_helmet, new THREE.TorusGeometry(0.19, 0.008, 6, 16, Math.PI), std(0x333333), 0, 1.92, 0, 0, Math.PI / 2, 0);
    part(A.metal_helmet, new THREE.SphereGeometry(0.19, 16, 12, 0, Math.PI * 2, 0, Math.PI / 1.8), metal, 0, 1.8, 0);
    part(A.metal_helmet, new THREE.BoxGeometry(0.26, 0.05, 0.03), std(0x111111), 0, 1.8, 0.17);
    part(A.metal_helmet, new THREE.BoxGeometry(0.28, 0.16, 0.04), metal, 0, 1.7, 0.16);
    for (const sx of [-1, 1]) {
      part(A.armored_pants, new THREE.BoxGeometry(0.15, 0.25, 0.05), metal, sx * 0.11, 0.72, 0.1);
      part(A.armored_pants, new THREE.BoxGeometry(0.15, 0.2, 0.05), metal, sx * 0.11, 0.35, 0.1);
    }
    for (const k in A) { A[k].visible = false; r.add(A[k]); }
  }

  setEquip(slots) {
    for (const k in this.armor) this.armor[k].visible = false;
    for (const s of slots) if (s && this.armor[s.id]) this.armor[s.id].visible = true;
  }

  render(dt) {
    this.t += dt;
    this.root.rotation.y = Math.sin(this.t * 0.6) * 0.6;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (w && h && (this._w !== w || this._h !== h)) {
      this._w = w; this._h = h;
      this.renderer.setSize(w, h, false);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    }
    this.renderer.render(this.scene, this.camera);
  }
}
