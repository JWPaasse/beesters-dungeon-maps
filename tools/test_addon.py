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
local function anything()
    local t = {}
    return setmetatable(t, { __index = function(self, key)
        local f = function() return self end
        rawset(self, key, f)
        return f
    end })
end

function CreateFrame(kind, name, parent, template)
    local frame = anything()
    frame.scripts = {}
    frame.SetScript = function(self, event, fn) self.scripts[event] = fn end
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
MapCanvasPinMixin = {}
MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }

-- A small piece of the real map tree.
local maps = {
    [947]  = { name = "Azeroth", mapType = 1, parentMapID = 946 },
    [1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1413] = { name = "The Barrens", mapType = 3, parentMapID = 1414 },
    [1420] = { name = "Tirisfal Glades", mapType = 3, parentMapID = 1415 },
    [1458] = { name = "Undercity", mapType = 3, parentMapID = 1420 },
}
setmetatable(maps, { __index = function(_, id) return { name = "Zone " .. id, mapType = 3, parentMapID = 0 } end })
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetMapRectOnMap = function(child, parent) return 0.4, 0.6, 0.3, 0.5 end,
    GetBestMapForUnit = function() return 1413 end,
}
C_Texture = { GetAtlasInfo = function(atlas) return nil end }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0-test" end }
function GetBuildInfo() return "1.60.1", "70753", "Nov 4 2026", 16001 end

SlashCmdList = { OTHERADDON = function() end }
SLASH_OTHERADDON1 = "/other"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("[chat] " .. msg) end }
GameTooltip = anything()
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return name end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) print("[settings] opened " .. id) end,
}

acquired = {}
WorldMapFrame = {
    providers = {},
    IsShown = function() return true end,
    AddDataProvider = function(self, provider) provider.owningMap = self; table.insert(self.providers, provider) end,
    GetMapID = function(self) return self.mapID end,
    RemoveAllPinsByTemplate = function() acquired = {} end,
    AcquirePin = function(self, template, entrance, x, y, kind)
        table.insert(acquired, { entrance = entrance, x = x, y = y, kind = kind })
    end,
}
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
        pin.SetScalingLimits = function() end
        pin:OnLoad()
        pin:OnAcquired(ns.Entrances[1427][1], 0.5, 0.5, "dungeon")
        pin:OnMouseEnter()
        pin:OnMouseLeave()
        check("pin and tooltip code runs (Blackrock Mountain, 2 dungeons)", true)

        SlashCmdList.BEESTERSDUNGEONMAPS("status")
        SlashCmdList.BEESTERSDUNGEONMAPS("")
        check("slash command runs", true)
        return table.concat(results, "\n")
    end""")
    output = checks(ns)
    print(output)
    if "FAIL" in output:
        sys.exit(1)


if __name__ == "__main__":
    main()
