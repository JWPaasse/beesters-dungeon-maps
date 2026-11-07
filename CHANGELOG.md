# Changelog

## Unreleased

- Minimap button: click it for a list of every dungeon and raid, with the ones for your level (within 5 levels) pinned on top and the rest in a scroll list by level band. Levels are coloured by difficulty for you. Click a dungeon to open its map; a "coming soon" one opens its zone. Drag the button to move it; right-click for options, where you can also hide it. `/bdm list` opens the list too.
- Clicking a dungeon during combat opens its map as soon as the fight ends (the game doesn't let addons open the map in combat).
- Fixed: an error when a dungeon map opened right after a dungeon with more floors.

## 1.0.1

- Fixed: clicking "Quest chain" sometimes opened the quest instead of folding the chain open.

## 1.0.0

The first full release. Thanks to everyone who tested the betas.

- "Work in progress" tag on dungeon maps whose data is still thin (bosses without a position or loot). Hover it to see what's missing. The entrance tooltip says so too.
- New Forever dungeons and raids that aren't in the data yet are listed as "coming soon" in their zone's Dungeons menu: The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace, Barrow Deeps and Hyjal Summit.
- Boss positions you placed under a name the addon no longer uses are cleaned up.
- Removed the `/bdm probe` test command.

## 0.2.10

- Item tooltips for new WoW Forever items (recipes, blueprints, food, new gear) now come from the game's own item data, with Forever's real values, until the game has loaded the item. Recipes also show the item they make. Old items Forever didn't change keep the classic-stats tooltip.

## 0.2.9

- Item tooltips for items the game hasn't loaded are now built from the classic item stats only (marked "Classic values; WoW Forever may differ"); the addon no longer includes tooltips copied from Wowhead.

## 0.2.8

- Horde/Alliance toggle on the dungeon quest tab: starts on your own faction, click to see the other side's quests.
- Quests you can't take yet show a greyed-out "!", so every quest has its icon in the same place.

## 0.2.7

- Boss pins are now the boss's portrait in a gold ring, with a small skull in the corner.
- Boss lists checked against Wowhead's WoW Forever Dungeon Journal: City of Dalaran, Hall of Thanes and the Excavation Site corrected (for example Magmatus and Arcanic Enigma), and the journal's rares and extra encounters added. Names are the ones you see in game.
- Boss positions for City of Dalaran, Hall of Thanes, the Excavation Site, and the rares that have a fixed spawn.
- City of Dalaran opens on The Underbelly, where a run starts.
- The dungeon quest tab now looks like the quest log: same border, spacing, scroll bar and "(Dungeon)" tag.
- When you've handed in every quest in a dungeon, the quest tab says so.
- Fixed: the "Currently equipped" comparison could stay on screen after hovering an item.

## 0.2.6

- Fuller loot tables: classic bosses' loot now comes from the Classic database's own loot tables, with drop chances. Dungeon set pieces are back (Scholomance, Stratholme, Blackrock Spire), world drops stay out.
- Every listed item has a tooltip, even when the game server doesn't send the item: WoW Forever's own tooltip from Wowhead, or one built from the classic item stats (marked as such).
- Dungeon maps open on a floor with bosses (Scholomance no longer opens on its empty entrance level); the floor menu shows how many bosses are on each floor.
- Share button in the quest details, next to "Show on map".
- Fixed: hovering a boss inside a dungeon could give an error (the boss portrait).
- Loot tables, item data and tooltips now update themselves daily.

## 0.2.5

- Fixed: clicking a place in the map's top bar during a fight could give an "action blocked" error. The Dungeons button in the top bar is now a separate button of the addon's own.
- Fixed: boss loot lists left out items the game hadn't loaded yet (for example Charlga Razorflank's Pronged Reaver), or showed them as "Loading..." for good. The addon now carries the names, quality and binding of boss loot itself.
- Items a boss shares with a rare or its own adds now count as its loot (for example the Haunting Blade, and Noxxion's items).

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
