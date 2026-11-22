-- The inbox, all inside Blizzard's InboxFrame: every mail read and tagged as soon as the mailbox opens (a short
-- coloured tag on the right of the subject), a tick box on the left of each mail, a bar at the top with Select, Open
-- selected and Return selected, our Open all in place of Blizzard's, Shift-click a mail to take everything in it and
-- Ctrl-click to return it, and one chat line with the gold you took when the mailbox closes.
--
-- Nothing of Blizzard's is replaced: the mail rows move right a little to make room for the tick boxes (a plain
-- re-anchor), Blizzard's Open All button is hidden while ours stands in its place, and the Shift-/Ctrl-clicks land on
-- a frame of ours that covers a row only while the key is held (so a plain click is always Blizzard's own). Hooks are
-- hooksecurefunc and HookScript only. With another mail addon loaded (ns.rival) all of that steps aside; the tags stay.
--
-- One queue does all the work (Open all, Open selected, Shift-click, Return selected, Ctrl-click). Each step reads the
-- inbox again, picks the last mail that still has something to do (the highest index first, so mails that vanish never
-- move the ones still to do), does one thing (take the money, else the next item, or return the mail) and waits for
-- the server: until no mail command is pending, then db.delay seconds more. A mail is known by what stays the same
-- about it (subject, sender, C.O.D.) and its expiry within a few minutes, never by its exact expiry or index alone.
-- With full bags it still takes gold, then pauses until there is room. Closing the mailbox stops it at once.
local _, ns = ...
local I = { list = {}, totals = {}, sel = {} }
ns.inbox = I

local ROWS = 7 -- INBOXITEMS_TO_DISPLAY
local MAX_TRIES = 2
local WAIT_MAX = 5 -- seconds a take may stay pending before the queue moves on
local SHIFT = 12   -- the rows move right by this much to make room for the tick boxes

-- tag colours per category
I.COLOR = {
  ah_sold = "62cf88", ah_expired = "e8a54b", ah_cancelled = "ef7d5d", ah_won = "6db8f7", ah_outbid = "9aa7c7",
  player = "f2f2f2", alt = "c39bf2", npc = "d9c38c", cod = "ef5d5d", other = "8d94a3",
}

local function db() return ns.db() end
local try = ns.try
local function C() return ns.C() end
local function say(msg) if ns.app then ns.app:Print(msg) end end
local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

function I.isAlt(name) return ns.isAlt(name) end
local function mailOpen() return MailFrame and MailFrame:IsShown() and true or false end
-- our own buttons and clicks: off while another mail addon does them
local function active() return db() ~= nil and not ns.rival() end
I.active = active

local function auctionsMail()
  if not (db() and db().ledger) then return nil end
  local api = rawget(_G, "EverlookDBAuctionsAPI")
  if not (api and type(api.version) == "number" and api.version >= 4) then return nil end
  local ok, mail = pcall(function() return api.mail end)
  return ok and mail or nil
end
I.auctionsMail = auctionsMail

---------------------------------------------------------------------------------------------------------------------
-- Reading the inbox; knowing a mail again after the inbox changed

local function same(m, t)
  local c = C()
  if not (c and m and t) or c.key(m) ~= t.key then return false end
  if m.exp and t.exp then return math.abs(m.exp - t.exp) <= (c.SAME_MAIL or 180) end
  return true
end

function I.ref(m) return { key = C().key(m), exp = m.exp, index = m.index } end

function I.byIndex(i)
  for _, m in ipairs(I.list) do if m.index == i then return m end end
end

-- the mail a ref means now: at its index if it is still there, else the closest one that matches
function I.find(t)
  local at = I.byIndex(t.index)
  if at and same(at, t) then return at end
  local best, bd
  for _, m in ipairs(I.list) do
    if same(m, t) then
      local d = math.abs(m.index - t.index)
      if not bd or d < bd then best, bd = m, d end
    end
  end
  if best then t.index = best.index end
  return best
end

function I.scan()
  local c = C()
  if not c then return I.list end
  I.list = c.scan(I.isAlt)
  I.totals = c.totals(I.list)
  local _, total = try(GetInboxNumItems)
  I.shown = #I.list
  I.total = tonumber(total) or #I.list
  for k = #I.sel, 1, -1 do
    if not I.find(I.sel[k]) then table.remove(I.sel, k) end
  end
  local mail = auctionsMail()
  if mail then pcall(mail.scanned, I.list) end
  return I.list
end

-- What we would take from this mail: false and why when we leave it alone. any: you asked for this mail (Shift-click,
-- Open selected, Shift-click on Open all), so only C.O.D. and GM mail are left alone. The third value is the short
-- reason for the end-of-run line.
function I.wanted(m, any)
  if type(m) ~= "table" then return false, "no mail" end
  if (m.cod or 0) > 0 then return false, "C.O.D.: open it to pay", "C.O.D." end
  if m.isGM then return false, "from a Game Master: open it yourself", "GM mail" end
  if (m.money or 0) <= 0 and #(m.items or {}) == 0 then return false, "nothing to take" end
  if any then return true end
  local o = db().open
  local cat = m.cat
  if cat and cat:match("^ah_") then return o.ah and true or false, "auction house mail is off", "off in /email" end
  if cat == "alt" then return o.alts and true or false, "mail from your alts is off", "off in /email" end
  if cat == "npc" then return o.npc and true or false, "NPC mail is off", "off in /email" end
  if cat == "player" or cat == "other" then
    if not o.players then return false, "mail from players is off", "off in /email" end
    if not m.wasRead and not o.letters then return false, "an unread letter from a player", "unread letter" end
    return true
  end
  return true
end

-- Can this mail go back to its sender? Only mail from players that still has something in it, and wasn't returned.
function I.canReturn(m)
  if type(m) ~= "table" then return false, "no mail" end
  if not m.canReply or (m.cat and (m.cat:match("^ah_") or m.cat == "npc")) then
    return false, "auction house and NPC mail can't be returned"
  end
  if m.isGM then return false, "GM mail can't be returned" end
  if m.wasReturned then return false, "it was returned to you already" end
  local canDelete = rawget(_G, "InboxItemCanDelete")
  local del
  if type(canDelete) == "function" then
    del = try(canDelete, m.index)
  else
    del = (m.money or 0) <= 0 and #(m.items or {}) == 0
  end
  if del then return false, "a letter with nothing in it can't be returned (delete it instead)" end
  return true
end

function I.counts(any)
  local out = { take = 0, money = 0, items = 0, skipped = 0, why = {} }
  for _, m in ipairs(I.list) do
    local ok, _, short = I.wanted(m, any)
    if ok then
      out.take = out.take + 1
      out.money = out.money + (m.money or 0)
      out.items = out.items + #(m.items or {})
    elseif (m.money or 0) > 0 or #(m.items or {}) > 0 then
      out.skipped = out.skipped + 1
      if short then out.why[short] = (out.why[short] or 0) + 1 end
    end
  end
  return out
end

-- "1 C.O.D., 2 unread letters"
local function whyText(why)
  local parts = {}
  for _, k in ipairs({ "C.O.D.", "GM mail", "unread letter", "off in /email" }) do
    local n = why[k]
    if n then
      if k == "off in /email" then parts[#parts + 1] = ("%d off in /email"):format(n)
      elseif k == "C.O.D." then parts[#parts + 1] = n .. " C.O.D."
      elseif k == "GM mail" then parts[#parts + 1] = n .. " GM mail"
      else parts[#parts + 1] = plural(n, k) end
    end
  end
  return table.concat(parts, ", ")
end
I.whyText = whyText

---------------------------------------------------------------------------------------------------------------------
-- Ticking mails

function I.isSelected(m)
  for _, t in ipairs(I.sel) do
    local x = I.find(t)
    if x and x.index == m.index then return true end
  end
  return false
end

function I.setSelected(m, on)
  for k = #I.sel, 1, -1 do
    local x = I.find(I.sel[k])
    if not x or x.index == m.index then table.remove(I.sel, k) end
  end
  if on then I.sel[#I.sel + 1] = I.ref(m) end
end

function I.selected()
  local out, seen = {}, {}
  for _, t in ipairs(I.sel) do
    local x = I.find(t)
    if x and not seen[x.index] then seen[x.index] = true; out[#out + 1] = x end
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

function I.selectWhere(fn)
  I.sel = {}
  for _, m in ipairs(I.list) do
    if fn(m) then I.sel[#I.sel + 1] = I.ref(m) end
  end
  I.refresh()
end

function I.clearSelection() I.sel = {}; I.refresh() end

-- The Select menu: what you can tick at once (only the kinds there are)
I.PICKS = {
  { "Auction house", function(m) return m.cat ~= nil and m.cat:match("^ah_") ~= nil end },
  { "AH sold: gold", function(m) return m.cat == "ah_sold" end },
  { "AH items back", function(m) return m.cat == "ah_expired" or m.cat == "ah_cancelled" end },
  { "AH won", function(m) return m.cat == "ah_won" end },
  { "Your alts", function(m) return m.cat == "alt" end },
  { "NPC", function(m) return m.cat == "npc" end },
  { "Players", function(m) return m.cat == "player" or m.cat == "other" end },
  { "With gold", function(m) return (m.money or 0) > 0 end },
  { "With items", function(m) return #(m.items or {}) > 0 end },
}

function I.selectItems()
  local items = { { title = "Tick" } }
  items[#items + 1] = { text = "All", note = tostring(#I.list), func = function() I.selectWhere(function() return true end) end }
  items[#items + 1] = { text = "None", func = I.clearSelection }
  items[#items + 1] = { divider = true }
  for _, p in ipairs(I.PICKS) do
    local n = 0
    for _, m in ipairs(I.list) do if p[2](m) then n = n + 1 end end
    if n > 0 then items[#items + 1] = { text = p[1], note = tostring(n), func = function() I.selectWhere(p[2]) end } end
  end
  return items
end

local function rowMail(r)
  local page = (InboxFrame and InboxFrame.pageNum) or 1
  local b = _G["MailItem" .. r .. "Button"]
  local index = (b and b.IsShown and b:IsShown() and type(b.index) == "number") and b.index or ((page - 1) * ROWS + r)
  return I.byIndex(index), index
end
I.rowMail = rowMail

-- a tick box clicked: Shift ticks the range from the last one, Ctrl every mail from the same sender
function I.tick(r, on)
  local m = rowMail(r)
  if not m then I.refresh() return end
  if IsShiftKeyDown() and I.lastTick then
    local a, b = math.min(I.lastTick, m.index), math.max(I.lastTick, m.index)
    for _, x in ipairs(I.list) do
      if x.index >= a and x.index <= b then I.setSelected(x, true) end
    end
  elseif IsControlKeyDown() and m.sender then
    for _, x in ipairs(I.list) do
      if x.sender == m.sender then I.setSelected(x, on) end
    end
  else
    I.setSelected(m, on)
  end
  I.lastTick = m.index
  I.refresh()
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

-- nil, or { kind = "take"|"return", all (Open all), any (ignore the Open all filters), targets = { refs },
--   fromSelection, money, items, returned, mails = {}, tries = {}, done = {}, paused, why, token, sent, current }
local Q
I.state = function() return Q end

local function tid(m) return (C() and C().key(m) or "?") .. "#" .. tostring(m.index) end

local function setOpeningAll(v)
  pcall(function() if C_Mail and C_Mail.SetOpeningAll then C_Mail.SetOpeningAll(v) end end)
end

local function mailCount(q)
  local n = 0
  for _ in pairs(q.mails) do n = n + 1 end
  return n
end

local function report(q, head)
  if q.kind == "return" then
    return ("%s %s returned."):format(head, plural(q.returned, "mail"))
  end
  return ("%s %s, %s from %s."):format(head, ns.money(q.money), plural(q.items, "item"), plural(mailCount(q), "mail"))
end

local function finish(msg)
  local q = Q
  Q = nil
  setOpeningAll(false)
  if q and q.fromSelection then I.sel = {} end
  if q and msg then say(msg) end
  I.lastRun = q
  I.refresh()
end

function I.stop(why)
  if not Q then return end
  finish(report(Q, why or "Stopped."))
end

local step

local function schedule(delay)
  if not Q then return end
  local token = {}
  Q.token = token
  C_Timer.After(delay, function() if Q and Q.token == token then step() end end)
end

-- The next mail to work on; nil, true when only items are left and the bags are full.
local function pick()
  local cands, seen = {}, {}
  local function add(m)
    local id = tid(m)
    if seen[id] or Q.done[id] or (Q.tries[id] or 0) >= MAX_TRIES then return end
    seen[id] = true
    cands[#cands + 1] = m
  end
  for _, t in ipairs(Q.targets) do
    local m = I.find(t)
    if m then
      if Q.kind == "return" then
        if I.canReturn(m) then add(m) end
      elseif I.wanted(m, true) then
        add(m)
      end
    end
  end
  if Q.all and Q.kind == "take" then
    for _, m in ipairs(I.list) do if I.wanted(m, Q.any) then add(m) end end
  end
  if #cands == 0 then return nil end
  table.sort(cands, function(a, b) return a.index > b.index end)
  if Q.kind == "take" and I.freeSlots() <= 0 then
    -- full bags: the gold still comes
    for _, m in ipairs(cands) do if (m.money or 0) > 0 then return m end end
    return nil, true
  end
  return cands[1]
end

local function pauseFull()
  Q.paused, Q.why = true, "bags"
  if not Q.toldFull then
    Q.toldFull = true
    say("Your bags are full: make room and it goes on (or click Continue).")
  end
  I.refresh()
end

step = function()
  if not Q or Q.paused then return end
  if not mailOpen() then return I.stop("The mailbox closed:") end
  -- the server is still busy with the last one
  local pending = C_Mail and C_Mail.IsCommandPending and try(C_Mail.IsCommandPending)
  if pending and (GetTime() - (Q.sent or 0)) < WAIT_MAX then return schedule(0.1) end
  I.scan()
  local m, full = pick()
  if full then return pauseFull() end
  if not m then
    local q = Q
    local msg = report(q, "Done:")
    if q.all then
      local left = whyText(I.counts(q.any).why)
      if left ~= "" then msg = msg .. " Left: " .. left .. "." end
      if (I.total or 0) > (I.shown or 0) then
        msg = msg .. (" %d more on the server: they come in as the inbox empties, and Open all goes on."):format(I.total - I.shown)
        I.more = { t = GetTime(), any = q.any }
        pcall(CheckInbox)
      end
    end
    finish(msg)
    return
  end
  local id = tid(m)
  Q.tries[id] = Q.tries[id] or 0
  Q.mails[id] = true
  Q.current = m
  local mail = auctionsMail()
  if Q.kind == "return" then
    Q.done[id] = true
    if pcall(ReturnInboxItem, m.index) then Q.returned = Q.returned + 1 end
  elseif (m.money or 0) > 0 then
    if mail then pcall(mail.taken, m, "money") end
    if pcall(TakeInboxMoney, m.index) then Q.money = Q.money + m.money else Q.tries[id] = Q.tries[id] + 1 end
  else
    local it = m.items[1]
    if mail then pcall(mail.taken, m, "item", it.slot) end
    if pcall(TakeInboxItem, m.index, it.slot) then Q.items = Q.items + 1 else Q.tries[id] = Q.tries[id] + 1 end
  end
  Q.sent = GetTime()
  I.refresh()
  schedule(math.max(0.15, tonumber(db().delay) or 0.3))
end

-- opts: kind ("take" default | "return"), all, any, targets, fromSelection. While a run of the same kind is going,
-- new mails join it (Shift-click three mails quickly: all three are taken).
local function start(opts)
  if not mailOpen() then say("Open a mailbox first.") return false end
  local kind = opts.kind or "take"
  if Q then
    if Q.kind ~= kind then say("Busy: wait for it to finish, or click Stop.") return false end
    for _, t in ipairs(opts.targets or {}) do Q.targets[#Q.targets + 1] = t end
    if opts.all and not Q.all then Q.all, Q.any = true, opts.any end
    if opts.fromSelection then Q.fromSelection = true end
    if Q.paused then Q.paused, Q.why = nil, nil; schedule(0) end
    I.refresh()
    return true
  end
  I.more = nil
  Q = { kind = kind, all = opts.all, any = opts.any, targets = opts.targets or {}, fromSelection = opts.fromSelection,
    money = 0, items = 0, returned = 0, mails = {}, tries = {}, done = {} }
  if kind == "take" then setOpeningAll(true) end
  schedule(0)
  I.refresh()
  return true
end

-- Open all: the mails the settings say; any (Shift-click on the button) takes every mail but C.O.D. and GM mail.
function I.openAll(any) return start({ all = true, any = any and true or nil }) end

-- Shift-click: everything in this one mail (by inbox index)
function I.takeMail(index)
  I.scan()
  local m = I.byIndex(index)
  local ok, why = I.wanted(m, true)
  if not ok then say(("Not taken: %s."):format(why)) return false end
  return start({ targets = { I.ref(m) } })
end

-- Ctrl-click: send this one mail back
function I.returnMail(index)
  I.scan()
  local m = I.byIndex(index)
  local ok, why = I.canReturn(m)
  if not ok then say(("Not returned: %s."):format(why)) return false end
  return start({ kind = "return", targets = { I.ref(m) } })
end

function I.openSelected()
  I.scan()
  local targets, skipped = {}, {}
  for _, m in ipairs(I.selected()) do
    local ok, why = I.wanted(m, true)
    if ok then targets[#targets + 1] = I.ref(m) elseif why ~= "nothing to take" then skipped[#skipped + 1] = why end
  end
  if #skipped > 0 then say(("%s left alone: %s."):format(plural(#skipped, "ticked mail"), skipped[1])) end
  if #targets == 0 then say("Nothing to take in the mail you ticked.") return false end
  return start({ targets = targets, fromSelection = true })
end

function I.returnSelected()
  I.scan()
  local targets, skipped = {}, {}
  for _, m in ipairs(I.selected()) do
    local ok, why = I.canReturn(m)
    if ok then targets[#targets + 1] = I.ref(m) else skipped[#skipped + 1] = why end
  end
  if #skipped > 0 then say(("%s can't go back: %s."):format(plural(#skipped, "ticked mail"), skipped[1])) end
  if #targets == 0 then return false end
  return start({ kind = "return", targets = targets, fromSelection = true })
end

---------------------------------------------------------------------------------------------------------------------
-- The rows: the tag, the tick box, the rows moved right for it, the Shift-/Ctrl-click cover

function I.tagText(m)
  local c = C()
  if not (c and m) or m.cat == "other" then return "" end
  local label = c.LABEL[m.cat] or m.cat or ""
  if m.cat == "ah_sold" and m.pending then label = "AH pending" end
  return ("|cff%s%s|r"):format(I.COLOR[m.cat] or "ffffff", label)
end

local moved -- the first row's anchor before we moved it
local function placeRows(on)
  local first = rawget(_G, "MailItem1")
  if not first then return end
  if on and not moved then
    local p, rel, rp, x, y = first:GetPoint(1)
    moved = { p or "TOPLEFT", rel or InboxFrame, rp or "TOPLEFT", tonumber(x) or 13, tonumber(y) or -70 }
    first:ClearAllPoints()
    first:SetPoint(moved[1], moved[2], moved[3], moved[4] + SHIFT, moved[5])
  elseif not on and moved then
    first:ClearAllPoints()
    first:SetPoint(moved[1], moved[2], moved[3], moved[4], moved[5])
    moved = nil
  end
end
I.rowsMoved = function() return moved ~= nil end

local function tickTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Tick for Open selected / Return selected")
  GameTooltip:AddLine("Shift-click: tick every mail from the last one you ticked.", 1, 1, 1, true)
  GameTooltip:AddLine("Ctrl-click: every mail from this sender.", 1, 1, 1, true)
  GameTooltip:Show()
end

local function ensureRow(r)
  local row = _G["MailItem" .. r]
  if not row then return nil end
  if not row.everlookTag then
    local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -21)
    t:SetJustifyH("RIGHT")
    row.everlookTag = t
  end
  if not row.everlookTick then
    local b = CreateFrame("CheckButton", "EverlookMailTick" .. r, row, "UICheckButtonTemplate")
    b:SetSize(20, 20)
    b:SetPoint("RIGHT", row, "LEFT", 0, 1)
    b:SetScript("OnClick", function(self) I.tick(r, self:GetChecked() and true or false) end)
    b:SetScript("OnEnter", tickTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    row.everlookTick = b
  end
  if not row.everlookClick then
    -- shown only while Shift or Ctrl is held, over a row with a mail: that click is ours, a plain click Blizzard's
    local c = CreateFrame("Button", "EverlookMailRowClick" .. r, row)
    c:SetAllPoints(row)
    c:SetFrameLevel((row:GetFrameLevel() or 1) + 10)
    c:RegisterForClicks("LeftButtonUp")
    c:SetScript("OnClick", function() I.modClick(r) end)
    c:SetScript("OnEnter", function(self) I.rowTip(self, r) end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:Hide()
    row.everlookClick = c
  end
  return row
end

function I.modClick(r)
  local d = db()
  local m, index = rowMail(r)
  if not (d and active() and m) then return end
  if IsControlKeyDown() and d.ctrlReturn then
    I.returnMail(index)
  elseif IsShiftKeyDown() and d.shiftClick then
    I.takeMail(index)
  end
end

function I.rowTip(self, r)
  local m = rowMail(r)
  if not m then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(m.subject or "Mail")
  if m.sender then GameTooltip:AddLine(m.sender, 1, 0.82, 0) end
  local d = db()
  if d.shiftClick then
    local ok, why = I.wanted(m, true)
    if ok then
      local parts = {}
      if (m.money or 0) > 0 then parts[#parts + 1] = ns.money(m.money) end
      if #(m.items or {}) > 0 then parts[#parts + 1] = plural(#m.items, "item") end
      GameTooltip:AddLine("Shift-click: take " .. table.concat(parts, " and "), 1, 1, 1)
    else
      GameTooltip:AddLine("Shift-click: " .. why, 0.6, 0.6, 0.6)
    end
  end
  if d.ctrlReturn then
    local ok, why = I.canReturn(m)
    local c = ok and 1 or 0.6
    GameTooltip:AddLine("Ctrl-click: " .. (ok and "return it to the sender" or why), c, c, c)
  end
  GameTooltip:Show()
end

-- the Shift-/Ctrl-click covers: shown while the key is held, over rows with a mail
function I.updateCovers()
  local d = db()
  local on = d and active() and mailOpen()
  local mod = on and ((IsShiftKeyDown() and d.shiftClick) or (IsControlKeyDown() and d.ctrlReturn))
  for r = 1, ROWS do
    local row = _G["MailItem" .. r]
    local c = row and row.everlookClick
    if c then
      local b = _G["MailItem" .. r .. "Button"]
      c:SetShown((mod and b and b:IsShown() and rowMail(r)) and true or false)
    end
  end
end

function I.paintRows()
  local d = db()
  if not d then return end
  local ticks = active() and d.select
  placeRows(ticks)
  for r = 1, ROWS do
    local row = ensureRow(r)
    if row then
      local m = rowMail(r)
      local subj = _G["MailItem" .. r .. "Subject"]
      if subj and not row.everlookSubjectW then
        local w = tonumber(subj:GetWidth()) or 0
        row.everlookSubjectW = w > 0 and w or 248
      end
      local text = (d.tags and m) and I.tagText(m) or ""
      row.everlookTag:SetText(text)
      row.everlookTag:SetShown(text ~= "")
      if subj and row.everlookSubjectW then
        -- the subject stops short of the tag instead of running under it
        local w = row.everlookSubjectW
        if text ~= "" then w = math.max(80, w - (tonumber(row.everlookTag:GetStringWidth()) or 40) - 8) end
        subj:SetWidth(w)
      end
      if ticks and m then
        row.everlookTick:Show()
        row.everlookTick:SetChecked(I.isSelected(m))
      else
        row.everlookTick:Hide()
      end
    end
  end
  I.updateCovers()
end

---------------------------------------------------------------------------------------------------------------------
-- The bar at the top of the inbox (Select, Open selected, Return selected) and our Open all

local bar, openAllBtn
I.bar = function() return bar end
I.openAllButton = function() return openAllBtn end

local function button(name, parent, text, w, onClick)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function tip(b, fn)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    fn()
    GameTooltip:Show()
  end)
end

local function makeBar()
  local f = CreateFrame("Frame", "EverlookMailInboxBar", InboxFrame)
  -- right of the portrait, under the title, above the first mail
  f:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 62, -28)
  f:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -8, -28)
  f:SetHeight(24)
  f.select = button("EverlookMailSelectButton", f, "Select", 72, function(self) ns.menu(self, I.selectItems()) end)
  f.select:SetPoint("TOPLEFT", 0, 0)
  tip(f.select, function()
    GameTooltip:SetText("Select")
    GameTooltip:AddLine("Tick all, none, or one kind of mail at once.", 1, 1, 1, true)
  end)
  f.ret = button("EverlookMailReturnSelected", f, "Return", 80, function() I.returnSelected() end)
  f.ret:SetPoint("TOPRIGHT", 0, 0)
  tip(f.ret, function()
    GameTooltip:SetText("Return selected")
    GameTooltip:AddLine("Sends the ticked mail back to the sender. Only mail from players can go back.", 1, 1, 1, true)
    GameTooltip:AddLine("Ctrl-click a mail to return just that one.", 0.7, 0.7, 0.7, true)
  end)
  f.open = button("EverlookMailOpenSelected", f, "Open selected", 96, function()
    if Q and Q.fromSelection and Q.kind == "take" and not Q.paused then I.stop("Stopped:") else I.openSelected() end
  end)
  f.open:SetPoint("TOPRIGHT", f.ret, "TOPLEFT", -2, 0)
  tip(f.open, function()
    GameTooltip:SetText("Open selected")
    GameTooltip:AddLine("Takes the gold and items of the ticked mail. C.O.D. and GM mail are left alone.", 1, 1, 1, true)
    GameTooltip:AddLine("Shift-click a mail to take just that one.", 0.7, 0.7, 0.7, true)
  end)
  return f
end

local function makeOpenAll()
  local b = CreateFrame("Button", "EverlookMailOpenAllButton", InboxFrame, "UIPanelButtonTemplate")
  b:SetSize(120, 24)
  b:SetPoint("CENTER", InboxFrame, "BOTTOM", 0, 26) -- where Blizzard's Open All is
  b:SetText("Open all")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, which)
    if which == "RightButton" then ns.app:Open("openall") return end
    if Q and Q.all and not Q.paused then I.stop("Stopped:") return end
    I.openAll(IsShiftKeyDown())
  end)
  tip(b, function()
    local cnt = I.counts()
    GameTooltip:SetText("Open all")
    if cnt.take > 0 then
      GameTooltip:AddLine(("Takes %s, %s from %s."):format(ns.money(cnt.money), plural(cnt.items, "item"), plural(cnt.take, "mail")), 1, 1, 1, true)
    else
      GameTooltip:AddLine("Nothing for it to take.", 1, 1, 1, true)
    end
    if cnt.skipped > 0 then GameTooltip:AddLine("Left alone: " .. whyText(cnt.why) .. ".", 0.7, 0.7, 0.7, true) end
    if (I.total or 0) > (I.shown or 0) then
      GameTooltip:AddLine(("%d more on the server: they come in as the inbox empties."):format(I.total - I.shown), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine("Shift-click: every mail but C.O.D. and GM mail.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Right-click: what it takes (/email).", 0.7, 0.7, 0.7, true)
  end)
  return b
end

local function blizzOpenAll() return rawget(_G, "OpenAllMail") end

function I.paintBar()
  local d = db()
  if not (d and InboxFrame) then return end
  local on = active()
  local tooMuch = rawget(_G, "InboxTooMuchMail")
  if on and d.select then
    bar = bar or makeBar()
    bar:Show()
    -- the game's "too much mail" line sits where our bar is: Open all's tooltip and its last line say it instead
    if tooMuch and tooMuch:IsShown() then tooMuch:Hide() end
    local open, ret = 0, 0
    for _, m in ipairs(I.selected()) do
      if I.wanted(m, true) then open = open + 1 end
      if I.canReturn(m) then ret = ret + 1 end
    end
    if Q and Q.fromSelection and not Q.paused and Q.kind == "take" then
      bar.open:SetText("Stop")
      bar.open:SetEnabled(true)
    else
      bar.open:SetText(open > 0 and ("Open (%d)"):format(open) or "Open selected")
      bar.open:SetEnabled(open > 0)
    end
    bar.ret:SetText(ret > 0 and ("Return (%d)"):format(ret) or "Return")
    bar.ret:SetEnabled(ret > 0 and not Q)
    bar.select:SetEnabled(#I.list > 0)
  elseif bar then
    bar:Hide()
  end
  local blizz = blizzOpenAll()
  if on then
    openAllBtn = openAllBtn or makeOpenAll()
    openAllBtn:Show()
    if blizz and blizz:IsShown() then blizz:Hide() end
    local cnt = I.counts()
    if Q and Q.paused then
      openAllBtn:SetText("Continue")
    elseif Q and Q.all then
      openAllBtn:SetText("Stop")
    else
      openAllBtn:SetText(cnt.take > 0 and ("Open all (%d)"):format(cnt.take) or "Open all")
    end
    openAllBtn:SetEnabled((Q ~= nil and (Q.all or Q.paused)) or (not Q and #I.list > 0))
  else
    if openAllBtn then openAllBtn:Hide() end
    if I.hidBlizz and blizz and not blizz:IsShown() then blizz:Show() end
  end
  I.hidBlizz = on or nil
end

function I.refresh()
  pcall(I.paintRows)
  pcall(I.paintBar)
end

---------------------------------------------------------------------------------------------------------------------
-- Events

local visit -- the gold you took while the mailbox is open: { last, got }
I.visit = function() return visit end

local pendingScan
local function queueScan()
  if pendingScan then return end
  pendingScan = true
  C_Timer.After(0.2, function()
    pendingScan = nil
    if not mailOpen() then return end
    pcall(I.scan)
    -- Open all finished with more on the server: it goes on once they are here
    local more = I.more
    if more and not Q and active() then
      if GetTime() - more.t > 120 then
        I.more = nil
      elseif I.counts(more.any).take > 0 then
        I.more = nil
        I.openAll(more.any)
      end
    end
    I.refresh()
  end)
end
I.queueScan = queueScan

local hooked
local function hookOnce()
  if hooked then return end
  hooked = true
  for r = 1, ROWS do ensureRow(r) end
  if InboxFrame and type(InboxFrame.Update) == "function" then
    hooksecurefunc(InboxFrame, "Update", function() I.refresh() end)
  end
  if type(rawget(_G, "InboxFrame_Update")) == "function" then
    hooksecurefunc("InboxFrame_Update", function() I.refresh() end)
  end
  local blizz = blizzOpenAll()
  if blizz and blizz.HookScript then
    -- the game shows its Open All again (gamepad mode): ours stays the one
    blizz:HookScript("OnShow", function(self) if active() and openAllBtn and openAllBtn:IsShown() then self:Hide() end end)
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "MAIL_FAILED", "UI_ERROR_MESSAGE", "BAG_UPDATE_DELAYED",
  "MODIFIER_STATE_CHANGED", "PLAYER_MONEY" }) do
  ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
  local d = db()
  if not d then return end
  if event == "MAIL_SHOW" then
    hookOnce()
    if ns.rival() then ns.stepAsideNotice() end
    visit = { last = tonumber((try(GetMoney))) or 0, got = 0 }
    queueScan()
  elseif event == "MAIL_INBOX_UPDATE" then
    queueScan()
  elseif event == "MAIL_CLOSED" then
    if Q then I.stop("The mailbox closed:") end
    I.more = nil
    local v = visit
    visit = nil
    if v and v.got > 0 and d.collected and active() then say(("You took %s from the mailbox."):format(ns.money(v.got))) end
    I.updateCovers()
  elseif event == "MAIL_FAILED" then
    if Q and Q.current then
      local id = tid(Q.current)
      Q.tries[id] = (Q.tries[id] or 0) + 1
    end
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = a2 or a1
    if Q and not Q.paused and Q.kind == "take" and type(msg) == "string" and msg == rawget(_G, "ERR_INV_FULL") then
      pauseFull()
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    -- room again: it goes on by itself
    if Q and Q.paused and Q.why == "bags" and I.freeSlots() > 0 then
      Q.paused, Q.why = nil, nil
      schedule(0)
      I.refresh()
    end
  elseif event == "MODIFIER_STATE_CHANGED" then
    if mailOpen() then I.updateCovers() end
  elseif event == "PLAYER_MONEY" then
    if visit and mailOpen() then
      local now = tonumber((try(GetMoney))) or visit.last
      if now > visit.last then visit.got = visit.got + (now - visit.last) end
      visit.last = now
    end
  end
end)
