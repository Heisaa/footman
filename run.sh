#!/usr/bin/env bash
# Convenience wrapper for the headless entry point and the test suite.
#
# Godot wants a writable data directory and the container's default one is not,
# so XDG_DATA_HOME is redirected here rather than in every command.
set -euo pipefail

export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.godot-data}"
mkdir -p "$XDG_DATA_HOME"

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

WORKERS_DEFAULT="$( (nproc 2>/dev/null || echo 4) )"

usage() {
	cat <<'EOF'
usage: ./run.sh <command> [args]

  test [--only NAME]        run the test suite
  record-golden             re-baseline the golden replay hashes

  smoke                     6 full matches, reduced fidelity  (~40 s)
  gate                      6 full matches, full fidelity     (~90 s)
  accept                    200 x 90 min, strict          (~50 min)
  pbatch --matches N        an arbitrary parallel batch
      [--workers K] [--minutes M] [--home Q] [--away Q] [--reduced]
      [--strict] [--keep] [--small] [--clock-rate R] [--pitch-scale F]

  match [--seed N]          simulate one match and print a summary
      [--urgency U]         --urgency forces the compressed match's scoring fit
                            on at any clock rate, for measurement: 0 is the
                            real-time engine, 0.68 the standard nine-minute
                            match, 1 the 30x anchor the fit was made at. Works on
                            match, diagnose, batch and pbatch. See
                            SimMatchConfig, "the compressed match's scoring fit"
  diagnose [--seed N]       simulate one match and break it down
      [--ablate]            add the table of whether each term in the decision
                            score ever changes what gets played. Costs ~4%
  chains --out FILE         run several matches and save the chains, or
      [--against FILE]      set them against a run saved before a change. Read
      [--matches N]         the conversion columns: more possessions moves every
                            count and says nothing about where a change landed
  box [--seed N]            the one-on-one: what a striker in the box is offered,
                            in set geometries (no match)
  behind [--seed N]         the ball in behind, struck in geometries that are
                            set rather than sampled: a passer, a runner, a flat
                            back four. Prints the ball and whether the man it is
                            for can reach it. No match runs; it is instant
  control [--trials N]      the contest at the end of a pass: what control_at_pass
                            said, against what the engine did with the same ball.
                            One geometry, every ball played, so no selection is
                            in it. Simulates: ~10 s at the default 40 trials
  scenario [--only NAME]    the 25 named situations, each set rather than waited
      [--trials N]          for, run forward a few seconds and scored by how it
      [--quality Q]         ended. A table of shares, and the same situations are
      [--acts]              watchable with `view3d --scenario NAME`. ~2 s each
      [--trace N]           at the default 40 trials.
                            --acts adds what the attacking side actually played,
                            per trial, by touch kind: the only way to tell an act
                            that is never generated from one that is chosen and
                            fails. --trace N prints trial N's event log in order
  world [--seed N]          print a generated club: the squad with names, ages,
      [--reputation Q]      wages and traits, who the tails are, and a scout
      [--reports N]         report on the first few. --league prints the
      [--league]            division instead -- nine clubs, sixteen games each
      [--clubs N]           over eighteen weeks -- with its first week of
      [--rounds N]          fixtures. --clubs and --rounds change that shape.
                            No match runs; it is instant
  strike [--seed N]         where a struck ball actually lands, against where
                            execution_accuracy told the decision layer it would.
                            The two share one error model or they do not. Instant
  replay --tick T           every decision around one tick of one seed, in
      [--scenario NAME]     --scenario opens a named situation instead of a
                            kick-off, so the candidate list behind a scenario row
                            can be read at --tick 1
      [--seed N] [--around S]
                            words. The other half of the overlay's bookmark:
                            it prints the command that reproduces it
  batch [--matches N]       serial batch (use pbatch instead for anything large)
  tactics [--matches N]     compare two contrasting plans, sharded across cores
  perf [--profile]          time a full-fidelity match, optionally per stage
  determinism [--seed N]    run one seed twice and compare the event logs
  view                      open the 2D debug view (needs a display)
  view3d [--seed N]         open the 3D match view (needs a display).
      [--world N]           two generated clubs of the league at world seed N
      [--home-club K]       instead of SimSquadGen squads: the clubs parade
      [--away-club J]       --world shows. match and diagnose take the same.
      [--render WxH]        draw the frame at that many pixels, stretched to
      [--windowed WxH]      the screen; or a window of that size, where the
                            compositor allows one (not under sway)
      [--speed X] [--step-fps N]
      [--small] [--clock-rate R] [--pitch-scale F]
      [--home Q] [--away Q]
      [--debug] [--layers 1,3] [--bookmark S]
      [--from-bookmark seed7-t34210]
      [--scenario NAME]
                            --debug turns on the overlay: what the man on the
                            ball chose and what he turned down, a ticker, and
                            seven annotation layers on keys 1-7. It drops the
                            clock rate to real time unless told otherwise,
                            because nothing on it can be read compressed.
                            --layers turns layers on from the command line, for
                            a screenshot; --bookmark marks a moment without
                            anyone pressing M. Keys: space pause, [ ] speed,
                            . step a tick, , step back, < > jump half a second,
                            enter play on from the moment on screen, M mark,
                            click to pin, N the next match, R this one again.
                            Stepped back, the panels and the layers describe the
                            moment on screen rather than the live one; enter
                            re-simulates to it and carries on from there.
                            At full time the board asks for N: the view keeps
                            running and the overlay carries over.
                            N also walks the squad quality: match one is 0.60 v
                            0.60, two is 1.00 v 1.00, three is 1.00 v 0.60, then
                            it wraps. R keeps this match's pair. --home Q /
                            --away Q pin one pair for the session instead.
                            F1 opens the same overlay in a match that was
                            started without it — including the main scene —
                            but cannot un-compress that match's clock.
                            --from-bookmark replays a marked moment: same seed,
                            fast-forwarded to five seconds before the tick,
                            played at quarter speed, paused on the tick.
                            Defaults to the compressed match: eleven a side, a
                            full ninety in about nine minutes at 1x speed.
                            --clock-rate 1 --pitch-scale 1 for real time.
                            --step-fps quantises the animation, for the old
                            stop-motion look; the default is smooth
                            --clock-rate R runs the match clock R times faster
                            than real time, so a full 90 takes 90/R minutes
                            --pitch-scale F shrinks the pitch, 11 a side kept
                            --scenario NAME watches one set situation instead of
                            a match: it starts in the moment, plays out, and
                            repeats on the next seed so the same thing can be
                            watched many times. The names are the rows of
                            `./run.sh scenario`, which counts the identical
                            situations. --scenario all is the tour: each
                            scenario repeats until N steps to the next one
                            in table order; R replays
  demo                      the six-a-side comparison, compressed the same way
  shot                      render one match frame to a PNG, from a virtual
                            display (SHOT_AT, SHOT_SPEED, SHOT_PATH, SHOT_RES)
  poses                     render every animation state side by side, labelled
                            (POSE_U picks where in each arc to freeze)
  ramp [--flat]             the FIFA ramp test on the match ball: four surfaces
      [--speed S]           side by side, a 1 m ramp at 45 degrees, and the
      [--shot PATH --at T]  4-10 m band the standard wants. Needs a display;
                            --shot renders one frame at T seconds and quits
  parade [--seed N]         a rank of that seed's players, close up, turning,
      [--page N] [--still]  each captioned with number, name, height and
      [--turn DEG]          appearance seed. The squad is the match squad, so a
      [--face 0-4]          note taken here holds in view3d at the same seed.
      [--elevation DEG]     camera height above level (7); 40 is the match angle.
      [--zoom N]            camera distance divisor (1); 2 is the heads.
      [--chin 0-1]          chin on the first man, +0.25 per man along the rank.
      [--brow 0-1]          brow ridge, the same way.
      [--world N]           a generated club's squad instead, captioned with the
      [--club K] [--rep R]  record: age, country, complexion, archetype. --club
                            K is the Kth club of the league at that seed.
      [--render WxH]        draw the frame at that many pixels, stretched to
      [--windowed WxH]      the screen; or a window of that size, where the
                            compositor allows one (not under sway)
      [--hair N] [--nose N] Keys: < > page, N / P seed, SPACE turn, 1-5
      [--tache N] [--beard N]
      [--man N] [--plain]   --hair/--nose/--tache/--beard walk a library from
                            N across the rank (-2 takes the face hair off);
                            --man puts squad member N in every column;
                            --plain takes the accessories off.
      [--anim NAME|all]     expression, [ ] step anim, A roll, 0 stand, Q quit.
      [--shot PATH]         --shot renders one frame from a
                            virtual display and quits, for a look without a
                            screen; --turn 180 --still shows the backs. --hair
                            puts cut N and the next three on the rank instead of
                            the men's own, so five pages walk the library.
  check                     parse-check every script, presentation included
  import                    refresh Godot's script class cache

Batches are sharded across processes because matches are independent and each
is reproducible from its seed. A gate nobody runs is not a gate, so the routine
check is sized for the wall clock first: see PLAN.md §11.1.
EOF
}

# Simulates `total` matches into the directory `out`, split across `workers`
# processes. Does not judge them: `aggregate` and `compare` both read a shard
# directory, so the same driver serves the gate and the tactics comparison.
#
# Shard w takes the seed block [base + w*chunk, base + (w+1)*chunk), so the set
# of seeds is identical however many workers are used and a batch stays
# reproducible when the worker count changes.
simulate_into() {
	local out="$1"; shift
	local total="$1"; shift
	local workers="$1"; shift
	local quiet_progress="$1"; shift

	local base=1
	local args=()
	while [ $# -gt 0 ]; do
		case "$1" in
			--seed) base="$2"; shift 2 ;;
			*) args+=("$1"); shift ;;
		esac
	done

	# More workers than matches just leaves processes idle while paying their
	# start-up cost, which at a five-match gate is most of the run.
	if (( workers > total )); then workers=$total; fi
	local chunk=$(( (total + workers - 1) / workers ))
	echo "Running $total matches over $workers workers ($chunk each), seeds $base..$((base + total - 1))"
	local started=$SECONDS

	local pids=()
	local w
	for (( w = 0; w < workers; w++ )); do
		local seed=$(( base + w * chunk ))
		local count=$chunk
		# The last shard may be short if the total does not divide evenly.
		if (( seed + count > base + total )); then
			count=$(( base + total - seed ))
		fi
		(( count > 0 )) || continue
		"$GODOT" --headless --script res://tools/headless_main.gd -- \
			batch --matches "$count" --seed "$seed" --quiet \
			--json "$out/shard-$(printf '%02d' "$w").json" \
			--progress "$out/progress-$w" "${args[@]}" \
			>"$out/shard-$w.log" 2>&1 &
		pids+=($!)
	done

	local reporter=""
	if [ "$quiet_progress" != 1 ]; then
		report_progress "$out" "$total" "$started" &
		reporter=$!
	fi

	local failed=0
	for pid in "${pids[@]}"; do
		wait "$pid" || failed=1
	done
	if [ -n "$reporter" ]; then
		kill "$reporter" 2>/dev/null || true
		wait "$reporter" 2>/dev/null || true
	fi
	if [ "$failed" = 1 ]; then
		echo "at least one shard failed; logs are in $out" >&2
		cat "$out"/shard-*.log >&2
		return 1
	fi

	echo "Simulated in $((SECONDS - started)) s"
}


# Simulates and then judges against the §11 bands.
parallel_batch() {
	local total="$1"; shift
	local workers="$1"; shift
	local keep="$1"; shift
	local out
	out="$(mktemp -d "${TMPDIR:-/tmp}/footman-batch-XXXXXX")"

	simulate_into "$out" "$total" "$workers" 0 "$@" || { rm -rf "$out"; return 1; }
	echo
	# The judging pass needs the same --minutes/--small/--strict flags the run
	# had, and ignores the rest.
	"$GODOT" --headless --script res://tools/headless_main.gd -- aggregate --dir "$out" "$@"
	if [ "$keep" = 1 ]; then
		echo
		echo "shards kept in $out"
	else
		rm -rf "$out"
	fi
}


# The Phase 5 distinguishability test: two contrasting plans, each an ordinary
# sharded batch over the same seeds, judged against each other. Running the two
# arms serially in one process was hours; this is minutes.
parallel_tactics() {
	local per_arm="$1"; shift
	local workers="$1"; shift
	local out
	out="$(mktemp -d "${TMPDIR:-/tmp}/footman-tactics-XXXXXX")"
	mkdir -p "$out/press" "$out/block"

	# Half the workers each, so the two arms run at once rather than one after
	# the other. Both arms use the same seeds, which pairs the noise.
	local each=$(( workers / 2 ))
	(( each > 0 )) || each=1
	echo "Press arm and block arm, $per_arm matches each, $each workers per arm"
	local started=$SECONDS
	simulate_into "$out/press" "$per_arm" "$each" 1 --plan press --away-plan balanced "$@" &
	local a=$!
	simulate_into "$out/block" "$per_arm" "$each" 1 --plan block --away-plan balanced "$@" &
	local b=$!
	local failed=0
	wait "$a" || failed=1
	wait "$b" || failed=1
	if [ "$failed" = 1 ]; then
		echo "a tactics arm failed; logs are in $out" >&2
		return 1
	fi
	echo "Simulated both arms in $((SECONDS - started)) s"
	echo
	"$GODOT" --headless --script res://tools/headless_main.gd -- \
		compare --dir-a "$out/press" --dir-b "$out/block"
	rm -rf "$out"
}

# Sums the shards' progress files and prints a combined line every few seconds.
#
# The running metrics matter as much as the count: a batch is ten minutes and
# the whole point of watching it is to notice that goals per match is sitting at
# seven, and stop, rather than finding out at the end.
report_progress() {
	local out="$1" total="$2" started="$3"
	local interval="${PROGRESS_INTERVAL:-15}"
	sleep 3
	while true; do
		local done=0 goals=0 shots=0 draws=0
		local f
		for f in "$out"/progress-*; do
			[ -f "$f" ] || continue
			# A shard may be mid-write; a short read just means this tick
			# undercounts slightly and the next one corrects it. Note `read`
			# reports failure on a line with no trailing newline even though it
			# has assigned the variables, so judge on the data, not the status.
			d=""; g=""; s=""; dr=""
			read -r d _ g s dr < "$f" 2>/dev/null || true
			[ -n "$dr" ] || continue
			done=$(( done + d )); goals=$(( goals + g ))
			shots=$(( shots + s )); draws=$(( draws + dr ))
		done
		if (( done > 0 )); then
			local elapsed=$(( SECONDS - started ))
			local eta=$(( elapsed * (total - done) / done ))
			printf '  [%3d/%3d] %3d%%  %s elapsed, ~%s left   goals/match %.2f  shots/team %.1f  draws %.0f%%\n' \
				"$done" "$total" $(( done * 100 / total )) \
				"$(fmt_time $elapsed)" "$(fmt_time $eta)" \
				"$(echo "$goals $done" | awk '{printf "%.2f", $1/$2}')" \
				"$(echo "$shots $done" | awk '{printf "%.1f", $1/($2*2)}')" \
				"$(echo "$draws $done" | awk '{printf "%.0f", 100*$1/$2}')"
		fi
		(( done < total )) || break
		sleep "$interval"
	done
}

fmt_time() {
	local s="$1"
	if (( s < 60 )); then printf '%ds' "$s"; else printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); fi
}

# Pulls --workers and --keep out of the argument list, leaving the rest for the
# simulation itself.
drive_parallel() {
	local total="$1"; shift
	local workers="$WORKERS_DEFAULT"
	local keep=0
	local rest=()
	while [ $# -gt 0 ]; do
		case "$1" in
			--workers) workers="$2"; shift 2 ;;
			--matches) total="$2"; shift 2 ;;
			--keep) keep=1; shift ;;
			*) rest+=("$1"); shift ;;
		esac
	done
	parallel_batch "$total" "$workers" "$keep" ${rest+"${rest[@]}"}
}

cmd="${1:-}"
shift || true

case "$cmd" in
	test)          exec "$GODOT" --headless --script res://tests/run_tests.gd -- "$@" ;;
	record-golden) exec "$GODOT" --headless --script res://tests/record_golden.gd ;;
	view)          exec "$GODOT" res://presentation/debug_match.tscn ;;
	view3d)        exec "$GODOT" res://presentation/match_3d.tscn -- "$@" ;;
	demo)
		# Six a side, for comparison against the eleven-a-side compressed match
		# the view now opens by default. Kept because it is the other answer to
		# the same question and the two are worth seeing side by side; the owner
		# chose eleven for the tactics it keeps.
		exec "$GODOT" res://presentation/match_3d.tscn -- \
			--small --clock-rate "${DEMO_CLOCK_RATE:-10}" "$@"
		;;
	shot)
		# Renders a frame from a virtual display, so the look can be checked
		# without anyone sitting and watching a match.
		# The virtual screen is sized to the frame: the window fills the screen
		# it is given, so a 1280x1024 default clamps anything wider.
		out="${SHOT_PATH:-/tmp/footman-frame.png}"
		res="${SHOT_RES:-1280x720}"
		xvfb-run -a -s "-screen 0 ${res}x24" "$GODOT" res://presentation/match_3d.tscn \
			--resolution "$res" \
			-- --shot "${SHOT_AT:-40}" --speed "${SHOT_SPEED:-8}" --shot-path "$out" "$@"
		echo "wrote $out"
		;;
	poses)
		# The pose sheet. A dive lasts under a second and happens a handful of
		# times a match, so this is the only practical way to look at one.
		out="${SHOT_PATH:-/tmp/footman-poses.png}"
		xvfb-run -a "$GODOT" res://presentation/match_3d.tscn --resolution 1920x1080 \
			-- --poses --pose-u "${POSE_U:-0.55}" --shot 1 --shot-path "$out" "$@"
		echo "wrote $out"
		;;
	ramp)
		if printf '%s\n' "$@" | grep -qx -- "--shot"; then
			exec xvfb-run -a -s "-screen 0 1920x1080x24" \
				"$GODOT" res://presentation/ramp.tscn -- "$@"
		fi
		exec "$GODOT" res://presentation/ramp.tscn -- "$@"
		;;
	parade)
		# The rank of players, close up and numbered. Same squad a match of that
		# seed uses. With --shot it renders one frame from a virtual display and
		# quits, so it can be looked at without a screen; without it, it opens a
		# window and waits for keys.
		if printf '%s\n' "$@" | grep -qx -- "--shot"; then
			# The screen size is the frame size, and `--resolution` is not: the
			# window fills whatever virtual screen it is given, so asking Godot
			# for 1920x1080 on xvfb-run's default 1280x1024 screen produced a
			# 640x480 shot -- four faces about fifty pixels wide, too small to
			# judge a brow on, which is what this view exists for.
			exec xvfb-run -a -s "-screen 0 1920x1080x24" \
				"$GODOT" res://presentation/parade.tscn -- "$@"
		fi
		exec "$GODOT" res://presentation/parade.tscn -- "$@"
		;;
	check)
		# Parse-checks every script in the project, presentation included.
		#
		# `test` cannot do this. It runs through the headless entry point and
		# never loads a scene, so a parse error in a view is invisible to it
		# while taking the whole scene down when anyone actually runs the game.
		# The import pass reports such errors but exits 0 regardless, so the
		# grep is what turns it into a gate.
		out="$("$GODOT" --headless --import 2>&1)"
		if printf '%s\n' "$out" | grep -qE "Parse Error|Failed to load script"; then
			printf '%s\n' "$out" | grep -E "Parse Error|Failed to load script|GDScript::reload"
			echo "FAIL"
			exit 1
		fi
		echo "all scripts parse"
		;;
	import)        exec "$GODOT" --headless --import ;;
	# The tight loop: whole standard matches at reduced fidelity, judged on the
	# sanity ranges only. Catches "I broke football" in the time it takes to
	# read the diff. Was 6 x 12 match-minutes; at the standard clock a full
	# ninety is nine minutes of football and costs less than those twelve did,
	# so smoke and gate now differ only in fidelity.
	smoke)         drive_parallel 6 --reduced --home 0.62 --away 0.55 "$@" ;;
	# The routine check: full-length, full-fidelity matches, small sample.
	gate)          drive_parallel 6 --home 0.62 --away 0.55 "$@" ;;
	# The tuning check. Only this one judges the §11 target table.
	accept)        drive_parallel 200 --strict --home 0.62 --away 0.55 "$@" ;;
	pbatch)        drive_parallel 8 "$@" ;;
	tactics)
		per_arm=12
		workers="$WORKERS_DEFAULT"
		rest=()
		while [ $# -gt 0 ]; do
			case "$1" in
				--matches) per_arm="$2"; shift 2 ;;
				--workers) workers="$2"; shift 2 ;;
				*) rest+=("$1"); shift ;;
			esac
		done
		parallel_tactics "$per_arm" "$workers" ${rest+"${rest[@]}"}
		;;
	match|diagnose|chains|batch|perf|determinism|aggregate|compare|replay|behind|box|strike|control|scenario|world)
	               exec "$GODOT" --headless --script res://tools/headless_main.gd -- "$cmd" "$@" ;;
	""|-h|--help)  usage ;;
	*)             echo "unknown command: $cmd" >&2; usage; exit 2 ;;
esac
