class_name SimDecision
extends RefCounted
## On-ball decision making (PLAN.md §4.2).
##
## Candidates are generated, each is scored as
##   success x gain - (1 - success) x risk_weight x loss
## and one is chosen by softmax, never by argmax. Deterministic argmax selection
## is the most common way this kind of engine ends up feeling robotic; the
## temperature falls with the decisions attribute, so better decision-makers
## more often pick the genuinely best option and weaker ones make
## plausible-but-wrong choices.
##
## All values are in goal-probability units, so expected threat, expected goals
## and the counter-attacking threat conceded on a turnover are directly
## comparable.

## `FEINT` is appended: the enum's numbers index the lost/calib tallies and
## the probes' name tables.
enum Action { HOLD, DRIBBLE, GROUND_PASS, LOFTED_PASS, THROUGH_BALL, CROSS, SHOOT, CLEAR, SET, DUMMY, FEINT }

## Which term an option that was on the list lost on.
##
## `received` in the off-ball table says a run was not found. It cannot say
## whether the ball to it scored badly or scored perfectly well and was beaten by
## something better, and those want opposite fixes -- one is the pass model, the
## other is the rest of the list. Guessing between them is how two changes went in
## backwards in one afternoon.
##
## So: on every decision, the best-scoring candidate of each kind is compared with
## the one actually played, and the four numbers the score is made of are summed
## for both sides. The averages come out as "a through ball, when it was the best
## of its kind and lost, had a success of 0.24 against the played option's 0.58" --
## which names the term without anybody having to reason about the softmax.
##
## Counted rather than logged, and for the same reason as `SimOffBall`'s tallies:
## a decision happens several times a second, `SimTelemetry.canonical_text` is
## hashed by the golden replay test, and a diagnostic has no business moving a
## digest. Nothing in `sim/` reads it back and it never touches `ctx.rng`.
const LOST_N := 0
const LOST_SUCCESS := 1
const LOST_GAIN := 2
const LOST_LOSS := 3
const LOST_BIAS := 4
const LOST_SCORE := 5
const WON_SUCCESS := 6
const WON_GAIN := 7
const WON_LOSS := 8
const WON_BIAS := 9
const WON_SCORE := 10
## And the five factors the losing candidate's `success` is a product of, for the
## pass kinds. A success of 0.05 can be one factor at 0.05 or three at 0.4, and
## those are unrelated faults in unrelated code, so the product on its own sends
## you looking in the wrong place.
const LOST_SPACE := 11
const LOST_IN_TIME := 12
const LOST_LANE := 13
const LOST_CONTROL := 14
const LOST_STRUCK := 15
## And the same model's claim about the balls it *played*, which is the only
## thing that can calibrate it.
##
## `LOST_SUCCESS` is the best rejected candidate of its kind and `completed` in
## the diagnostics is what the played ones did, so the two sit in one table and
## are not comparable: selection puts the second above the first by however much
## that kind is selected, and a kind that loses fourteen times for every one it
## plays is selected hard. A through ball reading 0.12 against 56% completed was
## either a model that is wrong by a factor of five or a model that is right and
## picking well, and nothing in the project could tell those apart.
##
## `PLAYED_MODEL` is the same number for the same balls: the product of the five
## factors, for the candidate that got played, averaged over the ones that did.
## Against the completion rate of that same population it is a calibration and
## not an insinuation. It is the product rather than `success` because
## `off_balance` is a penalty on the choice and not a claim about the ball.
## The same five factors again, for the played ball, because a calibration gap is
## a product and a product names nothing.
const PLAYED_N := 16
const PLAYED_MODEL := 17
const PLAYED_SPACE := 18
const PLAYED_IN_TIME := 19
const PLAYED_LANE := 20
const PLAYED_CONTROL := 21
const PLAYED_STRUCK := 22
const LOST_STRIDE := 23

## Slots of `_parts`, which is what a success model leaves behind for the tally.
##
## Named for what they mean rather than for either model's internals, so the two
## can share a table. A ball in the air has no `IN_TIME` and no `LANE` -- it
## cannot be cut out along the ground, which is the whole difference between it
## and a pass -- and a ball on the floor has no `CONTROL`, because a first touch
## does not decide whether a pass arrives; see `receiver_touch`. Each comes back
## as 1.0 for the model that does not have it rather than as a gap.
const PART_SPACE := 0
const PART_IN_TIME := 1
const PART_LANE := 2
const PART_CONTROL := 3
const PART_STRUCK := 4
const PARTS := 5

## What the last success model computed, and the same per candidate, written as
## each one is appended so index i means candidate i. Both are scratch, reused
## every decision.
static var _parts := PackedFloat32Array()
static var _cand_parts := PackedFloat32Array()


## Files the factors of the success just computed. Called by the two success
## models; picked up by `_keep_parts` when the candidate they belong to is
## appended.
static func _note_parts(space: float, in_time: float, lane: float, control: float, struck: float) -> void:
	if _parts.size() != PARTS:
		_parts.resize(PARTS)
	_parts[PART_SPACE] = space
	_parts[PART_IN_TIME] = in_time
	_parts[PART_LANE] = lane
	_parts[PART_CONTROL] = control
	_parts[PART_STRUCK] = struck


## Attaches them to the candidate that has just gone on the list.
static func _keep_parts() -> void:
	var at := (_candidates.size() - 1) * PARTS
	if _cand_parts.size() < at + PARTS:
		_cand_parts.resize(at + PARTS)
	for k in PARTS:
		_cand_parts[at + k] = _parts[k] if _parts.size() == PARTS else 1.0

## The named factors that went into the candidate being built, and the same per
## candidate, on the pattern `_parts` and `_cand_parts` set above.
##
## `SimAblation` takes a term back out of a score rather than rebuilding the
## candidate without it, which it could not do: candidate generation draws from
## `ctx.rng`, so a second pass through it would move the match. A factor applied
## here is therefore recorded here, and the instrument subtracts or divides it
## back out at the point `score_of` uses it.
##
## Both are scratch and both cost one boolean test when nobody is measuring.
static var _factors := PackedFloat32Array()
static var _cand_factors := PackedFloat32Array()


## Files one named factor of the candidate being built. Multiplicative priors are
## recorded as themselves; a factor that scales only part of a term is recorded
## as the amount it contributed, because dividing the whole term by it would take
## out everything else added alongside.
static func _note_factor(slot: int, v: float) -> void:
	if not SimAblation.enabled:
		return
	if _factors.size() != SimAblation.FACTORS:
		_clear_factors()
	_factors[slot] = v


## Attaches them to the candidate that has just gone on the list, and blanks the
## scratch so the next candidate starts from a term it does not have rather than
## from the last one's.
static func _keep_factors() -> void:
	if not SimAblation.enabled:
		return
	if _factors.size() != SimAblation.FACTORS:
		_clear_factors()
	var at := (_candidates.size() - 1) * SimAblation.FACTORS
	if _cand_factors.size() < at + SimAblation.FACTORS:
		_cand_factors.resize(at + SimAblation.FACTORS)
	for k in SimAblation.FACTORS:
		_cand_factors[at + k] = _factors[k]
	_clear_factors()


static func _clear_factors() -> void:
	_factors.resize(SimAblation.FACTORS)
	for k in SimAblation.FACTORS:
		_factors[k] = SimAblation.neutral_of(k)


## What one term contributed to one candidate, for the instrument to take out.
static func _undo(index: int, term: int) -> float:
	if term < 0 or index < 0:
		return 1.0
	var slot: int = SimAblation.TERM_SLOT[term]
	if slot < 0:
		return 1.0
	var at := index * SimAblation.FACTORS + slot
	if at < 0 or at >= _cand_factors.size():
		return SimAblation.neutral_of(slot)
	return _cand_factors[at]

static var lost := PackedFloat32Array()

## Scratch for the tally: the best-scoring candidate of each kind this decision.
static var _best_of_kind := PackedInt32Array()

## --- The model against what became of the ball ------------------------------
##
## `PLAYED_MODEL` beside `completed` says the model is out by a factor and stops
## there. It is a mean against a mean, so it cannot say whether the factor is one
## term charging for something that never happens or every term being a little
## strict, and those are different repairs in different functions.
##
## What separates them is the same balls resolved one at a time. A factor that is
## a probability of something the match can actually do is *higher on the balls
## that arrived than on the ones that did not*; a factor that is a flat discount
## on a thing nothing resolves reads the same on both, and its whole contribution
## is a constant the model is wrong by.
##
## Buckets of the product carry the other half: a model that is strict but ordered
## rises across them, and one that is not ordered at all is not a model.
const CALIB_BUCKETS := [0.25, 0.40, 0.55, 0.70, 0.85]
const CAL_N := 0
const CAL_SAID := 1
const CAL_OK := 2
const CAL_SLOTS := 3
## Per pass kind and bucket: how many balls, what the model said, how many arrived.
static var calib := PackedFloat32Array()
## And per pass kind and outcome (0 given away, 1 arrived): a count and the
## factors summed.
##
## Per kind, because the kinds are two different models sharing a table and a
## factor can be a constant in one and the whole story in the other. Pooled, the
## ground pass is three quarters of every played ball and the aerial branch cannot
## be seen at all.
static var calib_parts := PackedFloat32Array()
const CALIB_PART_STRIDE := PARTS + 1
const CALIB_KIND_STRIDE := 2 * CALIB_PART_STRIDE

## What the model claimed about the ball a man has in flight, kept until it
## resolves. One entry per player, because a man has one ball in flight at a time
## -- so the claim and the outcome are the same ball, and not a join by order that
## an unresolved pass would shift onto somebody else's.
static var _flight := PackedFloat32Array()
static var _flight_kind := PackedInt32Array()
static var _flight_action := PackedInt32Array()


## Clears the rejection tally. Called from `SimMatch.setup` with the rest of the
## static state, because a static outlives the match that filled it.
static func reset() -> void:
	reset_rare()
	unseen = 0
	shortlisted = 0
	lists = 0
	lists_capped = 0
	dropped = 0
	lost.resize(Action.size() * LOST_STRIDE)
	for i in lost.size():
		lost[i] = 0.0
	_exposure_tick = -1
	exposure_sum = 0.0
	exposure_line = 0.0
	exposure_n = 0.0
	stretch_sum = 0.0
	stretch_n = 0.0
	stretch_hi = 0.0
	break_decisions = 0.0
	break_in_window = 0.0
	break_on_sum = 0.0
	break_exposed_sum = 0.0
	break_secure_sum = 0.0
	break_hist.resize(BREAK_BUCKETS.size() + 1)
	for i in break_hist.size():
		break_hist[i] = 0
	behind_gate.resize(BEHIND_GATES.size())
	for i in behind_gate.size():
		behind_gate[i] = 0.0
	behind_gate_run.resize(BEHIND_GATES.size())
	for i in behind_gate_run.size():
		behind_gate_run[i] = 0.0
	behind_reach_sum = 0.0
	behind_reach_n = 0
	calib.resize(Action.size() * (CALIB_BUCKETS.size() + 1) * CAL_SLOTS)
	for i in calib.size():
		calib[i] = 0.0
	calib_parts.resize(Action.size() * CALIB_KIND_STRIDE)
	for i in calib_parts.size():
		calib_parts[i] = 0.0
	_flight.resize(0)
	_flight_kind.resize(0)
	_flight_action.resize(0)
	_set_worth = 0.0
	tally_set = 0
	tally_dummy = 0
	tally_shield = 0
	tally_feint = 0
	tally_beat = 0
	tally_beat_foul = 0


## One slot of the tally, for the diagnostics to read.
static func lost_at(kind: int, slot: int) -> float:
	var i := kind * LOST_STRIDE + slot
	return lost[i] if i >= 0 and i < lost.size() else 0.0


## Files every kind that was on the list and did not get played, against the one
## that did.
static func _note_rejections(passer: int, chosen: int) -> void:
	if lost.size() != Action.size() * LOST_STRIDE:
		reset()
	if _best_of_kind.size() != Action.size():
		_best_of_kind.resize(Action.size())
	for k in Action.size():
		_best_of_kind[k] = -1
	for i in _candidates.size():
		var kind := int(_candidates[i]["action"])
		var at: int = _best_of_kind[kind]
		if at < 0 or float(_candidates[i]["score"]) > float(_candidates[at]["score"]):
			_best_of_kind[kind] = i
	var won: Dictionary = _candidates[chosen]
	var won_kind := int(won["action"])
	_note_in_flight(passer, won_kind, chosen)
	if is_pass(won_kind):
		var won_at := chosen * PARTS
		if won_at + PARTS <= _cand_parts.size():
			var model := 1.0
			for k in PARTS:
				model *= _cand_parts[won_at + k]
			var won_base := won_kind * LOST_STRIDE
			lost[won_base + PLAYED_N] += 1.0
			lost[won_base + PLAYED_MODEL] += model
			lost[won_base + PLAYED_SPACE] += _cand_parts[won_at + PART_SPACE]
			lost[won_base + PLAYED_IN_TIME] += _cand_parts[won_at + PART_IN_TIME]
			lost[won_base + PLAYED_LANE] += _cand_parts[won_at + PART_LANE]
			lost[won_base + PLAYED_CONTROL] += _cand_parts[won_at + PART_CONTROL]
			lost[won_base + PLAYED_STRUCK] += _cand_parts[won_at + PART_STRUCK]
	for k in Action.size():
		var i: int = _best_of_kind[k]
		if i < 0 or i == chosen:
			continue
		var c: Dictionary = _candidates[i]
		var base := k * LOST_STRIDE
		lost[base + LOST_N] += 1.0
		lost[base + LOST_SUCCESS] += float(c.get("success", 0.0))
		lost[base + LOST_GAIN] += float(c.get("gain", 0.0))
		lost[base + LOST_LOSS] += float(c.get("loss", 0.0))
		lost[base + LOST_BIAS] += float(c.get("bias", 1.0))
		lost[base + LOST_SCORE] += float(c.get("score", 0.0))
		lost[base + WON_SUCCESS] += float(won.get("success", 0.0))
		lost[base + WON_GAIN] += float(won.get("gain", 0.0))
		lost[base + WON_LOSS] += float(won.get("loss", 0.0))
		lost[base + WON_BIAS] += float(won.get("bias", 1.0))
		lost[base + WON_SCORE] += float(won.get("score", 0.0))
		if is_pass(k):
			var at := i * PARTS
			if at + PARTS <= _cand_parts.size():
				lost[base + LOST_SPACE] += _cand_parts[at + PART_SPACE]
				lost[base + LOST_IN_TIME] += _cand_parts[at + PART_IN_TIME]
				lost[base + LOST_LANE] += _cand_parts[at + PART_LANE]
				lost[base + LOST_CONTROL] += _cand_parts[at + PART_CONTROL]
				lost[base + LOST_STRUCK] += _cand_parts[at + PART_STRUCK]


## The touch each pass action is struck as, so a claim made about a candidate can
## be matched to the ball that resolves. One map, because two would drift.
const PASS_TOUCH := {
	Action.GROUND_PASS: SimTelemetry.Touch.GROUND_PASS,
	Action.LOFTED_PASS: SimTelemetry.Touch.LOFTED_PASS,
	Action.THROUGH_BALL: SimTelemetry.Touch.THROUGH_BALL,
	Action.CROSS: SimTelemetry.Touch.CROSS,
}


## Files what the model said about the ball this man is about to strike, and
## clears the slot for anything that is not a pass, so a claim can never outlive
## the decision that made it.
static func _note_in_flight(passer: int, action: int, chosen: int) -> void:
	if passer < 0:
		return
	if _flight_kind.size() <= passer:
		_flight_kind.resize(passer + 1)
		_flight_action.resize(passer + 1)
		_flight.resize((passer + 1) * PARTS)
	var at := chosen * PARTS
	if not is_pass(action) or at + PARTS > _cand_parts.size():
		_flight_kind[passer] = -1
		return
	_flight_kind[passer] = int(PASS_TOUCH.get(action, -1))
	_flight_action[passer] = action
	for k in PARTS:
		_flight[passer * PARTS + k] = _cand_parts[at + k]


## And what became of it, from wherever the pass resolves. `touch` is checked
## against the claim so a restart -- a throw-in is a pass kind and never came out
## of a decision -- cannot be filed against the last ball this man played.
static func note_pass_outcome(passer: int, touch: int, ok: bool) -> void:
	if passer < 0 or passer >= _flight_kind.size():
		return
	if _flight_kind[passer] != touch or touch < 0:
		return
	var action := _flight_action[passer]
	_flight_kind[passer] = -1
	if calib.size() != Action.size() * (CALIB_BUCKETS.size() + 1) * CAL_SLOTS:
		reset()
	var model := 1.0
	for k in PARTS:
		model *= _flight[passer * PARTS + k]
	var b := 0
	while b < CALIB_BUCKETS.size() and model >= float(CALIB_BUCKETS[b]):
		b += 1
	var base := (action * (CALIB_BUCKETS.size() + 1) + b) * CAL_SLOTS
	calib[base + CAL_N] += 1.0
	calib[base + CAL_SAID] += model
	if ok:
		calib[base + CAL_OK] += 1.0
	var side := action * CALIB_KIND_STRIDE + (1 if ok else 0) * CALIB_PART_STRIDE
	calib_parts[side] += 1.0
	for k in PARTS:
		calib_parts[side + 1 + k] += _flight[passer * PARTS + k]


## One bucket of one kind, for the diagnostics to read.
static func calib_at(kind: int, bucket: int, slot: int) -> float:
	var i := (kind * (CALIB_BUCKETS.size() + 1) + bucket) * CAL_SLOTS + slot
	return calib[i] if i >= 0 and i < calib.size() else 0.0


## And one factor of one kind, on the balls that arrived or the ones that did not.
## `slot` is -1 for the count and a `PART_*` otherwise.
static func calib_part_at(kind: int, arrived: bool, slot: int) -> float:
	var i := kind * CALIB_KIND_STRIDE + (1 if arrived else 0) * CALIB_PART_STRIDE + slot + 1
	return calib_parts[i] if i >= 0 and i < calib_parts.size() else 0.0


## The kinds whose `success` is a product of the five factors above.
static func is_pass(action: int) -> bool:
	return action == Action.GROUND_PASS or action == Action.THROUGH_BALL \
		or action == Action.LOFTED_PASS or action == Action.CROSS

## Softmax temperature bounds, as a fraction of the spread of candidate scores.
## Low temperature means near-optimal play.
const TEMP_POOR := 0.55
const TEMP_GOOD := 0.11
## The success below which a candidate is not drawn at all, by the decisions
## attribute.
##
## A softmax never puts anything at zero, and a list of eighteen has a tail of
## balls priced at nothing -- a 28 m pass to a marked centre-half at `succ 0.000`
## carried 0.15% (seed 2, t695, 1.0 v 1.0, owner's bookmark). One in six
## hundred, and a side makes several hundred decisions a match, so the pick a
## footballer never makes landed once or twice a match and looked like this
## every time.
##
## On success, not on share. A floor at a share of the best option's weight
## (0.12, tried) cut the same tail and, with it, every forward pass sitting at
## 2-8% against a hold at 45%: over five matches box touches went 6.5 to 4.3 a
## team while completion rose. The near-tie is still the coin's
## (`docs/INVARIANTS.md`); what is cut is the ball that will not arrive, and a
## better decision-maker cuts deeper. Not the shot: its `success` is the chance
## of a goal, a different currency, and a long shot at 0.05 is a real option.
const SUCCESS_FLOOR_POOR := 0.05
const SUCCESS_FLOOR_GOOD := 0.15
## And a share floor beside it, low. The success floor cannot see the ball the
## owner marked next: a lofted 28 m ball back to the marked centre-half at
## `succ 0.36`, drawn at 2.2% of the hold's weight over a hold at 97% and a
## forward pass at 65% (seed 2, t695 again). At 0.12 of the best this floor
## cut the forward balls at 4-8% too; at 0.05 for the best decision-maker it
## cuts the one-in-fifty and leaves them. The same kinds as the success floor,
## `_floored_kind`: applied to every kind it took shots from 4.1 a team to 2.9
## and offsides from 1.1 to 0.3 over five matches, because the engine takes
## most of its shots and balls in behind from the tail -- a 2-5% option against
## a hold. That they live there is the attack's problem to fix by pricing them,
## not a floor's to hide.
const SHARE_FLOOR_POOR := 0.005
const SHARE_FLOOR_GOOD := 0.05
## Dribble probe directions, in the canonical attacking frame.
const DRIBBLE_DIRS := 8
const DRIBBLE_DISTANCE := 4.5
## How far a dribbler knocks it when he is running away from a challenge rather
## than carrying it. Long enough that the man on his back has to win a foot race
## for it instead of reaching round him for it.
const BURST_DISTANCE := 9.0
## How far in front of himself a carrier puts the ball, in seconds of his own
## running. `SimTouch.dribble` has claimed since it was written that the touch is
## "matched to stride", and nothing in it ever was: the size came off the room and
## the score and never once off the speed of the man playing it.
##
## Measured on seed 7, that is the whole of the complaint that the ball gets away
## from them. A carry pushed it 2.3 m in front while the carrier was travelling at
## about 2.9 m/s -- the ball leaves his foot at 5.3 -- so a jogging player struck
## every touch as though he were sprinting onto it, and then had to sprint onto
## it. A footballer's touch is about half a second of his own running ahead, and
## that is a *rate*: it is what makes a man at full pace push it four metres and
## the same man shifting it inside his own body length keep it under his sole,
## from one rule rather than two.
##
## It bootstraps rather than locking, which is the thing to watch. A standing
## player gets the floor, the floor is enough of a gap for `SimMovement` to pace
## him at it, and the touch after that is bigger because he is quicker. That is
## also how a footballer starts a run.
const TOUCH_SECONDS := 0.55
## The same measure for the knock past a man, which is deliberately further than
## his stride -- that is what makes it a foot race rather than a carry -- and the
## pace below which it is not a foot race at all. A jogger who launches it nine
## metres has not beaten anybody, he has given it away.
const BURST_SECONDS := 1.2
const BURST_PACE := 3.5
## How far past the man the ball has to finish for the knock to be a foot race
## rather than a touch he can stick a boot on -- his reach and a stride.
##
## In metres over the *grass*, which is the frame the man is standing in. The
## gate this replaces was `push < BURST_DISTANCE * 0.55`, five metres of *gap*,
## and the two are not the same test at any pace a footballer runs: measured on
## `take-on` at 5 m/s, five metres of gap is a **21.6 m** ball arriving 4.3
## seconds later, which `control_at_time` correctly prices at nothing because by
## then the whole defence is level with it. The engine's only take-on was a hoof
## into the corner wearing a take-on's name, and it scored `succ 0.00`
## (`docs/THE_FOOTBALL.md` 45).
const BURST_CLEAR := 2.5
## And how far past him is still a take-on rather than a ball into the corner.
## The upper end of the same window, in the same frame.
const BURST_PAST_MAX := 8.0
## How far in front of himself a man puts the ball when he is not trying to go
## anywhere with it. The smallest touch the engine has: `SimTouch.dribble`'s own
## floor, a ball kept inside the width of his own stride.
##
## It is the size that makes the hold the option it was scored as. See
## `_play_hold` -- and note that it is a *rate* only for the carry, deliberately
## not here. A hold does not grow with his pace, because a man who wants the ball
## to stay where it is does not push it further for running faster.
##
## The constant never did grow with his pace. The strike did, for as long as the
## hold went out through `SimTouch.dribble`, which adds the carrier's own speed
## to every touch because a carry is a distance measured against a moving man.
## `SimTouch.settle` is the same distance measured against the grass, which is
## the frame `_add_hold` scores in.
const HOLD_AHEAD := SimTouch.DRIBBLE_AHEAD_FLOOR
## Where a touch stops being a way of covering ground and starts being a way of
## setting yourself: the distance from the goal at which touches begin to shorten,
## and the size they shorten to on top of it.
## How far down a line a carrier is judged to be going, in seconds of his own
## running. The distance every term in a carry's score is read at.
##
## It is not the size of the touch, and the two had been one expression for a
## long time without it showing. `carry_room` answers "how big a touch fits
## here", which is a *gap* between him and the ball; this answers "how far down
## this line is he going", which is where the defender, the touchline and the
## goalkeeper actually are. The mixture was survivable only because the number
## that dominated it was `carry_travel` -- the ball's journey if he never touched
## it again, which is eight to twenty times the journey he plays. Correcting that
## to `touch_travel` collapsed the horizon with it: at twenty-one metres from
## goal the forward probe came back priced **two metres in front of his own
## feet**, which is exactly the short-sightedness `_add_dribbles`' own comment was
## written to prevent, and it is why a striker through on goal could never price
## running the ball into the box and shot from wherever he stood instead (owner,
## watching the one-on-one).
##
## A second or so of his own running is what "still going this way a few touches
## from now" means for a man at pace, and it is bounded below by the ordinary
## probe distance so a walking carrier still looks further than his own boot.
const CARRY_HORIZON_SECONDS := 1.2
## The share of the dribbling tax a carry pays with nobody near. See
## `_add_dribbles`.
const CARRY_SKILL_FLOOR := 0.25
const CLOSE_CONTROL_FAR := 22.0
const CLOSE_CONTROL_NEAR := 6.0
const CLOSE_CONTROL_TOUCH := 1.6
## Logistic width, in seconds, on the race between carrier and challenger for a
## dribble's landing point. Tighter than the pitch-control equivalent because
## this is one race between two known men, not a field-wide average.
const ESCAPE_TAU := 0.30
## How long after winning the ball back the priority is still to secure it
## rather than to advance it, in seconds.
const REGAIN_WINDOW := 2.0
## Where a pass stops being a thing you can play along the grass.
##
## These two numbers, and the lofted pass's own threshold, are the whole of the
## rule that a longer ball is a higher ball. Below the lofted threshold the only
## pass on offer is along the ground; between it and the ground limit both are
## generated and the softmax chooses; past the ground limit the ball in the air
## is the only pass there is. Nothing weights one against the other by distance —
## the share of passes that are lofted rises with length because that is which
## options exist, which is also how it works on a pitch.
##
## Thirty-two metres is already a driven ball rather than a pass, and the ground
## limit sat at thirty-eight, which is a ball nobody hits along the floor. Past
## the lofted limit it is not a pass at all, it is a clearance, and `_add_clear`
## is where those live.
## The driven ball: how much of the lane it buys back by being in the air over the
## middle of its journey, how much firmer it is struck than the roller beside it,
## and what the receiver pays for taking a ball that arrives at that pace.
##
## `docs/THE_FOOTBALL.md` 26. The strike was already built -- `ground_launch` lofts
## anything above `SimBallistics.DRIVE_FROM` and solves the hops -- and what was
## missing was the reason to choose one: the score priced it as a roller, so the
## engine drove balls without ever deciding to. It is a second candidate beside the
## rolled one rather than a replacement for it, because the choice between them is
## the football, and the softmax is what makes it.
## What a shot struck at a flat-out run is worth against the same shot standing
## still, and what is left of a man's finish when his legs have gone. The two
## things `expected_goals` could not see; see the note where they are applied.
## Generated against chosen, for the acts that exist and almost never happen.
##
## `The small acts` counts what got played: `chips 0`, `cuts tried 5, beat his man
## 0`. A zero there has two causes that want opposite fixes -- the act was never a
## candidate, or it was a candidate every time and lost the softmax -- and this
## project has been caught by the first four times. One tally, so the next zero is
## answered by reading a line rather than by adding an instrument.
##
## Indexed by `RARE_ACTS`. One-way, like every tally here.
const RARE_ACTS := ["chip", "round him", "dummy", "cut back", "open it", "bend it", "trivela", "feint"]
static var rare_offered := PackedInt32Array()
static var rare_played := PackedInt32Array()


static func reset_rare() -> void:
	feint_gate.resize(FEINT_GATES.size())
	for i in FEINT_GATES.size():
		feint_gate[i] = 0
	rare_offered.resize(RARE_ACTS.size())
	rare_played.resize(RARE_ACTS.size())
	for i in RARE_ACTS.size():
		rare_offered[i] = 0
		rare_played[i] = 0


## Teammates refused a place on the list because the passer could not see them.
static var unseen := 0
static var shortlisted := 0
## And refused for the other reason: the list is `MAX_PASS_TARGETS` long. Counted
## because a cap that never binds and a cap that throws away half the team look
## identical from outside, and the answer decides whether the number is worth
## paying for. `dropped` excludes the men the guarantees below put back.
static var lists := 0
static var lists_capped := 0
static var dropped := 0


static func _note_shortlist_unseen() -> void:
	unseen += 1


static func _note_rare(which: int, played: bool) -> void:
	if rare_offered.size() != RARE_ACTS.size():
		rare_offered.resize(RARE_ACTS.size())
		rare_played.resize(RARE_ACTS.size())
	rare_offered[which] += 1
	if played:
		rare_played[which] += 1


const RARE_CHIP := 0
const RARE_ROUND := 1
const RARE_DUMMY := 2
const RARE_PULLBACK := 3
const RARE_OPENING := 4
const RARE_BEND := 5
const RARE_TRIVELA := 6
const RARE_FEINT := 7

## Measured on the day it landed, twenty seeds: **it costs 1.58 goals a match**
## (4.04 to 2.46) and 0.07 of the conversion rate. That is the largest single
## scoring move in the engine's history and it is a *correction*, not a tuning
## choice -- the model was pricing a shot struck at a flat-out sprint by a spent
## man as if he were set and fresh. `PLAN.md` §11.1.1 and `CLAUDE.md` both say a
## mechanic is not softened to protect a statistic, so it stays and the number is
## recorded here rather than absorbed. One line each to lift if the owner wants
## the goal count back before the tuning freeze.
const SHOT_AT_PACE := 0.72
const SHOT_SPENT := 0.80
## How much of the pass model's failure is one cause wearing three hats.
##
## `docs/THE_FOOTBALL.md` 24, and the entry is explicit that a scale factor is the
## wrong answer -- `which factor knew` would read a third constant exactly the same
## way. The defect is the *shape*: `space`, `lane` and `struck` are multiplied as
## though they were independent, and they are not. One defender standing in the
## line lowers `lane` and lowers `space`, because he is also the man who gets
## there; a passer under pressure strikes it worse, and pressure is what put the
## defender there in the first place. Multiplying three views of one cause charges
## for it three times, which is why the model is under-confident on exactly the
## balls that have a defender near them and calibrated on the ones that do not.
##
## The rule: combine them along the line from their product to their minimum. At
## `CORRELATED` 0 this is the plain product and nothing changes; at 1 it is the
## worst factor alone, which is what perfectly-shared failure means -- one cause,
## priced once. In between it is the geometric interpolation, which keeps it a
## probability, keeps it monotone in each term, and cannot be mimicked by any
## constant because how far the product sits below the minimum depends on how many
## of the three are biting at once. Three balls with the same product and different
## spreads now come out differently, which is the whole claim.
##
## `in_time` stays outside it: it is a fact about the receiver's legs, not about
## the defender, and it is the one term here with a different cause.
## **Measured, and it is not the answer.** Built and run over twenty seeds at
## `CORRELATED` 0.45: goals fell 4.08 to 3.24 and shots 5.61 to 4.87, and the
## calibration it exists to fix **did not move** — the bottom bucket still said
## 0.12 for balls that arrived 52% of the time, against 0.11 and 52% before. So
## the residual under-confidence is not the three terms sharing a cause, or not
## mostly; whatever it is survives pricing that cause once. Left here, wired to
## nothing, because the next person to read 24 will reach for exactly this and the
## fact that it has been tried is the useful part.
const CORRELATED := 0.45


static func _joint(a: float, b: float, c: float) -> float:
	var product := a * b * c
	var worst: float = minf(a, minf(b, c))
	if product <= 0.0 or worst <= 0.0:
		return product
	# product^(1-k) * worst^k, written as a log-lerp so the exponent is explicit.
	return exp(lerpf(log(product), log(worst), CORRELATED))


## **27, tried and not the answer.** Making a direct plan charge less per metre of
## pass length -- 0.165 against a patient plan's 0.255, either side of the single
## 0.21 that is still used -- was the mechanic the proposal named for "the direct
## plan does not play the longer pass". Measured, it did not separate the two
## plans on length either: `pass_length` t=1.32, and `test_tactics` went red
## because it took the second separating measure with it. So directness is not
## expressed through length, and the open football question in 27 is still open --
## with one candidate answer now struck off it.
## The feint from a standstill: how close the man has to be for there to be
## anything to feint at, and what starting from nothing costs against cutting at
## pace. See `_try_beat`.
const FEINT_RANGE := 3.2
const FEINT_COST := 0.55
## The feint as a candidate (`_add_feint`): how long the body is sold before
## the ball moves. A quarter of a second is a dropped shoulder, and it is what
## the act costs against knocking it past him at once.
const FEINT_HOLD := 0.25
const DRIVEN_LANE := 0.55
const DRIVEN_PACE := 1.9
const DRIVEN_TOUCH := 0.82
## How much more of the lane the bent ball must survive before the driven
## candidate becomes the curled one. `OPENING_MIN`'s shape and reason: below
## this it is the same option and the bend is theatre.
const CURL_MIN := 0.05
## What a trivela keeps of the success it was priced at. The outside of the
## boot is the harder surface, and `SimTouch.TRIVELA_SIGMA` charges the strike
## the same fact; this is the half the decision sees, so the flipped bend is a
## fallback and not a free second lane.
const TRIVELA_CONTROL := 0.85
const LOFTED_FROM := 24.0
const MAX_GROUND_PASS := 32.0
## **45 to 55, 2026-08-23** (owner). The old ceiling was shorter than football's
## own long ball: a switch from one touchline to the other on a 68 m pitch is
## fifty-odd metres and a goalkeeper's kick is more, and `switch` measured what
## that costs -- the free man on the far side was 54 m away, so the ball the
## scenario is named for was never a candidate and the first decision of every
## trial was twelve carries and a hold. `SimTouch.strike_range` still caps every
## ball by the man striking it, so this is a ceiling on the act and not a promise
## about anybody's leg.
const MAX_LOFTED_PASS := 55.0
## How much grass a touch has to leave between the ball and the line. A ball
## that stops exactly on the paint is a ball nobody can do anything with.
const LINE_MARGIN := 1.2
## Standing penalties on the two passes that flatter themselves: they look
## valuable because they end up further forward, and they are much harder than
## the value function alone admits.
const THROUGH_BALL_BIAS := 0.55
const LOFTED_BIAS := 0.30
## How many teammates get fully scored as pass targets.
##
## Scoring a pass properly costs a pitch-control evaluation, an interception
## sweep and an execution-accuracy estimate, so doing it for all ten teammates
## times three pass kinds is most of the cost of the whole engine. A cheap
## pre-filter over values already computed this tick throws away the options
## nobody was ever going to take, and the softmax cannot tell the difference.
##
## **Six was the cost of a saving that does not exist, and it is nine.** Measured
## once the tally beside it was built: at six the cap bound on **78% of decisions
## and threw away 2.6 men each**, so the passer's options were chosen by the proxy
## score above and its three guarantee patches rather than by the model. The
## paragraph above assumed a decision happens constantly; a full match holds about
## 650 of them, so the whole cap was saving about 1,700 pass scorings. A
## full-length `diagnose` on seed 7 runs 16.2 s at six and 16.6 s at nine, which is
## one run of a diverging match against another and therefore no measurable cost
## at all. At nine the cap binds on 20% and drops 0.9 men, which is a bound rather
## than a chooser.
const MAX_PASS_TARGETS := 9
## The nearest teammates are always considered whatever the filter thinks, so a
## player under pressure never loses their safe ball.
const ALWAYS_KEEP_NEAREST := 2
## The switch of play. How far across the pitch a man has to be to count as one,
## how much grass around him counts as free, and what the anti-hoof prior gives
## back for it. `LOFTED_BIAS` exists to stop the engine
## hoofing it, and a switch to a free man is not a hoof -- it is the one ball
## that beats a collapse without going long to the front (the cross makes the
## same argument about its own priors at `CROSS_BIAS`). The lift is folded
## into the recorded `F_LOFTED` factor, so the chain still takes the whole
## prior out exactly.
const SWITCH_ACROSS := 12.0
const SWITCH_FREE_RADIUS := 8.0
const SWITCH_LIFT := 2.0


## The lofted prior's refund for a genuine switch: a ball across the pitch to a
## man with grass around him. 1.0 otherwise.
##
## **It used to be gated to the team's own half and that was the wrong half.**
## The gate read `from.x * attack_dir >= 0.0: return 1.0`, so the refund existed
## only while the ball was behind the halfway line -- and this function's own
## first line said the opposite of the constant above it, which is how it went
## unnoticed. A side is most compact in front of its own box, so the final third
## is where the ball across is worth most and where it was priced as a hoof:
## measured on `switch`, the 42 m ball to a free winger 14 m into the attacking
## half sat on the candidate list every tick at `bias 0.10` and never won one,
## and the row it is named for lost the ball in 88% of trials.
static func _switch_lift(ctx: SimContext, player: SimPlayer, mate: SimPlayer,
		believed: Vector3, from: Vector3) -> float:
	if absf(believed.z - from.z) < SWITCH_ACROSS:
		return 1.0
	var near := ctx.nearest_to(mate.pos, SimConsts.other_team(player.team))
	if near != null and near.dist_to(mate.pos) < SWITCH_FREE_RADIUS:
		return 1.0
	return SWITCH_LIFT

## Scratch candidate list, reused so the decision path allocates as little as
## possible. Candidates are dictionaries; there are rarely more than 30.
static var _candidates: Array[Dictionary] = []
static var _scores := PackedFloat32Array()
static var _weights := PackedFloat32Array()
static var _aim_weights := PackedFloat32Array()

## What the last softmax did, for the debug sink alone. Three stores per
## decision, read by nothing in the simulation: `SimDebug` is a one-way tap and
## the pick itself has already happened by the time these are looked at.
static var _last_pick := -1
static var _last_temp := 0.0
static var _last_spread := 0.0


## Called when `player` is in contact with the ball and may act.
static func choose_and_execute(ctx: SimContext, player: SimPlayer) -> void:
	if player.is_keeper:
		SimKeeper.decide_with_ball(ctx, player)
		return

	# Cleared on every decision and set again by `_play_hold`, so it describes the
	# touch just played rather than any earlier one. Shielding likewise.
	player.settling = false
	player.shielding = false

	var regain := _generate(ctx, player)

	if _candidates.is_empty():
		SimTouch.first_touch(ctx, player, ctx.pitch.target_goal(player.team) - player.pos)
		return

	var chosen := _softmax_pick(ctx, player)
	if SimDebug.enabled:
		SimDebug.capture_decision(
			ctx, player, _candidates, _last_pick, _weights, _last_temp, _last_spread, regain
		)
	if SimAblation.enabled:
		_ablation_pass(ctx, player)
	_execute(ctx, player, chosen, _uncontrolled)


## Set beside `_candidates` by `_generate`. Both `_execute` and the debug capture
## need it and neither builds the list, so it travels with the list rather than
## being worked out twice.
static var _uncontrolled := false


## Fill `_candidates` for this player and hand back his regain urgency, without
## anything being played. Split out of `choose_and_execute` so a drill can ask
## what a man is offered in a geometry it set up; `options_for` is the only other
## caller, and nothing in `sim/` uses it.
static func _generate(ctx: SimContext, player: SimPlayer) -> float:
	_candidates.clear()
	var incoming := ctx.ball.vel.length()
	_uncontrolled = incoming > 5.0 and ctx.ball.last_touch_player != player.id
	# Both are situational facts about this moment rather than about any one
	# candidate, so they are established once and handed down: who is coming to
	# take the ball off him, and whether he has only just won it.
	var challenger := ctx.nearest_challenger(player)
	var regain := regain_urgency(ctx, player)

	_add_shot(ctx, player, _uncontrolled)
	_add_passes(ctx, player, _uncontrolled, regain)
	_add_crosses(ctx, player, _uncontrolled)
	_add_pullback(ctx, player, _uncontrolled)
	_add_dribbles(ctx, player, _uncontrolled, challenger, regain)
	_add_opening(ctx, player, _uncontrolled, challenger)
	_add_feint(ctx, player, _uncontrolled, challenger)
	_add_hold(ctx, player, _uncontrolled, regain)
	_add_set_touch(ctx, player, _uncontrolled)
	if _uncontrolled:
		_add_dummy(ctx, player)
	_add_clear(ctx, player)
	_apply_set_damp(ctx, player)
	_file_develop(ctx, player)
	return regain


## Every option this player would be scored on, in a state nobody is going to
## play from. For `tools/behind_bench.gd`, which sets up one geometry and asks
## what ball comes out of it -- the whole point being that no match is running,
## so the answer is a property of the rule and not of the situation it was
## reached from.
static func options_for(ctx: SimContext, player: SimPlayer) -> Array[Dictionary]:
	_generate(ctx, player)
	return _candidates.duplicate()


# --- Candidate generation ---------------------------------------------------


static func _add_shot(ctx: SimContext, player: SimPlayer, first_time: bool) -> void:
	var goal := ctx.pitch.target_goal(player.team)
	var from := ctx.ball.pos
	var distance := SimConsts.horizontal_length(goal - from)
	if distance > 38.0:
		return
	# The beat, as a gate. See `SET_STRIKE_FLOOR`; `_apply_set_damp` is the price
	# either side of it, and this is before `_add_chip` because a chip at goal is
	# a strike and earns the same beat.
	if not first_time and readiness(ctx, player) < SET_STRIKE_FLOOR:
		return
	var aim := _pick_shot_aim(ctx, player, goal)
	var quality := expected_goals(ctx, player, from, aim)
	# Not every sight of goal is a shot, and the floor is here to keep a hopeless
	# attempt out of the softmax rather than to decide anything: a candidate
	# nobody would ever take still widens the spread of scores, and the spread is
	# what the temperature is measured against.
	#
	# At 0.075 it was doing a quite different job. The calibration in
	# `expected_goals` puts the edge of the box at about 0.09 before pressure and
	# bodies in the way are counted, so a shot from beyond eighteen yards -- or
	# from the edge of it with a man closing -- was not scored badly, it was never
	# generated at all. Whether a shot from twenty-two metres is worth taking is a
	# question the score answers on its own, against a turnover priced at
	# POSSESSION_VALUE plus the threat conceded, and answering it a second time
	# with a gate is how a team ends up with no long shots in it. 0.025 is roughly
	# twenty-five metres for an ordinary player with a clear sight of goal, and
	# less than that for one who has neither.
	var tactics := ctx.tactics(player.team)
	# Losing the ball with a shot costs little: the ball ends up deep in the
	# opponent's half either way. That restart is also where the possession
	# stands afterwards, so it is the point `score_of` prices the turnover at.
	var restart := Vector3(goal.x * 0.75, 0.0, 0.0)
	var loss := ctx.value.xt_at(SimConsts.other_team(player.team), restart, ctx.pitch)
	# The chip is generated whether or not the driven shot clears its floor: the
	# moment it exists for is exactly the one where the straight shot is poor.
	_add_chip(ctx, player, from, goal, distance, first_time, tactics, restart, loss)
	# The bend. When bodies sit on the straight corridor, a technician curls it
	# round them -- the foot picks the side (`curl_for`'s sign), so the choice
	# is whether, never which way. A variant *inside* the shot candidate, the
	# curled driven ball's shape, and the improvement is an integer -- a blocker
	# out of the corridor -- so there is no tuned threshold to argue with.
	var power := clampf(0.5 + distance / 40.0, 0.45, 1.0)
	var curl := 0.0
	var trivela := false
	var straight_blockers := _shot_blockers(ctx, player, from, aim)
	if straight_blockers > 0:
		var foot_sign: float = 1.0 if SimTouch.striking_foot(player, aim - from) \
			== SimAttributes.FOOT_RIGHT else -1.0
		var meant: float = SimTouch.SHOT_CURL_BENT \
			* clampf(player.attrs.technique, 0.0, 1.0) * foot_sign
		var speed: float = lerpf(SimConsts.SHOT_SPEED_MIN, SimConsts.SHOT_SPEED_MAX,
			clampf(power * lerpf(0.65, 1.0, player.attrs.power), 0.0, 1.0))
		var bow := SimBallistics.curl_bow(meant, speed, SimConsts.horizontal_length(aim - from))
		var bent_blockers := _shot_blockers(ctx, player, from, aim, bow)
		if bent_blockers < straight_blockers:
			curl = meant
			# What the bend buys, as the exact multiplier `expected_goals`
			# charged for the bodies it removes, so `--ablate` can take the
			# bend back out.
			var bought := pow(0.72, float(bent_blockers - straight_blockers))
			quality = minf(quality * bought, 0.92)
			_note_rare(RARE_BEND, false)
			_note_factor(SimAblation.F_CURL, bought)
		else:
			# The trivela, same fallback as the driven ball's: the natural bend
			# curls into a body, the other side is open.
			var flip_blockers := _shot_blockers(ctx, player, from, aim, -bow)
			if flip_blockers < straight_blockers:
				curl = -meant
				trivela = true
				var bought := pow(0.72, float(flip_blockers - straight_blockers)) \
					* TRIVELA_CONTROL
				quality = minf(quality * bought, 0.92)
				_note_rare(RARE_TRIVELA, false)
				_note_factor(SimAblation.F_CURL, bought)
	if quality < 0.025:
		return
	_candidates.append({
		"action": Action.SHOOT,
		"aim": aim,
		# Not `point`: the debug overlay draws the arrow at that key, and a shot's
		# arrow is its aim.
		"end": restart,
		"success": quality,
		"gain": 1.0,
		"loss": loss,
		"first_time": first_time,
		# A shot is already scored in the same currency as everything else --
		# success times gain, where the success is the chance of scoring and the
		# gain is the goal -- so this multiplier is not the knob for how often the
		# engine shoots. It is what a shot is worth *over and above* the goal it
		# might be: the corner, the rebound, the ball that stays in their half.
		# Somewhere around one, in other words.
		#
		# At a third to two thirds, which is where it was, it was instead a
		# standing tax, and the tax decided the whole of the engine's behaviour in
		# the penalty area. Expected threat peaks at 0.38 near the penalty spot,
		# and a shot from there with a man closing and two bodies in the way is
		# worth about 0.12 once `expected_goals` has counted them -- so carrying
		# the ball in the six-yard box scored better than striking it, every time,
		# and the carry is what got played.
		# `shot_appetite` is 1.0 at real time and only leaves it under compression:
		# see `SimMatchConfig`, "the compressed match's scoring fit".
		"bias": lerpf(0.75, 1.25, tactics.directness) * (0.6 if first_time else 1.0)
			* ctx.config.shot_appetite_at(quality),
		"power": power,
	})
	if curl != 0.0:
		_candidates[-1]["curl"] = curl
		if trivela:
			_candidates[-1]["trivela"] = true
	_keep_factors()


## Picks where in the goal to aim.
##
## Chosen by softmax over the available corners, not by always taking the one
## furthest from the keeper. Always picking the best corner means every shot
## that stays on target is an unsaveable one, and the conversion rate ends up
## three times what football produces. Composure and finishing sharpen the
## choice; a hurried player often just hits it down the middle.
static func _pick_shot_aim(ctx: SimContext, player: SimPlayer, goal: Vector3) -> Vector3:
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	var half := ctx.pitch.goal_half_width - 0.5
	var options := [
		Vector3(goal.x, 0.5, -half),
		Vector3(goal.x, 0.5, half),
		Vector3(goal.x, 1.7, -half * 0.8),
		Vector3(goal.x, 1.7, half * 0.8),
		Vector3(goal.x, 0.6, -half * 0.35),
		Vector3(goal.x, 0.6, half * 0.35),
		Vector3(goal.x, 0.5, 0.0),
	]
	if _aim_weights.size() != options.size():
		_aim_weights.resize(options.size())
	var scores := PackedFloat32Array()
	scores.resize(options.size())
	var best := -INF
	for i in options.size():
		var o: Vector3 = options[i]
		var score := 0.0
		if keeper != null:
			score += minf(keeper.dist_to(o), 8.0)
		score += (2.0 - o.y) * 0.6
		scores[i] = score
		best = maxf(best, score)
	# Placement is a skill: a composed finisher discriminates between corners,
	# a panicked one barely does.
	var temperature: float = lerpf(4.0, 0.7, (player.attrs.composure + player.attrs.finishing) * 0.5)
	temperature /= maxf(1.0 + ctx.pressure_on(player) * 0.6, 1.0)
	for i in options.size():
		_aim_weights[i] = exp((scores[i] - best) / maxf(temperature, 0.05))
	var idx: int = ctx.rng.weighted_index(_aim_weights)
	return options[maxi(idx, 0)]


## The engine's own estimate of shot quality. It informs the choice; the actual
## outcome is resolved physically by the flight of the ball and the keeper.
static func expected_goals(ctx: SimContext, player: SimPlayer, from: Vector3, aim: Vector3) -> float:
	var goal := ctx.pitch.target_goal(player.team)
	var dx := absf(goal.x - from.x)
	var dz := absf(from.z)
	var d: float = maxf(sqrt(dx * dx + dz * dz), 1.0)
	var half := ctx.pitch.goal_half_width
	var theta := absf(atan2(half - from.z, maxf(dx, 0.4)) - atan2(-half - from.z, maxf(dx, 0.4)))
	var angle_factor: float = pow(clampf(theta / 1.047, 0.0, 1.0), 0.7)
	# Calibrated against real shot data: about 0.26 from the penalty spot, 0.09
	# from the edge of the box, 0.03 from 25 m. Expected goals and expected
	# threat are compared directly when a player decides whether to shoot, so
	# getting their relative scale wrong means a team that walks it in or a team
	# that shoots from the halfway line.
	var base := 1.35 * exp(-0.11 * d) * angle_factor
	base *= lerpf(0.55, 1.35, player.attrs.finishing)
	base *= lerpf(1.0, 0.35, clampf(ctx.pressure_on(player), 0.0, 1.5) / 1.5)
	base *= lerpf(0.8, 1.05, player.attrs.composure)
	# And whether there is a shot there at all from where his body is pointing.
	# `SimTouch.shot` scales the strike by the same number, so the chance the
	# engine prices and the ball it then hits are the same event: a man with the
	# goal over his shoulder gets a scuffed poke, and the way to a real shot is to
	# turn first.
	base *= SimTouch.strike_scale(player, aim - from)
	# The two things the model was blind to, and only those two
	# (`docs/THE_FOOTBALL.md` 2). The trap this proposal names is double-counting:
	# `aim_sigma` prices skill, pressure, speed, distance, composure, facing and
	# fatigue, and four of those are already above -- so multiplying by execution
	# accuracy, which was the obvious fix, counts them twice. Body facing is done,
	# by the other route, through `strike_scale` a line up.
	#
	# What is left is a man shooting while running flat out, who cannot get his
	# body over it, and a man at the end of ninety minutes, whose strike has gone.
	# Neither appears anywhere else in this function.
	var running: float = SimConsts.horizontal_length(player.vel) / maxf(player.max_speed(), 0.1)
	base *= lerpf(1.0, SHOT_AT_PACE, clampf(running, 0.0, 1.0))
	base *= lerpf(SHOT_SPENT, 1.0, clampf(player.stamina, 0.0, 1.0))
	# Bodies in the way. A man mid-recovery is not one of them: a keeper who
	# has committed and a defender the cut has just left are on the ground or
	# facing the wrong way, and the moment they are is *the* moment to strike
	# -- it is what waiting for the right moment waits for, and until this the
	# model could not see it, so the number never rose and there was never a
	# reason not to shoot early.
	# Two populations. Inside `SimDuel.BLOCK_RANGE` a body throws itself at
	# the strike on the backlift, and the chance is the act's own
	# (`block_chance`, one function for the price and the block); beyond it a
	# body in the corridor sticks a leg out after his reaction, the old count.
	base *= SimDuel.block_survival(ctx, player, from, aim, SHOT_PRICED_SPEED)
	base *= pow(0.72, float(_shot_blockers(ctx, player, from, aim)))
	return clampf(base, 0.002, 0.92)


## The pace the block model prices a shot at before the power is chosen.
const SHOT_PRICED_SPEED := 22.0


## Bodies on a shot's corridor, the count `expected_goals` charges -- and, with
## a `bow`, the same count on the bent corridor, which is what the curled shot
## is priced by. Split out so the two paths cannot drift apart.
static func _shot_blockers(ctx: SimContext, player: SimPlayer, from: Vector3, aim: Vector3, bow: float = 0.0) -> int:
	var blockers := 0
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		# Inside lunge range he is `block_chance`'s, not a leg in the corridor.
		if o.on_pitch and o.recovery_ticks == 0 \
				and _near_segment(o.pos, from, aim, 1.1, bow) and o.dist_to(from) > SimDuel.BLOCK_RANGE:
			blockers += 1
	return blockers


## How far off his line the keeper has to be before there is anything to chip
## him over, or to knock the ball round.
const CHIP_KEEPER_OUT := 3.5
## What a pass into the box keeps of the receiver's own shot: he still has to
## take it and hit it. See the square-ball note in `_add_passes`.
const SQUARE_CONVERT := 0.6
## What a chip is worth at most. It is a finish that trades power for placement
## over a stranded man, not a better way to shoot.
const CHIP_CEILING := 0.6


## The chip, one of the three answers to the keeper's one-on-one: a keeper
## off his line is a goal with a man standing in front of it, and the answer is
## over him. Generated beside the driven shot, never instead of it; the softmax
## takes whichever the situation pays.
static func _add_chip(ctx: SimContext, player: SimPlayer, from: Vector3, goal: Vector3,
		distance: float, first_time: bool, tactics: SimTactics, restart: Vector3, loss: float) -> void:
	if distance < 7.0 or distance > 26.0:
		return
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	if keeper == null or not keeper.on_pitch:
		return
	var off_line := SimConsts.horizontal_length(goal - keeper.pos)
	if off_line < CHIP_KEEPER_OUT:
		return
	var quality := _chip_quality(ctx, player, from, goal, off_line)
	if quality < 0.02:
		return
	_note_rare(RARE_CHIP, false)
	_candidates.append({
		"action": Action.SHOOT,
		# Solved as a dropping arc: the aim is the grass just over the line, and
		# `SimTouch.shot` lofts it there. The keeper's save model still gets its
		# say from the forecast, which is what makes a bad chip a catch.
		"aim": Vector3(goal.x + ctx.pitch.attack_dir(player.team) * 0.8, 0.0, 0.0),
		"chip": true,
		"end": restart,
		"success": quality,
		"gain": 1.0,
		"loss": loss,
		"first_time": first_time,
		"bias": lerpf(0.75, 1.25, tactics.directness) * (0.6 if first_time else 1.0)
			* ctx.config.shot_appetite_at(quality),
		"power": 0.4,
	})
	_keep_factors()


## The chance a chip from here beats a keeper standing `off_line` metres out.
## Its own small model rather than `expected_goals` with the keeper deleted: the
## things that decide a chip -- touch, composure, and how much goal is behind
## the man -- are not the things that decide a drive.
static func _chip_quality(ctx: SimContext, player: SimPlayer, from: Vector3, goal: Vector3,
		off_line: float) -> float:
	var dx := absf(goal.x - from.x)
	var dz := absf(from.z)
	var d: float = maxf(sqrt(dx * dx + dz * dz), 1.0)
	var half := ctx.pitch.goal_half_width
	var theta := absf(atan2(half - from.z, maxf(dx, 0.4)) - atan2(-half - from.z, maxf(dx, 0.4)))
	var base: float = 0.9 * exp(-0.085 * d) * pow(clampf(theta / 1.047, 0.0, 1.0), 0.7)
	base *= lerpf(0.45, 1.1, player.attrs.technique)
	base *= lerpf(0.85, 1.05, player.attrs.composure)
	base *= lerpf(1.0, 0.45, clampf(ctx.pressure_on(player), 0.0, 1.5) / 1.5)
	# The whole point of the act: the further out he is, the more net is behind
	# him, and on his line there is nothing to chip over at all.
	base *= clampf((off_line - CHIP_KEEPER_OUT) / 6.0, 0.0, 1.0)
	base *= SimTouch.strike_scale(player, goal - from)
	# Only a body close to the striker can block a ball that leaves the ground.
	var blockers := 0
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if o.on_pitch and not o.is_keeper and o.dist_to(from) < 4.0 \
				and o.dist_to(from) > 0.8 and _near_segment(o.pos, from, goal, 1.1):
			blockers += 1
	base *= pow(0.72, float(blockers))
	return clampf(base, 0.0, CHIP_CEILING)


## A ball to feet is aimed a step off the marker, to the receiver's free side.
## The passer leads a run (`_lead_point`) and the receiver's first touch buys a
## better spot after it arrives; nothing put the ball itself on the safe side of
## a tight marker, so a marked man was served on the marker's toes. A stride, so
## it stays a ball to feet -- and it is priced from the shifted point, so
## `control_at_pass` and the lane see the same ball that gets struck.
const FREE_SIDE_STEP := 1.1
## How near the arrival point the marker has to be for the shift to be worth it.
const FREE_SIDE_RANGE := 4.5


static func _add_passes(ctx: SimContext, player: SimPlayer, uncontrolled: bool, regain: float) -> void:
	var tactics := ctx.tactics(player.team)
	# Straight after a regain the simple ball is worth more than it looks. Only
	# the ground pass is lifted: securing possession means finding a man, not
	# hitting the same forty-metre ball you would have looked for in settled
	# play, so the through ball and the lofted pass keep their standing prices.
	# One reading of the counter for both halves of it, rather than the same
	# function called twice a few lines apart.
	var on := break_on(ctx, player, regain)
	var secure: float = lerpf(1.0, 1.7, regain * (1.0 - on))
	var brk: float = lerpf(1.0, BREAK_BIAS, on)
	_note_break(on, turnover_exposure(ctx, SimConsts.other_team(player.team)), secure, regain)
	var from := ctx.ball.pos
	var attack_dir := ctx.pitch.attack_dir(player.team)
	# Nobody plays a measured pass off a ball that is still bouncing. This is
	# what makes a first touch the usual answer to a ball arriving at pace.
	var off_balance: float = 1.0
	if uncontrolled:
		off_balance = lerpf(0.3, 0.7, player.attrs.first_touch * player.attrs.technique)
	_set_worth = 0.0
	_open_behind_gates(ctx, player)

	for mate_id in _shortlist(ctx, player, from):
		var mate := ctx.players[mate_id]
		var believed := SimPerception.believed_pos(ctx, player, mate)
		# A man stood beyond the line is seen before he is priced. Only the
		# through ball used to ask, so a striker holding the shoulder a stride
		# too far got the ball to feet at full confidence and the flag went up
		# when he took it. Judged off the passer's picture of him, so a line
		# that stepped up since he last looked is still a mistake he can make.
		var flagged := SimReferee.would_be_offside(ctx, player.team, believed)
		var raw_distance := SimConsts.horizontal_length(believed - from)
		# How long a ball he can hit this way at all. A pass played across or
		# behind the body is not a shorter version of the same pass, it is a
		# different act with a fraction of the range -- see `SimTouch.strike_scale`,
		# which `ground_pass` and `lofted_pass` clamp the struck ball to. Gating the
		# candidate on the same number is what stops the engine scoring a
		# forty-metre diagonal off a man's back foot, choosing it, and then playing
		# a fifteen-metre one. The way to the long ball is to turn and hit it.
		var ground_reach := SimTouch.strike_range(player, believed - from, MAX_GROUND_PASS)
		var air_reach := SimTouch.strike_range(player, believed - from, MAX_LOFTED_PASS)

		# A ball he cannot hit only because of where his body points is not
		# refused, it is deferred: the setting touch is the act that buys it.
		# Remember the best of them for `_add_set_touch`.
		if (raw_distance > ground_reach and raw_distance <= MAX_GROUND_PASS) \
				or (raw_distance > air_reach and raw_distance <= MAX_LOFTED_PASS):
			var deferred := ctx.value.xt_at(player.team, believed, ctx.pitch)
			if deferred > _set_worth:
				_set_worth = deferred
				_set_point = believed

		# --- Ground pass to feet -------------------------------------------
		if raw_distance <= ground_reach:
			var pace := arrival_pace(raw_distance, tactics)
			var travel := ctx.ballistics.ground_travel_time(
				raw_distance, ctx.ballistics.ground_pass_speed(raw_distance, pace, ctx.env), ctx.env)
			var lead := _keep_in_play(ctx, _lead_point(ctx, mate, believed, travel))
			# A ground pass does not go in behind. `_lead_point` follows a
			# committed run wherever it goes, and a run in behind took the
			# ordinary pass past the line with it: the same ball as the through
			# ball beside it, struck at pass-to-feet weight -- the slow ball
			# into the channel with no chance of beating anyone (owner,
			# 2026-09-01), and the safer-priced twin that kept the real one
			# from ever scoring best. The ball in behind is the through ball's
			# act, and the loft's over the top; this one stops at the line.
			# But never behind where he already stands: a man level with or
			# beyond the line still takes a ball to his feet -- the first cut
			# clamped those back behind him and aimed passes at nobody. Only
			# the *lead* in behind is the through ball's.
			var behind_line := SimReferee.believed_offside_line(ctx, player) * attack_dir
			var lead_stop: float = maxf(behind_line - BEHIND_BREAK, believed.x * attack_dir)
			if lead.x * attack_dir > lead_stop:
				lead.x = lead_stop * attack_dir
				lead = _keep_in_play(ctx, lead)
			# Aiming ahead of a man lengthens the pass, so the flight time it was
			# aimed with is not the flight time it has. One correction is enough,
			# and without it a ball played into a run is judged against a shorter
			# journey than it makes -- which makes the runner look late for a ball
			# that would have reached him.
			var lead_distance := SimConsts.horizontal_length(lead - from)
			travel = ctx.ballistics.ground_travel_time(
				lead_distance, ctx.ballistics.ground_pass_speed(lead_distance, pace, ctx.env), ctx.env)
			# A ball put where a man is going is a ball into space, and arrival
			# there is a race rather than a delivery to a stationary target.
			# A ball put where a man is going is a ball into space -- unless he is
			# going to be standing there before it lands. Then it is a ball to
			# feet that happens to be aimed a few metres off him, and the contest
			# at the end is the one `AIMED_STEP_IN` prices: whoever else reaches
			# the spot has to take it off a man already on it. Priced as a race,
			# the arrival floor levelled him with any defender who could get
			# there by the time the ball did, and a full-back seven metres from
			# the touchline with his marker seven metres off read `space` 0.46.
			# `./run.sh control` row C is the same finding from the bench side:
			# a sprinting receiver at 0.39 to 0.73 while 88 to 100% arrived.
			var run_gap := SimConsts.horizontal_length(lead - believed)
			var there_first: bool = SimValueField.time_to_arrive(mate, lead, mate.reaction) \
				+ THERE_FIRST_MARGIN < travel
			var into_space := run_gap > 2.0 and not there_first
			# The ball to feet, aimed off the marker: a step to the free side.
			if not into_space:
				var marker := ctx.nearest_to(lead, SimConsts.other_team(player.team))
				if marker != null and not marker.is_keeper and marker.dist_to(lead) < FREE_SIDE_RANGE:
					var free := SimConsts.horizontal(lead - SimPerception.believed_pos(ctx, player, marker))
					if free.length_squared() > 1e-6:
						lead = _keep_in_play(ctx, lead + free.normalized() * FREE_SIDE_STEP)
						lead_distance = SimConsts.horizontal_length(lead - from)
						travel = ctx.ballistics.ground_travel_time(
							lead_distance, ctx.ballistics.ground_pass_speed(lead_distance, pace, ctx.env), ctx.env)
			var success := _pass_success(ctx, player, from, lead, travel, mate, into_space)
			if flagged:
				success *= OFFSIDE_DISCOUNT
			# The layoff. `off_balance` prices deciding while the ball still moves,
			# and it is the right price for a ball that has to be forced somewhere
			# new -- but a ball helped back the way it came is played with its own
			# pace, and charging it the full rate is why every target man killed
			# the ball and turned into his marker. The share
			# is read off the same function the strike pays its error through, so
			# the ball priced here is the ball that gets hit. The bounce is only
			# worth preferring when the man it goes to is facing play; to a man
			# with his own back to it, it has just moved the problem.
			var ob := off_balance
			var layoff := 1.0
			if uncontrolled:
				var share := SimTouch.redirect_share(ctx.ball.vel, lead - from)
				ob = lerpf(LAYOFF_OFF_BALANCE, off_balance, share)
				if share < LAYOFF_SHARE and mate.heading_dir().x * attack_dir > 0.1:
					layoff = LAYOFF_BIAS
			var xt := ctx.value.xt_at(player.team, lead, ctx.pitch)
			var focus := tactics.focus_at(lead.z, ctx.pitch)
			var gain := xt * focus
			var arrival := _arrival_gain(ctx, player.team, lead, believed, mate, travel)
			gain += arrival
			# The square ball across the face, and the cutback. A pass to a man
			# in the box is worth what *his* shot is, and the map cannot say so:
			# expected threat prices the grass, and the grass beside an open goal
			# reads much like the grass beside a defended one. Only asked inside
			# the area, where the difference is the whole answer to the keeper's
			# one-on-one. (Folds into `gain` before the factors are noted, so the
			# chain's focus column is approximate for these rare candidates.)
			if ctx.pitch.in_opponent_penalty_area(player.team, lead):
				# Carries the appetite for the same reason `_carry_shot_gain`
				# does: the shot this ball buys competes with the shot the
				# passer would take himself, and only one of them was being
				# multiplied by the fit.
				var square_xg := expected_goals(ctx, mate, lead,
					ctx.pitch.target_goal(player.team))
				var square: float = square_xg * SQUARE_CONVERT \
					* ctx.config.shot_appetite_at(square_xg)
				gain = maxf(gain, square)
			var length_bias := 1.0 / (1.0 + raw_distance * 0.21)
			var call := _call_bias(ctx, mate)
			var give_go := _give_and_go_bias(ctx, player, mate_id)
			var touch := receiver_touch(mate)
			_note_factor(SimAblation.F_FOCUS, gain - arrival - xt)
			_note_factor(SimAblation.F_ARRIVAL, arrival)
			_note_factor(SimAblation.F_OFF_BALANCE, ob)
			_note_factor(SimAblation.F_RETENTION, tactics.retention_bias())
			_note_factor(SimAblation.F_LENGTH, length_bias)
			_note_factor(SimAblation.F_SECURE, secure)
			_note_factor(SimAblation.F_CALL, call)
			_note_factor(SimAblation.F_GIVE_GO, give_go)
			_note_factor(SimAblation.F_TOUCH, touch)
			_candidates.append({
				"action": Action.GROUND_PASS,
				"target": mate_id,
				"point": lead,
				"end": lead,
				"first_time": uncontrolled,
				"success": success * ob,
				# Read where the ball is going and nowhere else. The floor that
				# used to be here -- worth at least 85% of the grass it left --
				# handed the ball played backwards the value of the position it
				# was giving up, which is the option this whole section exists to
				# price honestly.
				"gain": gain,
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lead, ctx.pitch),
				"pace": pace,
				# Football's pass-length distribution is heavily short. Without
				# this the engine plays a Hollywood ball every time.
				"bias": tactics.retention_bias() * length_bias * secure * call * give_go * touch * layoff,
			})
			_keep_parts()
			_keep_factors()

			# --- The same ball, driven -------------------------------------
			#
			# Offered beside the roller, never instead of it: a footballer chooses
			# between the two and the softmax is where that choice belongs. Only
			# once the ball is long enough to leave the floor at all
			# (`SimBallistics.DRIVE_FROM`), because below that they are the same
			# strike and the engine would be offering one act twice.
			if raw_distance >= SimBallistics.DRIVE_FROM:
				# Capped at `arrival_pace`'s own ceiling, in the m/s the whole
				# expression is in. It was `minf(..., 1.0)` from the day the
				# driven ball landed -- a normalized cap typed into a
				# real-units field -- so every driven ball arrived at one
				# metre a second, softer than the roller beside it, the 1.9
				# was dead code, and under ~24 m the launch never reached
				# `DRIVE_FROM`: the ball this block priced as airborne
				# (`DRIVEN_LANE`) and taxed as hot (`DRIVEN_TOUCH`) was a
				# roller arriving dead. Found by the bent lane, which needed
				# the hops that were not there (`tools/_curl_probe.gd`).
				var d_pace: float = minf(pace * DRIVEN_PACE, 12.0)
				var d_speed := ctx.ballistics.ground_pass_speed(lead_distance, d_pace, ctx.env)
				var d_travel := ctx.ballistics.ground_travel_time(lead_distance, d_speed, ctx.env)
				# The bend. Every driven ball carries its foot's bend as shape
				# (`SimTouch.pass_shape_curl`), so the plain driven candidate is
				# priced on that bowed path and not on the chord -- the ball the
				# model sees is the ball that is struck. The *meant* bend is a
				# variant *inside* the same candidate, never a third one beside
				# it -- the cross's whipped-and-fitted precedent; a
				# near-duplicate reads to the softmax as evidence for the act.
				# The foot picks the side (`curl_for`'s sign, off the same
				# comparison the strike is charged by), so what is chosen here
				# is whether, never which way. Offered only when the lifted,
				# whipped ball's lane is a real improvement on the shape's,
				# priced against the path the ball actually takes.
				var curl := 0.0
				var bow := 0.0
				var trivela := false
				var lane_tail: float = LANE_TAIL if into_space else FEET_TAIL
				if SimBallistics.drive_loft(d_speed) > 0.0:
					var meant := SimTouch.pass_shape_curl(player, lead - from)
					bow = SimBallistics.curl_bow(meant, d_speed, lead_distance,
						SimBallistics.DRIVEN_BOW_SHARE)
					var b := SimBallistics.curl_bow(meant, d_speed, lead_distance,
						SimBallistics.BEND_BOW_SHARE)
					var lane_straight := _lane_survival(ctx, player, from, lead, d_travel,
						lane_tail, -1, bow)
					var lane_bent := _lane_survival(ctx, player, from, lead, d_travel, lane_tail, -1, b)
					var straight_buy := maxf(lerpf(lane_straight, 1.0, DRIVEN_LANE), 0.001)
					if lane_bent >= lane_straight + CURL_MIN:
						curl = meant
						bow = b
						_note_rare(RARE_BEND, false)
						# What the bend is worth to `success`: the exact
						# multiplier the lane term gains from it, after the
						# `DRIVEN_LANE` buy-back both lanes get, so `--ablate`
						# can take the bend back out.
						_note_factor(SimAblation.F_CURL,
							lerpf(lane_bent, 1.0, DRIVEN_LANE) / straight_buy)
					else:
						# The trivela: when the game is closed on the side his
						# foot bends and open on the other, the outside of the
						# boot is the fallback -- flipped sign, control taxed.
						var lane_flip := _lane_survival(ctx, player, from, lead, d_travel,
							lane_tail, -1, -b)
						if lane_flip >= lane_straight + CURL_MIN:
							curl = -meant
							bow = -b
							trivela = true
							_note_rare(RARE_TRIVELA, false)
							_note_factor(SimAblation.F_CURL,
								lerpf(lane_flip, 1.0, DRIVEN_LANE) / straight_buy
								* TRIVELA_CONTROL)
				var d_success := _pass_success(ctx, player, from, lead, d_travel, mate,
					into_space, true, bow)
				if trivela:
					d_success *= TRIVELA_CONTROL
				if flagged:
					d_success *= OFFSIDE_DISCOUNT
				var d_arrival := _arrival_gain(ctx, player.team, lead, believed, mate, d_travel)
				var d_gain: float = xt * focus + d_arrival
				if ctx.pitch.in_opponent_penalty_area(player.team, lead):
					var d_xg := expected_goals(ctx, mate, lead,
						ctx.pitch.target_goal(player.team))
					d_gain = maxf(d_gain, d_xg * SQUARE_CONVERT
						* ctx.config.shot_appetite_at(d_xg))
				_note_factor(SimAblation.F_FOCUS, d_gain - d_arrival - xt)
				_note_factor(SimAblation.F_ARRIVAL, d_arrival)
				_note_factor(SimAblation.F_OFF_BALANCE, ob)
				_note_factor(SimAblation.F_RETENTION, tactics.retention_bias())
				_note_factor(SimAblation.F_LENGTH, length_bias)
				_note_factor(SimAblation.F_SECURE, secure)
				_note_factor(SimAblation.F_CALL, call)
				_note_factor(SimAblation.F_TOUCH, touch * DRIVEN_TOUCH)
				var driven_ball := {
					"action": Action.GROUND_PASS,
					"target": mate_id,
					"point": lead,
					"end": lead,
					"first_time": uncontrolled,
					"success": d_success * ob,
					"gain": d_gain,
					"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lead, ctx.pitch),
					"pace": d_pace,
					# The receiver pays for it: a ball arriving at that pace is a
					# harder first touch, and `receiver_touch` is where the engine
					# already prices exactly that about a man.
					"bias": tactics.retention_bias() * length_bias * secure * call
						* give_go * touch * DRIVEN_TOUCH * layoff,
				}
				if curl != 0.0:
					driven_ball["curl"] = curl
					if trivela:
						driven_ball["trivela"] = true
				_candidates.append(driven_ball)
				_keep_parts()
				_keep_factors()

		# --- Through ball in behind ----------------------------------------
		# Only worth considering for someone actually running in behind. A
		# through ball to a stationary midfielder is just a bad pass.
		var running_on: float = mate.vel.x * attack_dir
		# Role is the wrong test on its own, and it was the reason a through ball
		# was generated and then never chosen: it asks who is *usually* the man in
		# behind rather than who is going right now. A midfielder timing a run
		# past the last defender is exactly the pass this candidate is for, and
		# `making_run` is the movement layer saying so.
		var runner := SimRole.is_attacking(mate.role) or mate.making_run
		# Each gate named once and read twice: by the candidate below, and by the
		# tally that says which of them refuses a man who is making the run.
		var near_enough := raw_distance < 45.0
		# And the velocity test is the same proxy the role test was, one gate along.
		# It asks whether he is *already* sprinting, and a man who has just set off
		# is not: he is a stride into a run he has committed to for the next three
		# and a half seconds, which is exactly the moment the ball wants playing.
		# Measured over two seeds, a fifth of all runs past the last defender were
		# refused a candidate here while the run was under way — the ball can only
		# be offered once he is at speed, by which time he is past the line and it
		# has to beat him to a spot he is already arriving at.
		#
		# So the committed run answers for itself and the velocity stays as the
		# test for everybody else: a striker drifting onto the shoulder without an
		# intent is still a man worth playing in behind.
		# And the same argument once more, for every other committed run.
		#
		# `is_running_in_behind` answers for one intent. A man committed to a run
		# into the box, or a man a pattern has sent, is equally a man who is going
		# somewhere forward — and equally likely to be a stride into it with a
		# velocity that has not caught up. `moving_on` refused 45% of every man
		# ahead of the ball, the largest single gate in front of the ball in
		# behind, and it was reading the one thing that lags what he has decided.
		#
		# `destination_for` is the layer saying where he is going, and since it
		# reads `movement_override` it answers for the pattern runner too. Forward
		# of him by three metres is the test, so a man drifting square or checking
		# back is still refused, which is what the gate is for.
		var going_to := SimOffBall.destination_for(ctx, mate)
		var committed_on := not is_inf(going_to.x) \
			and (going_to.x - mate.pos.x) * attack_dir > 3.0
		var moving_on := running_on > 1.2 or committed_on \
			or SimOffBall.is_running_in_behind(ctx, mate)
		_note_behind_gate(mate_id, BEHIND_FAR if not near_enough
			else BEHIND_STILL if not moving_on
			else BEHIND_ROLE if not runner
			else BEHIND_REACH)
		if not mate.is_keeper and near_enough and moving_on and runner:
			# Where he is going, and a projection down the pitch only as the guess
			# made in its absence. Aiming at the guess is how a through ball gets
			# played to a yard the runner was never heading for.
			var going := SimOffBall.destination_for(ctx, mate)
			if not SimOffBall.is_running_in_behind(ctx, mate) or is_inf(going.x):
				going = believed + mate.vel * 0.4 \
					+ Vector3(attack_dir, 0.0, 0.0) * lerpf(7.0, 16.0, tactics.directness)
			var target := _behind_aim(ctx, player, mate, from, believed, going, tactics)
			# A ball in behind has to go in behind somebody, and nothing here ever
			# asked. The gates in front of this are all about the receiver -- is he
			# a runner, is he moving, is he close enough -- and none of them looks
			# at the defence he is supposed to be running past, so the candidate
			# fired for any attacking man drifting forward in midfield. A through
			# ball to a man who is not going beyond anyone is a forward pass, which
			# the ground pass beside it already offers, at a weight suited to feet
			# and priced as the safer ball it is. That is most of why one pass in
			# seven in the match was a through ball.
			#
			# The line is the one the *passer* believes in, so playing a man in
			# against a line that has stepped up since he last looked is a mistake
			# he is allowed to make -- the same belief `would_be_offside` is judged
			# against a few lines below.
			var line := SimReferee.believed_offside_line(ctx, player) * attack_dir
			var t_distance := SimConsts.horizontal_length(target - from)
			if target.x * attack_dir < line - BEHIND_BREAK:
				_note_behind_gate(mate_id, BEHIND_SHORT)
			elif t_distance <= 4.0 or t_distance > SimTouch.strike_range(player, target - from, MAX_GROUND_PASS + 6.0):
				# Refused on range, and the distance is filed: the lofted ball
				# over the top serves 24-55 m, so a refusal inside that band is
				# a man another act can still reach.
				behind_reach_sum += t_distance
				behind_reach_n += 1
			else:
				_note_behind_gate(mate_id, BEHIND_OFFERED)
				var t_pace := behind_pace(t_distance, tactics, mate)
				var t_speed := ctx.ballistics.ground_pass_speed(t_distance, t_pace, ctx.env)
				var t_travel := ctx.ballistics.ground_travel_time(t_distance, t_speed, ctx.env)
				# A ball the runner beats to the spot is not a ball he chases.
				# `BEHIND_ARRIVE` slows the strike so a chasing man can close on
				# it, and on an aim clamped inside the meeting point that
				# slowness is the ball that crawls into his back (owner,
				# 2026-09-01). When he is there first by a stride it is struck
				# as a pass to feet at the spot instead.
				if SimValueField.reach_in(mate, target - believed, t_travel) \
						- SimConsts.horizontal_length(target - believed) > BEHIND_EARLY:
					# Firm, not fired: capped at the runner's own top speed. The
					# uncapped arrival read 11-12 m/s and the owner called it
					# way too hard in the same breath as the slow ones.
					t_pace = minf(arrival_pace(t_distance, tactics), mate.max_speed())
					t_speed = ctx.ballistics.ground_pass_speed(t_distance, t_pace, ctx.env)
					t_travel = ctx.ballistics.ground_travel_time(t_distance, t_speed, ctx.env)
				# The runner beating everyone there is the whole question, and it
				# is asked once. Asking it twice -- once statically and once in
				# time -- squared a term that is small for every ball worth
				# playing in behind, and no through ball was ever chosen in a
				# match: 274 of them generated on one ten-minute seed, the best
				# at a 0.39 chance of arriving, and not one selected.
				var t_success := _pass_success(ctx, player, from, target, t_travel, mate, true)
				# Offside is judged where the *receiver* stands when the ball is
				# struck, not where it is going -- that is the entire point of a
				# through ball, and testing the target instead flagged every one
				# of them, because a ball played in behind lands in behind by
				# definition. Judged off the passer's belief, so a ball played to
				# a man who has already gone is a mistake he can make.
				if flagged:
					t_success *= OFFSIDE_DISCOUNT
				# The one act whose whole point is the line, so the one place the
				# single-step map is corrected. `docs/THE_FOOTBALL.md` 8b.
				var t_xt := ctx.value.xt_at(player.team, target, ctx.pitch) \
					* SimValueField.line_broken(ctx, player.team, target, ctx.pitch)
				var t_focus := tactics.focus_at(target.z, ctx.pitch)
				var t_arrival := _arrival_gain(ctx, player.team, target, believed, mate, t_travel)
				var t_call := _call_bias(ctx, mate)
				var t_length := behind_length_bias(t_distance)
				var t_touch := receiver_touch(mate)
				_note_factor(SimAblation.F_FOCUS, t_xt * t_focus - t_xt)
				_note_factor(SimAblation.F_ARRIVAL, t_arrival)
				_note_factor(SimAblation.F_OFF_BALANCE, off_balance)
				_note_factor(SimAblation.F_DIRECT, tactics.direct_bias())
				_note_factor(SimAblation.F_LENGTH, t_length)
				_note_factor(SimAblation.F_CALL, t_call)
				_note_factor(SimAblation.F_BREAK, brk)
				_note_factor(SimAblation.F_TOUCH, t_touch)
				_candidates.append({
					"action": Action.THROUGH_BALL,
					"target": mate_id,
					"point": target,
					"end": target,
					"first_time": uncontrolled,
					"success": t_success * off_balance,
					"gain": t_xt * t_focus + t_arrival,
					"loss": ctx.value.xt_at(SimConsts.other_team(player.team), target, ctx.pitch),
					# The pace it was scored at. This was a flat 6.0 while
					# `t_travel` -- and through it `t_success` and the arrival
					# gain -- were computed from `t_pace`, so the ball that got
					# struck was not the ball the race had been judged on. The
					# same mismatch the carry had between its scored touch and
					# its played one, in the other half of the decision layer.
					"pace": t_pace,
					"bias": tactics.direct_bias() * t_length * t_call * brk * t_touch,
				})
				_keep_parts()
				_keep_factors()

		# --- Lofted pass or cross ------------------------------------------
		# A ball in the air is a choice, not a default: only over a distance
		# that a ground pass cannot cover, or into the box.
		var box_target := ctx.pitch.in_opponent_penalty_area(player.team, believed)
		if raw_distance <= air_reach and (raw_distance > LOFTED_FROM or (box_target and raw_distance > 12.0)):
			# Flight time, which is the whole character of a ball in the air: ask
			# for a long one and the solver lobs it, ask for a short one and it
			# drives it. `SimTouch.lofted_flight` owns the rule and its own note
			# has the knee it sits on -- it was a second copy here and a third in
			# `_add_crosses`, and the accuracy model now needs the same number to
			# work out the angle the ball leaves at.
			var flight: float = SimTouch.lofted_flight(raw_distance)
			# Where he is going, not where he is pointing. This was
			# `believed + mate.vel * flight * 0.55` -- dead reckoning on the
			# velocity he happens to have, which is the exact defect `_lead_point`
			# was written for and which the ground pass and the through ball have
			# both been fixed of. It fails in the case a ball over the top exists
			# for: a man who has committed to a run has not accelerated into it
			# yet, so his velocity is small and the ball is dropped on his head.
			# Measured, the lofted ball was aimed 4.3 m in front of its receiver
			# against 3.1 m for a square pass to feet -- a ball over the top that
			# was not over anything.
			#
			# `_lead_point` falls back to the same dead reckoning when he has no
			# destination, so the man who has committed to nothing is unaffected
			# and this only moves the ball that was worth moving.
			var lofted_target := _keep_in_play(ctx, _lead_point(ctx, mate, believed, flight))
			lofted_target.y = 0.0
			var lofted_success := _lofted_success(ctx, player, lofted_target, flight, mate)
			if flagged:
				lofted_success *= OFFSIDE_DISCOUNT
			# The lofted ball over the top is the other act whose value is the line
			# it clears, so it gets the same correction as the through ball.
			# `docs/THE_FOOTBALL.md` 8b.
			var l_xt := ctx.value.xt_at(player.team, lofted_target, ctx.pitch)
			var l_focus := tactics.focus_at(lofted_target.z, ctx.pitch)
			var l_length := 1.0 / (1.0 + raw_distance * 0.055)
			var l_pattern := SimPatterns.pass_bias(ctx, player, mate_id, lofted_target)
			var l_call := _call_bias(ctx, mate)
			var l_break: float = brk if (lofted_target - from).x * attack_dir > 4.0 else 1.0
			var l_switch := _switch_lift(ctx, player, mate, believed, from)
			# The map value the focus actually added, not the multiplier.
			_note_factor(SimAblation.F_FOCUS, l_xt * l_focus - l_xt)
			_note_factor(SimAblation.F_OFF_BALANCE, off_balance)
			_note_factor(SimAblation.F_DIRECT, tactics.direct_bias())
			_note_factor(SimAblation.F_LOFTED, LOFTED_BIAS * l_switch)
			_note_factor(SimAblation.F_LENGTH, l_length)
			_note_factor(SimAblation.F_PATTERN, l_pattern)
			_note_factor(SimAblation.F_CALL, l_call)
			_note_factor(SimAblation.F_BREAK, l_break)
			# Not a cross, however deep it lands. The ball into the area is
			# `_add_crosses` and only that: one act generated in one place, priced
			# with one prior. This branch used to re-label itself a cross when its
			# target happened to be in the box, so the same act existed twice with
			# different biases depending on which function had built it.
			_candidates.append({
				"action": Action.LOFTED_PASS,
				"target": mate_id,
				"point": lofted_target,
				"end": lofted_target,
				"first_time": uncontrolled,
				"success": lofted_success * off_balance,
				"gain": l_xt * l_focus,
				"loss": ctx.value.xt_at(SimConsts.other_team(player.team), lofted_target, ctx.pitch),
				"flight": flight,
				# `l_break` is only the ball that actually goes somewhere: a lofted
				# ball played square or back is not a counter, it is a reset.
				"bias": tactics.direct_bias() * LOFTED_BIAS * l_switch * l_length
					* l_pattern * l_call * l_break,
			})
			_keep_parts()
			_keep_factors()
	_close_behind_gates()


## How wide he has to be before he is looking to cross, as a fraction of the half
## width. `tools/diagnostics.gd` `CROSS_WIDE` is the same number, so the chain's
## population and the candidate are drawn on one line.
const CROSS_WIDE := 0.45
## And how far the ball has to travel to be a cross rather than a pass.
##
## **Where the cross now stands, measured at n=20 twice in one day.** Of 1791
## wide-in-their-half situations a cross was offered in 211 (11.8%), scored best in
## 85, was played 83 times, and **19 of those reached the penalty area (22.9%)**,
## from which 17 shots and 6 goals. Against the morning's figures the played count
## went 46 to 83 and the goals 2 to 6, so the chain works and carries the box work.
##
## Two links are still thin and they are different problems. The offer rate has not
## moved at all (11.7% to 11.8%) and is a generation question. The last one is
## **delivery**: a cross reaches the area under a quarter of the time, and the
## reason is `SimTouch.long_sigma`, whose range error at 20-40 m was *measured
## against the integrator* by `./run.sh strike` and is the authority. So it is not
## a bug to be fixed here -- it is either a physical statement the engine should
## keep and the aim points should respect, or a tuning-freeze decision
## (`PLAN.md` §11.1.1). It is not `crossing`: that attribute is read, in
## `SimTouch` and in `aim_sigma` both.
const CROSS_FROM := 12.0
## How late a man can be for the ball and still be attacking it. He does not have
## to be standing there when it is struck -- that was the whole defect -- but a
## cross to somebody who arrives a second and a half after it lands is a cross to
## nobody, and naming him as the target would put the referee's offside check on a
## man who was never in the move.
const CROSS_LATE := 0.8
## The lift a ball into the area carries over the same ball anywhere else.
##
## And it is the whole prior on the act, which is why `LOFTED_BIAS` and the
## length penalty are not applied to it. Both of those exist to stop the engine
## hoofing it: `LOFTED_BIAS` is 0.30 on any ball in the air and the length term
## is another 0.31 over forty metres, so a cross generated through the lofted
## branch had the largest gain in the game -- 0.16 against a winning option's
## 0.017 -- multiplied by about a tenth, and lost every time. A cross is long and
## in the air by definition; charging it for both is charging it for being
## itself. Whether anybody wins the ball at the far end is a question `success`
## already answers, and answers honestly, because the target is a fixed point in
## the six-yard area rather than a man's feet.
const CROSS_BIAS := 1.15


## The ball into the box, aimed at the grass rather than at a shirt.
##
## The one candidate in the engine that is not generated from a teammate, and it
## has to be. `_add_passes` builds every ball by walking the shortlist and asking
## what could be played to that man, so a cross could only exist where somebody
## was already standing in the penalty area -- and the chain measured what that
## costs: of 313 wide moments in the opponent's half across three seeds, **11%
## produced a cross candidate at all**, seven were played in thirty minutes of
## football and none of them produced a goal. Raising `LOFTED_BIAS` cannot reach
## that, because a value knob cannot pick an option that was never on the list.
##
## Football does it the other way round. The near post, the penalty spot and the
## far post are the ball, and who attacks it is settled after it is in the air.
## So the targets here are fixed points off the goal, the receiver named on each
## is whoever can be there when it lands, and `_lofted_success` prices the
## arrival exactly as it does for any other ball in the air -- which is what says
## whether crossing into three defenders is worth anything.
## How deep the carrier has to be for the ball into the box to be a pull-back
## rather than a cross: inside the last `PULLBACK_DEEP` metres, which is the byline
## end of the penalty area and beyond.
const PULLBACK_DEEP := 12.0
## And where it is cut back to, measured out from the goal line. The penalty spot
## is 11 m; a pull-back is played behind the defence's eyeline, which is further
## out than that and is the whole point of the act.
const PULLBACK_BACK := 13.5
## How late a man can arrive and still be the target. Longer than `CROSS_LATE`,
## because a ball rolling across the face is available for longer than one
## dropping out of the air, which is the other half of why the act exists.
const PULLBACK_LATE := 1.1


## The pull-back: the ball cut back along the floor from the byline.
##
## `docs/THE_FOOTBALL.md` 29, and it is a different act from the three balls
## `_add_crosses` offers rather than a fourth target for them. Those are lofted
## into the six-yard area and contested in the air, and the whole reason a
## footballer goes to the byline instead is to take the keeper and the back line
## out of the picture entirely: the ball goes *backwards* to a man arriving at the
## edge of the area, facing goal, with every defender turned the wrong way and
## nobody able to attack the ball because it is rolling away from them.
##
## Three things follow from that and none of them is true of a cross. It is struck
## along the ground, so `_lofted_success` is the wrong model and the ordinary pass
## one is right. Its target is behind the ball, so the `xt` of the point
## understates it badly — the same blindness the square ball in `_add_passes`
## already corrects with `SQUARE_CONVERT`, and it is corrected the same way here.
## And the man it is for has longer to arrive, because a ball on the grass waits.
static func _add_pullback(ctx: SimContext, player: SimPlayer, uncontrolled: bool) -> void:
	var from := ctx.ball.pos
	var attack_dir := ctx.pitch.attack_dir(player.team)
	var goal := ctx.pitch.target_goal(player.team)
	# Deep, and wide. Deeper than a cross by construction: level with the six-yard
	# box or beyond it, which is where the angle for a shot has gone and the angle
	# for this one has arrived.
	if absf(goal.x - from.x) > PULLBACK_DEEP:
		return
	if absf(from.z) <= ctx.pitch.half_width * CROSS_WIDE:
		return
	var tactics := ctx.tactics(player.team)
	# Cut back to the edge of the area, on the ball's own side and through the
	# middle. Two points rather than three: the far corner of the area is a
	# different pass and `_add_passes` already offers it.
	var side: float = signf(from.z)
	if side == 0.0:
		side = 1.0
	var targets := [
		Vector3(goal.x - attack_dir * PULLBACK_BACK, 0.0, 0.0),
		Vector3(goal.x - attack_dir * PULLBACK_BACK, 0.0, side * ctx.pitch.penalty_half_width * 0.45),
	]
	# **Both points go on the list, and the score picks between them.** This used
	# to weigh them on `expected_goals` alone and append only the winner, which
	# reads as a value judgement and is not one: the central point is worth more
	# from anywhere, so it won every time, and whether the ball could actually get
	# there was then asked by `_pass_success` of the only option left. Measured on
	# `cross-pullback` seed 1, which is the scenario written for this act: the
	# point it offered was 21.4 m with a lane of **0.190** -- one defender 0.8 m
	# off the line of it -- and the point it threw away was 14.6 m with a lane of
	# **0.967**. The open cut-back was never a candidate, so no weight on the act
	# and no tuning of the lane could reach it. `docs/DIAGNOSTICS.md`: a value knob
	# cannot create an option that was never generated.
	#
	# Offering both is not offering more pull-backs. `_pass_success` prices the
	# blocked one at what it is worth and the softmax spends its weight on
	# whichever is open, which is the choice the footballer is making.
	var offered := false
	for point in targets:
		var distance := SimConsts.horizontal_length(point - from)
		if distance < 6.0 or distance > SimTouch.strike_range(player, point - from, MAX_GROUND_PASS):
			continue
		var pace := arrival_pace(distance, tactics)
		var travel := ctx.ballistics.ground_travel_time(
			distance, ctx.ballistics.ground_pass_speed(distance, pace, ctx.env), ctx.env)
		# Who is arriving, not who is standing there — the same question the cross
		# asks, with a longer window because the ball keeps rolling.
		var mate := -1
		var soonest := INF
		for mid in ctx.teammate_ids(player.team):
			if mid == player.id:
				continue
			var m := ctx.players[mid]
			if not m.on_pitch or m.is_keeper:
				continue
			if SimValueField.time_to_arrive(m, point, SimValueField.reaction_of(m)) \
					> travel + PULLBACK_LATE:
				continue
			var t_arrive := SimValueField.time_to_arrive(m, point, SimValueField.reaction_of(m))
			if t_arrive < soonest:
				soonest = t_arrive
				mate = mid
		if mate < 0:
			continue
		# The same man can be the soonest to both points. Cutting the ball back to
		# where he is not going is not a second option, it is the same one twice,
		# and the softmax would read the pair as evidence for the act.
		if _has_pullback_to(mate):
			continue
		var worth := expected_goals(ctx, ctx.players[mate], point, goal)
		_emit_pullback(ctx, player, uncontrolled, tactics, from, point, mate, worth, travel, pace)
		offered = true
	# Once a decision, not once a point: the ratio this feeds is how often the act
	# was on the list at all, and counting the same moment twice would move it
	# without anything about the football changing.
	if offered:
		_note_rare(RARE_PULLBACK, false)


## Whether a pull-back to this man is already on the list, by the mark
## `_emit_pullback` leaves.
static func _has_pullback_to(mate: int) -> bool:
	for c in _candidates:
		if c.get("pullback", false) and int(c.get("target", -1)) == mate:
			return true
	return false


## One pull-back, priced and appended. Split out of `_add_pullback` when the two
## target points stopped being a choice made before the scoring and became two
## candidates the scoring chooses between.
static func _emit_pullback(ctx: SimContext, player: SimPlayer, uncontrolled: bool,
		tactics: SimTactics, from: Vector3, point: Vector3, best_mate: int,
		best_worth: float, best_travel: float, pace: float) -> void:
	var mate: SimPlayer = ctx.players[best_mate]
	# Offside is judged where the receiver stands, like every other ball, and a
	# man cut back to is behind the ball and so onside by construction — but he is
	# judged rather than assumed, because the passer's belief can be wrong.
	var flagged := SimReferee.would_be_offside(ctx, player.team, mate.pos)
	var off_balance: float = 1.0
	if uncontrolled:
		off_balance = lerpf(0.3, 0.7, player.attrs.first_touch * player.attrs.technique)
	var success := _pass_success(ctx, player, from, point, best_travel, mate, true)
	if flagged:
		success *= OFFSIDE_DISCOUNT
	# What it is worth is what *his* shot is worth, not what the grass is. A point
	# thirteen metres out reads much like any other patch of the D on the map, and
	# the difference — that he is facing goal and nobody is — is the whole act.
	var gain: float = best_worth * SQUARE_CONVERT * ctx.config.shot_appetite_at(best_worth)
	var call := _call_bias(ctx, mate)
	var pattern := SimPatterns.pass_bias(ctx, player, best_mate, point)
	_note_factor(SimAblation.F_OFF_BALANCE, off_balance)
	_note_factor(SimAblation.F_CALL, call)
	_note_factor(SimAblation.F_PATTERN, pattern)
	_candidates.append({
		"action": Action.GROUND_PASS,
		"target": best_mate,
		"point": point,
		"end": point,
		"first_time": uncontrolled,
		"success": success * off_balance,
		"gain": gain,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), point, ctx.pitch),
		"pace": pace,
		"bias": call * pattern,
		# So `_has_pullback_to` can tell this candidate from the ordinary pass to
		# the same man that `_add_passes` may also have offered.
		"pullback": true,
	})
	_keep_parts()
	_keep_factors()
static func _add_crosses(ctx: SimContext, player: SimPlayer, uncontrolled: bool) -> void:
	var from := ctx.ball.pos
	var attack_dir := ctx.pitch.attack_dir(player.team)
	# In the final third, and wide. Both are about the man on the ball rather
	# than about any target, so they are asked once.
	#
	# The third rather than the half, and the mean cross length is why: measured
	# at the halfway line it came out at 37.7 m, which is a diagonal and not a
	# cross. The lofted pass already covers that ball. `tools/diagnostics.gd`
	# takes the whole of their half as the population it asks the question over,
	# deliberately -- an instrument that adopts every gate the mechanic has can
	# never report the mechanic refusing to fire.
	if from.x * attack_dir <= ctx.pitch.half_length / 3.0 \
			or absf(from.z) <= ctx.pitch.half_width * CROSS_WIDE:
		return
	var tactics := ctx.tactics(player.team)
	var goal := ctx.pitch.target_goal(player.team)
	var side: float = signf(from.z)
	if side == 0.0:
		side = 1.0
	# Near post, penalty spot, far post. The far one is pulled back and past the
	# post because that is where the ball hangs up for somebody arriving. Read
	# from `SimOffBall` rather than written out again here, because the ball and
	# the run have to be aimed at the same three points or neither is worth
	# anything -- which is what they were, in two copies, until one of them moved.
	var targets := SimOffBall.box_targets(ctx, player.team, from)
	var off_balance: float = 1.0
	if uncontrolled:
		off_balance = lerpf(0.3, 0.7, player.attrs.first_touch * player.attrs.technique)

	# One candidate, not three. Three balls into the same area are one act as far
	# as the softmax is concerned, and offering them separately would give the
	# cross three shares of the weight against one for the carry beside it.
	var best_point := Vector3.ZERO
	var best_mate := -1
	var best_flight := 0.0
	var best_worth := 0.0
	for i in targets.size():
		var point: Vector3 = targets[i]
		var distance := SimConsts.horizontal_length(point - from)
		if distance < CROSS_FROM or distance > SimTouch.strike_range(player, point - from, MAX_LOFTED_PASS):
			continue
		# The two flights this ball could have: whipped in, or hung up. Which one
		# is struck is decided below by the man it is for.
		var whipped: float = SimTouch.cross_flight(distance)
		var hung: float = SimTouch.cross_hang(distance)
		# Who is attacking it, and the man who has claimed the point is that man.
		# `SimOffBall.box_claimant` is the run being made right now; the race below
		# is the fallback for a ball into an area nobody has set off for yet, which
		# is still a cross a footballer plays.
		var mate := SimOffBall.box_claimant(ctx, player.team, from, i)
		var arrive := INF
		if mate >= 0 and mate != player.id:
			arrive = SimValueField.time_to_arrive(ctx.players[mate], point,
				SimValueField.reaction_of(ctx.players[mate]))
		# He has to be able to get there, claim or no claim -- but the ball can
		# wait for him, up to the hung flight, so what he is measured against is
		# the slowest ball rather than the fastest. The run's own window
		# (`SimOffBall.BOX_WINDOW`) allows a man four seconds away and no cross
		# hangs that long.
		if mate == player.id or arrive > hung + CROSS_LATE:
			mate = -1
			arrive = INF
		if mate < 0:
			for mid in ctx.teammate_ids(player.team):
				if mid == player.id:
					continue
				var m := ctx.players[mid]
				if not m.on_pitch or m.is_keeper:
					continue
				var t_arrive := SimValueField.time_to_arrive(m, point, SimValueField.reaction_of(m))
				if t_arrive > hung + CROSS_LATE:
					continue
				if t_arrive < arrive:
					arrive = t_arrive
					mate = mid
		if mate < 0:
			continue
		# **Both balls are scored, and the better one is played.** Whipped in, and
		# hung up long enough for the man it is for to arrive -- the same point,
		# two different questions, and the value model is what decides between
		# them. Fitting the flight to him and leaving it there was the first
		# version and it hangs the ball into an empty six-yard box, because the
		# only man who can get there is two seconds away and nothing was asked
		# what the goalkeeper would do in the meantime. He is a body in
		# `control_at_time` like any other, so asked, it answers.
		#
		# This is the whole of the owner's *aimed at where team mates are going to
		# end up, or areas where they dominate by just being more players*
		# (2026-08-23). The crowd term puts everyone who can reach a hung ball on
		# level terms -- so the point where we have the bodies wins the ranking on
		# the hung ball, and the man who is already there wins it on the whipped
		# one. Nothing here counts heads: the count was always in the model, and a
		# flight that could not vary was what stopped it saying anything.
		var fitted: float = clampf(arrive, whipped, hung)
		for flight in [whipped, fitted]:
			# A ball he cannot reach is not this ball, whatever it is worth.
			if arrive > flight + CROSS_LATE:
				continue
			# **And it is dropped on him rather than on the point he is running
			# at.** Measured on `cross-loaded`: the ball came down 7.3 m from the
			# man it was for and, 90% of the time, *in front of him* -- two metres
			# nearer the goal, which is two metres on the side the defenders are
			# already standing (owner, 2026-08-23: *the crosses are hit too far
			# forward, so the attacking players do not really have a chance*).
			#
			# The point is where his run is going and the ball is put where he
			# will be when it comes down, which is the same distinction the
			# through ball makes and the cross did not. Asked of
			# `SimValueField.time_to_arrive`, the function that decided the flight
			# in the first place, so the two halves cannot disagree about him.
			var aim_point := _meet_point(ctx, ctx.players[mate], point, flight)
			# **Built, measured and reverted: ranking the three points by what a
			# header from each would be worth** (`expected_goals` in place of the
			# value map here), on the argument that the field barely separates
			# three points a few metres apart -- and it does not: measured, the
			# ball went to the penalty spot on every cross in 40 trials, 11.0 m
			# from the goal line, and the header that followed was struck from
			# 12.6 m. Ranked by the header instead, the ball goes nearer the goal
			# and into worse company: `cross-loaded` `lost` 49% to **60%**, the
			# ball coming down 3.5 m from the nearest of ours to 4.3, and the
			# goals unmoved at n=100. `cross-deep` liked it -- 6% goals to 10% --
			# and paid the same way, 4.5 m to 6.3. What the near post is worth is
			# a value-map question (**8b**) and not one to settle from here.
			var worth: float = ctx.value.xt_at(player.team, aim_point, ctx.pitch) \
				* ctx.value.control_at_time(
					ctx, aim_point, player.team, flight, player.id)
			if worth > best_worth:
				best_worth = worth
				best_point = aim_point
				best_mate = mate
				best_flight = flight
	if best_mate < 0:
		return

	var mate: SimPlayer = ctx.players[best_mate]
	var success := _lofted_success(ctx, player, best_point, best_flight, mate, Action.CROSS)
	var distance := SimConsts.horizontal_length(best_point - from)
	var best_xt := ctx.value.xt_at(player.team, best_point, ctx.pitch)
	var focus := tactics.focus_at(best_point.z, ctx.pitch)
	var pattern := SimPatterns.pass_bias(ctx, player, best_mate, best_point)
	var call := _call_bias(ctx, mate)
	_note_factor(SimAblation.F_FOCUS, (best_xt * focus - best_xt) * CROSS_BIAS)
	_note_factor(SimAblation.F_OFF_BALANCE, off_balance)
	_note_factor(SimAblation.F_DIRECT, tactics.direct_bias())
	_note_factor(SimAblation.F_PATTERN, pattern)
	_note_factor(SimAblation.F_CALL, call)
	_candidates.append({
		"action": Action.CROSS,
		"target": best_mate,
		"point": best_point,
		"end": best_point,
		"first_time": uncontrolled,
		"success": success * off_balance,
		"gain": best_xt * focus * CROSS_BIAS,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), best_point, ctx.pitch),
		"flight": best_flight,
		"bias": tactics.direct_bias() * pattern * call,
	})
	_keep_parts()
	_keep_factors()


## How far along his run to `point` a man actually gets in `flight` seconds.
##
## The ball is aimed there rather than at the point itself: a cross that arrives
## where he is *going* is a cross to the defender standing goal-side of him.
## Bisected against `time_to_arrive` rather than solved, because that function is
## the engine's own answer about his legs -- a closed form here would be a second
## opinion about the same man, and the two would drift.
static func _meet_point(ctx: SimContext, mate: SimPlayer, point: Vector3, flight: float) -> Vector3:
	var reaction := SimValueField.reaction_of(mate)
	if SimValueField.time_to_arrive(mate, point, reaction) <= flight:
		return point
	var low := 0.0
	var high := 1.0
	for _i in 6:
		var mid := (low + high) * 0.5
		if SimValueField.time_to_arrive(mate, mate.pos.lerp(point, mid), reaction) <= flight:
			low = mid
		else:
			high = mid
	var met := mate.pos.lerp(point, low)
	met.y = 0.0
	return met


## The teammates worth scoring as pass targets, cheaply chosen.
##
## The proxy uses only things already computed this tick -- the cached per-player
## expected threat and a squared distance -- so the filter itself is free.
static var _short_ids := PackedInt32Array()
static var _short_scores := PackedFloat32Array()


static func _shortlist(ctx: SimContext, player: SimPlayer, from: Vector3) -> PackedInt32Array:
	_short_ids.clear()
	_short_scores.clear()
	for mate_id in ctx.teammate_ids(player.team):
		if mate_id == player.id:
			continue
		var mate := ctx.players[mate_id]
		if not mate.on_pitch:
			continue
		# He cannot pass to a man he cannot see (`docs/THE_FOOTBALL.md` 12). The
		# gate is here rather than on the candidate because an option outside
		# perception should never be generated at all -- scoring it and then
		# discarding it would leave it in every tally as a ball he turned down.
		if not SimPerception.can_see(ctx, player, mate, 1.0 - ctx.tactics(player.team).tempo):
			_note_shortlist_unseen()
			continue
		var dx := mate.pos.x - from.x
		var dz := mate.pos.z - from.z
		var d2 := dx * dx + dz * dz
		if d2 < 4.0 or d2 > 3600.0:
			continue
		var threat: float = ctx.player_threat[mate_id] if mate_id < ctx.player_threat.size() else 0.0
		# Ranked on where he is going, if he has committed to going anywhere.
		#
		# `player_threat` is the expected threat of the grass a man is standing on,
		# and for a man mid-run that is the grass he is trying to leave -- so the
		# run that is worth passing to was competing for a place on the list on the
		# strength of the position it was made *from*. Measured: 55% of moves into
		# space and 38% of runs past the last defender were never a scored candidate
		# at all. Not rejected -- never asked about.
		var offer := SimOffBall.destination_for(ctx, mate)
		if not is_inf(offer.x):
			threat = maxf(threat, ctx.value.xt_at(player.team, offer, ctx.pitch))
		# Forward and dangerous, or simply close. Both kinds of option matter.
		var score: float = threat * 3.0 + 1.0 / (1.0 + sqrt(d2) * 0.06)
		var i := 0
		while i < _short_scores.size() and _short_scores[i] >= score:
			i += 1
		shortlisted += 1
		_short_ids.insert(i, mate_id)
		_short_scores.insert(i, score)

	lists += 1
	if _short_ids.size() <= MAX_PASS_TARGETS:
		return _short_ids
	lists_capped += 1
	# Keep the best few, but never drop the nearest couple: the safe ball has to
	# stay on the table even when it looks worthless.
	var kept := _short_ids.slice(0, MAX_PASS_TARGETS)
	# Nor the man going past the last defender. Ranking him at his destination
	# above gets him onto most lists; this is the guarantee, and it is worth
	# spending a slot on because the alternative is the best ball in football
	# being invisible. Bounded by the quota in `SimOffBall`, which allows two.
	for mate_id in _short_ids:
		if SimOffBall.intent_of(ctx, ctx.players[mate_id]) == SimOffBall.BEHIND \
				and not kept.has(mate_id):
			kept.append(mate_id)
	var nearest := PackedInt32Array()
	var nearest_d := PackedFloat32Array()
	for mate_id in _short_ids:
		var mate := ctx.players[mate_id]
		var d := mate.dist_to(from)
		var i := 0
		while i < nearest_d.size() and nearest_d[i] <= d:
			i += 1
		nearest.insert(i, mate_id)
		nearest_d.insert(i, d)
	for i in mini(ALWAYS_KEEP_NEAREST, nearest.size()):
		if not kept.has(nearest[i]):
			kept.append(nearest[i])
	# And the switch. In own-half build-up the ranking above fills the list
	# with the cluster around the ball -- proximity is half the score and
	# expected threat is flat back there -- so the free man on the far side
	# never makes it, and the only ball out of a crowd was the long one to the
	# front (DECISIONS.md, "Width in build-up"). The same argument as the
	# runner in behind: the best ball out of a collapse is invisible unless a
	# slot guarantees it. One slot, the widest free man across the pitch.
	if from.x * ctx.pitch.attack_dir(player.team) < 0.0:
		var switch_id := -1
		var switch_z := SWITCH_ACROSS
		for mate_id in _short_ids:
			if kept.has(mate_id):
				continue
			var mate := ctx.players[mate_id]
			var across: float = absf(mate.pos.z - from.z)
			if across <= switch_z:
				continue
			var near := ctx.nearest_to(mate.pos, SimConsts.other_team(player.team))
			if near != null and near.dist_to(mate.pos) < SWITCH_FREE_RADIUS:
				continue
			switch_id = mate_id
			switch_z = across
		if switch_id >= 0:
			kept.append(switch_id)
	dropped += _short_ids.size() - kept.size()
	return kept


## Pace a ground pass should arrive at, in m/s. A short ball is rolled in; a
## long one has to be driven or the defence gets there first.
##
## The slope was 0.35 off a floor of 3.5, which puts an ordinary fourteen-metre
## ball into a man's feet at 9.2 m/s. That is not a pass, it is a drive, and it
## was the single biggest reason the ball read as running away from people:
## measured over two seeds, every ground pass in the match arrived at 8.7 m/s,
## and the `Taking it down` block then showed the ball arriving at 9.5 and
## leaving at 4.2 -- a first touch failing at a ball nobody should have hit that
## hard.
##
## It is also the one thing rolling resistance cannot reach.
## `SimBallistics.ground_pass_speed` solves the launch speed *against*
## `roll_decel` to hit the pace asked for here, so a grabbier pitch strikes the
## ball harder and it still arrives at 8.7. Arrival pace is invariant to friction
## by construction, and this function is the only place it is decided.
##
## The new curve is a footballer's: about 3.5 m/s at five metres, 4.7 at ten,
## 5.6 at fourteen, 7 at twenty, and just under 10 at the length where a ground
## pass stops being offered at all. The docstring's original point survives in
## the slope -- a long ball is still driven -- it is the intercept that was
## wrong.
##
## What it costs is on the books rather than hidden: a slower ball is longer in
## flight, `_pass_success` prices interception off exactly that, and the softmax
## will stop choosing the long ground passes that can now be cut out. A slow pass
## being easier both to control and to intercept is the trade football makes.
static func arrival_pace(distance: float, tactics: SimTactics) -> float:
	# The curve came down a tenth (2.2 + d*0.21 capped at 12) with the player
	# speeds going up, one feel change in two halves: the owner watched the
	# ball outrunning the men. The interception trade is priced as the comment
	# above says, and the launch solver keeps arrival exact against any pitch.
	#
	# **And the intercept went back up, 2026-08-23, because it had taken the
	# short pass with it** (owner: *slow short passes that are easy to intercept,
	# and the receiver needs to turn and run back to the ball*). At 2.0 a
	# ten-metre ball arrived at 4.3 m/s and spent **1.57 s** on the grass; at
	# five metres it was 3.2 m/s and a second. That is a ball rolled, not passed,
	# and a second and a half is time for anybody to step in front of it. The
	# slope is what the earlier change was about -- a long ball outrunning the men
	# -- so the slope stays where it was put and the floor under it moves:
	# 4.2 + 0.19 d puts ten metres at 6.1 m/s and about a second, twenty at 8.0.
	return clampf(4.2 + distance * 0.19, 4.2, 12.0) * lerpf(0.9, 1.2, tactics.tempo)


## What share of the receiver's top speed a ball in behind should still be doing
## when it reaches the spot it was aimed at.
##
## The old reasoning held this under 1.0 -- a ball arriving at his own pace is
## one he draws level with and never catches -- and that is true of a ball he
## chases from behind. It is not true since `_behind_aim` solves the meeting
## point: ball and man arrive at the aim *together*, the catch is geometry, and
## the arrival pace is only the character of the ball -- at 0.9 it spent its
## last third barely outpacing a sprinting man and the owner read it as a
## normal pass, not a through ball. At his full pace the strike is firmer and
## the meeting point deeper, which is the ball hit through the line. Still the
## eye's tuning constant -- `PLAN.md` §11.1.1.
const BEHIND_ARRIVE := 1.0

## The stride of slack past which the runner is judged to beat the ball to its
## aim, and the strike stops being slowed for his chase.
const BEHIND_EARLY := 3.0

## How comfortably the ball in behind must beat the goalkeeper to its aim
## before the aim stops retreating from him.
const KEEPER_BEAT := 0.25


## The length term the ball in behind did not have.
##
## The ground pass has carried `1/(1 + d·0.21)` since it was written, and its own
## note says why: football's pass-length distribution is heavily short, and without
## it the engine plays a Hollywood ball every time. The through ball carried no
## length term at all, so a 12 m ball slipped between two centre backs and a 30 m
## raking one were priced alike on length while `xt_at` paid the longer one more
## for finishing further up the pitch. On bias alone it was worth about five times
## a ground pass of the same length, and 8.5% of through balls were being played
## over thirty metres.
##
## **It is not the ground pass's law reused.** That law starts falling at the boot,
## and a ball in behind lives at fifteen to twenty-five metres — applied here it
## would not shape the pass, it would delete it. So length costs nothing up to
## `BEHIND_FREE`, the range the pass exists at, and falls away past it, where what
## is being played is a raking sixty-yarder wearing a through ball's name.
##
## Three constants answering two questions, kept apart because they move different
## things. `BEHIND_FREE` and `BEHIND_LENGTH` are the shape: where the term starts
## biting and how hard. `BEHIND_WORTH` is the level -- what a ball in behind is
## worth against a ball to feet of the same length -- and it is the one that would
## change how *often* the pass is played rather than how long it is.
##
## **The level was tried below 1.0 and it bought nothing.** At 0.75, over three
## ten-minute seeds, through balls fell from 207 to 161 and the through ball's
## share of all passes went from 14.3% to 14.1% -- because the whole passing game
## shrank with it, from 479 passes a match to 383. It cost a fifth of the football
## to buy two tenths of a percentage point. So the level stays at 1.0 and the
## frequency, which is still high, is not a length problem.
##
## All three are tuning constants -- `PLAN.md` §11.1.1.
const BEHIND_FREE := 24.0
const BEHIND_LENGTH := 0.16
const BEHIND_WORTH := 1.0

## How far short of the last defender a ball can still be aimed and count as one
## played in behind. A metre, because the line is not a wall: a ball rolled into
## the channel level with the last man is played in behind by anybody's eye, and
## the defender is turning while the runner is not.
const BEHIND_BREAK := 1.0

## What a pass to a man the passer can see is offside keeps of its success.
## Not zero: the whistle is only certain if the flagged man plays the ball, and
## a passer under pressure will still chance it.
const OFFSIDE_DISCOUNT := 0.12

## The layoff. What the *easiest* first-time ball keeps of
## its success instead of the full `off_balance` rate -- a ball eased back up
## its own line is barely a decision -- and the redirect share below which a
## first-time ball to a man facing play is preferred at all. The bias is the
## give-and-go's argument: a bounce to the man who can see the pitch is a ball
## whose decision was made before it arrived.
const LAYOFF_OFF_BALANCE := 0.88
const LAYOFF_SHARE := 0.45
const LAYOFF_BIAS := 1.35


static func behind_length_bias(distance: float) -> float:
	return BEHIND_WORTH / (1.0 + maxf(distance - BEHIND_FREE, 0.0) * BEHIND_LENGTH)


## How firmly to strike a ball in behind.
##
## A ball in behind is the one pass that is not aimed at a man: he runs onto it,
## so its weight is a fact about how fast *he* runs and not about how far it has
## to go. `arrival_pace` answers the other question -- how hard to hit a ball at
## somebody's feet, where longer means firmer so it is not cut out -- and asked
## here it produced a 25 m ball arriving at 10.3 m/s at a striker who tops out at
## 9.1. Measured over ten minutes of seed 7, 68% of through balls arrived faster
## than the man they were for could travel, 41% went straight to an opponent, and
## 35% reached the runner at all. That is not a ball being cut out; it is a ball
## nobody was ever going to reach.
##
## What it costs is on the books rather than hidden, and it is the same trade
## `arrival_pace` names: a slower ball is longer on the grass, `_pass_success`
## prices interception off exactly that, and the softmax will stop choosing the
## ones a covering defender can now get across to.
static func behind_pace(distance: float, tactics: SimTactics, mate: SimPlayer) -> float:
	return minf(arrival_pace(distance, tactics), mate.max_speed() * BEHIND_ARRIVE)


## Where to aim a ball in behind: as far along the line he is going as he can get
## while the ball travels, and no further.
##
## Both branches of the candidate needed this and only one had it. The committed
## run measured the flight to the far end and cut the aim back to what that flight
## buys; the projection went to a flat 7 to 16 m in front of him and asked nothing
## at all. The projection is the branch that fires for the man who has *not*
## committed -- a striker drifting onto the shoulder -- which is exactly the man
## least able to chase a ball rolled past him, and measured it aimed 12.6 m ahead
## whatever the distance was and whatever he was doing.
##
## One correction, the same one the ground pass makes in `_lead_point`: the flight
## is measured to the far end, the aim is cut back to what that flight buys, and
## the candidate's terms are then recomputed off the aim that came out -- so the
## ball that is scored is the ball that is struck.
static func _behind_aim(ctx: SimContext, player: SimPlayer, mate: SimPlayer, from: Vector3,
		believed: Vector3, going: Vector3, tactics: SimTactics) -> Vector3:
	var to_run := SimConsts.horizontal(going - believed)
	var span := to_run.length()
	if span < 0.5:
		return _keep_in_play(ctx, going)
	var dir := to_run / span
	# The meeting point, not the destination. The lead was capped at `span` --
	# where his run was going to *stop* -- and every ball whose flight outlasts
	# the run was under-led by the difference: the bench read `ahead` 11.5-14.1 m
	# against `he covers` 14.8-29.0, so the runner beat the ball to the spot by
	# metres, stood on it, and was hit in the back by his own pass (owner,
	# 2026-09-01). A man played in behind does not stop at his run point, he
	# runs on. So the aim is where his flat-out run and the ball's flight meet:
	# two rounds of the loop settle it, `reach_in` is the flat-out run because
	# chasing a ball rolled past you is one, and `_pass_success` still prices
	# everyone else who can get there.
	var aim := going
	for _i in 2:
		var d := SimConsts.horizontal_length(aim - from)
		var travel := ctx.ballistics.ground_travel_time(d,
			ctx.ballistics.ground_pass_speed(d, behind_pace(d, tactics, mate), ctx.env), ctx.env)
		aim = believed + dir * SimValueField.reach_in(mate, to_run, travel)
	# And short of the goalkeeper's collect. The meeting point of a deep run
	# lands happily where the keeper arrives first -- probed, the aim sat
	# 12.3 m from goal with the keeper there in 1.97 s against the ball's 2.30,
	# and `space` was right to halve the ball for it. The room a ball in behind
	# has ends at the goalkeeper, not at the paint: the carry learned it in
	# `keeper_room`, and this is the pass's copy of the same rule. Stepped back
	# toward the runner until the ball beats him by a beat, bounded rounds.
	var keeper: SimPlayer = ctx.teams[SimConsts.other_team(mate.team)].keeper()
	if keeper != null and keeper.on_pitch:
		for _k in 4:
			var kd := SimConsts.horizontal_length(aim - from)
			var kt := ctx.ballistics.ground_travel_time(kd,
				ctx.ballistics.ground_pass_speed(kd, behind_pace(kd, tactics, mate), ctx.env), ctx.env)
			if SimValueField.time_to_arrive(keeper, aim, SimValueField.reaction_of(keeper)) \
					> kt + KEEPER_BEAT:
				break
			aim = believed + (aim - believed) * 0.8
	# And no deeper than the passer can strike. A meeting point past his reach
	# is not a reason to have no ball at all -- struck as deep as he can, the
	# ball arrives first and rolls on ahead of the runner, which is a ball into
	# the channel and not one into his back. Under the range gate's own cap so
	# the clamped ball is still offered.
	aim = SimTouch.clamp_to_reach(player, from, aim, (MAX_GROUND_PASS + 6.0) * 0.97)
	return _keep_in_play(ctx, aim)


## Pulls a target point far enough inside the pitch that a ball played to it has
## somewhere to be received. Passes aimed at the touchline are how a match ends
## up with twenty corners and forty throw-ins.
static func _keep_in_play(ctx: SimContext, point: Vector3) -> Vector3:
	return ctx.pitch.clamp_to_pitch(point, 3.0)


## Where to aim a ball that will take `travel` seconds to reach a teammate.
##
## The old answer was `believed + vel * travel * 0.6`, dead reckoning on the
## velocity he happens to have right now, and it fails in the one case that
## matters. A player who has just committed to a run has not accelerated into it
## yet, so his velocity is small and the ball is played to his feet -- which
## means the through ball is mispriced precisely when it is worth playing,
## because the runner is still turning at the moment it should be struck. The
## `0.6` then under-leads even the runs it can see, so the ball arrives behind a
## man who is still going.
##
## Both are fixed by asking the receiver where he is going instead of guessing
## from where he is pointing. He is aimed at as far along his own committed run
## as he can physically get in the time the ball is in flight, and no further --
## `_pass_success` still has to be convinced he beats everyone else there, so an
## optimistic lead is priced rather than believed.
static func _lead_point(ctx: SimContext, mate: SimPlayer, believed: Vector3, travel: float) -> Vector3:
	var dest := SimOffBall.destination_for(ctx, mate)
	if is_inf(dest.x):
		return believed + mate.vel * travel * 0.6
	var to_dest := SimConsts.horizontal(dest - believed)
	var span := to_dest.length()
	if span < 0.5:
		return believed + mate.vel * travel * 0.6
	return believed + to_dest / span * minf(span, _run_reach(ctx, mate, to_dest, travel))


## As far along a run as the receiver can actually be when the ball arrives.
##
## Two things, and the engine had neither. `reach_in` starts him from the pace he
## is going rather than from his top speed, which is what a lead of `pace x
## travel` assumed; and the pace he is aiming for is the one his intent is being
## run at, which for a drift into a pocket is well under a sprint.
static func _run_reach(ctx: SimContext, mate: SimPlayer, dir: Vector3, travel: float) -> float:
	var capped: float = mate.max_speed() * maxf(SimOffBall.pace_for(ctx, mate), 0.2) * travel
	return minf(SimValueField.reach_in(mate, dir, travel), capped)


## What a teammate's committed offer is worth as a claim on the ball.
static func _call_bias(ctx: SimContext, mate: SimPlayer) -> float:
	var kind := SimOffBall.intent_of(ctx, mate)
	if kind == SimOffBall.BOX:
		return CALL_BOX
	if kind == SimOffBall.BEHIND:
		return CALL_BEHIND
	if kind == SimOffBall.SHOW:
		return CALL_SHOW
	if kind == SimOffBall.SPACE:
		return CALL_SPACE
	return 1.0


## The return ball, decaying across `GIVE_AND_GO_WINDOW` from the moment the ball
## reached him. Not from the moment it was struck: `SimContext.last_pass_arrival_tick`
## has what that cost, and it was most of the mechanic.
static func _give_and_go_bias(ctx: SimContext, player: SimPlayer, mate_id: int) -> float:
	if ctx.last_pass_to != player.id or ctx.last_pass_from != mate_id:
		return 1.0
	# Still on its way, so he is not the man deciding what to do with it.
	if ctx.last_pass_arrival_tick < ctx.last_pass_tick:
		return 1.0
	var elapsed := float(ctx.tick_index - ctx.last_pass_arrival_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed > GIVE_AND_GO_WINDOW:
		return 1.0
	return lerpf(GIVE_AND_GO_BIAS, 1.0, elapsed / GIVE_AND_GO_WINDOW)


## What the receiver does with the ball once it reaches him, as threat over and
## above the grass it stops on. See `RECEIVER_CARRY_SECONDS`.
##
## Only a man arriving *towards* goal earns any of it, which is the distinction
## expected threat cannot draw: the same ball to the same spot is worth one
## thing to a striker running onto it and another to one checking back to feet
## with his back to the play. Discounted by whether his side still holds the
## ball where the carry ends, so a run into a crowd earns nothing.
static func _arrival_gain(ctx: SimContext, team: int, point: Vector3, believed: Vector3,
		receiver: SimPlayer, travel: float) -> float:
	var goal := ctx.pitch.target_goal(team)
	var to_goal := SimConsts.horizontal(goal - point)
	var gl := to_goal.length()
	if gl < 2.0:
		return 0.0
	to_goal /= gl
	var run := SimConsts.horizontal(point - believed)
	var onto := 0.0
	if run.length() > 0.5:
		onto = clampf(run.normalized().dot(to_goal), 0.0, 1.0)
	else:
		# The body he has opened while the ball travelled (`_orient_receiver`),
		# not the way his last run left him.
		onto = clampf(receiver.heading_dir().dot(to_goal), 0.0, 1.0)
	if onto <= 0.01:
		return 0.0
	# How long he carries it on for, and it is not the same second for a man
	# receiving in a crowd and a man arriving past the last defender. See
	# `CLEAR_CARRY_SECONDS`.
	var seconds: float = lerpf(RECEIVER_CARRY_SECONDS, CLEAR_CARRY_SECONDS,
		_clear_ahead(ctx, team, point, goal))
	var carry: float = minf(receiver.max_speed() * seconds * onto, gl - 1.0)
	if carry <= 0.5:
		return 0.0
	var ahead := _keep_in_play(ctx, point + to_goal * carry)
	var step := ctx.value.xt_at(team, ahead, ctx.pitch) - ctx.value.xt_at(team, point, ctx.pitch)
	if step <= 0.0:
		return 0.0
	return step * ctx.value.control_at_time(ctx, ahead, team, travel + seconds)


## How much of the way to goal is actually open from the point the ball is going
## to, as 1 for nobody in front of him and falling away as bodies fill the lane.
##
## This is the half of `8b` that does not need a new value field. Expected threat
## is a map of the grass: the same twenty-five metres out is worth the same
## whether the back four is in front of him or behind him, so a ball played in
## behind was priced as its landing spot and the ball into the crowded pocket
## beside it scored the same. Counting who is between him and the goal is not the
## defence's orientation — that is still not modelled — but it is the half of it
## that decides what the man does next, and it is the half a viewer sees.
static func _clear_ahead(ctx: SimContext, team: int, point: Vector3, goal: Vector3) -> float:
	var in_the_way := 0
	for oid in ctx.opponent_ids(team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.is_keeper:
			continue
		if _near_segment(o.pos, point, goal, CLEAR_LANE):
			in_the_way += 1
	return pow(CLEAR_BODY, float(in_the_way))


## Probability a ground pass reaches its target: the receiving side must win the
## arrival point, and nobody may cut the line off on the way.
## How much earlier than the ball a receiver has to reach the point for the pass
## to be priced as one to feet. A stride: enough to have stopped and turned.
const THERE_FIRST_MARGIN := 0.35


static func _pass_success(ctx: SimContext, player: SimPlayer, from: Vector3, to: Vector3, travel: float, receiver: SimPlayer, into_space: bool = false, driven: bool = false, bow: float = 0.0) -> float:
	# Three separate questions, and conflating them is how an engine talks
	# itself into forty-metre passes: who owns that space, can this particular
	# receiver be there when the ball is, and does the ball survive the journey.
	#
	# The first question is asked of the moment the ball lands, not of now.
	# Nobody owns the grass behind a defensive line at the moment a through
	# ball is played -- that is what makes it space -- so a snapshot answers
	# "the defence, always" and prices every ball forward as a giveaway. And
	# it is asked as an *aimed* contest rather than a neutral race
	# (`control_at_pass`): the receiver knew where the ball was going before
	# it was struck and the defender is reacting to the flight, which is the
	# asymmetry backlog 24 measured as the model saying 0.46 on contested
	# balls that arrived 72% of the time. The snapshot the to-feet branch
	# used to take conflated "is that grass contested now" with "who touches
	# the arriving ball first", and the engine's own resolution rule
	# (`SimDuel._act`) answers only the second.
	var space := ctx.value.control_at_pass(
		ctx, to, player.team, travel, receiver.id, player.id, into_space)
	# A ball into space has two contests in it and is only as good as the weaker.
	#
	# The line above asks whether he wins the race to the grass. It cannot ask
	# whether he gets away to start running, because it is fought several metres
	# beyond him -- and the man marking him is not at that point and never will
	# be. Between the two, nobody priced the marker at all: `_lane_survival` hands
	# the last `LANE_TAIL` metres to this function as the arrival's business, and
	# this function is looking somewhere the marker is not.
	#
	# Measured, `./run.sh control` block D: a defender standing one metre from a
	# receiver running onto the ball took it 100 times out of 100, and the model
	# said 0.52. At two metres 100% and 0.54, at three 98% and 0.56. Crossing the
	# line at pace rather than standing changed the shape and not the size, so it
	# is the plain marker that was missing rather than the man on the move.
	#
	# So the same contest is asked a second time where he is standing now, and the
	# ball takes the worse of the two. A ball to feet is unaffected: there the two
	# points are the same point.
	#
	# On the *sharp* clock, whatever kind of ball this is. `AIMED_TAU` is earned by
	# the receiver being on the spot already, and at this point he is -- it is the
	# grass under his feet. The race for the space beyond him is the one that is
	# graded, and it is asked on the line above.
	#
	# On the escape clock, not the ball's. `control_at_pass` floors the receiver's
	# arrival at `ball_time` and floors no opponent at all, which is right where
	# the ball is going -- nobody plays it before it lands -- and wrong at his own
	# feet, where he is already standing. Handed the whole flight, the term asks
	# "who owns this grass three seconds from now", and three seconds from now he
	# is not on it: measured on `through-ball`, a runner with **5.3 m of grass
	# around him** came back at 0.003 on a 28 m ball, and the same runner at the
	# same distance from the same marker came back at 0.99 on a 12 m one. It was
	# reading the length of the pass and calling it a marker. `./run.sh control`
	# block D says the same from the other side: `space` sat at 0.99-1.00 down a
	# block whose whole variable is how close the marker is, which by that bench's
	# own legend is the signature of a factor that cannot see the geometry it owns.
	#
	# What bounds the marker is how long the receiver has to stay within his
	# reach, and that is a stride or two whatever the ball is doing.
	if into_space:
		space = minf(space, ctx.value.control_at_pass(
			ctx, receiver.pos, player.team, minf(travel, ESCAPE_WINDOW),
			receiver.id, player.id, false))
	# Whether the receiver is there when it is -- and only for a ball to feet.
	#
	# For a ball into space the two lines above and this one are the same question
	# asked twice about the same man. `control_at_time` floors every arrival at the
	# ball's journey and then weighs everyone who could be there against everyone
	# else; the receiver is on the passing side, so his own race is already inside
	# it, and a receiver who cannot get there is weighed at `exp(-(his time - the
	# ball's) / 0.42)`, which is nothing. Multiplying `in_time` on top squares a
	# term that is well under one for every ball worth playing in behind.
	#
	# It is the same mistake the through-ball branch found once before and fixed by
	# deleting the *other* copy of it -- the note is still up there in
	# `_add_passes` -- and this is the half that survived. Measured on the losing
	# candidates: a through ball came back at 0.05 with `space` 0.47 and `in_time`
	# 0.59, while the ones the engine did play completed two times in three.
	#
	# A ball to feet keeps it, at the margin of a man already at or beside the
	# point, where the logistic reads near one. `space` now knows when the ball
	# turns up for both branches, so most of what this term said is inside it;
	# what it still owns is the receiver adjusting the last stride onto a lead
	# point, which the share-of-weights form cannot state about him alone.
	var in_time := 1.0
	if not into_space:
		var receiver_time := SimValueField.time_to_arrive(receiver, to, receiver.reaction)
		in_time = _in_time(travel + 0.3 - receiver_time,
			SimConsts.horizontal_length(to - receiver.pos))
	var lane := _lane_survival(ctx, player, from, to, travel,
		LANE_TAIL if into_space else FEET_TAIL, -1, bow)
	# The driven ball is airborne over the middle of its journey, and that is the
	# whole football reason for hitting one (`docs/THE_FOOTBALL.md` 26). A leg put
	# in the lane takes a rolled ball and misses a driven one, so the interception
	# term is the one that has to know -- not the success as a whole, which is what
	# a scale factor on the outside would have done.
	#
	# It is a share of the way to a clear lane rather than a clear lane, because
	# the ball is only up for the middle of the flight: it leaves the floor and
	# sits back down onto it, and a man standing right in front of the striker or
	# right on the receiver can still take it.
	if driven:
		lane = lerpf(lane, 1.0, DRIVEN_LANE)
	var distance := SimConsts.horizontal_length(to - from)
	# The line is handed to the accuracy estimate, not just its length, so the ball
	# the passer would have to hit blind off his back foot is priced as the harder
	# ball it is. Without it the engine happily selects a pass it then scuffs, and
	# the facing model shows up only as passes going astray -- never as a player
	# choosing to turn, or to give it to the man he can see instead.
	var tolerance := pass_tolerance(distance) * (SPACE_TOLERANCE if into_space else 1.0)
	# A ball into space is aimed at grass and a ball to feet is aimed at a man, so
	# only the first of them can be the wrong *length*. See `SimTouch.LONG_NONE`.
	var struck := SimTouch.execution_accuracy(ctx, player, player.attrs.passing, distance,
		SimTouch.GROUND_AIM_BASE, tolerance, to - from,
		SimTouch.LONG_GROUND if into_space else SimTouch.LONG_NONE)
	# A ball along the floor has no `control` term. See `receiver_touch`: whether
	# the man takes it cleanly is not whether the ball reaches him, and it is
	# priced on what the pass is worth instead.
	_note_parts(space, in_time, lane, 1.0, struck)
	return clampf(space * in_time * lane * struck, 0.0, 0.99)


## How sure the receiver is of being where the ball is going. `margin` is the
## ball's journey less his own; `run` is how far he has to travel for it.
##
## The width was a flat 0.45 s, and a flat width is what made this a constant. A
## man standing on the spot the ball is rolled to has a margin of a second and a
## half, and a logistic never reaches one, so he was charged four per cent for a
## race he is not running -- on every pass in the match, in a term that could
## therefore never explain one.
##
## Measured over 358 played balls that resolved, `in time` came back at 0.96 on
## the ones that arrived and 0.99 on the ones that did not: a term that knew
## nothing, and leaned very slightly the wrong way. That is the signature of a
## constant, and `docs/DIAGNOSTICS.md` now names it as one.
##
## The width is the running instead. A race over no ground has no uncertainty in
## it; a race over twenty metres has most of a second, because a slip, a marker
## picking him up, or a stride misread is what the uncertainty in a race *is*, and
## none of it happens to a man who is already standing there.
static func _in_time(margin: float, run: float) -> float:
	var width: float = IN_TIME_WIDTH_FLOOR + run * IN_TIME_WIDTH_PER_M
	return clampf(1.0 / (1.0 + exp(-margin / width)), 0.0, 1.0)

const IN_TIME_WIDTH_FLOOR := 0.12
const IN_TIME_WIDTH_PER_M := 0.05

## How long the receiver of a ball into space has to stay inside his marker's
## reach before he is gone -- the clock the escape contest in `_pass_success` is
## settled on. See the note there for why it is not the ball's flight.
##
## It binds on the long ball and on nothing else, which is the whole of the fix:
## `./run.sh control` block D flies a 12 m pass, whose flight is inside the
## window, so every row of the bench this contest was built against is untouched
## by it. What changes is the ball the bench cannot reach -- the thirty-metre one
## in behind, where the flight was three seconds and the term was reading it as a
## marker.
const ESCAPE_WINDOW := 1.8


## How much of the far end of a lane belongs to the arrival rather than to the
## journey, for a ball played to feet.
##
## `LANE_TAIL` says the last defender is charged twice when the two halves of the
## pass model are divided exactly at the target -- he stands by it, so `space`
## counts him, and the last stride of the lane runs past him, so `_lane_survival`
## counts him again. That was found and fixed for the ball into space and left at
## zero here, on the reasoning that nothing else had priced the man marking him.
## `control_at` is what prices him, and always was.
##
## It is shorter than `LANE_TAIL` because it is the range over which `control_at`
## actually has an opinion, and that is not the same range. A defender six metres
## off a target the receiver is standing on arrives a second and a half behind him
## and is weighed at `exp(-1.5 / 0.42)`, which is two per cent; at two metres he is
## weighed at a fifth, which is a real charge. Two metres is where the double count
## lives.
const FEET_TAIL := 2.0


## The shape of the interception along a lane: how sharp the line between a
## defender who gets a leg to it and one who does not, and how late he can be and
## still take it half the time.
##
## Read off `./run.sh control`, block B — one defender standing on the line,
## halfway along a 12 m pass, `l` metres to the side of it. The engine takes the
## ball 95% at half a metre, 82% at one, 55% at one and a half, 20% at two, 10%
## at three and never past four and a half. All three constants come off those
## rows, and they go stale when the engine's defender does: the previous fit
## (0.29 late, 0.125 wide) was made against an engine that cut 98% at one and a
## half and 82% at two, and once the engine stopped doing that the model was
## calling every threaded ball a certainty the other way — probed on
## `through-ball`, `lane` read 0.000-0.005 on every ball in behind, so the act
## was generated, priced at succ 0.01, and never once won. Too harsh is the same
## bug as too generous: the model saying something the engine does not do.
##
## `LANE_TAU` is the width the transition actually has. `LANE_LATE` is the
## centre — a defender level with the ball no longer takes it far more often
## than half the time, so the lateness credit is gone.
##
## Fitted 2026-08-25, the seven rows read 0.07, 0.18, 0.51, 0.72, 0.91, 0.98,
## 0.99 against a ball kept 0.05, 0.18, 0.45, 0.80, 0.90, 1.00, 1.00.
##
## `AIMED_STEP_IN` in `SimValueField` is the same measurement one factor along,
## and the two say opposite-looking things for one reason: at the *end* of a pass
## the receiver is standing on the ball and a defender has to beat him to it,
## while *along* it there is nobody in the way and a defender only has to reach
## it. The same bench measures both, and it should be re-read when the defensive
## pass lands.
const LANE_TAU := 0.16
const LANE_LATE := 0.0
## And what being well placed is worth, as time rather than as odds: the gap
## in effective arrival between a defender who reads it and one who does not.
const LANE_POSITION := 0.08


## What the receiver's first touch is worth, as a discount on the ball rather than
## on its arrival.
##
## This was the `control` factor of `_pass_success`, `lerpf(0.72, 0.99, ...)`, and
## it was in the wrong model. A pass in this engine completes when a teammate
## reaches the ball, whatever he then does with it -- `SimDuel._resolve_pass_outcome`
## is the whole rule -- so a first touch cannot decide whether the pass arrives,
## and the term was a flat fourteen per cent charged against an event the match
## never produces. The instrument said so plainly: 0.86 on the balls that arrived
## and 0.85 on the ones that did not, a spread of one point.
##
## What it prices is real and stays, one model along. A man who cannot take it
## cleanly is worth less to give it to, because less of the position he is put in
## survives his first touch -- and *that* the engine does simulate, in
## `SimTouch.first_touch`. So it is a bias on the value of the ball, where it
## changes which man gets picked without claiming the pass will not get there.
##
## The aerial branch keeps its own version and should: `_lofted_success`'s
## `aerial` term is whether he wins the header, and losing a header is the other
## side heading it, which is exactly the pass failing to arrive.
static func receiver_touch(receiver: SimPlayer) -> float:
	return lerpf(0.72, 0.99, receiver.attrs.first_touch)


## How far off a pass can land and still be a pass. A longer ball gives the
## receiver more time to adjust to a poor one.
static func pass_tolerance(distance: float) -> float:
	return 2.0 + distance * 0.06


## How much more room a ball played into space has to land in than one to feet.
##
## The same mistake `AERIAL_TOLERANCE` names, in the other branch of the same
## function, and found the same way. `execution_accuracy` asks whether the ball
## lands inside a tolerance, and the tolerance was a standing receiver's for
## both. A ball played in behind is not aimed at a boot: it is aimed at grass a
## man is already running onto at six or seven metres a second, and two metres
## long is a better through ball rather than a failed one.
##
## Measured on the balls the engine actually played, seed 7 at ten minutes, the
## through ball's `struck` came back at 0.72 against 0.90 for a pass to feet --
## and the model priced those same balls at 0.29 while 65% of them arrived. Every
## other kind sits at 1.3 to 1.5 times its own claim; the through ball sat at
## 2.2. `said` against `completed` in the diagnose block is that measurement.
##
## The number is `AERIAL_TOLERANCE`'s, and for the same reason rather than by
## borrowing it: a receiver at a sprint covers about three metres in the time he
## has to adjust, which on a twenty-five metre ball is the 3.5 m tolerance again.
const SPACE_TOLERANCE := 1.8


## How much more room a ball in the air has to land in than one along the floor.
##
## `execution_accuracy` asks whether the ball lands inside a tolerance, and the
## tolerance was a rolled ball's for both. It is not the same question. A ball
## rolled at a man's feet either arrives at his feet or runs past him; a ball
## dropped near him hangs long enough to be walked onto, and he can attack it from
## a good deal further away than he can reach with a foot. Nobody heads a ball
## from exactly where they were standing when it was struck.
##
## Measured, the model was pricing the difference the wrong way round. The `struck`
## term for a lofted ball came back at 0.35 and for a cross at 0.34, against 0.82
## for a ground pass -- and lofted balls were the best rejected option 403 times in
## ten minutes while the ones that got played completed at 50 to 59%. The larger
## aim error a lofted ball is struck with is real and stays; what was wrong was
## measuring it against a target the size of a man's boot.
const AERIAL_TOLERANCE := 1.8


static func _lofted_success(ctx: SimContext, player: SimPlayer, to: Vector3, flight: float, receiver: SimPlayer, kind: int = Action.LOFTED_PASS) -> float:
	# A ball in the air cannot be cut out along the ground, but it is harder to
	# control and easier to attack in the air.
	var arrival := ctx.value.control_at_time(ctx, to, player.team, flight, player.id)
	var aerial: float = lerpf(0.55, 0.95, (receiver.attrs.heading + receiver.attrs.jumping) * 0.5)
	var distance := SimConsts.horizontal_length(to - ctx.ball.pos)
	# The skill the ball is *struck* with. `SimTouch.lofted_pass` hits a cross with
	# `crossing` and this priced every one of them with `passing`, so a winger who
	# can cross and cannot pass was talked out of the ball he is in the side for,
	# and a passer who cannot cross was talked into it. Link 1 of the chain: an
	# attribute that never reaches the ball it belongs to.
	var skill: float = player.attrs.crossing if kind == Action.CROSS else player.attrs.passing
	# How flat this particular ball is, so a hung cross is not charged the whipped
	# one's scatter. A lofted pass has one flight and asks for the default.
	var whip := SimTouch.cross_whip_share(distance, flight) if kind == Action.CROSS else 1.0
	var struck := SimTouch.execution_accuracy(ctx, player, skill, distance,
		SimTouch.AIR_MODEL_AIM_BASE, pass_tolerance(distance) * AERIAL_TOLERANCE,
		to - ctx.ball.pos,
		SimTouch.LONG_AIR_CROSS if kind == Action.CROSS else SimTouch.LONG_AIR, whip)
	# And where it goes when it does not go there, because a ball in the air that
	# misses its spot is a loose ball and not a turnover.
	#
	# `struck` used to multiply straight through, which prices every ball that
	# lands off the mark as the other side's. It is not. It drops twelve metres
	# further on and somebody wins it there, and often enough that is us. Charging
	# the full loss is the same mistake `receiver_touch` was: a factor claiming an
	# outcome the match does not produce.
	#
	# So the miss is priced where it lands. `long_sigma` is how far off the ball
	# goes and the engine now knows that honestly, which is what makes this
	# answerable at all -- before `./run.sh strike` the model thought the scatter
	# was a quarter of its real size, so there was nothing to scatter *to*.
	var lands := lerpf(_scattered(ctx, player, to, flight, distance, skill), arrival, struck)
	# Reported as the share of the aim point's worth that survives the scatter, so
	# the `struck` column still says how well the ball was hit and the five factors
	# still multiply out to the number the softmax was handed.
	var delivered: float = clampf(lands / maxf(arrival, 1e-4), 0.0, 1.0)
	# `struck` carries the passer's own skill as well here, and the two terms a
	# ground ball has and this one does not come back as 1.0 rather than as a gap.
	_note_parts(arrival, 1.0, 1.0, aerial, delivered * lerpf(0.7, 0.95, skill))
	return clampf(arrival * aerial * delivered * lerpf(0.7, 0.95, skill), 0.0, 0.97)


## Who owns the grass a mis-hit ball actually lands on, as the mean of the two
## ways it misses.
##
## Both, rather than the long one, because they are not the same miss and taking
## either alone leans the model. A ball hit short drops among the bodies it was
## aimed at, one of whom is our man arriving on it; a ball hit long clears all of
## them and runs on, which for a cross is the keeper's or the byline's. One is
## kinder than the aim point and one is harsher.
##
## It is two more `control_at_time` queries per aerial candidate, which is the one
## thing here nobody has measured -- `perf` is the owner's to run. They are pruned
## the same way every other control query is, and the aerial candidates are a
## handful per decision, so the expectation is that it does not show.
static func _scattered(ctx: SimContext, player: SimPlayer, to: Vector3, flight: float,
		distance: float, skill: float) -> float:
	var line := SimConsts.horizontal(to - ctx.ball.pos)
	if line.length_squared() < 1e-6:
		return 0.0
	var off := line.normalized() * SimTouch.long_sigma(player, skill, distance, SimTouch.LONG_AIR)
	var long_ball := _keep_in_play(ctx, to + off)
	var short_ball := _keep_in_play(ctx, to - off)
	return 0.5 * (ctx.value.control_at_time(ctx, long_ball, player.team, flight, player.id)
		+ ctx.value.control_at_time(ctx, short_ball, player.team, flight, player.id))


## How much of the far end of a lane belongs to the destination rather than to
## the journey, for a ball played into space.
##
## The two halves of a pass model divide at the target: `control_at_time` prices
## who owns the place it is going, `_lane_survival` prices getting there. Drawing
## that line exactly at the target charges the last defender twice -- he is stood
## by the target, so he counts in the first, and the last stride of the lane runs
## past him, so he counts again in the second. Six metres is about what
## `CONTROL_TAU` is already weighing at the far end.
const LANE_TAIL := 6.0


## Probability no opponent intercepts along the line. Only opponents actually
## near the line are considered, which keeps this cheap.
##
## `tail` is how much of the far end to leave to the destination model:
## `LANE_TAIL` for a ball into space, `FEET_TAIL` for one to feet. Neither is zero,
## and the note that said a ball to feet had nothing else pricing the man marking
## him was wrong -- `control_at` prices him, and always did.
## `ignore_id` is the man the act is *about*, and there is exactly one caller
## that has one: the knock past a defender. He is priced twice otherwise, once
## as the race in `_escape_value` and once as a leg in the lane here, and the
## two are the same man in the same act -- the whole point of a take-on is that
## he is in the way. `control_at_time` already takes him as its `ignore_id` for
## this reason; this term was the one that missed the convention.
##
## Measured before it did (`./run.sh replay --scenario take-on --seed 4001
## --tick 1`): the knock up the line came back `succ 0.02` against a settling
## touch's 0.40, with the full-back 2.2 m in front of the ball and 0.8 m off its
## line -- charged at almost a certainty here, so the take-on could not be worth
## anything however the rest of it was priced. 84% of trials ended `lost` and
## none in a goal (`docs/THE_FOOTBALL.md` 45).
## `bow` is the mid-chord offset of a curled ball's path in metres, signed
## positive toward the passer's left -- `SimBallistics.curl_bow`'s convention.
## Zero is the straight ball every caller priced before the bend existed.
static func _lane_survival(ctx: SimContext, player: SimPlayer, from: Vector3, to: Vector3, travel: float, tail: float = 0.0, ignore_id: int = -1, bow: float = 0.0) -> float:
	var survival := 1.0
	var seg := SimConsts.horizontal(to - from)
	var length: float = maxf(seg.length(), 0.1)
	var dir := seg / length
	var journey: float = maxf(length - tail, length * 0.5)
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if not o.on_pitch or o.id == ignore_id:
			continue
		survival *= 1.0 - _cut_chance(ctx, player, o, o.pos, from, dir, length, journey, travel, bow)
	return clampf(survival, 0.0, 1.0)


## One opponent's chance of cutting the ball out, standing at `at` -- which is
## his position now for every caller but `_add_opening`, which asks about where
## he will be after the carrier has moved him.
static func _cut_chance(ctx: SimContext, passer: SimPlayer, o: SimPlayer, at: Vector3, from: Vector3, dir: Vector3,
		length: float, journey: float, travel: float, bow: float = 0.0) -> float:
	var rel := SimConsts.horizontal(at - from)
	var along: float = rel.dot(dir)
	if along <= 0.5 or along >= journey:
		return 0.0
	# A curled ball is priced where the ball actually goes: a bend of `bow` at
	# mid-chord offsets the path by 4*bow*u*(1-u) at each station, positive
	# toward the passer's left. The station stays the chord projection and the
	# local direction stays the chord's -- both a few degrees off on a real
	# bend, accepted here -- but the metres of offset are what move a leg in
	# or out of reach, and those are real.
	var side: float = rel.x * -dir.z + rel.z * dir.x
	var u := along / length
	# `side` is positive to the right of travel, so a left bow sits negative.
	var path_side := -4.0 * bow * u * (1.0 - u)
	var lateral: float = absf(side - path_side)
	if lateral > 12.0:
		return 0.0
	var lat_dir := Vector3(-dir.z, 0.0, dir.x)
	var point := from + dir * along + lat_dir * path_side
	# A ball coming from behind him is not his until it is round to where his leg
	# reaches -- `SimDuel.in_reach_arc`, the contact rule's own gate -- so the
	# meeting is not at the foot of the perpendicular but further along the lane,
	# where the bearing first enters the arc. Bisected along the remaining lane;
	# no such point means he never gets a leg to it.
	var face := SimConsts.horizontal(o.heading_dir())
	if face.length_squared() > 1e-6 and not _bearing_in_arc(face, at, point):
		var lo := 0.0
		var hi: float = journey - along
		if not _bearing_in_arc(face, at, from + dir * journey):
			return 0.0
		for _i in 6:
			var mid := (lo + hi) * 0.5
			if _bearing_in_arc(face, at, point + dir * mid):
				hi = mid
			else:
				lo = mid
		along += hi
		u = along / length
		path_side = -4.0 * bow * u * (1.0 - u)
		point = from + dir * along + lat_dir * path_side
	var ball_time := travel * (along / length)
	# When does the ball get there, and when could they?
	#
	# "Could they" is not "could they stand on that spot". A defender a metre
	# off the line does not run to it, he sticks a leg out, and the first
	# CONTROL_RANGE of the gap between him and the ball's path costs him
	# nothing but his reaction. Charging him the full locomotion cost for it
	# is what made this model kind to a pass threaded straight past somebody:
	# measured across three ten-minute seeds, a quarter of all passes were
	# played with an opponent inside a metre and a half of the line, and they
	# completed at about 40% -- the engine was choosing them, watching them
	# get cut out, and choosing them again.
	var toward := SimConsts.horizontal(at - point)
	var gap := toward.length()
	var meet := point
	if gap > 1e-3:
		meet = point + toward / gap * minf(SimConsts.CONTROL_RANGE, gap)
	var opp_time := SimValueField.time_to_arrive_from(o, at, meet, SimValueField.reaction_of(o))
	opp_time += _facing_cost(ctx, passer, o, at, meet)
	# Positioning is a head start, not a discount on the chance. Read as a
	# multiplier on `p_cut` it put a floor under every lane in the match --
	# `1 - 0.97 * 0.75` at worst -- so a defender standing half a metre off
	# the line came back at 0.17 survival while the engine took that ball
	# 100 times out of 100. Read as time it says the same thing about the
	# man without saying anything about a ball that has no chance.
	var margin := ball_time - opp_time \
		+ lerpf(-LANE_POSITION, LANE_POSITION, o.attrs.positioning)
	if margin <= -0.9:
		return 0.0
	return clampf(1.0 / (1.0 + exp(-(margin + LANE_LATE) / LANE_TAU)), 0.0, 0.995)


## `SimDuel.in_reach_arc` for a man stood at `at` facing `face`.
static func _bearing_in_arc(face: Vector3, at: Vector3, p: Vector3) -> bool:
	var to := SimConsts.horizontal(p - at)
	if to.length_squared() < 0.04:
		return true
	return face.normalized().dot(to.normalized()) >= cos(SimDuel.REACH_ARC)


## What it costs a man to play a ball that is behind him: the turn, and the look.
##
## The lane read bodies and not which way they were pointing, so a back line
## facing its own goal was charged as interceptors for a ball cut back behind it
## -- every cut-back on the floor priced at 0.15-0.21 against 1.00 for the same
## ball in the air (`tools/_pullback_probe.gd`, 25 seeds). A defender's leg is
## only in the lane once his body is, and both halves of that are already the
## engine's own models:
##
## - **The turn.** Beyond `SimDuel.REACH_ARC`, which is what the contact rule
##   gives a leg for nothing, his body swings at `turn_rate` capped by
##   `TURN_GRIP` -- exactly what `SimPlayer.integrate` lets it do -- and that
##   falls with speed, so a man running toward his own goal pays more, not less. It overlaps
##   `time_to_arrive`'s momentum term for a man moving across the line; they are
##   two views of one body and the overlap is accepted rather than fitted away.
## - **The look.** A ball struck by a man he has not had in his eyes lately
##   (`SimPerception.saw_recently`, arc plus memory) is news when it reaches
##   him, not when it is hit, so he pays his reaction a second time. `SimDuel._has_seen_it` is the
##   contact rule's half of the same fact: with the charge here alone,
##   `./run.sh control` block B said 0.44 at 1 m against 82% cut out.
static func _facing_cost(ctx: SimContext, passer: SimPlayer, o: SimPlayer, at: Vector3, meet: Vector3) -> float:
	var face := SimConsts.horizontal(o.heading_dir())
	if face.length_squared() < 1e-6:
		return 0.0
	face = face.normalized()
	var cost := 0.0
	var to_meet := SimConsts.horizontal(meet - at)
	if to_meet.length_squared() > 1e-6:
		# Only the turn beyond what his leg reaches round: `SimDuel.REACH_ARC`
		# is the arc the contact rule gives him for nothing.
		var swing: float = maxf(acos(clampf(face.dot(to_meet.normalized()), -1.0, 1.0))
			- SimDuel.REACH_ARC, 0.0)
		var speed := o.speed()
		var rate: float = minf(o.turn_rate(speed), SimPlayer.TURN_GRIP / maxf(speed, 0.35))
		cost += swing / maxf(rate, 0.1)
	if not SimPerception.saw_recently(ctx, o, passer):
		cost += SimValueField.reaction_of(o)
	return cost


## How close the man on the carrier has to be for there to be anything to move
## him off, and the touch that does it.
const OPENING_RANGE := 4.0
const OPENING_TOUCH := 2.0
## How much better the pass has to price from the new spot before the two-step
## act is offered beside the one-step one. Below this it is the same option
## twice, and the softmax reads the pair as evidence for the act.
const OPENING_MIN := 0.05


## The carry that opens the pass: push it to the side of the man on you and play
## the ball from where he is not.
##
## A carry is valued by the grass it lands on, so a touch sideways under
## pressure read as "0.6 m left, gain 0.03" and never saw the cut-back it would
## have opened -- while the through ball it was standing beside, played straight
## into the keeper's hands at succ 0.15, won the pick at 92% because nothing on
## the list competed with its gain (`cross-pullback` seed 12, tick 28). The
## alternative was never a candidate. `docs/DIAGNOSTICS.md`: a value knob cannot
## create an option that was never generated.
##
## So the sideways touch is offered again, worth the pass it opens. The carry's
## own odds are the scored probe's, unchanged. The pass is re-priced from where
## the touch leaves the ball, with the challenger where he will be by then --
## still closing on where the ball *was*, for the length of the touch, because
## the touch is not news until it is played -- and the two are multiplied: he
## has to get the touch right and then the ball has to arrive. Only the through
## ball and the cut-back are asked, because those are the balls a man on the
## byline is blocked from playing, and only when the re-priced ball is clearly
## better than the same ball played now.
##
## The window is real in the engine as it stands: the challenger reacts late
## (`reaction_of`), sheds momentum before he can turn (`time_to_arrive`), and
## the carrier re-decides every touch cooldown, 0.17 to 0.27 s. What was missing
## was a candidate that could see two touches ahead.
static func _add_opening(ctx: SimContext, player: SimPlayer, uncontrolled: bool, challenger: SimPlayer) -> void:
	if uncontrolled or challenger == null or challenger.recovery_ticks > 0:
		return
	if challenger.dist_to(player.pos) > OPENING_RANGE:
		return
	# The balls he is blocked from playing, as already scored from here.
	var blocked: Array[Dictionary] = []
	for c in _candidates:
		if int(c["action"]) == Action.THROUGH_BALL or c.get("pullback", false):
			blocked.append(c)
	if blocked.is_empty():
		return
	var ball := ctx.ball.ground_pos()
	var to_man := SimConsts.horizontal(challenger.pos - ball)
	if to_man.length_squared() < 1e-6:
		return
	to_man = to_man.normalized()
	# Where he will be when the ball is played again: closing on where it is
	# now, for as long as the touch takes plus the cooldown before the next one.
	var offered := false
	for side in [-1.0, 1.0]:
		var want := Vector3(-to_man.z * side, 0.0, to_man.x * side)
		# The scored probe nearest that way. Its odds are the carry's odds, and
		# the touch that gets played is the one that was scored.
		var probe := {}
		var best := 0.5
		for c in _candidates:
			if int(c["action"]) != Action.DRIBBLE or c.has("push") or c.has("opening"):
				continue
			var d: float = Vector3(c["dir"]).dot(want)
			if d > best:
				best = d
				probe = c
		if probe.is_empty():
			continue
		var dir: Vector3 = probe["dir"]
		var touch: float = minf(float(probe["max_ahead"]), OPENING_TOUCH)
		var landing := ctx.pitch.clamp_to_pitch(ball + dir * touch, 1.0)
		var when := SimValueField.time_to_arrive(player, landing, 0.0) + player.touch_cooldown_length()
		var step: float = minf(SimConsts.horizontal_length(challenger.vel) * when,
			maxf(challenger.dist_to(ball) - SimConsts.CONTROL_RANGE, 0.0))
		var then := challenger.pos
		if step > 0.0:
			then += SimConsts.horizontal(challenger.vel).normalized() * step
		for c in blocked:
			var point: Vector3 = c["point"]
			var distance := SimConsts.horizontal_length(point - landing)
			if distance < 4.0 or distance > SimTouch.strike_range(player, point - landing, MAX_GROUND_PASS):
				continue
			var receiver: SimPlayer = ctx.players[int(c["target"])]
			var travel := ctx.ballistics.ground_travel_time(distance,
				ctx.ballistics.ground_pass_speed(distance, float(c["pace"]), ctx.env), ctx.env)
			var success := _pass_success(ctx, player, landing, point, travel, receiver, true)
			# The lane priced him where he stands. Swap that charge for the one
			# where he will be.
			var seg := SimConsts.horizontal(point - landing)
			var lane_dir := seg / maxf(seg.length(), 0.1)
			var journey: float = maxf(distance - LANE_TAIL, distance * 0.5)
			var now_cut := _cut_chance(ctx, player, challenger, challenger.pos, landing, lane_dir, distance, journey, travel)
			var then_cut := _cut_chance(ctx, player, challenger, then, landing, lane_dir, distance, journey, travel)
			if now_cut < 0.995:
				success *= (1.0 - then_cut) / (1.0 - now_cut)
			success = clampf(success, 0.0, 0.99)
			if success < float(c["success"]) + OPENING_MIN:
				continue
			_candidates.append({
				"action": Action.DRIBBLE,
				"point": landing,
				# Possession settles where the pass does; that is what the
				# turnover is priced at.
				"end": c["end"],
				"dir": dir,
				"escape": probe["escape"],
				"away": probe["away"],
				"space": probe["space"],
				"max_ahead": touch,
				"success": clampf(float(probe["success"]) * success, 0.0, 0.98),
				"gain": c["gain"],
				"loss": c["loss"],
				"bias": float(probe.get("bias", 1.0)) * float(c.get("bias", 1.0)),
				# The touch's own delay on top of what any pass is charged: the
				# one-step ball is discounted at `DISCOUNT_SECONDS` flat, not at
				# its travel, so this one is too.
				"seconds": when + DISCOUNT_SECONDS,
				"opening": int(c["action"]),
				"target": c["target"],
			})
			_keep_parts()
			_keep_factors()
			offered = true
	if offered:
		_note_rare(RARE_OPENING, false)


## The feint: a body turned without the ball, and the knock the other way.
##
## `_try_beat` already rolls a feint from a standstill *inside* a scored touch,
## which is a cut priced as the touch it rides on. This is the act on its own:
## the carrier stands, the man is closing on him, and he sells a step at the
## man for `FEINT_HOLD`, then knocks it past him on the scored probe across
## him. Priced as a lottery in front of that probe: with `beat_odds` the man is
## left -- his race for the landing void, so the probe's `success` over its own
## `escape` -- and otherwise the probe as it stands, which is generous by the
## quarter of a second given away. The gain and the loss are the probe's, a
## quarter of a second later. Offered on both sides, whichever has a probe;
## `RARE_FEINT` counts whether it was on the list at all, which is the first
## thing to know about it (CLAUDE.md, "a value knob cannot create an option").
static func _add_feint(ctx: SimContext, player: SimPlayer, uncontrolled: bool, challenger: SimPlayer) -> void:
	if feint_gate.size() != FEINT_GATES.size():
		feint_gate.resize(FEINT_GATES.size())
	if uncontrolled or challenger == null or challenger.recovery_ticks > 0:
		feint_gate[0] += 1
		return
	if player.speed() >= 1.5:
		feint_gate[1] += 1
		return
	var gap := challenger.dist_to(player.pos)
	if gap > FEINT_RANGE or gap < 1e-3:
		feint_gate[2] += 1
		return
	var to_me := SimConsts.horizontal(player.pos - challenger.pos) / gap
	var closing: float = challenger.vel.dot(to_me)
	if closing < 1.5:
		feint_gate[3] += 1
		return
	var to_man := -to_me
	var odds := beat_odds(player, challenger, closing, true)
	var offered := false
	for side in [-1.0, 1.0]:
		var want := Vector3(-to_man.z * side, 0.0, to_man.x * side)
		var probe := {}
		var best := 0.5
		for c in _candidates:
			if int(c["action"]) != Action.DRIBBLE or c.has("push") or c.has("opening"):
				continue
			var d: float = Vector3(c["dir"]).dot(want)
			if d > best:
				best = d
				probe = c
		if probe.is_empty():
			feint_gate[4] += 1
			continue
		var stood: float = float(probe["success"])
		var left: float = clampf(stood / maxf(float(probe.get("escape", 1.0)), 0.05), stood, 0.98)
		_candidates.append({
			"action": Action.FEINT,
			"point": probe["point"],
			"end": probe["end"],
			"dir": probe["dir"],
			"sell": to_man,
			"escape": probe["escape"],
			"away": probe["away"],
			"space": probe["space"],
			"max_ahead": probe.get("max_ahead", INF),
			"success": clampf(odds * left + (1.0 - odds) * stood, 0.0, 0.98),
			"gain": probe["gain"],
			"loss": probe["loss"],
			"bias": float(probe.get("bias", 1.0)),
			"seconds": float(probe.get("seconds", DISCOUNT_SECONDS)) + FEINT_HOLD,
			"odds": odds,
		})
		_keep_parts()
		_keep_factors()
		offered = true
	if offered:
		feint_gate[5] += 1
		_note_rare(RARE_FEINT, false)


## Which test the feint failed, per decision it was asked on. The off-ball
## table's "first test failed" for this act: a zero on the list is a gate
## before it is a price. Reset with the rare acts.
const FEINT_GATES := ["no man closing", "moving", "too far", "not committed", "no probe", "offered"]
static var feint_gate := PackedInt32Array()


## The race for a dribble's landing point, between the carrier and the man
## closing on him.
##
## This is what makes a change of direction a real option. Pitch control cannot
## express it: `control_at` counts the carrier on his own side, and he is the
## nearest man to every one of his own probes, so every direction comes back at
## roughly the same value and the eight candidates are told apart by nothing but
## expected threat -- which is why the carrier only ever dribbled forward, into
## the man.
##
## Asked as one race between two known players it discriminates sharply, because
## `SimValueField.time_to_arrive` charges each of them for the momentum he has
## to shed before he can travel across his own line. A touch played square
## across a committed challenger beats him; the same touch played down the pitch
## in front of him does not. Neither case is authored -- both fall out of the
## locomotion model.
##
## Returns 1.0 when nobody is challenging, so an uncontested carry is unchanged.
static func _escape_value(challenger: SimPlayer, player: SimPlayer, target: Vector3) -> float:
	if challenger == null:
		return 1.0
	# The carrier is not reacting to anything: he has just chosen this himself.
	var mine := SimValueField.time_to_arrive(player, target, 0.0)
	var theirs := SimValueField.time_to_arrive(challenger, target, challenger.reaction)
	return clampf(1.0 / (1.0 + exp(-(theirs - mine) / ESCAPE_TAU)), 0.02, 1.0)


## The knock a carrier could get away with here, in metres of relative gap,
## given where the touchline is.
##
## The conversion is the point. A dribble touch is struck to leave the ball
## `push` metres clear of a player who keeps running, so the ball's own travel
## over the ground is far greater than `push` -- it has to outrun him first and
## then wait for him. Asking whether there is room for the *gap* rather than for
## the ball is how a carrier ends up knocking it into touch and calling it a
## run in behind.
static func _room_ahead(ctx: SimContext, player: SimPlayer, dir: Vector3,
		round_keeper: bool = false) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var room := ctx.pitch.run_room(player.pos, dir, 1.0)
	# ...and it ends at the keeper, unless going past him is the act. See
	# `keeper_room`. The limit it returns is the ball's catch-up distance and
	# this inversion is its roll to a stop, which is the longer of the two, so
	# feeding one to the other errs toward the shorter knock -- the right way
	# round for a ball being knocked at a goalkeeper.
	if not round_keeper:
		room = minf(room, keeper_room(ctx, player.pos, dir, player.team, along))
	if is_inf(room):
		return BURST_DISTANCE
	# Undo the overshoot: ball travel is roughly its launch speed squared over
	# twice the rolling deceleration, and the launch speed is the carrier's own
	# pace plus whatever opens the gap.
	#
	# Inverted properly, which it was not. It used to check the full nine-metre
	# knock against the room and, when it did not fit, scale the knock by the
	# ratio `room / travel` -- but travel goes as the *square* of the launch speed
	# and the launch speed has the carrier's own pace already in it, so scaling
	# the gap by that ratio does not make the ball fit the room, it merely makes
	# it a bit less wrong. Worked through: a man running at 6 m/s with 20 m of
	# grass was allowed a 5 m knock, which leaves the ball travelling at 9.5 m/s
	# and rolling 28 m -- eight metres out of play, from a test whose entire job
	# was to stop that.
	#
	# It is the only thing in the engine that puts a carried ball out from the
	# middle of the pitch, and it is why. Measured, the dribble touches that ended
	# in a throw-in or a goal kick were played on average 16.6 m inside the
	# nearest line, at 10.7 m/s -- nowhere near the paint, and far too hard to be
	# an ordinary carry.
	#
	# The launch speed the ball can afford is the one that brings it to rest on
	# the line, `sqrt(2 * decel * room)`; what the knock is worth is whatever is
	# left of that after his own pace, converted back through the relative
	# deceleration the way `carry_room` does it.
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var delta: float = sqrt(2.0 * decel * maxf(room, 0.0)) - along
	if delta <= 0.0:
		return 0.0  # Running this fast, the ball is out of play before he is.
	return minf(BURST_DISTANCE, delta * delta / (2.0 * decel))


## How far a carried ball may travel this way before the goalkeeper is the man
## who ends it.
##
## The room tests below measure to the paint, and the paint is the wrong end of
## a run at goal. A ball knocked that way comes to rest in the keeper's hands
## twenty metres before it reaches the line, and every metre between him and the
## line is grass the touch may not spend. Nothing else in the engine said so:
## `carry_room` and `_room_ahead` both invert the ball's travel against
## `SimPitch.run_room`, and `close_control` shrinks the touch by where the ball
## is *now*, which on a run from thirty metres is nowhere near where this one
## ends up.
##
## Measured before it existed, `./run.sh scenario --only 1v1-clear --trace 1`:
## seed 4001 is a single 6.4 m knock from thirty metres out, the ball runs 24 m
## untouched, and the keeper collects it at 2.6 s -- the carrier's only touch of
## the whole situation. The row read `touch` 3.4 and `gap s` 2.84 where a carry
## that keeps the ball is under half a second (`docs/THE_FOOTBALL.md` 39).
##
## A hard test rather than a priced one, which is the right shape here: this is
## a line he is running *at*, not one he is running beside (`docs/INVARIANTS.md`,
## "a hard room test is the wrong shape for a line you are running beside").
##
## The race is between the keeper and the carrier for the ball's own resting
## place, and it is linear. The carrier meets it at `L / along` -- the carry is
## his and he has been running onto it the whole way. The keeper needs
## `a / vk + reaction`, where `a` is how far he stands along the touch. Setting
## the two equal gives `L = (a / vk + reaction) / (1 / along + 1 / vk)`, and no
## square roots: the ball may run as far as the last metre the keeper cannot
## beat him to.
##
## **Only inside his own penalty area**, which is the whole of what keeps this
## from banning the forward carry. A ball coming to rest thirty metres from goal
## is not a keeper's ball -- he has no hands out there and does not leave his
## line for it -- so the limit is never shorter than the distance to the edge of
## his area. What the rule bites on is the touch that would put the ball *past*
## that edge, unattended, with him waiting for it. A carry that never reaches
## the box is untouched by it, and so is a walking carrier: at low `along` the
## race is his by a distance.
##
## His offset from the line of the touch is charged as time rather than as
## distance -- the seconds it costs him to come across. A ball down the wing has
## him a long way off it, the limit goes out with him, and the winger carries as
## before.
## How far past the edge of his area to look when the pitch itself sets no
## bound, and how many halvings the race is solved in. Four puts the answer
## inside a metre over a sixteen-metre span, which is finer than the touch it
## sizes.
const KEEPER_RACE_SPAN := 16.0
const KEEPER_RACE_STEPS := 4


static func keeper_room(ctx: SimContext, from: Vector3, dir: Vector3, team: int, along: float) -> float:
	var keeper: SimPlayer = ctx.teams[SimConsts.other_team(team)].keeper()
	if keeper == null or not keeper.on_pitch or along <= 0.01:
		return INF
	var d := SimConsts.horizontal(dir)
	if d.length() < 1e-4:
		return INF
	d = d.normalized()
	# Where the touch first enters the area his hands work in. Outside it the
	# ball is nobody's in particular, and this says nothing about it.
	#
	# **Both bounds of the area, and the width one is not decoration.** Tested on
	# the depth alone -- which is what this was -- a ball carried up the touchline
	# thirty metres from the middle is "inside the box" the moment it passes the
	# eighteen-yard line, and the race below then cut a winger's knock up the line
	# from seven metres to under five, which is under the size that makes it a
	# foot race, so `_add_dribbles` stopped offering the take-on at all. A ball at
	# rest on the touchline is not a goalkeeper's whatever its x.
	var attack: float = ctx.pitch.attack_dir(team)
	var edge_x: float = ctx.pitch.target_goal(team).x - attack * ctx.pitch.penalty_depth
	var toward: float = d.x * attack
	if toward < 1e-4:
		return INF  # Not going his way at all.
	var box_entry: float = maxf((edge_x - from.x) / d.x, 0.0)
	# ...and the stretch of the touch that is between the two edges of the area,
	# which for a ball going straight down the line is nothing at all.
	var half_w: float = ctx.pitch.penalty_half_width
	if absf(d.z) > 1e-4:
		var t_a: float = (half_w - from.z) / d.z
		var t_b: float = (-half_w - from.z) / d.z
		var enter: float = minf(t_a, t_b)
		var leave: float = maxf(t_a, t_b)
		if leave <= box_entry:
			return INF  # Out of the area's width before it is deep enough.
		box_entry = maxf(box_entry, enter)
	elif absf(from.z) > half_w:
		return INF  # Straight down a line the area never reaches.
	var to_him := SimConsts.horizontal(keeper.pos - from)
	if to_him.dot(d) <= 0.0:
		return INF  # Behind the touch; not his ball.
	# The furthest along this line the ball can come to rest with the carrier
	# still beating him to it, solved against `SimValueField.time_to_arrive`
	# rather than in closed form.
	#
	# A closed form cannot see the keeper's *velocity*, and a keeper who has
	# already set off is the whole case this exists for: measured on `1v1-clear`,
	# a knock that the standing-keeper arithmetic said was won by three metres
	# was collected by an onrushing one. `time_to_arrive` charges him for the
	# momentum he has and the momentum he has to shed, which is the same function
	# every other race in the engine is settled by.
	var lo := box_entry
	var edge := ctx.pitch.run_room(from, d, LINE_MARGIN)
	var hi: float = maxf(edge, box_entry) if not is_inf(edge) else box_entry + KEEPER_RACE_SPAN
	hi = minf(hi, box_entry + KEEPER_RACE_SPAN)
	for _i in KEEPER_RACE_STEPS:
		var mid: float = (lo + hi) * 0.5
		var at := from + d * mid
		if SimValueField.time_to_arrive(keeper, at, keeper.reaction) > mid / along:
			lo = mid
		else:
			hi = mid
	return maxf(lo, box_entry)


## How big a touch this direction has room for, capped at `wanted`.
##
## Nothing else in the engine can see this. Every candidate point is clamped back
## inside the touchline before it is scored, so a touch played *along* the line
## and one played *over* it come back with the same expected threat, the same
## pitch control and the same everything else -- and the ball goes out. Measured
## on one seed, 19 of the 24 balls that went out of play in ten minutes were put
## there by a dribble, 11 of them carried over the goal line the carrier was
## running at.
##
## The distance to price it against is not where the touch puts the ball relative
## to the carrier: the ball is struck to be `ahead` metres clear of a man who
## keeps running, so in the world frame it travels much further. `carry_travel`
## is the figure, and this is that inversion.
##
## It used to charge the ball only as far as the point where it has slowed to his
## pace, on the reasoning that the carrier catches it there so it never gets to
## stop. He does not catch it there. That is the moment he *starts* closing, with
## the gap still open and the ball still doing his own speed; he reaches it most
## of the way to where it would have stopped anyway. At a sprint the two figures
## are 16 metres and 25, and the ten metres in between is where the ball crosses
## the line -- measured before this, carries that went out were struck 16.8 m
## inside the nearest line at 11.2 m/s, which passes a 16 m test and rolls 26.
##
## Nothing in between could have caught it either. The ball is beyond his reach
## for that whole stretch, so there is no second touch to shorten it with: the
## decision that put it there is the only one that could have known.
static func carry_room(ctx: SimContext, player: SimPlayer, dir: Vector3, wanted: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var allowed := wanted
	# The line is a hard end: past it the ball is out, so the touch shrinks to
	# fit and a direction with no room at all is not a direction.
	var room := ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN)
	if not is_inf(room):
		allowed = minf(allowed, carry_push_for(ctx, player, dir, maxf(room, 0.0)))
	# The keeper's ground is not that kind of end. He owns the grass a long
	# knock would run to and he does not stop a man taking a one-metre touch in
	# front of him, so this shortens the touch and never removes the direction.
	#
	# Floored for a specific reason. `_add_dribbles` drops a probe whose horizon
	# is under `DRIBBLE_AHEAD_FLOOR`, and unfloored this drove the forward probe
	# under it everywhere inside about sixteen metres -- so a man through on goal
	# had no goal-ward carry on his list at all and nothing to do but strike it
	# from wherever he happened to be. Measured on `./run.sh box`, the `carry`
	# column was empty in every row of the eleven- and seven-metre blocks. The
	# owner watched the same thing from the stand and called it shooting from too
	# far out.
	var his := keeper_room(ctx, ctx.ball.ground_pos(), dir, player.team, along)
	if not is_inf(his):
		allowed = minf(allowed, maxf(carry_push_for(ctx, player, dir, maxf(his, 0.0)),
			SimTouch.DRIBBLE_AHEAD_FLOOR))
	return minf(wanted, allowed)


## The same question for a settling touch, which does not carry his pace at all:
## `SimTouch.settle` strikes it to travel `ahead` over the grass, so the room test
## is the plain one. Asking `carry_room` -- which assumes a moving frame -- refused
## a sprinting player a forward settle he could comfortably make.
static func settle_room(ctx: SimContext, player: SimPlayer, dir: Vector3, wanted: float) -> float:
	var room := ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN)
	return wanted if is_inf(room) else minf(wanted, maxf(room, 0.0))


## How big a touch this direction is worth at the pace he is going.
##
## His speed *along the touch*, not his speed: a man running at eight metres a
## second who shifts it square across himself has none of that pace going where
## the ball is going, and the touch that comes back is the short one it should
## be. Turning and carrying on are told apart by the geometry, with nothing
## authored about either.
static func stride_room(player: SimPlayer, dir: Vector3, seconds: float = TOUCH_SECONDS) -> float:
	var along: float = maxf(player.vel.x * dir.x + player.vel.z * dir.z, 0.0)
	return maxf(along * seconds, SimTouch.DRIBBLE_AHEAD_FLOOR)


## Shrinks an intended touch by how close to goal it is being played.
##
## A knock four metres in front of you is a way of covering ground, and inside
## the penalty area there is no ground left to cover -- the ball has to stay
## somewhere it can be struck. A carrier who arrives in the box and pushes it
## another four metres has given the keeper the ball and himself no shot, which
## is the shape of every attack that gets that far and produces nothing.
##
## Nothing else in the engine shortens it. `carry_room` charges the touch for the
## grass it needs, and a man running *across* the six-yard box has all the grass
## in the world by that test while knocking the ball past the near post; the
## value function scores the point the ball ends up at, and four metres closer to
## goal always scores better. Neither can see that the act itself is the wrong
## one this close in.
##
## Applied to the long knock past a challenger as well, where it has a second
## effect worth naming: shortened below the size that made it a foot race, the
## burst fails its own gate in `_add_dribbles` and is not offered at all. That is
## the intention. Knocking it nine metres past a man and running is football at
## twenty metres from goal and is a ball given to the keeper at eight.
static func close_control(ctx: SimContext, player: SimPlayer, wanted: float) -> float:
	var goal := ctx.pitch.target_goal(player.team)
	var d := SimConsts.horizontal_length(goal - ctx.ball.pos)
	var t: float = clampf((d - CLOSE_CONTROL_NEAR) / (CLOSE_CONTROL_FAR - CLOSE_CONTROL_NEAR), 0.0, 1.0)
	return minf(wanted, lerpf(CLOSE_CONTROL_TOUCH, wanted, t))


## The ground a carry of this size covers before the carrier gets to it.
##
## Two stages, and leaving out the second is what let carries run off the pitch.
## The ball beats him by `delta` and that decays at the rolling rate, so after
## `delta / decel` seconds it is down to his pace with the gap fully open at
## `ahead` -- and he has closed nothing. Only then does he start gaining, and
## closing `ahead` metres on a ball that is still rolling takes as long again.
## The two stages come to `2 * along * delta / decel`, which at a sprint is 25 m
## against the 16 the first stage alone reports.
##
## Floored at `ahead`, which is the standing case: no pace to add, so the ball
## goes exactly as far as the touch was struck to send it.
static func carry_travel(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	# The same `delta` the strike uses, off the same function, or this is a model
	# of `SimTouch.dribble` that `SimTouch.dribble` does not obey.
	var delta: float = sqrt(2.0 * decel * SimTouch.dribble_opening(ctx, player, dir, ahead))
	return maxf(ahead, 2.0 * along * delta / decel)


## The knock, in metres of *gap*, that sends the ball `travel` metres over the
## grass. `carry_travel` read backwards, and the same inversion `carry_room`
## does inline.
##
## It exists because the two frames are not interchangeable and the burst's own
## size gate was written in the wrong one. A knock is specified as a gap between
## the ball and a man who keeps running; everything it has to clear -- a
## defender, a touchline, a goalkeeper -- is a distance over the grass; and at
## any real running pace the second is three or four times the first.
static func carry_push_for(ctx: SimContext, player: SimPlayer, dir: Vector3, travel: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	if along <= 0.01:
		return maxf(travel, 0.0)
	return maxf(travel, 0.0) * maxf(travel, 0.0) * decel / (8.0 * along * along)


## Where the ball is when the carrier plays it again, which for every touch but
## the burst is a long way short of `carry_travel`.
##
## `carry_travel` answers "where would the ball be if he never touched it again".
## That is the *burst's* question -- not re-touching is what makes a burst a
## burst -- and it was being used as the horizon for the ordinary carry too,
## which is re-taken the moment his cooldown lapses and the ball is inside
## `CONTROL_RANGE`.
##
## The two had never been run against each other, which is `docs/INVARIANTS.md`'s
## own trap: a function whose name is a claim about another function is unchecked
## until something runs both. Run: `carry_travel` claims 11 m for a 1.08 m touch
## at a sprint and 4.3 m at the mean speed of a match, and `./run.sh diagnose` --
## counting the ball's own position at consecutive dribble touches in that same
## match -- reports **0.55 m** between them, longest 0.78. Eight to twenty times
## out, and it was the point every carry probe was scored at.
##
## Near goal that is the whole of "he shoots from too far out" (owner, watching
## the one-on-one). The probe sat past the goal line, so `_in_play_odds` charged
## an unpressured striker for putting the ball out and `control_at_time` handed
## the grass to the keeper: a four-metre touch with nobody within twenty metres
## came back at `success` 0.28, nothing could beat the shot, and the shot was
## taken from wherever he happened to be standing.
##
## The gap opens to `ahead` and comes back, and he plays it at the first moment
## his cooldown has lapsed *and* the ball is within his reach. A touch smaller
## than his reach never leaves it, so that is simply the cooldown. Capped at
## `carry_travel`, which is the same journey with nobody interrupting it.
static func touch_travel(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	# Off the same opening the strike uses, so the two cannot disagree.
	var opening: float = SimTouch.dribble_opening(ctx, player, dir, ahead)
	var delta: float = sqrt(2.0 * decel * opening)
	var peak: float = delta / decel
	var wait: float = player.touch_cooldown_length()
	if ahead > SimConsts.CONTROL_RANGE:
		# It is out of his reach between these two moments, so if the cooldown
		# lapses inside that window he waits for it to come back.
		#
		# Measured against the *total* gap and not against the opening, which is
		# the whole of it. The ball a carrier plays is not at his feet -- it lies
		# most of a metre in front, right at the edge of `CONTROL_RANGE` -- so a
		# touch that opens only a few centimetres still puts it beyond his reach,
		# and he cannot play it again until friction has brought the whole gap
		# back inside. Asked about the opening alone this said a man at nine
		# metres a second would meet his ball 2.6 m on; the ball ran **seven
		# metres** into the keeper's hands, and `keeper_room` and
		# `control_at_time` were both being handed the short answer
		# (`docs/THE_FOOTBALL.md` 48).
		var span: float = sqrt(2.0 * decel * (ahead - SimConsts.CONTROL_RANGE)) / decel
		if wait > peak - span:
			wait = maxf(wait, peak + span)
	# The ball has stopped by then whatever happens, and cannot travel further
	# than its own roll.
	var launch: float = along + delta
	var t: float = minf(wait, launch / decel)
	return clampf(launch * t - 0.5 * decel * t * t, 0.0, launch * launch / (2.0 * decel))


## How long that takes -- the other half of `carry_travel`, and the half the
## engine kept implicit.
##
## A knock has a duration and it is not small. Nine metres in front of a man at
## 7.9 m/s puts the ball 43 m down the pitch and him on it five and a half
## seconds later, which is longer than most passing moves. Anything that prices
## the end of a carry -- who owns that grass, what it is worth by the time he
## gets there -- is answering a question about a board five seconds from now, and
## has to be told so.
##
## Read off the runner, not off the ball. The ball rolls further than this and
## stops later; the contest is where he meets it, and at pace that is
## `travel / along` -- the same `2 * delta / decel` the two stages above come to.
## Standing still he has no pace to run it down with, so the honest answer is the
## ball's own roll to a stop.
static func carry_time(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> float:
	var along: float = maxf(player.vel.dot(dir), 0.0)
	var decel: float = maxf(ctx.env.roll_decel, 0.1)
	var rolling: float = sqrt(2.0 * decel * maxf(ahead, 0.0)) / decel
	if along <= 0.01:
		return rolling
	return maxf(rolling, carry_travel(ctx, player, dir, ahead) / along)


## Probability this carry leaves the ball on the field of play.
##
## The room test above is a hard floor -- it stops a carrier walking the ball
## over a line he is running straight at -- and a hard floor is the wrong shape
## for the rest of the problem. A winger carrying it up the touchline has all
## the grass in the world along his direction and none at all beside it, so no
## test of the direction can fault the touch; what puts it out is the aim error,
## and the only honest answer is that his touch up the line is a riskier act than
## the same touch played infield. Priced, not forbidden: the softmax then turns
## him inside on its own, which is the behaviour that was wanted.
##
## Shortening the touch instead, which was the first attempt, does not help and
## may well hurt: he stays beside the line for longer and takes more touches
## there, each with its own chance of the same mistake. The measurement that
## rejected it was a single seed and too noisy to put a number on, but the
## mechanism is plain enough, and pricing the option is the engine's idiom
## anyway.
##
## Both channels of the execution model count. The yaw error opens sideways with
## distance; the weight error stretches or shortens the travel, which only
## matters for a line the touch is heading at. Sharing them with `SimTouch`
## means tuning the error model retunes what the engine is willing to try.
## `commits` is whether this is a touch he runs to the end of. The burst is the
## one that is -- not re-touching is the act -- so its ball really does travel
## the whole of `carry_travel`. Every other carry is re-taken while the ball is
## still nowhere near stopping, and asking this term about the longer journey
## charged an ordinary touch for a line the ball was never going to reach.
## Measured at eleven metres from goal with nobody recovering, that alone was
## the difference between `success` 0.19 and a carry a striker would actually
## play. See `touch_travel`.
static func _in_play_odds(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float,
		commits: bool = false) -> float:
	var travel: float = carry_travel(ctx, player, dir, ahead) if commits \
		else touch_travel(ctx, player, dir, ahead)
	if travel < 0.1:
		return 1.0
	var yaw := SimTouch.aim_sigma(ctx, player, player.attrs.dribbling, ahead, SimTouch.DRIBBLE_AIM_BASE, dir)
	# Travel goes as the square of the launch speed, so a relative error in how
	# firmly it is struck arrives roughly doubled in how far it runs.
	var stretch: float = 2.0 * SimTouch.weight_sigma(player, player.attrs.dribbling) * 1.25
	var ball := ctx.ball.ground_pos()
	var pitch := ctx.pitch
	var odds := 1.0
	odds *= _line_odds(pitch.half_length - LINE_MARGIN - ball.x, -dir.x, travel, yaw, stretch)
	odds *= _line_odds(ball.x + pitch.half_length - LINE_MARGIN, dir.x, travel, yaw, stretch)
	odds *= _line_odds(pitch.half_width - LINE_MARGIN - ball.z, -dir.z, travel, yaw, stretch)
	odds *= _line_odds(ball.z + pitch.half_width - LINE_MARGIN, dir.z, travel, yaw, stretch)
	return clampf(odds, 0.02, 1.0)


## One line's share of that: how much grass is left between the touch's landing
## point and the line, against how far the two errors can move it that way.
##
## `closing` is the component of the direction moving *away* from the line, so
## it is negative for a touch played at it -- which is also the only case where
## striking it too firmly matters.
static func _line_odds(clearance: float, closing: float, travel: float, yaw: float, stretch: float) -> float:
	var margin := clearance + travel * closing
	var sideways := yaw * travel
	var lengthways: float = stretch * travel * maxf(-closing, 0.0)
	var spread := sqrt(sideways * sideways + lengthways * lengthways)
	if spread < 1e-4:
		return 1.0 if margin >= 0.0 else 0.0
	# The same logistic approximation to a normal tail that the execution model
	# uses, one-sided.
	return clampf(1.0 / (1.0 + exp(-1.702 * margin / spread)), 0.0, 1.0)


## Which way a touch is played relative to the man closing: 1 straight away from
## him, 0 square across him, -1 straight into him.
##
## Carried on the touch for the log only. The escape value cannot stand in for
## it: that is a probability, and it comes back high for almost every direction
## the softmax would ever pick, so bucketing on it says nothing. Whether the
## carrier turned away from his man is a fact about the geometry, and it is the
## fact the complaint was about.
static func _awayness(challenger: SimPlayer, player: SimPlayer, dir: Vector3) -> float:
	if challenger == null:
		return 0.0
	var from_him := SimConsts.horizontal(player.pos - challenger.pos)
	if from_him.length() < 1e-3:
		return 0.0
	return SimConsts.horizontal(dir).normalized().dot(from_him.normalized())


## Shielding. The challenge above which a hold is played as a shield, what a
## strong shielder pays per unit of challenge instead of the bare 0.30, and the
## blend of attributes that holding a man off actually is.
const SHIELD_ON := 0.35
const SHIELD_CHALLENGE_COST := 0.16


static func shield_skill(player: SimPlayer) -> float:
	return clampf(player.attrs.strength * 0.65 + player.attrs.agility * 0.35, 0.0, 1.0)


## Beating a man with the cut. The knock past a man is a foot race; this is the other
## way, and it needs no new candidate: when a carrier at pace plays a scored
## touch sharply across a challenger who has committed at speed, the
## challenger's momentum is spent the wrong way and he is left. Resolved as a
## contest of dribbling-and-agility against tackling-and-agility, at the moment
## the touch is played -- and sometimes the man who is left brings him down
## instead, which is where the foul on the edge of the box comes from.
const BEAT_RANGE := 3.2
const BEAT_TURN := 0.6
const BEAT_BASE := 0.45
const BEAT_RECOVERY := 0.45
const BEAT_FOUL := 0.16

## Tallies for the mechanics that leave no event of their own. One-way, reset
## from `reset()` like everything else static here.
static var tally_set := 0
static var tally_dummy := 0
static var tally_shield := 0
static var tally_feint := 0
static var tally_beat := 0
static var tally_beat_foul := 0


## What a carry is worth where it puts him, over and above the grass: the shot
## he would have from there.
##
## Expected threat is a map of the pitch, and a map cannot see a situation. The
## same six metres from goal is worth 0.38 whether the keeper is set on his
## line or stranded halfway out, so a striker one-on-one read his carry as
## ordinary grass, his early shot as the only shot there was, and the ball
## back to a midfielder as the highest success on the list -- which is exactly
## the "shoots early or passes back" the owner watched. Priced as the shot,
## the carry deeper is worth what it is actually for, waiting becomes the
## winning option while the shot is still improving, and the moment it stops
## improving -- the keeper set, a body recovered into the lane -- the strike
## wins, which is the well-timed finish falling out of the scoring rather
## than being authored.
##
## `CARRY_SHOT_CONVERT` is under 1.0 because a shot now is certain to be taken
## and a shot a touch from now is not, and `score_of`'s own discount charges
## the wait on top.
const CARRY_SHOT_RANGE := 26.0
const CARRY_SHOT_CONVERT := 0.9

## The wide sibling of the pair. A carry toward the byline is worth the
## delivery it buys, and only a player-aware term can say so: the value map
## prices the byline cell level with the infield one (probed at every depth,
## `tools/_byline_probe.gd`), so the facing and control taxes turned the wide
## man infield every time and nothing ever approached the byline -- which is
## 51. Priced like the cross prices itself -- the box point's map value times
## who owns the dropping ball -- and discounted twice over `CARRY_SHOT_CONVERT`
## because the delivery is two acts away, not one.
const CARRY_DELIVERY_CONVERT := 0.55


## What a delivery from `target` would be worth, for a carry heading into
## crossing ground. The gates are the cross's own trigger asked of the horizon
## instead of the ball, so a carry is credited exactly where arriving would put
## the cross on the list.
static func _carry_delivery_gain(ctx: SimContext, player: SimPlayer, target: Vector3) -> float:
	var attack := ctx.pitch.attack_dir(player.team)
	if target.x * attack <= ctx.pitch.half_length / 3.0 \
			or absf(target.z) <= ctx.pitch.half_width * CROSS_WIDE:
		return 0.0
	var points := SimOffBall.box_targets(ctx, player.team, target)
	if points.size() == 0:
		return 0.0
	var spot: Vector3 = points[mini(1, points.size() - 1)]
	var reach := SimConsts.horizontal_length(spot - target)
	var flight: float = SimTouch.cross_flight(reach)
	var worth: float = ctx.value.xt_at(player.team, spot, ctx.pitch) \
		* ctx.value.control_at_time(ctx, spot, player.team, flight, player.id)
	# Measured flat on purpose. The length-law gradient (/ (1 + reach * 0.055))
	# was tried and pushed the term under the map everywhere -- dead. Flat, the
	# term's signal is the box: loaded it reads ~0.036 against the empty box's
	# ~0.02, which is "the wide man goes when his mates arrive" -- and the
	# probes say a few metres of direction cannot carry a gradient that beats
	# the facing tax anyway. Which direction he goes stays with `success`.
	return worth * CARRY_DELIVERY_CONVERT


static func _carry_shot_gain(ctx: SimContext, player: SimPlayer, target: Vector3) -> float:
	var goal := ctx.pitch.target_goal(player.team)
	if SimConsts.horizontal_length(goal - target) > CARRY_SHOT_RANGE:
		return 0.0
	# The compressed fit's appetite multiplies the shot he would take *now*, so
	# it has to multiply the shot he is carrying toward or the fit itself is
	# what shoots early: at urgency 0.68 the appetite is nearly 6x, and no
	# amount of patient pricing survives a 6:1 handicap. With it on both
	# sides, the fit decides how much shots are worth and the football decides
	# which shot gets taken.
	var chance := expected_goals(ctx, player, target, Vector3(goal.x, 0.9, 0.0))
	return chance * CARRY_SHOT_CONVERT * ctx.config.shot_appetite_at(chance)


## Whether a knock past the man in front is a finish round the keeper: he is
## out, he is close, the knock goes at goal, and nobody else covers. The other
## two answers to the one-on-one are `_add_chip` and the square ball in
## `_add_passes`; this one needs no candidate of its own, only the gates that
## were refusing the burst inside the box.
static func _round_the_keeper(ctx: SimContext, player: SimPlayer, dir: Vector3) -> bool:
	var goal := ctx.pitch.target_goal(player.team)
	var to_goal := SimConsts.horizontal(goal - player.pos)
	var d := to_goal.length()
	if d > 20.0 or d < 3.0:
		return false
	if dir.dot(to_goal / d) < 0.5:
		return false
	var keeper := ctx.teams[SimConsts.other_team(player.team)].keeper()
	if keeper == null or not keeper.on_pitch:
		return false
	if SimConsts.horizontal_length(goal - keeper.pos) < CHIP_KEEPER_OUT:
		return false
	if keeper.dist_to(player.pos) > 10.0:
		return false
	for oid in ctx.opponent_ids(player.team):
		var o := ctx.players[oid]
		if o.is_keeper or not o.on_pitch:
			continue
		if _near_segment(o.pos, player.pos, goal, 3.0):
			return false
	_note_rare(RARE_ROUND, false)
	return true


## Rolls the cut against the man closing. Returns true when the roll ended in a
## foul, which stops play -- the touch that was about to be played is not.
static func _try_beat(ctx: SimContext, player: SimPlayer, dir: Vector3) -> bool:
	var challenger := ctx.nearest_challenger(player)
	if challenger == null or challenger.recovery_ticks > 0:
		return false
	if challenger.dist_to(player.pos) > BEAT_RANGE:
		return false
	# It is only a cut if he changes line at pace...
	#
	# ...or a feint if he is standing still. The two are the same act at opposite
	# ends of the carrier's own momentum, and the engine only had the first: a man
	# stopped on the ball with a defender arriving could shield it or lose it, and
	# the third thing a footballer does there -- drop a shoulder from a standstill
	# and go -- was `docs/THE_FOOTBALL.md` 32's missing half.
	#
	# It is harder from nothing, because the cut spends momentum the carrier
	# already has and the feint has to manufacture it. `FEINT_COST` is what that
	# costs, applied to the same roll below, and `agility` is the attribute that
	# buys it back -- the small clever one's act, which is the roster this game is
	# built to have both ends of (`PLAN.md` §14).
	var travel := SimConsts.horizontal(player.vel)
	var standing := travel.length() < 1.5
	if standing and challenger.dist_to(player.pos) > FEINT_RANGE:
		return false
	var d := SimConsts.horizontal(dir)
	if d.length() < 1e-4:
		return false
	# A standing man has no line to change, so the turn test is about where he is
	# facing rather than where he is going -- and the body is its own state
	# now, so a man who has turned his hips has turned the defender's read.
	var from_dir := travel.normalized() if not standing \
		else SimConsts.horizontal(player.heading_dir()).normalized()
	if from_dir.length() < 1e-4:
		return false
	var swing := acos(clampf(from_dir.dot(d.normalized()), -1.0, 1.0))
	if swing < BEAT_TURN:
		return false
	# ...and only a beat if the man is committed across it. Momentum is what a
	# feint spends: a defender sitting off at a jockey is not beaten by it, so
	# what counts is his speed *toward the carrier*, not his speed.
	var to_me := SimConsts.horizontal(player.pos - challenger.pos)
	var gap := to_me.length()
	if gap < 1e-3:
		return false
	var closing: float = challenger.vel.dot(to_me / gap)
	if closing < 1.5:
		return false
	return _beat_roll(ctx, player, challenger, closing, standing)


## The odds the man is left. One model, so the candidate that prices a feint
## (`_add_feint`) and the roll that settles one read the same number.
static func beat_odds(player: SimPlayer, challenger: SimPlayer, closing: float, standing: bool) -> float:
	var edge: float = (player.attrs.dribbling * 0.6 + player.attrs.agility * 0.4) \
		- (challenger.attrs.tackling * 0.5 + challenger.attrs.agility * 0.5)
	var p: float = BEAT_BASE * clampf(0.5 + edge, 0.15, 0.95) * clampf(closing / 6.0, 0.4, 1.2)
	if standing:
		p *= lerpf(FEINT_COST, 1.0, player.attrs.agility)
	return clampf(p, 0.02, 0.7)


## The roll, and what follows it: the man left for `BEAT_RECOVERY`, or the foul.
## True when the foul stopped play.
static func _beat_roll(ctx: SimContext, player: SimPlayer, challenger: SimPlayer, closing: float, standing: bool) -> bool:
	tally_feint += 1
	if ctx.rng.chance(beat_odds(player, challenger, closing, standing)):
		tally_beat += 1
		# Left. The recovery is the turn he now has to make from a standing
		# start, and it is what the eye reads as a man being beaten.
		challenger.recovery_ticks = maxi(challenger.recovery_ticks,
			int(BEAT_RECOVERY * float(SimConsts.TICK_HZ)))
		if ctx.rng.chance(BEAT_FOUL * lerpf(0.6, 1.5, challenger.attrs.aggression)):
			tally_beat_foul += 1
			SimReferee.award_foul(ctx, challenger, player, closing)
			return true
	return false


static func _add_dribbles(ctx: SimContext, player: SimPlayer, uncontrolled: bool, challenger: SimPlayer, regain: float) -> void:
	if uncontrolled:
		return
	var tactics := ctx.tactics(player.team)
	var attack := ctx.pitch.attack_dir(player.team)
	var press: float = lerpf(1.0, 0.55, clampf(ctx.pressure_on(player), 0.0, 1.6) / 1.6)
	var skill: float = lerpf(0.62, 1.0, player.attrs.dribbling)
	# Dribbling is what keeps the ball under a man in a challenge; in open
	# grass a heavy touch runs a metre further and costs nothing. Charged flat,
	# every carry by an ordinary dribbler paid seventeen points whether or not
	# anybody was near -- measured over eight seeds, the carry was priced
	# 0.50-0.60 and kept 79%, while the pass beside it was priced 0.80 and kept
	# 78%. The tax follows the man on him; `CARRY_SKILL_FLOOR` of it always.
	var pressed: float = clampf(ctx.pressure_on(player) + ctx.challenge_on(player), 0.0, 1.0)
	var open_skill: float = lerpf(1.0, skill, maxf(pressed, CARRY_SKILL_FLOOR))
	var chal_id: int = challenger.id if challenger != null else -1
	# Having just won the ball is the worst moment to try to beat a man: the one
	# you took it from is turning back onto you and his nearest support is still
	# in the pocket. Play it, do not carry it.
	var settle: float = lerpf(1.0, 0.45, regain)
	for i in DRIBBLE_DIRS:
		var angle := TAU * float(i) / float(DRIBBLE_DIRS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		# How big a touch there is room for this way. A direction with no room
		# for even the smallest touch is not a direction he can carry the ball
		# in, and leaving it on the list was how an unpressured carrier walked
		# the ball over the line: clamped back inside the pitch, the probe
		# looked exactly like one played along it.
		var wanted := close_control(ctx, player, DRIBBLE_DISTANCE)
		var along_dir: float = maxf(player.vel.dot(dir), 0.0)
		var horizon := carry_room(ctx, player, dir, wanted)
		if horizon < SimTouch.DRIBBLE_AHEAD_FLOOR:
			continue
		# And only as big a touch as his own pace this way is worth.
		#
		# The distance he *looks* and the distance he *knocks it* are two numbers
		# and have to stay two numbers, which they briefly were not, with results
		# worth recording. Every term below is read at `pos + dir * <distance>`:
		# who owns the ground, whether the challenger beats him to it, what it is
		# worth, whether the ball stays on the field -- and, through `point`, where
		# he then runs. Sizing that off the touch made the whole risk model as
		# short-sighted as the touch was: a jogging carrier takes a 1.5 m touch, so
		# he was asking about the grass 1.5 m in front of his feet, where there is
		# never a defender and never a touchline. He ran into people and off the
		# side of the pitch, and every probe told him it was fine.
		#
		# A carry is not one touch, it is a direction he will still be going in
		# several touches from now, and `carry_room` and `close_control` already
		# say how far that direction can be pursued at all. That is the horizon to
		# price it over. The touch is the step he takes along it.
		# How far down this line he is going, which is a distance over the grass
		# and not a touch size. See `CARRY_HORIZON_SECONDS`.
		#
		# And as far as the grass will have him running. `SimMovement` paces a
		# carrier off the open lane in front of him -- from `CARRY_CLEAR` of it
		# he runs, at `CARRY_OPEN` flat out -- and the look reads the same rule,
		# so a man stood still with fifteen metres in front of him weighs the
		# carry he is about to make rather than the four metres his standing
		# pace bought. Read off the direction, at the pace it gives him, never
		# the pace he happens to have.
		var run_pace: float = SimMovement.carry_pace_for(ctx, player, dir) * player.max_speed()
		var pursuit: float = maxf(maxf(along_dir, run_pace) * CARRY_HORIZON_SECONDS, DRIBBLE_DISTANCE)
		pursuit = minf(pursuit, maxf(ctx.pitch.run_room(ctx.ball.ground_pos(), dir, LINE_MARGIN), 0.0))
		pursuit = minf(pursuit, maxf(keeper_room(ctx, ctx.ball.ground_pos(), dir, player.team, along_dir), 0.0))
		var reach: float = minf(horizon, stride_room(player, dir))
		# The size of the touch follows the room the direction actually buys, so
		# getting away from a man is a knock into space and being hemmed in is a
		# short one under the sole.
		#
		# Read off `reach` and not off `success`, which is what it used to be. The
		# score is a composite -- pitch control, the escape race, the body angle,
		# the touchline odds -- and every one of those terms is high for the
		# direction the softmax is about to pick, so taking the size from it meant
		# the chosen touch was the long one whatever the traffic in front of him.
		# This is the room, in metres, and nothing else.
		var space: float = clampf((reach - SimTouch.DRIBBLE_AHEAD_FLOOR)
			/ maxf(DRIBBLE_DISTANCE - SimTouch.DRIBBLE_AHEAD_FLOOR, 0.1), 0.0, 1.0)
		# And where that touch puts the ball, asked of the primitive that will play
		# it rather than guessed at here.
		#
		# This is the distance the horizon was never meant to stand in for. A man
		# jogging knocks it two metres and is back on it in half a second, which is
		# the carry the horizon describes. The same touch at 7 m/s is a different
		# act: his own pace goes into the strike, the ball leaves at 11, and it runs
		# twenty-six metres before he is near it again. Scored at the horizon, that
		# is a four-metre carry into open grass; played, it is a square ball to
		# whoever is standing twenty metres away, and the panel and the pitch
		# disagreed about which had happened.
		#
		# So the probe looks as far as the ball goes, or as far as the horizon,
		# whichever is further. The horizon stays because it is what stops a walking
		# carrier probing the metre in front of his feet and finding it empty; the
		# roll is added because it is where the ball ends up.
		var ahead := SimTouch.dribble_ahead(ctx, player, space, 0.0, reach)
		var look: float = maxf(pursuit, touch_travel(ctx, player, dir, ahead))
		# Bias the probe set toward the way this team attacks, so a right-back
		# does not consider dribbling into their own net as often as forward.
		var target := ctx.pitch.clamp_to_pitch(player.pos + dir * look, 1.0)
		# Where this touch actually leaves the ball, which is not where the
		# direction leads.
		#
		# The risk belongs to the touch and the reward belongs to the direction,
		# and reading both at one point is what stopped a striker running the
		# ball into the box. `target` is the horizon -- several touches down the
		# line, which is right for what a carry is *worth* -- and asking
		# `control_at_time` there means asking who owns grass six metres nearer
		# the keeper than the ball is going. Measured at twenty-two metres from
		# goal with nobody within twenty metres of him, the forward carry came
		# back at `success` **0.07** while the same probe's gain read 0.517: the
		# keeper owned the far end, so the man could never price carrying toward
		# him and struck it from where he stood instead.
		#
		# What survives here unchanged is `_lane_survival` below -- the ball's
		# own journey is this short, so the lane is this short -- and the gain
		# and the loss, which are read at the horizon because that is the
		# question they answer.
		var landing := ctx.pitch.clamp_to_pitch(
			ctx.ball.ground_pos() + dir * touch_travel(ctx, player, dir, ahead), 1.0)
		var forwardness: float = dir.x * attack
		var escape := _escape_value(challenger, player, landing)
		# When the contest at the far end happens, which is when he is there with
		# it. `control_at_time` is then the same question a ball into space is
		# priced with -- who owns that grass at the moment it matters, rather than
		# who is standing nearest to it now.
		var when := SimValueField.time_to_arrive(player, landing, 0.0)
		# A carrier arrives at his own touch with the ball, so the contest for
		# the landing is the one a ball to feet is priced with: an opponent
		# takes it only by getting in front of it and planting, and drawing
		# level is arriving second (`AIMED_STEP_IN`). The neutral race charged
		# every body half a second behind the play a third of the grass, which
		# on a two-metre touch was men six metres off who could not reach the
		# ball at all: `ctrl` read 0.81 for a free man with nine metres of
		# grass in front of him. And the challenger is priced once, in
		# `_escape_value` -- the burst's convention, which the ordinary carry
		# had missed: he was charged there, here and in the lane, three times
		# for the one race (`docs/INVARIANTS.md`, "Price the man an act is
		# about once").
		var success := ctx.value.control_at_pass(ctx, landing, player.team, when, player.id, chal_id)
		# Working the ball back across himself is a touch he is far less likely to
		# get right, and the probe set is the only place the engine can express
		# that as a *choice*. The race in `_escape_value` already charges him for
		# the momentum he has to shed to get there; this is the separate question
		# of whether the ball goes where he meant it to.
		success *= open_skill * press * escape * SimTouch.facing_control(player, dir)
		# And it is only a carry if the ball is still on the field afterwards.
		#
		# Priced on what he *wanted* to do, not on what the touchline has already
		# cut it down to, and the difference is the whole of whether this term
		# does anything. `carry_room` shortens the touch to fit the grass, so by
		# the time `horizon` comes back it is a touch that fits by construction --
		# feed that in and the lateral spread, which is the yaw error times the
		# travel, is small because the travel is small, and the odds come back
		# near one for a man running along the paint. The protection then collapses
		# to the shortening alone, which is the failure this function was written
		# to replace: he stays beside the line longer and takes more touches there,
		# each with its own chance of the same mistake.
		#
		# Asked of the full-sized carry he would like to play, the direction beside
		# the line is priced as the riskier act it is even though the touch he gets
		# is short, and the softmax turns him infield on its own.
		success *= _in_play_odds(ctx, player, dir, wanted)
		# And whether it survives the journey, which is the term a carry never had.
		#
		# A ball knocked past a man rolls through everything between here and
		# there. `control_at_time` asks who owns the far end; it cannot see the
		# defender standing eight metres along the line, because he is not near the
		# far end and never needed to be -- he sticks a leg out as it goes past. It
		# is the same question a pass is asked and the same function that answers
		# it, and a carry that outruns its own carrier *is* a pass, played to
		# whoever happens to be standing in it.
		#
		# It costs nothing on the carry that stays under his sole: the lane is two
		# metres long, and `_lane_survival` only counts opponents between the ends
		# of it.
		success *= _lane_survival(ctx, player, ctx.ball.ground_pos(), landing, when, 0.0, chal_id)
		var c_xt := ctx.value.xt_at(player.team, target, ctx.pitch)
		var c_focus := tactics.focus_at(target.z, ctx.pitch)
		# Near goal the carry is worth the shot it carries toward, not the
		# grass. See `_carry_shot_gain`.
		var c_gain: float = maxf(c_xt * c_focus, _carry_shot_gain(ctx, player, target))
		# And the delivery the direction carries toward, which is the wide
		# ground's version of the same idea.
		c_gain = maxf(c_gain, _carry_delivery_gain(ctx, player, target))
		_note_factor(SimAblation.F_FOCUS, c_xt * c_focus - c_xt)
		_note_factor(SimAblation.F_RETENTION, tactics.retention_bias())
		_candidates.append({
			"action": Action.DRIBBLE,
			"point": target,
			"end": target,
			"dir": dir,
			"escape": escape,
			"away": _awayness(challenger, player, dir),
			"success": clampf(success, 0.0, 0.98),
			"gain": c_gain,
			# Charged where the ball would be lost, which is where the touch was
			# going -- the convention every other candidate in the engine follows,
			# the knock past the man twenty lines below included. Read at the
			# carrier's own feet instead, as this was, it is the *same number for
			# all eight probes*, so the risk term cannot tell dribbling toward his
			# own goal from dribbling toward the other one.
			#
			# It is the only term that could, in one's own half. Expected threat
			# for the team in possession is flat back there -- of the order of
			# 0.0002 against the 0.013 the engine adds for merely having the ball
			# -- while the threat conceded on a turnover climbs steeply toward
			# one's own box, which is the whole reason a defender plays it long.
			"loss": ctx.value.xt_at(SimConsts.other_team(player.team), target, ctx.pitch),
			# The room the direction buys, in metres, and nothing else. Worked out
			# above, where the touch it sizes is worked out.
			"space": space,
			# And the touch that gets played has to be the touch that was scored.
			"max_ahead": reach,
			"bias": tactics.retention_bias() * lerpf(0.85, 1.1, 0.5 + forwardness * 0.5) * settle,
		})
		if debug_parts:
			_candidates[_candidates.size() - 1]["parts"] = {
				"ctrl": ctx.value.control_at_pass(ctx, landing, player.team, when, player.id, chal_id),
				"escape": escape,
				"skill_press": open_skill * press,
				"face": SimTouch.facing_control(player, dir),
				"in_play": _in_play_odds(ctx, player, dir, wanted),
				"lane": _lane_survival(ctx, player, ctx.ball.ground_pos(), landing, when, 0.0, chal_id),
			}
		_keep_factors()

	# --- Knock it past him and run -------------------------------------------
	# A carrier with a man on his shoulder and grass ahead does not take another
	# short touch under his sole. He pushes it a long way in front and turns it
	# into a foot race, which is a different option from the carry and has to be
	# on the list as one: the short probes can never express it, because at four
	# metres the challenger is still within reach of every one of them.
	#
	# It used to require a challenger, and that left a hole exactly where the
	# behaviour is most obvious to watch: a man running into an empty half has
	# nobody near enough to be `nearest_challenger`, so the only touch on offer
	# to him was a four-metre carry, and the way `SimMovement` paces a carrier --
	# off the gap between him and his own next touch -- meant he then jogged
	# after it. Knocking it into space and going is the same act whether or not
	# somebody is chasing; when nobody is, `_escape_value` returns 1.0 and
	# `control_at` ignores nobody, so the knock is priced on the grass alone.
	var running := SimConsts.horizontal(player.vel)
	if running.length() < BURST_PACE:
		return
	var burst_dir := running.normalized()
	# Round the keeper. `close_control` exists to stop the box knock giving the
	# keeper the ball, and it is exactly wrong in the one case where the keeper
	# is the man to beat: advanced, committed, with nothing behind him. There
	# the knock past *is* the finish, and the race below prices it honestly --
	# a committed keeper has all his momentum to shed.
	var round_keeper := _round_the_keeper(ctx, player, burst_dir)
	# Only as far as there is pitch to run into. The ball goes a long way further
	# than the gap it opens up -- it is struck to be `push` metres clear of a man
	# still running, so in the world frame it rolls two or three times that before
	# he catches it -- and none of that is visible to the value function, which
	# scores a point clamped back inside the touchline. Knocking it into space you
	# do not have is a throw-in, and unchecked it produced them by the dozen.
	var wanted_burst: float = BURST_DISTANCE * 0.7 if round_keeper else close_control(ctx, player, BURST_DISTANCE)
	var push := minf(wanted_burst, _room_ahead(ctx, player, burst_dir, round_keeper))
	# Beyond his stride, but still off it: the knock a man at full pace can run
	# onto is not the one a man who has just got going can.
	push = minf(push, stride_room(player, burst_dir, BURST_SECONDS))
	# In a one-on-one the man to beat is the keeper, who is never a challenger.
	var beat_man := challenger
	if round_keeper and beat_man == null:
		beat_man = ctx.teams[SimConsts.other_team(player.team)].keeper()
	# And the size of it is set by the man, not by a constant.
	#
	# A take-on is a ball put far enough past him that he cannot reach it and no
	# further -- `BURST_CLEAR` to `BURST_PAST_MAX` beyond where he stands, over
	# the grass. Left as a fixed gap the act was the same nine metres whoever was
	# in front of it and wherever he stood, which at pace is a twenty-metre ball
	# and a different act entirely. Nobody in front of him is the other case: the
	# knock into an empty half has no man to be sized by, and keeps the gap-frame
	# test it always had.
	var beat_along: float = -1.0
	if beat_man != null:
		beat_along = SimConsts.horizontal(beat_man.pos - ctx.ball.ground_pos()).dot(burst_dir)
	if beat_along > 0.0:
		push = minf(push, carry_push_for(ctx, player, burst_dir, beat_along + BURST_PAST_MAX))
		if carry_travel(ctx, player, burst_dir, push) < beat_along + BURST_CLEAR:
			return  # It does not finish past him, so it is not a foot race.
	elif push < BURST_DISTANCE * (0.35 if round_keeper else 0.55):
		return  # Not enough grass for this to be the knock it was scored as.
	# And every term below is read where the ball ends up, which is a long way
	# past where the gap opens.
	#
	# `push` is a distance between two moving things: the daylight left between
	# the ball and a man who keeps running. The ball's own journey is that plus
	# every metre he covers while it is still faster than him --
	# `travel = push + along * delta / decel`, which is `carry_travel`. At a
	# roll of 2.4 and a nine-metre knock the ball is out in front for 2.7 s, and
	# a carrier at 6 m/s runs 16 of the 25 metres it covers. Two and a half to
	# three and a half times `push`, rising with his pace.
	#
	# The ordinary carry has the same geometry and does not have the problem,
	# because he plays it again every third of a second and the gap never opens.
	# The burst is the one touch in the engine that runs to completion -- not
	# re-touching *is* the act -- so it is the only candidate whose ball really
	# travels the whole distance, and scoring it at `push` asked who owned the
	# grass, who won the race and what it was worth a third of the way there.
	# The touchline half of this was already converted, in `_room_ahead`; these
	# four terms sat four lines below it and were not.
	#
	# `carry_travel` is where the ball has slowed to his pace, which is the
	# moment he starts closing rather than the moment he arrives. The contest is
	# near there, and it is the last point on the journey the engine can name
	# without modelling the chase itself.
	var arrival := ctx.pitch.clamp_to_pitch(
		ctx.ball.ground_pos() + burst_dir * carry_travel(ctx, player, burst_dir, push), 1.0)
	# How long the ball is out there, and it is the whole of what was wrong with
	# the terms below.
	#
	# `control_at` is a snapshot: it asks who reaches a point first from where
	# everyone stands *now*, and weighs each man by how far behind the earliest
	# arrival he is. Asked about a point 43 m away that is a question with a
	# perverse answer. The carrier's own arrival is 5.5 s, the nearest defender's
	# is 2, and `CONTROL_TAU` is 0.42 -- so the man whose carry this is counts
	# `exp(-3.5 / 0.42)`, a quarter of a thousandth, and what came back as the
	# success of his burst was his *teammates'* share of grass he is the one
	# running onto. It reads about 0.28 in midfield and it is not a claim about
	# him at all. The complaint that found it was the plain one: he can never get
	# there first, and nothing in the number ever asked whether he could.
	#
	# `control_at_time` is that question asked properly. Nobody wins a ball before
	# it arrives, so every arrival is floored at the ball's journey -- which puts
	# the carrier and every defender who can cover the ground in 5.5 s on level
	# terms, and then the count of bodies decides it, which is what a ball knocked
	# into a defended third is actually decided by. It is the same function a
	# lofted pass into the box is priced with, for the same reason.
	var burst_seconds := carry_time(ctx, player, burst_dir, push)
	var burst_escape := _escape_value(beat_man, player, arrival)
	var burst_success := ctx.value.control_at_time(
		ctx, arrival, player.team, burst_seconds, beat_man.id if beat_man != null else -1)
	burst_success *= skill * burst_escape
	# The same question the carry above is asked. `_room_ahead` shortens the knock
	# to fit the grass, which stops him aiming it off the pitch, and says nothing
	# about his aiming it *near* the line and mishitting it -- and this is the
	# touch with the longest travel in the game, so the aim error has the furthest
	# to spread. Left unpriced while the carry was priced, the softmax simply
	# moved the problem: carries out of play fell by a fifth and bursts out of
	# play rose by a fifth.
	burst_success *= _in_play_odds(ctx, player, burst_dir, push, true)
	# The longest lane in the game, and the one most likely to have somebody
	# standing in it. Same term as the carry above and as every pass.
	# ...and the man it is being knocked past is not charged here as well. See
	# `_lane_survival`'s `ignore_id`: `burst_escape` above is his race and it is
	# the same man and the same act.
	burst_success *= _lane_survival(ctx, player, ctx.ball.ground_pos(), arrival, burst_seconds,
		0.0, beat_man.id if beat_man != null else -1)
	# Pace, acceleration and the room already won decide whether it comes off,
	# and all three are in the race above.
	#
	# The knock commits him past the ball: lose this one and the opponent has
	# possession *and* a man behind it, where losing a short touch leaves the
	# carrier still in the contest. That cost waited here unmodelled for a long
	# time rather than be papered over with a coefficient, and is now priced
	# where every candidate pays it -- `turnover_stretch` in `score_of` reads
	# the arrival point, and the arrival of a burst is exactly where the
	# nearest recovering shirt is furthest away.
	var b_xt := ctx.value.xt_at(player.team, arrival, ctx.pitch)
	var b_focus := tactics.focus_at(arrival.z, ctx.pitch)
	# The knock round the keeper arrives at an empty net, and only the shot
	# value can say so. Same rule as the probes above.
	var b_gain: float = maxf(b_xt * b_focus, _carry_shot_gain(ctx, player, arrival))
	_note_factor(SimAblation.F_FOCUS, b_xt * b_focus - b_xt)
	_note_factor(SimAblation.F_RETENTION, tactics.retention_bias())
	_candidates.append({
		"action": Action.DRIBBLE,
		# Where he runs, too. `_execute` hands this to the movement layer, and a
		# man who has knocked it twenty-five metres past a defender should not be
		# setting off toward the nine-metre mark.
		"point": arrival,
		"end": arrival,
		"dir": burst_dir,
		"escape": burst_escape,
		"away": _awayness(challenger, player, burst_dir),
		"success": clampf(burst_success, 0.0, 0.98),
		"gain": b_gain,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), arrival, ctx.pitch),
		# The longest action in the game, and until this it was discounted as
		# though it took a second like everything else. See `DISCOUNT_SECONDS`.
		"seconds": burst_seconds,
		"space": 1.0,
		# The execution has to push it as far as the score assumed it would. A
		# candidate scored on a nine-metre knock and then played as a four-metre
		# touch is the decision layer lying to itself about its own option.
		"push": push,
		"bias": tactics.retention_bias() * lerpf(0.9, 1.25, player.attrs.pace) * settle,
	})
	_keep_factors()


## Where the ball ends up if he holds it, which is two different places.
##
## A settling touch leaves it a metre in front of him on the grass -- that is
## what `SimTouch.settle` is for -- so his own feet are the right place to read
## it, to within a stride.
##
## A ball arriving with pace on it is not that act at all. `_play_hold` sends it
## to `SimTouch.first_touch`, which is a cushion and not a stop: an ordinary one
## leaves 2.6 to 3.5 m/s on the ball, one to two and a half metres of it, in a
## direction the receiver only partly chooses. Scored at his feet, that was the
## settling touch's bug in miniature -- the option said the ball stays here and
## the engine then moved it. `SimTouch.first_touch_drift` is the execution's own
## model asked in advance, so the two layers cannot drift apart again.
##
## Since `_hold_score` went in this feeds the loss term alone -- where the ball
## would be handed over, which for a first touch is a metre or two from where it
## was received. The gain half of the question is no longer asked here, because a
## hold is not worth the grass it sits on. It is worth what he does next.
##
## What this deliberately does not do is grade the *option* on how well he will
## take it. `success` is the chance his side still has the ball afterwards, and
## measured it is already about right: 86-92% kept three seconds later across all
## three bands of `Taking it down`, against the 0.72-0.97 this reads off the
## attribute.
static func _hold_rest_point(ctx: SimContext, player: SimPlayer, uncontrolled: bool,
		recv_dir := Vector3.ZERO) -> Vector3:
	if not uncontrolled:
		return player.pos
	var dir := recv_dir if recv_dir != Vector3.ZERO else safe_direction(ctx, player, HOLD_AHEAD)
	var drift := SimTouch.first_touch_drift(ctx, player, dir)
	return ctx.pitch.clamp_to_pitch(ctx.ball.ground_pos() + drift, 1.0)


## Where a receiving touch takes the ball, chosen rather than inherited.
##
## The receive used to play its first touch toward `safe_direction` -- forward
## if clear, sheltered otherwise -- which is the right rule for a man under a
## challenge and blind for a free one. An unpressed receiver's first touch is
## how he buys the better position (owner, 2026-08-25: receive and, under
## control, move the ball to a better angle, away from opponents), and nothing
## chose it: the direction was decided by a rule no candidate had scored, the
## same shape as `_play_hold`'s own history.
##
## Probes the compass through the touch model's own forecast
## (`first_touch_drift`, so the spot scored is where the compromised half-turn
## touch actually puts the ball) and takes the best of value and space:
## expected threat for the position, the nearest opponent's distance for "away
## from him". Sheltering still wins outright when a body is arriving -- no
## probe outweighs that.
const RECEIVE_DIRS := 8
## Metres to the nearest opponent past which a landing spot is as safe as it
## needs to be, and what full safety is worth beside expected threat. Threat
## moves ~0.01-0.02 over a touch, so 0.1 lets space dominate near a man and
## threat break the ties of a free one.
const RECEIVE_SPACE_FULL := 6.0
const RECEIVE_SPACE_WORTH := 0.1


## What taking an arriving ball down is worth against striking it first-time,
## by how free the receiver is. At 1.0 the pressed man keeps first-time
## football; the free man's end is the knob for how composed the receive looks.
const RECEIVE_FREE_BIAS := 2.2


static func _take_down_bias(ctx: SimContext, player: SimPlayer) -> float:
	var pressed := clampf(ctx.pressure_on(player) + ctx.challenge_on(player), 0.0, 1.0)
	return lerpf(RECEIVE_FREE_BIAS, 1.0, pressed)


static func receive_direction(ctx: SimContext, player: SimPlayer) -> Vector3:
	var safe := safe_direction(ctx, player, HOLD_AHEAD)
	if ctx.challenge_on(player) > 0.1:
		return safe
	var best_dir := safe
	var best := _receive_worth(ctx, player, safe)
	for i in RECEIVE_DIRS:
		var angle := TAU * float(i) / float(RECEIVE_DIRS)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var worth := _receive_worth(ctx, player, dir)
		if worth > best:
			best = worth
			best_dir = dir
	return best_dir


static func _receive_worth(ctx: SimContext, player: SimPlayer, dir: Vector3) -> float:
	var drift := SimTouch.first_touch_drift(ctx, player, dir)
	var run := SimConsts.horizontal_length(drift)
	# A drift the grass cannot hold is not a direction, and the clamped point
	# must not be scored in its place -- clamping hides that it was outside.
	if run > 0.05 and settle_room(ctx, player, drift / run, run) < run:
		return -INF
	var spot := ctx.ball.ground_pos() + drift
	var opp := ctx.nearest_to(spot, SimConsts.other_team(player.team))
	var space := 1.0
	if opp != null:
		space = clampf(opp.dist_to(spot) / RECEIVE_SPACE_FULL, 0.0, 1.0)
	return ctx.value.xt_at(player.team, spot, ctx.pitch) + space * RECEIVE_SPACE_WORTH


static func _add_hold(ctx: SimContext, player: SimPlayer, uncontrolled: bool, regain: float) -> void:
	var tactics := ctx.tactics(player.team)
	var recv_dir := Vector3.ZERO
	if uncontrolled:
		recv_dir = receive_direction(ctx, player)
	var rest := _hold_rest_point(ctx, player, uncontrolled, recv_dir)
	# Standing over the ball as a challenge comes in is how the ball is lost, and
	# it is the option the engine used to take almost every time, because the
	# pressure field it reads rates the man on the carrier's back at nearly
	# nothing. `success` is the only term here that says so.
	#
	# Unless he shields it. A hold under challenge is not a man frozen over the
	# ball, it is a man with his body between the ball and the challenger --
	# `safe_direction` already plays the touch across the man -- and how much of
	# the challenge tax that buys back is strength and balance, not luck. The
	# duel model honours the same fact from the other side (`SimDuel`), so the
	# option priced here and the contest that tests it agree.
	var success: float = lerpf(0.72, 0.97, player.attrs.first_touch)
	var shield_cost: float = lerpf(0.30, SHIELD_CHALLENGE_COST, shield_skill(player))
	success -= ctx.pressure_on(player) * 0.16 + ctx.challenge_on(player) * shield_cost
	# And a settling touch is a *check*, which a man at a sprint cannot make in
	# one touch.
	#
	# `SimTouch.settle` leaves the ball about a metre away measured against the
	# grass, with none of his pace on it -- and he keeps all of his. The distance
	# he needs to pull up in is his own, `v^2 / 2a`, and when that is longer than
	# where the ball comes to rest he runs straight past it and has to turn back.
	# Nothing said so: the hold read `success` 0.90 for a man doing nine metres a
	# second.
	#
	# Measured on `1v1-clear` trial 6: at **9.1 m/s** he settled the ball, it left
	# his foot at **3.0**, and it was 1.3 m *behind* him a quarter of a second
	# later. He braked from 9.1 to 2.4, turned, came back, and the situation had
	# lost 1.3 seconds and no ground -- the owner's "the ball ends up behind the
	# player, so he loses the momentum".
	#
	# Priced rather than forbidden, and `first_touch` is already the other half of
	# this success, so it stays what the owner asked for: something a man with bad
	# control does occasionally and a good one rarely.
	# Only for a ball already at his feet. A ball arriving with pace is taken by
	# `SimTouch.first_touch`, which is a cushion and not a stop -- it leaves pace
	# on the ball and the man running onto it keeps up with it, which is what
	# taking one down on the move is.
	if not uncontrolled:
		var pull_up: float = SimConsts.horizontal(player.vel).length_squared() \
			/ (2.0 * maxf(player.max_decel(), 0.1))
		success *= clampf(HOLD_AHEAD / maxf(pull_up, HOLD_AHEAD), 0.15, 1.0)
	_note_factor(SimAblation.F_RETENTION, tactics.retention_bias())
	_candidates.append({
		"action": Action.HOLD,
		# The receiving touch's chosen direction; ZERO for a settled ball, whose
		# hold direction stays `safe_direction`'s call at execution.
		"dir": recv_dir,
		# Not `point`: nothing executes a hold from a target, and the overlay
		# draws no arrow for it. It is where the ball would be handed over.
		"end": rest,
		"success": clampf(success, 0.05, 0.98),
		# Filled in by `_hold_score`, which is the only place a hold's value can
		# be worked out: it is the best of the other candidates, and they do not
		# exist yet. Written back so the debug overlay reports the number that
		# was used rather than one nothing reads.
		"gain": 0.0,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), rest, ctx.pitch),
		# "Take a touch rather than play a ball that is still moving" -- and how
		# strongly depends on who is near. A free receiver takes the ball down
		# and buys the better position (`receive_direction`); a pressed one has
		# no such luxury and the first-time ball keeps its place. The flat 1.5
		# this replaces gave the composed touch the same weight in both moments,
		# which is why 70% of passes were struck first-time by men nobody was
		# pressing (owner, 2026-08-25: the stressed look).
		"bias": tactics.retention_bias() * (_take_down_bias(ctx, player) if uncontrolled else 1.0)
			* lerpf(1.0, 0.5, regain),
	})
	_keep_factors()


## The setting touch: a metre out of the feet, onto the
## line of a strike the body is not set for. `strike_range` and `strike_scale`
## price what a bad facing costs; this is the act a footballer answers them
## with, made a candidate so it competes with playing something now. How far
## out of the feet it goes, what fraction of his facing the strike must have
## lost before the touch is worth a candidate, how long the beat costs (charged
## through the discount as `seconds`), and what a deferred long ball is assumed
## to complete at -- an estimate, because the real pass is scored properly on
## the next decision, once he is facing it.
const SET_AHEAD := 1.3
const SET_FACING := 0.7
const SET_SECONDS := 0.7
const SET_PASS_SUCCESS := 0.62

## The best long ball refused for facing this decision, filed by `_add_passes`.
static var _set_worth := 0.0
static var _set_point := Vector3.ZERO


static func _add_set_touch(ctx: SimContext, player: SimPlayer, uncontrolled: bool) -> void:
	if uncontrolled:
		return  # A moving ball is settled by the first touch; that act exists.
	var from := ctx.ball.pos
	var goal := ctx.pitch.target_goal(player.team)
	var best_dir := Vector3.ZERO
	var best_gain := 0.0
	# The shot he cannot hit facing this way.
	var goal_dist := SimConsts.horizontal_length(goal - from)
	if goal_dist <= 36.0 and goal_dist > 1.0:
		var scale := SimTouch.strike_scale(player, goal - from)
		if scale < SET_FACING:
			var q := expected_goals(ctx, player, from, Vector3(goal.x, 0.9, 0.0))
			var q_set: float = clampf(q / maxf(scale, 0.05), 0.0, 0.9)
			if q_set - q > 0.01:
				best_gain = q_set
				best_dir = SimConsts.horizontal(goal - from).normalized()
	# The long ball he cannot hit facing this way.
	if _set_worth > 0.0:
		var pass_gain: float = _set_worth * SET_PASS_SUCCESS
		if pass_gain > best_gain:
			best_gain = pass_gain
			best_dir = SimConsts.horizontal(_set_point - from).normalized()
	if best_gain <= 0.0 or best_dir == Vector3.ZERO:
		return
	if settle_room(ctx, player, best_dir, SET_AHEAD) < SimTouch.DRIBBLE_AHEAD_FLOOR:
		return
	# A setting touch with a man arriving is how the ball is taken off you --
	# that trade, priced, is what keeps this an act for a man with half a
	# second rather than a habit.
	var success: float = lerpf(0.75, 0.97, player.attrs.technique)
	success -= ctx.pressure_on(player) * 0.2 + ctx.challenge_on(player) * 0.5
	if success <= 0.1:
		return
	var rest := ctx.pitch.clamp_to_pitch(from + best_dir * SET_AHEAD, 1.0)
	_candidates.append({
		"action": Action.SET,
		"dir": best_dir,
		"point": ctx.pitch.clamp_to_pitch(from + best_dir * 3.0, 1.0),
		"end": rest,
		"success": clampf(success, 0.05, 0.97),
		# What the strike will be worth once he is over the ball, not the grass
		# the touch covers. `seconds` charges the beat it costs.
		"gain": best_gain,
		"seconds": SET_SECONDS,
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), rest, ctx.pitch),
		"bias": 1.0,
	})
	_keep_factors()


## The dummy: a ball arriving with pace that is better let run. The receiver
## steps over it and the man beyond, facing play, takes it instead -- the one
## act on the list that costs no touch at all, which is exactly why it wins
## when the receiver is pressed and every ball he could strike is off balance.
const DUMMY_MIN_PACE := 4.0
const DUMMY_RANGE := 16.0
const DUMMY_REACH := 2.8


static func _add_dummy(ctx: SimContext, player: SimPlayer) -> void:
	var vel := SimConsts.horizontal(ctx.ball.vel)
	var pace := vel.length()
	if pace < DUMMY_MIN_PACE:
		return
	var dir := vel / pace
	var from := ctx.ball.ground_pos()
	# The ball has to still be rolling when it gets there, so the reach of the
	# dummy is the ball's own roll.
	var roll: float = pace * pace / (2.0 * maxf(ctx.env.roll_decel, 0.1))
	var mate_id := -1
	var mate_along := INF
	for tid in ctx.teammate_ids(player.team):
		if tid == player.id:
			continue
		var mate := ctx.players[tid]
		if not mate.on_pitch or mate.is_keeper:
			continue
		var rel := SimConsts.horizontal(mate.pos - from)
		var along: float = rel.dot(dir)
		if along < 3.0 or along > minf(DUMMY_RANGE, roll - 1.0):
			continue
		if absf(rel.x * -dir.z + rel.z * dir.x) > DUMMY_REACH:
			continue
		if along < mate_along:
			mate_along = along
			mate_id = tid
	if mate_id < 0:
		return
	var mate := ctx.players[mate_id]
	var spot := from + dir * mate_along
	var when: float = clampf(mate_along / pace, 0.2, 2.0)
	# An opponent between the two cuts a dummied ball like any pass.
	var lane := _lane_survival(ctx, player, from, spot, when, FEET_TAIL)
	var success: float = lane * lerpf(0.7, 0.92, mate.attrs.first_touch)
	var xt := ctx.value.xt_at(player.team, spot, ctx.pitch)
	_note_rare(RARE_DUMMY, false)
	_candidates.append({
		"action": Action.DUMMY,
		"target": mate_id,
		"point": spot,
		"end": spot,
		"success": clampf(success, 0.02, 0.95),
		"gain": xt * ctx.tactics(player.team).focus_at(spot.z, ctx.pitch),
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), spot, ctx.pitch),
		# How long to stand out of the ball's way.
		"wait": clampf(2.5 / maxf(pace, 1.0) + 0.15, 0.25, 0.6),
		"bias": 1.0,
	})
	_keep_factors()


static func _add_clear(ctx: SimContext, player: SimPlayer) -> void:
	# Only a real option when deep and under pressure; it is a panic action.
	var own_goal := ctx.pitch.own_goal(player.team)
	var depth := absf(player.pos.x - own_goal.x)
	var chal := ctx.challenge_on(player)
	# Only a real option deep in your own territory. Anywhere else a clearance
	# is just a pass you have given away, and it puts the ball out of play.
	#
	# The exception is a man about to take it off you inside your own third.
	# Hooking it away rather than being tackled there is football; a defender who
	# never has that option has to stay in every challenge he cannot pass out of.
	#
	# Kept to the defensive third rather than the own half on purpose. Extended
	# to the halfway line it fired often enough to be the *first* answer to a
	# challenge rather than the last -- 29% of challenged touches and thirty-odd
	# clearances in ten minutes, which is a team that never plays through
	# anything. The situation is the same one; what changes with distance from
	# your own goal is whether giving the ball away is worth avoiding it.
	if depth > 26.0 and (chal < 0.8 or depth > ctx.pitch.half_length * (2.0 / 3.0)):
		return
	if depth > 18.0 and ctx.pressure_on(player) < 0.8 and chal < 0.8:
		return
	var landing := ctx.pitch.orient(player.team, Vector3(minf(player.pos.x * ctx.pitch.attack_dir(player.team) + 40.0, ctx.pitch.half_length - 5.0), 0.0, 0.0))
	_candidates.append({
		"action": Action.CLEAR,
		"end": landing,
		# A hack made with a man coming through you is not the same stroke as one
		# made in space, and if it were the clearance would be strictly the best
		# answer to a challenge: every other option's success falls as the man
		# arrives and this one used to be a flat 0.42 whatever was happening.
		"success": 0.42 * lerpf(1.0, 0.65, clampf(chal, 0.0, 1.0)),
		"gain": ctx.value.xt_at(player.team, landing, ctx.pitch) * 0.7,
		# The point of a clearance is what it avoids, so its loss term is the
		# threat it removes rather than the one it creates.
		"loss": ctx.value.xt_at(SimConsts.other_team(player.team), landing, ctx.pitch) * 0.5,
		# Deliberately not lifted by the challenge, and deliberately not lifted by
		# a regain either. The gate above already says a clearance is available
		# *because* a man is coming; paying for the same fact twice is what made it
		# the default answer to a challenge. And a clearance is the one thing a
		# player who has just won the ball should not be encouraged into -- putting
		# it back in the air is not getting it to a better place, it is giving it
		# away again, which is the very cycle the regain window exists to break.
		# With the lift on, clearances ran at three times their previous rate.
		"bias": 0.6 + clampf(ctx.pressure_on(player), 0.0, 2.0) * 0.55,
	})
	_keep_factors()


# --- Scoring and selection --------------------------------------------------


## What simply having the ball is worth, in goal probability: roughly the goals
## per match divided by the possessions per match.
##
## Without this term the engine compares only the positional value of where the
## ball ends up, and a fifty-metre punt to a well-placed striker looks better
## than a fifteen-metre pass that keeps the ball. Retention has to be on the
## books or the engine plays like a team chasing a game in the 94th minute.
##
## It is an average over the pitch, and `TERRITORY` says where.
const POSSESSION_VALUE := 0.013

## How much more a possession is worth at the far end of the pitch than at your
## own goal line, as a fraction either side of the average above.
##
## This is the term that sends the ball forward, and it is not a taste knob. It
## is there because expected threat as this engine bakes it is flat at the back
## and the flatness is not football: 0.0001 on your own eighteen-yard line, 0.004
## at the halfway line, against the 0.013 the engine adds for merely having the
## ball. Thirty-five metres of ground gained -- the whole of your own half --
## moved a candidate's score by under a third of what having the ball at all is
## worth, and `_add_passes` then multiplied that positional difference by a
## length bias of about a fifth while `POSSESSION_VALUE` went in untouched.
##
## What was left deciding between a pass forward and a pass back was `success`.
## The ball rolled back to a man with nobody near him is the highest success on
## the list by construction, so that is the ball that got played -- the same
## shape as the hold's, in `_hold_score`, from the same cause.
##
## Lifting the map instead does not work, and the reason is worth keeping. The
## map is read twice, once as `gain` where the ball is going and once as `loss`
## for the opponent at the same point, and only `gain` is scaled by the bias. Add
## the same territory to both and the loss half wins: a flatter map makes the
## *forward* pass score worse. Territory has to be priced where the bias cannot
## reach it, which is here, beside `POSSESSION_VALUE` and added after it.
##
## An ordinary ball forward is worth a slice of the ball itself, the same ball
## backwards costs the same again, and it is charged twice, because a turnover
## hands the opponent a possession by the same measure. It stays a small
## correction where expected threat is steep -- against 0.3 inside the box -- and
## is the whole positional signal where the map is flat, which is the region the
## ball would not leave.
##
## The size was 0.4 for as long as its counterweight did not exist. Territory is
## credited in metres, so the ball that gains most of it is the long one, a long
## ball escapes the length bias because this term is added after it, and measured
## at 0.75 in that engine the side stopped playing football: 37% of every ball
## long and forward at 47% completion, possessions of 1.4 passes. What should
## have been paying for that is the cost of losing it stretched, and now
## `turnover_stretch` is: the long ball is charged per candidate for landing
## where no shirt can press.
##
## Re-measured with that in, seeds 7 and 3 at ten minutes, 0.4 against 0.75: long
## forward balls 12% -> 16% of passes at 69% completion *both times*, backward
## flat at 33%, touches in the final third 9% -> 12% and 13%, shots 5 -> 14 and
## 9, possessions still three to eight passes long. The hoofball failure did not
## come back because its cause is priced now -- the counterweight is what
## changed, not the coefficient's defensibility.
##
## At 0.75 this equals `TERRITORY_URGENT` and the urgency lerp rests. A fact
## about the compressed fit having guessed the same number, not a reason to fold
## the two constants together.
const TERRITORY := 0.75

## The same term for a match compressed to three minutes. See `SimMatchConfig`,
## "the compressed match's scoring fit" — this is a fourth knob in that fit and
## belongs to it, kept here only because it reads `POSSESSION_VALUE` beside it.
##
## 0.75 is the other column of the measurement above, and the objection recorded
## there — that it stops the engine being a passing side, possessions of 1.4
## passes, a third of every ball long and forward at 47% completion — is the
## right objection to a ninety-minute match and beside the point in one holding
## fifty possessions. Measured on its own it moved goals not at all (0.39 to
## 0.32 over forty compressed matches) while raising touches in the box by a
## quarter, which is the whole reason it is here: it delivers the ball to the
## area, and the three knobs beside it are what make arriving there worth
## something.
const TERRITORY_URGENT := 0.75


## How far up the pitch a possession is worth more than at the back, for the
## match being played. See `TERRITORY` and `SimMatchConfig.urgency`.
static func territory(ctx: SimContext) -> float:
	return lerpf(TERRITORY, TERRITORY_URGENT, ctx.config.urgency())


## What having the ball at a point is worth to a team, in goal probability.
static func possession_value(ctx: SimContext, team: int, point: Vector3, ablate: int = -1) -> float:
	if ablate == SimAblation.T_POSSESSION:
		return 0.0
	var progress: float = clampf(
		point.x * ctx.pitch.attack_dir(team) / ctx.pitch.half_length, -1.0, 1.0)
	var tilt := 0.0 if ablate == SimAblation.T_TERRITORY else territory(ctx)
	return POSSESSION_VALUE * (1.0 + tilt * progress)


## What a turnover costs beyond the ball, as a multiplier on every `loss`.
##
## Expected threat answers what the *ball* is worth where it was lost, and for a
## ball given away twenty metres from their goal the answer is nothing: the
## opposition have it beside their own corner flag, which is the worst place on the
## pitch to have it. Measured, the `loss` on a through ball came back at 0.0002.
## Ninety per cent of the time it is cut out and the model says that costs you
## approximately zero.
##
## Every footballer knows it does not. What it costs is not where the ball is, it
## is where *you* are: eight men committed, a back line on the halfway line, and
## fifty metres of grass behind it for them to run into. `TERRITORY` has this
## exactly backwards -- it says a possession won deep in one's own half is worth
## less than average, which is true of building through a set defence and false of
## breaking against a side that has just lost it in your box.
##
## So the turnover is priced off the shape rather than off the ball. The reference
## is the second-deepest outfielder, which is the defensive line -- the deepest is
## often a full-back who has not got back yet, and taking the minimum would let one
## slow man tell the whole team it was safe.
##
## It scales every option's loss alike and does its discriminating through
## `(1 - success)`: an option that comes off nine times in ten hardly feels it, and
## a one-in-ten ball played with the side committed is priced as what it is. That
## is the shape a risk term should have.
const EXPOSURE_MAX := 2.5
## Where the line has to get to before any of this bites, and where it saturates,
## as a fraction of the pitch's length from one's own goal.
##
## Fitted to what this engine's shapes actually do, having first been guessed at a
## quarter and two thirds -- which sounded like football and was inert, because the
## defensive line here averages 28% up the pitch and the term therefore averaged
## 1.16 and never varied. That is the failure mode of a constant chosen from a
## mental picture rather than from the engine, and it is why the mean is printed
## in `diagnose` beside the table it feeds.
const EXPOSURE_FROM := 0.22
const EXPOSURE_TO := 0.42

## What losing the ball *there* costs beyond the ball, as a multiplier on that
## candidate's `loss`. The per-candidate half of the turnover price, beside
## `turnover_exposure`, which is per tick and therefore the same for every option
## on the list.
##
## The football is the counterpress. A ball lost among your own shirts is
## challenged within a second and often won straight back; a ball lost where you
## have nobody hands the opponent a settled possession against a side that has to
## reorganise before it can press. The engine charged both the same: `loss` reads
## what the ball is worth to them at the point, `exposure` reads how high the
## line is, and neither can tell a square ball lost in a crowd of teammates from
## a forty-metre ball lost where no shirt can reach. What held the long ball back
## was `success` alone — the burst's own note calls this "a cost to the shape
## rather than to the ball's position", and declined to paper it over.
##
## So the question asked is the plain one: how long until somebody on the losing
## side can put a challenge back on the ball? `time_to_arrive` for the nearest
## outfielder, from position and velocity, the same model every race in the
## engine runs. Inside `RECOVER_FREE` the loss is the loss already priced;
## by `RECOVER_GONE` nobody can press and the turnover costs `STRETCH_MAX`
## times the ball.
##
## This is the counterweight `TERRITORY`'s note says it is missing, and the
## reason that constant had to stay small: territory is credited in metres, the
## ball that gains most of them is the long one, and until this existed nothing
## per candidate said what losing it stretched costs.
const STRETCH_MAX := 2.0
## Seconds to a challenge at the loss point. Below the first there is no extra
## charge; the second is a press that cannot happen. Both are checked against the
## engine rather than trusted: the mean and range are printed in `diagnose`
## beside the exposure line, because `EXPOSURE_FROM`'s own note records what a
## constant chosen from a mental picture does — it sits outside the range the
## engine reaches and never varies.
const RECOVER_FREE := 1.0
const RECOVER_GONE := 3.0

## What the stretch multiplier actually came out at over the match, like
## `exposure_sum` above and for the same reason.
static var stretch_sum := 0.0
static var stretch_n := 0.0
static var stretch_hi := 0.0


static func turnover_stretch(ctx: SimContext, team: int, point: Vector3) -> float:
	var best := INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		var t := SimValueField.time_to_arrive(p, point, SimValueField.reaction_of(p))
		if t < best:
			best = t
	if is_inf(best):
		return 1.0
	var t: float = clampf((best - RECOVER_FREE) / maxf(RECOVER_GONE - RECOVER_FREE, 0.01), 0.0, 1.0)
	return lerpf(1.0, STRETCH_MAX, t)


## The applied value goes through here so the instrument counts the football and
## not the ablation pass's re-scores.
static func _stretch_applied(ctx: SimContext, team: int, point: Vector3, ablate: int) -> float:
	if ablate == SimAblation.T_STRETCH:
		return 1.0
	var out := turnover_stretch(ctx, team, point)
	if ablate < 0:
		stretch_sum += out
		stretch_n += 1.0
		if out > stretch_hi:
			stretch_hi = out
	return out


static var _exposure := PackedFloat32Array()
static var _exposure_tick := -1

## What the exposure multiplier actually came out at over the match, so a constant
## chosen for a range the engine never reaches shows up as one. Summed once per
## tick per team, alongside where the line was that made it.
static var exposure_sum := 0.0
static var exposure_line := 0.0
static var exposure_n := 0.0


## Cached per tick, because it is a fact about the shape rather than about any one
## candidate and `score_of` is called a dozen-odd times per decision.
static func turnover_exposure(ctx: SimContext, team: int) -> float:
	if _exposure.size() != 2:
		_exposure.resize(2)
		_exposure_tick = -1
	if _exposure_tick != ctx.tick_index:
		_exposure_tick = ctx.tick_index
		_exposure[0] = _measure_exposure(ctx, 0)
		_exposure[1] = _measure_exposure(ctx, 1)
	return _exposure[team] if team == 0 or team == 1 else 1.0


static func _measure_exposure(ctx: SimContext, team: int) -> float:
	var dir := ctx.pitch.attack_dir(team)
	var own_goal := ctx.pitch.own_goal(team)
	var deepest := INF
	var line := INF
	for pid in ctx.team_players[team]:
		var p := ctx.players[pid]
		if not p.on_pitch or p.is_keeper:
			continue
		var up := (p.pos.x - own_goal.x) * dir
		if up < deepest:
			line = deepest
			deepest = up
		elif up < line:
			line = up
	if is_inf(line):
		return 1.0
	var full: float = maxf(ctx.pitch.half_length * 2.0, 1.0)
	var t: float = clampf((line / full - EXPOSURE_FROM) / maxf(EXPOSURE_TO - EXPOSURE_FROM, 0.01), 0.0, 1.0)
	var out: float = lerpf(1.0, EXPOSURE_MAX, t)
	exposure_sum += out
	exposure_line += line / full
	exposure_n += 1.0
	return out


## How much a teammate's committed offer bids up the pass that serves it.
##
## The receiver's half of the decision. An off-ball run is currently a thing a
## player does *at* the ball rather than a thing he asks for: he commits, he
## runs, and the man on the ball weighs him exactly as he would weigh anybody
## standing in the same place. So a run that is ignored costs nothing and
## teaches nobody anything, which is the same complaint PLAN.md §5.3 makes about
## a pattern that fires and never resolves.
##
## Sized by how much of a claim each offer is. Coming to meet the ball is an
## invitation; going past the last defender is a demand, and it is the one that
## expires -- he is either found or he is offside, back onside, or blown.
##
## Moving into space used to be third of the three at 1.08, on the reasoning that
## it is barely more than standing well. It was, when it was a six-metre shuffle.
## It is now a nine-metre run gaining seven up the pitch, and 1.08 against the
## length bias -- which is `1 / (1 + distance x 0.21)`, so 0.19 at twenty metres
## against 0.32 at ten -- charged him for the running. Measured, a committed offer
## of any kind held about 7% of the softmax weight, against the 6% an option
## nobody favours gets on a list of seventeen: the whole receiver's half of the
## decision was worth one percentage point.
##
## These are priors on a value the decision layer was going to use anyway
## (PLAN.md §5.1), not a rule that the ball goes to whoever shouted.
const CALL_SHOW := 1.15
const CALL_SPACE := 1.3
const CALL_BEHIND := 1.5
## The man attacking the cross, and the largest of them, because his run is the
## most specific claim on the pitch: he is not offering to receive it somewhere,
## he is going to one of the three places the ball is already being aimed at.
const CALL_BOX := 1.6

## How long the man who laid it off stays a preferred option, in seconds, and
## what his return ball is worth over its map value while he does.
const GIVE_AND_GO_WINDOW := 1.4
const GIVE_AND_GO_BIAS := 1.45

## Seconds of the receiver's onward carry that a pass is credited with.
##
## Expected threat is a single-step model: it answers what the grass under the
## ball is worth and cannot answer what the man arriving on it is about to do
## with it. Those differ most for exactly the pass worth playing -- a ball in
## behind is priced as a patch of turf near the corner of the box when what it
## actually is is a striker running at an unset defence with the goal in front
## of him. `_arrival_gain` gives him this long to carry it before anyone gets
## near, and credits the pass with the threat he builds, discounted by whether
## his side will still own the ball when he gets there.
##
## It is a second step and not a solution: a real answer needs the defence's
## orientation, which the engine does not model. Kept short for that reason.
const RECEIVER_CARRY_SECONDS := 0.9
## And how long he gets when there is nobody in front of him at all.
##
## The short window was charged to every arrival alike, which made it the wrong
## number twice over: generous for a man taking it in a crowded pocket, and absurd
## for a man through on goal, who is going to run at it until somebody makes him
## stop. Measured before this went in, a through ball's `gain` was 0.038 against
## 0.097 for the option that beat it — **the most dangerous ball in football
## scored below the average of what it lost to**, because the grass it lands on
## looks like any other grass that far out.
##
## Two and a half seconds is the honest length of an unopposed run at the ball's
## pace, and it is bounded by the distance to goal, so nothing here can price a
## carry through the net. `CLEAR_BODY` is what one man in the way is worth: two
## defenders between him and the goal and the window is back to about where it
## started.
const CLEAR_CARRY_SECONDS := 2.6
const CLEAR_BODY := 0.55
## Width of the corridor a man running at goal is judged to be running in. The
## same figure the shape uses for a channel, and wider than the shot-blocking
## lane on purpose: a defender two metres off the line of his run is in front of
## him, whatever the geometry says about the ball.
const CLEAR_LANE := 6.0


## How recently this player won the ball back, as 1 at the instant of the
## regain decaying to 0 across REGAIN_WINDOW.
##
## This exists alongside the challenge field rather than inside it because the
## two describe different things. The man who has just lost the ball is often
## momentarily still -- he is carrying a recovery penalty and a touch cooldown --
## so he registers as no threat at all, while the pocket the ball was won in is
## the most crowded place on the pitch and everyone in it is about to turn round.
## A regain is a fact about the situation, not about any one opponent.
##
## Without it the roles at a turnover simply swap: the winner carries the ball
## straight back into the man he took it from, gets challenged, and the pair of
## them trade it until somebody hoofs it.
static func regain_urgency(ctx: SimContext, player: SimPlayer) -> float:
	var elapsed := float(ctx.tick_index - player.regain_tick) / float(SimConsts.TICK_HZ)
	if elapsed < 0.0 or elapsed >= REGAIN_WINDOW:
		return 0.0
	return 1.0 - elapsed / REGAIN_WINDOW


## How much the ball forward is worth in the seconds after winning it back.
##
## `secure` in `_add_passes` is the settled answer and it is the right one when
## the side that lost the ball is behind it: securing possession means finding a
## man. It is exactly wrong when they are not. A regain with their back line on
## the halfway line is the most dangerous ball in football, and the engine was
## lifting the square pass by seventy per cent and the ball in behind by nothing
## — a hundred and thirty-nine times in ten minutes, which is the most frequent
## trigger in the match wired against the attack.
##
## Whether the break is on is not a new measurement. It is `turnover_exposure`
## read from the other end: that function already prices what *we* lose by being
## stretched when we give it away, and a counter is the same fact from the side
## that just won it. Their line high, the break is on. Their line deep, it is
## not, and `secure` carries exactly as it did — which is why this cannot become
## a side that hits it long every time it wins a tackle in its own box.
static func break_on(ctx: SimContext, player: SimPlayer, regain: float) -> float:
	if regain <= 0.0:
		return 0.0
	var exposed := turnover_exposure(ctx, SimConsts.other_team(player.team))
	return regain * clampf((exposed - 1.0) / maxf(EXPOSURE_MAX - 1.0, 0.01), 0.0, 1.0)


## What `break_on` and the two multipliers hanging off it actually came out at,
## over the decisions where a pass was generated at all.
##
## `--ablate` reports `break_bias` applying to 5% of decisions and flipping none
## of them, and that is a statement about the whole match: it cannot say whether
## the counter is judged to be off because the window is closed or because the
## side that lost it was never up the pitch. So the population here is the
## decision, split at the window, and the distribution is of the number the two
## constants are multiplied through — not of the constants, which are known.
##
## The same one-way contract as every other tally in this file: written as the
## engine passes, never read back by it.
const BREAK_BUCKETS := [0.05, 0.25, 0.50, 0.75]
static var break_decisions := 0.0
static var break_in_window := 0.0
static var break_on_sum := 0.0
static var break_exposed_sum := 0.0
static var break_secure_sum := 0.0
static var break_hist := PackedInt32Array()


## Which gate refused a ball in behind to a man who was actually making the run.
##
## Link 4 of the chain, asked of the one act the whole counter is built around.
## `Chains` says a runner in behind exists in 449 decisions over five seeds and a
## through ball is offered in 214 of them, and no instrument could say what
## happened to the other 235. A gate upstream of every value knob is the thing
## this project has been caught by twice — the cross that was never a candidate,
## and the run that was scored and never committed — so it is counted before
## anything downstream of it is touched.
##
## The order is the order the gates are applied in, and each runner is filed under
## the first one he fails. `not on his list` is `_shortlist`, which keeps six of
## ten; the rest are the conditions on the candidate itself.
enum { BEHIND_UNSEEN, BEHIND_FAR, BEHIND_STILL, BEHIND_ROLE, BEHIND_SHORT, BEHIND_REACH, BEHIND_OFFERED }
const BEHIND_GATES := [
	"not on his list", "over 45 m away", "not moving forward yet", "not a runner",
	"not in behind anybody", "out of striking range", "offered",
]
static var behind_gate := PackedFloat32Array()
## Probe switch: when true, a dribble candidate carries a "parts" dictionary of
## its success factors. Off in play -- the dictionary is allocation per probe --
## and turned on only by the factor probes in tools/.
static var debug_parts := false
## The same tally again, committed runners only. The full population answers for
## generation; this one answers for the serve -- the man who has set off is who
## stage 2 of the order is about, and the shares above drown him twenty to one.
static var behind_gate_run := PackedFloat32Array()
## The distance of the ball the range gate refused, so "out of striking range"
## names a length and not just a share.
static var behind_reach_sum := 0.0
static var behind_reach_n := 0
## Per player, for the decision being built. -1 is a man who is not making the run
## and is therefore not part of the population at all.
static var _behind_state := PackedInt32Array()
static var _behind_running := PackedInt32Array()


## Opens the population for one decision: every teammate who could be played in
## behind, filed as unseen until the pass loop reaches him.
##
## **The population has to be wider than the gates it measures, and it was not.**
## It opened on `is_running_in_behind`, which is a *committed* run — and a
## committed man passes `moving_on` by construction, so `not moving forward yet`
## could never fire, and the whole projected branch of the candidate was invisible
## to the one instrument built to explain a missing ball in behind. That branch is
## the one this thread found aiming a flat 12.6 m ahead of a man whatever he was
## doing: broken, and unmeasurable, in the same place.
##
## So it opens on football instead of on a flag: an outfield teammate ahead of the
## ball is a man who could be played in behind, whatever the off-ball layer has
## decided about him. A committed runner joins whatever his position, because a run
## can begin from level with the ball. `not a runner` is the big bucket that
## results and that is the honest answer for most of them — a full-back ahead of
## the ball is not who a through ball is for, and the gates are ordered so the
## interesting ones still read underneath it.
static func _open_behind_gates(ctx: SimContext, player: SimPlayer) -> void:
	if _behind_state.size() != ctx.players.size():
		_behind_state.resize(ctx.players.size())
		_behind_running.resize(ctx.players.size())
	if behind_gate.size() != BEHIND_GATES.size():
		behind_gate.resize(BEHIND_GATES.size())
	if behind_gate_run.size() != BEHIND_GATES.size():
		behind_gate_run.resize(BEHIND_GATES.size())
	for i in _behind_state.size():
		_behind_state[i] = -1
		_behind_running[i] = 0
	var dir := ctx.pitch.attack_dir(player.team)
	for mate_id in ctx.teammate_ids(player.team):
		if mate_id == player.id:
			continue
		var mate := ctx.players[mate_id]
		if mate.is_keeper:
			continue
		var ahead := (mate.pos.x - ctx.ball.pos.x) * dir > 0.0
		if ahead or SimOffBall.is_running_in_behind(ctx, mate):
			_behind_state[mate_id] = BEHIND_UNSEEN
			if SimOffBall.is_running_in_behind(ctx, mate):
				_behind_running[mate_id] = 1


static func _note_behind_gate(mate_id: int, gate: int) -> void:
	if mate_id >= 0 and mate_id < _behind_state.size() and _behind_state[mate_id] >= 0:
		_behind_state[mate_id] = gate


## And files them, once the whole shortlist has been walked.
static func _close_behind_gates() -> void:
	for i in _behind_state.size():
		if _behind_state[i] >= 0:
			behind_gate[_behind_state[i]] += 1.0
			if i < _behind_running.size() and _behind_running[i] == 1:
				behind_gate_run[_behind_state[i]] += 1.0
			_behind_state[i] = -1


static func _note_break(on: float, exposed: float, secure: float, regain: float) -> void:
	break_decisions += 1.0
	if regain <= 0.0:
		return
	if break_hist.size() != BREAK_BUCKETS.size() + 1:
		break_hist.resize(BREAK_BUCKETS.size() + 1)
	break_in_window += 1.0
	break_on_sum += on
	break_exposed_sum += exposed
	break_secure_sum += secure
	var b := 0
	while b < BREAK_BUCKETS.size() and on >= float(BREAK_BUCKETS[b]):
		b += 1
	break_hist[b] += 1


## What a ball played forward on the break is multiplied by. Applied to the
## through ball and to a lofted ball that actually goes somewhere, never to the
## square one, which is what `secure` is for.
const BREAK_BIAS := 2.6


static func break_bias(ctx: SimContext, player: SimPlayer, regain: float) -> float:
	return lerpf(1.0, BREAK_BIAS, break_on(ctx, player, regain))


## `delay` is one further step of waiting, and only the hold passes anything but
## 1.0: it is how a deferred option is priced against the same option taken now.
## It multiplies the gain and never the loss, which is what makes waiting cost
## something at every sign -- a good option decays toward nothing while a bad one
## stays exactly as bad.
##
## `ablate` names one term to neutralise and `undo` is what that term contributed
## to this candidate; `-1` is the football, and only `SimAblation`'s pass ever
## passes anything else. The neutralisation is written here, at the point each
## term is applied, rather than in the instrument: a second copy of this formula
## would drift from this one and then report on an engine nobody is running.
static func score_of(ctx: SimContext, player: SimPlayer, c: Dictionary, delay: float = 1.0,
		ablate: int = -1, undo: float = 1.0) -> float:
	var tactics := ctx.tactics(player.team)
	var success: float = c["success"]
	var gain: float = c["gain"] * delay
	var loss: float = c["loss"]
	var bias: float = float(c.get("bias", 1.0))
	var risk := tactics.risk_weight()
	var exposure := turnover_exposure(ctx, player.team)
	if ablate >= 0:
		match SimAblation.TERM_COMPONENT[ablate]:
			SimAblation.C_SUCCESS:
				success = clampf(success / maxf(undo, 1e-6), 0.0, 1.0)
			SimAblation.C_GAIN_ADD:
				gain -= undo * delay
			SimAblation.C_BIAS:
				bias /= maxf(undo, 1e-6)
			_:
				match ablate:
					SimAblation.T_BIAS: bias = 1.0
					SimAblation.T_EXPOSURE: exposure = 1.0
					SimAblation.T_RISK: risk = 1.0
					SimAblation.T_RISK_HALF: risk = 0.0
	# Where the possession stands once the option has been played, which is what
	# decides what having it -- or handing it over -- is worth. Every candidate
	# carries it, the shot included, where it is the deep restart its `loss` is
	# already read at.
	var settles: Vector3 = c["end"]
	if c["action"] != Action.SHOOT:
		# Value that only arrives later is discounted; a high-tempo side
		# discounts harder and therefore releases the ball sooner.
		#
		# Charged per second of the action, because the actions are not the same
		# length. `future_discount` is a rate over `DISCOUNT_SECONDS`, and applying
		# it once to everything priced a five-second knock down the pitch exactly
		# as it priced a five-metre pass. A candidate that knows its own duration
		# says so; everything else is a second, which is what the flat version
		# assumed for all of them.
		gain *= pow(_discount(tactics, ablate),
			float(c.get("seconds", DISCOUNT_SECONDS)) / DISCOUNT_SECONDS)
		# The bias scales the positional value of the option, never the whole
		# expression: a penalty applied to a negative score would make a bad
		# option look better. Possession value is added after it for the same
		# reason it is not discounted: it is not a claim about a position the
		# plan has an opinion on, it is the ball.
		gain = gain * bias + possession_value(ctx, player.team, settles, ablate)
	else:
		gain *= bias
	loss += possession_value(ctx, SimConsts.other_team(player.team), settles, ablate)
	# Per candidate, where exposure is per tick: what losing it *there* costs,
	# given who could put a challenge back on it.
	loss *= exposure * _stretch_applied(ctx, player.team, settles, ablate)
	return success * gain - (1.0 - success) * risk * loss


## `future_discount`, with the instrument able to turn it off.
static func _discount(tactics: SimTactics, ablate: int) -> float:
	return 1.0 if ablate == SimAblation.T_DISCOUNT else tactics.future_discount()


## The delay one application of `tactics.future_discount()` stands for, in
## seconds, and so the duration assumed for any candidate that does not carry a
## `seconds` of its own.
##
## Implicit until a hold needed to be priced against the same option taken now,
## and wrong the moment it was left implicit. `future_discount` is a discount on
## an *action* -- a pass in flight, a carry into space, something on the order of
## a second. A hold defers by one touch cooldown, 0.17 to 0.27 s, and charging it
## a whole action's discount for a fifth of a second's wait is a units error.
##
## Measured, it is not a small one. Charged in full, the hold stops being chosen
## at all and the engine plays one-touch football: on seeds 7 and 3 at ten
## minutes, ground passes 218 and 314 against a real match's hundred-odd, carries
## down to 31 and 55, and 27 first touches in a whole match because every ball is
## played away before it is controlled. Charged per second of actual delay, one
## hold costs about four per cent and eleven in a row cost a third, which is the
## shape that was wanted.
const DISCOUNT_SECONDS := 1.0


## An unpressured man is not rushed. The discount prices "the board gets worse
## while you wait" -- and the board gets worse because somebody is closing you
## down. With nobody near, it barely does: the option decays at this fraction
## of the nominal rate, rising to the full rate as pressure arrives. Owner's
## call (DECISIONS.md, "Waiting is a first-class option"): the old flat rate
## made every free man play like a pressed one, which is the rushed look the
## dwell was built to remove. Waiting stays a losing game even at zero
## pressure -- `success` is below one and the risk half still charges -- so a
## free man dwells while his look is worth something and then plays; he does
## not stand on the ball forever.
const FREE_WAIT_COST := 0.1


## What waiting one more touch costs, as a multiplier on the deferred option.
static func _wait_discount(ctx: SimContext, player: SimPlayer, ablate: int = -1) -> float:
	var pressed := clampf(ctx.pressure_on(player) + ctx.challenge_on(player), 0.0, 1.0)
	var steps: float = player.touch_cooldown_length() / DISCOUNT_SECONDS \
		* lerpf(FREE_WAIT_COST, 1.0, pressed)
	return pow(_discount(ctx.tactics(player.team), ablate), steps)


## The beat: orient, decide, then act. A footballer who has just come by the
## ball is not set to strike it -- the body has to get over the ball and the
## decision has to finish -- so for the first half-second of a spell his
## strikes are rushed, and a rushed strike is a worse strike. The flight of the
## incoming ball is preparation he has already banked: a man a long pass was
## played to has scanned and decided while it travelled, and plays first-time
## at full accuracy. A ball won in a tackle came with no warning and earns the
## whole beat.
##
## It is a damp on `success`, not a gate: nothing is forbidden, the rushed ball
## is just priced as what it is, and the settling touch or the dwell wins the
## first decision instead -- which is the visible beat. `Clear` is exempt,
## because the panic hack is precisely an unprepared strike and taking it away
## leaves a tackled man no way out. One-touch combination football in tight
## areas is not this term's job: a pre-agreed ball is a decision already made,
## and the give-and-go and pattern biases still argue for it.
const PREPARE_SECONDS := 0.8
## How much of the beat the flight of an incoming ball can pay for. It used to
## pay all of it -- any ordinary flight banked the whole `PREPARE_SECONDS`, so
## the moment a receiver's controlled touch landed he was fully set to strike,
## and the reception was touch-pass with nothing between. The flight buys the
## scan; it cannot buy the body over the next ball, and that half starts at his
## first touch. Below `PREPARE_SECONDS` on purpose: every reception now carries
## a short visible beat -- touch, set, play -- which is the composed look the
## owner asked for (2026-08-25) in place of the machine-gun release. Above
## `SET_STRIKE_FLOOR`, also on purpose: a first-time strike at the end of a
## flight is a different act and keeps its full readiness through the other
## branch of `readiness`.
const FLIGHT_PREP_CAP := 0.1
## What a wholly unprepared strike keeps of its accuracy.
const SET_SUCCESS_FLOOR := 0.5
## And below this much orientation there is no strike at goal on the list at all.
##
## The damp above prices a rushed strike and cannot forbid one, and half of
## `success` is not enough to lose the pick against the compressed match's
## `shot_appetite`, which is 5.7 at the nine-minute clock. Measured on
## `shot-edge` (`./run.sh replay --scenario shot-edge --seed 4001 --tick 1`):
## with `set 0.50` already applied the shot scores 0.1356 against the settling
## touch's 0.0820, takes **98%** of the softmax, and is struck at **0.01 s** --
## 1.0 shots and 0.0 carries a trial, every trial, from a man who has this
## instant come by the ball with two centre-backs four metres in front of him
## (`docs/THE_FOOTBALL.md` 41).
##
## Two multipliers on opposite sides of one product cannot be compared by
## tuning either: the appetite is the compressed clock's scoring fit and is one
## object (`docs/INVARIANTS.md`), and the beat is a fact about a body. So the
## beat is a gate as well as a price, and the gate is narrow -- only a man whose
## ball is already under his control and who has had *no* look at all. A ball
## arriving with pace is a first-time strike and a different act: `readiness`
## counts its flight as preparation, and this is skipped for it besides.
## Everything above the floor is priced by the damp exactly as before.
const SET_STRIKE_FLOOR := 0.25


## Seconds of orientation this player has had: time on the ball this spell,
## plus the flight he watched before his first touch of it.
static func readiness(ctx: SimContext, player: SimPlayer) -> float:
	if ctx.ball.last_touch_player == player.id and player.spell_start_tick >= 0:
		return player.spell_prep_seconds \
			+ float(ctx.tick_index - player.spell_start_tick) * SimConsts.DT
	if ctx.ball.last_touch_tick < 0:
		return PREPARE_SECONDS
	return float(ctx.tick_index - ctx.ball.last_touch_tick) * SimConsts.DT


## Damps the strike candidates of a man who is not set yet. Runs once, after
## generation, so every builder stays ignorant of it; the recorded factor keeps
## the chain able to take it back out exactly (`SimAblation.T_SET`).
static func _apply_set_damp(ctx: SimContext, player: SimPlayer) -> void:
	var ready := clampf(readiness(ctx, player) / PREPARE_SECONDS, 0.0, 1.0)
	if ready >= 1.0:
		return
	var damp := lerpf(SET_SUCCESS_FLOOR, 1.0, ready)
	for i in _candidates.size():
		var c: Dictionary = _candidates[i]
		match int(c["action"]):
			Action.GROUND_PASS, Action.LOFTED_PASS, Action.THROUGH_BALL, \
			Action.CROSS, Action.SHOOT:
				c["success"] = clampf(float(c["success"]) * damp, 0.01, 0.98)
				# For the debug overlay, printed as `set`.
				c["set"] = damp
				if SimAblation.enabled and _cand_factors.size() >= (i + 1) * SimAblation.FACTORS:
					_cand_factors[i * SimAblation.FACTORS + SimAblation.F_SET] = damp


## The dwell: what one more look is worth to a man with time to take one.
##
## The owner watched real football and named what the engine lacks: a free man
## lets the ball roll beside him while he looks, and the pass comes a second or
## two later than this engine plays it. The engine's reason to release at once
## is structural -- waiting can never improve the board, because `_hold_score`
## prices the continuation off the board he sees now. But his board is not the
## board: `SimPerception` keeps his view of his teammates stale by design, and
## time on the ball is how a footballer buys the refresh. So a free man's
## continuation is understated by exactly as much as his picture is out of date,
## and this term puts it back.
##
## Zero under pressure -- a closed-down man has no time to look and the dwell
## must never make standing in a challenge attractive -- and zero once his
## picture is fresh, which is what ends the dwell and plays the pass. The decay
## is the perception cadence itself: awareness buys a faster scan, so the better
## reader of the game takes the shorter dwell, which is football.
const SCAN_GAIN := 1.0
## Mean teammate staleness, in seconds, that counts as a wholly out-of-date
## picture. Above it the bonus saturates.
##
## Both raised from 0.5 / 1.2: at those the look averaged 1.24 where it
## applied, flipped 5% of picks, and the owner watched a match and saw no
## dwell -- a chain of settling touches half a second long is not a behaviour,
## it is a stutter. The perception cadence keeps the mean teammate staleness
## well under the old saturation point, so the bonus rarely left the floor.
const SCAN_STALE_SECONDS := 0.7


## How much holding is worth over releasing now, 0 to `SCAN_GAIN`, as a
## fraction of the continuation.
## The run worth waiting for: the hold's continuation, priced off the board a
## live run is about to make rather than only the one he sees now.
##
## `_hold_score` prices deferring as the best current option discounted, so a
## future better than the present is invisible by construction -- and the
## through ball measured exactly that (`docs/THE_FOOTBALL.md` 33): on the list,
## the largest `gain` of any candidate, refused at `lane 0.000` because a
## defender stands on the line *now*. That is the ball a footballer waits for
## rather than declines, and nothing here could wait for it.
##
## For each floor pass aimed at a man mid-run, the same ball is asked again at
## the point the run is taking him -- `_pass_success` reused with the future
## geometry, never copied (the two-models rule) -- and the candidate's own
## success is scaled by the ratio, so every factor the run cannot change (the
## off-balance, the set damp, offside) rides along unchanged. The best of those
## futures, discounted by the wait it costs, is filed here; the hold takes the
## better of present and future. It terminates itself: as the run completes the
## future converges on the present, the edge goes to zero, and the pass is
## played. The release trigger is the run arriving, unauthored.
##
## Guards: nothing is filed for a pressed man -- the dwell's own `freedom`
## rule, a closed-down man has no time to wait for anybody; the forecast is
## capped at `DEVELOP_HORIZON`; and only the floor balls runs are served by are
## asked -- a cross's runners are the box claim's business.
const DEVELOP_HORIZON := 1.2
## A run with less than this left, in metres, is already the present board.
const DEVELOP_REMAINING_MIN := 1.0

## Best deferred ball a live run buys this decision, in score units, and the
## wait it needs. Reset every generation, like `_set_worth`.
static var _develop_value := -INF


static func _file_develop(ctx: SimContext, player: SimPlayer) -> void:
	_develop_value = -INF
	var freedom := 1.0 - clampf(ctx.pressure_on(player) + ctx.challenge_on(player), 0.0, 1.0)
	if freedom <= 0.0:
		return
	var tactics := ctx.tactics(player.team)
	var from := ctx.ball.pos
	for i in _candidates.size():
		var c: Dictionary = _candidates[i]
		var action := int(c["action"])
		if action != Action.GROUND_PASS and action != Action.THROUGH_BALL:
			continue
		var mate_id := int(c.get("target", -1))
		if mate_id < 0:
			continue
		var mate := ctx.players[mate_id]
		match SimOffBall.intent_of(ctx, mate):
			SimOffBall.SHOW, SimOffBall.SPACE, SimOffBall.BEHIND, SimOffBall.BOX, SimOffBall.SECOND:
				pass
			_:
				continue
		var dest := SimOffBall.destination_for(ctx, mate)
		if is_inf(dest.x):
			continue
		var whole := SimConsts.horizontal(dest - mate.pos)
		var remaining := whole.length()
		if remaining < DEVELOP_REMAINING_MIN:
			continue
		var speed: float = SimOffBall.pace_for(ctx, mate) * mate.max_speed()
		if speed < 0.5:
			continue
		var dt: float = clampf(remaining / speed, 0.2, DEVELOP_HORIZON)
		var aim: Vector3 = c["point"]
		var to: Vector3 = aim + whole / remaining * (speed * dt)
		# Scored where the run actually goes. A future point the pitch cannot
		# hold is no future -- clamped back it would hide that it was outside.
		if not ctx.pitch.in_bounds(to):
			continue
		var into_space := action == Action.THROUGH_BALL \
			or SimConsts.horizontal_length(aim - mate.pos) > 2.0
		var succ_now: float = maxf(_pass_success(ctx, player, from, aim,
			_pass_travel(ctx, SimConsts.horizontal_length(aim - from), tactics),
			mate, into_space), 0.01)
		var succ_fut := _pass_success(ctx, player, from, to,
			_pass_travel(ctx, SimConsts.horizontal_length(to - from), tactics),
			mate, into_space)
		var patched := c.duplicate()
		patched["success"] = clampf(float(c["success"]) * succ_fut / succ_now, 0.01, 0.98)
		patched["gain"] = float(c["gain"]) \
			+ ctx.value.xt_at(player.team, to, ctx.pitch) \
			- ctx.value.xt_at(player.team, aim, ctx.pitch)
		patched["end"] = to
		var worth := score_of(ctx, player, patched,
			pow(tactics.future_discount(), dt / DISCOUNT_SECONDS))
		if worth > _develop_value:
			_develop_value = worth


## The floor ball's flight, the way `_add_passes` computes it.
static func _pass_travel(ctx: SimContext, distance: float, tactics: SimTactics) -> float:
	var pace := arrival_pace(distance, tactics)
	return ctx.ballistics.ground_travel_time(
		distance, ctx.ballistics.ground_pass_speed(distance, pace, ctx.env), ctx.env)


static func scan_gain(ctx: SimContext, player: SimPlayer) -> float:
	var freedom := 1.0 - clampf(ctx.pressure_on(player) + ctx.challenge_on(player), 0.0, 1.0)
	if freedom <= 0.0:
		return 0.0
	var stale := 0.0
	var n := 0
	for pid in ctx.team_players[player.team]:
		var mate := ctx.players[pid]
		if mate.id == player.id or mate.is_keeper or not mate.on_pitch:
			continue
		stale += SimPerception.staleness(ctx, player, mate)
		n += 1
	if n == 0:
		return 0.0
	return SCAN_GAIN * clampf(stale / float(n) / SCAN_STALE_SECONDS, 0.0, 1.0) * freedom


## Whether an option's value depends on where this player's teammates are, which
## is the only thing a look up buys him. See the dwell in `_hold_score`.
static func _reads_teammates(action: int) -> bool:
	match action:
		Action.GROUND_PASS, Action.LOFTED_PASS, Action.THROUGH_BALL, Action.CROSS:
			return true
	return false


## What a hold is worth: the decision it defers, not the ball it keeps.
##
## Every other candidate resolves the possession. A pass ends with the ball at
## the target and a new situation on the pitch; a shot ends the possession
## outright. `score_of` states what the possession is worth afterwards, and for
## those that is a complete statement.
##
## A hold states nothing. The ball is where it was, he still has it, and he still
## has to decide -- so scoring it as `POSSESSION_VALUE` plus the grass under his
## feet credited him for retaining what was never at stake, and did it again
## every touch cooldown. Since expected threat is flat through the middle third,
## `POSSESSION_VALUE` was thirteen times the whole positional signal there and
## every candidate's gain collapsed to roughly the same number. What was left
## discriminating between them was `success` -- and the hold is the highest
## success by construction, because it is the option defined as not attempting
## anything. Measured on seed 2, one midfielder held eleven times in a row at
## 95-100% of the softmax weight, with a through ball on the list whose
## positional gain was twelve times the hold's scoring negative.
##
## So a hold is priced as one step of waiting: with `success` he still has the
## ball and faces the board he faces now, one touch later; otherwise he has lost
## it here. The continuation is the best of his other options put through
## `score_of` again with an extra `future_discount`, which is what makes deferring
## cost something -- a good option decays toward nothing while a bad one stays as
## bad, so the hold can beat a list of losing options and cannot beat a winning
## one. That is the shape that was wanted: hold because there is nothing on, never
## because holding is safe.
##
## Two things it is not. It is not a lookahead -- the board it assumes he will
## face is this one, which is exactly wrong in the case that matters most, a man
## about to be closed down. `success` carries some of that and the extra discount
## carries the rest, crudely. And it is a per-*decision* fix to what is really a
## per-*possession* problem: nothing here counts how long he has already held it,
## because the engine has no representation of a possession as a thing with a
## history. `docs/THE_FOOTBALL.md` is where that belongs.
static func _hold_score(ctx: SimContext, player: SimPlayer, c: Dictionary, best_index: int,
		ablate: int = -1, undo: float = 1.0, best_undo: float = 1.0) -> float:
	var tactics := ctx.tactics(player.team)
	var success: float = c["success"]
	var risk := tactics.risk_weight()
	var exposure := turnover_exposure(ctx, player.team)
	if ablate >= 0:
		match SimAblation.TERM_COMPONENT[ablate]:
			SimAblation.C_SUCCESS:
				success = clampf(success / maxf(undo, 1e-6), 0.0, 1.0)
			_:
				match ablate:
					SimAblation.T_EXPOSURE: exposure = 1.0
					SimAblation.T_RISK: risk = 1.0
					SimAblation.T_RISK_HALF: risk = 0.0
	var loss: float = (float(c["loss"]) + possession_value(
		ctx, SimConsts.other_team(player.team), c["end"], ablate)) * exposure \
		* _stretch_applied(ctx, player.team, c["end"], ablate)
	var continuation := 0.0
	if best_index >= 0:
		continuation = score_of(ctx, player, _candidates[best_index],
			_wait_discount(ctx, player, ablate), ablate, best_undo)
	# A prior has to move the option the same way whatever the sign of what it is
	# applied to, and multiplying does not: a bias of 1.5 on a negative
	# continuation makes waiting look *worse*, and `score_of`'s own guard --
	# ignore the bias when the value is negative -- silently drops the prior
	# instead. Both are wrong here, and the second is worse than it sounds: the
	# 1.5 on `uncontrolled` is the whole of "take a touch rather than play a ball
	# that is still moving", and in the middle third the continuation is usually
	# negative, so it was being dropped exactly where it does its work. Measured,
	# first touches fell from 142 in a match to 27. Scaling toward zero for a
	# prior above one, and away from it for one below, keeps a prior a prior.
	var raw_bias: float = float(c.get("bias", 1.0))
	if ablate == SimAblation.T_BIAS:
		raw_bias = 1.0
	elif ablate >= 0 and SimAblation.TERM_COMPONENT[ablate] == SimAblation.C_BIAS:
		raw_bias /= maxf(undo, 1e-6)
	var bias: float = maxf(raw_bias, 0.01)
	continuation = continuation * bias if continuation > 0.0 else continuation / bias
	# The dwell. Applied with the same sign guard as the bias: above zero the
	# look makes waiting worth more, below zero it makes waiting cost less --
	# both are "the board after a look is better than this one".
	#
	# **And only to a continuation a look could improve.** `scan_gain` is the
	# understatement in his continuation caused by `SimPerception` keeping his
	# view of his *teammates* stale -- that is the whole of its derivation. A
	# shot at goal, a carry and a clearance do not depend on where his teammates
	# are, so for those the understatement is zero and there is nothing to buy.
	#
	# Applied to them anyway it broke this function's own invariant. The
	# docstring above says a hold "cannot beat a winning one", and the arithmetic
	# of a man through on goal was `0.83 success x 1.05 bias x 1.28 look x 0.99
	# discount` = **1.10 times the option it was deferring** -- so waiting beat
	# acting outright, every decision, for as long as he was unpressured.
	# Measured, he took six touches, advanced nine metres of which seven were his
	# first, and then struck it from wherever the dwell had left him standing:
	# `1v1-clear` shot from 21.3 m however the shot and the carry were priced
	# (`docs/THE_FOOTBALL.md` 46, owner watching the one-on-one).
	var scan := scan_gain(ctx, player)
	if ablate == SimAblation.T_SCAN:
		scan = 0.0
	if best_index >= 0 and not _reads_teammates(int(_candidates[best_index]["action"])):
		scan = 0.0
	if scan > 0.0:
		var look := 1.0 + scan
		continuation = continuation * look if continuation > 0.0 else continuation / look
	if ablate < 0:
		# Stamped for the debug overlay, which prints it as `look`: a hold at
		# 1.0 is "nothing on", a hold above it is a dwell.
		c["scan"] = 1.0 + scan
	# The run worth waiting for. Taken *after* the bias and the look, so the
	# modeled future stands raw against the fully-blessed present: the hold
	# only waits when the ball a run is about to make genuinely beats the best
	# thing he could do now, priors and all. See `_file_develop`.
	var dev := _develop_value
	if ablate == SimAblation.T_DEVELOP:
		dev = -INF
	if dev > continuation:
		continuation = dev
		if ablate < 0:
			c["develop"] = dev
	c["gain"] = continuation
	return success * continuation - (1.0 - success) * risk * loss


## Softmax over candidate scores, never argmax. Temperature falls with the
## decisions attribute, so better decision-makers more often pick the genuinely
## best option and weaker ones make plausible-but-wrong choices.
##
## The temperature is *relative* to the spread of the candidate scores. An
## absolute temperature cannot work: scores here are goal probabilities, so the
## whole candidate list often fits inside a range of 0.02, and any fixed
## temperature is either indistinguishable from random or indistinguishable
## from argmax depending on the situation.
static func _marker_gap(ctx: SimContext, mate: SimPlayer) -> float:
	var near := ctx.nearest_to(mate.pos, SimConsts.other_team(mate.team))
	return near.dist_to(mate.pos) if near != null else 99.0


static func _softmax_pick(ctx: SimContext, player: SimPlayer) -> Dictionary:
	var n := _candidates.size()
	if _weights.size() != n:
		_weights.resize(n)

	_score_all(ctx, player, _scores, -1)
	for i in n:
		_candidates[i]["score"] = _scores[i]
	var shape := _softmax_weights(player, _scores, _weights)
	var temp := shape.x
	var spread := shape.y
	# The ball that will not arrive is not drawn. See `SUCCESS_FLOOR_POOR`.
	var floor: float = lerpf(SUCCESS_FLOOR_POOR, SUCCESS_FLOOR_GOOD, player.attrs.decisions)
	var share: float = lerpf(SHARE_FLOOR_POOR, SHARE_FLOOR_GOOD, player.attrs.decisions)
	var kept := 0
	for i in n:
		# `_softmax_weights` puts the best at exactly 1, so a weight is its
		# share of the best.
		if _floored_kind(_candidates[i]) \
				and (_weights[i] < share or float(_candidates[i]["success"]) < floor):
			_weights[i] = 0.0
		elif _weights[i] > 0.0:
			kept += 1
	if kept == 0:
		_softmax_weights(player, _scores, _weights)

	var total := 0.0
	for i in n:
		total += _weights[i]
	# What each man offering for it was worth, back to the layer that sent him.
	# A tally and nothing else -- see `SimOffBall.note_offer`.
	if total > 0.0:
		var best := -INF
		for i in n:
			best = maxf(best, _scores[i])
		for i in n:
			var offer := int(_candidates[i].get("target", -1))
			if offer >= 0:
				var at := i * PARTS
				var has_parts := _cand_parts.size() >= at + PARTS
				SimOffBall.note_offer(offer, _weights[i] / total,
					float(_candidates[i]["success"]), float(_candidates[i]["gain"]),
					float(_candidates[i]["loss"]), float(_candidates[i].get("bias", 1.0)),
					_scores[i] - best,
					_cand_parts[at + PART_SPACE] if has_parts else 0.0,
					_cand_parts[at + PART_IN_TIME] if has_parts else 0.0,
					_cand_parts[at + PART_LANE] if has_parts else 0.0,
					_cand_parts[at + PART_STRUCK] if has_parts else 0.0,
					SimConsts.horizontal_length(_candidates[i].get("point", ctx.players[offer].pos) - ctx.players[offer].pos),
					_marker_gap(ctx, ctx.players[offer]))
	var idx: int = ctx.rng.weighted_index(_weights)
	if idx < 0:
		idx = 0
	_note_rejections(player.id, idx)
	if SimChoices.enabled:
		_note_choice(ctx, player, idx)
	_last_pick = idx
	_last_temp = temp
	_last_spread = spread
	return _candidates[idx]


## Files this decision as a two-way coin between the best kind of act on the list
## and the best one that is a different kind. See `SimChoices`.
##
## Which *kind* was played, not which candidate: a pass to one man and a pass to
## another are the same act to anybody watching, and the comparison worth
## randomising is carry against pass. The propensity is therefore the weight of the
## whole kind against the whole of the other kind, which is exactly how likely the
## engine was to play one rather than the other.
## Which candidates the success floor applies to: the ball to feet and the
## carry, whose `success` is calibrated. Not the shot, whose success is a goal
## chance; and not the ball into space -- through ball, cross, cut-back -- which
## the model prices at 0.15-0.35 and which arrives 55-67% of the time
## (`docs/THE_FOOTBALL.md` 24). Floored with the rest, five matches went from
## 4.2 shots a team to 2.5 and offsides from 1.1 to 0.4: the floor was cutting
## the balls that make chances, on a number that is known to be low.
static func _floored_kind(c: Dictionary) -> bool:
	match int(c["action"]):
		Action.GROUND_PASS, Action.LOFTED_PASS:
			return not c.get("pullback", false)
		Action.DRIBBLE, Action.HOLD, Action.SET, Action.DUMMY, Action.CLEAR:
			return true
	return false


static func _note_choice(ctx: SimContext, player: SimPlayer, picked: int) -> void:
	var n := _candidates.size()
	var best := -1
	for i in n:
		if best < 0 or _scores[i] > _scores[best]:
			best = i
	if best < 0:
		return
	var kind_a := int(_candidates[best]["action"])
	var other := -1
	for i in n:
		if int(_candidates[i]["action"]) == kind_a:
			continue
		if other < 0 or _scores[i] > _scores[other]:
			other = i
	if other < 0:
		return
	var kind_b := int(_candidates[other]["action"])
	var wa := 0.0
	var wb := 0.0
	var kinds := 0
	for i in n:
		var k := int(_candidates[i]["action"])
		kinds |= 1 << k
		if k == kind_a:
			wa += _weights[i]
		elif k == kind_b:
			wb += _weights[i]
	var total := wa + wb
	if total <= 0.0:
		return
	# Whether anybody was running in behind, which is the situation the through
	# ball exists to serve and the only stage of that chain no event can reach: a
	# run nobody played to leaves nothing in the log at all.
	var flags := 0
	for mate_id in ctx.teammate_ids(player.team):
		if mate_id != player.id and SimOffBall.intent_of(ctx, ctx.players[mate_id]) == SimOffBall.BEHIND:
			flags |= SimChoices.F_RUNNER_BEHIND
			break
	SimChoices.note(ctx.tick_index, ctx.possession_id, player.team,
		kind_a, kind_b, int(_candidates[picked]["action"]), wa / total,
		ctx.ball.pos.x * ctx.pitch.attack_dir(player.team), absf(ctx.ball.pos.z),
		kinds, flags)


## Every candidate scored, with one term optionally neutralised.
##
## Two passes, because a hold is not an action in the sense the others are and
## cannot be scored beside them. See `_hold_score`.
##
## Shared by the pick and by `SimAblation`'s counterfactual, so the instrument
## cannot end up measuring a formula the engine does not play with.
static func _score_all(ctx: SimContext, player: SimPlayer, into: PackedFloat32Array,
		ablate: int) -> void:
	var n := _candidates.size()
	if into.size() != n:
		into.resize(n)
	var best_other := -INF
	var best_index := -1
	for i in n:
		if int(_candidates[i]["action"]) == Action.HOLD:
			continue
		var s := score_of(ctx, player, _candidates[i], 1.0, ablate, _undo(i, ablate))
		into[i] = s
		if s > best_other:
			best_other = s
			best_index = i
	var best_undo := _undo(best_index, ablate)
	for i in n:
		if int(_candidates[i]["action"]) == Action.HOLD:
			into[i] = _hold_score(ctx, player, _candidates[i], best_index,
				ablate, _undo(i, ablate), best_undo)


## The softmax over a set of scores, into `weights`. Returns the temperature and
## the spread it was taken from.
static func _softmax_weights(player: SimPlayer, scores: PackedFloat32Array,
		weights: PackedFloat32Array) -> Vector2:
	var n := scores.size()
	if weights.size() != n:
		weights.resize(n)
	var best := -INF
	var total_score := 0.0
	for i in n:
		total_score += scores[i]
		best = maxf(best, scores[i])
	var mean := total_score / float(n)
	var variance := 0.0
	for i in n:
		var d: float = scores[i] - mean
		variance += d * d
	var spread: float = sqrt(variance / float(n))

	var temp: float = lerpf(TEMP_POOR, TEMP_GOOD, player.attrs.decisions) * spread
	temp *= lerpf(1.3, 0.85, player.attrs.composure)
	temp /= maxf(player.fatigue_factor(), 0.6)
	temp = maxf(temp, 1e-7)

	for i in n:
		weights[i] = exp((scores[i] - best) / temp)
	return Vector2(temp, spread)


# --- What a term is worth ----------------------------------------------------
#
# See `SimAblation`. The pass below is the whole of the instrument that lives in
# this file; everything it records lives there.


static var _ab_scores := PackedFloat32Array()
static var _ab_weights := PackedFloat32Array()
static var _ab_real := PackedFloat32Array()
static var _ab_gain := PackedFloat32Array()
static var _ab_shares := PackedFloat32Array()
static var _ab_shares_now := PackedFloat32Array()


## Scores the list again with each term neutralised in turn, and records what
## that did to the choice.
##
## Run after the pick and before the touch, so what it compares against is the
## decision that was actually taken. It never draws from `ctx.rng`: the pick is
## compared on the best option rather than on a second sample, because a second
## sample would consume the stream and the match would no longer be the seed's.
static func _ablation_pass(ctx: SimContext, player: SimPlayer) -> void:
	var n := _candidates.size()
	if n == 0:
		return
	# `_hold_score` writes its continuation back into the candidate, so every
	# ablated re-score would leave behind a `gain` belonging to a match nobody
	# played -- and the overlay reads that field. Saved here, put back at the end.
	if _ab_gain.size() != n:
		_ab_gain.resize(n)
		_ab_real.resize(n)
	for i in n:
		_ab_gain[i] = float(_candidates[i].get("gain", 0.0))
		_ab_real[i] = float(_candidates[i]["score"])
	_action_shares(_weights, _ab_shares)
	var real_best := _best_of(_ab_real)

	SimAblation.note_decision()
	for term in SimAblation.TERMS:
		_note_term_values(ctx, player, term)
		_score_all(ctx, player, _ab_scores, term)
		var moved := 0.0
		var moved_n := 0
		for i in n:
			var d: float = absf(_ab_scores[i] - _ab_real[i])
			if d > 1e-9:
				moved += d
				moved_n += 1
		if moved_n == 0:
			# The term touched nothing on this list. Not a null result and not a
			# weak one: it is the term not being wired to this situation at all,
			# which is a different fault from being applied and losing.
			continue
		_softmax_weights(player, _ab_scores, _ab_weights)
		_action_shares(_ab_weights, _ab_shares_now)
		var tvd := 0.0
		for a in SimAblation.ACTIONS:
			tvd += absf(_ab_shares_now[a] - _ab_shares[a])
		var best := _best_of(_ab_scores)
		var from_action := -1
		var to_action := -1
		if best != real_best and real_best >= 0 and best >= 0:
			from_action = int(_candidates[real_best]["action"])
			to_action = int(_candidates[best]["action"])
		SimAblation.note(term, moved / float(moved_n), tvd * 0.5, from_action, to_action)

	for i in n:
		_candidates[i]["gain"] = _ab_gain[i]


## What the term itself came out at on this decision, for the range column.
##
## Read per candidate where the term is a property of the option, and once where
## it is a property of the situation. A recorded factor sitting at its neutral
## value is skipped: that is the term not applying to that candidate, and
## averaging it in would flatten the swing the column exists to show.
static func _note_term_values(ctx: SimContext, player: SimPlayer, term: int) -> void:
	var tactics := ctx.tactics(player.team)
	match term:
		SimAblation.T_TERRITORY:
			SimAblation.note_value(term, territory(ctx))
			return
		SimAblation.T_EXPOSURE:
			SimAblation.note_value(term, turnover_exposure(ctx, player.team))
			return
		SimAblation.T_RISK:
			SimAblation.note_value(term, tactics.risk_weight())
			return
		SimAblation.T_DISCOUNT:
			SimAblation.note_value(term, tactics.future_discount())
			return
		SimAblation.T_SCAN:
			# A property of the situation, noted where it applies: zero is the
			# term not biting (pressured, or picture fresh), and averaging the
			# zeros in would flatten the swing the column exists to show.
			var scan := scan_gain(ctx, player)
			if scan > 0.0:
				SimAblation.note_value(term, 1.0 + scan)
			return
	for i in _candidates.size():
		var c: Dictionary = _candidates[i]
		match term:
			SimAblation.T_BIAS:
				SimAblation.note_value(term, float(c.get("bias", 1.0)))
			SimAblation.T_POSSESSION:
				SimAblation.note_value(term, possession_value(ctx, player.team, c["end"]))
			SimAblation.T_RISK_HALF:
				var success: float = c["success"]
				SimAblation.note_value(term, (1.0 - success) * tactics.risk_weight()
					* (float(c["loss"]) + possession_value(
						ctx, SimConsts.other_team(player.team), c["end"]))
					* turnover_exposure(ctx, player.team)
					* turnover_stretch(ctx, player.team, c["end"]))
			SimAblation.T_STRETCH:
				SimAblation.note_value(term, turnover_stretch(ctx, player.team, c["end"]))
			_:
				var slot: int = SimAblation.TERM_SLOT[term]
				if slot < 0:
					continue
				var v := _undo(i, term)
				if not is_equal_approx(v, SimAblation.neutral_of(slot)):
					SimAblation.note_value(term, v)


## The softmax's weight on each kind of action, which is the distribution the
## counterfactual is compared against. Candidates are compared by what they *are*
## rather than one by one: eleven ways of passing that all lose a point of weight
## to a carry is one change to the football, not eleven.
static func _action_shares(weights: PackedFloat32Array, into: PackedFloat32Array) -> void:
	if into.size() != SimAblation.ACTIONS:
		into.resize(SimAblation.ACTIONS)
	for a in SimAblation.ACTIONS:
		into[a] = 0.0
	var total := 0.0
	for i in mini(weights.size(), _candidates.size()):
		total += weights[i]
	if total <= 0.0:
		return
	for i in mini(weights.size(), _candidates.size()):
		var a := int(_candidates[i]["action"])
		if a >= 0 and a < SimAblation.ACTIONS:
			into[a] += weights[i] / total


static func _best_of(scores: PackedFloat32Array) -> int:
	var best := -1
	for i in mini(scores.size(), _candidates.size()):
		if best < 0 or scores[i] > scores[best]:
			best = i
	return best


# --- Execution --------------------------------------------------------------


static func _execute(ctx: SimContext, player: SimPlayer, c: Dictionary, uncontrolled: bool) -> void:
	var action: int = c["action"]
	var xv: float = float(c.get("score", 0.0))
	var ft := bool(c.get("first_time", false))
	match action:
		Action.SHOOT:
			# The candidate's signed bend executes, as the pass's does.
			if c.has("curl"):
				_note_rare(RARE_TRIVELA if c.get("trivela", false) else RARE_BEND, true)
			SimTouch.shot(ctx, player, c["aim"], c["power"], c["first_time"], c["success"],
				bool(c.get("chip", false)), float(c.get("curl", NAN)),
				bool(c.get("trivela", false)))
		Action.GROUND_PASS:
			# The candidate's signed bend executes -- never `curl_for` re-read
			# here, where the foot could disagree with the one that was priced.
			if c.has("curl"):
				_note_rare(RARE_TRIVELA if c.get("trivela", false) else RARE_BEND, true)
			SimTouch.ground_pass(ctx, player, c["point"], c["pace"], c["target"],
				SimTelemetry.Touch.GROUND_PASS, xv, ft, float(c.get("curl", NAN)),
				bool(c.get("trivela", false)))
		Action.THROUGH_BALL:
			SimTouch.ground_pass(ctx, player, c["point"], c["pace"], c["target"], SimTelemetry.Touch.THROUGH_BALL, xv, ft)
		Action.LOFTED_PASS:
			SimTouch.lofted_pass(ctx, player, c["point"], c["flight"], c["target"], SimTelemetry.Touch.LOFTED_PASS,
				SimTouch.curl_for(ctx, player, c["point"] - ctx.ball.pos, SimTouch.LOFT_CURL, SimTouch.LOFT_CURL_SIGMA), xv, ft)
		Action.CROSS:
			SimTouch.lofted_pass(ctx, player, c["point"], c["flight"], c["target"], SimTelemetry.Touch.CROSS,
				SimTouch.curl_for(ctx, player, c["point"] - ctx.ball.pos, SimTouch.CROSS_CURL, SimTouch.CROSS_CURL_SIGMA), xv, ft)
		Action.DRIBBLE:
			if c.has("opening"):
				_note_rare(RARE_OPENING, true)
			if _try_beat(ctx, player, c["dir"]):
				return  # The cut drew the foul; play is stopping.
			SimTouch.dribble(ctx, player, c["dir"], c["space"], float(c.get("push", 0.0)), float(c.get("away", 0.0)), float(c.get("max_ahead", INF)))
			player.move_target = c["point"]
			player.move_speed_cap = INF
		Action.FEINT:
			# The body sold at the man, the ball untouched for the hold, and
			# the man rolled for now: he has committed, and what he has
			# committed to is settled here. The knock past him is the next
			# decision's, with the man in recovery and the body to turn back.
			_note_rare(RARE_FEINT, true)
			var sell: Vector3 = c["sell"]
			player.look_target = player.pos + sell * 2.0
			player.touch_cooldown = maxf(player.touch_cooldown, FEINT_HOLD)
			ctx.log_event(SimTelemetry.Ev.FEINT, {
				"player": player.id, "team": player.team, "pos": ctx.ball.ground_pos(),
			})
			var challenger := ctx.nearest_challenger(player)
			if challenger != null and challenger.recovery_ticks <= 0:
				var gap := challenger.dist_to(player.pos)
				if gap > 1e-3:
					var closing: float = challenger.vel.dot(
						SimConsts.horizontal(player.pos - challenger.pos) / gap)
					_beat_roll(ctx, player, challenger, closing, true)
		Action.CLEAR:
			SimTouch.clearance(ctx, player)
		Action.SET:
			# The setting touch: a metre out of the feet, onto the line of the
			# strike it was scored for. The turn happens as he steps onto it.
			player.settling = true
			tally_set += 1
			SimTouch.settle(ctx, player, c["dir"], settle_room(ctx, player, c["dir"], SET_AHEAD))
		Action.DUMMY:
			# He lets it run. No touch is played; the cooldown is what stops him
			# being a contender again while the ball goes past him.
			tally_dummy += 1
			player.touch_cooldown = maxf(player.touch_cooldown, float(c.get("wait", 0.4)))
		Action.HOLD:
			_play_hold(ctx, player, uncontrolled, c.get("dir", Vector3.ZERO))
		_:
			_play_hold(ctx, player, uncontrolled)


## Plays the hold: a settling touch that leaves the ball where it is.
##
## The size is the whole of this function, and it used to be `space` 0.15, which
## is a 2.2 m knock. A hold is scored as the ball *not moving* -- `_add_hold`
## reads its gain and its loss at the player's own feet, and calls itself "safe
## but goes nowhere" -- and it was then executed as two metres of ground covered
## in a direction no candidate had been scored for. Measured on seed 7, three
## quarters of every carry touch in the match came out of here rather than out of
## the eight scored probes: 403 of 527, one every 0.47 s, 2.08 m at a time.
##
## Both halves of "he runs into people and off the side of the pitch" are that
## number. Nothing on this path asks what is in front of him, nothing asks where
## the touchline is, and nothing shortens the touch in the penalty area, because
## all three of those live in `_add_dribbles` and this is not `_add_dribbles`.
## Split by which path played them, the carries that went out of play near a line
## were *all* holds, and holds were three times as likely as a scored dribble to
## be knocked into a body four to fifteen metres up the lane -- which lost the
## ball inside two seconds about 45% of the time, against 15% for a clear one.
##
## So the hold is a hold: the smallest touch the engine has, which is what makes
## the scored option and the played one the same option again. Covering ground is
## `_add_dribbles`' job, it is offered on every decision, and it is priced.
## `close_control` is not consulted because it could not bite -- a hold is
## already shorter than the touch it would shorten to -- but `carry_room` is,
## because a metre played at a line the man is standing on is still a metre too
## far.
static func _play_hold(ctx: SimContext, player: SimPlayer, uncontrolled: bool,
		recv_dir := Vector3.ZERO) -> void:
	if uncontrolled:
		# The direction the candidate was scored on (`receive_direction`), so
		# the spot the option priced is the spot the touch goes to.
		var chosen := recv_dir if recv_dir != Vector3.ZERO \
			else safe_direction(ctx, player, HOLD_AHEAD)
		SimTouch.first_touch(ctx, player, chosen)
		return
	var dir := safe_direction(ctx, player, HOLD_AHEAD)
	player.settling = true
	# A hold with a challenger on it is a shield: the body goes between the man
	# and the ball. The flag is what the duel reads, and what marks the touch so
	# the log can tell holding a man off from standing over the ball.
	if ctx.challenge_on(player) > SHIELD_ON:
		player.shielding = true
		tally_shield += 1
	SimTouch.settle(ctx, player, dir, settle_room(ctx, player, dir, HOLD_AHEAD))


## Where to take a settling touch: forward if the way is clear and there is grass
## for it, out of the way of whoever is in it otherwise.
##
## Sheltering the ball is not allowed to cost ground, and that restriction is
## the whole of this function's difficulty. A hold is scored as keeping the ball
## where it is and then *executed* as a real touch, so whatever direction comes
## back here the ball actually travels along it -- a metre now, and two before
## `_play_hold` made the touch the size the score assumed. Read literally, "away
## from the nearest man" points at one's own goal for as long as he is goal-side
## -- which, since the recovery run went in, is most of the time a carrier is
## under pressure. Ten holds in a row is then a twenty-metre retreat to one's own
## byline that no candidate was ever scored for and no decision was ever taken:
## measured on seed 1 it ran six seconds and 22 metres, with the man on his back
## the whole way.
##
## What is left once the retreating component is stripped out is the act the
## original was reaching for. The ball goes *across* the man rather than away
## from him -- side-on, out of his reach, conceding nothing behind. Dropping
## back with the ball is still available; it is available where it belongs, in
## the eight scored dribble probes and in a pass, both of which price the ground
## they give up.
## Public because `SimAerial` asks the same question of a ball taken down off the
## chest: he is not choosing between candidates, he is putting the ball somewhere
## he can still play it.
static func safe_direction(ctx: SimContext, player: SimPlayer, ahead: float) -> Vector3:
	var forward := SimConsts.horizontal(ctx.pitch.target_goal(player.team) - player.pos)
	if forward.length() < 0.1:
		return player.heading_dir()
	forward = forward.normalized()
	var blocker := _hold_obstacle(ctx, player, forward, ahead)
	if blocker == null and _hold_fits(ctx, player, forward, ahead):
		return forward
	if blocker != null:
		var away := SimConsts.horizontal(player.pos - blocker.pos)
		if away.length() >= 0.1:
			var dir := forward * 0.4 + away.normalized()
			dir -= forward * minf(dir.dot(forward), 0.0)
			if dir.length() > 0.2:
				dir = dir.normalized()
				if _hold_fits(ctx, player, dir, ahead):
					return dir
	# He is squarely between the carrier and the goal, so there is no forward
	# component of "away" left to keep -- or the way out is at a line. The ball
	# goes square, to whichever side has the pitch to take it: a hold that
	# shelters the ball into the touchline is a throw-in with extra steps.
	var square := Vector3(-forward.z, 0.0, forward.x)
	if ctx.pitch.run_room(player.pos, square, 1.0) < ctx.pitch.run_room(player.pos, -square, 1.0):
		square = -square
	return square


## Whether a settling touch this way has the grass to be played at all.
##
## The same question `_add_dribbles` asks of each of its eight probes, and the
## same gate: a direction with no room for even the smallest touch is not a
## direction the ball can go. Nothing on the hold path asked it, which is why
## every carry that went out of play beside a line was one -- the forward branch
## returned "at the goal" from two metres inside the byline and the touch was
## played with nothing to shorten it.
static func _hold_fits(ctx: SimContext, player: SimPlayer, dir: Vector3, ahead: float) -> bool:
	return settle_room(ctx, player, dir, ahead) >= SimTouch.DRIBBLE_AHEAD_FLOOR


## The man a settling touch has to be sheltered from: whoever is close enough to
## reach it, either standing over the carrier already or waiting down the line
## the ball is about to be played along.
##
## The second half is the new one. This used to be `nearest_opponent` inside four
## metres, full stop, and that is both too short and the wrong shape. Too short:
## `CHALLENGE_SIGHT` is 5.5 m, so a man the rest of the engine already considers
## an imminent challenge did not register here at all. Wrong shape: it is the
## nearest man in *any* direction, so a marker three metres behind the carrier
## moved the touch and a defender six metres dead in front of him did not.
## Measured, that is where the ball went -- 28% of holds were knocked into a body
## four to fifteen metres up the lane, and they lost it inside two seconds about
## 45% of the time.
##
## How far down the lane to look is not a constant, because the answer depends on
## how fast the man is going: the ball runs further from a moving carrier for the
## same touch, and `carry_travel` already says how much further. A standing
## player looks about five metres, a man at full pace about ten, from one rule
## rather than two. The floor is the old radius, which is the man on his back.
const HOLD_SHELTER := 4.0
## Half the width of the lane, a body and a step either side of the line the ball
## takes.
const HOLD_LANE := 3.0


static func _hold_obstacle(ctx: SimContext, player: SimPlayer, forward: Vector3, ahead: float) -> SimPlayer:
	var look := carry_travel(ctx, player, forward, ahead) + HOLD_SHELTER
	var best: SimPlayer = null
	var best_d := INF
	for j in ctx.opponent_ids(player.team):
		var o: SimPlayer = ctx.players[j]
		if not o.on_pitch:
			continue
		var to := SimConsts.horizontal(o.pos - player.pos)
		var d := to.length()
		if d >= best_d:
			continue
		if d < HOLD_SHELTER:
			best = o
			best_d = d
			continue
		var along := to.dot(forward)
		if along > 0.0 and along < look and absf(to.x * -forward.z + to.z * forward.x) < HOLD_LANE:
			best = o
			best_d = d
	return best


## True if `point` lies within `radius` of the segment from `a` to `b` -- or,
## given a `bow`, of the curled path over the same chord: offset by
## 4*bow*t*(1-t) at each station, positive toward the striker's left
## (`SimBallistics.curl_bow`'s sign). The station stays the chord projection,
## the same approximation `_cut_chance` accepts and says why.
static func _near_segment(point: Vector3, a: Vector3, b: Vector3, radius: float, bow: float = 0.0) -> bool:
	var ab := SimConsts.horizontal(b - a)
	var length_sq: float = ab.length_squared()
	if length_sq < 1e-6:
		return SimConsts.horizontal_length(point - a) <= radius
	var t: float = clampf(SimConsts.horizontal(point - a).dot(ab) / length_sq, 0.0, 1.0)
	var at := a + ab * t
	if bow != 0.0:
		var dir := ab / sqrt(length_sq)
		at += Vector3(-dir.z, 0.0, dir.x) * (-4.0 * bow * t * (1.0 - t))
	return SimConsts.horizontal_length(point - at) <= radius
