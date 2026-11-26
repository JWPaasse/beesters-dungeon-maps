-- Beester's Dungeon Maps: options panel in the game's own Settings window.
-- Built from Blizzard's own templates so it looks like the rest of the game.

local _, ns = ...

local panel

-- The page is built top to bottom: each part goes below the last at a fixed left edge, so
-- everything lines up whatever its kind.
local Layout = {}
Layout.__index = Layout

local function NewLayout(content, top)
    return setmetatable({ content = content, y = top }, Layout)
end

-- A section title with a thin line under it, like the categories in the game's settings.
function Layout:Header(text)
    self.y = self.y - (self.started and 22 or 0)
    self.started = true
    local header = self.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, self.y)
    header:SetText(text)
    local line = self.content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    line:SetPoint("RIGHT", self.content, "RIGHT", -24, 0)
    self.y = self.y - 30
    return header
end

function Layout:Checkbox(label, tooltip, key)
    local check = CreateFrame("CheckButton", nil, self.content, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 24, self.y)
    check:SetSize(26, 26)
    local text = check.Text or check.text
    if text then
        text:SetText(label)
        text:SetFontObject("GameFontHighlight")
    end
    check.tooltipText = tooltip
    check:SetScript("OnShow", function(self) self:SetChecked(ns.db[key]) end)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        ns:RefreshMapPins()
        if ns.UpdateDungeonTracker then ns:UpdateDungeonTracker() end
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.y = self.y - 30
    return check
end

function Layout:Slider(name, label, key, minValue, maxValue, onChange)
    self.y = self.y - 18 -- room for the label above the bar
    local ok, slider = pcall(CreateFrame, "Slider", name, self.content, "OptionsSliderTemplate")
    if not ok or not slider then
        slider = CreateFrame("Slider", name, self.content, "UISliderTemplateWithLabels")
    end
    slider:SetPoint("TOPLEFT", 32, self.y)
    slider:SetWidth(220)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local title = slider.Text or _G[name .. "Text"]
    local low = slider.Low or _G[name .. "Low"]
    local high = slider.High or _G[name .. "High"]
    if low then low:SetText(minValue) end
    if high then high:SetText(maxValue) end

    local function UpdateLabel(value)
        if title then title:SetText(("%s: %d"):format(label, value)) end
    end
    slider:SetScript("OnShow", function(self)
        self:SetValue(ns.db[key])
        UpdateLabel(ns.db[key])
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if ns.db[key] ~= value then
            ns.db[key] = value
            if onChange then onChange(value) else ns:RefreshMapPins() end
        end
        UpdateLabel(value)
    end)
    self.y = self.y - 40 -- the bar and the numbers under it
    return slider
end

function ns:InitOptions()
    panel = CreateFrame("Frame")
    panel.name = ns.title

    -- The page scrolls when the window is too short for it.
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "ScrollFrameTemplate")
    if not ok or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 600)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width) content:SetWidth(width) end)

    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.logo)
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 12, -8)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    title:SetText(ns.title)

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(("Version %s · open with %s · entrance data: QuestieDB %s"):format(
        ns.version, ns.slashCommand or "/beesterdm", tostring(ns.dataVersion)))

    local page = NewLayout(content, -76)

    page:Header(WORLD_MAP or "World Map")
    page:Checkbox("Show dungeon entrances", "Show dungeon entrances on zone and continent maps.", "showDungeons")
    page:Checkbox("Show raid entrances", "Show raid entrances on zone and continent maps.", "showRaids")
    page:Checkbox("Also show entrances on continent maps", "Turn off to show entrances only on zone maps.", "showOnContinents")
    page:Checkbox("List dungeons in the map's top bar",
        "Adds a Dungeons button after the zone name (World > Kalimdor > Durotar > Dungeons).", "dungeonsInTopBar")
    page:Slider("BeestersDungeonMapsEntranceSizeSlider", "Entrance icon size", "entranceSize", 16, 48)

    page:Header("Dungeon maps")
    page:Checkbox("Open the dungeon map inside dungeons",
        "When you open your map inside a dungeon, show that dungeon's map.", "autoOpenInside")
    page:Checkbox("Show which boss drops an item",
        "Adds \"Dropped by: boss (dungeon)\" to the tooltip of every item the dungeon bosses drop.", "dropTooltip")

    page:Header(QUESTS_LABEL or "Quests")
    page:Checkbox("Show the dungeon's quests next to its map",
        "Adds a tab with the dungeon's quests to the quest list while a dungeon map is open.", "questPanel")
    page:Checkbox("Track the dungeon's quests inside dungeons",
        "Inside a dungeon, shows the quests in your log for that dungeon with their objectives, like the game's quest tracker. Drag it to move it.", "dungeonTracker")
    page:Slider("BeestersDungeonMapsTrackerFontSlider", "Quest tracker text size", "dungeonTrackerFontSize", 9, 20,
        function() if ns.UpdateDungeonTrackerFonts then ns:UpdateDungeonTrackerFonts() end end)

    page:Header(MINIMAP_LABEL or "Minimap")
    page:Checkbox("Show the minimap button",
        "A button on the minimap that lists every dungeon and raid, yours on top. The list also opens with /bdm list.", "minimapButton")
    page:Checkbox("List the dungeons for your level on top",
        "Pins the dungeons within 5 levels of yours above the full list. Turn off to see only the full list.", "suggestDungeons")

    content:SetHeight(-page.y + 16)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- The game's Settings window can't be opened by an addon during combat: open it afterwards.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ns:OpenOptions()
end)

function ns:OpenOptions()
    if InCombatLockdown() then
        afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns:Print("The options open when combat ends.")
        return
    end
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice on purpose: the old options window needs it to scroll to the category.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
