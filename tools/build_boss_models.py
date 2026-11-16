#!/usr/bin/env python3
"""Build tools/boss_models.json: the creature model (display ID) of each boss, for its picture.

    python3 tools/build_boss_models.py ClassicDB.sql.gz

The model IDs come from the CMaNGOS Classic database (GPL-3.0, https://github.com/cmangos/classic-db),
creature_template.ModelId1. Bosses new in WoW Forever aren't in it; the addon asks the game for
those by creature ID instead. tools/build_bosses.py writes the result into Data/Bosses.lua; this
script also updates that block right away.
"""
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOSSES = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
OUT = ROOT / "tools" / "boss_models.json"
sys.path.insert(0, str(ROOT / "tools"))
from build_quest_text import parse_values  # noqa: E402


LEARNED = ROOT / "tools" / "learned_models.json"
INFO = ROOT / "tools" / "boss_info.json"


def info_block(info):
    """[npcID] = { minLevel, maxLevel, rank, creatureType } for the line under a boss's name.
    Rank: 1 elite, 2 rare elite, 3 boss (level ??), 4 rare. Creature type: the game's numbers."""
    lines = ["-- [npcID] = { minLevel, maxLevel, rank (1 elite, 2 rare elite, 3 boss, 4 rare), creature type }",
             "-- (CMaNGOS Classic-DB, GPL-3.0)", "ns.BossInfo = {"]
    for nid in sorted(info, key=int):
        lines.append("    [%s] = {%s}," % (nid, ",".join(str(int(v)) for v in info[nid])))
    lines.append("}")
    return "\n".join(lines)


def models_block(models):
    """The classic bosses' models, plus the Forever bosses' models noted in game when a player
    targeted them (tools/learned_models.json, from their saved settings)."""
    models = dict(models)
    if LEARNED.exists():
        for nid, display in json.loads(LEARNED.read_text(encoding="utf-8"))["models"].items():
            models.setdefault(nid, display)
    lines = ["-- [npcID] = creature display ID, for the boss's picture (CMaNGOS Classic-DB, GPL-3.0;",
             "-- bosses new in WoW Forever: noted in game, tools/learned_models.json)", "ns.BossModels = {"]
    for nid in sorted(models, key=int):
        lines.append("    [%s] = %d," % (nid, models[nid]))
    lines.append("}")
    return "\n".join(lines)


def write_block(models):
    text = BOSSES.read_text(encoding="utf-8")
    block = models_block(models)
    if "ns.BossModels = {" in text:
        text = re.sub(r"-- \[npcID\] = creature display ID.*?\nns\.BossModels = \{.*?\n\}", lambda m: block, text, flags=re.S)
    else:
        text = text.replace("-- [npcID] = { itemID, ... }", block + "\n\n-- [npcID] = { itemID, ... }", 1)
    if INFO.exists():
        block = info_block(json.loads(INFO.read_text(encoding="utf-8"))["info"])
        if "ns.BossInfo = {" in text:
            text = re.sub(r"-- \[npcID\] = \{ minLevel.*?\nns\.BossInfo = \{.*?\n\}", lambda m: block, text, flags=re.S)
        else:
            text = text.replace("-- [npcID] = { itemID, ... }", block + "\n\n-- [npcID] = { itemID, ... }", 1)
    BOSSES.write_text(text, encoding="utf-8")


def main():
    raw = Path(sys.argv[1]).read_bytes()
    sql = gzip.decompress(raw).decode("utf-8", errors="replace") if sys.argv[1].endswith(".gz") else raw.decode("utf-8", errors="replace")
    create = re.search(r"CREATE TABLE `creature_template` \((.*?)\) ENGINE", sql, re.S).group(1)
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)
    wanted = {int(n) for n in re.findall(r'\{\d+,"(?:[^"\\]|\\.)*",(\d+)[,}]', BOSSES.read_text(encoding="utf-8"))}
    models, info = {}, {}
    for m in re.finditer(r"INSERT INTO `creature_template` VALUES (.*?);\n", sql, re.S):
        for row in parse_values(m.group(1)):
            r = dict(zip(cols, row))
            if r["Entry"] in wanted and r["ModelId1"]:
                models[str(r["Entry"])] = r["ModelId1"]
            if r["Entry"] in wanted:
                info[str(r["Entry"])] = [r.get("MinLevel") or 0, r.get("MaxLevel") or 0, r.get("Rank") or 0, r.get("CreatureType") or 0]
    OUT.write_text(json.dumps({"_source": "CMaNGOS Classic-DB creature_template.ModelId1 (GPL-3.0)", "models": models}, indent=1) + "\n", encoding="utf-8")
    INFO.write_text(json.dumps({"_source": "CMaNGOS Classic-DB creature_template MinLevel, MaxLevel, Rank, CreatureType (GPL-3.0)",
                                "info": info}, indent=1) + "\n", encoding="utf-8")
    write_block(models)
    print(f"Models for {len(models)} of {len(wanted)} bosses, level and type for {len(info)}")


if __name__ == "__main__":
    main()
