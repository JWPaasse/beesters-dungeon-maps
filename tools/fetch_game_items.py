#!/usr/bin/env python3
"""Download the WoW Forever client's item tables from wago.tools, kept to the bosses' loot.

    python3 tools/fetch_game_items.py

The game ships every item's data in its own files (DB2 tables); wago.tools publishes them per
build. This keeps the rows the loot tooltips need and writes tools/game_items.json:
    {"build": ..., "tables": {name: {"columns": [...], "rows": [[...], ...]}}, "errors": {...}}
Small lookup tables (weapon damage and armour per item level, skills, item types) are kept whole.
tools/build_game_tooltips.py turns this into tooltips.
"""
import csv
import io
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOSSES = ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua"
OUT = ROOT / "tools" / "game_items.json"
WAGO = "https://wago.tools"

# Kept whole: small tables the tooltip maths and labels need.
WHOLE = [
    "ItemDamageOneHand", "ItemDamageOneHandCaster", "ItemDamageTwoHand", "ItemDamageTwoHandCaster",
    "ItemDamageAmmo", "ItemDamageRanged", "ItemDamageThrown", "ItemDamageWand",
    "ItemArmorQuality", "ItemArmorShield", "ItemArmorTotal", "ArmorLocation",
    "ItemClass", "ItemSubClass", "SkillLine", "ItemLimitCategory",
]


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read().decode("utf-8")


def table(name, build):
    rows = list(csv.reader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
    return rows[0], rows[1:]


def loot_ids():
    loot = BOSSES.read_text(encoding="utf-8").split("ns.BossLoot = {")[1]
    return {int(i) for body in re.findall(r"^    \[\d+\] = \{([\d,]+)\}", loot, re.M) for i in body.split(",")}


def col(columns, *names):
    for n in names:
        if n in columns:
            return columns.index(n)
    return None


def as_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def main():
    build = json.loads(fetch(WAGO + "/api/builds"))["wowf"][0]["version"]
    items = loot_ids()
    result = {"_source": f"WoW Forever client tables, build {build} (via wago.tools), kept to the bosses' loot.",
              "build": build, "tables": {}, "errors": {}}

    def keep(name, columns, rows):
        result["tables"][name] = {"columns": columns, "rows": rows}
        print(f"{name}: {len(rows)} rows, {len(columns)} columns")

    def get(name):
        try:
            return table(name, build)
        except (urllib.error.URLError, OSError, ValueError) as err:
            result["errors"][name] = str(err)
            print(f"{name}: {err}")
            return None, None

    # Item effects: which spells an item uses or teaches (Use:/Equip: lines, recipes).
    spells = set()
    for name, item_cols in (("ItemEffect", ("ParentItemID",)), ("ItemXItemEffect", ("ItemID",))):
        columns, rows = get(name)
        if columns:
            c = col(columns, *item_cols)
            kept = [r for r in rows if c is not None and as_int(r[c]) in items] if c is not None else []
            keep(name, columns, kept)
    effect_ids = set()
    if "ItemXItemEffect" in result["tables"]:
        t = result["tables"]["ItemXItemEffect"]
        c = col(t["columns"], "ItemEffectID")
        effect_ids = {as_int(r[c]) for r in t["rows"]} if c is not None else set()
        columns, rows = get("ItemEffect")
        if columns:
            keep("ItemEffect", columns, [r for r in rows if as_int(r[0]) in effect_ids]
                 + result["tables"].get("ItemEffect", {}).get("rows", []))
    t = result["tables"].get("ItemEffect")
    if t:
        c = col(t["columns"], "SpellID")
        spells = {as_int(r[c]) for r in t["rows"]} - {None, 0} if c is not None else set()

    # Recipes: the item their spell creates, so the tooltip can show it like the game does.
    created = set()
    columns, rows = get("SpellEffect")
    if columns:
        cs, ci = col(columns, "SpellID"), col(columns, "EffectItemType")
        kept = [r for r in rows if as_int(r[cs]) in spells]
        keep("SpellEffect", columns, kept)
        if ci is not None:
            created = {as_int(r[ci]) for r in kept} - {None, 0}
    all_items = items | created

    for name in ("ItemSparse", "Item"):
        columns, rows = get(name)
        if columns:
            keep(name, columns, [r for r in rows if as_int(r[0]) in all_items])
    for name in ("SpellName", "Spell"):
        columns, rows = get(name)
        if columns:
            c = col(columns, "ID")
            keep(name, columns, [r for r in rows if as_int(r[c if c is not None else 0]) in spells])
    for name in WHOLE:
        columns, rows = get(name)
        if columns:
            keep(name, columns, rows)

    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: {len(items)} loot items, {len(created)} crafted items, {len(spells)} spells; "
          f"{OUT.stat().st_size // 1024} KB")
    if "ItemSparse" not in result["tables"]:
        sys.exit("ItemSparse could not be downloaded")


if __name__ == "__main__":
    main()
