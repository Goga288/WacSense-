#!/usr/bin/env bash
# Собирает архив для загрузки в Яндекс Игры (index.html в корне архива).
set -euo pipefail
cd "$(dirname "$0")"
OUT=rusty-island.zip
rm -f "$OUT"
if command -v zip >/dev/null 2>&1; then
  zip -r -9 "$OUT" index.html style.css js -x '*.DS_Store'
else
  python3 - "$OUT" <<'EOF'
import sys, os, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in ['index.html', 'style.css']:
        z.write(f)
    for root, _, files in os.walk('js'):
        for f in files:
            z.write(os.path.join(root, f))
EOF
fi
echo "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
