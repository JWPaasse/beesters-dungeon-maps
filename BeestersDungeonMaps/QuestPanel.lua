-- Beester's Dungeon Maps: the dungeon's quests, in the quest list of the Map & Quest Log window.
--
-- While a dungeon map is open, a small tab bar sits on top of the quest list:
--   [Quest log] [Ragefire Chasm]
-- The dungeon tab lists that dungeon's quests in four groups:
--   Dungeon quests  - in your quest log: objectives, ready for turn-in, track checkbox
--   Available quests - what you can pick up now (!), chains you've started (step 1/2),
--                      and quests you're too low for (red "Requires level X")
--   Starts inside   - quests that start inside the dungeon (blue)
--   Handed in       - hidden until you click "Show handed in"
-- Clicking a quest that isn't in your log opens a detail pane in the lower third: the quest's
-- text, where it starts, its rewards, and a button that shows the start on the map.
-- Data: QuestieDB's Forever quests (Data/Quests.lua).

local _, ns = ...

local panel        -- content (list + detail pane)
local strip        -- tab bar
local selected     -- questID shown in the detail pane
local showHandedIn = false
local tab = "dungeon"

local ROW_HEIGHT = 16
local LIST_INDENT = 22

----------------------------------------------------------------------
-- Quest state
----------------------------------------------------------------------

local function Q(id) return ns.Quests and ns.Quests[id] end
local F = { NAME = 1, LEVEL = 2, REQ = 3, FACTION = 4, TEXT = 5, START_NPC = 6, START_OBJ = 7, START_ITEM = 8,
    END_NPC = 9, END_OBJ = 10, PRE_ANY = 11, PRE_ALL = 12, ITEMS = 13, REWARDS = 14, CLASSES = 15, REPEATABLE = 16 }

local function IsDone(id)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

local function InLog(id)
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil
end

local function ReadyToTurnIn(id)
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id) then return true end
    return C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
end

local playerFaction, playerClassBit
local function ForPlayer(q)
    if not playerFaction then
        local faction = UnitFactionGroup("player")
        playerFaction = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or "?"
        local _, _, classID = UnitClass("player")
        playerClassBit = classID and 2 ^ (classID - 1) or 0
    end
    if q[F.FACTION] and q[F.FACTION] ~= playerFaction then return false end
    local classes = q[F.CLASSES]
    if type(classes) == "number" and classes > 0 and playerClassBit > 0 then
        if math.floor(classes / playerClassBit) % 2 == 0 then return false end
    end
    return true
end

local function PrereqsDone(q)
    for _, id in ipairs(q[F.PRE_ALL] or {}) do
        if not IsDone(id) then return false end
    end
    local any = q[F.PRE_ANY] or {}
    if #any == 0 then return true end
    for _, id in ipairs(any) do
        if IsDone(id) then return true end
    end
    return false
end

-- Starts inside the dungeon: started by an item, or by someone/something with no outdoor spot.
local function StartsInside(q)
    if #(q[F.START_ITEM] or {}) > 0 then return true end
    local outside = false
    for _, id in ipairs(q[F.START_NPC] or {}) do
        local npc = ns.NPCs and ns.NPCs[id]
        if npc and npc[6] then outside = true end
    end
    for _, id in ipairs(q[F.START_OBJ] or {}) do
        local obj = ns.Objects and ns.Objects[id]
        if obj and obj[2] then outside = true end
    end
    return not outside and (#(q[F.START_NPC] or {}) + #(q[F.START_OBJ] or {})) > 0
end

-- The steps that lead to a quest, first step first (follows the required quests back).
local function Chain(id)
    local steps, seen = {}, {}
    local current = id
    while current and not seen[current] do
        seen[current] = true
        table.insert(steps, 1, current)
        local q = Q(current)
        if not q then break end
        local nextID
        for _, pre in ipairs(q[F.PRE_ALL] or {}) do
            if Q(pre) and ForPlayer(Q(pre)) then nextID = pre break end
        end
        if not nextID then
            for _, pre in ipairs(q[F.PRE_ANY] or {}) do
                if Q(pre) and ForPlayer(Q(pre)) then nextID = pre break end
            end
        end
        current = nextID
    end
    return steps
end

-- Where a quest starts: name, uiMapID, x, y (map spot may be nil when it starts inside).
local function StartInfo(q)
    for _, id in ipairs(q[F.START_NPC] or {}) do
        local npc = ns.NPCs and ns.NPCs[id]
        if npc then
            local where = npc[6]
            return npc[1], where and where[1], where and where[2], where and where[3]
        end
    end
    for _, id in ipairs(q[F.START_OBJ] or {}) do
        local obj = ns.Objects and ns.Objects[id]
        if obj then
            local where = obj[2]
            return obj[1], where and where[1], where and where[2], where and where[3]
        end
    end
    for _, id in ipairs(q[F.START_ITEM] or {}) do
        local item = ns.QuestItems and ns.QuestItems[id]
        if item then return item[1] end
    end
end

----------------------------------------------------------------------
-- Building the list
----------------------------------------------------------------------

local function Classify(key)
    local groups = { log = {}, available = {}, inside = {}, done = {} }
    local seen = {}
    for _, id in ipairs(ns.DungeonQuests and ns.DungeonQuests[key] or {}) do
        local q = Q(id)
        if q and not seen[id] and ForPlayer(q) then
            seen[id] = true
            local entry = { id = id, q = q }
            if IsDone(id) and not q[F.REPEATABLE] then
                table.insert(groups.done, entry)
            elseif InLog(id) then
                entry.ready = ReadyToTurnIn(id)
                table.insert(groups.log, entry)
            elseif StartsInside(q) then
                entry.canTake = PrereqsDone(q)
                table.insert(groups.inside, entry)
            else
                local steps = Chain(id)
                entry.steps = steps
                if #steps > 1 then
                    -- Which step are you on? The first one that isn't handed in.
                    for i, step in ipairs(steps) do
                        if not IsDone(step) then entry.step = i break end
                    end
                    entry.step = entry.step or #steps
                    entry.started = entry.step > 1 or InLog(steps[1])
                    entry.stepInLog = InLog(steps[entry.step])
                end
                local current = Q(steps[entry.step or 1]) or q
                entry.canTake = PrereqsDone(current) and not InLog(steps[entry.step or 1])
                entry.tooLow = (current[F.REQ] or 0) > UnitLevel("player")
                table.insert(groups.available, entry)
            end
        end
    end
    local function byLevel(a, b)
        if (a.q[F.LEVEL] or 0) ~= (b.q[F.LEVEL] or 0) then return (a.q[F.LEVEL] or 0) < (b.q[F.LEVEL] or 0) end
        return a.q[F.NAME] < b.q[F.NAME]
    end
    for _, list in pairs(groups) do table.sort(list, byLevel) end
    return groups
end

ns.ClassifyDungeonQuests = Classify -- used by tools/test_addon.py

----------------------------------------------------------------------
-- Rows (pooled)
----------------------------------------------------------------------

local rows, used = {}, 0

local function DifficultyColor(level)
    if GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level or 1)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

local function AcquireRow()
    used = used + 1
    local row = rows[used]
    if not row then
        row = CreateFrame("Button", nil, panel.Child)
        row:SetHeight(ROW_HEIGHT)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(16, 16)
        row.Icon:SetPoint("LEFT", 2, 0)
        row.Badge = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.Badge:SetPoint("CENTER", row.Icon, "CENTER")
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Text:SetPoint("LEFT", LIST_INDENT, 0)
        row.Text:SetPoint("RIGHT", -24, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetWordWrap(true)
        row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.Highlight:SetPoint("TOPLEFT", row.Text, "TOPLEFT", -2, 1)
        row.Highlight:SetPoint("BOTTOMRIGHT", row.Text, "BOTTOMRIGHT", 2, -1)
        row.Highlight:SetColorTexture(1, 1, 1, 0.08)
        row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Check:SetSize(20, 20)
        row.Check:SetPoint("RIGHT", 0, 0)
        row.Check:SetScript("OnClick", function(self)
            local id = self:GetParent().questID
            if self:GetChecked() then
                if C_QuestLog.AddQuestWatch then C_QuestLog.AddQuestWatch(id) end
            else
                if C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(id) end
            end
        end)
        row:RegisterForClicks("LeftButtonUp")
        rows[used] = row
    end
    row:Show()
    row.Icon:Hide()
    row.Badge:SetText("")
    row.Check:Hide()
    row.Highlight:Hide()
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row.questID = nil
    row.Text:SetFontObject("GameFontNormal")
    row.Text:SetPoint("LEFT", LIST_INDENT, 0)
    return row
end

local function SetIcon(row, atlas)
    if atlas and C_Texture.GetAtlasInfo(atlas) then
        row.Icon:SetAtlas(atlas)
        row.Icon:Show()
    end
end

local function Place(row, y, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 6, -y)
    row:SetPoint("RIGHT", panel.Child, "RIGHT", -4, 0)
    row:SetHeight(height or ROW_HEIGHT)
    return y + (height or ROW_HEIGHT)
end

local function QuestTitle(entry, core)
    local q = entry.q
    local level = q[F.LEVEL] or 0
    local text = ("[%d%s] %s"):format(level, core and "+" or "", q[F.NAME])
    if core then text = text .. " (" .. (LFG_TYPE_DUNGEON or "Dungeon") .. ")" end
    return text
end

local function QuestTooltip(self)
    local q = Q(self.questID)
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(q[F.NAME], 1, 1, 1)
    if q[F.TEXT] then GameTooltip:AddLine(q[F.TEXT], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
    if self.hint then GameTooltip:AddLine(self.hint, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b) end
    GameTooltip:Show()
end

local Refresh -- forward
local ShowDetail

local function AddHeader(y, text, count)
    local row = AcquireRow()
    row.Text:SetFontObject("GameFontHighlightMedium")
    row.Text:SetPoint("LEFT", 4, 0)
    row.Text:SetText(("%s |cff888888(%d)|r"):format(text, count))
    return Place(row, y + 6, 20)
end

local function AddObjectiveLines(y, id, ready)
    local lines = {}
    if ready then
        table.insert(lines, "- " .. (QUEST_WATCH_QUEST_READY or "Ready for turn-in"))
    elseif C_QuestLog.GetQuestObjectives then
        for _, obj in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if obj.text and obj.text ~= "" then table.insert(lines, "- " .. obj.text) end
        end
    end
    for _, line in ipairs(lines) do
        local row = AcquireRow()
        row.Text:SetFontObject("GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", LIST_INDENT + 8, 0)
        row.Text:SetText(line)
        y = Place(row, y, 14)
    end
    return y
end

local function AddQuestRow(y, entry, kind)
    local q = entry.q
    local row = AcquireRow()
    row.questID = entry.id
    row.Highlight:Show()
    row.Text:SetText(QuestTitle(entry, true))
    local r, g, b = DifficultyColor(q[F.LEVEL])
    if kind == "inside" then r, g, b = 0.4, 0.75, 1 end
    if kind == "done" then r, g, b = 0.5, 0.5, 0.5 end
    row.Text:SetTextColor(r, g, b)

    if kind == "log" then
        if entry.ready then SetIcon(row, "QuestTurnin") end
        row.Check:Show()
        local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(entry.id) ~= nil
        row.Check:SetChecked(watched)
        row.hint = "<Click to open the quest>"
        row:SetScript("OnClick", function(self)
            if QuestMapFrame_ShowQuestDetails then QuestMapFrame_ShowQuestDetails(self.questID) end
        end)
    else
        if kind == "available" then
            if entry.steps and #entry.steps > 1 and entry.started then
                row.Badge:SetText(("%d/%d"):format(entry.step, #entry.steps))
            elseif entry.canTake and not entry.tooLow then
                SetIcon(row, "QuestNormal")
            end
        elseif kind == "inside" then
            SetIcon(row, "QuestNormal")
        end
        row.hint = "<Click for details>"
        row:SetScript("OnClick", function(self) ShowDetail(self.questID, entry) end)
    end
    row:SetScript("OnEnter", QuestTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = Place(row, y, ROW_HEIGHT + 2)

    if kind == "log" then
        y = AddObjectiveLines(y, entry.id, entry.ready)
    elseif kind == "available" then
        local line
        if entry.steps and #entry.steps > 1 then
            local stepQuest = Q(entry.steps[entry.step])
            if entry.stepInLog then
                line = ("- Step %d of %d in your log: %s"):format(entry.step, #entry.steps, stepQuest[F.NAME])
            else
                line = ("- Starts with: %s"):format(stepQuest[F.NAME])
            end
        end
        if line then
            local sub = AcquireRow()
            sub.Text:SetFontObject("GameFontHighlightSmall")
            sub.Text:SetPoint("LEFT", LIST_INDENT + 8, 0)
            sub.Text:SetText(line)
            y = Place(sub, y, 14)
        end
        if entry.tooLow then
            local current = Q(entry.steps and entry.steps[entry.step] or entry.id) or q
            local sub = AcquireRow()
            sub.Text:SetFontObject("GameFontHighlightSmall")
            sub.Text:SetPoint("LEFT", LIST_INDENT + 8, 0)
            sub.Text:SetText(("- Requires level %d"):format(current[F.REQ] or 0))
            sub.Text:SetTextColor(1, 0.25, 0.25)
            y = Place(sub, y, 14)
        end
    end
    return y + 2
end

function Refresh()
    if not panel or not panel:IsShown() then return end
    local key = ns:CurrentDungeonKey()
    if not key then return end
    for i = 1, used do rows[i]:Hide() end
    used = 0

    local groups = Classify(key)
    local y = 0
    if #groups.log > 0 then
        y = AddHeader(y, "Dungeon quests", #groups.log)
        for _, e in ipairs(groups.log) do y = AddQuestRow(y, e, "log") end
    end
    if #groups.available > 0 then
        y = AddHeader(y, "Available quests", #groups.available)
        for _, e in ipairs(groups.available) do y = AddQuestRow(y, e, "available") end
    end
    if #groups.inside > 0 then
        y = AddHeader(y, "Starts inside", #groups.inside)
        for _, e in ipairs(groups.inside) do y = AddQuestRow(y, e, "inside") end
    end
    if showHandedIn and #groups.done > 0 then
        y = AddHeader(y, "Handed in", #groups.done)
        for _, e in ipairs(groups.done) do y = AddQuestRow(y, e, "done") end
    end
    if used == 0 then
        local row = AcquireRow()
        row.Text:SetFontObject("GameFontDisable")
        row.Text:SetText(#groups.done > 0 and "You've done every quest here." or "No quests known for this dungeon.")
        y = Place(row, 10, 20)
    end
    panel.Child:SetHeight(math.max(y + 10, 10))
    panel.HandedIn:SetText(showHandedIn and "Hide handed in" or ("Show handed in (%d)"):format(#groups.done))
    panel.HandedIn:SetEnabled(#groups.done > 0)
end

----------------------------------------------------------------------
-- Detail pane (lower third)
----------------------------------------------------------------------

local function Layout()
    if not panel then return end
    local h = panel:GetHeight()
    panel.Scroll:ClearAllPoints()
    panel.Scroll:SetPoint("TOPLEFT", 0, -4)
    if panel.Detail:IsShown() then
        panel.Detail:SetHeight(math.floor(h / 3))
        panel.Scroll:SetPoint("BOTTOMRIGHT", panel.Detail, "TOPRIGHT", -24, 6)
    else
        panel.Scroll:SetPoint("BOTTOMRIGHT", -24, 30)
    end
    panel.Child:SetWidth(math.max(panel.Scroll:GetWidth(), 50))
end

function ShowDetail(id, entry)
    local q = Q(id)
    if not q then return end
    selected = id
    local d = panel.Detail
    -- For a chain, show the step you're on.
    local stepID = entry and entry.steps and entry.steps[entry.step or 1] or id
    local step = Q(stepID) or q
    d.Title:SetText(step[F.NAME])
    local r, g, b = DifficultyColor(step[F.LEVEL])
    d.Title:SetTextColor(r, g, b)

    local lines = {}
    local levelLine = ("Level %d"):format(step[F.LEVEL] or 0)
    if (step[F.REQ] or 0) > UnitLevel("player") then
        levelLine = levelLine .. (" · |cffff4040Requires level %d|r"):format(step[F.REQ])
    elseif step[F.REQ] then
        levelLine = levelLine .. (" · requires level %d"):format(step[F.REQ])
    end
    table.insert(lines, levelLine)
    if stepID ~= id then
        table.insert(lines, ("Step %d of %d toward |cffffd100%s|r"):format(entry.step or 1, #entry.steps, q[F.NAME]))
    end
    local who, mapID, x, y = StartInfo(step)
    if who then
        local zone = mapID and C_Map.GetMapInfo(mapID)
        if zone then
            table.insert(lines, ("Starts at: |cffffffff%s|r, %s"):format(who, zone.name))
        else
            table.insert(lines, ("Starts with: |cffffffff%s|r (inside the dungeon)"):format(who))
        end
    end
    if step[F.TEXT] then table.insert(lines, "|cffffffff" .. step[F.TEXT] .. "|r") end
    d.Text:SetText(table.concat(lines, "\n"))

    -- Rewards: the dungeon quest's own rewards.
    local rewards = q[F.REWARDS] or {}
    for i, button in ipairs(d.Rewards) do
        local itemID = rewards[i]
        if itemID then
            button.itemID = itemID
            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or (GetItemIcon and GetItemIcon(itemID))
            button.Icon:SetTexture(icon or 134400)
            button:Show()
        else
            button:Hide()
        end
    end
    d.RewardsLabel:SetShown(#rewards > 0)

    d.MapButton.target = mapID and { mapID = mapID, x = x, y = y, title = step[F.NAME], who = who } or nil
    d.MapButton:SetEnabled(d.MapButton.target ~= nil)
    d:Show()
    Layout()
end

local function CreateDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetPoint("BOTTOMLEFT", 0, 26)
    d:SetPoint("BOTTOMRIGHT", 0, 26)
    d:Hide()
    local line = d:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 4, 0)
    line:SetPoint("TOPRIGHT", -4, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.6, 0.5, 0.3, 0.6)
    d.Title = d:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    d.Title:SetPoint("TOPLEFT", 8, -8)
    d.Title:SetPoint("RIGHT", -28, 0)
    d.Title:SetJustifyH("LEFT")
    d.Close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.Close:SetPoint("TOPRIGHT", 0, 0)
    d.Close:SetScript("OnClick", function() d:Hide(); selected = nil; Layout() end)
    d.Text = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    d.Text:SetPoint("TOPLEFT", d.Title, "BOTTOMLEFT", 0, -6)
    d.Text:SetPoint("RIGHT", -8, 0)
    d.Text:SetJustifyH("LEFT")
    d.Text:SetJustifyV("TOP")
    d.Text:SetSpacing(2)
    d.RewardsLabel = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    d.RewardsLabel:SetPoint("BOTTOMLEFT", 8, 30)
    d.RewardsLabel:SetText(REWARDS or "Rewards")
    d.Rewards = {}
    for i = 1, 6 do
        local b = CreateFrame("Button", nil, d)
        b:SetSize(24, 24)
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 28, 4)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(self.itemID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        d.Rewards[i] = b
    end
    d.MapButton = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.MapButton:SetSize(110, 22)
    d.MapButton:SetPoint("BOTTOMRIGHT", -6, 4)
    d.MapButton:SetText("Show on map")
    d.MapButton:SetScript("OnClick", function(self)
        local t = self.target
        if t then ns:ShowQuestMarker(t.mapID, t.x, t.y, t.title, t.who) end
    end)
    return d
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

local function SetTab(which)
    tab = which
    if strip then
        strip.Log.Selected:SetShown(which == "log")
        strip.Dungeon.Selected:SetShown(which == "dungeon")
        strip.Log:SetNormalFontObject(which == "log" and "GameFontHighlight" or "GameFontNormal")
        strip.Dungeon:SetNormalFontObject(which == "dungeon" and "GameFontHighlight" or "GameFontNormal")
    end
    if panel then
        panel:SetShown(which == "dungeon")
        if which == "dungeon" then Layout(); Refresh() end
    end
end

-- The button gets its own font string: a button whose text is still empty has none yet.
local function SetTabText(b, text)
    b.Label:SetText(text)
    b:SetWidth(math.max(40, b.Label:GetStringWidth() + 20))
end

local function CreateTabButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.Label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.Label:SetPoint("CENTER", 0, 1)
    b:SetFontString(b.Label)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    SetTabText(b, text)
    b.Selected = b:CreateTexture(nil, "ARTWORK")
    b.Selected:SetPoint("BOTTOMLEFT", 6, 1)
    b.Selected:SetPoint("BOTTOMRIGHT", -6, 1)
    b.Selected:SetHeight(2)
    b.Selected:SetColorTexture(1, 0.82, 0, 0.9)
    return b
end

local function CreateFrames()
    local list = QuestScrollFrame
    local host = (QuestMapFrame and QuestMapFrame.QuestsFrame) or (list and list:GetParent())
    if not (host and list) then return false end

    strip = CreateFrame("Frame", "BeestersDungeonMapsQuestTabs", host)
    strip:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, 0)
    strip:SetHeight(24)
    strip:SetFrameLevel(list:GetFrameLevel() + 30)
    strip:EnableMouse(true)
    local stripBg = strip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints()
    stripBg:SetColorTexture(0.06, 0.05, 0.03, 1)
    strip.Log = CreateTabButton(strip, QUEST_LOG or "Quest log")
    strip.Log:SetPoint("LEFT", 4, 0)
    strip.Log:SetScript("OnClick", function() SetTab("log") end)
    strip.Dungeon = CreateTabButton(strip, "")
    strip.Dungeon:SetPoint("LEFT", strip.Log, "RIGHT", 4, 0)
    strip.Dungeon:SetScript("OnClick", function() SetTab("dungeon") end)
    strip:Hide()

    panel = CreateFrame("Frame", "BeestersDungeonMapsQuests", host)
    panel:SetAllPoints(list)
    panel:SetFrameLevel(list:GetFrameLevel() + 20)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local source = type(list.Background) == "table" and list.Background or nil
    if source and source.GetAtlas and source:GetAtlas() then
        bg:SetAtlas(source:GetAtlas())
    elseif source and source.GetTexture and source:GetTexture() then
        bg:SetTexture(source:GetTexture())
    else
        bg:SetColorTexture(0.08, 0.06, 0.04, 0.97)
    end

    local ok, scroll = pcall(CreateFrame, "ScrollFrame", "BeestersDungeonMapsQuestScroll", panel, "UIPanelScrollFrameTemplate")
    if not ok then scroll = CreateFrame("ScrollFrame", nil, panel) end
    panel.Scroll = scroll
    panel.Child = CreateFrame("Frame", nil, scroll)
    panel.Child:SetSize(200, 10)
    scroll:SetScrollChild(panel.Child)

    panel.HandedIn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.HandedIn:SetSize(170, 22)
    panel.HandedIn:SetPoint("BOTTOMLEFT", 6, 4)
    panel.HandedIn:SetScript("OnClick", function()
        showHandedIn = not showHandedIn
        Refresh()
    end)

    panel.Detail = CreateDetail(panel)
    panel:SetScript("OnSizeChanged", function() Layout(); Refresh() end)
    panel:Hide()
    return true
end

----------------------------------------------------------------------
-- Public: shown together with the dungeon map
----------------------------------------------------------------------

function ns:ShowDungeonQuests(key)
    if not ns.db.questPanel then return end
    if not panel and not CreateFrames() then return end
    SetTabText(strip.Dungeon, ns.Instances[key] and ns.Instances[key].name or key)
    strip:Show()
    panel.Detail:Hide()
    selected = nil
    SetTab("dungeon")
end

function ns:HideDungeonQuests()
    if strip then strip:Hide() end
    if panel then panel:Hide() end
end

function ns:InitQuestPanel()
    if not ns.Quests then return end
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
        "PLAYER_LEVEL_UP", "QUEST_WATCH_LIST_CHANGED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    local pending = false
    events:SetScript("OnEvent", function()
        if pending or not (panel and panel:IsShown()) then return end
        pending = true
        C_Timer.After(0.2, function() pending = false; Refresh() end)
    end)
    ns.questPanelActive = true
end
