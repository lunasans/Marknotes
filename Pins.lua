-- Angeheftete Notizen: eine Notiz als schlankes Fenster direkt auf dem
-- Bildschirm, gerendert mit Markdown wie in der Ansicht.
--
-- Eingestellt wird in der Notiz selbst, im Kopfblock ganz oben:
--
--   ---
--   anheften: ja        pin: yes          an/aus
--   breite: 300         width: 300        Pixel, 150 bis 1000
--   höhe: 200           height: 200       Pixel; ohne: passt sich an (bis 500)
--   deckkraft: 70       opacity: 70       Hintergrund in Prozent, 0 bis 100
--   größe: 100          scale: 100        Skalierung in Prozent, 50 bis 200
--   fixieren: ja        lock: yes         nicht verschiebbar
--   titel: nein         title: no         Kopfzeile ausblenden
--   kampf: ausblenden   combat: hide      im Kampf ausblenden
--   ---
--
-- Der Text bleibt die einzige Quelle: Knopf "Anheften" und das Kreuz an
-- der angehefteten Notiz schreiben nur "anheften: ja/nein" um. Nur die
-- Stelle auf dem Bildschirm steht neben dem Text in der Notiz (note.pinPos),
-- weil man sie mit der Maus festlegt und nicht tippt.
local ADDON, ns = ...

local P = {}
ns.Pins = P
local U, W, L = ns.U, ns.W, ns.L
local MD = ns.Markdown

local HEADER   = 20     -- Höhe der Kopfzeile
local PAD      = 8      -- Innenabstand
local AUTO_MAX = 500    -- Höchsthöhe ohne "höhe"

P.frames = {}           -- Notiz-Tabelle -> Fenster
local free = {}         -- unbenutzte Fenster zum Wiederverwenden

-- ---------------------------------------------------------------- Einstellungen

local function settings(note)
    local meta = MD.Meta(note.text)
    if not meta or not MD.Bool(meta.pin, false) then return nil end

    -- "kampf: ausblenden" und "kampf: nein" heißen dasselbe.
    local combat = meta.combat
    return {
        width   = MD.Number(meta.width, 300, 150, 1000),
        height  = meta.height and MD.Number(meta.height, nil, 60, 1200),
        opacity = MD.Number(meta.opacity, 70, 0, 100) / 100,
        scale   = MD.Number(meta.scale, 100, 50, 200) / 100,
        lock    = MD.Bool(meta.lock, false),
        title   = MD.Bool(meta.title, true),
        hideInCombat = combat ~= nil and not MD.Bool(combat, true),
    }
end

-- ---------------------------------------------------------------- Fenster

local function savePlace(f)
    local point, _, relPoint, x, y = f:GetPoint()
    f.note.pinPos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function create()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    U:Skin(f, 0.7)

    local function startMove()
        if not f.settings.lock then f:StartMoving() end
    end
    local function stopMove()
        f:StopMovingOrSizing()
        savePlace(f)
    end
    f:SetScript("OnDragStart", startMove)
    f:SetScript("OnDragStop", stopMove)

    -- Kopfzeile: Titel und Kreuz zum Lösen.
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEADER)
    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints()
    head.bg:SetColorTexture(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.18)

    head.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head.title:SetPoint("LEFT", PAD, 0)
    head.title:SetPoint("RIGHT", -22, 0)
    head.title:SetJustifyH("LEFT")
    head.title:SetWordWrap(false)
    head.title:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])

    local close = CreateFrame("Button", nil, head)
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", -2, 0)
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    close.label:SetPoint("CENTER")
    close.label:SetText("×")
    close.label:SetTextColor(0.7, 0.7, 0.7)
    close:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 0.4, 0.4)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Unpin"], 1, 1, 1)
        GameTooltip:AddLine(L["Sets the note back to \"pin: no\"."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.7, 0.7, 0.7)
        GameTooltip:Hide()
    end)
    close:SetScript("OnClick", function() P:Unpin(f.note) end)

    -- Doppelklick auf die Kopfzeile öffnet die Notiz im Fenster.
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", startMove)
    head:SetScript("OnDragStop", stopMove)
    local lastClick = 0
    head:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        local now = GetTime()
        if now - lastClick < 0.4 then
            lastClick = 0
            P:Open(f.note)
        else
            lastClick = now
        end
    end)
    f.head = head

    -- Inhalt, scrollbar mit dem Mausrad. Ohne sichtbaren Rollbalken: der
    -- kostet Platz, und meist passt die Notiz ohnehin hinein.
    local view = CreateFrame("ScrollFrame", nil, f)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local to = self:GetVerticalScroll() - delta * 30
        self:SetVerticalScroll(math.max(0, math.min(range, to)))
    end)

    local content = CreateFrame("Frame", nil, view)
    content:SetSize(1, 1)
    content:EnableMouse(true)
    content:SetHyperlinksEnabled(true)
    content:RegisterForDrag("LeftButton")
    content:SetScript("OnDragStart", startMove)
    content:SetScript("OnDragStop", stopMove)
    view:SetScrollChild(content)
    view.content = content
    view.onToggle = function(line) P:ToggleCheck(f.note, line) end
    ns.Notes:LinkHandlers(content, view)
    f.view = view

    return f
end

local function acquire(note)
    local f = P.frames[note]
    if f then return f end
    f = table.remove(free) or create()
    f.note = note
    P.frames[note] = f

    local pos = note.pinPos
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        -- Neue Notizen leicht versetzt, damit sie nicht genau übereinander liegen.
        local n = 0
        for _ in pairs(P.frames) do n = n + 1 end
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260 - (n - 1) * 24, -220 - (n - 1) * 24)
    end
    return f
end

local function release(note)
    local f = P.frames[note]
    if not f then return end
    f:Hide()
    f.note = nil
    P.frames[note] = nil
    free[#free + 1] = f
end

-- Fenster nach den Einstellungen der Notiz aufbauen und Text zeichnen.
local function layout(f, cfg)
    f.settings = cfg
    f:SetScale(cfg.scale)
    pcall(f.SetBackdropColor, f, U.COLOR.bg[1], U.COLOR.bg[2], U.COLOR.bg[3], cfg.opacity)
    pcall(f.SetBackdropBorderColor, f, 0, 0, 0, cfg.opacity > 0 and 1 or 0)

    f.head:SetShown(cfg.title)
    f.head.title:SetText(ns.Notes.Label(f.note, f.index or 1))
    local top = cfg.title and (HEADER + 4) or PAD

    local inner = cfg.width - 2 * PAD
    f.view:ClearAllPoints()
    f.view:SetPoint("TOPLEFT", PAD, -top)
    f.view:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.view.content:SetWidth(inner)

    local keep = f.view:GetVerticalScroll()
    MD:Render(f.view, f.note.text or "", inner)

    local height = cfg.height
    if not height then
        height = math.min(AUTO_MAX, top + f.view.content:GetHeight() + PAD)
    end
    f:SetSize(cfg.width, height)

    f.view:UpdateScrollChildRect()
    f.view:SetVerticalScroll(math.min(keep, f.view:GetVerticalScrollRange()))
end

local function visible(cfg)
    return not (cfg.hideInCombat and P.inCombat)
end

-- ---------------------------------------------------------------- Ablauf

-- Alle Notizen durchgehen: angeheftete zeigen, alle anderen weg.
function P:Update()
    if not ns.db then return end
    local seen = {}
    for i, note in ipairs(ns.db.notes.list) do
        local cfg = settings(note)
        if cfg then
            seen[note] = true
            local f = acquire(note)
            f.index = i
            layout(f, cfg)
            f:SetShown(visible(cfg))
        end
    end
    -- Gelöst oder gelöscht.
    for note in pairs(self.frames) do
        if not seen[note] then release(note) end
    end
end

-- Beim Tippen nicht jede Taste neu zeichnen, sondern kurz danach.
function P:Schedule()
    if self.pending then return end
    self.pending = true
    C_Timer.After(0.25, function()
        P.pending = false
        P:Update()
    end)
end

function P:ToggleCheck(note, line)
    note.text = MD.ToggleCheck(note.text, line)
    note.updated = time()
    self:Update()
    ns.Notes:NoteChanged(note)
end

function P:Unpin(note)
    note.text = MD.SetPin(note.text, false, GetLocale() == "deDE")
    note.updated = time()
    self:Update()
    ns.Notes:NoteChanged(note)
end

-- Die Notiz im großen Fenster öffnen.
function P:Open(note)
    for i, n in ipairs(ns.db.notes.list) do
        if n == note then
            ns.Notes:Show()
            ns.Notes:Select(i)
            return
        end
    end
end

ns:On("PLAYER_LOGIN", function() P:Update() end)

ns:On("PLAYER_REGEN_DISABLED", function()
    P.inCombat = true
    for _, f in pairs(P.frames) do
        if f.settings.hideInCombat then f:Hide() end
    end
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    P.inCombat = false
    for _, f in pairs(P.frames) do f:Show() end
end)
