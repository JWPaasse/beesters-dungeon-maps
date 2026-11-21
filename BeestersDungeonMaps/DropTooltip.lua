local _, ns = ...

----------------------------------------------------------------------
-- "Dropped by: Boss (Dungeon)" in item tooltips, for the boss loot the dungeon maps list:
-- Bind on Pickup, Uncommon and better. Items that drop from more than a few bosses (cloth,
-- potions, world drops) get no line; the list would be longer than the tooltip.
----------------------------------------------------------------------

local MAX_SOURCES = 3
local MIN_QUALITY = 2
local BIND_ON_PICKUP = 1
local LABEL = "Dropped by:"

local sources -- [itemID] = { "Boss (Dungeon)", ... }

local function BuildIndex()
    sources = {}
    local where = {} -- [npcID] = "Boss (Dungeon)"
    local keys = {}
    for key in pairs(ns.Bosses or {}) do table.insert(keys, key) end
    table.sort(keys) -- the same boss in two wings: always the same one wins
    for _, key in ipairs(keys) do
        local dungeon = ns.Instances and ns.Instances[key] and ns.Instances[key].name or key
        for _, boss in ipairs(ns.Bosses[key]) do
            local npcID, name = boss[3], boss[2]
            if npcID and npcID > 0 and not where[npcID] then
                where[npcID] = ("%s (%s)"):format(name, dungeon)
            end
        end
    end
    for npcID, items in pairs(ns.BossLoot or {}) do
        local text = where[npcID]
        if text then
            for _, itemID in ipairs(items) do
                local list = sources[itemID]
                if not list then
                    list = {}
                    sources[itemID] = list
                end
                local seen = false
                for _, t in ipairs(list) do if t == text then seen = true end end
                if not seen then table.insert(list, text) end
            end
        end
    end
    for _, list in pairs(sources) do table.sort(list) end
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- The line for this item, or nil.
function ns.DroppedByText(itemID)
    if not itemID then return nil end
    if not sources then BuildIndex() end
    local list = sources[itemID]
    if not list or #list > MAX_SOURCES then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local name, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = getInfo(itemID)
        -- Only what the boss loot lists show; an item not loaded yet is shown, it's on a boss list.
        if name and ((quality or 0) < MIN_QUALITY or (bindType ~= nil and bindType ~= BIND_ON_PICKUP)) then
            return nil
        end
    end
    return table.concat(list, ", ")
end

local function AddLine(tooltip, itemID)
    if not ns.db or not ns.db.dropTooltip or not tooltip or not tooltip.AddLine then return end
    -- Some tooltips are filled twice (comparison, refresh): one line per item.
    if tooltip.bdmDropItem == itemID then return end
    local text = ns.DroppedByText(itemID)
    if not text then return end
    tooltip.bdmDropItem = itemID
    local n = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
    tooltip:AddLine(("|cff%02x%02x%02x%s|r %s"):format(n.r * 255, n.g * 255, n.b * 255, LABEL, text), 1, 1, 1, true)
    if tooltip.Show then tooltip:Show() end
end

local function Clear(tooltip) tooltip.bdmDropItem = nil end

function ns:InitDropTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            local itemID = data and data.id
            if not itemID and tooltip.GetItem then itemID = ItemIDFromLink(select(2, tooltip:GetItem())) end
            AddLine(tooltip, itemID)
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tooltip and tooltip.HookScript then
                tooltip:HookScript("OnTooltipSetItem", function(self)
                    AddLine(self, ItemIDFromLink(select(2, self:GetItem())))
                end)
            end
        end
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then tooltip:HookScript("OnTooltipCleared", Clear) end
    end
end
