# footman2

A football management roguelike. Godot 4.7, GDScript, no engine physics.

`PLAN.md` is the spec. `docs/` holds one subject per file, named for it; read the
one covering a layer before changing it, and **read `docs/INVARIANTS.md` before
touching `sim/`** — every rule in it cost a real bug.

**Write docs, comments and code plainly**: fewest words, no decoration.

## What this is judged by

**Make it look like football. Ignore the numbers until it does. Then tune.**

The owner judges by eye; a statistic says what happened, never why it looked
wrong. A new behaviour is expected to break the numbers, and that is not a
regression — adding one behaviour to an engine missing the others unbalances it.

- **Do not gate a mechanic on a band.** If it reads as football, it goes in.
- **Do not soften a mechanic to protect a statistic.** Tune once, late, at the
  tuning freeze (`PLAN.md` §11.1.1).
- **Report a band move as a result**, not a regression: this went in, these
  numbers moved, this missing mechanic would answer it.
- **Sanity ranges still catch real breakage** — no shots, a ball that never
  moves, a team that never crosses halfway. Say whether the behaviour explains
  it, and let the owner look.

**Right now the work is the attack, and it is meant to overshoot.** The defence
is missing most of its behaviours, so goals should run far above the finished
game's target and the goals sanity ceiling is suspended until the defensive pass
restores it. Do not build a defensive mechanic to bring the count down; that is
the next pass. `PLAN.md` §11.4.

## Test and debug with causality in mind

**Find out where a thing broke before arguing about why.** A constant reaches a
goal down six links, and a link broken early makes everything below it noise.
`docs/DIAGNOSTICS.md`, "The chain", is the list; the first three cost nothing.

- **Blaming a term before checking it reaches the pick is the commonest wasted
  afternoon.** `--ablate` says whether it is applied, varies, and changes which
  option wins. A term that fails there cannot be the cause of anything.
- **A value knob cannot create an option that was never generated.** When a
  mechanic does not happen, ask whether it was a candidate before asking what it
  was worth. This project has been caught by that three times.
- **A diff of two runs is not a measurement of a change.** One different decision
  and it is a different match. Measure counterfactually inside one match
  (`--ablate`), or compare conversions across seeds (`chains --against`).
- **Correlation is the default and has to be designed out.** Splitting outcomes
  by what was played is as much a fact about the situations that act gets chosen
  in. `The coin the softmax tossed` is the one exception: a near-tie is settled by
  `ctx.rng` and nothing else.

And in a test:
- **Assert the mechanism, not the outcome.** A check on a number several links
  downstream fails for whatever moved last, and names nothing.
- **Where an outcome check is the point** — the whole-match invariants — make the
  floor structural, at a level only the failure itself crosses. Not a tuned figure.
- **Do not assert a direction nobody has decided.** If which way a number should
  move is an open football question, the check fails for being right. Record the
  question instead.

## Verification is proportional to the change

**The owner's time is the scarce resource.** Use the fastest check that answers
the question, and no more.
- **A small change is done when it compiles.** `./run.sh check` takes seconds and
  most edits need nothing else.
- **A look-and-feel change is done when it compiles too.** Anything judged by
  watching is not graded by rendering frames or counting what the code did.
  Exceptions: render one frame if the change could produce *nothing* (a black
  screen, a camera in the stand), and measure once if the owner's words were a
  quantity.
- **Measure only when the question is a quantity**, and take the quickest
  measurement that answers it. `diagnose --seed N --minutes 10` is about 15 s.
- **Measure at `clock_rate` 10 and nowhere else.** The nine-minute match is the
  default in every entry point, the match that ships, and the match the numbers
  are tuned to. The scoring fit that comes with it — shot appetite, shot aim,
  the keeper — is the format, not inflation to correct for. **Do not run
  `--clock-rate 1`**: a figure from it describes a match nobody plays. Use
  `--urgency U` if the fit itself is the question. `docs/STATUS.md`, "what every
  figure here is worth".
- **Ask before anything slower**, saying what it would tell you and how long it
  takes. Do not start it and report back afterwards.
- **Do not add verification to feel thorough.** A check nobody asked for costs
  minutes and answers a question nobody asked.

**Which runs are mine, which are yours**, enforced by
`.claude/hooks/guard-slow-runs.sh`.
- **Mine, no asking:** `check`; the benches, which run no match; a `diagnose` of
  ten match-minutes or less; the sub-second test cases; and `record-golden`.
- **Yours to approve, mine to offer:** anything measured in minutes — the slow
  test cases, the full suite, `match`, `perf`, `determinism`, a full-length
  `diagnose`, `smoke`, `pbatch`, `tactics`. Say what one would tell you before it
  starts, never chain a second, and remember a batch still measures a machine
  missing parts: five matches is the ceiling, and a `diagnose` is usually the
  honest answer instead.
- **Yours:** `gate` and `accept`. Tens of minutes, and never the answer to a
  question that came up mid-change.

**A changed mechanic breaks the golden replay digests. Re-record them with
`./run.sh record-golden` and say so — do not ask.** Ask only when they move after
a change that should not have touched behaviour: that is a real finding.

`./run.sh` wraps every entry point and redirects `XDG_DATA_HOME`, which is
unwritable here; with no argument it lists the commands. `presentation/` depends
on `sim/`, nothing depends on `presentation/`, and headless enforces it.
