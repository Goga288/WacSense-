// Звук гонки: мотор (два осциллятора через фильтр), визг шин, свист «впритирку», удар, сигнал.
let ctx = null, master = null, eng = null, screech = null, noiseBuf = null, muted = false;

export function initAudio(enabled) {
  muted = !enabled;
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = muted ? 0 : 0.5;
  master.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  const o1 = ctx.createOscillator(), o2 = ctx.createOscillator();
  o1.type = 'sawtooth'; o2.type = 'square';
  const f = ctx.createBiquadFilter();
  f.type = 'lowpass'; f.frequency.value = 900; f.Q.value = 3;
  const g = ctx.createGain();
  g.gain.value = 0.0;
  const g2 = ctx.createGain();
  g2.gain.value = 0.35;
  o1.connect(f); o2.connect(g2).connect(f); f.connect(g).connect(master);
  o1.start(); o2.start();
  eng = { o1, o2, f, g };
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf; src.loop = true;
  const bf = ctx.createBiquadFilter();
  bf.type = 'bandpass'; bf.frequency.value = 2400; bf.Q.value = 4;
  const sg = ctx.createGain();
  sg.gain.value = 0;
  src.connect(bf).connect(sg).connect(master);
  src.start();
  screech = sg;
}

export function engine(rpm, throttle, on) {
  if (!eng) return;
  const t = ctx.currentTime;
  const f = 28 + rpm / 60 * 1.1;
  eng.o1.frequency.setTargetAtTime(f, t, 0.03);
  eng.o2.frequency.setTargetAtTime(f * 0.5, t, 0.03);
  eng.f.frequency.setTargetAtTime(500 + throttle * 1400 + rpm * 0.08, t, 0.05);
  eng.g.gain.setTargetAtTime(on ? 0.1 + throttle * 0.12 : 0, t, 0.08);
}

export function tires(level) {
  if (!screech) return;
  screech.gain.setTargetAtTime(Math.min(0.25, level), ctx.currentTime, 0.05);
}

function burst(dur, freq, type, vol) {
  if (!ctx || muted) return;
  const t = ctx.currentTime;
  const s = ctx.createBufferSource();
  s.buffer = noiseBuf;
  const f = ctx.createBiquadFilter();
  f.type = type; f.frequency.value = freq;
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  s.connect(f).connect(g).connect(master);
  s.start(t, Math.random() * 0.5);
  s.stop(t + dur);
}

export function whoosh() { burst(0.5, 900, 'bandpass', 0.7); }
export function crash() { burst(1.2, 600, 'lowpass', 1.6); burst(0.6, 3000, 'highpass', 0.8); }
export function horn(on) {
  if (!ctx || muted) return;
  if (on && !horn.o) {
    const a = ctx.createOscillator(), b = ctx.createOscillator(), g = ctx.createGain();
    a.type = b.type = 'square';
    a.frequency.value = 410; b.frequency.value = 500;
    g.gain.value = 0.08;
    a.connect(g); b.connect(g); g.connect(master);
    a.start(); b.start();
    horn.o = [a, b];
  } else if (!on && horn.o) {
    horn.o.forEach((o) => o.stop());
    horn.o = null;
  }
}

export function suspend(v) {
  if (!ctx) return;
  if (v) ctx.suspend(); else ctx.resume();
}

export function close() {
  if (ctx) ctx.close();
  ctx = null; eng = null; screech = null;
}
