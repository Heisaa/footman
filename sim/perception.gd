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
	ctx.seen_ticks.resize(n * n)
	for i in n:
		for j in n:
			ctx.beliefs[i * n + j] = ctx.players[j].pos
			ctx.belief_ticks[i * n + j] = -1000
			ctx.seen_ticks[i * n + j] = -1000


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
		# The plan's half of how much he is looking, read once for the whole scan.
		var scan := 1.0 - SimTempo.tempo_of(ctx, observer.team)
		var cos_half := cos(view_half(observer, scan))
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
			# And whether this one was actually in front of him, which is the
			# thing `can_see` remembers. Stamped in the scan rather than tested
			# on demand, so one scan is one look: a man who was in the arc when
			# the observer last swept it stays passable for `SEEN_MEMORY`.
			if in_view >= cos_half:
				ctx.seen_ticks[i * n + j] = ctx.tick_index


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


## Whether the observer can see the target at all, right now.
##
## `docs/THE_FOOTBALL.md` 12, and checking it first is what the entry asked for.
## The answer was that **there is no visibility model** — `update` refreshes every
## observer's belief about every other player at 4 to 8 Hz whatever anyone is
## looking at, and being behind you only widens the noise from 0.35 m to 1.5 m.
## Nothing is ever unseen, so the option outside perception the proposal worried
## about could not exist, and neither could the football it describes: a man
## screaming for it over your shoulder who genuinely does not get the ball.
##
## So this is the model that was missing rather than a gate on the one that was
## there. Inside `NEAR_ALWAYS` he is seen however he stands — you hear him, you
## know he is there, and a five-metre ball to a man behind you is a real pass.
## Beyond it he has to be inside the arc the observer is facing, widened by
## `awareness`, which is the attribute whose whole job is this and which until now
## only moved the refresh rate.
##
## Deliberately about the *observer's body*, not about a scan flag: `SimMovement`
## already turns a receiver's hips and `SimTouch` already prices striking across
## the body, so the same facing that decides whether he can hit the pass now
## decides whether he can find it. A man who wants the ball behind him has to
## turn, and turning is what the dwell is for.
##
## **It is a memory, not a cone, and that is the correction.** Written as an
## instantaneous arc it refused 46% of every teammate a passer weighed (`The small
## acts`, seed 7), because a man is outside a 200-degree arc a little under half
## the time and nothing above remembers he was inside it a moment ago. That is also
## two models of the same event, which `docs/INVARIANTS.md` names as its own class
## of bug: `update` refreshes a belief about a man behind you and prices the
## staleness, and then this said he did not exist. Real football is the memory --
## scanning is coached precisely so that the man you checked over your shoulder is
## a pass you can still play, and the ball you cannot play is to a man who has
## arrived somewhere you have never looked.
##
## So the question is when he was last in the arc, and `update` stamps that in the
## same sweep it refreshes the belief in. `believed_pos` already prices what the
## delay costs: the position is stale by up to `SEEN_MEMORY` and extrapolated along
## a velocity that may have changed, which is exactly the blind ball this is for.
const NEAR_ALWAYS := 9.0
## Half-arc of vision either side of where he is facing, in radians: a poor
## scanner sees not much past his shoulders, a good one has eyes in the back of
## his head. 1.4 rad is about 80 degrees each way, 2.2 about 126.
const VIEW_HALF_POOR := 1.4
const VIEW_HALF_GOOD := 2.2
## How long a man stays findable after the last look that found him. A footballer
## scans every few seconds and plays off what the last scan told him; a poor one
## looks less often and forgets sooner, which is the second thing `awareness`
## buys after the refresh rate.
const SEEN_MEMORY_POOR := 1.2
const SEEN_MEMORY_GOOD := 3.0


## How much of the world he takes in at once: a plan quantity as much as an
## attribute, since a side playing quick and direct plays with its head down and a
## patient one scans before it receives. `scan` is the plan's half of it,
## `awareness` the man's, and they average -- so a good scanner on a hurried plan
## still sees more than a poor one, which is what makes it an attribute and not a
## switch.
static func view_half(observer: SimPlayer, scan: float) -> float:
	return lerpf(VIEW_HALF_POOR, VIEW_HALF_GOOD,
		(observer.attrs.awareness + clampf(scan, 0.0, 1.0)) * 0.5)


## Whether the observer has had the target in his eyes lately: inside the arc
## now, or inside it within `SEEN_MEMORY`. `can_see` with the near rule taken
## off -- knowing a man is behind you is not seeing him strike a ball.
static func saw_recently(ctx: SimContext, observer: SimPlayer, target: SimPlayer) -> bool:
	if not ENABLED:
		return true
	var to := SimConsts.horizontal(target.pos - observer.pos)
	var d := to.length()
	if d < 0.1:
		return true
	var facing := SimConsts.horizontal(observer.heading_dir())
	var f := facing.length()
	if f < 0.01:
		return true
	if to.dot(facing) / (d * f) >= cos(view_half(observer, 0.5)):
		return true
	var idx := observer.id * ctx.players.size() + target.id
	if idx >= ctx.seen_ticks.size():
		return true
	var since := float(ctx.tick_index - ctx.seen_ticks[idx]) * SimConsts.DT
	return since <= lerpf(SEEN_MEMORY_POOR, SEEN_MEMORY_GOOD, observer.attrs.awareness)


static func can_see(ctx: SimContext, observer: SimPlayer, target: SimPlayer, scan: float = 0.5) -> bool:
	if not ENABLED:
		return true
	var to := SimConsts.horizontal(target.pos - observer.pos)
	var d := to.length()
	if d <= NEAR_ALWAYS:
		return true
	var facing := SimConsts.horizontal(observer.heading_dir())
	var f := facing.length()
	if f < 0.01:
		return true
	if to.dot(facing) / (d * f) >= cos(view_half(observer, scan)):
		return true
	# Not in front of him now. Then it is what the last look found, and how long
	# ago that was.
	var idx := observer.id * ctx.players.size() + target.id
	if idx >= ctx.seen_ticks.size():
		return true
	var since := float(ctx.tick_index - ctx.seen_ticks[idx]) * SimConsts.DT
	return since <= lerpf(SEEN_MEMORY_POOR, SEEN_MEMORY_GOOD, observer.attrs.awareness)


## How stale an observer's view of a target is, in seconds.
static func staleness(ctx: SimContext, observer: SimPlayer, target: SimPlayer) -> float:
	var n := ctx.players.size()
	var idx := observer.id * n + target.id
	if idx >= ctx.belief_ticks.size() or ctx.belief_ticks[idx] < 0:
		return 0.0
	return float(ctx.tick_index - ctx.belief_ticks[idx]) * SimConsts.DT
