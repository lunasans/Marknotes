-- Markdown für die Notizen: Lese-Ansicht neben dem Bearbeiten.
--
-- Eine EditBox kann beim Tippen keine Formatierung zeigen (Größen,
-- Hintergründe, Tabellen). Deshalb gibt es zwei Ansichten: geschrieben
-- wird Markdown im Textfeld, gelesen wird die gerenderte Fassung.
--
-- Unterstützt:
--   # / ## / ###      Überschriften
--   **fett** __fett__ hervorgehoben (echtes Fett gibt es im Fließtext
--                     nicht - eine FontString hat genau eine Schrift)
--   *kursiv*          farbig abgesetzt, aus demselben Grund
--   ~~weg~~ `code`    durchgestrichen (grau) / Code
--   - / * / + / 1.    Listen, eingerückt mit zwei Leerzeichen je Stufe
--   - [ ] / - [x]     Checkboxen, per Klick abhakbar
--   > Zitat, ---, ``` Codeblock ```
--   | a | b |         Tabellen, mit |---|:--:|--:| für Kopf und Ausrichtung
--   [Text](https://…) und nackte https://-Adressen als Links
--   {stern} {totenschädel} {rt1}  Zielmarkierungen wie im Chat
--
-- Links öffnet WoW nicht im Browser - für Addons gibt es diesen Weg
-- nicht. Ein Klick legt die Adresse markiert ins Kopierfenster.
--
-- Der Parser (Parse, Inline, ToggleCheck) braucht keine Spiel-API und
-- lässt sich außerhalb von WoW testen. Erst Render fasst Frames an.
--
-- Gleicher Stand wie Modules\NotesMarkdown.lua in Luna Sans UI. Bei
-- Änderungen am Parser beide Dateien mitnehmen.
local ADDON, ns = ...

local MD = {}
ns.Markdown = MD

-- ---------------------------------------------------------------- Parser

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Nur A-Z klein machen. string.lower richtet sich nach dem Gebietsschema
-- und verändert dann die Bytes von Umlauten ("höhe" würde nicht erkannt).
local function lower(s)
    return (s:gsub("[A-Z]", string.lower))
end

-- Buchstaben, die hinter | eine WoW-Steuerfolge bilden (Farbe, Link,
-- Textur, Atlas, Umbruch ...). Ein | davor ist KEIN Tabellentrenner.
local ESCAPE = "[cCrRHhTtAaKkn]"

-- Tabellenzeile: beginnt mit |, das keine Steuerfolge einleitet.
-- Getippte | legt die EditBox je nach Client als || ab - beides zählt.
local function isTableRow(line)
    local s = line:match("^%s*(.*)$")
    if s:sub(1, 1) ~= "|" then return false end
    local nx = s:sub(2, 2)
    return nx == "|" or nx == "" or not nx:match(ESCAPE)
end

local function splitRow(line)
    local s = trim(line)
    local cells, buf, i, n = {}, {}, 1, #s

    local function push()
        cells[#cells + 1] = trim(table.concat(buf))
        buf = {}
    end

    while i <= n do
        local c = s:sub(i, i)
        if c == "|" then
            local nx = s:sub(i + 1, i + 1)
            if nx == "|" then
                push()
                i = i + 2
            elseif nx ~= "" and nx:match(ESCAPE) then
                -- Steuerfolge (Gegenstandslink in einer Zelle): bleibt.
                buf[#buf + 1] = c
                i = i + 1
            else
                push()
                i = i + 1
            end
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    push()

    -- Rand-Trenner erzeugen leere Zellen vorn und hinten.
    if cells[1] == "" then table.remove(cells, 1) end
    if #cells > 0 and cells[#cells] == "" and s:sub(-1) == "|" then
        table.remove(cells)
    end
    return cells
end

local function isSeparator(cells)
    if #cells == 0 then return false end
    for _, c in ipairs(cells) do
        if not c:match("^:?%-+:?$") then return false end
    end
    return true
end

local function alignOf(cell)
    local l, r = cell:sub(1, 1) == ":", cell:sub(-1) == ":"
    if l and r then return "CENTER" end
    if r then return "RIGHT" end
    return "LEFT"
end

local function indentOf(ws)
    local width = #ws:gsub("\t", "    ")
    return math.min(4, math.floor(width / 2))
end

-- Text in Blöcke zerlegen. Jeder Block mit Zeilennummer, wo es eine
-- Rückverbindung braucht (Checkboxen schreiben in ihre Zeile zurück).
function MD.Parse(text)
    text = (text or ""):gsub("\r\n", "\n")

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end

    local blocks = {}
    local function add(b) blocks[#blocks + 1] = b end

    local i = 1
    while i <= #lines do
        local line = lines[i]

        if line:match("^%s*```") then
            local code = {}
            i = i + 1
            while i <= #lines and not lines[i]:match("^%s*```") do
                code[#code + 1] = lines[i]
                i = i + 1
            end
            add({ type = "code", lines = code })
            i = i + 1

        elseif isTableRow(line) then
            local rows = {}
            while i <= #lines and isTableRow(lines[i]) do
                rows[#rows + 1] = splitRow(lines[i])
                i = i + 1
            end
            local t = { type = "table", rows = rows, align = {} }
            if rows[2] and isSeparator(rows[2]) then
                t.header = true
                for c, cell in ipairs(rows[2]) do t.align[c] = alignOf(cell) end
                table.remove(rows, 2)
            end
            add(t)

        elseif not line:match("%S") then
            -- Mehrere Leerzeilen sind ein Abstand, nicht mehrere.
            if #blocks > 0 and blocks[#blocks].type ~= "blank" then
                add({ type = "blank" })
            end
            i = i + 1

        else
            local hashes, htext = line:match("^%s*(#+)%s+(.+)$")
            local ind, rest     = line:match("^(%s*)[%-%*%+]%s+(.*)$")
            local oind, num, orest = line:match("^(%s*)(%d+)[%.%)]%s+(.*)$")

            if hashes and #hashes <= 6 then
                add({ type = "heading", level = math.min(#hashes, 3),
                      text = htext:gsub("%s+#+%s*$", "") })

            -- Vor den Listen: "* * *" ist eine Linie, keine Aufzählung.
            elseif line:match("^%s*([%-%*_])%s*%1%s*%1[%s%-%*_]*$") then
                add({ type = "rule" })

            elseif line:match("^%s*>") then
                add({ type = "quote", text = line:match("^%s*>%s?(.*)$") })

            elseif ind then
                local mark, ctext = rest:match("^%[([ xX])%]%s*(.*)$")
                -- check: nil = keine Checkbox, false = offen, true = erledigt.
                -- Nicht als "a and b or nil" schreiben - bei b = false
                -- käme nil heraus und die offene Checkbox verschwände.
                local check
                if mark then check = (mark ~= " ") end
                add({ type = "list", indent = indentOf(ind), line = i,
                      text = mark and ctext or rest, check = check })

            elseif oind then
                add({ type = "list", indent = indentOf(oind), line = i,
                      text = orest, number = num })

            else
                add({ type = "para", text = line })
            end
            i = i + 1
        end
    end

    -- Abstand am Ende hat keinen Zweck.
    if #blocks > 0 and blocks[#blocks].type == "blank" then table.remove(blocks) end
    return blocks
end

-- Checkbox in Zeile lineIndex umschalten. Liefert den neuen Text.
function MD.ToggleCheck(text, lineIndex)
    local out, n = {}, 0
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if n == lineIndex then
            line = line:gsub("%[([ xX])%]", function(m)
                return m == " " and "[x]" or "[ ]"
            end, 1)
        end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------- Inline

MD.COLOR = {
    bold   = "|cffffffff",
    italic = "|cffb4bed2",
    strike = "|cff808080",
    code   = "|cffe6b464",
    link   = "|cff7aa2f7",
}

-- Zielmarkierungen, geschrieben wie im Chat: {rt1} bis {rt8}, englisch
-- oder deutsch - unabhängig von der Spielsprache, damit eine geteilte
-- Notiz bei allen gleich aussieht.
local MARKERS = {
    star = 1,     stern = 1,
    circle = 2,   kreis = 2,   coin = 2,
    diamond = 3,  diamant = 3,
    triangle = 4, dreieck = 4,
    moon = 5,     mond = 5,
    square = 6,   quadrat = 6,
    cross = 7,    kreuz = 7,   x = 7,
    skull = 8,    ["totenschädel"] = 8, totenkopf = 8, ["schädel"] = 8,
}
for i = 1, 8 do MARKERS["rt" .. i] = i end
MD.MARKER_NAMES_EN = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
MD.MARKER_NAMES_DE = { "stern", "kreis", "diamant", "dreieck", "mond", "quadrat", "kreuz", "totenschädel" }

function MD.MarkerIcon(i, size)
    return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":" .. (size or 0) .. "|t"
end

local function linkFor(url, label)
    return "|Hurl:" .. url .. "|h" .. MD.COLOR.link .. label .. "|r|h"
end

-- Markdown einer Zeile in WoW-Steuerfolgen übersetzen.
--
-- Was schon eine Steuerfolge ist (Gegenstandslinks, Texturen) und was
-- keine Formatierung mehr bekommen darf (Code, Link-Adressen), wird
-- vorher weggelegt und am Ende wieder eingesetzt. Sonst machte ein
-- Sternchen in einem Gegenstandsnamen oder ein _ in einer Adresse den
-- Link kaputt.
function MD.Inline(s)
    local keep = {}
    local function stash(v)
        keep[#keep + 1] = v
        return "\1" .. #keep .. "\2"
    end

    s = s:gsub("|c[^|]*|H.-|h.-|h|r", stash)
    s = s:gsub("|H.-|h.-|h", stash)
    s = s:gsub("|T.-|t", stash)
    s = s:gsub("|A.-|a", stash)

    s = s:gsub("`([^`]+)`", function(c) return stash(MD.COLOR.code .. c .. "|r") end)

    -- Unbekanntes in {} bleibt stehen, wie es ist.
    s = s:gsub("{([^{}]+)}", function(name)
        local i = MARKERS[lower(name)]
        if i then return stash(MD.MarkerIcon(i)) end
    end)

    s = s:gsub("%[([^%]]+)%]%(([^%)%s]+)%)", function(label, url)
        return stash(linkFor(url, label))
    end)

    -- Nackte Adressen. Satzzeichen am Ende gehören zum Satz, nicht zur
    -- Adresse ("siehe https://example.com.").
    s = s:gsub("https?://[^%s\1\2]+", function(url)
        local tail = url:match("[%.,;:!%?%)]+$") or ""
        url = url:sub(1, #url - #tail)
        return stash(linkFor(url, url)) .. tail
    end)

    s = s:gsub("%*%*(.-)%*%*", MD.COLOR.bold .. "%1|r")
    s = s:gsub("__(.-)__",     MD.COLOR.bold .. "%1|r")
    s = s:gsub("~~(.-)~~",     MD.COLOR.strike .. "%1|r")
    s = s:gsub("%*([^%*%s][^%*]-)%*", MD.COLOR.italic .. "%1|r")

    -- Weggelegtes kann Weggelegtes enthalten (Code im Linktext).
    for _ = 1, 5 do
        local found
        s, found = s:gsub("\1(%d+)\2", function(k) return keep[tonumber(k)] end)
        if found == 0 then break end
    end
    return s
end

-- ---------------------------------------------------------------- Darstellung

local BODY   = { 0.86, 0.86, 0.86 }
local MUTED  = { 0.55, 0.55, 0.55 }
local HEAD_SIZE = { 20, 17, 15 }

-- Pools je Ansicht: Frames lassen sich nicht löschen, also werden sie
-- bei jedem Neuaufbau versteckt und wiederverwendet.
local function begin(view)
    view.pools = view.pools or { fs = { n = 0 }, tex = { n = 0 }, check = { n = 0 },
                                 copy = { n = 0 } }
    for _, p in pairs(view.pools) do
        for k = 1, #p do p[k]:Hide() end
        p.n = 0
    end
end

local function acquire(view, kind, make)
    local p = view.pools[kind]
    p.n = p.n + 1
    local obj = p[p.n]
    if not obj then
        obj = make()
        p[p.n] = obj
    end
    obj:ClearAllPoints()
    obj:Show()
    return obj
end

local function text(view, width)
    local fs = acquire(view, "fs", function()
        return view.content:CreateFontString(nil, "OVERLAY")
    end)
    fs:SetFontObject(ChatFontNormal)
    fs:SetTextColor(BODY[1], BODY[2], BODY[3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
    fs:SetSpacing(2)
    fs:SetWidth(width)
    return fs
end

local function rect(view, layer, r, g, b, a)
    local tex = acquire(view, "tex", function()
        return view.content:CreateTexture(nil, "BACKGROUND")
    end)
    tex:SetDrawLayer(layer or "BACKGROUND")
    tex:SetColorTexture(r, g, b, a)
    return tex
end

local function checkbox(view)
    return acquire(view, "check", function()
        local b = CreateFrame("Button", nil, view.content)
        b:SetSize(14, 14)
        ns.U:Skin(b, 0.5)
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetPoint("TOPLEFT", -3, 3)
        b.mark:SetPoint("BOTTOMRIGHT", 3, -3)
        b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b:SetScript("OnClick", function(self)
            if view.onToggle then view.onToggle(self.line) end
        end)
        return b
    end)
end

-- Kopierknopf für Codeblöcke. Ein Addon kann nicht in die Zwischenablage
-- schreiben - der Knopf legt den Code markiert ins Kopierfenster, Strg+C
-- erledigt den Rest.
local COPY_W = 64

local function copyButton(view, label)
    local b = acquire(view, "copy", function()
        local btn = ns.W:Button(view.content, { label = label, width = COPY_W - 8,
                                                height = 16, y = 0,
            onClick = function(self) ns.U:ShowCopyBox(self.title, self.code, 560, 260) end })
        btn:SetFrameLevel(view.content:GetFrameLevel() + 5)
        return btn
    end)
    b.label:SetText(label)
    return b
end

local function measure(view, s)
    local m = view.measure
    if not m then
        m = view.content:CreateFontString(nil, "OVERLAY")
        m:SetFontObject(ChatFontNormal)
        m:SetWordWrap(false)
        m:Hide()
        view.measure = m
    end
    m:SetText(s)
    local w = m.GetUnboundedStringWidth and m:GetUnboundedStringWidth()
              or m:GetStringWidth()
    return math.ceil(w or 0) + 1
end

local function headingFont(fs, size)
    local path, _, flags = fs:GetFont()
    if path then pcall(fs.SetFont, fs, path, size, flags or "") end
end

-- Tabelle ab y zeichnen; liefert das neue y.
local function renderTable(view, t, y, width)
    local PADX, PADY = 6, 4
    local rows = t.rows

    local ncol = 0
    for _, row in ipairs(rows) do ncol = math.max(ncol, #row) end
    if ncol == 0 then return y end

    -- Natürliche Breite je Spalte, dann auf den Platz verteilen.
    local natural, sum = {}, 0
    for c = 1, ncol do
        natural[c] = 0
        for _, row in ipairs(rows) do
            natural[c] = math.max(natural[c], measure(view, MD.Inline(row[c] or "")))
        end
        sum = sum + natural[c]
    end

    local widths, tableW = {}, 0
    local free = width - ncol * 2 * PADX
    for c = 1, ncol do
        local w = natural[c]
        if sum > free and sum > 0 then
            w = math.max(30, math.floor(natural[c] / sum * free))
        end
        widths[c] = w + 2 * PADX
        tableW = tableW + widths[c]
    end

    local accent = ns.W.ACCENT
    local top = y
    local lines = {}

    for r, row in ipairs(rows) do
        local isHead = t.header and r == 1
        local rowH, x, cells = 0, 0, {}

        for c = 1, ncol do
            local fs = text(view, widths[c] - 2 * PADX)
            fs:SetJustifyH(t.align[c] or "LEFT")
            fs:SetText(MD.Inline(row[c] or ""))
            if isHead then fs:SetTextColor(1, 1, 1) end
            fs:SetPoint("TOPLEFT", x + PADX, y - PADY)
            rowH = math.max(rowH, fs:GetStringHeight() or 0)
            x = x + widths[c]
            cells[c] = fs
        end
        rowH = math.ceil(rowH) + 2 * PADY

        local bg
        if isHead then
            bg = rect(view, "BACKGROUND", accent[1], accent[2], accent[3], 0.22)
        elseif r % 2 == 0 then
            bg = rect(view, "BACKGROUND", 1, 1, 1, 0.04)
        end
        if bg then
            bg:SetPoint("TOPLEFT", 0, y)
            bg:SetSize(tableW, rowH)
        end

        y = y - rowH
        lines[#lines + 1] = y
    end

    -- Gitter: Rahmen, Zeilen- und Spaltentrenner.
    local h = top - y
    local function hline(at)
        local l = rect(view, "ARTWORK", 1, 1, 1, 0.14)
        l:SetPoint("TOPLEFT", 0, at)
        l:SetSize(tableW, 1)
    end
    local function vline(at)
        local l = rect(view, "ARTWORK", 1, 1, 1, 0.14)
        l:SetPoint("TOPLEFT", at, top)
        l:SetSize(1, h)
    end
    hline(top)
    for _, at in ipairs(lines) do hline(at) end
    local x = 0
    vline(0)
    for c = 1, ncol do
        x = x + widths[c]
        vline(math.min(x, tableW - 1))
    end

    return y
end

-- Notiztext in view.content zeichnen. view.onToggle(line) wird beim
-- Klick auf eine Checkbox gerufen.
function MD:Render(view, source, width)
    begin(view)

    local blocks = MD.Parse(source)
    local y = 0
    local accent = ns.W.ACCENT

    if #blocks == 0 then
        local fs = text(view, width)
        fs:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        fs:SetText(ns.L["Empty note - double-click to write."])
        fs:SetPoint("TOPLEFT", 0, 0)
        view.content:SetHeight(40)
        return
    end

    for index, b in ipairs(blocks) do
        local kind = b.type

        if kind == "heading" then
            if index > 1 then y = y - 6 end
            local fs = text(view, width)
            headingFont(fs, HEAD_SIZE[b.level])
            fs:SetTextColor(accent[1], accent[2], accent[3])
            fs:SetText(MD.Inline(b.text))
            fs:SetPoint("TOPLEFT", 0, y)
            y = y - math.ceil(fs:GetStringHeight()) - 4
            if b.level == 1 then
                local l = rect(view, "ARTWORK", accent[1], accent[2], accent[3], 0.35)
                l:SetPoint("TOPLEFT", 0, y)
                l:SetSize(width, 1)
                y = y - 6
            end

        elseif kind == "para" then
            local fs = text(view, width)
            fs:SetText(MD.Inline(b.text))
            fs:SetPoint("TOPLEFT", 0, y)
            y = y - math.ceil(fs:GetStringHeight()) - 3

        elseif kind == "blank" then
            y = y - 8

        elseif kind == "rule" then
            y = y - 5
            local l = rect(view, "ARTWORK", 1, 1, 1, 0.15)
            l:SetPoint("TOPLEFT", 0, y)
            l:SetSize(width, 1)
            y = y - 7

        elseif kind == "quote" then
            local fs = text(view, width - 14)
            fs:SetTextColor(0.72, 0.72, 0.72)
            fs:SetText(MD.Inline(b.text))
            fs:SetPoint("TOPLEFT", 14, y)
            local h = math.ceil(fs:GetStringHeight())
            local bar = rect(view, "ARTWORK", accent[1], accent[2], accent[3], 0.6)
            bar:SetPoint("TOPLEFT", 3, y + 1)
            bar:SetSize(2, h + 2)
            y = y - h - 4

        elseif kind == "list" then
            local x = b.indent * 16
            local fs

            if b.check ~= nil then
                local box = checkbox(view)
                box:SetPoint("TOPLEFT", x, y + 1)
                box.line = b.line
                box.mark:SetShown(b.check)
                fs = text(view, width - x - 20)
                fs:SetPoint("TOPLEFT", x + 20, y)
                if b.check then fs:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end

            elseif b.number then
                local num = text(view, 22)
                num:SetJustifyH("RIGHT")
                num:SetTextColor(accent[1], accent[2], accent[3])
                num:SetText(b.number .. ".")
                num:SetPoint("TOPLEFT", x - 4, y)
                fs = text(view, width - x - 24)
                fs:SetPoint("TOPLEFT", x + 24, y)

            else
                -- Punkt als Fläche statt Zeichen: nicht jede Schrift hat •.
                local dot = rect(view, "ARTWORK", accent[1], accent[2], accent[3], 0.9)
                dot:SetPoint("TOPLEFT", x + 4, y - 6)
                dot:SetSize(4, 4)
                fs = text(view, width - x - 16)
                fs:SetPoint("TOPLEFT", x + 16, y)
            end

            fs:SetText(MD.Inline(b.text))
            y = y - math.max(16, math.ceil(fs:GetStringHeight())) - 3

        elseif kind == "code" then
            y = y - 2
            local code = table.concat(b.lines, "\n")
            -- Rechts Platz für den Kopierknopf lassen.
            local fs = text(view, width - 16 - COPY_W)
            fs:SetTextColor(0.90, 0.75, 0.45)
            fs:SetText(code)
            fs:SetPoint("TOPLEFT", 8, y - 6)
            local h = math.max(24, math.ceil(fs:GetStringHeight()) + 12)
            local bg = rect(view, "BACKGROUND", 0, 0, 0, 0.35)
            bg:SetPoint("TOPLEFT", 0, y)
            bg:SetSize(width, h)
            if code:match("%S") then
                local copy = copyButton(view, ns.L["Copy"])
                copy.code, copy.title = code, ns.L["Copy code"]
                copy:SetPoint("TOPRIGHT", view.content, "TOPLEFT", width - 4, y - 4)
            end
            y = y - h - 6

        elseif kind == "table" then
            y = renderTable(view, b, y - 2, width) - 8
        end
    end

    view.content:SetHeight(math.max(1, -y + 8))
end
