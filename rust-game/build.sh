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
if [ -d models ]; then cp -r models dist/; fi

OUT=rusty-island.zip
rm -f "$OUT"
python3 - "$OUT" <<'EOF'
import sys, os, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, _, files in os.walk('dist'):
        for f in sorted(files):
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, 'dist'))
EOF
echo "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
