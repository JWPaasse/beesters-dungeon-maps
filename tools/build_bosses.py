#!/usr/bin/env python3
"""Build BeestersDungeonMaps/Data/Bosses.lua: every dungeon's bosses in order, plus each boss's loot.

Usage:
    python3 tools/build_bosses.py /path/to/QuestieDB [DungeonEncounter.csv]
    python3 tools/build_bosses.py /path/to/QuestieDB --loot-only   (keep the boss list, redo the loot)

Boss list and order: the game's own DungeonEncounter table from the latest WoW Forever client
build, read from wago.tools (product "wowf"). Pass a CSV file instead to work offline.
Each boss is matched to its creature in QuestieDB by name. A boss's loot is every item that only
bosses drop (one boss, or several bosses sharing it), so trash drops and world drops are left out.
Food, drink and trade goods are left out too. The addon also hides anything below Uncommon quality
(the game knows each item's quality; QuestieDB doesn't).
"""
import csv
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
sys.path.insert(0, str(ROOT / "tools"))
from build_data import lua_str, parse_dungeons  # noqa: E402
from build_quests import field, ids, load_questiedb, to_py  # noqa: E402

WAGO = "https://wago.tools"
DIFFICULTIES = {0, 1}          # normal; 198/201/215 are Season of Discovery versions
LOOT_CLASSES = {2, 4, 9, 12, 15}  # weapons, armour, recipes, quest items, miscellaneous
WORLD_DROP_LIMIT = 20          # dropped by more creatures than this = a world drop, not boss loot
N_NAME, N_RANK, N_SPAWNS = 1, 6, 7
I_NPC_DROPS, I_CLASS = 2, 12


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def latest_forever_build():
    builds = json.loads(fetch(WAGO + "/api/builds"))
    return builds["wowf"][0]["version"]


def norm(name):
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def boss_only_loot(bosses, droppers):
    """[npcID] = items that only bosses drop (from any dungeon), so no trash or world drops."""
    boss_npcs = {nid for entries in bosses.values() for _, _, nid in entries if nid}
    loot = {}
    for iid, who in droppers.items():
        if who <= boss_npcs:
            for nid in who:
                loot.setdefault(nid, []).append(iid)
    return {nid: sorted(v) for nid, v in loot.items()}


def loot_only(qdb):
    """Keep the boss list in Bosses.lua and recompute only the loot (works without wago.tools)."""
    text = OUT.read_text(encoding="utf-8")
    head, _ = text.split("-- [npcID] = { itemID, ... }")
    bosses = {}
    for key, body in re.findall(r'\["(\w+)"\] = \{(.*?)\},\n', head.split("ns.Bosses = {")[1]):
        bosses[key] = [(int(e), n, None if nid == "nil" else int(nid))
                       for e, n, nid in re.findall(r'\{(\d+),"((?:[^"\\]|\\.)*)",(\w+)\}', body)]
    lua = load_questiedb(qdb)
    items = lua.eval("DB.Item.entities")
    droppers = {}
    for iid, entity in items.items():
        npc_list = ids(to_py(entity[I_NPC_DROPS]))
        if npc_list and entity[I_CLASS] in LOOT_CLASSES:
            droppers[iid] = set(npc_list)
    loot = boss_only_loot(bosses, droppers)
    lines = [head.rstrip("\n"), "", "-- [npcID] = { itemID, ... }", "ns.BossLoot = {"]
    for nid in sorted(loot):
        lines.append("    [%d] = {%s}," % (nid, ",".join(str(i) for i in loot[nid])))
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Loot redone: {len(loot)} bosses, {sum(len(v) for v in loot.values())} items")


def main():
    if len(sys.argv) == 3 and sys.argv[2] == "--loot-only":
        return loot_only(Path(sys.argv[1]).resolve())
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    qdb = Path(sys.argv[1]).resolve()
    if len(sys.argv) == 3:
        build = "local file " + Path(sys.argv[2]).name
        text = Path(sys.argv[2]).read_text(encoding="utf-8")
    else:
        build = latest_forever_build()
        text = fetch(f"{WAGO}/db2/DungeonEncounter/csv?build={build}")
    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows or "MapID" not in rows[0]:
        sys.exit("DungeonEncounter data looks wrong; keeping the existing Bosses.lua")

    config = json.loads((ROOT / "tools" / "instances.json").read_text(encoding="utf-8"))
    curated = config["instances"]
    aliases = {norm(k): v for k, v in config.get("encounterCreatures", {}).items() if not k.startswith("_")}
    dungeons = parse_dungeons(qdb / "support" / "Forever" / "Zones" / "dungeons.lua")

    lua = load_questiedb(qdb)
    npcs = lua.eval("DB.Npc.entities")
    items = lua.eval("DB.Item.entities")

    by_name = {}
    for nid, entity in npcs.items():
        by_name.setdefault(norm(entity[N_NAME]), []).append(nid)

    def match_npc(name, areas):
        candidates = by_name.get(norm(aliases.get(norm(name), name)), [])
        if not candidates:
            return None
        best = None
        for nid in candidates:
            spawns = to_py(npcs[nid][N_SPAWNS]) or {}
            if isinstance(spawns, dict) and areas & set(spawns):
                return nid
            if best is None or (not spawns and (npcs[nid][N_RANK] or 0) >= 1):
                best = nid
        return best

    # Every item's droppers, for the boss-only filter below.
    droppers = {}
    for iid, entity in items.items():
        npc_list = ids(to_py(entity[I_NPC_DROPS]))
        if npc_list and entity[I_CLASS] in LOOT_CLASSES:
            droppers[iid] = set(npc_list)

    bosses, loot, unmatched = {}, {}, []
    for area_str, info in curated.items():
        map_id = info.get("map")
        wing = {norm(n) for n in info.get("bosses", [])}
        area = int(area_str)
        areas = {area, *(dungeons.get(area, {}).get("alternates") or [])}
        chosen, seen = [], set()
        for row in rows:
            if int(row["MapID"]) != map_id or int(row["DifficultyID"]) not in DIFFICULTIES:
                continue
            if wing and norm(row["Name_lang"]) not in wing:
                continue
            if norm(row["Name_lang"]) in seen:
                continue
            seen.add(norm(row["Name_lang"]))
            chosen.append(row)
        chosen.sort(key=lambda r: (int(r["OrderIndex"]), int(r["ID"])))
        entries = []
        for row in chosen:
            nid = match_npc(row["Name_lang"], areas)
            if nid is None:
                unmatched.append(f"{info['name']}: {row['Name_lang']}")
            # Where the encounter's name differs from the creature's (instances.json,
            # encounterCreatures), show the creature's name: that's the one players see.
            name = row["Name_lang"]
            if nid is not None and norm(name) in aliases:
                name = npcs[nid][N_NAME]
            entries.append((int(row["ID"]), name, nid))
        bosses[info["key"]] = entries

    loot = boss_only_loot(bosses, droppers)

    out = [
        "-- AUTO GENERATED by tools/build_bosses.py. Do not edit by hand.",
        f"-- Bosses and their order: the game's DungeonEncounter table, WoW Forever build {build} (via wago.tools).",
        "-- Creatures and loot: QuestieDB (GPL-3.0) Forever data.",
        "local _, ns = ...",
        "",
        "-- [instanceKey] = { { encounterID, name, npcID }, ... } in the game's order",
        "ns.Bosses = {",
    ]
    for key in sorted(bosses):
        parts = ", ".join("{%d,%s,%s}" % (eid, lua_str(name), nid if nid else "nil") for eid, name, nid in bosses[key])
        out.append(f"    [{lua_str(key)}] = {{ {parts} }},")
    out += ["}", ""]
    # The bosses' pictures (tools/boss_models.json, made by tools/build_boss_models.py).
    models_file = ROOT / "tools" / "boss_models.json"
    if models_file.exists():
        from build_boss_models import models_block
        out += [models_block(json.loads(models_file.read_text(encoding="utf-8"))["models"]), ""]
    out += ["-- [npcID] = { itemID, ... }", "ns.BossLoot = {"]
    for nid in sorted(loot):
        out.append("    [%d] = {%s}," % (nid, ",".join(str(i) for i in loot[nid])))
    out.append("}")
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")

    total = sum(len(v) for v in bosses.values())
    print(f"Wrote {OUT.relative_to(ROOT)}: {total} bosses in {sum(1 for v in bosses.values() if v)} instances, "
          f"loot for {len(loot)} bosses, {sum(len(v) for v in loot.values())} items (build {build})")
    for key in sorted(bosses):
        print(f"  {key}: " + ", ".join(name for _, name, _ in bosses[key]))
    for u in unmatched:
        print("  no creature in QuestieDB for", u)


if __name__ == "__main__":
    main()
