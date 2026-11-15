#!/usr/bin/env python3
"""The models (display IDs) of the bosses new in WoW Forever, for their portraits.

    python3 tools/fetch_forever_models.py

tools/boss_models.json has the classic bosses' models from the CMaNGOS Classic database. Bosses
new in WoW Forever aren't in it; their models come from the WoW Forever client's own tables
(Creature, CreatureXDisplayInfo), read from wago.tools. Written to tools/forever_models.json;
tools/build_bosses.py adds them to the portraits.
"""
import csv
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "forever_models.json"
BOSSES = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
WAGO = "https://wago.tools"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read().decode("utf-8")


def as_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def main():
    classic = json.loads((ROOT / "tools" / "boss_models.json").read_text(encoding="utf-8"))["models"]
    text = BOSSES.read_text(encoding="utf-8")
    body = text.split("ns.Bosses = {", 1)[1].split("\n}\n", 1)[0]
    npcs = {int(n) for n in re.findall(r'\{\d+,"(?:[^"\\]|\\.)*",(\d+),', body)} - {int(k) for k in classic}
    print(f"{len(npcs)} bosses without a model from the Classic database")

    build = json.loads(fetch(WAGO + "/api/builds"))["wowf"][0]["version"]
    found, errors = {}, {}
    for name in ["Creature", "CreatureXDisplayInfo"]:
        try:
            rows = list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
        except Exception as err:  # noqa: BLE001 - report and go on
            errors[name] = str(err)
            print(f"{name}: {err}")
            continue
        print(f"{name}: {len(rows)} rows; columns {list(rows[0].keys()) if rows else []}")
        for r in rows:
            if name == "Creature":
                nid = as_int(r.get("ID"))
                display = next((as_int(r.get(c)) for c in ("DisplayID_0", "DisplayID[0]", "DisplayID") if as_int(r.get(c))), None)
            else:
                nid = as_int(r.get("CreatureID"))
                display = as_int(r.get("CreatureDisplayInfoID"))
            if nid in npcs and display and nid not in found:
                found[nid] = display
    result = {"_source": f"WoW Forever client tables Creature / CreatureXDisplayInfo, build {build} (via wago.tools).",
              "errors": errors, "models": {str(k): v for k, v in sorted(found.items())},
              "missing": sorted(npcs - set(found))}
    OUT.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: {len(found)} of {len(npcs)} bosses")
    if len(errors) == 2:
        sys.exit("Nothing could be downloaded")


if __name__ == "__main__":
    main()
