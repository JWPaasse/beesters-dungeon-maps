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

    -- Positions you placed yourself are saved under the boss's name. Names the addon no longer
    -- uses (a boss renamed or dropped since) would never show again: forget them.
    if ns.db.bossPositions and ns.Bosses then
        for key, placed in pairs(ns.db.bossPositions) do
            local known = {}
            for _, boss in ipairs(ns.Bosses[key] or {}) do known[boss[2]] = true end
            if ns.Bosses[key] then
                for name in pairs(placed) do
                    if not known[name] then placed[name] = nil end
                end
            end
        end
    end

    ns:InitSlashCommands()
    ns:InitOptions()
    ns:InitMapPins()
    ns:InitDungeonMap()
    ns:InitQuestPanel()
end)

-- Item tooltips with the game's comparison tooltips ("Currently equipped"). Those hang off
-- GameTooltip; when a row is left, hidden or reused quickly they could stay on screen, so
-- they're cleared explicitly every time.
local function HideComparison()
    if GameTooltip_HideShoppingTooltips then pcall(GameTooltip_HideShoppingTooltips, GameTooltip) end
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local tip = _G[name]
        if tip and tip.Hide then tip:Hide() end
    end
end

function ns:ShowItemByID(owner, itemID)
    HideComparison()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

-- Hide the tooltip (and its comparisons) if it belongs to owner, or to any frame when owner is nil.
function ns:HideItemTooltip(owner)
    local current = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner == nil or current == owner then GameTooltip:Hide() end
    HideComparison()
end

-- When a panel closes under the mouse, its rows get no OnLeave: drop a tooltip they own.
function ns:HideTooltipWithin(frame)
    local current = GameTooltip:IsShown() and GameTooltip:GetOwner()
    while current do
        if current == frame then
            GameTooltip:Hide()
            HideComparison()
            return
        end
        current = current.GetParent and current:GetParent()
    end
end
