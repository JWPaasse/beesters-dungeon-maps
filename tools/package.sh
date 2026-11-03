#!/usr/bin/env bash
# Builds dist/BeestersDungeonMaps-<version>.zip, ready to unzip into Interface\AddOns.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -m1 '^## Version:' BeestersDungeonMaps/BeestersDungeonMaps.toc | sed 's/## Version: *//' | tr -d '\r')
mkdir -p dist
rm -f "dist/BeestersDungeonMaps-${version}.zip"
cp LICENSE BeestersDungeonMaps/LICENSE.md
python3 - "$version" <<'EOF'
import sys, zipfile, pathlib
version = sys.argv[1]
out = pathlib.Path(f"dist/BeestersDungeonMaps-{version}.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for path in sorted(pathlib.Path("BeestersDungeonMaps").rglob("*")):
        if path.is_file():
            z.write(path, path.as_posix())
print(out)
EOF
rm BeestersDungeonMaps/LICENSE.md
