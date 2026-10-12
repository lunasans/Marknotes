-- Knopf am Minimap-Rand: Linksklick öffnet, Rechtsklick legt eine neue
-- Notiz an, Ziehen verschiebt ihn am Rand entlang.
--
-- Ohne LibDBIcon - das wären drei Bibliotheken für einen Knopf. Der Name
-- endet auf "MinimapButton", damit Knopfsammler (Luna Sans UI, MBB und
-- ähnliche) ihn erkennen und einsammeln.
local ADDON, ns = ...
local L = ns.L

local M = {}
ns.Minimap = M

local function radius()
    return (Minimap:GetWidth() / 2) + 10
end

function M:Place()
    local b = self.button
    if not b then return end
    local a = math.rad(ns.db.minimap.angle or 225)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius(), math.sin(a) * radius())
end

-- Winkel vom Kartenmittelpunkt zum Mauszeiger.
local function cursorAngle()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale  = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
end

function M:Build()
    if self.button then return self.button end

    local b = CreateFrame("Button", "MarknotesMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Aufbau wie Blizzards eigene Minimap-Knöpfe: Grund, Symbol, Ring.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.Notes:Show()
            ns.Notes:New()
        else
            ns.Notes:Toggle()
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            ns.db.minimap.angle = cursorAngle()
            M:Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Marknotes", 0.48, 0.63, 0.97)
        GameTooltip:AddLine(L["Left-click: open notes"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: new note"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move button"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = b
    self:Place()
    return b
end

function M:Toggle()
    local db = ns.db.minimap
    db.hide = not db.hide
    self:Build():SetShown(not db.hide)
    ns:Print(db.hide
        and L["Minimap button hidden - show it again with |cffffff00/notiz minimap|r."]
        or  L["Minimap button shown."])
end

ns:On("PLAYER_LOGIN", function()
    M:Build():SetShown(not ns.db.minimap.hide)
end)
