// Модели предметов в руках (вид от первого лица).
import * as THREE from './three.module.min.js';

const M = (c) => new THREE.MeshLambertMaterial({ color: c, flatShading: true });
const SKIN = M(0xd9a47c);
const WOOD = M(0x7a5230);
const STONE = M(0x8d8a84);
const METAL = M(0x9aa3aa);
const DARK = M(0x2e2e30);
const CLOTH = M(0xcdb991);

function b(w, h, d, m, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
  mesh.position.set(x, y, z);
  mesh.rotation.set(rx, ry, rz);
  return mesh;
}

const ITEM_COLORS = {
  wood: 0x7a5230, stones: 0x8d8a84, metal_ore: 0x8a5a3a, sulfur_ore: 0xd8c23a, metal_frag: 0x9aa3aa,
  sulfur: 0xe8d84a, charcoal: 0x222222, cloth: 0xcdb991, scrap: 0x777777, pipe: 0x9aa3aa, gunpowder: 0x333333,
  raw_meat: 0xc0504a, cooked_meat: 0x7a3f1f, mushroom: 0xb8342a, bandage: 0xf0f0e8, medkit: 0xd8e8f0,
  arrow: 0x8a6a3a, pistol_ammo: 0xd8a830, campfire: 0x7a5230, furnace: 0x8d8a84, storage_box: 0x8a6236,
  sleeping_bag: 0x4a6a3a, door: 0x6b4423,
};

export function buildViewModel(item) {
  const root = new THREE.Group();
  const pivot = new THREE.Group();
  root.add(pivot);
  const model = item ? item.model : null;
  // кулак/рука
  const hand = b(0.12, 0.12, 0.3, SKIN, 0, -0.02, 0.1);
  pivot.add(hand);
  const head = item && item.metal ? METAL : STONE;
  switch (model) {
    case 'rock':
      pivot.add(new THREE.Mesh(new THREE.IcosahedronGeometry(0.1, 0), STONE));
      pivot.children[1].position.set(0, 0.05, -0.08);
      break;
    case 'hatchet':
      pivot.add(b(0.04, 0.5, 0.04, WOOD, 0, 0.18, -0.02));
      pivot.add(b(0.03, 0.12, 0.18, head, 0, 0.38, -0.1));
      break;
    case 'pickaxe':
      pivot.add(b(0.04, 0.55, 0.04, WOOD, 0, 0.2, -0.02));
      pivot.add(b(0.04, 0.05, 0.45, head, 0, 0.44, -0.02, 0.15, 0, 0));
      break;
    case 'spear':
      pivot.add(b(0.035, 0.035, 1.6, WOOD, 0, 0.02, -0.4));
      pivot.add(new THREE.Mesh(new THREE.ConeGeometry(0.035, 0.18, 5), WOOD));
      pivot.children[2].rotation.x = -Math.PI / 2;
      pivot.children[2].position.set(0, 0.02, -1.28);
      break;
    case 'hammer':
      pivot.add(b(0.04, 0.4, 0.04, WOOD, 0, 0.15, -0.02));
      pivot.add(b(0.1, 0.1, 0.2, WOOD, 0, 0.35, -0.02));
      break;
    case 'plan': {
      const paper = b(0.28, 0.01, 0.2, M(0x3b6fb5), 0, 0.02, -0.1, 0.5, 0, 0);
      pivot.add(paper);
      pivot.add(b(0.2, 0.012, 0.01, M(0xffffff), 0, 0.03, -0.12, 0.5, 0, 0));
      pivot.add(b(0.01, 0.012, 0.14, M(0xffffff), 0.05, 0.03, -0.1, 0.5, 0, 0));
      break;
    }
    case 'bow': {
      const arc = new THREE.Mesh(new THREE.TorusGeometry(0.35, 0.015, 4, 12, Math.PI * 0.9), WOOD);
      arc.rotation.set(0, Math.PI / 2, Math.PI / 2 + Math.PI * 0.05);
      arc.position.set(0, 0.02, -0.05);
      pivot.add(arc);
      const str = b(0.004, 0.68, 0.004, CLOTH, 0, 0.02, 0.06);
      pivot.add(str);
      pivot.add(b(0.012, 0.012, 0.7, WOOD, 0.02, 0.02, -0.25));
      break;
    }
    case 'revolver':
      pivot.add(b(0.05, 0.12, 0.07, WOOD, 0, -0.04, 0.02, -0.3, 0, 0));
      pivot.add(b(0.06, 0.06, 0.1, DARK, 0, 0.06, -0.06));
      pivot.add(b(0.03, 0.03, 0.22, DARK, 0, 0.08, -0.2));
      hand.position.set(0, -0.06, 0.12);
      break;
    default:
      if (item) {
        const c = ITEM_COLORS[item.id] ?? 0xaaaaaa;
        pivot.add(b(0.12, 0.1, 0.12, M(c), 0, 0.06, -0.06));
      }
  }
  root.userData.pivot = pivot;
  return root;
}
