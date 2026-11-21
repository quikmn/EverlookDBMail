-- Sending: a list button beside the To: box with your recent recipients and your alts on this realm, names completed
-- as you type (from those two lists), and the postage with what the mail costs you in all. Recipients are remembered
-- when the game says the mail went (MAIL_SEND_SUCCESS). No bulk sending.
local _, ns = ...
local UI = LibStub("EverlookUI-1")
local S = {}
ns.send = S

local function db() return ns.db() end
local try = ns.try

-- The names for the list and completion: recent first, then alts not already there. { { name, alt = bool } }
function S.names()
  local out, seen = {}, {}
  local d = db()
  if not d then return out end
  local me = ns.me()
  if d.send.recent then
    for _, r in ipairs(d.recent) do
      local key = r.name:lower()
      if not seen[key] and r.name ~= me then
        seen[key] = true
        out[#out + 1] = { name = r.name, alt = ns.isAlt(r.name), recent = true }
      end
    end
  end
  if d.send.alts then
    for _, a in ipairs(ns.altList()) do
      local key = a.name:lower()
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = { name = a.name, alt = true, class = a.class, level = a.level }
      end
    end
  end
  return out
end

-- The first known name that starts with `typed` (case does not matter); nil when none or it is already whole.
function S.complete(typed)
  if type(typed) ~= "string" or #typed < 2 then return nil end
  local low = typed:lower()
  for _, n in ipairs(S.names()) do
    if n.name:lower():sub(1, #low) == low and #n.name > #typed then return n.name end
  end
end

-- "Postage 30c · sending 5g · 5g 30c in all"
function S.costText()
  local postage = tonumber((try(GetSendMailPrice))) or 0
  local send = 0
  if SendMailMoney and MoneyInputFrame_GetCopper then send = tonumber((try(MoneyInputFrame_GetCopper, SendMailMoney))) or 0 end
  local cod = SendMailCODButton and SendMailCODButton.GetChecked and SendMailCODButton:GetChecked()
  local parts = { "Postage " .. ns.money(postage) }
  if send > 0 and not cod then
    parts[#parts + 1] = "sending " .. ns.money(send)
    parts[#parts + 1] = ns.money(send + postage) .. " in all"
  elseif send > 0 and cod then
    parts[#parts + 1] = "C.O.D. " .. ns.money(send) .. " to you"
  end
  return table.concat(parts, "  \194\183  ")
end

---------------------------------------------------------------------------------------------------------------------
-- The list

local menu
local function closeMenu() if menu then menu:Hide() end end

local CLASS_HEX = setmetatable({}, { __index = function(t, class)
  local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  local v = c and c.colorStr or "ffc39bf2"
  rawset(t, class or "?", v)
  return v
end })

local function showMenu(anchor)
  local T = ns.app.T
  if not menu then
    menu = CreateFrame("Frame", "EverlookMailRecipients", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    UI.WindowChrome(menu, T)
    menu:EnableMouse(true)
    menu.buttons = {}
    menu.empty = UI.Text(menu, T.font, T.muted)
    menu.empty:SetPoint("TOPLEFT", 10, -10)
    menu.empty:SetWidth(200)
    menu.empty:SetText("No names yet: whoever you send mail to is added here, and each of your characters when it logs in.")
  end
  local names = S.names()
  for _, b in ipairs(menu.buttons) do b:Hide() end
  local y = -8
  local lastRecent = false
  for i, n in ipairs(names) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(20)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT")
      b.hl:SetAllPoints()
      b.hl:SetColorTexture(1, 1, 1, 0.08)
      b.text = UI.Text(b, T.font, T.text)
      b.text:SetPoint("LEFT", 8, 0)
      b.note = UI.Text(b, T.font - 1, T.muted)
      b.note:SetPoint("RIGHT", -8, 0)
      b.note:SetJustifyH("RIGHT")
      b:SetScript("OnClick", function(self)
        if SendMailNameEditBox then
          SendMailNameEditBox:SetText(self.name)
          if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
        end
        closeMenu()
      end)
      menu.buttons[i] = b
    end
    if lastRecent and not n.recent then y = y - 6 end -- a little gap between recent names and alts
    lastRecent = n.recent
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4, y)
    b:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
    b.name = n.name
    b.text:SetText(n.alt and ("|c%s%s|r"):format(CLASS_HEX[n.class or "?"], n.name) or n.name)
    b.note:SetText(n.alt and (n.level and ("your alt, " .. n.level) or "your alt") or "recent")
    b:Show()
    y = y - 20
  end
  menu.empty:SetShown(#names == 0)
  menu:SetSize(220, #names == 0 and 64 or (-y + 8))
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
end
S.showMenu = showMenu
S.menu = function() return menu end

---------------------------------------------------------------------------------------------------------------------
-- Setting up the send tab (once, the first time the mailbox opens)

local built
function S.build()
  if built or not SendMailNameEditBox then return end
  built = true
  local box = SendMailNameEditBox
  local T = ns.app.T
  local b = CreateFrame("Button", "EverlookMailRecipientsButton", box:GetParent() or box)
  b:SetSize(20, 20)
  b:SetPoint("LEFT", box, "RIGHT", 4, 0)
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  UI.SetIcon(tex, "user")
  tex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
  b:SetScript("OnClick", function(self)
    if menu and menu:IsShown() then closeMenu() else showMenu(box) end
  end)
  UI.Tooltip(b, "Recent recipients and your alts", "Click a name to put it in To:.")
  S.button = b
  local cost = (box:GetParent() or box):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cost:SetPoint("LEFT", b, "RIGHT", 6, 0)
  S.cost = cost
  box:HookScript("OnTextChanged", function(self, userInput)
    if not (userInput and db() and db().send.complete) then return end
    if S.completing then return end
    local typed = self:GetText() or ""
    local cursor = self.GetCursorPosition and self:GetCursorPosition() or #typed
    if cursor ~= #typed then return end
    local full = S.complete(typed)
    if full then
      S.completing = true
      self:SetText(full)
      self:HighlightText(#typed, #full)
      if self.SetCursorPosition then self:SetCursorPosition(#typed) end
      S.completing = nil
    end
  end)
  box:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function()
    if menu and menu:IsShown() and not menu:IsMouseOver() then closeMenu() end
  end) end)
  if SendMailFrame then
    SendMailFrame:HookScript("OnHide", closeMenu)
  end
  S.refresh()
end

function S.refresh()
  if S.cost then S.cost:SetText(S.costText()) end
  if S.button then S.button:SetShown(db() and (db().send.recent or db().send.alts) and true or false) end
end

-- the name of the mail being sent, remembered when the game says it went
local sending
if type(SendMail) == "function" then hooksecurefunc("SendMail", function(name) sending = ns.okv(name) end) end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MAIL_SHOW")
ev:RegisterEvent("MAIL_SEND_SUCCESS")
ev:RegisterEvent("MAIL_SEND_INFO_UPDATE")
ev:RegisterEvent("MAIL_FAILED")
ev:RegisterEvent("MAIL_CLOSED")
ev:SetScript("OnEvent", function(_, event)
  if not db() then return end
  if event == "MAIL_SHOW" then
    pcall(S.build)
  elseif event == "MAIL_SEND_SUCCESS" then
    if sending then pcall(ns.noteRecipient, sending) end
    sending = nil
    S.refresh()
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    S.refresh()
  elseif event == "MAIL_FAILED" then
    sending = nil
  elseif event == "MAIL_CLOSED" then
    closeMenu()
  end
end)
-- the money boxes change the total too
if SendMailMoney then
  for _, k in ipairs({ "gold", "silver", "copper" }) do
    local e = SendMailMoney[k] or _G["SendMailMoney" .. k:sub(1, 1):upper() .. k:sub(2)]
    if e and e.HookScript then e:HookScript("OnTextChanged", function() S.refresh() end) end
  end
end
