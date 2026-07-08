-- Frame compositor: clear, stage, both fighters (via Rig), HUD, plus hit-spark
-- flashes and a short screen-shake on heavy hits. Also draws the title and the
-- round/match banners.

Draw = {}

local gfx <const> = playdate.graphics

local sparks = {}   -- { x, y, life, max, big }

function Draw.spark(x, y, big)
    sparks[#sparks + 1] = { x = x, y = y, life = big and 8 or 5,
                            max = big and 8 or 5, big = big }
end

function Draw.resetFx()
    sparks = {}
    G.shake = 0
    G.swarmFx = nil
end

-- Phase 5: the discarded shell husks left behind when a fighter Molts. Drawn
-- behind the fighters (a cracked-open empty carapace on the ground).
function Draw.moltHusks()
    for _, f in ipairs({ G.p1, G.p2 }) do
        local s = f and f.moltShell
        if s then
            -- a cracked-open empty carapace: white fill so the split seam + curled
            -- legs read clearly as a discarded shell on any backdrop
            gfx.setColor(gfx.kColorWhite)
            gfx.fillEllipseInRect(s.x - 24, s.y - 22, 48, 24)
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(3)
            gfx.drawEllipseInRect(s.x - 24, s.y - 22, 48, 24)
            -- jagged split seam down the shed shell
            gfx.setLineWidth(2)
            gfx.drawLine(s.x - 3, s.y - 22, s.x + 2, s.y - 14)
            gfx.drawLine(s.x + 2, s.y - 14, s.x - 2, s.y - 6)
            gfx.drawLine(s.x - 2, s.y - 6, s.x + 3, s.y - 1)
            -- a couple of curled empty legs
            gfx.setLineWidth(1)
            gfx.drawLine(s.x - 16, s.y - 8, s.x - 24, s.y - 13)
            gfx.drawLine(s.x + 16, s.y - 8, s.x + 24, s.y - 13)
        end
    end
    gfx.setLineWidth(1)
end

-- Phase 5: the Army Ant SWARM super -- a wall of little marching ant
-- silhouettes sweeping across the arena while the super is active.
function Draw.swarm()
    local sw = G.swarmFx
    if not sw then return end
    sw.life = sw.life - 1
    if sw.life <= 0 then G.swarmFx = nil; return end
    local dir = sw.dir or 1
    local t = playdate.getCurrentTimeMilliseconds() / 1000
    local bandY = C.GROUND_Y - 40
    gfx.setColor(gfx.kColorBlack)
    for i = 1, 18 do
        local ax = ((t * 300 * dir + i * 33) % (C.W + 40)) - 20
        local ay = bandY + (i % 4) * 12 + math.sin(t * 6 + i) * 2
        gfx.fillCircleAtPoint(ax, ay, 3)
        gfx.fillCircleAtPoint(ax - dir * 5, ay, 2)
        gfx.fillCircleAtPoint(ax + dir * 4, ay, 2)
        for _, dx in ipairs({ -2, 0, 2 }) do gfx.drawLine(ax + dx, ay, ax + dx, ay + 4) end
    end
end

local function drawSparks()
    for i = #sparks, 1, -1 do
        local s = sparks[i]
        local f = s.life / s.max
        local r = (s.big and 16 or 9) * f
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(s.x, s.y, r + 2)
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(s.big and 3 or 2)
        -- a 4-point star burst
        for a = 0, 3 do
            local ang = a * (math.pi / 2) + (s.big and 0.4 or 0)
            gfx.drawLine(s.x, s.y,
                s.x + math.cos(ang) * r * 1.4,
                s.y + math.sin(ang) * r * 1.4)
        end
        s.life = s.life - 1
        if s.life <= 0 then table.remove(sparks, i) end
    end
    gfx.setLineWidth(1)
end

-- spit projectiles: a spiked venom blob
function Draw.projectiles()
    local list = G.projectiles
    if not list then return end
    for _, p in ipairs(list) do
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(p.x, p.y, 8)
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        for a = 0, 5 do
            local ang = a * (math.pi / 3) + p.x * 0.08
            gfx.drawLine(p.x, p.y, p.x + math.cos(ang) * 10, p.y + math.sin(ang) * 10)
        end
        gfx.drawCircleAtPoint(p.x, p.y, 6)
        gfx.fillCircleAtPoint(p.x, p.y, 3)
    end
    gfx.setLineWidth(1)
end

local function banner(text, sub)
    local W = C.W
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 96, W, sub and 52 or 34)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(text, W / 2, 104, kTextAlignment.center)
    if sub then gfx.drawTextAligned(sub, W / 2, 126, kTextAlignment.center) end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- title: bold logo over the drifting stage, clean framing
local function titleScreen()
    Stage.draw()
    local W = C.W
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(30, 66, W - 60, 68)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(2); gfx.drawRect(34, 70, W - 68, 60); gfx.setLineWidth(1)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned("FIGHTIN'  CHITIN", W / 2, 84, kTextAlignment.center)
    gfx.drawTextAligned("six bugs enter", W / 2, 108, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.drawTextAligned("- press Ⓐ -", W / 2, 156, kTextAlignment.center)
end

-- interstitial: ladder / continue banner over the (dimmed) stage
local function interstitialScreen()
    Stage.draw()
    local W = C.W
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 96, W, 44)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(G.interText or "NEXT", W / 2, 104, kTextAlignment.center)
    local opp = G.selId2 and Fighters.def(G.selId2).name or ""
    gfx.drawTextAligned("vs  " .. opp, W / 2, 122, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- a generic result / game-over card
local function resultScreen()
    Stage.draw()
    local W = C.W
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(40, 74, W - 80, 92)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(2); gfx.drawRect(44, 78, W - 88, 84); gfx.setLineWidth(1)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(G.resultTitle or "RESULT", W / 2, 92, kTextAlignment.center)
    local lines = G.resultLines or {}
    for i, ln in ipairs(lines) do
        gfx.drawTextAligned(ln, W / 2, 118 + (i - 1) * 18, kTextAlignment.center)
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- Arcade ending: the winning fighter's rig + its two-line ending
local function endingScreen()
    Stage.set(Stage.forFighter(G.endingId))
    Stage.draw()
    local W = C.W
    local def = Fighters.def(G.endingId)
    -- the victor standing centre-stage
    local fake = {
        x = W / 2, y = C.GROUND_Y - 6, facing = 1, def = def, rig = def.rig,
        state = "idle", crouching = false, onGround = true, walkPhase = 0,
        move = nil, moveFrame = 0, hitFlash = 0, hp = def.hp, maxHp = def.hp,
    }
    Rig.draw(fake)
    -- title plate + the ending couplet on a bottom card
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 8, W, 22)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(def.name .. "  -  THE END", W / 2, 12, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    local e = def.ending or { "", "" }
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, C.H - 44, W, 44)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(e[1] or "", W / 2, C.H - 40, kTextAlignment.center)
    gfx.drawTextAligned(e[2] or "", W / 2, C.H - 22, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function Draw.frame()
    -- Balance mode: skip the expensive two-pass rig/stage render (it caps the
    -- headless run at ~45fps). Clear to WHITE (never a black frame) and draw a
    -- tiny moving marker so the simulator keeps refreshing the display and macOS
    -- App Nap doesn't suspend the process.
    if G.balance then
        gfx.clear(gfx.kColorWhite)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(((G.rounds or 0) * 7) % (C.W - 6), 2, 5, 5)
        return
    end

    gfx.clear(gfx.kColorWhite)

    if G.state == "title" then titleScreen(); return end
    if G.state == "menu" then Menu.draw(); return end
    if G.state == "select" then Select.draw(); return end
    if G.state == "interstitial" then interstitialScreen(); return end
    if G.state == "ending" then endingScreen(); return end
    if G.state == "result" then resultScreen(); return end

    if G.state == "done" then
        Stage.draw()
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(0, 80, C.W, 44)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawTextAligned("BALANCE RUN COMPLETE", C.W / 2, 92, kTextAlignment.center)
        gfx.drawTextAligned(tostring(G.matches or 0) .. " matches logged",
            C.W / 2, 108, kTextAlignment.center)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        return
    end

    -- screen shake
    local sh = G.shake or 0
    local ox, oy = 0, 0
    if sh > 0 then
        ox = math.random(-sh, sh)
        oy = math.random(-sh, sh)
        gfx.setDrawOffset(ox, oy)
        G.shake = sh - 1
    end

    Stage.draw()
    Draw.moltHusks()
    if G.p1 then
        -- draw the rear fighter first for a touch of depth
        if G.p1.x <= G.p2.x then
            Rig.draw(G.p2); Rig.draw(G.p1)
        else
            Rig.draw(G.p1); Rig.draw(G.p2)
        end
    end
    Draw.projectiles()
    Draw.swarm()
    drawSparks()

    gfx.setDrawOffset(0, 0)

    Hud.draw()

    if G.state == "roundover" then
        local msg = G.roundResult or "K.O."
        local sub
        if G.roundWinner == 0 then sub = "DRAW"
        elseif G.roundWinner == 1 then sub = "P1 WINS THE ROUND"
        else sub = "P2 WINS THE ROUND" end
        banner(msg, sub)
    elseif G.state == "matchover" then
        local who = G.matchWinner == 1 and "PLAYER 1 WINS" or "PLAYER 2 WINS"
        banner(who, "- new match -")
    end
end
