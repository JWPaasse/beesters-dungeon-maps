#!/usr/bin/env python3
"""Build tools/loot_items.json: name, quality and binding of every item in the bosses' loot.

    python3 tools/build_loot_items.py ClassicDB.sql.gz

Most classic items aren't stored in the game client; the game asks the server for them the
first time they're needed, and until the answer comes there's no name, quality or binding.
So the addon carries these itself: classic items from the CMaNGOS Classic database
(item_template, GPL-3.0), items new in WoW Forever from the client's own ItemSparse table
(tools/forever_items.json). tools/build_bosses.py writes the result into Data/Bosses.lua;
this script also updates that block right away.
"""
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOSSES = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
OUT = ROOT / "tools" / "loot_items.json"
sys.path.insert(0, str(ROOT / "tools"))
from build_data import lua_str  # noqa: E402
from build_quest_text import parse_values  # noqa: E402

MARK = "-- [itemID] = { name, quality, binding (1 = Bind on Pickup) }"


def items_block(items):
    lines = [MARK, "ns.LootItems = {"]
    for iid in sorted(items, key=int):
        name, quality, bonding = items[iid]
        lines.append("    [%s] = {%s,%d,%d}," % (iid, lua_str(name), quality, bonding))
    lines.append("}")
    return "\n".join(lines)


def write_block(items):
    text = BOSSES.read_text(encoding="utf-8")
    block = items_block(items)
    if "ns.LootItems = {" in text:
        text = re.sub(re.escape(MARK) + r"\nns\.LootItems = \{.*?\n\}", lambda m: block, text, flags=re.S)
    else:
        text = text.replace("-- [npcID] = { itemID, ... }", block + "\n\n-- [npcID] = { itemID, ... }", 1)
    BOSSES.write_text(text, encoding="utf-8")


def main():
    raw = Path(sys.argv[1]).read_bytes()
    sql = gzip.decompress(raw).decode("utf-8", errors="replace") if sys.argv[1].endswith(".gz") else raw.decode("utf-8", errors="replace")
    loot_part = BOSSES.read_text(encoding="utf-8").split("ns.BossLoot = {")[1]
    wanted = {int(i) for body in re.findall(r"^    \[\d+\] = \{([\d,]+)\}", loot_part, re.M) for i in body.split(",")}
    create = re.search(r"CREATE TABLE `item_template` \((.*?)\) ENGINE", sql, re.S).group(1)
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)
    items = {}
    for m in re.finditer(r"INSERT INTO `item_template` VALUES (.*?);\n", sql, re.S):
        for row in parse_values(m.group(1)):
            r = dict(zip(cols, row))
            if r["entry"] in wanted:
                items[str(r["entry"])] = [r["name"], r["Quality"], r["bonding"]]
    forever = json.loads((ROOT / "tools" / "forever_items.json").read_text(encoding="utf-8"))["items"]
    for iid, (name, quality, bonding, _) in forever.items():
        if int(iid) in wanted:
            items[iid] = [name, quality, bonding]  # WoW Forever's own data wins
    OUT.write_text(json.dumps({"_source": "CMaNGOS Classic-DB item_template (GPL-3.0) and the WoW Forever client's ItemSparse table", "items": items}, indent=0) + "\n", encoding="utf-8")
    write_block(items)
    missing = sorted(wanted - {int(i) for i in items})
    print(f"Item data for {len(items)} of {len(wanted)} loot items; {len(missing)} left to the game: {missing[:20]}...")


if __name__ == "__main__":
    main()
