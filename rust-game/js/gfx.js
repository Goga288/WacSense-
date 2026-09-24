// Графика: качество, материалы и шейдеры, небо, окружение, облака, трава, постобработка.
import * as THREE from './three.module.min.js';
import { Sky } from './vendor/Sky.js';
import { EffectComposer } from './vendor/postprocessing/EffectComposer.js';
import { RenderPass } from './vendor/postprocessing/RenderPass.js';
import { GTAOPass } from './vendor/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from './vendor/postprocessing/UnrealBloomPass.js';
import { OutputPass } from './vendor/postprocessing/OutputPass.js';
import { buildTextures } from './textures.js';
import { smoothstep, lerp, mulberry32 } from './util.js';

// Чёткая картинка: полное разрешение, без постобработки, резкие тени и текстуры.
export const QUALITY = {
  low: { name: 'Низкая', shadows: 0, grass: 0, grassCell: 1.6, post: false, env: false, tex: 512, pr: 1.0, aniso: 4 },
  medium: { name: 'Средняя', shadows: 2048, grass: 3000, grassCell: 1.35, post: false, env: true, tex: 1024, pr: 1.5, aniso: 16 },
  high: { name: 'Высокая', shadows: 4096, grass: 6000, grassCell: 1.0, post: false, env: true, tex: 1024, pr: 2, aniso: 16 },
  // «Ультра» нагружает видеокарту: затенение в углах (GTAO), свечение ярких источников, MSAA ×4.
  ultra: { name: 'Ультра', shadows: 4096, grass: 9000, grassCell: 0.85, post: false, ao: true, bloom: true, env: true, tex: 1024, pr: 2, aniso: 16 },
};
export const QUALITY_ORDER = ['low', 'medium', 'high', 'ultra'];

export const wind = { value: 0 };

// ---------- утилиты геометрии ----------
// Склейка геометрий с сохранением UV; color — оттенок (вершинный цвет), normalFn — свои нормали.
export function mergeUV(parts, normalFn) {
  const pos = [], nor = [], uv = [], col = [];
  const c = new THREE.Color();
  for (const p of parts) {
    const g = p.geo.index ? p.geo.toNonIndexed() : p.geo.clone();
    if (p.matrix) g.applyMatrix4(p.matrix);
    if (!g.attributes.normal) g.computeVertexNormals();
    const pa = g.attributes.position.array, na = g.attributes.normal.array;
    const ua = g.attributes.uv ? g.attributes.uv.array : null;
    c.set(p.color !== undefined ? p.color : 0xffffff);
    for (let i = 0, j = 0; i < pa.length; i += 3, j += 2) {
      pos.push(pa[i], pa[i + 1], pa[i + 2]);
      if (normalFn) {
        const n = normalFn(pa[i], pa[i + 1], pa[i + 2]);
        nor.push(n[0], n[1], n[2]);
      } else nor.push(na[i], na[i + 1], na[i + 2]);
      if (ua) uv.push(ua[j] * (p.uvScale ? p.uvScale[0] : 1), ua[j + 1] * (p.uvScale ? p.uvScale[1] : 1));
      else uv.push(0, 0);
      const sh = p.shade ? p.shade(pa[i], pa[i + 1], pa[i + 2]) : 1;
      col.push(c.r * sh, c.g * sh, c.b * sh);
    }
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  out.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  out.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  return out;
}

// Индексирует геометрию, объединяя совпадающие вершины (для гладких нормалей).
export function mergeVerts(geo) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  const pa = g.attributes.position.array;
  const map = new Map();
  const pos = [], idx = [];
  for (let i = 0; i < pa.length; i += 3) {
    const k = `${Math.round(pa[i] * 1e4)},${Math.round(pa[i + 1] * 1e4)},${Math.round(pa[i + 2] * 1e4)}`;
    let id = map.get(k);
    if (id === undefined) {
      id = pos.length / 3;
      pos.push(pa[i], pa[i + 1], pa[i + 2]);
      map.set(k, id);
    }
    idx.push(id);
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  out.setIndex(idx);
  return out;
}

// Коробка с UV в мировых единицах (текстура повторяется каждые tile метров).
const boxCache = new Map();
export function worldBox(sx, sy, sz, tile = 3) {
  const k = `${sx}|${sy}|${sz}|${tile}`;
  let g = boxCache.get(k);
  if (g) return g;
  g = new THREE.BoxGeometry(sx, sy, sz);
  const uv = g.attributes.uv;
  const dims = [[sz, sy], [sz, sy], [sx, sz], [sx, sz], [sx, sy], [sx, sy]];
  for (let f = 0; f < 6; f++) {
    for (let v = 0; v < 4; v++) {
      const i = f * 4 + v;
      uv.setXY(i, uv.getX(i) * dims[f][0] / tile, uv.getY(i) * dims[f][1] / tile);
    }
  }
  boxCache.set(k, g);
  return g;
}

// ---------- шейдерные дополнения ----------
const TRIPLANAR = `
vec3 triplanar(sampler2D t, vec3 p, vec3 n, float s) {
  vec3 b = pow(abs(n), vec3(4.0));
  b /= (b.x + b.y + b.z);
  return texture2D(t, p.yz * s).rgb * b.x + texture2D(t, p.xz * s).rgb * b.y + texture2D(t, p.xy * s).rgb * b.z;
}`;

const WORLD_VARYINGS_VERT = `
  vec4 wpos4 = vec4(transformed, 1.0);
  vec3 wnrm = objectNormal;
  #ifdef USE_INSTANCING
    wpos4 = instanceMatrix * wpos4;
    wnrm = mat3(instanceMatrix) * wnrm;
  #endif
  vWPos = (modelMatrix * wpos4).xyz;
  vWNrm = normalize(mat3(modelMatrix) * wnrm);
`;

function terrainMaterial(T) {
  const m = new THREE.MeshStandardMaterial({ roughness: 0.97, metalness: 0 });
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, {
      tGrass: { value: T.grass }, tDirt: { value: T.dirt }, tRock: { value: T.rock },
      tSand: { value: T.sand }, tDetail: { value: T.detail },
    });
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec4 splat;\nvarying vec4 vSplat;\nvarying vec3 vWPos;\nvarying vec3 vWNrm;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvSplat = splat;' + WORLD_VARYINGS_VERT);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
uniform sampler2D tGrass; uniform sampler2D tDirt; uniform sampler2D tRock; uniform sampler2D tSand; uniform sampler2D tDetail;
varying vec4 vSplat; varying vec3 vWPos; varying vec3 vWNrm;
${TRIPLANAR}`)
      .replace('#include <map_fragment>', `
  vec2 wuv = vWPos.xz;
  float det = texture2D(tDetail, wuv * 0.013).r;
  float det2 = texture2D(tDetail, wuv * 0.061 + 0.37).r;
  vec3 cg = mix(texture2D(tGrass, wuv * 0.2).rgb, texture2D(tGrass, wuv * 0.047 + 0.5).rgb, 0.18);
  vec3 cd = texture2D(tDirt, wuv * 0.21).rgb;
  vec3 cs = texture2D(tSand, wuv * 0.19).rgb;
  vec3 cr = triplanar(tRock, vWPos, vWNrm, 0.11);
  vec4 w = vSplat;
  // переходы с учётом «высоты» текстур — выглядят естественнее линейного смешивания
  w.y *= 0.6 + det2 * 0.8;
  w.x *= 0.7 + (1.0 - det2) * 0.6;
  w /= max(w.x + w.y + w.z + w.w, 0.001);
  vec3 tcol = cg * w.x + cd * w.y + cr * w.z + cs * w.w;
  tcol *= 0.85 + det * 0.3;
  diffuseColor.rgb *= tcol;
`);
  };
  m.customProgramCacheKey = () => 'terrain';
  return m;
}

function rockMaterial(T) {
  const m = new THREE.MeshStandardMaterial({ roughness: 0.93, metalness: 0, vertexColors: true });
  m.onBeforeCompile = (sh) => {
    sh.uniforms.tRock = { value: T.rock };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;\nvarying vec3 vWNrm;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + WORLD_VARYINGS_VERT);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>\nuniform sampler2D tRock;\nvarying vec3 vWPos;\nvarying vec3 vWNrm;\n${TRIPLANAR}`)
      .replace('#include <map_fragment>', 'diffuseColor.rgb *= triplanar(tRock, vWPos, vWNrm, 0.35) * 1.15;');
  };
  m.customProgramCacheKey = () => 'rock';
  return m;
}

// Покачивание от ветра (трава, хвоя, листья).
function addWind(mat, key, amountExpr, strength) {
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = wind;
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float uTime;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
  vec3 ipos = vec3(0.0);
  #ifdef USE_INSTANCING
    ipos = vec3(instanceMatrix[3][0], instanceMatrix[3][1], instanceMatrix[3][2]);
  #endif
  float wph = uTime * 1.5 + ipos.x * 0.21 + ipos.z * 0.17;
  float wamt = ${amountExpr};
  transformed.x += (sin(wph) * 0.6 + sin(wph * 2.7 + position.y) * 0.25) * wamt * ${strength.toFixed(3)};
  transformed.z += cos(wph * 0.83) * 0.4 * wamt * ${strength.toFixed(3)};`);
    sh.fragmentShader = sh.fragmentShader.replace('#include <normal_fragment_begin>', '#include <normal_fragment_begin>\n  normal = normalize(vNormal);');
  };
  mat.customProgramCacheKey = () => 'wind-' + key;
}

function cardMaterial(map, key, amountExpr, strength, lambert = false, alphaTest = 0.4) {
  const opts = { map, alphaTest, side: THREE.DoubleSide, vertexColors: true };
  const m = lambert ? new THREE.MeshLambertMaterial(opts) : new THREE.MeshStandardMaterial({ ...opts, roughness: 0.85 });
  addWind(m, key, amountExpr, strength);
  return m;
}

export function cardDepth(map) {
  return new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map, alphaTest: 0.35, side: THREE.DoubleSide });
}

export function buildMaterials(T) {
  const std = (o) => new THREE.MeshStandardMaterial({ roughness: 0.9, metalness: 0, ...o });
  const M = {
    terrain: terrainMaterial(T),
    rock: rockMaterial(T),
    bark: std({ map: T.bark, normalMap: T.barkNormal, roughness: 0.95 }),
    birch: std({ map: T.birch, roughness: 0.8 }),
    needles: cardMaterial(T.needles, 'needles', 'max(position.y - 2.0, 0.0) * 0.012 + length(position.xz) * 0.025', 1, false, 0.32),
    leaves: cardMaterial(T.leaves, 'leaves', 'max(position.y - 2.0, 0.0) * 0.015 + length(position.xz) * 0.03', 1),
    bush: cardMaterial(T.leaves, 'bush', 'position.y * 0.08', 1),
    hemp: cardMaterial(T.hemp, 'hemp', 'position.y * 0.08', 1),
    grass: cardMaterial(T.grassBlade, 'grass', 'position.y', 0.22, false, 0.45),
    tiers: [
      std({ map: T.twig, alphaTest: 0.5, side: THREE.DoubleSide, roughness: 1 }),
      std({ map: T.planks, normalMap: T.planksNormal, roughness: 0.85 }),
      std({ map: T.stone, normalMap: T.stoneNormal, roughness: 0.95 }),
      std({ map: T.metal, normalMap: T.metalNormal, roughness: 0.6, metalness: 0.35 }),
    ],
    door: std({ map: T.planks, normalMap: T.planksNormal, color: 0x9a7a60, roughness: 0.8 }),
    concrete: std({ map: T.concrete, roughness: 0.95 }),
    contRed: std({ map: T.contRed, normalMap: T.metalNormal, roughness: 0.7, metalness: 0.2 }),
    contBlue: std({ map: T.contBlue, normalMap: T.metalNormal, roughness: 0.7, metalness: 0.2 }),
    contGreen: std({ map: T.contGreen, normalMap: T.metalNormal, roughness: 0.7, metalness: 0.2 }),
    rustMetal: std({ map: T.metal, normalMap: T.metalNormal, color: 0x9a7a66, roughness: 0.75, metalness: 0.3 }),
    redMetal: std({ map: T.metal, normalMap: T.metalNormal, color: 0xc06050, roughness: 0.6, metalness: 0.25 }),
    crate: std({ map: T.planks, normalMap: T.planksNormal, roughness: 0.85 }),
    crateMil: std({ map: T.planks, normalMap: T.planksNormal, color: 0x7f9a60, roughness: 0.85 }),
    barrel: std({ map: T.metal, normalMap: T.metalNormal, roughness: 0.55, metalness: 0.35 }),
    cloth: std({ map: T.cloth, roughness: 1 }),
    stoneBlocks: std({ map: T.stone, normalMap: T.stoneNormal, roughness: 0.95 }),
    vcolor: std({ vertexColors: true }),
    flame: new THREE.SpriteMaterial({ map: T.flame, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }),
  };
  M.needlesDepth = cardDepth(T.needles);
  M.leavesDepth = cardDepth(T.leaves);
  M.hempDepth = cardDepth(T.hemp);
  M.twigDepth = cardDepth(T.twig);
  M.tiers[0].userData.depth = M.twigDepth;
  return M;
}

// Подбор текстурированного материала для объектов монументов по цвету.
export function staticMaterial(M, color) {
  switch (color) {
    case 0x9b3b2b: return M.contRed;
    case 0x2f5d8a: return M.contBlue;
    case 0x3f6b3a: return M.contGreen;
    case 0xb03a2e: case 0xd04030: return M.redMetal;
    case 0x5c5a55: case 0x6d4a35: case 0x5a5550: case 0x7b3b2b: case 0x3f5063: case 0x807360: return M.rustMetal;
    default: return M.concrete;
  }
}

// ---------- Графическая система ----------
export class Gfx {
  constructor(game, qualityKey) {
    this.game = game;
    this.qkey = QUALITY[qualityKey] ? qualityKey : 'high';
    this.q = QUALITY[this.qkey];
    const r = game.renderer;
    this.T = buildTextures(this.q.tex, Math.min(this.q.aniso, r.capabilities.getMaxAnisotropy()));
    this.M = buildMaterials(this.T);
    this.envElev = -9;
    this.envRT = null;
  }

  // ---------- небо ----------
  initSky(scene) {
    this.scene = scene;
    this.sky = new Sky();
    this.sky.scale.setScalar(1000);
    this.sky.frustumCulled = false;
    this.sky.userData.noAO = true;
    scene.add(this.sky);
    const u = this.sky.material.uniforms;
    u.turbidity.value = 2.5;
    u.rayleigh.value = 1.1;
    u.mieCoefficient.value = 0.0025;
    u.mieDirectionalG.value = 0.8;

    // звёзды
    const N = 1500, p = new Float32Array(N * 3);
    const rr = mulberry32(3);
    for (let i = 0; i < N; i++) {
      const a = rr() * Math.PI * 2, y = rr() * 0.95 + 0.05, rad = Math.sqrt(1 - y * y);
      p[i * 3] = Math.cos(a) * rad * 800; p[i * 3 + 1] = y * 800; p[i * 3 + 2] = Math.sin(a) * rad * 800;
    }
    const sg = new THREE.BufferGeometry();
    sg.setAttribute('position', new THREE.BufferAttribute(p, 3));
    this.stars = new THREE.Points(sg, new THREE.PointsMaterial({
      color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, depthWrite: false, fog: false,
    }));
    this.stars.frustumCulled = false;
    scene.add(this.stars);
    this.moon = new THREE.Mesh(new THREE.SphereGeometry(14, 16, 12), new THREE.MeshBasicMaterial({ color: 0xdfe6f5, fog: false }));
    scene.add(this.moon);

    // облака — мягкие спрайты
    this.clouds = new THREE.Group();
    this.cloudMat = new THREE.SpriteMaterial({ map: this.T.cloud, transparent: true, depthWrite: false, fog: false, opacity: 0.85 });
    const cr = mulberry32(9);
    for (let i = 0; i < 34; i++) {
      const c = new THREE.Group();
      const n = 4 + Math.floor(cr() * 5);
      for (let j = 0; j < n; j++) {
        const s = new THREE.Sprite(this.cloudMat);
        const sc = 45 + cr() * 50;
        s.scale.set(sc * 1.6, sc, 1);
        s.position.set((j - n / 2) * 28 + cr() * 20, cr() * 12, cr() * 30);
        c.add(s);
      }
      c.position.set((cr() * 2 - 1) * 900, 170 + cr() * 60, (cr() * 2 - 1) * 900);
      this.clouds.add(c);
    }
    scene.add(this.clouds);

    // блик солнца
    this.glare = new THREE.Sprite(new THREE.SpriteMaterial({
      map: this.T.glare, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, transparent: true,
    }));
    this.glare.scale.setScalar(260);
    scene.add(this.glare);

    // сцена для карты окружения
    if (this.q.env) {
      this.pmrem = new THREE.PMREMGenerator(this.game.renderer);
      this.envScene = new THREE.Scene();
      this.envSky = new Sky();
      this.envSky.scale.setScalar(100);
      this.envScene.add(this.envSky);
      this.envGround = new THREE.Mesh(new THREE.PlaneGeometry(400, 400).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x3a3a2a }));
      this.envGround.position.y = -2;
      this.envScene.add(this.envGround);
    }
    this.fogDay = new THREE.Color(0xb4cde4);
    this.fogSet = new THREE.Color(0xd9a67a);
    this.fogNight = new THREE.Color(0x0e1522);
    this.tmpC = new THREE.Color();
  }

  // t: 0..1 (0 — полночь, 0.5 — полдень). Возвращает параметры освещения.
  updateSky(t, camera, dt, cloud = 0) {
    const ang = (t - 0.25) * Math.PI * 2;
    const elev = Math.sin(ang);
    const sd = new THREE.Vector3(Math.cos(ang), elev, 0.35).normalize();
    const day = smoothstep(-0.12, 0.2, elev);
    const set = (1 - smoothstep(0.0, 0.35, Math.abs(elev))) * smoothstep(-0.25, 0.05, elev);
    const u = this.sky.material.uniforms;
    u.sunPosition.value.copy(sd);
    u.turbidity.value = lerp(lerp(2.5, 6, set), 16, cloud);
    u.rayleigh.value = lerp(lerp(1.1, 2.4, set), 0.6, cloud);
    this.sky.position.copy(camera.position);
    this.stars.position.copy(camera.position);
    this.stars.material.opacity = 1 - smoothstep(-0.2, 0.05, elev);
    this.stars.visible = this.stars.material.opacity > 0.01;
    this.moon.position.copy(camera.position).addScaledVector(sd, -700);
    this.moon.visible = elev < 0.15;
    this.glare.position.copy(camera.position).addScaledVector(sd, 600);
    this.glare.visible = elev > -0.08;
    this.glare.material.opacity = smoothstep(-0.08, 0.12, elev) * 0.9 * (1 - cloud);
    this.glare.material.color.setRGB(1, 1, 1).lerp(this.fogSet, set * 0.6);
    for (const c of this.clouds.children) {
      c.position.x += dt * 3;
      if (c.position.x > 900) c.position.x = -900;
    }
    this.clouds.position.set(camera.position.x * 0.9, 0, camera.position.z * 0.9);
    const cc = this.tmpC.setRGB(1, 1, 1).lerp(this.fogSet, set * 0.8).multiplyScalar((0.12 + day * 0.9) * (1 - cloud * 0.55));
    this.cloudMat.color.copy(cc);
    this.cloudMat.opacity = 0.85 + cloud * 0.15;
    const cs = 1 + cloud * 1.3;
    this.clouds.scale.set(cs, 1, cs);

    const fog = new THREE.Color().copy(this.fogNight).lerp(this.fogDay, day).lerp(this.fogSet, set * 0.6);
    fog.lerp(new THREE.Color(0x7d868f).multiplyScalar(0.15 + day * 0.85), cloud * 0.75);
    // карта окружения обновляется, когда солнце заметно сдвинулось
    if (this.q.env && (Math.abs(elev - this.envElev) > 0.035 || Math.abs(cloud - (this.envCloud || 0)) > 0.1)) {
      this.envElev = elev;
      this.envCloud = cloud;
      const eu = this.envSky.material.uniforms;
      for (const k of ['turbidity', 'rayleigh', 'mieCoefficient', 'mieDirectionalG']) eu[k].value = u[k].value;
      eu.sunPosition.value.copy(sd);
      this.envGround.material.color.setRGB(0.1, 0.09, 0.06).multiplyScalar(0.2 + day);
      const rt = this.pmrem.fromScene(this.envScene, 0, 0.1, 500);
      if (this.envRT) this.envRT.dispose();
      this.envRT = rt;
      this.scene.environment = rt.texture;
    }
    if (this.scene.environment) this.scene.environmentIntensity = 0.3 + 0.7 * day;
    return { elev, sd, day, set, fog };
  }

  // ---------- постобработка (только «Ультра») ----------
  initPost(w, h) {
    if (!this.q.ao && !this.q.bloom) return;
    const g = this.game, r = g.renderer;
    const pr = r.getPixelRatio();
    const rt = new THREE.WebGLRenderTarget(Math.floor(w * pr), Math.floor(h * pr), { type: THREE.HalfFloatType, samples: 4 });
    this.composer = new EffectComposer(r, rt);
    this.composer.addPass(new RenderPass(g.scene, g.camera));
    if (this.q.ao) {
      const ao = new GTAOPass(g.scene, g.camera, w, h);
      ao.updateGtaoMaterial({ radius: 0.9, distanceExponent: 1.6, thickness: 1.5, scale: 1.25, samples: 16, distanceFallOff: 1, screenSpaceRadius: false });
      ao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 5, rings: 2, samples: 16 });
      ao.blendIntensity = 0.9;
      // листва, трава, вода и спрайты не участвуют в затенении (иначе видны тёмные квадраты)
      ao.overrideVisibility = function () {
        const cache = this._visibilityCache;
        this.scene.traverse((o) => {
          cache.set(o, o.visible);
          const m = o.material;
          if (o.isPoints || o.isLine || o.isSprite || o.userData.noAO) { o.visible = false; return; }
          if (m && !Array.isArray(m) && (m.alphaTest > 0 || m.transparent)) o.visible = false;
        });
      };
      this.ao = ao;
      this.composer.addPass(ao);
    }
    this.vmPass = new RenderPass(g.vmScene, g.vmCamera);
    this.vmPass.clear = false;
    this.vmPass.clearDepth = true;
    this.composer.addPass(this.vmPass);
    if (this.q.bloom) {
      this.bloom = new UnrealBloomPass(new THREE.Vector2(w, h), 0.28, 0.25, 1.4);
      this.composer.addPass(this.bloom);
    }
    this.composer.addPass(new OutputPass());
  }

  resize(w, h) {
    if (this.composer) this.composer.setSize(w, h);
  }

  render(scene, camera, vmScene, vmCamera, drawVm) {
    const r = this.game.renderer;
    if (this.composer) {
      this.vmPass.enabled = drawVm;
      this.composer.render();
      return;
    }
    r.setRenderTarget(null);
    r.clear();
    r.render(scene, camera);
    if (drawVm) { r.clearDepth(); r.render(vmScene, vmCamera); }
  }
}

// ---------- Трава вокруг игрока ----------
export class Grass {
  constructor(world, scene, material, max, cell) {
    this.world = world;
    this.max = max;
    this.cell = cell;
    this.R = max > 4000 ? 40 : 32;
    const parts = [];
    for (let k = 0; k < 3; k++) {
      const g = new THREE.PlaneGeometry(1.1, 0.75);
      g.translate(0, 0.375, 0);
      g.rotateY((k / 3) * Math.PI);
      parts.push({ geo: g, shade: (x, y) => 0.75 + (y / 0.75) * 0.4 });
    }
    const geo = mergeUV(parts, () => [0, 1, 0]);
    this.im = new THREE.InstancedMesh(geo, material, max);
    this.im.count = 0;
    this.im.frustumCulled = false;
    this.im.receiveShadow = true;
    this.im.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    const c = new THREE.Color(1, 1, 1);
    for (let i = 0; i < max; i++) this.im.setColorAt(i, c);
    scene.add(this.im);
    this.center = null;
    this.dirty = true;
  }

  update(pos) {
    if (!this.dirty && this.center && Math.hypot(pos.x - this.center.x, pos.z - this.center.z) < 5) return;
    this.dirty = false;
    this.center = { x: pos.x, z: pos.z };
    const w = this.world, R = this.R, cell = this.cell;
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), p = new THREE.Vector3(), s = new THREE.Vector3();
    const col = new THREE.Color();
    let n = 0;
    const x0 = Math.floor((pos.x - R) / cell), x1 = Math.floor((pos.x + R) / cell);
    const z0 = Math.floor((pos.z - R) / cell), z1 = Math.floor((pos.z + R) / cell);
    for (let ix = x0; ix <= x1 && n < this.max; ix++) {
      for (let iz = z0; iz <= z1 && n < this.max; iz++) {
        let h = Math.imul(ix, 374761393) ^ Math.imul(iz, 668265263);
        h = Math.imul(h ^ (h >>> 13), 1274126177);
        const r1 = ((h >>> 0) & 1023) / 1024, r2 = ((h >>> 10) & 1023) / 1024, r3 = ((h >>> 20) & 1023) / 1024;
        const x = (ix + r1) * cell, z = (iz + r2) * cell;
        const d = Math.hypot(x - pos.x, z - pos.z);
        if (d > R) continue;
        const g = w.grassAt(x, z);
        if (g < 0.35 + r3 * 0.4) continue;
        const y = w.getHeight(x, z);
        if (y < 1.7) continue;
        const cs = w.colliders.query(x - 0.3, z - 0.3, x + 0.3, z + 0.3);
        if (cs.some((c) => c.minY < y + 0.8 && c.maxY > y - 0.5)) continue;
        const sc = (0.6 + r3 * 0.5) * smoothstep(R, R - 8, d);
        e.set(0, r1 * 6.283, 0);
        q.setFromEuler(e);
        p.set(x, y - 0.05, z);
        s.set(sc, sc * (0.8 + r2 * 0.5), sc);
        m.compose(p, q, s);
        this.im.setMatrixAt(n, m);
        const v = 0.8 + r2 * 0.35;
        col.setRGB(v * (0.95 + r3 * 0.15), v, v * 0.9);
        this.im.setColorAt(n, col);
        n++;
      }
    }
    this.im.count = n;
    this.im.instanceMatrix.needsUpdate = true;
    if (this.im.instanceColor) this.im.instanceColor.needsUpdate = true;
  }
}
