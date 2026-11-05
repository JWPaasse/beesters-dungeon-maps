# Changelog

## 0.2.4

- Quest details show experience and money as reward buttons, like the game's quest log. Experience, money and items come from the game itself whenever it has them, so they match what the game shows you.
- Boss positions for Ruins of Lordaeron.
- Boss names as you see them in game: The Baron (was The Butcher), Gelihast, Kirtonos the Herald and Ras Frostwhisper.
- Fixed: a quest opened in the Quest Log tab left its rewards drawn over the dungeon's quest tab.
- The quest text frame has a closed border, with "Show on map" underneath it instead of over the text.

## 0.2.3

- Hovering a boss skull shows the boss's portrait and its loot, grouped into Gear, Recipes and Other. Gear is ordered weapons, off-hands, armour from head to feet, then necklaces, rings and trinkets; recipes are grouped by profession.
- Click the skull to keep the loot open, so you can hover each item for its tooltip.
- The loot list shows only Bind on Pickup items, Uncommon and better.

## 0.2.2

- Quest chains that WoW Forever changed at launch or that QuestieDB doesn't link yet, taken from Wowhead's quest pages and comments:
  - Ruins of Lordaeron: The Wrath of Rath'mael needs Rear Guard Patrol, The New Plague needs A Recipe For Death, and Unending Torment is one chain of five
  - City of Dalaran: An Alarming Request (Alliance) and Blood in the Streets (Horde) come first
  - Excavation Site: Wetlands: Open the Maw needs Dragonmaw Rumors, Horrors in the Highland needs Rethiel the Greenwarden's chain, Highland Hides needs Young Crocolisk Skins, and three quests have their follow-up linked
- A quest chain whose first step drops inside the dungeon is listed under "Starts inside" (Unending Torment in Ruins of Lordaeron).

## 0.2.1

- Fixed: closing the map during a fight could give an "action blocked" error (`SetPassThroughButtons`) after the dungeon map had moved the world map. The addon now lets the game switch the map itself, and doesn't move it during combat.
- Loot for Kirtonos the Herald and Ras Frostwhisper.

## 0.2.0

- Dungeon maps. WoW Forever has no maps inside dungeons; the addon now shows one in the Map & Quest Log window:
  - the classic dungeon maps for all 22 old dungeons and raids (the images are still in the game files, the game just doesn't use them any more)
  - Santiago Reyes's maps for Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran (both floors), with his permission
- The map opens by itself when you open your map inside a dungeon, when you click an entrance on the world map, or from the map's top bar: World › Kalimdor › Durotar › Dungeons.
- Floor picker for dungeons with several levels (Scarlet Monastery wings, Blackrock Spire, Dire Maul, ...).
- Right-click the dungeon map, or click a name in the top bar, to go back to the normal map.
- Boss skulls on the map for 197 bosses, placed from the Dungeon Journal, Wowhead and the bosses' spawn points in the CMaNGOS Classic database. Bosses without a fixed spot (summoned or event bosses, and the bosses of the new Forever dungeons) are listed in a corner of the map. Shift-drag one onto the map to place it yourself; shift-right-click undoes it.
- Click a skull for the boss's loot: items only bosses drop (one boss, or shared between bosses), Uncommon and better. Hover an item for its normal tooltip; shift-click links it in chat.
- Dungeon quests: while a dungeon map is open, a tab above the quest list switches between your quest log and the dungeon's quests, laid out like the normal quest log:
  - quests in your log and chains you've started, with their objectives
  - quests you can pick up, quests that start inside, and handed-in quests (folded away)
  - quest chains show the step you're on; the rest of the chain folds out, and a dungeon quest that is part of a longer chain is shown inside that chain
  - click a quest or a chain step for its original quest text, level, start, rewards and a "Show on map" button
  - quest data from QuestieDB, quest text and rewards from the CMaNGOS Classic database
- Entrance icons are bigger by default (32 instead of 24) and drawn above the big city badges, so Ragefire Chasm now shows on Durotar. Click one to open its dungeon map.
- New options: open the dungeon map automatically inside dungeons, list dungeons in the map's top bar, show the dungeon quest list.
- `/bdm map` opens the map of the dungeon you're in.
- Fixed: "action blocked" errors when the map was open during combat.

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
