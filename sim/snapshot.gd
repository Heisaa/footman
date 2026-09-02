class_name SimSnapshot
extends RefCounted
## A flat, read-only view of the simulation for the presentation layer.
##
## Presentation reads snapshots and never writes back (PLAN.md §2.3). The sim
## runs on its own fixed clock; Godot interpolates between the last two
## snapshots for smooth display, whether the sim is being stepped 60 times a
## second or as fast as the machine can manage.

var tick := 0
var clock := 0.0
var period := SimConsts.Period.FIRST_HALF
var phase := SimConsts.Phase.KICKOFF

var ball_pos := Vector3.ZERO
var ball_vel := Vector3.ZERO
var ball_spin := Vector3.ZERO

var player_count := 0
var player_id := PackedInt32Array()
var player_team := PackedInt32Array()
var player_shirt := PackedInt32Array()
var player_pos := PackedVector3Array()
var player_vel := PackedVector3Array()
var player_facing := PackedFloat32Array()
var player_stamina := PackedFloat32Array()
var player_anim := PackedInt32Array()
## The foot the last footed touch was struck with (`SimAttributes.FOOT_*`), so
## a kick and a hold are posed on the foot that played them.
var player_foot := PackedInt32Array()
## 1 while he is holding a man off the ball (`SimPlayer.shielding`): an arm
## goes out behind him over whatever gait he is in.
var player_shielding := PackedInt32Array()
var player_on_pitch := PackedInt32Array()

var score := PackedInt32Array([0, 0])
## Which way each team is attacking, so the presentation can label the ends.
var attack_x := PackedFloat32Array([1.0, -1.0])
var half_length := SimConsts.HALF_LENGTH
var half_width := SimConsts.HALF_WIDTH

## Set when the ball is out of play or the whistle has gone, so the presentation
## can show a restart marker without asking the sim any further questions.
var in_play := true
## Index into SimTelemetry.Ev of the most recent notable event, or -1.
var last_event := -1


func resize(n: int) -> void:
	if player_count == n:
		return
	player_count = n
	player_id.resize(n)
	player_team.resize(n)
	player_shirt.resize(n)
	player_pos.resize(n)
	player_vel.resize(n)
	player_facing.resize(n)
	player_stamina.resize(n)
	player_anim.resize(n)
	player_foot.resize(n)
	player_shielding.resize(n)
	player_on_pitch.resize(n)


func copy_from(other: SimSnapshot) -> void:
	resize(other.player_count)
	tick = other.tick
	clock = other.clock
	period = other.period
	phase = other.phase
	ball_pos = other.ball_pos
	ball_vel = other.ball_vel
	ball_spin = other.ball_spin
	player_id = other.player_id.duplicate()
	player_team = other.player_team.duplicate()
	player_shirt = other.player_shirt.duplicate()
	player_pos = other.player_pos.duplicate()
	player_vel = other.player_vel.duplicate()
	player_facing = other.player_facing.duplicate()
	player_stamina = other.player_stamina.duplicate()
	player_anim = other.player_anim.duplicate()
	player_foot = other.player_foot.duplicate()
	player_shielding = other.player_shielding.duplicate()
	player_on_pitch = other.player_on_pitch.duplicate()
	score = other.score.duplicate()
	attack_x = other.attack_x.duplicate()
	half_length = other.half_length
	half_width = other.half_width
	in_play = other.in_play
	last_event = other.last_event
