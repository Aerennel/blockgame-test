extends Node3D

const SIZE := 128
const HALF := SIZE / 2
const HEIGHT := 32
const WATER := 3
const WL := WATER + 0.4
const CHUNK := 16
const CN := (SIZE + CHUNK - 1) / CHUNK
const REACH := 6.0

const PW := 0.3
const PH := 1.8
const EYE := 1.6
const SPEED := 5.0
const GRAVITY := 25.0
const JUMP_V := 8.5
const LOOK_SENS := 0.004
const REPEAT := 0.22

const SAVE_PATH := "user://world.dat"
const SAVE_TMP := "user://world.tmp"
const SAVE_VERSION := 1

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
var hotbar := [GRASS, DIRT, STONE, SAND, WOOD, LEAVES]
var selected := 0

var blocks := PackedByteArray()
var heights := PackedInt32Array()
var col_top := PackedInt32Array()
var chunks := {}
var block_mat: StandardMaterial3D
var cam: Camera3D
var hud: Hud
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var on_ground := false
var in_water := false
var yaw := 0.0
var pitch := 0.0
var move_touch := -1
var look_touch := -1
var jump_touch := -1
var break_touch := -1
var place_touch := -1
var break_cd := 0.0
var place_cd := 0.0
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO

var world_ready := false
var dirty := false
var save_timer := 0.0
var menu_open := false
var confirm_new := false
var menu: Control
var menu_dim: ColorRect
var btn_continue: Button
var btn_new: Button

func _ready():
	block_mat = StandardMaterial3D.new()
	block_mat.vertex_color_use_as_albedo = true
	setup_env()
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
	var cols: Array[Color] = []
	for t in hotbar:
		var c: Color = palette[t]
		cols.append(c)
	hud.slot_colors = cols
	build_menu()
	if not load_world():
		generate_world()
		spawn()
	build_all_chunks()
	world_ready = true

func _notification(what):
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if world_ready:
			save_world()

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

func in_world(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and z >= 0 and z < SIZE and y >= 0 and y < HEIGHT

func get_type(x: int, y: int, z: int) -> int:
	if not in_world(x, y, z):
		return 0
	return blocks[idx(x, y, z)]

func set_block(x: int, y: int, z: int, t: int):
	if not in_world(x, y, z):
		return
	blocks[idx(x, y, z)] = t
	if t != 0 and y > col_top[x * SIZE + z]:
		col_top[x * SIZE + z] = y

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
	col_top.resize(SIZE * SIZE)
	col_top.fill(0)
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

func rebuild_columns():
	col_top.resize(SIZE * SIZE)
	heights.resize(SIZE * SIZE)
	for x in range(SIZE):
		for z in range(SIZE):
			var i := x * SIZE + z
			var base := i * HEIGHT
			var y := HEIGHT - 1
			while y > 0 and blocks[base + y] == 0:
				y -= 1
			col_top[i] = y
			while y > 0 and (blocks[base + y] == 0 or blocks[base + y] == WOOD or blocks[base + y] == LEAVES):
				y -= 1
			heights[i] = y

func save_world():
	var f := FileAccess.open_compressed(SAVE_TMP, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_32(SAVE_VERSION)
	f.store_32(SIZE)
	f.store_32(HEIGHT)
	f.store_float(pos.x)
	f.store_float(pos.y)
	f.store_float(pos.z)
	f.store_float(yaw)
	f.store_float(pitch)
	f.store_32(selected)
	f.store_32(blocks.size())
	f.store_buffer(blocks)
	f.close()
	var d := DirAccess.open("user://")
	if d:
		var err := d.rename("world.tmp", "world.dat")
		if err != OK:
			d.remove("world.dat")
			d.rename("world.tmp", "world.dat")
	dirty = false
	save_timer = 0.0

func load_world() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open_compressed(SAVE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	if f.get_32() != SAVE_VERSION or f.get_32() != SIZE or f.get_32() != HEIGHT:
		f.close()
		return false
	var px := f.get_float()
	var py := f.get_float()
	var pz := f.get_float()
	var yw := f.get_float()
	var pt := f.get_float()
	var sel := f.get_32()
	var n := f.get_32()
	if n != SIZE * SIZE * HEIGHT:
		f.close()
		return false
	var data := f.get_buffer(n)
	f.close()
	if data.size() != n:
		return false
	blocks = data
	rebuild_columns()
	pos = Vector3(px, py, pz)
	yaw = yw
	pitch = pt
	selected = clampi(sel, 0, hotbar.size() - 1)
	vel = Vector3.ZERO
	while collides(pos) and pos.y < HEIGHT:
		pos.y += 1.0
	return true

func new_world():
	generate_world()
	spawn()
	yaw = 0.0
	pitch = 0.0
	build_all_chunks()
	save_world()

func shade(x: int, y: int, z: int) -> float:
	return 0.88 + 0.12 * fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)

func build_all_chunks():
	for cx in range(CN):
		for cz in range(CN):
			build_chunk(cx, cz)

func build_chunk(cx: int, cz: int):
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	for x in range(cx * CHUNK, mini((cx + 1) * CHUNK, SIZE)):
		for z in range(cz * CHUNK, mini((cz + 1) * CHUNK, SIZE)):
			var top := col_top[x * SIZE + z]
			for y in range(top + 1):
				var t := blocks[idx(x, y, z)]
				if t == 0:
					continue
				if is_air(x - 1, y, z) or is_air(x + 1, y, z) or is_air(x, y - 1, z) or is_air(x, y + 1, z) or is_air(x, y, z - 1) or is_air(x, y, z + 1):
					var c: Color = palette[t]
					var s := shade(x, y, z)
					positions.append(Vector3(x, y, z))
					colors.append(Color(c.r * s, c.g * s, c.b * s))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
	var key := Vector2i(cx, cz)
	if chunks.has(key):
		chunks[key].multimesh = mm
	else:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = block_mat
		add_child(node)
		chunks[key] = node

func rebuild_around(x: int, z: int):
	var cx := x / CHUNK
	var cz := z / CHUNK
	var list := {}
	list[Vector2i(cx, cz)] = true
	if x % CHUNK == 0 and cx > 0:
		list[Vector2i(cx - 1, cz)] = true
	if x % CHUNK == CHUNK - 1 and cx < CN - 1:
		list[Vector2i(cx + 1, cz)] = true
	if z % CHUNK == 0 and cz > 0:
		list[Vector2i(cx, cz - 1)] = true
	if z % CHUNK == CHUNK - 1 and cz < CN - 1:
		list[Vector2i(cx, cz + 1)] = true
	for k in list.keys():
		build_chunk(k.x, k.y)

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
	plane.position = Vector3(c, WL, c)
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

func raycast() -> Dictionary:
	var eye := pos + Vector3(0, EYE, 0)
	var origin := eye + Vector3(0.5, 0.5, 0.5)
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var prev := cell
	var stepv := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in range(3):
		if dir[a] > 0.0:
			stepv[a] = 1
			t_delta[a] = 1.0 / dir[a]
			t_max[a] = (cell[a] + 1 - origin[a]) / dir[a]
		elif dir[a] < 0.0:
			stepv[a] = -1
			t_delta[a] = -1.0 / dir[a]
			t_max[a] = (origin[a] - cell[a]) / -dir[a]
	while true:
		var ax := 0
		if t_max.y < t_max[ax]:
			ax = 1
		if t_max.z < t_max[ax]:
			ax = 2
		var t: float = t_max[ax]
		if t > REACH:
			break
		prev = cell
		cell[ax] += stepv[ax]
		t_max[ax] += t_delta[ax]
		if get_type(cell.x, cell.y, cell.z) != 0:
			return {"cell": cell, "prev": prev}
	return {}

func do_break():
	var hit := raycast()
	if hit.is_empty():
		return
	var c: Vector3i = hit["cell"]
	if c.y == 0:
		return
	set_block(c.x, c.y, c.z, 0)
	rebuild_around(c.x, c.z)
	dirty = true

func do_place():
	var hit := raycast()
	if hit.is_empty():
		return
	var p: Vector3i = hit["prev"]
	if not in_world(p.x, p.y, p.z):
		return
	if get_type(p.x, p.y, p.z) != 0:
		return
	set_block(p.x, p.y, p.z, hotbar[selected])
	if collides(pos):
		set_block(p.x, p.y, p.z, 0)
		return
	rebuild_around(p.x, p.z)
	dirty = true

func build_menu():
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	menu = Control.new()
	menu.visible = false
	ui.add_child(menu)
	menu_dim = ColorRect.new()
	menu_dim.color = Color(0, 0, 0, 0.6)
	menu.add_child(menu_dim)
	btn_continue = Button.new()
	btn_continue.text = "Продолжить"
	btn_continue.focus_mode = Control.FOCUS_NONE
	btn_continue.pressed.connect(close_menu)
	menu.add_child(btn_continue)
	btn_new = Button.new()
	btn_new.text = "Новый мир"
	btn_new.focus_mode = Control.FOCUS_NONE
	btn_new.pressed.connect(on_new_pressed)
	menu.add_child(btn_new)

func release_touches():
	move_touch = -1
	look_touch = -1
	jump_touch = -1
	break_touch = -1
	place_touch = -1
	joy_vec = Vector2.ZERO

func open_menu():
	save_world()
	release_touches()
	confirm_new = false
	var sz := get_viewport().get_visible_rect().size
	menu_dim.position = Vector2.ZERO
	menu_dim.size = sz
	var bw := sz.y * 0.9
	var bh := sz.y * 0.16
	var fs := int(sz.y * 0.06)
	btn_continue.add_theme_font_size_override("font_size", fs)
	btn_new.add_theme_font_size_override("font_size", fs)
	btn_continue.size = Vector2(bw, bh)
	btn_new.size = Vector2(bw, bh)
	btn_continue.position = Vector2((sz.x - bw) * 0.5, sz.y * 0.28)
	btn_new.position = Vector2((sz.x - bw) * 0.5, sz.y * 0.28 + bh * 1.4)
	btn_new.text = "Новый мир"
	menu.visible = true
	menu_open = true

func close_menu():
	menu.visible = false
	menu_open = false
	confirm_new = false

func on_new_pressed():
	if not confirm_new:
		confirm_new = true
		btn_new.text = "Точно? Старый мир удалится"
		return
	new_world()
	close_menu()

func jump_center(sz: Vector2) -> Vector2:
	return Vector2(sz.x - sz.y * 0.18, sz.y * 0.80)

func break_center(sz: Vector2) -> Vector2:
	return Vector2(sz.x - sz.y * 0.18, sz.y * 0.55)

func place_center(sz: Vector2) -> Vector2:
	return Vector2(sz.x - sz.y * 0.42, sz.y * 0.80)

func pause_center(sz: Vector2) -> Vector2:
	return Vector2(sz.y * 0.1, sz.y * 0.1)

func over_button(p: Vector2, c: Vector2, sz: Vector2) -> bool:
	return p.distance_to(c) < sz.y * 0.11

func slot_rect(i: int, sz: Vector2) -> Rect2:
	var s := sz.y * 0.1
	var gap := sz.y * 0.015
	var total := hotbar.size() * s + (hotbar.size() - 1) * gap
	var x0 := sz.x * 0.5 - total * 0.5
	return Rect2(x0 + i * (s + gap), sz.y - s - gap * 1.5, s, s)

func slot_hit(p: Vector2, sz: Vector2) -> int:
	for i in range(hotbar.size()):
		if slot_rect(i, sz).grow(sz.y * 0.01).has_point(p):
			return i
	return -1

func _input(event):
	if menu_open:
		return
	var sz := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if p.distance_to(pause_center(sz)) < sz.y * 0.09:
				open_menu()
			elif over_button(p, jump_center(sz), sz) and jump_touch == -1:
				jump_touch = event.index
			elif over_button(p, break_center(sz), sz) and break_touch == -1:
				break_touch = event.index
				break_cd = 0.0
			elif over_button(p, place_center(sz), sz) and place_touch == -1:
				place_touch = event.index
				place_cd = 0.0
			elif slot_hit(p, sz) >= 0:
				selected = slot_hit(p, sz)
				dirty = true
			elif p.x < sz.x * 0.4 and move_touch == -1:
				move_touch = event.index
				joy_origin = p
				joy_vec = Vector2.ZERO
			elif p.x >= sz.x * 0.4 and look_touch == -1:
				look_touch = event.index
		else:
			if event.index == move_touch:
				move_touch = -1
				joy_vec = Vector2.ZERO
			elif event.index == look_touch:
				look_touch = -1
			elif event.index == jump_touch:
				jump_touch = -1
			elif event.index == break_touch:
				break_touch = -1
			elif event.index == place_touch:
				place_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == move_touch:
			var r := sz.y * 0.13
			joy_vec = (event.position - joy_origin).limit_length(r) / r
		elif event.index == look_touch:
			yaw -= event.relative.x * LOOK_SENS
			pitch = clampf(pitch - event.relative.y * LOOK_SENS, -1.5, 1.5)

func _process(delta: float):
	delta = minf(delta, 0.05)
	var sz := get_viewport().get_visible_rect().size
	hud.size = sz
	hud.joy_active = move_touch != -1
	hud.joy_base = joy_origin
	hud.joy_knob = joy_origin + joy_vec * sz.y * 0.13
	hud.jump_pos = jump_center(sz)
	hud.break_pos = break_center(sz)
	hud.place_pos = place_center(sz)
	hud.pause_pos = pause_center(sz)
	hud.underwater = pos.y + EYE < WL
	var rects: Array[Rect2] = []
	for i in range(hotbar.size()):
		rects.append(slot_rect(i, sz))
	hud.slot_rects = rects
	hud.selected = selected
	hud.queue_redraw()
	if menu_open:
		return

	save_timer += delta
	if dirty and save_timer > 15.0:
		save_world()

	in_water = pos.y + 0.6 < WL
	var spd := SPEED
	if in_water:
		spd = SPEED * 0.6

	var jv := joy_vec
	if jv.length() < 0.15:
		jv = Vector2.ZERO
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var step := (right * jv.x + fwd * -jv.y) * spd * delta

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

	if blocked and (on_ground or in_water) and not collides(pos + step + Vector3(0, 1.05, 0)):
		vel.y = JUMP_V
		if in_water:
			vel.y = 10.0
	elif jump_touch != -1 and on_ground and not in_water:
		vel.y = JUMP_V

	if in_water:
		if jump_touch != -1 and pos.y + 1.3 < WL:
			if vel.y < 3.5:
				vel.y = minf(vel.y + 20.0 * delta, 3.5)
		else:
			var dec := 6.0
			if vel.y > 0.0:
				dec = GRAVITY
			vel.y = maxf(vel.y - dec * delta, -3.0)
	else:
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

	break_cd -= delta
	place_cd -= delta
	if break_touch != -1 and break_cd <= 0.0:
		do_break()
		break_cd = REPEAT
	if place_touch != -1 and place_cd <= 0.0:
		do_place()
		place_cd = REPEAT

class Hud extends Control:
	var joy_active := false
	var joy_base := Vector2.ZERO
	var joy_knob := Vector2.ZERO
	var jump_pos := Vector2.ZERO
	var break_pos := Vector2.ZERO
	var place_pos := Vector2.ZERO
	var pause_pos := Vector2.ZERO
	var underwater := false
	var slot_rects: Array[Rect2] = []
	var slot_colors: Array[Color] = []
	var selected := 0

	func _draw():
		var h := size.y
		if underwater:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.35, 0.8, 0.3))
		if joy_active:
			draw_circle(joy_base, h * 0.13, Color(1, 1, 1, 0.12))
			draw_circle(joy_knob, h * 0.055, Color(1, 1, 1, 0.35))
		var r := h * 0.09
		var k := r * 0.4
		var white := Color(1, 1, 1, 0.7)
		draw_circle(jump_pos, r, Color(1, 1, 1, 0.18))
		var tri := PackedVector2Array([
			jump_pos + Vector2(0, -r * 0.45),
			jump_pos + Vector2(r * 0.45, r * 0.3),
			jump_pos + Vector2(-r * 0.45, r * 0.3)])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.45))
		draw_circle(break_pos, r, Color(1, 0.4, 0.4, 0.25))
		draw_line(break_pos + Vector2(-k, -k), break_pos + Vector2(k, k), white, 5.0)
		draw_line(break_pos + Vector2(-k, k), break_pos + Vector2(k, -k), white, 5.0)
		draw_circle(place_pos, r, Color(0.4, 1, 0.5, 0.25))
		draw_line(place_pos + Vector2(-k, 0), place_pos + Vector2(k, 0), white, 5.0)
		draw_line(place_pos + Vector2(0, -k), place_pos + Vector2(0, k), white, 5.0)
		draw_circle(pause_pos, h * 0.055, Color(1, 1, 1, 0.18))
		draw_rect(Rect2(pause_pos + Vector2(-h * 0.02, -h * 0.025), Vector2(h * 0.014, h * 0.05)), white)
		draw_rect(Rect2(pause_pos + Vector2(h * 0.006, -h * 0.025), Vector2(h * 0.014, h * 0.05)), white)
		for i in range(slot_rects.size()):
			var rc := slot_rects[i]
			draw_rect(rc, slot_colors[i])
			if i == selected:
				draw_rect(rc.grow(4.0), Color(1, 1, 1, 0.95), false, 4.0)
			else:
				draw_rect(rc, Color(0, 0, 0, 0.4), false, 2.0)
		draw_circle(size * 0.5, 3.0, Color(1, 1, 1, 0.6))