#!/usr/bin/env python3
"""Fetch boss positions from the Cataclysm Classic Dungeon Journal (via wago.tools).

    python3 tools/fetch_cata_positions.py

Retail's Dungeon Journal (tools/journal_positions.json) has positions for the dungeons as they
are today. Several classic dungeons were rebuilt after Cataclysm (Ragefire Chasm, Scarlet
Monastery, Scholomance, ...), so retail lists different bosses there. Cataclysm's journal still
had the original bosses, on the same map images the WoW Forever client ships.

Writes tools/journal_positions_cata.json in the same format: [floorKey, encounterID, name, x, y].
Needs network access to wago.tools (the GitHub Action has it).
"""
import csv
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WAGO = "https://wago.tools"

# Scholomance: our floors use the "legacy" copy of the original art; in Cataclysm the same
# original art was still in the main scholomance folder (first tiles 448178, 448190, ...).
EXTRA_FIRST_TILES = {"scholo": [448178, 448190, 448202, 448214]}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read().decode("utf-8")


def table(name, build):
    return list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))


def latest_cata_build():
    builds = json.loads(fetch(WAGO + "/api/builds"))
    versions = []
    for product, entries in builds.items():
        for entry in entries:
            version = entry.get("version", "")
            if version.startswith("4.4."):
                versions.append(version)
    if not versions:
        sample = {p: [e.get("version") for e in entries[:3]] for p, entries in list(builds.items())[:12]}
        sys.exit(f"No Cataclysm Classic build found on wago.tools. Products: {sample}")
    return max(versions, key=lambda v: [int(p) for p in v.split(".")])


def main():
    build = latest_cata_build()
    print("Cataclysm Classic build", build)
    maps = json.loads((ROOT / "tools" / "dungeon_maps.json").read_text(encoding="utf-8"))["maps"]

    first_tile_to_floor = {}
    for key, floors in maps.items():
        for n, tiles in enumerate(floors, 1):
            first_tile_to_floor[tiles[0]] = f"{key}|{n}"
    for key, first_tiles in EXTRA_FIRST_TILES.items():
        for n, fd in enumerate(first_tiles, 1):
            first_tile_to_floor[fd] = f"{key}|{n}"

    art_to_floor = {}
    for row in table("UiMapArtTile", build):
        if row["RowIndex"] == "0" and row["ColIndex"] == "0":
            floor = first_tile_to_floor.get(int(row["FileDataID"]))
            if floor:
                art_to_floor[row["UiMapArtID"]] = floor
    map_to_floor = {}
    for row in table("UiMapXMapArt", build):
        floor = art_to_floor.get(row["UiMapArtID"])
        if floor:
            map_to_floor[row["UiMapID"]] = floor

    bosses = []
    for row in table("JournalEncounter", build):
        if "Map_0" not in row:
            sys.exit(f"JournalEncounter columns changed: {list(row)}")
        floor = map_to_floor.get(row.get("UiMapID", ""))
        if floor:
            x, y = float(row["Map_0"]), float(row["Map_1"])
            if 0 < x < 1 and 0 < y < 1:
                bosses.append([floor, int(row.get("DungeonEncounterID") or 0), row["Name_lang"], round(x, 3), round(y, 3)])
    if len(bosses) < 20:
        sys.exit(f"Only {len(bosses)} positions found (floors matched: {len(art_to_floor)} art, "
                 f"{len(map_to_floor)} maps); keeping the existing file")
    out = {
        "_source": f"Cataclysm Classic Dungeon Journal, build {build}, via wago.tools (tools/fetch_cata_positions.py).",
        "bosses": sorted(bosses),
    }
    (ROOT / "tools" / "journal_positions_cata.json").write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    print(f"{len(bosses)} boss positions on {len(set(b[0] for b in bosses))} floors")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        if e.code not in (None, 0):
            print(f"::error::{e.code}")
        raise
    except Exception as e:  # show the reason in the Actions summary (annotations)
        print(f"::error::{type(e).__name__}: {e}")
        raise
