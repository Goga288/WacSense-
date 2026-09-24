// Процедурные звуки на WebAudio — без внешних файлов.
let ctx = null;
let master = null;
let noiseBuf = null;
let muted = false;
let volume = 0.5;

export function initAudio() {
  if (ctx) {
    if (ctx.state === 'suspended') ctx.resume();
    return;
  }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = muted ? 0 : volume;
  master.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
}

export function setMuted(m) {
  muted = m;
  if (master) master.gain.value = m ? 0 : volume;
  if (ctx) {
    if (m && ctx.state === 'running') ctx.suspend();
    else if (!m && ctx.state === 'suspended') ctx.resume();
  }
}

function noise(dur, freq, type, vol, q = 1) {
  const t = ctx.currentTime;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.frequency.value = freq;
  f.Q.value = q;
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t, Math.random() * 0.5);
  src.stop(t + dur);
}

function tone(freq, dur, type, vol, toFreq) {
  const t = ctx.currentTime;
  const o = ctx.createOscillator();
  o.type = type;
  o.frequency.setValueAtTime(freq, t);
  if (toFreq) o.frequency.exponentialRampToValueAtTime(toFreq, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  o.connect(g).connect(master);
  o.start(t);
  o.stop(t + dur);
}

export function sfx(name, vol = 1) {
  if (!ctx || muted || vol <= 0.01) return;
  switch (name) {
    case 'wood':
      noise(0.12, 700, 'lowpass', 0.7 * vol);
      tone(140, 0.12, 'sine', 0.5 * vol, 70);
      break;
    case 'stone':
      noise(0.08, 2500, 'bandpass', 0.8 * vol, 2);
      tone(900, 0.05, 'square', 0.08 * vol, 500);
      break;
    case 'metal':
      tone(1400, 0.2, 'triangle', 0.15 * vol, 1200);
      noise(0.06, 4000, 'highpass', 0.4 * vol);
      break;
    case 'flesh':
      noise(0.15, 400, 'lowpass', 0.8 * vol);
      break;
    case 'swing':
      noise(0.15, 1200, 'bandpass', 0.25 * vol, 0.8);
      break;
    case 'shot':
      noise(0.35, 1800, 'lowpass', 1.2 * vol);
      tone(120, 0.2, 'sawtooth', 0.4 * vol, 40);
      break;
    case 'npcshot':
      noise(0.3, 1500, 'lowpass', 0.9 * vol);
      tone(100, 0.15, 'sawtooth', 0.25 * vol, 40);
      break;
    case 'bow':
      tone(220, 0.15, 'triangle', 0.3 * vol, 90);
      noise(0.1, 3000, 'highpass', 0.2 * vol);
      break;
    case 'empty':
      tone(1800, 0.03, 'square', 0.1 * vol);
      break;
    case 'reload':
      tone(600, 0.05, 'square', 0.1 * vol);
      setTimeout(() => ctx && tone(800, 0.05, 'square', 0.1 * vol), 400);
      break;
    case 'hurt':
      tone(220, 0.25, 'sawtooth', 0.25 * vol, 110);
      break;
    case 'pickup':
      tone(600, 0.08, 'sine', 0.25 * vol, 900);
      break;
    case 'craft':
      tone(500, 0.1, 'sine', 0.2 * vol, 1000);
      setTimeout(() => ctx && tone(800, 0.12, 'sine', 0.2 * vol, 1200), 90);
      break;
    case 'build':
      noise(0.2, 500, 'lowpass', 0.9 * vol);
      tone(90, 0.2, 'sine', 0.5 * vol, 60);
      break;
    case 'eat':
      noise(0.1, 900, 'bandpass', 0.4 * vol, 3);
      setTimeout(() => ctx && noise(0.1, 900, 'bandpass', 0.4 * vol, 3), 150);
      break;
    case 'drink':
      tone(300, 0.15, 'sine', 0.3 * vol, 500);
      break;
    case 'door':
      tone(200, 0.3, 'triangle', 0.2 * vol, 120);
      noise(0.2, 600, 'lowpass', 0.3 * vol);
      break;
    case 'growl':
      tone(90, 0.5, 'sawtooth', 0.25 * vol, 60);
      break;
    case 'hit':
      tone(1000, 0.05, 'square', 0.08 * vol, 1300);
      break;
    case 'step':
      noise(0.06, 300, 'lowpass', 0.15 * vol);
      break;
    case 'rifle':
      noise(0.28, 2600, 'lowpass', 1.1 * vol);
      noise(0.08, 5000, 'highpass', 0.5 * vol);
      tone(150, 0.12, 'sawtooth', 0.35 * vol, 50);
      break;
    case 'sniper':
      noise(0.5, 2000, 'lowpass', 1.4 * vol);
      noise(0.12, 6000, 'highpass', 0.6 * vol);
      tone(90, 0.3, 'sawtooth', 0.45 * vol, 35);
      setTimeout(() => ctx && (tone(700, 0.05, 'square', 0.08 * vol, 500), noise(0.08, 3000, 'bandpass', 0.2 * vol, 3)), 450);
      break;
    case 'shotgun':
      noise(0.45, 1200, 'lowpass', 1.5 * vol);
      tone(80, 0.25, 'sawtooth', 0.5 * vol, 35);
      setTimeout(() => ctx && (noise(0.07, 1500, 'bandpass', 0.3 * vol, 2), setTimeout(() => ctx && noise(0.07, 1100, 'bandpass', 0.3 * vol, 2), 120)), 380);
      break;
    case 'equip':
      noise(0.1, 800, 'bandpass', 0.35 * vol, 2);
      tone(300, 0.08, 'triangle', 0.1 * vol, 200);
      break;
    case 'thunder':
      noise(3.2, 160, 'lowpass', 1.6 * vol);
      noise(1.2, 600, 'lowpass', 0.8 * vol);
      tone(45, 2.5, 'sine', 0.6 * vol, 28);
      break;
    case 'heart':
      tone(60, 0.12, 'sine', 0.6 * vol, 40);
      setTimeout(() => ctx && tone(55, 0.12, 'sine', 0.45 * vol, 38), 180);
      break;
    case 'crack':
      noise(0.5, 1800, 'highpass', 0.6 * vol);
      tone(180, 0.6, 'sawtooth', 0.15 * vol, 60);
      break;
    case 'thud':
      noise(0.8, 250, 'lowpass', 1.2 * vol);
      tone(70, 0.6, 'sine', 0.8 * vol, 35);
      break;
  }
}

// ---------- Фоновые звуки: ветер, прибой, птицы, сверчки ----------
let amb = null;

function loopNoise(type, freq, q) {
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  src.loop = true;
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.frequency.value = freq;
  f.Q.value = q;
  const g = ctx.createGain();
  g.gain.value = 0;
  src.connect(f).connect(g).connect(master);
  src.start();
  return { f, g };
}

function chirp() {
  const t0 = ctx.currentTime;
  const n = 2 + Math.floor(Math.random() * 4);
  const base = 2200 + Math.random() * 1500;
  const pan = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
  const out = ctx.createGain();
  out.gain.value = 0.025 + Math.random() * 0.02;
  if (pan) { pan.pan.value = Math.random() * 2 - 1; out.connect(pan).connect(master); } else out.connect(master);
  for (let i = 0; i < n; i++) {
    const t = t0 + i * (0.09 + Math.random() * 0.05);
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(base, t);
    o.frequency.exponentialRampToValueAtTime(base * (1.3 + Math.random() * 0.4), t + 0.06);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(1, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.07);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + 0.08);
  }
}

function cricket() {
  const t0 = ctx.currentTime;
  const out = ctx.createGain();
  out.gain.value = 0.012;
  out.connect(master);
  for (let i = 0; i < 3; i++) {
    const t = t0 + i * 0.06;
    const o = ctx.createOscillator();
    o.type = 'triangle';
    o.frequency.value = 4300 + Math.random() * 200;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(1, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.04);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + 0.05);
  }
}

// p: { day 0..1, shore 0..1, height }
export function updateAmbient(dt, p) {
  if (!ctx || muted || ctx.state !== 'running') return;
  if (!amb) {
    amb = {
      wind: loopNoise('bandpass', 450, 0.5), sea: loopNoise('lowpass', 420, 0.6), rain: loopNoise('highpass', 1400, 0.4),
      rainLow: loopNoise('lowpass', 700, 0.5), t: 0, bird: 2, cr: 0,
    };
    // гул двигателей самолёта
    const o1 = ctx.createOscillator(), o2 = ctx.createOscillator();
    o1.type = 'sawtooth'; o2.type = 'sawtooth';
    o1.frequency.value = 62; o2.frequency.value = 65.5;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass'; lp.frequency.value = 380;
    const eg = ctx.createGain();
    eg.gain.value = 0;
    o1.connect(lp); o2.connect(lp); lp.connect(eg).connect(master);
    o1.start(); o2.start();
    amb.engine = eg;
  }
  const rain = p.rain || 0;
  amb.rain.g.gain.setTargetAtTime(rain * 0.16, ctx.currentTime, 0.5);
  amb.rainLow.g.gain.setTargetAtTime(rain * 0.12, ctx.currentTime, 0.5);
  amb.engine.gain.setTargetAtTime(p.engine || 0, ctx.currentTime, 0.3);
  amb.t += dt;
  const now = ctx.currentTime;
  const hk = Math.min(1, Math.max(0, p.height / 35));
  const gust = 0.5 + 0.3 * Math.sin(amb.t * 0.27) + 0.2 * Math.sin(amb.t * 0.71);
  amb.wind.g.gain.setTargetAtTime((0.04 + hk * 0.07) * gust, now, 0.6);
  amb.wind.f.frequency.setTargetAtTime(350 + gust * 250, now, 0.6);
  const swell = 0.6 + 0.4 * Math.sin(amb.t * 0.55);
  amb.sea.g.gain.setTargetAtTime(p.shore * 0.22 * swell, now, 0.4);
  amb.bird -= dt;
  if (amb.bird <= 0) {
    amb.bird = 1.2 + Math.random() * 4.5;
    if (p.day > 0.5 && p.shore < 0.6 && rain < 0.2) chirp();
  }
  amb.cr -= dt;
  if (amb.cr <= 0) {
    amb.cr = 0.35 + Math.random() * 0.9;
    if (p.day < 0.25 && p.shore < 0.8) cricket();
  }
}
