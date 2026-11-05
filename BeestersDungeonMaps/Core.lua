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
    entranceSize = 32,
    autoOpenInside = true,
    dungeonsInTopBar = true,
    questPanel = true,
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
    ns:Print("World map pins: " .. (ns.mapPinsActive and "|cff40ff40active|r" or "|cffff4040not active|r")
        .. " · Dungeon maps: " .. (ns.dungeonMapActive and "|cff40ff40active|r" or "|cffff4040not active|r"))
end

-- Answers the questions the next versions depend on. Run /bdm probe once outside and once
-- inside a dungeon (with the map open), and send a screenshot of the chat.
local function Probe()
    local function yesno(value) return value and "|cff40ff40yes|r" or "|cffff4040no|r" end
    local function loaded(name)
        if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
        return IsAddOnLoaded and IsAddOnLoaded(name)
    end
    local _, _, _, interface = GetBuildInfo()
    ns:Print("|cffffffffProbe|r · interface " .. tostring(interface))
    ns:Print("Questie loaded: " .. yesno(loaded("Questie")) .. " · QuestieDB loaded: " .. yesno(loaded("QuestieDB")))
    ns:Print("Map frames: QuestMapFrame " .. yesno(QuestMapFrame) .. " · QuestScrollFrame " .. yesno(QuestScrollFrame)
        .. " · WorldMapFrame.QuestLog " .. yesno(WorldMapFrame and WorldMapFrame.QuestLog)
        .. " · NavBar " .. yesno(WorldMapFrame and WorldMapFrame.NavBar))
    local atlasOK = C_Texture and C_Texture.GetAtlasInfo
    ns:Print("Icons: Dungeon " .. yesno(atlasOK and C_Texture.GetAtlasInfo("Dungeon"))
        .. " · Raid " .. yesno(atlasOK and C_Texture.GetAtlasInfo("Raid")))

    -- Does the client have Classic's dungeon map art? (Wailing Caverns, Ragefire Chasm, Deadmines)
    for _, id in ipairs({ 279, 213, 291 }) do
        local info = C_Map.GetMapInfo(id)
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(id)
        ns:Print(("Map %d: %s · art layers: %s"):format(id, info and info.name or "|cffff4040none|r",
            layers and #layers or "|cffff4040none|r"))
    end

    local inInstance, instanceType = IsInInstance()
    if inInstance then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        local layers = mapID and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
        ns:Print(("Inside: %s (%s, instance %s) · player map %s %s · art layers %s"):format(
            tostring(name), tostring(instanceType), tostring(instanceID), tostring(mapID),
            info and info.name or "none", layers and #layers or "none"))
    else
        ns:Print("Not inside an instance. Run /bdm probe again inside a dungeon too.")
    end
    if WorldMapFrame and WorldMapFrame:IsShown() then
        local mapID = WorldMapFrame:GetMapID()
        local info = mapID and C_Map.GetMapInfo(mapID)
        ns:Print(("World map open on map %s (%s, type %s)"):format(tostring(mapID), info and info.name or "?",
            info and tostring(info.mapType) or "?"))
    end
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
        elseif message == "probe" then
            Probe()
        elseif message == "map" then
            local key = ns.CurrentInstanceKey and ns.CurrentInstanceKey()
            if key then ns:OpenDungeonMap(key) else ns:Print("You are not inside a dungeon. Click an entrance on the map instead.") end
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

    -- 0.2.0: entrance icons became bigger by default (24 was hard to spot on Forever's maps).
    if (ns.db.settingsVersion or 1) < 2 then
        if ns.db.entranceSize == 24 then ns.db.entranceSize = ns.defaults.entranceSize end
        ns.db.settingsVersion = 2
    end

    ns:InitSlashCommands()
    ns:InitOptions()
    ns:InitMapPins()
    ns:InitDungeonMap()
    ns:InitQuestPanel()
end)
