extends Node3D

const SIZE := 48
const HALF := 24
const WATER := 3

var cam: Camera3D
var yaw := 0.6
var pitch := -0.6
var dist := 45.0
var target := Vector3(-0.5, 3, -0.5)
var heights := PackedInt32Array()
var rng := RandomNumberGenerator.new()
var positions: Array[Vector3] = []
var colors: Array[Color] = []

func _ready():
	rng.randomize()
	setup_env()
	generate()
	build_mesh()
	add_water()
	cam = Camera3D.new()
	cam.far = 300.0
	add_child(cam)
	update_cam()

func setup_env():
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

func gh(x: int, z: int) -> int:
	if x < -HALF or x >= HALF or z < -HALF or z >= HALF:
		return -1
	return heights[(x + HALF) * SIZE + (z + HALF)]

func jitter(c: Color) -> Color:
	var j := rng.randf_range(0.88, 1.0)
	return Color(c.r * j, c.g * j, c.b * j)

func add_block(pos: Vector3, c: Color):
	positions.append(pos)
	colors.append(jitter(c))

func block_color(y: int, h: int) -> Color:
	if y == h:
		if h <= WATER + 1:
			return Color(0.86, 0.80, 0.52)
		elif h >= 11:
			return Color(0.95, 0.95, 0.97)
		elif h >= 9:
			return Color(0.5, 0.5, 0.52)
		return Color(0.3, 0.7, 0.25)
	if h >= 9:
		return Color(0.45, 0.45, 0.47)
	return Color(0.45, 0.3, 0.15)

func generate():
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.035
	heights.resize(SIZE * SIZE)
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var h := int(round(noise.get_noise_2d(x, z) * 9.0 + 5.0))
			heights[(x + HALF) * SIZE + (z + HALF)] = maxi(h, 1)
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var h := gh(x, z)
			var low := mini(mini(gh(x - 1, z), gh(x + 1, z)), mini(gh(x, z - 1), gh(x, z + 1)))
			var start := maxi(0, mini(h, low + 1))
			for y in range(start, h + 1):
				add_block(Vector3(x, y, z), block_color(y, h))
			if h > WATER + 1 and h < 9 and rng.randf() < 0.015 and abs(x) < HALF - 3 and abs(z) < HALF - 3:
				add_tree(x, h, z)

func add_tree(x: int, h: int, z: int):
	for i in range(1, 5):
		add_block(Vector3(x, h + i, z), Color(0.4, 0.26, 0.12))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if abs(dx) == 2 and abs(dz) == 2:
				continue
			if dx == 0 and dz == 0:
				continue
			for dy in [h + 3, h + 4]:
				add_block(Vector3(x + dx, dy, z + dz), Color(0.15, 0.5, 0.15))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			add_block(Vector3(x + dx, h + 5, z + dz), Color(0.15, 0.5, 0.15))

func build_mesh():
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat
	add_child(mmi)

func add_water():
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	plane.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.45, 0.85, 0.65)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.material_override = wm
	plane.position = Vector3(-0.5, WATER + 0.4, -0.5)
	add_child(plane)

func update_cam():
	var p := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.look_at_from_position(target + p, target)

func _input(event):
	if event is InputEventScreenDrag:
		yaw -= event.relative.x * 0.005
		pitch = clamp(pitch - event.relative.y * 0.005, -1.4, -0.1)
		update_cam()
	elif event is InputEventMagnifyGesture:
		dist = clampf(dist / event.factor, 10.0, 90.0)
		update_cam()