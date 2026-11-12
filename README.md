<p align="center"><img src="docs/logo-256.png" width="160" alt="Beester's Dungeon Maps logo"></p>

# Beester's Dungeon Maps

An addon for World of Warcraft: Forever. It puts dungeon and raid entrances on your world map, gives every dungeon a map with its bosses and their loot, and lists the dungeon's quests next to that map.

It's built to look like part of the game: the world map's own pins and menus, the game's tooltips, the quest log's layout and the game's Settings window.

## What it does

**On the world map**
- Dungeon and raid entrances on zone and continent maps. Hover one for its level range, and whether it's new in Forever. Blackrock Mountain shows both Blackrock Depths and Blackrock Spire.
- A **Dungeons** menu in the map's top bar (World › Kalimdor › Durotar › Dungeons) to open any dungeon in the zone you're looking at.
- The newest Forever dungeons (The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace) have entrances too. There's no map of them yet, so their page shows a "Work in progress" notice with their bosses and quests. The two Hyjal raids are listed as "coming soon".

**Minimap button**
- Click it for a list of every dungeon and raid. Your dungeons (within 5 levels of you) are pinned on top; the rest scrolls underneath, by level band, raids last. Levels are coloured by difficulty for you, like quest titles.
- Click a dungeon to open its map. A dungeon that's "coming soon" opens its zone, so you know where to find it.
- Drag the button around the minimap, right-click it for the options, or hide it there. `/bdm list` opens the list too.

**Dungeon maps**
- Opens by itself when you open your map inside a dungeon, or click an entrance.
- The classic dungeon maps that still ship with the game, and Santiago Reyes's maps for the new Forever dungeons.
- Each boss has a pin with its portrait. Hover it for the boss's loot (Bind on Pickup, Uncommon and better, sorted into gear, recipes and other). Click to keep the loot list open.
- Multi-level dungeons have a floor menu that shows how many bosses are on each level.
- A boss without a known position is listed in the corner. Shift-drag it onto the map to place it yourself; shift-right-click your pin to undo.
- Dungeons whose data is still thin (no map yet, or bosses without a position or loot) show a "Work in progress" tag. Hover it to see what's missing.

**Dungeon quests**
- The dungeon's quests in a tab next to its map, in the quest log's own style: the ones you have, the ones you can still pick up and where, and the ones that start inside.
- Quest chains fold to the step you're on. Click a quest for its text, objectives and rewards, share it with your group, or show it on the map.
- A Horde/Alliance switch, so you can see the other side's quests too.

**Item tooltips**
- When the game hasn't loaded an item yet, the addon shows its own copy of the tooltip until the game's arrives: built from the game's own files for items new in Forever, and from classic item stats (marked as such) for the rest.

## Installing

The easiest way is the CurseForge app: search for **Beester's Dungeon Maps** and pick WoW Forever.

To install by hand:
1. Download `BeestersDungeonMaps-<version>.zip` from the [Releases page](../../releases).
2. Open your World of Warcraft folder and go to `_forever_\Interface\AddOns`.
   (Usually `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.)
3. Unzip the file there. You should now have a folder called `BeestersDungeonMaps` inside `AddOns`.
4. Start the game. On the character screen, click **AddOns** and make sure **Beester's Dungeon Maps** is ticked.

To update by hand, delete the old `BeestersDungeonMaps` folder first, then unzip the new one. Your settings are kept.

## Commands

- `/bdm` opens the options. If another addon already uses `/bdm`, use `/beesterdm`.
- `/bdm map` opens the map of the dungeon you're in.
- `/bdm list` opens the list of all dungeons and raids.
- `/bdm status` prints the addon, game and data versions and the map you're on. Please include it when you report a problem.

Right-click a dungeon map to go back to the normal map.

## Works with Questie

You don't need Questie, and the two run side by side. The addon carries its own small copy of the quest data it needs, built from QuestieDB, and doesn't touch Questie's frames or settings. If you do see an error with both installed, please [open an issue](../../issues) with the error text.

## Language

English only for now. Item names show in your game's language once the game has loaded them; everything else is in English.

## Data and credits

- **Entrances and dungeon quests:** [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), Forever data, with all its corrections applied.
- **Quest text and rewards:** the [CMaNGOS Classic database](https://github.com/cmangos/classic-db) (GPL-3.0). Quests new in Forever aren't in it yet and show QuestieDB's objective line instead. Quest text is © Blizzard Entertainment.
- **Bosses:** the WoW Forever client's own encounter list, read from [wago.tools](https://wago.tools), checked by hand against the game. Loot from QuestieDB, the CMaNGOS Classic database, and hand-checked lists for the new Forever bosses.
- **Item tooltips:** the WoW Forever client's own item tables, read from [wago.tools](https://wago.tools); classic item stats from the CMaNGOS Classic database for items Forever didn't change.
- **Maps of the old dungeons:** the classic dungeon map images that still ship with the game. The addon only refers to them; it doesn't include them.
- **Maps of the new Forever dungeons:** Santiago Reyes (Atlas de Azeroth: Forever), used with permission.
- **Boss positions:** the Dungeon Journal's positions for the same map images (retail, and Cataclysm Classic for dungeons that were rebuilt later), plus positions players placed in game.

A GitHub Action refreshes all of this every day until 23 December 2026, then every Monday, and publishes a new release when the data the addon loads has changed. `docs/AUDIT.md` shows, per dungeon, what's placed and what's missing.

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. This addon isn't made or endorsed by Blizzard.

## For developers

The addon itself is plain Lua in `BeestersDungeonMaps/`. Everything in `BeestersDungeonMaps/Data/` is generated by the scripts in `tools/`:

```
python3 tools/build_data.py /path/to/QuestieDB         # entrances and instance list  -> Data/Entrances.lua
python3 tools/build_quests.py /path/to/QuestieDB       # dungeon quests (needs lupa)   -> Data/Quests.lua
python3 tools/get_classicdb.py /tmp/classicdb.sql.gz   # download the Classic database
python3 tools/build_quest_text.py /tmp/classicdb.sql.gz --questiedb /path/to/QuestieDB  # -> Data/QuestText.lua
python3 tools/build_bosses.py /path/to/QuestieDB       # bosses and loot (reads wago.tools) -> Data/Bosses.lua
python3 tools/fetch_game_items.py                      # the game's item tables (wago.tools)
python3 tools/build_game_tooltips.py                   # tooltips from those tables
python3 tools/build_loot_tooltips.py                   # -> Data/LootTooltips.lua
python3 tools/build_maps.py                            # dungeon maps and boss positions (needs numpy, pillow) -> Data/Maps.lua
python3 tools/audit.py                                 # -> docs/AUDIT.md
pip install lupa && python3 tools/test_addon.py        # run the checks
./tools/package.sh                                     # build the zip into dist/
```

Releasing: bump `## Version` in `BeestersDungeonMaps.toc`, add a section to `CHANGELOG.md`, and merge to `main`. The release workflow tags it, builds the zip, publishes the GitHub release and uploads it to CurseForge (as beta below 1.0).

## License

GNU General Public License v3.0. See `LICENSE`.
