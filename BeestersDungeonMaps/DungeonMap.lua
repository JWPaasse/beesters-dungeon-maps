-- Beester's Dungeon Maps: the dungeon map view inside the game's own Map & Quest Log window.
--
-- WoW Forever has no maps inside dungeons (the map falls back to the World view there).
-- This view takes the place of the map picture while a dungeon is open:
--   * old dungeons: the classic dungeon map tiles that still ship in the game files
--   * new Forever dungeons: Santiago Reyes's maps (watermarked, used with permission)
-- with boss pins (Dungeon Journal positions and ones placed in game), a game-style tooltip with
-- the boss's loot, and a "Work in progress" tag while an instance's data is still thin.
--
-- It opens by itself inside a dungeon, from an entrance pin, or from the map's top bar
-- (World > Kalimdor > Durotar > Dungeons). Any other map navigation closes it again.

local _, ns = ...

local view            -- the frame that covers the map picture
local current = {}    -- key, floor, zoneMapID
local pendingMap      -- { mapID, after, keepQuests } while we wait for the map to switch

local MAP_W, MAP_H = 1002, 668 -- classic map tiles: 4 x 3 tiles of 256, this much is shown
local SKULL_ATLAS = "DungeonSkull"
local SKULL_FALLBACK = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- Floor names where the game's own names are well known. Others are "Level 1", "Level 2", ...
local FLOOR_NAMES = {
    sm = { "Graveyard", "Library", "Armory", "Cathedral" },
    strat = { "Main Gate", "Service Gate" },
    ulda = { "Uldaman", "Hall of the Keepers" },
    mara = { "Caverns of Maraudon", "Zaetar's Grave" },
}

-- Boss names that differ between the game's boss list and the Dungeon Journal.
local NAME_ALIASES = {
    hazzas = "wardensofthedream", morphaz = "wardensofthedream",
    weaver = "wardensofthedream", dreamscythe = "wardensofthedream",
    nekrumgutchewer = "nekrumsezzziz", shadowpriestsezzziz = "nekrumsezzziz",
    cannonmasterwilley = "willeyhopebreaker", archivistgalford = "instructorgalford",
    malorthezealous = "commandermalor", baronrivendare = "lordauriusrivendare",
    overlordramtusk = "warlordramtusk",
    -- The Dungeon Journal's group names
    sneedsshredder = "sneed", jammalantheprophetogomthewretched = "jammalantheprophet",
    weaverdreamscythe = "wardensofthedream", hazzasmorphaz = "wardensofthedream",
    kinggordokchorushtheobserver = "kinggordok", nekrumgutchewershadowpriestsezzziz = "nekrumsezzziz",
    warchiefrendblackhandgyth = "warchiefrendblackhand",
    scarletcommandermograinehighinquisitorwhitemane = "highinquisitorwhitemane",
    warderstilgissverek = "warderstilgiss", groyattheblindhunter = "blindhunter",
    ringofthelaw = "ringoflaw", chestoftheseven = "theseven",
}

local function Normalize(name)
    local n = (name or ""):lower():gsub("[^%a]", "")
    return NAME_ALIASES[n] or n
end

----------------------------------------------------------------------
-- Data helpers
----------------------------------------------------------------------

-- Dungeons without a map yet still get a page: a notice where the map would be, the bosses
-- in the corner list and the quests beside it. Their "map" is one blank level.
if ns.DungeonMaps and ns.Instances then
    for key in pairs(ns.Instances) do
        if not ns.DungeonMaps[key] then
            ns.DungeonMaps[key] = { placeholder = true, floors = { { name = "No map yet" } } }
        end
    end
end

local function FloorName(key, index)
    local map = ns.DungeonMaps[key]
    local floor = map and map.floors[index]
    if floor and floor.name then return floor.name end
    local names = FLOOR_NAMES[key]
    return names and names[index] or (("Level %d"):format(index))
end

-- The game's boss list for an instance, each with its map position when the Journal has one.
local function BossesWithPositions(key)
    local positions = ns.BossPositions and ns.BossPositions[key] or {}
    local byEncounter, byName = {}, {}
    for _, p in ipairs(positions) do
        if p[4] and p[4] ~= 0 then byEncounter[p[4]] = p end
        byName[Normalize(p[5])] = p
    end
    local result = {}
    local custom = ns.db and ns.db.bossPositions and ns.db.bossPositions[key]
    local list = ns.Bosses and ns.Bosses[key]
    if list then
        for order, boss in ipairs(list) do
            local encounterID, name, npcID, note = boss[1], boss[2], boss[3], boss[4]
            local p = (encounterID ~= 0 and byEncounter[encounterID]) or byName[Normalize(name)]
            local mine = custom and custom[name]
            if mine then p = { mine[1], mine[2], mine[3] } end
            table.insert(result, {
                order = order, encounterID = encounterID, name = name, npcID = npcID,
                note = note ~= "" and note or nil,
                floor = p and p[1], x = p and p[2], y = p and p[3], custom = mine and true or nil,
            })
        end
    else
        -- No boss list from the game (yet): show the Journal's bosses as they are.
        for order, p in ipairs(positions) do
            table.insert(result, { order = order, encounterID = p[4], name = p[5], floor = p[1], x = p[2], y = p[3] })
        end
    end
    return result
end

-- How many bosses stand on each floor, and the floor to open on: the first floor unless
-- it has no bosses (Scholomance's entrance level), then the floor with the most.
local function BossesPerFloor(key)
    local counts = {}
    for _, b in ipairs(BossesWithPositions(key)) do
        if b.floor then counts[b.floor] = (counts[b.floor] or 0) + 1 end
    end
    return counts
end

-- Where a group starts: the City of Dalaran run begins in The Underbelly (its second map).
local START_FLOOR = { dal = 2 }

-- Inside a dungeon the game no longer says which level you're on, but the subzone name under
-- the minimap does. Known subzones per floor; others are learned (below) and matched by name.
-- Forever's files list each dungeon's subzone names (tools/floor_subzones.json) but no longer
-- which map level they're on; these are the ones the boss positions settle. Dungeons with no
-- subzones at all (Blackrock Depths, Maraudon, ...) rely on the run's level and the bosses.
local SUBZONE_FLOORS = {
    dal = { ["Dalaran"] = 1, ["City of Dalaran"] = 1, ["The Underbelly"] = 2 },
    -- Gilnid in the foundry, Mr. Smite in the mast room, the ship in the cove: the second map.
    dm = { ["Goblin Foundry"] = 2, ["Mast Room"] = 2, ["Ironclad Cove"] = 2 },
    -- Stratholme's two maps are the city's two halves: the living side and the undead side.
    strat = {
        ["King's Square"] = 1, ["Market Row"] = 1, ["The Scarlet Bastion"] = 1, ["The Hall of Lights"] = 1,
        ["The Crimson Throne"] = 1,
        ["Elders' Square"] = 2, ["The Gauntlet"] = 2, ["Slaughter Square"] = 2, ["The Slaughter House"] = 2,
    },
    -- Learned in game: the wings' halls (Library, Armory, Cathedral).
    sm = { ["Athenaeum"] = 2, ["Hall of Champions"] = 3, ["Crusader's Chapel"] = 4 },
    -- Learned in game; the game writes "Engineering Labs" with a space after it.
    gnomer = { ["Engineering Labs "] = 3, ["Engineering Labs"] = 3, ["Tinkers' Court"] = 4 },
}

-- The subzone under the minimap, unless it's just the dungeon's own name (that says nothing).
local function SubzoneHere(key)
    local subzone = GetSubZoneText and GetSubZoneText() or ""
    local instance = ns.Instances[key] and ns.Instances[key].name
    if subzone == "" or subzone == instance or subzone == (GetZoneText and GetZoneText()) then return nil end
    return subzone
end

-- The floor you're standing on, when it can be told from the subzone; nil otherwise.
local function FloorHere(key)
    local subzone = SubzoneHere(key)
    if not subzone then return nil end
    local known = SUBZONE_FLOORS[key] and SUBZONE_FLOORS[key][subzone]
    if known then return known end
    local learned = ns.db.subzoneFloors and ns.db.subzoneFloors[key] and ns.db.subzoneFloors[key][subzone]
    if learned then return learned end
    local map = ns.DungeonMaps[key]
    for i = 1, map and #map.floors or 0 do
        if FloorName(key, i) == subzone then return i end
    end
end

-- The level you're on during this run, for dungeons without subzones (Gnomeregan): the last
-- level you looked at inside, or the level of the boss you last pulled or targeted. It starts
-- over when you leave the dungeon.
local run = { key = nil, floor = nil }

local function NoteRunFloor(key, floor)
    if floor and ns.CurrentInstanceKey and ns.CurrentInstanceKey() == key then
        run.key, run.floor = key, floor
    end
end

local function RunFloor(key)
    return run.key == key and run.floor or nil
end

-- A boss of this run, by encounter ID or name: the level it stands on.
local function BossFloor(key, encounterID, name)
    local wanted = name and Normalize(name)
    for _, boss in ipairs(BossesWithPositions(key)) do
        if boss.floor and ((encounterID and encounterID ~= 0 and boss.encounterID == encounterID)
            or (wanted and Normalize(boss.name) == wanted)) then
            return boss.floor
        end
    end
end

-- Switching floors by hand inside the dungeon teaches the addon which floor this subzone is on.
local function LearnFloorHere(key, floor)
    if not (ns.CurrentInstanceKey and ns.CurrentInstanceKey() == key) then return end
    local subzone = SubzoneHere(key)
    if not subzone or (SUBZONE_FLOORS[key] and SUBZONE_FLOORS[key][subzone]) then return end
    ns.db.subzoneFloors = ns.db.subzoneFloors or {}
    ns.db.subzoneFloors[key] = ns.db.subzoneFloors[key] or {}
    ns.db.subzoneFloors[key][subzone] = floor
end

local function DefaultFloor(key)
    if START_FLOOR[key] then return START_FLOOR[key] end
    local counts = BossesPerFloor(key)
    if (counts[1] or 0) > 0 then return 1 end
    local best, most = 1, 0
    for floor, n in pairs(counts) do
        if n > most or (n == most and floor < best) then best, most = floor, n end
    end
    return best
end

-- Is the addon's data for this instance still missing a real part? Counts the regular bosses
-- (rares left out): a "work in progress" instance has no map, or more than a quarter of them
-- without a place on the map or without loot. Returns nil when the data is complete enough.
local WIP_SHARE = 0.75
function ns:InstanceStatus(key)
    local map = ns.DungeonMaps and ns.DungeonMaps[key]
    if not map or map.placeholder then
        return { noMap = true }
    end
    local total, placed, withLoot = 0, 0, 0
    for _, boss in ipairs(BossesWithPositions(key)) do
        if boss.note ~= "Rare" then
            total = total + 1
            if boss.x then placed = placed + 1 end
            local loot = boss.npcID and ns.BossLoot and ns.BossLoot[boss.npcID]
            if loot and #loot > 0 then withLoot = withLoot + 1 end
        end
    end
    if total == 0 or placed < total * WIP_SHARE or withLoot < total * WIP_SHARE then
        return { total = total, placed = placed, withLoot = withLoot }
    end
end

local WIP_COLOR = { r = 1, g = 0.5, b = 0.25 } -- the game's orange for warnings
ns.WIP_COLOR = WIP_COLOR

local function ShowStatusTooltip(owner, status)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Work in progress", WIP_COLOR.r, WIP_COLOR.g, WIP_COLOR.b)
    if status.noMap then
        GameTooltip:AddLine("No map for this instance yet.", 1, 1, 1, true)
    else
        GameTooltip:AddLine(("Boss positions: %d of %d placed"):format(status.placed, status.total), 1, 1, 1)
        GameTooltip:AddLine(("Loot: %d of %d bosses"):format(status.withLoot, status.total), 1, 1, 1)
    end
    GameTooltip:AddLine("The data for this instance isn't complete yet. Found a mistake? Let us know on CurseForge.",
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Boss tooltip (name, place in the dungeon, loot)
----------------------------------------------------------------------

local MIN_QUALITY = 2 -- Uncommon and better

local BIND_ON_PICKUP = 1

-- name, link, quality, icon, bindType (1 = Bind on Pickup)
-- Most classic items aren't in the game files: the game has to ask the server for them, and
-- until it answers there's nothing. So the addon carries name, quality and binding itself
-- (ns.LootItems); the game's own data is used when it has it (names in your language).
local function ItemInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, quality, icon, bindType
    if getInfo then
        local _
        name, link, quality, _, _, _, _, _, _, icon, _, _, _, bindType = getInfo(itemID)
    end
    local known = ns.LootItems and ns.LootItems[itemID]
    if not name and known then
        name, quality, bindType = known[1], known[2], known[3]
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        local hex = color and color.hex or "|cffffffff"
        link = ("%s|Hitem:%d::::::::::::::|h[%s]|h|r"):format(hex, itemID, name)
        local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        icon = getInstant and select(5, getInstant(itemID)) or 134400
    end
    if known and bindType == nil then bindType = known[3] end
    return name, link, quality, icon, bindType
end

-- Ask the server for an item the game doesn't have yet; redraw what's open once it arrives.
-- A request can get lost (the server answers a limited number at once), so an item still
-- missing a few seconds later is asked for again the next time its list is drawn.
local requested = {}
local retryScheduled = false
local ShowItemTooltip -- below, with the loot rows
local attempts = {}
local function GaveUp(itemID) return (attempts[itemID] or 0) >= 3 end
local function RequestItem(itemID)
    local now = GetTime and GetTime() or 0
    if requested[itemID] and now - requested[itemID] < 3 then return end
    if GaveUp(itemID) then return end -- the server doesn't send it; leave it out
    attempts[itemID] = (attempts[itemID] or 0) + 1
    requested[itemID] = now
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(itemID)
        if item and item.ContinueOnItemLoad then
            item:ContinueOnItemLoad(function()
                requested[itemID] = nil
                if ns.OnLootItemLoaded then ns.OnLootItemLoaded() end
            end)
            return
        end
    end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

----------------------------------------------------------------------
-- Loot: what only bosses drop (tools/build_bosses.py), Bind on Pickup, Uncommon and better, grouped: Gear (weapons, then off-hands, armour from head to feet, then necklaces,
-- rings and trinkets), Recipes (by profession), Other. Shown in the boss's tooltip on
-- mouse-over; a click opens it as a panel that stays, so you can hover the items.
----------------------------------------------------------------------

local SLOT_ORDER = {
    INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1,
    INVTYPE_RANGED = 2, INVTYPE_RANGEDRIGHT = 2, INVTYPE_THROWN = 2,
    INVTYPE_SHIELD = 3, INVTYPE_HOLDABLE = 3, INVTYPE_RELIC = 3,
    INVTYPE_HEAD = 10, INVTYPE_SHOULDER = 11, INVTYPE_CLOAK = 12, INVTYPE_CHEST = 13, INVTYPE_ROBE = 13,
    INVTYPE_WRIST = 14, INVTYPE_HAND = 15, INVTYPE_WAIST = 16, INVTYPE_LEGS = 17, INVTYPE_FEET = 18,
    INVTYPE_BODY = 19, INVTYPE_TABARD = 19,
    INVTYPE_NECK = 30, INVTYPE_FINGER = 31, INVTYPE_TRINKET = 32,
}
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local SECTIONS = {
    { key = "gear", title = "Gear" },
    { key = "recipe", title = "Recipes" },
    { key = "other", title = "Other" },
}

local function ItemKind(itemID)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInstant then return "other" end
    local _, _, subType, equipLoc, _, classID = getInstant(itemID)
    if classID == RECIPE_CLASS then return "recipe", subType or "" end
    if equipLoc and SLOT_ORDER[equipLoc] then return "gear", SLOT_ORDER[equipLoc] end
    return "other"
end

-- { gear = {items}, recipe = {...}, other = {...} } sorted, and whether item names are still loading.
local function LootGroups(boss)
    local loot = boss.npcID and ns.BossLoot and ns.BossLoot[boss.npcID] or {}
    local groups = { gear = {}, recipe = {}, other = {} }
    local waiting = false
    for _, itemID in ipairs(loot) do
        local name, link, quality, icon, bindType = ItemInfo(itemID)
        if not name and GaveUp(itemID) then
            -- Asked three times and never sent: not an item this server has. Leave it out.
        elseif not name then
            -- Not loaded yet: list it anyway (its kind and icon are known without the server),
            -- so nothing goes missing while the rest of the list is already there.
            waiting = true
            RequestItem(itemID)
            local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            local instantIcon = getInstant and select(5, getInstant(itemID))
            local kind, sortKey = ItemKind(itemID)
            table.insert(groups[kind], { id = itemID, name = SEARCH_LOADING_TEXT or "Loading...", loading = true,
                icon = instantIcon or 134400, sortKey = sortKey })
        elseif (quality or 0) >= MIN_QUALITY and (bindType == nil or bindType == BIND_ON_PICKUP) then
            local kind, sortKey = ItemKind(itemID)
            table.insert(groups[kind], { id = itemID, name = name, link = link, quality = quality, icon = icon, sortKey = sortKey })
        end
    end
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            if a.sortKey ~= b.sortKey and a.sortKey and b.sortKey then return a.sortKey < b.sortKey end
            if (a.loading or false) ~= (b.loading or false) then return not a.loading end
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
    end
    if waiting and not retryScheduled and C_Timer then
        -- Look again in a few seconds: redraws what's open and asks again for what's missing.
        retryScheduled = true
        C_Timer.After(3, function()
            retryScheduled = false
            if ns.OnLootItemLoaded then ns.OnLootItemLoaded() end
        end)
    end
    return groups, waiting
end

-- Walks the groups in display order: onHeader(text, isProfession), onItem(item, sectionKey).
local function ForEachLoot(groups, onHeader, onItem)
    for _, section in ipairs(SECTIONS) do
        local list = groups[section.key]
        if #list > 0 then
            onHeader(section.title, false)
            local profession
            for _, item in ipairs(list) do
                if section.key == "recipe" and item.sortKey ~= profession then
                    profession = item.sortKey
                    if profession ~= "" then onHeader(profession, true) end
                end
                onItem(item, section.key)
            end
        end
    end
end

-- The boss's picture: the game's still portrait of the creature's model (the same picture
-- the Dungeon Journal uses), nothing around it. Model IDs: tools/boss_models.json.
-- The picture sits in a few empty tooltip lines, anchored to the first of them. (Not with
-- GameTooltip_InsertFrame: that does arithmetic on the tooltip's line height, which inside a
-- dungeon is a "secret" value the addon may not touch, and it writes into the game's tooltip.)
local PORTRAIT_LINES = 5 -- blank lines that make room for the 64 px picture
local portrait
local function ShowPortrait(tooltip, boss, firstLine)
    local displayID = boss.npcID and ns.BossModels and ns.BossModels[boss.npcID]
    if not (displayID and SetPortraitTextureFromCreatureDisplayID) then return end
    local anchor = _G[tooltip:GetName() .. "TextLeft" .. firstLine]
    if not portrait then
        portrait = CreateFrame("Frame", nil, tooltip)
        portrait:SetSize(64, 64)
        portrait.Image = portrait:CreateTexture(nil, "ARTWORK")
        portrait.Image:SetAllPoints()
        portrait:RegisterEvent("PORTRAITS_UPDATED")
        portrait:SetScript("OnEvent", function(self)
            if self:IsShown() and self.displayID then SetPortraitTextureFromCreatureDisplayID(self.Image, self.displayID) end
        end)
        -- Gone as soon as the tooltip shows something else.
        tooltip:HookScript("OnTooltipCleared", function() portrait:Hide() end)
        tooltip:HookScript("OnHide", function() portrait:Hide() end)
    end
    for _ = 1, PORTRAIT_LINES do tooltip:AddLine(" ") end
    if not anchor then
        anchor = _G[tooltip:GetName() .. "TextLeft" .. firstLine]
        if not anchor then return end
    end
    portrait.displayID = displayID
    SetPortraitTextureFromCreatureDisplayID(portrait.Image, displayID)
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -2)
    portrait:Show()
end

local lootPanel
local tooltipBoss -- the boss whose tooltip is showing (refreshed when item names arrive)

local function ShowBossTooltip(owner, boss, total)
    tooltipBoss = { owner = owner, boss = boss, total = total }
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    GameTooltip:AddLine(("Boss %d of %d"):format(boss.order, total), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    if boss.note then GameTooltip:AddLine(boss.note, 0.75, 0.75, 0.75) end
    ShowPortrait(GameTooltip, boss, boss.note and 4 or 3) -- after the name, "Boss x of y" and its note
    local hasLoot = boss.npcID and ns.BossLoot and ns.BossLoot[boss.npcID]
    local panelOpen = lootPanel and lootPanel:IsShown() and lootPanel.boss == boss
    if hasLoot and not panelOpen then
        local groups, waiting = LootGroups(boss)
        local any = false
        ForEachLoot(groups, function(text, isProfession)
            if isProfession then
                GameTooltip:AddLine("  " .. text, 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(text, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            end
        end, function(item)
            any = true
            local color = item.loading and GRAY_FONT_COLOR or (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality])
            GameTooltip:AddLine(("|T%s:16|t %s"):format(item.icon or 134400, item.name),
                color and color.r or 1, color and color.g or 1, color and color.b or 1)
        end)
        if waiting and not any then
            GameTooltip:AddLine(SEARCH_LOADING_TEXT or "Loading...", 0.6, 0.6, 0.6)
        end
        if any then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("<Click to keep the loot open>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        end
    end
    if boss.custom then
        GameTooltip:AddLine("Placed by you. Shift-right-click to undo.", 0.6, 0.6, 0.6, true)
    elseif not boss.x then
        GameTooltip:AddLine("Shift-drag onto the map to place this boss.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- The game's item tooltip needs the server's data. While that hasn't come (or for items the
-- server never sends) it would say "Retrieving item information" for good, so show what the
-- addon knows instead: name, binding, slot and type. The real tooltip replaces it as soon as
-- the data arrives.
ShowItemTooltip = function(owner, itemID)
    owner.waitingTooltip = nil
    ns:HideItemTooltip(nil) -- clears comparisons left from the previous item
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local known = ns.LootItems and ns.LootItems[itemID]
    if (getInfo and getInfo(itemID)) or not known then
        ns:ShowItemByID(owner, itemID)
        return
    end
    RequestItem(itemID)
    owner.waitingTooltip = itemID
    -- A tooltip from the game's own item tables, else classic item stats (Data/LootTooltips.lua).
    local lines = ns.LootTooltips and ns.LootTooltips[itemID]
    if lines then
        for i, line in ipairs(lines) do
            local left, right = line:match("^(.-)\t(.*)$")
            if i == 1 then
                GameTooltip:SetText(line, 1, 1, 1)
            elseif left then
                GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
        return
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[known[2]]
    GameTooltip:SetText(known[1], color and color.r or 1, color and color.g or 1, color and color.b or 1)
    if known[3] == 1 then
        GameTooltip:AddLine(ITEM_BIND_ON_PICKUP or "Binds when picked up", 1, 1, 1)
    elseif known[3] == 2 then
        GameTooltip:AddLine(ITEM_BIND_ON_EQUIP or "Binds when equipped", 1, 1, 1)
    end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if getInstant then
        local _, _, subType, equipLoc = getInstant(itemID)
        local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
        if slot or subType then
            GameTooltip:AddDoubleLine(slot or "", subType or "", 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddLine("The game hasn't sent this item's details yet.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function AcquireRow(panel, index)
    local row = panel.Rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, panel)
    row:SetSize(230, 22)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(20, 20)
    row.Icon:SetPoint("LEFT")
    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    row.Name:SetPoint("RIGHT")
    row.Name:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", function(self) ShowItemTooltip(self, self.itemID) end)
    row:SetScript("OnLeave", function(self) ns:HideItemTooltip(self) end)
    row:SetScript("OnClick", function(self)
        if HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
    end)
    panel.Rows[index] = row
    return row
end

local function AcquireHeader(panel, index, sub)
    local h = panel.Headers[index]
    if not h then
        h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        h:SetJustifyH("LEFT")
        panel.Headers[index] = h
    end
    h:SetFontObject(sub and "GameFontDisableSmall" or "GameFontNormalSmall")
    return h
end

local function RefreshLootPanel()
    local panel = lootPanel
    if not panel or not panel:IsShown() then return end
    local boss = panel.boss
    panel.Title:SetText(boss.name)
    local groups, waiting = LootGroups(boss)

    local y, rowIndex, headerIndex = 32, 0, 0
    panel.shown = {} -- { section, itemID } in display order (read by tools/test_addon.py)
    ForEachLoot(groups, function(text, sub)
        if not sub and headerIndex > 0 then y = y + 4 end
        headerIndex = headerIndex + 1
        local h = AcquireHeader(panel, headerIndex, sub)
        h:SetText(text)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", sub and 16 or 12, -(y + (sub and 2 or 4)))
        h:Show()
        y = y + (sub and 16 or 20)
    end, function(item, sectionKey)
        rowIndex = rowIndex + 1
        local row = AcquireRow(panel, rowIndex)
        row.itemID, row.link = item.id, item.link
        table.insert(panel.shown, { sectionKey, item.id })
        row.Icon:SetTexture(item.icon)
        row.Name:SetText(item.name)
        local color = item.loading and GRAY_FONT_COLOR or (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality])
        if color then row.Name:SetTextColor(color.r, color.g, color.b) else row.Name:SetTextColor(1, 1, 1) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, -y)
        row:Show()
        y = y + 22
    end)
    for i = rowIndex + 1, #panel.Rows do panel.Rows[i]:Hide() end
    for i = headerIndex + 1, #panel.Headers do panel.Headers[i]:Hide() end
    panel.Empty:SetShown(rowIndex == 0)
    panel.Empty:SetText(waiting and (SEARCH_LOADING_TEXT or "Loading...") or "No Bind on Pickup loot of Uncommon or better known.")
    panel:SetHeight(rowIndex == 0 and 66 or y + 12)
end

local function CreateLootPanel(parent)
    local panel = CreateFrame("Frame", "BeestersDungeonMapsLoot", parent, BackdropTemplateMixin and "BackdropTemplate")
    panel:SetSize(254, 100)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.Title:SetPoint("TOPLEFT", 12, -10)
    panel.Title:SetPoint("RIGHT", -30, 0)
    panel.Title:SetJustifyH("LEFT")
    panel.Close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.Close:SetPoint("TOPRIGHT", 2, 2)
    panel.Empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.Empty:SetPoint("TOPLEFT", 12, -34)
    panel.Rows = {}
    panel.Headers = {}
    panel:SetScript("OnHide", function(self) ns:HideTooltipWithin(self) end)
    panel:Hide()
    return panel
end

local function ToggleLoot(owner, boss)
    if not lootPanel then lootPanel = CreateLootPanel(view) end
    GameTooltip:Hide()
    if lootPanel:IsShown() and lootPanel.boss == boss then
        lootPanel:Hide()
        return
    end
    lootPanel.boss = boss
    lootPanel:ClearAllPoints()
    lootPanel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    lootPanel:SetClampedToScreen(true)
    lootPanel:Show()
    RefreshLootPanel()
end

-- Item names arrive from the server a moment later; refresh what's open once they do.
local itemListener = CreateFrame("Frame")
local function RefreshOpenLoot()
    if itemListener.pending then return end
    itemListener.pending = true
    C_Timer.After(0.1, function()
        itemListener.pending = false
        RefreshLootPanel()
        local t = tooltipBoss
        local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if t and owner == t.owner then
            ShowBossTooltip(t.owner, t.boss, t.total)
        elseif owner and type(owner.waitingTooltip) == "number" then
            local id = owner.waitingTooltip
            owner.waitingTooltip = nil
            ShowItemTooltip(owner, id)
        end
    end)
end
ns.OnLootItemLoaded = RefreshOpenLoot
itemListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemListener:SetScript("OnEvent", RefreshOpenLoot)

----------------------------------------------------------------------
-- Placing bosses yourself (for bosses no data source has a position for)
----------------------------------------------------------------------

local ShowFloor -- defined below

local function SaveCustomPosition(boss, x, y)
    ns.db.bossPositions = ns.db.bossPositions or {}
    local list = ns.db.bossPositions[current.key] or {}
    ns.db.bossPositions[current.key] = list
    list[boss.name] = { current.floor, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000 }
end

local function CursorOnArt()
    local left, bottom, width, height = view.Art:GetRect()
    if not left then return end
    local scale = view.Art:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local x, y = (cx - left) / width, (bottom + height - cy) / height
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

local function StartPlacing(self)
    if not IsShiftKeyDown() then return end
    local map = ns.DungeonMaps[current.key]
    if map and map.placeholder then return end -- no map to place a boss on
    self.placing = true
    SetCursor("Interface\\Cursor\\UI-Cursor-Move")
end

local function StopPlacing(self)
    if not self.placing then return end
    self.placing = false
    ResetCursor()
    local x, y = CursorOnArt()
    if x then
        SaveCustomPosition(self.boss, x, y)
        ShowFloor(current.floor)
    end
end

local function BossClick(self, button)
    if button == "RightButton" and IsShiftKeyDown() and self.boss.custom then
        local list = ns.db.bossPositions and ns.db.bossPositions[current.key]
        if list then list[self.boss.name] = nil end
        ShowFloor(current.floor)
    elseif button == "LeftButton" and not IsShiftKeyDown() then
        ToggleLoot(self, self.boss)
    end
end

local function SetupBossFrame(frame)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartPlacing)
    frame:SetScript("OnDragStop", StopPlacing)
    frame:SetScript("OnClick", BossClick)
    frame:SetScript("OnEnter", function(self) ShowBossTooltip(self, self.boss, self.total) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- The view
----------------------------------------------------------------------

-- Boss pin: the boss's still portrait in a round gold ring, with a small skull in the bottom-left
-- corner. Bosses without a known portrait keep the plain skull.
local PIN_SIZE, RING_SIZE, BADGE_SIZE = 30, 38, 14
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD_RING = "Interface\\Common\\GoldRing"

local function SetSkull(texture)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKULL_ATLAS) then
        texture:SetAtlas(SKULL_ATLAS)
    else
        texture:SetTexture(SKULL_FALLBACK)
    end
end

local function CreateBossButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(PIN_SIZE, PIN_SIZE)
    -- Portrait, masked round.
    button.Portrait = button:CreateTexture(nil, "ARTWORK")
    button.Portrait:SetAllPoints()
    local mask = button:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(button.Portrait)
    button.Portrait:AddMaskTexture(mask)
    button.Ring = button:CreateTexture(nil, "OVERLAY")
    button.Ring:SetTexture(GOLD_RING)
    button.Ring:SetSize(RING_SIZE, RING_SIZE)
    button.Ring:SetPoint("CENTER")
    -- Skull badge: a dark disc with the skull on it.
    button.BadgeBack = button:CreateTexture(nil, "OVERLAY", nil, 2)
    button.BadgeBack:SetSize(BADGE_SIZE, BADGE_SIZE)
    button.BadgeBack:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -3, -3)
    button.BadgeBack:SetColorTexture(0.12, 0.08, 0.04, 1)
    local badgeMask = button:CreateMaskTexture()
    badgeMask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    badgeMask:SetAllPoints(button.BadgeBack)
    button.BadgeBack:AddMaskTexture(badgeMask)
    button.Badge = button:CreateTexture(nil, "OVERLAY", nil, 3)
    button.Badge:SetSize(BADGE_SIZE - 2, BADGE_SIZE - 2)
    button.Badge:SetPoint("CENTER", button.BadgeBack, "CENTER")
    SetSkull(button.Badge)
    -- Plain skull, for bosses without a portrait.
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(26, 26)
    button.Icon:SetPoint("CENTER")
    SetSkull(button.Icon)
    button.Highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.Highlight:SetBlendMode("ADD")
    button.Highlight:SetAlpha(0.4)
    SetupBossFrame(button)
    return button
end

-- Portrait or plain skull, for the boss this pin shows now.
local function UpdateBossPin(button)
    local boss = button.boss
    local displayID = boss and boss.npcID and ns.BossModels and ns.BossModels[boss.npcID]
    local portrait = displayID and SetPortraitTextureFromCreatureDisplayID and true or false
    button.displayID = portrait and displayID or nil
    if portrait then SetPortraitTextureFromCreatureDisplayID(button.Portrait, displayID) end
    button.Portrait:SetShown(portrait)
    button.Ring:SetShown(portrait)
    button.BadgeBack:SetShown(portrait)
    button.Badge:SetShown(portrait)
    button.Icon:SetShown(not portrait)
    button.Highlight:ClearAllPoints()
    if portrait then
        button.Highlight:SetTexture(GOLD_RING)
        button.Highlight:SetSize(RING_SIZE, RING_SIZE)
        button.Highlight:SetPoint("CENTER")
    else
        SetSkull(button.Highlight)
        button.Highlight:SetAllPoints(button.Icon)
    end
end

-- Portraits load a moment later the first time; draw them again when they do.
local portraitWatcher = CreateFrame("Frame")
portraitWatcher:RegisterEvent("PORTRAITS_UPDATED")
portraitWatcher:SetScript("OnEvent", function()
    if not (view and view.BossButtons) then return end
    for _, button in ipairs(view.BossButtons) do
        if button:IsShown() and button.displayID then
            SetPortraitTextureFromCreatureDisplayID(button.Portrait, button.displayID)
        end
    end
end)

local function CreateListRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKULL_ATLAS) then
        row.Icon:SetAtlas(SKULL_ATLAS)
    else
        row.Icon:SetTexture(SKULL_FALLBACK)
    end
    row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    SetupBossFrame(row)
    return row
end

local function Layout()
    if not view or not view:IsShown() then return end
    local w, h = view:GetSize()
    if w <= 0 or h <= 0 then return end
    -- Keep the map's 3:2 shape and fit it inside the map area.
    local artW = math.min(w, h * 1.5)
    local artH = artW / 1.5
    view.Art:SetSize(artW, artH)

    local map = current.key and ns.DungeonMaps[current.key]
    local floor = map and map.floors[current.floor]
    if not floor then return end -- not set up yet; ShowFloor lays it out again
    if map.placeholder then
        -- nothing to size
    elseif floor.tiles then
        local scale = artW / MAP_W
        for i = 1, 12 do
            local tex = view.Tiles[i]
            tex:SetSize(256 * scale, 256 * scale)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", view.Art, "TOPLEFT", ((i - 1) % 4) * 256 * scale, -math.floor((i - 1) / 4) * 256 * scale)
        end
    else
        view.Left:SetSize(artW * 1024 / 1536, artH)
        view.Right:SetSize(artW * 512 / 1536, artH)
    end

    for _, button in ipairs(view.BossButtons) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("CENTER", view.Art, "TOPLEFT", button.boss.x * artW, -button.boss.y * artH)
        end
    end
end

function ShowFloor(index)
    if lootPanel then lootPanel:Hide() end
    local map = ns.DungeonMaps[current.key]
    current.floor = index
    NoteRunFloor(current.key, index)
    local floor = map.floors[index]

    view.NoMap:SetShown(map.placeholder == true)
    if map.placeholder then
        view.Left:Hide()
        view.Right:Hide()
        for i = 1, 12 do view.Tiles[i]:Hide() end
        local name = ns.Instances[current.key] and ns.Instances[current.key].name or current.key
        view.NoMap.Text:SetText(("There's no map of %s yet.\nIts bosses are listed in the corner, its quests in the tab beside the map."):format(name))
    elseif floor.tiles then
        view.Left:Hide()
        view.Right:Hide()
        for i = 1, 12 do
            view.Tiles[i]:SetTexture(floor.tiles[i])
            view.Tiles[i]:Show()
        end
    else
        for i = 1, 12 do view.Tiles[i]:Hide() end
        view.Left:SetTexture(floor.texture .. "a")
        view.Right:SetTexture(floor.texture .. "b")
        view.Left:Show()
        view.Right:Show()
    end
    view.Credit:SetShown(map.artist ~= nil)
    if map.artist then
        view.Credit:SetText(("Map by %s"):format(map.artist))
    end

    -- Boss pins on this floor; bosses without a known position go in the list.
    local bosses = BossesWithPositions(current.key)
    local pinIndex, rowIndex = 0, 0
    for _, boss in ipairs(bosses) do
        if boss.x and boss.floor == index then
            pinIndex = pinIndex + 1
            local button = view.BossButtons[pinIndex] or CreateBossButton(view.Art)
            view.BossButtons[pinIndex] = button
            button.boss, button.total = boss, #bosses
            UpdateBossPin(button)
            button:Show()
        elseif not boss.x then
            rowIndex = rowIndex + 1
            local row = view.ListRows[rowIndex] or CreateListRow(view.List)
            view.ListRows[rowIndex] = row
            row.boss, row.total = boss, #bosses
            row.Text:SetText(boss.name)
            row:SetWidth(row.Text:GetStringWidth() + 24)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", view.List, "TOPLEFT", 8, -24 - (rowIndex - 1) * 18)
            row:Show()
        end
    end
    for i = pinIndex + 1, #view.BossButtons do view.BossButtons[i]:Hide() end
    for i = rowIndex + 1, #view.ListRows do view.ListRows[i]:Hide() end
    view.List:SetShown(rowIndex > 0)
    if rowIndex > 0 then
        local widest = 120
        for i = 1, rowIndex do widest = math.max(widest, view.ListRows[i]:GetWidth() + 16) end
        view.List:SetSize(widest, 30 + rowIndex * 18)
    end

    if view.FloorDropdown then
        view.FloorDropdown:SetShown(#map.floors > 1)
        if view.FloorDropdown.GenerateMenu then view.FloorDropdown:GenerateMenu() end
        if view.FloorDropdown.SetText and not view.FloorDropdown.GenerateMenu then
            view.FloorDropdown:SetText(FloorName(current.key, index))
        end
    end
    if view.StatusBadge then
        local status = ns:InstanceStatus(current.key)
        view.StatusBadge.status = status or false
        view.StatusBadge:SetShown(status ~= nil)
    end
    Layout()
end

local function CreateView()
    local container = WorldMapFrame.ScrollContainer
    view = CreateFrame("Frame", "BeestersDungeonMapsView", container)
    view:SetAllPoints(container)
    view:SetFrameLevel(container:GetFrameLevel() + 1)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function() end) -- don't zoom the hidden map underneath
    view:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns:CloseDungeonMap(true) end -- like zooming out on the map
    end)
    view:SetScript("OnSizeChanged", Layout)
    view:Hide()

    local background = view:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 1)

    view.Art = CreateFrame("Frame", nil, view)
    view.Art:SetPoint("CENTER")
    view.Art:SetClipsChildren(true)
    view.Tiles = {}
    for i = 1, 12 do
        view.Tiles[i] = view.Art:CreateTexture(nil, "ARTWORK")
    end
    view.Left = view.Art:CreateTexture(nil, "ARTWORK")
    view.Left:SetPoint("TOPLEFT")
    view.Right = view.Art:CreateTexture(nil, "ARTWORK")
    view.Right:SetPoint("TOPLEFT", view.Left, "TOPRIGHT")
    view.BossButtons = {}

    view.Credit = view.Art:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.Credit:SetPoint("BOTTOMLEFT", 10, 8)

    -- Where the map would be, for a dungeon that has none yet.
    view.NoMap = CreateFrame("Frame", nil, view.Art)
    view.NoMap:SetAllPoints()
    local parchment = view.NoMap:CreateTexture(nil, "BACKGROUND")
    parchment:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestDetailsBackgrounds") then
        parchment:SetAtlas("QuestDetailsBackgrounds")
    else
        parchment:SetColorTexture(0.24, 0.19, 0.12, 1)
    end
    view.NoMap.Title = view.NoMap:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    view.NoMap.Title:SetPoint("BOTTOM", view.NoMap, "CENTER", 0, 12)
    view.NoMap.Title:SetTextColor(0.18, 0.12, 0.06)
    view.NoMap.Title:SetText("Work in progress")
    view.NoMap.Text = view.NoMap:CreateFontString(nil, "ARTWORK", "QuestFont")
    view.NoMap.Text:SetPoint("TOP", view.NoMap, "CENTER", 0, 0)
    view.NoMap.Text:SetWidth(380)
    view.NoMap.Text:SetTextColor(0.18, 0.12, 0.06)
    view.NoMap:Hide()

    -- Bosses whose place on the map isn't known yet.
    view.List = CreateFrame("Frame", nil, view.Art, BackdropTemplateMixin and "BackdropTemplate")
    view.List:SetPoint("BOTTOMRIGHT", -10, 10)
    view.List:SetFrameLevel(view.Art:GetFrameLevel() + 5) -- over the no-map notice
    if view.List.SetBackdrop then
        view.List:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        view.List:SetBackdropColor(0, 0, 0, 0.75)
        view.List:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    end
    view.List.Title = view.List:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    view.List.Title:SetPoint("TOPLEFT", 8, -8)
    view.List.Title:SetText(BOSSES or "Bosses")
    view.ListRows = {}

    -- Floor picker, like the game's own floor dropdown on multi-level maps.
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetPoint("TOPLEFT", 12, -10)
        dropdown:SetWidth(190)
        dropdown:SetupMenu(function(_, root)
            local map = current.key and ns.DungeonMaps[current.key]
            if not map then return end
            local counts = BossesPerFloor(current.key)
            for i = 1, #map.floors do
                local n = counts[i] or 0
                local label = FloorName(current.key, i) .. (n > 0 and ("  |cff9d9d9d(%d %s)|r"):format(n, n == 1 and "boss" or "bosses") or "")
                root:CreateRadio(label,
                    function() return current.floor == i end,
                    function() LearnFloorHere(current.key, i); ShowFloor(i) end)
            end
        end)
    else
        dropdown = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        dropdown:SetPoint("TOPLEFT", 12, -10)
        dropdown:SetSize(190, 22)
        dropdown:SetScript("OnClick", function()
            local map = ns.DungeonMaps[current.key]
            ShowFloor(current.floor % #map.floors + 1)
        end)
    end
    view.FloorDropdown = dropdown

    -- "Work in progress" tag, top right, for instances whose data isn't complete yet.
    local badge = CreateFrame("Button", nil, view, BackdropTemplateMixin and "BackdropTemplate")
    badge:SetPoint("TOPRIGHT", -12, -12)
    badge:SetHeight(24)
    if badge.SetBackdrop then
        badge:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        badge:SetBackdropColor(0, 0, 0, 0.8)
        badge:SetBackdropBorderColor(WIP_COLOR.r, WIP_COLOR.g, WIP_COLOR.b, 0.9)
    end
    badge.Icon = badge:CreateTexture(nil, "ARTWORK")
    badge.Icon:SetSize(14, 14)
    badge.Icon:SetPoint("LEFT", 7, 0)
    badge.Icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    badge.Text = badge:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    badge.Text:SetPoint("LEFT", badge.Icon, "RIGHT", 4, 0)
    badge.Text:SetTextColor(WIP_COLOR.r, WIP_COLOR.g, WIP_COLOR.b)
    badge.Text:SetText("Work in progress")
    badge:SetWidth(badge.Text:GetStringWidth() + 36)
    badge:SetScript("OnEnter", function(self) if self.status then ShowStatusTooltip(self, self.status) end end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:Hide()
    view.StatusBadge = badge
end

----------------------------------------------------------------------
-- Opening and closing
----------------------------------------------------------------------

function ns:IsDungeonMapOpen()
    return view ~= nil and view:IsShown()
end

function ns:CurrentDungeonFloor() return current.floor end

function ns:CurrentDungeonKey()
    return current.key
end

-- In combat the game won't let us hide its map picture (its pins are protected), so ours
-- would open underneath it. Then ours goes up one layer, over the game's, until combat ends.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG" }
local canvasRetry

local function LiftView(lift)
    if not view then return end
    local base = WorldMapFrame:GetFrameStrata()
    local strata = base
    if lift then
        for i, name in ipairs(STRATA) do
            if name == base then strata = STRATA[math.min(i + 1, #STRATA)] end
        end
    end
    if view:GetFrameStrata() ~= strata then view:SetFrameStrata(strata) end
    if lootPanel then lootPanel:SetFrameStrata(lift and STRATA[#STRATA] or "DIALOG") end
end

local function SetCanvasShown(shown)
    local child = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not child then return end
    if InCombatLockdown() then
        -- Hands off the game's map; cover it instead, and sort it out after combat.
        LiftView(not shown)
        canvasRetry = canvasRetry or CreateFrame("Frame")
        canvasRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
        canvasRetry:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            SetCanvasShown(not ns:IsDungeonMapOpen())
        end)
        return
    end
    child:SetShown(shown)
    LiftView(false)
end

-- Change the world map the way the game itself does. Calling WorldMapFrame:SetMapID (or
-- ShowUIPanel) from an addon taints the map: later, in combat, the game's own quest pins then
-- trip over a locked function (ADDON_ACTION_BLOCKED ... SetPassThroughButtons), even when you
-- just close the map. C_Map.OpenWorldMap asks the game to do it (WORLD_MAP_OPEN): the map's
-- own code opens and switches it, so nothing of ours sticks to the map. That function is
-- restricted, so in combat we don't move the map at all and use the map that's showing.
-- after() runs once the map is there.
local function FinishPending(p)
    if pendingMap ~= p then return end
    pendingMap = nil
    if p.keepQuests then ns.keepQuestPanel = true end
    ns:CloseDungeonMap(false)
    ns.keepQuestPanel = false
    if p.after then p.after() end
end

local function OnTarget(mapID)
    return WorldMapFrame:IsShown() and (not mapID or WorldMapFrame:GetMapID() == mapID)
end

function ns:GoToMap(mapID, after, keepQuests)
    if OnTarget(mapID) or (InCombatLockdown() and WorldMapFrame:IsShown()) then
        if after then after() end
        return
    end
    if InCombatLockdown() then return end -- map closed and in combat: nothing we can safely do
    local p = { mapID = mapID, after = after, keepQuests = keepQuests }
    pendingMap = p
    if C_Map.OpenWorldMap then
        C_Map.OpenWorldMap(mapID)
    else
        p.direct = true
    end
    -- The switch may happen right away, a frame later, or not at all (already on that map,
    -- or the game didn't let it through). Then fall back to switching the map ourselves.
    C_Timer.After(0, function()
        if pendingMap ~= p then return end
        if not OnTarget(mapID) and not InCombatLockdown() then
            if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
            if mapID and WorldMapFrame:GetMapID() ~= mapID then WorldMapFrame:SetMapID(mapID) end
        end
        if pendingMap == p and OnTarget(mapID) then FinishPending(p) end
        pendingMap = nil
    end)
end

function ns:OpenDungeonMap(key, floor)
    if not (ns.DungeonMaps and ns.DungeonMaps[key]) then
        ns:Print(("No map for %s yet."):format(ns.Instances[key] and ns.Instances[key].name or key))
        return
    end
    if not view then CreateView() end

    -- Stay on the current map when it shows this dungeon's entrance; otherwise go to the
    -- entrance's zone, so the top bar reads World > Kalimdor > Durotar > Ragefire Chasm.
    local target
    local mapID = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local onZone = info and info.mapType >= Enum.UIMapType.Zone
    if onZone and ns:MapShowsDungeon(mapID, key) then
        target = mapID
    else
        target = ns:EntranceMapFor(key) or mapID or nil
    end

    ns:GoToMap(target, function()
        if key == "dme" or key == "dmn" or key == "dmw" then
            ns.db.lastDireMaulWing = key
        end
        current.key = key
        -- Inside this dungeon: the level you're on. Otherwise where a group starts.
        local inside = ns.CurrentInstanceKey and ns.CurrentInstanceKey() == key
        local here = inside and FloorHere(key)
        current.floor = floor or here or (inside and RunFloor(key)) or DefaultFloor(key) -- before Show: its layout reads it
        current.zoneMapID = WorldMapFrame:GetMapID()
        SetCanvasShown(false)
        view:Show()
        ShowFloor(current.floor)
        if ns.UpdateDungeonCrumb then ns:UpdateDungeonCrumb() end
        if ns.ShowDungeonQuests then ns:ShowDungeonQuests(key) end
    end)
end

function ns:CloseDungeonMap(refreshNavBar)
    if not ns:IsDungeonMapOpen() then return end
    view:Hide()
    if lootPanel then lootPanel:Hide() end
    if ns.HideDungeonQuests then ns:HideDungeonQuests() end
    current.key = nil
    current.zoneMapID = nil
    SetCanvasShown(true)
    if refreshNavBar and ns.UpdateDungeonCrumb then ns:UpdateDungeonCrumb() end
end

-- Which of our dungeons is the player in right now?
local function CurrentInstanceKey()
    local inInstance = IsInInstance()
    if not inInstance then return nil end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local key = ns.InstanceByMap and ns.InstanceByMap[instanceID]
    if key == "dme" and ns.db.lastDireMaulWing then
        key = ns.db.lastDireMaulWing
    end
    return key
end
ns.CurrentInstanceKey = CurrentInstanceKey

----------------------------------------------------------------------
-- Top bar (breadcrumb): World > Kalimdor > Durotar > Dungeons / Ragefire Chasm
----------------------------------------------------------------------

local function DungeonMenuList(mapID)
    local list = {}
    for _, key in ipairs(ns:DungeonsOnMap(mapID)) do
        if ns.DungeonMaps[key] then
            table.insert(list, {
                text = ns.Instances[key].name,
                id = key,
                func = function(_, id) ns:OpenDungeonMap(id) end,
            })
        end
    end
    for _, key in ipairs(ns:ZoneOnlyDungeonsOnMap(mapID)) do
        table.insert(list, { text = ns.Instances[key].name, id = key, func = function(_, id) ns:OpenDungeonMap(id) end })
    end
    for _, instance in ipairs(ns:ComingSoonOnMap(mapID)) do
        table.insert(list, { text = instance.name .. "  |cff9d9d9d(coming soon)|r", soon = instance })
    end
    return list
end

-- Our crumb is a button of our own, made from the game's crumb template but never part of the
-- bar's own list. Adding it with NavBar_AddButton would hand the bar a button whose click
-- handler was set up by addon code; when the bar later reuses that button for a zone, clicking
-- it switches the map "as the addon", and in combat that trips ADDON_ACTION_BLOCKED.
local crumb
local function GetCrumb(navBar)
    if crumb then return crumb end
    crumb = CreateFrame("Button", nil, navBar, "NavButtonTemplate")
    crumb:SetScript("OnShow", nil) -- the template's OnShow would wire the menu to the bar's list
    -- The crumb's own art, set again explicitly (same files as the game's crumbs).
    crumb:SetNormalTexture("Interface\\HelpFrame\\CS_HelpTextures_Tile")
    crumb:SetPushedTexture("Interface\\HelpFrame\\CS_HelpTextures_Tile")
    crumb:SetHighlightTexture("Interface\\HelpFrame\\CS_HelpTextures", "ADD")
    local normal, pushed, highlight = crumb:GetNormalTexture(), crumb:GetPushedTexture(), crumb:GetHighlightTexture()
    if normal then normal:SetTexCoord(0, 1, 0.0625, 0.12109375); normal:SetHorizTile(true) end
    if pushed then pushed:SetTexCoord(0, 1, 0.125, 0.18359375); pushed:SetHorizTile(true) end
    if highlight then highlight:SetTexCoord(0.00195313, 0.25195313, 0.65625, 0.921875) end
    crumb:RegisterForClicks("LeftButtonUp")
    crumb:SetScript("OnClick", function(self)
        local arrow = rawget(self, "MenuArrowButton")
        if type(arrow) == "table" and arrow.OpenMenu then arrow:OpenMenu() end
    end)
    local arrow = rawget(crumb, "MenuArrowButton")
    if type(arrow) == "table" and arrow.SetupMenu then
        arrow:SetupMenu(function(_, rootDescription)
            for _, entry in ipairs(crumb.listFunc and crumb.listFunc() or {}) do
                if entry.soon then
                    -- Greyed out: known, but the addon has no data for it yet.
                    local soon = entry.soon
                    local button = rootDescription:CreateButton(entry.text, function() end)
                    if button.SetEnabled then button:SetEnabled(false) end
                    if button.SetTooltip then
                        button:SetTooltip(function(tooltip)
                            GameTooltip_SetTitle(tooltip, soon.name)
                            local kind = soon.kind == "raid" and (RAID or "Raid") or (LFG_TYPE_DUNGEON or "Dungeon")
                            GameTooltip_AddNormalLine(tooltip, kind .. " · " .. (LEVEL or "Level") .. " " .. soon.levels
                                .. (soon.size and (" · " .. soon.size) or ""))
                            GameTooltip_AddHighlightLine(tooltip, "New in WoW Forever. Its map, bosses and loot aren't in the addon yet.", true)
                        end)
                    end
                else
                    rootDescription:CreateButton(entry.text, function() entry.func(nil, entry.id) end)
                end
            end
        end)
        arrow:Show()
    end
    crumb:Hide()
    ns.DungeonCrumb = crumb -- read by tools/test_addon.py
    return crumb
end

local DecorateNavBar
function ns:UpdateDungeonCrumb()
    if WorldMapFrame.NavBar then DecorateNavBar(WorldMapFrame.NavBar) end
end

DecorateNavBar = function(navBar)
    if crumb then crumb:Hide() end
    local list = navBar.navList
    local last = type(list) == "table" and list[#list]
    if not last then return end
    -- The zone's crumb as the game left it: the current map, selected and not clickable.
    local lastSel = rawget(last, "selected")
    if type(lastSel) == "table" then lastSel:Show() end
    last:Disable()
    if not ns.db or not ns.db.dungeonsInTopBar then return end

    local name, listFunc
    if ns:IsDungeonMapOpen() then
        name = ns.Instances[current.key].name
        -- The dungeons of the zone the map was on. When the dungeon opened over the world or a
        -- continent view (inside it, or during combat) that can be none: then its entrance's zone.
        listFunc = function()
            local entries = DungeonMenuList(current.zoneMapID)
            if #entries == 0 then entries = DungeonMenuList(ns:EntranceMapFor(current.key)) end
            return entries
        end
    elseif #DungeonMenuList(WorldMapFrame:GetMapID()) > 0 then
        name = DUNGEONS or "Dungeons"
        -- Read the map when the list opens, not when the bar was built.
        listFunc = function() return DungeonMenuList(WorldMapFrame:GetMapID()) end
    else
        return
    end

    local c = GetCrumb(navBar)
    c.name, c.listFunc = name, listFunc
    c:SetText(name)
    local label = rawget(c, "text")
    c:SetWidth((type(label) == "table" and label:GetStringWidth() or 60) + 53)
    c:ClearAllPoints()
    c:SetPoint("LEFT", last, "RIGHT", tonumber(rawget(last, "xoffset")) or 0, 0)
    -- The game stacks each crumb above the one after it, so a crumb's arrow overlaps the next
    -- one. Ours comes last, so it goes underneath the zone's crumb.
    local barLevel = navBar.GetFrameLevel and navBar:GetFrameLevel() or 0
    if last:GetFrameLevel() - 1 <= barLevel then
        for _, button in ipairs(list) do button:SetFrameLevel(button:GetFrameLevel() + 1) end
    end
    c:SetFrameLevel(last:GetFrameLevel() - 1)
    -- Ours is the bar's last crumb now, so it gets the "selected" look; the zone before it
    -- looks and works like any other crumb (its click is the game's own, so it stays clean).
    local sel = rawget(c, "selected")
    if type(sel) == "table" then sel:Show() end
    c:Enable()
    c:SetButtonState("NORMAL")
    if type(lastSel) == "table" then lastSel:Hide() end
    last:Enable()
    c:Show()
end

----------------------------------------------------------------------
-- Set-up
----------------------------------------------------------------------

function ns:InitDungeonMap()
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer and ns.DungeonMaps) then return end

    -- Any map change we didn't make ourselves closes the dungeon map.
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        local p = pendingMap
        if p and p.mapID and WorldMapFrame:GetMapID() == p.mapID then
            FinishPending(p)
        elseif not p then
            ns:CloseDungeonMap(false)
        end
    end)
    local navBar = WorldMapFrame.NavBar
    if navBar then
        if navBar.Refresh then hooksecurefunc(navBar, "Refresh", DecorateNavBar) end
        -- Clicking a crumb for the map we're already on doesn't change the map; still close.
        if navBar.GoToMap then
            hooksecurefunc(navBar, "GoToMap", function() ns:CloseDungeonMap(true) end)
        end
    end

    -- Inside a dungeon the game has no map, so open ours when the map opens.
    WorldMapFrame:HookScript("OnShow", function()
        if not ns.db.autoOpenInside then return end
        local key = CurrentInstanceKey()
        if key and ns.DungeonMaps[key] then
            C_Timer.After(0, function()
                if WorldMapFrame:IsShown() and not ns:IsDungeonMapOpen() and not pendingMap then
                    ns:OpenDungeonMap(key)
                end
            end)
        end
    end)
    -- Walking to another level with the map open turns the page, like the game's own maps.
    local zoneWatcher = CreateFrame("Frame")
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do pcall(zoneWatcher.RegisterEvent, zoneWatcher, event) end
    zoneWatcher:SetScript("OnEvent", function()
        if not (ns:IsDungeonMapOpen() and current.key and CurrentInstanceKey() == current.key) then return end
        local here = FloorHere(current.key)
        if here and here ~= current.floor then ShowFloor(here) end
    end)

    -- Leaving the dungeon ends the run; a boss pulled or targeted tells which level you're on.
    local runWatcher = CreateFrame("Frame", "BeestersDungeonMapsRunWatcher")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ENCOUNTER_START", "PLAYER_TARGET_CHANGED" }) do
        pcall(runWatcher.RegisterEvent, runWatcher, event)
    end
    runWatcher:SetScript("OnEvent", function(_, event, encounterID, encounterName)
        local key = CurrentInstanceKey()
        if event == "PLAYER_ENTERING_WORLD" then
            if key ~= run.key then run.key, run.floor = nil, nil end
            return
        end
        if not key then return end
        local floor
        -- Names inside instances can be hidden from addons ("secret" values): never fail on one.
        pcall(function()
            if event == "ENCOUNTER_START" then
                floor = BossFloor(key, encounterID, encounterName)
            elseif UnitExists("target") and not UnitIsPlayer("target") then
                floor = BossFloor(key, nil, UnitName("target"))
            end
        end)
        if not floor then return end
        NoteRunFloor(key, floor)
        -- A boss pulled here stands on this level: remember the subzone (targeting can reach
        -- across levels, so only a pull counts).
        if event == "ENCOUNTER_START" then LearnFloorHere(key, floor) end
        if ns:IsDungeonMapOpen() and current.key == key and current.floor ~= floor then ShowFloor(floor) end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        ns:CloseDungeonMap(false)
        if ns.ClearQuestMarker then ns:ClearQuestMarker() end
    end)
    ns.dungeonMapActive = true
end
