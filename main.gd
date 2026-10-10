extends Node3D

var cam: Camera3D
var yaw := 0.6
var pitch := -0.6
var dist := 16.0

func _ready():
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.53, 0.81, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.3, 0.7, 0.25)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.45, 0.3, 0.15)

	for x in range(-8, 8):
		for z in range(-8, 8):
			add_block(Vector3(x, 0, z), grass)
			add_block(Vector3(x, -1, z), dirt)

	cam = Camera3D.new()
	add_child(cam)
	update_cam()

func add_block(pos: Vector3, mat: Material):
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	m.material_override = mat
	m.position = pos
	add_child(m)

func update_cam():
	var p := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.look_at_from_position(p, Vector3.ZERO)

func _input(event):
	if event is InputEventScreenDrag:
		yaw -= event.relative.x * 0.005
		pitch = clamp(pitch - event.relative.y * 0.005, -1.4, -0.1)
		update_cam()