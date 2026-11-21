-- The inbox: every mail read and tagged as soon as the mailbox opens, a summary panel beside the mailbox with the totals
-- per kind and the Open all button, the Open all queue, and shift-left-click on a mail to take all of it.
--
-- Open all and shift-click share one queue. Each step reads the inbox again, picks the last mail that still has
-- something to take (the highest index first, so emptied mails vanishing never moves the ones still to do), takes one
-- thing from it (the money, else the next attachment), and waits for the server: until no mail command is pending,
-- then db.delay seconds more. It pauses with a message when the bags are full, skips a mail that fails twice, and
-- stops at once when the mailbox closes. C.O.D. and Game Master mail are never taken.
local _, ns = ...
local UI = LibStub("EverlookUI-1")
local I = { list = {}, totals = {} }
ns.inbox = I

local ROWS = 7 -- INBOXITEMS_TO_DISPLAY
local MAX_TRIES = 2
local WAIT_MAX = 5 -- seconds a take may stay pending before the queue moves on

-- tag colours per category
I.COLOR = {
  ah_sold = "62cf88", ah_expired = "e8a54b", ah_cancelled = "ef7d5d", ah_won = "6db8f7", ah_outbid = "9aa7c7",
  player = "f2f2f2", alt = "c39bf2", npc = "d9c38c", cod = "ef5d5d", other = "8d94a3",
}

local function db() return ns.db() end
local try = ns.try

local function C() return ns.C() end

function I.isAlt(name) return ns.isAlt(name) end

local function auctionsMail()
  if not (db() and db().ledger) then return nil end
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  if not (api and type(api.version) == "number" and api.version >= 4) then return nil end
  local ok, mail = pcall(function() return api.mail end)
  return ok and mail or nil
end
I.auctionsMail = auctionsMail

---------------------------------------------------------------------------------------------------------------------
-- Reading the inbox

function I.scan()
  local c = C()
  if not c then return I.list end
  I.list = c.scan(I.isAlt)
  I.totals = c.totals(I.list)
  local _, total = try(GetInboxNumItems)
  I.shown = #I.list
  I.total = tonumber(total) or #I.list
  local mail = auctionsMail()
  if mail then pcall(mail.scanned, I.list) end
  return I.list
end

function I.byIndex(i)
  for _, m in ipairs(I.list) do if m.index == i then return m end end
end

-- What Open all would take from this mail: false and why when it leaves it alone.
function I.wanted(m, single)
  if type(m) ~= "table" then return false, "no mail" end
  if (m.cod or 0) > 0 then return false, "C.O.D.: open it to pay" end
  if m.isGM then return false, "from a Game Master" end
  if (m.money or 0) <= 0 and #(m.items or {}) == 0 then return false, "nothing to take" end
  if single then return true end
  local o = db().open
  local cat = m.cat
  if cat and cat:match("^ah_") then return o.ah and true or false, "auction house mail is off" end
  if cat == "alt" then return o.alts and true or false, "mail from your alts is off" end
  if cat == "npc" then return o.npc and true or false, "NPC mail is off" end
  if cat == "player" or cat == "other" then
    if not o.players then return false, "mail from players is off" end
    if not m.wasRead and not o.letters then return false, "unread mail from a player" end
    return true
  end
  return true
end

function I.counts()
  local out = { take = 0, money = 0, items = 0, skipped = 0 }
  for _, m in ipairs(I.list) do
    if I.wanted(m) then
      out.take = out.take + 1
      out.money = out.money + (m.money or 0)
      out.items = out.items + #(m.items or {})
    elseif (m.money or 0) > 0 or #(m.items or {}) > 0 then
      out.skipped = out.skipped + 1
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- Bags

function I.freeSlots()
  local free = 0
  local getFree = C_Container and C_Container.GetContainerNumFreeSlots or rawget(_G, "GetContainerNumFreeSlots")
  for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
    local n, kind = try(getFree, bag)
    if n and (kind == nil or kind == 0) then free = free + n end
  end
  return free
end

---------------------------------------------------------------------------------------------------------------------
-- The queue

local Q -- nil, or { single = key|nil, money, items, mails = {}, tries = {}, paused, why, token }
I.state = function() return Q end

local function say(msg)
  if ns.app then ns.app:Print(msg) end
end

local function mailId(m)
  local c = C()
  return c and (c.key(m) .. "|" .. tostring(m.exp or "")) or tostring(m.index)
end

local function finish(msg)
  local q = Q
  Q = nil
  pcall(function() if C_Mail and C_Mail.SetOpeningAll then C_Mail.SetOpeningAll(false) end end)
  if q and msg then say(msg) end
  I.lastRun = q
  I.refresh()
end

function I.stop(why)
  if not Q then return end
  local q = Q
  local n = 0
  for _ in pairs(q.mails) do n = n + 1 end
  finish(("%s %s, %d item%s from %d mail%s."):format(why or "Stopped.", ns.money(q.money), q.items,
    q.items == 1 and "" or "s", n, n == 1 and "" or "s"))
end

local step

local function schedule(delay)
  if not Q then return end
  local token = {}
  Q.token = token
  C_Timer.After(delay, function() if Q and Q.token == token then step() end end)
end

local function pick()
  local single = Q.single
  for k = #I.list, 1, -1 do
    local m = I.list[k]
    local id = mailId(m)
    if (Q.tries[id] or 0) < MAX_TRIES then
      if single then
        if id == single and I.wanted(m, true) then return m, id end
      elseif I.wanted(m) then
        return m, id
      end
    end
  end
end

step = function()
  if not Q or Q.paused then return end
  if not (MailFrame and MailFrame:IsShown()) then return I.stop("The mailbox closed:") end
  -- the server is still busy with the last take
  local pending = C_Mail and C_Mail.IsCommandPending and try(C_Mail.IsCommandPending)
  if pending and (GetTime() - (Q.sent or 0)) < WAIT_MAX then return schedule(0.1) end
  I.scan()
  local m, id = pick()
  if not m then
    local n = 0
    for _ in pairs(Q.mails) do n = n + 1 end
    local more = (I.total or 0) > (I.shown or 0) and ((" %d more on the server: they come in as the inbox empties."):format(I.total - I.shown)) or ""
    finish(("Done: %s, %d item%s from %d mail%s.%s"):format(ns.money(Q.money), Q.items, Q.items == 1 and "" or "s",
      n, n == 1 and "" or "s", more))
    if more ~= "" then pcall(CheckInbox) end
    return
  end
  local mail = auctionsMail()
  Q.tries[id] = (Q.tries[id] or 0)
  Q.mails[id] = true
  Q.current = m
  if (m.money or 0) > 0 then
    if mail then pcall(mail.taken, m, "money") end
    local ok = pcall(TakeInboxMoney, m.index)
    if ok then Q.money = Q.money + m.money else Q.tries[id] = Q.tries[id] + 1 end
  else
    if I.freeSlots() <= 0 then
      Q.paused = true
      Q.why = "bags"
      say("Your bags are full: make room, then click Continue (or /email open).")
      I.refresh()
      return
    end
    local it = m.items[1]
    if mail then pcall(mail.taken, m, "item", it.slot) end
    local ok = pcall(TakeInboxItem, m.index, it.slot)
    if ok then Q.items = Q.items + 1 else Q.tries[id] = Q.tries[id] + 1 end
  end
  Q.sent = GetTime()
  I.refresh()
  schedule(math.max(0.15, tonumber(db().delay) or 0.3))
end

local function start(single)
  if not (MailFrame and MailFrame:IsShown()) then say("Open a mailbox first.") return false end
  if Q then
    if Q.paused then Q.paused, Q.why = nil, nil; schedule(0) end
    return true
  end
  Q = { single = single, money = 0, items = 0, mails = {}, tries = {} }
  pcall(function() if C_Mail and C_Mail.SetOpeningAll then C_Mail.SetOpeningAll(true) end end)
  schedule(0)
  I.refresh()
  return true
end

function I.openAll() return start(nil) end

-- Shift-left-click: everything in this one mail (by inbox index)
function I.takeMail(index)
  I.scan()
  local m = I.byIndex(index)
  local ok, why = I.wanted(m, true)
  if not ok then say(("Not taken: %s."):format(why)) return false end
  if Q and not Q.single then return false end -- Open all is running: it gets there
  return start(mailId(m))
end

---------------------------------------------------------------------------------------------------------------------
-- Tags on the inbox rows

function I.tagText(m)
  local c = C()
  if not (c and m) then return "" end
  local label = c.LABEL[m.cat] or m.cat or ""
  if m.cat == "ah_sold" and m.pending then label = "AH sold, money soon" end
  return ("|cff%s%s|r"):format(I.COLOR[m.cat] or "ffffff", label)
end

function I.paintRows()
  local on = db() and db().tags
  local page = (InboxFrame and InboxFrame.pageNum) or 1
  for r = 1, ROWS do
    local row = _G["MailItem" .. r]
    if row then
      if not row.everlookTag then
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 7)
        t:SetJustifyH("RIGHT")
        row.everlookTag = t
      end
      local m = on and I.byIndex((page - 1) * ROWS + r)
      row.everlookTag:SetText(m and I.tagText(m) or "")
      row.everlookTag:SetShown(m and true or false)
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- The summary panel

local panel
function I.panel() return panel end

local function makePanel()
  local T = ns.app.T
  local f = CreateFrame("Frame", "EverlookMailSummary", MailFrame or UIParent)
  f:SetSize(240, 300)
  UI.WindowChrome(f, T)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rel, x, y = self:GetPoint()
    db().panel = { p, rel, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
  end)
  local title = UI.Text(f, T.font + 2, T.text)
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Inbox")
  f.title = title
  local sub = UI.Text(f, T.font - 1, T.muted)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  f.sub = sub
  local gear = CreateFrame("Button", nil, f)
  gear:SetSize(16, 16)
  gear:SetPoint("TOPRIGHT", -10, -11)
  local gt = gear:CreateTexture(nil, "ARTWORK")
  gt:SetAllPoints()
  UI.SetIcon(gt, "gear")
  gt:SetVertexColor(0.6, 0.65, 0.72)
  gear:SetScript("OnClick", function() ns.app:Open() end)
  UI.Tooltip(gear, "EverlookDB Mail", "Settings: /email")
  f.rows = {}
  for i, cat in ipairs((C() and C().CATS) or {}) do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(18)
    r:SetPoint("LEFT", 12, 0)
    r:SetPoint("RIGHT", -12, 0)
    r.label = UI.Text(r, T.font, T.text)
    r.label:SetPoint("LEFT")
    r.value = UI.Text(r, T.font, T.muted)
    r.value:SetPoint("RIGHT")
    r.value:SetJustifyH("RIGHT")
    r.cat = cat
    f.rows[i] = r
  end
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
  f.line = line
  local total = UI.Text(f, T.font, T.text)
  f.total = total
  local status = UI.Text(f, T.font - 1, T.muted)
  status:SetPoint("LEFT", 12, 0)
  status:SetPoint("RIGHT", -12, 0)
  f.status = status
  -- the screen's one primary button
  local btn = UI.Button(f, "Open all", function()
    local q = Q
    if q and not q.paused then I.stop("Stopped:") else I.openAll() end
  end, 216, "accent")
  btn:SetPoint("BOTTOM", 0, 12)
  f.button = btn
  f:Hide()
  return f
end

local function place(f)
  f:ClearAllPoints()
  local p = db().panel
  if type(p) == "table" and type(p[1]) == "string" then
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  elseif rawget(_G, "OpenMailFrame") and OpenMailFrame:IsShown() then
    -- a mail is open beside the inbox: next to it, not over it
    f:SetPoint("TOPLEFT", OpenMailFrame, "TOPRIGHT", 6, 0)
  elseif MailFrame then
    f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
  else
    f:SetPoint("CENTER")
  end
end

function I.paintPanel()
  if not (db() and db().summary and MailFrame and MailFrame:IsShown()) then
    if panel then panel:Hide() end
    return
  end
  panel = panel or makePanel()
  if not panel:IsShown() then place(panel) end
  panel:Show()
  local c = C()
  local n = #I.list
  panel.title:SetText(n == 1 and "Inbox: 1 mail" or ("Inbox: %d mails"):format(n))
  local more = (I.total or 0) > n and ((" · %d more on the server"):format(I.total - n)) or ""
  panel.sub:SetText("What each mail is" .. more)
  local y = -52
  local money, items = 0, 0
  for _, r in ipairs(panel.rows) do
    local t = I.totals[r.cat]
    if t and t.n > 0 then
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 12, y)
      r:SetPoint("RIGHT", -12, 0)
      r.label:SetText(("|cff%s%s|r  %d"):format(I.COLOR[r.cat] or "ffffff", c.LABEL[r.cat] or r.cat, t.n))
      local parts = {}
      if t.money > 0 then parts[#parts + 1] = ns.money(t.money) end
      if t.items > 0 then parts[#parts + 1] = t.items == 1 and "1 item" or (t.items .. " items") end
      if t.cod > 0 then parts[#parts + 1] = "pay " .. ns.money(t.cod) end
      r.value:SetText(#parts > 0 and table.concat(parts, " · ") or "|cff8d94a3emptied|r")
      r:Show()
      y = y - 18
      money, items = money + t.money, items + t.items
    else
      r:Hide()
    end
  end
  if n == 0 then y = y - 4 end
  panel.line:ClearAllPoints()
  panel.line:SetPoint("TOPLEFT", 12, y - 6)
  panel.line:SetPoint("TOPRIGHT", -12, y - 6)
  panel.total:ClearAllPoints()
  panel.total:SetPoint("TOPLEFT", 12, y - 14)
  panel.total:SetText(n == 0 and "The inbox is empty." or ("In the mail: %s · %d item%s"):format(ns.money(money), items, items == 1 and "" or "s"))
  local cnt = I.counts()
  local q = Q
  local status
  if q and q.paused then
    status = "|cffe8a54bPaused: your bags are full.|r Make room and click Continue."
    panel.button:SetText("Continue")
  elseif q then
    local done = 0
    for _ in pairs(q.mails) do done = done + 1 end
    local togo = q.single and 0 or cnt.take
    status = ("Taking mail %d: %s and %d item%s so far."):format(done, ns.money(q.money), q.items, q.items == 1 and "" or "s")
    if togo > 0 then status = status .. ("\n%d more to go."):format(togo) end
    panel.button:SetText("Stop")
  else
    if cnt.take > 0 then
      status = ("Open all takes %d mail%s: %s, %d item%s."):format(cnt.take, cnt.take == 1 and "" or "s", ns.money(cnt.money),
        cnt.items, cnt.items == 1 and "" or "s")
    else
      status = "Nothing for Open all to take."
    end
    if cnt.skipped > 0 then
      status = status .. ("\n%d left alone: C.O.D., unread letters, or off in /email."):format(cnt.skipped)
    end
    if I.lastRun then
      local r = I.lastRun
      status = status .. ("\nLast run: %s, %d item%s."):format(ns.money(r.money), r.items, r.items == 1 and "" or "s")
    end
    panel.button:SetText(cnt.take > 0 and ("Open all (%d)"):format(cnt.take) or "Open all")
  end
  panel.button:SetUsable(q ~= nil or cnt.take > 0)
  panel.status:ClearAllPoints()
  panel.status:SetPoint("TOPLEFT", 12, y - 36)
  panel.status:SetPoint("RIGHT", -12, 0)
  panel.status:SetText(status)
  panel:SetHeight(math.max(150, -y + 36 + 44 + 44))
end

function I.refresh()
  pcall(I.paintRows)
  pcall(I.paintPanel)
end

---------------------------------------------------------------------------------------------------------------------
-- Shift-left-click on an inbox row

local function wrapButtons()
  for r = 1, ROWS do
    local b = _G["MailItem" .. r .. "Button"]
    if b and not b.everlookWrapped then
      local orig = b:GetScript("OnClick")
      b.everlookWrapped = true
      b:SetScript("OnClick", function(self, button, ...)
        if button == "LeftButton" and IsShiftKeyDown() and db() and db().shiftClick and self.index then
          if self.SetChecked then self:SetChecked(false) end
          I.takeMail(self.index)
          return
        end
        if orig then return orig(self, button, ...) end
      end)
    end
  end
end
I.wrapButtons = wrapButtons

---------------------------------------------------------------------------------------------------------------------
-- Events

local pendingScan
local function queueScan()
  if pendingScan then return end
  pendingScan = true
  C_Timer.After(0.2, function()
    pendingScan = nil
    if MailFrame and MailFrame:IsShown() then
      pcall(I.scan)
      I.refresh()
    end
  end)
end
I.queueScan = queueScan

local hooked
local ev = CreateFrame("Frame")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_INBOX_UPDATE")
ev:RegisterEvent("MAIL_CLOSED")
ev:RegisterEvent("MAIL_FAILED")
ev:RegisterEvent("UI_ERROR_MESSAGE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function(_, event, a1, a2)
  if not db() then return end
  if event == "MAIL_SHOW" then
    if not hooked then
      hooked = true
      wrapButtons()
      if InboxFrame and type(InboxFrame.Update) == "function" then
        hooksecurefunc(InboxFrame, "Update", function() pcall(I.paintRows) end)
      end
      local open = rawget(_G, "OpenMailFrame")
      if open and open.HookScript then
        -- the open mail sits beside the inbox: the summary moves next to it and back (unless you dragged it)
        local function replace() if panel and panel:IsShown() and not db().panel then place(panel) end end
        open:HookScript("OnShow", replace)
        open:HookScript("OnHide", replace)
      end
    end
    queueScan()
  elseif event == "MAIL_INBOX_UPDATE" then
    queueScan()
  elseif event == "MAIL_CLOSED" then
    if Q then I.stop("The mailbox closed:") end
    if panel then panel:Hide() end
  elseif event == "MAIL_FAILED" then
    if Q and Q.current then
      local id = mailId(Q.current)
      Q.tries[id] = (Q.tries[id] or 0) + 1
    end
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = a2 or a1
    if Q and not Q.paused and type(msg) == "string" and msg == rawget(_G, "ERR_INV_FULL") then
      Q.paused, Q.why = true, "bags"
      say("Your bags are full: make room, then click Continue (or /email open).")
      I.refresh()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    if Q and Q.paused and Q.why == "bags" and I.freeSlots() > 0 then I.refresh() end
  end
end)
