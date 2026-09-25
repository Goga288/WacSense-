// Блогер-миллионер — детский кликер. Все персонажи вымышленные.
(function () {
  'use strict';

  const SAVE_KEY = 'blogger_clicker_v1';
  const $ = (id) => document.getElementById(id);

  // ---------- Персонажи (оригинальные, нарисованы кодом) ----------
  const CHARS = [
    { name: 'Тапыч', skin: '#f2c29b', hair: '#5a3a22', top: '#e63946', top2: '#b71c2c', cap: '#1d4ed8', style: 'cap' },
    { name: 'Лайкуша', skin: '#f6d0b1', hair: '#ff5fa2', top: '#8b5cf6', top2: '#6d28d9', cap: null, style: 'buns' },
    { name: 'Турбо-Бро', skin: '#c68a5e', hair: '#1f1f1f', top: '#22c55e', top2: '#15803d', cap: null, style: 'shades' },
  ];

  function charSVG(c, mood = 0) {
    const mouth = mood > 0
      ? '<path d="M82 128 Q100 150 118 128 Q100 138 82 128Z" fill="#7a1f1f"/>'
      : '<path d="M84 128 Q100 142 116 128" stroke="#5a1a1a" stroke-width="5" fill="none" stroke-linecap="round"/>';
    let hair = '';
    if (c.style === 'cap') {
      hair = `<path d="M58 88 Q100 40 142 88 Z" fill="${c.cap}"/><rect x="58" y="80" width="84" height="12" rx="6" fill="${c.cap}"/>
        <path d="M130 86 Q168 86 170 96 Q140 98 128 92Z" fill="${c.cap}"/><circle cx="100" cy="62" r="6" fill="#fff"/>`;
    } else if (c.style === 'buns') {
      hair = `<circle cx="62" cy="62" r="18" fill="${c.hair}"/><circle cx="138" cy="62" r="18" fill="${c.hair}"/>
        <path d="M60 96 Q64 58 100 56 Q136 58 140 96 Q124 74 100 74 Q76 74 60 96Z" fill="${c.hair}"/>
        <circle cx="136" cy="80" r="6" fill="#ffe066"/>`;
    } else {
      hair = `<path d="M60 92 Q62 52 100 50 Q140 52 140 92 Q130 66 100 70 Q72 66 60 92Z" fill="${c.hair}"/>`;
    }
    const eyes = c.style === 'shades'
      ? `<rect x="68" y="96" width="28" height="16" rx="6" fill="#111"/><rect x="104" y="96" width="28" height="16" rx="6" fill="#111"/>
         <rect x="94" y="100" width="12" height="4" fill="#111"/><rect x="72" y="99" width="8" height="4" rx="2" fill="#fff" opacity="0.6"/>`
      : `<ellipse cx="84" cy="104" rx="8" ry="10" fill="#fff"/><ellipse cx="116" cy="104" rx="8" ry="10" fill="#fff"/>
         <circle cx="86" cy="106" r="5" fill="#222"/><circle cx="118" cy="106" r="5" fill="#222"/>
         <circle cx="88" cy="103" r="1.8" fill="#fff"/><circle cx="120" cy="103" r="1.8" fill="#fff"/>`;
    return `<svg viewBox="0 0 200 220" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="100" cy="212" rx="60" ry="8" fill="rgba(0,0,0,0.25)"/>
      <path d="M42 214 Q40 158 100 150 Q160 158 158 214Z" fill="${c.top}"/>
      <path d="M84 152 L100 176 L116 152" fill="${c.top2}"/>
      <rect x="140" y="160" width="26" height="44" rx="6" fill="#222" transform="rotate(-12 153 182)"/>
      <rect x="144" y="165" width="18" height="30" rx="3" fill="#4fc3f7" transform="rotate(-12 153 182)"/>
      <circle cx="146" cy="196" r="11" fill="${c.skin}"/>
      <circle cx="100" cy="102" r="46" fill="${c.skin}"/>
      <circle cx="54" cy="106" r="9" fill="${c.skin}"/><circle cx="146" cy="106" r="9" fill="${c.skin}"/>
      ${hair}
      ${eyes}
      <ellipse cx="72" cy="122" rx="7" ry="4" fill="#ff8fa3" opacity="0.6"/><ellipse cx="128" cy="122" rx="7" ry="4" fill="#ff8fa3" opacity="0.6"/>
      ${mouth}
    </svg>`;
  }

  // ---------- Данные ----------
  const TAP_UPS = [
    { id: 'phone', icon: '📱', name: 'Новый телефон', desc: '+1 за тап', add: 1, cost: 15 },
    { id: 'mic', icon: '🎤', name: 'Микрофон', desc: '+4 за тап', add: 4, cost: 150 },
    { id: 'lamp', icon: '💡', name: 'Кольцевая лампа', desc: '+15 за тап', add: 15, cost: 1400 },
    { id: 'cam', icon: '📷', name: 'Камера 4K', desc: '+60 за тап', add: 60, cost: 12000 },
    { id: 'edit', icon: '🎬', name: 'Монтажёр', desc: '+250 за тап', add: 250, cost: 110000 },
    { id: 'drone', icon: '🚁', name: 'Дрон для съёмки', desc: '+1200 за тап', add: 1200, cost: 1100000 },
    { id: 'team', icon: '👨‍👩‍👧‍👦', name: 'Команда блогеров', desc: '+6000 за тап', add: 6000, cost: 12000000 },
  ];
  const IDLE_UPS = [
    { id: 'shorts', icon: '🎞️', name: 'Короткие ролики', desc: '+1 в секунду', add: 1, cost: 50 },
    { id: 'stream', icon: '🎮', name: 'Стримы', desc: '+6 в секунду', add: 6, cost: 500 },
    { id: 'ads', icon: '📢', name: 'Реклама в роликах', desc: '+30 в секунду', add: 30, cost: 4000 },
    { id: 'merch', icon: '👕', name: 'Свой мерч', desc: '+150 в секунду', add: 150, cost: 35000 },
    { id: 'studio', icon: '🏢', name: 'Своя студия', desc: '+800 в секунду', add: 800, cost: 300000 },
    { id: 'agency', icon: '🎙️', name: 'Продюсерский центр', desc: '+4000 в секунду', add: 4000, cost: 2500000 },
    { id: 'show', icon: '📺', name: 'Своё шоу на ТВ', desc: '+20 000 в секунду', add: 20000, cost: 20000000 },
    { id: 'brand', icon: '🥤', name: 'Свой бренд газировки', desc: '+100 000 в секунду', add: 100000, cost: 180000000 },
  ];
  const LUX = [
    { id: 'scooter', icon: '🛴', name: 'Самокат', cost: 5000 },
    { id: 'bike', icon: '🚲', name: 'Велосипед', cost: 25000 },
    { id: 'moped', icon: '🛵', name: 'Мопед', cost: 120000 },
    { id: 'car', icon: '🏎️', name: 'Спорткар', cost: 1000000 },
    { id: 'limo', icon: '🚘', name: 'Лимузин', cost: 5000000 },
    { id: 'house', icon: '🏰', name: 'Особняк', cost: 25000000 },
    { id: 'yacht', icon: '🛥️', name: 'Яхта', cost: 100000000 },
    { id: 'heli', icon: '🚁', name: 'Вертолёт', cost: 400000000 },
    { id: 'jet', icon: '✈️', name: 'Самолёт', cost: 1500000000 },
    { id: 'island', icon: '🏝️', name: 'Свой остров', cost: 10000000000 },
    { id: 'rocket', icon: '🚀', name: 'Ракета на Луну', cost: 100000000000 },
  ];
  const CUPS = [
    { subs: 1000, icon: '🥉', name: 'Бронзовый кубок' },
    { subs: 10000, icon: '🥈', name: 'Серебряный кубок' },
    { subs: 100000, icon: '🥇', name: 'Золотой кубок' },
    { subs: 1000000, icon: '💎', name: 'Бриллиантовый кубок' },
    { subs: 10000000, icon: '👑', name: 'Королевский кубок' },
    { subs: 100000000, icon: '🌌', name: 'Космический кубок' },
  ];
  const RANKS = [
    [0, 'Новичок'], [1000, 'Начинающий блогер'], [100000, 'Блогер'], [1000000, 'Миллионер'],
    [100000000, 'Мультимиллионер'], [1000000000, 'Миллиардер'], [1000000000000, 'Легенда'],
  ];
  const LUX_BONUS = 0.08, CUP_BONUS = 0.15;
  // Машины для режима «Шашки»: седан есть сразу, остальные — после покупки в «Роскоши».
  const RACE_CARS = [
    { id: 'sedan', icon: '🚗', name: 'Седан', need: null, desc: 'До 180 км/ч' },
    { id: 'sport', icon: '🏎️', name: 'Спорткар', need: 'car', desc: 'До 290 км/ч, бешеный разгон' },
    { id: 'limo', icon: '🚘', name: 'Лимузин', need: 'limo', desc: 'До 200 км/ч, длинный как автобус' },
  ];
  const PAINTS = [0xc0392b, 0x1f2a36, 0xf2f2f0, 0x1d5fbf, 0xf1c40f, 0x27ae60, 0x8e44ad, 0xff6fa8];
  const TIMES = [['day', '☀️ День'], ['sunset', '🌇 Закат'], ['night', '🌙 Ночь']];

  // ---------- Состояние ----------
  const fresh = () => ({ money: 0, total: 0, subs: 0, char: -1, ups: {}, lux: {}, cups: 0, taps: 0, last: Date.now(), boostUntil: 0, sound: true,
    race: { car: 'sedan', paint: 0, time: 'day', best: 0, runs: 0 } });
  let S = fresh();
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (raw) S = Object.assign(fresh(), JSON.parse(raw));
    if (!S.race) S.race = fresh().race;
  } catch (e) { /* ignore */ }

  const lvl = (id) => S.ups[id] || 0;
  const cost = (u, lv) => Math.ceil(u.cost * Math.pow(1.15, lv));
  const costN = (u, n) => { let c = 0; for (let i = 0; i < n; i++) c += cost(u, lvl(u.id) + i); return c; };
  const mult = () => (1 + Object.keys(S.lux).length * LUX_BONUS) * (1 + S.cups * CUP_BONUS) * (Date.now() < S.boostUntil ? 2 : 1) * (hypeUntil > Date.now() ? 7 : 1);
  const perTap = () => (1 + TAP_UPS.reduce((a, u) => a + u.add * lvl(u.id), 0)) * mult();
  const perSec = () => IDLE_UPS.reduce((a, u) => a + u.add * lvl(u.id), 0) * mult();

  function fmt(n) {
    n = Math.floor(n);
    const units = [[1e15, ' квдрлн'], [1e12, ' трлн'], [1e9, ' млрд'], [1e6, ' млн'], [1e3, ' тыс']];
    for (const [v, s] of units) if (n >= v) return (n / v).toFixed(n / v < 10 ? 2 : n / v < 100 ? 1 : 0).replace('.', ',') + s;
    return String(n);
  }

  // ---------- Звук ----------
  let actx = null, muted = false;
  function audio() {
    if (!actx) { try { actx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return null; } }
    if (actx.state === 'suspended') actx.resume();
    return actx;
  }
  function beep(freq, dur, type = 'sine', vol = 0.12, to) {
    if (!S.sound || muted) return;
    const a = audio();
    if (!a) return;
    const t = a.currentTime;
    const o = a.createOscillator(), g = a.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(a.destination);
    o.start(t);
    o.stop(t + dur);
  }
  const sndTap = () => beep(500 + Math.random() * 300, 0.08, 'triangle', 0.1, 900);
  const sndBuy = () => { beep(660, 0.1, 'sine', 0.15); setTimeout(() => beep(990, 0.15, 'sine', 0.15), 80); };
  const sndWin = () => [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => beep(f, 0.25, 'triangle', 0.15), i * 120));
  function setMuted(m) { muted = m; if (actx) { if (m) actx.suspend(); else actx.resume(); } }

  // ---------- Yandex SDK ----------
  let ysdk = null, yplayer = null;
  async function initSDK() {
    try {
      if (!window.YaGames) return;
      ysdk = await window.YaGames.init();
      try { yplayer = await ysdk.getPlayer({ scopes: false }); } catch (e) { yplayer = null; }
      if (yplayer) {
        try {
          const d = await yplayer.getData(['save']);
          if (d && d.save) {
            const cloud = JSON.parse(d.save);
            if ((cloud.total || 0) > S.total) S = Object.assign(fresh(), cloud);
          }
        } catch (e) { /* ignore */ }
      }
    } catch (e) { console.warn('SDK', e); }
  }
  function showRewarded(onReward) {
    if (!ysdk) { onReward(); return; }
    let got = false;
    ysdk.adv.showRewardedVideo({
      callbacks: {
        onOpen: () => setMuted(true),
        onRewarded: () => { got = true; },
        onClose: () => { setMuted(false); if (got) onReward(); },
        onError: () => setMuted(false),
      },
    });
  }
  function showFullscreen() {
    if (!ysdk) return;
    try {
      ysdk.adv.showFullscreenAdv({ callbacks: { onOpen: () => setMuted(true), onClose: () => setMuted(false), onError: () => setMuted(false) } });
    } catch (e) { /* ignore */ }
  }

  // ---------- Сохранение ----------
  let cloudT = 0;
  function save() {
    S.last = Date.now();
    const json = JSON.stringify(S);
    try { localStorage.setItem(SAVE_KEY, json); } catch (e) { /* ignore */ }
    if (yplayer && Date.now() - cloudT > 60000) {
      cloudT = Date.now();
      yplayer.setData({ save: json }).catch(() => {});
    }
  }

  // ---------- Интерфейс ----------
  const bloggerEl = $('blogger');
  function drawBlogger(mood = 0) {
    const c = CHARS[S.char >= 0 ? S.char : 0];
    bloggerEl.innerHTML = charSVG(c, mood);
  }

  function floater(x, y, text, cls = '') {
    const d = document.createElement('div');
    d.className = 'fl ' + cls;
    d.textContent = text;
    d.style.left = x + 'px';
    d.style.top = y + 'px';
    $('floaters').appendChild(d);
    setTimeout(() => d.remove(), 950);
  }

  function coins(x, y, n) {
    for (let i = 0; i < n; i++) {
      const d = document.createElement('div');
      d.className = 'fl coin';
      d.textContent = '🪙';
      d.style.left = x + 'px';
      d.style.top = y + 'px';
      const a = Math.random() * Math.PI * 2, r = 60 + Math.random() * 60;
      d.style.setProperty('--dx', Math.cos(a) * r + 'px');
      d.style.setProperty('--dy', Math.sin(a) * r - 40 + 'px');
      $('floaters').appendChild(d);
      setTimeout(() => d.remove(), 850);
    }
  }

  let moodT = null;
  function tap(e) {
    e.preventDefault();
    audio();
    const r = $('stage').getBoundingClientRect();
    const x = (e.clientX || r.left + r.width / 2) - r.left, y = (e.clientY || r.top + r.height / 2) - r.top;
    const gain = perTap();
    S.money += gain;
    S.total += gain;
    S.subs += Math.max(1, Math.round(gain / 10 + 1));
    S.taps++;
    floater(x, y - 20, '+' + fmt(gain));
    if (Math.random() < 0.35) coins(x, y, 2);
    sndTap();
    bloggerEl.classList.add('tap');
    setTimeout(() => bloggerEl.classList.remove('tap'), 70);
    drawBlogger(1);
    clearTimeout(moodT);
    moodT = setTimeout(() => drawBlogger(0), 250);
    $('tapHint').classList.add('hidden');
    checkCups();
    renderTop();
  }

  function renderTop() {
    $('money').textContent = fmt(S.money);
    $('perSec').textContent = fmt(perSec()) + ' / сек';
    $('perTap').textContent = '+' + fmt(perTap()) + ' за тап';
    $('subs').textContent = fmt(S.subs);
    let rank = RANKS[0][1], next = null;
    for (let i = 0; i < RANKS.length; i++) {
      if (S.total >= RANKS[i][0]) rank = RANKS[i][1];
      else { next = RANKS[i]; break; }
    }
    $('rank').textContent = rank;
    if (next) {
      const prev = RANKS[RANKS.findIndex((r) => r === next) - 1][0];
      const k = Math.min(1, (S.total - prev) / (next[0] - prev));
      $('goalBar').style.width = k * 100 + '%';
      $('goalText').textContent = `До звания «${next[1]}»: ${fmt(Math.max(0, next[0] - S.total))}`;
    } else {
      $('goalBar').style.width = '100%';
      $('goalText').textContent = 'Ты легенда блогинга!';
    }
    const boost = Math.max(S.boostUntil - Date.now(), 0), hype = Math.max(hypeUntil - Date.now(), 0);
    const bb = $('boostBadge');
    if (hype > 0) { bb.classList.remove('hidden'); bb.textContent = `🔥 Вирусное видео! ×7 · ${Math.ceil(hype / 1000)} с`; }
    else if (boost > 0) { bb.classList.remove('hidden'); bb.textContent = `⚡ Доход ×2 · ${Math.ceil(boost / 1000)} с`; }
    else bb.classList.add('hidden');
    $('btnAd').disabled = boost > 0;
  }

  let tab = 'tap', buyN = 1;
  function itemHTML(icon, name, desc, extra, btn, cls = '') {
    return `<div class="item ${cls}"><div class="ic">${icon}</div><div class="info"><div class="nm">${name}</div><div class="ds">${desc}</div>${extra}</div>${btn}</div>`;
  }

  function renderShop() {
    const L = $('list');
    let html = '';
    if (tab === 'tap' || tab === 'idle') {
      const list = tab === 'tap' ? TAP_UPS : IDLE_UPS;
      list.forEach((u, i) => {
        const prevOwned = i === 0 || lvl(list[i - 1].id) > 0;
        const c = costN(u, buyN);
        if (!prevOwned && lvl(u.id) === 0) {
          html += itemHTML('❓', '???', 'Купи предыдущее улучшение', '', `<button class="buy" disabled>🔒</button>`, 'locked');
          return;
        }
        html += itemHTML(u.icon, u.name, u.desc + (buyN > 1 ? ` (×${buyN})` : ''), `<div class="lv">Уровень ${lvl(u.id)}</div>`,
          `<button class="buy" data-buy="${u.id}" ${S.money < c ? 'disabled' : ''}>🪙 ${fmt(c)}</button>`);
      });
      $('shop').querySelector('.buyMode').style.display = '';
    } else if (tab === 'lux') {
      $('shop').querySelector('.buyMode').style.display = 'none';
      html += `<div class="ds" style="text-align:center;margin-bottom:8px">Каждая покупка даёт +${LUX_BONUS * 100}% ко всему доходу</div>`;
      for (const x of LUX) {
        if (S.lux[x.id]) html += itemHTML(x.icon, x.name, `+${LUX_BONUS * 100}% к доходу`, '', `<div class="ownedMark">✅ Твоё!</div>`, 'owned');
        else html += itemHTML(x.icon, x.name, `+${LUX_BONUS * 100}% к доходу`, '', `<button class="buy" data-lux="${x.id}" ${S.money < x.cost ? 'disabled' : ''}>🪙 ${fmt(x.cost)}</button>`);
      }
    } else if (tab === 'race') {
      $('shop').querySelector('.buyMode').style.display = 'none';
      const R = S.race;
      html += `<div class="race-head"><b>🚗 Шашки по городу</b><div class="ds">Лавируй в потоке на скорости! Проезжай впритирку — больше монет.<br>Рекорд: ${(R.best / 1000).toFixed(2).replace('.', ',')} км · Заездов: ${R.runs}</div></div>`;
      html += `<div class="opts">${TIMES.map(([id, n]) => `<button data-time="${id}" class="${R.time === id ? 'sel' : ''}">${n}</button>`).join('')}</div>`;
      html += `<div class="opts">${PAINTS.map((c, i) => `<button class="swatch ${R.paint === i ? 'sel' : ''}" data-paint="${i}" style="background:#${c.toString(16).padStart(6, '0')}"></button>`).join('')}</div>`;
      for (const c of RACE_CARS) {
        const open = !c.need || S.lux[c.need];
        const needName = c.need ? LUX.find((l) => l.id === c.need).name : '';
        html += itemHTML(open ? c.icon : '🔒', c.name, open ? c.desc : `Купи «${needName}» во вкладке «Роскошь»`, '',
          open ? `<button class="buy" data-race="${c.id}">▶ Поехать</button>` : `<button class="buy" disabled>🔒</button>`, open ? '' : 'locked');
      }
    } else if (tab === 'cups') {
      $('shop').querySelector('.buyMode').style.display = 'none';
      html += `<div class="ds" style="text-align:center;margin-bottom:8px">Каждый кубок даёт +${CUP_BONUS * 100}% ко всему доходу</div>`;
      CUPS.forEach((c, i) => {
        const got = i < S.cups;
        html += itemHTML(got ? c.icon : '🔒', c.name, `За ${fmt(c.subs)} подписчиков`,
          got ? '' : `<div class="lv">Осталось: ${fmt(Math.max(0, c.subs - S.subs))}</div>`,
          got ? `<div class="ownedMark">✅ Получен</div>` : `<div class="ownedMark" style="color:#bbb">${Math.floor(Math.min(1, S.subs / c.subs) * 100)}%</div>`, got ? 'owned' : '');
      });
    } else if (tab === 'me') {
      $('shop').querySelector('.buyMode').style.display = 'none';
      html += `<div class="item"><div class="ic">📊</div><div class="info"><div class="nm">Статистика</div>
        <div class="ds">Заработано всего: ${fmt(S.total)} · Тапов: ${fmt(S.taps)}<br>Множитель дохода: ×${mult().toFixed(2).replace('.', ',')}</div></div></div>`;
      html += `<div class="item"><div class="ic">😎</div><div class="info"><div class="nm">Сменить блогера</div><div class="ds">Выбери, кто будет вести канал</div></div>
        <button class="buy" data-act="chars">Выбрать</button></div>`;
      html += `<div class="item"><div class="ic">🔄</div><div class="info"><div class="nm">Начать заново</div><div class="ds">Весь прогресс будет сброшен</div></div>
        <button class="buy" data-act="reset">Сброс</button></div>`;
    }
    L.innerHTML = html;
  }

  function buyUp(id) {
    const u = TAP_UPS.concat(IDLE_UPS).find((x) => x.id === id);
    const c = costN(u, buyN);
    if (S.money < c) return;
    S.money -= c;
    S.ups[id] = lvl(id) + buyN;
    sndBuy();
    renderAll();
    save();
  }

  function buyLux(id) {
    const x = LUX.find((l) => l.id === id);
    if (S.lux[id] || S.money < x.cost) return;
    S.money -= x.cost;
    S.lux[id] = true;
    sndWin();
    confetti();
    modal(`<div class="big">${x.icon}</div><h2>${x.name} куплен!</h2><p>Теперь весь доход больше на ${LUX_BONUS * 100}%.</p>`, [['Круто!', null]]);
    renderAll();
    save();
  }

  function renderBg() {
    const owned = LUX.filter((x) => S.lux[x.id]);
    const spots = [[6, 12], [80, 10], [4, 62], [84, 60], [14, 36], [74, 34], [44, 6], [30, 70], [62, 72], [20, 86], [70, 86]];
    $('bgItems').innerHTML = owned.map((x, i) => `<span style="left:${spots[i % spots.length][0]}%;top:${spots[i % spots.length][1]}%">${x.icon}</span>`).join('');
  }

  function renderAll() {
    renderTop();
    renderShop();
    renderBg();
  }

  function checkCups() {
    while (S.cups < CUPS.length && S.subs >= CUPS[S.cups].subs) {
      const c = CUPS[S.cups];
      S.cups++;
      sndWin();
      confetti();
      modal(`<div class="big">${c.icon}</div><h2>${c.name}!</h2><p>У тебя ${fmt(c.subs)} подписчиков! Доход вырос на ${CUP_BONUS * 100}%.</p>`, [['Ура!', null]]);
      renderAll();
      save();
    }
  }

  // ---------- Окна ----------
  function modal(html, buttons) {
    $('modalBody').innerHTML = html;
    const B = $('modalBtns');
    B.innerHTML = '';
    for (const [text, fn, cls] of buttons) {
      const b = document.createElement('button');
      b.textContent = text;
      if (cls) b.className = cls;
      b.onclick = () => { $('modal').classList.add('hidden'); if (fn) fn(); };
      B.appendChild(b);
    }
    $('modal').classList.remove('hidden');
  }

  function chooseChar(first) {
    const html = `<h2>${first ? 'Выбери своего блогера!' : 'Сменить блогера'}</h2><p>Он будет снимать ролики и зарабатывать миллионы 🤑</p>
      <div class="chars">${CHARS.map((c, i) => `<button data-char="${i}" class="${S.char === i ? 'sel' : ''}">${charSVG(c, 1)}<b>${c.name}</b></button>`).join('')}</div>`;
    modal(html, first ? [] : [['Закрыть', null, 'alt']]);
    for (const b of document.querySelectorAll('.chars button')) {
      b.onclick = () => {
        audio();
        S.char = +b.dataset.char;
        $('modal').classList.add('hidden');
        drawBlogger();
        sndBuy();
        save();
      };
    }
  }

  // ---------- Конфетти ----------
  const cv = $('confetti'), cx = cv.getContext('2d');
  let parts = [];
  function confetti() {
    cv.width = innerWidth; cv.height = innerHeight;
    const cols = ['#ffd23f', '#ff5fa2', '#4fc3f7', '#7dffa0', '#ffffff', '#ff8a3d'];
    for (let i = 0; i < 140; i++) {
      parts.push({ x: innerWidth / 2, y: innerHeight * 0.35, vx: (Math.random() - 0.5) * 14, vy: -Math.random() * 12 - 4,
        r: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.4, c: cols[i % cols.length], life: 2.5 });
    }
  }
  function drawConfetti(dt) {
    if (!parts.length) return;
    cx.clearRect(0, 0, cv.width, cv.height);
    for (const p of parts) {
      p.vy += 18 * dt; p.x += p.vx * 60 * dt * 0.5; p.y += p.vy * 60 * dt * 0.5; p.r += p.vr; p.life -= dt;
      cx.save(); cx.translate(p.x, p.y); cx.rotate(p.r); cx.fillStyle = p.c; cx.fillRect(-5, -3, 10, 6); cx.restore();
    }
    parts = parts.filter((p) => p.life > 0 && p.y < cv.height + 20);
    if (!parts.length) cx.clearRect(0, 0, cv.width, cv.height);
  }

  // ---------- Золотая монета «Хайп» ----------
  let hypeUntil = 0, hypeT = 25 + Math.random() * 30, hypeFly = null;
  function spawnHype() {
    const el = $('hype');
    el.classList.remove('hidden');
    const fromLeft = Math.random() < 0.5;
    hypeFly = { x: fromLeft ? -60 : innerWidth + 60, y: innerHeight * (0.2 + Math.random() * 0.35), vx: (fromLeft ? 1 : -1) * (90 + Math.random() * 60), t: 0 };
  }
  $('hype').addEventListener('pointerdown', (e) => {
    e.preventDefault();
    $('hype').classList.add('hidden');
    hypeFly = null;
    hypeUntil = Date.now() + 15000;
    sndWin();
    confetti();
    renderTop();
  });

  // ---------- Цикл ----------
  let last = performance.now(), saveT = 0, shopT = 0;
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    const ps = perSec();
    if (ps > 0) {
      S.money += ps * dt;
      S.total += ps * dt;
      S.subs += (ps / 20) * dt;
    }
    hypeT -= dt;
    if (hypeT <= 0 && !hypeFly) { hypeT = 45 + Math.random() * 45; spawnHype(); }
    if (hypeFly) {
      hypeFly.t += dt;
      hypeFly.x += hypeFly.vx * dt;
      const el = $('hype');
      el.style.left = hypeFly.x + 'px';
      el.style.top = hypeFly.y + Math.sin(hypeFly.t * 3) * 30 + 'px';
      if (hypeFly.x < -100 || hypeFly.x > innerWidth + 100) { el.classList.add('hidden'); hypeFly = null; }
    }
    drawConfetti(dt);
    shopT -= dt;
    if (shopT <= 0) { shopT = 0.25; renderTop(); renderShop(); checkCups(); }
    saveT += dt;
    if (saveT > 5) { saveT = 0; save(); }
  }

  // ---------- Запуск ----------
  function bind() {
    bloggerEl.addEventListener('pointerdown', tap);
    $('list').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b || b.disabled) return;
      if (b.dataset.buy) buyUp(b.dataset.buy);
      else if (b.dataset.lux) buyLux(b.dataset.lux);
      else if (b.dataset.act === 'chars') chooseChar(false);
      else if (b.dataset.time) { S.race.time = b.dataset.time; renderShop(); save(); }
      else if (b.dataset.paint) { S.race.paint = +b.dataset.paint; renderShop(); save(); }
      else if (b.dataset.race) startRace(b.dataset.race);
      else if (b.dataset.act === 'reset') {
        modal('<h2>Начать заново?</h2><p>Все деньги, покупки и кубки пропадут.</p>', [
          ['Да, сбросить', () => { const snd = S.sound; S = fresh(); S.sound = snd; save(); renderAll(); chooseChar(true); }],
          ['Отмена', null, 'alt'],
        ]);
      }
    });
    for (const b of document.querySelectorAll('#tabs button')) {
      b.onclick = () => {
        tab = b.dataset.tab;
        for (const x of document.querySelectorAll('#tabs button')) x.classList.toggle('sel', x === b);
        renderShop();
      };
    }
    $('btnX1').onclick = () => { buyN = 1; $('btnX1').classList.add('sel'); $('btnX10').classList.remove('sel'); renderShop(); };
    $('btnX10').onclick = () => { buyN = 10; $('btnX10').classList.add('sel'); $('btnX1').classList.remove('sel'); renderShop(); };
    $('btnAd').onclick = () => showRewarded(() => {
      S.boostUntil = Date.now() + 120000;
      sndWin();
      renderTop();
      save();
    });
    $('btnSound').onclick = () => {
      S.sound = !S.sound;
      $('btnSound').textContent = S.sound ? '🔊' : '🔇';
      save();
    };
    $('btnSound').textContent = S.sound ? '🔊' : '🔇';
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) { setMuted(true); save(); if (ysdk) try { ysdk.features.GameplayAPI.stop(); } catch (e) { /* */ } }
      else { setMuted(false); if (ysdk) try { ysdk.features.GameplayAPI.start(); } catch (e) { /* */ } }
    });
    window.addEventListener('pagehide', save);
    document.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  // ---------- Режим «Шашки» (3D-гонка подгружается по требованию) ----------
  function loadRacer() {
    return new Promise((res, rej) => {
      if (window.Racer) { res(); return; }
      const sc = document.createElement('script');
      sc.src = 'racer.js';
      sc.onload = () => res();
      sc.onerror = () => rej(new Error('racer.js не найден'));
      document.body.appendChild(sc);
    });
  }

  function startRace(car) {
    const btn = document.querySelector(`[data-race="${car}"]`);
    if (btn) { btn.disabled = true; btn.textContent = '⏳ Загрузка…'; }
    loadRacer().then(() => {
      S.race.car = car;
      const scale = Math.max(1, perTap() * 0.3 + perSec() * 0.05);
      window.Racer.startRace({
        car, color: PAINTS[S.race.paint], time: S.race.time, sound: S.sound,
        mobile: matchMedia('(pointer: coarse)').matches, coinScale: scale,
        onReward: (coins) => { S.money += coins; S.total += coins; save(); },
        rewarded: (cb) => showRewarded(cb),
        onClose: (r) => {
          S.race.runs++;
          if (r && r.dist > S.race.best) S.race.best = r.dist;
          save();
          renderAll();
          showFullscreen();
        },
      });
    }).catch((e) => {
      modal(`<h2>Не получилось загрузить гонку</h2><p>${e.message}</p>`, [['Ок', null]]);
      renderShop();
    });
  }

  function offlineEarnings() {
    const away = Math.min(2 * 3600, (Date.now() - (S.last || Date.now())) / 1000);
    const base = IDLE_UPS.reduce((a, u) => a + u.add * lvl(u.id), 0) * (1 + Object.keys(S.lux).length * LUX_BONUS) * (1 + S.cups * CUP_BONUS);
    const earned = Math.floor(base * away * 0.5);
    if (away < 60 || earned <= 0) return;
    const give = (k) => { S.money += earned * k; S.total += earned * k; sndBuy(); renderAll(); save(); };
    modal(`<div class="big">💤</div><h2>С возвращением!</h2><p>Пока тебя не было, канал заработал</p><h2>🪙 ${fmt(earned)}</h2>`, [
      ['📺 Забрать ×2 за рекламу', () => showRewarded(() => give(2)), 'ad'],
      ['Забрать', () => give(1)],
    ]);
  }

  async function start() {
    await initSDK();
    bind();
    drawBlogger();
    renderAll();
    requestAnimationFrame(frame);
    try { ysdk && ysdk.features.LoadingAPI.ready(); } catch (e) { /* */ }
    try { ysdk && ysdk.features.GameplayAPI.start(); } catch (e) { /* */ }
    if (S.char < 0) chooseChar(true);
    else { offlineEarnings(); showFullscreen(); }
    if (S.taps > 0) $('tapHint').classList.add('hidden');
  }
  window.clicker = { get state() { return S; }, perTap, perSec, fmt };
  start();
})();
