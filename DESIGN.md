# Fightin' Chitin

A one-on-one 2D fighting game for the Playdate, starring the insect world's
real brawlers. Two attack buttons keep it approachable; motion inputs and the
**crank** give it a deep special-move layer. Six fighters, each a distinct
archetype drawn from real behaviour, form a clean rock-paper-scissors of
grappler / rushdown / zoner. Single-player-focused (the Playdate has no second
controller): an **Arcade ladder** with per-character endings, plus Survival,
Time Attack and Training.

Tone: crunchy, comic, tactile. Big bold 1-bit silhouettes; the crank is your
adrenaline.

---

## 1. Design pillars

1. **Simple to hold, deep to master.** Two attack buttons (Light / Heavy) plus
   directional and motion inputs — no six-button arcade layout to fake on a
   d-pad.
2. **The crank is the signature.** It drives the **Frenzy** super meter and the
   **Molt** comeback — mechanics that only make sense on this hardware.
3. **Archetypes over gimmicks.** Every fighter is a legible role (grappler,
   rushdown, zoner, aerial) with real strengths and weaknesses, so matchups are
   readable and balance is tunable.
4. **1-bit as a strength.** Bold outline-forward silhouettes, dithered
   carapace, hit-sparks and screen-shake sell impact. Fighters are
   **parametric skeletal rigs**, not hand-drawn frame stacks — the same
   procedural-animation technique used across this repo's other games.
5. **The AI is the test harness.** One behaviour system powers the CPU
   opponent, the second player, and the headless smoke autopilot — so we can
   auto-tune balance from AI-vs-AI win-rate matrices.

---

## 2. Controls

The Playdate gives us d-pad + Ⓐ + Ⓑ + crank. The scheme:

| Input | Action |
|---|---|
| **✛ ←/→** | Walk toward / away. Holding *away* from the foe = **block**. Double-tap = **dash / back-hop**. |
| **✛ ↓** | Crouch (low block, low attacks). |
| **✛ ↑ / ↖ / ↗** | Jump (neutral / back / forward). |
| **Ⓐ** | **Light** attack — fast, low damage, chains into combos. |
| **Ⓑ** | **Heavy** attack — slow, high damage, launches / knocks down. |
| **Ⓐ + Ⓑ** | **Throw** in close (beats block); **Super** when Frenzy is full. |
| **Crank** | **Frenzy** — spin to charge the super meter. |

Each attack has stand / crouch / jump / forward-press variants, so two buttons
yield ~6 normals — enough vocabulary without a stick.

**Specials = motion + button** (Street Fighter grammar). With two attack
buttons each motion has a Light and a Heavy version:

- **↓ ↘ → + Ⓐ/Ⓑ** — quarter-circle forward: projectile / lunge
- **→ ↓ ↘ + Ⓐ/Ⓑ** — "dragon punch" Z-motion: anti-air reversal
- **charge ← 1s, then → + Ⓐ/Ⓑ** — charge special (rewards defensive play)
- **360° + Ⓐ+Ⓑ** — command grab (grapplers only)

Input is buffered (~8 frames) with lenient motion windows for the small d-pad.

---

## 3. Combat systems

### 3.1 Health & rounds
- Two health bars (100 HP each), a Frenzy gauge, a round timer (~60s), round
  pips. **Best of 3.** KO or time-out (higher HP wins) ends a round.

### 3.2 Normals & combos
- **Light** chains into **Heavy** (Ⓐ→Ⓐ→Ⓑ). Specials cancel out of normals.
- Frame data (startup / active / recovery, in 30 fps frames) lives in a config
  table per move — the single source of truth for balance.
- On hit: **hitstun**; on block: **blockstun** + chip damage (Heavy/specials
  only). Heavy launches into a juggle window; hard knockdown on sweep.

### 3.3 Defense
- Block (hold away), low block (crouch), throw-break (Ⓐ+Ⓑ on incoming throw).
- Advanced tech: a **crank-flick parry** — a fast crank snap in the last few
  frames before a hit negates it and grants advantage (high risk/reward,
  optional, for experts).

### 3.4 Frenzy (the crank super)
- The crank *is* the meter. Spinning charges Frenzy fast — but you're committed
  while you spin (no dash, weakened block), so building meter is a **real
  risk** taken in openings, not a passive drip. Combat also charges it slowly,
  so cranking is *acceleration, not a chore*.
- At full bar, **Ⓐ+Ⓑ unleashes the fighter's Super** — a cinematic, high-damage
  signature move with brief invulnerability on startup.

### 3.5 Molt (comeback)
- At critical health, spend a full Frenzy bar to **Molt**: shed the exoskeleton
  for a one-time heal and a few seconds of *teneral rage* (faster, stronger)
  at the cost of taking extra damage while soft. A dramatic, thematic reversal.
  *(Mechanic named for the molt; kept distinct from the sibling game MOLT.)*

---

## 4. Roster (6 fighters)

Balance triangle: **Grapplers beat Zoners → Zoners beat Rushdown → Rushdown
beats Grapplers.** Aerial and DoT fighters cut across the triangle.

| # | Fighter | Archetype | Feel | Specials (L / H variants) | Super |
|---|---|---|---|---|---|
| 1 | **Rhinoceros Beetle** | Grappler (heavy) | Slow, armored, huge damage; armor on some startups | **Pry-&-Flip** (360 command throw); **Gore Charge** (charge ←→) | *Boulder Toss* — grab, horn-launch across the screen |
| 2 | **Leaf-footed Bug** | Grappler (technical) | Wrestling, spiked hind-leg grabs, counters | **Leg-Hook** (360 throw); **Thorn Counter** (QCB — reflects a hit) | *Bramble Suplex* — multi-throw chain |
| 3 | **Praying Mantis** | Rushdown (glass cannon) | Fast, deadly, fragile (low HP) | **Strike Rush** (QCF, spiked-foreleg dash); **Overhead Reap** (DP) | *Prayer's End* — foreleg flurry |
| 4 | **Tiger Beetle** | Rushdown (speed) | Fastest walk/dash; mixups | **Blur Dash** (QCF, teleport-slash); **Mandible Flurry** (mash after QCB) | *Blur Storm* — full-screen dashes |
| 5 | **Dragonfly** | Aerial zoner | Flight, air-dashes, dives | **Wing Buffet** (QCF projectile, air-OK); **Dogfight Dive** (DP, aerial overhead) | *Hawking Run* — multi-angle dive-bombs |
| 6 | **Assassin Bug** | Zoner (DoT) | Long reach, venom damage-over-time | **Venom Jab** (QCF, applies poison DoT); **Rostrum Spear** (charge, long poke) | *Liquefy* — pin + venom flood, heavy DoT |

Boss (later phase): the **Army Ant Major** — an intentionally-unbalanced final
CPU with a swarm super; unlockable as a joke pick.

Each fighter also carries: distinct HP (Mantis low, Rhino high), walk/dash
speed, jump arc, and a 2-line Arcade ending.

---

## 5. Stages (habitat-themed, 1-bit parallax)

Each ties to a fighter's turf, one recommended per character:

1. **Rotting Log Arena** (beetles) — bracket fungi, drifting spores.
2. **Pond Surface** (dragonfly) — reflections, skating water-striders in the bg.
3. **Flower Meadow** (leaf-footed) — nodding blooms, drifting pollen.
4. **Kitchen Counter at Night** (assassin bug) — a looming porch-light glow,
   human-world scale.
5. **Ant-Hill Mound** (boss) — marching ant silhouettes.
6. **Bark Face** (mantis / tiger beetle) — vertical grooves, moss dither.

Optional ecological **hazards** (a drip, a passing shadow) — toggleable,
**off by default** for competitive balance.

---

## 6. Graphics — parametric skeletal rigs

The fighter trap is animation volume (~40 poses × 6 = hundreds of frames). We
sidestep it the way this repo's other games do: **each insect is a rig of
jointed segments** (thorax, abdomen, head, leg pairs, forelegs, wings,
horn/mandibles). A **pose** is a table of scalar joint parameters (body lean,
crouch depth, lead-foreleg extension & angle, wing flare, …); a **move** is a
timed interpolation between keyframe poses. Benefits:

- 6 fighters become feasible; animation is smooth and cheap.
- Plays to 1-bit strengths: **outline-forward silhouettes** (white outline,
  black carapace fill, dithered shading) stay readable even with two bugs
  overlapping mid-combo (two-pass outline renderer).
- Attacks are legible: the striking foreleg visibly extends during active
  frames; recovery visibly retracts.

Hit-sparks, dust puffs, and screen-shake are drawn procedurally. Backdrops are
layered 1-bit parallax planes.

---

## 7. Audio

Per the repo playbook: the synth kit + a **clock-driven step sequencer**
(drift-free). Each stage gets a short looping theme; punchy hit / whiff /
block / KO SFX; a rising sting on Super and Molt; a tense boss theme.

---

## 8. Modes & structure

- **Arcade** — 6-fight ladder vs CPU, per-character ending. The single-player
  heart.
- **Survival** — endless, HP carries over.
- **Time Attack** — clear the ladder against the clock.
- **Training** — dummy with adjustable behaviour + input display.
- *(No local 2P — no second controller — so effort goes into a strong Arcade.)*

---

## 9. Balance & AI

- The CPU, player 2, and headless smoke autopilot are **one behaviour system**:
  a state machine (approach → poke → punish → block → retreat) with difficulty
  tiers (reaction delay, combo length, meter usage, block rate).
- `tools/smoke.sh` drives **AI-vs-AI** matches headless, logging round outcomes
  to a datastore heartbeat and stamping screenshots — so we smoke-test *and*
  produce win-rate matrices across all matchups for balance tuning, with no
  human in the loop.
- All damage / frame data / speeds live in `config.lua`'s `C` table for legible
  iteration.

---

## 10. Technical architecture

House conventions: **global namespace tables** per concern, `import` into one
shared env (file locals don't cross files), **smokeflag-first config**, fixed
30 fps (`C.DT = 1/30`), 400×240 1-bit.

```
source/
  config.lua    import "smokeflag" (line 1); C tunables (frame data, damage,
                speeds) + G mutable state
  util.lua      clamp/lerp/sign/dist/near + delayed-call scheduler
  harness.lua   smoke: pcall-wrapped update, heartbeat, screenshots, autopilot
  rig.lua       parametric skeleton: pose params, interpolation, draw
  fighters.lua  per-character rigs, movelists, frame data, stats
  fight.lua     physics, hitbox/hurtbox, damage, hitstun, combos, round flow
  input.lua     input buffer + motion parser + autopilot hook
  ai.lua        behaviour state machine + difficulty (CPU / P2 / autopilot)
  meter.lua     Frenzy (crank) + Molt
  stage.lua     backdrops, parallax, hazards
  sfx.lua       music sequencer + combat SFX
  hud.lua       health / Frenzy / timer / round pips
  draw.lua      frame compositor (stage + fighters + hud + fx)
  main.lua      state machine (menu / arcade / fight / result), tick, harness
```

Build: `make` → `out/Chitin.pdx`; `make smoke` → instrumented. bundleID
`com.sdwfrost.chitin`.

---

## 11. Build phases

1. **Core fight loop** — one rig, two mirror fighters, walk/jump/crouch,
   Light/Heavy normals with hitboxes, block, damage, hitstun, knockdown, round
   flow (best of 3, timer, KO), HUD, one stage, CPU + autopilot, smoke green.
   *Prove the feel.* ← Phase 1
2. **Motion inputs + specials + Frenzy super.**
3. **Full roster** — 6 fighters as rigs + movelists; balance pass via AI-vs-AI.
4. **Stages, audio, Arcade ladder + endings, menus.**
5. **Polish** — Molt comeback, boss, unlocks, on-device feel tuning.

---

## 12. Risks & open questions

- **Feel is everything.** Hit-stop, buffering, cancel windows — only truly
  judged on-device by hand. The autopilot proves *no crash* and gives win-rate
  data, not "does it feel good." Budget real device time each phase.
- **Parametric rigs** trade drawing-frames for rigging-math up front; Phase 1
  is the make-or-break proof.
- **Motion inputs on a small d-pad** need generous buffers and windows.
- **1-bit readability** with two overlapping insects — solved with
  outline-forward art (two-pass outline renderer).
