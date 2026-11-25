-- Offline tests for EverlookDB Mail against wowmock.lua: loading and defaults, reading and tagging the inbox, the tick
-- boxes and Select, Open selected and Return selected, Open all (what it takes and skips, full bags, the mailbox
-- closing, more mail on the server), Shift-click take-all and Ctrl-click return (through the cover frame, never
-- Blizzard's own click), the hand-over to EverlookDB Auctions, sending (recent recipients, alts, friends and guild,
-- completion, Tab, the To: list, the total, gold as the subject), stepping aside for another mail addon, the API and
-- the shared classifier.
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
local function logHas(s)
  for _, l in ipairs(MOCK.log) do if l:find(s, 1, true) then return true end end
  return false
end

MOCK.secretsOn = false
MOCK.SetGroup(1)
MOCK.units.player.class = "MAGE"
MOCK.units.player.level = 60
UnitLevel = function() return 60 end
MOCK.now = 1700000000
time = function() return MOCK.now end
MOCK.gold = 1000000
GetMoney = function() return MOCK.gold end
NUM_BAG_SLOTS = 4
ERR_INV_FULL = "Inventory is full."
MOCK.loaded = {}
C_AddOns.IsAddOnLoaded = function(name) return MOCK.loaded[name] or false end

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
local function hasStuff(m)
  if m.money > 0 then return true end
  for a = 1, 16 do if m.items[a] then return true end end
  return false
end

GetInboxNumItems = function() return #MOCK.inbox, #MOCK.inbox + (MOCK.extra or 0) end
GetInboxHeaderInfo = function(i)
  local m = MOCK.inbox[i]
  if not m then return nil end
  local n, first = 0, nil
  for a = 1, 16 do if m.items[a] then n = n + 1; first = first or m.items[a] end end
  return "pkg", "stat", m.sender, m.subject, m.money, m.cod, m.days, n, m.read or false, m.returned or false, false, m.canReply,
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
-- the clock moves on with every take, so a mail's expiry (now + days left) moves by a second each time: a mail must
-- still be known as the same one
TakeInboxMoney = function(i)
  local m = MOCK.inbox[i]
  MOCK.took[#MOCK.took + 1] = "money:" .. (m and m.subject or "?")
  if m then MOCK.money = MOCK.money + m.money; MOCK.gold = MOCK.gold + m.money; m.money = 0 end
  MOCK.now = MOCK.now + 1
  compact()
  MOCK.Fire("PLAYER_MONEY")
end
TakeInboxItem = function(i, a)
  local m = MOCK.inbox[i]
  MOCK.took[#MOCK.took + 1] = "item:" .. (m and m.items[a] and m.items[a].name or "?")
  if m then m.items[a] = nil end
  MOCK.free = MOCK.free - 1
  MOCK.now = MOCK.now + 1
  compact()
end
MOCK.returned = {}
ReturnInboxItem = function(i)
  local m = MOCK.inbox[i]
  MOCK.returned[#MOCK.returned + 1] = m and m.subject or "?"
  if m then table.remove(MOCK.inbox, i) end
end
InboxItemCanDelete = function(i)
  local m = MOCK.inbox[i]
  return not m or not m.canReply or m.returned or not hasStuff(m)
end
AutoLootMailItem = function(i) MOCK.took[#MOCK.took + 1] = "autoloot:" .. i end
CheckInbox = function() MOCK.checked = true end
C_Mail = { IsCommandPending = function() return false end, SetOpeningAll = function(v) MOCK.openingAll = v end, HasInboxMoney = function() return false end }
C_Container = { GetContainerNumFreeSlots = function(bag) if bag == 0 then return MOCK.free, 0 end return 0, 0 end }
GetSendMailPrice = function() return 30 end
MOCK.sent = {}
SendMail = function(name, subject) MOCK.sent[#MOCK.sent + 1] = name end
C_FriendList = {
  GetNumFriends = function() return 2 end,
  GetFriendInfoByIndex = function(i)
    return ({ { name = "Frieda", connected = true, className = "Priest" }, { name = "Fritz", connected = false } })[i]
  end,
}
IsInGuild = function() return true end
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(i)
  if i == 1 then return "Gunnar-MockRealm", "Member", 1, 40, "Warrior", "Ironforge", "", "", false, 0, "WARRIOR" end
  if i == 2 then return "Greta-MockRealm", "Member", 1, 50, "Mage", "Stormwind", "", "", true, 0, "MAGE" end
end
Ambiguate = function(name) return (name:match("^([^%-]+)")) end

-- Blizzard's new menus: the generator is run into a root we can read and click
MOCK.menu = nil
MenuUtil = { CreateContextMenu = function(owner, gen)
  local root = { items = {}, owner = owner }
  function root:CreateButton(t, fn) local b = { text = t, fn = fn }; table.insert(self.items, b); return b end
  function root:CreateTitle(t) table.insert(self.items, { title = t }) end
  function root:CreateDivider() table.insert(self.items, { divider = true }) end
  function root:SetScrollMode() end
  gen(owner, root)
  MOCK.menu = root
  return root
end }
local function menuClick(text)
  for _, it in ipairs(MOCK.menu.items) do
    if it.text and it.text:find(text, 1, true) then it.fn() return true end
  end
  error("no menu item " .. text)
end
local function menuTitles()
  local t = {}
  for _, it in ipairs(MOCK.menu.items) do if it.title then t[#t + 1] = it.title end end
  return table.concat(t, ",")
end

-- Blizzard's mail frame, as far as we touch it
MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
InboxFrame = CreateFrame("Frame", "InboxFrame", MailFrame)
InboxFrame.pageNum = 1
InboxFrame.updates = 0
InboxFrame.Update = function(self) self.updates = self.updates + 1 end
OpenAllMail = CreateFrame("Button", "OpenAllMail", InboxFrame, "UIPanelButtonTemplate")
InboxTooMuchMail = CreateFrame("Frame", "InboxTooMuchMail", InboxFrame)
InboxTooMuchMail:Hide()
MOCK.plainClicks = 0
local blizzClick = function(self) MOCK.plainClicks = MOCK.plainClicks + 1 end
for r = 1, 7 do
  local row = CreateFrame("Frame", "MailItem" .. r, InboxFrame)
  if r == 1 then row:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 13, -70) end
  local b = CreateFrame("CheckButton", "MailItem" .. r .. "Button", row)
  b:SetScript("OnClick", blizzClick)
  local s = row:CreateFontString("MailItem" .. r .. "Subject")
  s:SetWidth(248)
end
-- what InboxFrame:Update does to the rows we read: which mail each one shows
local function blizzUpdate()
  for r = 1, 7 do
    local b = _G["MailItem" .. r .. "Button"]
    local index = (InboxFrame.pageNum - 1) * 7 + r
    b.index = index
    b:SetShown(MOCK.inbox[index] ~= nil)
  end
  InboxFrame:Update()
end

SendMailFrame = CreateFrame("Frame", "SendMailFrame", MailFrame)
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
SendMailSubjectEditBox = CreateFrame("EditBox", "SendMailSubjectEditBox", SendMailFrame)
SendMailCostMoneyFrame = CreateFrame("Frame", "SendMailCostMoneyFrame", SendMailFrame)
SendMailMoney = CreateFrame("Frame", "SendMailMoney", SendMailFrame)
SendMailMoneyGold = CreateFrame("EditBox", "SendMailMoneyGold", SendMailMoney)
SendMailCODButton = CreateFrame("CheckButton", "SendMailCODButton", SendMailFrame)
MOCK.sendCopper = 0
MoneyInputFrame_GetCopper = function() return MOCK.sendCopper end
function SendMailNameEditBox:HighlightText(a, b) self.hl = { a, b } end

-- Blizzard's suggestion list under To: (AutoComplete.lua, the parts Tab and Enter use)
AutoCompleteBox = CreateFrame("Frame", "AutoCompleteBox", UIParent)
AutoCompleteBox:Hide()
for i = 1, 5 do CreateFrame("Button", "AutoCompleteButton" .. i, AutoCompleteBox) end
local function showSuggestions(box, names)
  AutoCompleteBox.parent = box
  AutoCompleteBox.numResults = #names
  AutoCompleteBox.selectedIndex = 1
  for i = 1, 5 do _G["AutoCompleteButton" .. i].nameInfo = names[i] and { name = names[i] } or nil end
  AutoCompleteBox:Show()
end
AutoCompleteButton_OnClick = function(self)
  local box = AutoCompleteBox.parent
  AutoCompleteBox:Hide()
  box:SetText(self.nameInfo.name)
  box:SetCursorPosition(#self.nameInfo.name)
end
MOCK.tabbed = 0
SendMailNameEditBox:SetScript("OnTabPressed", function(self)
  -- AutoCompleteEditBox_OnTabPressed, else EditBox_HandleTabbing
  if AutoCompleteBox:IsShown() and AutoCompleteBox.parent == self then
    local n, sel = AutoCompleteBox.numResults, AutoCompleteBox.selectedIndex
    if IsShiftKeyDown() then sel = sel - 1; if sel <= 0 then sel = n end else sel = (sel + 1) % n; if sel == 0 then sel = n end end
    AutoCompleteBox.selectedIndex = sel
  else
    MOCK.tabbed = MOCK.tabbed + 1
    SendMailSubjectEditBox:SetFocus()
  end
end)
SendMailNameEditBox:SetScript("OnTextChanged", function() end)

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
local function fresh()
  if ns.inbox.state() then ns.inbox.stop("Stopped.") end
  MOCK.free = 10
  standardInbox()
  ns.inbox.scan()
  blizzUpdate()
  MOCK.took, MOCK.returned = {}, {}
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
  check(db and db.tags == true and db.select == true and db.shiftClick == true and db.ctrlReturn == true, "defaults")
  check(db.open.letters == false and db.delay == 0.3 and db.send.tab == true and db.send.wire == true, "defaults 2")
  check(SlashCmdList.EVERLOOKMAIL and SLASH_EVERLOOKMAIL1 == "/email", "no /email")
  check(SLASH_EVERLOOKMAIL2 == "/mail", "/mail alias not taken while free")
  check(db.alts["1"] and db.alts["1"].Tester and db.alts["1"].Tester.class == "MAGE", "this character not noted as an alt")
  check(ns.rival() == nil, "a rival without one loaded")
end)

step("/mail is left alone when another addon has it", function()
  SLASH_SOMEOTHERMAIL1 = "/mail"
  check(ns.slashFree("/mail") == false, "taken /mail looks free")
  SLASH_SOMEOTHERMAIL1 = nil
  check(ns.slashFree("/mail") == true, "free /mail looks taken")
end)

step("bare /email opens the settings window, with no errors; the new settings are found by search words", function()
  local before = #MOCK.errors
  SlashCmdList.EVERLOOKMAIL("")
  check(ns.app.window and ns.app.window:IsShown(), "window not shown")
  check(#MOCK.errors == before, "errors: " .. tostring(MOCK.errors[#MOCK.errors]))
  ns.app.window:Hide()
  for _, k in ipairs({ "select", "ctrlreturn", "collected", "send.tab", "send.wire", "send.total", "send.friends" }) do
    local def = ns.app:GetSetting(k)
    check(def and def.keywords and #def.keywords > 0, "no keywords for " .. k)
  end
  check(not ns.app:GetSetting("send.total").label:find("postage"), "the total's label still says it sits under the postage")
end)

step("every mail is read and given its category; alts are your own characters", function()
  EverlookMailDB.alts["1"].Bankalt = { class = "WARRIOR", level = 20, t = 1 }
  standardInbox()
  MailFrame:Show()
  MOCK.Fire("MAIL_SHOW")
  settle()
  blizzUpdate()
  local cats = {}
  for _, m in ipairs(ns.inbox.list) do cats[#cats + 1] = m.cat end
  check(table.concat(cats, ",") == "ah_sold,ah_expired,ah_cancelled,ah_won,player,alt,npc,cod", "categories: " .. table.concat(cats, ","))
  local sold = ns.inbox.list[1]
  check(sold.invoice and sold.invoice.buyer == "Bob" and sold.invoice.cut == 50 and sold.item == "Linen Cloth", "invoice not read")
  check(ns.inbox.list[2].item == "Copper Ore" and ns.inbox.list[2].count == 5, "subject count not parsed")
  check(#ns.inbox.list[6].items == 2 and ns.inbox.list[6].items[2].slot == 3, "attachments in their slots")
  check(EverlookDBMailAPI.isAlt("Bankalt") and not EverlookDBMailAPI.isAlt("Anna") and not EverlookDBMailAPI.isAlt("Tester"), "isAlt")
end)

step("each row has a small tag next to the subject, and the subject makes room for it", function()
  check(MailItem1.everlookTag:GetText():find("AH sold"), "row 1: " .. tostring(MailItem1.everlookTag:GetText()))
  check(MailItem6.everlookTag:GetText():find("Your alt"), "row 6")
  check(MailItem7.everlookTag:GetText():find("NPC"), "row 7")
  check(MailItem1Subject:GetWidth() < 248, "subject not shortened: " .. MailItem1Subject:GetWidth())
  check(MailItem1.everlookTag:GetParent() == MailItem1, "tag not inside the row")
  check(rawget(_G, "EverlookMailSummary") == nil, "the old side panel is still made")
  EverlookMailDB.tags = false
  ns.inbox.refresh()
  check(not MailItem1.everlookTag:IsShown() and MailItem1Subject:GetWidth() == 248, "tag still shown when off")
  EverlookMailDB.tags = true
  ns.inbox.refresh()
  check(MailItem1.everlookTag:IsShown(), "tag not back")
end)

step("tick boxes on the left of each mail; the rows move right for them and back when off", function()
  check(MailItem1.everlookTick:IsShown(), "no tick box")
  local p, rel, rp, x, y = MailItem1:GetPoint(1)
  check(p == "TOPLEFT" and rel == InboxFrame and x == 25 and y == -70, "rows not moved: " .. tostring(x))
  local tp, trel, trp = MailItem1.everlookTick:GetPoint(1)
  check(tp == "RIGHT" and trel == MailItem1 and trp == "LEFT", "tick box not left of the row")
  EverlookMailDB.select = false
  ns.inbox.refresh()
  check(not MailItem1.everlookTick:IsShown() and not ns.inbox.bar():IsShown(), "still there when off")
  check(select(4, MailItem1:GetPoint(1)) == 13, "rows not put back")
  EverlookMailDB.select = true
  ns.inbox.refresh()
  check(select(4, MailItem1:GetPoint(1)) == 25, "rows not moved again")
end)

step("Blizzard's own row click is never replaced", function()
  for r = 1, 7 do check(_G["MailItem" .. r .. "Button"]:GetScript("OnClick") == blizzClick, "row " .. r .. " click replaced") end
end)

step("ticking: a click, Shift for a range, Ctrl for one sender; the bar counts what it can do", function()
  local tick = function(r) local b = _G["EverlookMailTick" .. r]; b:SetChecked(not b:GetChecked()); b:GetScript("OnClick")(b) end
  tick(2)
  check(#ns.inbox.selected() == 1 and ns.inbox.selected()[1].index == 2, "one tick")
  MOCK.mods.shift = true
  tick(4)
  MOCK.mods.shift = false
  local idx = {}
  for _, m in ipairs(ns.inbox.selected()) do idx[#idx + 1] = m.index end
  check(table.concat(idx, ",") == "2,3,4", "range " .. table.concat(idx, ","))
  check(EverlookMailTick3:GetChecked(), "row 3 not shown ticked")
  local bar = ns.inbox.bar()
  check(bar:IsShown() and bar.open:GetText() == "Open (3)" and bar.ret:GetText() == "Return" and not bar.ret:IsEnabled(), "bar " .. bar.open:GetText() .. " / " .. bar.ret:GetText())
  ns.inbox.clearSelection()
  MOCK.mods.ctrl = true
  tick(1)
  MOCK.mods.ctrl = false
  check(#ns.inbox.selected() == 4, "Ctrl: every mail from the auction house " .. #ns.inbox.selected())
  ns.inbox.clearSelection()
  check(bar.open:GetText() == "Open selected" and not bar.open:IsEnabled(), "not reset")
end)

step("Select menu: all, none and the kinds there are", function()
  MOCK.Click = nil
  ns.inbox.bar().select:GetScript("OnClick")(ns.inbox.bar().select)
  check(MOCK.menu and menuTitles() == "Tick", "no menu")
  menuClick("All")
  check(#ns.inbox.selected() == 8, "all " .. #ns.inbox.selected())
  menuClick("None")
  check(#ns.inbox.selected() == 0, "none")
  menuClick("AH items back")
  local idx = {}
  for _, m in ipairs(ns.inbox.selected()) do idx[#idx + 1] = m.index end
  check(table.concat(idx, ",") == "2,3", "items back " .. table.concat(idx, ","))
  local hasOutbid = false
  for _, it in ipairs(MOCK.menu.items) do if it.text and it.text:find("AH won", 1, true) then hasOutbid = true end end
  check(hasOutbid, "kinds that are there are offered")
end)

step("Open selected takes the ticked mail, then clears the ticks", function()
  MOCK.took = {}
  ns.inbox.bar().open:GetScript("OnClick")(ns.inbox.bar().open)
  settle(200)
  check(table.concat(MOCK.took, ",") == "item:Wool Cloth,item:Copper Ore", "took " .. table.concat(MOCK.took, ","))
  check(#ns.inbox.selected() == 0 and ns.inbox.state() == nil, "not cleared")
  check(last():find("Done") and last():find("2 items"), "message " .. last())
end)

step("Return selected sends player mail back and explains the rest", function()
  fresh()
  for _, i in ipairs({ 1, 5, 6 }) do ns.inbox.setSelected(ns.inbox.byIndex(i), true) end
  ns.inbox.refresh()
  check(ns.inbox.bar().ret:GetText() == "Return (2)", "count " .. ns.inbox.bar().ret:GetText())
  ns.inbox.bar().ret:GetScript("OnClick")(ns.inbox.bar().ret)
  check(logHas("can't go back: auction house and NPC mail"), "no explanation")
  settle(200)
  check(table.concat(MOCK.returned, ",") == "mats,for you", "returned " .. table.concat(MOCK.returned, ","))
  check(last():find("2 mails returned"), last())
  check(#MOCK.inbox == 6 and #ns.inbox.selected() == 0, "inbox " .. #MOCK.inbox)
end)

step("the inbox goes to EverlookDB Auctions' ledger as it is read", function()
  check(auctionsCalls.scanned > 0 and auctionsCalls.lastList, "not handed over")
  EverlookMailDB.ledger = false
  local n = auctionsCalls.scanned
  ns.inbox.scan()
  check(auctionsCalls.scanned == n, "handed over while off")
  EverlookMailDB.ledger = true
end)

step("our Open all stands where Blizzard's is; Blizzard's stays hidden", function()
  fresh()
  local b = ns.inbox.openAllButton()
  check(b and b:IsShown() and not OpenAllMail:IsShown(), "buttons")
  check(b:GetText() == "Open all (6)", "text " .. b:GetText())
  local p, rel, rp, x, y = b:GetPoint(1)
  check(p == "CENTER" and rel == InboxFrame and rp == "BOTTOM" and y == 26, "not in Blizzard's place")
  OpenAllMail:Show()
  check(not OpenAllMail:IsShown(), "Blizzard's came back")
end)

step("Open all takes money and items, last mail first, skips C.O.D. and unread letters, tells Auctions, says what it left", function()
  fresh()
  auctionsCalls.taken = {}
  ns.inbox.openAllButton():GetScript("OnClick")(ns.inbox.openAllButton(), "LeftButton")
  check(MOCK.openingAll == true, "SetOpeningAll not set")
  settle(200)
  check(ns.inbox.state() == nil, "still running")
  local took = table.concat(MOCK.took, ",")
  check(took == "money:Your reward,item:Iron Ore,item:Coal,item:Silk Cloth,item:Wool Cloth,item:Copper Ore,money:Auction successful: Linen Cloth (20)", "took " .. took)
  check(#MOCK.inbox == 3 and MOCK.inbox[1].sender == "Anna" and MOCK.inbox[3].cod == 999, "left " .. #MOCK.inbox)
  check(#auctionsCalls.taken == 7 and auctionsCalls.taken[1] == "npc:money:nil" and auctionsCalls.taken[2] == "alt:item:1", "auctions: " .. table.concat(auctionsCalls.taken, ","))
  check(last():find("Done") and last():find("5 items") and last():find("Left: 1 C.O.D., 1 unread letter"), "message " .. last())
  check(MOCK.openingAll == false, "SetOpeningAll not cleared")
end)

step("unread letters too when that is on; Shift-click on Open all takes them anyway, never C.O.D.", function()
  EverlookMailDB.open.letters = true
  MOCK.took = {}
  ns.inbox.openAll()
  settle(200)
  check(table.concat(MOCK.took, ",") == "money:for you", "took " .. table.concat(MOCK.took, ","))
  EverlookMailDB.open.letters = false
  fresh()
  MOCK.mods.shift = true
  ns.inbox.openAllButton():GetScript("OnClick")(ns.inbox.openAllButton(), "LeftButton")
  MOCK.mods.shift = false
  settle(200)
  check(#MOCK.took == 8, "count " .. #MOCK.took)
  local letter = false
  for _, t in ipairs(MOCK.took) do if t == "money:for you" then letter = true end end
  check(letter and #MOCK.inbox == 3 and MOCK.inbox[3].cod == 999, "shift: letter " .. tostring(letter))
end)

step("full bags: the gold still comes, then it pauses, and goes on by itself when there is room", function()
  fresh()
  MOCK.free = 0
  ns.inbox.openAll()
  settle(200)
  local q = ns.inbox.state()
  check(q and q.paused and q.why == "bags", "not paused")
  check(last():find("bags are full"), "no message: " .. last())
  check(table.concat(MOCK.took, ",") == "money:Your reward,money:Auction successful: Linen Cloth (20)", "took while full " .. table.concat(MOCK.took, ","))
  check(ns.inbox.openAllButton():GetText() == "Continue", "button " .. ns.inbox.openAllButton():GetText())
  local said = #MOCK.log
  settle(20)
  check(#MOCK.log == said, "said it again")
  MOCK.free = 10
  MOCK.Fire("BAG_UPDATE_DELAYED")
  settle(200)
  check(ns.inbox.state() == nil and #MOCK.took == 7, "did not finish: " .. #MOCK.took)
end)

step("the bag-full error from the server pauses it too", function()
  fresh()
  ns.inbox.openAll()
  MOCK.RunTimers()
  MOCK.Fire("UI_ERROR_MESSAGE", 1, "Inventory is full.")
  check(ns.inbox.state() and ns.inbox.state().paused, "not paused")
  ns.inbox.stop("Stopped.")
  check(ns.inbox.state() == nil, "not stopped")
end)

step("closing the mailbox stops it at once and says the gold you took", function()
  fresh()
  MOCK.Fire("MAIL_SHOW")
  settle()
  MOCK.took = {}
  ns.inbox.openAll()
  MOCK.RunTimers()
  MailFrame:Hide()
  MOCK.Fire("MAIL_CLOSED")
  settle(200)
  check(ns.inbox.state() == nil, "still running")
  check(#MOCK.took == 1, "kept taking: " .. #MOCK.took)
  check(logHas("mailbox closed") and last():find("You took 2.*from the mailbox"), "message " .. last())
  MailFrame:Show()
  MOCK.Fire("MAIL_SHOW")
  settle()
end)

local function cover(r) return _G["EverlookMailRowClick" .. r] end
local function holdShift(v) MOCK.mods.shift = v; MOCK.Fire("MODIFIER_STATE_CHANGED") end
local function holdCtrl(v) MOCK.mods.ctrl = v; MOCK.Fire("MODIFIER_STATE_CHANGED") end

step("Shift-click takes everything in that mail, even as its expiry moves, without Blizzard's click", function()
  fresh()
  check(not cover(6):IsShown(), "cover shown without Shift")
  holdShift(true)
  check(cover(6):IsShown() and cover(6):GetParent() == MailItem6, "no cover while Shift is held")
  cover(6):GetScript("OnClick")(cover(6), "LeftButton")
  settle(200)
  check(table.concat(MOCK.took, ",") == "item:Iron Ore,item:Coal", "took " .. table.concat(MOCK.took, ","))
  check(MOCK.plainClicks == 0, "Blizzard's click ran too")
  holdShift(false)
  check(not cover(6):IsShown(), "cover stays after Shift")
end)

step("Shift-click several mails quickly: all of them are taken", function()
  fresh()
  holdShift(true)
  cover(6):GetScript("OnClick")(cover(6), "LeftButton")
  MOCK.RunTimers()
  cover(2):GetScript("OnClick")(cover(2), "LeftButton")
  cover(1):GetScript("OnClick")(cover(1), "LeftButton")
  holdShift(false)
  settle(200)
  check(table.concat(MOCK.took, ",") == "item:Iron Ore,item:Coal,item:Copper Ore,money:Auction successful: Linen Cloth (20)", "took " .. table.concat(MOCK.took, ","))
end)

step("Shift-click never pays C.O.D.; it takes unread letters (you asked)", function()
  fresh()
  check(ns.inbox.takeMail(8) == false and last():find("C.O.D."), "C.O.D. taken: " .. last())
  ns.inbox.takeMail(5)
  settle(200)
  check(table.concat(MOCK.took, ",") == "money:for you", "letter " .. table.concat(MOCK.took, ","))
end)

step("Ctrl-click returns a player's mail; auction house mail can't go back", function()
  fresh()
  holdCtrl(true)
  check(cover(6):IsShown(), "no cover while Ctrl is held")
  cover(6):GetScript("OnClick")(cover(6), "LeftButton")
  settle(200)
  check(table.concat(MOCK.returned, ",") == "mats", "returned " .. table.concat(MOCK.returned, ","))
  cover(1):GetScript("OnClick")(cover(1), "LeftButton")
  settle(200)
  check(#MOCK.returned == 1 and last():find("can't be returned"), "AH returned: " .. last())
  holdCtrl(false)
  check(MOCK.plainClicks == 0, "Blizzard's click ran")
end)

step("Shift-click and Ctrl-click off: no cover, Blizzard's click as always", function()
  fresh()
  EverlookMailDB.shiftClick = false
  EverlookMailDB.ctrlReturn = false
  holdShift(true)
  holdCtrl(true)
  check(not cover(1):IsShown(), "cover while off")
  holdShift(false)
  holdCtrl(false)
  EverlookMailDB.shiftClick = true
  EverlookMailDB.ctrlReturn = true
end)

step("the row cover's tooltip says what Shift- and Ctrl-click do", function()
  fresh()
  local lines = {}
  local old = GameTooltip.AddLine
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  ns.inbox.rowTip(cover(6), 6)
  GameTooltip.AddLine = old
  local all = table.concat(lines, "|")
  check(all:find("Shift%-click: take") and all:find("Ctrl%-click: return"), all)
end)

step("more mail on the server: Open all says so, asks for it, and goes on when it comes", function()
  MOCK.inbox = { mail({ sender = "Thrall", subject = "gift", money = 5, canReply = false }) }
  MOCK.extra = 12
  MOCK.checked = false
  MOCK.took = {}
  ns.inbox.openAll()
  settle(200)
  check(last():find("12 more on the server") and MOCK.checked, "message " .. last())
  MOCK.extra = nil
  MOCK.inbox = { mail({ sender = "Thrall", subject = "gift 2", money = 7, canReply = false }) }
  MOCK.Fire("MAIL_INBOX_UPDATE")
  settle(200)
  check(table.concat(MOCK.took, ",") == "money:gift,money:gift 2", "did not go on: " .. table.concat(MOCK.took, ","))
end)

step("the game's \"too much mail\" line gives way to our bar", function()
  fresh()
  InboxTooMuchMail:Show()
  blizzUpdate()
  check(not InboxTooMuchMail:IsShown(), "still over the bar")
end)

step("sending: recent recipients remembered when the mail goes, newest first, once each", function()
  MOCK.Fire("MAIL_SHOW")
  settle()
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

step("names: recent, then alts, friends and guild (online first)", function()
  local list = {}
  for _, n in ipairs(ns.send.names()) do list[#list + 1] = n.name end
  check(table.concat(list, ",") == "Fay,Eve,Dan,Bankalt,Frieda,Fritz,Greta,Gunnar", "names " .. table.concat(list, ","))
  EverlookMailDB.send.friends = false
  check(#ns.send.names() == 4, "friends and guild while off")
  EverlookMailDB.send.friends = true
end)

step("the arrow attached to To: lists them in sections; picking one fills To:", function()
  local b = EverlookMailToButton
  check(b and b:IsShown(), "no arrow")
  local p, rel = b:GetPoint(1)
  check(p == "LEFT" and rel == SendMailNameEditBox, "not attached to To:")
  b:GetScript("OnClick")(b)
  check(menuTitles() == "Recent,Your alts,Friends,Guild", "sections " .. menuTitles())
  menuClick("Bankalt")
  check(SendMailNameEditBox:GetText() == "Bankalt" and MOCK.focus == SendMailSubjectEditBox, "To: not filled")
end)

step("names complete as you type", function()
  check(ns.send.complete("ba") == "Bankalt" and ns.send.complete("e") == nil and ns.send.complete("Bankalt") == nil, "complete")
  check(ns.send.complete("gre") == "Greta", "guild names")
  SendMailNameEditBox:SetText("Fa")
  SendMailNameEditBox:SetCursorPosition(2)
  SendMailNameEditBox:GetScript("OnTextChanged")(SendMailNameEditBox, true)
  check(SendMailNameEditBox:GetText() == "Fay" and SendMailNameEditBox.hl[1] == 2, "not completed: " .. SendMailNameEditBox:GetText())
  EverlookMailDB.send.complete = false
  SendMailNameEditBox:SetText("Da")
  SendMailNameEditBox:SetCursorPosition(2)
  SendMailNameEditBox:GetScript("OnTextChanged")(SendMailNameEditBox, true)
  check(SendMailNameEditBox:GetText() == "Da", "completed while off")
  EverlookMailDB.send.complete = true
end)

local function tab(box) box:GetScript("OnTabPressed")(box) end

step("Tab takes the name completed in the box and stays in To:", function()
  local box = SendMailNameEditBox
  box:SetFocus()
  MOCK.tabbed = 0
  box:SetText("Fa")
  box:SetCursorPosition(2)
  box:GetScript("OnTextChanged")(box, true)
  showSuggestions(box, { "Fay", "Farin" })
  tab(box)
  check(box:GetText() == "Fay" and box:GetCursorPosition() == 3, "not taken: " .. box:GetText() .. " " .. box:GetCursorPosition())
  check(not AutoCompleteBox:IsShown() and MOCK.tabbed == 0 and MOCK.focus == box, "list or focus")
  tab(box)
  check(MOCK.tabbed == 1 and MOCK.focus == SendMailSubjectEditBox, "Tab with nothing to complete did not move on")
end)

step("Tab takes the game's suggestion (the highlighted one), not the next one", function()
  local box = SendMailNameEditBox
  box:SetFocus()
  MOCK.tabbed = 0
  box:SetText("Ka")
  box:SetCursorPosition(2)
  showSuggestions(box, { "Kalle", "Karin", "Kasper" })
  tab(box)
  check(box:GetText() == "Kalle" and not AutoCompleteBox:IsShown() and MOCK.tabbed == 0, "took " .. box:GetText())
  -- the second suggestion highlighted with the arrow keys: Tab takes that one
  box:SetText("Ka")
  box:SetCursorPosition(2)
  showSuggestions(box, { "Kalle", "Karin", "Kasper" })
  AutoCompleteBox.selectedIndex = 2
  tab(box)
  check(box:GetText() == "Karin", "took " .. box:GetText())
  -- Shift-Tab is the game's own
  box:SetText("Ka")
  box:SetCursorPosition(2)
  showSuggestions(box, { "Kalle", "Karin" })
  MOCK.mods.shift = true
  tab(box)
  MOCK.mods.shift = false
  check(box:GetText() == "Ka" and AutoCompleteBox:IsShown(), "Shift-Tab took a name")
  AutoCompleteBox:Hide()
  EverlookMailDB.send.tab = false
  showSuggestions(box, { "Kalle", "Karin" })
  tab(box)
  check(box:GetText() == "Ka", "Tab took a name while off")
  AutoCompleteBox:Hide()
  EverlookMailDB.send.tab = true
end)

step("the total above the money boxes (clear of the Subject box), and gold as the subject", function()
  MOCK.sendCopper = 50000
  SendMailSubjectEditBox:SetText("")
  SendMailMoneyGold:GetScript("OnTextChanged")(SendMailMoneyGold)
  check(EverlookMailSendTotal:IsShown() and EverlookMailSendTotal:GetText():find("Total 5"), "total " .. tostring(EverlookMailSendTotal:GetText()))
  local p, rel = EverlookMailSendTotal:GetPoint(1)
  check(rel == (rawget(_G, "SendMailMoney") or SendMailCostMoneyFrame), "not above the money boxes")
  check(SendMailSubjectEditBox:GetText() == "5g", "subject " .. SendMailSubjectEditBox:GetText())
  MOCK.sendCopper = 52000
  SendMailMoneyGold:GetScript("OnTextChanged")(SendMailMoneyGold)
  check(SendMailSubjectEditBox:GetText() == "5g 20s", "subject not updated " .. SendMailSubjectEditBox:GetText())
  SendMailSubjectEditBox:SetText("rent")
  MOCK.sendCopper = 60000
  SendMailMoneyGold:GetScript("OnTextChanged")(SendMailMoneyGold)
  check(SendMailSubjectEditBox:GetText() == "rent", "own subject overwritten")
  SendMailCODButton:SetChecked(true)
  ns.send.refresh()
  check(EverlookMailSendTotal:GetText():find("C.O.D."), "C.O.D. " .. EverlookMailSendTotal:GetText())
  SendMailCODButton:SetChecked(false)
  MOCK.sendCopper = 0
  ns.send.refresh()
  check(not EverlookMailSendTotal:IsShown(), "total without gold")
end)

step("with another mail addon loaded we step aside (said once); the tags stay", function()
  MOCK.loaded.Postal = true
  ns.findRival()
  check(ns.rival() == "Postal", "not found")
  local before = #MOCK.log
  fresh()
  MOCK.Fire("MAIL_SHOW")
  settle()
  blizzUpdate()
  check(#MOCK.log == before + 1 and last():find("Postal is loaded"), "not said: " .. last())
  MOCK.Fire("MAIL_SHOW")
  settle()
  check(#MOCK.log == before + 1, "said twice")
  check(not ns.inbox.bar():IsShown() and not ns.inbox.openAllButton():IsShown() and OpenAllMail:IsShown(), "our buttons still there")
  check(not MailItem1.everlookTick:IsShown() and select(4, MailItem1:GetPoint(1)) == 13, "tick boxes or moved rows")
  check(MailItem1.everlookTag:IsShown(), "tags gone")
  holdShift(true)
  check(not cover(1):IsShown(), "our Shift-click still there")
  holdShift(false)
  local box = SendMailNameEditBox
  box:SetText("Ka")
  box:SetCursorPosition(2)
  showSuggestions(box, { "Kalle", "Karin" })
  tab(box)
  check(box:GetText() == "Ka", "our Tab still there")
  AutoCompleteBox:Hide()
  ns.send.refresh()
  check(not EverlookMailToButton:IsShown(), "our To: arrow still there")
  ns.app:PrintStatus()
  check(logHas("leaves the inbox buttons"), "not in /email status")
  MOCK.loaded.Postal = nil
  ns.findRival()
  ns.inbox.refresh()
  ns.send.refresh()
  check(ns.inbox.bar():IsShown() and not OpenAllMail:IsShown() and EverlookMailToButton:IsShown(), "not back")
end)

step("/email forget and /email alts", function()
  SlashCmdList.EVERLOOKMAIL("alts")
  check(last():find("Bankalt"), last())
  local api = EverlookDBAuctionsAPI
  EverlookDBAuctionsAPI = { version = 7, inventory = { gold = function()
    return 70000, { { name = "Bankalt", money = 50000, mail = 20000 }, { name = "Tester", me = true, money = 1 } }
  end } }
  SlashCmdList.EVERLOOKMAIL("alts")
  check(last():find("Bankalt (", 1, true), "gold with EverlookDB Auctions: " .. last())
  EverlookDBAuctionsAPI = api
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
