# footman2

A football management roguelike. Godot 4.7, GDScript.

`PLAN.md` is the spec. This file is the instructions. Each doc below owns one
subject; read the one covering a layer before you change that layer.

- `docs/GLOSSARY.md` — what the words mean: carry, hold, burst, room, pressure vs challenge
- `docs/THE_FOOTBALL.md` — every behaviour a viewer can see, and whether the engine has it
- `docs/DIAGNOSTICS.md` — what each `diagnose` block, the live overlay and a batch can and cannot see, and **the chain**: the six links from a constant to a goal, and which instrument says which one broke
- `docs/INVARIANTS.md` — the architectural rules, the compressed clock, and why each matters
- `docs/PITFALLS.md` — real bugs that were invisible from the code
- `docs/STATUS.md` — phase status, and what every mechanic measured
- `docs/BACKLOG.md` — proposed work, not built yet
- `DECISIONS.md` — open `[DECIDE]` questions, amendments to the plan, owner design calls

## Writing style

Write plainly. This applies to answers, docs, comments and code alike.

- Say the thing in the fewest words that still say it.
- Short sentences, one idea each. Active voice. Plain words.
- No throat-clearing, no rhetorical build-up, no restating the point you just made.
- Cut any word that carries no information.
- The names and the numbers are the content. Keep those; drop the decoration.

## What this is judged by

**Make it look like football. Ignore the numbers until it does. Then tune.**

That is the order of work, and everything below follows from it. The engine is
not a set of statistics being refined toward a target; it is a set of football
behaviours being added until a match reads right by eye. The bands get fitted
afterwards, once, to whatever engine that turns out to be (`PLAN.md` §11.1.1).

The owner judges the game by eye. A statistic tells you what happened, never why
it looked wrong.

A new behaviour is expected to break the numbers, and that is not a regression.
Adding one football behaviour to an engine missing the others unbalances it,
every time.

- **Do not gate a mechanic on the bands.** If it reads as football, it goes in.
- **Do not soften a mechanic to protect a statistic.** That fits the engine to a
  provisional number and removes the behaviour that was the point. Tune late,
  once, at the tuning freeze (`PLAN.md` §11.1.1).
- **Do not report a band move as a regression.** Report it as: this mechanic went
  in, these numbers moved, this missing mechanic would answer it.
- **Sanity ranges still catch real breakage** — no shots, a ball that never moves,
  a team that never crosses halfway. When one breaks right after a behaviour
  lands, say whether the behaviour explains it and let the owner look.

Of the two printed tables only the sanity ranges mean anything yet. The §11
tuning bands are advisory.

## Running things

`./run.sh` wraps every entry point, and redirects `XDG_DATA_HOME`, which is
unwritable here.

```
./run.sh check                   # every script parses               (seconds)
./run.sh test [--only ball]      # the suite, or one case          (owner runs)
./run.sh smoke                   # 6 full matches, reduced fidelity (owner runs)
./run.sh gate                    # 6 full matches, full fidelity    (owner runs)
./run.sh accept                  # the 200-match acceptance run    (owner runs)
./run.sh match --seed 7          # simulate one match, print a summary
./run.sh diagnose --seed 7       # break that match down by touch, pass, third
./run.sh replay --seed 7 --tick T  # every decision around one tick, in words
./run.sh tactics --matches 12    # the Phase 5 distinguishability test
./run.sh perf --profile          # per-stage timing | determinism --seed 7 runs it twice
./run.sh view                    # 2D debug view (display) | demo is the 6-a-side one
./run.sh view3d --debug          # the match with the decision overlay on (display)
./run.sh view3d --from-bookmark seed7-t34210   # watch a marked moment again, slowly
./run.sh strike                  # where a struck ball lands vs where the model said
./run.sh shot | poses            # one frame to a PNG via xvfb | the labelled pose sheet
./run.sh record-golden           # re-baseline the golden replay hashes
```

### Verification is proportional to the change

**The owner's time is the scarce resource.** Match the check to the size of the
change, and use the fastest one that can answer the question.

- **A small change is done when it compiles.** `./run.sh check` takes seconds,
  and most edits need nothing beyond it.
- **Measure only when the question is a quantity**, and then take the quickest
  measurement that answers it. `diagnose --seed N --minutes 10` is about 15 s.
- **Ask before running anything slower than that.** Say what you would run, what
  it would tell you, and roughly how long it takes. Do not start it and report
  back afterwards.
- **Do not add verification to feel thorough.** A check nobody asked for costs
  minutes and answers a question nobody asked.

The rules below are that principle applied to specific cases.

**For a look-and-feel change, compiling is the whole check.** Anything the owner
judges by watching — camera, a pose, a colour, a constant in `presentation/` — is
done when `check` passes. Do not render frames to grade your own work, and do not
instrument the code to count what it did. Two exceptions: render a frame when the
change could plausibly produce *nothing* (black screen, camera in the stand,
geometry that fails to build), and measure when the owner's own words are a
quantity ("it cuts too often") — then once, and stop.

**Which runs are mine, which are yours.** Three tiers, and
`.claude/hooks/guard-slow-runs.sh` enforces them.

- **Mine, no asking.** `check`; `strike` and `behind`, which run no match at all;
  `diagnose --seed N --minutes 10` or shorter;
  `test --only rng|clock|ball|locomotion|value_field|distances`; and `record-golden`, which is
  required after a mechanic change rather than optional.
- **Yours to approve, mine to offer.** Everything measured in minutes: the slow
  single test cases (`--only touch|match|golden|determinism|patterns`), `test` in
  full (about 2 min, and `--bands` adds the statistical half on top), `match`,
  `perf`, `determinism`, a full-length `diagnose`, `smoke`, `pbatch` and
  `tactics`. The guard turns these into a prompt. Say what one would tell you
  before it starts, and never chain a second. A batch still measures a machine
  that is missing parts, so five matches is the ceiling and `diagnose` is usually
  the honest answer instead — but that is now your judgement to make in a
  keystroke rather than the guard's to make for you.
- **Yours.** `gate` and `accept`. Tens of minutes, and never the answer to a
  question that came up mid-change.

The middle tier is the point. A rule that only says *no* has nothing left to say
the moment it is lifted, which is how a scoped permission — "you can unblock the
golden re-record" — became a whole suite. A prompt costs one keystroke, keeps the
decision yours, and leaves a gradient to reason about when it is suspended.

**A changed mechanic breaks the golden replay digests. Re-record them with
`./run.sh record-golden` and say so — do not ask.** Ask only when they move after
a change that should not have touched behaviour. That is a real finding.

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

One line each. `docs/INVARIANTS.md` has the reasoning and the bugs behind them.

- **The simulation never touches the engine** — no nodes, no `_process`, no frame
  delta, no `Time`, no input. Headless is the enforcement mechanism.
- **All randomness comes from `ctx.rng`**, whose methods are deliberately not
  named `randf`/`randfn`/`randi_range`. Do not rename them back.
- **One forecast and one value field per tick, shared** (`ctx.trajectory_now()`).
- **Tactics are priors on the decision function, never behaviour switches**
  (§5.1). Named patterns are a trigger plus a nudge, and every firing is counted.
- **The anti-swarm guard lives in `SimMovement._assign_chasers`**, nowhere else.
- **Sim state kept in a static is reset from `SimMatch.setup`** — never by
  watching for tick 0 from inside the layer.
- **The reduced-fidelity tier strides decisions, never physics.**
- **Tune late** (§11.1.1). A constant that affects scoring has to be reachable
  from one place — `docs/INVARIANTS.md` says why.
- **After adding a `class_name`, run `./run.sh import` once.**
