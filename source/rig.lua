-- Parametric bug fighters (Phase 3): SIX distinct jointed silhouettes, drawn
-- from primitives (NOT sprite frames), facing right and mirrored by f.facing.
-- A pose is a table of scalar params interpolated from the fighter's state/move/
-- timer (shared across the roster); the BODY PLAN is chosen by f.rig, so each
-- insect reads as its own creature. The striking limb visibly EXTENDS during a
-- move's active frames and retracts on recovery. Rendered outline-forward: a
-- white halo pass then a black fill pass, so two overlapping bugs stay readable.
--
-- Body plans (f.rig):
--   rhino     bulky rounded body, big forward horn, stubby legs      -- heavy
--   leaf      narrow body, spiked leaf-shaped hind legs              -- tech
--   mantis    tall thin upright, big raptorial forelegs              -- fast
--   tiger     low sleek body, long legs, prominent mandibles         -- speed
--   dragonfly long thin abdomen + two pairs of wings (hovers airborne)
--   assassin  narrow body, long forward rostrum/beak                 -- reach

Rig = {}

local gfx <const> = playdate.graphics

-- Pose params (body space, facing right, feet at origin, +y = UP):
--   lean    forward body lean (adds forward x with height)
--   crouch  0..1 vertical compression
--   armExt  striking-limb reach, -0.3 (wound back) .. 1 (fully extended)
--   armAng  striking-limb elevation (+ up, - down/low)
--   bob     whole-body vertical bob offset (px, world)
--   ko      0..1 fallen-on-back blend
function Rig.pose(f)
    local p = { lean = 0, crouch = 0, armExt = 0, armAng = 0.05, bob = 0, ko = 0 }

    if f.state == "ko" then p.ko = 1; return p end
    if f.state == "knockdown" then
        p.ko = f.onGround and 1 or 0.6
        return p
    end

    if f.crouching and f.onGround
        and (f.state == "crouch" or f.state == "idle" or f.state == "blockstun") then
        p.crouch = 0.6
    end

    if f.state == "idle" then
        p.bob = math.sin((f.walkPhase or 0) * 0.6 + (f.x or 0) * 0.05) * 1.2
    elseif f.state == "walk" then
        p.lean = 0.10
        p.bob = math.abs(math.sin(f.walkPhase)) * -2
    elseif f.state == "block" or f.state == "blockstun" then
        p.lean = -0.12
        p.armAng = 0.25
    elseif f.state == "hitstun" then
        p.lean = -0.40
        p.armAng = -0.1
    elseif f.state == "jump" then
        p.bob = 0
        p.lean = 0.05
    elseif f.state == "attack" then
        local mv = f.move
        local fr = f.moveFrame
        local aLen = mv.active
        if mv.kind == "flurry" then aLen = mv.active + (f.flurryMash or 0) end
        if fr <= mv.startup then
            local w = mv.startup > 0 and (fr / mv.startup) or 1
            p.armExt = -0.30 * w
            p.lean = -0.10 * w
            if mv.kind == "counter" then p.armExt = 0.2; p.lean = -0.18 end
        elseif fr <= mv.startup + aLen then
            p.armExt = 1
            p.lean = 0.26
            if mv.kind == "counter" then p.armExt = 0.35; p.lean = -0.15 end
            if mv.kind == "flurry" then
                p.armExt = 0.7 + 0.3 * math.abs(math.sin(fr * 0.9))
            end
        else
            local rt = (fr - mv.startup - aLen) / mv.recovery
            p.armExt = 1 - rt
            p.lean = 0.26 * (1 - rt)
        end
        p.armAng = mv.armAng or 0.1
        if mv.low then p.crouch = 0.5 end
        if mv.isSuper or mv.kind == "super" then p.super = true; p.lean = 0.34 end
        if mv.kind == "reversal" then p.armExt = math.max(p.armExt, 0.6) end
        if mv.kind == "counter" then p.counter = true end
    end
    return p
end

-- One rig-drawing pass. inflate>0 draws the white halo (bigger); inflate==0 the
-- black fill. lw is the line width for that pass. Body plan chosen by f.rig.
local function drawPass(f, p, inflate, lw)
    local fac = f.facing
    local comp = 1 - 0.30 * p.crouch
    local baseY = f.y - p.bob
    local t = playdate.getCurrentTimeMilliseconds() / 1000

    local function P(dx, dy)
        local wx = f.x + (dx + p.lean * dy * 0.30) * fac
        local wy = baseY - dy * comp
        return wx, wy
    end
    local function seg(x1, y1, x2, y2)
        local ax, ay = P(x1, y1); local bx, by = P(x2, y2)
        gfx.drawLine(ax, ay, bx, by)
    end
    local function ellipse(dx, dy, w, h)
        local cx, cy = P(dx, dy)
        w = w + inflate; h = h + inflate
        gfx.fillEllipseInRect(cx - w / 2, cy - h / 2, w, h)
    end
    local function circle(dx, dy, r)
        local cx, cy = P(dx, dy)
        gfx.fillCircleAtPoint(cx, cy, r + inflate / 2)
    end
    -- a two-segment striking limb, extending with p.armExt; returns the tip
    local function striker(bx, by, base, span, tipR)
        local ext = p.armExt
        local reach = base + span * ext
        local ex = bx + reach * 0.45
        local ey = by + p.armAng * 8
        local tx = bx + reach
        local ty = by + p.armAng * 22
        seg(bx, by, ex, ey)
        seg(ex, ey, tx, ty)
        local cx, cy = P(tx, ty)
        gfx.fillCircleAtPoint(cx, cy, (tipR or 3) + inflate / 2)
        return tx, ty
    end

    gfx.setLineWidth(lw)
    gfx.setLineCapStyle(gfx.kLineCapStyleRound)

    -- shared KO pose (all bugs flop on their backs, legs waving)
    if p.ko > 0 then
        local lift = (1 - p.ko) * 20
        local gy = baseY - lift
        gfx.fillEllipseInRect(f.x - 30 - inflate / 2, gy - 16 - inflate / 2,
            60 + inflate, 22 + inflate)
        gfx.fillCircleAtPoint(f.x - fac * 30, gy - 8, 9 + inflate / 2)
        for i = -1, 1 do
            gfx.drawLine(f.x + i * 12, gy - 12, f.x + i * 14, gy - 30)
        end
        return
    end

    local variant = f.rig or (f.def and f.def.rig) or "rhino"
    local wob = (f.state == "walk") and f.walkPhase or 0

    local function legs(xs, top, len)
        for i, lx in ipairs(xs) do
            local swing = math.sin(wob + i) * (f.state == "walk" and 6 or 0)
            seg(lx, top, lx + swing, len)
        end
    end

    -- ---------------------------------------------------------------------
    if variant == "rhino" then
        legs({ -14, -2, 12 }, 22, 1)                      -- stubby legs
        ellipse(-18, 28, 40, 32)                          -- broad abdomen
        ellipse(6, 30, 30, 30)                            -- bulky thorax
        circle(22, 32, 11)                                -- big head
        seg(28, 40, 40, 56); seg(40, 56, 34, 48)          -- forward horn
        seg(26, 22, 34, 12)                               -- lower horn prong
        striker(12, 30, 10, 30, 4)                        -- foreleg thrust

    elseif variant == "leaf" then
        -- narrow body, spiked leaf-shaped hind legs
        for i = 0, 1 do
            local hx = -20 - i * 2
            seg(hx, 22, hx - 12, 12)
            ellipse(hx - 16, 8, 16, 10)                   -- leaf-shaped tibia flag
        end
        legs({ -6, 6 }, 20, 1)
        ellipse(-16, 30, 26, 22)                          -- slim abdomen
        ellipse(4, 30, 22, 24)                            -- thorax
        circle(18, 33, 8)                                 -- head
        seg(20, 40, 27, 50)                               -- antenna
        striker(10, 30, 12, 32, 3)

    elseif variant == "mantis" then
        -- tall, thin, upright; big raptorial foreleg is the read. The narrow
        -- upright body sits back at x~=-14, so legs ANCHOR to the lower-thorax
        -- hip (not the wide-base default) and stay attached in every pose.
        local hipX, hipY = -12, 16
        local sw = (f.state == "walk") and 5 or 0
        for i, footX in ipairs({ -22, -12, -3 }) do
            local swing = math.sin(wob + i) * sw
            seg(hipX, hipY, footX + swing, 1)             -- legs fan from the hip
        end
        seg(hipX, hipY + 8, -26, 28)                      -- raised back leg
        ellipse(-14, 30, 16, 40)                          -- upright slender thorax
        ellipse(-20, 12, 14, 18)                          -- abdomen curled low/back
        circle(-8, 52, 8)                                 -- head held high
        seg(-6, 58, 0, 68); seg(-10, 58, -16, 68)         -- antennae
        -- RAPTORIAL FORELEGS: the signature read. At rest they fold up into the
        -- classic "praying" pose (bent, held in front of the head); on active
        -- attack frames they SHOOT FORWARD to reach, retracting on recovery.
        local t = math.max(0, math.min(1, p.armExt))      -- 0 folded .. 1 extended
        local sx, sy = -2, 46                             -- shoulder (upper thorax)
        local ex = 6 + 10 * t                             -- elbow: by head -> forward
        local ey = 56 - 6 * t + p.armAng * 4
        local tx = 3 + 37 * t                             -- claw: folded up -> reaching
        local ty = 63 - 15 * t + p.armAng * 18 * t
        for k = 0, 1 do                                   -- two folded forelegs
            local o = k * 3
            seg(sx, sy - o, ex, ey - o)
            seg(ex, ey - o, tx, ty - o)
        end
        local mcx, mcy = P(tx, ty)
        gfx.fillCircleAtPoint(mcx, mcy, 3 + inflate / 2)

    elseif variant == "tiger" then
        -- low sleek body, long legs, prominent forward mandibles
        legs({ -16, -4, 10, 16 }, 18, 1)                  -- four long legs
        ellipse(-14, 22, 30, 18)                          -- low flat abdomen
        ellipse(8, 22, 24, 18)                            -- low thorax
        circle(22, 24, 8)                                 -- head
        -- mandibles: two forward-splayed prongs, opening with the strike
        local open = 4 + p.armExt * 6
        seg(28, 26, 40 + p.armExt * 12, 26 + open)
        seg(28, 22, 40 + p.armExt * 12, 22 - open)
        striker(14, 22, 8, 24, 2)

    elseif variant == "dragonfly" then
        -- long thin abdomen trailing back + two pairs of wings; hovers airborne
        local flying = (not f.onGround)
        seg(-6, 30, -46, 34)                              -- long thin abdomen
        circle(-46, 34, 4)                                -- abdomen tip
        ellipse(2, 32, 20, 20)                            -- compact thorax
        circle(16, 36, 8)                                 -- head, big eyes
        circle(20, 40, 3)
        -- two pairs of wings, flapping when airborne
        local flap = flying and math.sin(t * 22) * 0.5 or 0.15
        for _, wy in ipairs({ 44, 40 }) do
            for s = -1, 1, 2 do
                local wx = 2 + s * 4
                seg(wx, wy, wx + s * 26, wy + 10 + flap * 16 * s)
            end
        end
        legs({ 0, 8 }, 22, 12)                            -- short tucked legs
        striker(10, 30, 10, 26, 3)                        -- dive foreleg

    elseif variant == "ant" then
        -- ARMY ANT MAJOR (boss): big segmented body -- gaster + waist + thorax +
        -- an oversized head with a pair of forward mandibles that open on the
        -- strike. Reads bigger and heavier than the six normal bugs.
        legs({ -18, -6, 8, 20 }, 20, 1)                   -- six long legs
        ellipse(-26, 30, 46, 36)                          -- big gaster (abdomen)
        seg(-6, 30, -2, 30)                               -- petiole (waist)
        ellipse(4, 32, 28, 28)                            -- thorax
        circle(28, 38, 15)                                -- BIG head
        seg(32, 48, 42, 62); seg(36, 48, 48, 58)          -- antennae
        -- mandibles: two big forward pincers, opening as the strike extends
        local open = 5 + p.armExt * 9
        seg(40, 38, 56 + p.armExt * 12, 38 + open)
        seg(40, 38, 56 + p.armExt * 12, 38 - open)
        local mx, my = P(40, 38); gfx.fillCircleAtPoint(mx, my, 3 + inflate / 2)
        striker(16, 30, 12, 30, 4)                        -- foreleg thrust

    else -- assassin
        -- narrow body, very long forward rostrum/beak (the reach read)
        legs({ -10, 0, 10 }, 20, 1)
        ellipse(-14, 30, 24, 20)                          -- narrow abdomen
        ellipse(4, 30, 20, 22)                            -- narrow thorax
        circle(16, 32, 7)                                 -- small head
        -- long rostrum extends further on the strike
        local rlen = 22 + p.armExt * 26
        seg(20, 30, 20 + rlen, 26)
        local tx, ty = P(20 + rlen, 26)
        gfx.fillCircleAtPoint(tx, ty, 2 + inflate / 2)
        seg(18, 38, 24, 48)                               -- antenna
    end
end

function Rig.draw(f)
    local p = Rig.pose(f)

    -- Frenzy-super aura: radiating spokes behind the body
    if p.super then
        local t = playdate.getCurrentTimeMilliseconds() / 60
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        for a = 0, 7 do
            local ang = a * (math.pi / 4) + t
            local r0, r1 = 30, 30 + (a % 2 == 0 and 26 or 16)
            gfx.drawLine(f.x + math.cos(ang) * r0, (f.y - 34) + math.sin(ang) * r0,
                f.x + math.cos(ang) * r1, (f.y - 34) + math.sin(ang) * r1)
        end
        gfx.setLineWidth(1)
    end

    -- teneral rage (Phase 5): a freshly-molted fighter shimmers -- a bold ring of
    -- glistening specks orbiting the body that reads as its soft new shell.
    if (f.teneral or 0) > 0 then
        local tt = playdate.getCurrentTimeMilliseconds() / 130
        local cy = f.y - 32
        for a = 0, 9 do
            local ang = a * (math.pi / 5) + tt
            local r = 36 + math.sin(tt * 3 + a) * 4
            local dx = f.x + math.cos(ang) * r
            local dy = cy + math.sin(ang) * r * 0.72
            gfx.setColor(gfx.kColorWhite)
            gfx.fillCircleAtPoint(dx, dy, 3)     -- bright halo
            gfx.setColor(gfx.kColorBlack)
            gfx.fillCircleAtPoint(dx, dy, 2)     -- speck core (reads on any bg)
        end
    end

    -- counter stance: a defensive brace ring
    if p.counter then
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(1)
        gfx.drawCircleAtPoint(f.x + f.facing * 14, f.y - 36, 22)
    end

    -- HIT FLASH: for the few frames after being struck, draw the whole rig as an
    -- INVERTED silhouette -- black halo + WHITE fill (the fighter flashes
    -- negative) instead of the normal white halo + black fill. No white box.
    -- Scoped tightly: only setColor is touched (never draw mode), and the frame
    -- always cleared to WHITE up-front, so nothing leaks to the rest of the scene.
    if f.hitFlash and f.hitFlash > 0 then
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setColor(gfx.kColorBlack)
        drawPass(f, p, 4, 8)          -- black outline halo
        gfx.setColor(gfx.kColorWhite)
        drawPass(f, p, 0, 3)          -- white body fill (negative)
        gfx.setColor(gfx.kColorBlack)
    else
        -- pass 1: white halo (outline-forward readability)
        gfx.setColor(gfx.kColorWhite)
        drawPass(f, p, 4, 8)
        -- pass 2: black body
        gfx.setColor(gfx.kColorBlack)
        drawPass(f, p, 0, 3)
    end

    -- poison indicator: rising specks over a poisoned fighter
    if f.poison and f.poison.ticks and f.poison.ticks > 0 then
        local tt = playdate.getCurrentTimeMilliseconds() / 200
        gfx.setColor(gfx.kColorBlack)
        for i = 0, 2 do
            local px = f.x - 10 + i * 10
            local py = f.y - 58 - ((tt + i) % 2) * 14
            gfx.fillCircleAtPoint(px, py, 2)
        end
    end
    gfx.setColor(gfx.kColorBlack)
end
