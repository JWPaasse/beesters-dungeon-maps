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

function PinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.2)
    -- Hover shows a tooltip; clicks pass through to the map so zooming and dragging keep working.
    if self.SetMouseClickEnabled then
        self:SetMouseClickEnabled(false)
        self:SetMouseMotionEnabled(true)
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
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Data provider
----------------------------------------------------------------------

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function Provider:RefreshAllData()
    self:RemoveAllData()

    local db = ns.db
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    local mapInfo = mapID and C_Map.GetMapInfo(mapID)
    if not db or not mapInfo then return end

    local mapType = mapInfo.mapType
    if mapType == Enum.UIMapType.Cosmic or mapType == Enum.UIMapType.World then return end
    if mapType == Enum.UIMapType.Continent and not db.showOnContinents then return end

    for zoneMapID, entrances in pairs(ns.Entrances) do
        local direct = (zoneMapID == mapID)
        local minX, maxX, minY, maxY
        if not direct and IsAncestor(mapID, zoneMapID) then
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
