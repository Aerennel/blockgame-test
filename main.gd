extends Node3D

const SIZE := 128
const HALF := SIZE / 2
const HEIGHT := 40
const WATER := 12
const WL := WATER + 0.4
const CHUNK := 16
const CN := (SIZE + CHUNK - 1) / CHUNK
const REACH := 6.0
const DAY_LEN := 480.0

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
const STATE_PATH := "user://state.cfg"
const SAVE_VERSION := 2

const GRASS := 1
const DIRT := 2
const SAND := 3
const STONE := 4
const SNOW := 5
const WOOD := 6
const LEAVES := 7
const PLANKS := 8
const BRICK := 9
const GLASS := 10
const COAL := 11
const IRON := 12
const GOLD := 13
const DIAMOND := 14
const TORCH := 15

var palette := [
	Color(0, 0, 0),
	Color(0.3, 0.7, 0.25),
	Color(0.45, 0.3, 0.15),
	Color(0.86, 0.80, 0.52),
	Color(0.5, 0.5, 0.52),
	Color(0.95, 0.95, 0.97),
	Color(0.4, 0.26, 0.12),
	Color(0.15, 0.5, 0.15),
	Color(0.72, 0.55, 0.32),
	Color(0.65, 0.28, 0.22),
	Color(0.8, 0.92, 1.0),
	Color(0.2, 0.2, 0.22),
	Color(0.75, 0.62, 0.52),
	Color(0.95, 0.8, 0.2),
	Color(0.3, 0.88, 0.9),
	Color(1.0, 0.7, 0.2),
]
var hotbar := [GRASS, DIRT, STONE, SAND, WOOD, PLANKS, BRICK, GLASS, LEAVES, TORCH]
var selected := 0

var ndx := PackedInt32Array([1, -1, 0, 0, 0, 0])
var ndy := PackedInt32Array([0, 0, 1, -1, 0, 0])
var ndz := PackedInt32Array([0, 0, 0, 0, 1, -1])

var blocks := PackedByteArray()
var light := PackedByteArray()
var heights := PackedInt32Array()
var col_top := PackedInt32Array()
var water_map := PackedByteArray()
var bfs_q := PackedInt32Array()
var rem_q := PackedInt32Array()
var rem_lv := PackedInt32Array()
var changed := {}
var track := false
var torch_cells := {}
var chunks := {}
var gchunks := {}
var water_node: MultiMeshInstance3D
var torch_node: MultiMeshInstance3D
var box_mesh: BoxMesh
var plane_mesh: PlaneMesh
var torch_mesh: BoxMesh
var block_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var water_mat: StandardMaterial3D
var torch_mat: StandardMaterial3D
var env_res: Environment
var sky_root: Node3D
var sun_node: MeshInstance3D
var moon_node: MeshInstance3D
var star_mat: StandardMaterial3D
var day_time := DAY_LEN * 0.08
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

func make_shader(glass: bool) -> Shader:
	var code := """shader_type spatial;
render_mode unshaded;

uniform float day = 1.0;

varying vec3 v_col;
varying vec2 v_light;
varying float v_face;
varying float v_a;

void vertex() {
	v_col = COLOR.rgb;
	v_a = COLOR.a;
	v_light = INSTANCE_CUSTOM.xy;
	float s = 0.78;
	if (NORMAL.y > 0.5) {
		s = 1.0;
	} else if (NORMAL.y < -0.5) {
		s = 0.55;
	} else if (abs(NORMAL.x) > 0.5) {
		s = 0.68;
	}
	v_face = s;
}

void fragment() {
	float sl = pow(clamp(v_light.x * day, 0.0, 1.0), 1.6);
	float bl = pow(clamp(v_light.y, 0.0, 1.0), 1.6);
	vec3 sky_c = mix(vec3(0.5, 0.6, 1.0), vec3(1.0), day) * sl;
	vec3 blk_c = vec3(1.0, 0.78, 0.5) * bl;
	vec3 lit = max(sky_c, blk_c);
	lit = max(lit, vec3(0.03, 0.035, 0.06));
	ALBEDO = v_col * v_face * lit;
}
"""
	if glass:
		code = code.replace("ALBEDO = v_col * v_face * lit;", "ALBEDO = v_col * v_face * lit;\n\tALPHA = v_a;")
	var sh := Shader.new()
	sh.code = code
	return sh

func _ready():
	box_mesh = BoxMesh.new()
	plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(1, 1)
	torch_mesh = BoxMesh.new()
	torch_mesh.size = Vector3(0.18, 0.6, 0.18)
	block_mat = ShaderMaterial.new()
	block_mat.shader = make_shader(false)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = make_shader(true)
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.25, 0.55, 0.95, 0.65)
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	torch_mat = StandardMaterial3D.new()
	torch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torch_mat.albedo_color = Color(1.0, 0.72, 0.25)
	setup_env()
	setup_sky()
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
	load_state()
	if not load_world():
		generate_world()
		spawn()
	compute_all_light()
	build_all_chunks()
	build_water()
	build_torches()
	world_ready = true

func _notification(what):
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if world_ready:
			save_world()

func setup_env():
	var env := WorldEnvironment.new()
	env_res = Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0.53, 0.81, 0.92)
	env.environment = env_res
	add_child(env)

func setup_sky():
	sky_root = Node3D.new()
	add_child(sky_root)
	var sun_mat := StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.95, 0.7)
	sun_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var sun_quad := QuadMesh.new()
	sun_quad.size = Vector2(45, 45)
	sun_node = MeshInstance3D.new()
	sun_node.mesh = sun_quad
	sun_node.material_override = sun_mat
	sky_root.add_child(sun_node)
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.85, 0.9, 1.0)
	moon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var moon_quad := QuadMesh.new()
	moon_quad.size = Vector2(32, 32)
	moon_node = MeshInstance3D.new()
	moon_node.mesh = moon_quad
	moon_node.material_override = moon_mat
	sky_root.add_child(moon_node)
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.albedo_color = Color(1, 1, 1, 0)
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var star_quad := QuadMesh.new()
	star_quad.size = Vector2(1.4, 1.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var spos: Array[Vector3] = []
	for i in range(220):
		var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if v.length() < 0.001:
			continue
		spos.append(v.normalized() * 255.0)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = star_quad
	smm.instance_count = spos.size()
	for i in range(spos.size()):
		smm.set_instance_transform(i, Transform3D(Basis(), spos[i]))
	var star_node := MultiMeshInstance3D.new()
	star_node.multimesh = smm
	star_node.material_override = star_mat
	sky_root.add_child(star_node)

func update_sky():
	var a := day_time / DAY_LEN * TAU
	var sh := sin(a) + 0.15
	var d := smoothstep(-0.05, 0.3, sh)
	var day_u := lerpf(0.28, 1.0, d)
	block_mat.set_shader_parameter("day", day_u)
	glass_mat.set_shader_parameter("day", day_u)
	var sky_c := Color(0.02, 0.03, 0.09).lerp(Color(0.53, 0.81, 0.92), d)
	var g := clampf(1.0 - absf(sh) / 0.3, 0.0, 1.0)
	sky_c = sky_c.lerp(Color(0.95, 0.55, 0.35), g * 0.5)
	env_res.background_color = sky_c
	var k := lerpf(0.2, 1.0, d)
	water_mat.albedo_color = Color(0.25 * k, 0.55 * k, 0.95 * k, 0.65)
	star_mat.albedo_color = Color(1, 1, 1, clampf(1.0 - d * 1.6, 0.0, 1.0))
	var sd := Vector3(cos(a), sin(a), 0.3).normalized()
	sky_root.position = cam.position
	sun_node.position = sd * 250.0
	moon_node.position = -sd * 250.0
	sun_node.visible = sh > -0.08
	moon_node.visible = sh < 0.08

func save_state():
	var cfg := ConfigFile.new()
	cfg.set_value("s", "t", day_time)
	cfg.save(STATE_PATH)

func load_state():
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) == OK:
		day_time = float(cfg.get_value("s", "t", day_time))

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
	var t := blocks[idx(x, y, z)]
	return t != 0 and t != TORCH

func water_at(wx: float, wy: float, wz: float) -> bool:
	if wy > WL:
		return false
	var x := roundi(wx)
	var y := roundi(wy)
	var z := roundi(wz)
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return false
	if water_map[x * SIZE + z] == 0:
		return false
	return get_type(x, y, z) == 0

func generate_world():
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.035
	var cave_freq := 0.03
	var cave_w := 0.07
	var cave_a := FastNoiseLite.new()
	cave_a.seed = rng.randi()
	cave_a.frequency = cave_freq
	cave_a.fractal_type = FastNoiseLite.FRACTAL_NONE
	var cave_b := FastNoiseLite.new()
	cave_b.seed = rng.randi()
	cave_b.frequency = cave_freq
	cave_b.fractal_type = FastNoiseLite.FRACTAL_NONE
	var cave_c := FastNoiseLite.new()
	cave_c.seed = rng.randi()
	cave_c.frequency = 0.025
	cave_c.fractal_type = FastNoiseLite.FRACTAL_NONE
	blocks.resize(SIZE * SIZE * HEIGHT)
	blocks.fill(0)
	heights.resize(SIZE * SIZE)
	water_map.resize(SIZE * SIZE)
	water_map.fill(0)
	col_top.resize(SIZE * SIZE)
	col_top.fill(0)
	for x in range(SIZE):
		for z in range(SIZE):
			var h := int(round(noise.get_noise_2d(x - HALF, z - HALF) * 9.0 + 14.0))
			h = clampi(h, 2, 24)
			heights[x * SIZE + z] = h
			if h < WATER:
				water_map[x * SIZE + z] = 1
			for y in range(h + 1):
				var t := STONE
				if y == h:
					if h <= WATER + 1:
						t = SAND
					elif h >= 20:
						t = SNOW
					elif h >= 18:
						t = STONE
					else:
						t = GRASS
				elif h < 18 and y > h - 4:
					t = DIRT
				else:
					if h >= WATER + 2 and y >= 3:
						if absf(cave_a.get_noise_3d(x, y * 1.3, z)) < cave_w and absf(cave_b.get_noise_3d(x, y * 1.3, z)) < cave_w:
							continue
						if y < h - 8 and cave_c.get_noise_3d(x, y * 1.3, z) > 0.5:
							continue
					var r := rng.randf()
					if y < h - 2 and r < 0.02:
						if r < 0.001:
							t = DIAMOND
						elif r < 0.003:
							t = GOLD
						elif r < 0.008:
							t = IRON
						else:
							t = COAL
				set_block(x, y, z, t)
	for x in range(3, SIZE - 3):
		for z in range(3, SIZE - 3):
			var h2 := heights[x * SIZE + z]
			if h2 > WATER + 1 and h2 < 18 and rng.randf() < 0.015:
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
			while y > 0 and (blocks[base + y] == 0 or blocks[base + y] == WOOD or blocks[base + y] == LEAVES or blocks[base + y] == TORCH):
				y -= 1
			heights[i] = y

func get_l(i: int, ch: int) -> int:
	return (light[i] >> (ch * 4)) & 15

func set_l(i: int, ch: int, v: int):
	if ch == 0:
		light[i] = (light[i] & 240) | v
	else:
		light[i] = (light[i] & 15) | (v << 4)

func mark_chunk(x: int, z: int):
	var cx := x / CHUNK
	var cz := z / CHUNK
	changed[Vector2i(cx, cz)] = true
	var lx := x % CHUNK
	var lz := z % CHUNK
	if lx == 0 and cx > 0:
		changed[Vector2i(cx - 1, cz)] = true
	if lx == CHUNK - 1 and cx < CN - 1:
		changed[Vector2i(cx + 1, cz)] = true
	if lz == 0 and cz > 0:
		changed[Vector2i(cx, cz - 1)] = true
	if lz == CHUNK - 1 and cz < CN - 1:
		changed[Vector2i(cx, cz + 1)] = true

func mark_changed(i: int):
	var col := i / HEIGHT
	mark_chunk(col / SIZE, col % SIZE)

func flush_changed():
	for k in changed.keys():
		build_chunk(k.x, k.y)
	changed.clear()

func spread(ch: int):
	var head := 0
	while head < bfs_q.size():
		var i := bfs_q[head]
		head += 1
		var l := (light[i] >> (ch * 4)) & 15
		if l <= 1:
			continue
		var y := i % HEIGHT
		var col := i / HEIGHT
		var z := col % SIZE
		var x := col / SIZE
		for d in range(6):
			var nx := x + ndx[d]
			var ny := y + ndy[d]
			var nz := z + ndz[d]
			if nx < 0 or nx >= SIZE or ny < 0 or ny >= HEIGHT or nz < 0 or nz >= SIZE:
				continue
			var ni := (nx * SIZE + nz) * HEIGHT + ny
			var t := blocks[ni]
			if t != 0 and t != GLASS and t != TORCH:
				continue
			var nl := l - 1
			if ch == 0 and d == 3 and l == 15:
				nl = 15
			if ((light[ni] >> (ch * 4)) & 15) < nl:
				set_l(ni, ch, nl)
				bfs_q.append(ni)
				if track:
					mark_changed(ni)

func unspread(start: int, ch: int):
	rem_q.clear()
	rem_lv.clear()
	bfs_q.clear()
	var old := get_l(start, ch)
	set_l(start, ch, 0)
	rem_q.append(start)
	rem_lv.append(old)
	var head := 0
	while head < rem_q.size():
		var i := rem_q[head]
		var ol := rem_lv[head]
		head += 1
		var y := i % HEIGHT
		var col := i / HEIGHT
		var z := col % SIZE
		var x := col / SIZE
		for d in range(6):
			var nx := x + ndx[d]
			var ny := y + ndy[d]
			var nz := z + ndz[d]
			if nx < 0 or nx >= SIZE or ny < 0 or ny >= HEIGHT or nz < 0 or nz >= SIZE:
				continue
			var ni := (nx * SIZE + nz) * HEIGHT + ny
			var nl := get_l(ni, ch)
			if nl == 0:
				continue
			var dep := nl < ol
			if ch == 0 and d == 3 and ol == 15 and nl == 15:
				dep = true
			if dep:
				set_l(ni, ch, 0)
				rem_q.append(ni)
				rem_lv.append(nl)
				if track:
					mark_changed(ni)
			else:
				bfs_q.append(ni)
	spread(ch)

func seed_from_neighbors(i: int, ch: int):
	bfs_q.clear()
	var y := i % HEIGHT
	var col := i / HEIGHT
	var z := col % SIZE
	var x := col / SIZE
	for d in range(6):
		var nx := x + ndx[d]
		var ny := y + ndy[d]
		var nz := z + ndz[d]
		if nx < 0 or nx >= SIZE or ny < 0 or ny >= HEIGHT or nz < 0 or nz >= SIZE:
			continue
		var ni := (nx * SIZE + nz) * HEIGHT + ny
		if get_l(ni, ch) > 1:
			bfs_q.append(ni)
	spread(ch)

func compute_all_light():
	track = false
	light.resize(SIZE * SIZE * HEIGHT)
	light.fill(0)
	var tops := PackedInt32Array()
	tops.resize(SIZE * SIZE)
	for x in range(SIZE):
		for z in range(SIZE):
			var base := (x * SIZE + z) * HEIGHT
			var y := HEIGHT - 1
			while y >= 0:
				var t := blocks[base + y]
				if t != 0 and t != GLASS and t != TORCH:
					break
				light[base + y] = 15
				y -= 1
			tops[x * SIZE + z] = y
	bfs_q.clear()
	for x in range(SIZE):
		for z in range(SIZE):
			var t0 := tops[x * SIZE + z]
			var m := t0
			if x > 0:
				m = maxi(m, tops[(x - 1) * SIZE + z])
			if x < SIZE - 1:
				m = maxi(m, tops[(x + 1) * SIZE + z])
			if z > 0:
				m = maxi(m, tops[x * SIZE + z - 1])
			if z < SIZE - 1:
				m = maxi(m, tops[x * SIZE + z + 1])
			var base2 := (x * SIZE + z) * HEIGHT
			for y in range(t0 + 1, m + 1):
				bfs_q.append(base2 + y)
	spread(0)
	torch_cells.clear()
	bfs_q.clear()
	var ti := blocks.find(TORCH)
	while ti != -1:
		var ty := ti % HEIGHT
		var tcol := ti / HEIGHT
		torch_cells[Vector3i(tcol / SIZE, ty, tcol % SIZE)] = true
		set_l(ti, 1, 14)
		bfs_q.append(ti)
		ti = blocks.find(TORCH, ti + 1)
	spread(1)

func edit_block(x: int, y: int, z: int, new_t: int):
	var i := idx(x, y, z)
	var old_t := int(blocks[i])
	var was_t := old_t == 0 or old_t == GLASS or old_t == TORCH
	var now_t := new_t == 0 or new_t == GLASS or new_t == TORCH
	track = true
	changed.clear()
	mark_chunk(x, z)
	set_block(x, y, z, new_t)
	if old_t == TORCH:
		torch_cells.erase(Vector3i(x, y, z))
		if get_l(i, 1) > 0:
			unspread(i, 1)
	if new_t == TORCH:
		torch_cells[Vector3i(x, y, z)] = true
	if was_t and not now_t:
		for ch in range(2):
			if get_l(i, ch) > 0:
				unspread(i, ch)
	elif (not was_t) and now_t:
		for ch in range(2):
			seed_from_neighbors(i, ch)
	if new_t == TORCH:
		set_l(i, 1, 14)
		bfs_q.clear()
		bfs_q.append(i)
		spread(1)
	track = false
	flush_changed()
	if old_t == TORCH or new_t == TORCH:
		build_torches()

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
	f.store_32(water_map.size())
	f.store_buffer(water_map)
	f.close()
	var d := DirAccess.open("user://")
	if d:
		var err := d.rename("world.tmp", "world.dat")
		if err != OK:
			d.remove("world.dat")
			d.rename("world.tmp", "world.dat")
	save_state()
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
	var wn := f.get_32()
	if wn != SIZE * SIZE:
		f.close()
		return false
	var wdata := f.get_buffer(wn)
	f.close()
	if data.size() != n or wdata.size() != wn:
		return false
	blocks = data
	water_map = wdata
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
	day_time = DAY_LEN * 0.08
	compute_all_light()
	build_all_chunks()
	build_water()
	build_torches()
	save_world()

func shade(x: int, y: int, z: int) -> float:
	return 0.88 + 0.12 * fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)

func build_all_chunks():
	for cx in range(CN):
		for cz in range(CN):
			build_chunk(cx, cz)

func make_mm(positions: Array[Vector3], colors: Array[Color], mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
	return mm

func make_mm_lit(positions: Array[Vector3], colors: Array[Color], lights: Array[Color]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = box_mesh
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, lights[i])
	return mm

func set_chunk_node(store: Dictionary, key: Vector2i, mm: MultiMesh, mat: Material):
	if store.has(key):
		store[key].multimesh = mm
	else:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = mat
		add_child(node)
		store[key] = node

func clear_light(x: int, y: int, z: int) -> int:
	if y < 0:
		return -1
	if y >= HEIGHT or x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return 15
	var i := (x * SIZE + z) * HEIGHT + y
	var t := blocks[i]
	if t == 0 or t == GLASS or t == TORCH:
		return light[i]
	return -1

func air_light(x: int, y: int, z: int) -> int:
	if y < 0:
		return -1
	if y >= HEIGHT or x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return 15
	var i := (x * SIZE + z) * HEIGHT + y
	var t := blocks[i]
	if t == 0 or t == TORCH:
		return light[i]
	return -1

func lmax(a: int, b: int, c: int, d: int, e: int, f: int, shift: int) -> int:
	var m := 0
	if a >= 0:
		m = maxi(m, (a >> shift) & 15)
	if b >= 0:
		m = maxi(m, (b >> shift) & 15)
	if c >= 0:
		m = maxi(m, (c >> shift) & 15)
	if d >= 0:
		m = maxi(m, (d >> shift) & 15)
	if e >= 0:
		m = maxi(m, (e >> shift) & 15)
	if f >= 0:
		m = maxi(m, (f >> shift) & 15)
	return m

func build_chunk(cx: int, cz: int):
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	var lights: Array[Color] = []
	var gpos: Array[Vector3] = []
	var gcols: Array[Color] = []
	var glights: Array[Color] = []
	for x in range(cx * CHUNK, mini((cx + 1) * CHUNK, SIZE)):
		for z in range(cz * CHUNK, mini((cz + 1) * CHUNK, SIZE)):
			var base := (x * SIZE + z) * HEIGHT
			var top := col_top[x * SIZE + z]
			for y in range(top + 1):
				var t := blocks[base + y]
				if t == 0 or t == TORCH:
					continue
				if t == GLASS:
					var g1 := air_light(x - 1, y, z)
					var g2 := air_light(x + 1, y, z)
					var g3 := air_light(x, y - 1, z)
					var g4 := air_light(x, y + 1, z)
					var g5 := air_light(x, y, z - 1)
					var g6 := air_light(x, y, z + 1)
					if g1 < 0 and g2 < 0 and g3 < 0 and g4 < 0 and g5 < 0 and g6 < 0:
						continue
					gpos.append(Vector3(x, y, z))
					gcols.append(Color(0.8, 0.92, 1.0, 0.35))
					glights.append(Color(lmax(g1, g2, g3, g4, g5, g6, 0) / 15.0, lmax(g1, g2, g3, g4, g5, g6, 4) / 15.0, 0.0, 0.0))
				else:
					var l1 := clear_light(x - 1, y, z)
					var l2 := clear_light(x + 1, y, z)
					var l3 := clear_light(x, y - 1, z)
					var l4 := clear_light(x, y + 1, z)
					var l5 := clear_light(x, y, z - 1)
					var l6 := clear_light(x, y, z + 1)
					if l1 < 0 and l2 < 0 and l3 < 0 and l4 < 0 and l5 < 0 and l6 < 0:
						continue
					var bc: Color = palette[t]
					var s := shade(x, y, z)
					positions.append(Vector3(x, y, z))
					colors.append(Color(bc.r * s, bc.g * s, bc.b * s))
					lights.append(Color(lmax(l1, l2, l3, l4, l5, l6, 0) / 15.0, lmax(l1, l2, l3, l4, l5, l6, 4) / 15.0, 0.0, 0.0))
	var key := Vector2i(cx, cz)
	set_chunk_node(chunks, key, make_mm_lit(positions, colors, lights), block_mat)
	set_chunk_node(gchunks, key, make_mm_lit(gpos, gcols, glights), glass_mat)

func build_water():
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	for x in range(SIZE):
		for z in range(SIZE):
			if water_map[x * SIZE + z] == 1:
				positions.append(Vector3(x, WL, z))
				colors.append(Color(1, 1, 1, 1))
	var mm := make_mm(positions, colors, plane_mesh)
	if water_node == null:
		water_node = MultiMeshInstance3D.new()
		water_node.material_override = water_mat
		add_child(water_node)
	water_node.multimesh = mm

func build_torches():
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	for k in torch_cells.keys():
		var c: Vector3i = k
		positions.append(Vector3(c.x, c.y - 0.2, c.z))
		colors.append(Color(1, 1, 1, 1))
	var mm := make_mm(positions, colors, torch_mesh)
	if torch_node == null:
		torch_node = MultiMeshInstance3D.new()
		torch_node.material_override = torch_mat
		add_child(torch_node)
	torch_node.multimesh = mm

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
	edit_block(c.x, c.y, c.z, 0)
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
	var t: int = hotbar[selected]
	var i := idx(p.x, p.y, p.z)
	blocks[i] = t
	var hits_player := collides(pos)
	blocks[i] = 0
	if hits_player:
		return
	edit_block(p.x, p.y, p.z, t)
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
	var s := sz.y * 0.09
	var gap := sz.y * 0.0135
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
	hud.underwater = water_at(pos.x, pos.y + EYE, pos.z)
	var rects: Array[Rect2] = []
	for i in range(hotbar.size()):
		rects.append(slot_rect(i, sz))
	hud.slot_rects = rects
	hud.selected = selected
	hud.queue_redraw()
	update_sky()
	if menu_open:
		return

	day_time = fposmod(day_time + delta, DAY_LEN)
	save_timer += delta
	if dirty and save_timer > 15.0:
		save_world()

	in_water = water_at(pos.x, pos.y + 0.6, pos.z)
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