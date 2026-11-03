#!/usr/bin/env bash
# Uploads a built zip to CurseForge.
# Usage: tools/upload_curseforge.sh <zip> <display name> <changelog text>
# Needs CF_API_TOKEN (secret) and CF_PROJECT_ID (variable). Skips quietly when they are not set,
# so GitHub releases keep working before the CurseForge project exists.
#
# Game version 17053 is "WoW Forever" on CurseForge (the same ID Questie uploads with).
# List of IDs: GET https://wow.curseforge.com/api/game/versions with header X-API-TOKEN.
set -euo pipefail

zip_file="$1"
display_name="$2"
changelog="${3:-}"

if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_PROJECT_ID:-}" ]; then
  echo "CurseForge is not set up yet (CF_API_TOKEN or CF_PROJECT_ID missing). Skipping the upload."
  exit 0
fi

version=$(grep -m1 '^## Version:' BeestersDungeonMaps/BeestersDungeonMaps.toc | sed 's/## Version: *//' | tr -d '\r')
# Until 1.0, uploads are marked "beta" so CurseForge users know it is still a test version.
case "$version" in
  0.*) release_type="beta" ;;
  *)   release_type="release" ;;
esac

metadata=$(python3 - "$display_name" "$release_type" "$changelog" <<'EOF'
import json, sys
name, release_type, changelog = sys.argv[1:4]
print(json.dumps({
    "displayName": name,
    "releaseType": release_type,
    "changelog": changelog or name,
    "changelogType": "markdown",
    "gameVersions": [17053],
}))
EOF
)

echo "Uploading $zip_file to CurseForge project $CF_PROJECT_ID as $release_type"
status=$(curl -sS -o /tmp/cf_response.txt -w "%{http_code}" \
  -H "X-API-TOKEN: $CF_API_TOKEN" \
  -F "metadata=$metadata" \
  -F "file=@$zip_file" \
  "https://wow.curseforge.com/api/projects/${CF_PROJECT_ID}/upload-file")

if [ "$status" = "200" ]; then
  echo "CurseForge upload successful: $(cat /tmp/cf_response.txt)"
else
  echo "CurseForge upload failed (HTTP $status):"
  cat /tmp/cf_response.txt
  exit 1
fi
