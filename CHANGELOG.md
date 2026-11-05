# Changelog

## 0.2.0 (test build)

- Dungeon maps. WoW Forever has no maps inside dungeons; the addon now shows one in the Map & Quest Log window:
  - the classic dungeon maps for all 22 old dungeons and raids (the images are still in the game files, the game just doesn't use them any more)
  - Santiago Reyes's maps for Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran (both floors), with his permission
- Opens by itself when you open your map inside a dungeon, when you click an entrance on the map, or from the map's top bar: World › Kalimdor › Durotar › Dungeons.
- Boss icons on the map in the game's own skull style, with the boss's place in the dungeon and its loot in the tooltip. Positions come from the Dungeon Journal; bosses without a known position are listed in a corner of the map.
- Floor picker for dungeons with several levels (Scarlet Monastery wings, Blackrock Spire, Dire Maul, ...).
- Right-click the dungeon map, or click a name in the top bar, to go back to the normal map.
- Entrance icons are bigger by default (32 instead of 24) and are drawn above the big city badges, so Ragefire Chasm now shows on Durotar.
- New options: open the dungeon map automatically inside dungeons, list dungeons in the map's top bar.
- `/bdm map` opens the map of the dungeon you're in.

## 0.1.1

- Fixed: opening the world map gave a Lua error (`Blizzard_MapCanvas.lua:309: assertion failed`) and no entrance pins showed. Found by testing in the UIForever simulator.
- Entrances inside capital cities now also show on the zone around them: Ragefire Chasm on Durotar, Ruins of Lordaeron on Tirisfal Glades, The Stockade on Elwynn Forest.

## 0.1.0 (first test build)

- Dungeon and raid entrance pins on zone and continent maps, using the world map's own pin system.
- Tooltips with name, type, level range and a "New in WoW Forever" line.
- Addon icon in the AddOns list and on the options page.
- Options in the game's Settings window: show dungeons, show raids, show on continent maps, entrance icon size.
- `/bdm` (or `/beesterdm` if another addon uses `/bdm`) opens the options; `/bdm status` prints version and map information; `/bdm probe` checks what the game supports.
- Entrance data from QuestieDB (Forever): 26 instances, including Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran.
- Not yet in the data: The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Barrow Deeps and Forever's Hyjal Summit.
