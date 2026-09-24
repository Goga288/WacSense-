// Предметы, рецепты, таблицы лута и инвентарь.
import { randi } from './util.js';

const FIST = { dmg: 6, range: 2.0, rate: 0.55, tree: 0.4, ore: 0.2, flesh: 0.5 };
export { FIST };

export const ITEMS = {
  // --- ресурсы ---
  wood: { name: 'Дерево', icon: '🪵', stack: 1000 },
  stones: { name: 'Камни', icon: '🪨', stack: 1000 },
  metal_ore: { name: 'Металлическая руда', icon: '🟤', stack: 1000, smelt: 'metal_frag' },
  sulfur_ore: { name: 'Серная руда', icon: '🟡', stack: 1000, smelt: 'sulfur' },
  metal_frag: { name: 'Фрагменты металла', icon: '🔩', stack: 1000 },
  sulfur: { name: 'Сера', icon: '🧂', stack: 1000 },
  charcoal: { name: 'Уголь', icon: '⚫', stack: 1000 },
  cloth: { name: 'Ткань', icon: '🧶', stack: 1000 },
  scrap: { name: 'Скрап', icon: '⚙️', stack: 1000 },
  pipe: { name: 'Металлическая труба', icon: '🔧', stack: 20 },
  gunpowder: { name: 'Порох', icon: '💥', stack: 1000 },
  // --- еда и медицина ---
  raw_meat: { name: 'Сырое мясо', icon: '🥩', stack: 20, eat: { food: 8, water: 0, hp: -5 }, cook: 'cooked_meat' },
  cooked_meat: { name: 'Жареное мясо', icon: '🍖', stack: 20, eat: { food: 40, water: 2, hp: 8 } },
  mushroom: { name: 'Гриб', icon: '🍄', stack: 20, eat: { food: 15, water: 8, hp: 3 } },
  bandage: { name: 'Бинт', icon: '🩹', stack: 5, heal: 15 },
  medkit: { name: 'Шприц', icon: '💉', stack: 3, heal: 50 },
  // --- инструменты и оружие ---
  rock: { name: 'Булыжник', icon: '✊', model: 'rock',
    melee: { dmg: 12, range: 2.3, rate: 0.75, tree: 1, ore: 1, flesh: 1 } },
  stone_hatchet: { name: 'Каменный топор', icon: '🪓', model: 'hatchet',
    melee: { dmg: 18, range: 2.4, rate: 0.8, tree: 3, ore: 0.5, flesh: 2 } },
  stone_pickaxe: { name: 'Каменная кирка', icon: '⛏️', model: 'pickaxe',
    melee: { dmg: 16, range: 2.4, rate: 0.9, tree: 0.6, ore: 3, flesh: 1 } },
  metal_hatchet: { name: 'Металлический топор', icon: '🪓', model: 'hatchet', metal: true,
    melee: { dmg: 26, range: 2.5, rate: 0.75, tree: 5, ore: 1, flesh: 3 } },
  metal_pickaxe: { name: 'Металлическая кирка', icon: '⛏️', model: 'pickaxe', metal: true,
    melee: { dmg: 22, range: 2.5, rate: 0.85, tree: 1, ore: 5, flesh: 1.5 } },
  spear: { name: 'Деревянное копьё', icon: '🔱', model: 'spear',
    melee: { dmg: 35, range: 3.1, rate: 0.95, tree: 0.4, ore: 0.3, flesh: 1.5 } },
  bow: { name: 'Охотничий лук', icon: '🏹', model: 'bow',
    ranged: { dmg: 45, ammo: 'arrow', rate: 1.0, speed: 55, spread: 0.004 } },
  revolver: { name: 'Револьвер', icon: '🔫', short: 'REV', model: 'revolver',
    gun: { dmg: 30, ammo: 'pistol_ammo', mag: 8, rate: 0.3, reload: 1.8, spread: 0.012, range: 140, recoil: 0.03 } },
  rifle: { name: 'Автомат (АК)', icon: '🔫', short: 'AK', model: 'ak',
    gun: { dmg: 26, ammo: 'rifle_ammo', mag: 30, rate: 0.12, reload: 2.6, spread: 0.022, range: 220, auto: true, recoil: 0.018, snd: 'rifle' } },
  bolt: { name: 'Болтовка со снайперским прицелом', icon: '🎯', short: 'BOLT', model: 'bolt',
    gun: { dmg: 85, ammo: 'rifle_ammo', mag: 4, rate: 1.5, reload: 3.4, spread: 0.035, adsSpread: 0.0004, range: 450, recoil: 0.07, scope: true, snd: 'sniper', cycle: true } },
  lmg: { name: 'Пулемёт', icon: '🔫', short: 'LMG', model: 'lmg',
    gun: { dmg: 22, ammo: 'rifle_ammo', mag: 100, rate: 0.095, reload: 4.8, spread: 0.03, range: 220, auto: true, recoil: 0.014, snd: 'rifle' } },
  shotgun: { name: 'Помповый дробовик', icon: '🔫', short: 'PUMP', model: 'shotgun',
    gun: { dmg: 14, pellets: 9, ammo: 'shells', mag: 6, rate: 0.95, reload: 3.2, spread: 0.075, range: 60, recoil: 0.07, snd: 'shotgun', cycle: true } },
  torch: { name: 'Факел', icon: '🔥', model: 'torch',
    melee: { dmg: 8, range: 2.2, rate: 0.8, tree: 0.3, ore: 0.2, flesh: 0.5 } },
  arrow: { name: 'Стрела', icon: '➶', stack: 64 },
  pistol_ammo: { name: 'Пистолетные патроны', icon: '🔸', stack: 128 },
  rifle_ammo: { name: 'Винтовочные патроны', icon: '🔶', stack: 128 },
  shells: { name: 'Дробовые патроны', icon: '🔴', stack: 64 },
  double_barrel: { name: 'Двустволка', icon: '🔫', short: 'DB', model: 'double_barrel',
    gun: { dmg: 15, pellets: 10, ammo: 'shells', mag: 2, rate: 0.28, reload: 3.0, spread: 0.09, range: 45, recoil: 0.08, snd: 'shotgun' } },
  rocket_launcher: { name: 'Ракетница', icon: '🚀', short: 'RL', model: 'launcher',
    launcher: { ammo: 'rocket', rate: 1.2, reload: 3.5, speed: 40 } },
  rocket: { name: 'Ракета', icon: '🧨', stack: 3 },
  explosive: { name: 'Взрывчатка', icon: '💣', stack: 100 },
  // --- броня ---
  wood_armor: { name: 'Деревянная броня', icon: '🛡️', short: 'WOOD', armor: { slot: 'chest', prot: 0.45 } },
  metal_chest: { name: 'Металлический нагрудник', icon: '🛡️', short: 'MET', armor: { slot: 'chest', prot: 0.72 } },
  bucket_helmet: { name: 'Шлем из ведра', icon: '🪣', armor: { slot: 'head', prot: 0.35 } },
  metal_helmet: { name: 'Металлический шлем', icon: '⛑️', armor: { slot: 'head', prot: 0.65 } },
  armored_pants: { name: 'Бронештаны', icon: '👖', armor: { slot: 'legs', prot: 0.45 } },
  scrap_armor: { name: 'Броня из металлолома', icon: '🛡️', short: 'SCRP', armor: { slot: 'chest', prot: 0.58 } },
  iron_mask: { name: 'Железная маска', icon: '🎭', armor: { slot: 'head', prot: 0.55 } },
  hazmat: { name: 'Защитный костюм', icon: '🥼', short: 'HAZ', armor: { slot: 'chest', prot: 0.3, full: true, rad: 1 } },
  hammer: { name: 'Киянка', icon: '🔨', model: 'hammer', special: 'hammer' },
  plan: { name: 'План постройки', icon: '📐', model: 'plan', special: 'plan' },
  // --- размещаемое ---
  campfire: { name: 'Костёр', icon: '🏕️', stack: 3, deploy: 'campfire' },
  furnace: { name: 'Печь', icon: '🏭', stack: 1, deploy: 'furnace' },
  storage_box: { name: 'Ящик для хранения', icon: '📦', stack: 3, deploy: 'box' },
  sleeping_bag: { name: 'Спальный мешок', icon: '🛏️', stack: 3, deploy: 'sleeping_bag' },
  door: { name: 'Деревянная дверь', icon: '🚪', stack: 3, deploy: 'door' },
};
for (const id in ITEMS) {
  ITEMS[id].id = id;
  if (!ITEMS[id].stack) ITEMS[id].stack = 1;
}

export const CATEGORIES = ['Инструменты', 'Оружие', 'Броня', 'Строительство', 'Предметы', 'Боеприпасы', 'Медицина'];
export const ARMOR_SLOTS = ['head', 'chest', 'legs'];
export const ARMOR_WEIGHT = { head: 0.25, chest: 0.5, legs: 0.25 };

export const RECIPES = [
  { out: 'stone_hatchet', n: 1, time: 3, cat: 'Инструменты', cost: { wood: 200, stones: 100 } },
  { out: 'stone_pickaxe', n: 1, time: 3, cat: 'Инструменты', cost: { wood: 200, stones: 100 } },
  { out: 'metal_hatchet', n: 1, time: 6, cat: 'Инструменты', cost: { wood: 100, metal_frag: 75, scrap: 10 } },
  { out: 'metal_pickaxe', n: 1, time: 6, cat: 'Инструменты', cost: { wood: 100, metal_frag: 75, scrap: 10 } },
  { out: 'hammer', n: 1, time: 2, cat: 'Инструменты', cost: { wood: 100 } },
  { out: 'plan', n: 1, time: 2, cat: 'Инструменты', cost: { wood: 20 } },
  { out: 'spear', n: 1, time: 3, cat: 'Оружие', cost: { wood: 300 } },
  { out: 'bow', n: 1, time: 5, cat: 'Оружие', cost: { wood: 200, cloth: 50 } },
  { out: 'revolver', n: 1, time: 10, cat: 'Оружие', cost: { metal_frag: 125, scrap: 25, pipe: 1 } },
  { out: 'shotgun', n: 1, time: 12, cat: 'Оружие', cost: { metal_frag: 200, scrap: 60, pipe: 2 } },
  { out: 'rifle', n: 1, time: 20, cat: 'Оружие', cost: { metal_frag: 400, scrap: 150, pipe: 3 } },
  { out: 'bolt', n: 1, time: 20, cat: 'Оружие', cost: { metal_frag: 350, scrap: 120, pipe: 3 } },
  { out: 'lmg', n: 1, time: 30, cat: 'Оружие', cost: { metal_frag: 650, scrap: 250, pipe: 5 } },
  { out: 'wood_armor', n: 1, time: 5, cat: 'Броня', cost: { wood: 250, cloth: 20 } },
  { out: 'bucket_helmet', n: 1, time: 4, cat: 'Броня', cost: { metal_frag: 30, cloth: 10 } },
  { out: 'armored_pants', n: 1, time: 6, cat: 'Броня', cost: { cloth: 40, metal_frag: 60 } },
  { out: 'metal_helmet', n: 1, time: 8, cat: 'Броня', cost: { metal_frag: 150, scrap: 30 } },
  { out: 'metal_chest', n: 1, time: 10, cat: 'Броня', cost: { metal_frag: 250, scrap: 50, cloth: 30 } },
  { out: 'scrap_armor', n: 1, time: 8, cat: 'Броня', cost: { metal_frag: 150, scrap: 20, cloth: 25 } },
  { out: 'iron_mask', n: 1, time: 6, cat: 'Броня', cost: { metal_frag: 100, cloth: 10 } },
  { out: 'hazmat', n: 1, time: 10, cat: 'Броня', cost: { cloth: 80, scrap: 40, metal_frag: 40 } },
  { out: 'double_barrel', n: 1, time: 8, cat: 'Оружие', cost: { metal_frag: 150, wood: 100, pipe: 2 } },
  { out: 'rocket_launcher', n: 1, time: 25, cat: 'Оружие', cost: { metal_frag: 500, scrap: 200, pipe: 4 } },
  { out: 'explosive', n: 1, time: 3, cat: 'Боеприпасы', cost: { gunpowder: 50, metal_frag: 10, sulfur: 10 } },
  { out: 'rocket', n: 1, time: 6, cat: 'Боеприпасы', cost: { explosive: 5, gunpowder: 40, pipe: 1 } },
  { out: 'torch', n: 1, time: 1, cat: 'Инструменты', cost: { wood: 20, cloth: 10 } },
  { out: 'arrow', n: 2, time: 1, cat: 'Боеприпасы', cost: { wood: 25, stones: 10 } },
  { out: 'gunpowder', n: 10, time: 2, cat: 'Боеприпасы', cost: { charcoal: 30, sulfur: 20 } },
  { out: 'pistol_ammo', n: 4, time: 2, cat: 'Боеприпасы', cost: { metal_frag: 10, gunpowder: 10 } },
  { out: 'rifle_ammo', n: 5, time: 3, cat: 'Боеприпасы', cost: { metal_frag: 10, gunpowder: 15 } },
  { out: 'shells', n: 4, time: 2, cat: 'Боеприпасы', cost: { metal_frag: 5, gunpowder: 10 } },
  { out: 'campfire', n: 1, time: 2, cat: 'Строительство', cost: { wood: 100 } },
  { out: 'furnace', n: 1, time: 5, cat: 'Строительство', cost: { stones: 200, wood: 100, cloth: 20 } },
  { out: 'storage_box', n: 1, time: 3, cat: 'Строительство', cost: { wood: 100 } },
  { out: 'door', n: 1, time: 3, cat: 'Строительство', cost: { wood: 300 } },
  { out: 'sleeping_bag', n: 1, time: 3, cat: 'Предметы', cost: { cloth: 30 } },
  { out: 'bandage', n: 1, time: 1, cat: 'Медицина', cost: { cloth: 4 } },
  { out: 'medkit', n: 1, time: 4, cat: 'Медицина', cost: { cloth: 15, metal_frag: 10 } },
];

// [шанс, предмет, мин, макс]
export const LOOT = {
  barrel: [
    [1, 'scrap', 2, 5], [0.5, 'metal_frag', 10, 25], [0.3, 'cloth', 5, 12],
    [0.15, 'pistol_ammo', 3, 6], [0.15, 'pipe', 1, 1], [0.2, 'bandage', 1, 1], [0.1, 'gunpowder', 5, 15],
  ],
  crate: [
    [0.15, 'shells', 4, 10], [0.08, 'bucket_helmet', 1, 1], [0.06, 'wood_armor', 1, 1],
    [0.08, 'hazmat', 1, 1], [0.05, 'double_barrel', 1, 1], [0.06, 'iron_mask', 1, 1],
    [0.9, 'scrap', 5, 10], [0.5, 'metal_frag', 25, 60], [0.3, 'pipe', 1, 2], [0.25, 'gunpowder', 10, 25],
    [0.3, 'pistol_ammo', 5, 12], [0.2, 'medkit', 1, 1], [0.25, 'arrow', 6, 12], [0.08, 'revolver', 1, 1],
    [0.1, 'metal_hatchet', 1, 1], [0.1, 'metal_pickaxe', 1, 1], [0.12, 'bow', 1, 1], [0.3, 'cloth', 10, 25],
  ],
  military: [
    [1, 'scrap', 15, 30], [0.7, 'metal_frag', 50, 120], [0.5, 'pipe', 1, 3], [0.5, 'gunpowder', 20, 50],
    [0.6, 'pistol_ammo', 10, 24], [0.4, 'medkit', 1, 2], [0.25, 'revolver', 1, 1],
    [0.4, 'rifle_ammo', 15, 40], [0.07, 'rifle', 1, 1], [0.05, 'bolt', 1, 1], [0.08, 'shotgun', 1, 1],
    [0.3, 'shells', 6, 16], [0.12, 'metal_helmet', 1, 1], [0.1, 'metal_chest', 1, 1], [0.15, 'armored_pants', 1, 1],
    [0.15, 'hazmat', 1, 1], [0.06, 'rocket_launcher', 1, 1], [0.12, 'rocket', 1, 2], [0.1, 'double_barrel', 1, 1],
    [0.2, 'metal_hatchet', 1, 1], [0.2, 'metal_pickaxe', 1, 1], [0.3, 'sulfur', 30, 80],
  ],
  airdrop: [
    [1, 'rifle_ammo', 40, 80], [0.5, 'rifle', 1, 1], [0.25, 'bolt', 1, 1], [0.2, 'lmg', 1, 1],
    [0.35, 'metal_chest', 1, 1], [0.35, 'metal_helmet', 1, 1], [0.8, 'medkit', 2, 3], [1, 'metal_frag', 150, 300],
    [0.2, 'rocket_launcher', 1, 1], [0.3, 'rocket', 1, 3], [0.3, 'hazmat', 1, 1], [0.3, 'explosive', 5, 15],
    [0.7, 'scrap', 40, 80], [0.5, 'gunpowder', 50, 100], [0.35, 'metal_hatchet', 1, 1],
    [0.35, 'metal_pickaxe', 1, 1], [0.4, 'revolver', 1, 1], [0.5, 'pistol_ammo', 20, 40],
  ],
  scientist: [
    [1, 'pistol_ammo', 4, 12], [0.6, 'scrap', 5, 15], [0.4, 'metal_frag', 20, 50], [0.5, 'rifle_ammo', 8, 20], [0.05, 'rifle', 1, 1],
    [0.35, 'medkit', 1, 1], [0.12, 'revolver', 1, 1], [0.3, 'bandage', 1, 2],
  ],
};

// Выход переработчика для предметов без рецепта.
export const RECYCLE_EXTRA = {
  pipe: { scrap: 5, metal_frag: 10 },
  rocket: { explosive: 2, pipe: 1 },
};

export function recycleYield(id) {
  if (RECYCLE_EXTRA[id]) return RECYCLE_EXTRA[id];
  const r = RECIPES.find((x) => x.out === id);
  if (!r) return null;
  const out = {};
  for (const k in r.cost) {
    const v = Math.floor((r.cost[k] * 0.5) / r.n);
    if (v > 0) out[k] = v;
  }
  if (ITEMS[id].gun || ITEMS[id].armor || ITEMS[id].launcher) out.scrap = (out.scrap || 0) + 5;
  return Object.keys(out).length ? out : null;
}

export function rollLoot(table) {
  const out = [];
  for (const [ch, id, a, b] of LOOT[table]) {
    if (Math.random() < ch) out.push({ id, n: randi(a, b) });
  }
  if (!out.length) out.push({ id: 'scrap', n: randi(2, 5) });
  return out;
}

export function makeStack(id, n) {
  const s = { id, n };
  if (ITEMS[id].gun) s.ammo = 0;
  return s;
}

export class Inventory {
  constructor(size) {
    this.slots = new Array(size).fill(null);
    this.onChange = null;
  }
  changed() {
    if (this.onChange) this.onChange();
  }
  // Порядок слотов: предметы для рук — сначала на пояс, ресурсы — сначала в рюкзак.
  order(id, from) {
    const it = ITEMS[id];
    const hand = it.melee || it.gun || it.ranged || it.eat || it.heal || it.deploy || it.special;
    const idx = [];
    for (let i = from; i < this.slots.length; i++) idx.push(i);
    if (this.slots.length === 30 && from === 0 && !hand) {
      return idx.filter((i) => i >= 6).concat(idx.filter((i) => i < 6));
    }
    return idx;
  }
  // Возвращает количество, которое не поместилось.
  add(id, n, from = 0) {
    const max = ITEMS[id].stack;
    const order = this.order(id, from);
    for (const i of order) {
      if (n <= 0) break;
      const s = this.slots[i];
      if (s && s.id === id && s.n < max) {
        const k = Math.min(max - s.n, n);
        s.n += k;
        n -= k;
      }
    }
    for (const i of order) {
      if (n <= 0) break;
      if (!this.slots[i]) {
        const k = Math.min(max, n);
        this.slots[i] = makeStack(id, k);
        n -= k;
      }
    }
    this.changed();
    return n;
  }
  // Положить готовый стек (с сохранением патронов и т.п.)
  addStack(stack, from = 0) {
    if (ITEMS[stack.id].stack === 1) {
      for (const i of this.order(stack.id, from)) {
        if (!this.slots[i]) { this.slots[i] = stack; this.changed(); return 0; }
      }
      return stack.n;
    }
    return this.add(stack.id, stack.n, from);
  }
  count(id) {
    let c = 0;
    for (const s of this.slots) if (s && s.id === id) c += s.n;
    return c;
  }
  remove(id, n) {
    for (let i = this.slots.length - 1; i >= 0 && n > 0; i--) {
      const s = this.slots[i];
      if (s && s.id === id) {
        const k = Math.min(s.n, n);
        s.n -= k;
        n -= k;
        if (s.n <= 0) this.slots[i] = null;
      }
    }
    this.changed();
    return n === 0;
  }
  has(cost, mult = 1) {
    for (const id in cost) if (this.count(id) < Math.ceil(cost[id] * mult)) return false;
    return true;
  }
  take(cost, mult = 1) {
    if (!this.has(cost, mult)) return false;
    for (const id in cost) this.remove(id, Math.ceil(cost[id] * mult));
    return true;
  }
  isEmpty() {
    return this.slots.every((s) => !s);
  }
  serialize() {
    return this.slots.map((s) => (s ? { ...s } : null));
  }
  load(arr) {
    this.slots.fill(null);
    if (!arr) return;
    for (let i = 0; i < Math.min(arr.length, this.slots.length); i++) {
      const s = arr[i];
      this.slots[i] = s && ITEMS[s.id] ? { ...s } : null;
    }
    this.changed();
  }
}

export function costText(cost, mult = 1) {
  return Object.entries(cost)
    .map(([id, n]) => `${ITEMS[id].icon} ${Math.ceil(n * mult)}`)
    .join('  ');
}
