#!/usr/bin/env python3
"""Build tools/classic_item_tooltips.json: tooltips made from the Classic database's item stats,
for loot items Wowhead's WoW Forever database doesn't have.

    python3 tools/build_classic_tooltips.py ClassicDB.sql.gz

Source: CMaNGOS Classic-DB item_template (GPL-3.0). These are classic values: WoW Forever may
have changed an item, and spell effects ("Equip: ...") only appear as a placeholder, so the
tooltip says so. tools/fetch_loot_tooltips.py uses these where Wowhead has nothing.
"""
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "classic_item_tooltips.json"
sys.path.insert(0, str(ROOT / "tools"))
from build_quest_text import parse_values  # noqa: E402

QUALITY = ["9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80"]
SLOTS = {1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet",
         9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket", 13: "One-Hand", 14: "Off Hand", 15: "Ranged",
         16: "Back", 17: "Two-Hand", 19: "Tabard", 20: "Chest", 21: "Main Hand", 22: "Off Hand",
         23: "Held In Off-hand", 25: "Thrown", 26: "Ranged", 28: "Relic"}
WEAPONS = {0: "Axe", 1: "Axe", 2: "Bow", 3: "Gun", 4: "Mace", 5: "Mace", 6: "Polearm", 7: "Sword", 8: "Sword",
           10: "Staff", 13: "Fist Weapon", 15: "Dagger", 16: "Thrown", 18: "Crossbow", 19: "Wand", 20: "Fishing Pole"}
ARMOR = {1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate", 6: "Shield"}
STATS = {3: "Agility", 4: "Strength", 5: "Intellect", 6: "Spirit", 7: "Stamina"}
RESIST = [("holy_res", "Holy"), ("fire_res", "Fire"), ("nature_res", "Nature"), ("frost_res", "Frost"),
          ("shadow_res", "Shadow"), ("arcane_res", "Arcane")]
TRIGGER = {0: "Use", 1: "Equip", 2: "Chance on hit"}


def tooltip(r):
    lines = [f"|cff{QUALITY[r['Quality']]}{r['name']}|r"]
    if r.get("ItemLevel"):
        lines.append(f"|cffffd100Item Level {r['ItemLevel']}|r")
    lines += {1: ["Binds when picked up"], 2: ["Binds when equipped"], 3: ["Binds when used"], 4: ["Quest Item"]}.get(r["bonding"], [])
    if r.get("MaxCount") == 1:
        lines.append("Unique")
    slot = SLOTS.get(r["InventoryType"])
    kind = WEAPONS.get(r["subclass"]) if r["class"] == 2 else ARMOR.get(r["subclass"]) if r["class"] == 4 else None
    if slot:
        lines.append(slot + (f"\t{kind}" if kind else ""))
    if r["class"] == 2 and r.get("dmg_max1"):
        speed = (r["delay"] or 0) / 1000
        lines.append(f"{int(r['dmg_min1'])} - {int(r['dmg_max1'])} Damage\tSpeed {speed:.2f}")
        if speed:
            lines.append(f"({(r['dmg_min1'] + r['dmg_max1']) / 2 / speed:.1f} damage per second)")
    if r.get("armor"):
        lines.append(f"{r['armor']} Armor")
    for i in range(1, 11):
        stat, value = r.get(f"stat_type{i}"), r.get(f"stat_value{i}")
        if value and stat in STATS:
            lines.append(f"{value:+d} {STATS[stat]}")
    for col, label in RESIST:
        if r.get(col):
            lines.append(f"+{r[col]} {label} Resistance")
    if r.get("MaxDurability"):
        lines.append(f"Durability {r['MaxDurability']} / {r['MaxDurability']}")
    if r.get("RequiredLevel", 0) > 1:
        lines.append(f"Requires Level {r['RequiredLevel']}")
    effects = [TRIGGER.get(r.get(f"spelltrigger_{i}"), "Equip") for i in range(1, 6) if r.get(f"spellid_{i}")]
    for trigger in effects:
        lines.append(f"|cff1eff00{trigger}: (effect not listed here)|r")
    lines.append("|cff808080Classic values; WoW Forever may differ.|r")
    return lines


def main():
    raw = Path(sys.argv[1]).read_bytes()
    sql = gzip.decompress(raw).decode("utf-8", errors="replace") if sys.argv[1].endswith(".gz") else raw.decode("utf-8", errors="replace")
    bosses = (ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua").read_text(encoding="utf-8").split("ns.BossLoot = {")[1]
    wanted = {int(i) for body in re.findall(r"^    \[\d+\] = \{([\d,]+)\}", bosses, re.M) for i in body.split(",")}
    create = re.search(r"CREATE TABLE `item_template` \((.*?)\) ENGINE", sql, re.S).group(1)
    cols = re.findall(r"^\s*`(\w+)`", create, re.M)
    tips = {}
    for m in re.finditer(r"INSERT INTO `item_template` VALUES (.*?);\n", sql, re.S):
        for row in parse_values(m.group(1)):
            r = dict(zip(cols, row))
            if r["entry"] in wanted and r["class"] in (2, 4):
                tips[str(r["entry"])] = tooltip(r)
    OUT.write_text(json.dumps({"_source": "CMaNGOS Classic-DB item_template (GPL-3.0)", "items": tips}, indent=0, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Classic tooltips for {len(tips)} weapons and armour")


if __name__ == "__main__":
    main()
