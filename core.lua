--[[
    Daseeki Armory — core: addon table, SavedVariables, slot model, login flow.

    A per-character equipment-set manager modeled on ItemRack's "Sets" feature,
    built to plug into the shared Daseeki-Core hub (global DaseekiSuite). Sets are
    stored per character (## SavedVariablesPerCharacter: DaseekiArmoryDB).

    Global table: DaseekiArmory  (also _G['Daseeki-Armory'])
--]]

local ADDON, Addon = ...
DaseekiArmory      = Addon
_G['Daseeki-Armory'] = Addon

-- ── Equipment slot model ──────────────────────────────────────────────────────
-- id = inventory slot id (GetInventorySlotInfo order); laid out for the paper-doll
-- builder (left column, right column, then weapons across the bottom).
Addon.SLOTS = {
    { id = 1,  name = "Head",      col = "L", slotName = "HeadSlot" },
    { id = 2,  name = "Neck",      col = "L", slotName = "NeckSlot" },
    { id = 3,  name = "Shoulder",  col = "L", slotName = "ShoulderSlot" },
    { id = 15, name = "Back",      col = "L", slotName = "BackSlot" },
    { id = 5,  name = "Chest",     col = "L", slotName = "ChestSlot" },
    { id = 4,  name = "Shirt",     col = "L", slotName = "ShirtSlot" },
    { id = 19, name = "Tabard",    col = "L", slotName = "TabardSlot" },
    { id = 9,  name = "Wrist",     col = "L", slotName = "WristSlot" },

    { id = 10, name = "Hands",     col = "R", slotName = "HandsSlot" },
    { id = 6,  name = "Waist",     col = "R", slotName = "WaistSlot" },
    { id = 7,  name = "Legs",      col = "R", slotName = "LegsSlot" },
    { id = 8,  name = "Feet",      col = "R", slotName = "FeetSlot" },
    { id = 11, name = "Finger 1",  col = "R", slotName = "Finger0Slot" },
    { id = 12, name = "Finger 2",  col = "R", slotName = "Finger1Slot" },
    { id = 13, name = "Trinket 1", col = "R", slotName = "Trinket0Slot" },
    { id = 14, name = "Trinket 2", col = "R", slotName = "Trinket1Slot" },

    { id = 16, name = "Main Hand", col = "W", slotName = "MainHandSlot" },
    { id = 17, name = "Off Hand",  col = "W", slotName = "SecondaryHandSlot" },
    { id = 18, name = "Ranged",    col = "W", slotName = "RangedSlot" },
}

-- Per-slot empty-slot artwork (Blizzard paper-doll background), resolved lazily.
function Addon:GetSlotEmptyTexture(slotDef)
    if slotDef._emptyTex == nil and slotDef.slotName then
        local _, tex = GetInventorySlotInfo(slotDef.slotName)
        slotDef._emptyTex = tex or false
    end
    return slotDef._emptyTex or Addon.EMPTY_ICON
end

-- Ordered list of just the slot ids (used by the equip engine / SaveCurrentGear).
Addon.SLOT_IDS = {}
for _, s in ipairs(Addon.SLOTS) do Addon.SLOT_IDS[#Addon.SLOT_IDS + 1] = s.id end

Addon.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
Addon.EMPTY_ICON   = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- ── SavedVariables defaults ───────────────────────────────────────────────────
local DEFAULT_DB = {
    sets        = {},    -- name -> { name, icon, order, equip = { [slotId] = entry } }
    currentSet  = nil,   -- last equipped set name (for widget highlight)
    settings    = {
        flyoutPerRow = 5,         -- icons per row in the inventory flyout before wrapping
        flyoutTooltip = "ctrl",   -- "ctrl" (show item tooltip only while Ctrl held) | "always"
        chatMessages  = false,    -- print combat-queue messages to chat
        widget = {
            show     = false,
            locked   = false,
            point    = "CENTER",
            relPoint = "CENTER",
            x        = 250,
            y        = 0,
            scale    = 1,
            radius   = 92,
            openTrigger    = "click",   -- "click" | "hover"
            mode           = "radial",  -- "radial" | "dropdown"
            dropdownType   = "icon",    -- "icon" | "list" (dropdown mode only)
            dropdownDir    = "right",   -- icon type: "right"|"left"|"up"|"down"
            dropdownPerRow = 5,         -- icon type: icons per row before wrapping
            dropdownAlwaysOpen = false, -- icon type: stay open permanently, no hover/click needed
        },
        slotPopouts = {        -- detached gear-slot buttons (alt+click a char slot)
            locked  = false,
            scale   = 1,
            buttons = {},  -- [slotId] = { point, relPoint, x, y, dir, perRow, anchor }
        },
        -- Phase-4 hardening (all additive; ApplyDefaults leaves existing keys untouched)
        stats = {
            attach = false,            -- dock the stats panel to the character window
            -- Block value source. false (default) = Armory's own calculation per
            -- CSC_BEHAVIOR_SPEC §7.4 (gear scan + Strength/20 + set/enchant terms);
            -- true = GetShieldBlock() verbatim. Additive key; existing saves seed it
            -- from this default, so no migration.
            blizzardBlockValue = false,
        },
        trinkets = {
            -- Cooldown spiral/text on the trinket slots, their detached popouts,
            -- and the trinket flyout. TRINKETMENU_BEHAVIOR_SPEC §6 defaults its
            -- numeric text OFF; Armory has shipped this ON since it was added, so
            -- the released default is kept (turning it off for existing users
            -- would be a silent regression). Additive key, no migration.
            showCooldowns = true,
            -- Spec §4.3 / §6: large = 16pt gold centered, small = 14pt white at
            -- the bottom edge. Spec default is large.
            largeNumbers  = true,
        },
        charWindow = {
            qualityBorders = true,     -- quality-colored soft glow on equipped-slot buttons
        },
        goalPicker = {
            -- Hide items the viewing character can never equip (class locks, opposite
            -- faction, wrong armor/weapon proficiency). Default ON per the owner
            -- directive; the picker's footer toggles it for edge cases. Additive key,
            -- per character on purpose — usability is a property of the character.
            showUnusable = false,
        },
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Addon:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and Addon:DeepCopy(v) or v
    end
    return copy
end

function Addon:GetCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- ── Field Ledger token bridge (BRAND_SPEC rollout) ────────────────────────────
-- Armory renders many transient surfaces (item/set flyouts, radial widget, slot
-- popouts, pickers) that pre-date DaseekiUI and can also run standalone (Core is an
-- OptionalDep). These helpers read live theme tokens when Daseeki-Core is present,
-- so every surface tracks SetTheme, and fall back to Armory's legacy palette when it
-- is absent — the no-Core look is preserved exactly. Colors are read at render time
-- (flyout Layout / radial build / picker refresh run on every open), so no explicit
-- re-skin wiring is needed for those; the few build-once borders register UI.Skin.
--
-- FALLBACK mirrors the historical hardcoded values so a Core-less client is unchanged
-- (dominant black backings + gold accent). brand/bronze fall back to the old gold.
local FALLBACK = {
    ground = { 0.06, 0.05, 0.04 }, inset = { 0, 0, 0 },
    panel  = { 0.09, 0.09, 0.11 }, raised = { 0.13, 0.11, 0.13 },
    border = { 0.30, 0.30, 0.30 }, borderLite = { 0.40, 0.40, 0.40 },
    control = { 0.17, 0.15, 0.11 }, controlBorder = { 0.30, 0.30, 0.30 },
    brand  = { 1, 0.82, 0 }, brandBright = { 1, 0.9, 0.4 },
    bronze = { 1, 0.82, 0 }, bronzeDim = { 0.7, 0.57, 0 }, idle = { 0.43, 0.39, 0.31 },
    text   = { 1, 1, 1 }, muted = { 0.7, 0.7, 0.7 }, faint = { 0.5, 0.5, 0.5 },
    accent = { 1, 0.82, 0 }, ok = { 0.5, 0.9, 0.5 },
    warn   = { 1, 0.53, 0 }, danger = { 0.9, 0.35, 0.28 },
}

-- r,g,b,a from the active theme token, or the legacy fallback when Core is absent.
function Addon:Col(token, alpha)
    local UI = _G.DaseekiUI
    if UI and UI.Color then return UI.Color(token, alpha) end
    local c = FALLBACK[token] or FALLBACK.text
    return c[1], c[2], c[3], alpha or c[4] or 1
end

-- Token → "|cffRRGGBB" escape prefix for chat / popup strings (no FontObject there);
-- nil when Core is absent so callers fall back to a plain/legacy literal.
function Addon:Hex(token)
    local UI = _G.DaseekiUI
    if not (UI and UI.Color) then return nil end
    local r, g, b = UI.Color(token)
    local function b255(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x"):format(b255(r), b255(g), b255(b))
end

-- Wrap `text` in a token color for chat/popup strings; plain text if Core is absent.
function Addon:Wrap(token, text)
    local h = Addon:Hex(token)
    if not h then return tostring(text) end
    return h .. tostring(text) .. "|r"
end

-- Brand-tinted chat identity tag (falls back to the legacy cyan tag without Core).
function Addon:Tag(text)
    text = text or "Armory"
    local h = Addon:Hex("brand")
    if h then return h .. text .. "|r" end
    return "|cff66ccff" .. text .. "|r"
end

-- Apply the ceremonial (MORPHEUS >=16) title font to a FontString when Core is present.
-- Returns true if applied, so callers can keep their legacy color/font otherwise.
function Addon:TrySetCeremonial(fs, size)
    local UI = _G.DaseekiUI
    if UI and UI.GetCeremonialFont then
        fs:SetFontObject(UI.GetCeremonialFont(size or 16))
        return true
    end
    return false
end

-- Apply a shared DaseekiUI body-family font object to a FontString when Core is
-- present — the general form of the two helpers above, for the ordinary surfaces
-- (list rows, hints, counters) that were still left on stock GameFont templates and
-- so ignored the Core font picker. Roles: body / muted / small / accent / danger /
-- header / microLabel. Because these are FontObjects, Core re-applies the picked face
-- and theme tint on every font/theme change for free.
--
-- CALL BEFORE any SetTextColor on the same FontString: SetFontObject also re-applies
-- that object's own color, which would otherwise overwrite the caller's token tint.
-- Without Core this is a no-op and the caller's GameFont template stands — that IS the
-- pre-Core appearance. Returns true when the kit face was applied.
function Addon:TrySetFont(fs, role)
    local UI = _G.DaseekiUI
    if fs and fs.SetFontObject and UI and UI.fonts then
        local fo = UI.fonts[role or "body"] or UI.fonts.body
        if fo then fs:SetFontObject(fo); return true end
    end
    return false
end

-- Apply the telemetry numeral (ARIALN+OUTLINE) font to a FontString when Core present.
function Addon:TrySetNumeral(fs)
    local UI = _G.DaseekiUI
    if UI and UI.fonts and UI.fonts.numeral then
        fs:SetFontObject(UI.fonts.numeral)
        return true
    end
    return false
end

function Addon:Init()
    DaseekiArmoryDB = DaseekiArmoryDB or {}
    ApplyDefaults(DaseekiArmoryDB, DEFAULT_DB)
    Addon.db = DaseekiArmoryDB
end

-- ── Login ─────────────────────────────────────────────────────────────────────
function Addon:OnLogin()
    -- BEFORE InitWidget: the widget asks the dock which mode the swapper is
    -- effectively in, and the subscription's own first delivery is what makes
    -- that answer true rather than hopeful. Subscribing is a push registration —
    -- it never blocks, never polls, and answers "no surface" immediately when
    -- Daseeki-Chat is absent (see chatdock.lua's rendezvous note).
    if Addon.InitChatDock  then Addon:InitChatDock()  end
    if Addon.InitWidget    then Addon:InitWidget()    end
    if Addon.RegisterOptions then Addon:RegisterOptions() end
    if Addon.BuildIconList then Addon:BuildIconList() end
    if Addon.IndexOwnedItems then Addon:IndexOwnedItems() end
    if Addon.InitTooltip     then Addon:InitTooltip()     end
    if Addon.InitPaperdoll   then Addon:InitPaperdoll()   end
    if Addon.InitSlotPopouts then Addon:InitSlotPopouts() end
    if Addon.InitStats     then Addon:InitStats()     end
    if Addon.InitTrinkets  then Addon:InitTrinkets()  end
    if Addon.InitBorders   then Addon:InitBorders()   end
    if Addon.ApplySetBindings then Addon:ApplySetBindings() end
    if Addon.InitGoals then Addon:InitGoals() end
    -- Addon:InitItemScan() USED TO BE CALLED HERE. It bound the account-wide scan
    -- cache and, on an account that had never completed a scan, armed a 15-second
    -- timer that announced "building the item database for the first time" and
    -- walked 32 000 item ids. The item database is shipped in catalog.lua now, so
    -- there is nothing to build, nothing to announce, and no SavedVariable to bind:
    -- the login path does not touch the scan at all. (The scan survives as a
    -- developer tool behind /darmory devscan's flag; see itemScan.lua.)
    if Addon.WarmGoalItems then C_Timer.After(5, function() Addon:WarmGoalItems() end) end

    -- Macro entry points, unique to Armory so they never collide with ItemRack's
    -- global EquipSet(). Use: /run ArmEquip("1 - DPS")
    ArmEquip  = function(name) return Addon:EquipSet(name)  end
    ArmToggle = function(name) return Addon:ToggleSet(name) end
    -- used only by the secure set-binding macro, after its /equipslot lines
    ArmEquipSecure = function(name) return Addon:EquipSet(name, { secureWeapons = true }) end

    local n = 0
    for _ in pairs(Addon.db.sets) do n = n + 1 end
    print(string.format(
        "%s loaded — %d set%s. %s for options.",
        Addon:Tag("Daseeki Armory"), n, n == 1 and "" or "s", Addon:Wrap("text", "/darmory")))
end

-- ── Event wiring ──────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            Addon:Init()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not Addon.db then Addon:Init() end
        Addon:OnLogin()
        ev:UnregisterEvent("PLAYER_LOGIN")
    end
end)
