-- =====================================================================
-- THE COLD CLIENT — a virtual WoW world whose axis is WARMTH.
--
-- Companion to equip-mock.lua, whose axis is SETTLEMENT. That one models
-- "the operation has not landed yet"; this one models "the ANSWER has not
-- arrived yet", which is the axis CLIENT_ASYNC_LESSONS.md Class 4 (partial /
-- cold data presented as complete) and Class 5 (truthy-zero and sticky
-- calibration) live on.
--
-- ── WHY IT EXISTS (SUITE_DATA_HONESTY_AUDIT.md §5, brief O) ──────────────────
-- Before this file, `Daseeki-Armory/harness/` was ABSENT for stats.lua: neither
-- run-selftests.lua nor equip-mock.lua stubbed GameTooltip, GetItemStats,
-- GetNumTalentTabs, GetTalentInfo or GetNumSpellTabs, and stats.lua had no
-- in-file self-tests. Every finding in brief O (ARM-1..ARM-4) was invisible
-- headless for exactly that reason — and worse, statmath.lua's own suite PINNED
-- THE COLD ANSWER AS CORRECT (`BlockValue(0, 220, 0, 0) == 11`), so the harness
-- was not merely silent about the defect, it certified it. Those assertions are
-- re-based in run-selftests.lua alongside this file.
--
-- ── THE UNKIND CONTRACT ──────────────────────────────────────────────────────
-- Simulator doctrine (CLIENT_ASYNC_LESSONS.md, closing paragraph): any sim for
-- client interactions starts UNKIND; the spec-behaving profile is secondary.
-- The unkind profile here is COLD, and it is the default:
--
--   1. ITEM DATA IS ABSENT UNTIL ASKED FOR AND DELIVERED. A cold item's
--      GetItemInfo answers nil, GetItemStats answers nil, and
--      C_Item.IsItemDataCachedByID answers false. The LINK is still there —
--      the client knows what is in the slot, it just cannot tell you about it.
--      That asymmetry is the whole Class 4 trap: everything looks readable.
--   2. A COLD TOOLTIP RENDERS ITS TITLE AND NOTHING ELSE. NumLines() == 1 and
--      TextLeft1 carries the item name. This is the proven live shape (Armory's
--      own classMask-0 incident; Nexus's title-only chronoboon read), and it is
--      why a body walk that sums to 0 is indistinguishable from a real zero.
--   3. REQUESTING IS NOT RECEIVING. RequestLoadItemDataByID is COUNTED, and for
--      an item the client does NOT hold nothing else happens: the fixture decides
--      when — and whether — the answer ever arrives, because "the server never
--      sent that item this session" is the scenario ARM-3 is about.
--      BUT (Class 9, 2026-08-10) for an item the client ALREADY HOLDS the answer
--      is immediate, and immediate means FROM INSIDE THE REQUEST: the client
--      dispatches ITEM_DATA_LOAD_RESULT to every registered handler in the
--      session before RequestLoadItemDataByID returns. That is the whole hazard,
--      and the state it needs is 3a.
--   3a. RESIDENT IS NOT RENDERED. `w:residentButUnrendered(id)` is the third
--      state — the one stats.lua's own comment names: "an item the client thinks
--      it has cached but whose tooltip has not been built yet". C_Item says
--      cached, GetItemInfo answers, and the TOOLTIP still renders title-only. It
--      is the only state in which the addon asks for something the client can
--      answer in-call, so it is the state the Class 9 fixtures use.
--   4. DELIVERY IS AN EVENT. w:warmItem(id) fires GET_ITEM_INFO_RECEIVED(id,
--      true). Code that does not listen does not heal, and the sim will not
--      heal it by hand. w:warmItem(id, true) delivers SILENTLY, which is how a
--      fixture proves a cache was never memoized rather than merely repainted.
--   5. THE TREE AND THE BOOK ANSWER ZERO, NOT NIL. A cold GetNumTalentTabs()
--      and a cold GetNumSpellTabs() return 0 — a number, truthy, and wrong —
--      which is the Class 5 shape both ARM-2 and ARM-4 latch on. Warming them
--      fires NOTHING: nothing in the client announces "the talent tree is
--      readable now", so code that latches on the cold read must re-read, not
--      wait for a signal it will never get.
--
-- The WARM profile (`cold.new(P, cold.WARM)`) has to be asked for by name.
--
-- Usage:
--   local cold = dofile("cold-mock.lua")
--   local w = cold.new(P)                                   -- COLD (the default)
--   local w = cold.new(P, cold.WARM)                        -- opt-in warm
--   local w = cold.new(P, { noCItem = true })               -- a build with no C_Item
--   local w = cold.new(P, { files = { "iconData.lua" } })   -- which files to load
-- =====================================================================

local Cold = {}

Cold.WARM = { profile = "warm" }
Cold.COLD = { profile = "cold" }

-- ── Dispatch (CLIENT_ASYNC_LESSONS.md Class 9) ────────────────────────────────
-- SYNC by doctrine: when the client can answer a load request it answers from
-- inside the call. The runner flips this module-level default to replay every
-- cold suite under async; every cold.new that does not name a dispatch inherits it.
Cold.DEFAULT_DISPATCH = "sync"
Cold.SYNC  = { dispatch = "sync" }
Cold.ASYNC = { dispatch = "async" }

-- Slot ids in the order core.lua's Addon.SLOTS declares them.
local SLOT_IDS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- Localization strings the block-value scraper builds its patterns from. These
-- are the shapes the live client ships (a long sentence with a %d, plus a short
-- column label), because the point of the fixture is to grade the REAL pattern
-- builder against tooltip text it did not choose.
Cold.ITEM_MOD_BLOCK_VALUE        = "Increases the block value of your shield by %d."
Cold.ITEM_MOD_BLOCK_RATING       = "Increases your shield block rating by %d."
Cold.ITEM_MOD_BLOCK_RATING_SHORT = "Block Rating"

-- id -> definition. `block` renders through the long sentence, `blockRating`
-- through the short label, `mp5` through a line that must NOT match either.
local DEFAULT_ITEMS = {
    [5001] = { name = "Aegis of the Scarlet Commander", equipLoc = "INVTYPE_SHIELD",
               armor = 2450, block = 46 },
    [5002] = { name = "Drillborer Disk",  equipLoc = "INVTYPE_SHIELD", armor = 2600, blockRating = 7 },
    [5003] = { name = "Plain Buckler",    equipLoc = "INVTYPE_SHIELD", armor = 900 },
    [5010] = { name = "Lionheart Helm",   equipLoc = "INVTYPE_HEAD",   armor = 600 },
    [5011] = { name = "Cloak of Concentrated Hatred", equipLoc = "INVTYPE_CLOAK", armor = 60 },
    [5020] = { name = "Robe of Insight",  equipLoc = "INVTYPE_ROBE",   armor = 120, mp5 = 8 },
    [5021] = { name = "Belt of the Archmage", equipLoc = "INVTYPE_WAIST", armor = 80, mp5 = 5 },
    -- Weapons, for the secure-macro fixtures (ARM-3).
    [6001] = { name = "Quel'Serrar",      equipLoc = "INVTYPE_WEAPON" },
    [6002] = { name = "Thunderfury",      equipLoc = "INVTYPE_WEAPON" },
    [6003] = { name = "Larvae of the Great Worm", equipLoc = "INVTYPE_RANGED" },
    -- Battlegear of Might (set-bonus ids live in statmath.lua).
    [16861] = { name = "Battlegear Bracers", equipLoc = "INVTYPE_WRIST", armor = 300 },
    [16862] = { name = "Battlegear Gauntlets", equipLoc = "INVTYPE_HAND", armor = 400 },
    [16863] = { name = "Battlegear Belt", equipLoc = "INVTYPE_WAIST", armor = 350 },
}

-- Talent tree fixture. Layout is deliberately identity-ordered (tier = index,
-- column = 1) so the remap is a no-op — BuildTalentRemap's own arithmetic is
-- covered by the pure suite, and mixing the two questions here would blur which
-- one a red is about.
local DEFAULT_TALENTS = {
    { name = "Arcane", talents = {
        { name = "Arcane Subtlety",    rank = 0, maxRank = 2 },
        { name = "Arcane Meditation",  rank = 3, maxRank = 3 },
        { name = "Arcane Instability", rank = 3, maxRank = 3 },
    }},
    { name = "Fire", talents = {
        { name = "Improved Fireball", rank = 5, maxRank = 5 },
        { name = "Critical Mass",     rank = 0, maxRank = 3 },
    }},
    { name = "Frost", talents = {
        { name = "Frost Warding", rank = 0, maxRank = 2 },
        { name = "Ice Shards",    rank = 5, maxRank = 5 },
    }},
}

local DEFAULT_SPELLBOOK = {
    { name = "General", spells = {
        { name = "Attack", tex = "Interface\\Icons\\INV_Sword_04" },
        { name = "Shoot",  tex = "Interface\\Icons\\Ability_Marksmanship" },
    }},
    { name = "Arcane", spells = {
        { name = "Arcane Missiles", tex = "Interface\\Icons\\Spell_Nature_StarFall" },
        { name = "Evocation",       tex = "Interface\\Icons\\Spell_Nature_Purge" },
    }},
}

-- Build an item link. enchant/suffix default to 0.
function Cold.link(id, enchant, suffix)
    return string.format("item:%d:%d:0:0:0:0:%d:0:60:0", id, enchant or 0, suffix or 0)
end

local function idFromLink(link)
    if type(link) == "number" then return link end
    return tonumber(tostring(link):match("item:(%d+)"))
end

local TOOLTIP_MAX_LINES = 40

function Cold.new(P, opts)
    opts = opts or {}
    local profile = opts.profile or "cold"
    local bornWarm = (profile == "warm")

    local w = {
        profile  = profile,
        dispatch = opts.dispatch or Cold.DEFAULT_DISPATCH,
        inCall   = 0,      -- depth of client calls we are currently inside
        warm    = {},      -- [itemId] = true once the client holds its data
        tipCold = {},      -- [itemId] = true when resident but NOT rendered (3a)
        worn    = {},      -- [slotId] = link
        items   = {},      -- [itemId] = definition
        frames  = {},
        tooltips = {},
        events  = {},
        printed = {},
        clock   = 0,
        seq     = 0,
        timers  = {},
        talentsReadable  = bornWarm,
        spellbookReadable = bornWarm,
        talents   = {},
        spellbook = {},
        skillLines = {},
        auras = {},        -- flat array of helpful aura spell ids
        class = "WARRIOR",
        stats = {
            loadRequests = 0,       -- every RequestLoadItemDataByID
            inCallEvents = 0,       -- …that the client answered from INSIDE the call
            tooltipScans = 0,       -- every SetInventoryItem
            coldScans    = 0,       -- …that rendered title-only
            talentReads  = 0,       -- every GetTalentInfo
            spellWalks   = 0,       -- every GetNumSpellTabs answered non-zero
        },
        loadRequested = {},         -- [itemId] = count
        unitStats = { [1] = 220, [2] = 100, [3] = 300, [4] = 40, [5] = 50 },
        armorValue = 5000,
        manaRegenPerSec = 3.0,
        hasMana = false,
    }

    for id, def in pairs(DEFAULT_ITEMS) do
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        w.items[id] = copy
        if bornWarm then w.warm[id] = true end
    end
    for i, tab in ipairs(DEFAULT_TALENTS) do
        local t = { name = tab.name, talents = {} }
        for j, tal in ipairs(tab.talents) do
            t.talents[j] = { name = tal.name, rank = tal.rank, maxRank = tal.maxRank }
        end
        w.talents[i] = t
    end
    for i, tab in ipairs(DEFAULT_SPELLBOOK) do
        local t = { name = tab.name, spells = {} }
        for j, s in ipairs(tab.spells) do t.spells[j] = { name = s.name, tex = s.tex } end
        w.spellbook[i] = t
    end
    -- Defense sits under the Weapon Skills header, which is what the skill-line
    -- walk in stats.lua looks for.
    w.skillLines = {
        { name = "Weapon Skills", isHeader = true },
        { name = "Defense", isHeader = false, rank = 300, modifier = 15 },
        { name = "Swords",  isHeader = false, rank = 300, modifier = 0 },
    }

    ---------------------------------------------------------------- clock
    function w:after(delay, fn)
        self.seq = self.seq + 1
        self.timers[#self.timers + 1] = { at = self.clock + (delay or 0), seq = self.seq, fn = fn }
    end

    -- Run the clock forward until the queue drains or `limit` virtual seconds pass.
    function w:settle(limit)
        limit = limit or 30
        local guard = 0
        while true do
            guard = guard + 1
            if guard > 100000 then error("cold-mock: timer storm (possible infinite loop)") end
            local best
            for i, t in ipairs(self.timers) do
                if not best or t.at < self.timers[best].at
                   or (t.at == self.timers[best].at and t.seq < self.timers[best].seq) then best = i end
            end
            if not best then return end
            local t = self.timers[best]
            if t.at > limit then return end
            table.remove(self.timers, best)
            if t.at > self.clock then self.clock = t.at end
            t.fn()
        end
    end

    ---------------------------------------------------------------- events
    function w:fireEvent(evt, a, b)
        local inCall = (self.inCall or 0) > 0
        self.events[#self.events + 1] = { evt = evt, a = a, b = b, at = self.clock, inCall = inCall }
        if inCall then self.stats.inCallEvents = self.stats.inCallEvents + 1 end
        if self.onEvent then self.onEvent(evt, a, b, inCall) end
        local snap = {}
        for i, f in ipairs(self.frames) do snap[i] = f end
        for _, f in ipairs(snap) do
            if f._events[evt] and f._script then f._script(f, evt, a, b) end
        end
    end

    function w:countEvents(evt)
        local n = 0
        for _, e in ipairs(self.events) do if e.evt == evt then n = n + 1 end end
        return n
    end

    -- Is ANY live frame listening for this event? The question a fixture asks to
    -- prove a repair path exists at all.
    function w:isRegistered(evt)
        for _, f in ipairs(self.frames) do if f._events[evt] then return true end end
        return false
    end

    function w:output() return table.concat(self.printed, "\n") end

    ---------------------------------------------------------------- the world
    function w:setWorn(slotId, link) self.worn[slotId] = link end

    -- Equip an item by id (link built for you) and answer the link.
    function w:equip(slotId, id, enchant)
        local link = Cold.link(id, enchant)
        self.worn[slotId] = link
        return link
    end

    function w:defineItem(id, def)
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        self.items[id] = copy
        if self.profile == "warm" then self.warm[id] = true end
        return id
    end

    -- THE DELIVERY. `silent` withholds GET_ITEM_INFO_RECEIVED so a fixture can
    -- prove a value was re-READ rather than merely repainted by the event.
    function w:warmItem(id, silent)
        if not id then return end
        local first = not self.warm[id]
        self.warm[id] = true
        self.tipCold[id] = nil
        if first and not silent then self:fireEvent("GET_ITEM_INFO_RECEIVED", id, true) end
    end

    -- STATE 3a (Class 9). The client HOLDS the item — C_Item says cached and
    -- GetItemInfo answers its name — but the tooltip has not been built, so a
    -- body walk still reads title-only. This is the only state in which the
    -- addon asks the client for something it can answer immediately, and
    -- "immediately" is what dispatches the echo from inside the request.
    function w:residentButUnrendered(id)
        if not id then return end
        self.warm[id]    = true
        self.tipCold[id] = true
    end

    -- The tooltip finally gets built. Announces itself, as the client does.
    function w:renderTooltip(id, silent)
        if not id then return end
        self.tipCold[id] = nil
        if not silent then self:fireEvent("GET_ITEM_INFO_RECEIVED", id, true) end
    end

    -- Warm everything currently equipped (and nothing else — an item nobody is
    -- wearing has no reason to arrive).
    function w:warmWorn(silent)
        local ids = {}
        for _, link in pairs(self.worn) do
            local id = idFromLink(link)
            if id then ids[#ids + 1] = id end
        end
        table.sort(ids)                        -- Class 8: deterministic delivery order
        for _, id in ipairs(ids) do self:warmItem(id, silent) end
    end

    function w:warmAll(silent)
        local ids = {}
        for id in pairs(self.items) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do self:warmItem(id, silent) end
    end

    function w:isWarm(id) return self.warm[id] == true end

    -- The talent tree becoming readable announces NOTHING. Deliberate: the client
    -- has no such event, which is why ARM-2's latch could never heal.
    function w:warmTalents() self.talentsReadable = true end
    function w:coolTalents() self.talentsReadable = false end

    function w:warmSpellbook() self.spellbookReadable = true end

    -- Visit a trainer. Fires LEARNED_SPELL_IN_TAB, exactly as the client does.
    function w:learnSpell(name, tex, tab)
        tab = tab or #self.spellbook
        local t = self.spellbook[tab]
        if not t then return end
        t.spells[#t.spells + 1] = { name = name, tex = tex or ("Interface\\Icons\\" .. name) }
        self:fireEvent("LEARNED_SPELL_IN_TAB", tab)
    end

    ---------------------------------------------------------------- tooltip text
    -- The lines a WARM tooltip renders for an item. A cold one renders element 1
    -- and stops there.
    function w:tooltipTextFor(id)
        local def = self.items[id]
        if not def then return nil end
        local out = { def.name }
        -- TITLE-ONLY: the Class 4 shape. Either the client does not hold the item
        -- at all, or it holds it and has not built the tooltip yet (state 3a) —
        -- indistinguishable to a body walk, which is the trap.
        if not self.warm[id] or self.tipCold[id] then return out end
        out[#out + 1] = "Binds when picked up"
        out[#out + 1] = (def.equipLoc or "INVTYPE_MISC"):gsub("^INVTYPE_", "")
        if def.armor then out[#out + 1] = def.armor .. " Armor" end
        if def.block then out[#out + 1] = string.format(Cold.ITEM_MOD_BLOCK_VALUE, def.block) end
        if def.blockRating then
            out[#out + 1] = "+" .. def.blockRating .. " " .. Cold.ITEM_MOD_BLOCK_RATING_SHORT
        end
        if def.mp5 then
            out[#out + 1] = "Equip: Restores " .. def.mp5 .. " mana per 5 sec."
        end
        out[#out + 1] = "Requires Level 60"
        return out
    end

    ---------------------------------------------------------------- API install
    local G = _G

    -- Everything shadowed, so a later suite is never affected. Globals that did
    -- not exist are restored to nil (`saved` holds nil for them, which is right).
    local INSTALLED = {
        "C_Item", "C_Timer", "C_Container", "CreateFrame", "GetTime", "print",
        "UIParent", "WorldFrame", "DaseekiArmory",
        "GetInventoryItemLink", "GetInventoryItemID", "GetInventoryItemTexture",
        "GetInventorySlotInfo", "IsInventoryItemLocked",
        "GetItemInfo", "GetItemInfoInstant", "GetItemStats",
        "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo", "GetTalentTabInfo",
        "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName",
        "GetSpellBookItemTexture", "BOOKTYPE_SPELL",
        "GetMacroIcons", "GetMacroItemIcons",
        "GetNumSkillLines", "GetSkillLineInfo", "UnitDefense",
        "WEAPON_SKILLS", "DEFENSE",
        "ITEM_MOD_BLOCK_VALUE", "ITEM_MOD_BLOCK_RATING", "ITEM_MOD_BLOCK_RATING_SHORT",
        "UnitClass", "UnitStat", "UnitArmor", "UnitAttackPower", "UnitRangedAttackPower",
        "UnitDamage", "UnitRangedDamage", "UnitAttackSpeed", "UnitHealthMax",
        "UnitPowerMax", "UnitResistance", "UnitHasMana", "UnitAura", "UnitName",
        "UnitAffectingCombat", "UnitIsDeadOrGhost", "UnitIsFeignDeath",
        "GetManaRegen", "GetSpellBonusDamage", "GetSpellCritChance", "GetSpellBonusHealing",
        "GetSpellHitModifier", "GetSpellPenetration", "GetHitModifier", "GetCritChance",
        "GetRangedCritChance", "GetDodgeChance", "GetParryChance", "GetBlockChance",
        "GetShieldBlock", "IsRangedWeapon", "HasWandEquipped", "GetWeaponEnchantInfo",
        "GetRealmName",
        "InCombatLockdown", "ClearOverrideBindings", "SetOverrideBindingClick",
        "CursorHasItem", "ClearCursor", "SpellIsTargeting",
        "ArmEquip", "ArmToggle", "ArmEquipSecure",
        "strtrim", "wipe",
    }
    local saved = {}
    for _, k in ipairs(INSTALLED) do saved[k] = G[k] end
    -- Tooltip fontstrings are named after the tooltip, so they cannot be listed
    -- ahead of time. Each one records the value it displaced — nil for a fresh
    -- name, and the OUTER world's fontstring when a fixture nests a second world.
    local extraGlobals = {}

    function w:teardown()
        for _, k in ipairs(INSTALLED) do G[k] = saved[k] end
        for k, prev in pairs(extraGlobals) do G[k] = prev.value end
    end

    G.UIParent   = { _isUIParent = true }
    G.WorldFrame = { _isWorldFrame = true }

    G.ITEM_MOD_BLOCK_VALUE        = Cold.ITEM_MOD_BLOCK_VALUE
    G.ITEM_MOD_BLOCK_RATING       = Cold.ITEM_MOD_BLOCK_RATING
    G.ITEM_MOD_BLOCK_RATING_SHORT = Cold.ITEM_MOD_BLOCK_RATING_SHORT
    G.WEAPON_SKILLS = "Weapon Skills"
    G.DEFENSE       = "Defense"
    G.BOOKTYPE_SPELL = "spell"

    ------------------------------------------------------------ frames
    local function newFrame(name)
        local f = { _events = {}, _script = nil, _attrs = {}, _name = name }
        function f:RegisterEvent(e)   self._events[e] = true end
        function f:UnregisterEvent(e) self._events[e] = nil  end
        function f:UnregisterAllEvents() self._events = {} end
        function f:SetScript(k, fn)   if k == "OnEvent" then self._script = fn end end
        function f:HookScript() end
        function f:GetName()          return self._name end
        function f:SetAttribute(k, v) self._attrs[k] = v end
        function f:GetAttribute(k)    return self._attrs[k] end
        function f:RegisterForClicks() end
        function f:Show() self._shown = true end
        function f:Hide() self._shown = false end
        function f:IsShown() return self._shown and true or false end
        function f:SetWidth() end
        function f:SetHeight() end
        function f:SetSize() end
        function f:SetPoint() end
        function f:ClearAllPoints() end
        function f:SetFrameStrata() end
        function f:EnableMouse() end
        function f:Raise() end
        w.frames[#w.frames + 1] = f
        return f
    end

    ------------------------------------------------------------ the scanning tooltip
    -- A GameTooltip with the readback surface the scraper uses: NumLines() plus
    -- the global <name>TextLeft<i> fontstrings. SetInventoryItem renders the
    -- item's lines — ALL of them when warm, the title alone when cold.
    local function newTooltip(name)
        local tip = newFrame(name)
        tip._lines = {}

        local function fsName(i) return (name or "ColdMockTooltip") .. "TextLeft" .. i end
        local fontstrings = {}
        for i = 1, TOOLTIP_MAX_LINES do
            local fs = { _text = nil }
            function fs:GetText() return self._text end
            function fs:SetText(t) self._text = t end
            fontstrings[i] = fs
            local gname = fsName(i)
            if extraGlobals[gname] == nil then extraGlobals[gname] = { value = G[gname] } end
            G[gname] = fs
        end

        local function render(lines)
            tip._lines = lines or {}
            for i = 1, TOOLTIP_MAX_LINES do
                fontstrings[i]._text = tip._lines[i]
            end
        end

        function tip:SetOwner() end
        function tip:ClearLines() render({}) end
        function tip:NumLines() return #self._lines end
        function tip:GetLine(i) return self._lines[i] end

        function tip:SetInventoryItem(_, slotId)
            w.stats.tooltipScans = w.stats.tooltipScans + 1
            local link = w.worn[slotId]
            if not link then render({}); return false end
            local id = idFromLink(link)
            local lines = w:tooltipTextFor(id)
            if not lines then render({}); return false end
            if #lines <= 1 then w.stats.coldScans = w.stats.coldScans + 1 end
            render(lines)
            return true
        end

        function tip:SetHyperlink(link)
            local id = idFromLink(link)
            local lines = id and w:tooltipTextFor(id)
            render(lines or {})
        end

        w.tooltips[#w.tooltips + 1] = tip
        return tip
    end

    G.CreateFrame = function(kind, name, _, _)
        if kind == "GameTooltip" then return newTooltip(name) end
        return newFrame(name)
    end

    -- A tooltip a FIXTURE owns, for grading the sim without going through
    -- stats.lua. Same constructor the addon uses.
    function w:scanTip(name)
        return G.CreateFrame("GameTooltip", name or "ColdMockScanTooltip", G.UIParent, "GameTooltipTemplate")
    end

    ------------------------------------------------------------ item data
    -- REQUESTING IS NOT RECEIVING. Counted, and nothing else happens.
    if not opts.noCItem then
        G.C_Item = {
            IsItemDataCachedByID = function(id)
                id = idFromLink(id)
                return w.warm[id] == true
            end,
            -- CLASS 9. Counted always. Answered ONLY when the client already
            -- holds the item — and then answered from INSIDE this call under
            -- sync dispatch, so every handler in the session runs before the
            -- request returns. An item the client does not hold answers nothing:
            -- requesting is still not receiving.
            RequestLoadItemDataByID = function(id)
                id = idFromLink(id)
                if not id then return end
                w.stats.loadRequests = w.stats.loadRequests + 1
                w.loadRequested[id] = (w.loadRequested[id] or 0) + 1
                if not w.warm[id] then return end
                local function answer() w:fireEvent("ITEM_DATA_LOAD_RESULT", id, true) end
                if w.dispatch == "sync" then
                    w.inCall = (w.inCall or 0) + 1
                    local ok, err = pcall(answer)
                    w.inCall = w.inCall - 1
                    if not ok then error(err, 0) end
                else
                    w:after(0, answer)
                end
            end,
        }
    else
        G.C_Item = nil
    end

    function w:loadsFor(id) return w.loadRequested[id] or 0 end

    G.GetItemInfoInstant = function(link)
        local id = idFromLink(link)
        local def = id and w.items[id]
        if not def then return nil end
        -- id, type, subType, equipLoc, icon, classID, subclassID — OFFLINE and
        -- synchronous for anything the client holds, warm or not. That is real:
        -- it is why goalPicker.lua can build its list without waiting.
        return id, "Armor", "Misc", def.equipLoc, "Interface\\Icons\\INV_Misc_QuestionMark", 4, 6
    end

    G.GetItemInfo = function(link)
        local id = idFromLink(link)
        local def = id and w.items[id]
        if not def then return nil end
        if not w.warm[id] then return nil end            -- cold: the name is not here yet
        return def.name, (type(link) == "number" and Cold.link(link) or link), 3, 66, 60,
               "Armor", "Misc", 1, def.equipLoc, "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    G.GetItemStats = function(link)
        local id = idFromLink(link)
        local def = id and w.items[id]
        if not def then return nil end
        if not w.warm[id] then return nil end            -- cold: no stat table at all
        local t = {}
        if def.mp5   then t["ITEM_MOD_POWER_REGEN0_SHORT"] = def.mp5 end
        if def.armor then t["RESISTANCE0_NAME"] = def.armor end
        if def.block then t["ITEM_MOD_BLOCK_VALUE_SHORT"] = def.block end
        return t
    end

    ------------------------------------------------------------ inventory
    G.GetInventoryItemLink    = function(_, slotId) return w.worn[slotId] end
    G.GetInventoryItemID      = function(_, slotId) return idFromLink(w.worn[slotId]) end
    G.GetInventoryItemTexture = function(_, slotId)
        return w.worn[slotId] and "Interface\\Icons\\INV_Misc_QuestionMark" or nil
    end
    G.GetInventorySlotInfo    = function(nm) return 1, "Interface\\PaperDoll\\" .. tostring(nm) end
    G.IsInventoryItemLocked   = function() return false end
    G.C_Container = {
        GetContainerNumSlots = function() return 0 end,
        GetContainerItemLink = function() return nil end,
        GetContainerItemInfo = function() return nil end,
        GetContainerNumFreeSlots = function() return 0, 0 end,
        PickupContainerItem = function() end,
    }
    G.CursorHasItem = function() return false end
    G.ClearCursor = function() end
    G.SpellIsTargeting = function() return false end

    ------------------------------------------------------------ talents
    -- 0 tabs is what a cold client answers. It is a NUMBER, it is TRUTHY, and it
    -- is wrong — every character has three trees.
    G.GetNumTalentTabs = function()
        if not w.talentsReadable then return 0 end
        return #w.talents
    end
    G.GetNumTalents = function(tab)
        if not w.talentsReadable then return 0 end
        local t = w.talents[tab]
        return t and #t.talents or 0
    end
    G.GetTalentTabInfo = function(tab)
        if not w.talentsReadable then return nil end
        local t = w.talents[tab]
        if not t then return nil end
        return t.name
    end
    G.GetTalentInfo = function(tab, index)
        w.stats.talentReads = w.stats.talentReads + 1
        if not w.talentsReadable then return nil end
        local t = w.talents[tab]
        local tal = t and t.talents[index]
        if not tal then return nil end
        -- name, icon, tier, column, rank, maxRank
        return tal.name, "icon", index, 1, tal.rank, tal.maxRank
    end

    ------------------------------------------------------------ spellbook
    G.GetNumSpellTabs = function()
        if not w.spellbookReadable then return 0 end
        w.stats.spellWalks = w.stats.spellWalks + 1
        return #w.spellbook
    end
    G.GetSpellTabInfo = function(tab)
        if not w.spellbookReadable then return nil end
        local t = w.spellbook[tab]
        if not t then return nil end
        local offset = 0
        for i = 1, tab - 1 do offset = offset + #w.spellbook[i].spells end
        -- name, texture, offset, numSpells
        return t.name, "icon", offset, #t.spells
    end
    local function spellAt(index)
        if not w.spellbookReadable then return nil end
        local n = 0
        for _, t in ipairs(w.spellbook) do
            for _, s in ipairs(t.spells) do
                n = n + 1
                if n == index then return s end
            end
        end
    end
    G.GetSpellBookItemName    = function(i) local s = spellAt(i); return s and s.name or nil end
    G.GetSpellBookItemTexture = function(i) local s = spellAt(i); return s and s.tex or nil end

    G.GetMacroIcons = function(t)
        if type(t) == "table" then
            t[#t + 1] = "Interface\\Icons\\Ability_Warrior_Charge"
            t[#t + 1] = 132355
        end
    end
    G.GetMacroItemIcons = function(t)
        if type(t) == "table" then t[#t + 1] = 133784 end
    end

    ------------------------------------------------------------ skills / units
    G.GetNumSkillLines = function() return #w.skillLines end
    G.GetSkillLineInfo = function(i)
        local s = w.skillLines[i]
        if not s then return nil end
        -- name, isHeader, isExpanded, rank, numTempPoints, modifier
        return s.name, s.isHeader, true, s.rank, 0, s.modifier
    end
    G.UnitDefense = function() return 300, 0 end

    G.UnitClass  = function() return w.class, w.class end
    G.UnitName   = function() return "Coldtest" end
    G.GetRealmName = function() return "Testrealm" end
    G.UnitStat   = function(_, i) return w.unitStats[i] or 0, w.unitStats[i] or 0, 0, 0 end
    G.UnitArmor  = function() return w.armorValue, w.armorValue, 0, 0, 0 end
    G.UnitAttackPower       = function() return 800, 0, 0 end
    G.UnitRangedAttackPower = function() return 200, 0, 0 end
    G.UnitDamage            = function() return 100, 150, 100, 150, 0, 0, 1 end
    G.UnitRangedDamage      = function() return 2.9, 80, 120, 0, 0, 1 end
    G.UnitAttackSpeed       = function() return 2.5, 0 end
    G.UnitHealthMax = function() return 4200 end
    G.UnitPowerMax  = function() return w.hasMana and 3000 or 0 end
    G.UnitResistance = function(_, i) return 10 * (i + 1), 10 * (i + 1), 0, 0 end
    G.UnitHasMana = function() return w.hasMana end
    G.UnitAura = function(_, i)
        local id = w.auras[i]
        if not id then return nil end
        return "Aura " .. id, nil, nil, nil, nil, nil, nil, nil, nil, id
    end
    G.UnitAffectingCombat = function() return w.combat or false end
    G.UnitIsDeadOrGhost   = function() return false end
    G.UnitIsFeignDeath    = function() return false end

    G.GetManaRegen         = function() return w.manaRegenPerSec, w.manaRegenPerSec end
    G.GetSpellBonusDamage  = function() return 100 end
    G.GetSpellCritChance   = function() return 0 end
    G.GetSpellBonusHealing = function() return 120 end
    G.GetSpellHitModifier  = function() return 6 end
    G.GetSpellPenetration  = function() return 0 end
    G.GetHitModifier       = function() return 4 end
    G.GetCritChance        = function() return 12.5 end
    G.GetRangedCritChance  = function() return 11.0 end
    G.GetDodgeChance       = function() return 15.0 end
    G.GetParryChance       = function() return 14.0 end
    G.GetBlockChance       = function() return 30.0 end
    G.GetShieldBlock       = function() return 42 end
    G.IsRangedWeapon       = function() return w.worn[18] ~= nil end
    G.HasWandEquipped      = function() return false end
    G.GetWeaponEnchantInfo = function() return false end

    ------------------------------------------------------------ misc
    G.InCombatLockdown        = function() return w.combat or false end
    G.ClearOverrideBindings   = function() end
    G.SetOverrideBindingClick = function(_, _, key, btn)
        w.bindings = w.bindings or {}
        w.bindings[key] = btn
    end

    G.C_Timer = { After = function(d, fn) w:after(d, fn) end }
    G.GetTime = function() return w.clock end

    G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
    G.wipe    = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.print   = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        w.printed[#w.printed + 1] = table.concat(parts, " ")
    end

    ---------------------------------------------------------------- addon load
    local Addon = {}
    Addon.SLOT_IDS = SLOT_IDS
    Addon.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
    Addon.EMPTY_ICON   = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
    Addon.db = {
        sets = {}, currentSet = nil,
        settings = {
            chatMessages = true,
            stats = { attach = false, blizzardBlockValue = false },
        },
    }
    function Addon:Tag() return "[Armory]" end
    function Addon:Col() return 1, 1, 1, 1 end
    function Addon:Hex() return nil end
    function Addon:Wrap(_, t) return tostring(t) end
    function Addon:TrySetFont() return false end
    function Addon:TrySetCeremonial() return false end
    function Addon:TrySetNumeral() return false end

    G.DaseekiArmory = Addon

    for _, file in ipairs(opts.files or { "statmath.lua", "stats.lua" }) do
        local fn, err = loadfile(P(file))
        if not fn then error("cold-mock: cannot compile " .. file .. " -> " .. tostring(err)) end
        local ok, rerr = pcall(fn, "Daseeki-Armory", Addon)
        if not ok then error("cold-mock: " .. file .. " raised at load -> " .. tostring(rerr)) end
    end

    w.Addon = Addon

    -- Reach a stat row through the SHIPPED spec table, so a fixture drives the
    -- exact closure the panel renders with — including its NA handling.
    function w:cell(blockTitle, label)
        for _, blk in ipairs(Addon:StatBlockSpecs()) do
            if blk.title == blockTitle then
                for _, c in ipairs(blk.cells) do
                    if c[1] == label then return c[2] end
                end
            end
        end
        return nil
    end

    -- Read a stat row's display string the way a refresh does.
    function w:read(blockTitle, label)
        local fn = self:cell(blockTitle, label)
        if not fn then return nil end
        local ok, s = pcall(fn)
        return ok and s or nil
    end

    -- One refresh tick: bump the memo serial so per-tick memos (mana regen) are
    -- recomputed, exactly as MarkStatsDirty does.
    function w:tick()
        Addon._statsSerial = (Addon._statsSerial or 0) + 1
    end

    -- Define a set from { [slotId] = itemId }. Requires sets.lua to be loaded.
    function w:defineSet(name, slots, key)
        local set = { name = name, equip = {}, disabled = {}, key = key }
        for slotId, id in pairs(slots) do
            set.equip[slotId] = { id = id, str = tostring(id), exact = tostring(id) }
        end
        Addon.db.sets[name] = set
        return set
    end

    return w
end

Cold.SLOT_IDS = SLOT_IDS
Cold.ITEMS    = DEFAULT_ITEMS
return Cold
