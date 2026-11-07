-- Beester's Dungeon Maps: the minimap button and its list of every dungeon and raid.
--
-- Click the button: a game-style list opens. On top, pinned, the dungeons for your level
-- (any part of their level range within 5 levels of yours); under it, everything, by level
-- band, raids last, in a scroll list. Instances the addon has no data for yet ("coming soon")
-- are listed too, so nobody misses one. Click a dungeon to open its map, like clicking its
-- entrance; a coming-soon one opens its zone. Drag the button to move it around the minimap;
-- right-click it for the options.

local _, ns = ...

local LEVEL_RANGE = 5        -- "for your level": within this many levels of yours
local ROW_HEIGHT = 18
local LIST_WIDTH = 290
local SCROLL_MAX, SCROLL_MIN = 260, 120
local DEFAULT_ANGLE = 225    -- degrees, 0 = right of the minimap, counter-clockwise

local button, list

----------------------------------------------------------------------
-- The list's data
----------------------------------------------------------------------

local function LevelRange(levels)
    local low, high = (levels or ""):match("(%d+)%D+(%d+)")
    low = tonumber(low or (levels or ""):match("%d+")) or 1
    return low, tonumber(high) or low
end

-- Colour of a level range for the player, like quest titles: grey, green, yellow, orange, red.
local FALLBACK = {
    trivial = { r = 0.5, g = 0.5, b = 0.5 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
    difficult = { r = 1, g = 1, b = 0 }, verydifficult = { r = 1, g = 0.5, b = 0.25 },
    impossible = { r = 1, g = 0.1, b = 0.1 },
}
local function LevelColor(low, high, level)
    local key
    if level > high + 3 then key = "trivial"
    elseif level > high then key = "standard"
    elseif level >= low then key = "difficult"
    elseif low - level <= 3 then key = "verydifficult"
    else key = "impossible" end
    return (QuestDifficultyColors and QuestDifficultyColors[key]) or FALLBACK[key]
end

local entries
local function Entries()
    if entries then return entries end
    entries = {}
    for key, instance in pairs(ns.Instances or {}) do
        local low, high = LevelRange(instance.levels)
        table.insert(entries, {
            key = key, name = instance.name, kind = instance.kind, levels = instance.levels, low = low, high = high,
            size = instance.size, isNew = instance.isNew, zoneID = ns:EntranceMapFor(key),
        })
    end
    for _, instance in ipairs(ns.ComingSoon or {}) do
        local low, high = LevelRange(instance.levels)
        table.insert(entries, {
            name = instance.name, kind = instance.kind, levels = instance.levels, low = low, high = high,
            size = instance.size, soon = true, zoneName = instance.zone, zoneID = ns:ZoneMapID(instance.zone),
        })
    end
    table.sort(entries, function(a, b)
        if (a.kind == "raid") ~= (b.kind == "raid") then return b.kind == "raid" end
        if a.low ~= b.low then return a.low < b.low end
        if (a.soon or false) ~= (b.soon or false) then return not a.soon end
        return a.name < b.name
    end)
    return entries
end

-- mine: dungeons for this level (coming soon ones too); all: headers and entries in order.
function ns:DungeonList(level)
    local mine, all, band = {}, {}, nil
    for _, e in ipairs(Entries()) do
        if e.kind ~= "raid" and e.low <= level + LEVEL_RANGE and e.high >= level - LEVEL_RANGE then
            table.insert(mine, e)
        end
        local b = e.kind == "raid" and (RAIDS or "Raids")
            or ("%s %d–%d"):format(LEVEL or "Level", math.floor(e.low / 10) * 10, math.floor(e.low / 10) * 10 + 10)
        if b ~= band then
            band = b
            table.insert(all, { header = b })
        end
        table.insert(all, e)
    end
    return mine, all
end

----------------------------------------------------------------------
-- Opening an entry
----------------------------------------------------------------------

local function Open(e)
    if InCombatLockdown() and not WorldMapFrame:IsShown() then
        ns:Print("The map can't be opened during combat.")
        return
    end
    if list then list:Hide() end
    if not e.soon and ns.DungeonMaps and ns.DungeonMaps[e.key] then
        ns:OpenDungeonMap(e.key)
    elseif e.zoneID then
        ns:GoToMap(e.zoneID)
    end
end

local function ShowEntryTooltip(row)
    local e = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
    GameTooltip:SetText(e.name, 1, 1, 1)
    local kind = e.kind == "raid" and (RAID or "Raid") or (LFG_TYPE_DUNGEON or "Dungeon")
    GameTooltip:AddLine(kind .. " · " .. (LEVEL or "Level") .. " " .. e.levels .. (e.size and (" · " .. e.size) or ""),
        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    local zone = e.zoneID and C_Map.GetMapInfo(e.zoneID)
    zone = zone and zone.name or e.zoneName
    if zone then GameTooltip:AddLine(zone, 0.8, 0.8, 0.8) end
    if e.isNew or e.soon then GameTooltip:AddLine("New in WoW Forever", 0.31, 0.82, 0.88) end
    local c = ns.WIP_COLOR or { r = 1, g = 0.5, b = 0.25 }
    if e.soon then
        GameTooltip:AddLine("Coming soon: its map, bosses and loot aren't in the addon yet.", c.r, c.g, c.b, true)
        if e.zoneID then
            GameTooltip:AddLine(("<Click to show %s>"):format(zone or "its zone"), GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        end
    else
        if ns.InstanceStatus and ns.DungeonMaps and ns.DungeonMaps[e.key] and ns:InstanceStatus(e.key) then
            GameTooltip:AddLine("Work in progress: some data missing", c.r, c.g, c.b)
        end
        GameTooltip:AddLine("<Click to open the map>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- The list frame
----------------------------------------------------------------------

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Name:SetPoint("LEFT", 14, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.Level:SetPoint("RIGHT", -6, 0)
    row.Name:SetPoint("RIGHT", row.Level, "LEFT", -8, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self) Open(self.entry) end)
    row:SetScript("OnEnter", ShowEntryTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function NewHeader(parent)
    local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h:SetJustifyH("LEFT")
    h:SetTextColor(0.79, 0.64, 0.29)
    return h
end

local function FillRow(row, e, level)
    row.entry = e
    row.Name:SetText(e.soon and (e.name .. "  |cff808080(coming soon)|r") or e.name)
    if e.soon then
        row.Name:SetTextColor(0.5, 0.5, 0.5)
        row.Level:SetTextColor(0.5, 0.5, 0.5)
    else
        row.Name:SetTextColor(1, 1, 1)
        local c = LevelColor(e.low, e.high, level)
        row.Level:SetTextColor(c.r, c.g, c.b)
    end
    row.Level:SetText(e.levels)
    row:Show()
end

local function CreateList()
    list = CreateFrame("Frame", "BeestersDungeonMapsList", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    list:SetFrameStrata("DIALOG")
    list:SetWidth(LIST_WIDTH)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    if list.SetBackdrop then
        list:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        list:SetBackdropColor(0.04, 0.04, 0.08, 0.95)
        list:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    list:Hide()
    table.insert(UISpecialFrames, "BeestersDungeonMapsList") -- Escape closes it

    list.Title = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    list.Title:SetPoint("TOPLEFT", 12, -10)
    list.Title:SetText("For your level")
    list.Range = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    list.Range:SetPoint("TOPRIGHT", -12, -12)
    list.Mine = {}

    list.Divider = list:CreateTexture(nil, "ARTWORK")
    list.Divider:SetHeight(1)
    list.Divider:SetColorTexture(0.35, 0.35, 0.45, 0.8)
    list.AllTitle = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    list.AllTitle:SetText("All dungeons and raids")

    local ok, scroll = pcall(CreateFrame, "ScrollFrame", "BeestersDungeonMapsListScroll", list, "UIPanelScrollFrameTemplate")
    if not ok then scroll = CreateFrame("ScrollFrame", "BeestersDungeonMapsListScroll", list) end
    scroll:EnableMouseWheel(true)
    list.Scroll = scroll
    list.Child = CreateFrame("Frame", nil, scroll)
    list.Child:SetWidth(LIST_WIDTH - 40)
    list.Child:SetHeight(1)
    scroll:SetScrollChild(list.Child)
    list.Rows, list.Headers = {}, {}

    -- A click anywhere else closes it, like the game's menus.
    pcall(list.RegisterEvent, list, "GLOBAL_MOUSE_DOWN")
    list:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (button and button:IsMouseOver()) then self:Hide() end
    end)
    list:SetScript("OnHide", function() GameTooltip:Hide() end)
end

local function Layout()
    local level = UnitLevel("player") or 1
    local mine, all = ns:DungeonList(level)
    list.Range:SetText(("%s %d–%d"):format(LEVEL or "Level", math.max(1, level - LEVEL_RANGE), level + LEVEL_RANGE))

    -- Pinned: yours.
    local y = 30
    for i, e in ipairs(mine) do
        local row = list.Mine[i] or NewRow(list)
        list.Mine[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)
        row:SetPoint("TOPRIGHT", -6, -y)
        FillRow(row, e, level)
        y = y + ROW_HEIGHT
    end
    for i = #mine + 1, #list.Mine do list.Mine[i]:Hide() end
    if #mine == 0 then y = y + 4 end

    list.Divider:ClearAllPoints()
    list.Divider:SetPoint("TOPLEFT", 12, -(y + 6))
    list.Divider:SetPoint("TOPRIGHT", -12, -(y + 6))
    list.AllTitle:ClearAllPoints()
    list.AllTitle:SetPoint("TOPLEFT", 12, -(y + 14))
    y = y + 32

    -- Scrolling: everything, by level band.
    local cy, rowIndex, headerIndex = 0, 0, 0
    for _, item in ipairs(all) do
        if item.header then
            headerIndex = headerIndex + 1
            local h = list.Headers[headerIndex] or NewHeader(list.Child)
            list.Headers[headerIndex] = h
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 6, -(cy + 4))
            h:SetText(item.header)
            h:Show()
            cy = cy + 18
        else
            rowIndex = rowIndex + 1
            local row = list.Rows[rowIndex] or NewRow(list.Child)
            list.Rows[rowIndex] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -cy)
            row:SetPoint("TOPRIGHT", 0, -cy)
            FillRow(row, item, level)
            cy = cy + ROW_HEIGHT
        end
    end
    for i = rowIndex + 1, #list.Rows do list.Rows[i]:Hide() end
    for i = headerIndex + 1, #list.Headers do list.Headers[i]:Hide() end
    list.Child:SetHeight(cy)

    -- The scroll part gives up height when the pinned part is long, so the list stays on screen.
    local scrollHeight = math.max(SCROLL_MIN, math.min(SCROLL_MAX, 460 - y))
    list.Scroll:ClearAllPoints()
    list.Scroll:SetPoint("TOPLEFT", 8, -y)
    list.Scroll:SetPoint("TOPRIGHT", -30, -y)
    list.Scroll:SetHeight(scrollHeight)
    list:SetHeight(y + scrollHeight + 10)
end

local function Anchor(owner)
    list:ClearAllPoints()
    local x, y = owner:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local right = type(x) == "number" and type(w) == "number" and x > w / 2
    local low = type(y) == "number" and type(h) == "number" and y < h / 2
    local point = (low and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    local relative = (low and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT")
    list:SetPoint(point, owner, relative, 0, 0)
end

function ns:ToggleDungeonList(owner)
    if not list then CreateList() end
    if list:IsShown() then list:Hide() return end
    Layout()
    if owner and owner:IsVisible() then Anchor(owner) else list:ClearAllPoints(); list:SetPoint("CENTER") end
    list:Show()
    if list.Scroll.SetVerticalScroll then list.Scroll:SetVerticalScroll(0) end
end

----------------------------------------------------------------------
-- The minimap button
----------------------------------------------------------------------

local function Place()
    local angle = math.rad(ns.db.minimapAngle or DEFAULT_ANGLE)
    local x, y = math.cos(angle), math.sin(angle)
    local radius = (Minimap:GetWidth() / 2) + 10
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- Square minimaps (some UI addons): slide along the edge instead of a circle.
        x = math.max(-1, math.min(x * 1.42, 1))
        y = math.max(-1, math.min(y * 1.42, 1))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local atan2 = math.atan2 or function(a, b) return math.atan(a, b) end
    ns.db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
    Place()
end

local function CreateButton()
    button = CreateFrame("Button", "BeestersDungeonMapsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    -- The same parts as the game's own minimap buttons.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\AddOns\\BeestersDungeonMaps\\Media\\Logo64")
    icon:SetPoint("TOPLEFT", 7, -6)
    if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    button.Icon = icon
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if list then list:Hide() end
            ns:OpenOptions()
        else
            GameTooltip:Hide()
            ns:ToggleDungeonList(self)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        if list then list:Hide() end
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        if list and list:IsShown() then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.title, 1, 1, 1)
        GameTooltip:AddLine("<Click for the dungeon list>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        GameTooltip:AddLine("<Right-click for options>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        GameTooltip:AddLine("Drag to move this button.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.MinimapButton = button -- read by tools/test_addon.py
end

function ns:UpdateMinimapButton()
    if not button then return end
    if ns.db.minimapButton then
        Place()
        button:Show()
    else
        button:Hide()
        if list then list:Hide() end
    end
end

function ns:InitMinimap()
    if not Minimap then return end
    CreateButton()
    ns:UpdateMinimapButton()
end
