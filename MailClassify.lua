-- EverlookMailClassify: reads every mail in the inbox and says what each one is. Shared by EverlookDB Auctions (its
-- income ledger) and EverlookDB Mail (the inbox tags and the summary).
--
-- Single source of truth: D:\Dev\EverlookDBAuctions\MailClassify.lua. EverlookDB Mail carries a byte-identical copy
-- (its tests compare them). Versioned with LibStub: when both addons are loaded, the newest copy is the one both use.
-- Bump MINOR whenever this file changes.
--
--   local C = LibStub("EverlookMailClassify-1")
--   local m = C.read(index[, isAlt])  -- everything about one mail, classified (nil when there is no such mail)
--   local list = C.scan(isAlt)        -- every mail in the inbox, read and classified, in inbox order
--   C.classify(m, isAlt)              -- the category of a mail read by C.read (or built by hand in tests)
--   C.key(m)                          -- what stays the same about a mail while you take things out of it
--
-- A mail (m): { index, sender, subject, money, cod, daysLeft, exp (time it expires), itemCount, wasRead, wasReturned,
--   textCreated, canReply, isGM, items = { { slot, name, id, count, quality, link } },
--   invoice = { type = "seller"|"seller_temp_invoice"|"buyer", item, buyer, bid, buyout, deposit, cut, delay, count },
--   cat, item (the item the subject or invoice names), count, pending (sold, money not sent yet) }
-- Categories: ah_sold (money), ah_expired (item back), ah_cancelled (item back), ah_won (item bought), ah_outbid
-- (money back), player, alt (one of your characters), npc (an NPC or the game), cod, other.
--
-- Every API read is in pcall; nothing here throws. GetInboxText is never called: it marks a mail as read.
local MAJOR, MINOR = "EverlookMailClassify-1", 1
local C = LibStub and LibStub:NewLibrary(MAJOR, MINOR)
if not C then return end

C.CATS = { "ah_sold", "ah_expired", "ah_cancelled", "ah_won", "ah_outbid", "player", "alt", "npc", "cod", "other" }
C.LABEL = {
  ah_sold = "AH sold", ah_expired = "AH expired", ah_cancelled = "AH cancelled", ah_won = "AH won",
  ah_outbid = "AH outbid", player = "Player", alt = "Your alt", npc = "NPC", cod = "C.O.D.", other = "Other",
}
-- what each brings: money, an item back, an item bought
C.WHAT = {
  ah_sold = "money", ah_expired = "item back", ah_cancelled = "item back", ah_won = "item bought",
  ah_outbid = "money back", player = "from a player", alt = "from your alt", npc = "from an NPC or the game",
  cod = "pay on delivery", other = "other",
}
C.ATTACHMENTS = 16   -- ATTACHMENTS_MAX in the game's MailFrame.lua

local function okv(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- A game format string ("Auction expired: %s") as a pattern that captures the %s.
local function pattern(f)
  if type(f) ~= "string" or not f:find("%%s") then return nil end
  f = f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
  return "^" .. f .. "$"
end
C.pattern = pattern

-- The mail subjects the auction house sends, from GlobalStrings (English when the game doesn't have one).
C.SUBJECTS = {
  { "ah_sold", "AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s" },
  { "ah_sold", "AUCTION_INVOICE_MAIL_SUBJECT", "Sale Pending: %s", pending = true },
  { "ah_expired", "AUCTION_EXPIRED_MAIL_SUBJECT", "Auction expired: %s" },
  { "ah_cancelled", "AUCTION_REMOVED_MAIL_SUBJECT", "Auction canceled: %s" },
  { "ah_won", "AUCTION_WON_MAIL_SUBJECT", "Auction won: %s" },
  { "ah_outbid", "AUCTION_OUTBID_MAIL_SUBJECT", "Outbid on %s" },
}

-- "Linen Cloth (20)" -> "Linen Cloth", 20
local function splitCount(s)
  if type(s) ~= "string" then return nil end
  local name, n = s:match("^(.-)%s*%((%d+)%)$")
  if name and name ~= "" then return name, tonumber(n) end
  return s, nil
end
C.splitCount = splitCount

-- The auction house kind of a subject, the item it names and how many: "ah_expired", "Linen Cloth", 20.
function C.parseSubject(subject)
  subject = okv(subject)
  if type(subject) ~= "string" or subject == "" then return nil end
  for _, s in ipairs(C.SUBJECTS) do
    local f = rawget(_G, s[2])
    local forms = { s[3] }
    if type(f) == "string" and f ~= s[3] then forms = { f, s[3] } end
    for _, form in ipairs(forms) do
      local p = pattern(form)
      local what = p and subject:match(p)
      if what then
        local name, n = splitCount(what)
        return s[1], name, n, s.pending
      end
    end
  end
  return nil
end

-- "Name-Realm" -> "Name"; nil for nothing.
function C.shortName(sender)
  sender = okv(sender)
  if type(sender) ~= "string" or sender == "" then return nil end
  return (sender:match("^([^%-]+)") or sender)
end

-- The category of a mail. isAlt(name) -> true for your own characters (optional).
function C.classify(m, isAlt)
  if type(m) ~= "table" then return "other" end
  local kind, name, n, pending = C.parseSubject(m.subject)
  local inv = m.invoice
  m.item, m.count, m.pending = nil, nil, nil
  if inv and inv.type then
    m.item, m.count = inv.item, inv.count
  end
  if (m.cod or 0) > 0 then
    m.cat = "cod"
  elseif inv and (inv.type == "seller" or inv.type == "seller_temp_invoice") then
    m.cat, m.pending = "ah_sold", inv.type == "seller_temp_invoice" or nil
  elseif inv and inv.type == "buyer" then
    m.cat = "ah_won"
  elseif kind then
    m.cat, m.pending = kind, pending or nil
    m.item, m.count = m.item or name, m.count or n
  elseif m.isGM then
    m.cat = "npc"
  elseif m.canReply == false then
    -- nobody to reply to: an NPC, a quest, a holiday, the game itself
    m.cat = "npc"
  elseif m.sender and isAlt and C.shortName(m.sender) and isAlt(C.shortName(m.sender)) then
    m.cat = "alt"
  elseif m.sender and m.canReply then
    m.cat = "player"
  else
    m.cat = "other"
  end
  if m.cat == "ah_sold" and not m.item and kind == "ah_sold" then m.item, m.count = name, n end
  if not m.item and m.items and m.items[1] then m.item = m.items[1].name end
  return m.cat
end

-- One mail, everything the game says about it without opening it.
function C.read(i, isAlt, now)
  if type(i) ~= "number" or i < 1 then return nil end
  local okH, packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned,
    textCreated, canReply, isGM, firstQty, firstLink = call(GetInboxHeaderInfo, i)
  if not okH then return nil end
  subject = okv(subject)
  if subject == nil and okv(sender) == nil and okv(money) == nil then return nil end
  now = now or (time and time()) or 0
  local m = {
    index = i, sender = okv(sender), subject = subject, money = tonumber(okv(money)) or 0, cod = tonumber(okv(cod)) or 0,
    daysLeft = tonumber(okv(daysLeft)), itemCount = tonumber(okv(itemCount)) or 0, wasRead = okv(wasRead) and true or false,
    wasReturned = okv(wasReturned) and true or false, textCreated = okv(textCreated) and true or false,
    canReply = okv(canReply) and true or false, isGM = okv(isGM) and true or false,
    icon = okv(packageIcon) or okv(stationeryIcon), firstQty = okv(firstQty), firstLink = okv(firstLink), items = {},
  }
  if m.daysLeft then m.exp = math.floor(now + m.daysLeft * 86400 + 0.5) end
  if m.itemCount > 0 then
    for a = 1, C.ATTACHMENTS do
      local okI, name, id, tex, count, quality, canUse, isCurrency = call(GetInboxItem, i, a)
      if okI and okv(name) then
        local okL, link = call(GetInboxItemLink, i, a)
        m.items[#m.items + 1] = { slot = a, name = okv(name), id = tonumber(okv(id)), count = tonumber(okv(count)) or 1,
          quality = tonumber(okv(quality)), icon = okv(tex), link = okL and okv(link) or nil, currency = okv(isCurrency) and true or nil }
      end
    end
  end
  local okV, itype, item, player, bid, buyout, deposit, cut, delay, etaH, etaM, count = call(GetInboxInvoiceInfo, i)
  itype = okV and okv(itype) or nil
  if itype then
    m.invoice = { type = itype, item = okv(item), buyer = okv(player), bid = tonumber(okv(bid)) or 0,
      buyout = tonumber(okv(buyout)) or 0, deposit = tonumber(okv(deposit)) or 0, cut = tonumber(okv(cut)) or 0,
      delay = tonumber(okv(delay)), count = tonumber(okv(count)) }
  end
  C.classify(m, isAlt)
  return m
end

-- Every mail in the inbox, in order.
function C.scan(isAlt, now)
  local out = {}
  local okN, n = call(GetInboxNumItems)
  n = okN and tonumber(okv(n)) or 0
  for i = 1, n do
    local m = C.read(i, isAlt, now)
    if m then out[#out + 1] = m end
  end
  return out
end

-- A short fingerprint of a text (a name), so a name can be recognised without being saved.
function C.hash(s)
  if type(s) ~= "string" then return nil end
  s = s:lower()
  local h = 5381
  for k = 1, #s do h = (h * 33 + s:byte(k)) % 4294967296 end
  return ("%08x"):format(h)
end

-- What stays the same about a mail while you take its money and items: subject, sender (fingerprint) and C.O.D.
-- Its expiry (m.exp) is compared separately, with some slack (C.SAME_MAIL seconds).
C.SAME_MAIL = 180
function C.key(m)
  if type(m) ~= "table" then return nil end
  return table.concat({ tostring(m.subject or ""), C.hash(m.sender or "") or "", tostring(m.cod or 0) }, "|")
end

-- Totals per category: { [cat] = { n = mails, money = copper, items = attachments, cod = copper } }.
function C.totals(list)
  local t = {}
  for _, m in ipairs(list or {}) do
    local c = m.cat or "other"
    local row = t[c] or { n = 0, money = 0, items = 0, cod = 0 }
    row.n = row.n + 1
    row.money = row.money + (m.money or 0)
    row.items = row.items + (m.items and #m.items or m.itemCount or 0)
    row.cod = row.cod + (m.cod or 0)
    t[c] = row
  end
  return t
end

return C
