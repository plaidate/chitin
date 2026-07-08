-- Fight engine: fighter physics, hitbox/hurtbox resolution, damage, hitstun,
-- blockstun, knockdown. Phase 3: fully DATA-DRIVEN -- every stat and movelist is
-- read from the active fighter's def (f.def, seeded in newFighter from
-- Fighters.def). No single character is hardcoded here.
--
-- Phase-3 systems added on top of Phase 1/2: poison damage-over-time, a
-- counter/reflect stance, a mashable flurry, flight/air-dash (Dragonfly), and
-- weight-scaled knockback / push.
--
-- Fighter state machine (f.state):
--   idle | walk | crouch | block | jump | attack | hitstun | blockstun |
--   knockdown | ko
-- Coordinates: f.x = horizontal centre, f.y = feet (== C.GROUND_Y grounded);
-- the body is drawn upward from the feet. f.facing is +1 (right) / -1 (left).

Fight = {}

local function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- knockback taken scales down with the receiver's weight (heavier = sturdier)
local function kbScale(b)
    return C.BASE_WEIGHT / (b.weight or 1)
end

function Fight.newFighter(x, facing, isP1, defId)
    local def = Fighters.def(defId or "rhino")
    local hp0 = def.hp or C.MAX_HP
    -- balance mode halves HP so AI-vs-AI rounds KO fast (relative match-ups
    -- are preserved; both sides scale the same)
    if G.balance and C.BALANCE_HP_SCALE then
        hp0 = math.floor(hp0 * C.BALANCE_HP_SCALE)
    end
    local f = {
        defId = defId, def = def,
        x = x, y = C.GROUND_Y, facing = facing, isP1 = isP1,
        -- stats from the def (fall back to C.* baselines)
        maxHp = hp0,
        walkSpd = def.walkSpd or C.WALK_SPD,
        dashSpd = def.dashSpd or C.DASH_SPD,
        jumpVy = def.jumpVy or C.JUMP_VY,
        weight = def.weight or C.BASE_WEIGHT,
        canFly = def.canFly or false,
        hp = hp0,
        vx = 0, vy = 0, onGround = true,
        state = "idle", stateTimer = 0,
        move = nil, moveName = nil, moveFrame = 0, connected = false,
        hitstun = 0, blockstun = 0, getup = 0,
        crouching = false, blocking = false, lowBlock = false,
        dash = 0, hitFlash = 0, walkPhase = 0,
        -- Phase 2
        frenzy = 0, cranking = false,
        armorHits = 0, projSpawned = false, grabDone = false, superLastHit = -100,
        -- Phase 3
        poison = nil, flurryMash = 0,
        airTime = 0, airDashed = false, flying = false, flyVy = 0, airDashFr = 0,
    }
    Motion.reset(f)
    return f
end

function Fight.addFrenzy(f, amt)
    if not f then return end
    f.frenzy = Util.clamp((f.frenzy or 0) + amt, 0, 1)
    G.frenzyPeak = math.max(G.frenzyPeak or 0, f.frenzy)  -- highest ever, for smoke
end

-- invulnerable during a reversal/super/grab-super startup window, OR during the
-- brief Molt-shed window (f.moltInvuln, Phase 5)
function Fight.isInvuln(f)
    if (f.moltInvuln or 0) > 0 then return true end
    return f.state == "attack" and f.move and f.move.invuln
        and f.moveFrame <= f.move.invuln
end

-- Phase 5: teneral-rage damage scaling. A teneral attacker hits TENERAL_DMG
-- harder; a teneral (soft) defender takes TENERAL_SOFT extra. Applied to every
-- damage path (melee / grab / projectile).
function Fight.dmgMul(attacker, defender)
    local m = 1
    if attacker and (attacker.teneral or 0) > 0 then m = m * C.TENERAL_DMG end
    if defender and (defender.teneral or 0) > 0 then m = m * C.TENERAL_SOFT end
    return m
end

-- Phase 5: MOLT. Shed the exoskeleton -- a one-time-per-match comeback. Heals a
-- chunk, drops a discarded shell husk, grants shed-invuln then teneral rage;
-- consumes the full Frenzy bar. Preconditions (critical HP + full meter + not
-- yet molted) are checked by the caller (Fight.control).
function Fight.startMolt(f)
    f.molted = true
    -- once PER MATCH: remember the shed on the match-level side flag so a fresh
    -- round (newFighter) re-seeds it and the fighter can't molt again this match
    if f.isP1 then G.moltedP1 = true else G.moltedP2 = true end
    f.frenzy = 0
    f.hp = math.min(f.maxHp, f.hp + math.floor(f.maxHp * C.MOLT_HEAL))
    f.moltInvuln = C.MOLT_INVULN
    f.teneral = C.TENERAL_FRAMES
    -- leave the shed shell behind (drawn by Draw for the rest of the round)
    f.moltShell = { x = f.x, y = f.y, facing = f.facing, rig = f.def and f.def.rig }
    -- interrupt whatever we were doing; stand up teneral
    f.state = "idle"
    f.move = nil; f.moveName = nil; f.moveFrame = 0
    f.hitstun = 0; f.blockstun = 0
    f.vx = 0
    Draw.spark(f.x, f.y - 40, true)
    G.shake = math.max(G.shake or 0, 9)
    Sfx.molt()
    Harness.count("molts")
end

-- effective active length (flurry extends while mashed)
local function activeLen(f)
    local mv = f.move
    if not mv then return 0 end
    if mv.kind == "flurry" then return mv.active + (f.flurryMash or 0) end
    return mv.active
end

-- ---- poison (damage-over-time) -----------------------------------------------

function Fight.applyPoison(target, pdef)
    if not target or not pdef or target.state == "ko" then return end
    local cur = target.poison
    -- refresh to the stronger of the current / incoming stacks
    if not cur or pdef.ticks > (cur.ticks or 0) then
        target.poison = { ticks = pdef.ticks, dmgPerTick = pdef.dmgPerTick,
                          timer = C.POISON_EVERY }
    end
    Harness.count("poisons")
end

function Fight.tickPoison(f)
    local p = f.poison
    if not p or f.state == "ko" then return end
    p.timer = p.timer - 1
    if p.timer > 0 then return end
    p.timer = C.POISON_EVERY
    f.hp = f.hp - p.dmgPerTick
    f.hitFlash = 2
    p.ticks = p.ticks - 1
    Harness.count("poisonTicks")
    if p.ticks <= 0 then f.poison = nil end
    if f.hp <= 0 then f.hp = 0; Fight.ko(f) end
end

-- ---- moves -------------------------------------------------------------------

function Fight.startMove(f, name)
    local mv = f.def.moves[name]
    if not mv then return end
    f.state = "attack"
    f.moveName = name
    f.move = mv
    f.moveFrame = 0
    f.connected = false
    f.armorHits = mv.armorHits or 0
    f.flurryMash = 0
    f.vx = 0
    f.blocking = false
    Sfx.whiff()
    Harness.count("attacks")
end

-- start a per-character special (motion move). Locks the fighter for the full
-- startup+active+recovery; no cancels in Phase 2/3.
function Fight.startSpecial(f, name)
    local mv = f.def.specials[name]
    if not mv then return end
    local airborne = not f.onGround
    f.state = "attack"
    f.moveName = name
    f.move = mv
    f.moveFrame = 0
    f.connected = false
    f.projSpawned = false
    f.grabDone = false
    f.superLastHit = -100
    f.flurryMash = 0
    f.armorHits = mv.armorHits or 0
    f.blocking = false
    f.bufLight = 0
    f.bufHeavy = 0
    -- an air-OK projectile keeps the fighter's airborne momentum; everything else
    -- plants / launches from the ground
    if not (mv.airOK and airborne) then
        f.vx = 0
    end
    f.flying = false                 -- specials manage their own vy (dive/rise)
    if mv.kind == "reversal" then
        f.onGround = false
        f.vy = mv.riseVY or -12
        f.vx = f.facing * 1.5
    elseif mv.kind == "lunge" then
        f.vx = f.facing * (mv.lungeVX or 8)
    end
    Sfx.whiff()
    if mv.isSuper or mv.kind == "super" then
        Harness.count("supers")
        Sfx.super()
        G.shake = math.max(G.shake or 0, 8)
        -- Army Ant SWARM super: a wall of little ants sweeps across the screen
        -- (visual overlay; damage comes from the wide multi-hit super hbox).
        if mv.swarm then
            G.swarmFx = { life = mv.startup + activeLen(f) + mv.recovery,
                          dir = f.facing, owner = f }
            Harness.count("swarms")
        end
    elseif mv.kind == "grab" then
        Harness.count("grabs")
    elseif mv.kind == "counter" then
        Harness.count("counters")
    else
        Harness.count("specials")
    end
end

function Fight.moveActive(f)
    if f.state ~= "attack" or not f.move then return false end
    local mv = f.move
    return f.moveFrame > mv.startup and f.moveFrame <= mv.startup + activeLen(f)
end

-- projectile: spawn one blob (one per owner onscreen at a time)
function Fight.spawnProjectile(f, mv)
    G.projectiles = G.projectiles or {}
    for _, p in ipairs(G.projectiles) do
        if p.owner == f then return end
    end
    local pr = mv.proj
    G.projectiles[#G.projectiles + 1] = {
        x = f.x + f.facing * 26, y = f.y - 42,
        vx = f.facing * pr.vx, facing = f.facing,
        dmg = pr.dmg, hitstun = pr.hitstun, kb = pr.kb, life = pr.life,
        poison = pr.poison, owner = f,
    }
    Harness.count("projectiles")
    Sfx.spit()
end

function Fight.applyProjectileHit(p, b)
    if Fight.isInvuln(b) then return end
    -- crank-flick parry negates the projectile too (no attacker recovery)
    if Fight.tryParry(p.owner, b, p.x, p.y, true) then return end
    -- counter/reflect: an armed counter bounces the projectile back at its owner
    if b.state == "attack" and b.move and b.move.kind == "counter"
        and b.moveFrame >= b.move.armStart and b.moveFrame <= b.move.armEnd then
        p.vx = -p.vx
        p.facing = -p.facing
        p.owner = b
        Harness.count("counters")
        Sfx.block()
        Draw.spark(p.x, p.y, false)
        G.shake = math.max(G.shake, 3)
        b.state = "idle"; b.move = nil; b.moveName = nil
        return
    end
    local canBlock = b.blocking and b.onGround and b.state ~= "attack"
        and b.hitstun <= 0
    if canBlock then
        b.blockstun = 8
        b.state = "blockstun"
        b.vx = p.facing * 2
        if b.cranking then b.hp = math.max(0, b.hp - 1) end
        Sfx.block()
        Draw.spark(p.x, p.y, false)
        G.shake = math.max(G.shake, 2)
        return
    end
    b.hp = b.hp - p.dmg * Fight.dmgMul(p.owner, b)
    b.hitFlash = 4
    Sfx.hit()
    Draw.spark(p.x, p.y, false)
    G.shake = math.max(G.shake, 3)
    Harness.count("hits")
    Fight.addFrenzy(p.owner, C.FRENZY_ON_HIT)
    Fight.addFrenzy(b, C.FRENZY_ON_HIT * 0.5)
    if p.poison then Fight.applyPoison(b, p.poison) end
    if b.hp <= 0 then b.hp = 0; Fight.ko(b); return end
    b.state = "hitstun"
    b.hitstun = p.hitstun
    b.vx = p.facing * p.kb * kbScale(b)
end

-- command grab / plain throw / grab-super: unblockable, connects only within range
function Fight.tryGrab(f, opp, mv)
    f.grabDone = true
    if not opp or opp.state == "ko" then return end
    if Fight.isInvuln(opp) then return end
    if math.abs(opp.x - f.x) > (mv.range or 50) then return end  -- whiff
    opp.hp = opp.hp - mv.damage * Fight.dmgMul(f, opp)
    opp.hitFlash = 4
    Sfx.hit()
    Draw.spark((f.x + opp.x) / 2, f.y - 40, mv.isSuper)
    G.shake = math.max(G.shake, mv.isSuper and 9 or 6)
    Harness.count("hits")
    Fight.addFrenzy(f, C.FRENZY_ON_HIT)
    Fight.addFrenzy(opp, C.FRENZY_ON_HIT * (mv.isSuper and 0.2 or 1))
    if mv.poison then Fight.applyPoison(opp, mv.poison) end
    if opp.hp <= 0 then opp.hp = 0; Fight.ko(opp); return end
    opp.state = "knockdown"
    opp.onGround = false
    opp.vy = mv.launchVy or -9
    opp.vx = f.facing * (mv.kb or 6) * kbScale(opp)
    opp.getup = C.KNOCKDOWN_LIE
    opp.hitstun = 0
    opp.blockstun = 0
    Harness.count("knockdowns")
end

local function advanceMove(f, opp)
    f.moveFrame = f.moveFrame + 1
    local mv = f.move
    local kind = mv.kind
    local aLen = activeLen(f)

    -- projectile spawns on the first active frame
    if kind == "projectile" and f.moveFrame == mv.startup + 1
        and not f.projSpawned then
        Fight.spawnProjectile(f, mv)
        f.projSpawned = true
    end
    -- grab connects during active frames
    if kind == "grab" and not f.grabDone and f.moveFrame > mv.startup
        and f.moveFrame <= mv.startup + aLen then
        Fight.tryGrab(f, opp, mv)
    end
    -- lunge stops sliding after the active window
    if kind == "lunge" and f.moveFrame > mv.startup + aLen then
        f.vx = 0
    end

    if f.moveFrame >= mv.startup + aLen + mv.recovery then
        f.state = "idle"
        f.move = nil
        f.moveName = nil
        f.connected = false
        f.armorHits = 0
        f.flurryMash = 0
    end
end

-- world-space active hitbox rect, or nil
function Fight.hitbox(f)
    if not Fight.moveActive(f) then return nil end
    local b = f.move.hbox
    if not b then return nil end   -- projectiles / grabs / counters carry none
    local x = f.facing == 1 and (f.x + b.x) or (f.x - b.x - b.w)
    local top = f.y - b.y
    return x, top, b.w, b.h
end

-- world-space hurtbox (body) rect
function Fight.hurtbox(f)
    local bw = C.BODY_W
    local bh = (f.crouching and f.onGround) and C.CROUCH_H or C.BODY_H
    return f.x - bw / 2, f.y - bh, bw, bh
end

-- ---- specials dispatch -------------------------------------------------------

-- fire a special slot IF this fighter owns it; returns true if it fired
local function trySpecial(f, slot)
    if f.def.specials[slot] then Fight.startSpecial(f, slot); return true end
    return false
end

-- ---- per-fighter control (state changes from input) --------------------------

function Fight.control(f, opp, inp)
    Motion.feed(f, opp, inp)
    local crank = math.abs(inp.crank or 0)
    f.cranking = crank > 2 and f.state ~= "ko"
    if crank > 0 then Fight.addFrenzy(f, crank * C.FRENZY_PER_DEG) end
    -- crank-flick parry: a hard SNAP this frame arms a short parry window
    if crank >= C.PARRY_MAG then f.parryWin = C.PARRY_WINDOW end
    if (f.parryWin or 0) > 0 then f.parryWin = f.parryWin - 1 end

    -- teneral rage / molt-shed invuln countdowns (Phase 5)
    if (f.teneral or 0) > 0 then f.teneral = f.teneral - 1 end
    if (f.moltInvuln or 0) > 0 then f.moltInvuln = f.moltInvuln - 1 end

    -- double-tap DOWN detection (the Molt input; f.mframe from Motion.feed)
    local downNow = inp.down and true or false
    if downNow and not f.prevDown then
        if (f.mframe - (f.lastDownTap or -100)) <= C.DTAP_WIN then
            f.doubleDown = C.DTAP_HOLD
        end
        f.lastDownTap = f.mframe
    end
    f.prevDown = downNow
    if (f.doubleDown or 0) > 0 then f.doubleDown = f.doubleDown - 1 end

    if f.state == "ko" then return end

    if f.hitstun > 0 then f.hitstun = f.hitstun - 1 end
    if f.blockstun > 0 then f.blockstun = f.blockstun - 1 end
    if f.bufLight and f.bufLight > 0 then f.bufLight = f.bufLight - 1 end
    if f.bufHeavy and f.bufHeavy > 0 then f.bufHeavy = f.bufHeavy - 1 end
    if f.hitFlash > 0 then f.hitFlash = f.hitFlash - 1 end

    -- mid-attack: advance frames. Flurry can be extended by mashing an attack.
    if f.state == "attack" then
        if f.move and f.move.kind == "flurry"
            and (inp.lightPressed or inp.heavyPressed)
            and f.moveFrame > f.move.startup then
            f.flurryMash = math.min((f.flurryMash or 0) + 2, 14)
            Harness.count("mashes")
        end
        advanceMove(f, opp)
        return
    end

    if f.hitstun > 0 then f.state = "hitstun"; return end
    if f.blockstun > 0 then f.state = "blockstun"; return end

    if f.state == "knockdown" then
        if f.onGround then
            f.getup = f.getup - 1
            if f.getup <= 0 then f.state = "idle" end
        end
        return
    end

    -- airborne
    if not f.onGround then
        if f.canFly then
            -- POWERED FLIGHT: while stamina (airTime) remains she moves freely --
            -- Up climbs, Down descends, neutral drifts, left/right flies across --
            -- plus a burst air-dash and air-OK specials (Wing Buffet / Dogfight
            -- Dive). When stamina hits 0 she falls and must land to recharge.
            local d = opp.x - f.x
            if d ~= 0 then f.facing = d > 0 and 1 or -1 end
            -- air special takes over (clears flight; dive/buffet manage own vy)
            if inp.lightPressed or inp.heavyPressed then
                local heavy = inp.heavyPressed
                local m = Motion.scan(f)
                if m.dp and trySpecial(f, heavy and "dpH" or "dpL") then return
                elseif m.qcf and f.def.specials.qcfL and f.def.specials.qcfL.airOK then
                    trySpecial(f, heavy and "qcfH" or "qcfL"); return
                end
            end
            if (f.airTime or 0) > 0 then
                f.flying = true
                if inp.up then f.flyVy = -C.FLY_CLIMB
                elseif inp.down then f.flyVy = C.FLY_DESCEND
                else f.flyVy = C.FLY_DRIFT end
                if (inp.mvx or 0) ~= 0 then f.vx = inp.mvx * C.FLY_MOVE
                else f.vx = f.vx * 0.75 end
                local dd = inp.dash or 0
                if dd ~= 0 and not f.airDashed then
                    f.vx = dd * C.AIRDASH_VX
                    f.airDashed = true
                    f.airDashFr = C.AIRDASH_FRAMES
                    f.airTime = math.max(0, f.airTime - 6)
                    Harness.count("airdashes")
                end
            else
                f.flying = false          -- out of stamina: gravity reclaims her
            end
            f.state = "jump"
            return
        end
        f.state = "jump"
        return
    end

    -- grounded and free: auto-face the foe, then read input
    local d = opp.x - f.x
    if d ~= 0 then f.facing = d > 0 and 1 or -1 end
    -- teneral rage speeds movement up (Phase 5)
    local tmul = (f.teneral or 0) > 0 and C.TENERAL_SPD or 1

    if inp.lightPressed then f.bufLight = C.BUFFER end
    if inp.heavyPressed then f.bufHeavy = C.BUFFER end

    f.crouching = inp.down and true or false

    -- ---- MOLT (Phase 5): double-tap DOWN + Ⓐ+Ⓑ, at critical HP with a FULL
    -- Frenzy bar, once per match. Checked BEFORE throw/super so the shared A+B
    -- press can't be swallowed by the plain throw. Distinct from Super (QCF+A+B)
    -- and the command grab (360+A+B): the double-down is the discriminator.
    if inp.throw and not f.molted
        and (f.frenzy or 0) >= 1 and (f.doubleDown or 0) > 0
        and f.hp <= f.maxHp * C.MOLT_CRIT then
        Fight.startMolt(f)
        return
    end

    -- ---- specials & throws: motion + button, BEAT normals ---------------------
    if inp.throw then
        local m = Motion.scan(f)
        if (f.frenzy or 0) >= 1 and m.qcf and f.def.specials.super then
            f.frenzy = 0
            Fight.startSpecial(f, "super")
        elseif m.ring and f.def.specials.grab then
            Fight.startSpecial(f, "grab")
        elseif f.def.specials.throw then
            Fight.startSpecial(f, "throw")
        end
        return
    end
    if inp.lightPressed or inp.heavyPressed then
        local heavy = inp.heavyPressed
        local m = Motion.scan(f)
        if m.dp and trySpecial(f, heavy and "dpH" or "dpL") then return
        elseif m.charge and trySpecial(f, heavy and "chargeH" or "chargeL") then return
        elseif m.qcb and trySpecial(f, heavy and "qcbH" or "qcbL") then return
        elseif m.qcf and trySpecial(f, heavy and "qcfH" or "qcfL") then return
        end
        -- no matching motion/slot: fall through to a normal (buffered below)
    end

    -- attacks (buffered)
    if (f.bufLight or 0) > 0 then
        Fight.startMove(f, f.crouching and "crouchLight" or "light")
        f.bufLight = 0
        return
    end
    if (f.bufHeavy or 0) > 0 then
        Fight.startMove(f, f.crouching and "crouchHeavy" or "heavy")
        f.bufHeavy = 0
        return
    end

    -- jump
    if inp.up then
        f.onGround = false
        f.vy = f.jumpVy
        f.vx = (inp.mvx or 0) * C.JUMP_VX
        f.state = "jump"
        f.crouching = false
        if f.canFly then
            f.airTime = C.FLY_TIME
            f.airDashed = false
            f.flying = true
            f.flyVy = -C.FLY_CLIMB
        end
        return
    end

    -- double-tap dash / back-hop (blocked while cranking)
    local dd = f.cranking and 0 or (inp.dash or 0)
    if dd ~= 0 then
        if dd == f.facing then
            f.vx = f.dashSpd * tmul * f.facing
            f.dash = C.DASH_FRAMES
            f.state = "walk"
        else
            f.onGround = false
            f.vy = C.BACKHOP_VY
            f.vx = -f.facing * C.BACKHOP_VX
            f.state = "jump"
            if f.canFly then f.airTime = C.FLY_TIME; f.airDashed = false end
        end
        f.crouching = false
        return
    end

    -- walk / block stance
    local awayHeld = (inp.mvx or 0) == -f.facing
    if awayHeld then
        f.blocking = true
        f.lowBlock = f.crouching
        f.vx = -f.facing * C.BACK_SPD * tmul
        f.state = f.crouching and "crouch" or "block"
    elseif (inp.mvx or 0) == f.facing then
        f.blocking = false
        f.vx = f.facing * f.walkSpd * tmul
        f.state = f.crouching and "crouch" or "walk"
    else
        f.blocking = false
        f.vx = 0
        f.state = f.crouching and "crouch" or "idle"
    end

    if f.state == "walk" then
        f.walkPhase = f.walkPhase + 0.35
    end
end

-- ---- physics integration -----------------------------------------------------

function Fight.physics(f)
    if f.state == "ko" then
        f.vy = f.vy + C.GRAVITY
        f.x = f.x + f.vx
        f.y = f.y + f.vy
        if f.y >= C.GROUND_Y then f.y = C.GROUND_Y; f.vy = 0; f.vx = f.vx * 0.6 end
        f.x = Util.clamp(f.x, C.MARGIN, C.W - C.MARGIN)
        return
    end

    -- horizontal
    f.x = f.x + f.vx
    if f.dash > 0 then
        f.dash = f.dash - 1
        if f.dash == 0 then f.vx = 0 end
    end
    if f.airDashFr and f.airDashFr > 0 then
        f.airDashFr = f.airDashFr - 1
        if f.airDashFr == 0 and not f.onGround then f.vx = f.vx * 0.4 end
    end

    -- friction on knockback while grounded & not steering
    if f.onGround and (f.hitstun > 0 or f.blockstun > 0 or f.state == "knockdown") then
        f.vx = f.vx * 0.75
        if math.abs(f.vx) < 0.15 then f.vx = 0 end
    end

    -- gravity / airborne. Powered flight (canFly + flying + stamina) drives vy
    -- directly and drains stamina; otherwise normal gravity.
    if not f.onGround then
        if f.canFly and f.flying and (f.airTime or 0) > 0 then
            f.airTime = f.airTime - 1
            f.vy = f.flyVy or 0
            f.y = f.y + f.vy
            if f.y < C.FLY_CEIL then f.y = C.FLY_CEIL; f.vy = 0 end
        else
            f.vy = f.vy + C.GRAVITY
            f.y = f.y + f.vy
        end
        if f.y >= C.GROUND_Y then
            f.y = C.GROUND_Y
            f.vy = 0
            f.onGround = true
            f.flying = false
            f.airTime = 0
            f.airDashed = false
            f.airDashFr = 0
            if f.state == "knockdown" then
                f.getup = C.KNOCKDOWN_LIE
            elseif f.state == "jump" then
                f.state = "idle"
            end
            if f.state ~= "knockdown" then f.vx = 0 end
        end
    end

    f.x = Util.clamp(f.x, C.MARGIN, C.W - C.MARGIN)
end

-- keep bodies from overlapping; weight-proportional (heavier moves less)
function Fight.pushApart(a, b)
    local mind = C.BODY_W - 6
    local d = b.x - a.x
    local ad = math.abs(d)
    if ad >= mind then return end
    local s = d >= 0 and 1 or -1
    if s == 0 then s = 1 end
    local push = (mind - ad)
    local wa, wb = a.weight or 1, b.weight or 1
    local aShare = push * (wb / (wa + wb))
    local bShare = push * (wa / (wa + wb))
    a.x = a.x - s * aShare
    b.x = b.x + s * bShare
    a.x = Util.clamp(a.x, C.MARGIN, C.W - C.MARGIN)
    b.x = Util.clamp(b.x, C.MARGIN, C.W - C.MARGIN)
    -- second pass: corner transfer
    d = b.x - a.x
    ad = math.abs(d)
    if ad < mind then
        s = d >= 0 and 1 or -1
        if s == 0 then s = 1 end
        if a.x <= C.MARGIN or a.x >= C.W - C.MARGIN then
            b.x = Util.clamp(a.x + s * mind, C.MARGIN, C.W - C.MARGIN)
        else
            a.x = Util.clamp(b.x - s * mind, C.MARGIN, C.W - C.MARGIN)
        end
    end
end

-- ---- hit resolution ----------------------------------------------------------

function Fight.ko(f)
    f.state = "ko"
    f.onGround = false
    f.vy = -7
    f.vx = -f.facing * 3
    f.poison = nil
    Sfx.ko()
end

-- Phase 5: crank-flick parry. b snapped the crank in the last few frames
-- (b.parryWin > 0): NEGATE a's hit, reward b Frenzy, and dump a into recovery
-- (dropping its active window). Returns true if the hit was parried.
function Fight.tryParry(a, b, cx, cy, isProj)
    if (b.parryWin or 0) <= 0 or b.state == "ko" then return false end
    b.parryWin = 0
    Harness.count("parries")
    Fight.addFrenzy(b, C.FRENZY_ON_PARRY)
    Sfx.parry()
    Draw.spark(cx, cy, true)
    G.shake = math.max(G.shake or 0, 6)
    if not isProj and a and a.move then
        -- lose the active window: jump the attacker to its recovery phase
        a.moveFrame = a.move.startup + activeLen(a) + 1
        a.connected = true
    end
    return true
end

-- b's armed counter catches a's melee hit: negate it and punish a
local function counterFires(a, b, cx, cy)
    local mv = b.move
    b.state = "idle"; b.move = nil; b.moveName = nil
    Harness.count("counters")
    Sfx.hit()
    Draw.spark(cx, cy, true)
    G.shake = math.max(G.shake, 6)
    Fight.addFrenzy(b, C.FRENZY_ON_HIT)
    a.hp = a.hp - (mv.counterDmg or 12)
    a.hitFlash = 4
    if a.hp <= 0 then a.hp = 0; Fight.ko(a); return end
    if mv.knockdown then
        a.state = "knockdown"; a.onGround = false; a.vy = -8
        a.vx = b.facing * (mv.counterKb or 8) * kbScale(a)
        a.getup = C.KNOCKDOWN_LIE
        Harness.count("knockdowns")
    else
        a.state = "hitstun"; a.hitstun = 16
        a.vx = b.facing * (mv.counterKb or 8) * kbScale(a)
    end
end

-- a attacks b. Normals/reversals/lunges hit once (a.connected); super/flurry
-- re-hit every hitEvery frames.
function Fight.resolveHits(a, b)
    if not Fight.moveActive(a) then return end
    local mv = a.move
    local multi = (mv.kind == "super" or mv.kind == "flurry")
    if multi then
        if (a.superLastHit or -100) + (mv.hitEvery or 3) > a.moveFrame then return end
    elseif a.connected then
        return
    end

    local hx, hy, hw, hh = Fight.hitbox(a)
    if not hx then return end   -- projectiles/grabs/counters carry no body hitbox
    local bx, by, bw, bh = Fight.hurtbox(b)
    if not rectsOverlap(hx, hy, hw, hh, bx, by, bw, bh) then return end

    local cx = (hx + hw / 2)
    local cy = (hy + hh / 2)

    local function claim()
        if multi then a.superLastHit = a.moveFrame else a.connected = true end
    end

    if b.state == "ko" then claim(); return end
    if Fight.isInvuln(b) then claim(); return end

    -- crank-flick parry: a fast snap in the last few frames negates the hit
    if Fight.tryParry(a, b, cx, cy) then claim(); return end

    -- counter/reflect stance: negate a's hit, punish a
    if b.state == "attack" and b.move and b.move.kind == "counter"
        and b.moveFrame >= b.move.armStart and b.moveFrame <= b.move.armEnd then
        claim()
        counterFires(a, b, cx, cy)
        return
    end

    -- lunge armor: absorb a startup hit (still take chip), keep charging
    if b.state == "attack" and b.move
        and (b.armorHits or 0) > 0 and b.moveFrame <= b.move.startup then
        b.armorHits = b.armorHits - 1
        b.hp = math.max(0, b.hp - mv.damage * Fight.dmgMul(a, b))
        b.hitFlash = 3
        Sfx.hit()
        Draw.spark(cx, cy, false)
        G.shake = math.max(G.shake, 3)
        Fight.addFrenzy(a, C.FRENZY_ON_HIT)
        claim()
        if b.hp <= 0 then b.hp = 0; Fight.ko(b) end
        return
    end

    claim()

    -- block (holding away, grounded, not attacking) stops normals & specials
    local canBlock = b.blocking and b.onGround and b.state ~= "attack"
        and b.hitstun <= 0
    if canBlock then
        b.blockstun = mv.blockstun
        b.state = "blockstun"
        b.vx = a.facing * mv.kb * 0.45 * kbScale(b)
        local chip = 0
        if mv.heavy or mv.kind then chip = chip + 1 end
        if b.cranking then chip = chip + 1 end
        if chip > 0 then b.hp = math.max(0, b.hp - chip) end
        Sfx.block()
        Draw.spark(cx, cy, false)
        G.shake = math.max(G.shake, 2)
        Harness.count("blocks")
        if b.hp <= 0 then b.hp = 0; Fight.ko(b) end
        return
    end

    b.hp = b.hp - mv.damage * Fight.dmgMul(a, b)
    b.hitFlash = 4
    Sfx.hit()
    Draw.spark(cx, cy, mv.heavy or multi)
    G.shake = math.max(G.shake, multi and 9 or (mv.heavy and 6 or 3))
    Harness.count("hits")
    Fight.addFrenzy(a, C.FRENZY_ON_HIT)
    Fight.addFrenzy(b, C.FRENZY_ON_HIT * 0.5)
    if mv.poison then Fight.applyPoison(b, mv.poison) end

    if b.hp <= 0 then
        b.hp = 0
        Fight.ko(b)
        return
    end

    if mv.knockdown then
        b.state = "knockdown"
        b.onGround = false
        b.vy = -8
        b.vx = a.facing * mv.kb * kbScale(b)
        b.getup = C.KNOCKDOWN_LIE
        Harness.count("knockdowns")
    else
        b.state = "hitstun"
        b.hitstun = mv.hitstun
        b.vx = a.facing * mv.kb * kbScale(b)
    end
end

-- move & collide all projectiles (one full-fight step)
function Fight.updateProjectiles()
    local list = G.projectiles
    if not list then return end
    for i = #list, 1, -1 do
        local p = list[i]
        p.x = p.x + p.vx
        p.life = p.life - 1
        local target = (p.owner == G.p1) and G.p2 or G.p1
        local remove = p.life <= 0 or p.x < -20 or p.x > C.W + 20
        if not remove and target and target.state ~= "ko" then
            local bx, by, bw, bh = Fight.hurtbox(target)
            if rectsOverlap(p.x - 6, p.y - 6, 12, 12, bx, by, bw, bh) then
                Fight.applyProjectileHit(p, target)
                remove = true
            end
        end
        if remove then table.remove(list, i) end
    end
end

-- one full fight step: control both, integrate, separate, resolve, tick poison
function Fight.update(inp1, inp2)
    local p1, p2 = G.p1, G.p2
    Fight.control(p1, p2, inp1)
    Fight.control(p2, p1, inp2)
    Fight.physics(p1)
    Fight.physics(p2)
    Fight.pushApart(p1, p2)
    Fight.resolveHits(p1, p2)
    Fight.resolveHits(p2, p1)
    Fight.updateProjectiles()
    Fight.tickPoison(p1)
    Fight.tickPoison(p2)
end

-- physics-only step (used during the round-over freeze so KO'd bodies settle)
function Fight.settle()
    Fight.physics(G.p1)
    Fight.physics(G.p2)
    Fight.pushApart(G.p1, G.p2)
end
