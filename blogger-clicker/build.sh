#!/usr/bin/env bash
# Архив для загрузки в Яндекс Игры (index.html в корне).
set -euo pipefail
cd "$(dirname "$0")"
OUT=blogger-clicker.zip
rm -f "$OUT"
python3 - "$OUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in ['index.html', 'style.css', 'game.js']:
        z.write(f)
PY
echo "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
