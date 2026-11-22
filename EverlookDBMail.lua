-- EverlookDB Mail: a simple mailbox helper for WoW Forever. Its settings window, chat commands, saved data, your alts,
-- the small menu helper both tabs use, stepping aside for another mail addon, and the small API other addons read.
-- Inbox.lua has the inbox (tags, tick boxes, Open/Return selected, Open all, Shift- and Ctrl-click); Send.lua the send
-- tab (Tab completion, the To: list, the total, money in the subject). Everything lives inside Blizzard's mail frame.
--
-- Saved: EverlookMailDB = { settings (below), recent = { newest first: { name, t } }, alts = { [realm key] = { [name] =
--   { class, level, t } } }, window, told = { [notice] = true } }. The realm key is the realm ID from the character's
--   GUID ("Player-6946-..."), since GetRealmName() can be empty on this client.
--
-- API (EverlookDBMailAPI, read-only): version, isAlt(name), alts() (names on this realm), lastScan() (a copy of the
-- inbox as last read: the classifier's mails), categories (EverlookMailClassify's ids and labels).
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")

function ns.C() return (LibStub("EverlookMailClassify-1", true)) end

ns.DEFAULTS = {
  tags = true,          -- a category tag on each inbox row
  select = true,        -- tick boxes on the inbox rows, Select, Open selected and Return selected
  shiftClick = true,    -- Shift-click a mail: take its money and items
  ctrlReturn = true,    -- Ctrl-click a mail: return it to the sender
  collected = true,     -- one chat line when the mailbox closes: the gold you took
  ledger = true,        -- hand every mail to EverlookDB Auctions' income ledger when it is loaded
  delay = 0.3,          -- seconds between two takes (the server needs a moment)
  open = { ah = true, alts = true, npc = true, players = true, letters = false },
  send = { recent = true, max = 12, alts = true, friends = true, complete = true, tab = true, total = true, wire = true },
  recent = {},
  alts = {},
  told = {},
}

local db
ns.db = function() return db end

local function okv(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end
ns.okv = okv
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return okv(a), okv(b), okv(c) end
end
ns.try = try

---------------------------------------------------------------------------------------------------------------------
-- Money text: 1g 20s 5c

function ns.money(c)
  c = math.floor(tonumber(c) or 0)
  local neg = c < 0
  c = math.abs(c)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = ("%d|cffffd700g|r"):format(g) end
  if s > 0 then out[#out + 1] = ("%d|cffc7c7cfs|r"):format(s) end
  if k > 0 or #out == 0 then out[#out + 1] = ("%d|cffeda55fc|r"):format(k) end
  return (neg and "-" or "") .. table.concat(out, " ")
end

---------------------------------------------------------------------------------------------------------------------
-- Your characters (alts): each one adds itself when it logs in

function ns.realmKey()
  local g = try(UnitGUID, "player")
  local id = type(g) == "string" and g:match("^Player%-(%d+)%-")
  if id then return id end
  local r = try(GetRealmName)
  return (type(r) == "string" and r ~= "") and r or "?"
end

local function shortName(name)
  name = okv(name)
  if type(name) ~= "string" or name == "" then return nil end
  return name:match("^([^%-]+)") or name
end
ns.shortName = shortName

function ns.me() return shortName(try(UnitName, "player")) end

function ns.altList()
  local out = {}
  local realm = db and db.alts[ns.realmKey()]
  local me = ns.me()
  for name, a in pairs(realm or {}) do
    if name ~= me then out[#out + 1] = { name = name, class = a.class, level = a.level, t = a.t } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function ns.isAlt(name)
  local short = shortName(name)
  if not short or not db then return false end
  if short == ns.me() then return false end
  local realm = db.alts[ns.realmKey()]
  return (realm and realm[short]) and true or false
end

function ns.noteMe()
  if not db then return end
  local name = ns.me()
  if not name then return end
  local key = ns.realmKey()
  db.alts[key] = db.alts[key] or {}
  local _, class = try(UnitClass, "player")
  db.alts[key][name] = { class = class, level = try(UnitLevel, "player"), t = time() }
end

-- forget a name: from your alts and the recent recipients
function ns.forget(name)
  local short = shortName(name)
  if not short or not db then return false end
  local gone = false
  for _, realm in pairs(db.alts) do
    for n in pairs(realm) do
      if n:lower() == short:lower() then realm[n] = nil; gone = true end
    end
  end
  for i = #db.recent, 1, -1 do
    if (db.recent[i].name or ""):lower() == name:lower() or (shortName(db.recent[i].name) or ""):lower() == short:lower() then
      table.remove(db.recent, i); gone = true
    end
  end
  return gone
end

---------------------------------------------------------------------------------------------------------------------
-- Recent recipients (newest first, once each)

function ns.noteRecipient(name)
  if not db or not db.send.recent then return end
  name = okv(name)
  if type(name) ~= "string" then return end
  name = name:match("^%s*(.-)%s*$")
  if name == "" then return end
  -- "anna" -> "Anna": the way the game shows names
  name = name:sub(1, 1):upper() .. name:sub(2)
  for i = #db.recent, 1, -1 do
    if db.recent[i].name:lower() == name:lower() then table.remove(db.recent, i) end
  end
  table.insert(db.recent, 1, { name = name, t = time() })
  local max = math.max(1, math.floor(tonumber(db.send.max) or 12))
  while #db.recent > max do table.remove(db.recent) end
end

---------------------------------------------------------------------------------------------------------------------
-- A small menu: Blizzard's own (MenuUtil) when the client has it, else a plain list of ours.
-- items: { { title = "Recent" }, { text = "Anna", func = fn, disabled = bool, note = "your alt" }, { divider = true } }

local plainMenu
local function closePlain() if plainMenu then plainMenu:Hide() end end
ns.closeMenu = closePlain

function ns.menu(owner, items)
  if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
    return MenuUtil.CreateContextMenu(owner, function(_, root)
      if root.SetScrollMode then root:SetScrollMode(420) end
      for _, it in ipairs(items) do
        if it.divider then
          root:CreateDivider()
        elseif it.title then
          root:CreateTitle(it.title)
        else
          local text = it.note and (it.text .. "  |cff8d94a3" .. it.note .. "|r") or it.text
          local b = root:CreateButton(text, function() it.func() end)
          if it.disabled and b and b.SetEnabled then b:SetEnabled(false) end
        end
      end
    end)
  end
  local T = ns.app.T
  if not plainMenu then
    plainMenu = CreateFrame("Frame", "EverlookMailMenu", UIParent)
    plainMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    plainMenu:SetClampedToScreen(true)
    UI.WindowChrome(plainMenu, T)
    plainMenu:EnableMouse(true)
    plainMenu.rows = {}
  end
  for _, r in ipairs(plainMenu.rows) do r:Hide() end
  local y = -6
  for i, it in ipairs(items) do
    local r = plainMenu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, plainMenu)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT")
      r.hl:SetAllPoints()
      r.hl:SetColorTexture(1, 1, 1, 0.08)
      r.text = UI.Text(r, T.font, T.text)
      r.text:SetPoint("LEFT", 8, 0)
      r.note = UI.Text(r, T.font - 1, T.muted)
      r.note:SetPoint("RIGHT", -8, 0)
      r:SetScript("OnClick", function(self)
        if self.func and not self.disabled then closePlain(); self.func() end
      end)
      plainMenu.rows[i] = r
    end
    local h = it.divider and 7 or (it.title and 18 or 20)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, y)
    r:SetPoint("RIGHT", plainMenu, "RIGHT", -4, 0)
    r:SetHeight(h)
    r.func, r.disabled = it.func, it.disabled
    r.text:SetText(it.title and ("|cffffd100" .. it.title .. "|r") or (it.text or ""))
    r.note:SetText(it.note or "")
    r:EnableMouse(it.func ~= nil)
    r:Show()
    y = y - h
  end
  plainMenu.items = items
  plainMenu:SetSize(210, -y + 6)
  plainMenu:ClearAllPoints()
  plainMenu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  plainMenu:Show()
  return plainMenu
end
ns.plainMenu = function() return plainMenu end

---------------------------------------------------------------------------------------------------------------------
-- Another mail addon that does the same things: we step aside for the overlapping parts (the inbox buttons, tick
-- boxes, Shift-/Ctrl-click, Open all, the To: box, money in the subject) and keep the tags, the total and the ledger.
-- Said once in chat, and in /email status and the settings.

ns.RIVALS = { "Postal" }
local function loaded(name)
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  if type(f) ~= "function" then return false end
  local ok, a = pcall(f, name)
  return ok and a and true or false
end
ns.loaded = loaded

function ns.findRival()
  ns.rivalName = nil
  for _, n in ipairs(ns.RIVALS) do
    if loaded(n) then ns.rivalName = n break end
  end
  return ns.rivalName
end
function ns.rival() return ns.rivalName end

-- true the first time a notice is asked for (per account, ever)
function ns.tellOnce(key)
  if not db then return false end
  db.told = db.told or {}
  if db.told[key] then return false end
  db.told[key] = true
  return true
end

function ns.stepAsideText()
  local r = ns.rivalName
  return r and ("%s is loaded, so EverlookDB Mail leaves the inbox buttons, tick boxes, Shift- and Ctrl-click, Open all and the To: box to %s. The tag on each mail and the total when you send gold still show. To use ours instead, disable %s (Esc > AddOns) and /reload."):format(r, r, r) or nil
end

function ns.stepAsideNotice()
  local r = ns.rivalName
  if r and ns.tellOnce("stepAside:" .. r) then ns.app:Print(ns.stepAsideText()) end
end

---------------------------------------------------------------------------------------------------------------------
-- Settings window and chat commands

local app = UI:NewApp({
  name = "EverlookDB Mail",
  addon = ADDON,
  slash = "/email",
  tagline = "Tick mails and open them, Shift-click to take one, a tag on every mail, and Tab completes names when you send.",
  aiAbout = "EverlookDB Mail works inside Blizzard's mailbox. Inbox: a tick box on every mail with Select (all, none, auction house, sold, items back, alts, NPC, players, with money, with items), Open selected and Return selected buttons, an Open all button (skips C.O.D., GM mail and unread letters from players unless set otherwise; Shift-click it to ignore the filters; pauses when bags are full but still takes gold), Shift-click a mail to take everything in it, Ctrl-click a mail to return it, a small coloured tag on every mail (AH sold, AH expired, AH cancelled, AH won, AH outbid, Player, Your alt, NPC, C.O.D.), and one chat line with the gold you took when the mailbox closes. Send: Tab completes the suggested name, an arrow next to To: lists recent recipients, your alts, friends and guild, names complete as you type, the total cost when you send gold, and the gold amount as the subject when you leave it empty. With EverlookDB Auctions loaded it hands every mail to Auctions' income ledger.",
  height = 560,
  searchTop = true,
  icon = "Interface\\AddOns\\EverlookDBMail\\Media\\icon",
  position = function() return db end,
  feedbackURL = "https://github.com/quikmn/EverlookDBMail/issues",
})
ns.app = app

local function refresh()
  if ns.inbox and ns.inbox.refresh then pcall(ns.inbox.refresh) end
  if ns.send and ns.send.refresh then pcall(ns.send.refresh) end
end
ns.refresh = refresh

local function setting(def)
  def.after = def.after or refresh
  app:Setting(def)
end
local function aside() return ns.rivalName ~= nil end

setting({ key = "tags", type = "bool", label = "A tag on each mail: what it is",
  keywords = { "category", "label", "sold", "expired", "alt", "inbox", "colour", "tag" },
  desc = "A short coloured word on the right of the subject: AH sold, AH expired, AH cancelled, AH won, AH outbid, Player, Your alt, NPC or C.O.D.",
  get = function() return db.tags end, set = function(v) db.tags = v end, default = true })
setting({ key = "select", type = "bool", label = "Tick boxes: Open selected and Return selected",
  keywords = { "tick", "check", "checkbox", "select", "selected", "open selected", "return selected", "bulk", "several" },
  desc = "A tick box on the left of every mail, a Select button (all, none, auction house, sold, items back, alts...) and Open selected / Return selected at the top of the inbox.",
  get = function() return db.select end, set = function(v) db.select = v end, disabled = aside, default = true })
setting({ key = "shiftclick", type = "bool", label = "Shift-click a mail: take everything in it",
  keywords = { "shift", "click", "take", "loot", "package", "take all" },
  desc = "Its money and every item, without opening it. A plain click opens the mail as always. C.O.D. mail is never taken this way: open it to pay.",
  get = function() return db.shiftClick end, set = function(v) db.shiftClick = v end, disabled = aside, default = true })
setting({ key = "ctrlreturn", type = "bool", label = "Ctrl-click a mail: return it to the sender",
  keywords = { "ctrl", "control", "return", "send back", "bounce" },
  desc = "Only mail from players can be returned; auction house and NPC mail can't.",
  get = function() return db.ctrlReturn end, set = function(v) db.ctrlReturn = v end, disabled = aside, default = true })
setting({ key = "collected", type = "bool", label = "Say how much gold you took when the mailbox closes",
  keywords = { "gold", "collected", "money", "total", "chat", "summary", "income" },
  desc = "One line in chat, only when you took gold.",
  get = function() return db.collected end, set = function(v) db.collected = v end, default = true })
setting({ key = "ledger", type = "bool", label = "Tell EverlookDB Auctions' income ledger about every mail",
  keywords = { "auctions", "income", "ledger", "eah" },
  desc = "Sold auctions tick off \"money waiting\", items back tick off expired or cancelled auctions. Only when EverlookDB Auctions is loaded; it also reads the mail itself, and each mail counts once.",
  get = function() return db.ledger end, set = function(v) db.ledger = v end, default = true })

setting({ key = "open.ah", type = "bool", label = "Auction house mail", keywords = { "open all", "auction", "sold", "expired" },
  desc = "Sales, expired and cancelled auctions, bids won and outbid refunds.",
  get = function() return db.open.ah end, set = function(v) db.open.ah = v end, default = true })
setting({ key = "open.alts", type = "bool", label = "Mail from your alts", keywords = { "open all", "alt", "twink", "bank" },
  get = function() return db.open.alts end, set = function(v) db.open.alts = v end, default = true })
setting({ key = "open.npc", type = "bool", label = "Mail from NPCs and the game", keywords = { "open all", "npc", "quest", "system" },
  get = function() return db.open.npc end, set = function(v) db.open.npc = v end, default = true })
setting({ key = "open.players", type = "bool", label = "Mail from other players (already read)", keywords = { "open all", "player", "friend" },
  desc = "Mail from players that you have opened before.",
  get = function() return db.open.players end, set = function(v) db.open.players = v end, default = true })
setting({ key = "open.letters", type = "bool", label = "Also unread mail from players",
  keywords = { "open all", "letter", "unread", "read", "text" },
  desc = "Off: Open all leaves unread mail from players alone, so you don't miss a letter. C.O.D. and GM mail are never opened by Open all.",
  get = function() return db.open.letters end, set = function(v) db.open.letters = v end, default = false })
setting({ key = "delay", type = "number", label = "Pause between two takes", min = 0.15, max = 1.5, step = 0.05,
  keywords = { "speed", "throttle", "delay", "fast", "slow", "disconnect" },
  desc = "Seconds. Open all also waits for the server to answer each take.",
  fmt = "%.2f s",
  get = function() return db.delay end, set = function(v) db.delay = v end, default = 0.3 })

setting({ key = "send.tab", type = "bool", label = "Tab takes the suggested name",
  keywords = { "tab", "autocomplete", "complete", "suggestion", "name", "to" },
  desc = "In To:, Tab fills in the name that is suggested (the highlighted one). With nothing to complete, Tab moves to the next box as usual.",
  get = function() return db.send.tab end, set = function(v) db.send.tab = v end, disabled = aside, default = true })
setting({ key = "send.complete", type = "bool", label = "Complete names as you type",
  keywords = { "autocomplete", "complete", "typing" },
  desc = "From your recent recipients, alts, friends and guild. Tab or Enter keeps it; keep typing to change it.",
  get = function() return db.send.complete end, set = function(v) db.send.complete = v end, disabled = aside, default = true })
setting({ key = "send.recent", type = "bool", label = "Remember who you send mail to",
  keywords = { "recent", "recipients", "names", "history" },
  get = function() return db.send.recent end, set = function(v) db.send.recent = v end, default = true })
setting({ key = "send.max", type = "number", label = "Recent recipients kept", min = 3, max = 30, step = 1,
  keywords = { "recent", "how many" },
  get = function() return db.send.max end, set = function(v) db.send.max = v end,
  disabled = function() return not db.send.recent end, default = 12 })
setting({ key = "send.alts", type = "bool", label = "Your alts in the To: list", keywords = { "alts", "characters", "dropdown" },
  desc = "Your characters on this realm (each one is added when it logs in).",
  get = function() return db.send.alts end, set = function(v) db.send.alts = v end, default = true })
setting({ key = "send.friends", type = "bool", label = "Friends and guild in the To: list", keywords = { "friends", "guild", "dropdown", "contacts" },
  get = function() return db.send.friends end, set = function(v) db.send.friends = v end, default = true })
setting({ key = "send.total", type = "bool", label = "What the mail costs you in all, under the postage",
  keywords = { "postage", "cost", "total", "price" },
  desc = "Shown when you send gold or set C.O.D.",
  get = function() return db.send.total end, set = function(v) db.send.total = v end, default = true })
setting({ key = "send.wire", type = "bool", label = "Gold as the subject when you leave it empty",
  keywords = { "wire", "subject", "money", "gold", "send gold" },
  desc = "Send 5g with no subject and the subject becomes \"5g\". Type your own subject and it stays.",
  get = function() return db.send.wire end, set = function(v) db.send.wire = v end, disabled = aside, default = true })

app:Command("open", "open", "Open all now (at a mailbox)", function()
  if ns.inbox then ns.inbox.openAll() end
end, { "openall", "take" })
app:Command("stop", "stop", "stop Open all", function()
  if ns.inbox then ns.inbox.stop("Stopped.") end
end)
app:Command("alts", "alts", "your characters on this realm", function()
  local list = ns.altList()
  if #list == 0 then app:Print("no other characters on this realm yet: each one is added when it logs in."); return end
  local names = {}
  for _, a in ipairs(list) do names[#names + 1] = a.name end
  app:Print("your alts here: " .. table.concat(names, ", "))
end)
app:Command("forget", "forget <name>", "take a name off your alts and recent recipients", function(rest)
  local name = rest and rest:match("^%s*(%S+)")
  if not name then app:Print("|cffef5d5dforget who? Example: /email forget Anna|r"); return end
  if ns.forget(name) then app:Print(("forgot %s."):format(name)) else app:Print(("%s isn't on your lists."):format(name)) end
  refresh()
end)
app:StatusLines(function()
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  local lines = { ("%d alts here, %d recent recipients"):format(#ns.altList(), #(db and db.recent or {})) }
  lines[#lines + 1] = (api and api.version and api.version >= 4) and "EverlookDB Auctions: found, its income ledger hears every mail"
    or "EverlookDB Auctions: not loaded (Mail works on its own)"
  if ns.rivalName then lines[#lines + 1] = ns.stepAsideText() end
  return lines
end)

local function asideNote(stack)
  if ns.rivalName then UI.Note(stack, "|cffffd25a" .. ns.stepAsideText() .. "|r") end
end

app:Section("inbox", "Inbox", function(stack)
  asideNote(stack)
  UI.Header(stack, "Inbox", "Inside Blizzard's mailbox: a tag on every mail, tick boxes, and quick clicks.")
  app:Widget(stack, "tags")
  app:Widget(stack, "select")
  app:Widget(stack, "shiftclick")
  app:Widget(stack, "ctrlreturn")
  app:Widget(stack, "collected")
  UI.Note(stack, "On a tick box, Shift-click ticks every mail from the last one you ticked, and Ctrl-click every mail from the same sender.")
  UI.Header(stack, "EverlookDB Auctions", "Its income ledger ticks off sales and items back as you take them.")
  app:Widget(stack, "ledger")
  UI.Stat(stack, "EverlookDB Auctions", function()
    local api = rawget(_G, "EverlookDBAuctionsAPI")
    return (api and api.version and api.version >= 4) and "|cff62cf88found|r" or "|cff8d94a3not loaded|r: Mail works on its own"
  end)
end, { icon = "page", desc = "Tags, tick boxes, Shift- and Ctrl-click." })

app:Section("openall", "Open all", function(stack)
  asideNote(stack)
  UI.Header(stack, "Open all takes", "The money and items of these mails. When your bags are full it still takes the gold, then pauses; closing the mailbox stops it.")
  app:Widget(stack, "open.ah")
  app:Widget(stack, "open.alts")
  app:Widget(stack, "open.npc")
  app:Widget(stack, "open.players")
  app:Widget(stack, "open.letters")
  UI.Note(stack, "Shift-click Open all to take every mail whatever these say. Right-click it to come here.")
  UI.Header(stack, "Speed")
  app:Widget(stack, "delay")
  UI.Note(stack, "C.O.D. mail and mail from a Game Master are never taken by Open all, Open selected or Shift-click: open them yourself.")
end, { icon = "download", desc = "Which mail the Open all button takes." })

app:Section("sending", "Sending", function(stack)
  asideNote(stack)
  UI.Header(stack, "To:", "The arrow next to To: lists your recent recipients, alts, friends and guild.")
  app:Widget(stack, "send.tab")
  app:Widget(stack, "send.complete")
  app:Widget(stack, "send.recent")
  app:Widget(stack, "send.max")
  app:Widget(stack, "send.alts")
  app:Widget(stack, "send.friends")
  UI.Header(stack, "Gold")
  app:Widget(stack, "send.total")
  app:Widget(stack, "send.wire")
  UI.Stat(stack, "Your alts here", function()
    local names = {}
    for _, a in ipairs(ns.altList()) do names[#names + 1] = a.name end
    return #names > 0 and table.concat(names, ", ") or "none yet (each character is added when it logs in)"
  end)
  UI.Note(stack, "/email forget <name> takes a name off your recent recipients and alts.")
end, { icon = "share", desc = "Tab completion, the To: list and sending gold." })

---------------------------------------------------------------------------------------------------------------------
-- The API other addons read (EverlookDB Auctions asks isAlt)

local api = {
  version = 1,
  isAlt = function(name) return ns.isAlt(name) end,
  alts = function()
    local out = {}
    for _, a in ipairs(ns.altList()) do out[#out + 1] = a.name end
    return out
  end,
  lastScan = function()
    local out = {}
    for i, m in ipairs(ns.inbox and ns.inbox.list or {}) do
      local c = {}
      for k, v in pairs(m) do c[k] = v end
      out[i] = c
    end
    return out
  end,
}
EverlookDBMailAPI = setmetatable({}, {
  __index = function(_, k)
    if k == "categories" then
      local C = ns.C()
      return C and { ids = C.CATS, labels = C.LABEL } or nil
    end
    return api[k]
  end,
  __newindex = function() error("EverlookDBMailAPI is read-only", 2) end,
  __metatable = false,
})

---------------------------------------------------------------------------------------------------------------------
-- Loading

-- /mail too, when no other addon has it
local function slashFree(word)
  word = word:lower()
  for k, v in pairs(_G) do
    if type(k) == "string" and k:match("^SLASH_") and type(v) == "string" and v:lower() == word and not k:match("^SLASH_EVERLOOKMAIL") then
      return false
    end
  end
  return true
end
ns.slashFree = slashFree

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    EverlookMailDB = UI.Util.FillDefaults(type(EverlookMailDB) == "table" and EverlookMailDB or {}, ns.DEFAULTS)
    db = EverlookMailDB
  elseif event == "PLAYER_LOGIN" then
    pcall(ns.noteMe)
    ns.findRival()
    if slashFree("/mail") then
      SLASH_EVERLOOKMAIL2 = "/mail"
      ns.mailAlias = true
    end
  end
end)

app:RegisterSlash("EVERLOOKMAIL")
