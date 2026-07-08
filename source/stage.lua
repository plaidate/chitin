-- Phase 4: data-driven stage system (mirrors fighters.lua). Six habitat
-- backdrops, each a 1-bit parallax scene drawn from primitives with a slow
-- animated layer (drifting spores / skating striders / marching ants / swaying
-- blooms / a porch-light glow / moss grooves). Kept muted in the mid-band so the
-- two outline-forward fighters always read clearly on top.
--
--   Stage.LIST         ordered stage ids
--   Stage.def(id)      { name, music, draw }
--   Stage.set(id)      make a stage current (counts distinct stages for smoke)
--   Stage.current      active stage id (draw target)
--   Stage.draw()       render the current stage
--   Stage.forFighter(id)  the fighter's recommended home stage

Stage = {}

local gfx <const> = playdate.graphics
local DTH <const> = gfx.image.kDitherTypeBayer4x4

local function gray(d) gfx.setDitherPattern(1 - d, DTH) end
local function black() gfx.setColor(gfx.kColorBlack) end
local function white() gfx.setColor(gfx.kColorWhite) end

-- module frame clock: one tick per rendered frame (Stage.draw runs once/frame)
local T = 0

-- shared ground plate: a dithered earth band under the baseline + a bold line
local function groundPlate(dark, gy)
    gy = gy or C.GROUND_Y
    gray(dark or 0.42)
    gfx.fillRect(0, gy, C.W, C.H - gy)
    black(); gfx.setLineWidth(2)
    gfx.drawLine(0, gy, C.W, gy)
    gfx.setLineWidth(1)
end

-- ===========================================================================
-- 1. ROTTING LOG ARENA (rhino / beetles) -- bracket fungi, drifting spores
-- ===========================================================================
local function drawLog()
    local W, gy = C.W, C.GROUND_Y
    local logY = gy - 34
    gray(0.28); gfx.fillRect(0, logY, W, 30)
    black(); gfx.setLineWidth(2); gfx.drawLine(0, logY, W, logY)
    -- bark rings on the near end
    gray(0.5); gfx.fillEllipseInRect(W - 46, logY, 40, 30)
    black(); gfx.drawEllipseInRect(W - 46, logY, 40, 30)
    gfx.drawEllipseInRect(W - 38, logY + 8, 24, 14)
    -- bracket fungi
    local function bracket(x, y, r)
        black(); gfx.fillEllipseInRect(x - r, y - r * 0.5, r * 2, r)
        white(); gfx.setLineWidth(1); gfx.drawLine(x - r * 0.5, y - 1, x + r * 0.5, y - 1)
        black()
    end
    bracket(70, logY + 6, 14); bracket(150, logY + 10, 10); bracket(300, logY + 4, 12)
    -- drifting spores: tiny motes rising in the upper air
    black()
    for i = 1, 10 do
        local sx = (i * 41 + math.floor(T * 0.3)) % W
        local sy = 30 + ((i * 53 - math.floor(T * 0.8)) % 130)
        gfx.fillCircleAtPoint(sx, sy, (i % 3 == 0) and 2 or 1)
    end
    groundPlate(0.42, gy)
    gray(0.7)
    gfx.fillCircleAtPoint(40, gy + 22, 3); gfx.fillCircleAtPoint(360, gy + 30, 4)
    gfx.fillCircleAtPoint(210, gy + 34, 3)
    black(); gfx.setLineWidth(1)
end

-- ===========================================================================
-- 2. POND SURFACE (dragonfly) -- reflections, skating water-striders
-- ===========================================================================
local function drawPond()
    local W, gy = C.W, C.GROUND_Y
    -- distant reed silhouettes leaning at the horizon
    black()
    for _, rx in ipairs({ 30, 90, 340, 372 }) do
        gfx.setLineWidth(2)
        gfx.drawLine(rx, 96, rx + 6, 40 + (rx % 20))
    end
    -- water band behind the action with shimmering reflection stripes
    local wtop = gy - 44
    gray(0.16); gfx.fillRect(0, wtop, W, gy - wtop)
    for i = 0, 5 do
        gray(0.5)
        local ry = wtop + 6 + i * 7
        local off = math.floor(T * (0.6 + i * 0.15)) % 60
        for x = -off, W, 60 do gfx.fillRect(x, ry, 34, 2) end
    end
    -- skating water-striders: long-legged silhouettes gliding across the bg
    black(); gfx.setLineWidth(1)
    for i = 1, 3 do
        local sx = math.floor((T * (0.9 + i * 0.4) + i * 150) % (W + 60)) - 30
        local sy = wtop + 10 + i * 9
        gfx.fillCircleAtPoint(sx, sy, 2)
        for _, dx in ipairs({ -10, -4, 6, 12 }) do
            gfx.drawLine(sx, sy, sx + dx, sy + 5)
        end
    end
    -- near bank the fighters stand on
    black(); gfx.setLineWidth(2); gfx.drawLine(0, gy, W, gy)
    gray(0.34); gfx.fillRect(0, gy, W, C.H - gy)
    black(); gfx.setLineWidth(1)
end

-- ===========================================================================
-- 3. FLOWER MEADOW (leaf-footed) -- nodding blooms, drifting pollen
-- ===========================================================================
local function drawMeadow()
    local W, gy = C.W, C.GROUND_Y
    -- stalks with nodding bloom heads (sway with T), placed at the sides/back
    local function bloom(x, h, ph)
        local sway = math.sin(T * 0.04 + ph) * 6
        local topx, topy = x + sway, gy - h
        black(); gfx.setLineWidth(2); gfx.drawLine(x, gy, topx, topy)
        -- petals: a ring of small white-cored ellipses
        white(); gfx.fillCircleAtPoint(topx, topy, 9)
        black(); gfx.drawCircleAtPoint(topx, topy, 9)
        for a = 0, 5 do
            local an = a * (math.pi / 3)
            gfx.fillCircleAtPoint(topx + math.cos(an) * 9, topy + math.sin(an) * 9, 3)
        end
        gray(0.7); gfx.fillCircleAtPoint(topx, topy, 4); black()
    end
    bloom(38, 96, 0); bloom(84, 70, 1.4); bloom(320, 104, 2.1); bloom(366, 78, 3.3)
    -- drifting pollen motes floating across the air
    gray(0.85)
    for i = 1, 14 do
        local px = (i * 33 + math.floor(T * 0.5)) % W
        local py = 40 + ((i * 47 + math.floor(T * 0.25)) % 120)
        gfx.fillCircleAtPoint(px, py, 1)
    end
    black()
    groundPlate(0.4, gy)
    -- grass tufts along the baseline
    black(); gfx.setLineWidth(1)
    for x = 10, W, 26 do
        gfx.drawLine(x, gy, x - 3, gy - 8); gfx.drawLine(x, gy, x + 3, gy - 7)
    end
end

-- ===========================================================================
-- 4. KITCHEN COUNTER AT NIGHT (assassin) -- porch-light glow, human scale
-- ===========================================================================
local function drawKitchen()
    local W, H, gy = C.W, C.H, C.GROUND_Y
    -- night wall: dark dither over the whole back
    gray(0.2); gfx.fillRect(0, 0, W, gy)
    -- overhead porch-light glow: nested white rings fading out (radial-ish)
    local cx, cy = 300, 10
    for r = 96, 20, -14 do
        gray(0.85 - (r / 96) * 0.6)
        gfx.fillCircleAtPoint(cx, cy, r)
    end
    white(); gfx.fillCircleAtPoint(cx, cy, 14); black()
    -- a looming human-world object for scale: a giant mug silhouette at left
    black()
    gfx.fillRect(24, gy - 92, 70, 92)
    white(); gfx.fillRect(30, gy - 84, 58, 76); black()
    gfx.setLineWidth(3); gfx.drawArc(96, gy - 54, 22, 300, 60); gfx.setLineWidth(1)
    gfx.drawRect(24, gy - 92, 70, 92)
    -- counter surface: a lit band the fighters stand on (keeps them readable)
    gray(0.5); gfx.fillRect(0, gy - 8, W, 8)
    black(); gfx.setLineWidth(2); gfx.drawLine(0, gy, W, gy)
    -- tile grout receding on the counter top
    gray(0.34); gfx.fillRect(0, gy, W, H - gy)
    black(); gfx.setLineWidth(1)
    for x = 40, W, 80 do gfx.drawLine(x, gy, x + 26, H) end
    gfx.drawLine(0, gy + 18, W, gy + 18)
end

-- ===========================================================================
-- 5. ANT-HILL MOUND (boss turf) -- marching ant silhouettes
-- ===========================================================================
local function drawAnthill()
    local W, gy = C.W, C.GROUND_Y
    -- the mound: a big dithered dome behind, with a dark entrance hole
    gray(0.3)
    gfx.fillEllipseInRect(W / 2 - 150, gy - 96, 300, 150)
    black(); gfx.setLineWidth(2)
    gfx.drawEllipseInRect(W / 2 - 150, gy - 96, 300, 150)
    gfx.fillEllipseInRect(W / 2 - 16, gy - 40, 32, 26) -- entrance
    -- marching ant silhouettes crossing a bg trail
    local trailY = gy - 30
    gfx.setLineWidth(1)
    for i = 1, 9 do
        local ax = math.floor((T * 0.9 + i * 46) % (W + 40)) - 20
        black()
        -- three body segments + legs
        gfx.fillCircleAtPoint(ax, trailY, 3)
        gfx.fillCircleAtPoint(ax + 5, trailY, 2)
        gfx.fillCircleAtPoint(ax - 5, trailY, 2)
        for _, dx in ipairs({ -3, 0, 3 }) do gfx.drawLine(ax + dx, trailY, ax + dx, trailY + 4) end
    end
    groundPlate(0.44, gy)
    -- scattered soil pellets
    gray(0.7)
    gfx.fillCircleAtPoint(60, gy + 24, 3); gfx.fillCircleAtPoint(300, gy + 30, 4)
    gfx.fillCircleAtPoint(180, gy + 20, 2)
    black(); gfx.setLineWidth(1)
end

-- ===========================================================================
-- 6. BARK FACE (mantis / tiger beetle) -- vertical grooves, moss dither
-- ===========================================================================
local function drawBark()
    local W, H, gy = C.W, C.H, C.GROUND_Y
    -- pale bark field
    gray(0.12); gfx.fillRect(0, 0, W, gy)
    -- vertical grooves running the full height (slight wobble per column)
    black(); gfx.setLineWidth(2)
    for x = 14, W, 34 do
        local w = math.sin(x * 0.5) * 4
        gfx.drawLine(x + w, 0, x - w, gy)
    end
    gfx.setLineWidth(1)
    for x = 30, W, 34 do
        gray(0.3); gfx.drawLine(x, 0, x, gy)
    end
    -- moss dither patches clinging in the grooves
    for _, m in ipairs({ { 50, 60, 40, 30 }, { 210, 30, 60, 40 }, { 330, 90, 44, 34 } }) do
        gray(0.6); gfx.fillEllipseInRect(m[1], m[2], m[3], m[4])
    end
    -- a knot / eye in the bark
    black(); gfx.setLineWidth(2); gfx.drawEllipseInRect(150, 40, 40, 26)
    gray(0.45); gfx.fillEllipseInRect(158, 46, 24, 14)
    -- ledge the fighters stand on
    black(); gfx.setLineWidth(2); gfx.drawLine(0, gy, W, gy)
    gray(0.4); gfx.fillRect(0, gy, W, H - gy)
    black(); gfx.setLineWidth(1)
end

-- ---------------------------------------------------------------------------
local STAGES = {
    log     = { name = "ROTTING LOG",   music = "log",     draw = drawLog },
    pond    = { name = "POND SURFACE",  music = "pond",    draw = drawPond },
    meadow  = { name = "FLOWER MEADOW", music = "meadow",  draw = drawMeadow },
    kitchen = { name = "KITCHEN NIGHT", music = "kitchen", draw = drawKitchen },
    anthill = { name = "ANT-HILL MOUND",music = "anthill", draw = drawAnthill },
    bark    = { name = "BARK FACE",     music = "bark",    draw = drawBark },
}

-- Survival cycles this order (Arcade uses each opponent's home stage instead).
-- log + anthill lead so the endless run visits the two "home-less" stages first.
Stage.LIST = { "log", "anthill", "pond", "meadow", "kitchen", "bark" }
Stage.current = "log"

-- each fighter's recommended home turf (DESIGN section 5)
local HOME = {
    rhino = "log", leaf = "meadow", mantis = "bark", tiger = "bark",
    dragonfly = "pond", assassin = "kitchen",
}
function Stage.forFighter(id) return HOME[id] or "log" end

function Stage.def(id) return STAGES[id] or STAGES.log end

-- distinct-stage bookkeeping for the smoke autopilot (stagesSeen counter)
G.stageSeen = G.stageSeen or {}
function Stage.set(id)
    if not STAGES[id] then id = "log" end
    Stage.current = id
    if not G.stageSeen[id] then
        G.stageSeen[id] = true
        Harness.count("stagesSeen")
    end
end

function Stage.seenCount()
    local n = 0
    for _ in pairs(G.stageSeen) do n = n + 1 end
    return n
end

function Stage.draw()
    T = T + 1
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    Stage.def(Stage.current).draw()
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.setDitherPattern(0)   -- reset dither so callers draw solid
end
