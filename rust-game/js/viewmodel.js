// Модели предметов в руках (вид от первого лица).
import * as THREE from './three.module.min.js';
import { rockGeo } from './models.js';

const std = (o) => new THREE.MeshStandardMaterial({ roughness: 0.8, metalness: 0, ...o });
const SKIN = std({ color: 0xc4916e, roughness: 0.65 });
const WOOD = std({ color: 0x7a5534, roughness: 0.85 });
const DARK = std({ color: 0x2a2a2c, roughness: 0.45, metalness: 0.7 });
const ROPE = std({ color: 0xb09a6a, roughness: 1 });

let cache = null;
function mats(M) {
  if (cache) return cache;
  const sleeve = M.cloth.clone();
  sleeve.color.setHex(0x8a7a5c);
  const blade = M.rustMetal.clone();
  blade.color.setHex(0xb8b0a8);
  // чертёж для плана постройки
  const cv = document.createElement('canvas');
  cv.width = cv.height = 128;
  const ctx = cv.getContext('2d');
  ctx.fillStyle = '#2f5f9e';
  ctx.fillRect(0, 0, 128, 128);
  ctx.strokeStyle = 'rgba(255,255,255,0.35)';
  for (let i = 0; i <= 128; i += 16) {
    ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, 128); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(128, i); ctx.stroke();
  }
  ctx.strokeStyle = '#fff';
  ctx.lineWidth = 3;
  ctx.strokeRect(28, 40, 72, 56);
  ctx.beginPath(); ctx.moveTo(28, 40); ctx.lineTo(64, 18); ctx.lineTo(100, 40); ctx.stroke();
  const planTex = new THREE.CanvasTexture(cv);
  planTex.colorSpace = THREE.SRGBColorSpace;
  cache = {
    sleeve, blade, rock: M.rock, bark: M.bark, planks: M.crate,
    plan: std({ map: planTex, roughness: 0.9, side: THREE.DoubleSide }),
  };
  return cache;
}

function mesh(geo, m, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
  const o = new THREE.Mesh(geo, m);
  o.position.set(x, y, z);
  o.rotation.set(rx, ry, rz);
  o.scale.set(sx, sy, sz);
  return o;
}
const cap = (r, l) => new THREE.CapsuleGeometry(r, l, 4, 10);
const cyl = (r1, r2, h, n = 10) => new THREE.CylinderGeometry(r1, r2, h, n);
const box = (x, y, z) => new THREE.BoxGeometry(x, y, z);

const ITEM_COLORS = {
  wood: 0x7a5230, stones: 0x8d8a84, metal_ore: 0x8a5a3a, sulfur_ore: 0xd8c23a, metal_frag: 0x9aa3aa,
  sulfur: 0xe8d84a, charcoal: 0x222222, cloth: 0xcdb991, scrap: 0x777777, pipe: 0x9aa3aa, gunpowder: 0x333333,
  raw_meat: 0xa8403a, cooked_meat: 0x6a3a1c, mushroom: 0x8a5a36, bandage: 0xe8e4d8, medkit: 0xd8e8f0,
  arrow: 0x8a6a3a, pistol_ammo: 0xc89a30, campfire: 0x7a5230, furnace: 0x8d8a84, storage_box: 0x8a6236,
  sleeping_bag: 0x6a7a4a, door: 0x6b4423,
};

// Кисть руки, сжимающая рукоять (рукоять — вдоль оси Y).
function hand(M, grip = true) {
  const m = mats(M);
  const g = new THREE.Group();
  g.add(mesh(cap(0.05, 0.3), SKIN, 0, -0.06, 0.2, Math.PI / 2 - 0.25, 0, 0));
  g.add(mesh(cyl(0.068, 0.07, 0.2, 12), m.sleeve, 0, -0.1, 0.36, Math.PI / 2 - 0.25, 0, 0));
  g.add(mesh(new THREE.SphereGeometry(0.058, 12, 10), SKIN, 0.0, -0.02, 0.03, 0, 0, 0, 1, 0.9, 1.25));
  if (grip) {
    for (let i = 0; i < 4; i++) {
      g.add(mesh(cap(0.017, 0.05), SKIN, -0.035, 0.02 - i * 0.028, -0.03, 0, 0, Math.PI / 2));
    }
    g.add(mesh(cap(0.018, 0.05), SKIN, 0.035, 0.03, -0.02, 0.5, 0, 0.6));
  }
  return g;
}

// Вспышка выстрела у дула.
function addFlash(M, pivot, root, z, y, size) {
  const fl = new THREE.Sprite(M.flame.clone());
  fl.scale.setScalar(size);
  fl.position.set(0, y, z);
  fl.visible = false;
  pivot.add(fl);
  root.userData.flash = fl;
}

// Внешние модели (CC0 .glb), если игрок положил их в папку models/.
export const external = {};

function attachExternal(item, pivot) {
  const ext = external[item.id];
  if (!ext) return false;
  const o = ext.scene.clone(true);
  o.traverse((c) => { if (c.isMesh) { c.castShadow = false; } });
  if (ext.transform) {
    const t = ext.transform;
    if (t.rot) o.rotation.set(...t.rot);
    if (t.pos) o.position.set(...t.pos);
    if (t.scale) o.scale.setScalar(t.scale);
  } else {
    // автоподгонка: длинная ось — вперёд (-Z), длина — как у встроенной модели
    const b = new THREE.Box3().setFromObject(o);
    const sz = b.getSize(new THREE.Vector3());
    if (sz.x > sz.z && sz.x > sz.y) o.rotation.y = Math.PI / 2;
    const b2 = new THREE.Box3().setFromObject(o);
    const s2 = b2.getSize(new THREE.Vector3());
    const len = Math.max(s2.x, s2.y, s2.z) || 1;
    const target = ext.length || 0.9;
    o.scale.multiplyScalar(target / len);
    const b3 = new THREE.Box3().setFromObject(o);
    const c = b3.getCenter(new THREE.Vector3());
    o.position.sub(c).add(new THREE.Vector3(0, 0.05, -target * 0.35));
  }
  pivot.add(o);
  return true;
}

export function buildViewModel(item, M) {
  const m = mats(M);
  const root = new THREE.Group();
  const pivot = new THREE.Group();
  root.add(pivot);
  const model = item ? item.model : null;
  const head = item && item.metal ? m.blade : m.rock;
  pivot.add(hand(M, !!model || !item));
  if (item && attachExternal(item, pivot)) {
    root.userData.pivot = pivot;
    return root;
  }
  switch (model) {
    case 'rock': {
      const r = mesh(rockGeo(606), m.rock, 0, 0.05, -0.06);
      r.scale.setScalar(0.1);
      pivot.add(r);
      break;
    }
    case 'hatchet':
      pivot.add(mesh(cyl(0.018, 0.022, 0.5), WOOD, 0, 0.16, 0));
      if (item.metal) {
        pivot.add(mesh(box(0.025, 0.12, 0.17), m.blade, 0, 0.36, -0.08));
        pivot.add(mesh(box(0.05, 0.06, 0.06), DARK, 0, 0.36, 0));
      } else {
        const st = mesh(rockGeo(707), m.rock, 0, 0.36, -0.07);
        st.scale.set(0.04, 0.07, 0.11);
        pivot.add(st);
        pivot.add(mesh(new THREE.TorusGeometry(0.03, 0.01, 6, 12), ROPE, 0, 0.34, 0, Math.PI / 2, 0, 0));
        pivot.add(mesh(new THREE.TorusGeometry(0.03, 0.01, 6, 12), ROPE, 0, 0.38, 0, Math.PI / 2, 0, 0));
      }
      break;
    case 'pickaxe':
      pivot.add(mesh(cyl(0.018, 0.022, 0.55), WOOD, 0, 0.19, 0));
      pivot.add(mesh(new THREE.ConeGeometry(0.03, 0.24, 6), head, 0, 0.44, -0.12, -Math.PI / 2 - 0.2, 0, 0));
      pivot.add(mesh(new THREE.ConeGeometry(0.03, 0.2, 6), head, 0, 0.44, 0.1, Math.PI / 2 + 0.2, 0, 0));
      pivot.add(mesh(new THREE.TorusGeometry(0.03, 0.01, 6, 12), ROPE, 0, 0.44, 0, Math.PI / 2, 0, 0));
      break;
    case 'spear':
      pivot.add(mesh(cyl(0.016, 0.02, 1.7), WOOD, 0, 0.02, -0.4, Math.PI / 2, 0, 0));
      pivot.add(mesh(new THREE.ConeGeometry(0.02, 0.18, 7), WOOD, 0, 0.02, -1.33, -Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.024, 0.024, 0.12), ROPE, 0, 0.02, -1.15, Math.PI / 2, 0, 0));
      break;
    case 'hammer':
      pivot.add(mesh(cyl(0.018, 0.022, 0.4), WOOD, 0, 0.13, 0));
      pivot.add(mesh(cyl(0.05, 0.05, 0.2), m.bark, 0, 0.34, -0.02, Math.PI / 2, 0, 0));
      break;
    case 'plan': {
      const p = mesh(new THREE.PlaneGeometry(0.28, 0.22), m.plan, -0.02, 0.04, -0.1, -0.9, 0.1, 0);
      pivot.add(p);
      break;
    }
    case 'bow': {
      const arc = mesh(new THREE.TorusGeometry(0.38, 0.014, 6, 24, Math.PI * 0.85), WOOD, 0, 0.02, -0.02, 0, Math.PI / 2, Math.PI / 2 + Math.PI * 0.075);
      pivot.add(arc);
      pivot.add(mesh(cyl(0.003, 0.003, 0.72), ROPE, 0, 0.02, 0.11));
      pivot.add(mesh(cyl(0.006, 0.006, 0.75), WOOD, 0.02, 0.02, -0.25, Math.PI / 2, 0, 0));
      pivot.add(mesh(new THREE.ConeGeometry(0.012, 0.05, 5), DARK, 0.02, 0.02, -0.64, -Math.PI / 2, 0, 0));
      break;
    }
    case 'revolver':
      pivot.add(mesh(box(0.045, 0.13, 0.07), WOOD, 0, -0.04, 0.02, -0.3, 0, 0));
      pivot.add(mesh(box(0.05, 0.07, 0.1), DARK, 0, 0.06, -0.05));
      pivot.add(mesh(cyl(0.035, 0.035, 0.07, 8), DARK, 0, 0.06, -0.06, Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.014, 0.016, 0.22, 10), DARK, 0, 0.085, -0.2, Math.PI / 2, 0, 0));
      pivot.add(mesh(box(0.008, 0.015, 0.01), DARK, 0, 0.1, -0.3));
      {
        const fl = new THREE.Sprite(M.flame.clone());
        fl.scale.setScalar(0.22);
        fl.position.set(0, 0.085, -0.36);
        fl.visible = false;
        pivot.add(fl);
        root.userData.flash = fl;
      }
      break;
    case 'torch': {
      pivot.add(mesh(cyl(0.018, 0.024, 0.55), WOOD, 0, 0.18, 0));
      pivot.add(mesh(cyl(0.036, 0.03, 0.13), std({ color: 0x3a2a1a, roughness: 1 }), 0, 0.46, 0));
      const flames = [];
      for (let i = 0; i < 4; i++) {
        const fl = new THREE.Sprite(M.flame.clone());
        fl.position.set((Math.random() - 0.5) * 0.04, 0.55, (Math.random() - 0.5) * 0.04);
        fl.userData.ph = Math.random();
        pivot.add(fl);
        flames.push(fl);
      }
      root.userData.flames = flames;
      break;
    }
    case 'ak': {
      const M2 = DARK, W = WOOD;
      pivot.add(mesh(box(0.052, 0.07, 0.36), M2, 0, 0.06, -0.12));           // ствольная коробка
      pivot.add(mesh(box(0.046, 0.02, 0.3), M2, 0, 0.1, -0.12));             // крышка
      pivot.add(mesh(box(0.058, 0.06, 0.2), W, 0, 0.05, -0.38));             // цевьё
      pivot.add(mesh(box(0.04, 0.03, 0.18), W, 0, 0.1, -0.38));              // накладка
      pivot.add(mesh(cyl(0.013, 0.013, 0.32, 10), M2, 0, 0.065, -0.62, Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.011, 0.011, 0.28, 8), M2, 0, 0.1, -0.52, Math.PI / 2, 0, 0)); // газовая трубка
      pivot.add(mesh(cyl(0.019, 0.017, 0.07, 10), M2, 0, 0.065, -0.8, Math.PI / 2, 0, 0)); // дульный тормоз
      pivot.add(mesh(box(0.012, 0.045, 0.014), M2, 0, 0.1, -0.74));          // мушка
      pivot.add(mesh(box(0.03, 0.02, 0.04), M2, 0, 0.11, -0.3));             // прицел
      for (let i = 0; i < 4; i++) {                                          // изогнутый магазин
        pivot.add(mesh(box(0.034, 0.05, 0.064), M2, 0, -0.005 - i * 0.043, -0.22 + i * 0.018, 0.25 + i * 0.12, 0, 0));
      }
      pivot.add(mesh(box(0.034, 0.1, 0.045), W, 0, -0.02, -0.02, -0.35, 0, 0)); // рукоять
      pivot.add(mesh(box(0.042, 0.075, 0.26), W, 0, 0.03, 0.16, -0.12, 0, 0));  // приклад
      pivot.add(mesh(box(0.03, 0.035, 0.03), M2, 0, 0.0, -0.08));           // спуск
      addFlash(M, pivot, root, -0.86, 0.065, 0.3);
      break;
    }
    case 'bolt': {
      const M2 = DARK, W = WOOD;
      pivot.add(mesh(box(0.045, 0.06, 0.3), M2, 0, 0.06, -0.14));
      pivot.add(mesh(cyl(0.012, 0.014, 0.62, 10), M2, 0, 0.065, -0.6, Math.PI / 2, 0, 0));
      pivot.add(mesh(box(0.056, 0.07, 0.62), W, 0, 0.03, -0.2));             // ложа
      pivot.add(mesh(box(0.046, 0.09, 0.26), W, 0, 0.0, 0.18, -0.18, 0, 0));  // приклад
      pivot.add(mesh(cyl(0.022, 0.022, 0.26, 12), M2, 0, 0.135, -0.14, Math.PI / 2, 0, 0)); // прицел
      pivot.add(mesh(cyl(0.028, 0.022, 0.06, 12), M2, 0, 0.135, -0.3, Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.026, 0.022, 0.05, 12), M2, 0, 0.135, 0.01, Math.PI / 2, 0, 0));
      pivot.add(mesh(box(0.014, 0.04, 0.02), M2, 0, 0.1, -0.2));
      pivot.add(mesh(box(0.014, 0.04, 0.02), M2, 0, 0.1, -0.08));
      const handle = mesh(cyl(0.006, 0.006, 0.07, 6), M2, 0.04, 0.07, -0.03, 0, 0, Math.PI / 2 - 0.3);
      pivot.add(handle);
      pivot.add(mesh(new THREE.SphereGeometry(0.012, 8, 6), M2, 0.075, 0.06, -0.03));
      root.userData.bolt = handle;
      addFlash(M, pivot, root, -0.93, 0.065, 0.3);
      break;
    }
    case 'lmg': {
      const M2 = DARK;
      pivot.add(mesh(box(0.07, 0.09, 0.42), M2, 0, 0.06, -0.14));
      pivot.add(mesh(box(0.075, 0.075, 0.24), M2, 0, 0.055, -0.46));
      for (let i = 0; i < 5; i++) pivot.add(mesh(box(0.077, 0.012, 0.03), std({ color: 0x111111 }), 0, 0.075, -0.37 - i * 0.045));
      pivot.add(mesh(cyl(0.016, 0.016, 0.34, 10), M2, 0, 0.06, -0.74, Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.022, 0.02, 0.07, 10), M2, 0, 0.06, -0.92, Math.PI / 2, 0, 0));
      pivot.add(mesh(box(0.1, 0.11, 0.1), std({ color: 0x3a4a30, roughness: 0.8 }), -0.07, -0.02, -0.16)); // короб с лентой
      pivot.add(mesh(box(0.02, 0.03, 0.16), M2, 0, 0.13, -0.18));           // ручка
      pivot.add(mesh(box(0.02, 0.04, 0.02), M2, 0, 0.115, -0.1));
      pivot.add(mesh(box(0.02, 0.04, 0.02), M2, 0, 0.115, -0.26));
      pivot.add(mesh(box(0.035, 0.1, 0.045), M2, 0, -0.03, -0.0, -0.3, 0, 0));
      pivot.add(mesh(box(0.05, 0.09, 0.24), M2, 0, 0.04, 0.17, -0.08, 0, 0));
      pivot.add(mesh(cyl(0.006, 0.006, 0.22, 6), M2, -0.02, 0.02, -0.66, Math.PI / 2 - 0.1, 0, 0)); // сошки
      pivot.add(mesh(cyl(0.006, 0.006, 0.22, 6), M2, 0.02, 0.02, -0.66, Math.PI / 2 - 0.1, 0, 0));
      addFlash(M, pivot, root, -0.98, 0.06, 0.34);
      break;
    }
    case 'shotgun': {
      const M2 = DARK, W = WOOD;
      pivot.add(mesh(box(0.05, 0.075, 0.26), M2, 0, 0.06, -0.1));
      pivot.add(mesh(cyl(0.016, 0.016, 0.56, 10), M2, 0, 0.08, -0.52, Math.PI / 2, 0, 0));
      pivot.add(mesh(cyl(0.013, 0.013, 0.46, 10), M2, 0, 0.045, -0.46, Math.PI / 2, 0, 0)); // трубчатый магазин
      const pump = mesh(cyl(0.024, 0.024, 0.16, 10), W, 0, 0.045, -0.42, Math.PI / 2, 0, 0);
      pivot.add(pump);
      root.userData.pump = pump;
      pivot.add(mesh(box(0.034, 0.1, 0.045), W, 0, -0.02, 0.0, -0.35, 0, 0));
      pivot.add(mesh(box(0.045, 0.085, 0.26), W, 0, 0.03, 0.17, -0.12, 0, 0));
      pivot.add(mesh(new THREE.SphereGeometry(0.008, 6, 4), std({ color: 0xd8c070, metalness: 0.8, roughness: 0.3 }), 0, 0.1, -0.79));
      addFlash(M, pivot, root, -0.84, 0.08, 0.36);
      break;
    }
    default:
      if (item) {
        const c = ITEM_COLORS[item.id] ?? 0xaaaaaa;
        pivot.add(mesh(new THREE.BoxGeometry(0.11, 0.09, 0.11), std({ color: c }), 0, 0.06, -0.05));
      }
  }
  root.userData.pivot = pivot;
  return root;
}
