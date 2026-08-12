--[[
    Daseeki Armory — THE CHAT DOCK: the set swapper as a vertical column of set
    icons anchored outside Daseeki-Chat's right edge.

    Owner, 2026-08-12, verbatim: "i want to try integrating the armory set
    swapper with the Daseeki-Chat window. if the option in armory is 'Chat' for
    the set swapper i want it to anchor the sets in a single vertical column on
    the right side of the chat panel. size the icons so that 10 sets can fit the
    panel. the selected set should have a green border around it. if its unknown
    what set was chosen last then ignore the green border."

    ── THE CONTRACT, AND WHO OWNS WHICH HALF ─────────────────────────────────────
    Daseeki-Chat publishes a GENERIC attach surface (_G.DaseekiChatAttach): the
    chassis frame, its live geometry, and a subscription that pushes a new answer
    whenever that geometry changes. It knows nothing about Armory, gear sets or
    columns — the whole "put ten icons down the right-hand side" decision lives
    in THIS file, in THIS repo. Chat gained a published shape and zero behaviour.

    ── WHY NOTHING POLLS, AND NOTHING TIMES ──────────────────────────────────────
    Class 2 says event-gate, never timer-guess, and this seam has a real ordering
    hazard: Chat's view module and Armory's login both come up on PLAYER_LOGIN,
    in an order nobody defines. It is answered rather than bet on:
      * The attach TABLE is published at Chat's file-load time, so it exists for
        the whole session before any login event, in either load order. No
        OptionalDeps line is required to make it appear (and none is added).
      * Subscribe DELIVERS THE CURRENT ANSWER at registration — honestly "nothing
        is there yet" if the view has not enabled — and Chat announces again the
        moment it does enable. So whichever addon wins the coin flip, both ends
        converge on the same geometry, and neither ever asks twice.
      * Every later change (resize, move, tab-placement, enable, disable) arrives
        on the same push. There is no state here that has to be re-read on a
        schedule, so nothing here schedules.

    ── THE FALLBACK POSTURE, WHICH IS THE DEFAULT ────────────────────────────────
    "Chat" is a PLACEMENT that needs a surface. Without Daseeki-Chat installed,
    with its view module disabled, or with the addon simply not painting, there
    is no surface — and a placement without a place is not a mode. The swapper
    then runs in the shipped default (radial), exactly as it does today, with no
    error, no message and no frame created. Every other mode is untouched: this
    file creates nothing at all until the mode is "chat" AND a surface answers.
--]]

local _, Addon = ...

-- ── THE OWNER'S NUMBERS ───────────────────────────────────────────────────────
-- Ten icons fit the panel. That is the sizing RULE, not a cap on how many sets
-- are drawn: eleven sets are drawn at the ten-fit size and the column runs past
-- the panel's bottom edge, because inventing a scroller for a case the owner
-- does not have would be a bigger surprise than a slightly long column.
Addon.CHAT_DOCK_SLOTS    = 10
Addon.CHAT_DOCK_GAP      = 2
Addon.CHAT_DOCK_MIN_ICON = 4     -- below this the ten-fit rule yields to legibility
Addon.CHAT_DOCK_BORDER   = 2     -- the selected-set edge, in UI units

-- The published global Daseeki-Chat's attach surface lands on, and the contract
-- version this file was written against.
Addon.CHAT_ATTACH_GLOBAL  = "DaseekiChatAttach"
Addon.CHAT_ATTACH_API_MIN = 1

-- What the swapper falls back to when "chat" has no surface: the DEFAULT_DB
-- mode, so the fallback is the shipped behaviour and not a third posture.
Addon.SWAPPER_FALLBACK_MODE = "radial"

local ATTACH_FNS = { "Available", "Surface", "Geometry", "Subscribe", "Unsubscribe" }

-- ── PRESENCE PROBE ────────────────────────────────────────────────────────────
-- Type-guarded at every step, with a human reason on refusal (the nexus.lua
-- precedent). `G` is injectable so the harness can drive absence, partial
-- surfaces and version mismatches without a client.
function Addon:ChatAttachSurface(G)
    G = G or _G
    if type(G) ~= "table" then return nil, "no global table" end
    local A = G[Addon.CHAT_ATTACH_GLOBAL]
    if type(A) ~= "table" then
        return nil, "Daseeki-Chat is not installed (no attach surface published)"
    end
    local api = tonumber(A.API_VERSION)
    if not api or api < Addon.CHAT_ATTACH_API_MIN then
        return nil, "the attach surface is older than this build understands"
    end
    for _, fname in ipairs(ATTACH_FNS) do
        if type(A[fname]) ~= "function" then
            return nil, "the attach surface lacks " .. fname .. " (API mismatch)"
        end
    end
    return A
end

-- Is there a chat panel to hang the column on RIGHT NOW? An absent addon, a
-- disabled view and a chassis that is not painting are all the same answer, and
-- none of them is an error.
function Addon:ChatDockAvailable(G)
    local A = Addon:ChatAttachSurface(G)
    if not A then return false end
    local ok, avail = pcall(A.Available)
    return (ok and avail) and true or false
end

-- ── THE MODE THE SWAPPER ACTUALLY RUNS IN ─────────────────────────────────────
-- Every other value passes through untouched, so "radial" and "dropdown" are
-- byte-identical to what they were before this file existed.
function Addon:EffectiveSwapperMode(G)
    local s = Addon.db and Addon.db.settings
    local w = s and s.widget
    local mode = (w and w.mode) or Addon.SWAPPER_FALLBACK_MODE
    if mode ~= "chat" then return mode end
    if Addon:ChatDockAvailable(G) then return "chat" end
    return Addon.SWAPPER_FALLBACK_MODE
end

-- The column is showing when the swapper is enabled, its placement is "chat",
-- and a surface answers. All three, or nothing is created.
function Addon:ChatDockActive(G)
    local s = Addon.db and Addon.db.settings
    local w = s and s.widget
    if not (w and w.show) then return false end
    return Addon:EffectiveSwapperMode(G) == "chat"
end

-- ── THE ICON MATH ─────────────────────────────────────────────────────────────
-- Ten icons and nine gaps fill the chassis height EXACTLY:
--     icon = (height - (slots - 1) * gap) / slots
-- Fractional sizes are kept rather than rounded away, because rounding is what
-- would make ten icons stop meeting the bottom edge — the one property the
-- owner asked for by name. Returns nil for a height that is not a height
-- (Class 5: an unknown height is not a zero-height panel), and clamps at
-- MIN_ICON with a second return of true so a caller can say the rule yielded.
function Addon:ChatDockIconSize(chassisHeight)
    local h = tonumber(chassisHeight)
    if not h or h <= 0 then return nil end
    local slots = Addon.CHAT_DOCK_SLOTS
    local gap   = Addon.CHAT_DOCK_GAP
    local size  = (h - (slots - 1) * gap) / slots
    if size < Addon.CHAT_DOCK_MIN_ICON then
        return Addon.CHAT_DOCK_MIN_ICON, true
    end
    return size, false
end

-- ── WHICH SET IS SELECTED, AND WHEN WE HONESTLY DO NOT KNOW ───────────────────
-- db.currentSet is the LAST EQUIPPED set's name — written by equip.lua when a
-- swap lands, cleared by sets.lua when that set is deleted, carried across a
-- rename, and seeded from an ItemRack import. It is nil on a character that has
-- never swapped through Armory this install.
--
-- THE OWNER'S EXPLICIT RULE: "if its unknown what set was chosen last then
-- ignore the green border." So nil is NOT dressed up. Neither is a name that no
-- longer resolves to a set — a stale pointer is not knowledge, and painting a
-- border on nothing (or on the wrong row) would be worse than painting none.
-- The green border is therefore drawn ONLY when the name resolves to a set that
-- is actually in the column.
function Addon:ChatDockSelectedSet()
    local db = Addon.db
    local cur = db and db.currentSet
    if type(cur) ~= "string" or cur == "" then return nil end
    if not (db.sets and db.sets[cur]) then return nil end
    return cur
end

-- ── THE LAYOUT, AS DATA ───────────────────────────────────────────────────────
-- One pure function produces the whole column: sizes, offsets, which row wears
-- the border, and the anchor triple. The frame layer below only applies it, and
-- the harness drives it with no client at all — so the arithmetic the owner
-- specified is pinned rather than inferred from pixels.
--
-- ANCHORING: TOPLEFT of the column to TOPRIGHT of the chassis. That is OUTSIDE
-- the box, past its border, top-aligned to the box's top — which also means a
-- right-side TAB RAIL (which lives INSIDE the chassis) can never collide with
-- it, and a drag needs no announce at all, because an anchored child moves with
-- its parent for free.
function Addon:ChatDockPlan(geom)
    if type(geom) ~= "table" then return nil, "no geometry" end
    local size, clamped = Addon:ChatDockIconSize(geom.height)
    if not size then return nil, "the chassis has no resolvable height" end

    local gap   = Addon.CHAT_DOCK_GAP
    local slots = Addon.CHAT_DOCK_SLOTS
    local sets  = Addon:GetSetsSorted()          -- ARMORY'S OWN ORDER (Class 8: sorted)
    local sel   = Addon:ChatDockSelectedSet()

    local rows, selectedRow = {}, nil
    for i, set in ipairs(sets) do
        local isSel = (sel ~= nil) and (set.name == sel)
        if isSel then selectedRow = i end
        rows[i] = {
            name     = set.name,
            icon     = set.icon or Addon.DEFAULT_ICON,
            y        = -((i - 1) * (size + gap)),
            selected = isSel,
        }
    end

    local n = #rows
    return {
        size     = size,
        gap      = gap,
        slots    = slots,
        count    = n,
        width    = size,
        height   = (n > 0) and (n * size + (n - 1) * gap) or 0,
        -- The ten-fit answer, always — a column of three still uses the size
        -- ten would need, and simply fills from the top.
        fitHeight = slots * size + (slots - 1) * gap,
        point    = "TOPLEFT",
        relPoint = "TOPRIGHT",
        x        = 0,
        y        = 0,
        border   = Addon.CHAT_DOCK_BORDER,
        selected = (selectedRow ~= nil) and sel or nil,
        selectedRow = selectedRow,
        rows     = rows,
        -- Honest flags rather than silent behaviour: the column runs past the
        -- panel's bottom edge when there are more sets than slots, or when the
        -- panel got too short for the ten-fit size to stay legible.
        overflow = (n > slots) or clamped,
        clamped  = clamped,
    }
end

-- ══ THE FRAME LAYER ═══════════════════════════════════════════════════════════
-- Nothing below runs until the dock is ACTIVE, so an Armory in any other mode
-- (or on a client with no Daseeki-Chat) has created no frame, no texture and no
-- script — the inert pin the harness asserts.

local dock

local function ensureDock(parent)
    if dock then
        if parent and dock:GetParent() ~= parent then dock:SetParent(parent) end
        return dock
    end
    if type(_G.CreateFrame) ~= "function" then return nil end
    local f = _G.CreateFrame("Frame", "DaseekiArmoryChatDock", parent or _G.UIParent)
    f:Hide()
    f.btns = {}
    dock = f
    Addon._chatDock = f     -- reachable for /darmory and the harness; never a second owner
    return f
end

local EDGE_SIDES = { "top", "bottom", "left", "right" }   -- ordered, never pairs()

-- One column button. Built once, re-sized on every layout beat (the chassis is
-- resizable and the icon size is a function of its height).
local function makeButton(i)
    local b = _G.CreateFrame("Button", nil, dock)
    b:RegisterForClicks("LeftButtonUp")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(Addon:Col("brand", 0.3))

    -- THE GREEN BORDER, as four OVERLAY edges rather than a backdrop: a backdrop
    -- edgeFile is a repeating art texture whose thickness is whatever the file
    -- is, and the owner asked for a thin green edge. Four flat textures are
    -- exactly that, at exactly CHAT_DOCK_BORDER units, in the theme's own green
    -- (Core's "ok" token, falling back to Armory's legacy green without Core).
    b.edges = {}
    for _, side in ipairs(EDGE_SIDES) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:Hide()
        b.edges[side] = t
    end

    b:SetScript("OnEnter", function(self)
        if not self._name then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:AddLine(self._name, 1, 0.82, 0)
        if self._selected then
            -- Three components only: AddLine's fourth argument is `wrap`, and
            -- handing it an alpha would turn a colour into a layout instruction.
            local r, g, bl = Addon:Col("ok")
            _G.GameTooltip:AddLine("Currently equipped set", r, g, bl)
        end
        _G.GameTooltip:AddLine("Click to equip", 0.7, 0.7, 0.7)
        _G.GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    -- THE CLICK IS THE SWAPPER'S OWN, unchanged: Addon:EquipSet already owns the
    -- combat-lockdown rules (queue the swap, announce it if chatMessages is on,
    -- drain when combat ends). Only the container and its anchoring are new.
    b:SetScript("OnClick", function(self)
        if self._name then Addon:EquipSet(self._name) end
    end)

    dock.btns[i] = b
    return b
end

local function paintEdges(b, thick, on)
    if not on then
        for _, side in ipairs(EDGE_SIDES) do b.edges[side]:Hide() end
        return
    end
    local r, g, bl, a = Addon:Col("ok")
    local t = b.edges.top
    t:ClearAllPoints(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
    t:SetHeight(thick); t:SetColorTexture(r, g, bl, a or 1); t:Show()
    t = b.edges.bottom
    t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
    t:SetHeight(thick); t:SetColorTexture(r, g, bl, a or 1); t:Show()
    t = b.edges.left
    t:ClearAllPoints(); t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT")
    t:SetWidth(thick); t:SetColorTexture(r, g, bl, a or 1); t:Show()
    t = b.edges.right
    t:ClearAllPoints(); t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT")
    t:SetWidth(thick); t:SetColorTexture(r, g, bl, a or 1); t:Show()
end

-- Returns FALSE on purpose: RefreshChatDock hands this back, so its return value
-- reads "the column is up" rather than "the call succeeded". Note it never
-- CREATES the frame — a swapper that has never docked has no frame to hide.
function Addon:HideChatDock()
    if dock then dock:Hide() end
    return false
end

-- Apply a plan to the frames. Split from RefreshChatDock so the plan can be
-- computed (and pinned) without a client.
function Addon:ApplyChatDockPlan(plan, chassis)
    if not (plan and chassis) then return false end
    local f = ensureDock(chassis)
    if not f then return false end

    f:SetParent(chassis)
    -- The chassis belongs to ANOTHER ADDON: every method we call on it is
    -- type-checked, so a future Chat that hands back a different kind of object
    -- degrades to a plainly-anchored column instead of erroring in its layout.
    if type(chassis.GetFrameStrata) == "function" then
        f:SetFrameStrata(chassis:GetFrameStrata())
    end
    -- Above the chassis, so the icons are never drawn under the box's own art.
    local lvl = (type(chassis.GetFrameLevel) == "function") and chassis:GetFrameLevel() or 1
    f:SetFrameLevel((lvl or 1) + 5)
    f:ClearAllPoints()
    f:SetPoint(plan.point, chassis, plan.relPoint, plan.x, plan.y)
    f:SetSize(math.max(plan.width, 1), math.max(plan.height, 1))

    for _, b in ipairs(f.btns) do b:Hide() end
    for i, row in ipairs(plan.rows) do
        local b = f.btns[i] or makeButton(i)
        b:SetSize(plan.size, plan.size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, row.y)
        b.bg:SetColorTexture(Addon:Col("inset", 0.6))
        b.icon:SetTexture(row.icon)
        b._name, b._selected = row.name, row.selected
        paintEdges(b, plan.border, row.selected)
        b:Show()
    end
    f:Show()
    return true
end

-- The single refresh beat. Called from the geometry announce, from
-- RefreshWidget (so a swap / add / rename / delete re-paints the column and its
-- border), and from the options pane's live-apply.
function Addon:RefreshChatDock()
    if not Addon:ChatDockActive() then return Addon:HideChatDock() end
    local A = Addon:ChatAttachSurface()
    if not A then return Addon:HideChatDock() end
    local okG, geom = pcall(A.Geometry)
    if not okG or type(geom) ~= "table" then return Addon:HideChatDock() end
    local chassis = geom.frame
    if type(chassis) ~= "table" then return Addon:HideChatDock() end
    local plan = Addon:ChatDockPlan(geom)
    if not plan then return Addon:HideChatDock() end
    return Addon:ApplyChatDockPlan(plan, chassis)
end

-- ── THE SUBSCRIPTION ──────────────────────────────────────────────────────────
-- One registration, at login. It is a PUSH: the surface answers immediately
-- with whatever is true right now (possibly nothing), and again on every
-- geometry change — so a resize re-sizes the icons live, with no OnUpdate, no
-- ticker and no repeat probing anywhere in this file.
Addon._chatDockSubscribed = false

function Addon:OnChatGeometry(geom, why)
    Addon._chatDockGeom = geom
    Addon._chatDockWhy  = why
    Addon:RefreshChatDock()
end

function Addon:InitChatDock(G)
    if Addon._chatDockSubscribed then return true end
    local A, why = Addon:ChatAttachSurface(G)
    if not A then
        Addon._chatDockWhy = why
        return false, why
    end
    local handler = function(geom, w) Addon:OnChatGeometry(geom, w) end
    Addon._chatDockHandler = handler
    local ok = pcall(A.Subscribe, handler)
    if not ok then return false, "Subscribe raised" end
    Addon._chatDockSubscribed = true
    return true
end
