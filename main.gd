extends Node3D

const SIZE := 48
const HALF := SIZE / 2
const HEIGHT := 32
const WATER := 3

const PW := 0.3
const PH := 1.8
const EYE := 1.6
const SPEED := 5.0
const GRAVITY := 25.0
const JUMP_V := 8.5
const LOOK_SENS := 0.004

const GRASS := 1
const DIRT := 2
const SAND := 3
const STONE := 4
const SNOW := 5
const WOOD := 6
const LEAVES := 7

var palette := [
	Color(0, 0, 0),
	Color(0.3, 0.7, 0.25),
	Color(0.45, 0.3, 0.15),
	Color(0.86, 0.80, 0.52),
	Color(0.5, 0.5, 0.52),
	Color(0.95, 0.95, 0.97),
	Color(0.4, 0.26, 0.12),
	Color(0.15, 0.5, 0.15),
]

var blocks := PackedByteArray()
var heights := PackedInt32Array()
var mmi: MultiMeshInstance3D
var cam: Camera3D
var hud: Hud
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var on_ground := false
var yaw := 0.0
var pitch := 0.0
var move_touch := -1
var look_touch := -1
var jump_touch := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO

func _ready():
	setup_env()
	generate_world()
	build_mesh()
	add_water()
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 80.0
	add_child(cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	spawn()

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

func idx(x: int, y: int, z: int) -> int:
	return (x * SIZE + z) * HEIGHT + y

func set_block(x: int, y: int, z: int, t: int):
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE or y < 0 or y >= HEIGHT:
		return
	blocks[idx(x, y, z)] = t

func is_solid(x: int, y: int, z: int) -> bool:
	if y < 0:
		return true
	if y >= HEIGHT:
		return false
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return true
	return blocks[idx(x, y, z)] != 0

func is_air(x: int, y: int, z: int) -> bool:
	if y < 0:
		return false
	if y >= HEIGHT or x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return true
	return blocks[idx(x, y, z)] == 0

func generate_world():
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.035
	blocks.resize(SIZE * SIZE * HEIGHT)
	blocks.fill(0)
	heights.resize(SIZE * SIZE)
	for x in range(SIZE):
		for z in range(SIZE):
			var h := int(round(noise.get_noise_2d(x - HALF, z - HALF) * 9.0 + 5.0))
			h = clampi(h, 1, 14)
			heights[x * SIZE + z] = h
			for y in range(h + 1):
				var t := DIRT
				if y == h:
					if h <= WATER + 1:
						t = SAND
					elif h >= 11:
						t = SNOW
					elif h >= 9:
						t = STONE
					else:
						t = GRASS
				elif h >= 9:
					t = STONE
				set_block(x, y, z, t)
	for x in range(3, SIZE - 3):
		for z in range(3, SIZE - 3):
			var h2 := heights[x * SIZE + z]
			if h2 > WATER + 1 and h2 < 9 and rng.randf() < 0.015:
				add_tree(x, h2, z)

func add_tree(x: int, h: int, z: int):
	for i in range(1, 5):
		set_block(x, h + i, z, WOOD)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if abs(dx) == 2 and abs(dz) == 2:
				continue
			if dx == 0 and dz == 0:
				continue
			set_block(x + dx, h + 3, z + dz, LEAVES)
			set_block(x + dx, h + 4, z + dz, LEAVES)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			set_block(x + dx, h + 5, z + dz, LEAVES)

func shade(x: int, y: int, z: int) -> float:
	return 0.88 + 0.12 * fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)

func build_mesh():
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	for x in range(SIZE):
		for z in range(SIZE):
			var top := mini(heights[x * SIZE + z] + 7, HEIGHT - 1)
			for y in range(top + 1):
				var t := blocks[idx(x, y, z)]
				if t == 0:
					continue
				if is_air(x - 1, y, z) or is_air(x + 1, y, z) or is_air(x, y - 1, z) or is_air(x, y + 1, z) or is_air(x, y, z - 1) or is_air(x, y, z + 1):
					var c: Color = palette[t]
					var s := shade(x, y, z)
					positions.append(Vector3(x, y, z))
					colors.append(Color(c.r * s, c.g * s, c.b * s))
	if mmi:
		mmi.queue_free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
	mmi = MultiMeshInstance3D.new()
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
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material_override = wm
	var c := (SIZE - 1) * 0.5
	plane.position = Vector3(c, WATER + 0.4, c)
	add_child(plane)

func spawn():
	var best := Vector2i(HALF, HALF)
	var found := false
	for r in range(0, HALF - 3):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if found:
					break
				var x := HALF + dx
				var z := HALF + dz
				if heights[x * SIZE + z] > WATER + 1:
					best = Vector2i(x, z)
					found = true
		if found:
			break
	var h := heights[best.x * SIZE + best.y]
	pos = Vector3(best.x, h + 0.5 + 0.01, best.y)
	while collides(pos) and pos.y < HEIGHT:
		pos.y += 1.0
	vel = Vector3.ZERO

func collides(p: Vector3) -> bool:
	var x0 := floori(p.x - PW + 0.5)
	var x1 := floori(p.x + PW + 0.5)
	var z0 := floori(p.z - PW + 0.5)
	var z1 := floori(p.z + PW + 0.5)
	var y0 := floori(p.y + 0.5)
	var y1 := floori(p.y + PH - 0.001 + 0.5)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				if is_solid(x, y, z):
					return true
	return false

func jump_center(sz: Vector2) -> Vector2:
	return Vector2(sz.x - sz.y * 0.2, sz.y * 0.78)

func _input(event):
	var sz := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(jump_center(sz)) < sz.y * 0.12 and jump_touch == -1:
				jump_touch = event.index
			elif event.position.x < sz.x * 0.4 and move_touch == -1:
				move_touch = event.index
				joy_origin = event.position
				joy_vec = Vector2.ZERO
			elif event.position.x >= sz.x * 0.4 and look_touch == -1:
				look_touch = event.index
		else:
			if event.index == move_touch:
				move_touch = -1
				joy_vec = Vector2.ZERO
			elif event.index == look_touch:
				look_touch = -1
			elif event.index == jump_touch:
				jump_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == move_touch:
			var r := sz.y * 0.13
			joy_vec = (event.position - joy_origin).limit_length(r) / r
		elif event.index == look_touch:
			yaw -= event.relative.x * LOOK_SENS
			pitch = clampf(pitch - event.relative.y * LOOK_SENS, -1.5, 1.5)

func _process(delta):
	delta = minf(delta, 0.05)
	var sz := get_viewport().get_visible_rect().size
	hud.size = sz
	hud.joy_active = move_touch != -1
	hud.joy_base = joy_origin
	hud.joy_knob = joy_origin + joy_vec * sz.y * 0.13
	hud.jump_pos = jump_center(sz)
	hud.queue_redraw()

	var jv := joy_vec
	if jv.length() < 0.15:
		jv = Vector2.ZERO
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var step := (right * jv.x + fwd * -jv.y) * SPEED * delta

	var blocked := false
	if step.x != 0.0:
		pos.x += step.x
		if collides(pos):
			pos.x -= step.x
			blocked = true
	if step.z != 0.0:
		pos.z += step.z
		if collides(pos):
			pos.z -= step.z
			blocked = true

	if blocked and on_ground and not collides(pos + step + Vector3(0, 1.05, 0)):
		vel.y = JUMP_V
	elif jump_touch != -1 and on_ground:
		vel.y = JUMP_V

	vel.y = maxf(vel.y - GRAVITY * delta, -18.0)
	pos.y += vel.y * delta
	on_ground = false
	if collides(pos):
		if vel.y < 0.0:
			pos.y = floorf(pos.y + 0.5) + 0.5005
			on_ground = true
		else:
			pos.y -= vel.y * delta
		vel.y = 0.0

	if pos.y < -20.0:
		spawn()

	cam.position = pos + Vector3(0, EYE, 0)
	cam.rotation = Vector3(pitch, yaw, 0)

class Hud extends Control:
	var joy_active := false
	var joy_base := Vector2.ZERO
	var joy_knob := Vector2.ZERO
	var jump_pos := Vector2.ZERO

	func _draw():
		var h := size.y
		if joy_active:
			draw_circle(joy_base, h * 0.13, Color(1, 1, 1, 0.12))
			draw_circle(joy_knob, h * 0.055, Color(1, 1, 1, 0.35))
		var r := h * 0.09
		draw_circle(jump_pos, r, Color(1, 1, 1, 0.18))
		var tri := PackedVector2Array([
			jump_pos + Vector2(0, -r * 0.45),
			jump_pos + Vector2(r * 0.45, r * 0.3),
			jump_pos + Vector2(-r * 0.45, r * 0.3)])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.45))
		draw_circle(size * 0.5, 3.0, Color(1, 1, 1, 0.6))