-- Texte. Englisch ist der Schlüssel und zugleich die Grundsprache;
-- fehlt eine Übersetzung, erscheint der englische Text.
local ADDON, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

if GetLocale() ~= "deDE" then return end

-- Fenster
L["Notes"]                 = "Notizen"
L["New note"]              = "Neue Notiz"
L["Delete"]                = "Löschen"
L["Title"]                 = "Titel"
L["Edit"]                  = "Bearbeiten"
L["Preview"]               = "Ansicht"
L["Note %d"]               = "Notiz %d"
L["Delete this note?"]     = "Diese Notiz löschen?"
L["Empty note - double-click to write."] = "Leere Notiz - Doppelklick zum Schreiben."

-- Gegenstände / Auktionshaus
L["Items - click to search the Auction House"] =
    "Gegenstände - Klick sucht im Auktionshaus"
L["Shift-click an item to insert it."] =
    "Shift-Klick auf einen Gegenstand fügt ihn ein."
L["+ Item"]                = "+ Gegenstand"
L["Insert item"]           = "Gegenstand einfügen"
L["Insert an item by name, item ID or Wowhead link.\nShift-clicking an item works too."] =
    "Gegenstand über Name, Item-ID oder Wowhead-Link einfügen.\nShift-Klick auf einen Gegenstand geht auch."
L["Item name (from bags or equipment), item ID or Wowhead link"] =
    "Name (aus Taschen oder Ausrüstung), Item-ID oder Wowhead-Link"
L["Not found - try the item ID or a Wowhead link."] =
    "Nicht gefunden - Item-ID oder Wowhead-Link versuchen."
L["Click: search the Auction House"] = "Klick: im Auktionshaus suchen"
L["Open the Auction House first to search."] =
    "Zum Suchen erst das Auktionshaus öffnen."
L["Search term entered - press Enter to search."] =
    "Suchbegriff eingetragen - mit Enter suchen."
L["Open Marknotes next to the Auction House."] =
    "Marknotes neben dem Auktionshaus öffnen."

-- Links
L["Click: copy address"]   = "Klick: Adresse kopieren"
L["Copy link"]             = "Link kopieren"
L["Copy"]                  = "Kopieren"
L["Copy code"]             = "Code kopieren"
L["Text is selected - press |cffffffffCtrl+C|r to copy, |cffffffffESC|r closes."] =
    "Text ist markiert - mit |cffffffffStrg+C|r kopieren, |cffffffffESC|r schließt."
L["Select all"]            = "Alles wählen"

-- Werkzeugleiste
L["Heading 1"]             = "Überschrift 1"
L["Heading 2"]             = "Überschrift 2"
L["Heading 3"]             = "Überschrift 3"
L["B"]                     = "F"
L["I"]                     = "K"
L["Bold  **Text**"]        = "Fett  **Text**"
L["Italic  *Text*"]        = "Kursiv  *Text*"
L["Strikethrough  ~~Text~~"] = "Durchgestrichen  ~~Text~~"
L["Inline code  `Text`"]   = "Code im Text  `Text`"
L["List"]                  = "Liste"
L["Bullet list  - Item"]   = "Aufzählung  - Punkt"
L["Numbered list  1. Item"] = "Nummerierte Liste  1. Punkt"
L["Checkbox  - [ ] Item\nTick it off in the preview with a click."] =
    "Checkbox  - [ ] Punkt\nIn der Ansicht per Klick abhaken."
L["Quote"]                 = "Zitat"
L["Quote  > Text"]         = "Zitat  > Text"
L["Link  [Text](https://...)\nIn the preview a click copies the address."] =
    "Link  [Text](https://...)\nIn der Ansicht kopiert ein Klick die Adresse."
L["Table"]                 = "Tabelle"
L["Table with header row\n:--- / :---: / ---: aligns columns."] =
    "Tabelle mit Kopfzeile\n:--- / :---: / ---: richtet Spalten aus."
L["Code block  ``` ... ```"] = "Codeblock  ``` ... ```"
L["Rule"]                  = "Linie"
L["Horizontal rule  ---"]  = "Trennlinie  ---"
L["Raid marker  {star} {skull} ...\nLike in chat. English, German or {rt1} to {rt8}."] =
    "Zielmarkierung  {stern} {totenschädel} ...\nWie im Chat. Deutsch, Englisch oder {rt1} bis {rt8}."
L["Column 1"]              = "Spalte 1"
L["Column 2"]              = "Spalte 2"

-- Minimap / Befehle
L["Left-click: open notes"]  = "Linksklick: Notizen öffnen"
L["Right-click: new note"]   = "Rechtsklick: neue Notiz"
L["Drag: move button"]       = "Ziehen: Knopf verschieben"
L["Minimap button hidden - show it again with |cffffff00/notiz minimap|r."] =
    "Minimap-Knopf ausgeblendet - wieder einblenden mit |cffffff00/notiz minimap|r."
L["Minimap button shown."]   = "Minimap-Knopf eingeblendet."
L["Commands: |cffffff00/notiz|r open, |cffffff00/notiz new|r new note, |cffffff00/notiz minimap|r show/hide button."] =
    "Befehle: |cffffff00/notiz|r öffnen, |cffffff00/notiz neu|r neue Notiz, |cffffff00/notiz minimap|r Knopf ein/aus."
L["%d notes imported from Luna Sans UI."] = "%d Notizen aus Luna Sans UI übernommen."
