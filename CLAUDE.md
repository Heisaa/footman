# footman2

A football management roguelike. Godot 4.7, GDScript. `PLAN.md` is the spec and
the source of truth for design decisions; this file is the instructions. Detail
lives elsewhere, and is worth reading before touching the layer it covers:

- `docs/GLOSSARY.md` — what the words mean: carry, hold, burst, room, pressure vs challenge
- `docs/DIAGNOSTICS.md` — every `diagnose` block, what it can and cannot see, batch mechanics
- `docs/INVARIANTS.md`, `docs/PITFALLS.md` — the architectural rules, and real bugs the code could not show
- `docs/COMPRESSED_CLOCK.md` — `--clock-rate`, what scales with it, why the pitch is full size
- `docs/STATUS.md` — phase status, and the measured account of every mechanic that moved numbers
- `DECISIONS.md` — open `[DECIDE]` questions, amendments to the plan, goals-per-match knobs

## What this is judged by

**The game is judged by eye, and the owner does that judging.** A statistic tells
you *what* happened, never *why it looked wrong*, and that is the entire job at
this stage. **A new behaviour is expected to break the numbers, and that is not a
regression** — adding one football behaviour to an engine missing the others
unbalances it, necessarily, every time. So:

- **Do not gate a mechanic on the bands.** If it reads as football, it goes in.
- **Do not soften a mechanic to protect a statistic.** That fits the engine to a
  provisional number and removes the behaviour that was the point; tune late,
  once, at the tuning freeze (`PLAN.md` §11.1.1).
- **Do not report a band move as a regression.** Report it as: this mechanic went
  in, these numbers moved, here is the missing mechanic that would answer it.
- **Sanity ranges still catch genuine breakage** — no shots, a ball that never moves,
  a team that never crosses halfway. When one breaks right after a behaviour lands,
  ask whether the behaviour explains it and let the owner look. Of the two printed
  tables only the sanity ranges mean anything yet; the §11 bands are advisory.

## Running things

`./run.sh` wraps every entry point (and redirects `XDG_DATA_HOME`, unwritable here).

```
./run.sh check                   # every script parses               (seconds)
./run.sh test [--only ball]      # the suite, or one case          (owner runs)
./run.sh smoke                   # 6 x 12 min, reduced fidelity    (owner runs)
./run.sh gate                    # 6 x 90 min, full fidelity       (owner runs)
./run.sh accept                  # the 200-match acceptance run    (owner runs)
./run.sh match --seed 7          # simulate one match, print a summary
./run.sh diagnose --seed 7       # break that match down by touch, pass, third
./run.sh tactics --matches 12    # the Phase 5 distinguishability test
./run.sh perf --profile          # per-stage timing | determinism --seed 7 runs it twice
./run.sh view                    # 2D debug view (display) | demo is the 6-a-side one
./run.sh shot | poses            # one frame to a PNG via xvfb | the labelled pose sheet
./run.sh record-golden           # re-baseline the golden replay hashes
```

**Never run `./run.sh test`. It is the owner's, like `smoke`, `gate` and `accept`.**
If you find yourself reasoning that this change really ought to be tested, that is
the thought this rule exists to overrule: say what you changed and let the owner run
it. `--only <case>` is there for one specific check.

**Do not run statistical batches. Five matches is the ceiling** — above that is the
owner's; ask first, and only when the answer needs it. A batch measures a machine
that is missing parts. Use, in order: `check` for correctness, `diagnose --seed N
--minutes 10` (~15 s) for behaviour, at most a five-match `pbatch` for a structural
aggregate. Say which you ran, what it can and cannot see, and quote the sample size
with any band result.

**For a look-and-feel change, compiling is the whole check.** Anything the owner
judges by watching — camera, a pose, a colour, a constant in `presentation/` — is
done when `check` passes; do not render frames to grade your own work or
instrument the code to count what it did. Two narrow exceptions: render a frame
when the change could plausibly produce *nothing* (black screen, camera in the
stand, geometry that fails to build), and measure when the owner's own words are a
quantity ("it cuts too often") — then once, and stop.

**A changed mechanic breaks the golden replay digests. Re-record them with
`./run.sh record-golden` and say so — do not ask.** Ask only when they move after
a change that should not have touched behaviour at all; that is a real finding.

## Layout

```
sim/          the simulation — no scene tree, no nodes, no frame delta. core/ is rng,
              constants, environment; *.gd is ball, player, touch, decision, ...
presentation/ reads snapshots and draws them. Depends on sim; nothing depends on it.
shared/       palette (used by both, contains no logic)
tools/        headless entry point, batch runner, validation, diagnostics; tests/
              is the suite, run through the same entry point
```

## The rules that hold the design up

Breaking these is easy and the damage is not local; `docs/INVARIANTS.md` has why.

- **The simulation never touches the engine** — no nodes, no `_process`, no frame
  delta, no `Time`, no input. Headless is the enforcement mechanism.
- **All randomness comes from `ctx.rng`**, whose methods are deliberately not
  named `randf`/`randfn`/`randi_range`; do not rename them back.
- **One forecast and one value field per tick, shared** (`ctx.trajectory_now()`).
- **Tactics are priors on the decision function, never behaviour switches** (§5.1);
  named patterns are a trigger plus a nudge, and every firing is counted.
- **The anti-swarm guard lives in `SimMovement._assign_chasers`**, nowhere else.
- **The reduced-fidelity tier strides decisions, never physics.**
- **Tune late** (§11.1.1); read `DECISIONS.md` before adding a constant that affects
  scoring. After adding a `class_name`, run `./run.sh import` once.
