#!/usr/bin/env bash
# PreToolUse guard: put the long-running commands in this project behind a prompt
# rather than behind a wall.
#
# The problem it solves is not cost, it is attention. A test suite or a batch is
# minutes of simulation that answers a question nobody asked, against an engine
# that is missing parts (CLAUDE.md, "What this is judged by"). The instruments
# that see the thing being built are `./run.sh check`, a short
# `./run.sh diagnose`, and the owner's eyes.
#
# Three tiers, matching CLAUDE.md, "Which runs are mine, which are yours":
#
#   allow  check, a short diagnose, the four sub-second test cases, and
#          record-golden -- which CLAUDE.md *requires* after a mechanic change,
#          so blocking it only produced a negotiation about a mandated command.
#   ask    everything measured in minutes: the slow single test cases, the whole
#          suite, the single-match tools, `smoke`, `pbatch` and `tactics`. These
#          are sometimes the right answer, so they cost the owner one keystroke
#          instead of a paragraph.
#   deny   `gate` and `accept` -- tens of minutes, and never the answer to a
#          question that came up mid-change.
#
# A deny is not a wall either: asking for one in your last message allows it, and
# that is how the owner overrides any of this.
#
# Per-case timings measured on this machine, 2026-08-12, before the suite was
# shortened. The figures they replaced were stale by a factor of two to three,
# and these will go the same way -- re-measure before trusting them:
#   test_rng 85ms  test_ball 96ms  test_locomotion 41ms  test_value_field 276ms
#   test_touch 26s  test_match 42s  test_golden 62s  test_determinism 64s
# `test_tactics` and `test_patterns` were not reached in that run. Tactics alone
# simulated 112 match-minutes, more than every other case combined, so the whole
# suite was around nine minutes rather than the 195s those eight sum to.
#
# It has since been cut to roughly two minutes, with the statistical half behind
# `--bands` (tests/run_tests.gd). That figure is an estimate from match-minutes
# simulated, not a measurement.
#
# So the five fast cases stay in `allow` through `--only`; the rest sit in
# `ask`. (`test_clock` and `test_distances` joined it: no match simulated,
# sub-second both.)
#
# stdin is the PreToolUse JSON. Allowing is silence (exit 0); anything else is a
# JSON permissionDecision on stdout.

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# --- Which tier is this? -----------------------------------------------------

slow=""    # what to call it in the message
tier=""    # ask | deny

# The suite. `--only` with one of the five sub-second cases is allowed through;
# `--only` with a slow case asks; the whole suite is the owner's.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+test\b'; then
	if printf '%s' "$cmd" | grep -qE '\-\-only[[:space:]]+(rng|clock|ball|locomotion|value_field|distances)\b'; then
		:
	elif printf '%s' "$cmd" | grep -qE '\-\-only[[:space:]]+[a-z_]+'; then
		slow="a slow test case (20-70 s)"
		tier="ask"
	else
		slow="the whole test suite (about 195 s)"
		tier="ask"
	fi
fi

# The short batches. Minutes, and they measure an engine that is missing parts,
# so the answer is usually `diagnose` instead -- but that is a judgement the
# owner can make in one keystroke rather than one the guard should make for them.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+(smoke|pbatch|tactics)\b'; then
	slow="a batch (minutes)"
	tier="ask"
fi

# The long ones. Tens of minutes, and none of them answers a question that comes
# up mid-change.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+(gate|accept)\b'; then
	slow="a full acceptance-scale run"
	tier="deny"
fi

# The single-match tools. One ninety-minute match, so tens of seconds to a couple
# of minutes: worth offering, never worth starting unannounced.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+(match|perf|determinism)\b'; then
	slow="a full-length single-match run"
	tier="ask"
fi

# `diagnose` is the sanctioned instrument, but only in its short form. Without
# `--minutes` it simulates a whole match.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+diagnose\b'; then
	minutes=$(printf '%s' "$cmd" | grep -oE '\-\-minutes[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
	if [ -z "$minutes" ] || [ "$minutes" -gt 12 ]; then
		slow="a full-length diagnose"
		tier="ask"
	fi
fi

# The same things spelled without run.sh. `record_golden.gd` is deliberately not
# here: re-recording after a mechanic change is required, not optional.
if printf '%s' "$cmd" | grep -qE 'run_tests\.gd'; then
	slow="the whole test suite"
	tier="ask"
fi

[ -z "$tier" ] && exit 0

# --- Did the user ask for it? ------------------------------------------------

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
last_user=""
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
	# Only messages the user actually typed. A transcript's user-role entries also
	# carry tool results, slash-command output and injected notices; without the
	# filter the last one of those masks the real instruction, and the guard is
	# then reading `/context` output to decide what the user wanted.
	last_user=$(jq -rs '
		[ .[]
		  | select(.type == "user" and .isMeta != true and .isSidechain != true
		           and (has("toolUseResult") | not))
		  | .message.content
		  | if type == "string" then .
		    else ([ .[] | select(.type == "text") | .text ] | join(" "))
		    end
		  | select(length > 0)
		] | last // ""
	' "$transcript" 2>/dev/null | tr '\n' ' ')
fi

asked=0
if printf '%s' "$last_user" | grep -qiE '(run|rerun|re-run|kick off|go ahead and run).{0,40}(test|suite|smoke|gate|accept|batch|golden|determinism|perf|diagnose)|record-golden|run\.sh (test|smoke|gate|accept|pbatch|match|perf|determinism)'; then
	asked=1
fi
# A question or a refusal that happens to contain the word is not a request.
if printf '%s' "$last_user" | grep -qiE "(don'?t|do not|stop|never|avoid|no more|why are you|instead of)"; then
	asked=0
fi

if [ "$asked" = "1" ]; then
	exit 0
fi

# --- Answer -------------------------------------------------------------------

if [ "$tier" = "ask" ]; then
	reason="This is ${slow}. It is the owner's call rather than yours to start: say what it would tell you and what you would do with the answer, and let them decide. Do not chain a second one after it."
else
	reason="Blocked ${slow}: it is tens of minutes and it is the owner's. Use ./run.sh check for correctness, ./run.sh diagnose --seed N --minutes 10 for behaviour, and a rendered frame for anything about how it looks. Everything measured in minutes -- the suite, smoke, pbatch, tactics, a single match -- will prompt rather than refuse, so reach for one of those if it genuinely needs a longer look. If this really needs running, say so and let the owner ask for it."
fi

jq -n --arg t "$tier" --arg r "$reason" '{
	hookSpecificOutput: {
		hookEventName: "PreToolUse",
		permissionDecision: $t,
		permissionDecisionReason: $r
	}
}'
exit 0
