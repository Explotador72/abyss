@tool
extends Node3D

func _ready() -> void:
	if get_child_count() == 0:
		_generate()

func _make_probe(pos: Vector3, idx: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = CylinderMesh.new()
	m.mesh.bottom_radius = 0.04
	m.mesh.top_radius = 0.0
	m.mesh.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.8, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.position = pos
	m.name = "Probe_%d" % idx
	return m

func _generate() -> void:
	for c in get_children():
		c.queue_free()

	var positions: Array[Vector3] = []
	for y in [-0.4, -0.1]:
		for z in [-1.2, 0.0, 1.2]:
			for x in [-0.6, 0.6]:
				positions.append(Vector3(x, y, z))

	var idx := 0
	for p in positions:
		var probe := _make_probe(p, idx)
		add_child(probe)
		if Engine.is_editor_hint():
			probe.owner = get_tree().edited_scene_root
		idx += 1
