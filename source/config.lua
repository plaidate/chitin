import "smokeflag" -- must precede any SMOKE_BUILD block (config imports first)

-- Fightin' Chitin - tunables (C) and live state (G). Fixed 30fps step.
-- 400x240 1-bit. Phase 1: two mirror bug fighters, walk/jump/crouch, Light &
-- Heavy normals with hitboxes, block, damage/hitstun/knockdown, round flow
-- (best of 3, 60s timer, KO), HUD, one stage, CPU + headless autopilot.
--
-- G holds the live match: G.state (title|fight|roundover|matchover), the two
-- fighters G.p1/G.p2, round timer/wins, and transient fx.

C = {
    DT = 1 / 30,
    W = 400,
    H = 240,

    GROUND_Y = 200,       -- feet baseline; fighters stand on this line
    MARGIN = 26,          -- how close a body centre may get to a screen edge

    -- physics (per-frame velocities, 30fps)
    GRAVITY = 1.5,
    WALK_SPD = 2.2,
    BACK_SPD = 1.6,       -- walking backward (holding block) is slower
    DASH_SPD = 5.5,
    DASH_FRAMES = 8,
    BACKHOP_VX = 4.5,
    BACKHOP_VY = -8,
    JUMP_VY = -13,
    JUMP_VX = 3.2,

    -- fighter body / hurtbox (relative to centre x, feet at GROUND_Y)
    BODY_W = 44,
    BODY_H = 66,
    CROUCH_H = 40,

    MAX_HP = 100,
    ROUND_TIME = 60,      -- seconds
    ROUNDS_TO_WIN = 2,    -- best of 3
    KNOCKDOWN_LIE = 30,   -- frames flat on your back before getup
    BUFFER = 6,           -- attack-button buffer window (frames)

    -- Phase 2: motion-input parser windows (facing-relative direction history)
    HIST = 14,            -- rolling directional-history length (frames)
    MOTION_END = 4,       -- a motion must COMPLETE within this many frames of now
    CHARGE_MIN = 40,      -- frames of held-back to arm a charge special
    CHARGE_WINDOW = 12,   -- frames after releasing forward the charge stays live
    RING_WINDOW = 40,     -- frames all four extremes must fall within (360 motion)

    -- Phase 2: Frenzy (the crank super meter), per-fighter 0..1
    FRENZY_PER_DEG = 0.0012,  -- meter gained per degree of crank movement
    FRENZY_ON_HIT = 0.06,     -- meter gained when dealing a hit (half when taking)

    -- Phase 5: Molt comeback (DESIGN 3.5). Once per match, at CRITICAL health
    -- with a FULL Frenzy bar, a fighter can shed its exoskeleton (input:
    -- double-tap DOWN + Ⓐ+Ⓑ -- see Fight.control). It heals MOLT_HEAL*maxHp,
    -- consumes the whole Frenzy bar, grants MOLT_INVULN frames of shed invuln,
    -- then TENERAL_FRAMES of "teneral rage": TENERAL_SPD faster, TENERAL_DMG
    -- harder-hitting, but soft -- taking TENERAL_SOFT extra damage.
    MOLT_CRIT = 0.34,         -- HP fraction at/below which Molt is available
    MOLT_HEAL = 0.42,         -- HP restored (fraction of maxHp) on the shed
    MOLT_INVULN = 16,         -- invulnerable frames while shedding the shell
    TENERAL_FRAMES = 96,      -- ~3.2s of teneral rage after the molt
    TENERAL_SPD = 1.35,       -- walk/dash speed multiplier while teneral
    TENERAL_DMG = 1.5,        -- outgoing damage multiplier while teneral
    TENERAL_SOFT = 1.4,       -- incoming damage multiplier while soft (teneral)
    DTAP_WIN = 12,            -- frames between the two DOWN taps for a molt
    DTAP_HOLD = 8,            -- frames the "double-down armed" flag stays live

    -- Phase 5: crank-flick parry (DESIGN 3.3). A fast crank SNAP (>= PARRY_MAG
    -- degrees in one frame) arms a PARRY_WINDOW; an incoming hit landing inside
    -- it is NEGATED, the attacker is thrown into recovery, and the defender is
    -- rewarded FRENZY_ON_PARRY meter. High risk/reward, tight window. (The AI
    -- feeds a synthetic spike so parries fire headless; normal frenzy-cranking
    -- is far below PARRY_MAG so it never trips one.)
    PARRY_MAG = 90,           -- crank degrees/frame that arms a parry
    PARRY_WINDOW = 7,         -- frames the parry stays live after the snap
    FRENZY_ON_PARRY = 0.28,   -- meter awarded for a successful parry

    -- Phase 3: baseline stats (fighter defs in fighters.lua OVERRIDE these). The
    -- fight engine reads f.maxHp / f.walkSpd / f.dashSpd / f.jumpVy / f.weight,
    -- all seeded from the active fighter's def in Fight.newFighter.
    BASE_WEIGHT = 1.0,        -- knockback taken scales by BASE_WEIGHT / f.weight

    -- Phase 3: poison damage-over-time (Assassin Bug's Venom Jab / Liquefy).
    -- A poisoned fighter loses dmgPerTick HP every POISON_EVERY frames for
    -- `ticks` ticks; it can KO. Stacking refreshes to the larger remaining.
    POISON_EVERY = 12,

    -- Phase 3: flight / air-dash (Dragonfly only, def.canFly). Powered flight:
    -- while airTime (stamina) remains she moves freely in the air -- hold Up to
    -- climb, Down to descend, neutral to drift, left/right to fly across. When
    -- stamina runs out she falls and must touch down to recharge.
    FLY_TIME = 90,            -- frames of flight stamina per takeoff (~3s)
    FLY_CLIMB = 3.2,          -- upward speed while holding Up
    FLY_DESCEND = 3.0,        -- downward speed while holding Down
    FLY_DRIFT = 0.5,          -- gentle sink when neither up/down held
    FLY_MOVE = 2.7,           -- free horizontal air speed
    FLY_CEIL = 44,            -- highest her feet may climb (px from top)
    AIRDASH_VX = 7.5,         -- horizontal air-dash burst speed
    AIRDASH_FRAMES = 8,

    START_X1 = 140,
    START_X2 = 260,

    -- Frame data is the single source of truth for balance. Each move locks the
    -- fighter for startup+active+recovery frames. hbox is relative to the
    -- fighter centre, drawn IN FRONT (facing-mirrored), only during active
    -- frames: {x = forward offset to near edge, y = height of top above feet,
    -- w, h}. armAng steers the drawn striking foreleg.
    MOVES = {
        light = {
            startup = 4, active = 3, recovery = 8,
            damage = 6, hitstun = 12, blockstun = 6, kb = 4,
            knockdown = false, low = false, heavy = false,
            armAng = 0.15, hbox = { x = 18, y = 52, w = 34, h = 16 },
        },
        crouchLight = {
            startup = 4, active = 3, recovery = 9,
            damage = 5, hitstun = 12, blockstun = 6, kb = 3,
            knockdown = false, low = true, heavy = false,
            armAng = -0.45, hbox = { x = 16, y = 22, w = 34, h = 14 },
        },
        heavy = {
            startup = 10, active = 4, recovery = 18,
            damage = 14, hitstun = 18, blockstun = 10, kb = 8,
            knockdown = true, low = false, heavy = true,
            armAng = 0.28, hbox = { x = 16, y = 50, w = 44, h = 24 },
        },
        crouchHeavy = { -- sweep: low, knocks down
            startup = 9, active = 4, recovery = 20,
            damage = 12, hitstun = 16, blockstun = 10, kb = 7,
            knockdown = true, low = true, heavy = true,
            armAng = -0.55, hbox = { x = 14, y = 16, w = 48, h = 16 },
        },
    },

    -- Phase 3: per-character specials live in fighters.lua (Fighters.def). They
    -- share the MOVES frame-data shape (startup/active/recovery lock the fighter)
    -- plus a `kind` and kind-specific fields. All are punishable on block/whiff.
    -- Damage is delivered per-kind:
    --   projectile  spawns a G.projectiles entry on the first active frame
    --               (may carry `poison`); L slower/shorter, H faster/longer
    --   reversal    invulnerable during `invuln` startup frames, rises (riseVY),
    --               hits overhead via hbox, hard knockdown
    --   lunge       forward dash attack (lungeVX); armor absorbs `armorHits`
    --   grab        unblockable throw; connects only within `range` (throw + 360)
    --   counter     a brief armed stance (armStart..armEnd frames); a melee hit
    --               landing during it is negated and the attacker is punished
    --   flurry      mashable multi-hit stance (Mandible Flurry); re-hits per
    --               hitEvery, extendable by held/mashed buttons
    --   super       cinematic; invuln startup; consumes the full Frenzy bar;
    --               may be multi-hit (hitEvery) or a grab-launch
    -- moves/specials may carry `poison = {ticks, dmgPerTick}` (Assassin Bug).
}

G = {}
G.projectiles = {}
