-- Beester's Dungeon Maps: options panel in the game's own Settings window.
-- Built from Blizzard's own templates so it looks like the rest of the game.

local _, ns = ...

local panel

local function NewCheckbox(parent, label, tooltip, key, anchor)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
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
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return check
end

local function NewSlider(parent, name, label, key, minValue, maxValue, anchor)
    local ok, slider = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
    if not ok or not slider then
        slider = CreateFrame("Slider", name, parent, "UISliderTemplateWithLabels")
    end
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -28)
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
            ns:RefreshMapPins()
        end
        UpdateLabel(value)
    end)
    return slider
end

function ns:InitOptions()
    panel = CreateFrame("Frame")
    panel.name = ns.title

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.logo)
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 12, -10)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    title:SetText(ns.title)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(("Version %s · open with %s · entrance data: QuestieDB %s"):format(
        ns.version, ns.slashCommand or "/beesterdm", tostring(ns.dataVersion)))

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 4, -16)
    header:SetText(WORLD_MAP or "World Map")

    local dungeons = NewCheckbox(panel, "Show dungeon entrances", "Show dungeon entrances on zone and continent maps.", "showDungeons", header)
    local raids = NewCheckbox(panel, "Show raid entrances", "Show raid entrances on zone and continent maps.", "showRaids", dungeons)
    local continents = NewCheckbox(panel, "Also show entrances on continent maps", "Turn off to show entrances only on zone maps.", "showOnContinents", raids)
    local slider = NewSlider(panel, "BeestersDungeonMapsEntranceSizeSlider", "Entrance icon size", "entranceSize", 16, 48, continents)

    local mapsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    mapsHeader:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -28)
    mapsHeader:SetText("Dungeon maps")
    local auto = NewCheckbox(panel, "Open the dungeon map inside dungeons",
        "When you open your map inside a dungeon, show that dungeon's map.", "autoOpenInside", mapsHeader)
    NewCheckbox(panel, "List dungeons in the map's top bar",
        "Adds a Dungeons button after the zone name (World > Kalimdor > Durotar > Dungeons).", "dungeonsInTopBar", auto)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns:OpenOptions()
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice on purpose: the old options window needs it to scroll to the category.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
