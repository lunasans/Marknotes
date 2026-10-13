-- Grundgerüst: Events, gespeicherte Daten, Fenster, Knöpfe, Kopierfenster.
--
-- Bewusst ohne Bibliotheken. Ein Notizbuch braucht kein Ace3; jede
-- eingebettete Bibliothek wäre eine Fehlerquelle mehr bei jedem Patch.
local ADDON, ns = ...
local L = ns.L

ns.U, ns.W = {}, {}
local U, W = ns.U, ns.W

-- Leicht ins Blaue gezogen statt neutral grau: neutrales Grau wirkt neben
-- WoWs warmen Weltfarben schmutzig.
U.COLOR = {
    bg     = { 0.055, 0.062, 0.090 },
    accent = { 0.480, 0.630, 0.970 },
}
W.ACCENT = U.COLOR.accent

-- Version aus der TOC. Die Nummer setzt der Packager beim Release für
-- @project-version@ ein; eine Kopie direkt aus dem Repository trägt noch
-- den Platzhalter und heißt hier "dev".
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON, "Version")
    if not v or v == "" or v:find("@", 1, true) then v = "dev" end
    ns.version = v
    ns.author = getMeta and getMeta(ADDON, "Author") or nil
end

-- "v1.1.0 - by LunaSans-Thrall" für die kleine Zeile unten links im
-- Fenster. Beides kommt aus der TOC.
function ns:Credits()
    if self.author and self.author ~= "" then
        return self.version .. "  -  " .. L["by %s"]:format(self.author)
    end
    return self.version
end

function ns:Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cff7aa2f7Marknotes|r: " .. msg)
end

-- ---------------------------------------------------------------- Events

local handlers = {}
local dispatcher = CreateFrame("Frame")

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        dispatcher:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

dispatcher:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, event, ...)
        if not ok then ns:Print("|cffff5555Error|r in %s: %s", event, tostring(err)) end
    end
end)

-- ---------------------------------------------------------------- Daten

local DEFAULTS = {
    notes   = { list = {}, current = 1 },
    minimap = { angle = 225, hide = false },
    window  = {},   -- w, h, point, relPoint, x, y - erst nach dem ersten Ziehen
}

local function fill(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            fill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    MarknotesDB = MarknotesDB or {}
    fill(MarknotesDB, DEFAULTS)
    ns.db = MarknotesDB
end)

-- Einmalig: Notizen aus Luna Sans UI übernehmen, aus dem dieses Addon
-- hervorgegangen ist. Erst bei PLAYER_LOGIN - dann sind die
-- SavedVariables aller Addons geladen, unabhängig von der Reihenfolge.
-- Kopiert, nicht verschoben: Lunas Daten bleiben unangetastet.
ns:On("PLAYER_LOGIN", function()
    local db = ns.db
    if db.migrated then return end
    db.migrated = true

    local luna = _G.LunaSansUiDB and _G.LunaSansUiDB.notes
    if #db.notes.list == 0 and luna and type(luna.list) == "table" and #luna.list > 0 then
        db.notes.list = copy(luna.list)
        db.notes.current = luna.current or 1
        ns:Print(L["%d notes imported from Luna Sans UI."], #db.notes.list)
    end
end)

-- ---------------------------------------------------------------- Text

-- Farben, Links und Symbole entfernen. Erst den Anzeigetext aus Links
-- ziehen - danach wäre das Trennzeichen |h schon weg.
function U:StripFormatting(text)
    if not text then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    return text
end

-- ---------------------------------------------------------------- Rahmen

-- Flacher Hintergrund mit 1-Pixel-Kante.
function U:Skin(frame, alpha)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end

    local edge = 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        local ok, px = pcall(PixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
        if ok and type(px) == "number" and px > 0 then edge = px end
    end

    local ok = pcall(frame.SetBackdrop, frame, {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edge,
    })
    if not ok then return frame end

    local c = U.COLOR.bg
    pcall(frame.SetBackdropColor, frame, c[1], c[2], c[3], alpha or 0.85)
    pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 1)
    return frame
end

function W:Button(parent, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(opts.width or 170, opts.height or 24)

    U:Skin(b, 0.55)
    b:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.35)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(opts.label)
    b.label:SetTextColor(0.9, 0.9, 0.9)

    b:SetScript("OnClick", function(self, ...)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        if opts.onClick then opts.onClick(self, ...) end
    end)

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(W.ACCENT[1] * 0.45, W.ACCENT[2] * 0.45, W.ACCENT[3] * 0.5, 0.9)
        self:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1)
        self.label:SetTextColor(1, 1, 1)
        if opts.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(opts.label, 1, 1, 1)
            GameTooltip:AddLine(opts.tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)

    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.05, 0.05, 0.08, 0.55)
        self:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.35)
        self.label:SetTextColor(0.9, 0.9, 0.9)
        GameTooltip:Hide()
    end)

    return b
end

function W:Window(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    U:Skin(f, 0.96)
    pcall(f.SetBackdropBorderColor, f, W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.5)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 16, -13)
    f.title:SetText(title)
    f.title:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -36)
    line:SetPoint("TOPRIGHT", 0, -36)

    -- Schlichtes Kreuz statt rundem Blizzard-Knopf.
    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -6, -6)
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.label:SetPoint("CENTER")
    close.label:SetText("×")
    close.label:SetTextColor(0.7, 0.7, 0.7)
    close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function(self) self.label:SetTextColor(0.7, 0.7, 0.7) end)
    close:SetScript("OnClick", function() f:Hide() end)

    f.closeButton = close
    return f
end

-- Griff unten rechts zum Größe-Ändern.
--
-- opts.onStop kommt beim Loslassen, nicht während des Ziehens: wer daran
-- etwas Teures hängt, will das einmal pro Griff, nicht sechzigmal pro
-- Sekunde.
function W:MakeResizable(f, opts)
    opts = opts or {}

    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(opts.minWidth or 600, opts.minHeight or 400,
                          opts.maxWidth or 1600, opts.maxHeight or 1200)
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)

    -- Drei Striche als Griff.
    for i = 1, 3 do
        local strich = grip:CreateTexture(nil, "OVERLAY")
        strich:SetColorTexture(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.5)
        strich:SetSize(12 - (i - 1) * 4, 1)
        strich:SetPoint("BOTTOMRIGHT", -2, 2 + (i - 1) * 3)
    end

    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if opts.onStop then opts.onStop(f:GetWidth(), f:GetHeight()) end
    end)

    f.grip = grip
    return f
end

-- ---------------------------------------------------------------- Kopierfenster

-- WoW kann nichts in die Zwischenablage legen und keinen Browser öffnen.
-- Der übliche Umweg: Text markiert in ein Feld, der Spieler drückt Strg+C.
local copyFrame

function U:ShowCopyBox(title, text, width, height)
    if not copyFrame then
        local f = W:Window("MarknotesCopyBox", 560, 220, "")
        f:SetFrameStrata("DIALOG")
        tinsert(UISpecialFrames, "MarknotesCopyBox")

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -46)
        scroll:SetPoint("BOTTOMRIGHT", -30, 42)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Nur zum Kopieren da: Tippen setzt den Inhalt zurück.
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(f.rawText or "") end
        end)
        scroll:SetScrollChild(edit)

        local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", 14, 16)
        hint:SetText(L["Text is selected - press |cffffffffCtrl+C|r to copy, |cffffffffESC|r closes."])

        local selectAll = W:Button(f, {
            label = L["Select all"], width = 120, height = 22,
            onClick = function()
                edit:SetFocus()
                edit:HighlightText()
            end,
        })
        selectAll:SetPoint("BOTTOMRIGHT", -12, 10)

        f.edit = edit
        copyFrame = f
    end

    copyFrame:SetSize(width or 560, height or 220)
    copyFrame.edit:SetWidth((width or 560) - 60)
    copyFrame.title:SetText(title)
    copyFrame.rawText = text
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
    return copyFrame
end
