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


JOURNAL_KEYS = {
    "the-hall-of-thanes": "hot", "ruins-of-lordaeron": "rol", "excavation-site-wetlands": "exc",
    "city-of-dalaran": "dal", "ragefire-chasm": "rfc", "wailing-caverns": "wc", "the-deadmines": "dm",
    "shadowfang-keep": "sfk", "blackfathom-deeps": "bfd", "razorfen-kraul": "rfk", "the-stockade": "stocks",
    "gnomeregan": "gnomer", "scarlet-monastery-graveyard": "sm", "scarlet-monastery-library": "sm",
    "scarlet-monastery-armory": "sm", "scarlet-monastery-cathedral": "sm", "razorfen-downs": "rfd",
    "uldaman": "ulda", "zulfarrak": "zf", "maraudon": "mara", "the-temple-of-atalhakkar": "st",
    "blackrock-depths": "brd", "dire-maul-east": "dme", "dire-maul-west": "dmw", "dire-maul-north": "dmn",
    "scholomance": "scholo", "lower-blackrock-spire": "brs", "upper-blackrock-spire": "brs",
    "stratholme-live": "strat", "stratholme-undead": "strat",
}


def with_journal(bosses, npcs):
    """The boss list per instance from Wowhead's WoW Forever Dungeon Journal (tools/wowhead_journal.json),
    in its order, including rares (noted as such). Names are the creature's own name as the game shows it
    (Wowhead's spelling only for groups and events without one creature). The game's encounter IDs are kept
    where the creature matches, so map positions still line up. Instances the journal doesn't cover keep
    the game's own list."""
    path = ROOT / "tools" / "wowhead_journal.json"
    if not path.exists():
        return {k: [(e, n, nid, "") for e, n, nid, *_ in v] for k, v in bosses.items()}
    journal = json.loads(path.read_text(encoding="utf-8"))["journal"]
    result = {k: [] for k in bosses}
    covered = set()
    for slug, key in JOURNAL_KEYS.items():
        if slug not in journal:
            continue
        covered.add(key)
        old = bosses.get(key, [])
        by_npc = {o[2]: o for o in old if o[2]}
        by_name = {norm(o[1]): o for o in old}
        for wname, npc_ids, _loot in journal[slug]:
            note = ""
            m = re.match(r"^(.*?)\s*\(([^)]*)\)$", wname)
            base = m.group(1) if m else wname
            if m:
                note = m.group(2)
            base = base.replace("’", "'").replace(" Event", "") if len(npc_ids) <= 1 else base.replace("’", "'")
            match = next((by_npc[n] for n in npc_ids if n in by_npc), None) or by_name.get(norm(base))
            nid = (match[2] if match and match[2] else None) or (npc_ids[0] if npc_ids else None)
            if len(npc_ids) == 1 and npcs[npc_ids[0]] is not None and npcs[npc_ids[0]][N_NAME]:
                name = npcs[npc_ids[0]][N_NAME]
            elif not npc_ids and match:
                name = match[1]
            else:
                name = base
            result.setdefault(key, []).append((match[0] if match else 0, name, nid, note))
    for key, entries in bosses.items():
        if key not in covered:
            result[key] = [(e, n, nid, "") for e, n, nid, *_ in entries]
    return result


def with_journal_loot(loot):
    """Bosses new in WoW Forever: add the loot Wowhead's Dungeon Journal lists for them."""
    path = ROOT / "tools" / "wowhead_journal.json"
    if not path.exists():
        return loot
    merged = dict(loot)
    for entries in json.loads(path.read_text(encoding="utf-8"))["journal"].values():
        for _, npc_ids, items in entries:
            if items and npc_ids and npc_ids[0] > 200000:
                merged[npc_ids[0]] = sorted(set(merged.get(npc_ids[0], [])) | set(items))
    return merged


def boss_lines(bosses):
    out = ["-- [instanceKey] = { { encounterID, name, npcID, note }, ... } in the Dungeon Journal's order",
           "-- (note: \"Rare\", \"Warlock Quest\", ...; encounterID 0 = not in the game's encounter table)",
           "ns.Bosses = {"]
    for key in sorted(bosses):
        parts = ", ".join("{%d,%s,%s,%s}" % (eid, lua_str(name), nid if nid else "nil", lua_str(note))
                          for eid, name, nid, note in bosses[key])
        out.append(f"    [{lua_str(key)}] = {{ {parts} }},")
    out.append("}")
    return out


def with_classic_loot(loot):
    """Classic bosses: their loot from the Classic database's loot tables (tools/classic_boss_loot.json,
    made by tools/build_classic_loot.py), which keeps a dungeon's set pieces that trash drops too.
    Bosses the database doesn't have (new in WoW Forever) keep QuestieDB's boss-only rule."""
    path = ROOT / "tools" / "classic_boss_loot.json"
    if not path.exists():
        return loot
    classic = json.loads(path.read_text(encoding="utf-8"))["loot"]
    merged = dict(loot)
    for nid, items in classic.items():
        merged[int(nid)] = sorted({i for i, _ in items} | set(loot.get(int(nid), [])))
    return merged


def boss_like_npcs(bosses, npcs):
    """Creatures whose drops don't make an item ordinary loot: rares (they share drops with
    bosses, e.g. the Lordaeron Captain) and a boss's own adds ("Noxxion's Spawn")."""
    names = [norm(name) for entries in bosses.values() for _, name, *_ in entries]
    ok = set()
    for nid, entity in npcs.items():
        if entity[N_RANK] in (2, 4):
            ok.add(nid)
            continue
        name = norm((entity[N_NAME] or "").split("'s ")[0]) if "'s " in (entity[N_NAME] or "") else None
        if name and name in names:
            ok.add(nid)
    return ok


def boss_only_loot(bosses, droppers, boss_like=frozenset()):
    """[npcID] = items that only bosses drop (from any dungeon), so no trash or world drops.
    Rares and a boss's adds may drop them too (boss_like)."""
    boss_npcs = {nid for entries in bosses.values() for _, _, nid, *_ in entries if nid}
    loot = {}
    for iid, who in droppers.items():
        bosses_dropping = who & boss_npcs
        if bosses_dropping and who <= boss_npcs | boss_like:
            for nid in bosses_dropping:
                loot.setdefault(nid, []).append(iid)
    return {nid: sorted(v) for nid, v in loot.items()}


def loot_only(qdb):
    """Keep the boss list in Bosses.lua and recompute only the loot (works without wago.tools)."""
    text = OUT.read_text(encoding="utf-8")
    head, _ = text.split("-- [npcID] = { itemID, ... }")
    bosses = {}
    for key, body in re.findall(r'\["(\w+)"\] = \{(.*?)\},\n', head.split("ns.Bosses = {")[1].split("\n}")[0] + "\n"):
        bosses[key] = [(int(e), n.replace('\\"', '"'), None if nid == "nil" else int(nid))
                       for e, n, nid in re.findall(r'\{(\d+),"((?:[^"\\]|\\.)*)",(\w+)', body)]
    lua = load_questiedb(qdb)
    items = lua.eval("DB.Item.entities")
    npcs = lua.eval("DB.Npc.entities")
    bosses = with_journal(bosses, npcs)
    start = head.index("-- [instanceKey]")
    end = head.index("\n}", head.index("ns.Bosses = {")) + 2
    head = head[:start] + "\n".join(boss_lines(bosses)) + head[end:]
    droppers = {}
    for iid, entity in items.items():
        npc_list = ids(to_py(entity[I_NPC_DROPS]))
        if npc_list and entity[I_CLASS] in LOOT_CLASSES:
            droppers[iid] = set(npc_list)
    loot = with_journal_loot(with_classic_loot(boss_only_loot(bosses, droppers, boss_like_npcs(bosses, npcs))))
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

    bosses = with_journal(bosses, npcs)
    loot = with_journal_loot(with_classic_loot(boss_only_loot(bosses, droppers, boss_like_npcs(bosses, npcs))))

    out = [
        "-- AUTO GENERATED by tools/build_bosses.py. Do not edit by hand.",
        f"-- Bosses and their order: Wowhead's WoW Forever Dungeon Journal (tools/wowhead_journal.json); encounter IDs: the game's DungeonEncounter table, build {build} (wago.tools).",
        "-- Creatures and loot: QuestieDB (GPL-3.0) Forever data.",
        "local _, ns = ...",
        "",
    ] + boss_lines(bosses)
    out += [""]
    # The bosses' pictures (tools/boss_models.json, made by tools/build_boss_models.py).
    models_file = ROOT / "tools" / "boss_models.json"
    if models_file.exists():
        from build_boss_models import models_block
        out += [models_block(json.loads(models_file.read_text(encoding="utf-8"))["models"]), ""]
    # Name, quality and binding of the loot (tools/loot_items.json, made by tools/build_loot_items.py).
    items_file = ROOT / "tools" / "loot_items.json"
    if items_file.exists():
        from build_loot_items import items_block
        out += [items_block(json.loads(items_file.read_text(encoding="utf-8"))["items"]), ""]
    out += ["-- [npcID] = { itemID, ... }", "ns.BossLoot = {"]
    for nid in sorted(loot):
        out.append("    [%d] = {%s}," % (nid, ",".join(str(i) for i in loot[nid])))
    out.append("}")
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")

    total = sum(len(v) for v in bosses.values())
    print(f"Wrote {OUT.relative_to(ROOT)}: {total} bosses in {sum(1 for v in bosses.values() if v)} instances, "
          f"loot for {len(loot)} bosses, {sum(len(v) for v in loot.values())} items (build {build})")
    for key in sorted(bosses):
        print(f"  {key}: " + ", ".join(name for _, name, *_ in bosses[key]))
    for u in unmatched:
        print("  no creature in QuestieDB for", u)


if __name__ == "__main__":
    main()
