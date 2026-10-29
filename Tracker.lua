-- ASBuilder tracker: the small window you play with, in three separate panels:
--   BUILD    the active build of the hero's class: the next spell and piece of jewelry to
--            take or upgrade
--   SPELLS   every spell that matters: the build's (faded until taken, then a green dot), the
--            ones you took that it does not want (violet dot) and the ones to banish
--   JEWELRY  what you wear (green dot: in the build, violet dot: not), with what each piece
--            gives right now, and the build's pieces you still miss

local AB = ASBuilder
local W = AB.W
local T = AB.T

local TR = {}
AB.Tracker = TR

local WIDTH = 240
local ROW_H = 16
local GAP = 3
local SPELL_ROWS = 15   -- 6 build spells, up to 6 others you know, 3 to banish
local JEWEL_ROWS = 12
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a white circle

local f

local function SavePoint()
  local point, _, rel, x, y = f:GetPoint()
  ASBuilderDB.tracker.point = { point, rel, x, y }
end

function AB.ApplyTrackerLayout()
  if not f then return end
  local db = ASBuilderDB.tracker
  f:SetScale(db.scale or 1)
  f:ClearAllPoints()
  local p = db.point
  if p and p[1] then
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else
    f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
  end
end

-- ---------------------------------------------------------------- tooltips
local function RowTip(self, tt)
  local d = self.data
  if not d then return end
  local cls = AB.CurrentClass()
  local row, w = d.row, d.worn
  if d.pick then AB.FillTooltip(tt, cls, d.pick) else tt:SetText(w and w.name or "?", 1, 1, 1) end
  if d.ban then
    tt:AddLine(" ")
    if d.banished then
      tt:AddLine(T("Banished this run."), 0.6, 0.6, 0.6)
      tt:AddLine(T("Click: not banished after all"), 0.5, 1, 0.5)
    else
      tt:AddLine(T("Banish this card whenever it is offered."), 1, 0.4, 0.4, 1)
      tt:AddLine(T("Click once you have banished it."), 0.5, 1, 0.5)
    end
    return
  end
  if d.off then
    tt:AddLine(" ")
    tt:AddLine(T("You have it, but it is not part of this build."), 1, 0.6, 0.3, 1)
    return
  end
  if w then
    local _, lines = AB.WornStats(w, cls)
    tt:AddLine(" ")
    tt:AddLine(T("Now gives:"), 1, 0.82, 0)
    if table.getn(lines) == 0 then tt:AddLine(T("(reading its tooltip...)"), 0.5, 0.5, 0.5) end
    for i = 1, table.getn(lines) do tt:AddLine(lines[i], 0.12, 1, 0, 1) end
    if not row then tt:AddLine(T("You have it, but it is not part of this build."), 1, 0.6, 0.3, 1) end
  elseif row then
    tt:AddLine(" ")
    if row.owned then
      tt:AddLine(T("You have it at rank %d.", row.rank), 0.4, 1, 0.4)
    elseif row.blocked then
      tt:AddLine(T("Its slots are full with other pieces."), 0.7, 0.7, 0.7, 1)
    else
      tt:AddLine(T("Not taken yet."), 1, 0.4, 0.4)
    end
  end
  if row and (row.target > 0 or (row.target2 or 0) > 0) then
    if row.pick.t == "spell" then
      tt:AddLine(T("Target rank") .. ": " .. row.target, 0.8, 0.8, 0.8)
    else
      tt:AddLine(T("Target value") .. ": " .. AB.TargetText(row) .. (row.met and ("  |cff55ff55" .. T("reached") .. "|r") or ""), 0.8, 0.8, 0.8)
    end
  end
end

-- ---------------------------------------------------------------- building blocks
local function Panel(name)
  local p = CreateFrame("Frame", nil, f)
  p:SetWidth(WIDTH)
  W.Panel(p, 0.62, 0.2)
  p:SetBackdropColor(0, 0, 0, 0.62)
  if name then
    p.title = W.Text(p, "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 7, -5)
    p.title:SetText(name)
    p.count = W.Text(p, "GameFontDisableSmall", "RIGHT")
    p.count:SetPoint("TOPRIGHT", p, "TOPRIGHT", -7, -5)
    p.line = p:CreateTexture(nil, "ARTWORK")
    p.line:SetTexture(W.FLAT)
    p.line:SetVertexColor(1, 1, 1, 0.12)
    p.line:SetHeight(1)
    p.line:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -19)
    p.line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -19)
  end
  return p
end

local function Row(parent, nameWidth)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetTexture(W.FLAT)
  r.bg:SetAllPoints(r)
  W.Hover(r, 0.06)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetWidth(13)
  r.icon:SetHeight(13)
  r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.dot = r:CreateTexture(nil, "OVERLAY")
  r.dot:SetTexture(DOT)
  r.dot:SetWidth(7)
  r.dot:SetHeight(7)
  r.dot:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.dot:Hide()
  r.name = W.Text(r, "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.name:SetWidth(nameWidth)
  r.name:SetHeight(12)
  r.right = W.Text(r, "GameFontHighlightSmall", "RIGHT")
  r.right:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.right:SetWidth(WIDTH - nameWidth - 34)
  r.right:SetHeight(12)
  r.strike = r:CreateTexture(nil, "OVERLAY")
  r.strike:SetTexture(W.FLAT)
  r.strike:SetHeight(1)
  r.strike:Hide()
  W.Tip(r, RowTip)
  return r
end

local function Place(obj, parent, y, h)
  obj:ClearAllPoints()
  obj:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -y)
  obj:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -y)
  if h then obj:SetHeight(h) end
end

-- ---------------------------------------------------------------- the window
local function Create()
  f = CreateFrame("Frame", "ASBuilderTracker", UIParent)
  f:SetWidth(WIDTH)
  f:SetHeight(60)
  f:SetFrameStrata("MEDIUM")
  -- game 0.126.0+: stay visible over the level-up and jewelry cards
  if AZS_SetOnTopOfScreens then AZS_SetOnTopOfScreens(f, true) end
  f:SetMovable(true)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end

  -- a grip in the bottom-right corner: drag it to make the whole tracker bigger or smaller
  -- (the same size as /asb scale); the top-left corner stays where it is
  local grip = CreateFrame("Button", nil, f)
  grip:SetWidth(12)
  grip:SetHeight(12)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  for i = 1, 3 do
    for j = 1, i do
      local d = grip:CreateTexture(nil, "OVERLAY")
      d:SetTexture(W.FLAT)
      d:SetVertexColor(1, 1, 1, 0.45)
      d:SetWidth(2)
      d:SetHeight(2)
      d:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -(i - j) * 4, (j - 1) * 4)
    end
  end
  W.Hover(grip, 0.15)
  W.Tip(grip, function(self, tt)
    tt:SetText(T("Drag to resize"), 1, 0.82, 0)
    tt:AddLine(T("/asb reset: normal size and place"), 0.6, 0.6, 0.6, 1)
  end)
  local function StopSizing()
    if not grip:GetScript("OnUpdate") then return end
    grip:SetScript("OnUpdate", nil)
    ASBuilderDB.tracker.scale = f:GetScale()
    SavePoint()
  end
  grip:SetScript("OnMouseDown", function()
    -- the mouse-up can be lost (the grip moves away from the cursor): a second click ends it
    if grip:GetScript("OnUpdate") then StopSizing(); return end
    if ASBuilderDB.tracker.locked then return end
    local eff = f:GetEffectiveScale()
    grip.left, grip.top = f:GetLeft() * eff, f:GetTop() * eff
    grip:SetScript("OnUpdate", function()
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopSizing(); return end
      local ui = UIParent:GetEffectiveScale()
      local x = GetCursorPosition()
      local s = (x - grip.left) / (WIDTH * ui)
      if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
      f:SetScale(s)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", grip.left / (s * ui), grip.top / (s * ui))
    end)
  end)
  grip:SetScript("OnMouseUp", StopSizing)
  grip:SetScript("OnHide", StopSizing)

  -- BUILD panel: header, the next steps, the spells to banish
  local pb = Panel(nil)
  pb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.pBuild = pb

  local h = CreateFrame("Button", nil, pb)
  h:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1)
  h:SetPoint("TOPRIGHT", pb, "TOPRIGHT", -1, -1)
  h:SetHeight(20)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetTexture(W.FLAT)
  h.bg:SetAllPoints(h)
  h.bg:SetVertexColor(1, 1, 1, 0.06)
  W.Hover(h, 0.05)
  h.icon = h:CreateTexture(nil, "ARTWORK")
  h.icon:SetWidth(14)
  h.icon:SetHeight(14)
  h.icon:SetPoint("LEFT", h, "LEFT", 4, 0)
  h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  h.name = W.Text(h, "GameFontNormalSmall")
  h.name:SetPoint("LEFT", h.icon, "RIGHT", 5, 0)
  h.name:SetWidth(126)
  h.name:SetHeight(12)
  h.arrow = h:CreateTexture(nil, "ARTWORK")
  -- our own gold chevron: the game's chat arrow does not draw over the card screen
  h.arrow:SetTexture("Interface\\AddOns\\ASBuilder\\media\\chev.tga")
  h.arrow:SetWidth(14)
  h.arrow:SetHeight(14)
  h.arrow:SetPoint("LEFT", h.name, "RIGHT", 2, 0)
  h.prog = W.Text(h, "GameFontHighlightSmall", "RIGHT")
  h.prog:SetPoint("RIGHT", h, "RIGHT", -40, 0)
  h:RegisterForClicks("LeftButtonUp")
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function()
    if not ASBuilderDB.tracker.locked then f:StartMoving() end
  end)
  h:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    SavePoint()
    TR.dragged = GetTime()
  end)
  h:SetScript("OnClick", function()
    if TR.dragged and GetTime() - TR.dragged < 0.3 then return end
    TR.TogglePicker()
  end)
  W.Tip(h, function(self, tt)
    local b = AB.ActiveBuild(AB.CurrentClass())
    if b then
      tt:SetText(b.name, AB.ClassRGB(b.class))
      local v = TR.view and TR.view.variant
      if v then
        tt:AddLine(AB.N(v.name), 0.6, 0.8, 1)
        if v.notes and v.notes ~= "" then tt:AddLine(v.notes, 1, 0.82, 0, 1) end
      end
      tt:AddLine(" ")
    else
      tt:SetText("|cff7fd4ffAS|rBuilder")
    end
    tt:AddLine(T("Click: choose a build"), 0.7, 0.7, 0.7)
    if not ASBuilderDB.tracker.locked then tt:AddLine(T("Drag to move"), 0.5, 0.5, 0.5) end
  end)
  f.head = h

  local plan = W.IconButton(h, "Interface\\Icons\\INV_Misc_Book_11", 14)
  plan.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  plan:SetPoint("RIGHT", h, "RIGHT", -20, 0)
  plan:SetScript("OnClick", function()
    local b = AB.ActiveBuild(AB.CurrentClass())
    AB.OpenPlanner(b and b.id)
  end)
  W.Tip(plan, function(self, tt) tt:SetText(T("Open the planner")) end)

  local col = W.Button(h, "-", 14, 14)
  col:SetPoint("RIGHT", h, "RIGHT", -3, 0)
  col:SetScript("OnClick", function()
    ASBuilderDB.tracker.collapsed = not ASBuilderDB.tracker.collapsed
    TR.Refresh()
  end)
  W.Tip(col, function(self, tt) tt:SetText(T(ASBuilderDB.tracker.collapsed and "Expand" or "Collapse")) end)
  f.col = col

  -- the stage being followed; a click moves on to the next one by hand
  local st = CreateFrame("Button", nil, pb)
  st:SetHeight(16)
  st.bg = st:CreateTexture(nil, "BACKGROUND")
  st.bg:SetTexture(W.FLAT)
  st.bg:SetAllPoints(st)
  st.bg:SetVertexColor(0.3, 0.55, 1, 0.1)
  W.Hover(st, 0.06)
  st.label = W.Text(st, "GameFontDisableSmall")
  st.label:SetPoint("LEFT", st, "LEFT", 6, 0)
  st.label:SetWidth(46)
  st.text = W.Text(st, "GameFontHighlightSmall")
  st.text:SetPoint("LEFT", st, "LEFT", 54, 0)
  st.text:SetTextColor(0.6, 0.8, 1)
  st.count = W.Text(st, "GameFontDisableSmall", "RIGHT")
  st.count:SetPoint("RIGHT", st, "RIGHT", -6, 0)
  st:SetScript("OnClick", function()
    local b = AB.ActiveBuild(AB.CurrentClass())
    if b then AB.StepStage(b, AB.LiveState()); TR.Refresh() end
  end)
  W.Tip(st, function(self, tt)
    local v = TR.view and TR.view.variant
    tt:SetText(v and AB.N(v.name) or "", 0.6, 0.8, 1)
    if v and v.notes and v.notes ~= "" then tt:AddLine(v.notes, 1, 0.82, 0, 1) end
    tt:AddLine(" ")
    tt:AddLine(T("Moves on by itself when every pick of this stage reaches its target rank, and to the last stage when the run goes endless."), 0.7, 0.7, 0.7, 1)
    tt:AddLine(T("Click: next stage by hand (after the last one it follows the build again)."), 0.7, 0.7, 0.7, 1)
  end)
  f.stage = st

  local function NextLine()
    local n = CreateFrame("Button", nil, pb)
    n:SetHeight(20)
    n.bg = n:CreateTexture(nil, "BACKGROUND")
    n.bg:SetTexture(W.FLAT)
    n.bg:SetAllPoints(n)
    n.label = W.Text(n, "GameFontDisableSmall")
    n.label:SetPoint("LEFT", n, "LEFT", 6, 0)
    n.label:SetWidth(46)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetWidth(16)
    n.icon:SetHeight(16)
    n.icon:SetPoint("LEFT", n, "LEFT", 54, 0)
    n.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    n.text = W.Text(n, "GameFontNormalSmall")
    n.text:SetHeight(12)
    function n:SetIcon(icon)
      self.text:ClearAllPoints()
      if icon then
        self.icon:SetTexture(AB.Icon(icon))
        self.icon:Show()
        self.text:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
      else
        self.icon:Hide()
        self.text:SetPoint("LEFT", self, "LEFT", 54, 0)
      end
      self.text:SetPoint("RIGHT", self, "RIGHT", -4, 0)
    end
    n:SetIcon(nil)
    W.Tip(n, function(self, tt)
      if self.data then RowTip({ data = { row = self.data, pick = self.data.pick, worn = self.data.worn } }, tt) end
    end)
    return n
  end
  f.nextS = NextLine()
  f.nextJ = NextLine()
  -- the priority strips: icons in the build's order, no text
  f.prio = W.Text(pb, "GameFontNormalSmall", "CENTER")
  f.prio:SetWidth(WIDTH)
  f.prio:SetTextColor(1, 0.82, 0)
  f.prio:SetText(T("Priority"))
  f.stripS = {}


  -- SPELLS panel
  local ps = Panel(T("SPELLS"))
  f.pSpells = ps
  f.spellRows = {}
  for i = 1, SPELL_ROWS do
    local r = Row(ps, 136)
    r.icon:SetPoint("LEFT", r, "LEFT", 15, 0)
    -- a spell to banish: click it once you have banished it (the game does not tell addons)
    r:SetScript("OnClick", function()
      local d = this.data
      if not d or not d.ban then return end
      local k = d.pick.k
      ASBuilderDB.run.banished[k] = (not ASBuilderDB.run.banished[k]) or nil
      TR.Refresh()
    end)
    f.spellRows[i] = r
  end
  -- full slots: a line, then the build's spells that can no longer be taken
  f.missLine = ps:CreateTexture(nil, "ARTWORK")
  f.missLine:SetTexture(W.FLAT)
  f.missLine:SetVertexColor(1, 1, 1, 0.12)
  f.missLine:SetHeight(1)
  f.missLabel = W.Text(ps, "GameFontDisableSmall")

  -- JEWELRY panel
  local pj = Panel(T("JEWELRY"))
  f.pJewel = pj
  f.jewelRows = {}
  for i = 1, JEWEL_ROWS do
    local r = Row(pj, 126)
    r.icon:SetPoint("LEFT", r, "LEFT", 15, 0)
    f.jewelRows[i] = r
  end

  AB.ApplyTrackerLayout()
end

-- ---------------------------------------------------------------- filling the panels
local function SetNext(n, label, row, msg, lit)
  n.label:SetText(label)
  n.data = row
  if row then
    n:SetIcon(row.info and row.info.icon or "INV_Misc_QuestionMark")
    local name = row.info and AB.N(row.info.name) or row.pick.k
    if row.owned then
      local now
      if row.pick.t == "spell" then
        now = "R" .. row.rank
      else
        local tt = AB.TargetText(row)
        now = (row.value and AB.Num(row.value) or "?")
        if (row.target2 or 0) > 0 then now = now .. ", " .. (row.value2 and AB.Num(row.value2) or "?") end
        if tt ~= "" then now = now .. "/" .. tt end
      end
      n.text:SetText("|cffffd100" .. T("Upgrade %s", name) .. "|r |cff999999(" .. now .. ")|r")
    else
      n.text:SetText("|cff55ff55" .. T("Take %s", name) .. "|r")
    end
  else
    n:SetIcon(nil)
    n.text:SetText(msg or "")
  end
  if lit then n.bg:SetVertexColor(1, 0.75, 0.1, 0.22) else n.bg:SetVertexColor(1, 1, 1, 0.04) end
end

local function SpellStatus(row, inRun)
  local tgt = row.target or 0
  if not inRun then
    if tgt == 0 then return "|cff777777" .. T("max") .. "|r" end
    return "|cff777777R" .. tgt .. "|r"
  end
  if not row.owned then return "|cffff5555" .. T("missing") .. "|r" end
  if tgt == 0 then return "|cffffffffR" .. row.rank .. "|r" end
  if row.rank >= tgt then return "|cff55ff55R" .. row.rank .. "/" .. tgt .. "|r" end
  return "|cffffd100R" .. row.rank .. "/" .. tgt .. "|r"
end

local function RarityRGB(rarity)
  local c = rarity and AB.RARITY_COLOR[rarity]
  if c then return c[1], c[2], c[3] end
  return 1, 1, 1
end

-- One strip of icons left to right in the build's order, a ">" between them; hover for the
-- tooltip, a red cross over spells to banish, a gold edge on the next one to take, the ones
-- already at their target faded. Returns the height it takes (0 when empty).
local function StripCell(set, i)
  local c = CreateFrame("Button", nil, f.pBuild)
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetTexture(W.FLAT)
  c.bg:SetVertexColor(1, 0.82, 0, 0.9)
  c.bg:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
  c.bg:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetAllPoints(c)
  c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  c.cross = c:CreateTexture(nil, "OVERLAY")
  c.cross:SetTexture("Interface\\AddOns\\ASBuilder\\media\\cross.tga")
  c.cross:SetAllPoints(c)
  c.arrow = W.Text(c, "GameFontNormalSmall", "CENTER")
  c.arrow:SetTextColor(1, 0.85, 0.3)
  c.arrow:SetText(">")
  W.Tip(c, function(self, tt) if self.data then RowTip(self, tt) end end)
  set[i] = c
  return c
end

local STRIP_GAP = 9
-- the icon size that fits n icons in the panel
local function StripSize(n)
  if n == 0 then return 22 end
  return math.max(math.min(22, math.floor((WIDTH - 14 - (n - 1) * STRIP_GAP) / n)), 12)
end

local function LayoutStrip(set, list, y, size)
  for i = 1, table.getn(set) do set[i]:Hide() end
  local n = math.min(table.getn(list), 14)
  if n == 0 then return 0 end
  local gap = STRIP_GAP
  local x0 = math.floor((WIDTH - (n * size + (n - 1) * gap)) / 2)
  for i = 1, n do
    local c, e = set[i] or StripCell(set, i), list[i]
    c:SetWidth(size)
    c:SetHeight(size)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f.pBuild, "TOPLEFT", x0 + (i - 1) * (size + gap), -(y + 1))
    c.icon:SetTexture(AB.Icon(e.info and e.info.icon))
    c.icon:SetAlpha(e.dim and 0.4 or 1)
    c.data = e.data
    if e.lit then c.bg:Show() else c.bg:Hide() end
    if e.ban then c.cross:Show() else c.cross:Hide() end
    c.arrow:ClearAllPoints()
    c.arrow:SetPoint("CENTER", c, "RIGHT", gap / 2, 0)
    if i < n then c.arrow:Show() else c.arrow:Hide() end
    c:Show()
  end
  return size + 4
end

-- BUILD panel. Returns its height.
local function FillBuild(b, ev, live, stage, pinned)
  local pb, h = f.pBuild, f.head
  f.stage:Hide()
  local cls = AB.CurrentClass()
  h.icon:SetTexture(AB.Icon(AB.CLASS_ICON[cls]))
  f.col:SetLabel(ASBuilderDB.tracker.collapsed and "+" or "-")
  f.nextJ:Hide()
  f.nextS:Show()
  f.prio:Hide()
  LayoutStrip(f.stripS, {}, 0)
  local y = 22

  if not b then
    local c = AB.ClassInfo(cls)
    local has = table.getn(AB.BuildsFor(cls)) > 0
    h.name:SetText(T("Select a build"))
    h.name:SetTextColor(1, 0.82, 0)
    h.prog:SetText("")
    Place(f.nextS, pb, y)
    if has then
      SetNext(f.nextS, "", nil, "|cff999999" .. T("Click the name above to choose one") .. "|r")
    else
      SetNext(f.nextS, "", nil, "|cff999999" .. T("No %s builds yet: make one in the planner", c and AB.N(c.name) or cls) .. "|r")
    end
    return y + 22
  end

  h.name:SetText(b.name)
  h.name:SetTextColor(AB.ClassRGB(b.class))
  if live.inRun and ev.total > 0 then
    h.prog:SetText(((ev.done == ev.total) and "|cff55ff55" or "|cffcccccc") .. ev.done .. "/" .. ev.total .. "|r")
  else
    h.prog:SetText("")
  end

  -- the stage line, when the build has more than one stage with picks
  local stages = 0
  for i = 1, table.getn(b.variants) do if table.getn(b.variants[i].picks) > 0 then stages = stages + 1 end end
  if stages > 1 then
    Place(f.stage, pb, y)
    f.stage.label:SetText(T("Stage:"))
    f.stage.text:SetText(AB.N(b.variants[stage].name) .. (pinned and ("  |cff888888(" .. T("by hand") .. ")|r") or ""))
    f.stage.count:SetText(stage .. "/" .. table.getn(b.variants))
    f.stage:Show()
    y = y + 17
  end

  -- the priority strips: spells, then jewelry, in the planner's order; the spells to banish
  -- come last, after the build's own
  local spells = {}
  for i = 1, table.getn(ev.rows) do
    local r = ev.rows[i]
    if r.pick.t == "spell" and not r.extra and not r.pick.alt then
      table.insert(spells, { info = r.info, data = { row = r, pick = r.pick }, dim = live.inRun and not r.owned })
    end
  end
  local banished = ASBuilderDB.run.banished or {}
  for i = 1, table.getn(ev.bans) do
    local d = ev.bans[i]
    table.insert(spells, { info = d.info, ban = true, data = { pick = d.pick, ban = true, banished = banished[d.pick.k] } })
  end
  if table.getn(spells) == 0 then
    -- nothing to line up: the build has no spells
    if ev.total == 0 then
      Place(f.nextS, pb, y)
      SetNext(f.nextS, "", nil, "|cff999999" .. T("Empty build") .. "|r")
      return y + 22
    end
    f.nextS:Hide()
    return y + 2
  end
  f.nextS:Hide()
  f.prio:ClearAllPoints()
  f.prio:SetPoint("TOP", pb, "TOP", 0, -(y + 3))
  f.prio:Show()
  y = y + 17
  y = y + LayoutStrip(f.stripS, spells, y, StripSize(math.min(table.getn(spells), 14)))
  return y + 2
end

-- SPELLS panel. The build's spells come faded with no mark until you take them; taken, they
-- show in full with a green dot. A spell you took that the build does not want has a violet
-- dot. Spells to banish: faded with no mark until you have the spell, then a red dot and
-- BANISH; struck through once marked banished. When every spell slot is full, the build's
-- spells still missing drop below a line: they can no longer be taken. Header: slots used.
-- Returns its height, or nil when it has nothing to show.
local GREEN, VIOLET, RED = { 0.3, 1, 0.3 }, { 0.72, 0.4, 1 }, { 1, 0.25, 0.25 }

local function Dot(r, c)
  if not c then r.dot:Hide() return end
  r.dot:SetVertexColor(c[1], c[2], c[3])
  r.dot:Show()
end

-- spell slots used: every spell of the class you know
local function SpellsUsed(cls, live)
  local used = 0
  local c = AB.ClassInfo(cls)
  if c and live.inRun then
    for j = 1, table.getn(c.spells) do if live.spells[c.spells[j].key] then used = used + 1 end end
  end
  return used
end

local function FillSpells(b, ev, live)
  local ps = f.pSpells
  for i = 1, SPELL_ROWS do f.spellRows[i]:Hide() end
  f.missLine:Hide()
  f.missLabel:Hide()
  local cls = AB.CurrentClass()
  local top, below = {}, {}
  local used = SpellsUsed(cls, live)
  local full = live.inRun and used >= (AB.MAX.spell or 6)
  for i = 1, table.getn(ev.rows) do
    local row = ev.rows[i]
    if row.pick.t == "spell" then
      local e = { kind = "build", row = row, pick = row.pick, info = row.info }
      if full and not row.owned then table.insert(below, e) else table.insert(top, e) end
    end
  end
  for i = 1, table.getn(ev.off) do
    local o = ev.off[i]
    table.insert(top, { kind = "off", pick = o.pick, rank = o.rank, info = AB.Info(cls, o.pick), icon = o.icon })
  end
  local banished = ASBuilderDB.run.banished or {}
  for i = 1, table.getn(ev.bans) do
    local d = ev.bans[i]
    table.insert(top, { kind = "ban", pick = d.pick, info = d.info, rank = d.known, banished = banished[d.pick.k] })
  end
  if table.getn(top) + table.getn(below) == 0 then return nil end
  ps.count:SetText(live.inRun and (used .. "/" .. (AB.MAX.spell or 6)) or "")

  local y, n = 22, 0
  local function Show(e)
    n = n + 1
    local r = f.spellRows[n]
    if not r then return end
    Place(r, ps, y)
    y = y + ROW_H
    r.icon:SetTexture(AB.Icon((e.info and e.info.icon) or e.icon))
    r.name:SetText(e.info and AB.N(e.info.name) or e.pick.k)
    r.strike:Hide()
    r.bg:SetVertexColor(1, 1, 1, 0)
    r:SetAlpha(1)
    r.icon:SetVertexColor(1, 1, 1)
    r.name:SetTextColor(1, 1, 1)
    if e.kind == "build" then
      local row = e.row
      r.data = { row = row, pick = row.pick }
      if live.inRun and row.owned then
        Dot(r, GREEN)
      else
        -- not taken (or out of a run): faded, no mark
        Dot(r, nil)
        r.icon:SetVertexColor(0.45, 0.45, 0.45)
        r.name:SetTextColor(0.5, 0.5, 0.5)
      end
      r.right:SetText(SpellStatus(row, live.inRun))
      if row == ev.nextSpell then r.bg:SetVertexColor(1, 0.82, 0, 0.1) end
    elseif e.kind == "off" then
      r.data = { pick = e.pick, off = true }
      Dot(r, VIOLET)
      r.right:SetText("|cffffffffR" .. (e.rank or "?") .. "|r")
    else
      r.data = { pick = e.pick, ban = true, banished = e.banished }
      if e.banished then
        Dot(r, RED)
        r:SetAlpha(0.4)
        r.name:SetTextColor(0.6, 0.6, 0.6)
        r.right:SetText("|cff888888" .. T("banished") .. "|r")
        r.strike:SetVertexColor(0.9, 0.9, 0.9, 0.9)
        r.strike:ClearAllPoints()
        r.strike:SetPoint("LEFT", r.icon, "LEFT", -1, 0)
        r.strike:SetWidth(math.min(r.name:GetStringWidth() or 0, 136) + 20)
        r.strike:Show()
      elseif live.inRun and e.rank then
        -- you have the spell: banish its card when it comes up
        Dot(r, RED)
        r.name:SetTextColor(1, 0.45, 0.45)
        r.right:SetText("|cffff3333" .. T("BANISH") .. "|r")
      else
        -- not taken yet: faded with no mark, like the build's other spells
        Dot(r, nil)
        r.icon:SetVertexColor(0.45, 0.45, 0.45)
        r.name:SetTextColor(0.5, 0.5, 0.5)
        r.right:SetText("|cffff5555" .. T(live.inRun and "missing" or "banish") .. "|r")
      end
    end
    r:Show()
  end
  for i = 1, table.getn(top) do Show(top[i]) end
  if table.getn(below) > 0 then
    y = y + 3
    f.missLine:ClearAllPoints()
    f.missLine:SetPoint("TOPLEFT", ps, "TOPLEFT", 6, -y)
    f.missLine:SetPoint("TOPRIGHT", ps, "TOPRIGHT", -6, -y)
    f.missLine:Show()
    y = y + 3
    f.missLabel:ClearAllPoints()
    f.missLabel:SetPoint("TOPLEFT", ps, "TOPLEFT", 7, -y)
    f.missLabel:SetText(T("Missing (slots full):"))
    f.missLabel:Show()
    y = y + 13
    for i = 1, table.getn(below) do Show(below[i]) end
  end
  return y + 4
end

-- JEWELRY panel: worn pieces (the build's first, by slot) with what they give, then the
-- build's pieces still missing. With both rings and both trinkets worn, only the amulet's
-- missing pieces stay. Returns its height, or nil when it has nothing to show.
local GROUP_ORDER = { "ring", "trinket", "amulet" }
local function FillJewelry(b, ev, live)
  local pj = f.pJewel
  for i = 1, JEWEL_ROWS do f.jewelRows[i]:Hide() end
  local cls = AB.CurrentClass()
  local items = {}
  local wc = {}
  for w = 1, table.getn(live.worn or {}) do
    local g = live.worn[w].group
    wc[g] = (wc[g] or 0) + 1
  end
  local othersFull = live.inRun and (wc.ring or 0) >= AB.SLOT_CAP.ring and (wc.trinket or 0) >= AB.SLOT_CAP.trinket
  for g = 1, table.getn(GROUP_ORDER) do
    local group = GROUP_ORDER[g]
    for i = 1, table.getn(ev.rows) do
      local r = ev.rows[i]
      if AB.GROUP[r.pick.t] == group and r.worn then table.insert(items, { row = r, pick = r.pick, worn = r.worn }) end
    end
    for i = 1, table.getn(ev.wornOff or {}) do
      local w = ev.wornOff[i]
      if w.group == group then table.insert(items, { worn = w, pick = AB.WornAsPick(cls, w) }) end
    end
    for i = 1, table.getn(ev.rows) do
      local r = ev.rows[i]
      if AB.GROUP[r.pick.t] == group and not r.worn and not r.hide and not (othersFull and group ~= "amulet") then table.insert(items, { row = r, pick = r.pick }) end
    end
  end
  if table.getn(items) == 0 then return nil end

  local worn = live.worn and table.getn(live.worn) or 0
  pj.count:SetText(live.inRun and (worn .. "/5 " .. T("slots")) or "")
  local y = 22
  for i = 1, JEWEL_ROWS do
    local r, d = f.jewelRows[i], items[i]
    if d then
      Place(r, pj, y)
      y = y + ROW_H
      r.data = d
      local info = d.pick and AB.Info(cls, d.pick)
      local name = (info and AB.N(info.name)) or (d.worn and d.worn.name) or "?"
      if d.worn then
        -- worn: name in its rarity, rank, and what it gives right now
        r.icon:SetTexture(info and AB.Icon(info.icon) or d.worn.tex or AB.Icon(nil))
        r.icon:SetVertexColor(1, 1, 1)
        r.name:SetText(name)
        local cr, cg, cb = RarityRGB(d.worn.rarity)
        if d.pick and d.pick.t == "legend" then cr, cg, cb = 1, 0.5, 0 end
        if d.row then
          r.name:SetTextColor(cr, cg, cb)
          Dot(r, GREEN)
        else
          -- not in the build: dimmed, violet dot
          r.name:SetTextColor(cr * 0.7, cg * 0.7, cb * 0.7)
          Dot(r, VIOLET)
        end
        local short = AB.WornStats(d.worn, cls)
        if short == "" then short = "..." end
        local tgt = d.row and AB.TargetText(d.row) or ""
        if tgt ~= "" then
          local col = d.row.met and "|cff33ff33" or "|cffffd100"
          r.right:SetText(col .. short .. "|r |cff888888/" .. tgt .. "|r")
        else
          r.right:SetText("|cff33ff33" .. short .. "|r")
        end
      else
        -- a build piece not worn yet
        r.icon:SetTexture(AB.Icon(info and info.icon))
        r.icon:SetVertexColor(0.5, 0.5, 0.5)
        r.name:SetText(name)
        r.name:SetTextColor(0.55, 0.55, 0.55)
        Dot(r, nil)
        if d.row.extra then
          r.right:SetText("|cff88bbff" .. T("alt") .. "|r")
        elseif not live.inRun then
          local tgt = AB.TargetText(d.row)
          r.right:SetText("|cff777777" .. ((tgt ~= "") and ("/" .. tgt) or T("max")) .. "|r")
        elseif d.row.blocked then
          r.right:SetText("")
        else
          r.right:SetText("|cffff5555" .. T("missing") .. "|r")
        end
      end
      if d.row and d.row == ev.nextJewel then r.bg:SetVertexColor(1, 0.82, 0, 0.1) else r.bg:SetVertexColor(1, 1, 1, 0) end
      r:Show()
    end
  end
  return y + 4
end

-- ---------------------------------------------------------------- the build menu
-- Opens under the tracker's header: the saved builds of the hero's class, "None" and the
-- planner. It closes on a pick, on a second click of the header, with Escape, or a moment
-- after the mouse leaves it.
local MENU_ROWS = 16
local menu

local function MenuRow(parent, i)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(18)
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", 3, -3 - (i - 1) * 18)
  r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3 - (i - 1) * 18)
  W.Hover(r, 0.12)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetWidth(14)
  r.icon:SetHeight(14)
  r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.text = W.Text(r, "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r, "LEFT", 23, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -20, 0)
  r.text:SetHeight(12)
  r.check = r:CreateTexture(nil, "OVERLAY")
  r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  r.check:SetWidth(16)
  r.check:SetHeight(16)
  r.check:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  r.check:SetVertexColor(0.35, 1, 0.35)
  r:SetScript("OnClick", function()
    local self = this
    local cls = AB.CurrentClass()
    menu:Hide()
    if self.action == "build" then
      local b = AB.GetBuild(self.buildId)
      if b then AB.SetActive(b); AB.Print(T("Following: %s", b.name)) end
    elseif self.action == "none" then
      AB.ClearActive(cls)
    elseif self.action == "planner" then
      local b = AB.ActiveBuild(cls)
      AB.OpenPlanner(b and b.id)
    end
    TR.Refresh()
    if AB.Planner and AB.Planner.Refresh then AB.Planner.Refresh() end
  end)
  return r
end

local function CreateMenu()
  menu = CreateFrame("Frame", "ASBuilderBuildMenu", UIParent)
  menu:SetWidth(WIDTH)
  menu:SetFrameStrata("DIALOG")
  if AZS_SetOnTopOfScreens then AZS_SetOnTopOfScreens(menu, true) end
  W.Panel(menu, 0.97, 0.35)
  menu:EnableMouse(true)
  menu:Hide()
  table.insert(UISpecialFrames, "ASBuilderBuildMenu")
  menu.rows = {}
  for i = 1, MENU_ROWS do menu.rows[i] = MenuRow(menu, i) end
  menu.idle = 0
  menu:SetScript("OnUpdate", function()
    local over = MouseIsOver and (MouseIsOver(menu) or MouseIsOver(f.head))
    if over or not MouseIsOver then menu.idle = 0; return end
    menu.idle = menu.idle + (arg1 or 0)
    if menu.idle > 1.5 then menu:Hide() end
  end)
end

function TR.TogglePicker()
  if not f then return end
  if not menu then CreateMenu() end
  if menu:IsVisible() then menu:Hide(); return end
  local cls = AB.CurrentClass()
  local list = AB.BuildsFor(cls)
  local cur = ASBuilderDB.active[cls]
  local items = {}
  for i = 1, table.getn(list) do
    local b = list[i]
    local stages = 0
    for vi = 1, table.getn(b.variants) do if table.getn(b.variants[vi].picks) > 0 then stages = stages + 1 end end
    table.insert(items, { action = "build", buildId = b.id, icon = AB.CLASS_ICON[cls], on = b.id == cur,
      text = b.name .. ((stages > 1) and ("  |cff888888" .. T("%d stages", stages) .. "|r") or ""), r = 1, g = 1, bl = 1 })
  end
  if table.getn(items) == 0 then
    local c = AB.ClassInfo(cls)
    table.insert(items, { action = "planner", icon = "INV_Misc_Book_11", text = T("No %s builds yet: open the planner", c and AB.N(c.name) or cls), r = 0.7, g = 0.7, bl = 0.7 })
  else
    if table.getn(items) > MENU_ROWS - 2 then
      for i = table.getn(items), MENU_ROWS - 1, -1 do table.remove(items, i) end
    end
    table.insert(items, { action = "none", text = T("None"), on = cur == nil, r = 0.7, g = 0.7, bl = 0.7 })
    table.insert(items, { action = "planner", icon = "INV_Misc_Book_11", text = T("Open the planner"), r = 0.6, g = 0.8, bl = 1 })
  end
  for i = 1, MENU_ROWS do
    local row, it = menu.rows[i], items[i]
    if it then
      row.action, row.buildId = it.action, it.buildId
      row.text:SetText(it.text)
      row.text:SetTextColor(it.r, it.g, it.bl)
      if it.icon then row.icon:SetTexture(AB.Icon(it.icon)); row.icon:Show() else row.icon:Hide() end
      if it.on then row.check:Show() else row.check:Hide() end
      row:Show()
    else
      row:Hide()
    end
  end
  menu:SetHeight(table.getn(items) * 18 + 6)
  menu:SetScale(f:GetScale() or 1)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", -1, -2)
  menu.idle = 0
  menu:Show()
end

-- ---------------------------------------------------------------- choice boxes
-- While the game offers cards (level-up, lair, cache) two big boxes show the build's spells
-- and jewelry above the screen's dark veil: the ones still to take glow, the rest are dimmed.
-- CHOICE_RADIUS: the corner radius, to match the game's cards (media\corner.tga is a 64px quarter circle)
local CHOICE_ICON, CHOICE_GAP, CHOICE_N, CHOICE_RADIUS = 76, 8, 9, 16
-- the space between a box's border and its content, the same on all four sides
local CHOICE_PAD = 10
-- the width of six icons: more icons than that get smaller instead of making the box wider
local CHOICE_W = 6 * (CHOICE_ICON + CHOICE_GAP) - CHOICE_GAP
local choice

-- Where a box sits: the place and size the player gave it (drag it, or its bottom-right grip),
-- else its first corner. Saved as screen pixels of the top-left corner plus the scale.
-- every box keeps its own scale
local function ChoiceScale(p)
  local own = ASBuilderDB.choicePos and ASBuilderDB.choicePos[p.key]
  return own and own[3] or 1
end

local function ChoicePlace(p)
  local pos = ASBuilderDB.choicePos and ASBuilderDB.choicePos[p.key]
  p:ClearAllPoints()
  if pos then
    local s, ui = ChoiceScale(p), UIParent:GetEffectiveScale()
    p:SetScale(s)
    p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] / (s * ui), pos[2] / (s * ui))
  else
    p:SetScale(ChoiceScale(p))
    p:SetPoint(p.dpoint, UIParent, p.dpoint, p.dx, p.dy)
  end
end

local function ChoiceSave(p)
  if not p:GetLeft() then return end
  local eff = p:GetEffectiveScale()
  if type(ASBuilderDB.choicePos) ~= "table" then ASBuilderDB.choicePos = {} end
  ASBuilderDB.choicePos[p.key] = { p:GetLeft() * eff, p:GetTop() * eff, p:GetScale() }
end

-- The first place of each box: spells top left, jewelry top right, the order bar in the middle,
-- all hung from the same line at the top. Each is anchored to the screen alone, so resizing or
-- moving one never moves another.
local CHOICE_MARGIN, CHOICE_TOPM = 20, 36

function AB.ApplyChoiceLayout()
  if choice then
    ChoicePlace(choice.spells); ChoicePlace(choice.jewel); ChoicePlace(choice.bar)
  end
end

local function ChoiceBox(key, point, x, y)
  local p = CreateFrame("Frame", nil, choice)
  p.key, p.dpoint, p.dx, p.dy = key, point, x, y
  p:SetFrameStrata("TOOLTIP")
  -- above other TOOLTIP frames too (the damage meter's minimap button sits there); set before
  -- the cells are made, so they start above it
  p:SetFrameLevel(100)
  -- rounded like the game's cards: four corner pieces (media\corner.tga, a quarter circle with a gold
  -- rim and the dark fill) and plain gold lines and fill in between
  local R, B = CHOICE_RADIUS, 2
  local function Tex(layer, r, g, b, a)
    local t = p:CreateTexture(nil, layer)
    t:SetTexture(W.FLAT)
    t:SetVertexColor(r, g, b, a)
    return t
  end
  local function Corner(pt, l, r, t, bm)
    local c = p:CreateTexture(nil, "BACKGROUND")
    c:SetTexture("Interface\\AddOns\\ASBuilder\\media\\corner.tga")
    c:SetTexCoord(l, r, t, bm)
    c:SetWidth(R)
    c:SetHeight(R)
    c:SetPoint(pt, p, pt, 0, 0)
  end
  Corner("TOPLEFT", 0, 1, 0, 1)
  Corner("TOPRIGHT", 1, 0, 0, 1)
  Corner("BOTTOMLEFT", 0, 1, 1, 0)
  Corner("BOTTOMRIGHT", 1, 0, 1, 0)
  local mid = Tex("BACKGROUND", 0.06, 0.06, 0.08, 0.88)
  mid:SetPoint("TOPLEFT", p, "TOPLEFT", R, 0)
  mid:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -R, 0)
  local lf = Tex("BACKGROUND", 0.06, 0.06, 0.08, 0.88)
  lf:SetPoint("TOPLEFT", p, "TOPLEFT", B, -R)
  lf:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", R, R)
  local rt = Tex("BACKGROUND", 0.06, 0.06, 0.08, 0.88)
  rt:SetPoint("TOPLEFT", p, "TOPRIGHT", -R, -R)
  rt:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -B, R)
  local top = Tex("ARTWORK", 1, 0.85, 0.3, 1)
  top:SetPoint("TOPLEFT", p, "TOPLEFT", R, 0)
  top:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", -R, -B)
  local bot = Tex("ARTWORK", 1, 0.85, 0.3, 1)
  bot:SetPoint("TOPLEFT", p, "BOTTOMLEFT", R, B)
  bot:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -R, 0)
  local left = Tex("ARTWORK", 1, 0.85, 0.3, 1)
  left:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -R)
  left:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", B, R)
  local right = Tex("ARTWORK", 1, 0.85, 0.3, 1)
  right:SetPoint("TOPLEFT", p, "TOPRIGHT", -B, -R)
  right:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, R)
  ChoicePlace(p)
  -- drag the box anywhere, resize it from the bottom-right grip (same as the tracker)
  p:SetMovable(true)
  p:EnableMouse(true)
  p:RegisterForDrag("LeftButton")
  p:SetClampedToScreen(true)
  p:SetScript("OnDragStart", function()
    if not ASBuilderDB.tracker.locked then p.busy = true; p:StartMoving() end
  end)
  p:SetScript("OnDragStop", function() p.busy = nil; p:StopMovingOrSizing(); ChoiceSave(p) end)
  local grip = CreateFrame("Button", nil, p)
  grip:SetWidth(14)
  grip:SetHeight(14)
  grip:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -6, 6)
  grip:SetFrameLevel(p:GetFrameLevel() + 10)
  -- a small yellow arrow pointing out of the corner
  local arrow = grip:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\AddOns\\ASBuilder\\media\\grip.tga")
  arrow:SetAllPoints(grip)
  W.Hover(grip, 0.15)
  W.Tip(grip, function(self, tt)
    tt:SetText(T("Drag to resize"), 1, 0.82, 0)
    tt:AddLine(T("/asb reset: normal size and place"), 0.6, 0.6, 0.6, 1)
  end)
  local function StopSizing()
    if not grip:GetScript("OnUpdate") then return end
    grip:SetScript("OnUpdate", nil)
    p.busy = nil
    ChoiceSave(p)
  end
  grip:SetScript("OnMouseDown", function()
    if grip:GetScript("OnUpdate") then StopSizing(); return end
    if ASBuilderDB.tracker.locked then return end
    p.busy = true
    local eff = p:GetEffectiveScale()
    grip.left, grip.top = p:GetLeft() * eff, p:GetTop() * eff
    grip:SetScript("OnUpdate", function()
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopSizing(); return end
      local ui = UIParent:GetEffectiveScale()
      local cx = GetCursorPosition()
      local s = (cx - grip.left) / (p:GetWidth() * ui)
      if s < 0.4 then s = 0.4 elseif s > 2.5 then s = 2.5 end
      p:SetScale(s)
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", grip.left / (s * ui), grip.top / (s * ui))
    end)
  end)
  grip:SetScript("OnMouseUp", StopSizing)
  grip:SetScript("OnHide", StopSizing)
  if key == "bar" then return p end   -- the order bar fills its own cells (FillBar)
  p.cells = {}
  for i = 1, CHOICE_N do
    local c = CreateFrame("Frame", nil, p)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints(c)
    c.glow = c:CreateTexture(nil, "OVERLAY")
    c.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    c.glow:SetBlendMode("ADD")
    c.glow:SetPoint("CENTER", c, "CENTER", 0, 0)
    -- the name under the icon: a plain face with a dark outline reads best on the dimmed screen
    c.name = c:CreateFontString(nil, "OVERLAY")
    c.name:SetFont(W.FaceInfo("noto").file, 11, "THICKOUTLINE")
    if not c.name:GetFont() then c.name:SetFont(GameFontNormal:GetFont(), 11, "THICKOUTLINE") end
    c.name:SetPoint("TOP", c, "BOTTOM", 0, -6)
    -- tall enough for three lines so a long name wraps instead of ending in "..."
    c.name:SetHeight(48)
    c.name:SetJustifyV("TOP")
    p.cells[i] = c
  end
  -- jewelry box: a title over each group (rings, trinkets, amulets) and a plain line between them
  p.gt, p.dv = {}, {}
  for i = 1, 3 do
    local t = W.Text(p, "GameFontNormal")
    t:SetTextColor(1, 1, 0.6)
    p.gt[i] = t
    local d = p:CreateTexture(nil, "OVERLAY")
    d:SetTexture(1, 0.85, 0.3, 0.7)
    d:SetWidth(2)
    p.dv[i] = d
  end
  return p
end

local SEP, GTOP = 20, 16
local GORDER = { "ring", "trinket", "amulet" }
local GNAME = { spell = "Spells", ring = "Rings", trinket = "Trinkets", amulet = "Amulets" }

-- What is still to take: spells and jewelry not taken yet; taken ones leave the box.
-- Alternatives stay out, except the amulet's, which get a turquoise frame.
local function Wanted(r, isSpell)
  if (r.pick.t == "spell") ~= isSpell or r.owned or r.blocked or r.hide then return false end
  local amuletAlt = r.pick.alt and AB.GROUP[r.pick.t] == "amulet"
  if (r.pick.alt or r.extra) and not amuletAlt then return false end
  return true, amuletAlt
end

-- glow colours: spell to take, spell to banish, jewelry, amulet alternative
local GLOW = { spell = { 0.3, 1, 0.3 }, ban = { 1, 0.15, 0.15 }, jewel = { 1, 0.85, 0.2 }, alt = { 0.2, 1, 0.95 } }

local function FillChoice(p, ev, isSpell, slotsFull, force)
  local list = {}
  for i = 1, table.getn(ev.rows) do
    local ok, alt = Wanted(ev.rows[i], isSpell)
    if ok then
      table.insert(list, { info = ev.rows[i].info, pick = ev.rows[i].pick, glow = alt and GLOW.alt or (isSpell and GLOW.spell or GLOW.jewel) })
    end
  end
  -- the spells to banish stay while a new spell can still be offered
  if isSpell and (table.getn(list) > 0 or not slotsFull) then
    local banished = ASBuilderDB.run.banished or {}
    for i = 1, table.getn(ev.bans) do
      local d = ev.bans[i]
      if not d.known and not banished[d.pick.k] then table.insert(list, { info = d.info, pick = d.pick, glow = GLOW.ban }) end
    end
  end
  while table.getn(list) > CHOICE_N do table.remove(list) end
  if not isSpell then
    local sorted = {}
    for _, g in ipairs(GORDER) do
      for i = 1, table.getn(list) do
        if AB.GROUP[list[i].pick.t] == g then list[i].g = g; table.insert(sorted, list[i]) end
      end
    end
    list = sorted
  end
  local n = table.getn(list)
  local groups = 0
  for i = 1, n do
    if not isSpell and (i == 1 or list[i].g ~= list[i - 1].g) then groups = groups + 1 end
  end
  local sepW = math.max(groups - 1, 0) * SEP
  local size = math.min(CHOICE_ICON, math.floor((CHOICE_W + CHOICE_GAP - sepW) / math.max(n, 1)) - CHOICE_GAP)
  p.natural = size
  if force then size = force end   -- both boxes use the smaller of their two sizes
  local top = -CHOICE_PAD - GTOP   -- both boxes: a title row, then the icons, so they are as tall as each other
  for i = 1, 3 do
    p.gt[i]:Hide()
    p.dv[i]:Hide()
  end
  local x, gi, gstart = CHOICE_PAD, 0, CHOICE_PAD
  local maxh = 14   -- tallest name, so the box ends right under the names
  local function Title(g, from, to)
    gi = gi + 1
    p.gt[gi]:ClearAllPoints()
    p.gt[gi]:SetPoint("TOP", p, "TOPLEFT", (from + to) / 2, -CHOICE_PAD)
    p.gt[gi]:SetText(T(GNAME[g]))
    p.gt[gi]:Show()
  end
  for i = 1, n do
    local c, e = p.cells[i], list[i]
    if not isSpell and i > 1 and e.g ~= list[i - 1].g then
      local right = x - CHOICE_GAP
      Title(list[i - 1].g, gstart, right)
      x = right + SEP
      gstart = x
      -- from the top border to the bottom one, no gap
      local d = p.dv[gi]
      d:ClearAllPoints()
      d:SetPoint("TOP", p, "TOPLEFT", right + SEP / 2, -5)
      d:SetPoint("BOTTOM", p, "BOTTOMLEFT", right + SEP / 2, 5)
      d:Show()
    end
    c:SetWidth(size)
    c:SetHeight(size)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", p, "TOPLEFT", x, top)
    x = x + size + CHOICE_GAP
    local tex = AB.Icon(e.info and e.info.icon)
    c.icon:SetTexture(tex)
    c.glow:SetWidth(size * 1.9)
    c.glow:SetHeight(size * 1.9)
    c.glow:SetVertexColor(e.glow[1], e.glow[2], e.glow[3])
    c.name:SetWidth(size + CHOICE_GAP)
    c.name:SetText(e.info and AB.N(e.info.name) or e.pick.k)
    -- no GetStringHeight in this client: with no fixed height the text reports its own
    c.name:SetHeight(0)
    local nh = c.name:GetHeight() or 0
    c.name:SetHeight(48)
    if nh <= 0 then nh = 48 end
    if nh > maxh then maxh = nh end
    -- only amulets have a fixed rarity; spells, rings and trinkets get theirs on the card
    local rarity = e.pick.t == "legend" and "Legendary" or (e.info and e.info.rarity)
    c.name:SetTextColor(RarityRGB(rarity))
    c:Show()
  end
  for i = n + 1, CHOICE_N do p.cells[i]:Hide() end
  if n > 0 then Title(isSpell and "spell" or list[n].g, gstart, x - CHOICE_GAP) end
  p:SetWidth(math.max(x - CHOICE_GAP + CHOICE_PAD, 120))
  p:SetHeight(-top + size + 6 + math.min(maxh, 48) + CHOICE_PAD)
  if n > 0 then p:Show() else p:Hide() end
end

-- ORDER BAR: the build's spells in the planner's order (1 = top of its spell list), with the
-- spells to banish last and a red cross over them; a BANISH label sits above their numbers.
local BAR_N, BAR_ICON, BAR_GAP = 14, 40, 18

local function BarCell(p, i)
  local c = CreateFrame("Frame", nil, p)
  c:SetWidth(BAR_ICON)
  c:SetHeight(BAR_ICON)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetAllPoints(c)
  c.cross = c:CreateTexture(nil, "OVERLAY")
  c.cross:SetTexture("Interface\\AddOns\\ASBuilder\\media\\cross.tga")
  c.cross:SetAllPoints(c)
  c.num = W.Text(c, "GameFontNormalLarge", "CENTER")
  c.num:SetPoint("BOTTOM", c, "TOP", 0, 3)
  c.ban = W.Text(c, "GameFontNormalSmall", "CENTER")
  c.ban:SetPoint("BOTTOM", c.num, "TOP", 0, 1)
  c.ban:SetTextColor(1, 0.25, 0.25)
  c.name = c:CreateFontString(nil, "OVERLAY")
  c.name:SetFont(W.FaceInfo("noto").file, 11, "THICKOUTLINE")
  if not c.name:GetFont() then c.name:SetFont(GameFontNormal:GetFont(), 11, "THICKOUTLINE") end
  c.name:SetPoint("TOP", c, "BOTTOM", 0, -4)
  c.name:SetWidth(BAR_ICON + BAR_GAP - 4)
  c.name:SetHeight(30)
  c.name:SetJustifyV("TOP")
  c.arrow = W.Text(c, "GameFontNormalLarge", "CENTER")
  c.arrow:SetPoint("CENTER", c, "RIGHT", BAR_GAP / 2, 0)
  c.arrow:SetTextColor(1, 0.85, 0.3)
  c.arrow:SetText(">")
  p.cells[i] = c
  return c
end

local function FillBar(p, ev)
  p.cells = p.cells or {}
  local list = {}
  for i = 1, table.getn(ev.rows) do
    local r = ev.rows[i]
    if r.pick.t == "spell" and not r.extra and not r.pick.alt then
      table.insert(list, { info = r.info, pick = r.pick })
    end
  end
  local nban = table.getn(ev.bans)
  while table.getn(list) > BAR_N - nban do table.remove(list) end
  for i = 1, nban do table.insert(list, { info = ev.bans[i].info, pick = ev.bans[i].pick, ban = true }) end
  local n = table.getn(list)
  if n == 0 then p:Hide(); return end
  local top = -(CHOICE_PAD + 19 + (nban > 0 and 11 or 0))
  local maxh = 12
  for i = 1, n do
    local c, e = p.cells[i] or BarCell(p, i), list[i]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", p, "TOPLEFT", CHOICE_PAD + (i - 1) * (BAR_ICON + BAR_GAP), top)
    c.icon:SetTexture(AB.Icon(e.info and e.info.icon))
    c.name:SetText(e.info and AB.N(e.info.name) or e.pick.k)
    c.name:SetHeight(0)
    local nh = c.name:GetHeight() or 0
    c.name:SetHeight(30)
    if nh <= 0 then nh = 30 end
    if nh > maxh then maxh = nh end
    c.num:SetText(i)
    if e.ban then
      c.cross:Show()
      c.ban:SetText(T("BANISH"))
      c.num:SetTextColor(1, 0.35, 0.35)
      c.name:SetTextColor(1, 0.45, 0.45)
    else
      c.cross:Hide()
      c.ban:SetText("")
      c.num:SetTextColor(1, 1, 0.6)
      c.name:SetTextColor(1, 1, 1)
    end
    if i < n then c.arrow:Show() else c.arrow:Hide() end
    c:Show()
  end
  for i = n + 1, table.getn(p.cells) do p.cells[i]:Hide() end
  p:SetWidth(CHOICE_PAD + n * (BAR_ICON + BAR_GAP) - BAR_GAP + CHOICE_PAD)
  p:SetHeight(-top + BAR_ICON + 4 + math.min(maxh, 30) + CHOICE_PAD)
  p:Show()
end

local function ShowChoice(ev, slotsFull)
  if not choice then
    choice = CreateFrame("Frame", "ASBuilderChoice", UIParent)
    -- game 0.126.0+: keep the boxes over the cards (and clickable); older games just skip it
    if AZS_SetOnTopOfScreens then AZS_SetOnTopOfScreens(choice, true) end
    choice.spells = ChoiceBox("spells", "TOPLEFT", CHOICE_MARGIN, -CHOICE_TOPM)
    choice.jewel = ChoiceBox("jewel", "TOPRIGHT", -CHOICE_MARGIN, -CHOICE_TOPM)
    choice.bar = ChoiceBox("bar", "TOP", 0, -CHOICE_TOPM)
    -- the glow breathes so the eye finds it
    choice:SetScript("OnUpdate", function()
      local a = 0.6 + 0.25 * math.sin(GetTime() * 4)
      for _, p in ipairs({ choice.spells, choice.jewel }) do
        for i = 1, CHOICE_N do p.cells[i].glow:SetAlpha(a) end
      end
    end)
  end
  FillChoice(choice.spells, ev, true, slotsFull)
  FillChoice(choice.jewel, ev, false)
  -- the same icon size in both boxes: fill again at the smaller of the two
  local same = math.min(choice.spells.natural or CHOICE_ICON, choice.jewel.natural or CHOICE_ICON)
  FillChoice(choice.spells, ev, true, slotsFull, same)
  FillChoice(choice.jewel, ev, false, nil, same)
  FillBar(choice.bar, ev)
  -- each box has its own switch in the planner header
  for _, p in ipairs({ choice.spells, choice.jewel, choice.bar }) do
    if not ASBuilderDB.boxes[p.key] then p:Hide() end
  end
  -- the two boxes get the same frame height whatever their names need
  local hh = math.max(choice.spells:GetHeight(), choice.jewel:GetHeight())
  choice.spells:SetHeight(hh)
  choice.jewel:SetHeight(hh)
  choice:Show()
end

function TR.Refresh()
  if not AB.ready then return end
  -- the refresh hides the boxes and shows them again; hiding one that is being dragged or
  -- resized would drop it, so those stay
  if choice and not (choice.spells.busy or choice.jewel.busy or choice.bar.busy) then choice:Hide() end
  if not f then Create() end
  local db = ASBuilderDB.tracker
  if db.mode == "hidden" then f:Hide(); return end
  local live = AB.LiveState()
  if db.mode ~= "always" and not live.inRun then f:Hide(); return end
  local cls = AB.CurrentClass()
  local b = AB.ActiveBuild(cls)
  if not b and table.getn(AB.Builds()) == 0 and not live.inRun then f:Hide(); return end

  -- the stage to follow; with no build, the worn pieces are still read
  local stage, pinned = 1, false
  if b then
    stage, pinned = AB.StageOf(b, live)
    TR.view = AB.View(b, stage)
  else
    TR.view = nil
  end
  local ev = AB.Evaluate(TR.view or { class = cls, picks = {} }, live, b)
  local hb = FillBuild(b, ev, live, stage, pinned)
  f.pBuild:SetHeight(hb)
  local y = hb
  local panels = { { f.pSpells, FillSpells }, { f.pJewel, FillJewelry } }
  for i = 1, table.getn(panels) do
    local p, fill = panels[i][1], panels[i][2]
    local hp = nil
    if not db.collapsed then hp = fill(b, ev, live) end
    if hp then
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y + GAP))
      p:SetHeight(hp)
      p:Show()
      y = y + GAP + hp
    else
      p:Hide()
    end
  end
  f:SetHeight(y)
  f:Show()
  if b and live.phase == "choosing" then ShowChoice(ev, SpellsUsed(b.class, live) >= (AB.MAX.spell or 6)) end
end

AB.RefreshTracker = TR.Refresh
