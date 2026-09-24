Сюда можно положить свои 3D-модели оружия в формате .glb (например, бесплатные CC0-модели
из паков Quaternius «Ultimate Guns» или Kenney). Используйте только модели, лицензия которых
разрешает распространение (CC0 / CC-BY), и не берите ассеты из коммерческих игр.

1. Скопируйте файлы .glb в эту папку.
2. Создайте рядом файл models.json, например:

{
  "rifle":   { "file": "ak47.glb",    "length": 0.95 },
  "bolt":    { "file": "sniper.glb",  "length": 1.05 },
  "lmg":     { "file": "lmg.glb",     "length": 1.05 },
  "shotgun": { "file": "shotgun.glb", "length": 0.95 },
  "revolver":{ "file": "revolver.glb","length": 0.35 }
}

Ключи — это id предметов: rifle (АК), bolt (болтовка), lmg (пулемёт), shotgun, revolver, bow,
stone_hatchet, metal_hatchet, stone_pickaxe, metal_pickaxe, hammer, spear, torch.
Модель автоматически повернётся длинной стороной вперёд и масштабируется под length (метры).
Если получилось криво — добавьте "transform": { "rot": [0, 3.14, 0], "pos": [0, 0.05, -0.3], "scale": 0.01 }.

Модели загружаются только когда игра открыта через веб-сервер или на Яндекс Играх
(при открытии index.html двойным кликом браузер запрещает загрузку файлов).
