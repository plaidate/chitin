-- Phase 4: the main menu (after the title). Five modes, navigable by d-pad + A.
-- In smoke the autopilot auto-advances, cycling a schedule so every mode is
-- exercised across a long run (Arcade first so an ending is reached quickly).
--
--   Menu.enter()    reset the cursor
--   Menu.update()   -> mode-id string when a mode is chosen, else nil
--   Menu.draw()

Menu = {}

local gfx <const> = playdate.graphics

Menu.MODES = {
    { id = "arcade",   label = "ARCADE",      blurb = "Climb the 5-bug ladder to your ending" },
    { id = "survival", label = "SURVIVAL",    blurb = "Endless gauntlet, HP carries over" },
    { id = "timeattack", label = "TIME ATTACK", blurb = "Clear the ladder against the clock" },
    { id = "training", label = "TRAINING",    blurb = "Free spar vs an adjustable dummy" },
    { id = "versus",   label = "VERSUS",      blurb = "Single match, pick both fighters" },
}

-- smoke schedule: Arcade first (reach an ending fast), then the rest in turn
local SMOKE_ORDER = { "arcade", "survival", "training", "timeattack", "versus" }

function Menu.enter()
    G.menuCursor = G.menuCursor or 1
    G.t = 0
end

function Menu.update()
    if Harness.enabled then
        -- auto-pick after a short beat; advance the schedule each visit
        if (G.t or 0) > 0.6 then
            G.menuVisits = (G.menuVisits or 0) + 1
            local id = SMOKE_ORDER[((G.menuVisits - 1) % #SMOKE_ORDER) + 1]
            return id
        end
        return nil
    end
    local n = #Menu.MODES
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        G.menuCursor = (G.menuCursor % n) + 1
    elseif playdate.buttonJustPressed(playdate.kButtonUp) then
        G.menuCursor = ((G.menuCursor - 2) % n) + 1
    end
    if playdate.buttonJustPressed(playdate.kButtonA) then
        return Menu.MODES[G.menuCursor].id
    end
    if playdate.buttonJustPressed(playdate.kButtonB) then
        G.state = "title"
    end
    return nil
end

function Menu.draw()
    gfx.clear(gfx.kColorWhite)
    Stage.draw()
    -- title strip
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 12, C.W, 30)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned("FIGHTIN' CHITIN", C.W / 2, 20, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    local cur = G.menuCursor or 1
    local x, y0, rowH, w = 96, 58, 26, 208
    for i, m in ipairs(Menu.MODES) do
        local y = y0 + (i - 1) * rowH
        local sel = (i == cur)
        if sel then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(x, y, w, rowH - 4)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(x, y, w, rowH - 4)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(x, y, w, rowH - 4)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        gfx.drawTextAligned(m.label, x + w / 2, y + 4, kTextAlignment.center)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end
    -- blurb for the highlighted mode
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, C.H - 20, C.W, 20)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(Menu.MODES[cur].blurb, C.W / 2, C.H - 17, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end
