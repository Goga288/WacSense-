// Интерфейс: HUD, инвентарь, крафт, контейнеры, карта.
import { ITEMS, RECIPES, CATEGORIES, costText, ARMOR_SLOTS } from './items.js';
import { Doll } from './doll.js';
import { WORLD, HALF } from './world.js';
import { PIECES, TIERS } from './building.js';

const $ = (id) => document.getElementById(id);

export class UI {
  constructor(game) {
    this.game = game;
    this.open = false;
    this.container = null;
    this.held = null;
    this.cat = CATEGORIES[0];
    this.recipe = null;
    this.hoverSlot = null;
    this.lastStats = '';
    this.toastT = 0;

    this.el = {
      hud: $('hud'), prompt: $('prompt'), toast: $('toast'), feed: $('feed'), hotbar: $('hotbar'),
      buildinfo: $('buildinfo'), ammo: $('ammo'), queue: $('queue'), hitmarker: $('hitmarker'),
      vignette: $('vignette'), inventory: $('inventory'), invGrid: $('invGrid'), invHot: $('invHot'),
      contPanel: $('contPanel'), contGrid: $('contGrid'), contTitle: $('contTitle'), contActions: $('contActions'),
      craftCats: $('craftCats'), craftList: $('craftList'), craftInfo: $('craftInfo'), craftQueue: $('craftQueue'),
      itemInfo: $('itemInfo'), cursor: $('cursorItem'), clock: $('clock'),
      map: $('mapScreen'), mapCanvas: $('mapCanvas'), mapMarkers: $('mapMarkers'),
      compassStrip: $('compassStrip'), compassMarks: $('compassMarks'), dmgDir: $('dmgDir'), lowhp: $('lowhp'),
      rad: $('rad'), equipGrid: $('equipGrid'), armorInfo: $('armorInfo'), armor: document.querySelector('#stats .armor'),
      hp: document.querySelector('#stats .hp'), food: document.querySelector('#stats .food'),
      water: document.querySelector('#stats .water'),
    };

    // шкала компаса (0..720°, чтобы было бесшовно)
    this.PXDEG = 3;
    const names = { 0: 'С', 45: 'СВ', 90: 'В', 135: 'ЮВ', 180: 'Ю', 225: 'ЮЗ', 270: 'З', 315: 'СЗ' };
    let html = '';
    for (let d = -180; d <= 540; d += 15) {
      const n = ((d % 360) + 360) % 360;
      const x = (d + 180) * this.PXDEG;
      if (names[n] !== undefined) html += `<span class="lb ${n % 90 === 0 ? 'main' : ''}" style="left:${x}px">${names[n]}</span>`;
      else html += `<span class="tk" style="left:${x}px"></span>`;
    }
    this.el.compassStrip.innerHTML = html;
    this.el.compassStrip.style.width = 720 * this.PXDEG + 'px';

    // HUD-хотбар
    this.hudSlots = [];
    for (let i = 0; i < 6; i++) {
      const s = this.makeSlot();
      s.dataset.key = i + 1;
      s.addEventListener('pointerdown', (e) => {
        e.stopPropagation();
        this.game.selectSlot(i);
      });
      this.el.hotbar.appendChild(s);
      this.hudSlots.push(s);
    }
    // сетки инвентаря
    this.invSlots = [];
    for (let i = 6; i < 30; i++) this.el.invGrid.appendChild(this.bindSlot(this.makeSlot(), 'inv', i));
    for (let i = 0; i < 6; i++) this.el.invHot.appendChild(this.bindSlot(this.makeSlot(), 'inv', i));
    this.invSlots = [...this.el.invHot.children, ...this.el.invGrid.children];
    this.invSlotEls = new Array(30);
    for (const s of this.invSlots) this.invSlotEls[+s.dataset.idx] = s;

    // слоты брони
    const labels = { head: 'Голова', chest: 'Тело', legs: 'Ноги' };
    const hints = { head: '⛑️', chest: '🛡️', legs: '👖' };
    this.eqEls = ARMOR_SLOTS.map((slot, i) => {
      const el = this.bindSlot(this.makeSlot(), 'eq', i);
      el.dataset.label = labels[slot];
      el.dataset.hint = hints[slot];
      this.el.equipGrid.appendChild(el);
      return el;
    });
    try { this.doll = new Doll($('dollCanvas'), game.gfx.M); } catch (e) { this.doll = null; }

    // категории крафта
    for (const c of CATEGORIES) {
      const b = document.createElement('button');
      b.textContent = c;
      b.onclick = () => { this.cat = c; this.renderCraft(); };
      this.el.craftCats.appendChild(b);
    }

    $('invClose').onclick = () => this.game.closeInventory();
    // выброс предмета кликом мимо панелей
    this.el.inventory.addEventListener('pointerdown', (e) => {
      if (e.target === this.el.inventory && this.held) {
        this.game.dropItems([this.held]);
        this.held = null;
        this.refresh();
      }
    });
    window.addEventListener('pointermove', (e) => {
      this.el.cursor.style.left = e.clientX + 'px';
      this.el.cursor.style.top = e.clientY + 'px';
    });
    this.el.inventory.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  makeSlot() {
    const s = document.createElement('div');
    s.className = 'slot';
    s.innerHTML = '<span class="ic"></span><span class="n"></span><span class="bar"></span><span class="lb"></span>';
    return s;
  }

  bindSlot(el, where, idx) {
    el.dataset.where = where;
    el.dataset.idx = idx;
    el.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.slotClick(where, idx, e.button === 2, e.shiftKey || this.quickMove);
    });
    el.addEventListener('pointerenter', () => { this.hoverSlot = { where, idx }; this.renderItemInfo(); });
    return el;
  }

  invOf(where) {
    if (where === 'eq') return this.game.equip;
    return where === 'inv' ? this.game.inv : this.container && this.container.inv;
  }

  // Можно ли положить предмет в слот брони.
  fits(where, idx, stack) {
    if (where !== 'eq' || !stack) return true;
    const a = ITEMS[stack.id].armor;
    return !!a && a.slot === ARMOR_SLOTS[idx];
  }

  slotClick(where, idx, right, shift) {
    const inv = this.invOf(where);
    if (!inv) return;
    const s = inv.slots[idx];
    if (!this.held) {
      if (!s) return;
      const ar = ITEMS[s.id].armor;
      if (shift && where !== 'eq' && ar) {
        // быстро надеть броню
        const ei = ARMOR_SLOTS.indexOf(ar.slot);
        const eq = this.game.equip;
        inv.slots[idx] = eq.slots[ei];
        eq.slots[ei] = s;
        this.game.sfx('equip');
        inv.changed(); eq.changed();
        this.refresh();
        return;
      }
      if (shift && where === 'eq') {
        inv.slots[idx] = null;
        const left = this.game.inv.addStack(s, 0);
        if (left > 0) inv.slots[idx] = s;
        inv.changed();
        this.refresh();
        return;
      }
      if (shift) {
        // быстрое перемещение
        let target = null, from = 0;
        if (where === 'inv' && this.container && this.container.inv.slots.length > 0) target = this.container.inv;
        else if (where !== 'inv') target = this.game.inv;
        else { target = this.game.inv; from = idx < 6 ? 6 : 0; }
        inv.slots[idx] = null;
        const left = target.addStack(s, from);
        if (left > 0) inv.slots[idx] = { ...s, n: left };
      } else if (right && s.n > 1) {
        const half = Math.ceil(s.n / 2);
        this.held = { ...s, n: half };
        s.n -= half;
      } else {
        this.held = s;
        inv.slots[idx] = null;
      }
    } else {
      if (!this.fits(where, idx, this.held)) {
        this.notify('Сюда можно надеть только подходящую броню');
        return;
      }
      if (where === 'eq') this.game.sfx('equip');
      const max = ITEMS[this.held.id].stack;
      if (!s) {
        if (right) {
          inv.slots[idx] = { ...this.held, n: 1 };
          this.held.n -= 1;
          if (this.held.n <= 0) this.held = null;
        } else {
          inv.slots[idx] = this.held;
          this.held = null;
        }
      } else if (s.id === this.held.id && max > 1) {
        const k = Math.min(max - s.n, right ? 1 : this.held.n);
        s.n += k;
        this.held.n -= k;
        if (this.held.n <= 0) this.held = null;
      } else {
        inv.slots[idx] = this.held;
        this.held = s;
      }
    }
    this.game.sfx('pickup', null, 0.4);
    inv.changed();
    this.refresh();
  }

  fillSlot(el, s, selected = false) {
    const ic = el.children[0], n = el.children[1], bar = el.children[2], lb = el.children[3];
    if (lb) lb.textContent = s && ITEMS[s.id].short ? ITEMS[s.id].short : '';
    if (s) {
      const it = ITEMS[s.id];
      ic.textContent = it.icon;
      n.textContent = s.n > 1 ? s.n : it.gun ? `${s.ammo}/${it.gun.mag}` : '';
      el.title = it.name;
      bar.style.display = 'none';
    } else {
      ic.textContent = '';
      n.textContent = '';
      el.title = '';
      bar.style.display = 'none';
    }
    el.classList.toggle('sel', selected);
  }

  refresh() {
    const inv = this.game.inv;
    for (let i = 0; i < 6; i++) this.fillSlot(this.hudSlots[i], inv.slots[i], i === this.game.slot);
    if (!this.open) return;
    for (let i = 0; i < 30; i++) this.fillSlot(this.invSlotEls[i], inv.slots[i], i === this.game.slot);
    const eq = this.game.equip.slots;
    this.eqEls.forEach((el, i) => {
      this.fillSlot(el, eq[i]);
      el.classList.toggle('empty', !eq[i]);
      if (!eq[i]) el.children[0].textContent = el.dataset.hint;
    });
    this.el.armorInfo.textContent = `Защита: ${Math.round(this.game.armorValue() * 100)}%`;
    if (this.doll) this.doll.setEquip(eq);
    if (this.container) {
      const cs = this.container.inv.slots;
      if (this.el.contGrid.children.length !== cs.length) {
        this.el.contGrid.innerHTML = '';
        for (let i = 0; i < cs.length; i++) this.el.contGrid.appendChild(this.bindSlot(this.makeSlot(), 'cont', i));
      }
      for (let i = 0; i < cs.length; i++) this.fillSlot(this.el.contGrid.children[i], cs[i]);
      const c = this.container;
      if (c.kind === 'recycler') {
        this.el.contActions.innerHTML = '';
        const b = document.createElement('button');
        b.textContent = c.on ? 'Выключить' : 'Включить';
        b.className = c.on ? 'on' : '';
        b.onclick = () => { c.on = !c.on; c.tick = 0; this.game.sfx('recycler'); this.refresh(); };
        const hint = document.createElement('div');
        hint.className = 'hint';
        hint.textContent = 'Слоты 1–6 — вещи на переработку (оружие, броня, инструменты, трубы). Слоты 7–12 — полученные ресурсы и скрап.';
        this.el.contActions.append(b, hint);
      } else if (c.kind === 'deploy' && (c.type === 'furnace' || c.type === 'campfire')) {
        this.el.contActions.innerHTML = '';
        const b = document.createElement('button');
        b.textContent = c.on ? 'Потушить' : 'Зажечь';
        b.className = c.on ? 'on' : '';
        b.onclick = () => { this.game.building.setOn(c, !c.on); this.refresh(); };
        const hint = document.createElement('div');
        hint.className = 'hint';
        hint.textContent = c.type === 'furnace'
          ? 'Топливо — дерево. Руда переплавляется в металл и серу.'
          : 'Топливо — дерево. Жарит сырое мясо.';
        this.el.contActions.append(b, hint);
      } else {
        this.el.contActions.innerHTML = '';
      }
    }
    if (this.held) {
      this.el.cursor.style.display = 'block';
      this.el.cursor.innerHTML = `<span>${ITEMS[this.held.id].icon}</span><b>${this.held.n > 1 ? this.held.n : ''}</b>`;
    } else {
      this.el.cursor.style.display = 'none';
    }
    this.renderCraft();
    this.renderItemInfo();
  }

  renderItemInfo() {
    const h = this.hoverSlot;
    const inv = h && this.invOf(h.where);
    const s = inv && inv.slots[h.idx];
    const el = this.el.itemInfo;
    if (!s) { el.innerHTML = '<i>Наведите на предмет. ЛКМ — взять, ПКМ — половина, Shift+ЛКМ — переложить. Клик мимо окна — выбросить.</i>'; return; }
    const it = ITEMS[s.id];
    let d = '';
    if (it.melee) d = `Урон ${it.melee.dmg} · Добыча дерева ×${it.melee.tree} · руды ×${it.melee.ore}`;
    else if (it.gun) d = `Урон ${it.gun.dmg}${it.gun.pellets ? '×' + it.gun.pellets : ''} · Магазин ${it.gun.mag} · R — перезарядка · ПКМ — ${it.gun.scope ? 'оптика' : 'прицел'}`;
    else if (it.ranged) d = `Урон ${it.ranged.dmg} · Нужны стрелы`;
    else if (it.eat) d = `Еда +${it.eat.food}${it.eat.hp < 0 ? ' · лучше пожарить на костре' : ''}`;
    else if (it.heal) d = `Лечение +${it.heal}`;
    else if (it.armor) d = `Броня: ${{ head: 'голова', chest: 'тело', legs: 'ноги' }[it.armor.slot]}, защита ${Math.round(it.armor.prot * 100)}% · Shift+клик — надеть`;
    else if (it.deploy) d = 'Возьмите в руки и нажмите ЛКМ, чтобы поставить';
    else if (it.special === 'plan') d = 'ЛКМ — строить, ПКМ — выбрать тип, R — повернуть';
    else if (it.special === 'hammer') d = 'ЛКМ — улучшить постройку, ПКМ — разобрать/подобрать';
    else if (it.smelt) d = 'Переплавьте в печи';
    el.innerHTML = `<b>${it.icon} ${it.name}</b> ×${s.n}<br><small>${d}</small>`;
  }

  renderCraft() {
    if (!this.open) return;
    const inv = this.game.inv;
    for (const b of this.el.craftCats.children) b.classList.toggle('sel', b.textContent === this.cat);
    const list = RECIPES.filter((r) => r.cat === this.cat);
    const key = this.cat + '|' + list.map((r) => inv.has(r.cost) ? 1 : 0).join('');
    if (this._craftKey !== key) {
      this._craftKey = key;
      this.el.craftList.innerHTML = '';
      for (const r of list) {
        const d = document.createElement('div');
        d.className = 'recipe' + (inv.has(r.cost) ? ' can' : '') + (this.recipe === r ? ' sel' : '');
        d.innerHTML = `<span class="ic">${ITEMS[r.out].icon}</span><span>${ITEMS[r.out].name}${r.n > 1 ? ' ×' + r.n : ''}</span>`;
        d.onclick = () => { this.recipe = r; this._craftKey = ''; this.renderCraft(); };
        this.el.craftList.appendChild(d);
      }
    }
    const r = this.recipe && this.recipe.cat === this.cat ? this.recipe : null;
    if (r) {
      const parts = Object.entries(r.cost).map(([id, n]) => {
        const have = inv.count(id);
        return `<span class="${have >= n ? 'ok' : 'no'}">${ITEMS[id].icon} ${ITEMS[id].name}: ${have}/${n}</span>`;
      }).join('<br>');
      const infoKey = r.out + parts;
      if (this._infoKey !== infoKey) {
        this._infoKey = infoKey;
        this.el.craftInfo.innerHTML = `<b>${ITEMS[r.out].icon} ${ITEMS[r.out].name}</b> <small>(${r.time} с)</small><div class="cost">${parts}</div>`;
        const b1 = document.createElement('button');
        b1.textContent = 'Создать';
        b1.disabled = !inv.has(r.cost);
        b1.onclick = () => this.game.craft(r, 1);
        const b5 = document.createElement('button');
        b5.textContent = '×5';
        b5.disabled = !inv.has(r.cost, 5);
        b5.onclick = () => this.game.craft(r, 5);
        this.el.craftInfo.append(b1, b5);
      }
    } else if (this._infoKey !== '') {
      this._infoKey = '';
      this.el.craftInfo.innerHTML = '<i>Выберите рецепт</i>';
    }
    this.renderQueue();
  }

  renderQueue() {
    const q = this.game.craftQueue;
    const html = q.map((e, i) => `<span class="q">${ITEMS[e.r.out].icon}${i === 0 ? ' ' + Math.ceil(e.t) + 'с' : ''}</span>`).join('');
    if (this._q !== html) {
      this._q = html;
      this.el.queue.innerHTML = html;
      this.el.craftQueue.innerHTML = q.length ? 'Очередь: ' + html : '';
    }
  }

  showInventory(container) {
    this.open = true;
    this.container = container || null;
    this.el.inventory.classList.remove('hidden');
    document.body.classList.add('invopen');
    this.el.contPanel.classList.toggle('hidden', !container);
    this.el.inventory.classList.toggle('withcont', !!container);
    if (container) {
      this.el.contTitle.textContent = container.name || 'Контейнер';
      this.el.contGrid.innerHTML = '';
    }
    this._craftKey = '';
    this._infoKey = null;
    this.refresh();
  }

  hideInventory() {
    this.open = false;
    if (this.held) {
      const left = this.game.inv.addStack(this.held);
      if (left > 0) this.game.dropItems([{ ...this.held, n: left }]);
      this.held = null;
    }
    this.container = null;
    this.el.inventory.classList.add('hidden');
    document.body.classList.remove('invopen');
    this.el.cursor.style.display = 'none';
    this.refresh();
  }

  // ---------- HUD ----------
  notify(text) {
    this.el.toast.textContent = text;
    this.el.toast.classList.add('show');
    this.toastT = 2.2;
  }

  feed(id, n) {
    const d = document.createElement('div');
    d.className = 'fi';
    d.innerHTML = `${ITEMS[id].icon} <b>+${n}</b> ${ITEMS[id].name}`;
    this.el.feed.appendChild(d);
    while (this.el.feed.children.length > 5) this.el.feed.firstChild.remove();
    setTimeout(() => d.remove(), 2600);
  }

  hitmarker() {
    const h = this.el.hitmarker;
    h.classList.remove('on');
    void h.offsetWidth;
    h.classList.add('on');
  }

  // Направление урона: угол в радианах относительно взгляда (0 — спереди).
  damageDir(rel) {
    const d = this.el.dmgDir;
    d.style.transform = `rotate(${rel}rad)`;
    d.classList.add('on');
    clearTimeout(this._dmgT);
    this._dmgT = setTimeout(() => d.classList.remove('on'), 60);
  }

  updateCompass(heading, marks) {
    const W = 420;
    const x = W / 2 - (heading + 180) * this.PXDEG;
    this.el.compassStrip.style.transform = `translateX(${x}px)`;
    let html = '';
    for (const m of marks) {
      let rel = m.bearing - heading;
      rel = ((rel + 540) % 360) - 180;
      if (Math.abs(rel) > 65) continue;
      html += `<span class="mk2" style="left:${W / 2 + rel * this.PXDEG}px" title="${m.name}">${m.icon}</span>`;
    }
    if (this._marks !== html) { this._marks = html; this.el.compassMarks.innerHTML = html; }
  }

  setRad(level, prot) {
    const k = level > 0.02 ? `${Math.round(level * 100)}|${prot}` : '';
    if (this._rad === k) return;
    this._rad = k;
    const el = this.el.rad;
    if (!k) { el.style.display = 'none'; return; }
    el.style.display = 'block';
    el.classList.toggle('safe', prot >= 1);
    el.innerHTML = `☢ Радиация ${Math.round(level * 100)}%${prot >= 1 ? ' · защищено костюмом' : ' · нужен защитный костюм!'}`;
  }

  hurt() {
    const v = this.el.vignette;
    v.classList.remove('on');
    void v.offsetWidth;
    v.classList.add('on');
  }

  setPrompt(t) {
    if (this._prompt !== t) {
      this._prompt = t;
      this.el.prompt.textContent = t || '';
      this.el.prompt.style.display = t ? 'block' : 'none';
    }
  }

  setBuildInfo(t) {
    if (this._bi !== t) {
      this._bi = t;
      this.el.buildinfo.innerHTML = t || '';
      this.el.buildinfo.style.display = t ? 'block' : 'none';
    }
  }

  setAmmo(t) {
    if (this._ammo !== t) {
      this._ammo = t;
      this.el.ammo.textContent = t || '';
      this.el.ammo.style.display = t ? 'block' : 'none';
    }
  }

  updateStats(p) {
    const k = `${Math.ceil(p.hp)}|${Math.ceil(p.food)}|${Math.ceil(p.water)}|${this.game.armorValue()}`;
    if (k === this.lastStats) return;
    this.lastStats = k;
    const set = (el, v, max) => {
      el.querySelector('.bar > div').style.width = Math.max(0, (v / max) * 100) + '%';
      el.querySelector('b').textContent = Math.ceil(v);
      el.classList.toggle('low', v < max * 0.2);
    };
    set(this.el.hp, p.hp, 100);
    set(this.el.food, p.food, 100);
    set(this.el.water, p.water, 100);
    const av = Math.round(this.game.armorValue() * 100);
    this.el.armor.querySelector('.bar > div').style.width = av + '%';
    this.el.armor.querySelector('b').textContent = av + '%';
    this.el.armor.style.display = av > 0 ? '' : 'none';
    this.el.lowhp.classList.toggle('on', p.hp < 25 && p.alive);
  }

  update(dt) {
    if (this.toastT > 0) {
      this.toastT -= dt;
      if (this.toastT <= 0) this.el.toast.classList.remove('show');
    }
    const g = this.game;
    const h = Math.floor(g.dayTime * 24), m = Math.floor((g.dayTime * 24 - h) * 60);
    const ct = `${h < 6 || h >= 20 ? '🌙' : '☀️'} ${String(h).padStart(2, '0')}:${String(Math.floor(m / 10) * 10).padStart(2, '0')}`;
    if (this._clock !== ct) { this._clock = ct; this.el.clock.textContent = ct; }
    if (this.open) {
      this.renderCraft();
      if (this.doll) this.doll.render(dt);
    } else this.renderQueue();
    if (!this.el.map.classList.contains('hidden')) this.renderMapMarkers();
  }

  planInfo(b) {
    const cost = TIERS[0].cost.wood * PIECES[b.pieceType].mult;
    return `<b>${PIECES[b.pieceType].name}</b> · 🪵 ${Math.ceil(cost)}<br><small>ПКМ — сменить тип · R — повернуть</small>`;
  }

  // ---------- Карта ----------
  toggleMap(force) {
    const show = force !== undefined ? force : this.el.map.classList.contains('hidden');
    if (show) {
      if (!this.mapReady) {
        const src = this.game.world.renderMap(512);
        const cv = this.el.mapCanvas;
        cv.width = cv.height = 512;
        cv.getContext('2d').drawImage(src, 0, 0);
        this.mapReady = true;
      }
      this.el.map.classList.remove('hidden');
      this.renderMapMarkers();
    } else {
      this.el.map.classList.add('hidden');
    }
    return show;
  }

  renderMapMarkers() {
    const g = this.game;
    const pos = (x, z) => `left:${((x + HALF) / WORLD) * 100}%;top:${((z + HALF) / WORLD) * 100}%`;
    let html = '';
    for (const m of g.world.monuments) html += `<div class="mk mon" style="${pos(m.x, m.z)}">⚠️<span>${m.name}</span></div>`;
    if (g.spawnBag) html += `<div class="mk" style="${pos(g.spawnBag.x, g.spawnBag.z)}">🛏️</div>`;
    if (g.events) for (const m of g.events.markers()) html += `<div class="mk mon" style="${pos(m.x, m.z)}">${m.icon}<span>${m.name}</span></div>`;
    const deg = (-g.player.yaw * 180) / Math.PI;
    html += `<div class="mk me" style="${pos(g.player.pos.x, g.player.pos.z)};transform:translate(-50%,-50%) rotate(${deg}deg)">▲</div>`;
    if (this._mk !== html) { this._mk = html; this.el.mapMarkers.innerHTML = html; }
  }
}
