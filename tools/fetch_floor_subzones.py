#!/usr/bin/env python3
"""Which subzone names exist inside each multi-level dungeon, and on which level of its map.

    python3 tools/fetch_floor_subzones.py

Inside a dungeon WoW Forever no longer says which map level you're on; the subzone name under
the minimap is the only sign. This reads the WoW Forever client's own tables from wago.tools
and writes tools/floor_subzones.json, per instance:
- subzones: the instance's subzones (AreaTable, ParentAreaID = the instance's area)
- wmo_areas: the names the game shows inside its buildings (WMOAreaTable)
- floors: the classic map level each of our map pictures is (UiMapArtTile -> UiMapXMapArt -> UiMap),
  with the areas the game assigns to that level (UiMapAssignment)
"""
import csv
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "floor_subzones.json"
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
    build = json.loads(fetch(WAGO + "/api/builds"))["wowf"][0]["version"]
    tables, errors = {}, {}
    for name in ["AreaTable", "WMOAreaTable", "UiMap", "UiMapGroupMember", "UiMapAssignment",
                 "UiMapXMapArt", "UiMapArtTile", "UiMapArt", "Map"]:
        try:
            rows = list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
            tables[name] = rows
            print(f"{name}: {len(rows)} rows; columns {list(rows[0].keys()) if rows else []}")
        except Exception as err:  # noqa: BLE001 - report and go on
            errors[name] = str(err)
            print(f"{name}: {err}")

    entrances = (ROOT / "BeestersDungeonMaps" / "Data" / "Entrances.lua").read_text(encoding="utf-8")
    areas = {k: int(a) for k, a in re.findall(r'\["(\w+)"\] = \{ name = "[^"]*", kind = "[^"]*", levels = "[^"]*", areaId = (\d+)', entrances)}
    maps = json.loads((ROOT / "tools" / "dungeon_maps.json").read_text(encoding="utf-8"))["maps"]

    area_rows = tables.get("AreaTable", [])
    area_by_id = {as_int(r.get("ID")): r for r in area_rows}
    children = {}
    for r in area_rows:
        children.setdefault(as_int(r.get("ParentAreaID")), []).append(r)

    tile_to_art = {}
    for r in tables.get("UiMapArtTile", []):
        tile_to_art[as_int(r.get("FileDataID"))] = as_int(r.get("UiMapArtID"))
    art_to_map = {}
    for r in tables.get("UiMapXMapArt", []):
        art_to_map.setdefault(as_int(r.get("UiMapArtID")), []).append(as_int(r.get("UiMapID")))
    uimap = {as_int(r.get("ID")): r for r in tables.get("UiMap", [])}
    group = {as_int(r.get("UiMapID")): r for r in tables.get("UiMapGroupMember", [])}
    assign = {}
    for r in tables.get("UiMapAssignment", []):
        assign.setdefault(as_int(r.get("UiMapID")), []).append(r)

    result = {"_source": f"WoW Forever client tables, build {build} (via wago.tools).", "errors": errors, "instances": {}}
    for key, area in sorted(areas.items()):
        def tree(a, depth=0):
            out = []
            for c in children.get(a, []):
                out.append({"id": as_int(c.get("ID")), "name": c.get("AreaName_lang"), "depth": depth})
                if depth < 3:
                    out += tree(as_int(c.get("ID")), depth + 1)
            return out
        subzones = tree(area)
        sub_ids = {area} | {s["id"] for s in subzones}
        wmo = [{k: r.get(k) for k in r if k in ("ID", "AreaName_lang", "WMOID", "WMOGroupID", "NameSetID", "AreaTableID")}
               for r in tables.get("WMOAreaTable", []) if as_int(r.get("AreaTableID")) in sub_ids]
        floors = []
        for i, tiles in enumerate(maps.get(key, []), start=1):
            arts = {tile_to_art.get(t) for t in tiles} - {None}
            map_ids = sorted({m for a in arts for m in art_to_map.get(a, [])})
            floors.append({
                "floor": i,
                "uimaps": [{"id": m, "name": (uimap.get(m) or {}).get("Name_lang"),
                            "group": (group.get(m) or {}).get("Name_lang"),
                            "relativeHeightIndex": (group.get(m) or {}).get("RelativeHeightIndex"),
                            "areas": sorted({as_int(a.get("AreaID")) for a in assign.get(m, [])} - {None, 0}),
                            "area_names": sorted({(area_by_id.get(as_int(a.get("AreaID"))) or {}).get("AreaName_lang") or ""
                                                  for a in assign.get(m, [])} - {""}),
                            "wmo_groups": sorted({as_int(a.get("WmoGroupID")) for a in assign.get(m, [])} - {None, 0, -1})}
                           for m in map_ids],
            })
        result["instances"][key] = {"area": area, "name": (area_by_id.get(area) or {}).get("AreaName_lang"),
                                    "subzones": subzones, "wmo_areas": wmo, "floors": floors}
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}")
    if errors and len(errors) == 9:
        sys.exit("Nothing could be downloaded")


if __name__ == "__main__":
    main()
