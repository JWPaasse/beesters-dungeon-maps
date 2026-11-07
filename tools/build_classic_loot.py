#!/usr/bin/env python3
"""Build tools/classic_boss_loot.json: each classic boss's loot with drop chances.

    python3 tools/build_classic_loot.py ClassicDB.sql.gz

Source: the CMaNGOS Classic database's loot tables (GPL-3.0, https://github.com/cmangos/classic-db).
A boss's loot is what its own loot table lists, plus shared tables that only bosses (or rares and
a boss's own adds) use: so a dungeon's set pieces count, while tables that trash shares (world
drops, cloth, potions) don't. Chances are worked out the way the server rolls: an "equal chance"
group shares what its fixed-chance items leave, and a shared table's chance multiplies through.
Items under 1% are left out. tools/build_bosses.py uses this for every boss the database has;
bosses new in WoW Forever keep QuestieDB's data.
"""
import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "classic_boss_loot.json"
BOSSES = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
sys.path.insert(0, str(ROOT / "tools"))
from build_quest_text import parse_values  # noqa: E402

MIN_CHANCE = 1.0


def table(sql, name):
    create = re.search(r"CREATE TABLE `%s` \((.*?)\) ENGINE" % name, sql, re.S).group(1)
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)
    rows = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n" % name, sql, re.S):
        rows += [dict(zip(cols, r)) for r in parse_values(m.group(1))]
    return rows


def chances(rows):
    """(item or ('ref', id), chance%) for one loot table, groups worked out."""
    out, groups = [], defaultdict(list)
    for r in rows:
        (groups[r["groupid"]] if r["groupid"] else out).append(r)
    result = []
    for r in out:
        result.append((r, abs(r["ChanceOrQuestChance"])))
    for rs in groups.values():
        fixed = sum(abs(r["ChanceOrQuestChance"]) for r in rs if r["ChanceOrQuestChance"])
        equal = [r for r in rs if not r["ChanceOrQuestChance"]]
        share = max(0.0, 100.0 - fixed) / len(equal) if equal else 0
        for r in rs:
            result.append((r, abs(r["ChanceOrQuestChance"]) or share))
    return result


def main():
    raw = Path(sys.argv[1]).read_bytes()
    sql = gzip.decompress(raw).decode("utf-8", errors="replace") if sys.argv[1].endswith(".gz") else raw.decode("utf-8", errors="replace")
    creatures = table(sql, "creature_template")
    clt, rlt = table(sql, "creature_loot_template"), table(sql, "reference_loot_template")
    loot_id = {c["Entry"]: c["LootId"] or c["Entry"] for c in creatures}
    rank = {c["Entry"]: c["Rank"] for c in creatures}
    names = {c["Entry"]: c["Name"] for c in creatures}
    by_loot = defaultdict(list)
    for r in clt:
        by_loot[r["entry"]].append(r)
    refs = defaultdict(list)
    for r in rlt:
        refs[r["entry"]].append(r)

    bosses = {int(n) for n in re.findall(r'\{\d+,"(?:[^"\\]|\\.)*",(\d+)[,}]', BOSSES.read_text(encoding="utf-8").split("ns.Bosses = {")[1].split("\n}")[0])}
    boss_names = {re.sub(r"[^a-z]", "", names.get(b, "").lower()) for b in bosses}
    # Rares and a boss's own adds ("Noxxion's Spawn") may share a boss's tables.
    boss_like = set(bosses)
    for e, n in names.items():
        if rank.get(e) in (2, 4) or ("'s " in n and re.sub(r"[^a-z]", "", n.split("'s ")[0].lower()) in boss_names):
            boss_like.add(e)

    # Who uses each shared table (directly, or through another shared table)?
    users = defaultdict(set)
    loot_owners = defaultdict(set)
    for e, lid in loot_id.items():
        loot_owners[lid].add(e)
    for r in clt:
        if r["mincountOrRef"] < 0:
            users[-r["mincountOrRef"]] |= loot_owners[r["entry"]]
    changed = True
    while changed:
        changed = False
        for r in rlt:
            if r["mincountOrRef"] < 0:
                before = len(users[-r["mincountOrRef"]])
                users[-r["mincountOrRef"]] |= users[r["entry"]]
                changed |= len(users[-r["mincountOrRef"]]) != before
    boss_tables = {ref for ref, who in users.items() if who and who <= boss_like}

    def expand(rows, factor, depth=0):
        items = defaultdict(float)
        for r, chance in chances(rows):
            if r["mincountOrRef"] < 0:
                ref = -r["mincountOrRef"]
                if ref in boss_tables and depth < 5:
                    for item, c in expand(refs[ref], factor * chance / 100, depth + 1).items():
                        items[item] += c
            else:
                items[r["item"]] += factor * chance
        return items

    result = {}
    for boss in sorted(bosses):
        if boss not in loot_id:
            continue
        items = expand(by_loot[loot_id[boss]], 1.0)
        kept = sorted(((i, round(c, 2)) for i, c in items.items() if c >= MIN_CHANCE), key=lambda x: -x[1])
        if kept:
            result[str(boss)] = kept
    OUT.write_text(json.dumps({"_source": "CMaNGOS Classic-DB loot tables (GPL-3.0): [itemID, drop chance %]", "loot": result}, indent=0) + "\n", encoding="utf-8")
    print(f"Loot for {len(result)} classic bosses, {sum(len(v) for v in result.values())} items; {len(boss_tables)} boss-only shared tables")


if __name__ == "__main__":
    main()
