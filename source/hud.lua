-- HUD: two health bars, the round timer, and round-win pips. Drawn on top of the
-- fight, unaffected by screen shake.

Hud = {}

local gfx <const> = playdate.graphics

local BAR_W = 150
local BAR_H = 12
local BAR_Y = 10

local function healthBar(x, frac, rightAlign)
    frac = Util.clamp(frac, 0, 1)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, BAR_Y, BAR_W, BAR_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRect(x, BAR_Y, BAR_W, BAR_H)
    local fw = math.floor((BAR_W - 4) * frac)
    if fw > 0 then
        if rightAlign then
            gfx.fillRect(x + 2 + (BAR_W - 4 - fw), BAR_Y + 2, fw, BAR_H - 4)
        else
            gfx.fillRect(x + 2, BAR_Y + 2, fw, BAR_H - 4)
        end
    end
end

-- Frenzy gauge (crank super meter), drawn under each health bar. Flashes full.
local FR_W = 132
local FR_H = 6
local FR_Y = BAR_Y + BAR_H + 14

local function frenzyBar(x, frac, rightAlign)
    frac = Util.clamp(frac, 0, 1)
    local full = frac >= 1
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, FR_Y, FR_W, FR_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawRect(x, FR_Y, FR_W, FR_H)
    local fw = math.floor((FR_W - 2) * frac)
    if full and math.floor(playdate.getCurrentTimeMilliseconds() / 110) % 2 == 0 then
        fw = FR_W - 2   -- flash the full bar
    end
    if fw > 0 then
        if rightAlign then
            gfx.fillRect(x + 1 + (FR_W - 2 - fw), FR_Y + 1, fw, FR_H - 2)
        else
            gfx.fillRect(x + 1, FR_Y + 1, fw, FR_H - 2)
        end
    end
    if full then
        gfx.drawTextAligned("FRENZY!", rightAlign and (x + FR_W) or x, FR_Y + FR_H + 1,
            rightAlign and kTextAlignment.right or kTextAlignment.left)
    end
end

local function pips(x, wins, rightAlign)
    for i = 1, C.ROUNDS_TO_WIN do
        local px = rightAlign and (x - (i - 1) * 12) or (x + (i - 1) * 12)
        gfx.setColor(gfx.kColorBlack)
        if i <= wins then
            gfx.fillCircleAtPoint(px, BAR_Y + BAR_H + 8, 4)
        else
            gfx.drawCircleAtPoint(px, BAR_Y + BAR_H + 8, 4)
        end
    end
end

function Hud.draw()
    local p1, p2 = G.p1, G.p2
    if not p1 then return end

    healthBar(6, p1.hp / (p1.maxHp or C.MAX_HP), false)
    healthBar(C.W - 6 - BAR_W, p2.hp / (p2.maxHp or C.MAX_HP), true)

    -- fighter names in the bottom corners
    local n1 = (p1.def and p1.def.name) or "P1"
    local n2 = (p2.def and p2.def.name) or "P2"
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.drawTextAligned(n1, 6, C.H - 16, kTextAlignment.left)
    gfx.drawTextAligned(n2, C.W - 6, C.H - 16, kTextAlignment.right)

    frenzyBar(6, p1.frenzy or 0, false)
    frenzyBar(C.W - 6 - FR_W, p2.frenzy or 0, true)

    pips(10, G.wins1 or 0, false)
    pips(C.W - 10, G.wins2 or 0, true)

    -- timer box
    local secs = math.max(0, math.ceil((G.roundTimer or 0) / 30))
    local s = string.format("%02d", secs)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(C.W / 2 - 18, BAR_Y - 2, 36, BAR_H + 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(C.W / 2 - 18, BAR_Y - 2, 36, BAR_H + 8)
    gfx.drawTextAligned(s, C.W / 2, BAR_Y, kTextAlignment.center)

    -- mode / ladder progress under the timer
    local tag
    if G.mode == "arcade" and G.arcOrder then
        tag = G.inBoss and "ARCADE  -  BOSS" or ("ARCADE  " .. G.arcIdx .. "/" .. #G.arcOrder)
    elseif G.mode == "timeattack" and G.taOrder then
        local secs = math.floor((G.taClock or 0) / 30)
        tag = string.format("T.A.  %d/%d  %d:%02d", G.taIdx, #G.taOrder,
            math.floor(secs / 60), secs % 60)
    elseif G.mode == "survival" then
        tag = "SURVIVAL  x" .. (G.survScore or 0)
    elseif G.mode == "training" then
        tag = "TRAINING  [" .. (G.trainBehav or "cpu") .. "]"
    end
    if tag then
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.drawTextAligned(tag, C.W / 2, BAR_Y + BAR_H + 10, kTextAlignment.center)
    end
end
