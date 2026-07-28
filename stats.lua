--[[
    Daseeki Armory — character statistics.

    A full read-only stat breakdown (CharacterStatsClassic-parity: which stats and
    how they group), rendered two ways from ONE data layer:
      * a "Stats" section in the Armory hub (DaseekiUI flow), and
      * an optional compact panel attached to the right of the character window.

    ALL values come from the game's own stat APIs (verified against the 1.15.9 API
    catalog — see the module header table in the build report). No numbers are
    scraped, cached, or copied from any other addon; this is fresh code.

    Live-updates on the stat/rating/damage-mod event family (coalesced to one refresh
    per frame-ish via a dirty flag). Layout is token-driven per DREW_UI_STYLE:
    two-column compact stat blocks, labeled, hugging their natural width.
--]]

local _, Addon = ...

-- ── Formatting ────────────────────────────────────────────────────────────────
local function N(v)   v = v or 0; return tostring(math.floor(v + 0.5)) end
local function PCT(v) return string.format("%.2f%%", v or 0) end

-- ── Compute helpers (game APIs only) ──────────────────────────────────────────
local function stat(i)  return N(select(2, UnitStat("player", i))) end          -- effectiveStat
local function armor()  return N(select(2, UnitArmor("player"))) end            -- effectiveArmor

local function meleeAP()
    local base, pos, neg = UnitAttackPower("player")
    return N((base or 0) + (pos or 0) + (neg or 0))
end
local function rangedAP()
    local base, pos, neg = UnitRangedAttackPower("player")
    return N((base or 0) + (pos or 0) + (neg or 0))
end

-- Character-sheet damage formula: (base + physBonusPos + physBonusNeg) * percentMod.
local function meleeDamage()
    local minD, maxD, _, _, posB, negB, pct = UnitDamage("player")
    pct = pct or 1
    local lo = ((minD or 0) + (posB or 0) + (negB or 0)) * pct
    local hi = ((maxD or 0) + (posB or 0) + (negB or 0)) * pct
    return string.format("%d-%d", math.floor(lo + 0.5), math.floor(hi + 0.5))
end
local function meleeSpeed()
    local m, o = UnitAttackSpeed("player")
    if o and o > 0 then return string.format("%.2f / %.2f", m or 0, o) end
    return string.format("%.2f", m or 0)
end

local function rangedDamage()
    local _, minD, maxD, posB, negB, pct = UnitRangedDamage("player")
    pct = pct or 1
    local lo = ((minD or 0) + (posB or 0) + (negB or 0)) * pct
    local hi = ((maxD or 0) + (posB or 0) + (negB or 0)) * pct
    return string.format("%d-%d", math.floor(lo + 0.5), math.floor(hi + 0.5))
end
local function rangedSpeed()
    local speed = UnitRangedDamage("player")
    return string.format("%.2f", speed or 0)
end

-- Spell schools are 1-based: 1 Physical, 2 Holy, 3 Fire, 4 Nature, 5 Frost, 6 Shadow,
-- 7 Arcane (mirrors the game's SPELL_SCHOOL enum). GetSpellBonusDamage / GetSpellCritChance
-- take that index; the Spell block lists schools 2..7 (physical isn't a spell school).
local SPELL_SCHOOLS = { 2, 3, 4, 5, 6, 7 }
local function bonusDmg(school) return function() return N(GetSpellBonusDamage(school)) end end
local function maxSpellCrit()
    local best = 0
    for _, s in ipairs(SPELL_SCHOOLS) do
        local c = GetSpellCritChance(s) or 0
        if c > best then best = c end
    end
    return best
end
local function manaRegenBase()
    local base = GetManaRegen()          -- mana per second
    return N((base or 0) * 5)            -- MP5 while not casting
end
local function manaRegenCasting()
    local _, casting = GetManaRegen()
    return N((casting or 0) * 5)         -- MP5 while casting
end

local function defenseVal()
    local base, mod = UnitDefense("player")
    return N((base or 0) + (mod or 0))
end
-- Resistance indices: 0 Armor, 1 Holy (never itemized), 2 Fire, 3 Nature, 4 Frost,
-- 5 Shadow, 6 Arcane. select(2) is the effective value shown on the sheet.
local function resist(i) return function() return N(select(2, UnitResistance("player", i))) end end

-- ── Stat block specification (the shared data layer) ──────────────────────────
-- { title, cells = { { label, computeFn }, ... } }. Labels are static; each
-- computeFn returns the live display string. Both renderers register every cell's
-- value fontstring against a refresh registry so a single loop updates all of them.
local SPECS = {
    { title = "Attributes", cells = {
        { "Strength",  function() return stat(1) end },
        { "Agility",   function() return stat(2) end },
        { "Stamina",   function() return stat(3) end },
        { "Intellect", function() return stat(4) end },
        { "Spirit",    function() return stat(5) end },
        { "Armor",     armor },
        { "Health",    function() return N(UnitHealthMax("player")) end },
        { "Mana",      function() return N(UnitPowerMax("player", 0)) end },
    }},
    { title = "Melee", cells = {
        { "Attack Power", meleeAP },
        { "Damage",       meleeDamage },
        { "Speed",        meleeSpeed },
        { "Hit",          function() return PCT(GetHitModifier and GetHitModifier() or 0) end },
        { "Crit",         function() return PCT(GetCritChance()) end },
    }},
    { title = "Ranged", cells = {
        { "Attack Power", rangedAP },
        { "Damage",       rangedDamage },
        { "Speed",        rangedSpeed },
        { "Crit",         function() return PCT(GetRangedCritChance()) end },
    }},
    { title = "Spell", cells = {
        { "Holy",        bonusDmg(2) },
        { "Fire",        bonusDmg(3) },
        { "Nature",      bonusDmg(4) },
        { "Frost",       bonusDmg(5) },
        { "Shadow",      bonusDmg(6) },
        { "Arcane",      bonusDmg(7) },
        { "Healing",     function() return N(GetSpellBonusHealing()) end },
        { "Spell Hit",   function() return PCT(GetSpellHitModifier and GetSpellHitModifier() or 0) end },
        { "Spell Crit",  function() return PCT(maxSpellCrit()) end },
        { "Mana Regen",  manaRegenBase },
        { "MP5 Casting", manaRegenCasting },
        { "Spell Pen",   function() return N(GetSpellPenetration and GetSpellPenetration() or 0) end },
    }},
    { title = "Defense", cells = {
        { "Armor",       armor },
        { "Defense",     defenseVal },
        { "Dodge",       function() return PCT(GetDodgeChance()) end },
        { "Parry",       function() return PCT(GetParryChance()) end },
        { "Block",       function() return PCT(GetBlockChance()) end },
        { "Block Value", function() return N(GetShieldBlock and GetShieldBlock() or 0) end },
    }},
    { title = "Resistances", cells = {
        { "Fire",   resist(2) },
        { "Nature", resist(3) },
        { "Frost",  resist(4) },
        { "Shadow", resist(5) },
        { "Arcane", resist(6) },
    }},
}

function Addon:StatBlockSpecs() return SPECS end

-- ── Refresh registries ────────────────────────────────────────────────────────
local function refreshRegistry(reg)
    if not reg then return end
    for _, e in ipairs(reg) do
        local ok, s = pcall(e.fn)
        e.fs:SetText((ok and s) or "—")
    end
end

function Addon:RefreshStatsTab()
    refreshRegistry(Addon._statCellsHub)
end
function Addon:RefreshStatsPanel()
    if Addon._statsPanel and Addon._statsPanel:IsShown() then
        refreshRegistry(Addon._statCellsPanel)
    end
end

-- Coalesce a burst of stat events into one refresh next frame-ish.
function Addon:MarkStatsDirty()
    if Addon._statsDirty then return end
    Addon._statsDirty = true
    C_Timer.After(0.1, function()
        Addon._statsDirty = false
        Addon:RefreshStatsTab()
        Addon:RefreshStatsPanel()
    end)
end

-- ── Renderer: one stat block host (title + hairline + two-column cell grid) ────
-- Registers each value fontstring into `registry`. Returns a frame carrying an
-- arrange(width) -> height for both the flow pane and the standalone panel.
local TITLE_H = 24    -- serif title (18) + gap to the hairline/first row
local CELL_H  = 16
local CELL_PAD = 6

function Addon:_MakeStatHost(parent, blk, registry)
    local UI = DaseekiUI
    local host = CreateFrame("Frame", nil, parent)

    local title = host:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(UI.fonts.header)
    title:SetJustifyH("LEFT")
    title:SetText(blk.title)

    local rule = host:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    UI.Skin(rule, function(self) self:SetColorTexture(UI.Color("borderLite")) end)

    host._cells = {}
    for _, c in ipairs(blk.cells) do
        local lbl = host:CreateFontString(nil, "OVERLAY")
        lbl:SetFontObject(UI.fonts.muted); lbl:SetJustifyH("LEFT"); lbl:SetText(c[1])
        local val = host:CreateFontString(nil, "OVERLAY")
        val:SetFontObject(UI.fonts.body); val:SetJustifyH("RIGHT")
        host._cells[#host._cells + 1] = { lbl = lbl, val = val }
        registry[#registry + 1] = { fs = val, fn = c[2] }
    end

    host.arrange = function(width)
        width = math.max(width or 1, 1)
        host:SetWidth(width)
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -19)
        rule:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -19)

        local cols = (width < 240) and 1 or 2
        local colW = width / cols
        local labelW = colW * 0.58
        for i, cell in ipairs(host._cells) do
            local col  = (i - 1) % cols
            local rowN = math.floor((i - 1) / cols)
            local x = col * colW
            local y = TITLE_H + rowN * CELL_H
            cell.lbl:ClearAllPoints()
            cell.lbl:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
            cell.lbl:SetWidth(labelW)
            cell.val:ClearAllPoints()
            cell.val:SetPoint("TOPLEFT", host, "TOPLEFT", x + labelW, -y)
            cell.val:SetWidth(math.max(1, colW - labelW - CELL_PAD))
        end
        local rows = math.ceil(#host._cells / cols)
        local h = TITLE_H + rows * CELL_H
        host:SetHeight(math.max(h, 1))
        return h
    end

    return host
end

-- ── Hub "Stats" section ───────────────────────────────────────────────────────
function Addon:BuildStatsSection(flow)
    Addon.frames = Addon.frames or {}
    Addon.frames.stats = flow
    Addon:BuildStatsTab(flow)
end

function Addon:BuildStatsTab(flow)
    Addon._statsFlow    = flow
    Addon._statCellsHub = {}

    flow:Hint("Live character statistics — values update as your gear, buffs, and skills change.")
    flow:Checkbox({
        label   = "Attach a compact stats panel to the character window",
        get     = function() return Addon.db.settings.stats.attach end,
        set     = function(v)
            Addon.db.settings.stats.attach = v and true or false
            Addon:UpdateStatsPanelShown()
        end,
        tooltip = "Shows the same stat blocks docked to the right of the character sheet.",
    })

    local gap = (DaseekiUI.Token("rowGap") or 10)
    for _, blk in ipairs(SPECS) do
        local host = Addon:_MakeStatHost(flow.pane.child, blk, Addon._statCellsHub)
        flow.pane:AddBlock(host, host.arrange, gap, 0)
    end

    Addon:RefreshStatsTab()
end

-- ── Optional attach-to-character-window panel ─────────────────────────────────
function Addon:BuildStatsPanel()
    if Addon._statsPanel then return Addon._statsPanel end
    local UI = DaseekiUI
    local W, PAD, BLKGAP = 236, 12, 8

    local p = UI.FlatFrame(UIParent, "panel", "border")
    p:SetWidth(W)
    p:SetFrameStrata("MEDIUM")
    p:EnableMouse(true)   -- swallow clicks so they don't fall through to the world
    p:Hide()

    Addon._statCellsPanel = {}
    local y = PAD
    for _, blk in ipairs(SPECS) do
        local host = Addon:_MakeStatHost(p, blk, Addon._statCellsPanel)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -y)
        local h = host.arrange(W - PAD * 2)
        y = y + h + BLKGAP
    end
    p:SetHeight(math.max(y - BLKGAP + PAD, 1))

    Addon._statsPanel = p
    return p
end

function Addon:UpdateStatsPanelShown()
    local want = Addon.db and Addon.db.settings.stats and Addon.db.settings.stats.attach
    if not want then
        if Addon._statsPanel then Addon._statsPanel:Hide() end
        return
    end
    local p = Addon:BuildStatsPanel()
    if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", _G.CharacterFrame, "TOPRIGHT", 4, 0)
        p:Show()
        Addon:RefreshStatsPanel()
    else
        p:Hide()
    end
end

-- ── Init: live-update events + character-frame attach hooks ────────────────────
function Addon:InitStats()
    if Addon._statsInit then return end
    Addon._statsInit = true

    local ev = CreateFrame("Frame")
    local EVENTS = {
        "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK_SPEED",
        "UNIT_DAMAGE", "UNIT_RESISTANCES", "UNIT_MAXHEALTH", "PLAYER_DAMAGE_DONE_MODS",
        "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
        "SKILL_LINES_CHANGED", "UNIT_AURA", "PLAYER_ENTERING_WORLD",
    }
    for _, e in ipairs(EVENTS) do
        -- guard: a patch level that lacks a given event should not abort the rest
        pcall(function() ev:RegisterEvent(e) end)
    end
    ev:SetScript("OnEvent", function(_, event, unit)
        -- unit-scoped events: only care about the player
        if unit ~= nil and unit ~= "player" then return end
        Addon:MarkStatsDirty()
    end)
    Addon._statsEv = ev

    if _G.CharacterFrame then
        _G.CharacterFrame:HookScript("OnShow", function() Addon:UpdateStatsPanelShown() end)
        _G.CharacterFrame:HookScript("OnHide", function()
            if Addon._statsPanel then Addon._statsPanel:Hide() end
        end)
    end

    Addon:UpdateStatsPanelShown()
end
