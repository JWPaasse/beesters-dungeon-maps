#!/usr/bin/env python3
"""The new WoW Forever dungeons as the game itself knows them: instance IDs, entrances, bosses,
and which quests belong together (quest lines) or send you into each dungeon (objective areas).

    python3 tools/fetch_new_dungeons.py

Reads the WoW Forever client's own tables from wago.tools and writes tools/new_dungeons.json.
Used to check QuestieDB's quests for these dungeons: which are dungeon quests, and which form
a chain. The quests themselves still come from QuestieDB.
"""
import csv
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "new_dungeons.json"
WAGO = "https://wago.tools"

DUNGEONS = ["Drowned City", "Krol'dok", "Alcaz", "Blackmaw", "Shaper", "Barrow Deeps", "Hyjal"]
# Quests QuestieDB has whose text names one of these dungeons.
QUESTS = [95775, 95776, 95787, 95788, 95789, 95791, 96774, 97130,
          94968, 94969, 94972, 94973, 94975, 94980, 94982, 94983, 94984, 96771,
          95262, 95285, 95309, 95454, 96332, 96334, 96381, 96772,
          92343, 92344, 97173, 97198, 99187,
          95790, 95924, 95925, 95926, 95928, 97049]


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
    for name in ["Map", "JournalInstance", "DungeonEncounter", "QuestLine", "QuestLineXQuest",
                 "QuestPOIBlob", "UiMapAssignment", "UiMap", "AreaTable", "QuestV2"]:
        try:
            rows = list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
            tables[name] = rows
            if name == "DungeonEncounter":
                # The whole table too, so tools/build_bosses.py can run without network access.
                (ROOT / "tools" / "dungeon_encounter.csv").write_text(fetch(f"{WAGO}/db2/{name}/csv?build={build}"), encoding="utf-8")
            print(f"{name}: {len(rows)} rows; columns {list(rows[0].keys()) if rows else []}")
        except Exception as err:  # noqa: BLE001 - report and go on
            errors[name] = str(err)
            print(f"{name}: {err}")

    def named(row, *cols):
        text = " ".join(str(row.get(c) or "") for c in cols)
        return any(d.lower() in text.lower() for d in DUNGEONS)

    maps = [r for r in tables.get("Map", []) if named(r, "MapName_lang", "Directory")]
    map_ids = {as_int(r.get("ID")) for r in maps}
    journal = [r for r in tables.get("JournalInstance", []) if as_int(r.get("MapID")) in map_ids or named(r, "Name_lang")]
    encounters = [r for r in tables.get("DungeonEncounter", []) if as_int(r.get("MapID")) in map_ids]
    areas = [r for r in tables.get("AreaTable", []) if named(r, "AreaName_lang", "ZoneName")]

    # Quests whose objectives lie inside one of these dungeons (whatever their text says).
    poi = [r for r in tables.get("QuestPOIBlob", [])
           if as_int(r.get("MapID")) in map_ids or as_int(r.get("QuestID")) in QUESTS]
    quest_ids = set(QUESTS) | {as_int(r.get("QuestID")) for r in poi if as_int(r.get("MapID")) in map_ids}
    # The quest lines those quests are in, with every quest of each line, in order.
    lxq = tables.get("QuestLineXQuest", [])
    line_ids = {as_int(r.get("QuestLineID")) for r in lxq if as_int(r.get("QuestID")) in quest_ids}
    lines = {}
    for r in lxq:
        lid = as_int(r.get("QuestLineID"))
        if lid in line_ids:
            lines.setdefault(lid, []).append({k: r.get(k) for k in r})
    for lid in lines:
        lines[lid].sort(key=lambda r: as_int(r.get("OrderIndex")) or 0)
    line_names = {as_int(r.get("ID")): {k: r.get(k) for k in r} for r in tables.get("QuestLine", []) if as_int(r.get("ID")) in line_ids}
    quests_v2 = [r for r in tables.get("QuestV2", []) if as_int(r.get("ID")) in quest_ids]

    # Where the ghost goes when you die inside: the entrance, in world coordinates; and the
    # outdoor maps that cover that spot, to turn it into map coordinates.
    corpse_maps = {as_int(r.get("CorpseMapID")) for r in maps} - {None, -1}
    uimap = {as_int(r.get("ID")): r.get("Name_lang") for r in tables.get("UiMap", [])}
    entrances = []
    for m in maps:
        cmap = as_int(m.get("CorpseMapID"))
        try:
            cx, cy = float(m.get("Corpse_0") or m.get("Corpse[0]") or 0), float(m.get("Corpse_1") or m.get("Corpse[1]") or 0)
        except ValueError:
            continue
        if cmap in (None, -1) or (cx == 0 and cy == 0):
            continue
        for a in tables.get("UiMapAssignment", []):
            if as_int(a.get("MapID")) != cmap:
                continue
            try:
                x0, y0 = float(a["Region_0"]), float(a["Region_1"])
                x1, y1 = float(a["Region_3"]), float(a["Region_4"])
                u0, v0 = float(a["UiMin_0"]), float(a["UiMin_1"])
                u1, v1 = float(a["UiMax_0"]), float(a["UiMax_1"])
            except (KeyError, ValueError):
                continue
            if not (min(x0, x1) <= cx <= max(x0, x1) and min(y0, y1) <= cy <= max(y0, y1)):
                continue
            # The map's x runs along the world's -y, its y along the world's -x.
            fx = (y1 - cy) / (y1 - y0) if y1 != y0 else 0
            fy = (x1 - cx) / (x1 - x0) if x1 != x0 else 0
            ui = as_int(a.get("UiMapID"))
            entrances.append({"map": as_int(m.get("ID")), "name": m.get("MapName_lang"), "uiMapID": ui,
                              "uiMap": uimap.get(ui), "x": round(u0 + fx * (u1 - u0), 4), "y": round(v0 + fy * (v1 - v0), 4)})

    result = {"_source": f"WoW Forever client tables, build {build} (via wago.tools).", "errors": errors,
              "maps": maps, "journal": journal, "encounters": encounters, "areas": areas,
              "entrances": entrances, "corpseMaps": sorted(corpse_maps),
              "questPOI": poi, "questLines": {str(k): {"line": line_names.get(k), "quests": v} for k, v in lines.items()},
              "questV2": quests_v2}
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: {len(maps)} maps, {len(encounters)} encounters, {len(lines)} quest lines, {len(entrances)} entrance spots")
    if len(errors) == 10:
        sys.exit("Nothing could be downloaded")


if __name__ == "__main__":
    main()
