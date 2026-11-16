#!/usr/bin/env python3
"""Where the objects that dungeon quests use stand on the dungeon maps.

    python3 tools/build_quest_spots.py ClassicDB.sql.gz /path/to/QuestieDB

QuestieDB knows which object a quest needs (a book to read, a chest to open, a tablet to use)
but not where it stands inside a dungeon. The CMaNGOS Classic database (GPL-3.0) has every
object's spawn point; the game's own map tables (UiMapAssignment, UiMapXMapArt, UiMapArtTile,
via wago.tools) turn those into spots on the dungeon map pictures and pick the level by height.
Writes tools/quest_spots.json: [objectID] = [[instanceKey, floor, x, y], ...]. As a check, the
same is done for the bosses and compared with the positions the addon already has.
"""
import csv
import gzip
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "quest_spots.json"
WAGO = "https://wago.tools"
sys.path.insert(0, str(ROOT / "tools"))
from build_quest_text import parse_values  # noqa: E402


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BeestersDungeonMaps data build"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read().decode("utf-8")


def as_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def as_int(v):
    f = as_float(v)
    return int(f) if f is not None else None


def table(sql, name):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\) ENGINE" % name, sql, re.S)
    if not m:
        return []
    cols = re.findall(r"^\s*`(\w+)`", m.group(1), re.M)
    rows = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n" % name, sql, re.S):
        rows += [dict(zip(cols, r)) for r in parse_values(m.group(1))]
    return rows


def wago_tables(names):
    """The map tables of a client whose dungeons are still the classic ones: Wrath of the Lich
    King Classic (3.4). Later Classic clients have the Cataclysm and Mists rebuilds (Shadowfang
    Keep, the Deadmines, Scarlet Monastery, Scholomance), and Classic Era's copy of the table is
    nearly empty."""
    builds = json.loads(fetch(WAGO + "/api/builds"))
    candidates = []
    for product, versions in builds.items():
        for v in versions:
            if str(v.get("version", "")).startswith("3.4."):
                candidates.append((product, v["version"]))
    candidates.sort(key=lambda pv: [int(x) for x in pv[1].split(".")], reverse=True)
    for product, build in candidates[:4]:
        out = {}

        for name in names:
            out[name] = list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{name}/csv?build={build}"))))
        print(f"{product} {build}: " + ", ".join(f"{n} {len(r)} rows" for n, r in out.items()))
        if len(out["UiMapAssignment"]) > 1000:
            return product, build, out
    sys.exit("No build with the map tables found")


def quest_objects(qdb):
    """Objects the addon's dungeon quests use: objective objects, objects that drop an
    objective item, and objects that start or end a quest. {objectID: name}."""
    from build_quests import load_questiedb, to_py, field, ids, Q_STARTED_BY, Q_FINISHED_BY, Q_OBJECTIVES
    text = (ROOT / "BeestersDungeonMaps" / "Data" / "Quests.lua").read_text(encoding="utf-8")
    qids = {int(q) for q in re.findall(r"^    \[(\d+)\] = \{\"", text, re.M)}
    lua = load_questiedb(qdb)
    quests, items, objects = (lua.eval(f"DB.{t}.entities") for t in ("Quest", "Item", "Object"))
    wanted = set()
    for qid in qids:
        e = quests[qid]
        if e is None:
            continue
        q = to_py(e)
        objectives = field(q, Q_OBJECTIVES) or []
        wanted.update(field(o, 1) for o in (field(objectives, 2) or []) if field(o, 1))
        for o in (field(objectives, 3) or []):
            it = items[field(o, 1)] if field(o, 1) else None
            if it is not None:
                wanted.update(ids(to_py(it[3])))
        for who in (field(q, Q_STARTED_BY) or [], field(q, Q_FINISHED_BY) or []):
            wanted.update(ids(field(who, 2)))
    return {oid: (objects[oid][1] if objects[oid] is not None else "") for oid in wanted if isinstance(oid, int)}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raw = Path(sys.argv[1]).read_bytes()
    sql = gzip.decompress(raw).decode("utf-8", errors="replace") if sys.argv[1].endswith(".gz") else raw.decode("utf-8", errors="replace")
    objects = quest_objects(Path(sys.argv[2]).resolve())
    print(f"{len(objects)} objects used by dungeon quests")

    # Which UiMap each of our map pictures is: the current Classic client knows the picture
    # files (the map IDs are the same in every version); the regions come from Wrath Classic.
    latest = json.loads(fetch(WAGO + "/api/builds"))["wow_classic"][0]["version"]
    t = {n: list(csv.DictReader(io.StringIO(fetch(f"{WAGO}/db2/{n}/csv?build={latest}")))) for n in ("UiMapXMapArt", "UiMapArtTile")}
    product, build, t3 = wago_tables(["UiMapAssignment"])
    t["UiMapAssignment"] = t3["UiMapAssignment"]
    tile_art = {as_int(r["FileDataID"]): as_int(r["UiMapArtID"]) for r in t["UiMapArtTile"]}
    art_maps = {}
    for r in t["UiMapXMapArt"]:
        art_maps.setdefault(as_int(r["UiMapArtID"]), set()).add(as_int(r["UiMapID"]))

    # Our map pictures: which UiMap each floor of each dungeon is.
    tiles = json.loads((ROOT / "tools" / "dungeon_maps.json").read_text(encoding="utf-8"))
    floor_of_uimap = {}
    for key, floors in tiles["maps"].items():
        for n, ft in enumerate(floors, 1):
            for art in {tile_art.get(f) for f in ft} - {None}:
                for ui in art_maps.get(art, ()):
                    floor_of_uimap[ui] = (key, n)
    for wing, (base, wing_floors) in tiles["wings"].items():
        for i, n in enumerate(wing_floors, 1):
            for ui, owner in list(floor_of_uimap.items()):
                if owner == (base, n):
                    floor_of_uimap[ui] = (wing, i)

    instances = json.loads((ROOT / "tools" / "instances.json").read_text(encoding="utf-8"))["instances"]
    maps = {info["map"] for info in instances.values() if info.get("map")}
    regions = {}
    for r in t["UiMapAssignment"]:
        ui, mp = as_int(r["UiMapID"]), as_int(r["MapID"])
        if mp in maps and ui in floor_of_uimap:
            regions.setdefault(mp, []).append(r)

    def project(mp, x, y, z):
        best = None
        for r in regions.get(mp, []):
            x0, y0, z0 = (as_float(r[f"Region_{i}"]) for i in (0, 1, 2))
            x1, y1, z1 = (as_float(r[f"Region_{i}"]) for i in (3, 4, 5))
            if not (min(x0, x1) <= x <= max(x0, x1) and min(y0, y1) <= y <= max(y0, y1)):
                continue
            if not (min(z0, z1) - 1 <= z <= max(z0, z1) + 1):
                continue
            u0, v0, u1, v1 = (as_float(r[c]) for c in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
            fx = (max(y0, y1) - y) / abs(y1 - y0) if y1 != y0 else 0
            fy = (max(x0, x1) - x) / abs(x1 - x0) if x1 != x0 else 0
            size = abs(x1 - x0) * abs(y1 - y0)
            spot = (*floor_of_uimap[as_int(r["UiMapID"])], round(u0 + fx * (u1 - u0), 3), round(v0 + fy * (v1 - v0), 3))
            if best is None or size < best[0]:  # the most specific region (a floor) wins
                best = (size, spot)
        return best and best[1]

    spots, missing = {}, []
    for row in table(sql, "gameobject"):
        oid = as_int(row.get("id"))
        if oid not in objects or as_int(row.get("map")) not in maps:
            continue
        spot = project(as_int(row["map"]), as_float(row["position_x"]), as_float(row["position_y"]), as_float(row["position_z"]))
        if spot:
            spots.setdefault(oid, []).append(list(spot))
        else:
            missing.append(oid)
    for oid in spots:
        spots[oid] = sorted({tuple(s) for s in spots[oid]})[:6]

    # Check: the bosses' spawn points against the positions the addon already shows.
    bosses_lua = (ROOT / "BeestersDungeonMaps" / "Data" / "Bosses.lua").read_text(encoding="utf-8")
    boss_npc = {int(n): name for name, n in re.findall(r'\{\d+,"((?:[^"\\]|\\.)*)",(\d+),', bosses_lua)}
    maps_lua = (ROOT / "BeestersDungeonMaps" / "Data" / "Maps.lua").read_text(encoding="utf-8")
    known = {}
    for key, body in re.findall(r'\["(\w+)"\] = \{ (\{\d+,[\d.]+,[\d.]+,\d+,".*?) \},\n', maps_lua):
        for f, x, y, _, name in re.findall(r'\{(\d+),([\d.]+),([\d.]+),(\d+),"((?:[^"\\]|\\.)*)"\}', body):
            known[(key, name)] = (int(f), float(x), float(y))
    checks = []
    for row in table(sql, "creature"):
        nid = as_int(row.get("id"))
        if nid not in boss_npc or as_int(row.get("map")) not in maps:
            continue
        spot = project(as_int(row["map"]), as_float(row["position_x"]), as_float(row["position_y"]), as_float(row["position_z"]))
        if spot and (spot[0], boss_npc[nid]) in known:
            f, x, y = known[(spot[0], boss_npc[nid])]
            checks.append((spot[0], boss_npc[nid], spot[1] == f, round(((spot[2] - x) ** 2 + (spot[3] - y) ** 2) ** 0.5, 3)))
    good = [c for c in checks if c[2] and c[3] < 0.06]
    print(f"Check against known boss positions: {len(good)} of {len(checks)} on the right level within 6% of the map")
    for c in checks:
        if c not in good:
            print("  off:", c)

    result = {"_source": f"Object spawn points: CMaNGOS Classic database (GPL-3.0). Map projection: the game's UiMapAssignment ({product} {build}, via wago.tools).",
              "objects": {str(k): {"name": objects[k], "spots": v} for k, v in sorted(spots.items())},
              "missing": sorted(set(missing))}
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: spots for {len(spots)} objects; {len(set(missing))} outside any map region")


if __name__ == "__main__":
    main()
