// Необязательная загрузка сторонних моделей оружия (.glb) из папки models/.
// Формат models/models.json: { "rifle": { "file": "ak.glb", "length": 0.95 }, ... }
// Можно указать "transform": { "rot": [x,y,z], "pos": [x,y,z], "scale": s } для ручной подгонки.
import { GLTFLoader } from './vendor/loaders/GLTFLoader.js';
import { external } from './viewmodel.js';

export async function loadExternalModels() {
  if (location.protocol === 'file:') return 0; // из файла браузер не даёт загружать модели
  let list;
  try {
    const r = await fetch('models/models.json', { cache: 'no-cache' });
    if (!r.ok) return 0;
    list = await r.json();
  } catch (e) {
    return 0;
  }
  const loader = new GLTFLoader();
  let n = 0;
  await Promise.all(Object.entries(list).map(async ([id, cfg]) => {
    try {
      const gltf = await loader.loadAsync('models/' + cfg.file);
      external[id] = { scene: gltf.scene, length: cfg.length, transform: cfg.transform };
      n++;
    } catch (e) {
      console.warn('Не удалось загрузить модель', cfg.file, e);
    }
  }));
  return n;
}
