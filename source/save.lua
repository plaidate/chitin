-- Phase 5: persistence + unlocks in the "chitin" datastore. Mirrors the sibling
-- game whine/save.lua (Save.load populates G fields at boot; Save.store writes
-- them on an unlock / new record).
--
-- CAVEAT (simulator + kill-harness only): playdate.datastore flushes to disk on
-- a CLEAN exit; tools/smoke.sh hard-kills the sim, so a write made during a
-- smoke run does NOT survive to the next launch (reads return defaults). This is
-- a harness limitation, NOT a bug -- datastore.write persists immediately on
-- real hardware. So save/unlock logic is verified IN-SESSION (the write fires,
-- the flag flips, and dependent UI updates within the same run).
--
-- Schema (key "chitin"):
--   arcadeCleared  bool  -- has any fighter beaten the Army Ant boss?
--   antUnlocked    bool  -- is the Army Ant a selectable (7th, joke) pick?
--   clears         table -- per-fighter id -> Arcade-clear count
--   bestSurvival   int   -- most bugs survived in one Survival run
--   bestTime       int   -- fastest Time-Attack ladder clear (seconds; 0 = none)

Save = {}

function Save.load()
    local d = playdate.datastore.read("chitin") or {}
    G.arcadeCleared = d.arcadeCleared or false
    G.antUnlocked = d.antUnlocked or false
    G.clears = d.clears or {}
    G.bestSurvival = d.bestSurvival or 0
    G.bestTime = d.bestTime or 0
end

function Save.store()
    playdate.datastore.write({
        arcadeCleared = G.arcadeCleared or false,
        antUnlocked = G.antUnlocked or false,
        clears = G.clears or {},
        bestSurvival = G.bestSurvival or 0,
        bestTime = G.bestTime or 0,
    }, "chitin")
    Harness.count("saveWrites")
end
