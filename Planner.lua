-- ASBuilder planner: the window where builds are made. Left: your builds. Middle: the class
-- and every spell and piece of jewelry as icons; a click adds or removes one. Right: what
-- you picked, in priority order, with a target rank each, and your notes.

local AB = ASBuilder
local W = AB.W
local T = AB.T

local P = { selected = nil, offset = 0, variant = 1 }
AB.Planner = P

local FW, FH = 1040, 600
local VY = 32   -- the stage bar sits above the editor and the priority list
local LIST_ROWS = 18
local PRIO_ROWS = 9
local CELL, ICON, PER_ROW = 29, 26, 10
local MAX_TARGET = 30

local frame
local labels = {}

local function L(obj, key)
  table.insert(labels, { obj, key })
  if obj.SetLabel then obj:SetLabel(T(key)) else obj:SetText(T(key)) end
  return obj
end

local function Err(msg)
  UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.3, 1, 3)
end

-- The planner edits a draft: a copy of the selected build. Save writes it back; picking
-- another build throws unsaved changes away, so the build stays as it was last saved.
local function Saved()
  local b = AB.GetBuild(P.selected)
  if not b then
    b = AB.Builds()[1]
    P.selected = b and b.id or nil
  end
  return b
end

local function Draft()
  local s = Saved()
  if not s then P.draft = nil; return nil end
  if not P.draft or P.draft.id ~= s.id then P.draft = AB.CloneBuild(s) end
  return P.draft
end

-- the stage being edited, as a view (its picks are the draft's own list)
local function Selected()
  local d = Draft()
  if not d then return nil end
  if not d.variants[P.variant] then P.variant = 1 end
  return AB.View(d, P.variant)
end

function P.Select(id)
  if P.draft and P.draft.id ~= id and AB.IsDirty(P.draft) then
    local s = AB.GetBuild(P.draft.id)
    if s then AB.Print(T("Unsaved changes to \"%s\" were discarded.", s.name)) end
  end
  if not P.draft or P.draft.id ~= id then P.draft = nil; P.variant = 1 end
  P.selected = id
  if P.nameEdit then P.nameEdit:ClearFocus() end
end

local function Changed()
  P.Refresh()
  if AB.RefreshTracker then AB.RefreshTracker() end
end

-- ---------------------------------------------------------------- builds list (left)
local function BuildList(f)
  local head = W.Text(f, "GameFontNormal")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -44)
  L(head, "Builds")

  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -62)
  area:SetWidth(176)
  area:SetHeight(LIST_ROWS * 22)
  W.Panel(area, 0.6, 0.16)
  area:EnableMouseWheel(true)
  area:SetScript("OnMouseWheel", function()
    local n = table.getn(AB.Builds())
    P.offset = P.offset - (arg1 or 0)
    if P.offset > n - LIST_ROWS then P.offset = n - LIST_ROWS end
    if P.offset < 0 then P.offset = 0 end
    P.RefreshList()
  end)

  P.rows = {}
  for i = 1, LIST_ROWS do
    local r = CreateFrame("Button", nil, area)
    r:SetWidth(172)
    r:SetHeight(21)
    r:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -2 - (i - 1) * 22)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetTexture(W.FLAT)
    r.sel:SetAllPoints(r)
    r.sel:SetVertexColor(0.3, 0.55, 1, 0.22)
    W.Hover(r, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(15)
    r.icon:SetHeight(15)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = W.Text(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetWidth(122)
    r.name:SetHeight(12)
    r.active = r:CreateTexture(nil, "OVERLAY")
    r.active:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.active:SetWidth(16)
    r.active:SetHeight(16)
    r.active:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.active:SetVertexColor(0.35, 1, 0.35)
    r:SetScript("OnClick", function()
      if this.buildId then
        P.Select(this.buildId)
        P.Refresh()
      end
    end)
    W.Tip(r, function(self, tt)
      local b = AB.GetBuild(self.buildId)
      if not b then return end
      local c = AB.ClassInfo(b.class)
      tt:SetText(b.name, AB.ClassRGB(b.class))
      tt:AddLine(c and c.name or b.class, 0.7, 0.7, 0.7)
      if ASBuilderDB.active[b.class] == b.id then tt:AddLine(T("Active"), 0.35, 1, 0.35) end
      for vi = 1, table.getn(b.variants) do
        local v = b.variants[vi]
        local n = table.getn(v.picks)
        if n > 0 then tt:AddLine(v.name .. ": " .. n .. " " .. T("picks"), 0.8, 0.8, 0.8) end
      end
    end)
    P.rows[i] = r
  end

  P.empty = W.Text(area, "GameFontDisableSmall", "CENTER")
  P.empty:SetPoint("CENTER", area, "CENTER", 0, 0)
  P.empty:SetWidth(160)
  L(P.empty, "No builds yet. Press New.")

  local bNew = W.Button(f, "", 56, 22)
  bNew:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 40)
  L(bNew, "New")
  bNew:SetScript("OnClick", function()
    local b = AB.NewBuild(AB.CurrentClass())
    P.Select(b.id)
    local n = table.getn(AB.Builds())
    if n > LIST_ROWS then P.offset = n - LIST_ROWS end
    Changed()
    P.nameEdit:SetFocus()
    P.nameEdit:HighlightText()
  end)

  local bCopy = W.Button(f, "", 56, 22)
  bCopy:SetPoint("LEFT", bNew, "RIGHT", 4, 0)
  L(bCopy, "Copy")
  bCopy:SetScript("OnClick", function()
    local d = Draft()
    if not d then return end
    local nb = AB.CopyBuild(d)
    P.draft = nil
    P.Select(nb.id)
    Changed()
  end)
  P.bCopy = bCopy

  local bDel = W.Button(f, "", 56, 22)
  bDel:SetPoint("LEFT", bCopy, "RIGHT", 4, 0)
  L(bDel, "Delete")
  bDel:SetScript("OnClick", function()
    local b = Selected()
    if not b then return end
    P.pendingDelete = b.id
    StaticPopup_Show("ASBUILDER_DELETE", T("Delete build \"%s\"?", Saved().name))
  end)
  P.bDel = bDel

  local bImp = W.Button(f, "", 176, 22)
  bImp:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  L(bImp, "Import")
  bImp:SetScript("OnClick", function() P.ShowCode("import") end)

  P.always = W.Check(f, "", function(on)
    ASBuilderDB.tracker.mode = on and "always" or "run"
    if AB.RefreshTracker then AB.RefreshTracker() end
  end)
  P.always:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 72)
  L(P.always.text, "Show tracker outside runs")
end

function P.RefreshList()
  local list = AB.Builds()
  local n = table.getn(list)
  if P.offset > n - LIST_ROWS then P.offset = math.max(0, n - LIST_ROWS) end
  for i = 1, LIST_ROWS do
    local r = P.rows[i]
    local b = list[i + P.offset]
    if b then
      r.buildId = b.id
      r.icon:SetTexture(AB.Icon(AB.CLASS_ICON[b.class]))
      local shown = b
      if P.draft and P.draft.id == b.id then shown = P.draft end
      r.name:SetText(shown.name .. ((shown ~= b and AB.IsDirty(P.draft)) and " |cffff9933*|r" or ""))
      r.name:SetTextColor(AB.ClassRGB(shown.class))
      r.icon:SetTexture(AB.Icon(AB.CLASS_ICON[shown.class]))
      if b.id == P.selected then r.sel:Show() else r.sel:Hide() end
      if ASBuilderDB.active[b.class] == b.id then r.active:Show() else r.active:Hide() end
      r:Show()
    else
      r.buildId = nil
      r:Hide()
    end
  end
  if n == 0 then P.empty:Show() else P.empty:Hide() end
end

-- ---------------------------------------------------------------- editor (middle)
-- as many icons as the game data has (it comes from the game, so new pieces show up here)
local function MostSpells()
  local n = 0
  for i = 1, table.getn(ASBuilder_Data.classes) do
    n = math.max(n, table.getn(ASBuilder_Data.classes[i].spells))
  end
  return n
end
local SECTIONS = {
  { kind = "spell", label = "Spells", count = MostSpells() },
  { kind = "ring", label = "Rings", count = table.getn(ASBuilder_Data.rings) },
  { kind = "trinket", label = "Trinkets", count = table.getn(ASBuilder_Data.trinkets) },
  { kind = "amulet", label = "Amulet", count = table.getn(ASBuilder_Data.amulets) },
  { kind = "legend", label = "Legendary amulet", count = MostSpells() },
}

-- the picks a section offers for a class, as { t, k } in the data's order
local function Offers(kind, cls)
  local D, out = ASBuilder_Data, {}
  if kind == "spell" or kind == "legend" then
    local c = AB.ClassInfo(cls)
    if c then
      for i = 1, table.getn(c.spells) do
        if kind == "spell" or c.spells[i].amulet then table.insert(out, { t = kind, k = c.spells[i].key }) end
      end
    end
  elseif kind == "ring" then
    for i = 1, table.getn(D.rings) do table.insert(out, { t = "ring", k = D.rings[i].name }) end
  elseif kind == "trinket" then
    for i = 1, table.getn(D.trinkets) do table.insert(out, { t = "trinket", k = D.trinkets[i].name }) end
  elseif kind == "amulet" then
    for i = 1, table.getn(D.amulets) do table.insert(out, { t = "amulet", k = D.amulets[i].name }) end
  end
  return out
end

function P.PaletteTip(self, tt)
  local b = Selected()
  if not b or not self.pick then return end
  AB.FillTooltip(tt, b.class, self.pick)
  tt:AddLine(" ")
  local idx = AB.FindPick(b, self.pick.t, self.pick.k)
  local p = idx and b.picks[idx]
  if p and p.ban then
    tt:AddLine(T("Will be banished"), 1, 0.3, 0.3)
    tt:AddLine(T("Click: remove from the build"), 1, 0.5, 0.5)
    tt:AddLine(T("Right-click: take it instead"), 0.5, 1, 0.5)
  elseif p then
    if p.alt then tt:AddLine(T("Alternative"), 0.5, 0.75, 1) end
    tt:AddLine(T("Click: remove from the build"), 1, 0.5, 0.5)
    if p.t == "spell" then tt:AddLine(T("Right-click: banish this spell"), 1, 0.5, 0.5) end
  else
    tt:AddLine(T("Click: add to the build"), 0.5, 1, 0.5)
    if self.pick.t == "spell" then tt:AddLine(T("Right-click: banish this spell"), 1, 0.5, 0.5) end
  end
end

local function Editor(f)
  local ed = CreateFrame("Frame", nil, f)
  ed:SetAllPoints(f)
  P.ed = ed

  local nl = W.Text(ed, "GameFontNormalSmall")
  nl:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -44 - VY)
  L(nl, "Name")
  P.dirtyText = W.Text(ed, "GameFontHighlightSmall", "RIGHT")
  P.dirtyText:SetPoint("TOPRIGHT", f, "TOPLEFT", 500, -44 - VY)
  P.dirtyText:SetTextColor(1, 0.6, 0.2)
  local ne = W.Edit(ed, "ASBuilderNameEdit", 300, 22)
  ne:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -58 - VY)
  ne:SetScript("OnTextChanged", function()
    if P.filling then return end
    local d = Draft()
    if not d then return end
    local t = this:GetText() or ""
    if t == "" then return end
    d.name = t
    P.RefreshDirty()
    if AB.RefreshTracker then AB.RefreshTracker() end
  end)
  ne:SetScript("OnEditFocusLost", function()
    local d = Draft()
    if d and (this:GetText() or "") == "" then this:SetText(d.name) end
  end)
  P.nameEdit = ne

  -- the class row
  P.classBtns = {}
  local classes = ASBuilder_Data.classes
  for i = 1, table.getn(classes) do
    local c = classes[i]
    local cb = W.Slot(ed, 24)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 200 + (i - 1) * 27, -89 - VY)
    cb.icon:SetTexture(AB.Icon(AB.CLASS_ICON[c.key]))
    cb.classKey = c.key
    cb:SetScript("OnClick", function()
      local d = Draft()
      if not d or d.class == this.classKey then return end
      AB.SetClass(d, this.classKey)
      Changed()
    end)
    W.Tip(cb, function(self, tt)
      local ci = AB.ClassInfo(self.classKey)
      tt:SetText(ci.name, AB.ClassRGB(self.classKey))
    end)
    P.classBtns[i] = cb
  end
  P.className = W.Text(ed, "GameFontNormalSmall")
  P.className:SetPoint("LEFT", P.classBtns[table.getn(classes)], "RIGHT", 6, 0)

  -- the icon palette
  P.sections = {}
  for s = 1, table.getn(SECTIONS) do
    local sec = { def = SECTIONS[s], slots = {} }
    sec.label = W.Text(ed, "GameFontNormalSmall")
    for i = 1, sec.def.count do
      local sl = W.Slot(ed, ICON)
      sl.badge = sl:CreateTexture(nil, "OVERLAY")
      sl.badge:SetWidth(12)
      sl.badge:SetHeight(12)
      sl.badge:SetPoint("BOTTOMLEFT", sl, "BOTTOMLEFT", 1, 1)
      sl.badge:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      if sec.def.kind == "spell" then sl:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
      sl:SetScript("OnClick", function()
        local self, button = this, arg1
        local b = Selected()
        if not b or not self.pick then return end
        local ok, msg
        local idx = AB.FindPick(b, self.pick.t, self.pick.k)
        if button == "RightButton" then
          -- right-click a spell: mark it to banish (or back to take)
          if idx then ok, msg = AB.ToggleBan(b, idx) else ok, msg = AB.TogglePick(b, self.pick.t, self.pick.k, true) end
        else
          ok, msg = AB.TogglePick(b, self.pick.t, self.pick.k)
        end
        if not ok and msg then Err(msg) end
        -- show the tab of what was just changed
        P.tab = AB.GROUP[self.pick.t]
        Changed()
        if self:IsVisible() and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          P.PaletteTip(self, GameTooltip)
          GameTooltip:Show()
        end
      end)
      W.Tip(sl, function(self, tt) P.PaletteTip(self, tt) end)
      sec.slots[i] = sl
    end
    P.sections[s] = sec
  end
end

local function RefreshPalette(b)
  local y = -124 - VY
  for s = 1, table.getn(P.sections) do
    local sec = P.sections[s]
    local kind = sec.def.kind
    local group = AB.GROUP[kind]
    local offers = Offers(kind, b.class)
    local have, max = AB.CountGroup(b, group), AB.MAX[group]
    local full = have >= max
    local label = T(sec.def.label)
    if kind ~= "legend" then
      local col = full and "|cff55ff55" or "|cffaaaaaa"
      label = label .. "  " .. col .. have .. "/" .. max .. "|r"
      if AB.ALTS[group] then label = label .. "  |cff888888(" .. T("%d main + %d alternatives", AB.MAIN[group], AB.ALTS[group]) .. ")|r" end
    end
    if kind == "spell" and AB.CountBans(b) > 0 then
      label = label .. "   |cffff5555" .. T("Banish") .. " " .. AB.CountBans(b) .. "/" .. AB.MAX_BAN .. "|r"
    end
    -- each pick's place within its own tab
    local place = {}
    local tabIdx = AB.TabIndices(b, group)
    for t = 1, table.getn(tabIdx) do place[tabIdx[t]] = t end
    sec.label:SetText(label)
    sec.label:ClearAllPoints()
    sec.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 201, y)
    y = y - 14
    local n = table.getn(offers)
    for i = 1, sec.def.count do
      local sl = sec.slots[i]
      local p = offers[i]
      if p then
        local info = AB.Info(b.class, p)
        sl.pick = p
        sl.icon:SetTexture(AB.Icon(info and info.icon))
        local idx = AB.FindPick(b, p.t, p.k)
        if idx and b.picks[idx].ban then
          sl:SetPicked(false)
          sl:SetBanned()
        elseif idx and b.picks[idx].alt then
          sl:SetPicked(false)
          sl:SetAlt()
        else
          sl:SetPicked(idx ~= nil, idx and place[idx])
          -- a full group dims what cannot be added
          if not idx then sl:SetDim(full) end
        end
        if kind == "legend" then
          sl.badge:SetTexture(AB.Icon(info.spell.icon))
          sl.badge:Show()
        else
          sl.badge:Hide()
        end
        local row, col = math.floor((i - 1) / PER_ROW), math.mod(i - 1, PER_ROW)
        sl:ClearAllPoints()
        sl:SetPoint("TOPLEFT", frame, "TOPLEFT", 200 + col * CELL, y - row * CELL)
        sl:Show()
      else
        sl.pick = nil
        sl:Hide()
      end
    end
    y = y - math.ceil(n / PER_ROW) * CELL - 6
  end
end

-- ---------------------------------------------------------------- priority list (right)
-- One tab per slot group, each with its own priority order. Spells can be marked to banish.
local TABS = {
  { group = "spell", label = "Spells" },
  { group = "ring", label = "Rings" },
  { group = "trinket", label = "Trinkets" },
  { group = "amulet", label = "Amulet" },
}
P.tab = "spell"

-- a jewelry row's typed target: field "r" (its first stat) or "r2" (an amulet's second stat)
local function ValueBox(r, name, field)
  local e = W.Edit(r, name, 40, 18)
  e:SetMaxLetters(5)
  e:SetTextInsets(4, 4, 0, 0)
  if e.SetJustifyH then e:SetJustifyH("RIGHT") end
  e.hint = W.Text(e, "GameFontDisableSmall", "CENTER")
  e.hint:SetAllPoints(e)
  e.hint:SetText((field == "r2") and "-" or T("max"))
  e:SetScript("OnTextChanged", function()
    local t = this:GetText() or ""
    if t == "" then this.hint:Show() else this.hint:Hide() end
    if P.filling then return end
    local b = Selected()
    local p = b and r.pi and b.picks[r.pi]
    if not p then return end
    local n = tonumber((string.gsub(t, ",", ".")))
    p[field] = (n and n > 0) and n or 0
    P.RefreshDirty()
  end)
  e:SetScript("OnEditFocusGained", function() this.focus = true; this:HighlightText() end)
  e:SetScript("OnEditFocusLost", function() this.focus = false; P.Refresh() end)
  W.Tip(e, function(self, tt)
    local b = Selected()
    local p = b and r.pi and b.picks[r.pi]
    local info = p and AB.Info(b.class, p)
    local stat = info and p.t ~= "legend" and ((field == "r2") and AB.StatTemplate2(info) or AB.StatTemplate(info))
    tt:SetText(T("Target value"), 1, 0.82, 0)
    if stat then tt:AddLine((string.gsub(stat, "{v}", "x")), 0.5, 1, 0.5) end
    tt:AddLine(T("What this piece should give before the build moves on, read live from its tooltip: 30 for -30% cooldowns, 4.5 for +4.5 health per second."), 0.8, 0.8, 0.8, 1)
    if field == "r2" then
      tt:AddLine(T("Empty: no target for this stat."), 0.6, 0.6, 0.6, 1)
    else
      tt:AddLine(T("Empty: keep upgrading it whenever it is offered."), 0.6, 0.6, 0.6, 1)
    end
  end)
  return e
end

local function Priority(f)
  local ed = P.ed
  P.tabs = {}
  for i = 1, table.getn(TABS) do
    local tb = W.Button(ed, "", 72, 22)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 512 + (i - 1) * 74, -40 - VY)
    L(tb, TABS[i].label)
    tb.group = TABS[i].group
    tb:SetScript("OnClick", function()
      P.tab = this.group
      P.Refresh()
    end)
    W.Tip(tb, function(self, tt)
      tt:SetText(T(AB.GROUP_LABEL[self.group]), 1, 0.82, 0)
      tt:AddLine(T("Top = most important"), 0.8, 0.8, 0.8)
    end)
    P.tabs[i] = tb
  end

  P.tabCount = W.Text(ed, "GameFontHighlightSmall")
  P.tabCount:SetPoint("TOPLEFT", f, "TOPLEFT", 514, -70 - VY)
  -- empties the open tab, in the stage being edited
  P.clearBtn = W.Button(ed, "", 56, 18)
  P.clearBtn:SetPoint("TOPRIGHT", f, "TOPLEFT", 808, -66 - VY)
  L(P.clearBtn, "Clear")
  P.clearBtn:SetScript("OnClick", function()
    local b = Selected()
    if b and AB.ClearGroup(b, P.tab or "spell") > 0 then Changed() end
  end)
  W.Tip(P.clearBtn, function(self, tt)
    local b = Selected()
    local group = P.tab or "spell"
    tt:SetText(T("Clear"), 1, 0.82, 0)
    tt:AddLine(T("Removes every pick of the %s tab from %s.", T(AB.GROUP_LABEL[group]), b and b.variant.name or ""), 0.8, 0.8, 0.8, 1)
    if group == "spell" then tt:AddLine(T("Spells marked to banish go too."), 0.6, 0.6, 0.6, 1) end
    tt:AddLine(T("Not saved until you press Save."), 0.6, 0.6, 0.6, 1)
  end)

  P.prio = {}
  for i = 1, PRIO_ROWS do
    local r = CreateFrame("Frame", nil, ed)
    r:SetWidth(296)
    r:SetHeight(24)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 512, -86 - VY - (i - 1) * 26)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetTexture(W.FLAT)
    r.bg:SetAllPoints(r)

    r.num = W.Text(r, "GameFontDisableSmall", "RIGHT")
    r.num:SetWidth(18)
    r.num:SetPoint("LEFT", r, "LEFT", 0, 0)

    r.icon = W.Slot(r, 22)
    r.icon:SetPoint("LEFT", r, "LEFT", 22, 0)
    r.icon.row = r
    W.Tip(r.icon, function(self, tt)
      local b = Selected()
      local p = b and self.row.pi and b.picks[self.row.pi]
      if p then AB.FillTooltip(tt, b.class, p) end
    end)

    r.name = W.Text(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 49, 0)
    r.name:SetHeight(12)

    local function Target(delta)
      local b = Selected()
      local p = b and r.pi and b.picks[r.pi]
      if not p or p.ban then return end
      local v = (p.r or 0) + delta
      if v < 0 then v = 0 end
      if v > MAX_TARGET then v = MAX_TARGET end
      p.r = v
      Changed()
    end

    -- spells only: banish instead of take
    r.ban = W.Button(r, "", 38, 18)
    r.ban:SetPoint("LEFT", r, "LEFT", 138, 0)
    r.ban:SetScript("OnClick", function()
      local b = Selected()
      if not b or not r.pi then return end
      local p = b.picks[r.pi]
      local ok, msg
      if p and AB.ALTS[AB.GROUP[p.t]] then ok, msg = AB.ToggleAlt(b, r.pi) else ok, msg = AB.ToggleBan(b, r.pi) end
      if not ok and msg then Err(msg) end
      Changed()
    end)
    W.Tip(r.ban, function(self, tt)
      local b = Selected()
      local p = b and r.pi and b.picks[r.pi]
      if p and AB.ALTS[AB.GROUP[p.t]] then
        local word = ({ ring = "ring", trinket = "trinket" })[AB.GROUP[p.t]] or "amulet"
        tt:SetText(T("Alternative"), 0.5, 0.75, 1)
        if p.alt then
          tt:AddLine(T("An alternative: wearing it fills a %s slot just as well.", word), 0.8, 0.8, 0.8, 1)
          tt:AddLine(T("Click: make it a main %s", word), 0.5, 1, 0.5)
        else
          tt:AddLine(T("A main %s. Click to mark it as an alternative.", word), 0.8, 0.8, 0.8, 1)
        end
        return
      end
      tt:SetText(T("Banish"), 1, 0.4, 0.4)
      if p and p.ban then
        tt:AddLine(T("Will be banished"), 1, 0.3, 0.3)
        tt:AddLine(T("Click: take it instead"), 0.5, 1, 0.5)
      else
        tt:AddLine(T("Mark it to banish: when its card comes up, banish it instead of taking it."), 0.8, 0.8, 0.8, 1)
      end
    end)
    r.banText = W.Text(r, "GameFontHighlightSmall")
    r.banText:SetPoint("LEFT", r, "LEFT", 182, 0)
    r.banText:SetTextColor(1, 0.35, 0.35)

    r.minus = W.IconButton(r, "Interface\\Buttons\\UI-MinusButton-Up", 14)
    r.minus:SetPoint("LEFT", r, "LEFT", 180, 0)
    r.minus:SetScript("OnClick", function() Target(-1) end)
    r.rank = CreateFrame("Button", nil, r)
    r.rank:SetWidth(26)
    r.rank:SetHeight(18)
    r.rank:SetPoint("LEFT", r.minus, "RIGHT", 1, 0)
    r.rank.text = W.Text(r.rank, "GameFontHighlightSmall", "CENTER")
    r.rank.text:SetAllPoints(r.rank)
    r.rank:EnableMouseWheel(true)
    r.rank:SetScript("OnMouseWheel", function() Target(arg1 or 0) end)
    W.Tip(r.rank, function(self, tt)
      tt:SetText(T("Target rank"), 1, 0.82, 0)
      tt:AddLine(T("\"max\": keep upgrading it whenever it is offered."), 0.8, 0.8, 0.8, 1)
    end)
    r.plus = W.IconButton(r, "Interface\\Buttons\\UI-PlusButton-Up", 14)
    r.plus:SetPoint("LEFT", r.rank, "RIGHT", 1, 0)
    r.plus:SetScript("OnClick", function() Target(1) end)

    -- jewelry: the value the piece should give (typed), instead of a rank
    r.val = ValueBox(r, "ASBuilderTarget" .. i, "r")
    r.val:SetPoint("LEFT", r, "LEFT", 180, 0)
    r.unit = W.Text(r, "GameFontHighlightSmall")
    r.unit:SetPoint("LEFT", r.val, "RIGHT", 3, 0)
    -- an amulet with a second stat: a second box beside the first
    r.val2 = ValueBox(r, "ASBuilderTargetB" .. i, "r2")
    r.val2:SetPoint("LEFT", r, "LEFT", 210, 0)
    r.val2:SetWidth(28)

    r.up = W.IconButton(r, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", 18)
    r.up.tex:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    r.up:SetPoint("LEFT", r, "LEFT", 240, 0)
    r.up:SetScript("OnClick", function()
      local b = Selected()
      if b and r.pi then AB.MovePick(b, r.pi, -1); Changed() end
    end)
    W.Tip(r.up, function(self, tt) tt:SetText(T("Move up")) end)
    r.down = W.IconButton(r, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", 18)
    r.down.tex:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    r.down:SetPoint("LEFT", r.up, "RIGHT", 0, 0)
    r.down:SetScript("OnClick", function()
      local b = Selected()
      if b and r.pi then AB.MovePick(b, r.pi, 1); Changed() end
    end)
    W.Tip(r.down, function(self, tt) tt:SetText(T("Move down")) end)
    r.del = W.IconButton(r, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 18)
    r.del.tex:SetTexCoord(0.18, 0.82, 0.18, 0.82)
    r.del:SetPoint("LEFT", r.down, "RIGHT", 2, 0)
    r.del:SetScript("OnClick", function()
      local b = Selected()
      if b and r.pi and b.picks[r.pi] then table.remove(b.picks, r.pi); Changed() end
    end)
    W.Tip(r.del, function(self, tt) tt:SetText(T("Remove")) end)
    P.prio[i] = r
  end

  P.prioHint = W.Text(ed, "GameFontDisableSmall", "CENTER")
  P.prioHint:SetPoint("TOP", f, "TOPLEFT", 512 + 148, -170 - VY)
  P.prioHint:SetWidth(260)

  P.fill = W.Check(ed, "", function(on)
    local d = Draft()
    if d then d.fill = on; Changed() end
  end)
  P.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 514, -342 - VY)
  L(P.fill.text, "Fill empty slots before upgrading")

  local nl = W.Text(ed, "GameFontNormalSmall")
  nl:SetPoint("TOPLEFT", f, "TOPLEFT", 512, -364 - VY)
  P.notesLabel = nl
  P.notes = W.MultiEdit(ed, "ASBuilderNotes", 296, 110, 4000)
  P.notes:SetPoint("TOPLEFT", f, "TOPLEFT", 512, -378 - VY)
  P.notes.edit:SetScript("OnTextChanged", function()
    P.notes.scroll:UpdateScrollChildRect()
    if P.filling then return end
    local b = Selected()
    if b then b.variant.notes = this:GetText() or ""; P.RefreshDirty() end
  end)

  -- a link to a picture of the build (talents and so on); addons cannot open a browser,
  -- so a click selects it for Ctrl+C
  local ll = W.Text(ed, "GameFontNormalSmall")
  ll:SetPoint("TOPLEFT", f, "TOPLEFT", 512, -498 - VY)
  L(ll, "Image link")
  P.link = W.Edit(ed, "ASBuilderLink", 228, 20, GameFontHighlightSmall)
  P.link:SetPoint("TOPLEFT", f, "TOPLEFT", 580, -493 - VY)
  P.link:SetMaxLetters(255)
  P.link:SetScript("OnTextChanged", function()
    if P.filling then return end
    local d = Draft()
    if d then d.link = string.gsub(this:GetText() or "", "%s", ""); P.RefreshDirty() end
  end)
  P.link:SetScript("OnEditFocusGained", function() this.focus = true; this:HighlightText() end)
  P.link:SetScript("OnEditFocusLost", function() this.focus = false; this:HighlightText(0, 0) end)
  W.Tip(P.link, function(self, tt)
    tt:SetText(T("Image link"), 1, 0.82, 0)
    tt:AddLine(T("Paste a picture link (imgur, prnt.sc, Discord) to share your talents with the build."), 0.8, 0.8, 0.8, 1)
    tt:AddLine(T("To open it: click the box, press Ctrl+C and paste it into your browser. WoW addons cannot open a browser themselves."), 0.6, 0.6, 0.6, 1)
  end)

  -- notes and link only change after Edit is pressed (copying always works)
  local nlock = W.Lock(P.notes.edit, ed, function() local b = Selected(); return b and b.variant end, "notes",
    function() P.RefreshDirty() end)
  nlock:SetPoint("BOTTOMRIGHT", P.notes, "TOPRIGHT", 0, 1)
  local llock = W.Lock(P.link, ed, Draft, "link", function() P.RefreshDirty() end)
  llock:SetPoint("RIGHT", P.link, "RIGHT", -2, 0)
  P.link:SetTextInsets(6, 40, 0, 0)
end

local function RefreshPriority(b)
  local group = P.tab or "spell"
  for i = 1, table.getn(P.tabs) do
    local tb = P.tabs[i]
    tb:SetSelected(tb.group == group)
  end
  local have, max = AB.CountGroup(b, group), AB.MAX[group]
  local count = T(AB.GROUP_LABEL[group]) .. ": " .. ((have >= max) and "|cff55ff55" or "|cffcccccc") .. have .. "/" .. max .. "|r"
  if group == "spell" then
    count = count .. "    |cffff6666" .. T("Banish") .. ": " .. AB.CountBans(b) .. "/" .. AB.MAX_BAN .. "|r"
  elseif AB.ALTS[group] then
    local alts = AB.CountAlts(b, group)
    count = T(AB.GROUP_LABEL[group]) .. ": " .. (have - alts) .. "/" .. AB.MAIN[group] .. "    |cff88bbff" .. T("Alt") .. ": " .. alts .. "/" .. AB.ALTS[group] .. "|r"
  end
  P.tabCount:SetText(count)
  local inTab = 0
  for i = 1, table.getn(b.picks) do if AB.GROUP[b.picks[i].t] == group then inTab = inTab + 1 end end
  P.clearBtn:SetOn(inTab > 0)

  local list = AB.TabIndices(b, group)
  local n = table.getn(list)
  local takes = AB.CountGroup(b, group)
  for i = 1, PRIO_ROWS do
    local r = P.prio[i]
    local pi = list[i]
    local p = pi and b.picks[pi]
    if p then
      r.pi = pi
      local info = AB.Info(b.class, p)
      r.icon.icon:SetTexture(AB.Icon(info and info.icon))
      r.name:SetText(info and info.name or p.k)
      local canAlt = AB.ALTS[AB.GROUP[p.t]] ~= nil
      r.name:SetWidth((p.t == "spell" or canAlt) and 86 or 128)
      if p.t == "spell" then
        r.ban:Show()
        r.ban:SetLabel(T("Banish"))
        r.ban:SetDanger(p.ban)
      elseif canAlt then
        r.ban:Show()
        r.ban:SetLabel(T("Alt"))
        r.ban:SetSelected(p.alt)
        if not p.alt then r.ban:SetDanger(false) end
      else
        r.ban:Hide()
      end
      if p.ban then
        r.num:SetText("")
        r.icon:SetBanned()
        r.name:SetTextColor(1, 0.45, 0.45)
        r.banText:SetText(T("will banish"))
        r.banText:Show()
        r.minus:Hide(); r.rank:Hide(); r.plus:Hide(); r.val:Hide(); r.unit:Hide(); r.val2:Hide()
        r.bg:SetVertexColor(1, 0.2, 0.2, 0.07)
        -- banished spells keep their own order below the ones to take
        r.up:SetOn(i > takes + 1)
        r.down:SetOn(i < n)
      else
        r.num:SetText(p.alt and "" or (i .. "."))
        r.icon:SetPicked(false)
        r.icon:SetDim(false)
        if p.alt then r.icon:SetAlt() end
        if p.t == "legend" then r.name:SetTextColor(1, 0.5, 0)
        elseif p.t == "amulet" and info and info.rarity then
          local c = AB.RARITY_COLOR[info.rarity]
          r.name:SetTextColor(c[1], c[2], c[3])
        elseif p.t == "spell" then r.name:SetTextColor(1, 0.82, 0)
        else r.name:SetTextColor(1, 1, 1) end
        r.banText:Hide()
        if p.t == "spell" then
          r.val:Hide(); r.unit:Hide(); r.val2:Hide()
          r.minus:Show(); r.rank:Show(); r.plus:Show()
          if (p.r or 0) == 0 then
            r.rank.text:SetText(T("max"))
            r.rank.text:SetTextColor(0.6, 0.6, 0.6)
          else
            r.rank.text:SetText(tostring(p.r))
            r.rank.text:SetTextColor(1, 1, 1)
          end
          r.minus:SetOn((p.r or 0) > 0)
          r.plus:SetOn((p.r or 0) < MAX_TARGET)
        else
          r.minus:Hide(); r.rank:Hide(); r.plus:Hide()
          r.val:Show()
          if not r.val.focus then
            P.filling = true
            r.val:SetText(((p.r or 0) > 0) and AB.Num(p.r) or "")
            P.filling = false
          end
          local stat = info and p.t ~= "legend" and AB.StatTemplate(info)
          local stat2 = info and p.t ~= "legend" and AB.StatTemplate2(info)
          if stat2 then
            r.val:SetWidth(28)
            r.unit:Hide()
            r.val2:Show()
            if not r.val2.focus then
              P.filling = true
              r.val2:SetText(((p.r2 or 0) > 0) and AB.Num(p.r2) or "")
              P.filling = false
            end
          else
            r.val:SetWidth(40)
            r.val2:Hide()
            r.unit:Show()
            r.unit:SetText((not stat or string.find(stat, "%%")) and "%" or "")
          end
        end
        if p.alt then r.bg:SetVertexColor(0.3, 0.55, 1, 0.07) else r.bg:SetVertexColor(1, 1, 1, 0.035) end
        local mains = takes - (canAlt and AB.CountAlts(b, group) or 0)
        if p.alt then
          r.up:SetOn(i > mains + 1)
          r.down:SetOn(i < takes)
        else
          r.up:SetOn(i > 1)
          r.down:SetOn(i < mains)
        end
      end
      r:Show()
    else
      r.pi = nil
      r:Hide()
    end
  end
  if n == 0 then
    P.prioHint:SetText(T(group == "spell" and "Click spells on the left to add them.\nRight-click one to mark it to banish." or "Click icons on the left to add them.\nThe order here is your upgrade priority."))
    P.prioHint:Show()
  else
    P.prioHint:Hide()
  end
end

-- ---------------------------------------------------------------- stage bar (top)
-- Four stages of the build. Each has its own picks and notes; the tracker moves on to the
-- next one when the current one is complete.
function P.StageBar(f)
  local ed = P.ed
  P.stageTabs = {}
  for i = 1, table.getn(AB.STAGE_NAMES) do
    local tb = W.Button(ed, "", 96, 22)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 200 + (i - 1) * 99, -40)
    tb.vi = i
    tb:SetScript("OnClick", function()
      P.variant = this.vi
      P.stageEdit:ClearFocus()
      P.Refresh()
    end)
    W.Tip(tb, function(self, tt)
      local d = Draft()
      local v = d and d.variants[self.vi]
      if not v then return end
      tt:SetText(v.name, 1, 0.82, 0)
      tt:AddLine(T("Stage %d of %d", self.vi, table.getn(d.variants)), 0.7, 0.7, 0.7)
      tt:AddLine(table.getn(v.picks) .. " " .. T("picks"), 0.8, 0.8, 0.8)
      tt:AddLine(T("The tracker moves on to the next stage once every pick of this one reaches its target rank. Empty stages are skipped."), 0.6, 0.6, 0.6, 1)
    end)
    P.stageTabs[i] = tb
  end

  P.copyPrev = W.Button(ed, "", 104, 22)
  P.copyPrev:SetPoint("TOPLEFT", f, "TOPLEFT", 200 + 4 * 99 + 4, -40)
  L(P.copyPrev, "Copy previous")
  P.copyPrev:SetScript("OnClick", function()
    local d = Draft()
    if d and AB.CopyPreviousStage(d, P.variant) then Changed() end
  end)
  W.Tip(P.copyPrev, function(self, tt)
    local d = Draft()
    local prev = d and d.variants[P.variant - 1]
    tt:SetText(T("Copy previous"), 1, 0.82, 0)
    if prev then
      tt:AddLine(T("Replaces this stage's picks with a copy of \"%s\", to build on: raise target ranks, swap pieces.", prev.name), 0.8, 0.8, 0.8, 1)
    end
  end)

  local se = W.Edit(ed, "ASBuilderStageEdit", 100, 22)
  se:SetPoint("TOPLEFT", f, "TOPLEFT", 708, -40)
  se:SetMaxLetters(20)
  se:SetScript("OnTextChanged", function()
    if P.filling then return end
    local d = Draft()
    local t = this:GetText() or ""
    if not d or t == "" then return end
    d.variants[P.variant].name = t
    P.RefreshDirty()
  end)
  se:SetScript("OnEditFocusGained", function() P.stageFocus = true end)
  se:SetScript("OnEditFocusLost", function()
    P.stageFocus = false
    local d = Draft()
    if d and (this:GetText() or "") == "" then this:SetText(d.variants[P.variant].name) end
  end)
  W.Tip(se, function(self, tt)
    tt:SetText(T("Stage name"), 1, 0.82, 0)
    tt:AddLine(T("Type to rename the selected stage."), 0.8, 0.8, 0.8, 1)
  end)
  P.stageEdit = se

  -- a strip under the palette when this stage breaks the run's rules
  local w = CreateFrame("Button", nil, ed)
  w:SetWidth(300)
  w:SetHeight(34)
  w:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 200, 48)
  W.Panel(w, 1, 0.3)
  w:SetBackdropColor(0.35, 0.08, 0.05, 0.9)
  w:SetBackdropBorderColor(0.95, 0.35, 0.25, 1)
  w.text = W.Text(w, "GameFontHighlightSmall")
  w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 8, -5)
  w.text:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -62, 5)
  w.text:SetJustifyV("MIDDLE")
  w.fix = W.Button(w, "", 50, 20)
  w.fix:SetPoint("RIGHT", w, "RIGHT", -6, 0)
  L(w.fix, "Fix")
  w.fix:SetScript("OnClick", function()
    local d = Draft()
    if not d then return end
    local left = AB.FixStage(d, P.variant)
    if left > 0 then Err(T("No room for %d of them: remove some picks of this stage first.", left)) end
    Changed()
  end)
  W.Tip(w.fix, function(self, tt)
    tt:SetText(T("Fix"), 1, 0.82, 0)
    tt:AddLine(T("Brings back what earlier stages take and drops spells an earlier stage banishes."), 0.8, 0.8, 0.8, 1)
  end)
  W.Tip(w, function(self, tt)
    local d = Draft()
    local issues = d and AB.StageIssues(d, P.variant) or {}
    tt:SetText(T("This stage cannot happen in a run"), 1, 0.4, 0.3)
    tt:AddLine(T("Spells, rings and trinkets stay once taken; only the amulet can be swapped. A banished card never comes back."), 0.7, 0.7, 0.7, 1)
    tt:AddLine(" ")
    for i = 1, table.getn(issues) do tt:AddLine("- " .. issues[i].text, 1, 0.75, 0.6, 1) end
  end)
  w:Hide()
  P.warn = w
end

function P.RefreshStages(d)
  for i = 1, table.getn(P.stageTabs) do
    local tb = P.stageTabs[i]
    local v = d.variants[i]
    local n = v and table.getn(v.picks) or 0
    local bad = table.getn(AB.StageIssues(d, i)) > 0
    tb:SetLabel((bad and "|cffff5544!|r " or "") .. (v and v.name or "?") .. ((n > 0) and "" or " |cff666666-|r"))
    tb:SetSelected(i == P.variant)
  end
  P.copyPrev:SetOn(P.variant > 1)
  local issues = AB.StageIssues(d, P.variant)
  local n = table.getn(issues)
  if n > 0 then
    P.warn.text:SetText("|cffff7755!|r " .. ((n == 1) and issues[1].text or T("%d problems: this stage leaves out or re-takes picks of earlier stages. Point here for the list.", n)))
    P.warn:Show()
  else
    P.warn:Hide()
  end
end

-- ---------------------------------------------------------------- bottom bar
local function BottomBar(f)
  -- everything the hero has right now, as a new build
  P.transfer = W.Button(f, "", 230, 22)
  P.transfer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 200, 12)
  L(P.transfer, "Transfer Current Build Into Planner")
  P.transfer:SetScript("OnClick", function()
    local b, msg = AB.CaptureCurrent()
    if not b then Err(msg); return end
    P.Select(b.id)
    local n = table.getn(AB.Builds())
    if n > LIST_ROWS then P.offset = n - LIST_ROWS end
    AB.Print(T("Transferred into the planner: %s", b.name))
    Changed()
  end)
  W.Tip(P.transfer, function(self, tt)
    tt:SetText(T("Transfer Current Build Into Planner"), 1, 0.82, 0)
    tt:AddLine(T("Makes a new build of everything you have in this run: your spells and the jewelry you wear, each with its current rank as the target, in the first stage."), 0.8, 0.8, 0.8, 1)
  end)

  -- "Use this build" works on the saved build: what the tracker follows
  P.useBtn = W.Button(P.ed, "", 120, 22)
  P.useBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  P.useBtn:SetScript("OnClick", function()
    local b = Saved()
    if not b then return end
    AB.SetActive(b)
    local c = AB.ClassInfo(b.class)
    AB.Print(T("Active build for %s: %s", c and c.name or b.class, b.name))
    Changed()
  end)
  W.Tip(P.useBtn, function(self, tt)
    tt:SetText(T("Use this build"), 1, 0.82, 0)
    tt:AddLine(T("The tracker follows the saved version of this build while you play its class."), 0.8, 0.8, 0.8, 1)
  end)

  P.saveBtn = W.Button(P.ed, "", 90, 22)
  P.saveBtn:SetPoint("RIGHT", P.useBtn, "LEFT", -6, 0)
  L(P.saveBtn, "Save")
  P.saveBtn:SetScript("OnClick", function()
    local d = Draft()
    if not d or not AB.IsDirty(d) then return end
    local s = AB.SaveDraft(d)
    P.draft = nil
    AB.Print(T("Saved: %s", s.name))
    for vi = 2, table.getn(s.variants) do
      local n = table.getn(AB.StageIssues(s, vi))
      if n > 0 then AB.Print("|cffff7755" .. T("Warning: %s has %d problem(s) with earlier stages.", s.variants[vi].name, n) .. "|r") end
    end
    Changed()
  end)
  W.Tip(P.saveBtn, function(self, tt)
    tt:SetText(T("Save"), 1, 0.82, 0)
    tt:AddLine(T("Keeps your changes. Unsaved changes are thrown away when you pick another build."), 0.8, 0.8, 0.8, 1)
  end)

  local exp = W.Button(P.ed, "", 90, 22)
  exp:SetPoint("RIGHT", P.saveBtn, "LEFT", -6, 0)
  L(exp, "Export")
  exp:SetScript("OnClick", function()
    local d = Draft()
    if d then P.ShowCode("export", AB.Export(d)) end
  end)
end

-- ---------------------------------------------------------------- recommended stats (right)
-- what the character's stats should reach with this build (the game's Multipliers panel,
-- plus luck and gold): typed by the build's author, read by whoever uses the build
local function Stats(f)
  local ed = P.ed
  local hl = W.Text(ed, "GameFontNormalSmall")
  hl:SetPoint("TOPLEFT", f, "TOPLEFT", 822, -44 - VY)
  L(hl, "Recommended stats")
  local hn = W.Text(ed, "GameFontNormalSmall", "RIGHT")
  hn:SetPoint("TOPLEFT", f, "TOPLEFT", 974, -44 - VY)
  hn:SetWidth(52)
  L(hn, "Now")
  P.stats = {}
  local n = table.getn(AB.STAT_KEYS)
  for i = 1, n do
    local key = AB.STAT_KEYS[i]
    local y = -64 - VY - (i - 1) * 24
    local lb = W.Text(ed, "GameFontHighlightSmall")
    lb:SetPoint("TOPLEFT", f, "TOPLEFT", 824, y - 4)
    L(lb, AB.STAT_LABEL[key])
    local e = W.Edit(ed, "ASBuilderStat" .. i, 46, 18)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", 910, y)
    e:SetMaxLetters(6)
    e:SetTextInsets(4, 4, 0, 0)
    if e.SetJustifyH then e:SetJustifyH("RIGHT") end
    e.key = key
    e:SetScript("OnTextChanged", function()
      if P.filling then return end
      local b = Selected()
      if not b then return end
      local v = tonumber((string.gsub(this:GetText() or "", ",", ".")))
      if not b.variant.stats then b.variant.stats = {} end
      b.variant.stats[this.key] = (v and v > 0) and v or nil
      P.RefreshDirty()
    end)
    e:SetScript("OnEditFocusGained", function() this.focus = true; this:HighlightText() end)
    e:SetScript("OnEditFocusLost", function() this.focus = false; P.Refresh() end)
    local u = W.Text(ed, "GameFontDisableSmall")
    u:SetPoint("LEFT", e, "RIGHT", 3, 0)
    u:SetText(AB.STAT_UNIT[key])
    e.now = W.Text(ed, "GameFontHighlightSmall", "RIGHT")
    e.now:SetPoint("TOPLEFT", f, "TOPLEFT", 974, y - 4)
    e.now:SetWidth(52)
    P.stats[i] = e
  end
  P.statsHint = W.Text(ed, "GameFontDisableSmall", "LEFT")
  P.statsHint:SetPoint("TOPLEFT", f, "TOPLEFT", 822, -64 - VY - n * 24 - 4)
  P.statsHint:SetWidth(156)
  -- the game sends new numbers while you play: keep the Now column fresh
  local tick = CreateFrame("Frame", nil, ed)
  tick.t = 0
  tick:SetScript("OnUpdate", function()
    tick.t = tick.t + (arg1 or 0)
    if tick.t > 1 then tick.t = 0; P.RefreshNow() end
  end)
end

-- the Now column: green once a recommended value is reached, orange below it
function P.RefreshNow()
  local b = Selected()
  if not b or not P.stats then return end
  local s = AB.NowStats()
  for i = 1, table.getn(P.stats) do
    local e = P.stats[i]
    local v = AB.NowStat(s, e.key)
    local t = b.variant.stats and b.variant.stats[e.key]
    e.now:SetText(v and AB.Num(v) or "-")
    if not v then e.now:SetTextColor(0.5, 0.5, 0.5)
    elseif not t then e.now:SetTextColor(0.9, 0.9, 0.9)
    elseif v >= t then e.now:SetTextColor(0.35, 1, 0.35)
    else e.now:SetTextColor(1, 0.6, 0.2) end
  end
end

-- ---------------------------------------------------------------- the code dialog
local code
local function CodeDialog()
  local d = CreateFrame("Frame", "ASBuilderCodeDialog", UIParent)
  d:SetWidth(440)
  d:SetHeight(230)
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  d:SetFrameStrata("DIALOG")
  W.Panel(d, 0.97, 0.35)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", function() this:StartMoving() end)
  d:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  d:Hide()
  table.insert(UISpecialFrames, "ASBuilderCodeDialog")

  d.title = W.Text(d, "GameFontNormal")
  d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -10)
  d.hint = W.Text(d, "GameFontHighlightSmall")
  d.hint:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -28)
  d.hint:SetWidth(416)

  d.box = W.MultiEdit(d, "ASBuilderCodeEdit", 416, 130, 24000)
  d.box:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -46)
  d.box.edit:SetScript("OnTextChanged", function()
    d.box.scroll:UpdateScrollChildRect()
    -- an export code stays as it was made
    if d.mode == "export" and d.code and this:GetText() ~= d.code then
      this:SetText(d.code)
      this:HighlightText()
    end
  end)

  d.action = W.Button(d, "", 120, 22)
  d.action:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 12)
  d.action:SetScript("OnClick", function()
    if d.mode == "export" then
      d.box.edit:SetFocus()
      d.box.edit:HighlightText()
      return
    end
    local b, info = AB.Import(d.box.edit:GetText())
    if not b then
      d.hint:SetText("|cffff5555" .. info .. "|r")
      return
    end
    b = AB.AddBuild(b)
    P.Select(b.id)
    local n = table.getn(AB.Builds())
    if n > LIST_ROWS then P.offset = n - LIST_ROWS end
    AB.Print(T("Imported: %s", b.name))
    if info and info > 0 then AB.Print(T("%d unknown entries were skipped.", info)) end
    d:Hide()
    Changed()
  end)

  d.close = W.Button(d, "", 90, 22)
  d.close:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -12, 12)
  d.close:SetScript("OnClick", function() d:Hide() end)
  code = d
end

function P.ShowCode(mode, text)
  if not code then CodeDialog() end
  code.mode = mode
  code.code = text
  code.close:SetLabel(T("Close"))
  if mode == "export" then
    code.title:SetText(T("Export"))
    code.hint:SetText(T("Copy this code (Ctrl+C) and share it."))
    code.action:SetLabel(T("Select all"))
    code:Show()
    code.box.edit:SetText(text or "")
    code.box.edit:SetFocus()
    code.box.edit:HighlightText()
  else
    code.title:SetText(T("Import"))
    code.hint:SetText(T("Paste a build code (Ctrl+V), then press Import."))
    code.action:SetLabel(T("Import"))
    code:Show()
    code.box.edit:SetText("")
    code.box.edit:SetFocus()
  end
end

-- ---------------------------------------------------------------- the reading face
-- a button in the title band; its list shows every face's name in that face
function P.FontMenu(f, close)
  local fb = W.Button(f, "", 120, 18)
  fb:SetPoint("RIGHT", close, "LEFT", -6, 0)
  local fm = CreateFrame("Frame", nil, f)
  fm:SetFrameStrata("DIALOG")
  fm:SetWidth(120)
  fm:SetHeight(table.getn(W.FACES) * 18 + 6)
  fm:SetPoint("TOPRIGHT", fb, "BOTTOMRIGHT", 0, -2)
  W.Panel(fm, 0.97, 0.35)
  fm:EnableMouse(true)
  fm:Hide()
  fm.rows = {}
  local function Label() fb:SetLabel(T("Font: %s", W.FaceInfo(W.FaceKey()).label)) end
  for i = 1, table.getn(W.FACES) do
    local fc = W.FACES[i]
    local r = CreateFrame("Button", nil, fm)
    r:SetWidth(114)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", fm, "TOPLEFT", 3, -3 - (i - 1) * 18)
    W.Hover(r, 0.1)
    r.key = fc.key
    -- not W.Text: the name stays in its own face, whatever is picked
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
    if fc.file then r.text:SetFont(fc.file, 12) end
    r.text:SetText(fc.label)
    r:SetScript("OnClick", function()
      fm:Hide()
      ASBuilderDB.font = this.key
      W.ApplyFaces()
      if W.FaceKey() ~= this.key then
        ASBuilderDB.font = "classic"
        W.ApplyFaces()
        AB.Print(T("%s could not be loaded. New font files need a full game restart (not /reload).", fc.label))
      end
      Label()
      P.Refresh()
      if AB.RefreshTracker then AB.RefreshTracker() end
    end)
    W.Tip(r, function(self, tt)
      tt:SetText(fc.label, 1, 0.82, 0)
      tt:AddLine(T(fc.tip), 0.8, 0.8, 0.8, 1)
    end)
    fm.rows[i] = r
  end
  fm:SetScript("OnShow", function()
    local cur = W.FaceKey()
    for i = 1, table.getn(fm.rows) do
      local r = fm.rows[i]
      if r.key == cur then r.text:SetTextColor(0.35, 1, 0.35) else r.text:SetTextColor(1, 1, 1) end
    end
  end)
  fb:SetScript("OnClick", function() if fm:IsVisible() then fm:Hide() else fm:Show() end end)
  W.Tip(fb, function(self, tt)
    tt:SetText(T("Font"), 1, 0.82, 0)
    tt:AddLine(T("A typeface for the planner and the tracker that may be easier to read."), 0.8, 0.8, 0.8, 1)
  end)
  Label()
end

-- ---------------------------------------------------------------- the window
local function Create()
  local f = CreateFrame("Frame", "ASBuilderPlanner", UIParent)
  f:SetWidth(FW)
  f:SetHeight(FH)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  f:SetFrameStrata("HIGH")
  if f.SetToplevel then f:SetToplevel(true) end
  W.Panel(f, 0.96, 0.3)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:Hide()
  table.insert(UISpecialFrames, "ASBuilderPlanner")
  frame = f

  -- a thin title band
  local band = f:CreateTexture(nil, "BORDER")
  band:SetTexture(W.FLAT)
  band:SetVertexColor(1, 1, 1, 0.04)
  band:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  band:SetHeight(30)
  local title = W.Text(f, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
  title:SetText("|cff7fd4ffAS|rBuilder")
  local sub = W.Text(f, "GameFontDisableSmall")
  sub:SetPoint("LEFT", title, "RIGHT", 8, -1)
  L(sub, "Build Planner")
  local close = W.IconButton(f, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 22)
  close.tex:SetTexCoord(0.18, 0.82, 0.18, 0.82)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
  close:SetScript("OnClick", function() f:Hide() end)
  P.FontMenu(f, close)

  -- thin dividers between the three columns
  for _, x in ipairs({ 194, 506, 814 }) do
    local line = f:CreateTexture(nil, "BORDER")
    line:SetTexture(W.FLAT)
    line:SetVertexColor(1, 1, 1, 0.06)
    line:SetWidth(1)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", x, (x ~= 194) and (-40 - VY) or -40)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 44)
  end

  BuildList(f)
  Editor(f)
  P.StageBar(f)
  Priority(f)
  Stats(f)
  BottomBar(f)

  P.edEmpty = W.Text(f, "GameFontDisable", "CENTER")
  P.edEmpty:SetPoint("CENTER", f, "CENTER", 100, 0)
  L(P.edEmpty, "No builds yet. Press New.")

  f:SetScript("OnShow", function() P.Refresh() end)
  f:SetScript("OnHide", function()
    P.nameEdit:ClearFocus()
    P.notes.edit:ClearFocus()
    P.link:ClearFocus()
    for i = 1, table.getn(P.stats) do P.stats[i]:ClearFocus() end
  end)
end

function P.RefreshDirty()
  local d = Draft()
  if not d then return end
  local dirty = AB.IsDirty(d)
  P.saveBtn:SetOn(dirty)
  P.saveBtn:SetAccent(dirty)
  P.dirtyText:SetText(dirty and T("Unsaved changes") or "")
  P.RefreshStages(d)
  P.RefreshList()
end

function P.Refresh()
  if not frame or not frame:IsVisible() then return end
  P.RefreshList()
  local b = Selected()
  local hasAny = table.getn(AB.Builds()) > 0
  P.bCopy:SetOn(b ~= nil)
  P.bDel:SetOn(b ~= nil)
  P.always:SetChecked(ASBuilderDB.tracker.mode == "always")
  if not b then
    local live = AB.LiveState()
    P.transfer:SetOn(live.inRun and live.phase ~= "ready")
    P.ed:Hide()
    if hasAny then P.edEmpty:Hide() else P.edEmpty:Show() end
    return
  end
  P.ed:Show()
  P.edEmpty:Hide()
  local d = Draft()
  P.filling = true
  if P.lastSel ~= b.id then
    P.lastSel = b.id
    P.nameEdit:SetText(d.name)
  elseif P.nameEdit:GetText() ~= d.name and not P.nameFocus then
    P.nameEdit:SetText(d.name)
  end
  if P.notes.edit:GetText() ~= (b.variant.notes or "") then P.notes.edit:SetText(b.variant.notes or "") end
  if P.link:GetText() ~= (d.link or "") and not P.link.focus then P.link:SetText(d.link or "") end
  for i = 1, table.getn(P.stats) do
    local e = P.stats[i]
    local v = b.variant.stats and b.variant.stats[e.key]
    local t = v and AB.Num(v) or ""
    if not e.focus and e:GetText() ~= t then e:SetText(t) end
  end
  if P.stageEdit:GetText() ~= b.variant.name and not P.stageFocus then P.stageEdit:SetText(b.variant.name) end
  P.filling = false
  P.RefreshStages(d)
  P.notesLabel:SetText(T("Notes") .. "  |cff888888(" .. b.variant.name .. ")|r")
  P.statsHint:SetText(T("What your stats should reach in %s. Leave a box empty to skip it.", b.variant.name)
    .. (AB.NowStats() and "" or ("\n" .. T("Now: open your character window (C) in a run once."))))
  P.RefreshNow()
  for i = 1, table.getn(P.classBtns) do
    local cb = P.classBtns[i]
    local on = cb.classKey == b.class
    cb:SetPicked(on)
    cb:SetDim(not on)
  end
  local ci = AB.ClassInfo(b.class)
  P.className:SetText(ci and ci.name or "")
  P.className:SetTextColor(AB.ClassRGB(b.class))
  P.fill:SetChecked(d.fill ~= false)
  local saved = Saved()
  local active = ASBuilderDB.active[saved.class] == saved.id
  P.useBtn:SetLabel(active and T("Active") or T("Use this build"))
  P.useBtn:SetAccent(active)
  local dirty = AB.IsDirty(d)
  local live = AB.LiveState()
  P.transfer:SetOn(live.inRun and live.phase ~= "ready")
  P.saveBtn:SetOn(dirty)
  P.saveBtn:SetAccent(dirty)
  P.dirtyText:SetText(dirty and T("Unsaved changes") or "")
  RefreshPalette(b)
  RefreshPriority(b)
end

-- keep the name box from being rewritten while you type in it
local function WatchNameFocus()
  P.nameEdit:SetScript("OnEditFocusGained", function() P.nameFocus = true end)
  local lost = P.nameEdit:GetScript("OnEditFocusLost")
  P.nameEdit:SetScript("OnEditFocusLost", function()
    P.nameFocus = false
    if lost then lost() end
  end)
end

function AB.TogglePlanner()
  if not frame then Create(); WatchNameFocus() end
  if frame:IsVisible() then frame:Hide() else frame:Show() end
end

function AB.OpenPlanner(buildId)
  if not frame then Create(); WatchNameFocus() end
  if buildId then P.Select(buildId) end
  frame:Show()
  P.Refresh()
end

StaticPopupDialogs["ASBUILDER_DELETE"] = {
  text = "%s",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function()
    AB.DeleteBuild(P.pendingDelete)
    P.pendingDelete = nil
    P.draft = nil
    P.selected = nil
    Changed()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- ---------------------------------------------------------------- minimap button
local mm
local function PlaceMinimap()
  local a = math.rad(ASBuilderDB.mm.angle or 205)
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

local function MinimapButton()
  if mm or not Minimap then return end
  mm = CreateFrame("Button", "ASBuilderMinimapButton", Minimap)
  mm:SetWidth(31)
  mm:SetHeight(31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(8)
  local icon = mm:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", mm, "CENTER", 0, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      local db = ASBuilderDB.tracker
      db.mode = (db.mode == "hidden") and "run" or "hidden"
      if AB.RefreshTracker then AB.RefreshTracker() end
      AB.Print(T(db.mode == "hidden" and "Tracker: hidden." or "Tracker: shown in runs."))
    else
      AB.TogglePlanner()
    end
  end)
  mm:SetScript("OnDragStart", function()
    this:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      ASBuilderDB.mm.angle = math.deg(math.atan2(py / s - my, px / s - mx))
      PlaceMinimap()
    end)
  end)
  mm:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  W.Tip(mm, function(self, tt)
    tt:SetText("|cff7fd4ffAS|rBuilder")
    tt:AddLine(T("Left-click: planner  ·  Right-click: tracker on/off"), 0.8, 0.8, 0.8)
    tt:AddLine(T("Drag: move this button"), 0.6, 0.6, 0.6)
  end)
  PlaceMinimap()
end

-- ---------------------------------------------------------------- start-up
local prevReady = AB.OnReady
AB.OnReady = function()
  if prevReady then prevReady() end
  MinimapButton()
end
