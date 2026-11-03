<p align="center"><img src="docs/logo-256.png" width="160" alt="Beester's Dungeon Maps logo"></p>

# Beester's Dungeon Maps

A World of Warcraft: Forever addon that puts dungeon and raid entrances on your world map, shows dungeon maps with their bosses, and lists every dungeon's quests in the map's quest panel.

It is built to look and feel like the game's own interface: it uses the world map's own pin system, the game's tooltips and the game's Settings window.

## Status

**Version 0.1.0 (first test build):** dungeon and raid entrance pins on zone and continent maps, with tooltips, plus an options panel.

Coming next:
- Dungeon maps (Classic's own maps for the old dungeons, Santiago Reyes's maps for the new ones)
- Boss pins on dungeon maps
- The dungeon quest panel and quest details
- Browsing dungeons from the map's breadcrumb menus

## Installing

1. Download `BeestersDungeonMaps-<version>.zip` from the [Releases page](../../releases).
2. Open your World of Warcraft folder and go to `_forever_\Interface\AddOns`.
   (Usually `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`.)
3. Unzip the file there. You should now have a folder called `BeestersDungeonMaps` inside `AddOns`.
4. Start the game. On the character screen, click **AddOns** and make sure **Beester's Dungeon Maps** is ticked.

To update: delete the old `BeestersDungeonMaps` folder, then unzip the new one. Your settings are kept.

## Using it

- Open your world map: dungeon and raid entrances show on zone and continent maps. Hover one for its level range.
- `/bdm` opens the options. If another addon already uses `/bdm`, use `/beesterdm`.
- `/bdm status` prints the game version, the data version and the map you are on. Handy when reporting a problem.

## Works with Questie

Beester's Dungeon Maps does not need Questie and does not read Questie while you play. It ships its own small copy of the data it needs, built from QuestieDB. It does not change Questie's frames or settings, so the two can run side by side. If you do see an error with both installed, please open an issue with the error text.

## Data and credits

- Entrance coordinates: [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), Forever data. `tools/build_data.py` turns it into `BeestersDungeonMaps/Data/Entrances.lua`. A GitHub Action rebuilds it every day until December 23, 2026, then every Monday, and publishes a new release whenever the data changed.
- Instance list and level ranges: `tools/instances.json` (our own). New Forever dungeons missing from QuestieDB are listed there.
- Dungeon maps for the new Forever dungeons: Santiago Reyes (watermarked, used with permission). Coming in a later version.

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. This addon is not made or endorsed by Blizzard.

## For developers

```
python3 tools/build_data.py /path/to/QuestieDB   # rebuild data
pip install lupa && python3 tools/test_addon.py  # run the checks
./tools/package.sh                               # build the zip into dist/
```

## License

GNU General Public License v3.0. See `LICENSE`.
