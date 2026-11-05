#!/usr/bin/env python3
"""Load the addon in a small fake WoW environment and check that it starts and places pins.

This does not replace testing in the game. It catches syntax errors, missing names and
broken logic before a build reaches the game.
Requires: pip install lupa
"""
import sys
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "BeestersDungeonMaps"

FAKE_WOW = r"""
local NUMBERS = { GetWidth = 100, GetHeight = 50, GetStringWidth = 60, GetStringHeight = 14, GetFrameLevel = 5 }
local function anything()
    local t = { _shown = true }
    return setmetatable(t, { __index = function(self, key)
        local f
        if NUMBERS[key] then
            f = function() return NUMBERS[key] end
        elseif key == "GetSize" then
            f = function() return 800, 533 end
        elseif key == "Show" then
            f = function(s) s._shown = true end
        elseif key == "Hide" then
            f = function(s) s._shown = false end
        elseif key == "SetShown" then
            f = function(s, v) s._shown = v and true or false end
        elseif key == "IsShown" then
            f = function(s) return s._shown end
        elseif key == "HookScript" or key == "SetScript" then
            f = function(s, event, fn) local sc = rawget(s, "scripts") or {}; rawset(s, "scripts", sc); sc[event] = fn end
        elseif key == "GetFontString" then
            f = function() return nil end
        elseif key == "CreateFontString" or key == "CreateTexture" then
            f = function() return anything() end
        elseif key == "GetAtlas" or key == "GetTexture" then
            f = function() return nil end
        else
            f = function() return self end
        end
        rawset(self, key, f)
        return f
    end })
end

function hooksecurefunc(target, name, hook)
    if type(target) == "string" then target, name, hook = _G, target, name end
    local original = target[name]
    target[name] = function(...)
        local a, b, c, d = original(...)
        hook(...)
        return a, b, c, d
    end
end
C_Timer = { After = function(_, fn) fn() end }
-- Quality = id % 4. Bind on Pickup unless the id is a multiple of 100 + 50 (Bind on Equip).
C_Item = { GetItemInfo = function(id) return "Item " .. id, "|Hitem:" .. id .. "|h", id % 4, nil, nil, nil, nil, nil, nil, 134400, nil, nil, nil, (id % 100 == 50) and 2 or 1 end }
-- Item kinds by the last digit: 0-1 weapon, 2 trinket, 3 head, 4/8 recipe (Tailoring/Alchemy), others misc.
C_Item.GetItemInfoInstant = function(id)
    local d = id % 10
    if d <= 1 then return id, "Weapon", "Swords", "INVTYPE_WEAPON", 0, 2, 7 end
    if d == 2 then return id, "Armor", "Miscellaneous", "INVTYPE_TRINKET", 0, 4, 0 end
    if d == 3 then return id, "Armor", "Cloth", "INVTYPE_HEAD", 0, 4, 1 end
    if d == 4 then return id, "Recipe", "Tailoring", "", 0, 9, 2 end
    if d == 8 then return id, "Recipe", "Alchemy", "", 0, 9, 6 end
    return id, "Miscellaneous", "Junk", "", 0, 15, 0
end
ITEM_QUALITY_COLORS = { [0] = { r = .6, g = .6, b = .6 }, { r = 1, g = 1, b = 1 }, { r = .1, g = 1, b = 0 }, { r = 0, g = .4, b = 1 }, { r = .6, g = .2, b = 1 } }
shiftDown = false

function IsShiftKeyDown() return shiftDown end
function SetCursor() end
function ResetCursor() end
function GetCursorPosition() return 450, 250 end
function ShowUIPanel(frame) frame:Show() end
navButtons = {}
function NavBar_AddButton(navBar, data) table.insert(navButtons, data) end
function CreateFrame(kind, name, parent, template)
    local frame = anything()
    frame.GetChecked = function() return true end
    frame.Text = anything()
    frame.Low = anything()
    frame.High = anything()
    if name then _G[name] = frame end
    return frame
end

function CreateFromMixins(...)
    local result = {}
    for _, mixin in ipairs({ ... }) do for k, v in pairs(mixin) do result[k] = v end end
    return result
end
MapCanvasPinMixin = { GetMap = function(self) return self.owningMap end }
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }

-- A small piece of the real map tree.
local maps = {
    [947]  = { name = "Azeroth", mapType = 1, parentMapID = 946 },
    [1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1413] = { name = "The Barrens", mapType = 3, parentMapID = 1414 },
    [1420] = { name = "Tirisfal Glades", mapType = 3, parentMapID = 1415 },
    -- As in the real client: cities hang under the continent, not under their zone.
    [1458] = { name = "Undercity", mapType = 3, parentMapID = 1415 },
}
setmetatable(maps, { __index = function(_, id) return { name = "Zone " .. id, mapType = 3, parentMapID = 0 } end })
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetMapRectOnMap = function(child, parent) return 0.4, 0.6, 0.3, 0.5 end,
    GetBestMapForUnit = function() return 1413 end,
    GetMapArtLayers = function(id) if id == 279 then return { {} } end return nil end,
}
function IsInInstance() return false, "none" end
function InCombatLockdown() return inCombat == true end
function GetInstanceInfo() return "Wailing Caverns", "party", 1, "Normal", 5, 0, false, 43 end
C_Texture = { GetAtlasInfo = function(atlas) return nil end }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0-test" end }
function GetBuildInfo() return "1.60.1", "70753", "Nov 4 2026", 16001 end

SlashCmdList = { OTHERADDON = function() end }
SLASH_OTHERADDON1 = "/other"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
GREEN_FONT_COLOR = { r = 0.1, g = 1, b = 0.1 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
GRAY_FONT_COLOR = { r = .5, g = .5, b = .5 }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("[chat] " .. msg) end }
GameTooltip = anything()
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return name end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) print("[settings] opened " .. id) end,
}

acquired = {}
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.providers = {}
WorldMapFrame.mapID = 1413
WorldMapFrame.AddDataProvider = function(self, provider) provider.owningMap = self; table.insert(self.providers, provider) end
WorldMapFrame.GetMapID = function(self) return self.mapID end
WorldMapFrame.RemoveAllPinsByTemplate = function() acquired = {} end
WorldMapFrame.AcquirePin = function(self, template, entrance, x, y, kind)
    table.insert(acquired, { entrance = entrance, x = x, y = y, kind = kind })
end
WorldMapFrame.ScrollContainer = CreateFrame("Frame")
WorldMapFrame.ScrollContainer.Child = CreateFrame("Frame")
WorldMapFrame.NavBar = {
    Refresh = function(self) navButtons = {} end,
    navList = { CreateFrame("Button") }, -- the game's own crumbs (World ... zone)
    GoToMap = function(self, mapID) WorldMapFrame:SetMapID(mapID) end,
}
WorldMapFrame.OnMapChanged = function(self) self.NavBar:Refresh() end
-- The game's own map switch (C_Map.OpenWorldMap fires WORLD_MAP_OPEN, the map's code does
-- ShowUIPanel + SetMapID). Any SetMapID outside it comes from addon code and taints the map.
local gameSwitching = false
addonSetMapID = 0
WorldMapFrame.SetMapID = function(self, mapID)
    if not gameSwitching then addonSetMapID = addonSetMapID + 1 end
    if mapID ~= self.mapID then self.mapID = mapID; self:OnMapChanged() end
end
C_Map.OpenWorldMap = function(mapID)
    gameSwitching = true
    WorldMapFrame:Show()
    if mapID then WorldMapFrame:SetMapID(mapID) end
    gameSwitching = false
end
-- Quest log: Ragefire Chasm's quests for a Horde character (5722 handed in, 5723 in the log).
QuestScrollFrame = CreateFrame("ScrollFrame")
QuestMapFrame = CreateFrame("Frame")
QuestMapFrame.QuestsFrame = CreateFrame("Frame")
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return id == 5722 end,
    GetLogIndexForQuestID = function(id) if id == 5723 then return 3 elseif id == 5726 then return 4 end end,
    ReadyForTurnIn = function(id) return false end,
    IsComplete = function(id) return false end,
    GetQuestObjectives = function(id) return { { text = "0/8 Ragefire Trogg slain" } } end,
    GetQuestWatchType = function() return nil end,
}
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 14 end
function UnitName() return "Beester" end
function UnitRace() return "Orc" end
function UnitSex() return 2 end
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end
"""

def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE_WOW)
    run_file = lua.eval("function(code, chunkname, ns) local f, err = load(code, chunkname); if not f then error(err) end; return f('BeestersDungeonMaps', ns) end")
    ns = lua.table()

    toc = (ADDON / "BeestersDungeonMaps.toc").read_text(encoding="utf-8").splitlines()
    for line in toc:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = ADDON / line.replace("\\", "/")
        if path.suffix == ".lua":
            run_file(path.read_text(encoding="utf-8"), "@" + line, ns)
            print("loaded", line)
        else:
            print("skipped (XML, checked in game)", line)

    checks = lua.eval(r"""function(ns)
        local results = {}
        local function check(name, ok) table.insert(results, (ok and "PASS " or "FAIL ") .. name) end

        -- Start-up: call the ADDON_LOADED handler.
        -- Core.lua stored no global reference, so re-run its start-up steps the same way the handler does.
        BeestersDungeonMapsDB = nil
        BeestersDungeonMapsDB = {}
        for k, v in pairs(ns.defaults) do BeestersDungeonMapsDB[k] = v end
        ns.db = BeestersDungeonMapsDB
        ns:InitSlashCommands()
        ns:InitOptions()
        ns:InitMapPins()

        check("slash command /bdm registered", SLASH_BEESTERSDUNGEONMAPS1 == "/bdm")
        check("fallback /beesterdm registered", SLASH_BEESTERSDUNGEONMAPS2 == "/beesterdm")
        check("map pins active", ns.mapPinsActive == true)

        local provider = WorldMapFrame.providers[1]
        local function pinsOn(mapID)
            WorldMapFrame.mapID = mapID
            WorldMapFrame.IsShown = function() return true end
            provider:RefreshAllData()
            return #acquired
        end

        check("The Barrens shows 3 entrances", pinsOn(1413) == 3)
        check("Kalimdor continent shows Barrens entrances", pinsOn(1414) >= 3)
        check("Tirisfal shows Ruins of Lordaeron (from Undercity) and Scarlet Monastery", pinsOn(1420) == 2)
        check("Azeroth world map shows nothing", pinsOn(947) == 0)

        ns.db.showOnContinents = false
        check("continent pins can be turned off", pinsOn(1414) == 0)
        ns.db.showOnContinents = true

        ns.db.showDungeons = false
        check("dungeons can be turned off", pinsOn(1413) == 0)
        ns.db.showDungeons = true

        -- Tooltip and pin code paths
        local pin = CreateFromMixins(BeestersDungeonMapsEntrancePinMixin)
        pin.Icon = CreateFrame("Frame")
        pin.SetPosition = function() end
        pin.SetSize = function() end
        pin.UseFrameLevelType = function() end
        pin.owningMap = WorldMapFrame
        pin.SetScalingLimits = function() end
        pin:OnLoad()
        pin:OnAcquired(ns.Entrances[1427][1], 0.5, 0.5, "dungeon")
        pin:OnMouseEnter()
        pin:OnMouseLeave()
        check("pin and tooltip code runs (Blackrock Mountain, 2 dungeons)", true)

        -- Dungeon maps
        ns:InitDungeonMap()
        local mapCount = 0
        for _ in pairs(ns.DungeonMaps) do mapCount = mapCount + 1 end
        check("26 dungeon maps (22 classic, 4 by Santiago Reyes)", mapCount == 26)
        local missingMaps = {}
        for key in pairs(ns.Instances) do if not ns.DungeonMaps[key] then table.insert(missingMaps, key) end end
        check("every dungeon in the list has a map", #missingMaps == 0)
        check("every instance map ID points to a dungeon map", (function()
            for _, key in pairs(ns.InstanceByMap) do if not ns.DungeonMaps[key] then return false end end
            return true end)())

        WorldMapFrame.mapID = 1414 -- Kalimdor
        ns:OpenDungeonMap("wc")
        check("entrance pin opens Wailing Caverns", ns:IsDungeonMapOpen() and ns:CurrentDungeonKey() == "wc")
        check("opened from Kalimdor, the top bar goes through The Barrens", WorldMapFrame:GetMapID() == 1413)
        check("game's map picture hidden under the dungeon map", WorldMapFrame.ScrollContainer.Child:IsShown() == false)
        local view = BeestersDungeonMapsView
        local pins = 0
        for _, b in ipairs(view.BossButtons) do if b:IsShown() then pins = pins + 1 end end
        check("Wailing Caverns shows all 8 bosses as pins (Journal positions)", pins == 8)
        local crumb = ns.DungeonCrumb
        check("top bar ends with Wailing Caverns", crumb and crumb.name == "Wailing Caverns")
        check("the addon never adds buttons to the game's own top bar (taint)", #navButtons == 0)
        local menu = crumb.listFunc()
        check("its menu lists the other Barrens dungeons", #menu >= 3)

        -- Loot: click a boss, see only Uncommon+ items.
        local mutanus
        for _, b in ipairs(view.BossButtons) do if b:IsShown() and b.boss.name == "Mutanus the Devourer" then mutanus = b end end
        mutanus.scripts.OnClick(mutanus, "LeftButton")
        local panel = BeestersDungeonMapsLoot
        local rows, lowQuality = 0, false
        for _, r in ipairs(panel.Rows) do
            if r:IsShown() then
                rows = rows + 1
                if r.itemID % 4 < 2 then lowQuality = true end
            end
        end
        check("clicking a boss opens its loot", panel:IsShown() and rows > 0)
        check("loot shows only Uncommon or better", not lowQuality)
        local function contains(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end end
        check("Charlga Razorflank's loot has the Pronged Reaver", contains(ns.BossLoot[4421], 6692))
        -- The game hasn't loaded the Pronged Reaver: the addon's own item data fills in.
        local realInfo = C_Item.GetItemInfo
        C_Item.GetItemInfo = function(id) if id == 6692 then return nil end return realInfo(id) end
        ns.BossLoot[mutanus.boss.npcID] = { 6692 }
        panel:Hide(); mutanus.scripts.OnClick(mutanus, "LeftButton")
        check("an item the game hasn't loaded yet shows from the addon's own data",
            panel.shown[1] and panel.shown[1][2] == 6692 and ns.LootItems[6692][1] == "Pronged Reaver")
        C_Item.GetItemInfo = realInfo
        check("a rare's shared drop counts as boss loot (Haunting Blade, Lordaeron Captain)", contains(ns.BossLoot[255699], 6641))
        -- Hovering a boss shows its portrait in the tooltip.
        local inserted, portraitID = nil, nil
        GameTooltip_InsertFrame = function(tooltip, frame) inserted = frame end
        SetPortraitTextureFromCreatureDisplayID = function(texture, displayID) portraitID = displayID end
        mutanus.scripts.OnEnter(mutanus)
        check("hovering a boss shows its portrait", inserted ~= nil and portraitID == ns.BossModels[mutanus.boss.npcID])
        -- Fake loot covering every kind, to check the grouping and order.
        ns.BossLoot[mutanus.boss.npcID] = { 15, 22, 13, 30, 34, 38, 27, 42, 43, 150 }
        panel:Hide(); mutanus.scripts.OnClick(mutanus, "LeftButton")
        local order = {}
        for _, e in ipairs(panel.shown) do table.insert(order, e[1] .. ":" .. e[2]) end
        check("loot (Bind on Pickup only) grouped: weapons, armour, trinkets, then recipes by profession, then other",
            table.concat(order, " ") == "gear:30 gear:43 gear:22 gear:42 recipe:38 recipe:34 other:15 other:27")

        -- Placing a boss yourself: shift-drag a listed boss onto the map.
        ns:OpenDungeonMap("scholo")
        local row = view.ListRows[1]
        local placedName = row.boss.name
        view.Art.GetRect = function() return 100, 100, 600, 400 end
        view.Art.GetEffectiveScale = function() return 1 end
        shiftDown = true
        row.scripts.OnDragStart(row)
        row.scripts.OnDragStop(row)
        shiftDown = false
-- Quest log: Ragefire Chasm's quests for a Horde character (5722 handed in, 5723 in the log).
QuestScrollFrame = CreateFrame("ScrollFrame")
QuestMapFrame = CreateFrame("Frame")
QuestMapFrame.QuestsFrame = CreateFrame("Frame")
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return id == 5722 end,
    GetLogIndexForQuestID = function(id) if id == 5723 then return 3 elseif id == 5726 then return 4 end end,
    ReadyForTurnIn = function(id) return false end,
    IsComplete = function(id) return false end,
    GetQuestObjectives = function(id) return { { text = "0/8 Ragefire Trogg slain" } } end,
    GetQuestWatchType = function() return nil end,
}
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 14 end
function UnitName() return "Beester" end
function UnitRace() return "Orc" end
function UnitSex() return 2 end
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end
        local placed = ns.db.bossPositions and ns.db.bossPositions.scholo and ns.db.bossPositions.scholo[placedName]
        check("shift-dragging a listed boss onto the map places it", placed and placed[1] == 1
            and math.abs(placed[2] - 0.583) < 0.01 and math.abs(placed[3] - 0.625) < 0.01)
        local shownPins = 0
        for _, b in ipairs(view.BossButtons) do if b:IsShown() then shownPins = shownPins + 1 end end
        check("the placed boss now shows as a pin", shownPins == 1)
        ns:OpenDungeonMap("rfc")
        local rfcPins = 0
        for _, b in ipairs(view.BossButtons) do if b:IsShown() then rfcPins = rfcPins + 1 end end
        check("Ragefire Chasm shows all 4 classic bosses (placed in game)", rfcPins == 4)
        ns:OpenDungeonMap("wc")

        -- The addon never switches the map itself (that taints it: ADDON_ACTION_BLOCKED in combat).
        check("the addon only changes the map through the game's own map switch", addonSetMapID == 0)
        ns:CloseDungeonMap(true)
        WorldMapFrame.mapID = 1414
        inCombat = true
        ns:OpenDungeonMap("wc")
        check("in combat, opening a dungeon map leaves the map where it is", WorldMapFrame:GetMapID() == 1414 and ns:IsDungeonMapOpen())
        ns:CloseDungeonMap(true)
        inCombat = false
        ns:OpenDungeonMap("wc")

        WorldMapFrame:SetMapID(1415)
        check("changing the map closes the dungeon map", not ns:IsDungeonMapOpen() and WorldMapFrame.ScrollContainer.Child:IsShown())

        -- Open a dungeon somewhere else first: the Dungeons list must follow the map you're on.
        ns:OpenDungeonMap("scholo")
        ns:CloseDungeonMap(true)
        WorldMapFrame.mapID = 1413
        WorldMapFrame.NavBar:Refresh()
        check("top bar on The Barrens offers a Dungeons button", ns.DungeonCrumb.name == "Dungeons")
        local barrensList = ns.DungeonCrumb.listFunc()
        local names = {}
        for _, e in ipairs(barrensList) do names[e.id] = true end
        check("Dungeons on The Barrens lists the Barrens dungeons, not the last one opened",
            names.wc and names.rfk and names.rfd and not names.stocks)

        ns:OpenDungeonMap("dal")
        check("Dalaran opens (Santiago's map, two floors)", ns:IsDungeonMapOpen() and #ns.DungeonMaps.dal.floors == 2)
        local rows = 0
        for _, r in ipairs(view.ListRows) do if r:IsShown() then rows = rows + 1 end end
        check("Dalaran's bosses without a position are listed", rows > 0)
        WorldMapFrame.NavBar:GoToMap(WorldMapFrame:GetMapID())
        check("clicking the current zone in the top bar closes the dungeon map", not ns:IsDungeonMapOpen())

        ns:OpenDungeonMap("sm")
        local smPins = 0
        for _, b in ipairs(view.BossButtons) do if b:IsShown() then smPins = smPins + 1 end end
        ns:CloseDungeonMap(true)

        -- Quest panel
        ns:OpenDungeonMap("rfc")
        local qp = BeestersDungeonMapsQuests
        check("dungeon quest tab opens with the dungeon map", qp and qp:IsShown() and BeestersDungeonMapsQuestTabs:IsShown())
        local texts = {}
        for _, child in ipairs({}) do end
        local rowsShown = 0
        local function collect(frame) end
        local g = ns.ClassifyDungeonQuests("rfc")
        local function has(list, id) for _, e in ipairs(list) do if e.id == id then return e end end end
        print("rfc groups: log " .. #g.log .. ", available " .. #g.available .. ", inside " .. #g.inside .. ", done " .. #g.done)
        for _, name in ipairs({ "log", "available", "inside", "done" }) do
            for _, e in ipairs(g[name]) do print("  " .. name, e.id, e.q[1], e.q[4] or "-", e.steps and #e.steps or "", e.tooLow and "too low" or "") end
        end
        check("handed-in quest goes to Handed in", has(g.done, 5722) ~= nil)
        check("quest in your log goes to Dungeon quests", has(g.log, 5723) ~= nil)
        local hidden = has(g.log, 5728) or has(g.available, 5728)
        check("a chain you've started (step 1 in your log) shows under Dungeon quests",
            has(g.log, 5728) ~= nil and has(g.log, 5728).step == 1 and #has(g.log, 5728).steps == 3)
        local wc = ns.ClassifyDungeonQuests("wc")
        local listed, nested, fang = {}, false, nil
        for _, list in ipairs({ wc.log, wc.available }) do for _, e in ipairs(list) do listed[e.id] = true if e.q[1]:find("Leaders of the Fang") then fang = e end end end
        for _, list in ipairs({ wc.log, wc.available }) do for _, e in ipairs(list) do
            for i = 1, #(e.steps or {}) - 1 do if listed[e.steps[i]] then nested = true end end
        end end
        check("a dungeon quest that is a step of a longer chain isn't listed again", not nested)
        check("Leaders of the Fang carries the earlier dungeon quests in its chain", fang and fang.dungeonSteps and next(fang.dungeonSteps) ~= nil)
        -- A folded chain still shows the step you're on: the fold toggle plus that step.
        ns:OpenDungeonMap("rfc")
        local steps = 0
        for _, f in ipairs(ns.QuestPanelPools.step) do if f:IsShown() then steps = steps + 1 end end
        check("a folded chain still shows the step you're on", steps >= 2)
        -- WoW Forever's new requirements (tools/quest_prereqs.json) turn these into chains.
        local rol = ns.ClassifyDungeonQuests("rol")
        local function find(g, id) for _, list in pairs(g) do for _, e in ipairs(list) do if e.id == id then return e end end end end
        local rath, torment = find(rol, 92422), find(rol, 97292)
        check("The Wrath of Rath'mael starts with Rear Guard Patrol", rath and rath.steps and #rath.steps == 3 and rath.steps[1] == 356)
        check("Unending Torment is one chain of five", torment and torment.steps and #torment.steps == 5 and not find(rol, 97288) and not find(rol, 97291))
        local function inGroup(list, id) for _, e in ipairs(list) do if e.id == id then return true end end end
        check("Unending Torment starts inside (the head drops in the dungeon)", inGroup(rol.inside, 97292))
        local allianceOnly = false
        for _, list in pairs(g) do for _, e in ipairs(list) do if e.q[4] == "A" then allianceOnly = true end end end
        check("no Alliance-only quests for a Horde character", not allianceOnly)
        -- Detail page with the Classic database's text and rewards (The Power to Destroy...).
        local ok, err = pcall(ns.ShowQuestDetail, 5725)
        check("detail page opens for a quest with choice rewards" .. (ok and "" or (": " .. tostring(err))), ok and qp.Detail:IsShown())
        local entry = has(g.log, 5728)
        ok, err = pcall(ns.ShowQuestDetail, 5728, entry)
        check("detail page opens for a chain step" .. (ok and "" or (": " .. tostring(err))), ok)
        check("detail page has quest text for Ragefire Chasm quests", ns.QuestText and ns.QuestText[5725] ~= nil)
        -- Experience: from the data (5725 at its level), and the game's own number when it has one.
        local function special()
            local out = {}
            for i = 1, qp.Detail.buttonCount do local b = qp.Detail.buttons[i]; if b.special then table.insert(out, b.special.text) end end
            return table.concat(out, ",")
        end
        ns.ShowQuestDetail(5725)
        check("quest details show experience from the data", ns.QuestText[5725][7] > 0 and special():find("%d") ~= nil)
        GetQuestLogRewardXP = function(id) return id == 92422 and 4600 or 0 end
        GetNumQuestLogChoices = function(id) return id == 92422 and 2 or 0 end
        GetQuestLogChoiceInfo = function(i, id) return "x", 1, 1, 3, true, 251532 + i end
        ns.ShowQuestDetail(92422)
        check("quest details use the game's experience and rewards when it has them", special() == "4600")
        GetQuestLogRewardXP, GetNumQuestLogChoices, GetQuestLogChoiceInfo = nil, nil, nil
        -- Show on map keeps the dungeon's quests open; the dungeon tab brings the map back.
        local before = addonSetMapID
        ns:ShowQuestMarker(1454, 0.5, 0.5, "Hidden Enemies", "Pick up: Thrall")
        check("Show on map moves the map through the game's own map switch", addonSetMapID == before and WorldMapFrame:GetMapID() == 1454)
        check("Show on map keeps the dungeon quest tab open", qp:IsShown() and BeestersDungeonMapsQuestTabs:IsShown()
            and not ns:IsDungeonMapOpen())
        BeestersDungeonMapsQuestTabs.Dungeon.scripts.OnClick()
        check("the dungeon tab brings the dungeon map back", ns:IsDungeonMapOpen() and ns:CurrentDungeonKey() == "rfc")
        local used = 0
        for _, r in ipairs({ qp.Child }) do used = used + 1 end
        check("quest list has rows", qp.Child ~= nil)
        ns:CloseDungeonMap(true)
        check("quest tab closes with the dungeon map", not qp:IsShown() and not BeestersDungeonMapsQuestTabs:IsShown())

        IsInInstance = function() return true, "party" end
        GetInstanceInfo = function() return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 end
        WorldMapFrame.scripts.OnShow()
        check("opening the map inside Ragefire Chasm shows its map", ns:CurrentDungeonKey() == "rfc")
        WorldMapFrame.scripts.OnHide()
        check("closing the map closes the dungeon map", not ns:IsDungeonMapOpen())
        IsInInstance = function() return false, "none" end

        local pinFrame = CreateFromMixins(BeestersDungeonMapsEntrancePinMixin)
        pinFrame.entrance = ns.Entrances[1413][2]
        pinFrame:OnClick("LeftButton")
        check("clicking an entrance pin opens that dungeon", ns:CurrentDungeonKey() == "wc")
        ns:CloseDungeonMap(true)

        SlashCmdList.BEESTERSDUNGEONMAPS("status")
        SlashCmdList.BEESTERSDUNGEONMAPS("probe")
        IsInInstance = function() return true, "party" end
        SlashCmdList.BEESTERSDUNGEONMAPS("probe")
        SlashCmdList.BEESTERSDUNGEONMAPS("")
        check("slash command runs", true)
        return table.concat(results, "\n")
    end""")
    output = checks(ns)

    # The world map refuses pin templates that set their own OnEnter/OnLeave scripts
    # (assertion in MapCanvasMixin:AcquirePin); hovering must come from the mixin.
    import re
    xml = (ADDON / "MapPins.xml").read_text(encoding="utf-8")
    bad = re.search(r"<(OnEnter|OnLeave)\b", xml)
    output += "\n" + ("FAIL" if bad else "PASS") + " map pin template has no OnEnter/OnLeave scripts"
    motion = 'enableMouseMotion="true"' in xml
    output += "\n" + ("PASS" if motion else "FAIL") + " map pin template enables mouse motion (tooltips)"
    print(output)
    if "FAIL" in output:
        sys.exit(1)


if __name__ == "__main__":
    main()
