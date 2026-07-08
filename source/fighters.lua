-- Phase 3 roster. The single hardcoded Phase-1/2 bug is replaced by a
-- data-driven roster: six fighters, each a definition table the fight engine
-- reads for stats and movelists. NOTHING in fight.lua hardcodes a single
-- character any more -- it reads f.def (seeded in Fight.newFighter).
--
-- A def carries:
--   name, archetype               display strings (also shown on select/HUD)
--   hp, walkSpd, dashSpd, jumpVy  stats (override the C.* baselines)
--   weight                        pushback resistance (knockback / 1..)
--   rig                           which rig silhouette to draw (rig.lua)
--   ending                        2-line Arcade ending (unused until Phase 4)
--   moves                         normals map (a per-char copy of C.MOVES)
--   specials                      motion-slot -> special def. Slots the control
--                                 layer probes: qcfL/qcfH, dpL/dpH, chargeL/
--                                 chargeH, qcbL/qcbH (optional per char),
--                                 grab (360, grapplers), throw + super (all).
--   canFly                        Dragonfly: enables hover + air-dash.
--   aiKit                         motion kinds the autopilot may attempt, so a
--                                 char only ever inputs motions it actually owns.

Fighters = {}

local function dc(t)               -- deep copy (defs share the C.MOVES template)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = dc(v) end
    return o
end

-- a per-character copy of the base normals, optionally tweaked
local function normals(tweak)
    local m = dc(C.MOVES)
    if tweak then tweak(m) end
    return m
end

local DEFS = {}

-- ---------------------------------------------------------------------------
-- 1. RHINOCEROS BEETLE -- grappler (heavy). Highest HP, slowest, startup armor
--    on the heavy normal and the Gore Charge. Pry-&-Flip 360 grab; Gore Charge
--    (charge <->); Super Boulder Toss (grab -> horn-launch across the screen).
-- ---------------------------------------------------------------------------
DEFS.rhino = {
    name = "RHINO BEETLE", archetype = "GRAPPLER", rig = "rhino",
    hp = 108, walkSpd = 1.6, dashSpd = 4.4, jumpVy = -12, weight = 1.35,
    ending = { "The log is his throne once more.", "He flips the sign to: OCCUPIED." },
    moves = normals(function(m)
        m.heavy.damage = 15                   -- (armor removed: was stuffing rushdown)
        m.crouchHeavy.damage = 13
    end),
    aiKit = { "charge", "chargeH", "ring", "throw" },
    specials = {
        chargeL = { -- Gore Charge (light): armored lunge, but very punishable
            startup = 6, active = 8, recovery = 30,
            damage = 12, hitstun = 16, blockstun = 9, kb = 11,
            knockdown = true, armAng = 0.05,
            hbox = { x = 8, y = 30, w = 46, h = 40 },
            kind = "lunge", armorHits = 1, lungeVX = 8,
        },
        chargeH = { -- Gore Charge (heavy)
            startup = 8, active = 8, recovery = 34,
            damage = 16, hitstun = 18, blockstun = 11, kb = 13,
            knockdown = true, heavy = true, armAng = 0.05,
            hbox = { x = 8, y = 28, w = 54, h = 44 },
            kind = "lunge", armorHits = 1, lungeVX = 11,
        },
        grab = { -- Pry-&-Flip: 360 command grab
            startup = 3, active = 2, recovery = 32,
            damage = 17, hitstun = 0, blockstun = 0, kb = 8,
            knockdown = true, armAng = 0.2, kind = "grab", range = 56, command = true,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 10, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 50,
        },
        super = { -- Boulder Toss: grab, launch clear across the screen
            startup = 4, active = 3, recovery = 30,
            damage = 26, hitstun = 0, blockstun = 0, kb = 16,
            knockdown = true, armAng = 0.3, kind = "grab", range = 60,
            isSuper = true, invuln = 8, launchVy = -14,
        },
    },
}

-- ---------------------------------------------------------------------------
-- 2. LEAF-FOOTED BUG -- technical grappler. Leg-Hook 360 throw; Thorn Counter
--    (QCB reflect stance); Super Bramble Suplex (multi-throw chain).
-- ---------------------------------------------------------------------------
DEFS.leaf = {
    name = "LEAF-FOOT", archetype = "TECH GRAPPLER", rig = "leaf",
    hp = 118, walkSpd = 1.9, dashSpd = 4.9, jumpVy = -12.5, weight = 1.45,
    ending = { "Every meadow bows to the hook.", "The thorns remember his name." },
    moves = normals(function(m)
        m.heavy.damage = 15
    end),
    aiKit = { "qcb", "qcbH", "ring", "throw" },
    specials = {
        qcbL = { -- Thorn Counter (light): short arm window, light punish
            startup = 3, active = 10, recovery = 16,
            damage = 0, hitstun = 0, blockstun = 0, kb = 0, armAng = 0.3,
            kind = "counter", armStart = 3, armEnd = 13,
            counterDmg = 13, counterKb = 8,
        },
        qcbH = { -- Thorn Counter (heavy): longer window, bigger punish
            startup = 4, active = 14, recovery = 22,
            damage = 0, hitstun = 0, blockstun = 0, kb = 0, armAng = 0.35,
            kind = "counter", armStart = 4, armEnd = 18,
            counterDmg = 20, counterKb = 11, knockdown = true,
        },
        grab = { -- Leg-Hook: 360 throw
            startup = 3, active = 2, recovery = 28,
            damage = 22, hitstun = 0, blockstun = 0, kb = 8,
            knockdown = true, armAng = 0.2, kind = "grab", range = 56, command = true,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 10, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 50,
        },
        super = { -- Bramble Suplex: multi-throw, heavy damage
            startup = 4, active = 3, recovery = 30,
            damage = 32, hitstun = 0, blockstun = 0, kb = 12,
            knockdown = true, armAng = 0.3, kind = "grab", range = 58,
            isSuper = true, invuln = 8, launchVy = -12,
        },
    },
}

-- ---------------------------------------------------------------------------
-- 3. PRAYING MANTIS -- rushdown glass cannon. LOW HP, fast, high damage. Strike
--    Rush (QCF foreleg dash); Overhead Reap (DP); Super Prayer's End (flurry).
-- ---------------------------------------------------------------------------
DEFS.mantis = {
    name = "MANTIS", archetype = "RUSHDOWN", rig = "mantis",
    hp = 80, walkSpd = 2.7, dashSpd = 6.3, jumpVy = -14, weight = 0.75,
    ending = { "The prayer was never for mercy.", "Only for a faster kill." },
    moves = normals(function(m)
        m.light.damage = 7; m.light.startup = 3
        m.heavy.damage = 16; m.heavy.startup = 9
        m.crouchLight.damage = 6
    end),
    aiKit = { "qcf", "qcfH", "dp", "dpL", "throw" },
    specials = {
        qcfL = { -- Strike Rush (light): quick foreleg lunge
            startup = 5, active = 6, recovery = 18,
            damage = 11, hitstun = 15, blockstun = 8, kb = 7,
            knockdown = false, armAng = 0.2,
            hbox = { x = 10, y = 34, w = 44, h = 20 },
            kind = "lunge", lungeVX = 10,
        },
        qcfH = { -- Strike Rush (heavy): farther, harder
            startup = 7, active = 6, recovery = 24,
            damage = 15, hitstun = 17, blockstun = 10, kb = 9,
            knockdown = true, heavy = true, armAng = 0.2,
            hbox = { x = 10, y = 32, w = 52, h = 22 },
            kind = "lunge", lungeVX = 13,
        },
        dpL = { -- Overhead Reap (light)
            startup = 3, active = 6, recovery = 24,
            damage = 12, hitstun = 16, blockstun = 8, kb = 7,
            knockdown = true, armAng = 0.85,
            hbox = { x = 6, y = 34, w = 32, h = 48 },
            kind = "reversal", invuln = 6, riseVY = -12,
        },
        dpH = { -- Overhead Reap (heavy)
            startup = 4, active = 6, recovery = 30,
            damage = 17, hitstun = 18, blockstun = 10, kb = 9,
            knockdown = true, heavy = true, armAng = 0.9,
            hbox = { x = 6, y = 30, w = 34, h = 58 },
            kind = "reversal", invuln = 8, riseVY = -15,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 9, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 46,
        },
        super = { -- Prayer's End: foreleg flurry (multi-hit)
            startup = 5, active = 16, recovery = 26,
            damage = 6, hitstun = 6, blockstun = 6, kb = 2,
            knockdown = false, heavy = true, armAng = 0.4,
            hbox = { x = 6, y = 22, w = 56, h = 54 },
            kind = "super", invuln = 8, hitEvery = 2,
        },
    },
}

-- ---------------------------------------------------------------------------
-- 4. TIGER BEETLE -- speed rushdown. Fastest walk/dash. Blur Dash (QCF
--    teleport-slash); Mandible Flurry (mashable QCB multi-hit); Super Blur Storm.
-- ---------------------------------------------------------------------------
DEFS.tiger = {
    name = "TIGER BEETLE", archetype = "SPEED", rig = "tiger",
    hp = 94, walkSpd = 3.0, dashSpd = 7.0, jumpVy = -13.5, weight = 0.85,
    ending = { "Nothing on the bark is faster.", "Nothing on the bark is left." },
    moves = normals(function(m)
        m.light.startup = 3; m.light.recovery = 7
        m.heavy.damage = 14
    end),
    aiKit = { "qcf", "qcfH", "qcb", "qcbH", "throw" },
    specials = {
        qcfL = { -- Blur Dash (light): fast short teleport-slash
            startup = 4, active = 5, recovery = 18,
            damage = 10, hitstun = 15, blockstun = 8, kb = 6,
            knockdown = false, armAng = 0.15,
            hbox = { x = 10, y = 32, w = 46, h = 22 },
            kind = "lunge", lungeVX = 13,
        },
        qcfH = { -- Blur Dash (heavy): full-screen crossing slash
            startup = 6, active = 5, recovery = 24,
            damage = 14, hitstun = 17, blockstun = 10, kb = 8,
            knockdown = true, heavy = true, armAng = 0.15,
            hbox = { x = 10, y = 32, w = 54, h = 22 },
            kind = "lunge", lungeVX = 17,
        },
        qcbL = { -- Mandible Flurry (light): mashable multi-hit stance
            startup = 4, active = 14, recovery = 16,
            damage = 3, hitstun = 6, blockstun = 5, kb = 2,
            knockdown = false, armAng = 0.1,
            hbox = { x = 8, y = 30, w = 40, h = 24 },
            kind = "flurry", hitEvery = 3,
        },
        qcbH = { -- Mandible Flurry (heavy): longer, harder
            startup = 5, active = 20, recovery = 20,
            damage = 4, hitstun = 6, blockstun = 5, kb = 2,
            knockdown = false, heavy = true, armAng = 0.1,
            hbox = { x = 8, y = 30, w = 46, h = 26 },
            kind = "flurry", hitEvery = 3,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 9, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 46,
        },
        super = { -- Blur Storm: full-screen dashes (multi-hit)
            startup = 5, active = 18, recovery = 26,
            damage = 5, hitstun = 6, blockstun = 6, kb = 2,
            knockdown = false, heavy = true, armAng = 0.15,
            hbox = { x = 6, y = 24, w = 58, h = 40 },
            kind = "super", invuln = 8, hitEvery = 2,
        },
    },
}

-- ---------------------------------------------------------------------------
-- 5. DRAGONFLY -- aerial zoner. Hover + air-dash (canFly). Wing Buffet (QCF
--    projectile, air-OK); Dogfight Dive (DP aerial overhead); Super Hawking Run.
-- ---------------------------------------------------------------------------
DEFS.dragonfly = {
    name = "DRAGONFLY", archetype = "AERIAL ZONER", rig = "dragonfly",
    hp = 102, walkSpd = 2.4, dashSpd = 6.0, jumpVy = -14.5, weight = 0.8,
    canFly = true,
    ending = { "The pond belongs to the sky.", "And the sky belongs to her." },
    moves = normals(function(m)
        m.heavy.damage = 13
    end),
    aiKit = { "qcf", "qcfH", "dp", "dpL", "fly", "throw" },
    specials = {
        qcfL = { -- Wing Buffet (light): air-OK projectile
            startup = 7, active = 3, recovery = 18,
            damage = 0, hitstun = 0, blockstun = 6, kb = 0, armAng = 0.05,
            kind = "projectile", airOK = true,
            proj = { vx = 6, life = 60, dmg = 10, hitstun = 14, kb = 5 },
        },
        qcfH = { -- Wing Buffet (heavy)
            startup = 9, active = 3, recovery = 22,
            damage = 0, hitstun = 0, blockstun = 6, kb = 0, armAng = 0.05,
            kind = "projectile", airOK = true,
            proj = { vx = 9, life = 95, dmg = 13, hitstun = 16, kb = 6 },
        },
        dpL = { -- Dogfight Dive (light): aerial overhead
            startup = 3, active = 7, recovery = 22,
            damage = 14, hitstun = 16, blockstun = 8, kb = 7,
            knockdown = true, armAng = 0.7,
            hbox = { x = 6, y = 30, w = 34, h = 50 },
            kind = "reversal", invuln = 5, riseVY = -12,
        },
        dpH = { -- Dogfight Dive (heavy)
            startup = 4, active = 7, recovery = 28,
            damage = 18, hitstun = 18, blockstun = 10, kb = 9,
            knockdown = true, heavy = true, armAng = 0.75,
            hbox = { x = 6, y = 28, w = 36, h = 58 },
            kind = "reversal", invuln = 7, riseVY = -15,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 9, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 46,
        },
        super = { -- Hawking Run: multi-angle dive-bombs (multi-hit)
            startup = 5, active = 16, recovery = 26,
            damage = 6, hitstun = 6, blockstun = 6, kb = 3,
            knockdown = false, heavy = true, armAng = 0.5,
            hbox = { x = 6, y = 22, w = 56, h = 56 },
            kind = "super", invuln = 8, hitEvery = 3,
        },
    },
}

-- ---------------------------------------------------------------------------
-- 6. ASSASSIN BUG -- DoT zoner. Long reach. Venom Jab (QCF projectile, applies
--    poison); Rostrum Spear (charge, long-range poke); Super Liquefy (pin +
--    heavy venom DoT).
-- ---------------------------------------------------------------------------
DEFS.assassin = {
    name = "ASSASSIN BUG", archetype = "DoT ZONER", rig = "assassin",
    hp = 114, walkSpd = 2.3, dashSpd = 5.4, jumpVy = -13, weight = 1.0,
    ending = { "It never was a fair fight.", "Patience is its own venom." },
    moves = normals(function(m)
        -- long rostrum: reach on the standing normals
        m.light.hbox.w = 42; m.heavy.hbox.w = 52
    end),
    aiKit = { "qcf", "qcfH", "charge", "chargeH", "throw" },
    specials = {
        qcfL = { -- Venom Jab (light): poison projectile
            startup = 8, active = 3, recovery = 20,
            damage = 0, hitstun = 0, blockstun = 6, kb = 0, armAng = 0.05,
            kind = "projectile",
            proj = { vx = 6, life = 60, dmg = 7, hitstun = 12, kb = 4,
                     poison = { ticks = 6, dmgPerTick = 3 } },
        },
        qcfH = { -- Venom Jab (heavy): stronger poison
            startup = 10, active = 3, recovery = 24,
            damage = 0, hitstun = 0, blockstun = 6, kb = 0, armAng = 0.05,
            kind = "projectile",
            proj = { vx = 8, life = 95, dmg = 9, hitstun = 14, kb = 5,
                     poison = { ticks = 8, dmgPerTick = 3 } },
        },
        chargeL = { -- Rostrum Spear (light): long-range poke
            startup = 7, active = 4, recovery = 22,
            damage = 13, hitstun = 16, blockstun = 9, kb = 8,
            knockdown = false, armAng = 0.0,
            hbox = { x = 14, y = 34, w = 66, h = 14 },
            kind = "lunge", lungeVX = 3,
        },
        chargeH = { -- Rostrum Spear (heavy): longer, knockdown
            startup = 8, active = 4, recovery = 26,
            damage = 17, hitstun = 18, blockstun = 11, kb = 10,
            knockdown = true, heavy = true, armAng = 0.0,
            hbox = { x = 14, y = 34, w = 78, h = 14 },
            kind = "lunge", lungeVX = 4,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 9, hitstun = 0, blockstun = 0, kb = 6,
            knockdown = true, armAng = 0.2, kind = "grab", range = 48,
        },
        super = { -- Liquefy: pin + heavy venom flood
            startup = 4, active = 3, recovery = 30,
            damage = 16, hitstun = 0, blockstun = 0, kb = 4,
            knockdown = true, armAng = 0.3, kind = "grab", range = 56,
            isSuper = true, invuln = 8, launchVy = -8,
            poison = { ticks = 10, dmgPerTick = 4 },
        },
    },
}

-- ---------------------------------------------------------------------------
-- BOSS / 7th pick. ARMY ANT MAJOR -- the intentionally-tougher final CPU on the
-- Arcade ladder (fight 6, after the 5 normal opponents). Its own big-ant rig
-- (big head + mandibles + segmented body), the highest HP on the roster, and a
-- SWARM SUPER (summons a rush of small ant silhouettes across the screen as a
-- multi-hit wall). Beating it clears Arcade and UNLOCKS it as a joke playable
-- pick (persisted -- see save.lua). Kept OUT of Fighters.LIST so it never joins
-- the 6x6 balance matrix or the normal ladder; exposed via Fighters.selectable.
-- ---------------------------------------------------------------------------
DEFS.ant = {
    name = "ARMY ANT", archetype = "THE MAJOR", rig = "ant", boss = true,
    hp = 176, walkSpd = 2.0, dashSpd = 4.6, jumpVy = -11.5, weight = 1.6,
    ending = { "The colony has no ending.", "Only the next mound to take." },
    moves = normals(function(m)
        m.light.damage = 9; m.light.hbox.w = 40
        m.heavy.damage = 18; m.heavy.hbox.w = 50
        m.crouchHeavy.damage = 15
    end),
    aiKit = { "qcf", "qcfH", "throw" },
    specials = {
        qcfL = { -- Mandible Lunge (light)
            startup = 6, active = 7, recovery = 20,
            damage = 13, hitstun = 16, blockstun = 9, kb = 9,
            knockdown = false, armAng = 0.1, armorHits = 1,
            hbox = { x = 12, y = 32, w = 50, h = 26 },
            kind = "lunge", lungeVX = 9,
        },
        qcfH = { -- Mandible Lunge (heavy)
            startup = 8, active = 7, recovery = 26,
            damage = 18, hitstun = 18, blockstun = 11, kb = 12,
            knockdown = true, heavy = true, armAng = 0.1, armorHits = 1,
            hbox = { x = 12, y = 30, w = 60, h = 30 },
            kind = "lunge", lungeVX = 12,
        },
        throw = {
            startup = 2, active = 2, recovery = 22,
            damage = 12, hitstun = 0, blockstun = 0, kb = 7,
            knockdown = true, armAng = 0.2, kind = "grab", range = 52,
        },
        super = { -- Swarm Rush: a full-screen wall of marching ants (multi-hit)
            startup = 6, active = 26, recovery = 24,
            damage = 5, hitstun = 6, blockstun = 6, kb = 3,
            knockdown = false, heavy = true, armAng = 0.2,
            hbox = { x = -60, y = 20, w = 150, h = 70 },
            kind = "super", invuln = 8, hitEvery = 3, swarm = true,
        },
    },
}

-- ---------------------------------------------------------------------------

Fighters.LIST = { "rhino", "leaf", "mantis", "tiger", "dragonfly", "assassin" }
Fighters.BOSS = "ant"

function Fighters.def(id)
    return DEFS[id] or DEFS.rhino
end

function Fighters.count()
    return #Fighters.LIST
end

-- id at a wrapped list index (1-based); used by character select cycling
function Fighters.at(i)
    local n = #Fighters.LIST
    i = ((i - 1) % n) + 1
    return Fighters.LIST[i]
end

function Fighters.index(id)
    for i, v in ipairs(Fighters.LIST) do
        if v == id then return i end
    end
    return 1
end

-- Selectable roster: the 6 base fighters, plus the Army Ant appended once it has
-- been unlocked (G.antUnlocked, set on an Arcade clear and persisted in save.lua).
-- Character select cycles THIS list, so the ant appears the moment it unlocks --
-- in the same session -- while balance / the ladder keep using the base LIST.
function Fighters.selectable()
    local t = {}
    for _, id in ipairs(Fighters.LIST) do t[#t + 1] = id end
    if G.antUnlocked then t[#t + 1] = Fighters.BOSS end
    return t
end

function Fighters.selCount()
    return #Fighters.selectable()
end

function Fighters.selAt(i)
    local l = Fighters.selectable()
    local n = #l
    i = ((i - 1) % n) + 1
    return l[i]
end
