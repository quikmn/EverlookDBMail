-- Offline tests for EverlookDB Mail against wowmock.lua: loading and defaults, reading and tagging the inbox, the
-- summary, Open all (what it takes and skips, full bags, the mailbox closing), shift-click, the hand-over to
-- EverlookDB Auctions, sending (recent recipients, alts, completion, postage), the API and the shared classifier.
local ROOT = ...
local ADDON = "EverlookDBMail"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passes = passes + 1
    print("  ok   " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("  FAIL " .. name .. "\n         " .. tostring(err))
  end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function last() return MOCK.log[#MOCK.log] or "" end

MOCK.secretsOn = false
MOCK.SetGroup(1)
MOCK.units.player.class = "MAGE"
MOCK.units.player.level = 60
UnitLevel = function() return 60 end
MOCK.now = 1700000000
time = function() return MOCK.now end
GetMoney = function() return 1000000 end
NUM_BAG_SLOTS = 4
ERR_INV_FULL = "Inventory is full."

---------------------------------------------------------------------------------------------------------------------
-- The mailbox

local function mail(t)
  t.money = t.money or 0; t.cod = t.cod or 0; t.days = t.days or 29; t.items = t.items or {}
  if t.canReply == nil then t.canReply = true end
  return t
end

MOCK.inbox = {}
MOCK.free = 10
MOCK.took = {}
MOCK.money = 0
local function compact()
  for i = #MOCK.inbox, 1, -1 do
    local m = MOCK.inbox[i]
    local any = m.money > 0
    for a = 1, 16 do if m.items[a] then any = true end end
    if not any and not m.canReply then table.remove(MOCK.inbox, i) end -- AH and NPC mail goes once empty
  end
end

GetInboxNumItems = function() return #MOCK.inbox, #MOCK.inbox + (MOCK.extra or 0) end
GetInboxHeaderInfo = function(i)
  local m = MOCK.inbox[i]
  if not m then return nil end
  local n, first = 0, nil
  for a = 1, 16 do if m.items[a] then n = n + 1; first = first or m.items[a] end end
  return "pkg", "stat", m.sender, m.subject, m.money, m.cod, m.days, n, m.read or false, false, false, m.canReply,
    m.isGM or false, first and first.count, first and ("item:" .. first.id)
end
GetInboxItem = function(i, a)
  local m = MOCK.inbox[i]
  local it = m and m.items[a]
  if it then return it.name, it.id, "tex", it.count, 2, true, false end
end
GetInboxItemLink = function(i, a)
  local m = MOCK.inbox[i]
  local it = m and m.items[a]
  return it and ("|Hitem:" .. it.id .. "|h[" .. it.name .. "]|h") or nil
end
GetInboxInvoiceInfo = function(i)
  local m = MOCK.inbox[i]
  local v = m and m.invoice
  if v then return v.type, v.item, v.buyer, v.bid, v.buyout, v.deposit, v.cut, 0, 0, 0, v.count end
end
TakeInboxMoney = function(i)
  local m = MOCK.inbox[i]
  MOCK.took[#MOCK.took + 1] = "money:" .. (m and m.subject or "?")
  if m then MOCK.money = MOCK.money + m.money; m.money = 0 end
  compact()
end
TakeInboxItem = function(i, a)
  local m = MOCK.inbox[i]
  MOCK.took[#MOCK.took + 1] = "item:" .. (m and m.items[a] and m.items[a].name or "?")
  if m then m.items[a] = nil end
  MOCK.free = MOCK.free - 1
  compact()
end
AutoLootMailItem = function(i) MOCK.took[#MOCK.took + 1] = "autoloot:" .. i end
CheckInbox = function() MOCK.checked = true end
C_Mail = { IsCommandPending = function() return false end, SetOpeningAll = function(v) MOCK.openingAll = v end, HasInboxMoney = function() return false end }
C_Container = { GetContainerNumFreeSlots = function(bag) if bag == 0 then return MOCK.free, 0 end return 0, 0 end }
GetSendMailPrice = function() return 30 end
MOCK.sent = {}
SendMail = function(name, subject) MOCK.sent[#MOCK.sent + 1] = name end

MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
InboxFrame = CreateFrame("Frame", "InboxFrame", MailFrame)
InboxFrame.pageNum = 1
InboxFrame.Update = function() end
MOCK.plainClicks = 0
for r = 1, 7 do
  CreateFrame("Frame", "MailItem" .. r, InboxFrame)
  local b = CreateFrame("Button", "MailItem" .. r .. "Button", _G["MailItem" .. r])
  b:SetScript("OnClick", function(self) MOCK.plainClicks = MOCK.plainClicks + 1 end)
end
SendMailFrame = CreateFrame("Frame", "SendMailFrame", MailFrame)
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
SendMailSubjectEditBox = CreateFrame("EditBox", "SendMailSubjectEditBox", SendMailFrame)
function SendMailNameEditBox:HighlightText(a, b) self.hl = { a, b } end

local function settle(n)
  for _ = 1, n or 60 do
    if #MOCK.timers == 0 then return end
    MOCK.RunTimers()
  end
end

local function standardInbox()
  MOCK.inbox = {
    mail({ sender = "Auction House", subject = "Auction successful: Linen Cloth (20)", money = 1030, canReply = false,
      invoice = { type = "seller", item = "Linen Cloth", buyer = "Bob", bid = 1000, buyout = 1000, deposit = 80, cut = 50, count = 20 } }),
    mail({ sender = "Auction House", subject = "Auction expired: Copper Ore (5)", canReply = false,
      items = { { name = "Copper Ore", id = 2770, count = 5 } } }),
    mail({ sender = "Auction House", subject = "Auction canceled: Wool Cloth", canReply = false,
      items = { { name = "Wool Cloth", id = 2592, count = 1 } } }),
    mail({ sender = "Auction House", subject = "Auction won: Silk Cloth", canReply = false,
      invoice = { type = "buyer", item = "Silk Cloth", buyer = "Sam", bid = 500, buyout = 500, deposit = 0, cut = 0, count = 1 },
      items = { { name = "Silk Cloth", id = 4306, count = 1 } } }),
    mail({ sender = "Anna", subject = "for you", money = 5000, read = false }),
    mail({ sender = "Bankalt", subject = "mats", items = { { name = "Iron Ore", id = 2772, count = 20 }, [3] = { name = "Coal", id = 3857, count = 2 } }, read = true }),
    mail({ sender = "Thrall", subject = "Your reward", money = 200, canReply = false }),
    mail({ sender = "Seller", subject = "pay me", cod = 999, items = { { name = "Mageweave", id = 4338, count = 1 } } }),
  }
end

---------------------------------------------------------------------------------------------------------------------
-- Auctions, as far as Mail sees it: its API with the mail door

local auctionsCalls = { scanned = 0, taken = {} }
EverlookDBAuctionsAPI = { version = 4, mail = {
  version = 1,
  scanned = function(list) auctionsCalls.scanned = auctionsCalls.scanned + 1; auctionsCalls.lastList = list; return true end,
  taken = function(m, part, slot) auctionsCalls.taken[#auctionsCalls.taken + 1] = (m.cat or "?") .. ":" .. part .. ":" .. tostring(slot); return true end,
} }

---------------------------------------------------------------------------------------------------------------------

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

local function loadToc()
  local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
      local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
      if not chunk then error("syntax: " .. err) end
      setfenv(chunk, addonEnv)
      chunk(ADDON, ns)
    end
  end
end

step("loads, fills the defaults, has /email and takes /mail when it is free", function()
  EverlookMailDB = nil
  loadToc()
  MOCK.Fire("ADDON_LOADED", ADDON)
  MOCK.Fire("PLAYER_LOGIN")
  local db = EverlookMailDB
  check(db and db.tags == true and db.shiftClick == true and db.open.letters == false and db.delay == 0.3, "defaults")
  check(SlashCmdList.EVERLOOKMAIL and SLASH_EVERLOOKMAIL1 == "/email", "no /email")
  check(SLASH_EVERLOOKMAIL2 == "/mail", "/mail alias not taken while free")
  check(db.alts["1"] and db.alts["1"].Tester and db.alts["1"].Tester.class == "MAGE", "this character not noted as an alt")
end)

step("/mail is left alone when another addon has it", function()
  SLASH_SOMEOTHERMAIL1 = "/mail"
  check(ns.slashFree("/mail") == false, "taken /mail looks free")
  SLASH_SOMEOTHERMAIL1 = nil
  check(ns.slashFree("/mail") == true, "free /mail looks taken")
end)

step("bare /email opens the settings window, with no errors", function()
  local before = #MOCK.errors
  SlashCmdList.EVERLOOKMAIL("")
  local w = _G.EverlookDBMailOptionsWindow or _G.EVERLOOKDBMAILOptionsWindow
  check(ns.app.window and ns.app.window:IsShown(), "window not shown")
  check(#MOCK.errors == before, "errors: " .. tostring(MOCK.errors[#MOCK.errors]))
  ns.app.window:Hide()
end)

step("every mail is read and given its category; alts are your own characters", function()
  EverlookMailDB.alts["1"].Bankalt = { class = "WARRIOR", level = 20, t = 1 }
  standardInbox()
  MOCK.Fire("MAIL_SHOW")
  settle()
  local cats = {}
  for _, m in ipairs(ns.inbox.list) do cats[#cats + 1] = m.cat end
  check(table.concat(cats, ",") == "ah_sold,ah_expired,ah_cancelled,ah_won,player,alt,npc,cod", "categories: " .. table.concat(cats, ","))
  local sold = ns.inbox.list[1]
  check(sold.invoice and sold.invoice.buyer == "Bob" and sold.invoice.cut == 50 and sold.item == "Linen Cloth", "invoice not read")
  check(ns.inbox.list[2].item == "Copper Ore" and ns.inbox.list[2].count == 5, "subject count not parsed")
  check(#ns.inbox.list[6].items == 2 and ns.inbox.list[6].items[2].slot == 3, "attachments in their slots")
  check(ns.inbox.list[1].exp == MOCK.now + 29 * 86400, "expiry")
  check(EverlookDBMailAPI.isAlt("Bankalt") and not EverlookDBMailAPI.isAlt("Anna") and not EverlookDBMailAPI.isAlt("Tester"), "isAlt")
end)

step("each inbox row shows its tag; tags off hides them", function()
  check(MailItem1.everlookTag:GetText():find("AH sold"), "row 1: " .. tostring(MailItem1.everlookTag:GetText()))
  check(MailItem6.everlookTag:GetText():find("Your alt"), "row 6")
  check(MailItem7.everlookTag:GetText():find("NPC"), "row 7")
  EverlookMailDB.tags = false
  ns.inbox.refresh()
  check(not MailItem1.everlookTag:IsShown(), "tag still shown when off")
  EverlookMailDB.tags = true
  ns.inbox.refresh()
  check(MailItem1.everlookTag:IsShown(), "tag not back")
end)

step("the summary has the totals per kind and what Open all will take", function()
  local p = ns.inbox.panel()
  check(p and p:IsShown(), "no panel")
  check(p.title:GetText() == "Inbox: 8 mails", "title " .. tostring(p.title:GetText()))
  local shown = {}
  for _, r in ipairs(p.rows) do if r:IsShown() then shown[#shown + 1] = r.cat end end
  check(#shown == 8, "rows " .. table.concat(shown, ","))
  check(p.rows[1].value:GetText():find("10"), "sold money " .. tostring(p.rows[1].value:GetText()))
  -- Open all takes AH (4), the alt (1), the NPC (1); not the unread player letter, not C.O.D.
  check(p.button:GetText() == "Open all (6)", "button " .. tostring(p.button:GetText()))
  check(p.status:GetText():find("2 left alone"), "status " .. tostring(p.status:GetText()))
end)

step("the inbox goes to EverlookDB Auctions' ledger as it is read", function()
  check(auctionsCalls.scanned > 0 and #auctionsCalls.lastList == 8, "not handed over")
  EverlookMailDB.ledger = false
  local n = auctionsCalls.scanned
  ns.inbox.scan()
  check(auctionsCalls.scanned == n, "handed over while off")
  EverlookMailDB.ledger = true
end)

step("Open all takes money and items, last mail first, skips C.O.D. and unread letters, and tells Auctions", function()
  MOCK.took = {}
  auctionsCalls.taken = {}
  ns.inbox.openAll()
  check(MOCK.openingAll == true, "SetOpeningAll not set")
  settle(200)
  check(ns.inbox.state() == nil, "still running")
  local took = table.concat(MOCK.took, ",")
  check(took == "money:Your reward,item:Iron Ore,item:Coal,item:Silk Cloth,item:Wool Cloth,item:Copper Ore,money:Auction successful: Linen Cloth (20)", "took " .. took)
  check(MOCK.money == 1230, "money " .. MOCK.money)
  check(#MOCK.inbox == 3 and MOCK.inbox[1].sender == "Anna" and MOCK.inbox[3].cod == 999, "left " .. #MOCK.inbox)
  check(#auctionsCalls.taken == 7 and auctionsCalls.taken[1] == "npc:money:nil" and auctionsCalls.taken[2] == "alt:item:1", "auctions: " .. table.concat(auctionsCalls.taken, ","))
  check(last():find("Done") and last():find("7 items") == nil and last():find("5 items"), "message " .. last())
  check(MOCK.openingAll == false, "SetOpeningAll not cleared")
end)

step("unread letters too when that is on", function()
  EverlookMailDB.open.letters = true
  MOCK.took = {}
  ns.inbox.openAll()
  settle(200)
  check(table.concat(MOCK.took, ",") == "money:for you", "took " .. table.concat(MOCK.took, ","))
  EverlookMailDB.open.letters = false
end)

step("full bags pause Open all with a message; Continue goes on", function()
  standardInbox()
  ns.inbox.scan()
  MOCK.free = 0
  MOCK.took = {}
  ns.inbox.openAll()
  settle(200)
  local q = ns.inbox.state()
  check(q and q.paused and q.why == "bags", "not paused")
  check(last():find("bags are full"), "no message: " .. last())
  check(table.concat(MOCK.took, ",") == "money:Your reward", "took while full " .. table.concat(MOCK.took, ","))
  check(ns.inbox.panel().button:GetText() == "Continue", "button " .. ns.inbox.panel().button:GetText())
  MOCK.free = 10
  ns.inbox.openAll()
  settle(200)
  check(ns.inbox.state() == nil and #MOCK.took == 7, "did not finish: " .. #MOCK.took)
end)

step("the bag-full error from the server pauses it too", function()
  standardInbox()
  ns.inbox.scan()
  ns.inbox.openAll()
  MOCK.RunTimers()
  MOCK.Fire("UI_ERROR_MESSAGE", 1, "Inventory is full.")
  check(ns.inbox.state() and ns.inbox.state().paused, "not paused")
  ns.inbox.stop("Stopped.")
  check(ns.inbox.state() == nil, "not stopped")
end)

step("closing the mailbox stops Open all at once", function()
  standardInbox()
  ns.inbox.scan()
  MOCK.took = {}
  ns.inbox.openAll()
  MOCK.RunTimers()
  MailFrame:Hide()
  MOCK.Fire("MAIL_CLOSED")
  settle(200)
  check(ns.inbox.state() == nil, "still running")
  check(#MOCK.took == 1, "kept taking: " .. #MOCK.took)
  check(last():find("mailbox closed"), "message " .. last())
  check(not ns.inbox.panel():IsShown(), "panel still shown")
  MailFrame:Show()
end)

step("shift-left-click takes all of that one mail; a plain click is Blizzard's", function()
  standardInbox()
  ns.inbox.scan()
  MOCK.took = {}
  MOCK.mods.shift = true
  MailItem6Button.index = 6
  MailItem6Button:GetScript("OnClick")(MailItem6Button, "LeftButton")
  settle(200)
  check(table.concat(MOCK.took, ",") == "item:Iron Ore,item:Coal", "took " .. table.concat(MOCK.took, ","))
  check(MOCK.plainClicks == 0, "Blizzard's click ran too")
  MOCK.mods.shift = false
  MailItem6Button:GetScript("OnClick")(MailItem6Button, "LeftButton")
  check(MOCK.plainClicks == 1, "plain click not passed on")
  MOCK.mods.shift = true
  MailItem6Button:GetScript("OnClick")(MailItem6Button, "RightButton")
  check(MOCK.plainClicks == 2, "right click not passed on")
  MOCK.mods.shift = false
end)

step("shift-click never pays C.O.D.; it takes unread letters (you asked)", function()
  standardInbox()
  ns.inbox.scan()
  MOCK.took = {}
  MOCK.mods.shift = true
  MailItem8 = nil
  check(ns.inbox.takeMail(8) == false and last():find("C.O.D."), "C.O.D. taken: " .. last())
  ns.inbox.takeMail(5)
  settle(200)
  check(table.concat(MOCK.took, ",") == "money:for you", "letter " .. table.concat(MOCK.took, ","))
  MOCK.mods.shift = false
end)

step("shift-click off: Blizzard's click as always", function()
  EverlookMailDB.shiftClick = false
  MOCK.mods.shift = true
  local n = MOCK.plainClicks
  MOCK.took = {}
  MailItem1Button.index = 1
  MailItem1Button:GetScript("OnClick")(MailItem1Button, "LeftButton")
  check(MOCK.plainClicks == n + 1 and #MOCK.took == 0, "not passed on")
  MOCK.mods.shift = false
  EverlookMailDB.shiftClick = true
end)

step("more mail on the server: Open all says so and asks for it", function()
  MOCK.inbox = { mail({ sender = "Thrall", subject = "gift", money = 5, canReply = false }) }
  MOCK.extra = 12
  MOCK.checked = false
  ns.inbox.openAll()
  settle(200)
  check(last():find("12 more on the server") and MOCK.checked, "message " .. last())
  MOCK.extra = nil
end)

step("sending: recent recipients remembered when the mail goes, newest first, once each", function()
  MOCK.Fire("MAIL_SHOW")
  SendMail("anna", "hi", "")
  MOCK.Fire("MAIL_SEND_SUCCESS")
  SendMail("Bob", "hi", "")
  MOCK.Fire("MAIL_FAILED")
  SendMail("Carl", "hi", "")
  MOCK.Fire("MAIL_SEND_SUCCESS")
  SendMail("Anna", "hi", "")
  MOCK.Fire("MAIL_SEND_SUCCESS")
  local r = EverlookMailDB.recent
  check(#r == 2 and r[1].name == "Anna" and r[2].name == "Carl", "recent " .. #r .. " " .. tostring(r[1] and r[1].name))
  EverlookMailDB.send.max = 3
  for _, n in ipairs({ "Dan", "Eve", "Fay" }) do SendMail(n); MOCK.Fire("MAIL_SEND_SUCCESS") end
  check(#r == 3 and r[1].name == "Fay", "max not kept")
end)

step("the To: list has recent names, then your alts; picking one fills To:", function()
  local names = ns.send.names()
  local list = {}
  for _, n in ipairs(names) do list[#list + 1] = n.name end
  check(table.concat(list, ",") == "Fay,Eve,Dan,Bankalt", "names " .. table.concat(list, ","))
  check(names[4].alt and names[4].level == 20, "alt info")
  ns.send.showMenu(SendMailNameEditBox)
  local menu = ns.send.menu()
  check(menu:IsShown() and menu.buttons[4].name == "Bankalt", "menu")
  menu.buttons[4]:GetScript("OnClick")(menu.buttons[4])
  check(SendMailNameEditBox:GetText() == "Bankalt" and not menu:IsShown(), "To: not filled")
end)

step("names complete as you type", function()
  check(ns.send.complete("ba") == "Bankalt" and ns.send.complete("e") == nil and ns.send.complete("Bankalt") == nil, "complete")
  SendMailNameEditBox:SetText("Fa")
  SendMailNameEditBox:GetScript("OnTextChanged")(SendMailNameEditBox, true)
  check(SendMailNameEditBox:GetText() == "Fay" and SendMailNameEditBox.hl[1] == 2, "not completed: " .. SendMailNameEditBox:GetText())
  EverlookMailDB.send.complete = false
  SendMailNameEditBox:SetText("Da")
  SendMailNameEditBox:GetScript("OnTextChanged")(SendMailNameEditBox, true)
  check(SendMailNameEditBox:GetText() == "Da", "completed while off")
  EverlookMailDB.send.complete = true
end)

step("postage is shown", function()
  check(ns.send.costText():find("Postage 30"), ns.send.costText())
end)

step("/email forget and /email alts", function()
  SlashCmdList.EVERLOOKMAIL("alts")
  check(last():find("Bankalt"), last())
  SlashCmdList.EVERLOOKMAIL("forget bankalt")
  check(not ns.isAlt("Bankalt") and last():find("forgot"), last())
end)

step("the API is read-only and gives the last scan as copies", function()
  check(EverlookDBMailAPI.version == 1, "version")
  local ok = pcall(function() EverlookDBMailAPI.x = 1 end)
  check(not ok, "writable")
  local s = EverlookDBMailAPI.lastScan()
  check(type(s) == "table", "lastScan")
  if s[1] then s[1].cat = "changed"; check(ns.inbox.list[1].cat ~= "changed", "not a copy") end
  check(EverlookDBMailAPI.categories.labels.ah_sold == "AH sold", "categories")
end)

step("MailClassify.lua is the same file as EverlookDB Auctions' copy", function()
  local mine = assert(io.open(ROOT .. "/MailClassify.lua", "rb")):read("*a"):gsub("\r\n", "\n")
  local f = io.open(ROOT .. "/../EverlookDBAuctions/MailClassify.lua", "rb")
  if not f then print("         (EverlookDB Auctions not next to this repo: skipped)") return end
  local theirs = f:read("*a"):gsub("\r\n", "\n")
  check(mine == theirs, "MailClassify.lua differs from EverlookDBAuctions' copy: copy it over (and bump MINOR there)")
end)

step("the classifier, by hand: subjects, invoices, GM and C.O.D.", function()
  local C = LibStub("EverlookMailClassify-1")
  check(C.classify({ subject = "Outbid on Silk Cloth", canReply = false }) == "ah_outbid", "outbid")
  check(C.classify({ subject = "Sale Pending: Silk Cloth", canReply = false }) == "ah_sold", "pending")
  check(C.classify({ subject = "x", isGM = true, canReply = true, sender = "GM" }) == "npc", "gm")
  check(C.classify({ subject = "Auction won: X", cod = 5 }) == "cod", "cod first")
  check(C.classify({ subject = "hello" }) == "other", "other")
  local k1 = C.key({ subject = "a", sender = "Anna", cod = 0 })
  check(not k1:find("Anna"), "a name in the key")
end)

step("no stray globals", function()
  local allowed = { EverlookMailDB = true, EverlookDBMailAPI = true, SLASH_EVERLOOKMAIL1 = true, SLASH_EVERLOOKMAIL2 = true }
  for k in pairs(globalWrites) do
    check(allowed[k], "global written: " .. tostring(k))
  end
end)

step("no Lua errors along the way", function()
  check(#MOCK.errors == 0, tostring(MOCK.errors[1]))
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
