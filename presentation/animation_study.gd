extends RefCounted
## Controlled snapshots for inspecting the match poser, not football outcomes.

const TITLES := ["Movement", "Ball control", "Player contact", "Landing and getting up", "Catches and volleys"]
const SECONDS := 8.0


static func movement(t: float) -> Vector3:
	if t < 2.0:
		return Vector3(lerpf(-4.0, 4.0, smoothstep(0.0, 2.0, t)), 0.0, 0.0)
	if t < 3.0:
		return Vector3(4.0, 0.0, 0.0)
	if t < 5.0:
		return Vector3(lerpf(4.0, -2.0, smoothstep(3.0, 5.0, t)), 0.0, 0.0)
	return Vector3(-2.0, 0.0, lerpf(0.0, 2.0, smoothstep(6.0, 7.5, t)))


static func sample(s: SimSnapshot, group: int, tick: int) -> String:
	var t := float(tick) * SimConsts.DT
	var clip := mini(int(t / 2.0), 3)
	var u := t - float(clip) * 2.0
	s.tick = tick
	s.clock = t
	s.in_play = true
	s.player_on_pitch.fill(0)
	s.player_on_pitch[0] = 1
	s.player_on_pitch[1] = 1 if group == 2 else 0
	s.player_anim.fill(SimConsts.Anim.IDLE)
	s.player_vel.fill(Vector3.ZERO)
	s.player_facing.fill(0.0)
	s.player_shielding.fill(0)
	s.player_strike.fill(-1)
	s.player_plant.fill(-1)
	s.player_contact.fill(Vector3.INF)
	s.player_sidefoot.fill(0)
	s.player_touch_kind.fill(-1)
	s.player_touch_tick.fill(-1)
	s.player_touch_pos.fill(Vector3.INF)
	s.player_touch_in.fill(Vector3.ZERO)
	s.player_touch_out.fill(Vector3.ZERO)
	s.player_team[0] = 0
	s.player_team[1] = 1
	s.player_pos[0] = Vector3.ZERO
	s.player_pos[1] = Vector3(1.2, 0.0, 0.0)
	s.player_foot[0] = SimAttributes.FOOT_LEFT if clip % 2 == 0 else SimAttributes.FOOT_RIGHT
	s.ball_pos = Vector3(0.5, SimConsts.BALL_RADIUS, 0.0)
	s.ball_vel = Vector3.ZERO
	s.ball_spin = Vector3.ZERO
	var contact := Vector3(0.45, SimConsts.BALL_RADIUS, 0.0)
	var age := u - 0.5
	var at := int(round((float(clip) * 2.0 + 0.5) / SimConsts.DT))
	match group:
		0:
			s.player_pos[0] = movement(t)
			s.player_vel[0] = (movement(t + 0.001) - movement(maxf(t - 0.001, 0.0))) / 0.002
			s.player_facing[0] = PI * smoothstep(5.0, 6.0, t)
			s.player_anim[0] = SimConsts.Anim.RUN if s.player_vel[0].length() > 0.1 else SimConsts.Anim.IDLE
			s.ball_pos = Vector3(0.0, SimConsts.BALL_RADIUS, -3.0)
			return "Accelerate and brake" if t < 3.0 else ("Backpedal" if t < 5.0 else ("Turn in place" if t < 6.0 else "Side steps"))
		1:
			var trap := clip < 2
			var incoming := Vector3(4.0, 0.0, 0.0) if trap else Vector3.ZERO
			var outgoing := Vector3(0.4 if trap else 1.6, 0.0, 0.0)
			if trap:
				contact.x = -0.45
				s.player_facing[0] = PI
			else:
				s.player_pos[0].x = age * 0.8
				s.player_vel[0].x = 0.8
				s.player_anim[0] = SimConsts.Anim.JOG
			s.ball_pos = contact + (incoming if age < 0.0 else outgoing) * age
			s.ball_vel = incoming if age < 0.0 else outgoing
			if age >= 0.0:
				_touch(s, at, SimTelemetry.Touch.FIRST_TOUCH if trap else SimTelemetry.Touch.DRIBBLE, contact, incoming, outgoing)
				if age < (0.35 if trap else 0.4):
					s.player_anim[0] = SimConsts.Anim.TRAP if trap else SimConsts.Anim.KICK_LIGHT
			return ("Cushion a pass" if trap else "Nudge while moving") + _foot_name(s)
		2:
			if clip < 2:
				s.player_shielding[0] = 1
				s.player_pos[1] = Vector3(-0.3, 0.0, -0.65 if clip == 0 else 0.65)
				return "Shield: opponent on the " + ("right" if clip == 0 else "left")
			s.player_facing[1] = PI
			s.ball_pos = contact + Vector3(maxf(age, 0.0) * 1.5, 0.0, 0.0)
			if age >= 0.0:
				_touch(s, at, SimTelemetry.Touch.TACKLE, contact, Vector3(-1.0, 0.0, 0.0), Vector3(1.5, 0.0, 0.0))
				if age < 0.45:
					s.player_anim[0] = SimConsts.Anim.TACKLE
			return "Standing tackle" + _foot_name(s)
		3:
			if clip < 2:
				contact = Vector3(0.0, 2.0, 0.0)
				s.ball_pos = contact + Vector3(age * 2.0, -age * 0.3, 0.0)
				if age >= 0.0:
					_touch(s, at, SimTelemetry.Touch.HEADER, contact, Vector3(2.0, -0.3, 0.0), Vector3(2.0, 0.0, 0.0))
					if age < 0.45:
						s.player_anim[0] = SimConsts.Anim.HEADER if clip == 0 else SimConsts.Anim.JUMP
				return "Header and landing" if clip == 0 else "Jump and landing"
			s.ball_pos = Vector3(0.0, SimConsts.BALL_RADIUS, -3.0)
			if u < 1.2:
				s.player_anim[0] = SimConsts.Anim.FALL
			elif u < 1.8:
				s.player_anim[0] = SimConsts.Anim.GET_UP
			return "Fall, brace, kneel and stand"
		4:
			var catching := clip < 2
			contact = Vector3(0.4, (0.45 if clip == 0 else 1.8) if catching else 0.65, 0.0)
			var incoming := Vector3(-3.0, 0.0, 0.0)
			var outgoing := Vector3.ZERO if catching else Vector3(4.0, 1.0, 0.0)
			s.ball_pos = contact + incoming * age if age < 0.0 else contact + outgoing * age
			if age >= 0.0:
				_touch(s, at, SimTelemetry.Touch.KEEPER_CATCH if catching else SimTelemetry.Touch.SHOT, contact, incoming, outgoing)
				if catching:
					s.ball_pos = contact.lerp(Vector3(SimKeeper.HOLD_REACH, SimKeeper.HOLD_HEIGHT, 0.0), smoothstep(0.0, 0.5, age))
					s.player_anim[0] = SimConsts.Anim.KEEPER_CATCH if age < 0.6 else SimConsts.Anim.KEEPER_HOLD
				elif age < 0.4:
					s.player_anim[0] = SimConsts.Anim.VOLLEY
			return ("Low catch" if clip == 0 else "High catch") if catching else "Volley" + _foot_name(s)
	return ""


static func _foot_name(s: SimSnapshot) -> String:
	return " — left foot" if s.player_foot[0] == SimAttributes.FOOT_LEFT else " — right foot"


static func _touch(s: SimSnapshot, tick: int, kind: int, at: Vector3, incoming: Vector3, outgoing: Vector3) -> void:
	s.player_touch_tick[0] = tick
	s.player_touch_kind[0] = kind
	s.player_touch_pos[0] = at
	s.player_touch_in[0] = incoming
	s.player_touch_out[0] = outgoing
	if SimTouch.is_footed(kind):
		s.player_strike[0] = tick
		s.player_contact[0] = at
		s.player_strike_line[0] = SimConsts.horizontal(outgoing).normalized()
