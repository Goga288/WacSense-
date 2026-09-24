// Обёртка над Yandex Games SDK. Если SDK недоступен (локальный запуск) — всё работает без него.
import { setMuted } from './audio.js';

let ysdk = null;
let player = null;
let lastAd = 0;

export const Y = {
  available: false,
  onPause: null,
  onResume: null,

  async init() {
    try {
      if (!window.YaGames) return;
      ysdk = await window.YaGames.init();
      this.available = true;
      try {
        player = await ysdk.getPlayer({ scopes: false });
      } catch (e) {
        player = null;
      }
      // Системная пауза от Яндекса (например, открыт оверлей платформы)
      try {
        ysdk.on('game_api_pause', () => this.onPause && this.onPause());
        ysdk.on('game_api_resume', () => this.onResume && this.onResume());
      } catch (e) { /* старые версии SDK */ }
    } catch (e) {
      console.warn('Yandex SDK init failed', e);
    }
  },

  lang() {
    try {
      return ysdk ? ysdk.environment.i18n.lang : 'ru';
    } catch (e) {
      return 'ru';
    }
  },

  isMobile() {
    try {
      if (ysdk && ysdk.deviceInfo) return ysdk.deviceInfo.isMobile() || ysdk.deviceInfo.isTablet();
    } catch (e) { /* ignore */ }
    return matchMedia('(pointer: coarse)').matches;
  },

  ready() {
    try { ysdk && ysdk.features.LoadingAPI && ysdk.features.LoadingAPI.ready(); } catch (e) { /* ignore */ }
  },

  gameplayStart() {
    try { ysdk && ysdk.features.GameplayAPI && ysdk.features.GameplayAPI.start(); } catch (e) { /* ignore */ }
  },

  gameplayStop() {
    try { ysdk && ysdk.features.GameplayAPI && ysdk.features.GameplayAPI.stop(); } catch (e) { /* ignore */ }
  },

  // Полноэкранная реклама (частоту дополнительно ограничивает сам Яндекс).
  showFullscreen(done) {
    const now = Date.now();
    if (!ysdk || now - lastAd < 90000) { done && done(); return; }
    lastAd = now;
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      setMuted(false);
      done && done();
    };
    try {
      ysdk.adv.showFullscreenAdv({
        callbacks: {
          onOpen: () => setMuted(true),
          onClose: finish,
          onError: finish,
          onOffline: finish,
        },
      });
    } catch (e) {
      finish();
    }
  },

  // Реклама за вознаграждение. Без SDK награда выдаётся сразу (для локальных тестов).
  showRewarded(onReward, done) {
    if (!ysdk) { onReward && onReward(); done && done(); return; }
    let rewarded = false;
    const finish = () => {
      setMuted(false);
      if (rewarded) onReward && onReward();
      done && done();
    };
    try {
      ysdk.adv.showRewardedVideo({
        callbacks: {
          onOpen: () => setMuted(true),
          onRewarded: () => { rewarded = true; },
          onClose: finish,
          onError: finish,
        },
      });
    } catch (e) {
      finish();
    }
  },

  async saveCloud(json) {
    if (!player) return;
    try { await player.setData({ save: json }, false); } catch (e) { /* ignore */ }
  },

  async loadCloud() {
    if (!player) return null;
    try {
      const d = await player.getData(['save']);
      return d && d.save ? d.save : null;
    } catch (e) {
      return null;
    }
  },
};
