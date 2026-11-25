-- Sending, inside Blizzard's send tab: Tab in To: takes the suggested name (the one highlighted in the box, else the
-- one picked in the game's suggestion list), names complete as you type from your recent recipients, alts, friends
-- and guild, a small arrow attached to the To: box lists them, a line above the money boxes says what the mail costs you in
-- all when you send gold, and the gold becomes the subject when you leave it empty. Recipients are remembered when
-- the game says the mail went (MAIL_SEND_SUCCESS). No bulk sending.
--
-- Hooks only (HookScript, hooksecurefunc). The game's own suggestion list is never written to: Tab reads which name it
-- shows and clicks that name's button, the way Enter does. With another mail addon loaded (ns.rival) the To: parts and
-- the subject step aside; the total and remembering recipients stay.
local _, ns = ...
local S = {}
ns.send = S

local function db() return ns.db() end
local try = ns.try
local function active() return db() ~= nil and not ns.rival() end

local CLASS_HEX = setmetatable({}, { __index = function(t, class)
  local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  local v = c and c.colorStr or "ffc39bf2"
  rawset(t, class or "?", v)
  return v
end })

local function plainName(name)
  name = ns.okv(name)
  if type(name) ~= "string" or name == "" then return nil end
  if type(Ambiguate) == "function" then
    local ok, a = pcall(Ambiguate, name, "mail")
    if ok and type(a) == "string" and a ~= "" then return a end
  end
  return ns.shortName(name)
end

function S.friends()
  local out = {}
  local F = C_FriendList
  local n = F and F.GetNumFriends and tonumber((try(F.GetNumFriends))) or 0
  for i = 1, n do
    local info = try(F.GetFriendInfoByIndex, i)
    local name = type(info) == "table" and plainName(info.name)
    if name then out[#out + 1] = { name = name, online = info.connected and true or false, class = info.className } end
  end
  return out
end

function S.guild()
  local out = {}
  if not (type(IsInGuild) == "function" and try(IsInGuild)) then return out end
  local n = tonumber((try(GetNumGuildMembers))) or 0
  for i = 1, n do
    local ok, name, _, _, level, _, _, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
    name = ok and plainName(name)
    if name then out[#out + 1] = { name = name, level = ns.okv(level), online = ns.okv(online) and true or false, class = ns.okv(class) } end
  end
  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  return out
end

-- The names for the list and completion, once each, in this order: recent, alts, friends, guild.
-- { { name, from = "recent"|"alt"|"friend"|"guild", alt = bool, class, level, online } }
function S.names()
  local out, seen = {}, {}
  local d = db()
  if not d then return out end
  local me = ns.me()
  local function add(n, from)
    local key = n.name:lower()
    if seen[key] or n.name == me then return end
    seen[key] = true
    n.from = from
    out[#out + 1] = n
  end
  if d.send.recent then
    for _, r in ipairs(d.recent) do add({ name = r.name, alt = ns.isAlt(r.name) }, "recent") end
  end
  if d.send.alts then
    for _, a in ipairs(ns.altList()) do add({ name = a.name, alt = true, class = a.class, level = a.level }, "alt") end
  end
  if d.send.friends then
    for _, f in ipairs(S.friends()) do add(f, "friend") end
    for _, g in ipairs(S.guild()) do add(g, "guild") end
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

---------------------------------------------------------------------------------------------------------------------
-- Money: the total above the money boxes, and the gold as the subject

local function sendCopper()
  if SendMailMoney and MoneyInputFrame_GetCopper then return tonumber((try(MoneyInputFrame_GetCopper, SendMailMoney))) or 0 end
  return 0
end
local function isCOD() return SendMailCODButton and SendMailCODButton.GetChecked and SendMailCODButton:GetChecked() and true or false end

-- "5g 30s" without colours, for a subject
function S.plainMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end

-- "Total 5g 30c" when sending gold, "C.O.D.: they pay you 5g" for C.O.D., "" otherwise
function S.totalText()
  local send = sendCopper()
  if send <= 0 then return "" end
  if isCOD() then return "C.O.D.: they pay you " .. ns.money(send) end
  local postage = tonumber((try(GetSendMailPrice))) or 0
  return "Total " .. ns.money(send + postage)
end

-- the gold as the subject while the subject is empty (or still ours)
function S.wire()
  local d = db()
  local subj = rawget(_G, "SendMailSubjectEditBox")
  if not (d and d.send.wire and active() and subj) then return end
  local now = subj:GetText() or ""
  if now ~= "" and now ~= S.wired then return end
  local send = sendCopper()
  local text = (send > 0 and not isCOD()) and S.plainMoney(send) or ""
  if text ~= now then
    subj:SetText(text)
    if text ~= "" then S.wired = text else S.wired = nil end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- The To: list

function S.menuItems()
  local groups = { recent = {}, alt = {}, friend = {}, guild = {} }
  for _, n in ipairs(S.names()) do table.insert(groups[n.from], n) end
  local items = {}
  local function pick(name)
    return function()
      if SendMailNameEditBox then
        SendMailNameEditBox:SetText(name)
        if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
      end
    end
  end
  local function section(title, list, max, note)
    if #list == 0 then return end
    if #items > 0 then items[#items + 1] = { divider = true } end
    items[#items + 1] = { title = title }
    for i, n in ipairs(list) do
      if i > max then break end
      local text = (n.alt or n.class) and ("|c%s%s|r"):format(CLASS_HEX[n.class or "?"], n.name) or n.name
      items[#items + 1] = { text = text, name = n.name, note = note(n), func = pick(n.name) }
    end
  end
  section("Recent", groups.recent, 30, function(n) return n.alt and "your alt" or nil end)
  section("Your alts", groups.alt, 30, function(n) return n.level and tostring(n.level) or nil end)
  section("Friends", groups.friend, 20, function(n) return n.online and "online" or nil end)
  section("Guild", groups.guild, 25, function(n) return n.online and "online" or nil end)
  if #items == 0 then
    items[1] = { title = "No names yet" }
    items[2] = { text = "Whoever you send mail to shows up here, and your alts as they log in.", disabled = true, func = function() end }
  end
  return items
end

function S.showMenu()
  if SendMailNameEditBox then return ns.menu(SendMailNameEditBox, S.menuItems()) end
end

---------------------------------------------------------------------------------------------------------------------
-- Tab in To:

local function autoBox(box)
  local ac = rawget(_G, "AutoCompleteBox")
  if ac and ac:IsShown() and ac.parent == box then return ac end
end

-- After the game's own Tab handling (which only moves its list's highlight): take the suggestion.
function S.onTab(box)
  local d = db()
  if not (d and d.send.tab and active()) or IsShiftKeyDown() then return end
  local text = box:GetText() or ""
  local cur = box.GetCursorPosition and tonumber(box:GetCursorPosition()) or #text
  local ac = autoBox(box)
  if cur < #text then
    -- the name completed in the box (the highlighted rest): keep it
    if box.HighlightText then box:HighlightText(#text, #text) end
    if box.SetCursorPosition then box:SetCursorPosition(#text) end
    if ac then ac:Hide() end
    return "inline"
  end
  if ac then
    -- the game moved its highlight one down when Tab was pressed: the one it showed before is the one to take
    local n = tonumber(ac.numResults) or 0
    local sel = tonumber(ac.selectedIndex) or 1
    if n > 0 then
      local prev = sel - 1
      if prev < 1 then prev = n end
      local b = _G["AutoCompleteButton" .. prev]
      if b and b.nameInfo and type(AutoCompleteButton_OnClick) == "function" then
        AutoCompleteButton_OnClick(b)
        return "list"
      end
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- Setting up the send tab (once, the first time the mailbox opens)

local built
function S.build()
  if built or not SendMailNameEditBox then return end
  built = true
  local box = SendMailNameEditBox
  local parent = rawget(_G, "SendMailFrame") or box:GetParent() or box

  -- the arrow attached to the To: box
  local b = CreateFrame("Button", "EverlookMailToButton", parent)
  b:SetSize(22, 22)
  b:SetPoint("LEFT", box, "RIGHT", 1, 1)
  b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  b:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function() S.showMenu() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Recent, alts, friends and guild")
    GameTooltip:AddLine("Click a name to put it in To:. In To:, Tab takes the suggested name.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  S.button = b

  -- on the "Amount to send:" line, right above the money boxes (under Postage it ran into the Subject box)
  local total = parent:CreateFontString("EverlookMailSendTotal", "OVERLAY", "GameFontHighlightSmall")
  local money = rawget(_G, "SendMailMoney")
  local cost = rawget(_G, "SendMailCostMoneyFrame")
  if money then total:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", 0, 4)
  elseif cost then total:SetPoint("TOPRIGHT", cost, "BOTTOMRIGHT", 0, -1)
  else total:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -48) end
  total:SetJustifyH("RIGHT")
  S.total = total

  box:HookScript("OnTextChanged", function(self, userInput)
    if not (userInput and active() and db().send.complete) then return end
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
  box:HookScript("OnTabPressed", function(self) S.onTab(self) end)

  -- the money boxes and the Send money / C.O.D. choice change the total and the subject
  local function moneyChanged() S.refresh(); S.wire() end
  for _, n in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
    local e = rawget(_G, n)
    if e and e.HookScript then e:HookScript("OnTextChanged", moneyChanged) end
  end
  for _, n in ipairs({ "SendMailSendMoneyButton", "SendMailCODButton" }) do
    local e = rawget(_G, n)
    if e and e.HookScript then e:HookScript("OnClick", moneyChanged) end
  end
  if parent.HookScript then parent:HookScript("OnHide", function() ns.closeMenu() end) end
  S.refresh()
end

function S.refresh()
  local d = db()
  if not d then return end
  if S.total then
    local t = d.send.total and S.totalText() or ""
    S.total:SetText(t)
    S.total:SetShown(t ~= "")
  end
  if S.button then S.button:SetShown(active() and (d.send.recent or d.send.alts or d.send.friends) and true or false) end
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
    S.refresh()
  elseif event == "MAIL_SEND_SUCCESS" then
    if sending then pcall(ns.noteRecipient, sending) end
    sending = nil
    S.wired = nil
    S.refresh()
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    S.refresh()
  elseif event == "MAIL_FAILED" then
    sending = nil
  elseif event == "MAIL_CLOSED" then
    ns.closeMenu()
  end
end)
