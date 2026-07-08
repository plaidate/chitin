-- Fightin' Chitin - Phase 4: stages, music, the Arcade ladder + per-character
-- endings, and menus. Builds on Phases 1-3 (core loop, motions/specials/Frenzy
-- super, the 6-fighter roster + balance harness), none of which regress.
--
-- State flow:
--   title -> menu -> select -> fight <-> roundover -> matchover
--     -> (interstitial -> next fight) | ending | result -> menu
-- Modes: arcade (the single-player heart), survival, timeattack, training,
-- versus. Balance mode (make balance) keeps its own headless AI-vs-AI path.

import "CoreLibs/graphics"

import "config"
import "util"
import "harness"
import "save"
import "sfx"
import "rig"
import "stage"
import "fighters"
import "menu"
import "hud"
import "draw"
import "motion"
import "fight"
import "ai"
import "input"
import "select"

Game = {}

math.randomseed(playdate.getSecondsSinceEpoch())
playdate.display.setRefreshRate(SMOKE_BUILD and 0 or 30)
Harness.shotPath = SHOT_PATH

local BALANCE = (BALANCE_BUILD == true)
local BALANCE_MATCHES = 4

if BALANCE then
    C.ROUNDS_TO_WIN = 1
    C.ROUND_TIME = 12
    C.BALANCE_HP_SCALE = 0.5
end
-- Smoke (non-balance) shortens rounds so the autopilot can climb the whole
-- Arcade ladder (and cycle every mode) inside a bounded run.
local SMOKE = SMOKE_BUILD and not BALANCE
if SMOKE then C.ROUND_TIME = 15 end

-- Phase 5: load persisted unlocks / records (arcadeCleared, antUnlocked, clears,
-- bestSurvival, bestTime) into G before the state machine starts.
Save.load()

G.state = "title"
G.t = 0
G.wins1 = 0
G.wins2 = 0
G.round = 0
G.rounds = 0
G.shake = 0
G.roundTimer = 0
G.matchIdx = 0
G.matches = 0
G.seen = {}
G.selId1 = "rhino"
G.selId2 = "leaf"
G.mode = "versus"
G.trainBehav = "cpu"

-- balance mode state (unchanged from Phase 3)
G.balance = BALANCE
G.balPair = 1
G.balMatch = 0
G.balanceDone = false
G.winMatrix = {}
for i = 1, 6 do
    G.winMatrix[i] = {}
    for j = 1, 6 do G.winMatrix[i][j] = 0 end
end

local FREEZE_ROUND = BALANCE and 2 or 90
local FREEZE_MATCH = BALANCE and 2 or 90
local FREEZE_INTER = SMOKE and 3 or 70
-- ending/result linger a few extra frames in smoke so the per-character ENDING
-- screen is on-screen long enough for the harness state-shot to capture it
local FREEZE_END   = SMOKE and 8 or 90

local function markSeen(id) if id then G.seen[id] = true end end

local function others(pc)
    local t = {}
    for _, id in ipairs(Fighters.LIST) do if id ~= pc then t[#t + 1] = id end end
    return t
end

-- ---- round / fight construction -------------------------------------------

function Game.newRound()
    G.round = G.round + 1
    G.p1 = Fight.newFighter(C.START_X1, 1, true, G.selId1)
    G.p2 = Fight.newFighter(C.START_X2, -1, false, G.selId2)
    -- Molt is once PER MATCH: carry the shed flag across rounds of this match
    G.p1.molted = G.moltedP1 or false
    G.p2.molted = G.moltedP2 or false
    if G._p1StartHp then
        G.p1.hp = math.max(1, math.min(G._p1StartHp, G.p1.maxHp))
        G._p1StartHp = nil
    end
    G.projectiles = {}
    G.roundTimer = (G.mode == "training") and (99 * 30) or (C.ROUND_TIME * 30)
    G.roundResult = nil
    G.roundWinner = nil
    Draw.resetFx()
    G.state = "fight"
    G.t = 0
end

-- start a match on a given stage; rounds = wins needed (smoke forces 1)
function Game.startFight(opts)
    G.selId1 = opts.pc
    G.selId2 = opts.opp
    C.ROUNDS_TO_WIN = SMOKE and 1 or (opts.rounds or 2)
    Stage.set(opts.stage)
    Sfx.scene = Stage.def(Stage.current).music
    G.bossFight = opts.boss or false
    if opts.boss then Sfx.scene = "boss" end  -- tense boss cue over the stage
    G.moltedP1, G.moltedP2 = false, false      -- fresh Molt charge each match
    G.wins1, G.wins2, G.round = 0, 0, 0
    G._p1StartHp = opts.p1Hp
    markSeen(opts.pc); markSeen(opts.opp)
    Sfx.chime()
    Game.newRound()
end

-- balance path keeps the original entry point (no stage/music needed for stub)
function Game.newMatch()
    G.moltedP1, G.moltedP2 = false, false
    G.wins1, G.wins2, G.round = 0, 0, 0
    markSeen(G.selId1); markSeen(G.selId2)
    Sfx.chime()
    Game.newRound()
end

-- ---- mode starters ---------------------------------------------------------

function Game.startArcade(pc)
    G.mode = "arcade"; G.pcId = pc
    G.arcOrder = others(pc); G.arcIdx = 1; G.continues = 3
    G.arcRuns = (G.arcRuns or 0) + 1
    G.inBoss = false
    local opp = G.arcOrder[1]
    G.curOpp = opp
    Game.startFight({ pc = pc, opp = opp, stage = Stage.forFighter(opp), rounds = 2 })
end

function Game.startSurvival(pc)
    G.mode = "survival"; G.pcId = pc; G.survScore = 0; G.survFights = 0
    local opp = Fighters.at(Fighters.index(pc) + 1)
    Game.startFight({ pc = pc, opp = opp, stage = Stage.LIST[1], rounds = 1 })
end

function Game.startTimeAttack(pc)
    G.mode = "timeattack"; G.pcId = pc
    G.taOrder = others(pc); G.taIdx = 1; G.taClock = 0
    local opp = G.taOrder[1]
    Game.startFight({ pc = pc, opp = opp, stage = Stage.forFighter(opp), rounds = 1 })
end

function Game.startTraining(a, b)
    G.mode = "training"; G.pcId = a
    G.selId1 = a; G.selId2 = b
    C.ROUNDS_TO_WIN = 1
    Stage.set(Stage.forFighter(a))
    Sfx.scene = Stage.def(Stage.current).music
    markSeen(a); markSeen(b)
    Sfx.chime()
    Game.newRound()
end

function Game.startVersus(a, b)
    G.mode = "versus"; G.pcId = a
    Game.startFight({ pc = a, opp = b, stage = Stage.forFighter(b), rounds = 2 })
end

function Game.dispatchSelected()
    local m, a, b = G.mode, G.selId1, G.selId2
    if m == "arcade" then Game.startArcade(a)
    elseif m == "survival" then Game.startSurvival(a)
    elseif m == "timeattack" then Game.startTimeAttack(a)
    elseif m == "training" then Game.startTraining(a, b)
    else Game.startVersus(a, b) end
end

-- ---- transitions -----------------------------------------------------------

local function toMenu()
    G.state = "menu"; Menu.enter(); Sfx.scene = "menu"
end

local function toSelect()
    G.state = "select"; Select.enter()
end

local function interstitial(text, thenFn)
    G.interText = text; G.interNext = thenFn
    G.state = "interstitial"; G.t = 0; G.freeze = FREEZE_INTER
end

local function resultScreen(title, lines, victory)
    G.resultTitle = title; G.resultLines = lines
    G.state = "result"; G.t = 0; G.freeze = FREEZE_END
    if victory then Sfx.scene = "victory"; Sfx.victory() else Sfx.scene = "menu" end
end

-- ---- round / match resolution ----------------------------------------------

local function endRound(result, winner)
    G.roundResult = result; G.roundWinner = winner
    G.state = "roundover"; G.t = 0; G.freeze = FREEZE_ROUND
    G.rounds = G.rounds + 1
    Harness.count("roundEnds")
end

local function checkRoundEnd()
    local p1, p2 = G.p1, G.p2
    if G.mode == "training" then
        -- infinite spar: respawn either fighter that drops, never end
        if p1.hp <= 0 then p1.hp = p1.maxHp; p1.state = "idle" end
        if p2.hp <= 0 then p2.hp = p2.maxHp; p2.state = "idle" end
        return
    end
    if p1.hp <= 0 and p2.hp <= 0 then endRound("DOUBLE K.O.", 0)
    elseif p2.hp <= 0 then endRound("K.O.", 1)
    elseif p1.hp <= 0 then endRound("K.O.", 2)
    elseif G.roundTimer <= 0 then
        if p1.hp > p2.hp then endRound("TIME", 1)
        elseif p2.hp > p1.hp then endRound("TIME", 2)
        else endRound("TIME", 0) end
    end
end

-- Arcade progression -------------------------------------------------------
local BOSS_ID = Fighters.BOSS   -- the Army Ant Major, ladder fight 6

-- start the boss fight on its own turf (the Ant-Hill Mound), tense boss cue
local function startBossFight()
    G.inBoss = true
    G.curOpp = BOSS_ID
    interstitial("FINAL FOE:  ARMY ANT MAJOR", function()
        Game.startFight({ pc = G.pcId, opp = BOSS_ID, stage = "anthill",
            rounds = 2, boss = true })
    end)
end

-- boss beaten: the Arcade run is complete -> unlock the ant + record + ending
local function arcadeClear()
    Harness.count("endings")
    G.inBoss = false
    G.arcadeCleared = true
    G.clears = G.clears or {}
    G.clears[G.pcId] = (G.clears[G.pcId] or 0) + 1
    local newlyUnlocked = not G.antUnlocked
    G.antUnlocked = true                 -- ant becomes selectable THIS session
    if newlyUnlocked then Harness.count("unlocks") end
    Save.store()                         -- persist unlock + clear (in-session)
    G.endingId = G.pcId
    G.state = "ending"; G.t = 0; G.freeze = FREEZE_END
    Sfx.scene = "victory"; Sfx.victory()
end

local function arcadeWin()
    Harness.count("arcadeWins")
    if G.inBoss then arcadeClear(); return end   -- beat the boss = full clear
    G.arcIdx = G.arcIdx + 1
    if G.arcIdx > #G.arcOrder then startBossFight(); return end
    local opp = G.arcOrder[G.arcIdx]
    G.curOpp = opp
    interstitial(string.format("OPPONENT  %d / %d", G.arcIdx, #G.arcOrder), function()
        Game.startFight({ pc = G.pcId, opp = opp, stage = Stage.forFighter(opp), rounds = 2 })
    end)
end

local function arcadeLose()
    G.continues = G.continues - 1
    if G.continues < 0 then
        local where = G.inBoss and "the ARMY ANT MAJOR"
            or string.format("rung %d of %d", G.arcIdx, #G.arcOrder)
        resultScreen("GAME OVER", { "Fell at " .. where, "- press Ⓐ -" })
        return
    end
    local opp = G.curOpp or G.arcOrder[G.arcIdx]
    local isBoss = G.inBoss
    interstitial(string.format("CONTINUE?  (%d left)", G.continues), function()
        Game.startFight({ pc = G.pcId, opp = opp,
            stage = isBoss and "anthill" or Stage.forFighter(opp),
            rounds = 2, boss = isBoss })
    end)
end

-- Survival -----------------------------------------------------------------
-- persist a new Survival best (bugs survived in one run) if we beat the record
local function recordSurvival()
    if (G.survScore or 0) > (G.bestSurvival or 0) then
        G.bestSurvival = G.survScore
        Save.store()
    end
end

local function survivalWin()
    G.survScore = (G.survScore or 0) + 1
    G.survFights = (G.survFights or 0) + 1
    Harness.count("survivalWins")
    recordSurvival()
    if SMOKE and G.survScore >= 6 then
        resultScreen("SURVIVAL DEMO", { string.format("Survived %d bugs", G.survScore), "" })
        return
    end
    local heal = math.floor((G.p1 and G.p1.hp or 0) + (Fighters.def(G.pcId).hp or 100) * 0.35)
    local opp = Fighters.at(Fighters.index(G.pcId) + 1 + G.survFights)
    local stage = Stage.LIST[(G.survFights % #Stage.LIST) + 1]
    interstitial(string.format("SURVIVED  x%d", G.survScore), function()
        Game.startFight({ pc = G.pcId, opp = opp, stage = stage, rounds = 1, p1Hp = heal })
    end)
end

-- Time Attack --------------------------------------------------------------
local function timeAttackWin()
    Harness.count("taWins")
    G.taIdx = G.taIdx + 1
    if G.taIdx > #G.taOrder then
        local secs = math.floor((G.taClock or 0) / 30)
        if (G.bestTime or 0) == 0 or secs < G.bestTime then
            G.bestTime = secs                -- new fastest ladder clear
            Save.store()
        end
        resultScreen("LADDER CLEARED",
            { string.format("Time  %d:%02d", math.floor(secs / 60), secs % 60), "" }, true)
        return
    end
    local opp = G.taOrder[G.taIdx]
    interstitial(string.format("RUNG  %d / %d", G.taIdx, #G.taOrder), function()
        Game.startFight({ pc = G.pcId, opp = opp, stage = Stage.forFighter(opp), rounds = 1 })
    end)
end

-- record a completed match into the balance win matrix (unchanged)
local function recordBalance()
    local i1 = Fighters.index(G.selId1)
    local i2 = Fighters.index(G.selId2)
    if G.matchWinner == 1 then
        G.winMatrix[i1][i2] = G.winMatrix[i1][i2] + 1
    else
        G.winMatrix[i2][i1] = G.winMatrix[i2][i1] + 1
    end
    G.balMatch = G.balMatch + 1
    if G.balMatch >= BALANCE_MATCHES then
        G.balMatch = 0
        G.balPair = G.balPair + 1
        if G.balPair > Select.PAIRS then G.balanceDone = true end
    end
end

local function afterMatchModes()
    -- smoke biases P1 to advance so the ladder + endings are reached headless
    local won = (G.matchWinner == 1) or SMOKE
    local m = G.mode
    if m == "arcade" then
        if won then arcadeWin() else arcadeLose() end
    elseif m == "timeattack" then
        if won then timeAttackWin() else
            resultScreen("TIME ATTACK FAILED",
                { string.format("Stopped at rung %d/%d", G.taIdx, #G.taOrder), "- press Ⓐ -" })
        end
    elseif m == "survival" then
        if won then survivalWin() else
            recordSurvival()
            resultScreen("GAME OVER",
                { string.format("Survived %d bugs", G.survScore or 0), "- press Ⓐ -" })
        end
    else -- versus
        local who = G.matchWinner == 1 and "PLAYER 1 WINS" or "PLAYER 2 WINS"
        resultScreen(who,
            { Fighters.def(G.selId1).name .. "  vs  " .. Fighters.def(G.selId2).name, "- press Ⓐ -" })
    end
end

local function afterMatch()
    if G.balance then
        if G.balanceDone then
            playdate.datastore.write({ matrix = G.winMatrix, done = true,
                pairs = Select.PAIRS, perPair = BALANCE_MATCHES }, "balance")
            G.state = "done"
            return
        end
        toSelect()  -- next matchup (balance pair advance handled in recordBalance)
    else
        afterMatchModes()
    end
end

local function resolveRoundOver()
    local w = G.roundWinner
    if w == 1 then G.wins1 = G.wins1 + 1
    elseif w == 2 then G.wins2 = G.wins2 + 1 end

    if G.wins1 >= C.ROUNDS_TO_WIN or G.wins2 >= C.ROUNDS_TO_WIN then
        G.matchWinner = G.wins1 > G.wins2 and 1 or 2
        G.state = "matchover"; G.t = 0; G.freeze = FREEZE_MATCH
        G.matches = G.matches + 1
        Harness.count("matchovers")
        if G.balance then recordBalance() end
        Sfx.chime()
    else
        Game.newRound()
    end
end

-- ---- main tick -------------------------------------------------------------

local function proceed(canHuman)
    G.freeze = (G.freeze or 0) - 1
    if G.freeze > 0 then return false end
    if Harness.enabled then return true end
    if canHuman then return playdate.buttonJustPressed(playdate.kButtonA) end
    return true
end

local function tick()
    local dt = C.DT
    G.t = G.t + dt
    Util.runPending(dt)
    local s = G.state

    if s == "title" then
        if Input.confirm() then
            if G.balance then G.mode = "versus"; toSelect() else toMenu() end
        end

    elseif s == "menu" then
        local mode = Menu.update()
        if mode then
            G.mode = mode
            G.selSingle = (mode == "arcade" or mode == "survival" or mode == "timeattack")
            toSelect()
        end

    elseif s == "select" then
        if Select.update() then
            if G.balance then Game.newMatch() else Game.dispatchSelected() end
        end

    elseif s == "fight" then
        local inp1 = Input.forFighter(G.p1, G.p2)
        local inp2 = Input.forFighter(G.p2, G.p1)
        Fight.update(inp1, inp2)
        if G.mode ~= "training" and G.roundTimer > 0 then G.roundTimer = G.roundTimer - 1 end
        if G.mode == "timeattack" then G.taClock = (G.taClock or 0) + 1 end
        if G.mode == "training" then
            -- free spar: exit to menu on Ⓑ (human) / a beat (smoke)
            local quit = (not Harness.enabled and playdate.buttonJustPressed(playdate.kButtonB))
                or (Harness.enabled and (G.t or 0) > 4)
            if quit then toMenu() else checkRoundEnd() end
        else
            checkRoundEnd()
        end

    elseif s == "roundover" then
        Fight.settle()
        G.freeze = G.freeze - 1
        if G.freeze <= 0 then resolveRoundOver() end

    elseif s == "matchover" then
        Fight.settle()
        G.freeze = G.freeze - 1
        if G.freeze <= 0 then afterMatch() end

    elseif s == "interstitial" then
        if proceed(false) then
            local f = G.interNext; G.interNext = nil
            if f then f() end
        end

    elseif s == "ending" then
        if proceed(true) then toMenu() end

    elseif s == "result" then
        if proceed(true) then toMenu() end

    elseif s == "done" then
        if G.balance and (G.balDoneWrites or 0) < 3 then
            G.balDoneWrites = (G.balDoneWrites or 0) + 1
            playdate.datastore.write({ matrix = G.winMatrix, done = true,
                pairs = Select.PAIRS, perPair = BALANCE_MATCHES }, "balance")
        end
    end

    if not G.balance then Sfx.music(dt) end
    Draw.frame()
end

-- ---- system menu (music toggle + training-dummy behaviour) -----------------
do
    local sysmenu = playdate.getSystemMenu and playdate.getSystemMenu()
    if sysmenu then
        sysmenu:addCheckmarkMenuItem("music", true, function(v) Sfx.on = v; if not v then Sfx.musicStop() end end)
        sysmenu:addOptionsMenuItem("dummy", { "cpu", "block", "stand" }, "cpu",
            function(v) G.trainBehav = v end)
    end
end

-- ---- harness bookkeeping ---------------------------------------------------

local function seenList()
    local out = {}
    for _, id in ipairs(Fighters.LIST) do if G.seen[id] then out[#out + 1] = id end end
    return out
end

Harness.extra = function(t)
    t.state = G.state
    t.mode = G.mode
    t.stage = Stage.current
    t.stagesSeen = Stage.seenCount()
    t.wins1 = G.wins1
    t.wins2 = G.wins2
    t.round = G.round
    t.rounds = G.rounds
    t.matches = G.matches
    t.timer = math.max(0, math.ceil((G.roundTimer or 0) / 30))
    t.f1 = G.selId1
    t.f2 = G.selId2
    t.pc = G.pcId
    if G.mode == "arcade" and G.arcOrder then
        t.ladder = G.inBoss and "BOSS" or (G.arcIdx .. "/" .. #G.arcOrder)
    end
    if G.mode == "timeattack" and G.taOrder then t.ladder = G.taIdx .. "/" .. #G.taOrder end
    if G.survScore then t.survScore = G.survScore end
    -- Phase 5 markers (only stamped once true/nonzero, so grep is clean)
    if G.inBoss then t.inBoss = true end
    if G.bossFight then t.bossFight = true end
    if G.antUnlocked then t.antUnlocked = true end
    if G.arcadeCleared then t.arcadeCleared = true end
    t.selCount = Fighters.selCount()
    if (G.bestSurvival or 0) > 0 then t.bestSurvival = G.bestSurvival end
    if (G.bestTime or 0) > 0 then t.bestTime = G.bestTime end
    local sl = seenList()
    t.fighters = sl
    t.fightersSeen = #sl
    if G.p1 then
        t.hp1 = math.floor(G.p1.hp); t.hp2 = math.floor(G.p2.hp)
        t.x1 = math.floor(G.p1.x); t.x2 = math.floor(G.p2.x)
        t.move1 = G.p1.moveName or G.p1.state
        t.move2 = G.p2.moveName or G.p2.state
        t.frenzy1 = math.floor((G.p1.frenzy or 0) * 100)
        t.frenzy2 = math.floor((G.p2.frenzy or 0) * 100)
        t.frenzyPeak = math.floor((G.frenzyPeak or 0) * 100)
        t.pois1 = G.p1.poison and G.p1.poison.ticks or 0
        t.pois2 = G.p2.poison and G.p2.poison.ticks or 0
        if (G.p1.teneral or 0) > 0 then t.teneral1 = G.p1.teneral end
        if (G.p2.teneral or 0) > 0 then t.teneral2 = G.p2.teneral end
        if G.p1.molted then t.molted1 = true end
        if G.p2.molted then t.molted2 = true end
    end
    if G.matchWinner then t.matchWinner = G.matchWinner end
    if G.balance then
        t.balPair = G.balPair; t.balMatch = G.balMatch
        t.balanceDone = G.balanceDone; t.matrix = G.winMatrix
    end
end

local frame = 0
function playdate.update()
    frame = frame + 1
    Harness.frame(frame, tick)
end
