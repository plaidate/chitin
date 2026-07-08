-- Motion-input parser (Phase 2). Tracks a rolling, FACING-RELATIVE directional
-- history per fighter (forward = toward the opponent, derived from inp.mvx and
-- the fighter->foe direction, plus up/down), then detects fighting-game motions
-- ending on the frame an attack button is pressed. Windows are lenient for the
-- small d-pad. State lives on the fighter (f.dirHist / f.chargeBack / f.chargeWin
-- / f.ringSeen / f.mframe) so it resets cleanly each round with newFighter.
--
--   QCF    down, down-forward, forward   (quarter-circle forward)
--   DP     forward, down, down-forward   (dragon-punch Z-motion)
--   charge hold back >= CHARGE_MIN, then forward within CHARGE_WINDOW
--   ring   a full circle: forward + back + up + down all seen (360 command grab)
--
-- Motion.scan(f) returns { qcf, dp, charge, ring } booleans; fight.lua combines
-- them with the button(s) pressed this frame to pick a special (specials beat
-- normals). A history entry is { fwd = -1/0/1 (back/neutral/forward),
-- up = -1/0/1 (down/neutral/up) }.

Motion = {}

function Motion.reset(f)
    f.dirHist = {}
    f.chargeBack = 0
    f.chargeWin = 0
    f.ringSeen = { f = -999, b = -999, u = -999, d = -999 }
    f.mframe = 0
end

-- facing-relative (rx forward/back, ry up/down) for this frame's input
local function relDir(f, opp, inp)
    local fwd = (opp.x - f.x) >= 0 and 1 or -1
    local rx = 0
    if (inp.mvx or 0) ~= 0 then rx = (inp.mvx == fwd) and 1 or -1 end
    local ry = 0
    if inp.up then ry = 1 elseif inp.down then ry = -1 end
    return rx, ry
end

function Motion.feed(f, opp, inp)
    if not f.dirHist then Motion.reset(f) end
    f.mframe = f.mframe + 1
    local rx, ry = relDir(f, opp, inp)

    local h = f.dirHist
    h[#h + 1] = { fwd = rx, up = ry }
    while #h > C.HIST do table.remove(h, 1) end

    -- charge: count held-back frames; releasing forward arms a short window
    if rx == -1 then
        f.chargeBack = math.min((f.chargeBack or 0) + 1, 120)
    elseif rx == 1 then
        if (f.chargeBack or 0) >= C.CHARGE_MIN then f.chargeWin = C.CHARGE_WINDOW end
        f.chargeBack = 0
    else
        f.chargeBack = math.max(0, (f.chargeBack or 0) - 1)
    end
    if (f.chargeWin or 0) > 0 then f.chargeWin = f.chargeWin - 1 end

    -- ring: stamp the frame each extreme was last visited (survives a brief jump)
    local rs = f.ringSeen
    if rx == 1 then rs.f = f.mframe elseif rx == -1 then rs.b = f.mframe end
    if ry == 1 then rs.u = f.mframe elseif ry == -1 then rs.d = f.mframe end
end

local function isDown(h) return h.up == -1 end
local function isDownFwd(h) return h.up == -1 and h.fwd == 1 end
local function isFwd(h) return h.fwd == 1 end
local function isDownBack(h) return h.up == -1 and h.fwd == -1 end
local function isBack(h) return h.fwd == -1 end

-- ordered, lenient scan: find each step predicate in sequence; the final step is
-- allowed to absorb continued holds, and the completion must be recent.
local function seqMatch(hist, steps, endWithin)
    local n = #hist
    if n < #steps then return false end
    local si, lastIdx = 1, 0
    for i = 1, n do
        if si <= #steps and steps[si](hist[i]) then
            lastIdx = i
            si = si + 1
        end
    end
    if si <= #steps then return false end
    local fin = steps[#steps]
    for i = lastIdx + 1, n do
        if fin(hist[i]) then lastIdx = i else break end
    end
    return (n - lastIdx) <= endWithin
end

function Motion.scan(f)
    local out = { qcf = false, qcb = false, dp = false, charge = false, ring = false }
    local h = f.dirHist
    if not h or #h == 0 then return out end

    out.qcf = seqMatch(h, { isDown, isDownFwd, isFwd }, C.MOTION_END)
    out.qcb = seqMatch(h, { isDown, isDownBack, isBack }, C.MOTION_END)
    out.dp = seqMatch(h, { isFwd, isDown, isDownFwd }, C.MOTION_END)
    out.charge = (f.chargeWin or 0) > 0

    local rs, now = f.ringSeen, f.mframe
    out.ring = rs
        and (now - rs.f) <= C.RING_WINDOW and (now - rs.b) <= C.RING_WINDOW
        and (now - rs.u) <= C.RING_WINDOW and (now - rs.d) <= C.RING_WINDOW

    return out
end
