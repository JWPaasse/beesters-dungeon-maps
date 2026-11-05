-- Beester's Dungeon Maps: the dungeon map view inside the game's own Map & Quest Log window.
--
-- WoW Forever has no maps inside dungeons (the map falls back to the World view there).
-- This view takes the place of the map picture while a dungeon is open:
--   * old dungeons: the classic dungeon map tiles that still ship in the game files
--   * new Forever dungeons: Santiago Reyes's maps (watermarked, used with permission)
-- with boss pins (Dungeon Journal positions) and a game-style tooltip with the boss's loot.
--
-- It opens by itself inside a dungeon, from an entrance pin, or from the map's top bar
-- (World > Kalimdor > Durotar > Dungeons). Any other map navigation closes it again.

local _, ns = ...

local view            -- the frame that covers the map picture
local current = {}    -- key, floor, zoneMapID
local opening = false -- true while we change the map ourselves

local MAP_W, MAP_H = 1002, 668 -- classic map tiles: 4 x 3 tiles of 256, this much is shown
local SKULL_ATLAS = "DungeonSkull"
local SKULL_FALLBACK = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- Floor names where the game's own names are well known. Others are "Level 1", "Level 2", ...
local FLOOR_NAMES = {
    sm = { "Graveyard", "Library", "Armory", "Cathedral" },
    strat = { "Main Gate", "Service Gate" },
    ulda = { "Uldaman", "Hall of the Keepers" },
    mara = { "Caverns of Maraudon", "Zaetar's Grave" },
}

-- Boss names that differ between the game's boss list and the Dungeon Journal.
local NAME_ALIASES = {
    hazzas = "wardensofthedream", morphaz = "wardensofthedream",
    weaver = "wardensofthedream", dreamscythe = "wardensofthedream",
    nekrumgutchewer = "nekrumsezzziz", shadowpriestsezzziz = "nekrumsezzziz",
    cannonmasterwilley = "willeyhopebreaker", archivistgalford = "instructorgalford",
    malorthezealous = "commandermalor", baronrivendare = "lordauriusrivendare",
    overlordramtusk = "warlordramtusk",
}

local function Normalize(name)
    local n = (name or ""):lower():gsub("[^%a]", "")
    return NAME_ALIASES[n] or n
end

----------------------------------------------------------------------
-- Data helpers
----------------------------------------------------------------------

local function FloorName(key, index)
    local map = ns.DungeonMaps[key]
    local floor = map and map.floors[index]
    if floor and floor.name then return floor.name end
    local names = FLOOR_NAMES[key]
    return names and names[index] or (("Level %d"):format(index))
end

-- The game's boss list for an instance, each with its map position when the Journal has one.
local function BossesWithPositions(key)
    local positions = ns.BossPositions and ns.BossPositions[key] or {}
    local byEncounter, byName = {}, {}
    for _, p in ipairs(positions) do
        byEncounter[p[4]] = p
        byName[Normalize(p[5])] = p
    end
    local result = {}
    local custom = ns.db and ns.db.bossPositions and ns.db.bossPositions[key]
    local list = ns.Bosses and ns.Bosses[key]
    if list then
        for order, boss in ipairs(list) do
            local encounterID, name, npcID = boss[1], boss[2], boss[3]
            local p = byEncounter[encounterID] or byName[Normalize(name)]
            local mine = custom and custom[name]
            if mine then p = { mine[1], mine[2], mine[3] } end
            table.insert(result, {
                order = order, encounterID = encounterID, name = name, npcID = npcID,
                floor = p and p[1], x = p and p[2], y = p and p[3], custom = mine and true or nil,
            })
        end
    else
        -- No boss list from the game (yet): show the Journal's bosses as they are.
        for order, p in ipairs(positions) do
            table.insert(result, { order = order, encounterID = p[4], name = p[5], floor = p[1], x = p[2], y = p[3] })
        end
    end
    return result
end

----------------------------------------------------------------------
-- Boss tooltip (name, place in the dungeon, loot)
----------------------------------------------------------------------

local MIN_QUALITY = 2 -- Uncommon and better

local function ItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then
        local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        return name, link, quality, icon
    elseif GetItemInfo then
        local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        return name, link, quality, icon
    end
end

local function RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

local function ShowBossTooltip(owner, boss, total)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(boss.name, 1, 1, 1)
    GameTooltip:AddLine(("Boss %d of %d"):format(boss.order, total), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    if boss.npcID and ns.BossLoot and ns.BossLoot[boss.npcID] then
        GameTooltip:AddLine("<Click to see loot>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    end
    if boss.custom then
        GameTooltip:AddLine("Placed by you. Shift-right-click to undo.", 0.6, 0.6, 0.6, true)
    elseif not boss.x then
        GameTooltip:AddLine("Shift-drag onto the map to place this boss.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Loot panel: opens when you click a boss. Hover an item for its game tooltip,
-- shift-click to link it in chat, ctrl-click to try it on.
----------------------------------------------------------------------

local lootPanel

local function RefreshLootPanel()
    local panel = lootPanel
    if not panel or not panel:IsShown() then return end
    local boss = panel.boss
    local loot = boss.npcID and ns.BossLoot and ns.BossLoot[boss.npcID] or {}
    panel.Title:SetText(boss.name)
    local index, waiting = 0, false
    for _, itemID in ipairs(loot) do
        local name, link, quality, icon = ItemInfo(itemID)
        if not name then
            waiting = true
            RequestItem(itemID)
        elseif (quality or 0) >= MIN_QUALITY then
            index = index + 1
            local row = panel.Rows[index]
            if not row then
                row = CreateFrame("Button", nil, panel)
                row:SetSize(230, 22)
                row.Icon = row:CreateTexture(nil, "ARTWORK")
                row.Icon:SetSize(20, 20)
                row.Icon:SetPoint("LEFT")
                row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
                row.Name:SetPoint("RIGHT")
                row.Name:SetJustifyH("LEFT")
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:SetScript("OnClick", function(self)
                    if HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
                end)
                panel.Rows[index] = row
            end
            row.itemID, row.link = itemID, link
            row.Icon:SetTexture(icon)
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            row.Name:SetText(name)
            if color then row.Name:SetTextColor(color.r, color.g, color.b) end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 12, -30 - (index - 1) * 22)
            row:Show()
        end
    end
    for i = index + 1, #panel.Rows do panel.Rows[i]:Hide() end
    panel.Empty:SetShown(index == 0)
    panel.Empty:SetText(waiting and (SEARCH_LOADING_TEXT or "Loading...") or "No Uncommon or better loot known.")
    panel:SetHeight(44 + math.max(index, 1) * 22)
end

local function CreateLootPanel(parent)
    local panel = CreateFrame("Frame", "BeestersDungeonMapsLoot", parent, BackdropTemplateMixin and "BackdropTemplate")
    panel:SetSize(254, 100)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.Title:SetPoint("TOPLEFT", 12, -10)
    panel.Title:SetPoint("RIGHT", -30, 0)
    panel.Title:SetJustifyH("LEFT")
    panel.Close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panel.Close:SetPoint("TOPRIGHT", 2, 2)
    panel.Empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.Empty:SetPoint("TOPLEFT", 12, -34)
    panel.Rows = {}
    panel:Hide()
    return panel
end

local function ToggleLoot(owner, boss)
    if not lootPanel then lootPanel = CreateLootPanel(view) end
    if lootPanel:IsShown() and lootPanel.boss == boss then
        lootPanel:Hide()
        return
    end
    lootPanel.boss = boss
    lootPanel:ClearAllPoints()
    lootPanel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    lootPanel:SetClampedToScreen(true)
    lootPanel:Show()
    RefreshLootPanel()
end

-- Item names arrive from the server a moment later; refresh what's open once they do.
local itemListener = CreateFrame("Frame")
itemListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemListener:SetScript("OnEvent", function()
    if lootPanel and lootPanel:IsShown() then
        if not itemListener.pending then
            itemListener.pending = true
            C_Timer.After(0.1, function() itemListener.pending = false; RefreshLootPanel() end)
        end
    end
end)

----------------------------------------------------------------------
-- Placing bosses yourself (for bosses no data source has a position for)
----------------------------------------------------------------------

local ShowFloor -- defined below

local function SaveCustomPosition(boss, x, y)
    ns.db.bossPositions = ns.db.bossPositions or {}
    local list = ns.db.bossPositions[current.key] or {}
    ns.db.bossPositions[current.key] = list
    list[boss.name] = { current.floor, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000 }
end

local function CursorOnArt()
    local left, bottom, width, height = view.Art:GetRect()
    if not left then return end
    local scale = view.Art:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local x, y = (cx - left) / width, (bottom + height - cy) / height
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

local function StartPlacing(self)
    if not IsShiftKeyDown() then return end
    self.placing = true
    SetCursor("Interface\\Cursor\\UI-Cursor-Move")
end

local function StopPlacing(self)
    if not self.placing then return end
    self.placing = false
    ResetCursor()
    local x, y = CursorOnArt()
    if x then
        SaveCustomPosition(self.boss, x, y)
        ShowFloor(current.floor)
    end
end

local function BossClick(self, button)
    if button == "RightButton" and IsShiftKeyDown() and self.boss.custom then
        local list = ns.db.bossPositions and ns.db.bossPositions[current.key]
        if list then list[self.boss.name] = nil end
        ShowFloor(current.floor)
    elseif button == "LeftButton" and not IsShiftKeyDown() then
        ToggleLoot(self, self.boss)
    end
end

local function SetupBossFrame(frame)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartPlacing)
    frame:SetScript("OnDragStop", StopPlacing)
    frame:SetScript("OnClick", BossClick)
    frame:SetScript("OnEnter", function(self) ShowBossTooltip(self, self.boss, self.total) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- The view
----------------------------------------------------------------------

local function CreateBossButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(26, 26)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKULL_ATLAS) then
        button.Icon:SetAtlas(SKULL_ATLAS)
    else
        button.Icon:SetTexture(SKULL_FALLBACK)
    end
    button.Highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.Highlight:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKULL_ATLAS) then
        button.Highlight:SetAtlas(SKULL_ATLAS)
    else
        button.Highlight:SetTexture(SKULL_FALLBACK)
    end
    button.Highlight:SetBlendMode("ADD")
    button.Highlight:SetAlpha(0.4)
    SetupBossFrame(button)
    return button
end

local function CreateListRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(18)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SKULL_ATLAS) then
        row.Icon:SetAtlas(SKULL_ATLAS)
    else
        row.Icon:SetTexture(SKULL_FALLBACK)
    end
    row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    SetupBossFrame(row)
    return row
end

local function Layout()
    if not view or not view:IsShown() then return end
    local w, h = view:GetSize()
    if w <= 0 or h <= 0 then return end
    -- Keep the map's 3:2 shape and fit it inside the map area.
    local artW = math.min(w, h * 1.5)
    local artH = artW / 1.5
    view.Art:SetSize(artW, artH)

    local floor = ns.DungeonMaps[current.key].floors[current.floor]
    if floor.tiles then
        local scale = artW / MAP_W
        for i = 1, 12 do
            local tex = view.Tiles[i]
            tex:SetSize(256 * scale, 256 * scale)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", view.Art, "TOPLEFT", ((i - 1) % 4) * 256 * scale, -math.floor((i - 1) / 4) * 256 * scale)
        end
    else
        view.Left:SetSize(artW * 1024 / 1536, artH)
        view.Right:SetSize(artW * 512 / 1536, artH)
    end

    for _, button in ipairs(view.BossButtons) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("CENTER", view.Art, "TOPLEFT", button.boss.x * artW, -button.boss.y * artH)
        end
    end
end

function ShowFloor(index)
    if lootPanel then lootPanel:Hide() end
    local map = ns.DungeonMaps[current.key]
    current.floor = index
    local floor = map.floors[index]

    if floor.tiles then
        view.Left:Hide()
        view.Right:Hide()
        for i = 1, 12 do
            view.Tiles[i]:SetTexture(floor.tiles[i])
            view.Tiles[i]:Show()
        end
    else
        for i = 1, 12 do view.Tiles[i]:Hide() end
        view.Left:SetTexture(floor.texture .. "a")
        view.Right:SetTexture(floor.texture .. "b")
        view.Left:Show()
        view.Right:Show()
    end
    view.Credit:SetShown(map.artist ~= nil)
    if map.artist then
        view.Credit:SetText(("Map by %s"):format(map.artist))
    end

    -- Boss pins on this floor; bosses without a known position go in the list.
    local bosses = BossesWithPositions(current.key)
    local pinIndex, rowIndex = 0, 0
    for _, boss in ipairs(bosses) do
        if boss.x and boss.floor == index then
            pinIndex = pinIndex + 1
            local button = view.BossButtons[pinIndex] or CreateBossButton(view.Art)
            view.BossButtons[pinIndex] = button
            button.boss, button.total = boss, #bosses
            button:Show()
        elseif not boss.x then
            rowIndex = rowIndex + 1
            local row = view.ListRows[rowIndex] or CreateListRow(view.List)
            view.ListRows[rowIndex] = row
            row.boss, row.total = boss, #bosses
            row.Text:SetText(boss.name)
            row:SetWidth(row.Text:GetStringWidth() + 24)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", view.List, "TOPLEFT", 8, -24 - (rowIndex - 1) * 18)
            row:Show()
        end
    end
    for i = pinIndex + 1, #view.BossButtons do view.BossButtons[i]:Hide() end
    for i = rowIndex + 1, #view.ListRows do view.ListRows[i]:Hide() end
    view.List:SetShown(rowIndex > 0)
    if rowIndex > 0 then
        local widest = 120
        for i = 1, rowIndex do widest = math.max(widest, view.ListRows[i]:GetWidth() + 16) end
        view.List:SetSize(widest, 30 + rowIndex * 18)
    end

    if view.FloorDropdown then
        view.FloorDropdown:SetShown(#map.floors > 1)
        if view.FloorDropdown.GenerateMenu then view.FloorDropdown:GenerateMenu() end
        if view.FloorDropdown.SetText and not view.FloorDropdown.GenerateMenu then
            view.FloorDropdown:SetText(FloorName(current.key, index))
        end
    end
    Layout()
end

local function CreateView()
    local container = WorldMapFrame.ScrollContainer
    view = CreateFrame("Frame", "BeestersDungeonMapsView", container)
    view:SetAllPoints(container)
    view:SetFrameLevel(container:GetFrameLevel() + 1)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function() end) -- don't zoom the hidden map underneath
    view:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns:CloseDungeonMap(true) end -- like zooming out on the map
    end)
    view:SetScript("OnSizeChanged", Layout)
    view:Hide()

    local background = view:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 1)

    view.Art = CreateFrame("Frame", nil, view)
    view.Art:SetPoint("CENTER")
    view.Art:SetClipsChildren(true)
    view.Tiles = {}
    for i = 1, 12 do
        view.Tiles[i] = view.Art:CreateTexture(nil, "ARTWORK")
    end
    view.Left = view.Art:CreateTexture(nil, "ARTWORK")
    view.Left:SetPoint("TOPLEFT")
    view.Right = view.Art:CreateTexture(nil, "ARTWORK")
    view.Right:SetPoint("TOPLEFT", view.Left, "TOPRIGHT")
    view.BossButtons = {}

    view.Credit = view.Art:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.Credit:SetPoint("BOTTOMLEFT", 10, 8)

    -- Bosses whose place on the map isn't known yet.
    view.List = CreateFrame("Frame", nil, view.Art, BackdropTemplateMixin and "BackdropTemplate")
    view.List:SetPoint("BOTTOMRIGHT", -10, 10)
    if view.List.SetBackdrop then
        view.List:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        view.List:SetBackdropColor(0, 0, 0, 0.75)
        view.List:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    end
    view.List.Title = view.List:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    view.List.Title:SetPoint("TOPLEFT", 8, -8)
    view.List.Title:SetText(BOSSES or "Bosses")
    view.ListRows = {}

    -- Floor picker, like the game's own floor dropdown on multi-level maps.
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetPoint("TOPLEFT", 12, -10)
        dropdown:SetWidth(190)
        dropdown:SetupMenu(function(_, root)
            local map = current.key and ns.DungeonMaps[current.key]
            if not map then return end
            for i = 1, #map.floors do
                root:CreateRadio(FloorName(current.key, i),
                    function() return current.floor == i end,
                    function() ShowFloor(i) end)
            end
        end)
    else
        dropdown = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        dropdown:SetPoint("TOPLEFT", 12, -10)
        dropdown:SetSize(190, 22)
        dropdown:SetScript("OnClick", function()
            local map = ns.DungeonMaps[current.key]
            ShowFloor(current.floor % #map.floors + 1)
        end)
    end
    view.FloorDropdown = dropdown
end

----------------------------------------------------------------------
-- Opening and closing
----------------------------------------------------------------------

function ns:IsDungeonMapOpen()
    return view ~= nil and view:IsShown()
end

function ns:CurrentDungeonKey()
    return current.key
end

local function SetCanvasShown(shown)
    local child = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if child then child:SetShown(shown) end
end

function ns:OpenDungeonMap(key, floor)
    if not (ns.DungeonMaps and ns.DungeonMaps[key]) then
        ns:Print(("No map for %s yet."):format(ns.Instances[key] and ns.Instances[key].name or key))
        return
    end
    if not WorldMapFrame:IsShown() then
        ShowUIPanel(WorldMapFrame)
    end
    if not view then CreateView() end

    -- Stay on the current map when it shows this dungeon's entrance; otherwise go to the
    -- entrance's zone, so the top bar reads World > Kalimdor > Durotar > Ragefire Chasm.
    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local onZone = info and info.mapType >= Enum.UIMapType.Zone
    if not (onZone and ns:MapShowsDungeon(mapID, key)) then
        local zone = ns:EntranceMapFor(key)
        if zone and zone ~= mapID then
            opening = true
            WorldMapFrame:SetMapID(zone)
            opening = false
        end
    end

    if key == "dme" or key == "dmn" or key == "dmw" then
        ns.db.lastDireMaulWing = key
    end
    current.key = key
    current.zoneMapID = WorldMapFrame:GetMapID()
    SetCanvasShown(false)
    view:Show()
    ShowFloor(floor or 1)
    if WorldMapFrame.NavBar and WorldMapFrame.NavBar.Refresh then
        WorldMapFrame.NavBar:Refresh()
    end
    if ns.ShowDungeonQuests then ns:ShowDungeonQuests(key) end
end

function ns:CloseDungeonMap(refreshNavBar)
    if not ns:IsDungeonMapOpen() then return end
    view:Hide()
    if lootPanel then lootPanel:Hide() end
    if ns.HideDungeonQuests then ns:HideDungeonQuests() end
    current.key = nil
    current.zoneMapID = nil
    SetCanvasShown(true)
    if refreshNavBar and WorldMapFrame.NavBar and WorldMapFrame.NavBar.Refresh then
        WorldMapFrame.NavBar:Refresh()
    end
end

-- Which of our dungeons is the player in right now?
local function CurrentInstanceKey()
    local inInstance = IsInInstance()
    if not inInstance then return nil end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local key = ns.InstanceByMap and ns.InstanceByMap[instanceID]
    if key == "dme" and ns.db.lastDireMaulWing then
        key = ns.db.lastDireMaulWing
    end
    return key
end
ns.CurrentInstanceKey = CurrentInstanceKey

----------------------------------------------------------------------
-- Top bar (breadcrumb): World > Kalimdor > Durotar > Dungeons / Ragefire Chasm
----------------------------------------------------------------------

local function DungeonMenuList(mapID)
    local list = {}
    for _, key in ipairs(ns:DungeonsOnMap(mapID)) do
        if ns.DungeonMaps[key] then
            table.insert(list, {
                text = ns.Instances[key].name,
                id = key,
                func = function(_, id) ns:OpenDungeonMap(id) end,
            })
        end
    end
    return list
end

local function DecorateNavBar(navBar)
    if not ns.db or not ns.db.dungeonsInTopBar or not NavBar_AddButton then return end
    -- Read the map when the list opens, not when the bar was built.
    local listFunc = function() return DungeonMenuList(WorldMapFrame:GetMapID()) end

    if ns:IsDungeonMapOpen() then
        NavBar_AddButton(navBar, {
            name = ns.Instances[current.key].name,
            id = current.key,
            OnClick = function() end,
            listFunc = function() return DungeonMenuList(current.zoneMapID) end,
        })
    elseif #DungeonMenuList(WorldMapFrame:GetMapID()) > 0 then
        NavBar_AddButton(navBar, {
            name = DUNGEONS or "Dungeons",
            OnClick = function(button)
                -- The crumb itself opens its list, like the arrow next to it.
                if button.MenuArrowButton and button.MenuArrowButton.OpenMenu then
                    button.MenuArrowButton:OpenMenu()
                end
            end,
            listFunc = listFunc,
        })
    end
end

----------------------------------------------------------------------
-- Set-up
----------------------------------------------------------------------

function ns:InitDungeonMap()
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer and ns.DungeonMaps) then return end

    -- Any map change we didn't make ourselves closes the dungeon map.
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        if not opening then ns:CloseDungeonMap(false) end
    end)
    local navBar = WorldMapFrame.NavBar
    if navBar then
        if navBar.Refresh then hooksecurefunc(navBar, "Refresh", DecorateNavBar) end
        -- Clicking a crumb for the map we're already on doesn't change the map; still close.
        if navBar.GoToMap then
            hooksecurefunc(navBar, "GoToMap", function() ns:CloseDungeonMap(true) end)
        end
    end

    -- Inside a dungeon the game has no map, so open ours when the map opens.
    WorldMapFrame:HookScript("OnShow", function()
        if not ns.db.autoOpenInside then return end
        local key = CurrentInstanceKey()
        if key and ns.DungeonMaps[key] then
            C_Timer.After(0, function()
                if WorldMapFrame:IsShown() and not ns:IsDungeonMapOpen() then
                    ns:OpenDungeonMap(key)
                end
            end)
        end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        ns:CloseDungeonMap(false)
        if ns.ClearQuestMarker then ns:ClearQuestMarker() end
    end)
    ns.dungeonMapActive = true
end
