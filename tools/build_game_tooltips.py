#!/usr/bin/env python3
"""Build tools/game_item_tooltips.json: item tooltips made from the WoW Forever client's own tables.

    python3 tools/build_game_tooltips.py

Reads tools/game_items.json (from tools/fetch_game_items.py). The game's files hold the items
WoW Forever added or changed; for those this gives the real values, the way the game itself would
show them. Stats, armour and weapon damage are worked out the way the game does it: from the
item level, quality and slot, using the game's own budget tables.
tools/build_loot_tooltips.py prefers these over the classic-stats tooltips.
"""
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "game_items.json"
OUT = ROOT / "tools" / "game_item_tooltips.json"

QUALITY = ["9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff"]
GREEN, YELLOW, GREY = "|cff1eff00", "|cffffd100", "|cff808080"
SLOTS = {1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet",
         9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket", 13: "One-Hand", 14: "Off Hand", 15: "Ranged",
         16: "Back", 17: "Two-Hand", 18: "Bag", 19: "Tabard", 20: "Chest", 21: "Main Hand", 22: "Off Hand",
         23: "Held In Off-hand", 24: "Projectile", 25: "Thrown", 26: "Ranged", 28: "Relic"}
# Which column of the game's stat budget table a slot uses.
BUDGET_SLOT = {1: 0, 5: 0, 7: 0, 17: 0, 20: 0,
               3: 1, 6: 1, 8: 1, 10: 1, 12: 1,
               2: 2, 9: 2, 11: 2, 14: 2, 16: 2, 23: 2,
               13: 3, 21: 3, 22: 3,
               15: 4, 25: 4, 26: 4, 28: 4}
PRIMARY = {3: "Agility", 4: "Strength", 5: "Intellect", 6: "Spirit", 7: "Stamina"}
PRIMARY_ORDER = [4, 3, 5, 7, 6]  # the game lists them in this order, whatever the item data's order
SCHOOL_DAMAGE = {84: "Holy", 85: "Fire", 86: "Nature", 87: "Frost", 88: "Shadow", 89: "Arcane"}
RESIST = {51: "Fire", 52: "Frost", 53: "Holy", 54: "Shadow", 55: "Nature", 56: "Arcane"}
WEAPONS = {0: "Axe", 1: "Axe", 2: "Bow", 3: "Gun", 4: "Mace", 5: "Mace", 6: "Polearm", 7: "Sword", 8: "Sword",
           10: "Staff", 13: "Fist Weapon", 15: "Dagger", 16: "Thrown", 18: "Crossbow", 19: "Wand", 20: "Fishing Pole"}
ARMOR = {1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate", 6: "Shield", 7: "Libram", 8: "Idol", 9: "Totem"}
EQUIP_STAT = {
    38: "+{} Attack Power.",
    41: "Increases healing done by spells and effects by up to {}.",
    42: "Increases damage done by magical spells and effects by up to {}.",
    45: "Increases damage and healing done by magical spells and effects by up to {}.",
    12: "Increased Defense +{}.",
    132: "+{} Attack Power against Mechanical units.",
}
TRIGGER = {0: "Use", 1: "Equip", 2: "Chance on hit"}
CREATE_ITEM, LEARN_SPELL = 24, 36


def num(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return 0
    return int(f) if f == int(f) else f


class Data:
    def __init__(self, path):
        raw = json.loads(path.read_text(encoding="utf-8"))
        self.build = raw["build"]
        self.t = {name: [dict(zip(t["columns"], r)) for r in t["rows"]] for name, t in raw["tables"].items()}

    def by(self, table, key="ID", many=False):
        out = {}
        for r in self.t.get(table, []):
            k = num(r.get(key))
            if many:
                out.setdefault(k, []).append(r)
            else:
                out[k] = r
        return out


def fmt(n):
    n = round(n, 1)
    return str(int(n)) if n == int(n) else str(n)


def duration_text(ms):
    s = ms / 1000
    if s >= 3600 and s % 3600 == 0:
        return "1 hour" if s == 3600 else f"{int(s // 3600)} hrs"
    if s >= 60 and s % 60 == 0:
        return f"{int(s // 60)} min"
    if s >= 60:
        return f"{fmt(s / 60)} min"
    return f"{fmt(s)} sec"


class Builder:
    def __init__(self, data):
        self.d = data
        self.sparse = data.by("ItemSparse")
        self.item = data.by("Item")
        self.links = data.by("ItemXItemEffect", "ItemID", many=True)
        self.effect = data.by("ItemEffect")
        self.spell_text = data.by("Spell")
        self.spell_name = data.by("SpellName")
        self.spell_eff = data.by("SpellEffect", "SpellID", many=True)
        self.misc = data.by("SpellMisc", "SpellID")
        self.aura = data.by("SpellAuraOptions", "SpellID")
        self.cooldown = data.by("SpellCooldowns", "SpellID")
        self.durations = data.by("SpellDuration")
        self.radius = data.by("SpellRadius")
        self.budget = data.by("RandPropPoints")
        self.subclass = {(num(r["ClassID"]), num(r["SubClassID"])): r for r in data.t.get("ItemSubClass", [])}
        self.skill = data.by("SkillLine")
        self.classes = data.by("ChrClasses")
        self.limit = data.by("ItemLimitCategory")
        self.unknown = 0

    # --- spells -------------------------------------------------------------------------
    def effects(self, spell):
        return sorted(self.spell_eff.get(spell, []), key=lambda e: num(e["EffectIndex"]))

    def effect_value(self, spell, index, kind, math_only=False):
        effs = self.effects(spell)
        if index - 1 >= len(effs):
            return None
        e = effs[index - 1]
        bp = num(e["EffectBasePointsF"])
        if num(e.get("EffectRealPointsPerLevel")):
            return None  # grows with the player's level: no single number to show
        if kind in ("s", "m", "M"):
            var = num(e.get("Variance"))
            if kind == "s" and var and not math_only:
                return f"{fmt(abs(bp) * (1 - var / 2))} to {fmt(abs(bp) * (1 + var / 2))}"
            return abs(bp)
        if kind == "t":
            return num(e["EffectAuraPeriod"]) / 1000
        if kind == "o":
            period = num(e["EffectAuraPeriod"])
            dur = self.duration_ms(spell)
            if not period and num(e["EffectAura"]) in (84, 85) and dur:
                # Food and drink: WoW Forever shows base x seconds / 5.2 (checked on 8 items).
                return int(math.floor(abs(bp) * dur / 1000 / 5.2 + 0.5))
            return abs(bp) * (dur // period) if period and dur else None
        if kind == "a":
            r = self.radius.get(num(e["EffectRadiusIndex_0"]))
            return num(r["Radius"]) if r else None
        if kind == "x":
            return num(e["EffectChainTargets"])
        return None

    def duration_ms(self, spell):
        m = self.misc.get(spell)
        d = self.durations.get(num(m["DurationIndex"])) if m else None
        return num(d["Duration"]) if d else 0

    def spell_var(self, spell, kind, index, math_only=False):
        if kind == "proccooldown":
            a = self.aura.get(spell)
            return num(a["ProcCategoryRecovery"]) / 1000 if a and num(a["ProcCategoryRecovery"]) else None
        if kind in "smMtoax":
            return self.effect_value(spell, index or 1, kind, math_only)
        if kind == "d":
            ms = self.duration_ms(spell)
            if ms <= 0:
                return None
            return ms / 1000 if math_only else duration_text(ms)
        if kind in "hH":
            a = self.aura.get(spell)
            return num(a["ProcChance"]) if a else None
        if kind == "u":
            a = self.aura.get(spell)
            return num(a.get("CumulativeAura")) if a else None
        if kind == "n":
            a = self.aura.get(spell)
            return num(a.get("ProcCharges")) if a else None
        if kind == "i":
            return None
        return None

    def describe(self, spell):
        row = self.spell_text.get(spell)
        text = (row or {}).get("Description_lang") or ""
        if not text:
            return ""
        # $g male:female; and $l singular:plural; -> first form
        text = re.sub(r"\$[gG]([^:;]*):([^;]*);", r"\1", text)
        text = re.sub(r"\$[lL]([^:;]*):([^;]*);", r"\2", text)

        def expr(m):
            body = m.group(1)

            def inner(v):
                val = self.spell_var(num(v.group(1)) or spell, v.group(2), num(v.group(3)) or 1, math_only=True)
                if val is None or isinstance(val, str):
                    raise ValueError
                return str(val)
            try:
                e = re.sub(r"\$(\d*)([a-zA-Z])(\d?)", inner, body)
                if not re.fullmatch(r"[\d.+\-*/() ]+", e):
                    raise ValueError
                value = eval(e)  # noqa: S307 - digits and operators only
                return f"{value:.{m.group(2)}f}" if m.group(2) else str(int(math.floor(value + 0.5)))
            except (ValueError, ZeroDivisionError, SyntaxError):
                raise LookupError

        def proc_cooldown(m):
            val = self.spell_var(spell, "proccooldown", 0)
            if not val:
                raise LookupError
            return fmt(val)

        def divide(m):
            val = self.spell_var(num(m.group(2)) or spell, m.group(3), num(m.group(4)) or 1, math_only=True)
            if val is None or isinstance(val, str):
                raise LookupError
            return fmt(val / num(m.group(1)))

        def var(m):
            val = self.spell_var(num(m.group(1)) or spell, m.group(2), num(m.group(3)) or None)
            if val is None:
                raise LookupError
            return val if isinstance(val, str) else fmt(val)
        try:
            text = re.sub(r"\$\{([^}]*)\}(?:\.(\d))?", expr, text)
            text = re.sub(r"\$/(\d+);(\d*)([smMtoa])(\d?)", divide, text)
            text = re.sub(r"\$proccooldown", proc_cooldown, text)
            text = re.sub(r"\$(\d*)([smMtoadhHunxi])(\d?)", var, text)
        except LookupError:
            return None  # a placeholder we can't fill: leave the line out rather than show "$s1"
        if "$" in text:
            return None
        lines = [re.sub(r"[ \t]+", " ", l).strip() for l in text.replace("\r", "").split("\n")]
        return "\n".join(l for l in lines if l)

    def cooldown_text(self, effect):
        ms = num(effect.get("CoolDownMSec")) if effect else 0
        if ms <= 0:
            ms = num(effect.get("CategoryCoolDownMSec")) if effect else 0
        if ms <= 1500:  # the global cooldown: the game doesn't list it
            return ""
        s = ms / 1000
        if s >= 3600:
            t = f"{fmt(s / 3600)} Hour" + ("s" if s != 3600 else "")
        elif s >= 60:
            t = f"{fmt(s / 60)} Min"
        else:
            t = f"{fmt(s)} Sec"
        return f" ({t} Cooldown)"

    # --- item maths ---------------------------------------------------------------------
    def stat_amount(self, s, alloc):
        ilvl, q, inv = num(s["ItemLevel"]), num(s["OverallQualityID"]), num(s["InventoryType"])
        row, slot = self.budget.get(ilvl), BUDGET_SLOT.get(inv)
        if not row or slot is None:
            return None
        tier = "Epic" if q >= 4 else "Superior" if q == 3 else "Good"
        points = num(row.get(f"{tier}_{slot}"))
        return int(math.floor(alloc * points * 0.0001 + 0.5))

    def armor(self, s, it):
        ilvl, q, inv = num(s["ItemLevel"]), num(s["OverallQualityID"]), num(s["InventoryType"])
        cls, sub = num(it["ClassID"]), num(it["SubclassID"])
        if cls != 4:
            return 0
        if sub == 6:
            r = next((r for r in self.d.t.get("ItemArmorShield", []) if num(r["ItemLevel"]) == ilvl), None)
            return int(math.floor(num(r[f"Quality_{q}"]) + 0.5)) if r else 0
        if sub not in (1, 2, 3, 4) and inv != 16:
            return 0
        total = next((r for r in self.d.t.get("ItemArmorTotal", []) if num(r["ItemLevel"]) == ilvl), None)
        qual = next((r for r in self.d.t.get("ItemArmorQuality", []) if num(r["ID"]) == ilvl), None)
        loc = next((r for r in self.d.t.get("ArmorLocation", []) if num(r["ID"]) == (5 if inv == 20 else inv)), None)
        if not (total and qual and loc):
            return 0
        if inv == 16:  # cloaks count as cloth
            sub = 1
        material = ["", "Cloth", "Leather", "Mail", "Plate"][sub]
        modifier = ["", "Clothmodifier", "Leathermodifier", "Chainmodifier", "Platemodifier"][sub]
        return int(math.floor(num(total[material]) * num(loc[modifier]) * num(qual[f"Qualitymod_{q}"]) + 0.5))

    def damage(self, s, it):
        if num(it["ClassID"]) != 2 or not num(s["ItemDelay"]):
            return None
        ilvl, q, inv, sub = num(s["ItemLevel"]), num(s["OverallQualityID"]), num(s["InventoryType"]), num(it["SubclassID"])
        caster = bool(num(s["Flags_1"]) & 0x200)
        if sub == 19:
            table = "ItemDamageWand"
        elif sub == 16:
            table = "ItemDamageThrown"
        elif inv in (15, 26):
            table = "ItemDamageRanged"
        elif inv == 17:
            table = "ItemDamageTwoHandCaster" if caster else "ItemDamageTwoHand"
        else:
            table = "ItemDamageOneHandCaster" if caster else "ItemDamageOneHand"
        row = next((r for r in self.d.t.get(table, []) if num(r["ItemLevel"]) == ilvl), None)
        if not row:
            return None
        delay = num(s["ItemDelay"]) / 1000
        dps = num(row[f"Quality_{q}"])
        avg = dps * delay
        var = num(s["DmgVariance"])
        low = int(math.floor(avg * (1 - var / 2)))
        high = int(math.floor(avg * (1 + var / 2) + 0.5))
        return low, high, delay

    # --- tooltip ------------------------------------------------------------------------
    def kind(self, it, inv):
        cls, sub = num(it["ClassID"]), num(it["SubclassID"])
        if cls == 2:
            return WEAPONS.get(sub, "")
        if cls == 4 and inv != 16:
            return ARMOR.get(sub, "")  # "Miscellaneous" armour (rings, trinkets, held items) has none
        return ""

    def tooltip(self, item_id, nested=False):
        s, it = self.sparse.get(item_id), self.item.get(item_id)
        if not s or not it:
            return None
        q = num(s["OverallQualityID"])
        inv = num(s["InventoryType"])
        lines = [f"|cff{QUALITY[min(q, 7)]}{s['Display_lang']}|r"]
        if not nested:
            lines += {1: ["Binds when picked up"], 2: ["Binds when equipped"], 3: ["Binds when used"],
                      4: ["Quest Item"]}.get(num(s["Bonding"]), [])
        else:
            lines += {1: ["Binds when picked up"], 2: ["Binds when equipped"], 3: ["Binds when used"]}.get(num(s["Bonding"]), [])
        maxcount, limit = num(s["MaxCount"]), self.limit.get(num(s["LimitCategory"]))
        if maxcount == 1:
            lines.append("Unique")
        elif maxcount > 1:
            lines.append(f"Unique ({maxcount})")
        elif num(s["Flags_0"]) & 0x80000 or (limit and num(limit["Quantity"]) and num(limit["Flags"]) & 1):
            lines.append("Unique-Equipped")
        if num(s["Flags_1"]) & 0x80000000:
            lines.append("Crafting Reagent")
        if num(s["ContainerSlots"]):
            bag = self.subclass.get((1, num(it["SubclassID"]))) if num(it["SubclassID"]) else None
            lines.append(f"{num(s['ContainerSlots'])} Slot {(bag or {}).get('DisplayName_lang') or 'Bag'}")
        if num(s["StartQuestID"]):
            lines.append("This Item Begins a Quest")
        slot, kind = SLOTS.get(inv), self.kind(it, inv)
        if slot and inv != 18:
            lines.append(slot + (f"\t{kind}" if kind else ""))
        dmg = self.damage(s, it)
        if dmg:
            low, high, delay = dmg
            lines.append(f"{low} - {high} Damage\tSpeed {delay:.2f}")
            lines.append(f"({(low + high) / 2 / delay:.1f} damage per second)")
        armor = self.armor(s, it)
        if armor:
            lines.append(f"{armor} Armor")
        equip_lines, power, bonus_armor, primary = [], {}, 0, {}
        for k in range(10):
            stat, alloc = num(s[f"StatModifier_bonusStat_{k}"]), num(s[f"StatPercentEditor_{k}"])
            if stat in (-1,) or not alloc:
                continue
            amount = self.stat_amount(s, alloc)
            if amount is None:
                continue
            if stat in PRIMARY:
                primary[stat] = amount
            elif stat in SCHOOL_DAMAGE:
                equip_lines.append(f"{GREEN}Equip: Increases damage done by {SCHOOL_DAMAGE[stat]} spells and effects by up to {amount}.|r")
            elif stat == 50:
                bonus_armor = amount
            elif stat in RESIST:
                lines.append(f"+{amount} {RESIST[stat]} Resistance")
            elif stat in (41, 42):
                power[stat] = amount
            elif stat in EQUIP_STAT:
                equip_lines.append(f"{GREEN}Equip: {EQUIP_STAT[stat].format(amount)}|r")
            else:
                self.unknown += 1
                equip_lines.append(None)  # unknown stat: the tooltip would be incomplete
        if None in equip_lines:
            return None
        resist = [l for l in lines if l.endswith(" Resistance")]
        lines = [l for l in lines if not l.endswith(" Resistance")]
        lines += [f"{primary[k]:+d} {PRIMARY[k]}" for k in PRIMARY_ORDER if k in primary] + resist
        if bonus_armor:
            lines.append(f"+{bonus_armor} Armor")
        if 41 in power and 42 in power:
            equip_lines.insert(0, f"{GREEN}Equip: Increases healing done by up to {power[41]} and damage done by up to "
                                  f"{power[42]} for all magical spells and effects.|r")
        else:
            equip_lines[:0] = [f"{GREEN}Equip: {EQUIP_STAT[k].format(v)}|r" for k, v in power.items()]
        cls = num(s["AllowableClass"])
        if cls not in (-1, 0) and self.classes:
            names = [r["Name_lang"] for cid, r in sorted(self.classes.items()) if cid and cls & (1 << (cid - 1))]
            if names and len(names) < 9:
                lines.append("Classes: " + ", ".join(names))
        requires = []
        if num(s["RequiredLevel"]) > 1:
            requires.append(f"Requires Level {num(s['RequiredLevel'])}")
        ability = self.spell_name.get(num(s["RequiredAbility"]))
        if ability:
            lines.insert(1, f"Requires {ability['Name_lang']}")
        skill = self.skill.get(num(s["RequiredSkill"]))
        if skill:
            requires.append(f"Requires {skill['DisplayName_lang']} ({num(s['RequiredSkillRank'])})")
        head = lines
        lines = []
        created, teaches, charges, learn = None, [], 0, False
        for link in self.links.get(item_id, []):
            eff = self.effect.get(num(link["ItemEffectID"]))
            if not eff:
                continue
            spell, trigger = num(eff["SpellID"]), num(eff["TriggerType"])
            if abs(num(eff["Charges"])) > 1:
                charges = abs(num(eff["Charges"]))
            if trigger == 6:  # the spell the item teaches: what it makes, or what it does
                made = [num(e["EffectItemType"]) for e in self.effects(spell)
                        if num(e["Effect"]) == CREATE_ITEM and num(e["EffectItemType"])]
                if made:
                    created = made[0]
                text = self.describe(spell)
                if text:  # left out if it has a value we can't work out
                    teaches += text.split("\n")
                continue
            if any(num(e["Effect"]) == LEARN_SPELL for e in self.effects(spell)):
                learn = True  # "Learning": the item's own description says what it teaches
                continue
            text = self.describe(spell)
            if text is None:
                return None
            if text and trigger in TRIGGER:
                parts = text.split("\n")
                parts[0] = f"{TRIGGER[trigger]}: {parts[0]}"
                parts[-1] += self.cooldown_text(eff) if trigger == 0 else ""
                lines += [f"{GREEN}{part}|r" for part in parts]
        desc = s.get("Description_lang") or ""
        if desc:
            if learn:
                lines.append(f"Use: {desc}")
            else:
                lines.append(f'{YELLOW}"{desc}"|r')
        lines += teaches
        if charges:
            lines.append(f"{charges} Charges")
        if num(s["PageID"]):
            lines.append("<Right Click to Read>")
        elif num(s["LockID"]):
            lines.append("Locked")
        elif num(s["Flags_0"]) & 0x4:
            lines.append("<Right Click to Open>")
        sub = self.tooltip(created, nested=True) if created and not nested else None
        if sub:
            # A recipe, the way the game shows it: the item it makes, then what it teaches and needs.
            return head + [" "] + sub + lines + requires
        return head + requires + equip_lines + lines


def main():
    data = Data(SRC)
    b = Builder(data)
    bosses = (ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua").read_text(encoding="utf-8").split("ns.BossLoot = {")[1]
    wanted = {int(i) for body in re.findall(r"^    \[\d+\] = \{([\d,]+)\}", bosses, re.M) for i in body.split(",")}
    tips = {}
    for item_id in sorted(wanted):
        lines = b.tooltip(item_id)
        if lines:
            tips[str(item_id)] = lines
    OUT.write_text(json.dumps({"_source": f"WoW Forever client tables, build {data.build} (via wago.tools)",
                               "items": tips}, indent=0, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Game tooltips for {len(tips)} items ({b.unknown} stats of unknown kinds skipped their item)")


if __name__ == "__main__":
    main()
