WoW Forever's map has no dungeon maps, no boss locations and no list of dungeon quests. Beester's Dungeon Maps adds all three, and it's made to look like Blizzard shipped them.

## Built to look like the game

The aim from day one: nothing in this addon should look like an addon. Every part uses the game's own art and controls, so it sits in your map and quest log as if it had always been there.

- Entrance pins are the map's own dungeon and raid icons, and the **Dungeons** menu sits in the map's own top bar, next to World › Kalimdor › Durotar.
- The dungeon quests use the quest log's own frame, parchment, fonts, quest icons and thin scroll bar. The quest details copy the game's layout down to the Back button, the wooden "Rewards" header and the dark reward panel that rises as you scroll.
- Boss pins, floor menu, tooltips and buttons are the game's own templates. The options live in the game's Settings window, not in a window of their own.
- The dungeon maps are the classic maps that still ship with the game. The maps of the new Forever dungeons are by Santiago Reyes, drawn in the same style.

## Features

**Dungeon and raid entrances**
- Every entrance on your zone and continent maps. Hover one for its level range and whether it's new in Forever. Blackrock Mountain shows both Blackrock Depths and Blackrock Spire.
- A **Dungeons** menu in the map's top bar opens any dungeon in the zone you're looking at, even from the other side of the world.

**Minimap button**
- One click for a list of every dungeon and raid. The ones for your level (5 levels either way) are pinned on top; the rest scroll underneath, by level, raids last.
- Levels are coloured by difficulty for you, like quest titles. Click a dungeon to open its map.
- The raids that aren't out yet are listed too, so you can see what's coming.
- Drag the button anywhere around the minimap, right-click it for the options, or hide it.

**Dungeon maps**
- Open your map inside a dungeon and its map is already there. Or click an entrance on the world map.
- Multi-level dungeons open on the level you're standing on, worked out from the area you're in. When the game doesn't tell, the map turns to the level of the boss you pull or target.
- Every boss has a pin with its portrait. Hover it for its loot (Bind on Pickup, Uncommon and better), sorted into gear, recipes and other. Click to keep the loot list open, and shift-click an item to link it in chat.
- A floor menu shows how many bosses are on each level.
- Opening the map in combat works too: the dungeon map goes on top of the game's own until the fight is over.

**Dungeon quests**
- The dungeon's quests in a tab next to its map: the ones in your log, the ones you can still pick up and where, the ones that start inside, and the ones you've done.
- Quest chains fold up to the step you're on.
- Click a quest for its objectives, description and rewards. Experience and money are worked out for your level.
- Share a quest with your group, or show its quest giver on the map.
- Shift-click a quest to link it in chat. Quests you've never had in your log go in as a link Questie players can click, and you can click them too, even without Questie.
- Switch between Horde and Alliance quests.

**The new Forever dungeons**
- The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and Shaper's Terrace are in, with their entrances, bosses, loot and quests. There's no map of them yet, so their page shows a "Work in progress" notice where the map will go.

**Tooltips that don't get stuck**
- If the game hasn't loaded an item yet, you see the addon's copy of its tooltip instead of "Retrieving item information".

## Still in progress

- **Maps of the newest dungeons:** they'll be added as soon as they exist.
- **Quest data of the newest dungeons:** some quest givers and chains are still missing, and fill in as QuestieDB adds them.
- **Raids:** Barrow Deeps and Hyjal Summit follow after they open on 9 December.
- **Incomplete data:** a dungeon still missing a map, a boss position or loot shows a "Work in progress" tag. Hover it to see what's missing.
- **Language:** English only for now.

Know where a missing boss stands? Shift-drag it from the list in the corner onto the map to place it yourself, and let me know so everyone gets it.

## Commands

- `/bdm` opens the options (or `/beesterdm` if another addon already uses `/bdm`)
- `/bdm map` opens the map of the dungeon you're in
- `/bdm list` opens the dungeon list
- `/bdm status` shows the addon and game version. Please include it when you report a problem.

## Works with Questie

You don't need Questie, and the two run side by side without problems. If you do see an error with both installed, please report it with the error text.

## Credits

- Entrances and quests: QuestieDB, the open database behind Questie
- Quest text and classic item data: the CMaNGOS Classic database
- Maps of the new Forever dungeons: Santiago Reyes (Atlas de Azeroth: Forever), used with permission
- Bosses, level names and tooltips for new Forever items: the game's own files

The data updates automatically, so new Forever content shows up as it's added.

Source code and bug reports: https://github.com/JWPaasse/beesters-dungeon-maps
