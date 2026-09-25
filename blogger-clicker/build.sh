#!/usr/bin/env bash
# Архив для загрузки в Яндекс Игры (index.html в корне).
set -euo pipefail
cd "$(dirname "$0")"
# 3D-гонка «Шашки» собирается в один скрипт racer.js (глобальный объект Racer)
npx --yes esbuild@0.24.0 racer/src/main.js --bundle --format=iife --global-name=Racer --minify --target=es2019 \
  --legal-comments=none --outfile=racer.js
OUT=blogger-clicker.zip
rm -f "$OUT"
python3 - "$OUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in ['index.html', 'style.css', 'game.js', 'racer.js']:
        z.write(f)
PY
echo "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
