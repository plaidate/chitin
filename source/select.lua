-- Character select (Phase 3, extended in Phase 4). A VS screen before the fight.
-- Modes that pit the player against a mode-driven opponent (arcade / survival /
-- timeattack, G.selSingle) ask for ONE pick; training / versus pick both. In
-- smoke/balance the autopilot auto-advances: balance/dual modes march the
-- matchup schedule; single modes rotate the player fighter so successive Arcade
-- runs reach different endings.
--
-- Result: G.selId1 / G.selId2 (fighter ids) handed to the mode dispatcher.

Select = {}

local gfx <const> = playdate.graphics

-- matchup schedule: all 15 unique pairs, first three cover all six fighters.
local ORDER = {
    { 1, 2 }, { 3, 4 }, { 5, 6 }, { 1, 4 }, { 2, 5 }, { 3, 6 }, { 1, 6 },
    { 2, 4 }, { 3, 5 }, { 1, 3 }, { 2, 6 }, { 4, 5 }, { 1, 5 }, { 2, 3 }, { 4, 6 },
}
Select.ORDER = ORDER
Select.PAIRS = #ORDER

function Select.matchup(idx)
    local p = ORDER[(idx % #ORDER) + 1]
    return p[1], p[2]
end

function Select.enter()
    G.selConfirmed = false
    G.t = 0
    if Harness.enabled then
        if G.balance then
            local a, b = Select.matchup(G.balPair - 1)
            G.selI1, G.selI2 = a, b
        elseif G.selSingle then
            -- rotate the player fighter each single-mode entry (varies endings;
            -- selCount grows to 7 once the Army Ant unlocks, so it gets a turn)
            G.pcPick = (G.pcPick or 0)
            G.selI1 = (G.pcPick % Fighters.selCount()) + 1
            G.pcPick = G.pcPick + 1
            G.selI2 = (G.selI1 % Fighters.selCount()) + 1
        else
            local a, b = Select.matchup(G.matchIdx or 0)
            G.selI1, G.selI2 = a, b
            G.matchIdx = (G.matchIdx or 0) + 1
        end
        G.selPhase = "p1"
        return
    end
    G.selI1 = G.selI1 or 1
    G.selI2 = G.selI2 or 2
    G.selPhase = "p1"
end

-- returns true when the matchup is locked in (start the fight)
function Select.update()
    if Harness.enabled then
        if (G.t or 0) > 0.7 then
            -- balance keeps the 6-fighter matchup indices; other smoke modes use
            -- the selectable roster (which may include the unlocked ant)
            local at = G.balance and Fighters.at or Fighters.selAt
            G.selId1 = at(G.selI1)
            G.selId2 = at(G.selI2)
            return true
        end
        return false
    end

    local n = Fighters.selCount()
    local move = 0
    if playdate.buttonJustPressed(playdate.kButtonRight) then move = 1 end
    if playdate.buttonJustPressed(playdate.kButtonLeft) then move = -1 end
    local ticks = playdate.getCrankTicks and playdate.getCrankTicks(12) or 0
    if ticks ~= 0 then move = ticks > 0 and 1 or -1 end

    if G.selPhase == "p1" then
        if move ~= 0 then G.selI1 = ((G.selI1 - 1 + move) % n) + 1 end
        if playdate.buttonJustPressed(playdate.kButtonA) then
            if G.selSingle then
                G.selId1 = Fighters.selAt(G.selI1)
                G.selId2 = Fighters.selAt((G.selI1 % n) + 1)
                return true
            end
            G.selPhase = "p2"
        end
        if playdate.buttonJustPressed(playdate.kButtonB) then G.state = "menu"; Menu.enter() end
    else -- p2 (dual-pick modes only)
        if move ~= 0 then G.selI2 = ((G.selI2 - 1 + move) % n) + 1 end
        if playdate.buttonJustPressed(playdate.kButtonA) then
            G.selId1 = Fighters.selAt(G.selI1)
            G.selId2 = Fighters.selAt(G.selI2)
            return true
        end
        if playdate.buttonJustPressed(playdate.kButtonB) then G.selPhase = "p1" end
    end
    return false
end

-- one fighter panel. Name sits on the top plate, archetype on a bottom strip,
-- the rig standing clear between them (the Phase-3 name/archetype overlap fix).
local function panel(x, id, active, label)
    local def = Fighters.def(id)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(active and 3 or 1)
    gfx.drawRect(x, 58, 150, 124)
    gfx.setLineWidth(1)
    -- top plate: P-label + fighter name
    gfx.fillRect(x, 58, 150, 30)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(label, x + 75, 60, kTextAlignment.center)
    gfx.drawTextAligned(def.name, x + 75, 73, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    -- rig preview, feet clear of the bottom strip
    local fake = {
        x = x + 75, y = 158, facing = 1, def = def, rig = def.rig,
        state = "idle", crouching = false, onGround = true, walkPhase = 0,
        move = nil, moveFrame = 0, hitFlash = 0, hp = def.hp, maxHp = def.hp,
    }
    Rig.draw(fake)
    -- bottom strip: archetype label
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x, 164, 150, 18)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(def.archetype, x + 75, 166, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function Select.draw()
    gfx.clear(gfx.kColorWhite)
    Stage.draw()
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 20, C.W, 26)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    local head = G.selSingle and ("CHOOSE YOUR BUG  -  " .. string.upper(G.mode or ""))
        or "CHOOSE YOUR BUGS"
    gfx.drawTextAligned(head, C.W / 2, 26, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    local a1 = (G.selPhase == "p1")
    panel(12, Fighters.selAt(G.selI1), a1, "P1")

    if G.selSingle then
        -- opponent side: driven by the mode (ladder / gauntlet), not picked here
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(C.W - 162, 58, 150, 124)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.drawTextAligned(G.mode == "survival" and "GAUNTLET" or "THE LADDER",
            C.W - 87, 110, kTextAlignment.center)
        gfx.drawTextAligned("awaits", C.W - 87, 128, kTextAlignment.center)
    else
        panel(C.W - 162, Fighters.selAt(G.selI2), not a1, "P2")
    end

    gfx.setColor(gfx.kColorBlack)
    gfx.drawTextAligned("VS", C.W / 2, 112, kTextAlignment.center)
    local hint
    if G.selSingle then hint = "Ⓐ START  -  ✛/crank cycle  -  Ⓑ back"
    elseif a1 then hint = "Ⓐ pick P1  -  ✛/crank cycle"
    else hint = "Ⓐ FIGHT  -  Ⓑ back" end
    gfx.drawTextAligned(hint, C.W / 2, 204, kTextAlignment.center)
end
