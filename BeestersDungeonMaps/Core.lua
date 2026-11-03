-- Beester's Dungeon Maps
-- Copyright (C) 2026 Beester. Licensed under the GNU General Public License v3.0.

local ADDON_NAME, ns = ...

ns.title = "Beester's Dungeon Maps"
ns.logo = "Interface\\AddOns\\BeestersDungeonMaps\\Media\\Logo128"
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "?"

-- Settings that are saved between sessions. New settings get their default automatically.
ns.defaults = {
    showDungeons = true,
    showRaids = true,
    showOnContinents = true,
    entranceSize = 24,
}

function ns:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.title .. ":|r " .. tostring(message))
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

-- Returns true when another addon (or the game) already uses this slash command.
local function IsSlashCommandTaken(command)
    command = command:lower()
    for name in pairs(SlashCmdList) do
        local index = 1
        while true do
            local existing = _G["SLASH_" .. name .. index]
            if not existing then break end
            if existing:lower() == command then
                return true
            end
            index = index + 1
        end
    end
    return false
end

local function PrintStatus()
    local version, build, _, interface = GetBuildInfo()
    ns:Print(("Version %s · game %s.%s · interface %s"):format(ns.version, version, build, interface))
    ns:Print("Data: QuestieDB " .. tostring(ns.dataVersion))
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    ns:Print(("You are on map %s (%s)"):format(tostring(mapID), info and info.name or "unknown"))
    ns:Print("World map pins: " .. (ns.mapPinsActive and "|cff40ff40active|r" or "|cffff4040not active|r"))
end

function ns:InitSlashCommands()
    local commands = {}
    if not IsSlashCommandTaken("/bdm") then
        table.insert(commands, "/bdm")
    end
    table.insert(commands, "/beesterdm")
    for index, command in ipairs(commands) do
        _G["SLASH_BEESTERSDUNGEONMAPS" .. index] = command
    end
    ns.slashCommand = commands[1]

    SlashCmdList.BEESTERSDUNGEONMAPS = function(message)
        message = (message or ""):lower():match("^%s*(.-)%s*$")
        if message == "status" then
            PrintStatus()
        else
            ns:OpenOptions()
        end
    end
end

----------------------------------------------------------------------
-- Start-up
----------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedName)
    if loadedName ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    BeestersDungeonMapsDB = BeestersDungeonMapsDB or {}
    for key, value in pairs(ns.defaults) do
        if BeestersDungeonMapsDB[key] == nil then
            BeestersDungeonMapsDB[key] = value
        end
    end
    ns.db = BeestersDungeonMapsDB

    ns:InitSlashCommands()
    ns:InitOptions()
    ns:InitMapPins()
end)
