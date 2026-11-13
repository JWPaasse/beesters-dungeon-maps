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
    [1446] = { name = "Un'Goro Crater", mapType = 3, parentMapID = 1414 },
    [1450] = { name = "Mount Hyjal", mapType = 3, parentMapID = 1414 },
}
setmetatable(maps, { __index = function(_, id) return { name = "Zone " .. id, mapType = 3, parentMapID = 0 } end })
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetMapRectOnMap = function(child, parent) return 0.4, 0.6, 0.3, 0.5 end,
    GetBestMapForUnit = function() return 1413 end,
    GetMapArtLayers = function(id) if id == 279 then return { {} } end return nil end,
    GetMapChildrenInfo = function(id, mapType, all)
        local list = {}
        for mapID, info in pairs(maps) do
            if info.mapType == mapType then table.insert(list, { mapID = mapID, name = info.name }) end
        end
        return list
    end,
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
UIParent = CreateFrame("Frame")
Minimap = CreateFrame("Frame")
UISpecialFrames = {}
chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn) chatFilters[event] = fn end
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
        local mapCount, placeholders = 0, 0
        for _, m in pairs(ns.DungeonMaps) do
            if m.placeholder then placeholders = placeholders + 1 else mapCount = mapCount + 1 end
        end
        check("26 dungeon maps (22 classic, 4 by Santiago Reyes)", mapCount == 26)
        check("the 5 new dungeons without a map get a page", placeholders == 5)
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
        ns:OpenDungeonMap("scholo")
        check("Scholomance opens on a floor with bosses, not its empty entrance level", ns:CurrentDungeonFloor() ~= 1)
        ns:CloseDungeonMap(true)
        local function contains(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end end
        check("Charlga Razorflank's loot has the Pronged Reaver", contains(ns.BossLoot[4421], 6692))
        -- The game hasn't loaded the Pronged Reaver: the addon's own item data fills in.
        local realInfo = C_Item.GetItemInfo
        C_Item.GetItemInfo = function(id) if id == 6692 then return nil end return realInfo(id) end
        ns.BossLoot[mutanus.boss.npcID] = { 6692 }
        panel:Hide(); mutanus.scripts.OnClick(mutanus, "LeftButton")
        check("an item the game hasn't loaded yet shows from the addon's own data",
            panel.shown[1] and panel.shown[1][2] == 6692 and ns.LootItems[6692][1] == "Pronged Reaver")
        local tipText
        local realSetText = GameTooltip.SetText
        GameTooltip.SetText = function(_, text) tipText = text end
        panel.Rows[1].scripts.OnEnter(panel.Rows[1])
        GameTooltip.SetText = realSetText
        local comparisonHidden = false
        ShoppingTooltip1 = CreateFrame("Frame"); ShoppingTooltip1.Hide = function() comparisonHidden = true end
        panel.Rows[1].scripts.OnLeave(panel.Rows[1])
        check("leaving a loot item also hides the 'currently equipped' comparison", comparisonHidden)
        check("hovering an item the game hasn't loaded shows WoW Forever's tooltip from the addon's data", tipText and tipText:find("Pronged Reaver"))
        C_Item.GetItemInfo = realInfo
        check("a rare's own loot is listed (Haunting Blade, Deathsworn Captain)", contains(ns.BossLoot[3872], 6641))
        -- Hovering a boss shows its portrait in the tooltip.
        local inserted, portraitID = nil, nil
        GameTooltip_InsertFrame = function(tooltip, frame) inserted = frame end
        SetPortraitTextureFromCreatureDisplayID = function(texture, displayID) portraitID = displayID end
        GameTooltip.GetName = function() return "GameTooltip" end
        GameTooltipTextLeft3 = CreateFrame("Frame")
        mutanus.scripts.OnEnter(mutanus)
        local pinPortrait
        SetPortraitTextureFromCreatureDisplayID = function(texture, displayID) if texture == mutanus.Portrait then pinPortrait = displayID end portraitID = displayID end
        ns:CloseDungeonMap(true); ns:OpenDungeonMap("wc")
        for _, b in ipairs(view.BossButtons) do if b:IsShown() and b.boss.name == "Mutanus the Devourer" then mutanus = b end end
        check("boss pins show the boss's portrait in a ring", pinPortrait == ns.BossModels[mutanus.boss.npcID])
        mutanus.scripts.OnEnter(mutanus)
        check("hovering a boss shows its portrait", portraitID == ns.BossModels[mutanus.boss.npcID])
        check("the portrait doesn't use GameTooltip_InsertFrame (secret values inside dungeons)", inserted == nil)
        -- Fake loot covering every kind, to check the grouping and order.
        ns.BossLoot[mutanus.boss.npcID] = { 15, 22, 13, 30, 34, 38, 27, 42, 43, 150 }
        panel:Hide(); mutanus.scripts.OnClick(mutanus, "LeftButton")
        local order = {}
        for _, e in ipairs(panel.shown) do table.insert(order, e[1] .. ":" .. e[2]) end
        check("loot (Bind on Pickup only) grouped: weapons, armour, trinkets, then recipes by profession, then other",
            table.concat(order, " ") == "gear:30 gear:43 gear:22 gear:42 recipe:38 recipe:34 other:15 other:27")

        -- Placing a boss yourself: shift-drag a listed boss onto the map (on the empty floor 1).
        ns:OpenDungeonMap("scholo", 1)
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
        local strata
        local setStrata = view.SetFrameStrata
        view.SetFrameStrata = function(self, st) strata = st end
        WorldMapFrame.GetFrameStrata = function() return "HIGH" end
        ns:CloseDungeonMap(true)
        ns:OpenDungeonMap("wc")
        check("in combat the dungeon map goes over the game's map", strata == "DIALOG")
        ns:CloseDungeonMap(true)
        view.SetFrameStrata = setStrata
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
        check("Dalaran opens on The Underbelly", ns:CurrentDungeonFloor() == 2)
        ns:OpenDungeonMap("stocks")
        local rows = 0
        for _, r in ipairs(view.ListRows) do if r:IsShown() then rows = rows + 1 end end
        check("bosses without a position are listed (Bruegal Ironknuckle)", rows > 0)
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
        -- Everything handed in: a "completed" line above Handed in.
        local realDone = C_QuestLog.IsQuestFlaggedCompleted
        C_QuestLog.IsQuestFlaggedCompleted = function() return true end
        local realIndex = C_QuestLog.GetLogIndexForQuestID
        C_QuestLog.GetLogIndexForQuestID = function() return nil end
        ns:OpenDungeonMap("rfc")
        check("all quests handed in shows the 'completed all quests' line", BeestersDungeonMapsQuests.allDone == true)
        C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetLogIndexForQuestID = realDone, realIndex
        ns:OpenDungeonMap("rfc")
        check("with quests left, no 'completed' line", BeestersDungeonMapsQuests.allDone == false)
        -- Faction toggle: switches to the other side's quests and back.
        local toggle = BeestersDungeonMapsQuestTabs.Faction
        check("faction toggle starts on your own faction", ns.questFaction == "H")
        toggle.scripts.OnClick(toggle)
        local ga = ns.ClassifyDungeonQuests("stocks")
        local anyHorde = false
        for _, list in pairs(ga) do for _, e in ipairs(list) do if e.q[4] == "H" then anyHorde = true end end end
        check("on Alliance, only Alliance and shared quests are listed", ns.questFaction == "A" and not anyHorde and #ga.available + #ga.inside > 0)
        toggle.scripts.OnClick(toggle)
        local allianceOnly = false
        for _, list in pairs(g) do for _, e in ipairs(list) do if e.q[4] == "A" then allianceOnly = true end end end
        check("no Alliance-only quests for a Horde character", not allianceOnly)
        -- Detail page with the Classic database's text and rewards (The Power to Destroy...).
        local ok, err = pcall(ns.ShowQuestDetail, 5725)
        check("detail page opens for a quest with choice rewards" .. (ok and "" or (": " .. tostring(err))), ok and qp.Detail:IsShown())
        check("the details take the whole tab (the list is hidden)", not qp.Scroll:IsShown())
        local d = qp.Detail
        check("rewards sit on their own panel, which is shown", d.buttonCount > 0 and d.rtextCount > 0 and d.Rewards:IsShown() and rawget(d, "rewardTop") ~= nil)
        local entry = has(g.log, 5728)
        ok, err = pcall(ns.ShowQuestDetail, 5728, entry)
        check("detail page opens for a chain step" .. (ok and "" or (": " .. tostring(err))), ok)
        check("detail page has quest text for Ragefire Chasm quests", ns.QuestText and ns.QuestText[5725] ~= nil)
        -- Share: only for a quest in your log, while in a group.
        local pushed
        IsInGroup = function() return true end
        C_QuestLog.IsPushableQuest = function() return true end
        QuestLogPushQuest = function(index) pushed = index end
        ns.ShowQuestDetail(5723)
        local share = qp.Detail.ShareButton
        share.scripts.OnClick(share)
        check("Share sends a quest in your log to the group", pushed == 3 and rawget(share, "reason") == nil)
        ns.ShowQuestDetail(5725)
        check("Share is off for a quest you don't have", rawget(share, "reason") ~= nil)
        IsInGroup = function() return false end
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

        -- Work in progress: complete instances get no badge, thin ones do.
        check("a complete instance isn't marked work in progress", ns:InstanceStatus("dal") == nil)
        local thin
        for key in pairs(ns.Instances) do
            local st = ns:InstanceStatus(key)
            if not thin and st and not st.noMap and st.placed < st.total then thin = key end
        end
        check("an instance with missing bosses is marked work in progress", thin ~= nil)
        check("Razorfen Downs is complete now", ns:InstanceStatus("rfd") == nil)
        check("an instance without a map is marked work in progress", (ns:InstanceStatus("nomap") or {}).noMap == true)
        ns:OpenDungeonMap(thin or "rfd")
        check("the work-in-progress badge shows on its map", ns:IsDungeonMapOpen() and BeestersDungeonMapsView.StatusBadge:IsShown())
        ns:OpenDungeonMap("dal")
        check("the badge stays hidden on a complete map", not BeestersDungeonMapsView.StatusBadge:IsShown())
        ns:CloseDungeonMap(true)
        -- Coming soon: instances without data appear greyed out in their zone's Dungeons menu.
        local soon = ns:ComingSoonOnMap(1450)
        check("a coming-soon raid is found by its zone name", #soon == 2 and soon[1].name == "Barrow Deeps")
        check("Shaper's Terrace isn't coming soon any more", #ns:ComingSoonOnMap(1446) == 0)
        check("the new dungeons have entrances (read off the map in game)", ns:EntranceMapFor("shaper") == 1449 and ns:EntranceMapFor("alcaz") == 1445)
        -- A dungeon whose entrance isn't known is still listed under its zone.
        ns.Instances.testonly = { name = "Test Hold", kind = "dungeon", levels = "60", zone = "Un'Goro Crater" }
        local zoneOnly = ns:ZoneOnlyDungeonsOnMap(1446)
        check("a dungeon without a known entrance is listed under its zone", #zoneOnly == 1 and zoneOnly[1] == "testonly" and ns:EntranceMapFor("testonly") == 1446)
        ns.Instances.testonly = nil
        -- A new dungeon without a map: its page opens with the notice, its bosses in the list.
        ns:OpenDungeonMap("shaper")
        local v = BeestersDungeonMapsView
        check("a dungeon without a map opens its page with the notice", ns:IsDungeonMapOpen() and v.NoMap:IsShown() and v.List:IsShown())
        check("that page is marked work in progress", v.StatusBadge:IsShown() and v.StatusBadge.status.noMap == true)
        check("the new dungeons have their quests", #(ns.DungeonQuests.alcaz or {}) >= 5 and #(ns.DungeonQuests.drowned or {}) >= 5)
        check("being inside a new dungeon is recognised", ns.InstanceByMap[2970] == "drowned")
        ns:CloseDungeonMap(true)
        check("coming-soon dungeons show on the continent too", #ns:ComingSoonOnMap(1414) >= 1)

        -- The top bar's menu while a dungeon map is open over the world view (opened inside the
        -- dungeon, or in combat) still lists the dungeons of that dungeon's zone.
        inCombat = true
        WorldMapFrame.mapID = 947
        ns:OpenDungeonMap("wc")
        inCombat = false
        ns:UpdateDungeonCrumb()
        local items = ns.DungeonCrumb.listFunc and ns.DungeonCrumb.listFunc() or {}
        check("the top bar's dungeon menu isn't empty after opening over the world view", #items > 0)
        ns:CloseDungeonMap(true)
        WorldMapFrame.mapID = 1413

        -- Quest text in chat (Questie's form) becomes a link for dungeon quests this addon knows.
        local anyQuest
        for id in pairs(ns.Quests) do anyQuest = id; break end
        ns:InitQuestPanel()
        local filter = chatFilters["CHAT_MSG_PARTY"]
        check("a chat filter is set up for party chat", filter ~= nil)
        if filter then
            local name = ns.Quests[anyQuest][1]
            local _, out = filter(nil, "CHAT_MSG_PARTY", ("Doing [[33] %s (%d)] now"):format(name, anyQuest), "Someone")
            check("a dungeon quest in Questie's form becomes a link", type(out) == "string" and out:find("|Hbdmquest:" .. anyQuest .. "|h", 1, true) ~= nil)
            local changed = filter(nil, "CHAT_MSG_PARTY", "[Something Else (99999999)] and a normal line", "Someone")
            check("other text is left alone", changed == false)
        end

        -- Minimap button and the dungeon list.
        ns.db.minimapButton = true
        ns:InitMinimap()
        check("minimap button is made and shown", ns.MinimapButton ~= nil and ns.MinimapButton:IsShown())
        local mine, all = ns:DungeonList(30)
        local names, allNames, headers = {}, {}, 0
        for _, e in ipairs(mine) do names[e.name] = true end
        for _, e in ipairs(all) do if e.header then headers = headers + 1 else allNames[e.name] = true end end
        check("for level 30: Shadowfang Keep and Scarlet Monastery are yours", names["Shadowfang Keep"] and names["Scarlet Monastery"])
        check("for level 30: Ragefire Chasm and Stratholme aren't", not names["Ragefire Chasm"] and not names["Stratholme"])
        check("for level 30: The Drowned City (coming soon) is listed as yours", names["The Drowned City"] == true)
        check("the full list has every instance and coming-soon one", allNames["Onyxia's Lair"] and allNames["Hyjal Summit"] and allNames["Wailing Caverns"])
        check("the full list is split into level bands and raids", headers >= 6 and all[#all].kind == "raid")
        -- The error from 1.0.1: a dungeon opened after a two-floor one, while the map is closed.
        ns:OpenDungeonMap("dal", 2)
        ns:CloseDungeonMap(true)
        WorldMapFrame:Hide()
        check("opening a one-floor dungeon after Dalaran's second floor works",
            pcall(function() ns:OpenDungeonMap("rfc") end) and ns:CurrentDungeonKey() == "rfc")
        ns:CloseDungeonMap(true)
        -- In combat with the map closed: wait, then open when the fight ends.
        local shown = WorldMapFrame.IsShown
        WorldMapFrame.IsShown = function() return false end
        inCombat = true
        ns:OpenDungeonListEntry({ key = "wc", name = "Wailing Caverns", levels = "17–24" })
        check("in combat the dungeon map waits", not ns:IsDungeonMapOpen())
        inCombat = false
        WorldMapFrame.IsShown = shown
        ns:OpenDungeonListEntry({ key = "wc", name = "Wailing Caverns", levels = "17–24" })
        check("out of combat it opens", ns:IsDungeonMapOpen() and ns:CurrentDungeonKey() == "wc")
        ns:CloseDungeonMap(true)
        ns:ToggleDungeonList(ns.MinimapButton)
        check("clicking the button opens the list", BeestersDungeonMapsList:IsShown())
        SlashCmdList.BEESTERSDUNGEONMAPS("list")
        check("/bdm list closes it again", not BeestersDungeonMapsList:IsShown())
        BeestersDungeonMapsList:Hide()
        ns.db.suggestDungeons = false
        ns:ToggleDungeonList(ns.MinimapButton)
        check("with suggestions off, the list has no 'for your level' part", not BeestersDungeonMapsList.Title:IsShown())
        BeestersDungeonMapsList:Hide()
        ns.db.suggestDungeons = true
        -- Inside Dalaran the map opens on the level you're on, told by the subzone.
        local inInst, instInfo, subzone = IsInInstance, GetInstanceInfo, "Dalaran"
        IsInInstance = function() return true, "party" end
        GetInstanceInfo = function() return "City of Dalaran", "party", 1, "Normal", 5, 0, false, 2959 end
        GetSubZoneText = function() return subzone end
        ns:OpenDungeonMap("dal")
        check("inside Dalaran, upstairs: the city level opens", ns:CurrentDungeonFloor() == 1)
        ns:CloseDungeonMap(true)
        subzone = "The Underbelly"
        ns:OpenDungeonMap("dal")
        check("inside Dalaran, in the Underbelly: the Underbelly opens", ns:CurrentDungeonFloor() == 2)
        ns:CloseDungeonMap(true)
        -- Gnomeregan has no subzones: the map holds the level you picked during the run,
        -- and follows the boss you pull or target.
        subzone = ""
        GetMinimapZoneText = function() return "Gnomeregan" end
        GetInstanceInfo = function() return "Gnomeregan", "party", 1, "Normal", 5, 0, false, 90 end
        local runEvent = BeestersDungeonMapsRunWatcher.scripts.OnEvent
        runEvent(nil, "PLAYER_ENTERING_WORLD")
        ns:OpenDungeonMap("gnomer")
        local firstFloor = ns:CurrentDungeonFloor()
        ns:OpenDungeonMap("gnomer", 3)
        ns:CloseDungeonMap(true)
        ns:OpenDungeonMap("gnomer")
        check("inside Gnomeregan the map holds the level you picked", ns:CurrentDungeonFloor() == 3)
        local thermaplugg
        for _, b in ipairs(ns.BossPositions.gnomer or {}) do if b[5] and b[5]:find("Thermaplugg") then thermaplugg = b end end
        runEvent(nil, "ENCOUNTER_START", thermaplugg and thermaplugg[4] or 0, "Mekgineer Thermaplugg")
        check("pulling a boss turns the map to its level", thermaplugg and ns:CurrentDungeonFloor() == thermaplugg[1])
        ns:CloseDungeonMap(true)
        -- The dungeon's own name as subzone says nothing about the level.
        subzone = "Gnomeregan"
        ns:OpenDungeonMap("gnomer")
        check("the dungeon's own name isn't taken for a level", ns:CurrentDungeonFloor() == thermaplugg[1])
        ns:CloseDungeonMap(true)
        -- Uldaman: the entrance hall shares its name with the second level, but is on the first.
        subzone = "Hall of the Keepers"
        GetInstanceInfo = function() return "Uldaman", "party", 1, "Normal", 5, 0, false, 70 end
        runEvent(nil, "PLAYER_ENTERING_WORLD")
        ns:OpenDungeonMap("ulda")
        check("Uldaman's entrance hall opens the first level", ns:CurrentDungeonFloor() == 1)
        ns:CloseDungeonMap(true)
        -- Deadmines: Ironclad Cove is on the second map.
        GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
        runEvent(nil, "PLAYER_ENTERING_WORLD")
        subzone = "Ironclad Cove"
        ns:OpenDungeonMap("dm")
        check("Deadmines: Ironclad Cove opens the second map", ns:CurrentDungeonFloor() == 2)
        ns:CloseDungeonMap(true)
        -- Scholomance: pulling a boss teaches the addon the subzone's level.
        GetInstanceInfo = function() return "Scholomance", "party", 1, "Normal", 5, 0, false, 289 end
        runEvent(nil, "PLAYER_ENTERING_WORLD")
        subzone = "Vault of the Ravenian"
        local ravenian
        for _, b in ipairs(ns.BossPositions.scholo or {}) do if b[5] == "The Ravenian" then ravenian = b end end
        runEvent(nil, "ENCOUNTER_START", 0, "The Ravenian")
        runEvent(nil, "PLAYER_ENTERING_WORLD") -- a new day: the run's level is gone, the subzone stays
        ns:OpenDungeonMap("scholo")
        check("a subzone where a boss was pulled opens that boss's level", ravenian and ns:CurrentDungeonFloor() == ravenian[1])
        ns:CloseDungeonMap(true)
        IsInInstance, GetInstanceInfo = inInst, instInfo
        runEvent(nil, "PLAYER_ENTERING_WORLD")
        ns:OpenDungeonMap("gnomer")
        check("after leaving, the next run starts on the default level again", ns:CurrentDungeonFloor() == firstFloor)
        ns:CloseDungeonMap(true)
        ns:OpenDungeonMap("dal")
        check("outside, Dalaran still opens on the Underbelly", ns:CurrentDungeonFloor() == 2)
        ns:CloseDungeonMap(true)
        -- Options during combat wait for the fight to end (the Settings window is protected).
        inCombat = true
        check("options in combat don't error", pcall(function() ns:OpenOptions() end))
        inCombat = false

        ns.db.minimapButton = false
        ns:UpdateMinimapButton()
        check("the button can be hidden", not ns.MinimapButton:IsShown())

        SlashCmdList.BEESTERSDUNGEONMAPS("status")
        IsInInstance = function() return true, "party" end
        SlashCmdList.BEESTERSDUNGEONMAPS("map")
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
