#!/usr/bin/env python3
"""Build BeestersDungeonMaps/Data/Quests.lua from QuestieDB's corrected Forever data.

Usage:
    python3 tools/build_quests.py /path/to/QuestieDB

Uses QuestieDB's own loader (generator/flavor.lua) so every Forever correction is applied,
exactly as Questie sees the data in the game. Requires: pip install lupa
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "BeestersDungeonMaps" / "Data" / "Quests.lua"
sys.path.insert(0, str(ROOT / "tools"))
from build_data import lua_str, parse_area_to_uimap, parse_dungeons  # noqa: E402

# QuestieDB quest field numbers (see data/Forever/foreverQuestDB.lua, questKeys)
Q_NAME, Q_STARTED_BY, Q_FINISHED_BY, Q_REQ_LEVEL, Q_LEVEL, Q_RACES, Q_CLASSES = 1, 2, 3, 4, 5, 6, 7
Q_OBJ_TEXT, Q_OBJECTIVES, Q_SOURCE_ITEM, Q_PRE_GROUP, Q_PRE_SINGLE = 8, 10, 11, 12, 13
Q_ZONE, Q_NEXT_IN_CHAIN, Q_SPECIAL_FLAGS, Q_BREADCRUMB_FOR = 17, 22, 24, 27
N_NAME, N_MIN_LEVEL, N_MAX_LEVEL, N_RANK, N_SPAWNS, N_ZONE, N_SUBNAME = 1, 4, 5, 6, 7, 9, 14
O_NAME, O_SPAWNS = 1, 4
I_NAME, I_NPC_DROPS, I_OBJECT_DROPS, I_START_QUEST, I_QUEST_REWARDS = 1, 2, 3, 5, 6

# Dire Maul quests are filed under the whole of Dire Maul (2557), not a wing.
EXTRA_QUEST_AREAS = {"dme": [2557], "dmn": [2557], "dmw": [2557]}


def to_py(value):
    """Lua table -> Python list/dict (recursive)."""
    if lua51.lua_type(value) != "table":
        return value
    items = list(value.items())
    keys = [k for k, _ in items]
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v) for _, v in sorted(items)]
    return {k: to_py(v) for k, v in items}


def field(entity, index):
    if entity is None:
        return None
    if isinstance(entity, list):
        return entity[index - 1] if index <= len(entity) else None
    return entity.get(index)


def ids(value):
    if not value:
        return []
    if isinstance(value, dict):
        value = [v for _, v in sorted(value.items())]
    return [v for v in value if isinstance(v, int)]


def load_questiedb(qdb):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    old = os.getcwd()
    os.chdir(qdb)
    try:
        lua.execute(
            """
            local config = dofile("src/config.lua")
            local loader = dofile("generator/flavor.lua")
            local flavor
            for _, f in ipairs(config.flavors) do if f.name == "Forever" then flavor = f end end
            DB = loader.load(flavor, { Quest = true, Npc = true, Item = true, Object = true }, true)
            local masks = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.factionRaceMasks
            """
        )
    finally:
        os.chdir(old)
    return lua


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    qdb = Path(sys.argv[1]).resolve()
    zones = qdb / "support" / "Forever" / "Zones"
    area_to_ui = parse_area_to_uimap(zones / "areaIdToUiMapId.lua")
    dungeons = parse_dungeons(zones / "dungeons.lua")
    curated = json.loads((ROOT / "tools" / "instances.json").read_text(encoding="utf-8"))["instances"]

    lua = load_questiedb(qdb)
    quests_lua = lua.eval("DB.Quest.entities")
    npcs_lua = lua.eval("DB.Npc.entities")
    items_lua = lua.eval("DB.Item.entities")
    objects_lua = lua.eval("DB.Object.entities")

    def quest(qid):
        e = quests_lua[qid]
        return to_py(e) if e is not None else None

    def npc(nid):
        e = npcs_lua[nid]
        return to_py(e) if e is not None else None

    def item(iid):
        e = items_lua[iid]
        return to_py(e) if e is not None else None

    def obj(oid):
        e = objects_lua[oid]
        return to_py(e) if e is not None else None

    # Which instance does each quest belong to?
    area_to_key = {}
    for area_str, info in curated.items():
        area = int(area_str)
        areas = [area] + (dungeons.get(area, {}).get("alternates") or []) + EXTRA_QUEST_AREAS.get(info["key"], [])
        for a in areas:
            area_to_key.setdefault(a, []).append(info["key"])

    dungeon_quests = {info["key"]: [] for info in curated.values()}
    core = set()
    for qid, entity in quests_lua.items():
        zone = entity[Q_ZONE]
        if zone in area_to_key:
            for key in area_to_key[zone]:
                dungeon_quests[key].append(qid)
            core.add(qid)

    # Lead-in quests (everything that must be done first) and direct follow-ups.
    wanted = set(core)
    todo = list(core)
    while todo:
        qid = todo.pop()
        q = quest(qid)
        for pre in ids(field(q, Q_PRE_SINGLE)) + ids(field(q, Q_PRE_GROUP)):
            if pre not in wanted and quests_lua[pre] is not None:
                wanted.add(pre)
                todo.append(pre)
    followups = {}
    for qid, entity in quests_lua.items():
        q = None
        pres = ids(to_py(entity[Q_PRE_SINGLE])) + ids(to_py(entity[Q_PRE_GROUP]))
        hit = [p for p in pres if p in core]
        if hit and qid not in wanted:
            wanted.add(qid)
            followups[qid] = hit

    # Reward items: QuestieDB records, per item, which quests reward it.
    rewards = {}
    for iid, entity in items_lua.items():
        for qid in ids(to_py(entity[I_QUEST_REWARDS])):
            if qid in wanted:
                rewards.setdefault(qid, []).append(iid)

    horde = 8589934770
    alliance = 4294967373

    def faction_of(mask):
        if not mask:
            return None
        h = bool(mask & horde & ~alliance) or mask == horde
        a = bool(mask & alliance & ~horde) or mask == alliance
        if h and not a:
            return "H"
        if a and not h:
            return "A"
        return None

    def place(spawns):
        """First spawn -> (uiMapID, x, y)."""
        if not isinstance(spawns, dict):
            return None
        for area, points in sorted(spawns.items()):
            ui = area_to_ui.get(area)
            if ui and points:
                x, y = points[0][0], points[0][1]
                if x >= 0 and y >= 0:
                    return ui, round(x / 100, 4), round(y / 100, 4)
        return None

    npc_refs, obj_refs, item_refs = set(), set(), set()
    quest_rows = {}
    for qid in sorted(wanted):
        q = quest(qid)
        if not q:
            continue
        started = field(q, Q_STARTED_BY) or []
        finished = field(q, Q_FINISHED_BY) or []
        start_npcs, start_objs, start_items = (ids(field(started, i)) for i in (1, 2, 3))
        end_npcs, end_objs = (ids(field(finished, i)) for i in (1, 2))
        objectives = field(q, Q_OBJECTIVES) or []
        obj_items = [field(o, 1) for o in (field(objectives, 3) or []) if field(o, 1)]
        obj_creatures = [field(o, 1) for o in (field(objectives, 1) or []) if field(o, 1)]
        npc_refs.update(start_npcs + end_npcs + obj_creatures)
        obj_refs.update(start_objs + end_objs)
        item_refs.update(start_items + obj_items)
        text = field(q, Q_OBJ_TEXT)
        if isinstance(text, list):
            text = " ".join(t for t in text if isinstance(t, str))
        quest_rows[qid] = {
            "name": field(q, Q_NAME),
            "level": field(q, Q_LEVEL),
            "req": field(q, Q_REQ_LEVEL),
            "faction": faction_of(field(q, Q_RACES)),
            "classes": field(q, Q_CLASSES) or None,
            "text": text,
            "startNpc": start_npcs, "startObject": start_objs, "startItem": start_items,
            "endNpc": end_npcs, "endObject": end_objs,
            "preAny": ids(field(q, Q_PRE_SINGLE)), "preAll": ids(field(q, Q_PRE_GROUP)),
            "items": obj_items, "kills": obj_creatures,
            "rewards": sorted(rewards.get(qid, [])),
            "repeatable": bool((field(q, Q_SPECIAL_FLAGS) or 0) & 1),
            "followUp": followups.get(qid),
        }

    # Who drops the objective items and the items that start quests?
    for iid in list(item_refs):
        it = item(iid)
        npc_refs.update(ids(field(it, I_NPC_DROPS))[:6])

    npc_rows = {}
    for nid in sorted(npc_refs):
        n = npc(nid)
        if not n:
            continue
        npc_rows[nid] = {
            "name": field(n, N_NAME), "sub": field(n, N_SUBNAME),
            "minLevel": field(n, N_MIN_LEVEL), "maxLevel": field(n, N_MAX_LEVEL),
            "rank": field(n, N_RANK), "where": place(field(n, N_SPAWNS)), "zone": field(n, N_ZONE),
        }
    obj_rows = {}
    for oid in sorted(obj_refs):
        o = obj(oid)
        if o:
            obj_rows[oid] = {"name": field(o, O_NAME), "where": place(field(o, O_SPAWNS))}
    item_rows = {}
    for iid in sorted(item_refs):
        it = item(iid)
        if it:
            item_rows[iid] = {"name": field(it, I_NAME), "drops": ids(field(it, I_NPC_DROPS))[:6],
                              "objects": ids(field(it, I_OBJECT_DROPS))[:6], "starts": field(it, I_START_QUEST)}

    try:
        rev = subprocess.check_output(["git", "-C", str(qdb), "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        rev = "unknown"

    def lua_list(values):
        return "{" + ",".join(str(v) for v in values) + "}"

    def lua_where(w):
        return "{%d,%.4f,%.4f}" % w if w else "nil"

    out = [
        "-- AUTO GENERATED by tools/build_quests.py. Do not edit by hand.",
        f"-- Source: QuestieDB (GPL-3.0) Forever data with all corrections applied, revision {rev}.",
        "local _, ns = ...",
        "",
        "-- [instanceKey] = { questID, ... }",
        "ns.DungeonQuests = {",
    ]
    for key in sorted(dungeon_quests):
        out.append(f"    [{lua_str(key)}] = {lua_list(sorted(dungeon_quests[key]))},")
    out += ["}", "",
            "-- [questID] = { name, level, requiredLevel, faction ('H'/'A'/nil), objective text,",
            "--   startNpc, startObject, startItem, endNpc, endObject, preAny, preAll, objectiveItems, rewards,",
            "--   classes, repeatable, followUpOf, objectiveCreatures }",
            "ns.Quests = {"]
    for qid, r in quest_rows.items():
        parts = [
            lua_str(r["name"] or "?"), str(r["level"] or 0), str(r["req"] or 0),
            lua_str(r["faction"]) if r["faction"] else "nil",
            lua_str(r["text"]) if r["text"] else "nil",
            lua_list(r["startNpc"]), lua_list(r["startObject"]), lua_list(r["startItem"]),
            lua_list(r["endNpc"]), lua_list(r["endObject"]),
            lua_list(r["preAny"]), lua_list(r["preAll"]), lua_list(r["items"]), lua_list(r["rewards"]),
            str(r["classes"]) if r["classes"] else "nil",
            "true" if r["repeatable"] else "nil",
            lua_list(r["followUp"]) if r["followUp"] else "nil",
            lua_list(r["kills"]),
        ]
        out.append(f"    [{qid}] = {{{','.join(parts)}}},")
    out += ["}", "", "-- [npcID] = { name, title, minLevel, maxLevel, rank, {uiMapID, x, y} }", "ns.NPCs = {"]
    for nid, r in npc_rows.items():
        out.append("    [%d] = {%s,%s,%d,%d,%d,%s}," % (
            nid, lua_str(r["name"] or "?"), lua_str(r["sub"]) if r["sub"] else "nil",
            r["minLevel"] or 0, r["maxLevel"] or 0, r["rank"] or 0, lua_where(r["where"])))
    out += ["}", "", "-- [objectID] = { name, {uiMapID, x, y} }", "ns.Objects = {"]
    for oid, r in obj_rows.items():
        out.append("    [%d] = {%s,%s}," % (oid, lua_str(r["name"] or "?"), lua_where(r["where"])))
    out += ["}", "", "-- [itemID] = { name, droppedByNpcs, droppedByObjects, startsQuest }", "ns.QuestItems = {"]
    for iid, r in item_rows.items():
        out.append("    [%d] = {%s,%s,%s,%s}," % (iid, lua_str(r["name"] or "?"), lua_list(r["drops"]),
                                                  lua_list(r["objects"]), r["starts"] or "nil"))
    out.append("}")
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")

    total = sum(len(v) for v in dungeon_quests.values())
    print(f"Wrote {OUT.relative_to(ROOT)}: {total} dungeon quests, {len(quest_rows)} quests incl. lead-ins/follow-ups, "
          f"{len(npc_rows)} NPCs, {len(obj_rows)} objects, {len(item_rows)} quest items, "
          f"{sum(len(v) for v in rewards.values())} reward items, {OUT.stat().st_size // 1024} KB")
    for key in sorted(dungeon_quests, key=lambda k: -len(dungeon_quests[k])):
        print(f"  {key}: {len(dungeon_quests[key])}")


if __name__ == "__main__":
    main()
