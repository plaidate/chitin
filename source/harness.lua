-- Smoke-test harness. The Makefile stages smokeflag.lua: SMOKE_BUILD false
-- for release (no-op), true for `make smoke` (pcall-wrapped update writing
-- errors to "err", a 90-frame heartbeat to "smoke", periodic screenshots,
-- and an autopilot the input module consults).

import "smokeflag"

Harness = {
    enabled = SMOKE_BUILD,
    counters = {},
    autopilot = nil,
    extra = nil,
    shotPath = nil,
}

function Harness.count(key, n)
    if not Harness.enabled then return end
    Harness.counters[key] = (Harness.counters[key] or 0) + (n or 1)
end

function Harness.frame(frame, updateFn)
    if not Harness.enabled then
        updateFn()
        return
    end
    local ok, err = pcall(updateFn)
    if not ok then
        playdate.datastore.write({ err = tostring(err) }, "err")
    end
    if frame % 90 == 0 then
        local t = {}
        for k, v in pairs(Harness.counters) do t[k] = v end
        t.frame = frame
        if Harness.extra then pcall(Harness.extra, t) end
        playdate.datastore.write(t, "smoke")
    end
    -- balance mode draws only a throughput stub (white + one marker square), so
    -- it must NOT write screenshots -- otherwise its minimal frame masquerades as
    -- the real game on the shared shot path. Only the normal build captures art.
    if Harness.shotPath and playdate.simulator and not G.balance then
        if frame % 300 == 0 then
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), Harness.shotPath)
        end
        -- art sweep: keep the latest frame of each distinct scene, tagged by state
        if frame % 40 == 0 or frame == 10 then
            local tag = tostring(G.state or "none")
            local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-" .. tag .. ".png")
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
        end
        -- guaranteed one-shot per state (brief screens like the menu can slip
        -- between the periodic captures above)
        Harness.stateShot = Harness.stateShot or {}
        local st = tostring(G.state or "none")
        if not Harness.stateShot[st] and (G.t or 0) > 0.15 then
            Harness.stateShot[st] = true
            local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-" .. st .. ".png")
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
        end
        -- one mid-fight frame per STAGE, so every backdrop can be eyeballed
        Harness.stageShot = Harness.stageShot or {}
        if G.state == "fight" and G.p1 and (G.t or 0) > 0.03 then
            local sid = Stage and Stage.current
            if sid and not Harness.stageShot[sid] then
                Harness.stageShot[sid] = true
                local p = Harness.shotPath:gsub("chitin%-shot%.png$", "stage-" .. sid .. ".png")
                playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
            end
        end
        -- Phase 5: one frame of the ARMY ANT BOSS fight (big-ant rig on its
        -- Ant-Hill stage, both fighters visible)
        if not Harness.bossShot and G.state == "fight" and G.inBoss and G.p1
            and (G.t or 0) > 0.05 then
            Harness.bossShot = true
            local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-boss.png")
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
        end
        -- Phase 5: one frame of the SWARM super sweeping the screen
        if not Harness.swarmShot and G.state == "fight" and G.swarmFx then
            Harness.swarmShot = true
            local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-swarm.png")
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
        end
        -- Phase 5: one frame of a MOLT teneral state -- captured a little way into
        -- the rage (not the first frame) so the fighter has stepped clear of its
        -- discarded shell husk and both read distinctly
        if not Harness.moltShot and G.state == "fight" and G.p1 then
            for _, ff in ipairs({ G.p1, G.p2 }) do
                if (ff.teneral or 0) > 0 and (ff.teneral or 0) <= C.TENERAL_FRAMES - 22 then
                    Harness.moltShot = true
                    local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-molt.png")
                    playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
                end
            end
        end
        -- one guaranteed HIT frame: capture while a fighter is flashing negative
        if not Harness.hitShot and G.state == "fight" and G.p1
            and (((G.p1.hitFlash or 0) > 0) or ((G.p2.hitFlash or 0) > 0)) then
            Harness.hitShot = true
            local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-hit.png")
            playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
        end
        -- one frame with the Dragonfly aloft mid-screen (sustained flight, not a
        -- jump apex): airborne, well above the ground, still in powered flight
        if not Harness.flyShot and G.state == "fight" and G.p1 then
            for _, ff in ipairs({ G.p1, G.p2 }) do
                if ff.canFly and not ff.onGround and ff.flying
                    and ff.y <= C.GROUND_Y - 55 then
                    Harness.flyShot = true
                    local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-fly.png")
                    playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
                end
            end
        end
        -- one frame of the mantis mid-strike (forelegs shot out) to verify the
        -- praying-arm extension reads as its attack
        if not Harness.mantisAtk and G.state == "fight" and G.p1 then
            for _, ff in ipairs({ G.p1, G.p2 }) do
                if ff.def and ff.def.rig == "mantis" and ff.state == "attack"
                    and ff.move and ff.moveFrame > ff.move.startup
                    and ff.moveFrame <= ff.move.startup + ff.move.active + 2 then
                    Harness.mantisAtk = true
                    local p = Harness.shotPath:gsub("chitin%-shot%.png$", "art-mantis-atk.png")
                    playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
                end
            end
        end
        -- one fight frame per rig, so each silhouette can be inspected distinctly
        Harness.rigShot = Harness.rigShot or {}
        if G.state == "select" and G.selI1 and (G.t or 0) > 0.35 then
            for _, si in ipairs({ G.selI1, G.selI2 }) do
                local r = Fighters.def(Fighters.at(si)).rig
                if r and not Harness.rigShot[r] then
                    Harness.rigShot[r] = true
                    local p = Harness.shotPath:gsub("chitin%-shot%.png$", "rig-" .. r .. ".png")
                    playdate.simulator.writeToFile(playdate.graphics.getDisplayImage(), p)
                end
            end
        end
    end
end
