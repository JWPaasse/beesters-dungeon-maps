local _, ns = ...

----------------------------------------------------------------------
-- Dungeon quest tracker: inside a dungeon, the quests in your log that belong to it, with their
-- objectives, in the look of the game's own objective tracker. It shows nothing outside
-- dungeons, or when none of your quests are for the dungeon you're in.
----------------------------------------------------------------------

local tracker
local WIDTH = 235

-- The game's fonts for its tracker when the client has them; the usual ones otherwise.
local function Font(name, fallback)
    return _G[name] and name or fallback
end
local BASE_TITLE_FONT = Font("ObjectiveTrackerHeaderFont", "GameFontNormal")
local BASE_LINE_FONT = Font("ObjectiveTrackerLineFont", "GameFontHighlightSmall")
-- The tracker's own copies of those fonts, at the size set in the options (quest titles one
-- point bigger than the objectives, like the game's tracker).
local TITLE_FONT = CreateFont("BeestersDungeonMapsTrackerTitleFont")
local LINE_FONT = CreateFont("BeestersDungeonMapsTrackerLineFont")
TITLE_FONT:CopyFontObject(BASE_TITLE_FONT)
LINE_FONT:CopyFontObject(BASE_LINE_FONT)

-- Each font's typeface and the size the options ask for. Every line also gets the size set on
-- the line itself: a font object's new size doesn't always reach text already using it.
local fontSize = {} -- [font object] = { path, size, flags }

local function SetSize(font, base, size)
    local source = _G[base]
    if not (source and source.GetFont) then return end
    local path, _, flags = source:GetFont()
    if not path then return end
    font:SetFont(path, size, flags or "")
    fontSize[font] = { path, size, flags or "" }
end

function ns:UpdateDungeonTrackerFonts()
    local size = ns.db and ns.db.dungeonTrackerFontSize or 12
    SetSize(LINE_FONT, BASE_LINE_FONT, size)
    SetSize(TITLE_FONT, BASE_TITLE_FONT, size + 1)
    ns:UpdateDungeonTracker()
end
local HEADER_FONT = Font("ObjectiveTrackerHeaderFont", "GameFontNormalMed2")

local READY_TEXT = QUEST_WATCH_QUEST_READY or "Ready for turn-in"
local COMPLETE = { 0.6, 0.6, 0.6 }
local OPEN = { 0.8, 0.8, 0.8 }

-- The quests in your log that belong to this dungeon: { {questID, title, ready}, ... }
local function QuestsHere(key)
    local wanted = {}
    for _, lists in ipairs({ ns.DungeonQuests, ns.DungeonLogOnlyQuests }) do
        for _, id in ipairs(lists and lists[key] or {}) do wanted[id] = true end
    end
    local out = {}
    local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and wanted[info.questID] then
            local ready = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
            table.insert(out, { id = info.questID, title = info.title, level = info.level, ready = ready and true or false })
        end
    end
    return out
end

----------------------------------------------------------------------
-- Quest item buttons: an item the quest has you use, beside the quest like the game's own
-- tracker. Clicking uses it. Using an item takes a secure button, and secure buttons can't be
-- moved, shown or hidden during a fight; so they hang on UIParent (the tracker itself stays free
-- to change in combat) and are only set up out of combat. A change in a fight waits until it ends.
----------------------------------------------------------------------

local ITEM_SIZE = 26
local itemButtons = {}
local lineItem = {} -- [title line] = { itemID, icon }
local itemsPending = false

local function ItemCount(itemID)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(itemID) or 0
end

local function ItemSpell(itemID)
    local spell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    return spell and spell(itemID)
end

-- The item to show for this quest: the one the game ties to it, else one from the addon's data
-- that's in your bags and can be used. Returns itemID, icon.
local function QuestItem(questID, ready)
    -- Done with the quest's goals: the item has nothing left to do.
    if ready then return nil end
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    if index and GetQuestLogSpecialItemInfo then
        local link, icon = GetQuestLogSpecialItemInfo(index)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then return id, icon end
    end
    local q = ns.Quests and ns.Quests[questID]
    for _, id in ipairs(q and q[19] or {}) do
        if ItemCount(id) > 0 and ItemSpell(id) then
            local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
            return id, getIcon and getIcon(id) or 134400
        end
    end
end

local function ItemButton(index)
    local b = itemButtons[index]
    if b then return b end
    b = CreateFrame("Button", "BeestersDungeonMapsTrackerItem" .. index, UIParent, "SecureActionButtonTemplate")
    b:SetSize(ITEM_SIZE, ITEM_SIZE)
    -- Above the tracker (its quest lines take the mouse for clicking and dragging).
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints()
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = b:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetPoint("CENTER")
    normal:SetSize(ITEM_SIZE * 64 / 37, ITEM_SIZE * 64 / 37)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.Count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.Cooldown:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.itemID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    itemButtons[index] = b
    return b
end

local function UpdateItemCounts()
    for _, b in ipairs(itemButtons) do
        if b:IsShown() and b.itemID then
            local n = ItemCount(b.itemID)
            b.Count:SetText(n > 1 and n or "")
            local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
            if cd then
                local start, duration, enable = cd(b.itemID)
                if start and duration and duration > 0 and enable ~= 0 then
                    b.Cooldown:SetCooldown(start, duration)
                else
                    b.Cooldown:Clear()
                end
            end
        end
    end
end

-- Put the buttons beside their quests. Out of combat only.
local function PlaceItemButtons()
    if InCombatLockdown() then
        itemsPending = true
        return
    end
    itemsPending = false
    local used = 0
    if tracker and tracker:IsShown() and tracker.Content:IsShown() then
        local scale = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
        for _, line in ipairs(tracker.Lines) do
            local item = line:IsShown() and lineItem[line]
            if item and line:GetTop() then
                used = used + 1
                local b = ItemButton(used)
                b.itemID = item[1]
                b:SetAttribute("item", "item:" .. item[1])
                b.Icon:SetTexture(item[2] or 134400)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", tracker:GetRight() * scale - 2, line:GetTop() * scale)
                b:Show()
            end
        end
    end
    for i = used + 1, #itemButtons do
        itemButtons[i].itemID = nil
        itemButtons[i]:Hide()
    end
    UpdateItemCounts()
end
ns.PlaceTrackerItemButtons = PlaceItemButtons -- used by tools/test_addon.py

-- The whole tracker can be dragged: by its header, its quest lines or the space between them.
local function StartDrag()
    tracker:StartMoving()
    -- The item buttons follow while you drag (not in a fight; they catch up after it).
    tracker:SetScript("OnUpdate", function() if not InCombatLockdown() then PlaceItemButtons() end end)
end
local function StopDrag()
    tracker:StopMovingOrSizing()
    tracker:SetScript("OnUpdate", nil)
    PlaceItemButtons()
    local point, _, relPoint, x, y = tracker:GetPoint(1)
    ns.db.dungeonTrackerPos = { point, relPoint, x, y }
end
local function Draggable(frame)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
end

local function AcquireLine(index)
    local line = tracker.Lines[index]
    if not line then
        line = CreateFrame("Button", nil, tracker.Content)
        line:SetWidth(WIDTH - 12)
        line.Text = line:CreateFontString(nil, "ARTWORK", "BeestersDungeonMapsTrackerLineFont")
        line.Text:SetPoint("TOPLEFT")
        line.Text:SetWidth(WIDTH - 12)
        line.Text:SetJustifyH("LEFT")
        line:RegisterForClicks("LeftButtonUp")
        Draggable(line)
        line:SetScript("OnClick", function(self)
            if self.questID then ns:OpenTrackedQuest(self.questID) end
        end)
        line:SetScript("OnEnter", function(self)
            if not self.isTitle then return end
            self.Text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.title or "", 1, 0.82, 0)
            GameTooltip:AddLine("<Click to open it on the dungeon map>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            GameTooltip:AddLine("<Drag to move the tracker>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            GameTooltip:Show()
        end)
        line:SetScript("OnLeave", function(self)
            if self.isTitle then self.Text:SetTextColor(self.r, self.g, self.b) end
            GameTooltip:Hide()
        end)
        tracker.Lines[index] = line
    end
    return line
end

local function SetLine(line, font, text, color, indent, room)
    line.Text:SetFontObject(font)
    local f = fontSize[font]
    if f then line.Text:SetFont(f[1], f[2], f[3]) end
    line.Text:SetText(text)
    line.r, line.g, line.b = color[1], color[2], color[3]
    line.Text:SetTextColor(color[1], color[2], color[3])
    line.Text:ClearAllPoints()
    line.Text:SetPoint("TOPLEFT", indent or 0, 0)
    line.Text:SetWidth(WIDTH - 12 - (indent or 0) - (room or 0))
    line:SetHeight(line.Text:GetStringHeight() + 2)
end

function ns:UpdateDungeonTracker()
    if not tracker then return end
    local key = ns.CurrentInstanceKey and ns.CurrentInstanceKey()
    local quests = key and ns.db.dungeonTracker and QuestsHere(key) or {}
    if #quests == 0 then
        tracker:Hide()
        PlaceItemButtons()
        return
    end
    tracker:Show()
    tracker.Header.Text:SetText(ns.Instances[key] and ns.Instances[key].name or (QUESTS_LABEL or "Quests"))
    tracker.Content:SetShown(not ns.db.dungeonTrackerCollapsed)
    tracker.Header.Toggle:SetText(ns.db.dungeonTrackerCollapsed and "+" or "-")
    if ns.db.dungeonTrackerCollapsed then
        tracker:SetHeight(tracker.Header:GetHeight())
        PlaceItemButtons()
        return
    end

    local index, y = 0, 0
    local function Add(font, text, color, indent, questID, title, isTitle, itemID, itemIcon)
        index = index + 1
        local line = AcquireLine(index)
        -- A quest with an item: its lines leave room on the right for the button.
        SetLine(line, font, text, color, indent, itemID and (ITEM_SIZE + 4) or 0)
        line.questID, line.title, line.isTitle = questID, title, isTitle
        lineItem[line] = isTitle and itemID and { itemID, itemIcon } or nil
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", tracker.Content, "TOPLEFT", 0, -y)
        line:Show()
        y = y + line:GetHeight() + (isTitle and 3 or 1)
    end
    for qi, q in ipairs(quests) do
        if qi > 1 then y = y + 8 end
        local yellow = NORMAL_FONT_COLOR
        local title = q.title or ("Quest " .. q.id)
        if q.level and q.level > 0 then title = ("[%d] %s"):format(q.level, title) end -- as in the dungeon tab
        local itemID, itemIcon = QuestItem(q.id, q.ready)
        local top = y
        Add(TITLE_FONT, title, { yellow.r, yellow.g, yellow.b }, 0, q.id, q.title, true, itemID, itemIcon)
        if q.ready then
            local g = GREEN_FONT_COLOR
            Add(LINE_FONT, "- " .. READY_TEXT, { g.r, g.g, g.b }, 8, q.id, nil, nil, itemID)
        else
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.id) or {}) do
                if o.text and o.text ~= "" then
                    Add(LINE_FONT, "- " .. o.text, o.finished and COMPLETE or OPEN, 8, q.id, nil, nil, itemID)
                end
            end
        end
        -- The button is as tall as two lines: a one-line quest still makes room for it.
        if itemID then y = math.max(y, top + ITEM_SIZE + 2) end
    end
    for i = index + 1, #tracker.Lines do
        tracker.Lines[i]:Hide()
        lineItem[tracker.Lines[i]] = nil
    end
    tracker.Content:SetHeight(math.max(y, 1))
    tracker:SetHeight(tracker.Header:GetHeight() + 6 + y)
    PlaceItemButtons()
end

-- Clicking a quest: open its dungeon's map with that quest's details (not in combat: the game
-- doesn't let addons open the map then).
function ns:OpenTrackedQuest(questID)
    local key = ns.CurrentInstanceKey and ns.CurrentInstanceKey()
    if not key or InCombatLockdown() then return end
    if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    C_Timer.After(0.1, function()
        if not ns:IsDungeonMapOpen() then ns:OpenDungeonMap(key) end
        C_Timer.After(0.1, function()
            if ns.ShowQuestDetail then pcall(ns.ShowQuestDetail, questID) end
        end)
    end)
end

local function CreateTracker()
    tracker = CreateFrame("Frame", "BeestersDungeonMapsTracker", UIParent)
    tracker:SetSize(WIDTH, 40)
    tracker:SetFrameStrata("LOW")
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    local pos = ns.db.dungeonTrackerPos
    if pos then
        tracker:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        -- Where the game's own tracker sits: on the right, under the minimap.
        tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -85, -260)
    end

    -- Header: the game's tracker header when the client has the template, like "Quests" above
    -- the game's own list; drag it to move the tracker, the button folds it up.
    local header = CreateFrame("Button", nil, tracker)
    header:SetSize(WIDTH, 26)
    header:SetPoint("TOPLEFT")
    header.Background = header:CreateTexture(nil, "BACKGROUND")
    header.Background:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-QuestTracker-Primary-Objective-Header") then
        header.Background:SetAtlas("UI-QuestTracker-Primary-Objective-Header")
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Objective-Header") then
        header.Background:SetAtlas("Objective-Header")
    else
        header.Background:SetColorTexture(0, 0, 0, 0.35)
    end
    header.Text = header:CreateFontString(nil, "ARTWORK", HEADER_FONT)
    header.Text:SetPoint("LEFT", 8, 0)
    header.Text:SetPoint("RIGHT", -28, 0)
    header.Text:SetJustifyH("LEFT")
    header.Toggle = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.Toggle:SetSize(20, 18)
    header.Toggle:SetPoint("RIGHT", -2, 0)
    header.Toggle:SetText("-")
    header.Toggle:SetScript("OnClick", function()
        ns.db.dungeonTrackerCollapsed = not ns.db.dungeonTrackerCollapsed
        ns:UpdateDungeonTracker()
    end)
    Draggable(header)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dungeon quests", 1, 1, 1)
        GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tracker.Header = header

    Draggable(tracker)
    tracker.Content = CreateFrame("Frame", nil, tracker)
    tracker.Content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -6)
    tracker.Content:SetSize(WIDTH - 8, 1)
    tracker.Lines = {}
    tracker:Hide()
end

function ns:ResetDungeonTracker()
    ns.db.dungeonTrackerPos = nil
    if not tracker then return end
    tracker:ClearAllPoints()
    tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -85, -260)
    PlaceItemButtons()
end

function ns:InitDungeonTracker()
    if tracker then return end
    CreateTracker()
    ns:UpdateDungeonTrackerFonts()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED",
        "BAG_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    local pending = false
    events:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_COOLDOWN" then UpdateItemCounts() return end
        if event == "PLAYER_REGEN_ENABLED" and not itemsPending then return end
        -- Quest events come in bursts; draw once.
        if pending then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = false
            ns:UpdateDungeonTracker()
        end)
    end)
end
