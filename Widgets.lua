-- ASBuilder: small flat widgets shared by the planner and the tracker. No Blizzard templates
-- (they need named frames in 1.12), just a white texture tinted into a clean, quiet look.

local AB = ASBuilder
local W = {}
AB.W = W

W.FLAT = "Interface\\Buttons\\WHITE8X8"

-- ---------------------------------------------------------------- the reading face
-- Besides the game's own face a player can pick an easier one. Every text and box the addon
-- draws is noted here with its game face, so a new pick redraws all of them at once. A picked
-- face is drawn at the size that keeps the game face's width (measured in the game), so no
-- text grows out of its place.
local FONT_DIR = "Interface\\AddOns\\ASBuilder\\media\\fonts\\"
W.FACES = {
  { key = "classic", label = "Original", tip = "The game's own face." },
  { key = "inter", label = "Inter", file = FONT_DIR .. "ASB-Inter.ttf",
    tip = "Clean and modern, made for reading on screens." },
  { key = "lato", label = "Lato", file = FONT_DIR .. "ASB-Lato.ttf",
    tip = "Warm and round, easy on the eyes." },
  { key = "nunito", label = "Nunito", file = FONT_DIR .. "ASB-Nunito.ttf",
    tip = "Soft, rounded letters." },
  { key = "lexend", label = "Lexend", file = FONT_DIR .. "ASB-Lexend.ttf",
    tip = "Wide, open letters made to make reading easier." },
  { key = "noto", label = "Noto Sans", file = FONT_DIR .. "ASB-NotoSans.ttf",
    tip = "Plain and very clear." },
}
local faceReg = {}     -- every text and box: its game face, size and flags
local faceBroken = {}  -- faces the game could not load
local faceScale = {}   -- per picked face and game face: the size factor that keeps the width
local measure          -- a hidden string to measure faces with

function W.FaceInfo(key)
  for i = 1, table.getn(W.FACES) do if W.FACES[i].key == key then return W.FACES[i] end end
  return W.FACES[1]
end

function W.FaceKey()
  local f = W.FaceInfo(type(ASBuilderDB) == "table" and ASBuilderDB.font or "classic")
  if faceBroken[f.key] then return "classic" end
  return f.key
end

-- true if the text really draws in this face (the game keeps the old face otherwise)
local function Loaded(o, file)
  local got = o:GetFont()
  if type(got) ~= "string" then return false end
  local base = string.gsub(string.upper(file), "^.*\\", "")
  return string.find(string.upper(got), base, 1, true) ~= nil
end

local function Width(face, size)
  if not measure then
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetAlpha(0)  -- never anchored and never seen: it only measures
    measure = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  end
  measure:SetFont(face, size)
  if not Loaded(measure, face) then return nil end
  measure:SetText("The quick brown fox jumps over the lazy dog, 1234567890.")
  local w = measure:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then return nil end
  return w
end

local function Factor(file, face)
  local k = file .. "|" .. face
  if not faceScale[k] then
    local a, b = Width(face, 20), Width(file, 20)
    if a and b then faceScale[k] = math.max(0.75, math.min(1.2, a / b)) else faceScale[k] = 1 end
  end
  return faceScale[k]
end

local function ApplyFace(o, e)
  local pick = W.FaceInfo(W.FaceKey())
  if pick.file then
    o:SetFont(pick.file, math.floor(e.size * Factor(pick.file, e.face) + 0.5), e.flags)
    if Loaded(o, pick.file) then return end
    faceBroken[pick.key] = true  -- the game cannot draw it: back to its own face
  end
  o:SetFont(e.face, e.size, e.flags)
end

-- notes a text or box with its game face and draws it in the picked one
function W.Face(o)
  if faceReg[o] or not o.GetFont then return o end
  local face, size, flags = o:GetFont()
  if type(face) == "string" and type(size) == "number" then
    faceReg[o] = { face = face, size = size, flags = type(flags) == "string" and flags or "" }
    if W.FaceKey() ~= "classic" then ApplyFace(o, faceReg[o]) end
  end
  return o
end

-- redraws every text after a new pick
function W.ApplyFaces()
  for o, e in pairs(faceReg) do ApplyFace(o, e) end
end

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
  return W.Face(fs)
end

-- a texture that lights a button up under the mouse
function W.Hover(b, a)
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetTexture(W.FLAT)
  h:SetVertexColor(1, 1, 1, a or 0.08)
  h:SetAllPoints(b)
  return h
end

-- The addon's own tooltip frame: the game's GameTooltip is parked bottom right whatever
-- anchor it gets, a tooltip of our own can sit next to the mouse.
local tip
function W.Tooltip()
  if not tip then
    tip = CreateFrame("GameTooltip", "ASBuilderTip", UIParent, "GameTooltipTemplate")
    tip:SetFrameStrata("TOOLTIP")
  end
  return tip
end

-- owns the tooltip and puts it next to the mouse; flips to the other side near the screen edges
function W.TipOwner(owner)
  local tt = W.Tooltip()
  tt:SetOwner(owner, "ANCHOR_NONE")
  local s = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x, y = x / s, y / s
  local left = x > UIParent:GetWidth() - 320
  local below = y > UIParent:GetHeight() - 220
  tt:ClearAllPoints()
  tt:SetPoint((below and "TOP" or "BOTTOM") .. (left and "RIGHT" or "LEFT"), UIParent, "BOTTOMLEFT",
    x + (left and -14 or 14), y + (below and -14 or 14))
  return tt
end

function W.Tip(owner, fn)
  owner:SetScript("OnEnter", function()
    local tt = W.TipOwner(this)
    fn(this, tt)
    -- nothing to say: no empty box
    if tt.NumLines and (tt:NumLines() or 0) == 0 then tt:Hide() else tt:Show() end
  end)
  owner:SetScript("OnLeave", function() W.Tooltip():Hide() end)
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
  -- an alternative ring, trinket or amulet: a blue frame and a blue A
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
function W.Edit(parent, name, width, height, font)
  local e = CreateFrame("EditBox", name, parent)
  e:SetWidth(width)
  e:SetHeight(height or 22)
  W.Panel(e, 1, 0.3)
  e:SetBackdropColor(0.02, 0.02, 0.03, 1)
  e:SetFontObject(font or ChatFontNormal)
  e:SetTextInsets(6, 6, 0, 0)
  e:SetAutoFocus(false)
  e:SetMaxLetters(60)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  return W.Face(e)
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
  W.Face(e)
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

-- Edit, tick and cross at a box's top-right. Until Edit is pressed the box can be clicked,
-- selected and copied (Ctrl+C), but every change is undone at once. The tick keeps the
-- changes, the cross puts back the text from before Edit. src() gives the table that holds
-- the text under key; done() runs after the tick or the cross. Returns the frame to place.
function W.Lock(e, parent, src, key, done)
  e.locked = true
  local function Model()
    local t = src()
    return t and t[key] or ""
  end
  local onText = e:GetScript("OnTextChanged")
  e:SetScript("OnTextChanged", function()
    if e.locked then
      local m = Model()
      if this:GetText() ~= m then this:SetText(m); return end
    end
    if onText then onText() end
  end)

  local g = CreateFrame("Frame", nil, parent)
  g:SetWidth(34)
  g:SetHeight(16)
  g:SetFrameLevel((e:GetFrameLevel() or 1) + 3)
  local edit = W.Button(g, AB.T("Edit"), 34, 16)
  edit:SetPoint("RIGHT", g, "RIGHT", 0, 0)
  local no = W.IconButton(g, "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 16)
  no.tex:SetTexCoord(0.18, 0.82, 0.18, 0.82)
  no:SetPoint("RIGHT", g, "RIGHT", 0, 0)
  local ok = W.IconButton(g, "Interface\\Buttons\\UI-CheckBox-Check", 16)
  ok.tex:SetVertexColor(0.35, 1, 0.35)
  ok:SetPoint("RIGHT", no, "LEFT", -2, 0)
  for _, b in ipairs({ edit, ok, no }) do b:SetFrameLevel(g:GetFrameLevel() + 1) end

  local function Show()
    if e.locked then edit:Show(); ok:Hide(); no:Hide() else edit:Hide(); ok:Show(); no:Show() end
  end
  edit:SetScript("OnClick", function()
    e.locked = false
    e.target, e.orig = src(), Model()
    Show()
    e:SetFocus()
  end)
  ok:SetScript("OnClick", function()
    e.locked = true
    e:ClearFocus()
    Show()
    if done then done() end
  end)
  no:SetScript("OnClick", function()
    if e.target then e.target[key] = e.orig end
    e.locked = true
    e:ClearFocus()
    Show()
    e:SetText(Model())
    if done then done() end
  end)
  W.Tip(edit, function(self, tt)
    tt:SetText(AB.T("Edit"), 1, 0.82, 0)
    tt:AddLine(AB.T("Unlocks the box. Until then you can select and copy the text, but not change it."), 0.8, 0.8, 0.8, 1)
  end)
  W.Tip(ok, function(self, tt) tt:SetText(AB.T("Done: keep the changes")) end)
  W.Tip(no, function(self, tt) tt:SetText(AB.T("Cancel: put the old text back")) end)
  Show()
  return g
end
