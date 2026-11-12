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
local RaiseAboveQuestDetails -- defined with the tabs
local UpdateShareButton -- defined with the detail page
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
    if q[F.FACTION] and q[F.FACTION] ~= (ns.questFaction or playerFaction) then return false end
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
                -- A chain you've started counts as one of your dungeon quests. One you haven't,
                -- whose first step starts inside (an item that drops there), starts inside.
                local first = Q(steps[1])
                if entry.started or entry.stepInLog then
                    entry.chain = true
                    table.insert(groups.log, entry)
                elseif #steps > 1 and first and StartsInside(first) then
                    entry.canTake = PrereqsDone(first)
                    table.insert(groups.inside, entry)
                else
                    table.insert(groups.available, entry)
                end
            end
        end
    end
    -- One block per chain: a dungeon quest that is an earlier step of a longer chain in this
    -- list (Hamuul Runetotem on the way to Leaders of the Fang) is shown inside that chain.
    local partOf = {}
    for _, group in ipairs({ groups.log, groups.available, groups.inside }) do
        for _, entry in ipairs(group) do
            if entry.steps and #entry.steps > 1 then
                for i = 1, #entry.steps - 1 do
                    local step = entry.steps[i]
                    if seen[step] and not IsDone(step) then
                        partOf[step] = true
                        entry.dungeonSteps = entry.dungeonSteps or {}
                        entry.dungeonSteps[step] = true
                    end
                end
            end
        end
    end
    for _, key in ipairs({ "log", "available", "inside" }) do
        local kept = {}
        for _, entry in ipairs(groups[key]) do
            if not partOf[entry.id] then table.insert(kept, entry) end
        end
        groups[key] = kept
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
ns.QuestPanelPools = pools -- used by tools/test_addon.py
local chainOpen = {} -- [questID] = true when the whole chain is folded open
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
    t.Tag = t:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
    t:SetScript("OnMouseDown", nil)
    t:SetScript("OnMouseUp", nil)
    -- Round quest icon, like the quest log's.
    t.POI = false
    local ok, poi = pcall(CreateFrame, "Button", nil, t, "POIButtonTemplate")
    if ok and poi and poi.SetQuestID then
        t.POI = poi
        poi:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -4)
        poi:EnableMouse(false)
    end
    -- Our own icon for quests that aren't in your log yet ("!" on the same round button).
    t.Bang = t:CreateTexture(nil, "OVERLAY")
    t.Bang:SetSize(24, 24)
    t.Bang:SetPoint("TOPLEFT", t, "TOPLEFT", 6, -4)
    t.BangMark = t:CreateTexture(nil, "OVERLAY", nil, 2)
    t.BangMark:SetSize(13, 13)
    t.BangMark:SetPoint("CENTER", t.Bang, "CENTER")
    t.Badge = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.Badge:SetPoint("CENTER", t.Bang, "CENTER", 0, 0)
    -- Track checkbox: the template's own box when it has one.
    if not t.Box then
        t.Box = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
        t.Box:SetSize(20, 20)
        t.Box:SetPoint("TOPRIGHT", 0, -8)
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

-- Shift-click a quest to put its link in chat, as in the game's quest log. Chat only keeps a
-- link the game made itself, so the game makes it.
-- The game only makes a link for a quest it has loaded; quests you haven't picked up often
-- aren't. Ask for them (on hover already), and put the link in once the game has it.
local waitingLink -- { id, editBox }
local linkLoader = CreateFrame("Frame")
pcall(linkLoader.RegisterEvent, linkLoader, "QUEST_DATA_LOAD_RESULT")
local function LoadQuest(id)
    if id and C_QuestLog and C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
end

local function InsertGameLink(id, editBox)
    if ChatEdit_TryInsertQuestLinkForQuestID and not editBox then
        local ok, done = pcall(ChatEdit_TryInsertQuestLinkForQuestID, id)
        if ok and done then return true end
    end
    local ok, link = pcall(GetQuestLink or function() end, id)
    if not (ok and type(link) == "string" and link ~= "") then return false end
    if editBox and editBox.Insert then
        if not editBox:IsShown() and ChatFrame_OpenChat then ChatFrame_OpenChat(link) else editBox:Insert(link) end
        return true
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) return true end
    return false
end

-- The game makes no link for a quest you've never had in your log, and chat drops links it
-- didn't make. Then the quest goes in as text in Questie's form, "[[33] Hearts of Zeal (1234)]":
-- players with Questie, or with this addon, see it as a link (see the chat filter below).
local function QuestText(id)
    local q = Q(id)
    local name = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    name = name or (q and q[F.NAME])
    if not name then return nil end
    local level = q and q[F.LEVEL]
    if level and level > 0 then return ("[[%d] %s (%d)]"):format(level, name, id) end
    return ("[%s (%d)]"):format(name, id)
end

local function InsertQuestName(id, editBox)
    local text = QuestText(id)
    if not text then return end
    if editBox and editBox.Insert and editBox:IsShown() then editBox:Insert(text)
    elseif ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return
    elseif ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

linkLoader:SetScript("OnEvent", function(_, _, questID, success)
    local w = waitingLink
    if not (w and questID == w.id) then return end
    waitingLink = nil
    if not (success and InsertGameLink(w.id, w.editBox)) then InsertQuestName(w.id, w.editBox) end
end)

local function LinkQuestToChat(id)
    if not (id and IsModifiedClick and IsModifiedClick("CHATLINK")) then return false end
    if InsertGameLink(id) then return true end
    -- Not loaded yet: ask, and insert it when it arrives (into the chat box open now).
    local w = { id = id, editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or nil }
    waitingLink = w
    LoadQuest(id)
    -- No answer from the game (it often doesn't for quests you've never had): the name as text.
    C_Timer.After(0.5, function()
        if waitingLink == w then
            waitingLink = nil
            if not InsertGameLink(w.id, w.editBox) then InsertQuestName(w.id, w.editBox) end
        end
    end)
    return true
end

-- "[26] The Book of Ur", like the quest log; "(Dungeon)" goes to the right as its tag.
local function QuestTitle(entry)
    local q = entry.q
    return ("[%d] %s"):format(q[F.LEVEL] or 0, q[F.NAME])
end
local DUNGEON_TAG = ("(%s)"):format(LFG_TYPE_DUNGEON or "Dungeon")

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

-- Spacing as the game's quest log lays it out (QuestMapFrame.lua, QuestLogQuests_* and its
-- spacing pairs): first header 8 from the top, header to header 6, header to quest 2,
-- quest to quest -3, quest to header 4. Headers sit 9 in; quest text 31 in and 8 down;
-- objectives under the text, 3 below it and 2 apart; 6 extra under each quest (its icon).
local SPACING = {
    none = { header = 8, quest = 8 },
    header = { header = 6, quest = 2 },
    quest = { header = 4, quest = -3 },
}
local previous = "none" -- what the last thing in the list was
local TITLE_LEFT = 4    -- WoW Forever's quest log pads quest rows 4 in (titleFrameLeftPadding)
local objectiveGap = 3  -- gap before the next objective line (3 under a title, then 2)

local function Space(y, kind)
    local gap = SPACING[previous][kind]
    previous = kind
    return y + gap
end

local function AddHeader(y, group, text, count)
    y = Space(y, "header")
    local h = Acquire("header")
    h.group = group
    h.Label:SetText(count and ("%s (%d)"):format(text, count) or text)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 9, -y)
    h:SetWidth(math.min(289, ListWidth() - 11))
    SetHeaderCollapsed(h, collapsed[group])
    return y + h:GetHeight()
end

local function AddObjective(y, text, r, g, b, noDash)
    y = y + objectiveGap
    objectiveGap = 2
    local o = Acquire("objective")
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", TITLE_LEFT + 31, -y)
    o:SetWidth(ListWidth() - 45)
    o.DashText:SetText(noDash and "" or (QUEST_DASH or "- "))
    o.Label:SetText(text)
    o.Label:SetWidth(math.min(205, ListWidth() - 60))
    if r then o.Label:SetTextColor(r, g, b) else o.Label:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b) end
    local height = math.max(o.Label:GetStringHeight() or 12, 12)
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
    y = y + objectiveGap - 1 -- step lines are a little taller than objective lines
    objectiveGap = 2
    local st = Acquire("step")
    -- A quest's row is clickable over its full height, chain lines included: keep the chain
    -- lines above it, or a row made later would take their clicks (opening the quest instead
    -- of folding the chain open).
    st:SetFrameLevel(panel.Child:GetFrameLevel() + 3)
    st:ClearAllPoints()
    st:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", TITLE_LEFT + indent, -y)
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

-- The chain as a trail of steps. Folded (the default) it shows only the step you're on with
-- its progress (or where it starts); unfolded it adds the steps done and the steps to come.
local function AddChain(y, entry)
    local steps = entry.steps
    local open = chainOpen[entry.id] == true
    y = AddStepLine(y, 30, ("Quest chain · step %d of %d"):format(entry.step or 1, #steps),
        open and "open" or "closed", nil, nil, nil, function()
            chainOpen[entry.id] = not open
            panel.Refresh()
        end, true)
    for i, stepID in ipairs(steps) do
        local sq = Q(stepID)
        local current = i == (entry.step or 1)
        if sq and (open or current) then
            local last = i == #steps or not open
            local name = ("%d. %s"):format(i, sq[F.NAME])
            if entry.dungeonSteps and entry.dungeonSteps[stepID] then
                name = ("%s (%s)"):format(name, LFG_TYPE_DUNGEON or "Dungeon")
            end
            local showStep = function()
                if LinkQuestToChat(stepID) then return end
                ShowDetail(entry.id, entry, stepID)
            end
            if i < (entry.step or 1) then
                y = AddStepLine(y, 40, name, "done", 0.55, 0.55, 0.55, showStep, last, "<Click for details>")
            elseif i == (entry.step or 1) then
                local where
                if InLog(stepID) then
                    where = " – in your log"
                else
                    local who, mapID = StartInfo(sq)
                    local zone = mapID and C_Map.GetMapInfo(mapID)
                    if who and #(sq[F.START_ITEM] or {}) > 0 then
                        where = (" – starts from %s, which drops inside"):format(who)
                    elseif who then
                        where = (" – %s%s"):format(who, zone and (", " .. zone.name) or "")
                    end
                end
                y = AddStepLine(y, 40, name .. (where or ""), "current", 1, 1, 1, showStep, last, "<Click for details>")
                -- The step's progress, right under it.
                if InLog(stepID) and C_QuestLog.GetQuestObjectives then
                    for _, obj in ipairs(C_QuestLog.GetQuestObjectives(stepID) or {}) do
                        if obj.text and obj.text ~= "" then
                            local o = Acquire("objective")
                            o:ClearAllPoints()
                            o:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", TITLE_LEFT + 58, -y)
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
                y = AddStepLine(y, 40, name, "todo", 0.6, 0.6, 0.6, showStep, last, "<Click for details>")
            end
        end
    end
    return y
end

local function AddQuestRow(y, entry, kind)
    local q = entry.q
    y = Space(y, "quest")
    local rowTop = y
    local t = Acquire("title")
    t.questID = entry.id
    t:ClearAllPoints()
    t:SetFrameLevel(panel.Child:GetFrameLevel() + 1)
    t:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", TITLE_LEFT, -y)
    t:SetWidth(math.min(290, ListWidth() - TITLE_LEFT))
    t.Label:ClearAllPoints()
    t.Label:SetPoint("TOPLEFT", t, "TOPLEFT", 31, -8)
    t.Label:SetText(QuestTitle(entry))
    local r, g, b = DifficultyColor(q[F.LEVEL])
    if kind == "inside" then r, g, b = 0.4, 0.75, 1 end
    if kind == "done" then r, g, b = 0.6, 0.6, 0.6 end
    t.Label:SetTextColor(r, g, b)
    t.r, t.g, t.b = r, g, b
    -- "(Dungeon)" on the right, in front of the track box, as the quest log tags it.
    local tag = t.Tag
    tag:SetText(DUNGEON_TAG)
    tag:SetTextColor(r, g, b)
    tag:ClearAllPoints()
    tag:SetPoint("TOPRIGHT", t, "TOPRIGHT", -26, -8)
    tag:Show()
    t.Label:SetPoint("RIGHT", tag, "LEFT", -4, 0)

    -- Icon: the game's round quest button for quests in your log; "!" for ones you can pick up.
    if t.POI then t.POI:Hide() end
    t.Bang:Hide(); t.BangMark:Hide(); t.Badge:SetText("")
    t.Bang:SetDesaturated(false); t.BangMark:SetDesaturated(false)
    t.Bang:SetAlpha(1); t.BangMark:SetAlpha(1)
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
        else
            -- Not available yet (level, or an earlier quest first): the same "!", greyed out,
            -- so every quest has its icon in the same place.
            t.Bang:SetAtlas("UI-QuestPoi-QuestNumber")
            t.BangMark:SetAtlas("QuestNormal")
            t.Bang:SetDesaturated(true); t.BangMark:SetDesaturated(true)
            t.Bang:SetAlpha(0.6); t.BangMark:SetAlpha(0.6)
            t.Bang:Show(); t.BangMark:Show()
        end
    end

    -- The quest a shift-click links: for a chain, the step you're on.
    t.linkID = entry.chain and entry.steps and entry.steps[entry.step or 1] or entry.id
    local inLog = kind == "log" and not entry.chain
    t.Box:SetShown(inLog)
    if inLog then
        SetTracked(t, C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(entry.id) ~= nil)
        t.hint = "<Click for details>"
        t:SetScript("OnClick", function(self)
            if LinkQuestToChat(self.linkID) then return end
            ShowDetail(self.questID, entry)
        end)
    else
        t.hint = "<Click for details>"
        t:SetScript("OnClick", function(self)
            if LinkQuestToChat(self.linkID) then return end
            ShowDetail(self.questID, entry)
        end)
    end
    if t.Glow then t.Glow:Hide() end
    t:SetScript("OnEnter", function(self)
        LoadQuest(self.linkID) -- so a shift-click can link it straight away
        self.Label:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        self.Tag:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        if self.Glow then self.Glow:Show() end
        QuestTooltip(self)
    end)
    t:SetScript("OnLeave", function(self)
        self.Label:SetTextColor(self.r, self.g, self.b)
        self.Tag:SetTextColor(self.r, self.g, self.b)
        if self.Glow then self.Glow:Hide() end
        GameTooltip:Hide()
    end)
    y = y + 8 + math.max(t.Label:GetStringHeight() or 12, 12)
    objectiveGap = 3

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
    y = y + 6 -- room for the round icon, as in the quest log
    t:SetHeight(y - rowTop)
    return y
end

local GROUPS = {
    { key = "log", title = "Dungeon quests" },
    { key = "available", title = "Available quests" },
    { key = "inside", title = "Starts inside" },
    { key = "done", title = "Handed in" },
}

function Refresh()
    if not panel or not panel:IsShown() then return end
    local key = panel.key
    if not key then return end
    ReleaseAll()

    local groups = Classify(key)
    local y, any = 0, false
    previous = "none"
    -- Everything handed in: say so, above the handed-in list.
    if #groups.log + #groups.available + #groups.inside == 0 and #groups.done > 0 then
        any = true
        y = AddHeader(y, "log", GROUPS[1].title)
        previous = "quest"
        objectiveGap = 8
        y = AddObjective(y, "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t You've completed all the quests in this dungeon.",
            GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, true)
        panel.allDone = true
        y = y + 6
    else
        panel.allDone = false
    end
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
        objectiveGap = 10
        y = AddObjective(0, "No quests known for this dungeon.", 0.6, 0.6, 0.6, true)
    end
    panel.Child:SetHeight(math.max(y + 10, 10))
end

----------------------------------------------------------------------
-- Detail pane
----------------------------------------------------------------------

-- The details take the whole tab, as the game's own do; the list comes back when they close.
local function Layout()
    if not panel then return end
    local d = panel.Detail
    local open = d:IsShown() and true or false
    panel.Scroll:ClearAllPoints()
    panel.Scroll:SetPoint("TOPLEFT", 0, 0)
    panel.Scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.Scroll:SetShown(not open)
    if type(rawget(panel, "Border")) == "table" then panel.Border:SetShown(not open) end
    panel.Child:SetWidth(math.max(panel.Scroll:GetWidth(), 50))
    if d and d.Page then d.Page:SetWidth(math.max(d.Scroll:GetWidth(), 50)) end
end

----------------------------------------------------------------------
-- Detail page: laid out like the game's quest details (title, objectives, description,
-- rewards), on the same parchment, scrolling when it's long.
----------------------------------------------------------------------

local INK = { 0.18, 0.12, 0.06 }
local FADED_INK = { 0.36, 0.26, 0.15 } -- secondary lines (level, where): lighter brown, still readable

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

-- The rewards' heading and captions: the warm beige the game uses on its brown rewards panel.
local REWARD_INK = { 0.90, 0.79, 0.67 }

-- The game's own art for the rewards panel of its quest details, laid out as the game does it
-- (read from QuestMapFrame.DetailsFrame): the wooden header band at the top, the tile from
-- under it to the bottom, and the bottom piece over the tile's lower end. The tile is partly
-- see-through; in the game it lies on the dark frame behind, so here on a dark base.
local REWARD_ART = {
    tile = "QuestLog-reward-tile-vertical", header = "QuestLog-reward-header-top",
    bottom = "QuestLog-reward-bottom",
}
local function AtlasHeight(name, width)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if not (info and info.width and info.width > 0 and info.height) then return nil end
    return info.height * width / info.width -- its height at this width, keeping its shape
end

-- Text goes on the page, or on the rewards panel while d.host is set to it.
local function PageText(d, font, text, y, gap, ink, justify)
    local host = rawget(d, "host") or d.Page
    local onPage = host == d.Page
    local pool, key = onPage and d.texts or d.rtexts, onPage and "textCount" or "rtextCount"
    d[key] = d[key] + 1
    local fs = pool[d[key]]
    if not fs then
        fs = host:CreateFontString(nil, "ARTWORK", font)
        pool[d[key]] = fs
    end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetFontObject(_G[font] and font or "GameFontHighlightSmall")
    ink = ink or INK
    fs:SetTextColor(ink[1], ink[2], ink[3])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", host, "TOPLEFT", 10, -y)
    fs:SetWidth(d.Page:GetWidth() - 20)
    fs:SetText(text)
    fs:Show()
    return y + fs:GetStringHeight() + (gap or 8)
end

local function RewardButton(d, itemID, count, x, y)
    d.buttonCount = d.buttonCount + 1
    local b = d.buttons[d.buttonCount]
    local host = rawget(d, "host") or d.Page
    if not b then
        -- The small reward button of the map's own quest details; older clients' large one else.
        local ok, made = pcall(CreateFrame, "Button", nil, host, "SmallQuestRewardItemButtonTemplate")
        if not ok then ok, made = pcall(CreateFrame, "Button", nil, host, "LargeItemButtonTemplate") end
        b = ok and made or CreateFrame("Button", nil, host)
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
            if self.special then
                ns:HideItemTooltip(nil)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.special.tooltip, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                GameTooltip:Show()
            else
                ns:ShowItemByID(self, self.itemID)
            end
        end)
        b:SetScript("OnLeave", function(self) ns:HideItemTooltip(self) end)
        b:SetScript("OnClick", function(self)
            if self.special then return end
            local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(self.itemID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        d.buttons[d.buttonCount] = b
    end
    if type(itemID) == "table" then
        b.special, b.itemID, b.count = itemID, false, false
    else
        b.special, b.itemID, b.count = false, itemID, count
    end
    d.FillReward(b)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
    b:Show()
end

-- Name, colour and border of a reward; called again when the item's data arrives.
-- Experience and money use the same button, like the game's own reward list.
local function FillReward(b)
    if b.special then
        b.waiting = false
        if type(b.Icon) == "table" then b.Icon:SetTexture(b.special.icon) end
        if type(b.Name) == "table" then b.Name:SetText(b.special.text); b.Name:SetTextColor(1, 1, 1) end
        if type(b.Count) == "table" then b.Count:SetText(""); b.Count:Hide() end
        if type(b.IconBorder) == "table" then b.IconBorder:Hide() end
        return
    end
    local itemID = b.itemID
    local name, _, quality, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    b.waiting = not name
    if type(b.Icon) == "table" then b.Icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400) end
    if type(b.Name) == "table" then
        b.Name:SetText(name or (SEARCH_LOADING_TEXT or "Loading..."))
        b.Name:SetTextColor(1, 1, 1) -- white, as in the map's quest details; quality shows on the icon border
    end
    if type(b.Count) == "table" then
        b.Count:SetText(b.count and b.count > 1 and b.count or "")
        b.Count:SetShown(b.count and b.count > 1)
    end
    if quality and type(b.IconBorder) == "table" and SetItemButtonQuality then pcall(SetItemButtonQuality, b, quality, itemID) end
end

-- Rewards two per row, like the map's quest details; the buttons are scaled to fit if needed.
-- Experience and money each get a row of their own first, as the game shows them.
local function RewardGrid(d, items, y)
    local width = d.Page:GetWidth() - 20
    local col, row, rows, cellHeight = 0, 0, 0, 44
    for _, pair in ipairs(items) do
        RewardButton(d, pair[1], pair[2], 0, 0)
        local b = d.buttons[d.buttonCount]
        local w, h = b:GetSize()
        w = (type(w) == "number" and w > 0) and w or 147
        h = (type(h) == "number" and h > 0) and h or 41
        local scale = math.min(1, (width / 2 - 4) / w)
        local cellW, cellH = w * scale + 4, h * scale + 3
        local own = type(pair[1]) == "table" -- experience, money: a row of their own
        if own and col > 0 then col, row = 0, row + 1 end
        b:SetScale(scale)
        b:ClearAllPoints()
        -- Offsets are in the button's own (scaled) units.
        b:SetPoint("TOPLEFT", rawget(d, "host") or d.Page, "TOPLEFT", (10 + col * cellW) / scale, -(y + row * cellH) / scale)
        rows = row + 1
        if own or col == 1 then col, row = 0, row + 1 else col = 1 end
        cellHeight = cellH
    end
    return y + rows * cellHeight + 6
end

-- Experience for this character: the game's number while the quest is in your log,
-- otherwise the quest's experience scaled the way the game does it for higher levels
-- (full up to 5 levels above the quest, then less; none at the level cap).
local MAX_LEVEL = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
local function QuestXP(questID, baseXP, questLevel)
    if InLog(questID) and GetQuestLogRewardXP then
        local xp = GetQuestLogRewardXP(questID)
        if xp and xp > 0 then return xp end
    end
    if not baseXP or baseXP <= 0 then return 0 end
    local level = UnitLevel("player")
    if level >= MAX_LEVEL then return 0 end
    local factor = math.max(1, math.min(10, 2 * ((questLevel or level) - level) + 20))
    local xp = baseXP * factor / 10
    if xp <= 100 then xp = 5 * math.floor((xp + 2) / 5)
    elseif xp <= 500 then xp = 10 * math.floor((xp + 5) / 10)
    elseif xp <= 1000 then xp = 25 * math.floor((xp + 12) / 25)
    else xp = 50 * math.floor((xp + 25) / 50) end
    return xp
end

-- Rewards straight from the game (the same calls its quest tooltips use). The game loads a
-- quest's data on request; QUEST_DATA_LOAD_RESULT then redraws the details.
local requestedQuestData = {}
local function LiveRewards(questID)
    if not (GetQuestLogRewardXP and GetNumQuestLogChoices and GetQuestLogChoiceInfo) then return end
    if C_QuestLog.RequestLoadQuestByID and not requestedQuestData[questID]
        and not (C_QuestLog.HasQuestData and C_QuestLog.HasQuestData(questID)) then
        requestedQuestData[questID] = true -- once: the answer redraws the page, which must not ask again
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    local ok, result = pcall(function()
        local r = { xp = GetQuestLogRewardXP(questID) or 0, money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0,
            choice = {}, fixed = {} }
        for i = 1, GetNumQuestLogChoices(questID) or 0 do
            local _, _, count, _, _, itemID = GetQuestLogChoiceInfo(i, questID)
            if itemID then table.insert(r.choice, { itemID, count or 1 }) end
        end
        for i = 1, (GetNumQuestLogRewards and GetNumQuestLogRewards(questID)) or 0 do
            local _, _, count, _, _, itemID = GetQuestLogRewardInfo(i, questID)
            if itemID then table.insert(r.fixed, { itemID, count or 1 }) end
        end
        return r
    end)
    if ok and result and (result.xp > 0 or result.money > 0 or #result.choice > 0 or #result.fixed > 0) then
        return result
    end
end

-- Share works for a quest in your log that can be shared, while you're in a group.
UpdateShareButton = function(d, questID)
    local b = d.ShareButton
    if not b then return end
    b.questID = questID
    local reason
    if not InLog(questID) then
        reason = "Pick up this quest to share it."
    elseif C_QuestLog.IsPushableQuest and not C_QuestLog.IsPushableQuest(questID) then
        reason = "This quest can't be shared."
    elseif IsInGroup and not IsInGroup() then
        reason = "Join a group to share this quest."
    end
    b.reason = reason
    b:SetEnabled(reason == nil)
end

function ShowDetail(id, entry, stepOverride)
    local q = Q(id)
    if not q then return end
    selected = id
    local d = panel.Detail
    d:Show()
    Layout()
    -- For a chain: the step you clicked, or the step you're on.
    local stepID = stepOverride or (entry and entry.steps and entry.steps[entry.step or 1]) or id
    local step = Q(stepID) or q
    local text = ns.QuestText and ns.QuestText[stepID]
    local inLog = InLog(stepID)
    d.current = { id = id, entry = entry, stepOverride = stepOverride, stepID = stepID }
    d.textCount, d.buttonCount, d.rtextCount = 0, 0, 0
    d.host = nil
    for _, fs in ipairs(d.texts) do fs:Hide() end
    for _, fs in ipairs(d.rtexts) do fs:Hide() end
    for _, b in ipairs(d.buttons) do b:Hide() end

    local y = 8
    y = PageText(d, "QuestTitleFont", step[F.NAME], y, 6)
    local info = { ("Level %d"):format(step[F.LEVEL] or 0) }
    if inLog then
        table.insert(info, ReadyToTurnIn(stepID) and "ready to hand in" or "in your log")
    elseif IsDone(stepID) then
        table.insert(info, "handed in")
    elseif (step[F.REQ] or 0) > UnitLevel("player") then
        table.insert(info, ("|cffb00000Requires level %d|r"):format(step[F.REQ]))
    elseif step[F.REQ] then
        table.insert(info, ("requires level %d"):format(step[F.REQ]))
    end
    local line = table.concat(info, " · ")
    if stepID ~= id and entry and entry.steps then
        local index = 1
        for i, sid in ipairs(entry.steps) do if sid == stepID then index = i end end
        line = line .. "\n" .. ("Step %d of %d toward %s"):format(index, #entry.steps, q[F.NAME])
    end
    -- Where to go: hand-in when it's in your log, otherwise where it starts.
    local who, mapID, x, yy = StartInfo(step)
    local verb = "Starts at"
    if inLog then
        local tWho, tMap, tx, ty = TurnInInfo(step)
        if tWho then who, mapID, x, yy, verb = tWho, tMap, tx, ty, "Hand in at" end
    end
    if who then
        local zone = mapID and C_Map.GetMapInfo(mapID)
        line = line .. "\n" .. (zone and ("%s: %s, %s"):format(verb, who, zone.name) or ("%s: %s (inside the dungeon)"):format(verb, who))
    end
    y = PageText(d, "QuestFontNormalSmall", line, y, 10, FADED_INK)

    -- Objectives, then the quest's own story text, as in the quest log's details.
    y = PageText(d, "QuestFont", FillText(text and text[2] ~= "" and text[2] or step[F.TEXT] or ""), y, 6)
    if inLog and C_QuestLog.GetQuestObjectives then
        local lines = {}
        for _, obj in ipairs(C_QuestLog.GetQuestObjectives(stepID) or {}) do
            if obj.text and obj.text ~= "" then table.insert(lines, "- " .. obj.text) end
        end
        if #lines > 0 then y = PageText(d, "QuestFont", table.concat(lines, "\n"), y, 6) end
    end
    y = y + 6
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
    local xp = QuestXP(stepID, text and text[7], step[F.LEVEL])
    -- The game's own reward data, when it has it for this quest (exact for your character).
    local live = LiveRewards(stepID)
    if live then
        choice, fixed = live.choice, live.fixed
        if live.money > 0 then money = live.money end
        if live.xp > 0 then xp = live.xp end
    end
    -- Experience and money first, then the items you always get, as in the map's quest details.
    local receive = {}
    if xp > 0 then
        table.insert(receive, { { icon = "Interface\\Icons\\XP_Icon", text = BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp),
            tooltip = (EXPERIENCE_COLON or "Experience:") .. " " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) } })
    end
    if money > 0 then
        table.insert(receive, { { icon = "Interface\\Icons\\INV_Misc_Coin_01", text = MoneyText(money), tooltip = MoneyText(money) } })
    end
    for _, pair in ipairs(fixed) do table.insert(receive, pair) end
    if #choice > 0 or #receive > 0 then
        -- The rewards on their own dark brown panel, as in the map's quest details: "Rewards"
        -- in the wooden header band, small light captions. The panel sits at the bottom of the
        -- details from the start (over the text) and rises to its place as you scroll; the
        -- page keeps room for it at the end. Its y values count from the panel's top.
        local top = y + 2
        d.host = d.Rewards
        local boxW = d.RewardClip:GetWidth()
        if type(boxW) ~= "number" or boxW <= 0 then boxW = d.Box:GetWidth() end
        if type(boxW) ~= "number" or boxW <= 0 then boxW = d.Page:GetWidth() + 24 end
        local band = AtlasHeight(REWARD_ART.header, boxW)
        local ry
        if band then
            PageText(d, "QuestTitleFont", REWARDS or "Rewards", (band - 18) / 2, 0, REWARD_INK, "CENTER")
            ry = band + 6
            if type(rawget(d, "RewardDivider")) == "table" then d.RewardDivider:Hide() end
        else
            -- No such art in this client: the heading over a divider line.
            ry = PageText(d, "QuestTitleFont", REWARDS or "Rewards", 10, 2, REWARD_INK, "CENTER")
            if type(rawget(d, "RewardDivider")) ~= "table" then
                d.RewardDivider = d.Rewards:CreateTexture(nil, "ARTWORK")
                d.RewardDivider:SetTexture("Interface\\QuestFrame\\UI-HorizontalBreak")
                d.RewardDivider:SetHeight(16)
            end
            d.RewardDivider:ClearAllPoints()
            d.RewardDivider:SetPoint("TOPLEFT", d.Rewards, "TOPLEFT", 14, -(ry - 4))
            d.RewardDivider:SetPoint("TOPRIGHT", d.Rewards, "TOPRIGHT", -14, -(ry - 4))
            d.RewardDivider:Show()
            ry = ry + 10
        end
        local caption = REWARD_INK
        if #choice > 0 then
            ry = PageText(d, "GameFontHighlightSmall", REWARD_CHOICES or "You will be able to choose one of these rewards:", ry, 4, caption)
            ry = RewardGrid(d, choice, ry)
        end
        if #receive > 0 then
            ry = PageText(d, "GameFontHighlightSmall", (#choice > 0 and REWARD_ITEMS or REWARD_ITEMS_ONLY) or "You will receive:", ry, 4, caption)
            ry = RewardGrid(d, receive, ry)
        end
        ry = ry + 4
        d.host = nil
        d.rewardTop = top
        -- How much shows at the bottom before you scroll: the header and the first row or so.
        d.rewardPeek = math.min(ry, (band or 30) + 95)
        y = top + ry
    else
        d.rewardTop = nil
        if type(rawget(d, "RewardDivider")) == "table" then d.RewardDivider:Hide() end
    end
    d.Page:SetHeight(y + 8)
    d.Scroll:SetVerticalScroll(0)
    d.UpdateRewardPanel()

    d.MapButton.target = mapID and { mapID = mapID, x = x, y = yy, title = step[F.NAME],
        who = ("%s: %s"):format(inLog and "Hand in" or "Pick up", who or "?") } or nil
    d.MapButton:SetEnabled(d.MapButton.target ~= nil)
    UpdateShareButton(d, stepID)
end

ns.ShowQuestDetail = function(id, entry, step) ShowDetail(id, entry, step) end -- used by tools/test_addon.py

local function CreateDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    -- The whole tab; the border's top lines up with the list's.
    d:SetPoint("TOPLEFT", 0, 3)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    d:Hide()
    d:SetScript("OnHide", function(self) ns:HideTooltipWithin(self) end)
    d:EnableMouse(true)
    d.texts, d.buttons, d.textCount, d.buttonCount = {}, {}, 0, 0
    d.rtexts, d.rtextCount = {}, 0
    d.FillReward = FillReward
    -- The text sits in its own box (parchment and border, closed at the bottom); the
    -- buttons go underneath it, outside the border.
    local box = CreateFrame("Frame", nil, d)
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", 0, 30)
    d.Box = box
    -- The parchment of the game's own quest details.
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if C_Texture.GetAtlasInfo("QuestDetailsBackgrounds") then
        bg:SetAtlas("QuestDetailsBackgrounds")
    else
        bg:SetTexture("Interface\\QuestFrame\\QuestBG")
    end

    -- The same border the game puts around its quest details.
    local okBorder, border = pcall(CreateFrame, "Frame", nil, box, "QuestLogBorderFrameTemplate")
    if okBorder and border then
        border:SetPoint("TOPLEFT", -3, 4)
        border:SetPoint("BOTTOMRIGHT", 3, -3)
        d.Border = border
    end

    -- The game's thin scroll bar, just outside the parchment like the list's; the old
    -- template's bar inside it if this client can't make that one.
    local scroll = CreateFrame("ScrollFrame", "BeestersDungeonMapsQuestDetailScroll", box)
    scroll.scrollBarX, scroll.scrollBarTopY, scroll.scrollBarBottomY = 8, 6, -8
    local right = 0
    if not (ScrollFrame_OnLoad and pcall(ScrollFrame_OnLoad, scroll)) then
        scroll:Hide()
        local ok, made = pcall(CreateFrame, "ScrollFrame", "BeestersDungeonMapsQuestDetailScrollOld", box, "UIPanelScrollFrameTemplate")
        scroll = ok and made or CreateFrame("ScrollFrame", nil, box)
        right = -24
    end
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", right, 4)
    d.Scroll = scroll
    d.Page = CreateFrame("Frame", nil, scroll)
    d.Page:SetSize(200, 10)
    scroll:SetScrollChild(d.Page)

    -- The rewards panel: over the page, cut off at the top of the text area like the page,
    -- running edge to edge down to the bottom of the box.
    local clip = CreateFrame("Frame", nil, box)
    clip:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", right, 0)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    clip:SetFrameLevel(scroll:GetFrameLevel() + 2)
    d.RewardClip = clip
    local rewards = CreateFrame("Frame", nil, clip)
    rewards:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    rewards:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    -- Scrolling over the rewards scrolls the page.
    rewards:EnableMouseWheel(true)
    rewards:SetScript("OnMouseWheel", function(_, delta)
        local wheel = scroll:GetScript("OnMouseWheel")
        if type(wheel) == "function" then wheel(scroll, delta) end
    end)
    rewards:Hide()
    d.Rewards = rewards

    local hasArt = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(REWARD_ART.tile) ~= nil
    -- A dark base: the game's measured brown without the art, the frame behind it with it.
    local base = rewards:CreateTexture(nil, "BACKGROUND", nil, 1)
    base:SetAllPoints()
    if hasArt then base:SetColorTexture(0.07, 0.045, 0.03, 1) else base:SetColorTexture(0.22, 0.118, 0.06, 1) end
    local tile, header, bottom
    if hasArt then
        header = rewards:CreateTexture(nil, "BACKGROUND", nil, 3)
        header:SetAtlas(REWARD_ART.header, false)
        header:SetPoint("TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", 0, 0)
        tile = rewards:CreateTexture(nil, "BACKGROUND", nil, 2)
        tile:SetAtlas(REWARD_ART.tile, false)
        tile:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        tile:SetPoint("BOTTOMRIGHT", 0, 0)
        bottom = rewards:CreateTexture(nil, "BACKGROUND", nil, 3)
        bottom:SetAtlas(REWARD_ART.bottom, false)
        bottom:SetPoint("BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    d.UpdateRewardPanel = function()
        local top = rawget(d, "rewardTop")
        local offset = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
        if type(offset) ~= "number" then offset = 0 end
        if type(top) ~= "number" then rewards:Hide(); return end
        -- Where it is on the page, but never lower than its peek at the bottom.
        local t = top - offset
        local viewH, peek = clip:GetHeight(), rawget(d, "rewardPeek")
        if type(viewH) == "number" and viewH > 0 and type(peek) == "number" then
            t = math.min(t, viewH - peek)
        end
        rewards:ClearAllPoints()
        rewards:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, -t)
        rewards:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
        if header then
            local w = clip:GetWidth()
            if type(w) ~= "number" or w <= 0 then w = box:GetWidth() end
            header:SetHeight(AtlasHeight(REWARD_ART.header, w) or 55)
            bottom:SetHeight(AtlasHeight(REWARD_ART.bottom, w) or 87)
        end
        rewards:Show()
    end
    scroll:HookScript("OnVerticalScroll", function() d.UpdateRewardPanel() end)
    clip:SetScript("OnSizeChanged", function() d.UpdateRewardPanel() end)

    -- On the border's corner and above it (the border's filigree used to cover it).
    d.Close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.Close:SetPoint("TOPRIGHT", 5, 6)
    d.Close:SetFrameLevel(math.max(scroll:GetFrameLevel(), d.Border and d.Border:GetFrameLevel() or 0) + 10)
    d.Close:SetScript("OnClick", function() d:Hide(); selected = nil; Layout() end)

    d.MapButton = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    -- One bar of equal buttons under the text, like the game's Abandon | Share | Track.
    d.MapButton:SetHeight(22)
    d.MapButton:SetPoint("BOTTOMLEFT", d, "BOTTOM", 1, 2)
    d.MapButton:SetPoint("BOTTOMRIGHT", 0, 2)
    d.MapButton:SetFrameLevel(math.max(scroll:GetFrameLevel(), d.Border and d.Border:GetFrameLevel() or 0) + 10)
    d.MapButton:SetText("Show on map")
    d.MapButton:SetScript("OnClick", function(self)
        local t = self.target
        if t then ns:ShowQuestMarker(t.mapID, t.x, t.y, t.title, t.who) end
    end)

    -- Share the quest with your group, like the quest log's Share button.
    d.ShareButton = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.ShareButton:SetHeight(22)
    d.ShareButton:SetPoint("BOTTOMLEFT", 0, 2)
    d.ShareButton:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -1, 2)
    d.ShareButton:SetFrameLevel(d.MapButton:GetFrameLevel())
    d.ShareButton:SetText(SHARE_QUEST_ABBREV or "Share")
    d.ShareButton:SetMotionScriptsWhileDisabled(true)
    d.ShareButton:SetScript("OnClick", function(self)
        local index = self.questID and C_QuestLog.GetLogIndexForQuestID(self.questID)
        if index and QuestLogPushQuest then
            QuestLogPushQuest(index)
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN) end
        end
    end)
    d.ShareButton:SetScript("OnEnter", function(self)
        if self.reason then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.reason, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    d.ShareButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return d
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

-- A quest opened in the Quest Log tab keeps the game's own details (and their rewards) open
-- underneath. The dungeon tab goes on top of all of it; the game's details are left as they
-- were, so the Quest Log tab shows them again when you switch back.
RaiseAboveQuestDetails = function()
    if not panel then return end
    local top = QuestMapFrame and QuestMapFrame:GetFrameLevel() or 0
    local details = QuestMapFrame and rawget(QuestMapFrame, "DetailsFrame")
    if type(details) == "table" and details.GetChildren then
        top = math.max(top, details:GetFrameLevel())
        for _, child in ipairs({ details:GetChildren() }) do
            if child.GetFrameLevel then top = math.max(top, child:GetFrameLevel()) end
        end
    end
    local level = math.min(top + 50, 9000)
    if panel:GetFrameLevel() < level then panel:SetFrameLevel(level) end
    if panel.Border then panel.Border:SetFrameLevel(panel:GetFrameLevel() + 20) end
    if strip and strip:GetFrameLevel() < level + 10 then strip:SetFrameLevel(level + 10) end
end

local function SetTab(which)
    tab = which
    if strip then
        strip.Log.Selected:SetShown(which == "log")
        strip.Dungeon.Selected:SetShown(which == "dungeon")
        strip.Log:SetNormalFontObject(which == "log" and "GameFontHighlight" or "GameFontNormal")
        strip.Dungeon:SetNormalFontObject(which == "dungeon" and "GameFontHighlight" or "GameFontNormal")
    end
    if panel then
        if which == "dungeon" then RaiseAboveQuestDetails() end
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
    strip.Dungeon:SetScript("OnClick", function()
        if panel.key and not ns:IsDungeonMapOpen() then
            ns:OpenDungeonMap(panel.key) -- back from a "Show on map" zone map
        else
            SetTab("dungeon")
        end
    end)
    -- Horde / Alliance: which side's quests to list. Starts on your own faction.
    local f = CreateFrame("Button", nil, strip)
    f:SetHeight(20)
    f:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(16, 16)
    f.Icon:SetPoint("LEFT", 4, 0)
    f.Label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.Label:SetPoint("LEFT", f.Icon, "RIGHT", 3, 0)
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    f.Update = function(self)
        local horde = ns.questFaction == "H"
        self.Icon:SetTexture(horde and "Interface\\PVPFrame\\PVP-Currency-Horde" or "Interface\\PVPFrame\\PVP-Currency-Alliance")
        self.Label:SetText(horde and (FACTION_HORDE or "Horde") or (FACTION_ALLIANCE or "Alliance"))
        local c = horde and { 0.9, 0.3, 0.25 } or { 0.35, 0.6, 1 }
        self.Label:SetTextColor(c[1], c[2], c[3])
        self:SetWidth(self.Label:GetStringWidth() + 28)
    end
    f:SetScript("OnClick", function(self)
        ns.questFaction = ns.questFaction == "H" and "A" or "H"
        self:Update()
        if panel then panel.Detail:Hide(); selected = nil; Layout(); Refresh() end
        if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then self.ShowTip(self) end
    end)
    f.ShowTip = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        local side = ns.questFaction == "H" and "Horde" or "Alliance"
        local other = ns.questFaction == "H" and "Alliance" or "Horde"
        GameTooltip:SetText(("Showing %s quests"):format(side), 1, 1, 1)
        GameTooltip:AddLine(("<Click to show %s quests>"):format(other), GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        GameTooltip:Show()
    end
    f:SetScript("OnEnter", f.ShowTip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    strip.Faction = f
    local own = UnitFactionGroup("player")
    ns.questFaction = own == "Alliance" and "A" or "H"
    f:Update()
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

    -- The same scroll frame as the quest log's, with its scroll bar in the same place (just
    -- outside the list, 8 to the right), so ours covers the game's exactly.
    local scroll = CreateFrame("ScrollFrame", "BeestersDungeonMapsQuestScroll", panel)
    scroll.scrollBarX, scroll.scrollBarTopY, scroll.scrollBarBottomY = 8, 2, -4
    if not (ScrollFrame_OnLoad and pcall(ScrollFrame_OnLoad, scroll)) then
        scroll:Hide()
        local ok, made = pcall(CreateFrame, "ScrollFrame", "BeestersDungeonMapsQuestScrollOld", panel, "UIPanelScrollFrameTemplate")
        scroll = ok and made or CreateFrame("ScrollFrame", nil, panel)
    end
    panel.Scroll = scroll
    -- The quest log's frame around the list: gold border, filigree on top, shadow at the bottom.
    local okBorder, border = pcall(CreateFrame, "Frame", nil, panel, "QuestLogBorderFrameTemplate")
    if okBorder and border then
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", scroll, "TOPLEFT", -3, 7)
        border:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 3, -6)
        local shadow = border:CreateTexture(nil, "BACKGROUND")
        if C_Texture.GetAtlasInfo("questlog-frame-gradient-bottom") then
            shadow:SetAtlas("questlog-frame-gradient-bottom", true)
            shadow:SetPoint("BOTTOM", 0, 4)
        end
        border:SetFrameLevel(panel:GetFrameLevel() + 20)
        panel.Border = border
    end
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
    if panel.key ~= key then
        panel.Detail:Hide()
        selected = nil
    end
    panel.key = key
    SetTabText(strip.Dungeon, ns.Instances[key] and ns.Instances[key].name or key)
    strip:Show()
    SetTab("dungeon")
end

-- keepForMarker: "Show on map" moved to a zone map; the dungeon's quests stay, so you can
-- go on reading them. Clicking the dungeon tab brings the dungeon map back.
function ns:HideDungeonQuests(keepForMarker)
    if keepForMarker or ns.keepQuestPanel then return end
    if strip then strip:Hide() end
    if panel then panel:Hide(); panel.key = nil end
end

----------------------------------------------------------------------
-- Quest text in chat as links
----------------------------------------------------------------------
-- Messages with a dungeon quest in Questie's text form ("[[33] Hearts of Zeal (1234)]") get a
-- link on your screen; clicking it shows the quest. Only when Questie isn't running: Questie
-- does the same for every quest. Nothing is sent; this only changes how a message looks here.
local LINK_TYPE = "bdmquest"
local lastShown

local function ShowQuestReference(id)
    local q = Q(id)
    if not (q and ItemRefTooltip) then return false end
    if not ItemRefTooltip:IsShown() then lastShown = nil end
    ShowUIPanel(ItemRefTooltip)
    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
    ItemRefTooltip:ClearLines()
    ItemRefTooltip:AddLine(q[F.NAME], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    ItemRefTooltip:AddLine(("Level %d · %s quest"):format(q[F.LEVEL] or 0, LFG_TYPE_DUNGEON or "Dungeon"), 1, 1, 1)
    local who, mapID = StartInfo(q)
    local zone = mapID and C_Map.GetMapInfo(mapID)
    if who then
        ItemRefTooltip:AddLine(("Starts at %s%s"):format(who, zone and (", " .. zone.name) or ""), 0.8, 0.8, 0.8, true)
    end
    local text = ns.QuestText and ns.QuestText[id]
    if text and text[2] and text[2] ~= "" then
        ItemRefTooltip:AddLine(" ")
        ItemRefTooltip:AddLine(FillText(text[2]), 1, 1, 1, true)
    end
    ItemRefTooltip:Show()
    if ItemRefTooltip.SetPadding then ItemRefTooltip:SetPadding(16, 0) end
    if lastShown == id then ItemRefTooltip:Hide(); lastShown = nil else lastShown = id end -- a second click closes it
    return true
end

local function LinkUp(level, name, idText)
    local id = tonumber(idText)
    if not (id and Q(id)) then return nil end -- not a dungeon quest this addon knows
    local label = level and ("[[%s] %s]"):format(level, name) or ("[%s]"):format(name)
    return ("|cffffff00|H%s:%d|h%s|h|r"):format(LINK_TYPE, id, label)
end

local function ChatFilter(_, _, msg, ...)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) or not msg:find("%(%d+%)%]") then
        return false
    end
    local ok, changed = pcall(function()
        local out = msg:gsub("%[%[(%d+)%] ([^%]]-) %((%d+)%)%]", function(level, name, id)
            return LinkUp(level, name, id)
        end)
        return (out:gsub("%[([^%[%]]-) %((%d+)%)%]", function(name, id) return LinkUp(nil, name, id) end))
    end)
    if ok and changed and changed ~= msg then return false, changed, ... end
    return false
end

local function InitChatLinks()
    local questie = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")
        or (IsAddOnLoaded and IsAddOnLoaded("Questie"))
    if questie or not ChatFrame_AddMessageEventFilter then return end
    for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL" }) do
        ChatFrame_AddMessageEventFilter(event, ChatFilter)
    end
    -- Clicking the link: the game's link handler API, as Questie uses it on Forever (replacing
    -- the reference tooltip's SetHyperlink would taint every link click).
    if LinkUtil and LinkUtil.RegisterLinkHandler and LinkProcessorResponse then
        LinkUtil.RegisterLinkHandler(LINK_TYPE, function(link)
            if IsModifiedClick() then return LinkProcessorResponse.Unhandled end
            local id = tonumber((link or ""):match(LINK_TYPE .. ":(%d+)"))
            if id and ShowQuestReference(id) then return LinkProcessorResponse.Handled end
            return LinkProcessorResponse.Unhandled
        end)
    end
    ns.QuestChatFilter = ChatFilter -- read by tools/test_addon.py
end

function ns:InitQuestPanel()
    if not ns.Quests then return end
    InitChatLinks()
    -- Leaving the marker's zone map for any other map ends the dungeon's quest view.
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        if panel and panel.key and not ns:IsDungeonMapOpen() and not ns.keepQuestPanel then
            local m = ns.questMarker
            if not (m and m.mapID == WorldMapFrame:GetMapID()) then ns:HideDungeonQuests() end
        end
    end)
    WorldMapFrame:HookScript("OnHide", function() ns.keepQuestPanel = false; ns:HideDungeonQuests() end)
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
        "PLAYER_LEVEL_UP", "QUEST_WATCH_LIST_CHANGED", "GET_ITEM_INFO_RECEIVED", "QUEST_DATA_LOAD_RESULT", "GROUP_ROSTER_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    local pending = false
    events:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "GROUP_ROSTER_UPDATE" then
            local d = panel and panel.Detail
            if d and d:IsShown() and d.current then UpdateShareButton(d, d.current.stepID) end
            return
        end
        if event == "QUEST_DATA_LOAD_RESULT" then
            -- The game's reward data for the quest on the page has arrived: redraw it.
            local d = panel and panel.Detail
            local c = d and d:IsShown() and d.current
            if c and arg1 == c.stepID and arg2 then ShowDetail(c.id, c.entry, c.stepOverride) end
            return
        end
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
