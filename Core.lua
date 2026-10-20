-- ASBuilder core: saved builds, reading the run (spells and worn jewelry), working out what a
-- build still needs, and the import/export codes. Lua 5.0 / WoW 1.12 conventions throughout.

ASBuilder = {}
local AB = ASBuilder
local D = ASBuilder_Data

AB.VERSION = "1.1.0"

-- how many of each a hero can hold in a run
AB.MAX = { spell = 6, ring = 4, trinket = 4, amulet = 4 }   -- main picks + alternatives
-- the main picks of each group, and how many alternatives it may hold on top
AB.MAIN = { spell = 6, ring = 2, trinket = 2, amulet = 1 }
AB.ALTS = { ring = 2, trinket = 2, amulet = 3 }
-- spells marked to be banished when their card comes up (a run grants up to 3 banishes)
AB.MAX_BAN = 3
-- the slot group each kind of pick takes
AB.GROUP = { spell = "spell", ring = "ring", trinket = "trinket", amulet = "amulet", legend = "amulet" }
AB.GROUP_LABEL = { spell = "Spells", ring = "Rings", trinket = "Trinkets", amulet = "Amulet" }

AB.RARITY = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
AB.RARITY_COLOR = {
  Common = { 1, 1, 1 }, Uncommon = { 0.12, 1, 0 }, Rare = { 0.2, 0.55, 1 },
  Epic = { 0.64, 0.21, 0.93 }, Legendary = { 1, 0.5, 0 },
}
local LINK_RARITY = { ffffffff = "Common", ff1eff00 = "Uncommon", ff0070dd = "Rare", ffa335ee = "Epic", ffff8000 = "Legendary" }

-- the inventory slots a run fills: neck, two fingers, two trinkets
AB.SLOTS = { { 2, "amulet" }, { 11, "ring" }, { 12, "ring" }, { 13, "trinket" }, { 14, "trinket" } }

-- ---------------------------------------------------------------- words
-- the addon's texts (English only); fills in %s and %d
function AB.T(s, ...)
  if arg.n > 0 then return string.format(s, unpack(arg)) end
  return s
end
local T = AB.T

function AB.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffASBuilder:|r " .. msg)
end

function AB.Icon(icon)
  if not icon then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  return "Interface\\Icons\\" .. icon
end

-- ---------------------------------------------------------------- lookups
AB.classIndex, AB.spellIndex = {}, {}
AB.ringByName, AB.trinketByName, AB.amuletByName, AB.legendNames = {}, {}, {}, {}
for i = 1, table.getn(D.classes) do
  local c = D.classes[i]
  AB.classIndex[c.key] = i
  AB.spellIndex[c.key] = {}
  for j = 1, table.getn(c.spells) do
    local s = c.spells[j]
    AB.spellIndex[c.key][s.key] = s
    if s.amulet then AB.legendNames[s.amulet] = true end
  end
end
for i = 1, table.getn(D.rings) do AB.ringByName[D.rings[i].name] = D.rings[i] end
for i = 1, table.getn(D.trinkets) do AB.trinketByName[D.trinkets[i].name] = D.trinkets[i] end
for i = 1, table.getn(D.amulets) do AB.amuletByName[D.amulets[i].name] = D.amulets[i] end

-- each class's icon, as the game itself shows it
AB.CLASS_ICON = {}
for i = 1, table.getn(D.classes) do
  local c = D.classes[i]
  AB.CLASS_ICON[c.key] = c.icon or (c.spells[1] and c.spells[1].icon)
end

function AB.ClassInfo(key)
  local i = AB.classIndex[key]
  return i and D.classes[i] or nil
end

function AB.ClassColor(key)
  local c = AB.ClassInfo(key)
  return "|cff" .. (c and c.color or "ffffff")
end

function AB.ClassRGB(key)
  local c = AB.ClassInfo(key)
  local hex = c and c.color or "FFFFFF"
  return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- What a pick is: its name, icon and data. nil for a pick the data does not know.
-- A pick is { t = "spell"|"ring"|"trinket"|"amulet"|"legend", k = spell key or English name, r = target rank (0 = max) }
function AB.Info(cls, p)
  if not p then return nil end
  if p.t == "spell" or p.t == "legend" then
    local s = AB.spellIndex[cls] and AB.spellIndex[cls][p.k]
    if not s then return nil end
    if p.t == "spell" then return { name = s.name, icon = s.icon, data = s } end
    return { name = s.amulet, icon = (ASBuilder_AmuletIcons and ASBuilder_AmuletIcons[s.amulet]) or "INV_Jewelry_Necklace_16", data = s, spell = s }
  elseif p.t == "ring" then
    local d = AB.ringByName[p.k]
    if d then return { name = d.name, icon = d.icon, data = d } end
  elseif p.t == "trinket" then
    local d = AB.trinketByName[p.k]
    if d then return { name = d.name, icon = d.icon, data = d } end
  elseif p.t == "amulet" then
    local d = AB.amuletByName[p.k]
    if d then return { name = d.name, icon = d.icon, data = d, rarity = d.rarity } end
  end
  return nil
end

-- a stat line from the game as plain text: "+{v}% damage" -> "+X% damage"
function AB.StatText(t)
  if not t then return nil end
  local s = string.gsub(t, "{max}", "")
  s = string.gsub(s, "{%a+}", "X")
  return s
end

-- what an amulet gives at base (Stats.lua), nil for one not listed there yet
function AB.AmuletStats(key)
  local t = ASBuilder_AmuletStats
  return t and key and t[key] or nil
end

-- what a legendary amulet does to the spell it remakes (Stats.lua)
function AB.LegendStats(cls, key)
  local t = ASBuilder_LegendStats
  return t and cls and key and t[cls] and t[cls][key] or nil
end

-- the stat a pick's target is measured in: a ring's stat, an amulet's first base stat
function AB.StatTemplate(info)
  local d = info and info.data
  if not d then return nil end
  if d.stat then return d.stat end
  local base = d.key and AB.AmuletStats(d.key)
  return base and base[1] or nil
end

-- what a piece of jewelry gave the last time it was worn (its tooltip's green lines)
function AB.SeenLines(name)
  local seen = type(ASBuilderDB) == "table" and ASBuilderDB.seen
  return seen and name and seen[name] or nil
end

-- Fills GameTooltip (already owned) with what a pick does.
function AB.FillTooltip(tt, cls, p)
  local info = AB.Info(cls, p)
  if not info then tt:SetText(p and p.k or "?", 1, 1, 1); return end
  local d = info.data
  local gray = 0.6
  local function Seen(head)
    local lines = AB.SeenLines(info.name)
    if lines then
      tt:AddLine(head or T("When last worn:"), gray, gray, gray)
      for i = 1, table.getn(lines) do tt:AddLine(lines[i], 0.12, 1, 0, 1) end
      return true
    end
    return false
  end
  if p.t == "spell" then
    tt:SetText(info.name, 1, 0.82, 0)
    local c = AB.ClassInfo(cls)
    tt:AddLine(c and c.name or cls, AB.ClassRGB(cls))
    if d.amulet then tt:AddLine(T("Legendary amulet") .. ": " .. d.amulet, 1, 0.5, 0) end
  elseif p.t == "ring" or p.t == "trinket" then
    tt:SetText(info.name, 1, 1, 1)
    tt:AddLine(T(p.t == "ring" and "Ring" or "Trinket"), gray, gray, gray)
    tt:AddLine(AB.StatText(d.stat), 0.12, 1, 0, 1)
  elseif p.t == "amulet" then
    local c = AB.RARITY_COLOR[d.rarity] or AB.RARITY_COLOR.Common
    tt:SetText(info.name, c[1], c[2], c[3])
    tt:AddLine(T(d.rarity or "Common") .. " " .. T("amulet"), gray, gray, gray)
    local base = AB.AmuletStats(d.key)
    if base then
      for i = 1, table.getn(base) do tt:AddLine(base[i], 0.12, 1, 0, 1) end
      tt:AddLine(T("Base values. Offered again while worn, they grow toward 3x."), 0.5, 0.5, 0.5, 1)
      Seen()
    elseif not Seen() then
      tt:AddLine(T("Its stats show here once you have worn it."), 0.5, 0.5, 0.5, 1)
    end
  elseif p.t == "legend" then
    tt:SetText(info.name, 1, 0.5, 0)
    tt:AddLine((string.gsub(D.remakes or "Legendary amulet · remakes {spell}", "{spell}", d.name)), gray, gray, gray)
    local fx = AB.LegendStats(cls, d.key)
    if fx then
      for i = 1, table.getn(fx) do tt:AddLine(fx[i], 0.12, 1, 0, 1) end
      tt:AddLine(T("Offered only once you know the spell."), 0.5, 0.5, 0.5, 1)
    elseif not Seen() then
      tt:AddLine(T("Offered only once you know the spell."), 0.5, 0.5, 0.5, 1)
    end
  end
end

-- ---------------------------------------------------------------- saved data
-- ---------------------------------------------------------------- builds and their stages
-- A build has one class and four stages (variants): Early Game, Mid Game, End Game and
-- Endless by default, each renamable, each with its own picks and notes. The tracker
-- follows the first stage that is not complete yet.
AB.STAGE_NAMES = { "Early Game", "Mid Game", "End Game", "Endless" }

function AB.NewVariants()
  local v = {}
  for i = 1, table.getn(AB.STAGE_NAMES) do
    table.insert(v, { name = AB.STAGE_NAMES[i], picks = {}, notes = "" })
  end
  return v
end

-- one stage of a build as a "view": what the pick functions below work on
function AB.View(b, vi)
  local v = b.variants[vi or 1] or b.variants[1]
  return { id = b.id, class = b.class, fill = b.fill, name = b.name, picks = v.picks, notes = v.notes, variant = v }
end

local function CopyPicks(list)
  local out = {}
  for i = 1, table.getn(list or {}) do
    local p = list[i]
    table.insert(out, { t = p.t, k = p.k, r = p.r, ban = p.ban, alt = p.alt })
  end
  return out
end

local function CopyVariants(list)
  local out = {}
  for i = 1, table.getn(list or {}) do
    local v = list[i]
    table.insert(out, { name = v.name, picks = CopyPicks(v.picks), notes = v.notes or "" })
  end
  return out
end

-- stash[class][stage] = the spells and legendary amulet put aside when the class changed
local function CopyStash(stash)
  local out = {}
  if type(stash) == "table" then
    for cls, byStage in pairs(stash) do
      out[cls] = {}
      for vi, list in pairs(byStage) do out[cls][vi] = CopyPicks(list) end
    end
  end
  return out
end

-- brings an older saved build up to date: one list of picks becomes the first stage
local function Upgrade(b)
  if type(b.variants) ~= "table" or table.getn(b.variants) == 0 then
    b.variants = AB.NewVariants()
    if type(b.picks) == "table" then b.variants[1].picks = b.picks end
    if type(b.notes) == "string" then b.variants[1].notes = b.notes end
  end
  b.picks, b.notes = nil, nil
  for i = 1, table.getn(AB.STAGE_NAMES) do
    if not b.variants[i] then b.variants[i] = { name = AB.STAGE_NAMES[i], picks = {}, notes = "" } end
    local v = b.variants[i]
    if type(v.picks) ~= "table" then v.picks = {} end
    if type(v.notes) ~= "string" then v.notes = "" end
    if type(v.name) ~= "string" or v.name == "" then v.name = AB.STAGE_NAMES[i] end
  end
  if type(b.link) ~= "string" then b.link = "" end
  if type(b.stash) ~= "table" then b.stash = {} end
  for cls, byStage in pairs(b.stash) do
    -- the old form held one list per class: it belonged to the first stage
    if type(byStage) ~= "table" then b.stash[cls] = nil
    elseif byStage[1] and byStage[1].t then b.stash[cls] = { [1] = byStage } end
  end
  if b.fill == nil then b.fill = true end
end

-- The builds that come with the addon (Defaults.lua). Each is added once, by its key, and
-- never again: a player's own builds, and defaults they changed or deleted, stay untouched
-- by updates. A default whose class and name a build already has is not added.
local function AddDefaults(db)
  local list = ASBuilder_Defaults
  if type(list) ~= "table" then return end
  if type(db.defaults) ~= "table" then db.defaults = {} end
  for i = 1, table.getn(list) do
    local d = list[i]
    if d.key and not db.defaults[d.key] and AB.classIndex[d.class] then
      db.defaults[d.key] = true
      local have = false
      for j = 1, table.getn(db.builds) do
        if db.builds[j].class == d.class and db.builds[j].name == d.name then have = true end
      end
      if not have then
        local b = AB.CloneBuild(d)
        b.id = nil
        for vi = 1, table.getn(b.variants) do
          local picks = b.variants[vi].picks
          for j = table.getn(picks), 1, -1 do
            if not AB.Info(b.class, picks[j]) then table.remove(picks, j) end
          end
        end
        AB.AddBuild(b)
      end
    end
  end
end

function AB.InitDB()
  if type(ASBuilderDB) ~= "table" then ASBuilderDB = {} end
  local db = ASBuilderDB
  if type(db.builds) ~= "table" then db.builds = {} end
  if type(db.active) ~= "table" then db.active = {} end
  db.nextId = db.nextId or 1
  if type(db.tracker) ~= "table" then db.tracker = {} end
  if db.tracker.mode == nil then db.tracker.mode = "run" end
  db.tracker.scale = db.tracker.scale or 1
  if type(db.mm) ~= "table" then db.mm = { angle = 205 } end
  if type(db.run) ~= "table" then db.run = {} end
  if type(db.run.jr) ~= "table" then db.run.jr = {} end
  if type(db.run.stage) ~= "table" then db.run.stage = {} end
  if type(db.run.pin) ~= "table" then db.run.pin = {} end
  -- spells marked banished on the tracker this run (the game does not tell addons)
  if type(db.run.banished) ~= "table" then db.run.banished = {} end
  if type(db.seen) ~= "table" then db.seen = {} end
  -- every time you enter the game no build is chosen: pick one from the tracker's menu.
  -- A /reload keeps the choice (the game only logs out when you really leave).
  if db.session ~= "open" then db.active = {} end
  db.session = "open"
  for i = 1, table.getn(db.builds) do
    local b = db.builds[i]
    Upgrade(b)
    -- drop picks the data no longer knows (an older or newer data file)
    for vi = 1, table.getn(b.variants) do
      local list = b.variants[vi].picks
      for j = table.getn(list), 1, -1 do
        if not AB.Info(b.class, list[j]) then table.remove(list, j) end
      end
    end
    for cls, byStage in pairs(b.stash) do
      for vi, list in pairs(byStage) do
        for j = table.getn(list), 1, -1 do
          if not AB.Info(cls, list[j]) then table.remove(list, j) end
        end
      end
    end
    if b.id and b.id >= db.nextId then db.nextId = b.id + 1 end
    -- jewelry targets used to be ranks; they are values now (what the piece gives)
    if (db.dataVersion or 1) < 2 then
      for vi = 1, table.getn(b.variants) do AB.ClearJewelTargets(b.variants[vi].picks) end
    end
  end
  db.dataVersion = 2
  AddDefaults(db)
end

function AB.IsJewel(p) return p and p.t ~= "spell" end

function AB.ClearJewelTargets(list)
  for i = 1, table.getn(list or {}) do
    if AB.IsJewel(list[i]) then list[i].r = 0 end
  end
end

function AB.Builds() return ASBuilderDB.builds end

function AB.GetBuild(id)
  if not id then return nil end
  local list = ASBuilderDB.builds
  for i = 1, table.getn(list) do
    if list[i].id == id then return list[i], i end
  end
  return nil
end

function AB.BuildsFor(cls)
  local out, list = {}, ASBuilderDB.builds
  for i = 1, table.getn(list) do
    if list[i].class == cls then table.insert(out, list[i]) end
  end
  return out
end

local function UniqueName(name)
  local taken = {}
  local list = ASBuilderDB.builds
  for i = 1, table.getn(list) do taken[list[i].name] = true end
  if not taken[name] then return name end
  local n = 2
  while taken[name .. " " .. n] do n = n + 1 end
  return name .. " " .. n
end
AB.UniqueName = UniqueName

function AB.AddBuild(b)
  local db = ASBuilderDB
  b.id = db.nextId
  db.nextId = db.nextId + 1
  b.name = UniqueName(b.name or T("New build"))
  Upgrade(b)
  table.insert(db.builds, b)
  return b
end

function AB.NewBuild(cls)
  return AB.AddBuild({ class = cls, name = T("New build"), variants = AB.NewVariants(), fill = true })
end

-- a full, separate copy of a build (the planner edits one of these until you press Save)
function AB.CloneBuild(b)
  return { id = b.id, class = b.class, name = b.name, fill = b.fill, link = b.link or "",
    variants = CopyVariants(b.variants), stash = CopyStash(b.stash) }
end

-- everything a build holds, as one string, to tell whether two versions differ
local function PicksString(list)
  local parts = {}
  for i = 1, table.getn(list or {}) do
    local p = list[i]
    table.insert(parts, p.t .. ":" .. p.k .. ":" .. (p.r or 0) .. (p.ban and ":b" or "") .. (p.alt and ":a" or ""))
  end
  return table.concat(parts, ";")
end

function AB.Serialize(b)
  local stash = {}
  if type(b.stash) == "table" then
    for cls, byStage in pairs(b.stash) do
      for vi, list in pairs(byStage) do
        if table.getn(list) > 0 then table.insert(stash, cls .. vi .. "=" .. PicksString(list)) end
      end
    end
  end
  table.sort(stash)
  local parts = { b.name or "", b.class or "", (b.fill == false) and "0" or "1", b.link or "" }
  for i = 1, table.getn(b.variants or {}) do
    local v = b.variants[i]
    table.insert(parts, (v.name or "") .. "#" .. PicksString(v.picks) .. "#" .. (v.notes or ""))
  end
  table.insert(parts, table.concat(stash, "|"))
  return table.concat(parts, "\n")
end

function AB.IsDirty(draft)
  local saved = draft and AB.GetBuild(draft.id)
  if not saved then return false end
  return AB.Serialize(draft) ~= AB.Serialize(saved)
end

-- writes a draft over its saved build; a build that changed class hands its "active" mark
-- for the old class to another build of that class and takes it for the new one if free
function AB.SaveDraft(draft)
  local saved = AB.GetBuild(draft.id)
  if not saved then return nil end
  if saved.class ~= draft.class then
    local db = ASBuilderDB
    if db.active[saved.class] == saved.id then
      db.active[saved.class] = nil
      local rest = AB.BuildsFor(saved.class)
      for i = 1, table.getn(rest) do
        if rest[i].id ~= saved.id then db.active[saved.class] = rest[i].id; break end
      end
    end
    if not AB.ActiveBuild(draft.class) then db.active[draft.class] = saved.id end
  end
  saved.class = draft.class
  saved.name = draft.name
  saved.fill = draft.fill
  saved.link = draft.link or ""
  saved.variants = CopyVariants(draft.variants)
  saved.stash = CopyStash(draft.stash)
  return saved
end

function AB.CopyBuild(src)
  local c = AB.CloneBuild(src)
  c.id = nil
  c.name = src.name .. " " .. T("(copy)")
  return AB.AddBuild(c)
end

-- ---------------------------------------------------------------- stage checks
-- In a run, a spell, ring or trinket once taken stays to the end; only the amulet can be
-- swapped, and a banished card never comes back. So each stage must keep what the stages
-- before it take, and may not take a spell an earlier stage banishes.
local KEEPS = { spell = true, ring = true, trinket = true }

-- what the stages before vi (those with picks) take and banish
local function Earlier(b, vi)
  local takes, bans, from = {}, {}, {}
  for i = 1, vi - 1 do
    local v = b.variants[i]
    for j = 1, table.getn(v.picks) do
      local p = v.picks[j]
      local key = p.t .. ":" .. p.k
      if p.ban then
        bans[p.k] = bans[p.k] or v.name
      elseif KEEPS[p.t] and not p.alt and not takes[key] then
        takes[key] = p
        from[key] = v.name
      end
    end
  end
  return takes, bans, from
end

-- Returns the problems of stage vi: { text, pick } each (an empty table when it is fine)
function AB.StageIssues(b, vi)
  local out = {}
  local v = b.variants[vi]
  if not v or table.getn(v.picks) == 0 or vi < 2 then return out end
  local takes, bans, from = Earlier(b, vi)
  local view = AB.View(b, vi)
  local keys = {}
  for key in pairs(takes) do table.insert(keys, key) end
  table.sort(keys)
  for n = 1, table.getn(keys) do
    local p = takes[keys[n]]
    local i = AB.FindPick(view, p.t, p.k)
    local info = AB.Info(b.class, p)
    local name = info and info.name or p.k
    if not i then
      table.insert(out, { text = T("%s is taken in %s and stays for the whole run, but this stage leaves it out.", name, from[keys[n]]), pick = p, kind = "drop" })
    elseif v.picks[i].ban then
      table.insert(out, { text = T("%s is taken in %s: it cannot be banished later.", name, from[keys[n]]), pick = p, kind = "drop" })
    end
  end
  for j = 1, table.getn(v.picks) do
    local p = v.picks[j]
    if p.t == "spell" and not p.ban and bans[p.k] then
      local info = AB.Info(b.class, p)
      table.insert(out, { text = T("%s is banished in %s: its card never comes back that run.", info and info.name or p.k, bans[p.k]), pick = p, kind = "banned" })
    end
  end
  return out
end

-- Repairs stage vi: brings back what earlier stages take (when there is room) and drops
-- spells an earlier stage banishes. Returns how many could not be brought back.
function AB.FixStage(b, vi)
  local view = AB.View(b, vi)
  local issues = AB.StageIssues(b, vi)
  local left = 0
  -- first drop the impossible picks, to make room
  for n = 1, table.getn(issues) do
    local is = issues[n]
    if is.kind == "banned" then
      local i = AB.FindPick(view, is.pick.t, is.pick.k)
      if i then table.remove(view.picks, i) end
    end
  end
  for n = 1, table.getn(issues) do
    local is = issues[n]
    if is.kind == "drop" then
      local p = is.pick
      local i = AB.FindPick(view, p.t, p.k)
      local group = AB.GROUP[p.t]
      if i and view.picks[i].ban then table.remove(view.picks, i) end
      local np = { t = p.t, k = p.k, r = p.r or 0 }
      if AB.Fit(view, np) then
        table.insert(view.picks, np)
      else
        left = left + 1
      end
    end
  end
  return left
end

-- a stage takes the picks of the stage before it, to build on
function AB.CopyPreviousStage(b, vi)
  if vi < 2 or not b.variants[vi - 1] then return false end
  b.variants[vi].picks = CopyPicks(b.variants[vi - 1].picks)
  return true
end

function AB.DeleteBuild(id)
  local b, i = AB.GetBuild(id)
  if not b then return end
  table.remove(ASBuilderDB.builds, i)
  if ASBuilderDB.active[b.class] == id then
    local rest = AB.BuildsFor(b.class)
    ASBuilderDB.active[b.class] = rest[1] and rest[1].id or nil
  end
end

function AB.ActiveBuild(cls)
  local id = ASBuilderDB.active[cls]
  local b = AB.GetBuild(id)
  if b and b.class == cls then return b end
  return nil
end

function AB.SetActive(b)
  if b then ASBuilderDB.active[b.class] = b.id end
end

function AB.ClearActive(cls)
  ASBuilderDB.active[cls] = nil
end

-- the next build of the class, for the tracker's header click
function AB.CycleActive(cls)
  local list = AB.BuildsFor(cls)
  local n = table.getn(list)
  if n == 0 then return nil end
  local cur = ASBuilderDB.active[cls]
  local idx = 0
  for i = 1, n do if list[i].id == cur then idx = i end end
  local nb = list[math.mod(idx, n) + 1]
  ASBuilderDB.active[cls] = nb.id
  return nb
end

-- ---------------------------------------------------------------- picks (on a stage view)
-- A pick is { t = "spell"|"ring"|"trinket"|"amulet"|"legend", k, r = target rank (0 = max),
-- ban = a spell to banish, alt = an alternative }. Rings, trinkets and the amulet hold their
-- main picks (AB.MAIN) plus a few alternatives (AB.ALTS): wearing an alternative fills a slot
-- of its group just as well.
AB.MAX_ALT = AB.ALTS.amulet

-- picks that take a place in the group (a spell marked to banish takes none)
function AB.CountGroup(b, group)
  local n = 0
  for i = 1, table.getn(b.picks) do
    local p = b.picks[i]
    if AB.GROUP[p.t] == group and not p.ban then n = n + 1 end
  end
  return n
end

function AB.CountBans(b)
  local n = 0
  for i = 1, table.getn(b.picks) do
    if b.picks[i].ban then n = n + 1 end
  end
  return n
end

-- alternatives in one group (in every group when none is given)
function AB.CountAlts(b, group)
  local n = 0
  for i = 1, table.getn(b.picks) do
    local p = b.picks[i]
    if p.alt and (not group or AB.GROUP[p.t] == group) then n = n + 1 end
  end
  return n
end

-- Whether one more pick like p fits in a stage view. A main pick with its group's main
-- places full becomes an alternative, and an alternative with no place left a main pick.
function AB.Fit(view, p)
  if p.ban then return AB.CountBans(view) < AB.MAX_BAN end
  local group = AB.GROUP[p.t]
  if not group or AB.CountGroup(view, group) >= AB.MAX[group] then return false end
  local alts = AB.CountAlts(view, group)
  if p.alt and alts >= (AB.ALTS[group] or 0) then p.alt = nil end
  if not p.alt and AB.CountGroup(view, group) - alts >= AB.MAIN[group] then p.alt = true end
  return true
end

function AB.FindPick(b, t, k)
  for i = 1, table.getn(b.picks) do
    local p = b.picks[i]
    if p.t == t and p.k == k then return i end
  end
  return nil
end

local function FullMsg(group)
  return T("Slot full: %s (%d at most)", T(AB.GROUP_LABEL[group]), AB.MAX[group])
end

-- Adds a pick, or removes it if it is there. ban: add a spell as one to banish. A new ring,
-- trinket or amulet is a main pick while there is room, else an alternative.
-- Returns false and a message when there is no room.
function AB.TogglePick(b, t, k, ban)
  local i = AB.FindPick(b, t, k)
  if i then table.remove(b.picks, i); return true end
  if ban then
    if t ~= "spell" then return false end
    if AB.CountBans(b) >= AB.MAX_BAN then return false, T("Banish list full (%d at most)", AB.MAX_BAN) end
    table.insert(b.picks, { t = t, k = k, r = 0, ban = true })
    return true
  end
  local group = AB.GROUP[t]
  if AB.CountGroup(b, group) >= AB.MAX[group] then return false, FullMsg(group) end
  local p = { t = t, k = k, r = 0 }
  if AB.ALTS[group] and AB.CountGroup(b, group) - AB.CountAlts(b, group) >= AB.MAIN[group] then p.alt = true end
  table.insert(b.picks, p)
  return true
end

-- removes every pick of one group (a tab of the priority list) from a stage view;
-- returns how many went
function AB.ClearGroup(b, group)
  local n = 0
  for i = table.getn(b.picks), 1, -1 do
    if AB.GROUP[b.picks[i].t] == group then table.remove(b.picks, i); n = n + 1 end
  end
  return n
end

-- a spell in the build becomes one to banish, or back to one to take
function AB.ToggleBan(b, i)
  local p = b.picks[i]
  if not p or p.t ~= "spell" then return false end
  if p.ban then
    if AB.CountGroup(b, "spell") >= AB.MAX.spell then return false, FullMsg("spell") end
    p.ban = nil
  else
    if AB.CountBans(b) >= AB.MAX_BAN then return false, T("Banish list full (%d at most)", AB.MAX_BAN) end
    p.ban = true
    p.r = 0
  end
  return true
end

-- a ring, trinket or amulet becomes an alternative, or a main pick (with the main places
-- full, the last main pick of the group becomes an alternative in its place)
function AB.ToggleAlt(b, i)
  local p = b.picks[i]
  local group = p and AB.GROUP[p.t]
  if not p or not AB.ALTS[group] then return false end
  if p.alt then
    if AB.CountGroup(b, group) - AB.CountAlts(b, group) >= AB.MAIN[group] then
      local idx = AB.TabIndices(b, group)
      for n = table.getn(idx), 1, -1 do
        local q = b.picks[idx[n]]
        if not q.alt and not q.ban then q.alt = true; break end
      end
    end
    p.alt = nil
  else
    if AB.CountAlts(b, group) >= AB.ALTS[group] then return false, T("%d alternatives at most.", AB.ALTS[group]) end
    p.alt = true
  end
  return true
end

local function Kind(p)
  if p.ban then return "b" end
  if p.alt then return "a" end
  return "n"
end

-- The picks one tab of the priority list shows, as indices into b.picks: in priority order,
-- the ones to take first, then alternative amulets, then the spells to banish.
function AB.TabIndices(b, group)
  local lists = { n = {}, a = {}, b = {} }
  for i = 1, table.getn(b.picks) do
    local p = b.picks[i]
    if AB.GROUP[p.t] == group then table.insert(lists[Kind(p)], i) end
  end
  local out = lists.n
  for i = 1, table.getn(lists.a) do table.insert(out, lists.a[i]) end
  for i = 1, table.getn(lists.b) do table.insert(out, lists.b[i]) end
  return out
end

-- moves a pick up (-1) or down (1) past the next pick of its own tab and kind
function AB.MovePick(b, i, dir)
  local p = b.picks[i]
  if not p then return end
  local group, kind = AB.GROUP[p.t], Kind(p)
  local j = i + dir
  while j >= 1 and j <= table.getn(b.picks) do
    local q = b.picks[j]
    if AB.GROUP[q.t] == group and Kind(q) == kind then
      b.picks[i], b.picks[j] = q, p
      return
    end
    j = j + dir
  end
end

-- Another class: in every stage, the old class's spells and legendary amulet are put aside
-- in the build and come back when you switch back; the new class's own come out of it.
-- The jewelry everyone can wear stays. Nothing else changes until the build is saved.
function AB.SetClass(b, cls)
  if b.class == cls then return end
  if type(b.stash) ~= "table" then b.stash = {} end
  local old = {}
  local back = b.stash[cls] or {}
  for vi = 1, table.getn(b.variants) do
    local picks = b.variants[vi].picks
    local mine = {}
    for i = table.getn(picks), 1, -1 do
      local t = picks[i].t
      if t == "spell" or t == "legend" then table.insert(mine, 1, table.remove(picks, i)) end
    end
    old[vi] = mine
    local restore = back[vi] or {}
    for i = 1, table.getn(restore) do table.insert(picks, restore[i]) end
  end
  b.stash[b.class] = old
  b.stash[cls] = nil
  b.class = cls
end

-- ---------------------------------------------------------------- the run, read live
function AB.Phase()
  if not AZS_GetPhase then return nil end
  local ok, ph = pcall(AZS_GetPhase)
  if ok and ph and ph ~= "" then return ph end
  return nil
end

-- The hero's class: the run's, else the last run's, else the character's own.
function AB.CurrentClass()
  if type(AZS_ZONE) == "table" and AZS_ZONE.class and AZS_ZONE.class ~= "" then
    local c = string.lower(AZS_ZONE.class)
    if AB.classIndex[c] then
      if type(ASBuilderDB) == "table" then ASBuilderDB.lastClass = c end
      return c
    end
  end
  if type(ASBuilderDB) == "table" and ASBuilderDB.lastClass then return ASBuilderDB.lastClass end
  local _, c = UnitClass("player")
  if c and AB.classIndex[string.lower(c)] then return string.lower(c) end
  return "warrior"
end

-- spell key -> rank, from the run's spell list
function AB.SpellRanks()
  local t = {}
  if type(AZS_SPELLS) ~= "table" then return t end
  for i = 1, table.getn(AZS_SPELLS) do
    local s = AZS_SPELLS[i]
    if type(s) == "table" and s.key then
      local r = tonumber(s.rank) or 1
      if r < 1 then r = 1 end
      t[s.key] = r
    end
  end
  return t
end

local function IconKey(path)
  if type(path) ~= "string" then return nil end
  local _, _, base = string.find(path, "([^\\/]+)$")
  return string.lower(base or path)
end
AB.IconKey = IconKey

-- The hidden tooltip that reads a worn piece's green lines: their numbers change with
-- every upgrade, which is how a piece's rank is counted (the API has no rank for jewelry).
local scanTip
local function ScanTip()
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "ASBuilderScanTip", UIParent, "GameTooltipTemplate")
  end
  return scanTip
end

local function GreenHex(hex)
  local r = tonumber(string.sub(hex, 3, 4), 16)
  local g = tonumber(string.sub(hex, 5, 6), 16)
  local b = tonumber(string.sub(hex, 7, 8), 16)
  return r and g and b and g > 180 and r < 150 and b < 150
end

-- reads a worn piece's green lines: what it gives right now. Returns a signature of their
-- numbers (it changes with every upgrade) and the lines themselves.
function AB.ScanJewel(slot)
  local tip = ScanTip()
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:ClearLines()
  local ok = pcall(tip.SetInventoryItem, tip, "player", slot)
  if not ok then tip:Hide(); return nil, nil end
  local nums, lines = {}, {}
  for l = 2, (tip:NumLines() or 0) do
    local fs = getglobal("ASBuilderScanTipTextLeft" .. l)
    local raw = fs and fs:GetText()
    if type(raw) == "string" then
      local green = false
      if fs.GetTextColor then
        local r, g, b = fs:GetTextColor()
        green = type(g) == "number" and g > 0.7 and r < 0.6 and b < 0.6
      end
      local _, _, hex = string.find(raw, "|c(%x%x%x%x%x%x%x%x)")
      if hex and GreenHex(hex) then green = true end
      if green then
        local plain = string.gsub(raw, "|c%x%x%x%x%x%x%x%x", "")
        plain = string.gsub(plain, "|r", "")
        for seg in string.gfind(plain .. "\n", "(.-)\n") do
          if seg ~= "" then table.insert(lines, seg) end
        end
        for n in string.gfind(plain, "%d+[%.,]?%d*") do table.insert(nums, n) end
      end
    end
  end
  tip:Hide()
  if table.getn(nums) == 0 then return nil, lines end
  return table.concat(nums, "|"), lines
end

local function SlotName(slot)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
  if not link then return nil, nil end
  local _, _, n = string.find(link, "%[(.-)%]")
  return n, link
end

-- A worn piece starts at rank 1 when it appears; each time its numbers change it goes one
-- up. Another piece in the slot starts again at 1. Kept over a /reload, cleared each run.
function AB.UpdateJewelRanks()
  local jr = ASBuilderDB.run.jr
  for i = 1, table.getn(AB.SLOTS) do
    local slot = AB.SLOTS[i][1]
    local name = SlotName(slot)
    if not name then
      jr[slot] = nil
    else
      local sig, lines = AB.ScanJewel(slot)
      local rec = jr[slot]
      if not rec or rec.name ~= name then
        rec = { name = name, sig = sig, rank = 1 }
        jr[slot] = rec
      elseif sig and sig ~= rec.sig then
        if rec.sig then rec.rank = rec.rank + 1 end
        rec.sig = sig
      end
      if lines and table.getn(lines) > 0 then
        rec.lines = lines
        local eng = (ASBuilder_Names and ASBuilder_Names[name]) or name
        ASBuilderDB.seen[eng] = lines
      end
    end
  end
end

-- what the hero wears in the run's slots
function AB.Worn()
  local list = {}
  local jr = ASBuilderDB.run.jr
  for i = 1, table.getn(AB.SLOTS) do
    local slot, group = AB.SLOTS[i][1], AB.SLOTS[i][2]
    local name, link = SlotName(slot)
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
    if name or tex then
      local eng = name and ((ASBuilder_Names and ASBuilder_Names[name]) or name) or nil
      local _, _, hex = string.find(link or "", "|c(%x%x%x%x%x%x%x%x)")
      local rec = jr[slot]
      table.insert(list, {
        slot = slot, group = group, name = eng, icon = IconKey(tex), tex = tex,
        rarity = hex and LINK_RARITY[string.lower(hex)] or nil,
        rank = (rec and rec.name == name and rec.rank) or 1,
        lines = rec and rec.name == name and rec.lines or nil,
      })
    end
  end
  return list
end

-- A jewelry line boiled down to its number and a short stat name: "Equip: Increases damage
-- by 26%." -> "+26% DMG". The stat is found by keyword (checked in this order); a line in
-- another language falls back to the piece's codex category.
local STAT_KEYS = {
  { "critical strike damage", "CRIT DMG" }, { "critical damage", "CRIT DMG" }, { "crit damage", "CRIT DMG" },
  { "critical", "CRIT" }, { "crit", "CRIT" },
  { "damage over time", "DOT" }, { "tick", "DOT" },
  { "damage reduction", "DR" }, { "damage taken", "DR" }, { "damage you take", "DR" },
  { "all damage dealt heals", "LEECH" }, { "damage dealt heals", "LEECH" }, { "leech", "LEECH" },
  { "each kill heals", "HP/KILL" }, { "per kill", "HP/KILL" }, { "on kill", "HP/KILL" },
  { "health per second", "HP/S" }, { "health every second", "HP/S" }, { "regenerat", "HP/S" },
  { "cast twice", "ECHO" }, { "echo", "ECHO" },
  { "attackers take", "THORNS" }, { "thorns", "THORNS" },
  { "max health", "HP" }, { "maximum health", "HP" },
  { "cooldown", "CD" },
  { "area", "AREA" },
  { "movement speed", "SPD" }, { "move", "SPD" },
  { "pickup", "PICKUP" },
  { "experience", "XP" },
  { "luck", "LUCK" },
  { "gold", "GOLD" },
  { "buff", "BUFF" },
  { "return to life", "LIFE" }, { "lives", "LIFE" },
  { "leap", "LEAP" },
  { "target", "TARGET" },
  { "explode", "EXPLODE" },
  { "damage", "DMG" },
  { "health", "HP" },
}

local function StatKey(text)
  if not text then return nil end
  local low = string.lower(text)
  for i = 1, table.getn(STAT_KEYS) do
    if string.find(low, STAT_KEYS[i][1], 1, true) then return STAT_KEYS[i][2] end
  end
  return nil
end

function AB.ShortStat(line, fallbackCat)
  local text = string.gsub(line or "", "^%s*[^:]*:%s*", function(prefix)
    -- drop a leading "Equip:" (or a spell name before a colon), keep the rest
    return ""
  end)
  if not string.find(text, "%d") then text = line or "" end
  local s, e, num = string.find(text, "(%d+[%.,]?%d*%%?)")
  if not num then return nil end
  local key = StatKey(text) or StatKey(fallbackCat)
  -- the sign: as written, else "-" for cooldowns and "+" for the rest
  local before = string.sub(text, 1, s - 1)
  local sign = "+"
  if string.find(before, "%-%s*$") then sign = "-"
  elseif key == "CD" then sign = "-" end
  num = string.gsub(num, ",", ".")
  if key then return sign .. num .. " " .. key end
  return sign .. num
end

-- What a worn piece gives: its tooltip's green lines when read, else the codex value for
-- its rarity. Returns the short text for the tracker and the full lines for its tooltip.
function AB.WornStats(w, cls)
  local p = AB.WornAsPick(cls, w)
  local info = p and AB.Info(cls, p)
  local tmpl = AB.StatTemplate(info)
  local lines = w.lines or {}
  local short = {}
  for i = 1, table.getn(lines) do
    -- one line may hold two stats ("+4.4% damage reduction, +18% max health")
    for part in string.gfind(lines[i] .. ", ", "(.-), ") do
      local v = AB.ShortStat(part, tmpl)
      if v and table.getn(short) < 2 then table.insert(short, v) end
    end
  end
  return table.concat(short, "  "), lines
end

-- the main value a worn piece gives right now (its first number), or nil before its
-- tooltip was read; a cooldown cut counts as its size (-14% -> 14)
function AB.WornValue(w)
  local line = w and w.lines and w.lines[1]
  if not line then return nil end
  local text = string.gsub(line, "^%s*[^:]*:%s*", "")
  if not string.find(text, "%d") then text = line end
  local _, _, num = string.find(text, "(%d+[%.,]?%d*)")
  return num and tonumber((string.gsub(num, ",", "."))) or nil
end

-- a value target as text: 30 -> "30", 4.5 -> "4.5"
function AB.Num(v)
  if not v then return "" end
  if v == math.floor(v) then return tostring(v) end
  return string.format("%.1f", v)
end

-- a worn piece as a pick, for showing pieces that are not in the build
function AB.WornAsPick(cls, w)
  if not w.name then return nil end
  if w.group == "ring" and AB.ringByName[w.name] then return { t = "ring", k = w.name } end
  if w.group == "trinket" and AB.trinketByName[w.name] then return { t = "trinket", k = w.name } end
  if w.group == "amulet" then
    if AB.amuletByName[w.name] then return { t = "amulet", k = w.name } end
    local c = AB.ClassInfo(cls)
    if c then
      for i = 1, table.getn(c.spells) do
        if c.spells[i].amulet == w.name then return { t = "legend", k = c.spells[i].key } end
      end
    end
  end
  return nil
end

local function MatchWorn(cls, p, w)
  if AB.GROUP[p.t] ~= w.group then return false end
  local info = AB.Info(cls, p)
  if not info then return false end
  if w.name and w.name == info.name then return true end
  if w.icon and info.icon and w.icon == string.lower(info.icon) then return true end
  return false
end

function AB.LiveState()
  local ph = AB.Phase()
  local st = { phase = ph, inRun = ph ~= nil, spells = {}, worn = {} }
  -- before the first step ("ready") the spell list may still hold the last run's spells
  if ph and ph ~= "ready" then st.spells = AB.SpellRanks() end
  if ph then st.worn = AB.Worn() end
  st.endless = ph and type(AZS_RUN) == "table" and tonumber(AZS_RUN.endl) == 1
  return st
end

-- how many pieces of each kind the hero can wear at once
AB.SLOT_CAP = { ring = 2, trinket = 2, amulet = 1 }

-- Where a stage stands right now: each pick's rank, the spell and the piece of jewelry to
-- take or upgrade next, the spells to banish, and what the hero has that the build does not
-- want. Level-up cards are spells and caches offer jewelry, so each gets its own "next".
-- whole: the full build, so a spell planned for a later stage is not called off-build.
function AB.Evaluate(b, live, whole)
  live = live or AB.LiveState()
  local cls = b.class
  local res = { rows = {}, bans = {}, off = {}, done = 0, total = 0, inRun = live.inRun, phase = live.phase }
  local used, inBuild = {}, {}
  if whole and whole.variants then
    for vi = 1, table.getn(whole.variants) do
      local list = whole.variants[vi].picks
      for i = 1, table.getn(list) do if list[i].t == "spell" then inBuild[list[i].k] = true end end
    end
  end
  -- in the planner's tab order: spells, rings, trinkets, amulet, each by its priority
  local order = {}
  local groups = { "spell", "ring", "trinket", "amulet" }
  for g = 1, table.getn(groups) do
    local idx = AB.TabIndices(b, groups[g])
    for j = 1, table.getn(idx) do table.insert(order, idx[j]) end
  end
  for o = 1, table.getn(order) do
    local i = order[o]
    local p = b.picks[i]
    if p.ban then
      inBuild[p.k] = true
      table.insert(res.bans, { pick = p, index = i, info = AB.Info(cls, p), known = live.spells[p.k] })
    else
      local row = { pick = p, index = i, info = AB.Info(cls, p), target = p.r or 0 }
      if p.t == "spell" then
        row.rank = live.spells[p.k]
        inBuild[p.k] = true
      else
        for w = 1, table.getn(live.worn) do
          if not used[w] and MatchWorn(cls, p, live.worn[w]) then
            used[w] = true
            row.rank = live.worn[w].rank
            row.rarity = live.worn[w].rarity
            row.worn = live.worn[w]
            row.value = AB.WornValue(live.worn[w])
            break
          end
        end
      end
      row.owned = row.rank ~= nil
      if p.t == "spell" then
        row.met = row.owned and (row.target == 0 or row.rank >= row.target)
        row.full = row.owned and row.target > 0 and row.rank >= row.target
      else
        -- jewelry: the value it gives against the value it should reach
        local reached = row.value ~= nil and row.value >= row.target
        row.met = row.owned and (row.target == 0 or reached)
        row.full = row.owned and row.target > 0 and reached
      end
      table.insert(res.rows, row)
    end
  end
  -- a group with more picks than slots (alternatives): the worn picks, then the main ones,
  -- then the alternatives fill its slots and stand for it; the others are "extra" and,
  -- once every slot of the group is worn, hidden
  local jgroups = { "ring", "trinket", "amulet" }
  for g = 1, table.getn(jgroups) do
    local list = {}
    for i = 1, table.getn(res.rows) do
      if AB.GROUP[res.rows[i].pick.t] == jgroups[g] then table.insert(list, res.rows[i]) end
    end
    local cap = AB.SLOT_CAP[jgroups[g]]
    if table.getn(list) > cap then
      local rep, n, worn = {}, 0, 0
      for pass = 1, 3 do
        for i = 1, table.getn(list) do
          local r = list[i]
          local want
          if pass == 1 then want = r.owned
          elseif pass == 2 then want = not r.owned and not r.pick.alt
          else want = not r.owned and r.pick.alt end
          if want and n < cap then
            rep[r] = true
            n = n + 1
            if pass == 1 then worn = worn + 1 end
          end
        end
      end
      for i = 1, table.getn(list) do
        if not rep[list[i]] then list[i].extra = true; list[i].hide = worn >= cap end
      end
    end
  end
  -- a slot group filled with other pieces: its missing picks cannot be taken now
  local wornCount = {}
  for w = 1, table.getn(live.worn) do
    local g = live.worn[w].group
    wornCount[g] = (wornCount[g] or 0) + 1
  end
  for i = 1, table.getn(res.rows) do
    local r = res.rows[i]
    local g = AB.GROUP[r.pick.t]
    if g ~= "spell" and not r.owned and (wornCount[g] or 0) >= AB.SLOT_CAP[g] then r.blocked = true end
    if not r.extra then
      res.total = res.total + 1
      if r.met then res.done = res.done + 1 end
    end
  end
  -- complete: every pick that counts is at its target, or cannot be taken now
  res.complete = res.total > 0
  for i = 1, table.getn(res.rows) do
    local r = res.rows[i]
    if not r.extra and not r.met and not r.blocked then res.complete = false end
  end
  -- worn pieces the build has no place for
  res.wornOff = {}
  for w = 1, table.getn(live.worn) do
    if not used[w] then table.insert(res.wornOff, live.worn[w]) end
  end
  if live.inRun then
    -- the next step in each kind: a missing pick first (when the build fills its slots
    -- first), else the first pick in priority order still below its target
    local function NextOf(isSpell)
      if b.fill ~= false then
        for i = 1, table.getn(res.rows) do
          local r = res.rows[i]
          if (r.pick.t == "spell") == isSpell and not r.extra and not r.owned and not r.blocked then return r end
        end
      end
      for i = 1, table.getn(res.rows) do
        local r = res.rows[i]
        if (r.pick.t == "spell") == isSpell and not r.extra and not r.blocked and (not r.owned or not r.full) then return r end
      end
      return nil
    end
    res.nextSpell = NextOf(true)
    res.nextJewel = NextOf(false)
    res.next = res.nextSpell or res.nextJewel
    -- off-build spells (only when the build has something in it)
    local c = AB.ClassInfo(cls)
    if c and (table.getn(b.picks) > 0 or (whole and AB.HasPicks(whole))) then
      for j = 1, table.getn(c.spells) do
        local s = c.spells[j]
        if live.spells[s.key] and not inBuild[s.key] then
          table.insert(res.off, { pick = { t = "spell", k = s.key }, rank = live.spells[s.key], icon = s.icon })
        end
      end
    end
  end
  return res
end

function AB.HasPicks(b)
  for vi = 1, table.getn(b.variants or {}) do
    if table.getn(b.variants[vi].picks) > 0 then return true end
  end
  return false
end

-- The stage the tracker follows: the first stage (from the one reached so far this run)
-- that is not complete yet; empty stages are skipped. The Endless stage takes over once the
-- run goes endless. A stage picked by hand on the tracker stays until changed.
-- Returns the stage's index and whether it was picked by hand.
function AB.StageOf(b, live)
  local n = table.getn(b.variants)
  local function Has(i) return b.variants[i] and table.getn(b.variants[i].picks) > 0 end
  local first = 1
  for i = 1, n do if Has(i) then first = i; break end end
  if not live.inRun then return first, false end
  local run = ASBuilderDB.run
  local pin = run.pin[b.id]
  if pin and Has(pin) then return pin, true end
  if live.endless and Has(n) then run.stage[b.id] = n; return n, false end
  local start = run.stage[b.id] or first
  local idx
  for i = start, n do
    if Has(i) then
      idx = i
      if not AB.Evaluate(AB.View(b, i), live).complete then break end
    end
  end
  if not idx then
    -- nothing from the reached stage on: the last stage that has picks
    for i = n, 1, -1 do if Has(i) then idx = i; break end end
  end
  idx = idx or first
  run.stage[b.id] = idx
  return idx, false
end

-- the tracker's stage line: the next stage that has picks, by hand; after the last one
-- the stage goes back to following the build on its own
function AB.StepStage(b, live)
  local n = table.getn(b.variants)
  local cur = AB.StageOf(b, live)
  local run = ASBuilderDB.run
  local wasPinned = run.pin[b.id] ~= nil
  for i = cur + 1, n do
    if table.getn(b.variants[i].picks) > 0 then run.pin[b.id] = i; return i end
  end
  if wasPinned then
    run.pin[b.id] = nil
  else
    for i = 1, n do
      if table.getn(b.variants[i].picks) > 0 and i ~= cur then run.pin[b.id] = i; return i end
    end
  end
  run.stage[b.id] = nil
  return nil
end

-- A new run begins when the game is "ready" again, plays again after a run ended, or its
-- clock starts over. A /reload in the middle of a run keeps the jewelry ranks and stages.
local function NewRun()
  ASBuilderDB.run.jr = {}
  ASBuilderDB.run.stage = {}
  ASBuilderDB.run.pin = {}
  ASBuilderDB.run.banished = {}
end

local lastPhase, runOver = nil, false
function AB.WatchRun()
  local ph = AB.Phase()
  if ph ~= lastPhase then
    lastPhase = ph
    if ph == "dead" or ph == "victory" then
      runOver = true
    elseif ph == "ready" or (runOver and ph == "playing") then
      runOver = false
      NewRun()
    end
  end
  if ph and AZS_GetRunTime then
    local ok, t = pcall(AZS_GetRunTime)
    t = ok and tonumber(t) or nil
    if t then
      if ASBuilderDB.run.t and t + 5 < ASBuilderDB.run.t then NewRun() end
      ASBuilderDB.run.t = t
    end
  end
end

-- ---------------------------------------------------------------- import / export
-- A code is "ASB1:" + a 4-character checksum + the build, base64 (URL-safe alphabet, so it
-- has no "|" or spaces and survives chat, Discord and forums).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64I = {}
for i = 1, 64 do B64I[string.sub(B64, i, i)] = i - 1 end
local function C(n) return string.sub(B64, n + 1, n + 1) end

local function Enc(s)
  local out, len, i = {}, string.len(s), 1
  while i <= len do
    local a = string.byte(s, i)
    local b = (i + 1 <= len) and string.byte(s, i + 1) or nil
    local c = (i + 2 <= len) and string.byte(s, i + 2) or nil
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    table.insert(out, C(math.floor(n / 262144)))
    table.insert(out, C(math.mod(math.floor(n / 4096), 64)))
    if b then table.insert(out, C(math.mod(math.floor(n / 64), 64))) end
    if c then table.insert(out, C(math.mod(n, 64))) end
    i = i + 3
  end
  return table.concat(out)
end

local function Dec(s)
  local out, len, i = {}, string.len(s), 1
  while i <= len do
    local v, cnt = {}, 0
    for k = 0, 3 do
      if i + k <= len then
        local x = B64I[string.sub(s, i + k, i + k)]
        if not x then return nil end
        cnt = cnt + 1
        v[cnt] = x
      end
    end
    if cnt < 2 then return nil end
    local n = v[1] * 262144 + v[2] * 4096 + (v[3] or 0) * 64 + (v[4] or 0)
    table.insert(out, string.char(math.floor(n / 65536)))
    if cnt >= 3 then table.insert(out, string.char(math.mod(math.floor(n / 256), 256))) end
    if cnt >= 4 then table.insert(out, string.char(math.mod(n, 256))) end
    i = i + 4
  end
  return table.concat(out)
end

local function Sum(s)
  local a, b = 1, 0
  for i = 1, string.len(s) do
    a = math.mod(a + string.byte(s, i), 65521)
    b = math.mod(b + a, 65521)
  end
  local n = math.mod(b, 4096) * 4096 + math.mod(a, 4096)
  return C(math.floor(n / 262144)) .. C(math.mod(math.floor(n / 4096), 64)) .. C(math.mod(math.floor(n / 64), 64)) .. C(math.mod(n, 64))
end

-- one letter per kind of pick; "x" is a spell to banish, "b"/"c"/"q"/"u" an alternative
local LETTER = { spell = "s", ring = "r", trinket = "t", amulet = "a", legend = "l" }
local ALT_LETTER = { amulet = "b", legend = "c", ring = "q", trinket = "u" }
local KIND = { s = "spell", r = "ring", t = "trinket", a = "amulet", l = "legend", x = "spell", b = "amulet", c = "legend", q = "ring", u = "trinket" }
local IS_ALT = { b = true, c = true, q = true, u = true }

local function Esc(s)
  s = string.gsub(s or "", "\\", "\\\\")
  s = string.gsub(s, "\n", "\\n")
  return s
end
local function Unesc(s)
  return (string.gsub(s or "", "\\(.)", function(c) if c == "n" then return "\n" end return c end))
end

local function PicksCode(list)
  local parts = {}
  for i = 1, table.getn(list) do
    local p = list[i]
    local l = LETTER[p.t]
    if p.ban then l = "x" elseif p.alt then l = ALT_LETTER[p.t] or l end
    table.insert(parts, l .. ":" .. p.k .. ":" .. AB.Num(p.r or 0))
  end
  return table.concat(parts, ";")
end

-- ---- compact codes (ASB2): bytes, base64. Each distinct pick is written once (kind + key) and
-- every stage points at it with a small number, so repeating a spell in four stages costs
-- a byte or two; default stage names are left out. Keys, not names, so a code stays valid
-- in every language and across data updates that add new spells or jewelry.
local KIND_ID = { spell = 0, ring = 1, trinket = 2, amulet = 3, legend = 4 }
local KIND_OF = { [0] = "spell", "ring", "trinket", "amulet", "legend" }
local BY_NAME = { ring = AB.ringByName, trinket = AB.trinketByName, amulet = AB.amuletByName }
local NAME_OF = { ring = {}, trinket = {}, amulet = {} }
for i = 1, table.getn(D.rings) do NAME_OF.ring[D.rings[i].key] = D.rings[i].name end
for i = 1, table.getn(D.trinkets) do NAME_OF.trinket[D.trinkets[i].key] = D.trinkets[i].name end
for i = 1, table.getn(D.amulets) do NAME_OF.amulet[D.amulets[i].key] = D.amulets[i].name end

local function PutVar(out, n)
  n = math.floor(n)
  if n < 0 then n = 0 end
  while n >= 128 do
    table.insert(out, string.char(128 + math.mod(n, 128)))
    n = math.floor(n / 128)
  end
  table.insert(out, string.char(n))
end
local function PutStr(out, s)
  s = s or ""
  PutVar(out, string.len(s))
  table.insert(out, s)
end
-- a reader over a byte string; every read returns nil once the data runs out
local function Reader(s)
  local r = { s = s, i = 1, n = string.len(s) }
  function r:Var()
    local v, mul = 0, 1
    while true do
      if self.i > self.n or mul > 2097152 then return nil end
      local c = string.byte(self.s, self.i)
      self.i = self.i + 1
      v = v + math.mod(c, 128) * mul
      if c < 128 then return v end
      mul = mul * 128
    end
  end
  function r:Byte()
    if self.i > self.n then return nil end
    self.i = self.i + 1
    return string.byte(self.s, self.i - 1)
  end
  function r:Str()
    local len = self:Var()
    if not len or self.i + len - 1 > self.n then return nil end
    local v = string.sub(self.s, self.i, self.i + len - 1)
    self.i = self.i + len
    return v
  end
  return r
end
-- a 2-character checksum (12 bits) of the base64 text
local function Sum2(s)
  local a, b = 1, 0
  for i = 1, string.len(s) do
    a = math.mod(a + string.byte(s, i), 251)
    b = math.mod(b + a, 251)
  end
  local n = math.mod(a * 251 + b, 4096)
  return C(math.floor(n / 64)) .. C(math.mod(n, 64))
end

-- An item is written as its place in the game's list plus a 2-byte fingerprint of its key:
-- if a data update moves it, the fingerprint finds it again in the same list.
local function KeyHash(key)
  local h = 7
  for i = 1, string.len(key) do h = math.mod(h * 31 + string.byte(key, i), 65536) end
  return h
end
-- the list a kind of pick lives in (spells and legendary amulets: the class's spells)
local function KindList(kind, cls)
  if kind == "ring" then return D.rings end
  if kind == "trinket" then return D.trinkets end
  if kind == "amulet" then return D.amulets end
  local c = AB.ClassInfo(cls)
  return c and c.spells or {}
end
local function ListIndex(list, key)
  for i = 1, table.getn(list) do if list[i].key == key then return i end end
  return nil
end
local function FindByHash(list, pos, hash)
  if list[pos] and KeyHash(list[pos].key) == hash then return list[pos] end
  local found
  for i = 1, table.getn(list) do
    if KeyHash(list[i].key) == hash then
      if found then return nil end   -- two candidates: do not guess
      found = list[i]
    end
  end
  return found
end

local function PickKey(p)
  if BY_NAME[p.t] then
    local d = BY_NAME[p.t][p.k]
    return d and d.key or p.k
  end
  return p.k
end

function AB.Export(b)
  local out = { string.char(4) }
  PutStr(out, b.class)
  table.insert(out, string.char((b.fill == false) and 0 or 1))
  PutStr(out, (string.gsub(b.name or "", "[\r\n]", " ")))
  -- the distinct picks, in order of first use
  local items, index = {}, {}
  for i = 1, table.getn(b.variants) do
    local picks = b.variants[i].picks
    for j = 1, table.getn(picks) do
      local p = picks[j]
      local id = p.t .. "\1" .. PickKey(p)
      if not index[id] then
        table.insert(items, p)
        index[id] = table.getn(items)
      end
    end
  end
  PutVar(out, table.getn(items))
  for i = 1, table.getn(items) do
    local it = items[i]
    local key = PickKey(it)
    local pos = ListIndex(KindList(it.t, b.class), key) or 0
    PutVar(out, pos * 8 + (KIND_ID[it.t] or 0))
    local h = KeyHash(key)
    table.insert(out, string.char(math.floor(h / 256), math.mod(h, 256)))
  end
  table.insert(out, string.char(table.getn(b.variants)))
  for i = 1, table.getn(b.variants) do
    local v = b.variants[i]
    local vname = string.gsub(v.name or "", "[\r\n]", " ")
    PutStr(out, (vname == AB.STAGE_NAMES[i]) and "" or vname)
    PutVar(out, table.getn(v.picks))
    for j = 1, table.getn(v.picks) do
      local p = v.picks[j]
      local flag = (p.ban and 1) or (p.alt and 2) or 0
      PutVar(out, (index[p.t .. "\1" .. PickKey(p)] - 1) * 4 + flag)
      PutVar(out, math.floor((p.r or 0) * 10 + 0.5))
    end
    PutStr(out, v.notes or "")
  end
  -- the image link comes last: older versions stop reading before it
  if b.link and b.link ~= "" then PutStr(out, b.link) end
  local data = Enc(table.concat(out))
  return "ASB2:" .. Sum2(data) .. data
end

-- reads an ASB2 code into a build; returns the build and how many picks were skipped
local function ImportV4(data)
  local bad = T("The code is damaged or incomplete.")
  local body = Dec(data)
  if not body then return nil, bad end
  local r = Reader(body)
  if r:Var() ~= 4 then return nil, bad end
  local cls = r:Str()
  if not cls then return nil, bad end
  if not AB.classIndex[cls] then return nil, T("Unknown class in the code.") end
  local fill = r:Var()
  local name = r:Str()
  local nItems = r:Var()
  if not fill or not name or not nItems then return nil, bad end
  local items = {}
  for i = 1, nItems do
    local ref, hi, lo = r:Var(), r:Byte(), r:Byte()
    local hash = hi and lo and hi * 256 + lo
    if not ref or not hash then return nil, bad end
    local kind = KIND_OF[math.mod(ref, 8)]
    local d = kind and FindByHash(KindList(kind, cls), math.floor(ref / 8), hash)
    if d then
      items[i] = { t = kind, k = (NAME_OF[kind] and d.name) or d.key }
    else
      items[i] = {}   -- not in this version of the game: its picks are skipped
    end
  end
  local b = { class = cls, fill = fill ~= 0, name = name, variants = AB.NewVariants() }
  if b.name == "" then b.name = T("New build") end
  local nStages = r:Var()
  if not nStages then return nil, bad end
  local skipped = 0
  for i = 1, nStages do
    local vname, count = r:Str(), r:Var()
    if not vname or not count then return nil, bad end
    local v = b.variants[i]
    local view = v and { class = cls, picks = v.picks }
    for j = 1, count do
      local ref, target = r:Var(), r:Var()
      if not ref or not target then return nil, bad end
      local it = items[math.floor(ref / 4) + 1]
      local flag = math.mod(ref, 4)
      if view and it and it.t then
        local p = { t = it.t, k = it.k, r = target / 10 }
        if flag == 1 then p.ban, p.r = true, 0 elseif flag == 2 then p.alt = true end
        local room = AB.Fit(view, p)
        if AB.Info(cls, p) and not AB.FindPick(view, p.t, p.k) and room then
          table.insert(view.picks, p)
        else
          skipped = skipped + 1
        end
      elseif view then
        skipped = skipped + 1
      end
    end
    local notes = r:Str()
    if not notes then return nil, bad end
    if v then
      if vname ~= "" then v.name = vname end
      v.notes = notes
    end
  end
  b.link = r:Str() or ""
  return b, skipped
end

-- Version 3 (2 with value targets for jewelry): the class, the setting, the name and every stage (name, picks, notes).
function AB.ExportV3(b)
  local name = string.gsub(b.name or "", "[\r\n]", " ")
  local lines = { "3", b.class, (b.fill == false) and "0" or "1", name, tostring(table.getn(b.variants)) }
  for i = 1, table.getn(b.variants) do
    local v = b.variants[i]
    table.insert(lines, (string.gsub(v.name or "", "[\r\n]", " ")))
    table.insert(lines, PicksCode(v.picks))
    table.insert(lines, Esc(v.notes))
  end
  local data = Enc(table.concat(lines, "\n"))
  return "ASB1:" .. Sum(data) .. data
end

-- reads one stage's picks into a view; returns how many were skipped
local function ReadPicks(view, text)
  local skipped = 0
  for entry in string.gfind(text or "", "[^;]+") do
    local _, _, l, k, r = string.find(entry, "^(%a):(.-):([%d%.]+)$")
    local t = l and KIND[l]
    local p = t and { t = t, k = k, r = tonumber(r) or 0 }
    if p and l == "x" then p.ban = true; p.r = 0 end
    if p and IS_ALT[l] then p.alt = true end
    local room = p and AB.Fit(view, p)
    if p and AB.Info(view.class, p) and not AB.FindPick(view, t, k) and room then
      table.insert(view.picks, p)
    else
      skipped = skipped + 1
    end
  end
  return skipped
end

-- Reads a code. Returns a build table (not yet saved) and how many entries were skipped,
-- or nil and the reason. Codes from before stages (version 1) fill the first stage.
function AB.Import(code)
  local bad = T("The code is damaged or incomplete.")
  code = string.gsub(code or "", "%s", "")
  local _, _, sum2, data2 = string.find(code, "^ASB2:(..)(.+)$")
  if data2 then
    if Sum2(data2) ~= sum2 then return nil, bad end
    return ImportV4(data2)
  end
  local _, _, sum, data = string.find(code, "^ASB1:(....)(.+)$")
  if not data then return nil, T("This is not an ASBuilder code.") end
  if Sum(data) ~= sum then return nil, bad end
  local body = Dec(data)
  if not body then return nil, bad end
  local lines = {}
  for line in string.gfind(body .. "\n", "(.-)\n") do table.insert(lines, line) end
  local version = lines[1]
  if version ~= "1" and version ~= "2" and version ~= "3" then return nil, bad end
  local cls = lines[2]
  if not AB.classIndex[cls or ""] then return nil, T("Unknown class in the code.") end
  local b = { class = cls, fill = lines[3] ~= "0", name = lines[4], variants = AB.NewVariants() }
  if not b.name or b.name == "" then b.name = T("New build") end
  local skipped = 0
  if version == "1" then
    if not lines[5] then return nil, bad end
    -- version 1 kept its notes as plain lines after the picks
    local notes = {}
    for i = 6, table.getn(lines) do table.insert(notes, lines[i]) end
    local v = b.variants[1]
    v.notes = table.concat(notes, "\n")
    skipped = ReadPicks({ class = cls, picks = v.picks }, lines[5])
  else
    local n = tonumber(lines[5])
    if not n or table.getn(lines) < 5 + n * 3 then return nil, bad end
    for i = 1, n do
      local v = b.variants[i]
      if v then
        local base = 5 + (i - 1) * 3
        if lines[base + 1] ~= "" then v.name = lines[base + 1] end
        skipped = skipped + ReadPicks({ class = cls, picks = v.picks }, lines[base + 2])
        v.notes = Unesc(lines[base + 3])
      end
    end
  end
  -- codes before version 3 held ranks for jewelry, not values
  if version ~= "3" then
    for i = 1, table.getn(b.variants) do AB.ClearJewelTargets(b.variants[i].picks) end
  end
  return b, skipped
end

-- Everything the hero has in this run as a new build: the class's spells and the worn
-- jewelry, each with its current rank as the target, in the first stage.
function AB.CaptureCurrent()
  local live = AB.LiveState()
  if not live.inRun or live.phase == "ready" then
    return nil, T("Start a run first: there is nothing to transfer yet.")
  end
  local cls = AB.CurrentClass()
  local c = AB.ClassInfo(cls)
  local zone = type(AZS_ZONE) == "table" and AZS_ZONE.zname or nil
  local name = (c and c.name or cls) .. ((zone and zone ~= "") and (" - " .. zone) or "")
  local b = { class = cls, name = name, fill = true, variants = AB.NewVariants() }
  local view = { class = cls, picks = b.variants[1].picks }
  local count = 0
  if type(AZS_SPELLS) == "table" then
    for i = 1, table.getn(AZS_SPELLS) do
      local s = AZS_SPELLS[i]
      if type(s) == "table" and AB.spellIndex[cls] and AB.spellIndex[cls][s.key]
        and not AB.FindPick(view, "spell", s.key) and AB.CountGroup(view, "spell") < AB.MAX.spell then
        table.insert(view.picks, { t = "spell", k = s.key, r = live.spells[s.key] or 1 })
        count = count + 1
      end
    end
  end
  for w = 1, table.getn(live.worn) do
    local wp = AB.WornAsPick(cls, live.worn[w])
    local group = wp and AB.GROUP[wp.t]
    if wp and not AB.FindPick(view, wp.t, wp.k) and AB.CountGroup(view, group) < AB.MAX[group] then
      local v = AB.WornValue(live.worn[w])
      table.insert(view.picks, { t = wp.t, k = wp.k, r = v and math.floor(v * 10 + 0.5) / 10 or 0 })
      count = count + 1
    end
  end
  if count == 0 then return nil, T("Nothing to transfer: no spells or jewelry yet.") end
  return AB.AddBuild(b)
end

-- ---------------------------------------------------------------- events and the clock
local core = CreateFrame("Frame", "ASBuilderCore", UIParent)
core:RegisterEvent("VARIABLES_LOADED")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("UNIT_INVENTORY_CHANGED")
core:RegisterEvent("PLAYER_LOGOUT")
core:SetScript("OnEvent", function()
  if event == "PLAYER_LOGOUT" then
    if type(ASBuilderDB) == "table" then ASBuilderDB.session = "closed" end
    return
  end
  if event == "VARIABLES_LOADED" then
    AB.InitDB()
    AB.ready = true
    if AB.OnReady then AB.OnReady() end
  end
  if AB.ready and AB.RefreshTracker then AB.RefreshTracker() end
end)

local tick, scan = 0, 0
core:SetScript("OnUpdate", function()
  if not AB.ready then return end
  tick = tick + arg1
  scan = scan + arg1
  if tick < 0.5 then return end
  tick = 0
  AB.WatchRun()
  if scan >= 1 then
    scan = 0
    local ph = AB.Phase()
    if ph == "playing" or ph == "choosing" or ph == "paused" then AB.UpdateJewelRanks() end
  end
  if AB.RefreshTracker then AB.RefreshTracker() end
end)

-- ---------------------------------------------------------------- slash commands
SLASH_ASBUILDER1 = "/asb"
SLASH_ASBUILDER2 = "/asbuilder"
SlashCmdList["ASBUILDER"] = function(msg)
  if not AB.ready then return end
  msg = string.lower(msg or "")
  local _, _, cmd, rest = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd or ""
  local db = ASBuilderDB
  if cmd == "" then
    if AB.TogglePlanner then AB.TogglePlanner() end
  elseif cmd == "tracker" then
    local nxt = { run = "always", always = "hidden", hidden = "run" }
    db.tracker.mode = nxt[db.tracker.mode] or "run"
    local say = { run = "Tracker: shown in runs.", always = "Tracker: always shown.", hidden = "Tracker: hidden." }
    AB.Print(T(say[db.tracker.mode]))
  elseif cmd == "lock" then
    db.tracker.locked = not db.tracker.locked
    AB.Print(T(db.tracker.locked and "Tracker locked." or "Tracker unlocked."))
  elseif cmd == "scale" then
    local s = tonumber(rest)
    if s and s >= 0.5 and s <= 2 then db.tracker.scale = s end
    if AB.ApplyTrackerLayout then AB.ApplyTrackerLayout() end
  elseif cmd == "reset" then
    db.tracker.point = nil
    db.tracker.scale = 1
    if AB.ApplyTrackerLayout then AB.ApplyTrackerLayout() end
    AB.Print(T("Tracker moved back to its first place."))
  else
    AB.Print(T("Commands:"))
    AB.Print(T("/asb - open or close the planner"))
    AB.Print(T("/asb tracker - in runs / always / hidden"))
    AB.Print(T("/asb lock - lock or unlock the tracker"))
    AB.Print(T("/asb scale 0.9 - tracker size"))
    AB.Print(T("/asb reset - tracker back to its first place"))
  end
  if AB.RefreshTracker then AB.RefreshTracker() end
end
