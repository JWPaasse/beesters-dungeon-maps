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
local NUMBERS = { GetWidth = 100, GetHeight = 50, GetStringWidth = 60, GetFrameLevel = 5 }
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
function GetInstanceInfo() return "Wailing Caverns", "party", 1, "Normal", 5, 0, false, 43 end
C_Texture = { GetAtlasInfo = function(atlas) return nil end }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0-test" end }
function GetBuildInfo() return "1.60.1", "70753", "Nov 4 2026", 16001 end

SlashCmdList = { OTHERADDON = function() end }
SLASH_OTHERADDON1 = "/other"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
GREEN_FONT_COLOR = { r = 0.1, g = 1, b = 0.1 }
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
    GoToMap = function(self, mapID) WorldMapFrame:SetMapID(mapID) end,
}
WorldMapFrame.OnMapChanged = function(self) self.NavBar:Refresh() end
WorldMapFrame.SetMapID = function(self, mapID)
    if mapID ~= self.mapID then self.mapID = mapID; self:OnMapChanged() end
end
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
        check("top bar ends with Wailing Caverns", navButtons[#navButtons] and navButtons[#navButtons].name == "Wailing Caverns")
        local menu = navButtons[#navButtons].listFunc()
        check("its menu lists the other Barrens dungeons", #menu >= 3)

        WorldMapFrame:SetMapID(1415)
        check("changing the map closes the dungeon map", not ns:IsDungeonMapOpen() and WorldMapFrame.ScrollContainer.Child:IsShown())

        -- Open a dungeon somewhere else first: the Dungeons list must follow the map you're on.
        ns:OpenDungeonMap("stocks")
        ns:CloseDungeonMap(true)
        WorldMapFrame.mapID = 1413
        WorldMapFrame.NavBar:Refresh()
        check("top bar on The Barrens offers a Dungeons button", navButtons[#navButtons] and navButtons[#navButtons].name == "Dungeons")
        local barrensList = navButtons[#navButtons].listFunc()
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
