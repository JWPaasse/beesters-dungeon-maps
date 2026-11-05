-- Beester's Dungeon Maps: dungeon and raid entrance pins on the world map.
-- Uses the world map's own pin system (data provider + pin template), the same way
-- Blizzard's map features and other map addons add pins, so it does not touch protected frames.

local _, ns = ...

local PIN_TEMPLATE = "BeestersDungeonMapsEntrancePinTemplate"
local FALLBACK_ICON = "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function AtlasExists(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Is `ancestorID` a parent (or grandparent, ...) of `mapID`?
local ancestorCache = {}
local function IsAncestor(ancestorID, mapID)
    local key = ancestorID .. ":" .. mapID
    if ancestorCache[key] == nil then
        local found = false
        local info = C_Map.GetMapInfo(mapID)
        local steps = 0
        while info and info.parentMapID and info.parentMapID ~= 0 and steps < 10 do
            if info.parentMapID == ancestorID then
                found = true
                break
            end
            info = C_Map.GetMapInfo(info.parentMapID)
            steps = steps + 1
        end
        ancestorCache[key] = found
    end
    return ancestorCache[key]
end

-- Capital cities hang under the continent in the map tree, not under the zone around them,
-- so their entrances (Ragefire Chasm, Ruins of Lordaeron, The Stockade) would not show on
-- that zone. city map -> surrounding zone map.
local CITY_IN_ZONE = {
    [1454] = 1411, -- Orgrimmar -> Durotar
    [1458] = 1420, -- Undercity -> Tirisfal Glades
    [1453] = 1429, -- Stormwind City -> Elwynn Forest
    [1455] = 1426, -- Ironforge -> Dun Morogh
    [1456] = 1412, -- Thunder Bluff -> Mulgore
    [1457] = 1438, -- Darnassus -> Teldrassil
}

local function ShowsOn(mapID, zoneMapID)
    return IsAncestor(mapID, zoneMapID) or CITY_IN_ZONE[zoneMapID] == mapID
end

-- An entrance point can lead to more than one instance (Blackrock Mountain).
-- It counts as a raid only when every instance behind it is a raid.
local function EntranceKind(instanceKeys)
    for _, key in ipairs(instanceKeys) do
        local instance = ns.Instances[key]
        if instance and instance.kind ~= "raid" then
            return "dungeon"
        end
    end
    return "raid"
end

----------------------------------------------------------------------
-- Pin
----------------------------------------------------------------------

BeestersDungeonMapsEntrancePinMixin = CreateFromMixins(MapCanvasPinMixin)
local PinMixin = BeestersDungeonMapsEntrancePinMixin

-- The map calls SetPassThroughButtons on clickable pins whenever it changes. That function is
-- locked in combat, so changing the map in combat gave "ADDON_ACTION_BLOCKED". Our pins don't
-- pass clicks through, so they skip the call (the same fix HandyNotes uses).
function PinMixin:SetPassThroughButtons() end

-- Called by the world map (MapCanvasMixin:AcquirePin) when it creates a new pin.
function PinMixin:OnLoad()
    -- The dungeon entrance layer sits above the big city and area badges (Orgrimmar on Durotar).
    -- Forever's map has this layer (checked in the UIForever simulator, interface 16001).
    self:UseFrameLevelType("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    self:SetScalingLimits(1, 1.0, 1.2)
end

function PinMixin:OnMouseDown() end
function PinMixin:OnMouseUp() end

-- Left click opens the dungeon map. Blackrock Mountain leads to two dungeons: pick one.
function PinMixin:OnClick(button)
    local entrance = self.entrance
    if not entrance then return end
    if button == "RightButton" then
        local map = self:GetMap()
        if map and map.NavigateToParentMap then map:NavigateToParentMap() end
        return
    end
    local keys = {}
    for _, key in ipairs(entrance[3]) do
        if ns.DungeonMaps and ns.DungeonMaps[key] then table.insert(keys, key) end
    end
    if #keys == 1 then
        ns:OpenDungeonMap(keys[1])
    elseif #keys > 1 and MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, key in ipairs(keys) do
                root:CreateButton(ns.Instances[key].name, function() ns:OpenDungeonMap(key) end)
            end
        end)
    elseif #keys > 1 then
        ns:OpenDungeonMap(keys[1])
    end
end

function PinMixin:OnAcquired(entrance, x, y, kind)
    self.entrance = entrance
    self:SetPosition(x, y)
    local size = ns.db.entranceSize
    self:SetSize(size, size)

    local atlas = (kind == "raid") and "Raid" or "Dungeon"
    if AtlasExists(atlas) then
        self.Icon:SetAtlas(atlas)
        self.Icon:SetTexCoord(0, 1, 0, 1)
    else
        self.Icon:SetTexture(FALLBACK_ICON)
        self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

function PinMixin:OnReleased()
    self.entrance = nil
end

function PinMixin:OnMouseEnter()
    local entrance = self.entrance
    if not entrance then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for index, key in ipairs(entrance[3]) do
        local instance = ns.Instances[key]
        if instance then
            if index > 1 then
                GameTooltip:AddLine(" ")
            end
            GameTooltip:AddLine(instance.name, 1, 1, 1)
            local kindText
            if instance.kind == "raid" then
                kindText = RAID or "Raid"
            else
                kindText = LFG_TYPE_DUNGEON or "Dungeon"
            end
            local detail = kindText .. " · " .. (LEVEL or "Level") .. " " .. instance.levels
            if instance.size then
                detail = detail .. " · " .. instance.size
            end
            GameTooltip:AddLine(detail, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            if instance.isNew then
                GameTooltip:AddLine("New in WoW Forever", 0.31, 0.82, 0.88)
            end
            if instance.note then
                GameTooltip:AddLine(instance.note, 0.8, 0.8, 0.8, true)
            end
        end
    end
    if ns.DungeonMaps and ns.DungeonMaps[entrance[3][1]] then
        GameTooltip:AddLine("<Click to open the map>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    end
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Quest start marker ("Show on map" in the dungeon quest panel)
----------------------------------------------------------------------

local MARKER_TEMPLATE = "BeestersDungeonMapsMarkerPinTemplate"
BeestersDungeonMapsMarkerPinMixin = CreateFromMixins(MapCanvasPinMixin)
local MarkerMixin = BeestersDungeonMapsMarkerPinMixin
function MarkerMixin:SetPassThroughButtons() end

function MarkerMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    self:SetScalingLimits(1, 1.0, 1.2)
end

function MarkerMixin:OnAcquired(marker, x, y)
    self.marker = marker
    self:SetPosition(x, y)
    self:SetSize(30, 30)
    if C_Texture.GetAtlasInfo("QuestNormal") then
        self.Icon:SetAtlas("QuestNormal")
    else
        self.Icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
end

function MarkerMixin:OnMouseEnter()
    local m = self.marker
    if not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(m.title, 1, 1, 1)
    if m.who then GameTooltip:AddLine(m.who, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b) end
    GameTooltip:Show()
end

function MarkerMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function ns:ShowQuestMarker(mapID, x, y, title, who)
    ns.questMarker = { mapID = mapID, x = x, y = y, title = title, who = who }
    if WorldMapFrame:GetMapID() == mapID then
        ns:CloseDungeonMap(true)
        ns:RefreshMapPins()
    else
        WorldMapFrame:SetMapID(mapID) -- closes the dungeon map and redraws the pins
    end
end

function ns:ClearQuestMarker()
    ns.questMarker = nil
end

----------------------------------------------------------------------
-- Data provider
----------------------------------------------------------------------

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(MARKER_TEMPLATE)
end

function Provider:RefreshAllData()
    self:RemoveAllData()

    local db = ns.db
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    local mapInfo = mapID and C_Map.GetMapInfo(mapID)
    if not db or not mapInfo then return end

    local m = ns.questMarker
    if m and m.mapID == mapID then
        map:AcquirePin(MARKER_TEMPLATE, m, m.x, m.y)
    end

    local mapType = mapInfo.mapType
    if mapType == Enum.UIMapType.Cosmic or mapType == Enum.UIMapType.World then return end
    if mapType == Enum.UIMapType.Continent and not db.showOnContinents then return end

    for zoneMapID, entrances in pairs(ns.Entrances) do
        local direct = (zoneMapID == mapID)
        local minX, maxX, minY, maxY
        if not direct and ShowsOn(mapID, zoneMapID) then
            minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(zoneMapID, mapID)
        end
        local placeable = direct or (minX and maxX and maxX > minX and maxY > minY)

        if placeable then
            for _, entrance in ipairs(entrances) do
                local kind = EntranceKind(entrance[3])
                if (kind == "raid" and db.showRaids) or (kind == "dungeon" and db.showDungeons) then
                    local x, y = entrance[1], entrance[2]
                    if not direct then
                        x = minX + x * (maxX - minX)
                        y = minY + y * (maxY - minY)
                    end
                    map:AcquirePin(PIN_TEMPLATE, entrance, x, y, kind)
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Lookups used by the dungeon map and the top bar
----------------------------------------------------------------------

local function LevelOf(key)
    local levels = ns.Instances[key] and ns.Instances[key].levels or ""
    return tonumber(levels:match("%d+")) or 99
end

-- Dungeons whose entrance is on this map (or on a map inside it), lowest level first.
function ns:DungeonsOnMap(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info or info.mapType == Enum.UIMapType.Cosmic or info.mapType == Enum.UIMapType.World then
        return {}
    end
    local found, list = {}, {}
    for zoneMapID, entrances in pairs(ns.Entrances) do
        if zoneMapID == mapID or ShowsOn(mapID, zoneMapID) then
            for _, entrance in ipairs(entrances) do
                for _, key in ipairs(entrance[3]) do
                    if not found[key] then
                        found[key] = true
                        table.insert(list, key)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        local la, lb = LevelOf(a), LevelOf(b)
        if la ~= lb then return la < lb end
        return ns.Instances[a].name < ns.Instances[b].name
    end)
    return list
end

function ns:MapShowsDungeon(mapID, key)
    for _, k in ipairs(ns:DungeonsOnMap(mapID)) do
        if k == key then return true end
    end
    return false
end

-- The map an entrance of this dungeon is on (a zone or city map).
function ns:EntranceMapFor(key)
    for zoneMapID, entrances in pairs(ns.Entrances) do
        for _, entrance in ipairs(entrances) do
            for _, k in ipairs(entrance[3]) do
                if k == key then return zoneMapID end
            end
        end
    end
end

----------------------------------------------------------------------
-- Set-up
----------------------------------------------------------------------

function ns:RefreshMapPins()
    if ns.mapPinsActive and WorldMapFrame:IsShown() then
        Provider:RefreshAllData()
    end
end

function ns:InitMapPins()
    if ns.mapPinsActive then return end
    if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then
        ns:Print("This game version's world map does not support map pins. Entrances will not show.")
        return
    end
    WorldMapFrame:AddDataProvider(Provider)
    ns.mapPinsActive = true
end
