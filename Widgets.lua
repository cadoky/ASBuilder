-- ASBuilder: small flat widgets shared by the planner and the tracker. No Blizzard templates
-- (they need named frames in 1.12), just a white texture tinted into a clean, quiet look.

local AB = ASBuilder
local W = {}
AB.W = W

W.FLAT = "Interface\\Buttons\\WHITE8X8"

function W.Panel(f, alpha, border)
  f:SetBackdrop({ bgFile = W.FLAT, edgeFile = W.FLAT, tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(0.06, 0.06, 0.08, alpha or 0.95)
  local b = border or 0.22
  f:SetBackdropBorderColor(b, b, b + 0.04, 1)
end

function W.Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- a texture that lights a button up under the mouse
function W.Hover(b, a)
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetTexture(W.FLAT)
  h:SetVertexColor(1, 1, 1, a or 0.08)
  h:SetAllPoints(b)
  return h
end

function W.Tip(owner, fn)
  owner:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    fn(this, GameTooltip)
    -- nothing to say: no empty box
    if GameTooltip.NumLines and (GameTooltip:NumLines() or 0) == 0 then GameTooltip:Hide() else GameTooltip:Show() end
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a flat button with a label
function W.Button(parent, label, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width or 80)
  b:SetHeight(height or 20)
  W.Panel(b, 1, 0.3)
  b:SetBackdropColor(0.14, 0.14, 0.17, 1)
  W.Hover(b, 0.1)
  b.label = W.Text(b, "GameFontHighlightSmall", "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(label or "")
  function b:SetLabel(t) self.label:SetText(t) end
  function b:SetOn(on)
    if on then
      self:Enable()
      self.label:SetTextColor(1, 1, 1)
      self:SetBackdropColor(0.14, 0.14, 0.17, 1)
    else
      self:Disable()
      self.label:SetTextColor(0.45, 0.45, 0.45)
      self:SetBackdropColor(0.1, 0.1, 0.12, 1)
    end
  end
  function b:SetDanger(on)
    if on then
      self:SetBackdropColor(0.4, 0.08, 0.08, 1)
      self:SetBackdropBorderColor(0.9, 0.3, 0.3, 1)
      self.label:SetTextColor(1, 0.85, 0.85)
    else
      self:SetBackdropColor(0.14, 0.14, 0.17, 1)
      self:SetBackdropBorderColor(0.3, 0.3, 0.34, 1)
      self.label:SetTextColor(1, 1, 1)
    end
  end
  -- a tab: lit while it is the open one
  function b:SetSelected(on)
    if on then
      self:SetBackdropColor(0.16, 0.3, 0.45, 1)
      self:SetBackdropBorderColor(0.45, 0.7, 1, 1)
      self.label:SetTextColor(1, 1, 1)
    else
      self:SetBackdropColor(0.1, 0.1, 0.12, 1)
      self:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)
      self.label:SetTextColor(0.7, 0.7, 0.7)
    end
  end
  function b:SetAccent(on)
    if on then
      self:SetBackdropColor(0.1, 0.32, 0.14, 1)
      self:SetBackdropBorderColor(0.3, 0.75, 0.35, 1)
    else
      self:SetBackdropColor(0.14, 0.14, 0.17, 1)
      self:SetBackdropBorderColor(0.3, 0.3, 0.34, 1)
    end
  end
  return b
end

-- a small button showing a texture (arrows, plus, minus, close)
function W.IconButton(parent, tex, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size or 16)
  b:SetHeight(size or 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints(b)
  b.tex:SetTexture(tex)
  W.Hover(b, 0.15)
  function b:SetOn(on)
    if on then self:Enable(); self.tex:SetVertexColor(1, 1, 1) else self:Disable(); self.tex:SetVertexColor(0.35, 0.35, 0.35) end
  end
  return b
end

-- a square icon with a thin border that can light up green (picked) or stay plain
function W.Slot(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size)
  b:SetHeight(size)
  W.Panel(b, 1, 0.15)
  b:SetBackdropColor(0, 0, 0, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  W.Hover(b, 0.18)
  b.num = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.num:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
  -- a spell marked to banish: a red frame and a red B
  function b:SetBanned()
    self:SetBackdropBorderColor(1, 0.25, 0.25, 1)
    self.icon:SetVertexColor(0.8, 0.55, 0.55)
    self.num:SetText("B")
    self.num:SetTextColor(1, 0.3, 0.3)
  end
  -- an alternative amulet: a blue frame and a blue A
  function b:SetAlt()
    self:SetBackdropBorderColor(0.4, 0.65, 1, 1)
    self.icon:SetVertexColor(1, 1, 1)
    self.num:SetText("A")
    self.num:SetTextColor(0.5, 0.75, 1)
  end
  function b:SetPicked(on, n)
    self.num:SetTextColor(1, 1, 1)
    if on then
      self:SetBackdropBorderColor(0.35, 1, 0.35, 1)
      self.icon:SetVertexColor(1, 1, 1)
      self.num:SetText(n and tostring(n) or "")
    else
      self:SetBackdropBorderColor(0.15, 0.15, 0.19, 1)
      self.num:SetText("")
    end
  end
  function b:SetDim(on)
    if on then self.icon:SetVertexColor(0.35, 0.35, 0.35) else self.icon:SetVertexColor(1, 1, 1) end
  end
  return b
end

-- a small tick box with a label to its right
function W.Check(parent, label, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(14)
  b:SetHeight(14)
  W.Panel(b, 1, 0.35)
  b:SetBackdropColor(0.1, 0.1, 0.12, 1)
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b.mark:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.mark:SetWidth(18)
  b.mark:SetHeight(18)
  b.mark:SetVertexColor(0.35, 1, 0.35)
  b.text = W.Text(b, "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b, "RIGHT", 5, 0)
  b.text:SetText(label or "")
  W.Hover(b, 0.15)
  function b:SetChecked(on)
    self.checked = on and true or false
    if on then self.mark:Show() else self.mark:Hide() end
  end
  b:SetScript("OnClick", function()
    this:SetChecked(not this.checked)
    if onChange then onChange(this.checked) end
  end)
  return b
end

-- a one-line text box
function W.Edit(parent, name, width, height)
  local e = CreateFrame("EditBox", name, parent)
  e:SetWidth(width)
  e:SetHeight(height or 22)
  W.Panel(e, 1, 0.3)
  e:SetBackdropColor(0.02, 0.02, 0.03, 1)
  e:SetFontObject(ChatFontNormal)
  e:SetTextInsets(6, 6, 0, 0)
  e:SetAutoFocus(false)
  e:SetMaxLetters(60)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  return e
end

-- A text box of many lines inside a frame that scrolls with the mouse wheel and follows
-- the cursor. Returns the outer frame; .edit is the box.
function W.MultiEdit(parent, name, width, height, maxLetters)
  local box = CreateFrame("Frame", nil, parent)
  box:SetWidth(width)
  box:SetHeight(height)
  W.Panel(box, 1, 0.3)
  box:SetBackdropColor(0.02, 0.02, 0.03, 1)

  local sf = CreateFrame("ScrollFrame", name .. "Scroll", box)
  sf:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)

  local e = CreateFrame("EditBox", name, sf)
  e:SetWidth(width - 12)
  e:SetHeight(height - 12)
  e:SetMultiLine(true)
  e:SetAutoFocus(false)
  e:SetFontObject(GameFontHighlightSmall)
  e:SetMaxLetters(maxLetters or 2000)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  sf:SetScrollChild(e)
  box.edit, box.scroll = e, sf

  e:SetScript("OnCursorChanged", function()
    -- arg2: the cursor's offset from the top (negative), arg4: its height
    local y, h = -(arg2 or 0), arg4 or 12
    local top, view = sf:GetVerticalScroll(), sf:GetHeight()
    if y < top then
      sf:SetVerticalScroll(y)
    elseif y + h > top + view then
      sf:SetVerticalScroll(y + h - view)
    end
  end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function()
    local range = sf:GetVerticalScrollRange() or 0
    local v = sf:GetVerticalScroll() - (arg1 or 0) * 14
    if v < 0 then v = 0 end
    if v > range then v = range end
    sf:SetVerticalScroll(v)
  end)
  -- a click anywhere in the box puts the cursor in it
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() e:SetFocus() end)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() e:SetFocus() end)
  return box
end
