# Changelog

## 1.8.0

- Quests in your log show their full text in the dungeon quest details, straight from the game, exactly as the game's quest log shows it. This also fills in the description of the new Forever quests, which the addon has no text of its own for.
- The options page is tidier: sorted into World Map, Dungeon maps, Quests and Minimap, everything lined up, and it scrolls when the window is too small for it.
- New option: the text size of the dungeon quest tracker (Options › Quests).
- The quest item buttons in the dungeon quest tracker can be clicked now: they sat under the tracker, which took the clicks.
- A quest's item button goes away once the quest's goals are done. When that happens in a fight, it goes as soon as the fight is over.

## 1.7.0

- The dungeon quest tracker shows a quest's item beside it when you have it in your bags, like the game's own tracker: click it to use the item. In a fight the buttons can't be moved or changed (the game doesn't allow it), so a change waits until the fight is over.

## 1.6.0

- Sunken Temple has a second level: the lower ring with the six statues and Atal'alarion, which the game's own map leaves out. The map always opens on the game's level; pick "Lower Level" in the floor menu to see it. It then stays on that level until you pick the other one again or leave the dungeon. A note in its bottom-left corner says the map was made with AI and may contain errors, and that the numbers are the order in which to activate the statues.
- The floor menu on the dungeon maps moved a little to the right, so the game's own round map buttons no longer cover it.
- Item tooltips say where an item comes from: "Dropped by: Taragaman the Hungerer (Ragefire Chasm)". Only for boss loot the dungeon maps list (Bind on Pickup, Uncommon and better); you can turn it off in the options.
- Class quests whose work is done inside a dungeon are now on that dungeon's quest list, with the quests that lead up to them: the Sunken Temple class quests (The Green Drake, The Azure Key, Destroy Morphaz, Blood of Morphaz, Da Voodoo, Forging the Mightstone, Trolls of a Feather, Voodoo Feathers, A Better Ingredient), The Orb of Soran'ruk (Blackfathom Deeps and Shadowfang Keep), The Test of Righteousness (Shadowfang Keep and the Deadmines), Fire Hardened Mail, Brutal Armor and Elemental Aid (Razorfen Kraul), and more. You only see the ones for your class.
- The Dungeon Set 2 (Tier 0.5) quests show up under Blackrock Spire, Scholomance and Stratholme, and in the dungeon quest tracker, but only while you have them in your quest log. They run through all of these dungeons, so listing every one of them all the time would bury the dungeon's own quests.

## 1.5.0

- The map no longer goes blank (just the brown background) when a fight ends with the map open: after combat, and whenever the map opens, either the dungeon map or the game's own map shows, never neither.
- The addon no longer tries to note a boss's portrait and level when you target it: the game hides those from addons inside dungeons, so it never worked. The bosses new in Forever keep the ring with the skull until there's data for them.
- Alcaz Prison: all five bosses have their place on the map (Katerina the Cleaner and Blazeroar in the Maximum Security Unit).
- A dungeon quest tracker: inside a dungeon, the quests in your log for that dungeon with their objectives, in the look of the game's own tracker (for when Questie's tracker folds up inside). Quests show their level. Click a quest to open it on the dungeon map; drag the tracker anywhere to move it (`/bdm tracker reset` puts it back), the button folds it up. It can be turned off in the options.
- The quest details' button bar is Abandon | Share | Show on map, three equal buttons like the game's quest log. Abandon asks for confirmation the way the game does, and only works for quests in your log.

## 1.4.0

- Select a quest in the dungeon tab and the map shows where it's done: the bosses it has you kill get a blue area round their pin, and the objects it uses (a book, a chest, a tablet) get a blue spot of their own; hover a spot for its name. The map turns to their level if they're on another one. Quests about ordinary creatures get no marks. Objects are shown in the dungeons where their spot is known to be right: Blackfathom Deeps, the Deadmines, Dire Maul North, Ragefire Chasm, Razorfen Downs and Kraul, Scarlet Monastery, Sunken Temple and Zul'Farrak.
- Quests that only send you to someone (breadcrumbs, like Tabetha's Task: "Speak with Tabetha in Dustwallow Marsh") are no longer listed as dungeon quests when the quest they lead to is already there; Tiara of the Deep says where to find Tabetha. About a dozen of them, in Zul'Farrak, Gnomeregan, Blackrock Depths and Spire, Dire Maul and Blackfathom Deeps.

## 1.3.2

- The loot window says under the boss's name what it is, the way the game's own tooltip does: "Level 41 Humanoid (Elite)", or "Level ?? Dragonkin (Boss)". Classic bosses from the Classic database; the bosses new in Forever are noted when you target them.
- The Drowned City: Zul'Alai, Var'Taka and the Primeval Elemental show their loot. QuestieDB has several creatures by each name, and the addon picked one without loot; it now takes the one whose loot is known.

## 1.3.1

- The Drowned City: all six bosses have their place on the map (the Primeval Elemental in Atal'byzal).

## 1.3.0

- Bosses without a picture yet get the same ring as the others, round a dark disc with the boss skull, so every pin looks alike.
- Target a boss that has no picture yet and the addon notes its model, so its pin shows its portrait from then on. Mostly the bosses new in Forever: the game doesn't have their pictures in its files.
- Krol'dok Stronghold: Bossman Toof added to its bosses, all six have their place on the new map, and two go by the names the game shows: War Handler Ashka and Overlord Mugg (their encounters are called Handler Ashka and Overseer Mugg).
- Maps for The Drowned City (two levels: The Drowned City and Atal'byzal), Krol'dok Stronghold, Alcaz Prison (two levels: Main Unit and Maximum Security Unit), Shaper's Terrace and Blackmaw Hold, by Santiago Reyes. Their bosses don't have a place on them yet: shift-drag them from the list in the corner. Blackmaw Hold has six levels: Blackmaw Hold, Festering Grotto and the Depths of the Fallen Grove, the Elders, the Burrow and Forbidden Magic.
- Krol'dok Stronghold lists Krol'dok Moulding (both factions) and its follow-up Key Ingredients. The quest starts from an item that drops inside, so its text never names the dungeon.
- A quest chain's round icon shows just the step you're on ("12"); "12/16" didn't fit and ran over the icon. The line under the quest still says "step 12 of 16".

## 1.2.2

- Boss loot no longer lists the zone's common drops: items that ordinary creatures in the dungeon drop as well, like the OOX-17/TN Distress Beacon in Zul'Farrak, the Gordok Shackle Key in Dire Maul, Corruptor's Scourgestones and Demonic Runes. Shriveled Heart in Zul'Farrak too, which a dozen of its trolls drop.
- Boss loot looks like the Dungeon Journal's loot list: a bigger icon with its quality border, the name in its quality colour, and what kind of item it is underneath ("Legs, Cloth", "Staff", "One-Hand, Sword").
- Hovering a boss opens its loot list, and it stays open while you move the mouse onto it, so you can hover the items and shift-click them into chat. It closes by itself a moment after you move away; no more clicking to keep it open.
- Rare bosses have a silver ring round their portrait on the map instead of a gold one, like the silver dragon the game puts round a rare's portrait.
- Zul'Farrak: Sergeant Bly and Zerillis now have their place on the map.
- Uldaman turns to the right level in more places (Map Chamber, Temple Hall, The Stone Vault, Echomok Cavern, Dig Two and Dig Three on the first level; Khaz'goroth's Seat on the second).

## 1.2.1

- Uldaman's two levels had the wrong names, so the map opened on Archaedas's level when you walked in. They're now Hall of the Keepers (where you come in) and Khaz'Goroth's Seat (Archaedas).

## 1.2.0

- The five new dungeons are in: The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and Shaper's Terrace. They have no map yet, so their page shows a "Work in progress" notice, with the bosses (and their loot) listed in the corner and the dungeon's quests in the tab beside it. They're in the minimap list and their zone's Dungeons menu, and their page opens by itself when you open the map inside.
- Their quests come from QuestieDB. Quest chains are linked only where QuestieDB's own data shows the link; a quest without a known quest giver says so.
- Their entrances are on the world map like the others (read off the map in game, until QuestieDB has them).

## 1.1.5

- Shadowfang Keep: the Fel Steeds / Shadow Charger now have their place on the map.
- Blackfathom Deeps: the Fire of Aku'Mai is gone from the boss list. It's the event that opens the door to Aku'mai, not a boss.

## 1.1.4

- Opening the map in combat inside a dungeon now shows the dungeon map on top of the game's own. The game doesn't let addons hide its map during a fight, so the dungeon map now goes over it instead.
- Scarlet Monastery and Gnomeregan turn to the right level in more places (Athenaeum, Hall of Champions, Crusader's Chapel; Engineering Labs, Tinkers' Court).
- Razorfen Downs: Tuten'kash and Plaguemaw the Rotting now have their place on the map, so the dungeon is complete and loses its "Work in progress" tag.

## 1.1.3

- Quest details now look and work like the game's own: they fill the whole quest tab, with a Back button in a bar on top to return to the list. The rewards sit on the game's dark panel with its "Rewards" header, start at the bottom of the details and slide up to their place as you scroll. Experience and money come first, each on their own row, and the reward buttons are the game's small ones.
- The buttons under the details are one full-width bar (Share | Show on map), and the scroll bar is the game's thin one.
- Inside a dungeon, the tab bar no longer covers the Back button of the game's own quest details: it steps aside while those are open and comes back with the quest list.

## 1.1.2

- Shift-click a quest in the dungeon quest tab to put its link in chat, like in the game's quest log. On a quest chain, it links the step you're on. For a quest you've never had in your log the game makes no link, so it goes in as text in Questie's form ("[[33] Hearts of Zeal (1234)]"): players with Questie see it as a link.
- Dungeon quests in that form in chat become clickable links for you too, also without Questie: click one to see its level, where it starts and its objectives.

## 1.1.1

- Dungeons without subzones (like Gnomeregan): the map now holds the level you last looked at during your run, and turns to a boss's level when you pull or target that boss. A new run starts on the first level again.
- The Deadmines and Stratholme now switch levels by subzone too (Goblin Foundry, Mast Room and Ironclad Cove; Stratholme's living and undead sides).
- Pulling a boss teaches the addon which level that spot's subzone is on, so dungeons like Scholomance switch by themselves after a run.
- Scholomance: Darkmaster Gandling's pin moved to where he stands in WoW Forever.
- Fixed: the top bar's dungeon button sometimes did nothing until you reopened the map (when a dungeon map had opened over the world view, inside a dungeon or during combat). It now lists the dungeons of that dungeon's zone.

## 1.1.0

- Minimap button: click it for a list of every dungeon and raid, with the ones for your level (within 5 levels) pinned on top and the rest in a scroll list by level band. Levels are coloured by difficulty for you. Click a dungeon to open its map; a "coming soon" one opens its zone. Drag the button to move it; right-click for options, where you can also hide it. `/bdm list` opens the list too.
- Clicking a dungeon during combat opens its map as soon as the fight ends (the game doesn't let addons open the map in combat).
- Fixed: an error when a dungeon map opened right after a dungeon with more floors.
- Inside a dungeon, its map opens on the level you're on, and turns the page when you walk to another level (told by the subzone name under the minimap). City of Dalaran is known; in other multi-level dungeons the addon learns it the first time you switch floors by hand in a spot.
- New option: "List the dungeons for your level on top", to turn that part of the list off.
- Fixed: right-clicking the minimap button (or `/bdm`) during combat caused an error. The options now open when combat ends.

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
