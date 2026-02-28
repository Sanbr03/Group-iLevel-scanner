local addonName = ...
local frame = CreateFrame("Frame", addonName)
local levelCache = {}
-------------------------------------------------
-- Saved Variables
-------------------------------------------------
GroupILvlTooltipDB = GroupILvlTooltipDB or {}

-------------------------------------------------
-- Movable Icon Button
-------------------------------------------------
local button = CreateFrame("Button", addonName .. "Button", UIParent)
button:SetSize(32, 32)
button:SetMovable(true)
button:EnableMouse(true)
button:RegisterForDrag("LeftButton")
button:SetClampedToScreen(true)
button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

local tex = button:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetTexture(7549439)
button.texture = tex
button:Hide()

button:SetScript("OnDragStart", function(self) self:StartMoving() end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    GroupILvlTooltipDB.point = p
    GroupILvlTooltipDB.relativePoint = rp
    GroupILvlTooltipDB.xOfs = x
    GroupILvlTooltipDB.yOfs = y
end)

local function RestorePosition()
    button:ClearAllPoints()
    if GroupILvlTooltipDB.point then
        button:SetPoint(
            GroupILvlTooltipDB.point,
            UIParent,
            GroupILvlTooltipDB.relativePoint,
            GroupILvlTooltipDB.xOfs,
            GroupILvlTooltipDB.yOfs
        )
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-------------------------------------------------
-- Inspect System
-------------------------------------------------
local ilvlCache = {}
local inspectQueue = {}
local inspecting = nil
local retries = {}

local MAX_RETRIES = 6
local SCAN_INTERVAL = 3

-------------------------------------------------
-- Helpers
-------------------------------------------------
local function GetClassColor(unit)
    local _, class = UnitClass(unit)
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function GetIlvlColor(ilvl)
    if ilvl >= 147 then
        return "FFFF7700"
    elseif ilvl >= 134 then
        return "FFDC00FF"
    elseif ilvl >= 121 then
        return "FF0088FF"
    elseif ilvl >= 108 then
        return "FF00FF00"
    elseif ilvl >= 95 then
        return "FFFFFFFF"
    else
        return "FFAAAAAA"
    end
end

-------------------------------------------------
-- Queue (ONLY players without ilvl)
-------------------------------------------------
local function QueueInspects()
    wipe(inspectQueue)
    wipe(retries)

    if not IsInGroup() then return end

    local prefix = IsInRaid() and "raid" or "party"
    local num = GetNumGroupMembers()

    for i = 1, num do
        local unit = (prefix == "party" and i == num and "player") or prefix .. i
        if UnitExists(unit) and unit ~= "player" then
            local guid = UnitGUID(unit)
            if guid and not ilvlCache[guid] then
                table.insert(inspectQueue, unit)
            end
        end
    end
end

-------------------------------------------------
-- Inspect Logic (combat-safe, no rescans)
-------------------------------------------------
local function CanSafelyInspect(unit)
    return not UnitIsDeadOrGhost(unit)
        and CanInspect(unit)
end

local function InspectNext()
    if inspecting or #inspectQueue == 0 then return end

    local unit = table.remove(inspectQueue, 1)
    if not UnitExists(unit) then return end

    local guid = UnitGUID(unit)
    if ilvlCache[guid] then return end

    retries[guid] = (retries[guid] or 0) + 1
    if retries[guid] > MAX_RETRIES then return end

    if CanSafelyInspect(unit) then
        inspecting = unit
        NotifyInspect(unit)
    else
        table.insert(inspectQueue, unit)
    end
end

local scanTicker
local function StartScanning()
    if scanTicker or #inspectQueue == 0 then return end
    scanTicker = C_Timer.NewTicker(SCAN_INTERVAL, InspectNext)
end

local function StopScanning()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

-------------------------------------------------
-- Tooltip
-------------------------------------------------
local function UpdateTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Group Item Levels", 1, 1, 1)
    GameTooltip:AddLine(" ")

    if not IsInGroup() then
        GameTooltip:AddLine("Not in a group", 1, 0, 0)
        GameTooltip:Show()
        return
    end

    local members = {}
    local prefix = IsInRaid() and "raid" or "party"
    local num = GetNumGroupMembers()

    for i = 1, num do
        local unit = (prefix == "party" and i == num and "player") or prefix .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            table.insert(members, {
                unit = unit,
                name = UnitName(unit),
                ilvl = ilvlCache[guid],
                level = UnitLevel(unit),
                leader = UnitIsGroupLeader(unit),
                retries = retries[guid] or 0
            })
        end
    end

    table.sort(members, function(a, b)
        return (a.ilvl or 0) > (b.ilvl or 0)
    end)

    for _, m in ipairs(members) do
        local r, g, b = GetClassColor(m.unit)
        local name = m.name

        if m.leader then
            name = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14:0:-1|t " .. name
        end

        if m.ilvl then
            local rightText = string.format("|c%s%d|r", GetIlvlColor(m.ilvl), math.floor(m.ilvl))

            if m.level and m.level < 90 then
                name = name .. " "..m.level
            end

            GameTooltip:AddDoubleLine(
                name,
                rightText,
                r, g, b, 1, 1, 1
            )
        elseif m.retries >= MAX_RETRIES then
            GameTooltip:AddDoubleLine(
                name .. " |cffff5555(Unavailable)|r",
                "",
                r, g, b, 0.8, 0.2, 0.2
            )
        else
            GameTooltip:AddDoubleLine(
                name .. " (" .. m.retries .. ")",
                "Scanning...",
                r, g, b, 0.7, 0.7, 0.7
            )
        end
    end

    GameTooltip:Show()
end

button:SetScript("OnEnter", function()
    UpdateTooltip()
    button.tooltipTicker = C_Timer.NewTicker(0.25, UpdateTooltip)
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
    if button.tooltipTicker then
        button.tooltipTicker:Cancel()
        button.tooltipTicker = nil
    end
end)

-------------------------------------------------
-- Events
-------------------------------------------------
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("INSPECT_READY")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        RestorePosition()
    end

    if event == "INSPECT_READY" and inspecting then
        local guid = UnitGUID(inspecting)
        if not ilvlCache[guid] then
            local ilvl = C_PaperDollInfo.GetInspectItemLevel(inspecting)
            if ilvl and ilvl > 0 then
                ilvlCache[guid] = ilvl
            end
        end
        ClearInspectPlayer()
        inspecting = nil
        if #inspectQueue == 0 then StopScanning() end
        return
    end

    if IsInGroup() then
        button:Show()
        ilvlCache[UnitGUID("player")] = select(2, GetAverageItemLevel())
        QueueInspects()
        StartScanning()
    else
        button:Hide()
        wipe(ilvlCache)
        wipe(inspectQueue)
        wipe(retries)
        inspecting = nil
        StopScanning()
    end
end)
