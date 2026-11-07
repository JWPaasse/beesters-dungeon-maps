#!/usr/bin/env python3
"""Download the WoW Forever client's item tables from wago.tools, kept to the bosses' loot.

    python3 tools/fetch_game_items.py

The game ships item data in its own files (DB2 tables); wago.tools publishes them per build.
This keeps the rows the loot tooltips need and writes tools/game_items.json:
    {"build": ..., "tables": {name: {"columns": [...], "rows": [[...], ...]}}, "errors": {...}}
Kept: the loot items, the items their recipes make, the spells behind their Use:/Equip: lines
(and spells those texts refer to), and small lookup tables (stat budgets, weapon damage and
armour per item level, durations, skills, item types) whole.
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

WHOLE = [
    "ItemDamageOneHand", "ItemDamageOneHandCaster", "ItemDamageTwoHand", "ItemDamageTwoHandCaster",
    "ItemDamageAmmo", "ItemDamageRanged", "ItemDamageThrown", "ItemDamageWand",
    "ItemArmorQuality", "ItemArmorShield", "ItemArmorTotal", "ArmorLocation",
    "RandPropPoints", "DurabilityQuality", "DurabilityCosts",
    "ItemClass", "ItemSubClass", "SkillLine", "ItemLimitCategory",
    "SpellDuration", "SpellRadius", "ChrClasses",
]
BY_SPELL = ["SpellEffect", "SpellMisc", "SpellAuraOptions", "SpellCooldowns", "SpellCategories"]
CREATE_ITEM = 24
SPELL_REF = re.compile(r"\$(\d{2,})[a-zA-Z]")


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read().decode("utf-8")


def loot_ids():
    loot = BOSSES.read_text(encoding="utf-8").split("ns.BossLoot = {")[1]
    return {int(i) for body in re.findall(r"^    \[\d+\] = \{([\d,]+)\}", loot, re.M) for i in body.split(",")}


def as_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def main():
    build = json.loads(fetch(WAGO + "/api/builds"))["wowf"][0]["version"]
    errors = {}
    tables = {}

    def get(name):
        try:
            rows = list(csv.reader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
            tables[name] = (rows[0], rows[1:])
            print(f"{name}: {len(rows) - 1} rows")
        except (urllib.error.URLError, OSError, ValueError, IndexError) as err:
            errors[name] = str(err)
            print(f"{name}: {err}")

    for name in ["ItemSparse", "Item", "ItemXItemEffect", "ItemEffect", "Spell", "SpellName"] + BY_SPELL + WHOLE:
        get(name)
    if "ItemSparse" not in tables:
        sys.exit("ItemSparse could not be downloaded")

    def index(name, key):
        columns, rows = tables.get(name, ([], []))
        if key not in columns:
            return {}
        c = columns.index(key)
        out = {}
        for r in rows:
            out.setdefault(as_int(r[c]), []).append(r)
        return out

    def value(name, row, key):
        columns = tables[name][0]
        return row[columns.index(key)] if key in columns else None

    effects_of_item = index("ItemXItemEffect", "ItemID")
    effect_by_id = index("ItemEffect", "ID")
    spell_effects = index("SpellEffect", "SpellID")
    spell_text = index("Spell", "ID")

    items, spells = loot_ids(), set()
    while True:
        before = (len(items), len(spells))
        for item in list(items):
            for link in effects_of_item.get(item, []):
                for eff in effect_by_id.get(as_int(value("ItemXItemEffect", link, "ItemEffectID")), []):
                    spells.add(as_int(value("ItemEffect", eff, "SpellID")))
        for spell in list(spells):
            for eff in spell_effects.get(spell, []):
                if as_int(value("SpellEffect", eff, "Effect")) == CREATE_ITEM:
                    items.add(as_int(value("SpellEffect", eff, "EffectItemType")))
                spells.add(as_int(value("SpellEffect", eff, "EffectTriggerSpell")))
            for row in spell_text.get(spell, []):
                spells.update(int(m) for m in SPELL_REF.findall(value("Spell", row, "Description_lang") or ""))
        spells -= {None, 0}
        items -= {None, 0}
        if (len(items), len(spells)) == before:
            break

    # Items that need a skill specialisation ("Requires Master Axesmith"): the spell's name.
    columns, rows = tables["ItemSparse"]
    if "RequiredAbility" in columns:
        c = columns.index("RequiredAbility")
        spells |= {as_int(r[c]) for r in rows if as_int(r[0]) in items} - {None, 0}

    result = {"_source": f"WoW Forever client tables, build {build} (via wago.tools), kept to the bosses' loot.",
              "build": build, "tables": {}, "errors": errors}
    effect_ids = {as_int(value("ItemXItemEffect", r, "ItemEffectID"))
                  for i in items for r in effects_of_item.get(i, [])}
    keep = {
        "ItemSparse": ("ID", items), "Item": ("ID", items), "ItemXItemEffect": ("ItemID", items),
        "ItemEffect": ("ID", effect_ids), "Spell": ("ID", spells), "SpellName": ("ID", spells),
        **{name: ("SpellID", spells) for name in BY_SPELL},
    }
    for name, (columns, rows) in tables.items():
        if name in keep:
            key, wanted = keep[name]
            c = columns.index(key) if key in columns else None
            rows = [r for r in rows if c is not None and as_int(r[c]) in wanted]
        result["tables"][name] = {"columns": columns, "rows": rows}

    OUT.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: {len(items)} items, {len(spells)} spells; {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
