-- Combat SFX kit (Phase 1): hit thud, whiff, block tick, KO. Pure synth, no
-- music sequencer yet. All entry points are no-op-safe if the sound system is
-- unavailable so nothing crashes headless.

Sfx = {}

local ok, snd = pcall(function() return playdate.sound end)
if not ok then snd = nil end

local thud, whiffS, tick, koS
if snd then
    thud = snd.synth.new(snd.kWaveSquare)
    thud:setADSR(0.001, 0.08, 0, 0.05)
    whiffS = snd.synth.new(snd.kWaveNoise)
    whiffS:setADSR(0.001, 0.05, 0, 0.02)
    tick = snd.synth.new(snd.kWaveNoise)
    tick:setADSR(0.001, 0.03, 0, 0.01)
    koS = snd.synth.new(snd.kWaveSawtooth)
    koS:setADSR(0.001, 0.2, 0, 0.15)
end

function Sfx.hit()
    if not thud then return end
    thud:playNote(150, 0.4, 0.10)
end

function Sfx.whiff()
    if not whiffS then return end
    whiffS:playNote(600, 0.12, 0.06)
end

function Sfx.block()
    if not tick then return end
    tick:playNote(900, 0.3, 0.04)
end

function Sfx.ko()
    if not koS then return end
    koS:playNote(90, 0.5, 0.35)
    Util.after(0.05, function() if thud then thud:playNote(70, 0.5, 0.2) end end)
end

function Sfx.chime()
    if not thud then return end
    thud:playNote(660, 0.3, 0.08)
    Util.after(0.08, function() thud:playNote(990, 0.3, 0.1) end)
end

function Sfx.spit()
    if not whiffS then return end
    whiffS:playNote(300, 0.3, 0.09)
    if thud then thud:playNote(180, 0.3, 0.06) end
end

-- rising sting for the Frenzy super
function Sfx.super()
    if not koS then return end
    koS:playNote(220, 0.5, 0.10)
    Util.after(0.06, function() if koS then koS:playNote(330, 0.5, 0.10) end end)
    Util.after(0.12, function() if koS then koS:playNote(495, 0.5, 0.14) end end)
    Util.after(0.18, function() if thud then thud:playNote(660, 0.5, 0.18) end end)
end

-- Phase 5: the Molt shed -- a big cracking sting then a rising teneral shimmer
function Sfx.molt()
    if not koS then return end
    koS:playNote(110, 0.6, 0.14)
    if thud then thud:playNote(140, 0.5, 0.08) end
    Util.after(0.10, function() if koS then koS:playNote(392, 0.5, 0.12) end end)
    Util.after(0.20, function() if koS then koS:playNote(587, 0.5, 0.14) end end)
    Util.after(0.30, function() if thud then thud:playNote(880, 0.5, 0.16) end end)
end

-- Phase 5: crank-flick parry -- a bright metallic snap
function Sfx.parry()
    if tick then tick:playNote(1400, 0.4, 0.03) end
    if thud then thud:playNote(1046, 0.35, 0.06) end
end

-- ===========================================================================
-- Phase 4: MUSIC -- a clock-driven step sequencer (drift-free accumulator),
-- mirroring the sibling game whine/. Each stage + the title/menu + a victory
-- fanfare get their own palette (bps / root / scale / motif / bass / wave). The
-- current scene is a string in Sfx.scene, set by main.lua on state changes. The
-- accumulator advances every frame from Sfx.music(dt); it counts steps for the
-- smoke heartbeat and is fully no-op-safe if the synth kit is unavailable.
-- ===========================================================================

Sfx.on = true          -- music mute toggle (system-menu checkmark)
Sfx.scene = "title"    -- active palette key (main.lua sets this)

local mLead, mBass, mPad
if snd then
    mLead = snd.synth.new(snd.kWaveTriangle); mLead:setADSR(0.005, 0.09, 0, 0.12)
    mBass = snd.synth.new(snd.kWaveSquare);   mBass:setADSR(0.01, 0.12, 0, 0.16)
    mPad  = snd.synth.new(snd.kWaveSine);     mPad:setADSR(0.05, 0.2, 0.2, 0.3); mPad:setLegato(true)
end

local function hz(root, semis) return root * 2 ^ (semis / 12) end

-- bps beats/sec, root Hz, scale semitone steps, motif scale-degrees (-1 = rest),
-- bass degrees (one per 4 beats), drone semitone offset (nil = none), wave timbre.
local PAL = {
    title   = { bps = 3.6, root = 262, scale = {0,4,7,12},       motif = {0,2,4,7,4,2,7,4}, bass = {0,-5,-3,-5}, drone = -12, wave = snd and snd.kWaveTriangle },
    menu    = { bps = 3.0, root = 233, scale = {0,3,5,7,10},     motif = {0,3,5,3,7,5,3,-1}, bass = {0,-5,-7,-5}, drone = -12, wave = snd and snd.kWaveSquare },
    victory = { bps = 4.4, root = 349, scale = {0,4,7,11,12},    motif = {0,2,4,7,4,2,0,4}, bass = {0,3,4,7}, drone = 0, wave = snd and snd.kWaveTriangle },
    -- boss cue (Army Ant Major): fast, low, driving, dissonant (tense)
    boss    = { bps = 4.0, root = 147, scale = {0,1,3,6,7,8,11}, motif = {0,1,0,6,3,1,7,-1}, bass = {0,0,1,-1}, drone = -12, wave = snd and snd.kWaveSawtooth },
    -- stage themes (keyed to Stage.LIST ids)
    log     = { bps = 2.2, root = 196, scale = {0,3,5,7,10},     motif = {0,-1,3,-1,2,-1,5,-1}, bass = {0,-5,-7,-5}, drone = -12, wave = snd and snd.kWaveSine },
    pond    = { bps = 1.8, root = 330, scale = {0,2,4,7,9},      motif = {4,-1,2,-1,7,-1,4,-1}, bass = {0,4,-5,4}, drone = -12, wave = snd and snd.kWaveSine },
    meadow  = { bps = 2.6, root = 294, scale = {0,2,4,7,9},      motif = {0,2,4,2,7,4,2,0}, bass = {0,-5,-3,-5}, drone = -12, wave = snd and snd.kWaveTriangle },
    kitchen = { bps = 3.0, root = 220, scale = {0,1,3,5,7,8},    motif = {0,3,1,5,3,1,4,-1}, bass = {0,-1,-5,-6}, drone = -12, wave = snd and snd.kWaveSquare },
    anthill = { bps = 3.4, root = 175, scale = {0,2,3,5,7,8,10}, motif = {0,2,3,5,3,2,0,-1}, bass = {0,0,-5,-5}, drone = -12, wave = snd and snd.kWaveSquare },
    bark    = { bps = 2.4, root = 247, scale = {0,3,5,6,7,10},   motif = {0,-1,5,3,-1,6,5,3}, bass = {0,-7,-5,-7}, drone = -12, wave = snd and snd.kWaveSawtooth },
}

local mCur, mStep, mAcc = nil, 0, 0

function Sfx.musicStop()
    if mLead then mLead:noteOff() end
    if mBass then mBass:noteOff() end
    if mPad then mPad:noteOff() end
end

function Sfx.toggleMusic()
    Sfx.on = not Sfx.on
    if not Sfx.on then Sfx.musicStop() end
end

-- one-shot victory fanfare (played when an Arcade run is cleared)
function Sfx.victory()
    if not mLead then return end
    local ns = { 523, 659, 784, 1047, 784, 1047 }
    for i, n in ipairs(ns) do
        Util.after((i - 1) * 0.12, function()
            if mLead and Sfx.on then mLead:playNote(n, 0.4, 0.14) end
        end)
    end
end

function Sfx.music(dt)
    local key = Sfx.scene
    local p = PAL[key]
    if key ~= mCur then      -- scene changed: swap palette, restart the bar
        mCur, mStep, mAcc = key, 0, 0
        if not p then Sfx.musicStop()
        elseif mLead then
            if p.wave then mLead:setWaveform(p.wave) end
            if p.drone and mPad and Sfx.on then mPad:playNote(hz(p.root, p.drone), 0.1)
            elseif mPad then mPad:noteOff() end
        end
    end
    if not p then return end
    if not Sfx.on then return end     -- muted: hold the sequencer silent
    mAcc = mAcc + dt
    local spb = 1 / p.bps
    while mAcc >= spb do
        mAcc = mAcc - spb
        local sc = p.scale
        local m = p.motif[(mStep % #p.motif) + 1]
        if m and m >= 0 and mLead then
            local n = #sc
            local deg = sc[(m % n) + 1] + 12 * math.floor(m / n)
            mLead:playNote(hz(p.root, deg), 0.12, spb * 0.9)
        end
        if p.bass and mBass and (mStep % 2 == 0) then
            local bd = p.bass[(math.floor(mStep / 2) % #p.bass) + 1]
            mBass:playNote(hz(p.root, bd - 12), 0.1, spb * 1.4)
        end
        mStep = mStep + 1
        Harness.count("musicSteps")
    end
end
