extends SceneTree
## Where a built model's brows actually end up, against the skull's own surface.
##
##     godot --headless --script res://tools/_brow_probe.gd
##
## Kept because arithmetic lost to it three times running. The brows are posed
## by `SimCharacterBuilder._pose_brows` on a **sphere**, and `art/toy/`'s head is
## a rounded box; whether a bar lands proud of that head or six centimetres
## inside it is a question about two surfaces neither file can see at once.
## Printing the transforms answered it in one run, and the same run caught the
## export that had been failing silently for an hour.
##
## Read the `BrowL` position against the skull's aabb: the bar's z has to clear
## the skull's front face by a few millimetres. `art/toy/figure.py:BROW_STAND` is
## the number to move.

func _init() -> void:
	var appearance := SimCharacterModel.appearance_for(12345)
	appearance.hair_style = 2
	appearance.brow_style = 4
	var kit := PackedColorArray([Color.YELLOW, Color.NAVY_BLUE, Color.BLUE])
	var root := SimCharacterModel.build(12345, appearance, kit, 9)
	get_root().add_child(root)
	print("built ", root.name, "  head_r meta ", root.get_meta("head_r", -1.0),
		"  brow_style ", root.get_meta("brow_style", -1))
	var brows := root.find_child("Brows", true, false)
	print("Brows ", brows, "  pos ", brows.position if brows else "-")
	if brows:
		for c in brows.get_children():
			var m := c as MeshInstance3D
			print("  ", c.name, " visible=", c.visible, " pos=", c.position,
				" scale=", c.scale, " global=", (c as Node3D).global_position)
			if m:
				var mat := m.get_active_material(0)
				print("     surfaces=", m.get_surface_override_material_count(),
					" active=", mat, " albedo=",
					(mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else "-")
				print("     aabb=", m.get_aabb())
	print("root children: ", root.get_children().map(func(c): return c.name))
	print("root.get_node_or_null(\"Spine\") = ", root.get_node_or_null("Spine"))
	var found := root.find_child("Spine", true, false) as Node3D
	print("find_child(\"Spine\") = ", found, "  y=", found.position.y if found else "-")
	var skull := root.find_child("skull", true, false) as MeshInstance3D
	if skull:
		print("skull aabb ", skull.get_aabb(), " global ", skull.global_position)
	quit()
