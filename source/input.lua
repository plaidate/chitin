-- Input: gather d-pad / A / B into a per-frame table for a fighter. Buffers the
-- attack buttons and detects left/right double-taps into a one-frame dash flag.
-- In smoke builds, EVERY fighter is driven by the AI (AI-vs-AI headless), so
-- matches run to KO with no human. For a human P1, Input.human reads buttons.
--
-- input table: { mvx (-1/0/1 screen dir), up, down, lightPressed, heavyPressed,
--                throw, dash (-1/0/1 screen dir, one frame on a double-tap) }

Input = {}

local pd <const> = playdate

local function blank()
    return { mvx = 0, up = false, down = false,
             lightPressed = false, heavyPressed = false,
             throw = false, dash = 0, crank = 0 }
end
Input.blank = blank

-- double-tap tracking (human)
local tapWindow <const> = 12
local lastTap = { [-1] = -100, [1] = -100 }
local hframe = 0

function Input.human()
    hframe = hframe + 1
    local inp = blank()
    local left = pd.buttonIsPressed(pd.kButtonLeft)
    local right = pd.buttonIsPressed(pd.kButtonRight)
    if left then inp.mvx = -1 elseif right then inp.mvx = 1 end
    inp.up = pd.buttonIsPressed(pd.kButtonUp)
    inp.down = pd.buttonIsPressed(pd.kButtonDown)

    local a = pd.buttonJustPressed(pd.kButtonA)
    local b = pd.buttonJustPressed(pd.kButtonB)
    inp.lightPressed = a
    inp.heavyPressed = b
    inp.throw = a and b

    -- crank drives the Frenzy meter (degrees moved this frame)
    inp.crank = pd.getCrankChange()

    -- dash on a fresh double-tap in the same direction
    for _, dir in ipairs({ -1, 1 }) do
        local key = dir == -1 and pd.kButtonLeft or pd.kButtonRight
        if pd.buttonJustPressed(key) then
            if hframe - lastTap[dir] <= tapWindow then
                inp.dash = dir
            end
            lastTap[dir] = hframe
        end
    end
    return inp
end

-- input for a specific fighter, given its opponent
function Input.forFighter(f, opp)
    if Harness.enabled then
        return AI.decide(f, opp)
    end
    if f.isP1 then
        return Input.human()
    end
    -- Training: the P2 dummy follows the system-menu behaviour (cpu/block/stand)
    if G.mode == "training" then
        local b = G.trainBehav or "cpu"
        if b == "stand" then return blank() end
        if b == "block" then
            local inp = blank()
            inp.mvx = -f.facing            -- hold away = block
            return inp
        end
    end
    return AI.decide(f, opp)
end

-- title / result screens: A confirms; in smoke, auto-advance after a beat so the
-- autopilot marches through the whole flow.
function Input.confirm()
    if Harness.enabled then return (G.t or 0) > 0.6 end
    return pd.buttonJustPressed(pd.kButtonA)
end
