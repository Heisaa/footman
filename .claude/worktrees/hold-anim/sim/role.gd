class_name SimRole
extends RefCounted
## Positional roles and the attributes that matter for each.
##
## Roles are a squad-building and formation concept. They never switch
## behaviour wholesale -- they bias home positions and weight the decision
## function, in keeping with PLAN.md §5.1.

enum {
	GK,
	CB,
	FB,
	DM,
	CM,
	AM,
	WIDE,
	ST,
}

const NAMES := ["GK", "CB", "FB", "DM", "CM", "AM", "W", "ST"]

const _WEIGHTS := {
	GK: {"reflexes": 1.0, "handling": 1.0, "command": 0.8, "distribution": 0.6, "positioning": 0.9, "agility": 0.7, "composure": 0.5, "awareness": 0.6},
	CB: {"strength": 0.9, "heading": 0.9, "tackling": 1.0, "positioning": 1.0, "jumping": 0.8, "pace": 0.6, "composure": 0.6, "passing": 0.5, "decisions": 0.7, "awareness": 0.7},
	FB: {"pace": 0.9, "stamina": 1.0, "tackling": 0.8, "crossing": 0.8, "positioning": 0.7, "work_rate": 0.9, "acceleration": 0.8, "teamwork": 0.6, "awareness": 0.6},
	DM: {"tackling": 0.9, "positioning": 0.9, "passing": 0.8, "stamina": 0.8, "work_rate": 0.9, "decisions": 0.8, "awareness": 0.9, "strength": 0.6, "teamwork": 0.7},
	CM: {"passing": 1.0, "technique": 0.8, "stamina": 0.9, "decisions": 0.9, "awareness": 0.9, "work_rate": 0.8, "first_touch": 0.8, "teamwork": 0.7, "composure": 0.6},
	AM: {"passing": 0.9, "technique": 1.0, "dribbling": 0.8, "decisions": 0.8, "awareness": 0.9, "first_touch": 0.9, "finishing": 0.7, "agility": 0.7, "composure": 0.7},
	WIDE: {"pace": 1.0, "acceleration": 1.0, "dribbling": 1.0, "crossing": 0.9, "agility": 0.8, "technique": 0.8, "first_touch": 0.7, "stamina": 0.7, "finishing": 0.6},
	ST: {"finishing": 1.0, "composure": 0.9, "first_touch": 0.9, "heading": 0.7, "pace": 0.8, "acceleration": 0.8, "strength": 0.7, "awareness": 0.7, "technique": 0.7, "power": 0.7},
}


static func attribute_weights(role: int) -> Dictionary:
	return _WEIGHTS.get(role, _WEIGHTS[CM])


static func name_of(role: int) -> String:
	return NAMES[role] if role >= 0 and role < NAMES.size() else "??"


static func is_defensive(role: int) -> bool:
	return role == GK or role == CB or role == FB or role == DM


static func is_attacking(role: int) -> bool:
	return role == ST or role == WIDE or role == AM
