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

export function buildViewModel(item, M) {
  const m = mats(M);
  const root = new THREE.Group();
  const pivot = new THREE.Group();
  root.add(pivot);
  const model = item ? item.model : null;
  const head = item && item.metal ? m.blade : m.rock;
  pivot.add(hand(M, !!model || !item));
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
      break;
    default:
      if (item) {
        const c = ITEM_COLORS[item.id] ?? 0xaaaaaa;
        pivot.add(mesh(new THREE.BoxGeometry(0.11, 0.09, 0.11), std({ color: c }), 0, 0.06, -0.05));
      }
  }
  root.userData.pivot = pivot;
  return root;
}
