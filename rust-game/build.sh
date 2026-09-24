#!/usr/bin/env bash
# Собирает игру в один скрипт (dist/) и упаковывает архив для Яндекс Игр.
# Собранную версию можно открыть двойным кликом по dist/index.html — сервер не нужен.
# Требуется Node.js (esbuild скачивается через npx).
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist
npx --yes esbuild@0.24.0 js/main.js --bundle --format=iife --minify --target=es2019 \
  --legal-comments=none --outfile=dist/game.js
sed 's#<script type="module" src="js/main.js"></script>#<script src="game.js"></script>#' index.html > dist/index.html
grep -q 'src="game.js"' dist/index.html || { echo "Не удалось подменить скрипт в index.html" >&2; exit 1; }
cp style.css dist/
cp js/three.LICENSE dist/

OUT=rusty-island.zip
rm -f "$OUT"
python3 - "$OUT" <<'EOF'
import sys, os, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in sorted(os.listdir('dist')):
        z.write(os.path.join('dist', f), f)
EOF
echo "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
