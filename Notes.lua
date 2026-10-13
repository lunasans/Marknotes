-- Notizen mit Gegenstandslinks und Auktionshaus-Suche.
--
-- Shift-Klick auf einen Gegenstand (Taschen, Chat, Beute, Berufe ...)
-- fügt seinen Link in die Notiz ein, solange das Textfeld aktiv ist -
-- genau wie in den Chat. Ziehen und Fallenlassen geht auch. Unter dem
-- Text stehen alle verlinkten Gegenstände als Symbole: Klick sucht im
-- Auktionshaus, Shift-/Strg-Klick wie überall.
--
-- Geschrieben wird Markdown; die Lese-Ansicht stellt es dar
-- (Markdown.lua). Doppelklick in die Ansicht oder "Bearbeiten" wechselt
-- ins Textfeld, Esc zurück.
--
-- Gespeichert wird kontoweit in MarknotesDB.notes: eine Einkaufsliste
-- gilt für alle Charaktere.
--
-- Hervorgegangen aus Modules\Notes.lua in Luna Sans UI; Änderungen an
-- Werkzeugleiste und Ansicht dort mitziehen.
local ADDON, ns = ...

local M = {}
ns.Notes = M
local U = ns.U
local W = ns.W
local L = ns.L

-- Startgröße und zugleich Mindestbreite: schmaler passt die Werkzeugleiste
-- nicht mehr in eine Zeile.
local WIDTH, HEIGHT = 800, 520
local MIN_HEIGHT    = 440
local LIST          = 180     -- Breite der Notizliste links
local ICON, GAP     = 30, 4   -- Gegenstandssymbole unten
local ITEMS_H       = 92      -- Höhe des Bereichs mit den Symbolen

-- ---------------------------------------------------------------- Daten

local function store()
    return ns.db.notes
end

function M:Current()
    local s = store()
    return s.list[s.current]
end

local function labelFor(note, index)
    if note.title and note.title:match("%S") then return note.title end
    -- Sonst die erste Zeile, ohne Links und Farbcodes.
    local first = (note.text or ""):match("^[^\n]*") or ""
    first = U:StripFormatting(first):gsub("^%s+", "")
    if first ~= "" then return first end
    return L["Note %d"]:format(index)
end

local function isEmpty(note)
    return note and not (note.title or ""):match("%S")
                and not (note.text or ""):match("%S")
end

-- Eine leere aktuelle Notiz wird weiterbenutzt: sonst legt jeder Klick
-- auf "Neue Notiz" eine weitere leere an, und die Liste läuft voll.
function M:New()
    local s = store()
    if not isEmpty(s.list[s.current]) then
        s.list[#s.list + 1] = { title = "", text = "", updated = time() }
        s.current = #s.list
    end
    self:Refresh()
    self.frame.titleBox:SetFocus()
end

function M:Delete()
    local s = store()
    if not s.list[s.current] then return end
    table.remove(s.list, s.current)
    s.current = math.max(1, math.min(s.current, #s.list))
    self:Refresh()
end

function M:Select(index)
    store().current = index
    self:Refresh()
end

-- ---------------------------------------------------------------- Links

-- Alle Gegenstandslinks einer Notiz, ohne Doppelte.
--
-- Der volle Link (mit Farbe) wird zum Weitergeben gebraucht, der nackte
-- "item:..."-Teil für den Tooltip, der Name für die Suche. Die Farbe
-- steht seit 11.x auch als |cnIQ4: im Text, deshalb [^|]* statt %x+.
local function itemsIn(text)
    local out, seen, pos = {}, {}, 1
    while true do
        local a, b, hyper, name = text:find("|H(item:[^|]+)|h%[(.-)%]|h", pos)
        if not a then break end
        pos = b + 1

        if not seen[hyper] then
            seen[hyper] = true
            local color = text:sub(1, a - 1):match("(|c[^|]*)$") or ""
            local full  = color .. "|H" .. hyper .. "|h[" .. name .. "]|h"
                       .. (color ~= "" and "|r" or "")
            -- Qualitätsstufen der Berufe stecken als Symbol im Namen.
            local plain = name:gsub("|A.-|a", ""):gsub("|T.-|t", "")
            plain = plain:gsub("^%s+", ""):gsub("%s+$", "")

            out[#out + 1] = {
                link  = full,
                hyper = hyper,
                id    = tonumber(hyper:match("^item:(%d+)")),
                name  = plain,
            }
        end
    end
    return out
end

-- Shift-Klick landet über Blizzards Link-Weiterleitung hier. Mehrere
-- Wege führen zum selben Klick (HandleModifiedItemClick ruft
-- ChatEdit_InsertLink), deshalb pro Bild nur einmal einfügen.
local lastLink, lastTime

-- Shift-Klick fügt ein, sobald das Fenster offen ist - auch aus der
-- Ansicht heraus, ohne vorher ins Textfeld zu klicken. Hat ein anderes
-- Eingabefeld den Cursor (Chat, Auktionshaus-Suche, andere Addons),
-- gehört der Link dorthin.
local function capture(link)
    local f = M.frame
    if not link or not f or not f:IsShown() or M.ownClick then return end

    local now = GetTime()
    if link == lastLink and now == lastTime then return end
    lastLink, lastTime = link, now

    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()

    -- Eingabefenster "Gegenstand einfügen" offen: der Klick ist die Antwort.
    if focus and M.prompt and focus == M.prompt.box then
        M.prompt:Hide()
        M:InsertItem(link)
        return
    end
    if focus and focus ~= f.edit then return end

    if not f.edit:HasFocus() then
        -- Ohne Cursor im Text: ans Ende, mit Abstand zum Vorherigen.
        M:SetMode("edit")
        f.edit:SetCursorPosition(#f.edit:GetText())
        local text = f.edit:GetText()
        if text ~= "" and not text:match("%s$") then f.edit:Insert(" ") end
    end

    f.edit:Insert(link)
    M:SaveText()
end

-- Eigene Shift-Klicks (Gegenstandsleiste, Links in der Ansicht) laufen
-- über dieselbe Blizzard-Funktion - ohne Sperre landete der Link sofort
-- ein zweites Mal in der Notiz.
local function ownModifiedClick(link)
    M.ownClick = true
    pcall(HandleModifiedItemClick, link)
    M.ownClick = false
end

function M:HookLinks()
    if self.linksHooked then return end
    self.linksHooked = true

    if _G.ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", capture)
    end
    if _G.ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", capture)
    end
    if _G.HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if IsModifiedClick("CHATLINK") then capture(link) end
        end)
    end
end

-- Gegenstand aus der Tasche ins Textfeld ziehen.
local function dropFromCursor(edit)
    local kind, _, link = GetCursorInfo()
    if kind == "item" and link then
        ClearCursor()
        edit:SetFocus()
        edit:Insert(link)
        M:SaveText()
    end
end

-- ---------------------------------------------------------------- Auktionshaus

-- Name in Anführungszeichen: das Auktionshaus sucht dann genau diesen
-- Namen statt aller, die ihn enthalten.
function M:SearchAH(item)
    local ah = _G.AuctionHouseFrame
    if not (ah and ah:IsShown()) then
        ns:Print(L["Open the Auction House first to search."])
        return
    end

    local bar = ah.SearchBar
    if not (bar and bar.SearchBox) then return end

    -- Auf dem Verkaufen-Reiter ist die Suchleiste nicht da.
    if not bar:IsVisible() and ah.SetDisplayMode and _G.AuctionHouseFrameDisplayMode then
        pcall(ah.SetDisplayMode, ah, AuctionHouseFrameDisplayMode.Buy)
    end

    bar.SearchBox:SetText('"' .. item.name .. '"')
    if not (bar.StartSearch and pcall(bar.StartSearch, bar)) then
        ns:Print(L["Search term entered - press Enter to search."])
    end
end

function M:HookAuctionHouse()
    local ah = _G.AuctionHouseFrame
    if not ah or self.ahButton then return end

    local b = W:Button(ah, {
        label = L["Notes"], width = 90, height = 22,
        tooltip = L["Open Marknotes next to the Auction House."],
        onClick = function()
            local f = M:Build()
            if f:IsShown() then f:Hide() return end
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
            M:Show()
        end,
    })
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 4)
    self.ahButton = b
end

-- ---------------------------------------------------------------- Werkzeugleiste

-- Ob die EditBox Cursor-Positionen in Bytes oder in Zeichen zählt, ist
-- nirgends dokumentiert - bei Umlauten macht es den Unterschied. Statt zu
-- raten wird gemessen: Cursor ans Ende, Position mit der Bytelänge
-- vergleichen. Alles hier rechnet in Bytes und übersetzt nur an der
-- Schnittstelle zur EditBox.
local function countsBytes(edit, text)
    if not text:find("[\128-\255]") then return true end   -- egal: nur ASCII
    local keep = edit:GetCursorPosition()
    edit:SetCursorPosition(#text + 10)
    local max = edit:GetCursorPosition()
    edit:SetCursorPosition(keep)
    return max >= #text
end

local function charsToBytes(s, n)
    local count, i = 0, 1
    while count < n and i <= #s do
        local c = s:byte(i)
        i = i + ((c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1)
        count = count + 1
    end
    return i - 1
end

local function bytesToChars(s, b)
    local _, n = s:sub(1, b):gsub("[^\128-\191]", "")
    return n
end

-- Text, Cursor als Byte-Position.
local function cursorBytes(edit)
    local text = edit:GetText()
    local cur  = edit:GetCursorPosition()
    if not countsBytes(edit, text) then cur = charsToBytes(text, cur) end
    return text, math.min(cur, #text)
end

-- Neuen Text setzen und den Bereich [from, to) (Bytes) markieren - so
-- überschreibt das nächste Tippen den Platzhalter.
local function applyEdit(edit, text, from, to)
    edit:SetText(text)
    edit:SetFocus()
    if not countsBytes(edit, text) then
        from, to = bytesToChars(text, from), bytesToChars(text, to)
    end
    edit:SetCursorPosition(to)
    if to > from then edit:HighlightText(from, to) end
    M:SaveText()
end

-- Text um den Cursor legen: **Platzhalter**, Platzhalter markiert.
function M:Wrap(before, after, placeholder)
    local edit = self.frame.edit
    local text, cur = cursorBytes(edit)
    local head, tail = text:sub(1, cur), text:sub(cur + 1)
    local from = #head + #before
    applyEdit(edit, head .. before .. placeholder .. after .. tail,
              from, from + #placeholder)
end

-- Vorhandene Zeilenanfänge, die einander ersetzen: aus einer Liste wird
-- eine Checkbox, nicht "- [ ] - Punkt".
local PREFIXES = {
    "^#+%s+", "^[%-%*%+]%s+%[[ xX]%]%s*", "^[%-%*%+]%s+", "^%d+[%.%)]%s+", "^>%s?",
}

-- Zeilenanfang der aktuellen Zeile setzen. Derselbe Knopf nochmal nimmt
-- ihn wieder weg.
function M:LinePrefix(prefix)
    local edit = self.frame.edit
    local text, cur = cursorBytes(edit)

    local lineStart = 0
    for pos in text:sub(1, cur):gmatch("()\n") do lineStart = pos end
    local lineEnd = text:find("\n", cur + 1, true)
    lineEnd = lineEnd and lineEnd - 1 or #text

    local line = text:sub(lineStart + 1, lineEnd)
    local ind, body = line:match("^(%s*)(.*)$")

    local existing = ""
    for _, pattern in ipairs(PREFIXES) do
        local found = body:match(pattern)
        if found then
            existing = found
            body = body:sub(#found + 1)
            break
        end
    end

    -- Überschriften stehen immer ganz links.
    if prefix:match("^#") then ind = "" end

    local newLine
    if existing:gsub("%s+$", "") == prefix:gsub("%s+$", "") then
        newLine = ind .. body
    else
        newLine = ind .. prefix .. body
    end

    local result = text:sub(1, lineStart) .. newLine .. text:sub(lineEnd + 1)
    local at = lineStart + #newLine
    applyEdit(edit, result, at, at)
end

-- Block auf eigene Zeilen setzen (Tabelle, Codeblock, Linie). selFrom
-- und selLen markieren darin den Platzhalter.
function M:InsertBlock(block, selFrom, selLen)
    local edit = self.frame.edit
    local text, cur = cursorBytes(edit)
    local head, tail = text:sub(1, cur), text:sub(cur + 1)

    local pre  = (head ~= "" and not head:match("\n$")) and "\n" or ""
    local post = (tail ~= "" and not tail:match("^\n")) and "\n" or ""

    local from = #head + #pre + (selFrom or #block)
    applyEdit(edit, head .. pre .. block .. post .. tail, from, from + (selLen or 0))
end

local COL1, COL2 = L["Column 1"], L["Column 2"]
local TABLE = "| " .. COL1 .. " | " .. COL2 .. " |\n|---|---|\n|  |  |"

-- Knöpfe: Beschriftung, Tooltip, Aktion. false = etwas Abstand.
local TOOLS = {
    { "H1", L["Heading 1"], function() M:LinePrefix("# ") end },
    { "H2", L["Heading 2"], function() M:LinePrefix("## ") end },
    { "H3", L["Heading 3"], function() M:LinePrefix("### ") end },
    false,
    { "|cffffffff" .. L["B"] .. "|r", L["Bold  **Text**"], function() M:Wrap("**", "**", "Text") end },
    { "|cffb4bed2" .. L["I"] .. "|r", L["Italic  *Text*"], function() M:Wrap("*", "*", "Text") end },
    { "|cff808080S|r", L["Strikethrough  ~~Text~~"], function() M:Wrap("~~", "~~", "Text") end },
    { "|cffe6b464Code|r", L["Inline code  `Text`"], function() M:Wrap("`", "`", "Code") end },
    false,
    { L["List"], L["Bullet list  - Item"], function() M:LinePrefix("- ") end },
    { "1.", L["Numbered list  1. Item"], function() M:LinePrefix("1. ") end },
    { "[ ]", L["Checkbox  - [ ] Item\nTick it off in the preview with a click."],
      function() M:LinePrefix("- [ ] ") end },
    { L["Quote"], L["Quote  > Text"], function() M:LinePrefix("> ") end },
    false,
    { "Link", L["Link  [Text](https://...)\nIn the preview a click copies the address."],
      function() M:Wrap("[", "](https://)", "Text") end },
    { L["Table"], L["Table with header row\n:--- / :---: / ---: aligns columns."],
      function() M:InsertBlock(TABLE, 2, #COL1) end },
    { "Block", L["Code block  ``` ... ```"], function() M:InsertBlock("```\n\n```", 4, 0) end },
    { L["Rule"], L["Horizontal rule  ---"], function() M:InsertBlock("---") end },
    false,
    { ns.Markdown.MarkerIcon(1, 14), L["Raid marker  {star} {skull} ...\nLike in chat. English, German or {rt1} to {rt8}."],
      function(btn) M:MarkerMenu(btn) end },
}

-- Auswahl der acht Zielmarkierungen unter dem Knopf. Hängt an der
-- Werkzeugleiste und verschwindet mit ihr.
function M:MarkerMenu(btn)
    local menu = self.markerMenu
    if not menu then
        menu = U:Skin(CreateFrame("Frame", nil, self.frame.toolbar), 0.95)
        menu:SetFrameLevel(self.frame.toolbar:GetFrameLevel() + 30)
        menu:SetSize(8 * 24 + 6, 30)
        local names = GetLocale() == "deDE" and ns.Markdown.MARKER_NAMES_DE
                      or ns.Markdown.MARKER_NAMES_EN
        for i = 1, 8 do
            local b = CreateFrame("Button", nil, menu)
            b:SetSize(22, 22)
            b:SetPoint("LEFT", 4 + (i - 1) * 24, 0)
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
            b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.2)
            local tag = "{" .. names[i] .. "}"
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(tag, 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function()
                menu:Hide()
                M:Wrap(tag, "", "")
            end)
        end
        menu:Hide()
        self.markerMenu = menu
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    menu:SetShown(not menu:IsShown())
end

function M:BuildToolbar(f, left)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", left, -80)
    bar:SetPoint("TOPRIGHT", -18, -80)
    bar:SetHeight(22)

    local x = 0
    for _, tool in ipairs(TOOLS) do
        if tool then
            local b = W:Button(bar, { label = tool[1], width = 30, height = 22, y = 0,
                                      tooltip = tool[2], onClick = tool[3] })
            b:SetWidth(math.max(24, math.ceil(b.label:GetStringWidth()) + 14))
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            x = x + b:GetWidth() + 2
        else
            x = x + 6
        end
    end

    bar:Hide()
    return bar
end

-- ---------------------------------------------------------------- Fenster

local function skinInput(box)
    local back = U:Skin(CreateFrame("Frame", nil, box), 0.6)
    back:SetPoint("TOPLEFT", -4, 2)
    back:SetPoint("BOTTOMRIGHT", 4, -2)
    back:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
    return back
end

function M:Build()
    if self.frame then return self.frame end

    local f = W:Window("MarknotesFrame", WIDTH, HEIGHT, "Marknotes")
    tinsert(UISpecialFrames, "MarknotesFrame")

    -- Gemerkte Größe und Stelle. Vor dem Aufbau des Inhalts, damit der
    -- gleich in der richtigen Breite entsteht.
    local win = ns.db.window
    if win.w and win.h then
        f:SetSize(math.max(WIDTH, win.w), math.max(MIN_HEIGHT, win.h))
    end
    if win.point then
        f:ClearAllPoints()
        f:SetPoint(win.point, UIParent, win.relPoint, win.x, win.y)
    end

    -- Liste links, wie die Kategorien im Einstellungsfenster.
    local side = f:CreateTexture(nil, "BACKGROUND")
    side:SetColorTexture(0, 0, 0, 0.35)
    side:SetPoint("TOPLEFT", 1, -37)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(LIST)

    f.rows = {}

    local new = W:Button(f, { label = L["New note"], width = LIST - 20, height = 22,
                              onClick = function() M:New() end })
    new:ClearAllPoints()
    new:SetPoint("BOTTOMLEFT", 10, 40)

    local del = W:Button(f, { label = L["Delete"], width = LIST - 20, height = 22,
                              onClick = function()
                                  if M:Current() then StaticPopup_Show("MARKNOTES_DELETE") end
                              end })
    del:ClearAllPoints()
    del:SetPoint("BOTTOMLEFT", 10, 12)

    -- Rechts: Titel, Text, Gegenstände.
    local left = LIST + 20

    local titleBox = CreateFrame("EditBox", nil, f)
    titleBox:SetPoint("TOPLEFT", left, -50)
    titleBox:SetPoint("TOPRIGHT", -112, -50)
    titleBox:SetHeight(22)
    titleBox:SetAutoFocus(false)
    titleBox:SetFontObject(ChatFontNormal)
    titleBox:SetTextInsets(4, 4, 0, 0)
    skinInput(titleBox)
    titleBox.placeholder = titleBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    titleBox.placeholder:SetPoint("LEFT", 6, 0)
    titleBox.placeholder:SetText(L["Title"])
    titleBox:SetScript("OnTextChanged", function(self, userInput)
        self.placeholder:SetShown(self:GetText() == "")
        local note = M:Current()
        if userInput and note then
            note.title = self:GetText()
            note.updated = time()
            M:RefreshList()
        end
    end)
    titleBox:SetScript("OnEnterPressed", function() f.edit:SetFocus() end)
    titleBox:SetScript("OnEscapePressed", titleBox.ClearFocus)
    f.titleBox = titleBox

    -- Umschalter Lesen / Bearbeiten.
    local mode = W:Button(f, { label = L["Edit"], width = 86, height = 22,
                               onClick = function()
                                   M:SetMode(M.mode == "read" and "edit" or "read")
                               end })
    mode:ClearAllPoints()
    mode:SetPoint("TOPRIGHT", -18, -50)
    f.modeButton = mode

    -- Markdown-Knöpfe, nur beim Bearbeiten. Das Textfeld rückt dafür
    -- eine Zeile nach unten; die Ansicht braucht sie nicht.
    f.toolbar = self:BuildToolbar(f, left)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, -112)
    scroll:SetPoint("BOTTOMRIGHT", -32, ITEMS_H + 12)
    skinInput(scroll)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(f:GetWidth() - left - 50)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        M:SetMode("read")
    end)
    edit:SetScript("OnTextChanged", function(_, userInput)
        if userInput then M:SaveText() end
    end)
    -- Der Cursor soll beim Tippen im Bild bleiben.
    if _G.ScrollingEdit_OnCursorChanged then
        edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        edit:SetScript("OnUpdate", function(self, elapsed)
            ScrollingEdit_OnUpdate(self, elapsed, scroll)
        end)
    end
    edit:SetScript("OnReceiveDrag", dropFromCursor)
    edit:SetScript("OnMouseDown", function(self)
        if GetCursorInfo() then dropFromCursor(self) end
    end)
    scroll:SetScrollChild(edit)

    -- Ein Klick irgendwo in die Fläche setzt den Cursor, nicht nur auf
    -- die bereits beschriebenen Zeilen.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        edit:SetFocus()
        edit:SetCursorPosition(#edit:GetText())
    end)
    f.edit, f.scroll = edit, scroll

    -- Lese-Ansicht: an derselben Stelle wie das Textfeld, es ist immer
    -- nur eins von beiden zu sehen.
    local view = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    view:SetPoint("TOPLEFT", left, -86)
    view:SetPoint("BOTTOMRIGHT", -32, ITEMS_H + 12)
    skinInput(view)

    local content = CreateFrame("Frame", nil, view)
    content:SetSize(f:GetWidth() - left - 50, 1)
    content:EnableMouse(true)
    content:SetHyperlinksEnabled(true)
    view:SetScrollChild(content)
    view.content = content
    view:Hide()

    content:SetScript("OnHyperlinkEnter", function(self, link)
        view.overLink = true
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local url = link:match("^url:(.+)$")
        if url then
            GameTooltip:AddLine(url, 1, 1, 1, true)
            GameTooltip:AddLine(L["Click: copy address"], 0.48, 0.63, 0.97)
        else
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if link:match("^item:") then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click: search the Auction House"], 0.48, 0.63, 0.97)
            end
        end
        GameTooltip:Show()
    end)
    content:SetScript("OnHyperlinkLeave", function()
        view.overLink = false
        GameTooltip:Hide()
    end)
    content:SetScript("OnHyperlinkClick", function(_, link, text, button)
        local url = link:match("^url:(.+)$")
        if url then
            -- Einen Browser kann ein Addon nicht öffnen.
            U:ShowCopyBox(L["Copy link"], url, 560, 140)
        elseif link:match("^item:") then
            if IsModifiedClick() then
                ownModifiedClick(text)
            else
                local item = itemsIn(text)[1]
                if item then M:SearchAH(item) end
            end
        else
            pcall(SetItemRef, link, text, button)
        end
    end)

    -- Doppelklick in die Ansicht (nicht auf einen Link) öffnet das
    -- Textfeld. Ein einfacher Klick nicht: wer liest, klickt auch mal
    -- nur, um das Fenster nach vorn zu holen. Ein Frame kennt kein
    -- OnDoubleClick, deshalb zählt der Abstand zwischen zwei Klicks.
    local lastClick = 0
    local function toEdit(_, button)
        if button ~= "LeftButton" or view.overLink then return end
        local now = GetTime()
        if now - lastClick < 0.4 then
            lastClick = 0
            M:SetMode("edit")
        else
            lastClick = now
        end
    end
    content:SetScript("OnMouseUp", toEdit)
    view:EnableMouse(true)
    view:SetScript("OnMouseUp", toEdit)
    content:SetScript("OnReceiveDrag", function()
        M:SetMode("edit")
        dropFromCursor(edit)
    end)

    view.onToggle = function(line) M:ToggleCheck(line) end
    f.view = view

    -- Gegenstände dieser Notiz.
    local items = CreateFrame("Frame", nil, f)
    items:SetPoint("BOTTOMLEFT", left, 12)
    items:SetPoint("BOTTOMRIGHT", -18, 12)
    items:SetHeight(ITEMS_H - 6)

    items.label = items:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    items.label:SetPoint("TOPLEFT", 0, 0)
    items.buttons = {}
    f.items = items

    local add = W:Button(items, { label = L["+ Item"], width = 100, height = 18,
                                  tooltip = L["Insert an item by name, item ID or Wowhead link.\nShift-clicking an item works too."],
                                  onClick = function() M:ItemPrompt() end })
    add:SetWidth(math.ceil(add.label:GetStringWidth()) + 18)
    add:ClearAllPoints()
    add:SetPoint("TOPRIGHT", 0, 3)

    -- Größe ändern und Stelle merken.
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        M:SavePlace()
    end)
    W:MakeResizable(f, {
        minWidth = WIDTH, minHeight = MIN_HEIGHT,
        onStop = function() M:SavePlace() end,
    })
    f:SetScript("OnSizeChanged", function() M:Relayout() end)

    self.frame = f
    self:HookLinks()
    return f
end

function M:SavePlace()
    local f, win = self.frame, ns.db.window
    local point, _, relPoint, x, y = f:GetPoint()
    win.point, win.relPoint, win.x, win.y = point, relPoint, x, y
    win.w, win.h = f:GetSize()
end

-- Inhalt an die Fenstergröße anpassen.
--
-- Breiten und Liste sofort, damit beim Ziehen nichts überlappt. Die
-- Ansicht erst kurz nach dem letzten Größenwechsel: Tabellen messen jede
-- Zelle neu, und das soll nicht in jedem Bild des Ziehens passieren.
function M:Relayout()
    local f = self.frame
    if not f then return end

    local inner = f:GetWidth() - (LIST + 20) - 50
    f.edit:SetWidth(inner)
    f.view.content:SetWidth(inner)
    self:RefreshList()
    self:RefreshItems()

    if self.relayoutPending then return end
    self.relayoutPending = true
    C_Timer.After(0.1, function()
        M.relayoutPending = false
        if M.mode == "read" and f:IsShown() then M:RenderView() end
    end)
end

-- Text der aktuellen Notiz sichern. Läuft bei jeder Eingabe; die Liste
-- der Gegenstände zieht gleich mit.
function M:SaveText()
    local note = self:Current()
    if not note or not self.frame then return end
    note.text = self.frame.edit:GetText()
    note.updated = time()
    self:RefreshItems()
    self:RefreshList()
end

-- Lese-Ansicht neu zeichnen. Die Scrollstelle bleibt, damit ein
-- abgehakter Punkt unten in einer langen Liste nicht nach oben springt.
function M:RenderView()
    local f = self.frame
    local note = self:Current()
    local keep = f.view:GetVerticalScroll()
    ns.Markdown:Render(f.view, note and note.text or "", f.view.content:GetWidth())
    f.view:UpdateScrollChildRect()
    f.view:SetVerticalScroll(math.min(keep, f.view:GetVerticalScrollRange()))
end

-- "read" zeigt die gerenderte Notiz, "edit" das Textfeld.
function M:SetMode(mode, noFocus)
    local f = self.frame
    if not f then return end
    self.mode = mode

    if mode == "read" then
        f.edit:ClearFocus()
        self:RenderView()
        f.scroll:Hide()
        f.toolbar:Hide()
        f.view:Show()
        f.modeButton.label:SetText(L["Edit"])
    else
        f.view:Hide()
        f.scroll:Show()
        f.toolbar:Show()
        f.modeButton.label:SetText(L["Preview"])
        if not noFocus then f.edit:SetFocus() end
    end
end

-- Checkbox in der Ansicht abgehakt: in den Text zurückschreiben.
function M:ToggleCheck(line)
    local note = self:Current()
    if not note then return end
    note.text = ns.Markdown.ToggleCheck(note.text, line)
    note.updated = time()
    self.frame.edit:SetText(note.text)
    self:RenderView()
end

function M:RefreshList()
    local f = self.frame
    local s = store()

    for i, note in ipairs(s.list) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Button", nil, f)
            row:SetSize(LIST - 2, 24)
            row:SetPoint("TOPLEFT", 1, -44 - (i - 1) * 25)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(1, 1, 1, 0.06)

            row.marker = row:CreateTexture(nil, "ARTWORK")
            row.marker:SetColorTexture(unpack(W.ACCENT))
            row.marker:SetWidth(3)
            row.marker:SetPoint("TOPLEFT")
            row.marker:SetPoint("BOTTOMLEFT")

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 12, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)

            row:SetScript("OnClick", function(self) M:Select(self.index) end)
            f.rows[i] = row
        end

        local active = (i == s.current)
        row.index = i
        row.label:SetText(labelFor(note, i))
        row.label:SetTextColor(active and 1 or 0.75, active and 1 or 0.75, active and 1 or 0.75)
        row.bg:SetShown(active)
        row.marker:SetShown(active)
        -- Mehr Notizen als Platz: die übrigen werden ausgeblendet. Für
        -- eine Notizliste reicht das; zwölf passen untereinander.
        row:SetShown(-44 - i * 25 > -(f:GetHeight() - 80))
    end
    for i = #s.list + 1, #f.rows do f.rows[i]:Hide() end
end

function M:RefreshItems()
    local f = self.frame
    local box = f.items
    local note = self:Current()
    local list = itemsIn(note and note.text or "")

    box.label:SetText(#list > 0
        and L["Items - click to search the Auction House"]
        or  L["Shift-click an item to insert it."])

    -- Aus der Fenstergröße, nicht aus box:GetWidth(): beim ersten
    -- Öffnen hat der Bereich noch keine Breite.
    local width  = f:GetWidth() - (LIST + 20) - 18
    local perRow = math.max(1, math.floor((width + GAP) / (ICON + GAP)))

    for i, item in ipairs(list) do
        local b = box.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, box)
            b:SetSize(ICON, ICON)
            U:Skin(b, 0.6)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)

            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.hyper)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Click: search the Auction House"], 0.48, 0.63, 0.97)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                -- Sonst landet ein Shift-Klick über capture wieder in
                -- der eigenen Notiz.
                f.edit:ClearFocus()
                if IsModifiedClick() then
                    ownModifiedClick(self.item.link)
                else
                    M:SearchAH(self.item)
                end
            end)
            box.buttons[i] = b
        end

        b.item = item
        b.icon:SetTexture(item.id and C_Item.GetItemIconByID(item.id) or 134400)

        local quality = item.id and C_Item.GetItemQualityByID(item.id)
        local r, g, bl = 0, 0, 0
        if quality and quality > 1 then r, g, bl = C_Item.GetItemQualityColor(quality) end
        b:SetBackdropBorderColor(r, g, bl, 1)

        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", col * (ICON + GAP), -16 - row * (ICON + GAP))
        b:SetShown(row < 2)
    end
    for i = #list + 1, #box.buttons do box.buttons[i]:Hide() end
end

-- ---------------------------------------------------------------- Gegenstand einfügen

-- Eingabe in einen Gegenstandslink übersetzen. done(link) oder done(nil).
--
-- Reihenfolge: fertiger Link > Item-ID oder Wowhead-Adresse > Name. Ein
-- Name lässt sich nur finden, wenn das Spiel den Gegenstand kennt - in
-- Taschen, Ausrüstung oder kürzlich gesehen (Cache). Eine Suche über
-- alle Gegenstände gibt es für Addons nicht.
local function findItem(query, done)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return done(nil) end

    if query:find("|Hitem:", 1, true) then return done(query) end

    local id = tonumber(query) or tonumber(query:match("item[=:/](%d+)"))
    if id then
        if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then
            return done(nil)
        end
        local item = Item:CreateFromItemID(id)
        item:ContinueOnItemLoad(function() done(item:GetItemLink()) end)
        return
    end

    local wanted, partial = query:lower(), nil
    local function check(link)
        if not link then return false end
        local name = (link:match("|h%[(.-)%]|h") or ""):gsub("|A.-|a", ""):gsub("%s+$", ""):lower()
        if name == wanted then done(link) return true end
        if not partial and name:find(wanted, 1, true) then partial = link end
        return false
    end

    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and check(info.hyperlink) then return end
        end
    end
    for slot = 1, 19 do
        if check(GetInventoryItemLink("player", slot)) then return end
    end
    if partial then return done(partial) end

    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = getInfo(query)
    done(link)
end
M.FindItem = findItem

-- Link an der Stelle einfügen, an der der Cursor vor dem Eingabefenster
-- stand - ohne Cursor (aus der Ansicht) ans Ende.
function M:InsertItem(link)
    local f = self.frame
    local text = f.edit:GetText()
    local at = self.promptCursor
    if not at or at > #text then at = #text end

    local before = text:sub(1, at)
    local pre = (before ~= "" and not before:match("%s$")) and " " or ""

    self:SetMode("edit", true)
    local pos = at + #pre + #link
    applyEdit(f.edit, before .. pre .. link .. text:sub(at + 1), pos, pos)
end

function M:ItemPrompt()
    local f = self:Build()

    self.promptCursor = nil
    if self.mode == "edit" then
        local _, cur = cursorBytes(f.edit)
        self.promptCursor = cur
    end

    local p = self.prompt
    if not p then
        p = W:Window("MarknotesItemPrompt", 400, 116, L["Insert item"])
        p:SetFrameStrata("DIALOG")
        tinsert(UISpecialFrames, "MarknotesItemPrompt")

        local box = CreateFrame("EditBox", nil, p)
        box:SetPoint("TOPLEFT", 18, -52)
        box:SetPoint("TOPRIGHT", -18, -52)
        box:SetHeight(22)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal)
        box:SetTextInsets(4, 4, 0, 0)
        skinInput(box)

        p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p.hint:SetPoint("BOTTOMLEFT", 18, 16)
        p.hint:SetPoint("BOTTOMRIGHT", -18, 16)
        p.hint:SetJustifyH("LEFT")

        box:SetScript("OnEnterPressed", function(self)
            findItem(self:GetText(), function(link)
                if link then
                    p:Hide()
                    M:InsertItem(link)
                else
                    p.hint:SetText("|cffff6666" .. L["Not found - try the item ID or a Wowhead link."] .. "|r")
                end
            end)
        end)
        box:SetScript("OnEscapePressed", function() p:Hide() end)

        p.box = box
        self.prompt = p
    end

    p.hint:SetText(L["Item name (from bags or equipment), item ID or Wowhead link"])
    p.box:SetText("")
    p:ClearAllPoints()
    p:SetPoint("TOP", f, "TOP", 0, -120)
    p:Show()
    p.box:SetFocus()
end

-- Alles auf die aktuelle Notiz einstellen.
function M:Refresh()
    local f = self.frame
    if not f then return end

    local s = store()
    if #s.list == 0 then
        s.list[1] = { title = "", text = "", updated = time() }
        s.current = 1
    end

    local note = self:Current()
    f.titleBox:SetText(note.title or "")
    f.edit:SetText(note.text or "")
    f.edit:SetCursorPosition(0)
    f.scroll:SetVerticalScroll(0)
    f.view:SetVerticalScroll(0)

    -- Mit Inhalt zum Lesen öffnen, leer gleich zum Schreiben.
    self:SetMode((note.text or ""):match("%S") and "read" or "edit", true)

    self:RefreshList()
    self:RefreshItems()
end

-- anchor: optional ein Fenster, neben dem die Notizen erscheinen sollen.
function M:Show(anchor)
    local f = self:Build()
    if anchor then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    end
    f:Show()
    self:Refresh()
    return f
end

function M:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end

-- ---------------------------------------------------------------- Ablauf

StaticPopupDialogs["MARKNOTES_DELETE"] = {
    text         = L["Delete this note?"],
    button1      = L["Delete"],
    button2      = CANCEL,
    OnAccept     = function() M:Delete() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

ns:On("PLAYER_LOGIN", function()
    -- Das Auktionshaus lädt erst beim ersten Besuch.
    M:HookAuctionHouse()
end)

ns:On("ADDON_LOADED", function(_, addon)
    if addon == "Blizzard_AuctionHouseUI" then M:HookAuctionHouse() end
end)

-- Öffentliche Schnittstelle für andere Addons (Luna Sans UI leitet seine
-- Notizen hierher, sobald Marknotes geladen ist).
Marknotes = {
    Show   = function(_, anchor) return M:Show(anchor) end,
    Toggle = function() M:Toggle() end,
    New    = function(_, anchor) M:Show(anchor); M:New() end,
}

-- /notiz und /marknotes. /notiz ist bewusst derselbe Befehl wie in Luna:
-- wer umsteigt, tippt weiter dasselbe.
SLASH_MARKNOTES1 = "/notiz"
SLASH_MARKNOTES2 = "/marknotes"
SlashCmdList.MARKNOTES = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        M:Toggle()
    elseif cmd == "new" or cmd == "neu" then
        M:Show()
        M:New()
    elseif cmd == "minimap" then
        ns.Minimap:Toggle()
    else
        ns:Print(L["Commands: |cffffff00/notiz|r open, |cffffff00/notiz new|r new note, |cffffff00/notiz minimap|r show/hide button."])
    end
end
