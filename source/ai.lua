-- AI: ONE behaviour function drives the CPU (P2) and, in smoke, both fighters
-- (AI-vs-AI headless). Phase 3: the AI is now ROSTER-AWARE. It only attempts
-- motions the active fighter actually owns (f.def.aiKit), so every character
-- exercises its own specials -- QCF/DP/charge/QCB/360, plus flight for the
-- Dragonfly and the Frenzy super once the meter fills.
--
-- A running script lives on f.ai = { script = {...steps}, i }. Each step is
-- FACING-RELATIVE ({ f = -1/0/1 back/neutral/forward, d/u = down/up, btn/ab });
-- emit() converts it to a screen-space input for the current fighter->foe dir.

AI = {}

local ATTACK_RANGE = 62

local function blank() return Input.blank() end

-- per-frame steps for a named motion (held a couple frames each so the parser
-- sees a clean, lenient sequence, ending on a button press)
local function scriptFor(kind)
    if kind == "qcf" then
        return { { f = 0, d = true }, { f = 0, d = true }, { f = 1, d = true },
                 { f = 1, d = true }, { f = 1 }, { f = 1, btn = "L" } }
    elseif kind == "qcfH" then
        return { { f = 0, d = true }, { f = 0, d = true }, { f = 1, d = true },
                 { f = 1 }, { f = 1, btn = "H" } }
    elseif kind == "qcb" then
        return { { f = 0, d = true }, { f = 0, d = true }, { f = -1, d = true },
                 { f = -1, d = true }, { f = -1 }, { f = -1, btn = "L" } }
    elseif kind == "qcbH" then
        -- mash a couple extra buttons so the flurry EXTENDS (Tiger Beetle)
        return { { f = 0, d = true }, { f = 0, d = true }, { f = -1, d = true },
                 { f = -1 }, { f = -1, btn = "H" }, { btn = "H" }, { btn = "L" } }
    elseif kind == "dp" then
        return { { f = 1 }, { f = 1 }, { f = 0, d = true }, { f = 0, d = true },
                 { f = 1, d = true }, { f = 1, d = true, btn = "H" } }
    elseif kind == "dpL" then
        return { { f = 1 }, { f = 0, d = true }, { f = 1, d = true },
                 { f = 1, d = true, btn = "L" } }
    elseif kind == "charge" then
        local t = {}
        for _ = 1, 44 do t[#t + 1] = { f = -1 } end
        t[#t + 1] = { f = 1 }
        t[#t + 1] = { f = 1, btn = "L" }
        return t
    elseif kind == "chargeH" then
        local t = {}
        for _ = 1, 44 do t[#t + 1] = { f = -1 } end
        t[#t + 1] = { f = 1 }
        t[#t + 1] = { f = 1, btn = "H" }
        return t
    elseif kind == "super" then
        return { { f = 0, d = true }, { f = 0, d = true }, { f = 1, d = true },
                 { f = 1 }, { f = 1 }, { f = 1, ab = true } }
    elseif kind == "ring" then
        return { { f = -1 }, { f = 0, d = true }, { f = 1, d = true }, { f = 1 },
                 { f = 0, u = true }, { ab = true } }
    elseif kind == "throw" then
        return { { ab = true } }
    elseif kind == "molt" then
        -- double-tap DOWN then Ⓐ+Ⓑ (matches the Molt gate in Fight.control):
        -- down, release, down, down+A+B
        return { { d = true }, {}, { d = true }, { d = true, ab = true } }
    end
end

local function emit(f, opp, spec)
    local inp = blank()
    local fwd = (opp.x - f.x) >= 0 and 1 or -1
    if spec.f and spec.f ~= 0 then inp.mvx = spec.f * fwd end
    if spec.d then inp.down = true end
    if spec.u then inp.up = true end
    if spec.btn == "L" then inp.lightPressed = true
    elseif spec.btn == "H" then inp.heavyPressed = true end
    if spec.ab then
        inp.throw = true; inp.lightPressed = true; inp.heavyPressed = true
    end
    return inp
end

local function stepScript(f, opp)
    local ai = f.ai
    local spec = ai.script[ai.i]
    if not spec then ai.script = nil; return nil end
    ai.i = ai.i + 1
    if ai.i > #ai.script then ai.script = nil end
    return emit(f, opp, spec)
end

-- airborne behaviour for a flyer (Dragonfly): stay aloft and manoeuvre, fire
-- air Wing Buffet / Dogfight Dive, occasional air-dash. Holds Up most frames so
-- she sustains altitude (real flight) rather than falling like a jump.
local function airDecide(f, opp)
    f.ai.airT = (f.ai.airT or 0) + 1
    if not f.ai.airScript and (f.ai.airT % 9) == 4 then
        local r = math.random()
        if r < 0.45 then f.ai.airScript = scriptFor("qcf"); f.ai.airI = 1
        elseif r < 0.62 then f.ai.airScript = scriptFor("dpL"); f.ai.airI = 1 end
    end
    if f.ai.airScript then
        local spec = f.ai.airScript[f.ai.airI]
        if spec then
            f.ai.airI = f.ai.airI + 1
            if f.ai.airI > #f.ai.airScript then f.ai.airScript = nil end
            return emit(f, opp, spec)
        end
        f.ai.airScript = nil
    end
    local inp = blank()
    local dir = (opp.x - f.x) >= 0 and 1 or -1
    local r = math.random()
    if r < 0.62 then inp.up = true            -- climb / hold altitude
    elseif r < 0.74 then inp.down = true end  -- swoop down
    if math.random() < 0.7 then inp.mvx = dir end   -- fly toward the foe
    if r > 0.96 then inp.dash = dir end       -- occasional air-dash burst
    return inp
end

function AI.decide(f, opp)
    f.ai = f.ai or { i = 1, cool = 0 }
    f.ai.parryCd = math.max(0, (f.ai.parryCd or 0) - 1)

    if f.hitstun > 0 or f.blockstun > 0 or f.state == "ko"
        or f.state == "knockdown" then
        f.ai.script = nil
        return blank()
    end
    if f.state == "attack" then return blank() end

    -- a running scripted motion (special / MOLT) runs to completion FIRST, so a
    -- parry spike or block can't interrupt it mid-sequence
    if f.onGround and f.ai.script then
        local inp = stepScript(f, opp)
        if inp then return inp end
    end

    -- crank-flick PARRY (Phase 5): as the foe's attack starts up and we're in
    -- range, snap the crank. In smoke there's no physical crank, so this
    -- synthetic spike (>= PARRY_MAG) is what makes parries fire headless.
    if opp.state == "attack" and opp.move
        and (opp.moveFrame or 0) <= (opp.move.startup or 0) + 1
        and math.abs(opp.x - f.x) < 120
        and (f.ai.parryCd or 0) <= 0 and math.random() < 0.5 then
        f.ai.parryCd = 24
        local inp = blank()
        inp.crank = C.PARRY_MAG + 70      -- a hard flick, well past the threshold
        inp.mvx = -f.facing
        return inp
    end

    -- airborne: flyers act, others wait to land (and reset air script)
    if not f.onGround then
        if f.canFly then return airDecide(f, opp) end
        return blank()
    end
    f.ai.airT = 0; f.ai.airScript = nil

    f.ai.cool = math.max(0, (f.ai.cool or 0) - 1)

    -- MOLT comeback (Phase 5): at critical HP with a full Frenzy bar, shed --
    -- heal + teneral rage. Scripts the double-down + Ⓐ+Ⓑ the Molt gate wants.
    if not f.molted and (f.frenzy or 0) >= 1
        and f.hp <= f.maxHp * C.MOLT_CRIT then
        f.ai.script = scriptFor("molt"); f.ai.i = 1
        local inp = stepScript(f, opp)
        if inp then return inp end
    end

    local dx = opp.x - f.x
    local ad = math.abs(dx)
    local dir = dx >= 0 and 1 or -1

    -- block a close incoming attack
    if opp.state == "attack" and ad < 95 and math.random() < 0.35 then
        local inp = blank()
        inp.mvx = -f.facing
        if opp.moveName == "crouchLight" or opp.moveName == "crouchHeavy" then
            inp.down = true
        elseif math.random() < 0.25 then
            inp.down = true
        end
        return inp
    end

    -- launch a scripted special from this fighter's own kit
    if f.ai.cool <= 0 and ad < 165 then
        local kit = f.def.aiKit or {}
        local pick
        if not f.ai.didFirst and #kit > 0 then
            pick = kit[1]; f.ai.didFirst = true; f.ai.cool = 22   -- signature early
        elseif (f.frenzy or 0) >= 1 and f.def.specials.super
            and (f.molted or f.hp > f.maxHp * (C.MOLT_CRIT + 0.18))
            and math.random() < (f.def.boss and 0.95 or 0.5) then
            -- hold a full bar for the MOLT once HP dips toward critical; the boss
            -- leans hard on its Swarm super so the wall reliably shows up
            pick = "super"; f.ai.cool = 50
        elseif #kit > 0 and math.random() < 0.6 then
            pick = kit[math.random(#kit)]; f.ai.cool = 30
        end
        -- range gates for close-only motions
        if pick == "throw" and ad > 58 then pick = nil end
        if pick == "ring" and ad > 72 then pick = nil end

        if pick == "fly" then
            local inp = blank(); inp.up = true
            f.ai.cool = 42
            return inp
        elseif pick then
            f.ai.script = scriptFor(pick)
            if f.ai.script then
                f.ai.i = 1
                local inp = stepScript(f, opp)
                if inp then return inp end
            end
        end
    end

    -- neutral movement + Frenzy building (crank while the meter isn't full)
    local inp = blank()
    if (f.frenzy or 0) < 1 then inp.crank = 16 end

    if ad > ATTACK_RANGE then
        inp.mvx = dir
        local r = math.random()
        if r < 0.03 then inp.dash = dir
        elseif r < 0.06 and f.canFly then inp.up = true      -- flyers take to the air
        elseif r < 0.05 then inp.up = true; inp.mvx = dir end
        return inp
    end

    local r = math.random()
    if r < 0.40 then
        inp.lightPressed = true
        if math.random() < 0.35 then inp.down = true end
    elseif r < 0.62 then
        inp.heavyPressed = true
        if math.random() < 0.30 then inp.down = true end
    elseif r < 0.74 then
        inp.dash = -f.facing
    elseif r < 0.84 then
        inp.up = true
    else
        inp.mvx = -f.facing
    end
    return inp
end
