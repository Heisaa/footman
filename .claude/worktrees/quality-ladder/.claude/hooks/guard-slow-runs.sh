#!/usr/bin/env bash
# PreToolUse guard: refuse the long-running commands in this project unless the
# user asked for one in their most recent message.
#
# The problem it solves is not cost, it is attention. A test suite or a batch is
# minutes of simulation that answers a question nobody asked, against an engine
# that is missing parts (CLAUDE.md, "What this is judged by"). The instruments
# that see the thing being built are `./run.sh check`, a short
# `./run.sh diagnose`, and the owner's eyes.
#
# Timings the block list is drawn from, measured on this machine:
#   test_rng 40ms  test_ball 18ms  test_locomotion 25ms  test_value_field 107ms
#   test_touch 9.5s  test_golden 22s  test_match 16s  test_determinism 28s
# So the four fast cases stay available through `--only`; everything else in the
# suite is over the ten-second line on its own.
#
# stdin is the PreToolUse JSON. Allowing is silence (exit 0); refusing is a JSON
# permissionDecision on stdout.

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# --- Is this one of the slow ones? -------------------------------------------

slow=""

# The suite. `--only` with one of the four sub-second cases is allowed through;
# any other case, or the whole suite, is not.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+test\b'; then
	if printf '%s' "$cmd" | grep -qE '\-\-only[[:space:]]+(rng|ball|locomotion|value_field)\b'; then
		:
	else
		slow="the test suite"
	fi
fi

# The owner's batches, and the single-match tools that simulate ninety minutes.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+(smoke|gate|accept|pbatch|tactics|match|perf|determinism|record-golden)\b'; then
	slow="a full-length run"
fi

# `diagnose` is the sanctioned instrument, but only in its short form. Without
# `--minutes` it simulates a whole match.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(\./)?run\.sh[[:space:]]+diagnose\b'; then
	minutes=$(printf '%s' "$cmd" | grep -oE '\-\-minutes[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
	if [ -z "$minutes" ] || [ "$minutes" -gt 12 ]; then
		slow="a full-length diagnose"
	fi
fi

# The same things spelled without run.sh.
if printf '%s' "$cmd" | grep -qE '(run_tests|record_golden)\.gd'; then
	slow="the test suite"
fi

[ -z "$slow" ] && exit 0

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

reason="Blocked ${slow}: it takes far longer than ten seconds and the user has not asked for it in their last message. Use ./run.sh check for correctness, ./run.sh diagnose --seed N --minutes 10 for behaviour, and a rendered frame for anything about how it looks. ./run.sh test --only rng|ball|locomotion|value_field is still available. If this needs running, say so and let the user ask for it."

jq -n --arg r "$reason" '{
	hookSpecificOutput: {
		hookEventName: "PreToolUse",
		permissionDecision: "deny",
		permissionDecisionReason: $r
	}
}'
exit 0
