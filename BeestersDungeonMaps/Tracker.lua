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
local TITLE_FONT = Font("ObjectiveTrackerHeaderFont", "GameFontNormal")
local LINE_FONT = Font("ObjectiveTrackerLineFont", "GameFontHighlightSmall")
local HEADER_FONT = Font("ObjectiveTrackerHeaderFont", "GameFontNormalMed2")

local READY_TEXT = QUEST_WATCH_QUEST_READY or "Ready for turn-in"
local COMPLETE = { 0.6, 0.6, 0.6 }
local OPEN = { 0.8, 0.8, 0.8 }

-- The quests in your log that belong to this dungeon: { {questID, title, ready}, ... }
local function QuestsHere(key)
    local list = ns.DungeonQuests and ns.DungeonQuests[key]
    if not list then return {} end
    local wanted = {}
    for _, id in ipairs(list) do wanted[id] = true end
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

local function AcquireLine(index)
    local line = tracker.Lines[index]
    if not line then
        line = CreateFrame("Button", nil, tracker.Content)
        line:SetWidth(WIDTH - 12)
        line.Text = line:CreateFontString(nil, "ARTWORK", LINE_FONT)
        line.Text:SetPoint("TOPLEFT")
        line.Text:SetWidth(WIDTH - 12)
        line.Text:SetJustifyH("LEFT")
        line:RegisterForClicks("LeftButtonUp")
        line:SetScript("OnClick", function(self)
            if self.questID then ns:OpenTrackedQuest(self.questID) end
        end)
        line:SetScript("OnEnter", function(self)
            if not self.isTitle then return end
            self.Text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.title or "", 1, 0.82, 0)
            GameTooltip:AddLine("<Click to open it on the dungeon map>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
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

local function SetLine(line, font, text, color, indent)
    line.Text:SetFontObject(font)
    line.Text:SetText(text)
    line.r, line.g, line.b = color[1], color[2], color[3]
    line.Text:SetTextColor(color[1], color[2], color[3])
    line.Text:ClearAllPoints()
    line.Text:SetPoint("TOPLEFT", indent or 0, 0)
    line.Text:SetWidth(WIDTH - 12 - (indent or 0))
    line:SetHeight(line.Text:GetStringHeight() + 2)
end

function ns:UpdateDungeonTracker()
    if not tracker then return end
    local key = ns.CurrentInstanceKey and ns.CurrentInstanceKey()
    local quests = key and ns.db.dungeonTracker and QuestsHere(key) or {}
    if #quests == 0 then
        tracker:Hide()
        return
    end
    tracker:Show()
    tracker.Header.Text:SetText(ns.Instances[key] and ns.Instances[key].name or (QUESTS_LABEL or "Quests"))
    tracker.Content:SetShown(not ns.db.dungeonTrackerCollapsed)
    tracker.Header.Toggle:SetText(ns.db.dungeonTrackerCollapsed and "+" or "-")
    if ns.db.dungeonTrackerCollapsed then
        tracker:SetHeight(tracker.Header:GetHeight())
        return
    end

    local index, y = 0, 0
    local function Add(font, text, color, indent, questID, title, isTitle)
        index = index + 1
        local line = AcquireLine(index)
        SetLine(line, font, text, color, indent)
        line.questID, line.title, line.isTitle = questID, title, isTitle
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
        Add(TITLE_FONT, title, { yellow.r, yellow.g, yellow.b }, 0, q.id, q.title, true)
        if q.ready then
            local g = GREEN_FONT_COLOR
            Add(LINE_FONT, "- " .. READY_TEXT, { g.r, g.g, g.b }, 8, q.id)
        else
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.id) or {}) do
                if o.text and o.text ~= "" then
                    Add(LINE_FONT, "- " .. o.text, o.finished and COMPLETE or OPEN, 8, q.id)
                end
            end
        end
    end
    for i = index + 1, #tracker.Lines do tracker.Lines[i]:Hide() end
    tracker.Content:SetHeight(math.max(y, 1))
    tracker:SetHeight(tracker.Header:GetHeight() + 6 + y)
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

local function SavePosition()
    local point, _, relPoint, x, y = tracker:GetPoint(1)
    ns.db.dungeonTrackerPos = { point, relPoint, x, y }
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
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not InCombatLockdown() then tracker:StartMoving() end end)
    header:SetScript("OnDragStop", function() tracker:StopMovingOrSizing(); SavePosition() end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Dungeon quests", 1, 1, 1)
        GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tracker.Header = header

    tracker.Content = CreateFrame("Frame", nil, tracker)
    tracker.Content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -6)
    tracker.Content:SetSize(WIDTH - 8, 1)
    tracker.Lines = {}
    tracker:Hide()
end

function ns:InitDungeonTracker()
    if tracker then return end
    CreateTracker()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(events.RegisterEvent, events, event)
    end
    local pending = false
    events:SetScript("OnEvent", function()
        -- Quest events come in bursts; draw once.
        if pending then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = false
            ns:UpdateDungeonTracker()
        end)
    end)
end
