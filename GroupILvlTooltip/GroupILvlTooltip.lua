local addonName = ...
local frame = CreateFrame("Frame", addonName)
local settings

-------------------------------------------------
-- Defaults
-------------------------------------------------
local DEFAULT_THRESHOLDS = {
    { 272, "FFFF7700", "Orange" },
    { 259, "FFDC00FF", "Purple" },
    { 246, "FF0088FF", "Blue" },
    { 233, "FF00FF00", "Green" },
    { 220, "FFFFFFFF", "White" },
    { 0,   "FFAAAAAA", "Gray" },
}

-------------------------------------------------
-- Saved Variables
-------------------------------------------------
local function InitializeDB()
    if not GroupILvlTooltipDB then
        GroupILvlTooltipDB = {}
    end

    if not GroupILvlTooltipDB.thresholds then
        GroupILvlTooltipDB.thresholds = {}
    end

    if #GroupILvlTooltipDB.thresholds == 0 then
        for i, v in ipairs(DEFAULT_THRESHOLDS) do
            GroupILvlTooltipDB.thresholds[i] = { v[1], v[2], v[3] }
        end
    end
end

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

local MAX_RETRIES = 10
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
    for _, data in ipairs(GroupILvlTooltipDB.thresholds) do
        if ilvl >= data[1] then
            return data[2]
        end
    end
    return "FFFFFFFF"
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
        local unit

        if IsInRaid() then
            unit = "raid" .. i
        else
            unit = (i == num) and "player" or "party" .. i
        end

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
    if retries[guid] <= MAX_RETRIES then
        if CanSafelyInspect(unit) then
            inspecting = unit
            NotifyInspect(unit)
        else
            table.insert(inspectQueue, unit)
        end
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
        local unit

        if IsInRaid() then
            unit = "raid" .. i
        else
            unit = (i == num) and "player" or "party" .. i
        end

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

            if m.level and m.level < GetMaxPlayerLevel() then
                name = name .. " " .. m.level
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

local function gcToolTip()
    if button.tooltipTicker then
        button.tooltipTicker:Cancel()
        button.tooltipTicker = nil
    end
end

button:SetScript("OnEnter", function()
    UpdateTooltip()
    button.tooltipTicker = C_Timer.NewTicker(0.5, UpdateTooltip)
end)

button:SetScript("OnHide", function()
    gcToolTip()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
    gcToolTip()
end)




-------------------------------------------------
-- Settings Window
-------------------------------------------------
settings = CreateFrame("Frame", addonName .. "Settings", UIParent, "BackdropTemplate")
settings:SetSize(300, 280)
settings:SetPoint("CENTER")
settings:SetFrameStrata("DIALOG")
settings:SetToplevel(true)
settings:EnableMouse(true)
settings:SetMovable(true)
settings:RegisterForDrag("LeftButton")
settings:SetScript("OnDragStart", settings.StartMoving)
settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
settings:Hide()

settings:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})

CreateFrame("Button", nil, settings, "UIPanelCloseButton"):SetPoint("TOPRIGHT")

local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("iLvl Thresholds")

settings.inputs = {}

local function BuildSettingsUI()
    local labelX    = 30  -- left column
    local boxX      = 100 -- aligned edit box column
    local startY    = -50
    local rowHeight = 30

    for i, data in ipairs(GroupILvlTooltipDB.thresholds) do
        if not settings.inputs[i] then
            -- Label
            local label = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", labelX, startY - ((i - 1) * rowHeight))
            label:SetWidth(100)
            label:SetJustifyH("LEFT")
            label:SetText(data[3])

            -- EditBox
            local box = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
            box:SetSize(60, 20)
            box:SetPoint("TOPLEFT", boxX, startY - ((i - 1) * rowHeight))
            box:SetNumeric(true)
            box:SetAutoFocus(false)

            settings.inputs[i] = box
        end

        settings.inputs[i]:SetNumber(data[1])
    end
end

local saveBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
saveBtn:SetSize(100, 22)
saveBtn:SetPoint("BOTTOMLEFT", 40, 20)
saveBtn:SetText("Save")

saveBtn:SetScript("OnClick", function()
    for i, box in ipairs(settings.inputs) do
        GroupILvlTooltipDB.thresholds[i][1] = tonumber(box:GetText()) or 0
    end
    table.sort(GroupILvlTooltipDB.thresholds, function(a, b) return a[1] > b[1] end)
    settings:Hide()
end)

local resetBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
resetBtn:SetSize(100, 22)
resetBtn:SetPoint("LEFT", saveBtn, "RIGHT", 20, 0)
resetBtn:SetText("Reset")

resetBtn:SetScript("OnClick", function()
    wipe(GroupILvlTooltipDB.thresholds)
    for i, v in ipairs(DEFAULT_THRESHOLDS) do
        GroupILvlTooltipDB.thresholds[i] = { v[1], v[2], v[3] }
    end
    BuildSettingsUI()
end)


function CreateMinimapButton()
    local button = CreateFrame("Button", "GroupIlvlMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("TOPLEFT")
    button:SetFrameLevel(8)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(53, 53)
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetPoint("TOPLEFT")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(17, 17)
    button.icon:SetTexture(7549439)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function() settings:SetShown(not settings:IsShown()) end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Group Ilvl Scanner", 1, 0.82, 0)
        GameTooltip:AddLine("|cff00ff00Click|r to open settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------
-- Events
-------------------------------------------------
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeDB()
        BuildSettingsUI()
        CreateMinimapButton()
    end

    if event == "PLAYER_ENTERING_WORLD" then
        RestorePosition()
    end

    if event == "INSPECT_READY" and inspecting then
        local guid = arg1

        if UnitGUID(inspecting) == guid then
            if not ilvlCache[guid] then
                local ilvl = C_PaperDollInfo.GetInspectItemLevel(inspecting)
                if ilvl and ilvl > 0 then
                    ilvlCache[guid] = ilvl
                else
                    -- requeue inspect
                    table.insert(inspectQueue, inspecting)
                end
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
