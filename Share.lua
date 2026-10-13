-- Notizen mit der Gruppe oder dem Schlachtzug teilen.
--
-- Läuft über Addon-Nachrichten: unsichtbar im Chat, aber nur bei
-- Mitspielern, die Marknotes auch haben. Eine Nachricht fasst höchstens
-- 255 Bytes, also wird die Notiz in Stücke geteilt und beim Empfänger
-- wieder zusammengesetzt. Der Empfänger wird gefragt, bevor etwas in
-- seinen Notizen landet.
--
-- Teilt derselbe Spieler eine Notiz mit demselben Titel noch einmal,
-- wird die übernommene Notiz ersetzt statt verdoppelt - so kann die
-- Raidleitung ihre Liste aktualisieren.
--
-- Das Spiel drosselt Addon-Nachrichten (ein Vorrat von etwa zehn, dann
-- eine pro Sekunde). Gedrosselte Stücke werden einfach später erneut
-- gesendet. In Instanzen während eines Bosskampfs sperrt das Spiel
-- Addon-Nachrichten ganz; dann bricht das Teilen mit einem Hinweis ab.
--
-- Format jeder Nachricht:  1:<id>:<nr>:<anzahl>:<daten>
--   nr 0 ist der Titel, 1..anzahl der Text. Zeilenumbrüche und % sind
--   als %0A / %25 maskiert.
local ADDON, ns = ...

local S = {}
ns.Share = S
local L = ns.L

local PREFIX    = "Marknotes"
local VERSION   = "1"
local CHUNK     = 200     -- Nutzdaten je Nachricht, Rest ist Kopf
local MAX_PARTS = 60      -- etwa 12 KB; reicht für jede vernünftige Notiz
local STALE     = 120     -- unvollständige Übertragungen danach verwerfen

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

-- ---------------------------------------------------------------- Senden

local queue = {}

local function channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Rückgabe von SendAddonMessage: früher true/false, heute ein Wert aus
-- Enum.SendAddonMessageResult. "nil" heißt "erfolgreich" bei alten
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
        local msg = job.parts[job.next]
        local state = result(C_ChatInfo.SendAddonMessage(PREFIX, msg, job.channel))

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
            ns:Print(L["Sharing failed - addon messages are blocked right now (e.g. during a boss fight)."])
        else
            job.retries = 0
            job.next = job.next + 1
            if job.next > #job.parts then
                table.remove(queue, 1)
                ns:Print(L["Note \"%s\" sent to your group."], job.title)
            end
        end
    end
end

function S:Send(note, label)
    local ch = channel()
    if not ch then
        ns:Print(L["You are not in a group."])
        return
    end

    local text = encode(note.text or "")
    local count = math.max(1, math.ceil(#text / CHUNK))
    if count > MAX_PARTS then
        ns:Print(L["This note is too long to share."])
        return
    end

    -- Zeit und Zufall: zwei Übertragungen desselben Spielers bleiben
    -- auseinander, auch wenn sie sich überschneiden.
    local id = ("%x%x"):format(time() % 65536, math.random(0, 4095))
    local head = VERSION .. ":" .. id .. ":"
    local title = label or ""
    local parts = { head .. "0:" .. count .. ":" .. encode(title):sub(1, CHUNK) }
    for i = 1, count do
        parts[#parts + 1] = head .. i .. ":" .. count .. ":"
                         .. text:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end

    queue[#queue + 1] = { parts = parts, next = 1, channel = ch, title = title }
    if count > 8 then
        ns:Print(L["Sending note \"%s\" - this takes a few seconds."], title)
    end
    if not S.pumping then pump() end
end

-- ---------------------------------------------------------------- Empfangen

local incoming = {}   -- sender..id -> { title, total, parts, got, at }
local offers = {}     -- wartende Angebote, eins nach dem anderen fragen

local function me(sender)
    return shortName(sender) == UnitName("player")
end

function S:Next()
    if not offers[1] then return end
    if StaticPopup_Visible and StaticPopup_Visible("MARKNOTES_SHARE") then return end
    local o = table.remove(offers, 1)
    StaticPopup_Show("MARKNOTES_SHARE", shortName(o.from), o.title, o)
end

local function received(sender, msg)
    local ver, id, nr, total, data = msg:match("^(%d+):(%x+):(%d+):(%d+):(.*)$")
    if ver ~= VERSION then return end
    nr, total = tonumber(nr), tonumber(total)
    if total < 1 or total > MAX_PARTS or nr > total then return end

    local now = GetTime()
    for k, t in pairs(incoming) do
        if now - t.at > STALE then incoming[k] = nil end
    end

    local key = sender .. ":" .. id
    local t = incoming[key]
    if not t then
        t = { total = total, parts = {}, got = 0, at = now }
        incoming[key] = t
    end
    t.at = now

    if nr == 0 then
        t.title = decode(data)
    elseif not t.parts[nr] then
        t.parts[nr] = data
        t.got = t.got + 1
    end

    if t.title and t.got == t.total then
        incoming[key] = nil
        offers[#offers + 1] = {
            from  = sender,
            title = t.title ~= "" and t.title or L["Note"],
            text  = decode(table.concat(t.parts)),
        }
        S:Next()
    end
end

-- Angebot annehmen: als neue Notiz anlegen, oder eine früher vom selben
-- Spieler übernommene Notiz mit gleichem Titel ersetzen.
function S:Accept(o)
    local list = ns.db.notes.list
    local note
    for _, n in ipairs(list) do
        if n.shared and n.shared.from == o.from and n.shared.title == o.title then
            note = n
            break
        end
    end

    if note then
        note.text = o.text
        ns:Print(L["Note \"%s\" from %s updated."], o.title, shortName(o.from))
    else
        note = { title = o.title, shared = { from = o.from, title = o.title } }
        note.text = o.text
        list[#list + 1] = note
        ns:Print(L["Note \"%s\" from %s added."], o.title, shortName(o.from))
    end
    note.updated = time()

    local N = ns.Notes
    if N.frame and N.frame:IsShown() then N:Refresh() end
    ns.Pins:Update()
end

StaticPopupDialogs["MARKNOTES_SHARE"] = {
    text         = L["%s shares the note \"%s\" with you.\nAdd it to your notes?"],
    button1      = ACCEPT,
    button2      = DECLINE,
    OnAccept     = function(_, o) S:Accept(o) end,
    OnHide       = function() C_Timer.After(0, function() S:Next() end) end,
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
