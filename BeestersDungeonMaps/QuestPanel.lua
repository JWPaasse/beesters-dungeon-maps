-- Beester's Dungeon Maps: the dungeon's quests, in the quest list of the Map & Quest Log window.
--
-- While a dungeon map is open, a small tab bar sits on top of the quest list:
--   [Quest log] [Ragefire Chasm]
-- The dungeon tab lists that dungeon's quests in four groups:
--   Dungeon quests  - in your quest log: objectives, ready for turn-in, track checkbox
--   Available quests - what you can pick up now (!), chains you've started (step 1/2),
--                      and quests you're too low for (red "Requires level X")
--   Starts inside   - quests that start inside the dungeon (blue)
--   Handed in       - folded away, like a collapsed zone in the quest log
-- The rows are the quest log's own templates, so they look and behave like the normal list.
-- Clicking a quest that isn't in your log opens a detail pane in the lower third: the quest's
-- text, where it starts, its rewards, and a button that shows the start on the map.
-- Data: QuestieDB's Forever quests (Data/Quests.lua).

local _, ns = ...

local panel        -- content (list + detail pane)
local strip        -- tab bar
local selected     -- questID shown in the detail pane
local tab = "dungeon"


----------------------------------------------------------------------
-- Quest state
----------------------------------------------------------------------

local function Q(id) return ns.Quests and ns.Quests[id] end
local F = { NAME = 1, LEVEL = 2, REQ = 3, FACTION = 4, TEXT = 5, START_NPC = 6, START_OBJ = 7, START_ITEM = 8,
    END_NPC = 9, END_OBJ = 10, PRE_ANY = 11, PRE_ALL = 12, ITEMS = 13, REWARDS = 14, CLASSES = 15, REPEATABLE = 16,
    KILLS = 18 }

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

-- Where a quest is handed in: name, uiMapID, x, y.
local function TurnInInfo(q)
    for _, id in ipairs(q[F.END_NPC] or {}) do
        local npc = ns.NPCs and ns.NPCs[id]
        if npc then
            local where = npc[6]
            return npc[1], where and where[1], where and where[2], where and where[3]
        end
    end
    for _, id in ipairs(q[F.END_OBJ] or {}) do
        local obj = ns.Objects and ns.Objects[id]
        if obj then
            local where = obj[2]
            return obj[1], where and where[1], where and where[2], where and where[3]
        end
    end
end

-- Show a quest step on its zone map: where to hand it in when it's in your log,
-- otherwise where to pick it up.
local function ShowStepOnMap(stepID)
    local q = Q(stepID)
    if not q then return end
    local who, mapID, x, y
    local verb
    if InLog(stepID) then
        who, mapID, x, y = TurnInInfo(q)
        verb = "Hand in"
    else
        who, mapID, x, y = StartInfo(q)
        verb = "Pick up"
    end
    if mapID then
        ns:ShowQuestMarker(mapID, x, y, q[F.NAME], ("%s: %s"):format(verb, who or "?"))
    else
        ns:Print(("%s: %s – no map spot known (it may be inside a dungeon)."):format(q[F.NAME], who or "?"))
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
                -- A chain you've started counts as one of your dungeon quests.
                if entry.started or entry.stepInLog then
                    entry.chain = true
                    table.insert(groups.log, entry)
                else
                    table.insert(groups.available, entry)
                end
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
-- Rows, built from the game's own quest log templates so they look the same:
-- QuestLogHeaderTemplate (group bars), QuestLogTitleTemplate (quest titles with the
-- track checkbox), QuestLogObjectiveTemplate (objective lines) and POIButtonTemplate
-- (the round icons). Each falls back to a plain frame if a template is missing.
----------------------------------------------------------------------

local pools = { header = {}, title = {}, objective = {}, step = {} }
local usedCount = { header = 0, title = 0, objective = 0, step = 0 }
local chainOpen = {} -- [questID] = true/false; started chains start open
local collapsed = { done = true } -- "Handed in" starts folded, like the game's collapsed zones

local function DifficultyColor(level)
    if GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level or 1)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

-- A template child (parentKey) such as frame.Text; nil when the template doesn't have it.
local function Part(frame, key)
    local v = rawget(frame, key)
    if type(v) == "table" then return v end
    return false
end

local function TryTemplate(kind, template)
    local ok, frame = pcall(CreateFrame, kind == "objective" and "Frame" or "Button", nil, panel.Child, template)
    if ok and frame then return frame, true end
    return CreateFrame(kind == "objective" and "Frame" or "Button", nil, panel.Child), false
end

local function NewHeader()
    local h, native = TryTemplate("header", "QuestLogHeaderTemplate")
    h.Label = Part(h, "ButtonText")
    h.Collapse = Part(h, "CollapseButton")
    if not native or not h.Label then
        h:SetHeight(22)
        h.Label = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
        h.Label:SetPoint("LEFT", 8, 0)
    end
    -- The header's own scripts stay (hover highlight); only what a click does is ours.
    local function Toggle(self)
        collapsed[self.group] = not collapsed[self.group]
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        panel.Refresh()
    end
    if native and h.SetClickHandler then
        h:SetClickHandler(function(self, button) if button == "LeftButton" then Toggle(self) end end)
    else
        h:SetScript("OnClick", Toggle)
    end
    return h
end

local function SetHeaderCollapsed(h, isCollapsed)
    if ListHeaderMixin and ListHeaderMixin.UpdateCollapsedState and h.GetCollapseButton then
        pcall(ListHeaderMixin.UpdateCollapsedState, h, isCollapsed)
    end
end

local function NewTitle()
    local t, native = TryTemplate("title", "QuestLogTitleTemplate")
    t.Label = Part(t, "Text")
    t.Box = Part(t, "Checkbox")
    if not native or not t.Label then
        t:SetHeight(16)
        t.Label = t:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(t.Label)
        hl:SetColorTexture(1, 1, 1, 0.08)
    end
    -- The template's glow is switched by its own hover script; ours does the same.
    t.Glow = Part(t, "HighlightTexture")
    if t.Glow then t.Glow:Hide() end
    for _, key in ipairs({ "TagTexture", "TagText", "TaskIcon", "StorylineTexture" }) do
        local part = Part(t, key)
        if part then part:Hide() end
    end
    t:SetScript("OnMouseDown", nil)
    t:SetScript("OnMouseUp", nil)
    -- Round quest icon, like the quest log's.
    t.POI = false
    local ok, poi = pcall(CreateFrame, "Button", nil, t, "POIButtonTemplate")
    if ok and poi and poi.SetQuestID then
        t.POI = poi
        poi:SetPoint("TOPLEFT", t, "TOPLEFT", 4, 3)
        poi:EnableMouse(false)
    end
    -- Our own icon for quests that aren't in your log yet ("!" on the same round button).
    t.Bang = t:CreateTexture(nil, "OVERLAY")
    t.Bang:SetSize(24, 24)
    t.Bang:SetPoint("TOPLEFT", t, "TOPLEFT", 4, 3)
    t.BangMark = t:CreateTexture(nil, "OVERLAY", nil, 2)
    t.BangMark:SetSize(13, 13)
    t.BangMark:SetPoint("CENTER", t.Bang, "CENTER")
    t.Badge = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.Badge:SetPoint("CENTER", t.Bang, "CENTER", 0, 0)
    -- Track checkbox: the template's own box when it has one.
    if not t.Box then
        t.Box = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
        t.Box:SetSize(20, 20)
        t.Box:SetPoint("TOPRIGHT", -2, 2)
    end
    t.Box:EnableMouse(true)
    if t.Box:HasScript("OnClick") then t.Box:SetScript("OnClick", nil) end
    t.Box:SetScript("OnMouseDown", function(self)
        local id = self:GetParent().questID
        if not id then return end
        if C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil then
            if C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(id) end
        else
            if C_QuestLog.AddQuestWatch then C_QuestLog.AddQuestWatch(id) end
        end
        C_Timer.After(0.1, panel.Refresh)
    end)
    return t
end

local function SetTracked(t, tracked)
    local box = t.Box
    if box.SetChecked then
        box:SetChecked(tracked)
    elseif Part(box, "CheckMark") then
        box.CheckMark:SetShown(tracked)
    end
end

local function NewObjective()
    local o, native = TryTemplate("objective", "QuestLogObjectiveTemplate")
    o.Label, o.DashText = Part(o, "Text"), Part(o, "Dash")
    if not native or not o.Label or not o.DashText then
        o:SetHeight(16)
        o.Label = o:CreateFontString(nil, "ARTWORK", "ObjectiveFont")
        o.Label:SetPoint("TOPLEFT", 12, 0)
        o.DashText = o:CreateFontString(nil, "ARTWORK", "ObjectiveFont")
        o.DashText:SetPoint("TOPLEFT")
    end
    return o
end

-- Chain trail lines: a small icon and gold text, clearly apart from the white objectives.
local function NewStep()
    local st = CreateFrame("Button", nil, panel.Child)
    st:SetHeight(16)
    st.Icon = st:CreateTexture(nil, "ARTWORK")
    st.Icon:SetSize(14, 14)
    st.Icon:SetPoint("TOPLEFT", 0, 0)
    st.Label = st:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    st.Label:SetPoint("TOPLEFT", st.Icon, "TOPRIGHT", 4, -1)
    st.Label:SetJustifyH("LEFT")
    st.Line = st:CreateTexture(nil, "BACKGROUND")
    st.Line:SetWidth(1)
    st.Line:SetColorTexture(0.8, 0.65, 0.3, 0.5)
    st.Line:SetPoint("TOP", st.Icon, "BOTTOM", 0, 0)
    st.Line:SetPoint("BOTTOM", st, "BOTTOM", 0, -2)
    local hl = st:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", st.Label, "TOPLEFT", -2, 1)
    hl:SetPoint("BOTTOMRIGHT", st.Label, "BOTTOMRIGHT", 2, -1)
    hl:SetColorTexture(1, 1, 1, 0.08)
    return st
end

local function Acquire(kind)
    usedCount[kind] = usedCount[kind] + 1
    local frame = pools[kind][usedCount[kind]]
    if not frame then
        frame = (kind == "header" and NewHeader()) or (kind == "title" and NewTitle())
            or (kind == "step" and NewStep()) or NewObjective()
        pools[kind][usedCount[kind]] = frame
    end
    frame:Show()
    return frame
end

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for i = 1, #list do list[i]:Hide() end
        usedCount[kind] = 0
    end
end

local function ListWidth()
    return math.max(panel.Child:GetWidth(), 150)
end

local function QuestTitle(entry)
    local q = entry.q
    return ("[%d+] %s (%s)"):format(q[F.LEVEL] or 0, q[F.NAME], LFG_TYPE_DUNGEON or "Dungeon")
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

-- Objectives of a quest that isn't in your log yet, the way the log would show them:
-- "0/12 Magenta Fungus Cap". QuestieDB has what to collect or kill; the number comes from
-- the quest text ("Bring 12 Magenta Fungus Caps"), when it says one.
local function CountFor(text, name)
    if not text or not name then return nil end
    local stem = name:lower():sub(1, 5):gsub("%p", "%%%0")
    return text:lower():match("(%d+)%s+" .. stem)
end

local function DataObjectives(q, id)
    local lines = {}
    -- Exact goals and counts from the Classic database when it has the quest.
    local text = ns.QuestText and id and ns.QuestText[id]
    if text and text[6] and #text[6] > 0 then
        for _, goal in ipairs(text[6]) do
            local goalID, count, isItem = goal[1], goal[2], goal[3]
            local name
            if isItem then
                local item = ns.QuestItems and ns.QuestItems[goalID]
                name = (item and item[1]) or ((C_Item and C_Item.GetItemInfo or GetItemInfo)(goalID))
            else
                local npc = ns.NPCs and ns.NPCs[goalID]
                name = npc and (npc[1] .. " slain")
            end
            if name then table.insert(lines, ("0/%d %s"):format(count or 1, name)) end
        end
        if #lines > 0 then return lines end
    end
    for _, itemID in ipairs(q[F.ITEMS] or {}) do
        local item = ns.QuestItems and ns.QuestItems[itemID]
        if item then
            local n = CountFor(q[F.TEXT], item[1])
            table.insert(lines, n and ("0/%s %s"):format(n, item[1]) or item[1])
        end
    end
    for _, npcID in ipairs(q[F.KILLS] or {}) do
        local npc = ns.NPCs and ns.NPCs[npcID]
        if npc then
            local n = CountFor(q[F.TEXT], npc[1])
            table.insert(lines, n and ("0/%s %s slain"):format(n, npc[1]) or (npc[1] .. " slain"))
        end
    end
    if #lines == 0 and q[F.TEXT] then table.insert(lines, q[F.TEXT]) end
    return lines
end

local Refresh -- forward
local ShowDetail

local function AddHeader(y, group, text, count)
    local h = Acquire("header")
    h.group = group
    h.Label:SetText(("%s (%d)"):format(text, count))
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 1, -y)
    h:SetWidth(ListWidth() - 2)
    SetHeaderCollapsed(h, collapsed[group])
    return y + h:GetHeight() + 4
end

local function AddObjective(y, text, r, g, b)
    local o = Acquire("objective")
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 32, -y)
    o:SetWidth(ListWidth() - 50)
    o.DashText:SetText("-")
    o.Label:SetText(text)
    o.Label:SetWidth(ListWidth() - 64)
    if r then o.Label:SetTextColor(r, g, b) else o.Label:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b) end
    local height = math.max(o.Label:GetStringHeight() or 12, 12) + 2
    o:SetHeight(height)
    return y + height
end

local function SetStepIcon(st, state)
    st.Icon:SetTexCoord(0, 1, 0, 1)
    if state == "done" then
        st.Icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    elseif state == "current" then
        st.Icon:SetAtlas("QuestNormal")
    elseif state == "open" or state == "closed" then
        st.Icon:SetAtlas(state == "open" and "Options_ListExpand_Right_Expanded" or "Options_ListExpand_Right")
    else
        st.Icon:SetTexture("Interface\\Buttons\\UI-RadioButton")
        st.Icon:SetTexCoord(0, 0.25, 0, 1)
    end
end

local function AddStepLine(y, indent, text, state, r, g, b, onClick, last, hint)
    local st = Acquire("step")
    st:ClearAllPoints()
    st:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", indent, -y)
    st:SetWidth(ListWidth() - indent - 20)
    st.Label:SetWidth(ListWidth() - indent - 40)
    st.Label:SetText(text)
    st.Label:SetTextColor(r or NORMAL_FONT_COLOR.r, g or NORMAL_FONT_COLOR.g, b or NORMAL_FONT_COLOR.b)
    SetStepIcon(st, state)
    st.Line:SetShown(not last and state ~= "open" and state ~= "closed")
    st:SetScript("OnClick", onClick)
    st.hint = hint
    st:SetScript("OnEnter", hint and function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.hint, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        GameTooltip:Show()
    end or nil)
    st:SetScript("OnLeave", hint and function() GameTooltip:Hide() end or nil)
    local height = math.max(st.Label:GetStringHeight() or 12, 12) + 4
    st:SetHeight(height)
    return y + height
end

-- The chain as a trail of steps you can fold open: done steps ticked off, the step you're on
-- with its progress (or where it starts), and the steps still to come.
local function AddChain(y, entry)
    local steps = entry.steps
    local open = chainOpen[entry.id]
    if open == nil then open = entry.chain and true or false end
    y = AddStepLine(y, 30, ("Quest chain · step %d of %d"):format(entry.step or 1, #steps),
        open and "open" or "closed", nil, nil, nil, function()
            chainOpen[entry.id] = not open
            panel.Refresh()
        end, true)
    if not open then return y end
    for i, stepID in ipairs(steps) do
        local sq = Q(stepID)
        if sq then
            local last = i == #steps
            local name = ("%d. %s"):format(i, sq[F.NAME])
            local showMap = function() ShowStepOnMap(stepID) end
            if i < (entry.step or 1) then
                y = AddStepLine(y, 40, name, "done", 0.55, 0.55, 0.55, showMap, last, "<Click to show where it was picked up>")
            elseif i == (entry.step or 1) then
                local where
                if InLog(stepID) then
                    where = " – in your log"
                else
                    local who, mapID = StartInfo(sq)
                    local zone = mapID and C_Map.GetMapInfo(mapID)
                    if who then where = (" – %s%s"):format(who, zone and (", " .. zone.name) or "") end
                end
                y = AddStepLine(y, 40, name .. (where or ""), "current", 1, 1, 1, showMap, last,
                    InLog(stepID) and "<Click to show where to hand it in>" or "<Click to show where to pick it up>")
                -- The step's progress, right under it.
                if InLog(stepID) and C_QuestLog.GetQuestObjectives then
                    for _, obj in ipairs(C_QuestLog.GetQuestObjectives(stepID) or {}) do
                        if obj.text and obj.text ~= "" then
                            local o = Acquire("objective")
                            o:ClearAllPoints()
                            o:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 58, -y)
                            o:SetWidth(ListWidth() - 76)
                            o.DashText:SetText("-")
                            o.Label:SetWidth(ListWidth() - 90)
                            o.Label:SetText(obj.text)
                            local c = obj.finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR
                            o.Label:SetTextColor(c.r, c.g, c.b)
                            local h = math.max(o.Label:GetStringHeight() or 12, 12) + 2
                            o:SetHeight(h)
                            y = y + h
                        end
                    end
                end
            else
                y = AddStepLine(y, 40, name, "todo", 0.6, 0.6, 0.6, showMap, last, "<Click to show where to pick it up>")
            end
        end
    end
    return y
end

local function AddQuestRow(y, entry, kind)
    local q = entry.q
    local t = Acquire("title")
    t.questID = entry.id
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 0, -y)
    t:SetWidth(ListWidth())
    t.Label:ClearAllPoints()
    t.Label:SetPoint("TOPLEFT", t, "TOPLEFT", 31, -1)
    t.Label:SetWidth(ListWidth() - 60)
    t.Label:SetText(QuestTitle(entry))
    local r, g, b = DifficultyColor(q[F.LEVEL])
    if kind == "inside" then r, g, b = 0.4, 0.75, 1 end
    if kind == "done" then r, g, b = 0.6, 0.6, 0.6 end
    t.Label:SetTextColor(r, g, b)
    t.r, t.g, t.b = r, g, b

    -- Icon: the game's round quest button for quests in your log; "!" for ones you can pick up.
    if t.POI then t.POI:Hide() end
    t.Bang:Hide(); t.BangMark:Hide(); t.Badge:SetText("")
    if kind == "log" and entry.chain then
        t.Bang:SetAtlas("UI-QuestPoi-QuestNumber")
        t.Bang:Show()
        t.Badge:SetText(("%d/%d"):format(entry.step or 1, #entry.steps))
    elseif kind == "log" and t.POI then
        t.POI:SetQuestID(entry.id)
        if t.POI.SetStyle and POIButtonUtil then
            t.POI:SetStyle(entry.ready and POIButtonUtil.Style.QuestComplete or POIButtonUtil.Style.QuestInProgress)
        end
        if t.POI.UpdateButtonStyle then pcall(t.POI.UpdateButtonStyle, t.POI) end
        t.POI:Show()
    elseif kind == "available" or kind == "inside" then
        local started = entry.steps and #entry.steps > 1 and entry.started
        if started or (entry.canTake and not entry.tooLow) or kind == "inside" then
            t.Bang:SetAtlas("UI-QuestPoi-QuestNumber")
            t.Bang:Show()
            if started then
                t.Badge:SetText(("%d/%d"):format(entry.step, #entry.steps))
            else
                t.BangMark:SetAtlas("QuestNormal")
                t.BangMark:Show()
            end
        end
    end

    local inLog = kind == "log" and not entry.chain
    t.Box:SetShown(inLog)
    if inLog then
        SetTracked(t, C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(entry.id) ~= nil)
        t.hint = "<Click to open the quest>"
        t:SetScript("OnClick", function(self)
            if QuestMapFrame_ShowQuestDetails then QuestMapFrame_ShowQuestDetails(self.questID) end
        end)
    else
        t.hint = "<Click for details>"
        t:SetScript("OnClick", function(self) ShowDetail(self.questID, entry) end)
    end
    if t.Glow then t.Glow:Hide() end
    t:SetScript("OnEnter", function(self)
        self.Label:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        if self.Glow then self.Glow:Show() end
        QuestTooltip(self)
    end)
    t:SetScript("OnLeave", function(self)
        self.Label:SetTextColor(self.r, self.g, self.b)
        if self.Glow then self.Glow:Hide() end
        GameTooltip:Hide()
    end)
    local height = math.max(t.Label:GetStringHeight() or 14, 14) + 4
    t:SetHeight(height)
    y = y + height

    if entry.steps and #entry.steps > 1 and kind ~= "done" then
        y = AddChain(y, entry)
    elseif kind == "log" then
        if entry.ready then
            y = AddObjective(y, QUEST_WATCH_QUEST_READY or "Ready for turn-in")
        elseif C_QuestLog.GetQuestObjectives then
            for _, obj in ipairs(C_QuestLog.GetQuestObjectives(entry.id) or {}) do
                if obj.text and obj.text ~= "" then
                    local c = obj.finished and GRAY_FONT_COLOR
                    y = AddObjective(y, obj.text, c and c.r, c and c.g, c and c.b)
                end
            end
        end
    else
        -- Not in your log: what the quest asks, so every quest reads like one in the log.
        for _, line in ipairs(DataObjectives(entry.q, entry.id)) do
            y = AddObjective(y, line, kind == "done" and 0.5 or nil, kind == "done" and 0.5 or nil, kind == "done" and 0.5 or nil)
        end
    end
    if kind == "available" and entry.tooLow then
        local current = Q(entry.steps and entry.steps[entry.step] or entry.id) or q
        y = AddObjective(y, ("Requires level %d"):format(current[F.REQ] or 0), 1, 0.25, 0.25)
    end
    return y + 8
end

local GROUPS = {
    { key = "log", title = "Dungeon quests" },
    { key = "available", title = "Available quests" },
    { key = "inside", title = "Starts inside" },
    { key = "done", title = "Handed in" },
}

function Refresh()
    if not panel or not panel:IsShown() then return end
    local key = ns:CurrentDungeonKey()
    if not key then return end
    ReleaseAll()

    local groups = Classify(key)
    local y, any = 4, false
    for _, group in ipairs(GROUPS) do
        local list = groups[group.key]
        if #list > 0 then
            any = true
            y = AddHeader(y, group.key, group.title, #list)
            if not collapsed[group.key] then
                for _, e in ipairs(list) do y = AddQuestRow(y, e, group.key) end
            end
        end
    end
    if not any then
        y = AddObjective(10, "No quests known for this dungeon.", 0.6, 0.6, 0.6)
    end
    panel.Child:SetHeight(math.max(y + 10, 10))
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
        panel.Detail:SetHeight(math.floor(h * 0.55))
        panel.Scroll:SetPoint("BOTTOMRIGHT", panel.Detail, "TOPRIGHT", -24, 6)
    else
        panel.Scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    end
    panel.Child:SetWidth(math.max(panel.Scroll:GetWidth(), 50))
    local d = panel.Detail
    if d and d.Page then d.Page:SetWidth(math.max(d.Scroll:GetWidth(), 50)) end
end

----------------------------------------------------------------------
-- Detail page: laid out like the game's quest details (title, objectives, description,
-- rewards), on the same parchment, scrolling when it's long.
----------------------------------------------------------------------

local INK = { 0.18, 0.12, 0.06 }

-- Quest text placeholders: $N name, $C class, $R race, $B new line, $Gmale:female;
local function FillText(text)
    if not text then return "" end
    local name = UnitName("player") or ""
    local class = UnitClass("player") or ""
    local race = UnitRace and UnitRace("player") or ""
    local female = UnitSex and UnitSex("player") == 3
    text = text:gsub("%$[Gg]%s*([^:;]*):([^;]*);", function(male, fem) return female and fem or male end)
    text = text:gsub("%$[Nn]", name):gsub("%$[Cc]", class:lower()):gsub("%$[Rr]", race)
    text = text:gsub("%$[Bb]", "\n")
    return text
end

local function MoneyText(copper)
    if GetMoneyString then return GetMoneyString(copper, true) end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return (g > 0 and (g .. "g ") or "") .. (s > 0 and (s .. "s ") or "") .. (c > 0 and (c .. "c") or "")
end

local function PageText(d, font, text, y, gap)
    d.textCount = d.textCount + 1
    local fs = d.texts[d.textCount]
    if not fs then
        fs = d.Page:CreateFontString(nil, "ARTWORK", font)
        fs:SetJustifyH("LEFT")
        d.texts[d.textCount] = fs
    end
    fs:SetFontObject(font)
    fs:SetTextColor(INK[1], INK[2], INK[3])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", d.Page, "TOPLEFT", 10, -y)
    fs:SetWidth(d.Page:GetWidth() - 20)
    fs:SetText(text)
    fs:Show()
    return y + fs:GetStringHeight() + (gap or 8)
end

local function RewardButton(d, itemID, count, x, y)
    d.buttonCount = d.buttonCount + 1
    local b = d.buttons[d.buttonCount]
    if not b then
        local ok, made = pcall(CreateFrame, "Button", nil, d.Page, "LargeItemButtonTemplate")
        b = ok and made or CreateFrame("Button", nil, d.Page)
        if not ok then
            b:SetSize(147, 41)
            b.Icon = b:CreateTexture(nil, "ARTWORK")
            b.Icon:SetSize(36, 36)
            b.Icon:SetPoint("LEFT")
            b.Name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            b.Name:SetPoint("LEFT", b.Icon, "RIGHT", 6, 0)
            b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            b.Count:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", -2, 2)
        end
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
        d.buttons[d.buttonCount] = b
    end
    b.itemID, b.count = itemID, count
    d.FillReward(b)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", d.Page, "TOPLEFT", x, -y)
    b:Show()
end

-- Name, colour and border of a reward; called again when the item's data arrives.
local function FillReward(b)
    local itemID = b.itemID
    local name, _, quality, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    b.waiting = not name
    if type(b.Icon) == "table" then b.Icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400) end
    if type(b.Name) == "table" then
        b.Name:SetText(name or (SEARCH_LOADING_TEXT or "Loading..."))
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then b.Name:SetTextColor(color.r, color.g, color.b) else b.Name:SetTextColor(1, 1, 1) end
    end
    if type(b.Count) == "table" then
        b.Count:SetText(b.count and b.count > 1 and b.count or "")
        b.Count:SetShown(b.count and b.count > 1)
    end
    if quality and type(b.IconBorder) == "table" and SetItemButtonQuality then pcall(SetItemButtonQuality, b, quality, itemID) end
end

-- Rewards two per row, like the quest details; the buttons are scaled to fit.
local REWARD_W, REWARD_H = 147, 41
local function RewardGrid(d, items, y)
    local width = d.Page:GetWidth() - 20
    local scale = math.min(1, (width / 2 - 4) / REWARD_W)
    local cellW, cellH = REWARD_W * scale + 4, REWARD_H * scale + 4
    for i, pair in ipairs(items) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        RewardButton(d, pair[1], pair[2], 0, 0)
        local b = d.buttons[d.buttonCount]
        b:SetScale(scale)
        b:ClearAllPoints()
        -- Offsets are in the button's own (scaled) units.
        b:SetPoint("TOPLEFT", d.Page, "TOPLEFT", (10 + col * cellW) / scale, -(y + row * cellH) / scale)
    end
    return y + math.ceil(#items / 2) * cellH + 6
end

function ShowDetail(id, entry)
    local q = Q(id)
    if not q then return end
    selected = id
    local d = panel.Detail
    d:Show()
    Layout()
    -- For a chain, show the step you're on.
    local stepID = entry and entry.steps and entry.steps[entry.step or 1] or id
    local step = Q(stepID) or q
    local text = ns.QuestText and ns.QuestText[stepID]
    d.textCount, d.buttonCount = 0, 0
    for _, fs in ipairs(d.texts) do fs:Hide() end
    for _, b in ipairs(d.buttons) do b:Hide() end

    local y = 8
    y = PageText(d, "QuestTitleFont", step[F.NAME], y, 6)
    local info = { ("Level %d"):format(step[F.LEVEL] or 0) }
    if (step[F.REQ] or 0) > UnitLevel("player") then
        table.insert(info, ("|cffa00000Requires level %d|r"):format(step[F.REQ]))
    elseif step[F.REQ] then
        table.insert(info, ("requires level %d"):format(step[F.REQ]))
    end
    local line = table.concat(info, " · ")
    if stepID ~= id then
        line = line .. "\n" .. ("Step %d of %d toward %s"):format(entry.step or 1, #entry.steps, q[F.NAME])
    end
    local who, mapID, x, yy = StartInfo(step)
    if who then
        local zone = mapID and C_Map.GetMapInfo(mapID)
        line = line .. "\n" .. (zone and ("Starts at: %s, %s"):format(who, zone.name) or ("Starts with: %s (inside the dungeon)"):format(who))
    end
    y = PageText(d, "QuestFontNormalSmall", line, y, 10)

    -- Objectives, then the quest's own story text, as in the quest log's details.
    y = PageText(d, "QuestFont", FillText(text and text[2] ~= "" and text[2] or step[F.TEXT] or ""), y, 12)
    if text and text[1] ~= "" then
        y = PageText(d, "QuestTitleFont", QUEST_DESCRIPTION or "Description", y, 4)
        y = PageText(d, "QuestFont", FillText(text[1]), y, 12)
    end

    -- Rewards: "choose one" items, items you always get, money.
    local choice = text and text[3] or {}
    local fixed = text and text[4] or {}
    if #choice == 0 and #fixed == 0 and not text then
        for _, itemID in ipairs(step[F.REWARDS] or {}) do table.insert(fixed, { itemID, 1 }) end
    end
    local money = text and text[5] or 0
    if #choice > 0 or #fixed > 0 or money > 0 then
        y = PageText(d, "QuestTitleFont", REWARDS or "Rewards", y, 4)
        if #choice > 0 then
            y = PageText(d, "QuestFont", REWARD_CHOICES or "You will be able to choose one of these rewards:", y, 4)
            y = RewardGrid(d, choice, y)
        end
        if #fixed > 0 or money > 0 then
            y = PageText(d, "QuestFont", (#choice > 0 and REWARD_ITEMS or REWARD_ITEMS_ONLY) or "You will receive:", y, 4)
            if money > 0 then y = PageText(d, "QuestFont", MoneyText(money), y, 6) end
            if #fixed > 0 then y = RewardGrid(d, fixed, y) end
        end
    end
    d.Page:SetHeight(y + 8)
    d.Scroll:SetVerticalScroll(0)

    d.MapButton.target = mapID and { mapID = mapID, x = x, y = yy, title = step[F.NAME], who = who } or nil
    d.MapButton:SetEnabled(d.MapButton.target ~= nil)
end

ns.ShowQuestDetail = function(id, entry) ShowDetail(id, entry) end -- used by tools/test_addon.py

local function CreateDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetPoint("BOTTOMLEFT", 0, 0)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    d:Hide()
    d:EnableMouse(true)
    d.texts, d.buttons, d.textCount, d.buttonCount = {}, {}, 0, 0
    d.FillReward = FillReward
    -- The parchment of the game's own quest details.
    local bg = d:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if C_Texture.GetAtlasInfo("QuestDetailsBackgrounds") then
        bg:SetAtlas("QuestDetailsBackgrounds")
    else
        bg:SetTexture("Interface\\QuestFrame\\QuestBG")
    end

    -- The same border the game puts around its quest details.
    local okBorder, border = pcall(CreateFrame, "Frame", nil, d, "QuestLogBorderFrameTemplate")
    if okBorder and border then
        border:SetPoint("TOPLEFT", -3, 4)
        border:SetPoint("BOTTOMRIGHT", 3, -3)
        d.Border = border
    end

    local ok, scroll = pcall(CreateFrame, "ScrollFrame", "BeestersDungeonMapsQuestDetailScroll", d, "UIPanelScrollFrameTemplate")
    if not ok then scroll = CreateFrame("ScrollFrame", nil, d) end
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 32)
    d.Scroll = scroll
    d.Page = CreateFrame("Frame", nil, scroll)
    d.Page:SetSize(200, 10)
    scroll:SetScrollChild(d.Page)

    d.Close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.Close:SetPoint("TOPRIGHT", 0, 0)
    d.Close:SetFrameLevel(scroll:GetFrameLevel() + 10)
    d.Close:SetScript("OnClick", function() d:Hide(); selected = nil; Layout() end)

    d.MapButton = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.MapButton:SetSize(110, 22)
    d.MapButton:SetPoint("BOTTOMRIGHT", -6, 5)
    d.MapButton:SetFrameLevel(scroll:GetFrameLevel() + 10)
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

    panel.Detail = CreateDetail(panel)
    panel.Refresh = function() Refresh() end
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
        "PLAYER_LEVEL_UP", "QUEST_WATCH_LIST_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    local pending = false
    events:SetScript("OnEvent", function(_, event)
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- Reward names arrive a moment after the page opens; fill them in.
            local d = panel and panel.Detail
            if d and d:IsShown() then
                for i = 1, d.buttonCount do
                    local b = d.buttons[i]
                    if b and b.waiting then FillReward(b) end
                end
            end
            return
        end
        if pending or not (panel and panel:IsShown()) then return end
        pending = true
        C_Timer.After(0.2, function() pending = false; Refresh() end)
    end)
    ns.questPanelActive = true
end
