-- Notizen mit der Gruppe oder dem Schlachtzug teilen - und aktuell halten.
--
-- Läuft über Addon-Nachrichten: unsichtbar im Chat, aber nur bei
-- Mitspielern, die Marknotes auch haben. Eine Nachricht fasst höchstens
-- 255 Bytes, also wird die Notiz in Stücke geteilt und beim Empfänger
-- wieder zusammengesetzt.
--
-- Ablauf:
--   * "Teilen" gibt der Notiz eine feste Kennung (note.shareId) und
--     schickt sie an die Gruppe. Der Empfänger wird gefragt.
--   * Ab dann ist die Notiz "live": Jede Änderung (Text, Titel, Haken)
--     geht nach kurzer Pause von selbst an die Gruppe. Wer die Notiz
--     angenommen hat, bekommt die neue Fassung ohne Nachfrage. Wer
--     abgelehnt hat, bekommt nichts.
--   * Beim Aktualisieren behält der Empfänger seine eigenen Haken und
--     seine Einstellung zum Anheften. Alles andere kommt vom Absender.
--
-- Das Spiel drosselt Addon-Nachrichten (ein Vorrat von etwa zehn, dann
-- eine pro Sekunde). Gedrosselte Stücke werden später erneut gesendet.
-- In Instanzen während eines Bosskampfs sperrt das Spiel Addon-Nachrichten
-- ganz; automatische Updates holen das nach dem Kampf nach.
--
-- Format jeder Nachricht:  1:<übertragung>:<nr>:<anzahl>:<daten>
--   nr 0 ist der Kopf "<kennung>:<s|u>:<titel>" (s = geteilt, u = Update),
--   1..anzahl der Text. Zeilenumbrüche und % sind als %0A / %25 maskiert.
local ADDON, ns = ...

local S = {}
ns.Share = S
local L = ns.L
local MD = ns.Markdown

local PREFIX    = "Marknotes"
local VERSION   = "1"
local CHUNK     = 200     -- Nutzdaten je Nachricht, Rest ist Kopf
local MAX_PARTS = 60      -- etwa 12 KB; reicht für jede vernünftige Notiz
local STALE     = 120     -- unvollständige Übertragungen danach verwerfen
local DELAY     = 3       -- Sekunden Pause, bevor eine Änderung rausgeht

-- ---------------------------------------------------------------- Kodierung

local function encode(s)
    return (s:gsub("\r", ""):gsub("%%", "%%25"):gsub("\n", "%%0A"))
end

local function decode(s)
    return (s:gsub("%%0A", "\n"):gsub("%%25", "%%"))
end

local function shortName(name)
    return Ambiguate and Ambiguate(name, "short") or (name:match("^[^%-]+") or name)
end

local function newId()
    return ("%x%x"):format(time() % 65536, math.random(0, 65535))
end

-- ---------------------------------------------------------------- Senden

local queue = {}

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Rückgabe von SendAddonMessage: früher true/false, heute ein Wert aus
-- Enum.SendAddonMessageResult. nil heißt "erfolgreich" bei alten
-- Clients, die nichts zurückgeben.
local function result(r)
    if r == nil or r == true or r == 0 then return "ok" end
    local E = Enum and Enum.SendAddonMessageResult
    if r == false or (E and (r == E.AddonMessageThrottle or r == E.ChannelThrottle)) then
        return "throttle"
    end
    return "fail"
end

local function pump()
    S.pumping = false
    while queue[1] do
        local job = queue[1]
        local state = result(C_ChatInfo.SendAddonMessage(PREFIX, job.parts[job.next], job.channel))

        if state == "throttle" then
            job.retries = (job.retries or 0) + 1
            if job.retries > 120 then state = "fail" else
                S.pumping = true
                C_Timer.After(1, pump)
                return
            end
        end

        if state == "fail" then
            table.remove(queue, 1)
            if job.auto then
                -- Nach dem Kampf noch einmal (PLAYER_REGEN_ENABLED).
                S.retry = S.retry or {}
                S.retry[job.note] = true
            else
                ns:Print(L["Sharing failed - addon messages are blocked right now (e.g. during a boss fight)."])
            end
        else
            job.retries = 0
            job.next = job.next + 1
            if job.next > #job.parts then
                table.remove(queue, 1)
                if not job.auto then
                    ns:Print(L["Note \"%s\" shared with your group. Changes are sent automatically."], job.title)
                end
            end
        end
    end
end

local function labelOf(note)
    for i, n in ipairs(ns.db.notes.list) do
        if n == note then return ns.Notes.Label(note, i) end
    end
    return note.title or ""
end

-- auto: Update nach einer Änderung (still, ohne Meldungen).
local function send(note, auto)
    local ch = channel()
    if not ch then
        if not auto then ns:Print(L["You are not in a group."]) end
        return
    end

    local text = encode(note.text or "")
    local count = math.max(1, math.ceil(#text / CHUNK))
    if count > MAX_PARTS then
        if not auto then ns:Print(L["This note is too long to share."]) end
        return
    end

    local title = labelOf(note)
    local head = VERSION .. ":" .. newId() .. ":"
    local meta = note.shareId .. ":" .. (auto and "u" or "s") .. ":" .. encode(title):sub(1, 150)
    local parts = { head .. "0:" .. count .. ":" .. meta }
    for i = 1, count do
        parts[#parts + 1] = head .. i .. ":" .. count .. ":"
                         .. text:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end

    -- Eine noch nicht begonnene ältere Fassung derselben Notiz ist
    -- überholt - nur die neueste muss raus.
    for k = #queue, 1, -1 do
        if queue[k].note == note and queue[k].next == 1 then table.remove(queue, k) end
    end

    queue[#queue + 1] = { parts = parts, next = 1, channel = ch, title = title,
                          note = note, auto = auto }
    if not auto and count > 8 then
        ns:Print(L["Sending note \"%s\" - this takes a few seconds."], title)
    end
    if not S.pumping then pump() end
end

-- "Teilen" geklickt: Kennung vergeben (einmal, bleibt) und senden.
function S:Send(note)
    note.shareId = note.shareId or newId()
    send(note, false)
end

-- Eine Notiz wurde geändert. Ist sie geteilt, geht die neue Fassung
-- nach kurzer Pause an die Gruppe - höchstens alle DELAY Sekunden, beim
-- Tippen also nicht jede Taste.
local dirty = {}

function S:Changed(note)
    if not note or not note.shareId then return end
    dirty[note] = true
    if S.flushPending then return end
    S.flushPending = true
    C_Timer.After(DELAY, function()
        S.flushPending = false
        for n in pairs(dirty) do
            dirty[n] = nil
            -- Inzwischen gelöscht? Dann nichts mehr senden.
            for _, x in ipairs(ns.db.notes.list) do
                if x == n then send(n, true) break end
            end
        end
    end)
end

-- Teilen beenden: die Notiz bleibt bei allen, wird aber nicht mehr
-- aktualisiert.
function S:Stop(note)
    note.shareId = nil
    dirty[note] = nil
    ns:Print(L["Note is no longer shared. The others keep their copy."])
end

function S:IsShared(note)
    return note and note.shareId ~= nil
end

-- ---------------------------------------------------------------- Empfangen

local incoming = {}   -- sender..übertragung -> { meta, total, parts, got, at }
local offers = {}     -- wartende Angebote, eins nach dem anderen fragen

local function me(sender)
    return shortName(sender) == UnitName("player")
end

local function findShared(from, id)
    for _, n in ipairs(ns.db.notes.list) do
        if n.shared and n.shared.from == from and n.shared.id == id then return n end
    end
end

local function changed(note)
    local N = ns.Notes
    if N.frame and N.frame:IsShown() then
        if note == N:Current() then N:NoteChanged(note) end
        N:RefreshList()
    end
    ns.Pins:Update()
end

-- Neue Fassung in eine angenommene Notiz übernehmen: Haken und
-- Anheften bleiben, wie der Empfänger sie hatte.
local function apply(note, o)
    local text = MD.KeepChecks(o.text, note.text)
    local meta = MD.Meta(note.text)
    if meta and meta.pin ~= nil then
        local pinned = MD.Bool(meta.pin, false)
        local newMeta = MD.Meta(text)
        if not newMeta or MD.Bool(newMeta.pin, false) ~= pinned then
            text = MD.SetPin(text, pinned, GetLocale() == "deDE")
        end
    end
    note.text = text
    note.title = o.title
    note.updated = time()
    changed(note)
end

function S:Next()
    if S.showing or not offers[1] then return end
    local o = table.remove(offers, 1)
    S.showing = o
    StaticPopup_Show("MARKNOTES_SHARE", shortName(o.from), o.title, o)
end

local function complete(sender, t)
    local o = {
        from  = sender,
        id    = t.id,
        title = t.title ~= "" and t.title or L["Note"],
        text  = decode(table.concat(t.parts)),
    }

    -- Schon angenommen: still aktualisieren.
    local note = findShared(sender, o.id)
    if note then
        apply(note, o)
        if t.kind == "s" then
            ns:Print(L["Note \"%s\" from %s updated."], o.title, shortName(sender))
        end
        return
    end

    -- Wartet noch auf Antwort: dort die neueste Fassung einsetzen.
    for _, w in ipairs(offers) do
        if w.from == sender and w.id == o.id then
            w.title, w.text = o.title, o.text
            return
        end
    end
    local s = S.showing
    if s and s.from == sender and s.id == o.id then
        s.title, s.text = o.title, o.text
        return
    end

    -- Updates zu abgelehnten oder nie gesehenen Notizen fragen nicht
    -- noch einmal nach. Nur ein bewusstes "Teilen" tut das.
    if t.kind == "s" then
        offers[#offers + 1] = o
        S:Next()
    end
end

local function received(sender, msg)
    local ver, tid, nr, total, data = msg:match("^(%d+):(%x+):(%d+):(%d+):(.*)$")
    if ver ~= VERSION then return end
    nr, total = tonumber(nr), tonumber(total)
    if total < 1 or total > MAX_PARTS or nr > total then return end

    local now = GetTime()
    for k, t in pairs(incoming) do
        if now - t.at > STALE then incoming[k] = nil end
    end

    local key = sender .. ":" .. tid
    local t = incoming[key]
    if not t then
        t = { total = total, parts = {}, got = 0, at = now }
        incoming[key] = t
    end
    t.at = now

    if nr == 0 then
        local id, kind, title = data:match("^(%x+):([su]):(.*)$")
        if not id then incoming[key] = nil return end
        t.id, t.kind, t.title = id, kind, decode(title)
    elseif not t.parts[nr] then
        t.parts[nr] = data
        t.got = t.got + 1
    end

    if t.id and t.got == t.total then
        incoming[key] = nil
        complete(sender, t)
    end
end

-- Angebot annehmen: als neue Notiz anlegen. Kam die Notiz früher schon
-- einmal (abgelehnt, dann neu geteilt), wird nichts verdoppelt.
function S:Accept(o)
    local note = findShared(o.from, o.id)
    if note then
        apply(note, o)
    else
        note = { title = o.title, text = o.text, updated = time(),
                 shared = { from = o.from, id = o.id } }
        table.insert(ns.db.notes.list, note)
        changed(note)
    end
    ns:Print(L["Note \"%s\" from %s added. It updates automatically when %s changes it."],
             o.title, shortName(o.from), shortName(o.from))
end

StaticPopupDialogs["MARKNOTES_SHARE"] = {
    text         = L["%s shares the note \"%s\" with you.\nAdd it to your notes?"],
    button1      = ACCEPT,
    button2      = DECLINE,
    OnAccept     = function(_, o) S:Accept(o) end,
    OnHide       = function()
        S.showing = nil
        C_Timer.After(0, function() S:Next() end)
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

ns:On("CHAT_MSG_ADDON", function(_, prefix, msg, ch, sender)
    if prefix ~= PREFIX or not sender or me(sender) then return end
    -- Nur aus der eigenen Gruppe, nicht per Flüstern von Fremden.
    if ch ~= "PARTY" and ch ~= "RAID" and ch ~= "INSTANCE_CHAT" then return end
    received(sender, msg)
end)

-- Im Kampf gesperrte Updates nachholen.
ns:On("PLAYER_REGEN_ENABLED", function()
    if not S.retry then return end
    for note in pairs(S.retry) do S:Changed(note) end
    S.retry = nil
end)
