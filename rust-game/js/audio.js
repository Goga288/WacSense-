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
  }
}
