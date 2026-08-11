class_name SimPerception
extends RefCounted
## Players are not omniscient (PLAN.md §4.4).
##
## Each player carries a slightly stale, slightly noisy view of the others,
## refreshed at a per-player cadence scaled by awareness, with error growing for
## players behind them. This is cheap, and it is where blind passes, missed
## runners and defensive lapses come from.
##
## Phase 3 turns this on. Until then `believed_pos` returns the truth, and every
## caller already goes through it, so switching it on changes behaviour without
## changing a single call site.

const ENABLED := true
## Refresh cadence bounds in ticks: 4 Hz for a poor scanner, 8 Hz for a good one.
const REFRESH_SLOW := 15
const REFRESH_FAST := 8
## Positional noise, in metres, for a player in view and for one behind you.
const NOISE_IN_VIEW := 0.35
const NOISE_BEHIND := 1.5


static func ensure_storage(ctx: SimContext) -> void:
	var n := ctx.players.size()
	if ctx.beliefs.size() == n * n:
		return
	ctx.beliefs.resize(n * n)
	ctx.belief_ticks.resize(n * n)
	for i in n:
		for j in n:
			ctx.beliefs[i * n + j] = ctx.players[j].pos
			ctx.belief_ticks[i * n + j] = -1000


static func update(ctx: SimContext) -> void:
	if not ENABLED:
		return
	ensure_storage(ctx)
	var n := ctx.players.size()
	for i in n:
		var observer := ctx.players[i]
		if not observer.on_pitch:
			continue
		# Awareness buys a faster scan. Each player refreshes one slice of their
		# view per eligible tick, spread so no tick refreshes everything.
		var cadence: int = int(round(lerpf(REFRESH_SLOW, REFRESH_FAST, observer.attrs.awareness))) * ctx.config.decision_stride()
		if (ctx.tick_index + observer.id) % cadence != 0:
			continue
		var facing := observer.heading_dir()
		# Half the field of view per scan, alternating. Beliefs are noisy and
		# stale by design, so spreading the refresh over two passes costs
		# nothing real and halves the most expensive loop in the module.
		var parity := (ctx.tick_index / cadence) % 2
		for j in n:
			if j != i and j % 2 != parity:
				continue
			if i == j:
				ctx.beliefs[i * n + j] = observer.pos
				ctx.belief_ticks[i * n + j] = ctx.tick_index
				continue
			var target := ctx.players[j]
			if not target.on_pitch:
				continue
			var to_target := target.pos - observer.pos
			var dist: float = maxf(to_target.length(), 0.1)
			if dist > 38.0:
				# What the far side of the pitch is doing does not change any
				# decision this player is about to make, and refreshing it is
				# the single most expensive thing in this loop.
				continue
			var in_view := (to_target / dist).dot(facing)
			# Behind the shoulder is where information goes stale.
			var noise: float = lerpf(NOISE_BEHIND, NOISE_IN_VIEW, clampf((in_view + 1.0) * 0.5, 0.0, 1.0))
			noise *= lerpf(1.6, 0.6, observer.attrs.awareness)
			noise *= 1.0 + dist * 0.012
			var err := Vector3(
				ctx.rng.gauss_clamped(0.0, noise, 2.5),
				0.0,
				ctx.rng.gauss_clamped(0.0, noise, 2.5)
			)
			ctx.beliefs[i * n + j] = target.pos + err
			ctx.belief_ticks[i * n + j] = ctx.tick_index


## Where `observer` believes `target` is. Between refreshes the belief is
## extrapolated along the target's last-known velocity, which is why a player
## can be beaten by a change of direction they did not see.
static func believed_pos(ctx: SimContext, observer: SimPlayer, target: SimPlayer) -> Vector3:
	if not ENABLED:
		return target.pos
	var n := ctx.players.size()
	var idx := observer.id * n + target.id
	if idx >= ctx.beliefs.size() or ctx.belief_ticks[idx] < 0:
		return target.pos
	var age := float(ctx.tick_index - ctx.belief_ticks[idx]) * SimConsts.DT
	return ctx.beliefs[idx] + target.vel * age * 0.6


## How stale an observer's view of a target is, in seconds.
static func staleness(ctx: SimContext, observer: SimPlayer, target: SimPlayer) -> float:
	var n := ctx.players.size()
	var idx := observer.id * n + target.id
	if idx >= ctx.belief_ticks.size() or ctx.belief_ticks[idx] < 0:
		return 0.0
	return float(ctx.tick_index - ctx.belief_ticks[idx]) * SimConsts.DT
