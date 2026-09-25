// Процедурные модели машин (собственный дизайн, без марок и логотипов).
import * as THREE from './three.module.min.js';

export const SPECS = {
  sedan: { L: 4.6, W: 1.85, H: 1.45, belt: 0.97, clr: 0.2, R: 0.34, fOH: 0.95, rOH: 0.9, hood: 1.15, ws: 0.7, deck: 0.85, rg: 0.7, hoodDrop: 0.14, maxV: 50, acc: 7, name: 'Седан' },
  sport: { L: 4.5, W: 1.98, H: 1.24, belt: 0.83, clr: 0.14, R: 0.36, fOH: 1.02, rOH: 0.86, hood: 1.45, ws: 0.85, deck: 0.45, rg: 1.2, hoodDrop: 0.2, spoiler: true, seats2: true, maxV: 80, acc: 12, name: 'Спорткар' },
  limo: { L: 6.7, W: 1.9, H: 1.5, belt: 1.0, clr: 0.2, R: 0.36, fOH: 1.0, rOH: 1.0, hood: 1.2, ws: 0.7, deck: 0.9, rg: 0.72, hoodDrop: 0.14, pillars: 3, maxV: 56, acc: 6.5, name: 'Лимузин' },
  hatch: { L: 4.0, W: 1.78, H: 1.5, belt: 0.96, clr: 0.18, R: 0.32, fOH: 0.85, rOH: 0.6, hood: 1.05, ws: 0.72, deck: 0.12, rg: 0.28, hoodDrop: 0.15 },
  suv: { L: 4.8, W: 1.95, H: 1.78, belt: 1.12, clr: 0.32, R: 0.4, fOH: 0.95, rOH: 0.95, hood: 1.25, ws: 0.62, deck: 0.18, rg: 0.3, hoodDrop: 0.1 },
  van: { L: 5.3, W: 2.0, H: 2.35, belt: 1.15, clr: 0.24, R: 0.36, fOH: 0.9, rOH: 1.0, hood: 0.75, ws: 0.55, deck: 0.05, rg: 0.05, hoodDrop: 0.2, van: true },
  bus: { L: 11.5, W: 2.5, H: 3.1, belt: 1.15, clr: 0.3, R: 0.48, fOH: 2.4, rOH: 3.0, hood: 0.08, ws: 0.15, deck: 0.05, rg: 0.05, hoodDrop: 0.0, bus: true },
};

const tmpV = new THREE.Vector3(), tmpV2 = new THREE.Vector3();

function mesh(geo, mat, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.rotation.set(rx, ry, rz);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}
const box = (x, y, z) => new THREE.BoxGeometry(x, y, z);

// Брусок между двумя точками (стойки кузова и т.п.).
// mat может быть массивом по граням бокса [+x, -x, +y, -y, +z, -z] (внутренняя обшивка стоек).
function beam(p1, p2, t, mat) {
  const len = tmpV.copy(p2).sub(p1).length();
  const m = new THREE.Mesh(box(t, len, t), mat);
  m.position.copy(p1).add(p2).multiplyScalar(0.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), tmpV2.copy(p2).sub(p1).normalize());
  m.castShadow = true;
  return m;
}

function extrude(shape, depth, bevel, mat) {
  const g = new THREE.ExtrudeGeometry(shape, {
    depth: depth - bevel * 2, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel * 0.85, bevelOffset: -bevel * 0.85,
    bevelSegments: 4, curveSegments: 24,
  });
  g.translate(0, 0, -depth / 2 + bevel);
  const m = new THREE.Mesh(g, mat);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

// Колесо: шина (вращение профиля), литой диск со спицами, тормозной диск.
function wheel(R, width, M, outward) {
  const g = new THREE.Group();
  const rimR = R * 0.66;
  const w = width / 2;
  const prof = [
    new THREE.Vector2(rimR, -w), new THREE.Vector2(R - 0.05, -w), new THREE.Vector2(R, -w + 0.05),
    new THREE.Vector2(R, w - 0.05), new THREE.Vector2(R - 0.05, w), new THREE.Vector2(rimR, w),
  ];
  const tire = new THREE.Mesh(new THREE.LatheGeometry(prof, 36), M.rubber);
  tire.rotation.x = Math.PI / 2;
  tire.castShadow = true;
  g.add(tire);
  const face = new THREE.Group();
  face.position.z = outward * (w - 0.03);
  g.add(face);
  const rim = new THREE.Mesh(new THREE.CylinderGeometry(rimR, rimR, 0.04, 32), M.rim);
  rim.rotation.x = Math.PI / 2;
  face.add(rim);
  const barrel = new THREE.Mesh(new THREE.CylinderGeometry(rimR * 0.98, rimR * 0.98, width * 0.85, 32, 1, true), M.rimDark);
  barrel.rotation.x = Math.PI / 2;
  barrel.position.z = -outward * width * 0.4;
  face.add(barrel);
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    const sp = new THREE.Mesh(box(rimR * 0.9, 0.055, 0.035), M.rim);
    sp.position.set(Math.cos(a) * rimR * 0.48, Math.sin(a) * rimR * 0.48, outward * 0.03);
    sp.rotation.z = a;
    face.add(sp);
  }
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(rimR * 0.2, rimR * 0.2, 0.06, 16), M.chrome);
  hub.rotation.x = Math.PI / 2;
  hub.position.z = outward * 0.04;
  face.add(hub);
  const disc = new THREE.Mesh(new THREE.CylinderGeometry(rimR * 0.82, rimR * 0.82, 0.03, 24), M.disc);
  disc.rotation.x = Math.PI / 2;
  disc.position.z = -outward * 0.08;
  face.add(disc);
  const caliper = new THREE.Mesh(box(0.1, 0.16, 0.06), M.caliper);
  caliper.position.set(rimR * 0.62, rimR * 0.3, -outward * 0.06);
  g.add(caliper);
  return g;
}

// Салон: сиденья, торпедо, приборы, руль, экран, КПП, обшивка дверей.
function interior(body, s, M, full) {
  const I = new THREE.Group();
  body.add(I);
  const zin = s.W * 0.4;
  const floorY = s.clr + 0.12;
  const seatX = s.L / 2 - s.hood - (s.sport ? 1.1 : 1.0);
  const drvZ = -s.W * 0.21, pasZ = s.W * 0.21;
  if (!full) {
    // упрощённый салон для трафика: тёмные сиденья и силуэт водителя
    for (const z of [drvZ, pasZ]) I.add(mesh(box(0.5, 0.55, 0.45), M.dash, seatX, floorY + 0.45, z));
    const head = mesh(new THREE.SphereGeometry(0.11, 12, 10), M.skin, seatX + 0.05, s.belt + 0.22, drvZ);
    I.add(head);
    I.add(mesh(box(0.35, 0.3, 0.38), M.shirt, seatX + 0.05, s.belt - 0.05, drvZ));
    return {};
  }
  // пол
  I.add(mesh(box(s.L - s.hood - 0.6, 0.02, s.W * 0.78), M.carpet, -0.2 + (s.L / 2 - s.hood - (s.L - s.hood - 0.6) / 2 - 0.3) + 0.2, floorY, 0));
  // сиденья
  // сиденья масштабируются под высоту салона, чтобы подголовники не торчали сквозь крышу
  const k = Math.max(0.62, Math.min(1, (s.H - floorY - 0.1) / 1.22));
  const seat = (x, z) => {
    const g = new THREE.Group();
    g.position.set(x, floorY, z);
    g.scale.set(k, k, Math.min(1, k + 0.15));
    const cushion = mesh(new THREE.CapsuleGeometry(0.2, 0.18, 6, 16), M.leather, 0.02, 0.32, 0, 0, 0, Math.PI / 2);
    cushion.scale.set(1, 1, 1.15);
    g.add(cushion);
    const back = mesh(new THREE.CapsuleGeometry(0.22, 0.36, 6, 16), M.leather, -0.26, 0.72, 0, 0, 0, 0.22);
    back.scale.set(0.45, 1, 1.05);
    g.add(back);
    const bolsterL = mesh(new THREE.CapsuleGeometry(0.05, 0.4, 4, 10), M.leatherDark, -0.22, 0.72, -0.2, 0, 0, 0.22);
    const bolsterR = bolsterL.clone();
    bolsterR.position.z = 0.2;
    g.add(bolsterL, bolsterR);
    const head = mesh(new THREE.CapsuleGeometry(0.1, 0.12, 4, 12), M.leather, -0.36, 1.12, 0, 0, 0, Math.PI / 2 + 0.2);
    head.scale.set(1, 1, 1.2);
    g.add(head);
    g.add(mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.14), M.chrome, -0.33, 1.0, 0.07, 0, 0, 0.2));
    g.add(mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.14), M.chrome, -0.33, 1.0, -0.07, 0, 0, 0.2));
    I.add(g);
  };
  seat(seatX, drvZ);
  seat(seatX, pasZ);
  // задний диван (для лимузина — два ряда)
  const rows = s.seats2 ? 0 : s.pillars ? 2 : 1;
  for (let r = 0; r < rows; r++) {
    const bx = seatX - 0.88 - r * 1.3;
    const bench = mesh(box(0.5, 0.16, s.W * 0.7), M.leather, bx, floorY + 0.3 * k, 0);
    I.add(bench);
    I.add(mesh(box(0.14, 0.6 * k, s.W * 0.7), M.leather, bx - 0.28, floorY + 0.65 * k, 0, 0, 0, 0.18));
    for (const z of [-s.W * 0.22, s.W * 0.22]) {
      const hr = mesh(new THREE.CapsuleGeometry(0.09, 0.1, 4, 12), M.leather, bx - 0.3, floorY + 0.98 * k, z, 0, 0, Math.PI / 2 + 0.2);
      hr.scale.set(k, 1, 1.1);
      I.add(hr);
    }
  }
  // торпедо
  const cowlX = s.L / 2 - s.hood;
  const dashShape = new THREE.Shape();
  dashShape.moveTo(cowlX - 0.05, s.belt - 0.35);
  dashShape.lineTo(cowlX + 0.05, s.belt - 0.01);
  dashShape.quadraticCurveTo(cowlX - 0.25, s.belt + 0.07, cowlX - 0.5, s.belt + 0.01);
  dashShape.lineTo(cowlX - 0.55, s.belt - 0.12);
  dashShape.quadraticCurveTo(cowlX - 0.45, s.belt - 0.3, cowlX - 0.3, s.belt - 0.35);
  dashShape.closePath();
  const dash = extrude(dashShape, s.W * 0.8, 0.03, M.dash);
  I.add(dash);
  // карбоновая вставка
  I.add(mesh(box(0.02, 0.05, s.W * 0.78), M.carbon, cowlX - 0.51, s.belt - 0.04, 0, 0, 0, 0.3));
  // козырёк приборов и приборы
  const visor = mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.3, 24, 1, true, 0, Math.PI), M.dashSide, cowlX - 0.4, s.belt + 0.04, drvZ, 0, 0, Math.PI / 2);
  visor.scale.set(1, 1, 0.55);
  I.add(visor);
  const cluster = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.17), M.dials);
  cluster.position.set(cowlX - 0.47, s.belt + 0.06, drvZ);
  cluster.rotation.set(0, -Math.PI / 2, 0);
  cluster.rotateX(-0.25);
  I.add(cluster);
  const needleGeo = new THREE.PlaneGeometry(0.066, 0.006);
  needleGeo.translate(0.03, 0, 0);
  const mkNeedle = (lx) => {
    const n = new THREE.Mesh(needleGeo, M.needle);
    n.position.set(lx, 0, 0.003);
    cluster.add(n);
    const cap = new THREE.Mesh(new THREE.CircleGeometry(0.009, 16), M.chrome);
    cap.position.set(lx, 0, 0.004);
    cluster.add(cap);
    return n;
  };
  const speedNeedle = mkNeedle(-0.085), rpmNeedle = mkNeedle(0.085);
  // руль
  const wheelG = new THREE.Group();
  wheelG.position.set(cowlX - 0.74, s.belt - 0.13, drvZ);
  wheelG.rotation.z = -0.4;
  I.add(wheelG);
  const spin = new THREE.Group();
  wheelG.add(spin);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(0.18, 0.022, 14, 48), M.leatherDark);
  rim.rotation.y = Math.PI / 2;
  spin.add(rim);
  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.07, 0.06, 24), M.dash);
  hub.rotation.z = Math.PI / 2;
  spin.add(hub);
  for (const a of [Math.PI / 2 + 0.2, -Math.PI / 2 - 0.2, Math.PI]) {
    const sp = new THREE.Mesh(box(0.02, 0.16, 0.035), M.chrome);
    sp.position.set(0, Math.sin(a) * 0.09, Math.cos(a) * 0.09);
    sp.rotation.x = -a + Math.PI / 2;
    spin.add(sp);
  }
  wheelG.add(mesh(new THREE.CylinderGeometry(0.03, 0.035, 0.35, 12), M.dash, 0.18, 0, 0, 0, 0, Math.PI / 2));
  // экран навигатора
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(0.24, 0.15), M.nav);
  screen.position.set(cowlX - 0.52, s.belt - 0.02, 0);
  screen.rotation.set(0, -Math.PI / 2, 0);
  screen.rotateX(-0.2);
  I.add(screen);
  // моторный щит / ниша для ног (ковролин)
  const fw = Math.min(cowlX, s.L / 2 - s.fOH - s.R - 0.07) - 0.05;
  const fwm = new THREE.Mesh(new THREE.PlaneGeometry(s.W * 0.86, s.belt - floorY), M.carpet);
  fwm.position.set(fw, (s.belt + floorY) / 2 - 0.05, 0);
  fwm.rotation.y = -Math.PI / 2;
  I.add(fwm);
  // центральный тоннель, КПП
  I.add(mesh(box(0.9, 0.22, 0.24), M.dash, seatX + 0.25, floorY + 0.12, 0));
  I.add(mesh(box(0.35, 0.02, 0.18), M.carbon, seatX + 0.4, floorY + 0.24, 0));
  I.add(mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.14), M.chrome, seatX + 0.45, floorY + 0.31, 0));
  I.add(mesh(new THREE.SphereGeometry(0.035, 16, 12), M.leatherDark, seatX + 0.45, floorY + 0.39, 0));
  // обшивка дверей
  for (const sz of [-1, 1]) {
    const ph = s.belt - floorY;
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(s.L - s.hood - s.deck - 0.2, ph), M.doorPanel);
    panel.position.set((s.L / 2 - s.hood + (-s.L / 2 + s.deck)) / 2, floorY + ph / 2 - 0.02, sz * (zin - 0.02));
    panel.rotation.y = sz > 0 ? Math.PI : 0;
    I.add(panel);
    I.add(mesh(box(0.5, 0.05, 0.08), M.leather, seatX + 0.1, s.belt - 0.22, sz * (zin - 0.06)));
    I.add(mesh(box(0.1, 0.03, 0.03), M.chrome, seatX + 0.55, s.belt - 0.08, sz * (zin - 0.04)));
  }
  // потолок и зеркало
  const liner = new THREE.Mesh(new THREE.PlaneGeometry(Math.max(0.2, s.L - s.hood - s.deck - s.ws - s.rg + 0.05), s.W * 0.78), M.fabric);
  liner.rotation.x = Math.PI / 2;
  liner.position.set((s.L / 2 - s.hood - s.ws + (-s.L / 2 + s.deck + s.rg)) / 2, s.H - 0.06, 0);
  I.add(liner);
  const mx = s.L / 2 - s.hood - s.ws + 0.02;
  I.add(mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.07), M.plastic, mx, s.H - 0.08, 0));
  I.add(mesh(box(0.035, 0.065, 0.24), M.plastic, mx - 0.01, s.H - 0.14, 0));
  const mface = new THREE.Mesh(new THREE.PlaneGeometry(0.22, 0.05), M.mirror);
  mface.position.set(mx - 0.03, s.H - 0.14, 0);
  mface.rotation.y = -Math.PI / 2;
  I.add(mface);
  // пороги окон изнутри (обшивка верха дверей)
  for (const sz of [-1, 1]) {
    I.add(mesh(box(s.L - s.hood - s.deck - 0.15, 0.05, 0.2), M.dashSide, (s.L / 2 - s.hood + (-s.L / 2 + s.deck)) / 2, s.belt + 0.005, sz * (s.W / 2 - 0.16)));
  }
  // точка обзора водителя (в системе кузова)
  const eye = new THREE.Vector3(seatX - 0.22, floorY + 1.1 * k, drvZ);
  return { speedNeedle, rpmNeedle, steer: spin, eye };
}

export function carMaterials(T, envMap) {
  const phys = (o) => new THREE.MeshPhysicalMaterial({ envMap, ...o });
  const std = (o) => new THREE.MeshStandardMaterial({ envMap, ...o });
  return {
    paint: (color) => phys({ color, metalness: 0.55, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.04 }),
    glass: phys({ color: 0x080c10, metalness: 0, roughness: 0.03, transparent: true, opacity: 0.72, clearcoat: 0.5, envMapIntensity: 1.1, depthWrite: false }),
    chrome: std({ color: 0xe8e8e8, metalness: 1, roughness: 0.08 }),
    rim: std({ color: 0xc9ced4, metalness: 0.9, roughness: 0.22 }),
    rimDark: std({ color: 0x3a3d42, metalness: 0.8, roughness: 0.4 }),
    disc: std({ color: 0x6a6c70, metalness: 0.9, roughness: 0.35 }),
    caliper: std({ color: 0xc0282c, metalness: 0.3, roughness: 0.4 }),
    rubber: std({ map: T.tire, color: 0xffffff, roughness: 0.92 }),
    plastic: std({ color: 0x141518, roughness: 0.55, metalness: 0.2 }),
    grille: std({ color: 0x0c0d0f, roughness: 0.4, metalness: 0.6 }),
    head: std({ color: 0xffffff, emissive: 0xfff4e0, emissiveIntensity: 0.4, roughness: 0.1, metalness: 0.5 }),
    tail: std({ color: 0x5a0000, emissive: 0xff1a10, emissiveIntensity: 0.6, roughness: 0.2 }),
    blink: std({ color: 0x5a3000, emissive: 0xff9a00, emissiveIntensity: 0.0, roughness: 0.2 }),
    leather: std({ map: T.leather, roughness: 0.6 }),
    leatherDark: std({ color: 0x1c1a19, roughness: 0.55 }),
    dash: std({ map: T.soft, roughness: 0.85 }),
    dashSide: std({ map: T.soft, color: 0x9a9a9a, roughness: 0.8, side: THREE.DoubleSide }),
    trim: std({ map: T.soft, color: 0x8a8a8a, roughness: 0.9 }),
    mirror: std({ color: 0x5d6873, metalness: 1, roughness: 0.04 }),
    reverse: std({ color: 0xdadada, emissive: 0xffffff, emissiveIntensity: 0.05, roughness: 0.1 }),
    carbon: std({ map: T.carbon, roughness: 0.3, metalness: 0.4 }),
    fabric: std({ map: T.fabric, roughness: 1 }),
    carpet: std({ color: 0x1a1a1c, roughness: 1 }),
    doorPanel: std({ map: T.leather, color: 0x888888, roughness: 0.7 }),
    dials: new THREE.MeshBasicMaterial({ map: T.dials, toneMapped: false }),
    nav: new THREE.MeshBasicMaterial({ map: T.nav, toneMapped: false }),
    needle: new THREE.MeshBasicMaterial({ color: 0xff3b2f, toneMapped: false }),
    skin: std({ color: 0xc99a78, roughness: 0.7 }),
    shirt: std({ color: 0x2c3e50, roughness: 0.9 }),
    plateMats: [],
    plateTex: T.plate,
  };
}

// Сборка машины. Возвращает группу (перед машины смотрит в -Z) и ссылки на анимируемые части.
export function buildCar(kind, color, M, { interiorFull = false, plateSeed = 1 } = {}) {
  const s = { ...SPECS[kind] };
  const root = new THREE.Group();
  const body = new THREE.Group();
  body.rotation.y = Math.PI / 2;
  root.add(body);
  const paint = M.paint(color);
  const xr = -s.L / 2, xf = s.L / 2;
  const fa = xf - s.fOH, ra = xr + s.rOH;
  const yb = s.clr, belt = s.belt, ar = s.R + 0.07;
  const cowl = xf - s.hood, deck = xr + s.deck;

  // нижняя часть кузова — полая оболочка, чтобы был виден салон:
  // передний блок (капот), задний блок (багажник), тонкие боковины и пол
  const xsF = Math.min(cowl, fa - ar) - 0.02, xsR = Math.max(deck, ra + ar) + 0.02;
  const front = new THREE.Shape();
  front.moveTo(xsF, yb);
  front.lineTo(xsF, belt + 0.02);
  front.lineTo(cowl, belt + 0.02);
  front.quadraticCurveTo(xf - 0.25, belt - s.hoodDrop * 0.3, xf - 0.06, belt - s.hoodDrop);
  front.quadraticCurveTo(xf + 0.02, belt - s.hoodDrop - 0.06, xf, belt - s.hoodDrop - 0.16);
  front.lineTo(xf, yb + 0.16);
  front.quadraticCurveTo(xf, yb, xf - 0.14, yb);
  front.lineTo(fa + ar, yb);
  front.absarc(fa, s.R, ar, 0, Math.PI, false);
  front.lineTo(fa - ar, yb);
  front.lineTo(xsF, yb);
  body.add(extrude(front, s.W, 0.07, paint));
  const rear = new THREE.Shape();
  rear.moveTo(xsR, yb);
  rear.lineTo(ra + ar, yb);
  rear.absarc(ra, s.R, ar, 0, Math.PI, false);
  rear.lineTo(ra - ar, yb);
  rear.lineTo(xr + 0.12, yb);
  rear.lineTo(xr, yb + 0.14);
  rear.lineTo(xr, belt - 0.14);
  rear.quadraticCurveTo(xr, belt, xr + 0.16, belt);
  rear.lineTo(deck, belt + 0.02);
  rear.lineTo(xsR, belt + 0.02);
  rear.lineTo(xsR, yb);
  body.add(extrude(rear, s.W, 0.07, paint));
  const side = new THREE.Shape();
  side.moveTo(xsR - 0.05, yb);
  side.lineTo(xsR - 0.05, belt + 0.02);
  side.lineTo(xsF + 0.05, belt + 0.02);
  side.lineTo(xsF + 0.05, yb);
  side.closePath();
  for (const sz of [-1, 1]) {
    const w = extrude(side, 0.12, 0.04, paint);
    w.position.z = sz * (s.W / 2 - 0.06);
    body.add(w);
  }
  body.add(mesh(box(xsF - xsR, 0.08, s.W - 0.2), M.plastic, (xsF + xsR) / 2, yb + 0.08, 0));
  // остекление (купол) — сквозь него виден салон
  const cw = s.W * 0.84;
  const roofF = cowl - s.ws, roofR = deck + s.rg;
  const gl = new THREE.Shape();
  gl.moveTo(cowl - 0.02, belt);
  gl.lineTo(roofF + 0.06, s.H - 0.03);
  gl.quadraticCurveTo(roofF, s.H, roofF - 0.1, s.H);
  gl.lineTo(roofR + 0.1, s.H);
  gl.quadraticCurveTo(roofR, s.H, roofR - 0.05, s.H - 0.04);
  gl.lineTo(deck + 0.02, belt);
  gl.closePath();
  const glass = extrude(gl, cw, 0.05, M.glass);
  glass.castShadow = false;
  glass.renderOrder = 2;
  body.add(glass);
  // крыша
  const rf = new THREE.Shape();
  rf.moveTo(roofF - 0.08, s.H - 0.05);
  rf.lineTo(roofF - 0.12, s.H + 0.015);
  rf.lineTo(roofR + 0.12, s.H + 0.015);
  rf.lineTo(roofR + 0.08, s.H - 0.05);
  rf.closePath();
  body.add(extrude(rf, cw + 0.03, 0.03, paint));
  // стойки
  const zc = cw / 2;
  for (const sz of [-1, 1]) {
    const z = sz * (zc - 0.025);
    // у машины игрока стойки изнутри обшиты тёмным пластиком: грани [+x, -x, +y, -y, +z, -z]
    const pm = (inner) => {
      if (!interiorFull) return paint;
      const a = [paint, paint, paint, paint, paint, paint];
      for (const i of inner) a[i] = M.trim;
      a[sz > 0 ? 5 : 4] = M.trim;
      return a;
    };
    body.add(beam(new THREE.Vector3(cowl - 0.02, belt, z), new THREE.Vector3(roofF - 0.05, s.H, z), 0.07, pm([1])));
    body.add(beam(new THREE.Vector3(deck + 0.04, belt, z), new THREE.Vector3(roofR + 0.05, s.H, z), s.rg > 0.6 ? 0.1 : 0.16, pm([0])));
    const n = s.pillars || 1;
    for (let i = 1; i <= n; i++) {
      const x = roofF + (roofR - roofF) * (i / (n + 1)) - 0.05;
      body.add(beam(new THREE.Vector3(x, belt, z), new THREE.Vector3(x, s.H, z), 0.08, pm([])));
    }
    // молдинг по линии окон и ручки дверей
    body.add(mesh(box(roofF - roofR + 0.9, 0.025, 0.02), M.chrome, (roofF + roofR) / 2, belt + 0.005, sz * (s.W / 2 - 0.04)));
    // двери: зазоры, ручки, пороги
    if (!s.bus) {
      const dF = fa - ar - 0.06, dB = roofF + (roofR - roofF) / 2 - 0.05, dR = s.seats2 ? null : Math.max(ra + ar + 0.06, roofR + 0.05);
      const edges = s.seats2 ? [dF, roofR + 0.12] : s.van ? [dF, dB] : [dF, dB, dR];
      const hgt = belt - yb - 0.12;
      for (const x of edges) body.add(mesh(box(0.012, hgt, 0.004), M.grille, x, yb + 0.1 + hgt / 2, sz * (s.W / 2 + 0.001)));
      for (const x of s.van ? [dB + 0.22] : [edges[1] + 0.22, ...(edges[2] ? [edges[2] + 0.22] : [])]) {
        body.add(mesh(box(0.16, 0.03, 0.035), M.chrome, x, belt - 0.12, sz * (s.W / 2 + 0.012)));
      }
      body.add(mesh(box(fa - ra - ar * 2 - 0.04, 0.07, 0.05), M.plastic, (fa + ra) / 2, yb + 0.03, sz * (s.W / 2 - 0.02)));
    }
    // зеркала
    const mir = new THREE.Group();
    mir.position.set(cowl - 0.12, belt + 0.1, sz * (s.W / 2 + 0.05));
    mir.add(mesh(box(0.1, 0.12, 0.16), paint, 0, 0, sz * 0.06));
    mir.add(mesh(box(0.01, 0.09, 0.12), M.chrome, -0.05, 0, sz * 0.06));
    mir.add(mesh(box(0.06, 0.03, 0.08), M.plastic, 0.02, -0.03, 0));
    body.add(mir);
  }

  // оптика
  const lights = { tail: [], blinkL: [], blinkR: [], head: [] };
  const hy = belt - s.hoodDrop - 0.1;
  for (const sz of [-1, 1]) {
    // фара: тёмный корпус, линза и хромированный отражатель
    body.add(mesh(box(0.06, 0.13, 0.46), M.grille, xf - 0.02, hy, sz * (s.W / 2 - 0.32)));
    const h = mesh(box(0.05, 0.08, 0.3), M.head, xf, hy + 0.005, sz * (s.W / 2 - 0.36));
    lights.head.push(h);
    body.add(h);
    body.add(mesh(new THREE.SphereGeometry(0.04, 16, 12), M.chrome, xf - 0.005, hy, sz * (s.W / 2 - 0.16)));
    // фонари: стоп-сигнал, задний ход, окантовка
    const ty = belt - 0.2;
    body.add(mesh(box(0.05, 0.15, 0.52), M.grille, xr - 0.005, ty, sz * (s.W / 2 - 0.3)));
    const tl = mesh(box(0.04, 0.1, 0.34), M.tail, xr - 0.02, ty + 0.01, sz * (s.W / 2 - 0.25));
    lights.tail.push(tl);
    body.add(tl);
    body.add(mesh(box(0.04, 0.05, 0.12), M.reverse, xr - 0.02, ty - 0.03, sz * (s.W / 2 - 0.49)));
    const bf = mesh(box(0.05, 0.05, 0.1), M.blink.clone(), xf - 0.005, hy - 0.1, sz * (s.W / 2 - 0.14));
    const br = mesh(box(0.04, 0.035, 0.12), bf.material, xr - 0.02, ty + 0.055, sz * (s.W / 2 - 0.46));
    body.add(bf, br);
    (sz < 0 ? lights.blinkL : lights.blinkR).push(bf, br);
  }
  // решётка, бамперы, номера
  const gh = Math.max(0.06, Math.min(0.16, belt - s.hoodDrop - yb - 0.5));
  body.add(mesh(box(0.05, gh, s.W * 0.45), M.grille, xf, yb + 0.26 + gh / 2, 0));
  body.add(mesh(box(0.04, 0.02, s.W * 0.45), M.chrome, xf + 0.01, yb + 0.27 + gh, 0));
  body.add(mesh(box(0.14, 0.12, s.W * 0.92), M.plastic, xf, yb + 0.08, 0));
  body.add(mesh(box(0.14, 0.12, s.W * 0.92), M.plastic, xr, yb + 0.08, 0));
  // противотуманки и выхлоп
  for (const sz of [-1, 1]) {
    body.add(mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.04, 16), M.head, xf + 0.06, yb + 0.1, sz * s.W * 0.36, 0, 0, Math.PI / 2));
    if (!s.bus) body.add(mesh(new THREE.CylinderGeometry(0.04, 0.045, 0.16, 16, 1, true), M.chrome, xr - 0.02, yb + 0.02, sz * s.W * 0.28, 0, 0, Math.PI / 2));
  }
  // третий стоп-сигнал
  const tb = mesh(box(0.04, 0.03, 0.3), M.tail, deck + 0.05, belt + 0.035, 0);
  lights.tail.push(tb);
  body.add(tb);
  const plateMat = new THREE.MeshStandardMaterial({ map: M.plateTex(plateSeed), roughness: 0.5 });
  const pf = new THREE.Mesh(new THREE.PlaneGeometry(0.52, 0.11), plateMat);
  pf.position.set(xf + 0.005, yb + 0.2, 0);
  pf.rotation.y = Math.PI / 2;
  const pr = pf.clone();
  pr.position.set(xr - 0.005, yb + 0.32, 0);
  pr.rotation.y = -Math.PI / 2;
  body.add(pf, pr);
  if (s.spoiler) {
    body.add(mesh(box(0.25, 0.03, s.W * 0.85), paint, xr + 0.2, belt + 0.2, 0));
    for (const sz of [-1, 1]) body.add(mesh(box(0.08, 0.18, 0.03), M.plastic, xr + 0.25, belt + 0.1, sz * s.W * 0.3));
  }
  if (s.bus) {
    body.add(mesh(box(s.L - 0.4, 0.12, s.W + 0.01), M.plastic, 0, belt - 0.05, 0));
  }

  // колёса
  const wheels = [];
  for (const [x, front] of [[fa, true], [ra, false]]) {
    for (const sz of [-1, 1]) {
      const pivot = new THREE.Group();
      pivot.position.set(x, s.R, sz * (s.W / 2 - 0.16));
      const w = wheel(s.R, 0.26, M, sz);
      pivot.add(w);
      body.add(pivot);
      wheels.push({ pivot, spin: w, front });
    }
  }

  const inside = interior(body, s, M, interiorFull);
  // точка обзора водителя в системе root: (x,y,z)кузова → (z, y, -x)
  const eye = inside.eye ? new THREE.Vector3(inside.eye.z, inside.eye.y, -inside.eye.x) : null;
  root.traverse((o) => { if (o.isMesh && o.material !== M.glass) o.castShadow = true; });
  return { root, spec: s, wheels, lights, paint, steerWheel: inside.steer, speedNeedle: inside.speedNeedle, rpmNeedle: inside.rpmNeedle, eye };
}
