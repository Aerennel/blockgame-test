extends Node3D

const CHUNK := 16
const WSIZE := 256
const WMASK := 255
const HEIGHT := 40
const WATER := 12
const WL := WATER + 0.4
const VIEW := 32
const UNLOAD := 7
const REACH := 6.0
const DAY_LEN := 480.0
const CAVE_W := 0.07
const FRAME_BUDGET_US := 9000
const FILL_N := 600
const SPREAD_N := 500

const PW := 0.3
const PH := 1.8
const EYE := 1.6
const SPEED := 5.0
const GRAVITY := 25.0
const JUMP_V := 8.5
const LOOK_SENS := 0.004
const REPEAT := 0.22

const SAVE_PATH := "user://world3.dat"
const SAVE_TMP := "user://world3.tmp"
const SAVE_VERSION := 3

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

const J_GEN := 1
const J_MESH := 2

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
var tops := PackedInt32Array()
var lstate := PackedByteArray()

var world_seed := 0
var noise_a: FastNoiseLite
var noise_b: FastNoiseLite
var cave_a: FastNoiseLite
var cave_b: FastNoiseLite
var cave_c: FastNoiseLite

var loaded_keys := {}
var saved_chunks := {}
var modified := {}
var torch_cells := {}
var torches_dirty := false
var chunks := {}
var gchunks := {}
var wchunks := {}
var changed := {}
var track := false

var jq := BQ.new()
var eq := BQ.new()

var want: Array[Vector2i] = []
var want_i := 0
var mesh_set := {}
var last_pc := Vector2i.ZERO
var job_type := 0
var job_key := Vector2i.ZERO
var job_stage := 0
var job_step := 0
var job_saved := false
var j_pos: Array[Vector3] = []
var j_col: Array[Color] = []
var j_lit: Array[Color] = []
var j_gpos: Array[Vector3] = []
var j_gcol: Array[Color] = []
var j_glit: Array[Color] = []
var j_mm: MultiMesh
var j_gmm: MultiMesh

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
	blocks.resize(WSIZE * WSIZE * HEIGHT)
	blocks.fill(0)
	light.resize(WSIZE * WSIZE * HEIGHT)
	light.fill(0)
	heights.resize(WSIZE * WSIZE)
	heights.fill(0)
	col_top.resize(WSIZE * WSIZE)
	col_top.fill(0)
	tops.resize(WSIZE * WSIZE)
	tops.fill(-1)
	lstate.resize(256)
	lstate.fill(0)
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
	var from_save := load_world_file()
	if not from_save:
		world_seed = randi() & 0x3fffffff
	init_noise(world_seed)
	if not from_save:
		pos = find_spawn()
	begin_world()

func begin_world():
	vel = Vector3.ZERO
	last_pc = player_chunk()
	refresh_want(last_pc, 1)
	run_jobs(1 << 30)
	while collides(pos) and pos.y < HEIGHT:
		pos.y += 1.0
	refresh_want(last_pc, VIEW)
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
	env_res.fog_enabled = true
	env_res.fog_density = 0.01
	env_res.fog_light_color = Color(0.53, 0.81, 0.92)
	env.environment = env_res
	add_child(env)

func setup_sky():
	sky_root = Node3D.new()
	add_child(sky_root)
	var sun_mat := StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.95, 0.7)
	sun_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sun_mat.disable_fog = true
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
	moon_mat.disable_fog = true
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
	star_mat.disable_fog = true
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
	env_res.fog_light_color = sky_c
	var k := lerpf(0.2, 1.0, d)
	water_mat.albedo_color = Color(0.25 * k, 0.55 * k, 0.95 * k, 0.65)
	star_mat.albedo_color = Color(1, 1, 1, clampf(1.0 - d * 1.6, 0.0, 1.0))
	var sd := Vector3(cos(a), sin(a), 0.3).normalized()
	sky_root.position = cam.position
	sun_node.position = sd * 250.0
	moon_node.position = -sd * 250.0
	sun_node.visible = sh > -0.08
	moon_node.visible = sh < 0.08

func init_noise(s: int):
	noise_a = FastNoiseLite.new()
	noise_a.seed = s
	noise_a.frequency = 0.035
	noise_b = FastNoiseLite.new()
	noise_b.seed = s + 101
	noise_b.frequency = 0.008
	cave_a = FastNoiseLite.new()
	cave_a.seed = s + 202
	cave_a.frequency = 0.03
	cave_a.fractal_type = FastNoiseLite.FRACTAL_NONE
	cave_b = FastNoiseLite.new()
	cave_b.seed = s + 303
	cave_b.frequency = 0.03
	cave_b.fractal_type = FastNoiseLite.FRACTAL_NONE
	cave_c = FastNoiseLite.new()
	cave_c.seed = s + 404
	cave_c.frequency = 0.025
	cave_c.fractal_type = FastNoiseLite.FRACTAL_NONE

func terrain_h(x: int, z: int) -> int:
	var h := int(round(noise_a.get_noise_2d(x, z) * 9.0 + noise_b.get_noise_2d(x, z) * 8.0 + 14.0))
	return clampi(h, 2, 30)

func col_seed(x: int, z: int) -> int:
	return ((x * 73856093) ^ (z * 19349663) ^ (world_seed * 83492791)) & 0x7fffffff

func tree_r(x: int, z: int) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + world_seed * 0.0137) * 43758.5453, 1.0)

func find_spawn() -> Vector3:
	for r in range(0, 80):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var h := terrain_h(dx, dz)
				if h > WATER + 1 and h < 20:
					return Vector3(dx, h + 0.5 + 0.01, dz)
	return Vector3(0, 30, 0)

func cidx(x: int, z: int) -> int:
	return (x & WMASK) * WSIZE + (z & WMASK)

func lidx(x: int, y: int, z: int) -> int:
	return ((x & WMASK) * WSIZE + (z & WMASK)) * HEIGHT + y

func lkey(cx: int, cz: int) -> int:
	return ((cx & 15) << 4) | (cz & 15)

func is_loaded(cx: int, cz: int) -> bool:
	return lstate[((cx & 15) << 4) | (cz & 15)] == 1

func player_chunk() -> Vector2i:
	return Vector2i(floori(pos.x + 0.5) >> 4, floori(pos.z + 0.5) >> 4)

func get_type(x: int, y: int, z: int) -> int:
	if y < 0 or y >= HEIGHT:
		return 0
	if not is_loaded(x >> 4, z >> 4):
		return 0
	return blocks[lidx(x, y, z)]

func set_block(x: int, y: int, z: int, t: int):
	if y < 0 or y >= HEIGHT:
		return
	var c := cidx(x, z)
	blocks[c * HEIGHT + y] = t
	if t != 0 and y > col_top[c]:
		col_top[c] = y

func is_solid(x: int, y: int, z: int) -> bool:
	if y < 0:
		return true
	if y >= HEIGHT:
		return false
	if not is_loaded(x >> 4, z >> 4):
		return true
	var t := blocks[lidx(x, y, z)]
	return t != 0 and t != TORCH

func water_at(wx: float, wy: float, wz: float) -> bool:
	if wy > WL:
		return false
	var x := roundi(wx)
	var y := roundi(wy)
	var z := roundi(wz)
	if not is_loaded(x >> 4, z >> 4):
		return false
	if heights[cidx(x, z)] >= WATER:
		return false
	return get_type(x, y, z) == 0

func get_l(i: int, ch: int) -> int:
	return (light[i] >> (ch * 4)) & 15

func set_l(i: int, ch: int, v: int):
	if ch == 0:
		light[i] = (light[i] & 240) | v
	else:
		light[i] = (light[i] & 15) | (v << 4)

func gen_range(cx: int, cz: int, lx0: int, lx1: int):
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var rng := RandomNumberGenerator.new()
	for lx in range(lx0, lx1):
		for lz in range(CHUNK):
			var x := x0 + lx
			var z := z0 + lz
			var c := cidx(x, z)
			var base := c * HEIGHT
			var h := terrain_h(x, z)
			heights[c] = h
			rng.seed = col_seed(x, z)
			var top := 0
			for y in range(HEIGHT):
				if y > h:
					blocks[base + y] = 0
					continue
				var t := STONE
				if y == h:
					if h <= WATER + 1:
						t = SAND
					elif h >= 24:
						t = SNOW
					elif h >= 20:
						t = STONE
					else:
						t = GRASS
				elif h < 20 and y > h - 4:
					t = DIRT
				else:
					if h >= WATER + 2 and y >= 3:
						if absf(cave_a.get_noise_3d(x, y * 1.3, z)) < CAVE_W and absf(cave_b.get_noise_3d(x, y * 1.3, z)) < CAVE_W:
							blocks[base + y] = 0
							continue
						if y < h - 8 and cave_c.get_noise_3d(x, y * 1.3, z) > 0.5:
							blocks[base + y] = 0
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
				blocks[base + y] = t
				top = y
			col_top[c] = top

func put_leaf(x: int, y: int, z: int, t: int, x0: int, z0: int):
	if x < x0 or x >= x0 + CHUNK or z < z0 or z >= z0 + CHUNK or y < 0 or y >= HEIGHT:
		return
	var c := cidx(x, z)
	var i := c * HEIGHT + y
	if blocks[i] != 0:
		return
	blocks[i] = t
	if y > col_top[c]:
		col_top[c] = y

func gen_trees(cx: int, cz: int):
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for tx in range(x0 - 2, x0 + CHUNK + 2):
		for tz in range(z0 - 2, z0 + CHUNK + 2):
			if tree_r(tx, tz) >= 0.015:
				continue
			var h := terrain_h(tx, tz)
			if h <= WATER + 1 or h >= 20:
				continue
			for i in range(1, 5):
				put_leaf(tx, h + i, tz, WOOD, x0, z0)
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if abs(dx) == 2 and abs(dz) == 2:
						continue
					if dx == 0 and dz == 0:
						continue
					put_leaf(tx + dx, h + 3, tz + dz, LEAVES, x0, z0)
					put_leaf(tx + dx, h + 4, tz + dz, LEAVES, x0, z0)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					put_leaf(tx + dx, h + 5, tz + dz, LEAVES, x0, z0)

func extract_chunk(cx: int, cz: int) -> PackedByteArray:
	var out := PackedByteArray()
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for lx in range(CHUNK):
		for lz in range(CHUNK):
			var base := cidx(x0 + lx, z0 + lz) * HEIGHT
			out.append_array(blocks.slice(base, base + HEIGHT))
	return out

func load_saved(cx: int, cz: int, data: PackedByteArray):
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for lx in range(CHUNK):
		for lz in range(CHUNK):
			var x := x0 + lx
			var z := z0 + lz
			var c := cidx(x, z)
			var base := c * HEIGHT
			var src := (lx * CHUNK + lz) * HEIGHT
			var top := 0
			for y in range(HEIGHT):
				var t := data[src + y]
				blocks[base + y] = t
				if t != 0:
					top = y
				if t == TORCH:
					torch_cells[Vector3i(x, y, z)] = true
					torches_dirty = true
			heights[c] = terrain_h(x, z)
			col_top[c] = top

func top_or(x: int, z: int, fallback: int) -> int:
	if is_loaded(x >> 4, z >> 4):
		return tops[cidx(x, z)]
	return fallback

func light_init_chunk(cx: int, cz: int):
	jq.clear()
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for lx in range(CHUNK):
		for lz in range(CHUNK):
			var c := cidx(x0 + lx, z0 + lz)
			var base := c * HEIGHT
			var y := HEIGHT - 1
			while y >= 0:
				var t := blocks[base + y]
				if t != 0 and t != GLASS and t != TORCH:
					break
				light[base + y] = 15
				y -= 1
			tops[c] = y
			while y >= 0:
				light[base + y] = 0
				y -= 1
	for lx in range(CHUNK):
		for lz in range(CHUNK):
			var x := x0 + lx
			var z := z0 + lz
			var t0 := tops[cidx(x, z)]
			var m := t0
			m = maxi(m, top_or(x + 1, z, t0))
			m = maxi(m, top_or(x - 1, z, t0))
			m = maxi(m, top_or(x, z + 1, t0))
			m = maxi(m, top_or(x, z - 1, t0))
			for y in range(t0 + 1, m + 1):
				jq.push(x, y, z)

func seed_torches(cx: int, cz: int):
	jq.clear()
	for k in torch_cells.keys():
		var c: Vector3i = k
		if (c.x >> 4) == cx and (c.z >> 4) == cz:
			var i := lidx(c.x, c.y, c.z)
			set_l(i, 1, 14)
			jq.push(c.x, c.y, c.z)

func relax_border(cx: int, cz: int, ch: int):
	jq.clear()
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for s in range(4):
		var ncx := cx
		var ncz := cz
		if s == 0:
			ncx = cx - 1
		elif s == 1:
			ncx = cx + 1
		elif s == 2:
			ncz = cz - 1
		else:
			ncz = cz + 1
		if not is_loaded(ncx, ncz):
			continue
		for k in range(CHUNK):
			var ax := 0
			var az := 0
			var bx := 0
			var bz := 0
			if s == 0:
				ax = x0
				az = z0 + k
				bx = x0 - 1
				bz = az
			elif s == 1:
				ax = x0 + CHUNK - 1
				az = z0 + k
				bx = ax + 1
				bz = az
			elif s == 2:
				ax = x0 + k
				az = z0
				bx = ax
				bz = z0 - 1
			else:
				ax = x0 + k
				az = z0 + CHUNK - 1
				bx = ax
				bz = az + 1
			var ab := cidx(ax, az) * HEIGHT
			var bb := cidx(bx, bz) * HEIGHT
			for y in range(HEIGHT):
				var ta := blocks[ab + y]
				if (ta == 0 or ta == GLASS or ta == TORCH) and ((light[ab + y] >> (ch * 4)) & 15) > 1:
					jq.push(ax, y, az)
				var tb := blocks[bb + y]
				if (tb == 0 or tb == GLASS or tb == TORCH) and ((light[bb + y] >> (ch * 4)) & 15) > 1:
					jq.push(bx, y, bz)

func spread_n(q: BQ, ch: int, n: int) -> bool:
	var cnt := 0
	while q.head < q.xs.size():
		if cnt >= n:
			return false
		cnt += 1
		var x := q.xs[q.head]
		var y := q.ys[q.head]
		var z := q.zs[q.head]
		q.head += 1
		var l := (light[lidx(x, y, z)] >> (ch * 4)) & 15
		if l <= 1:
			continue
		var cxk := x >> 4
		var czk := z >> 4
		for d in range(6):
			var nx := x + ndx[d]
			var ny := y + ndy[d]
			var nz := z + ndz[d]
			if ny < 0 or ny >= HEIGHT:
				continue
			if (nx >> 4) != cxk or (nz >> 4) != czk:
				if not is_loaded(nx >> 4, nz >> 4):
					continue
			var ni := lidx(nx, ny, nz)
			var t := blocks[ni]
			if t != 0 and t != GLASS and t != TORCH:
				continue
			var nl := l - 1
			if ch == 0 and d == 3 and l == 15:
				nl = 15
			if ((light[ni] >> (ch * 4)) & 15) < nl:
				set_l(ni, ch, nl)
				q.push(nx, ny, nz)
				if track:
					mark_cell(nx, nz)
	q.clear()
	return true

func unspread(sx: int, sy: int, sz: int, ch: int):
	var rx := PackedInt32Array()
	var ry := PackedInt32Array()
	var rz := PackedInt32Array()
	var rl := PackedInt32Array()
	eq.clear()
	var si := lidx(sx, sy, sz)
	var old := get_l(si, ch)
	set_l(si, ch, 0)
	rx.append(sx)
	ry.append(sy)
	rz.append(sz)
	rl.append(old)
	var head := 0
	while head < rx.size():
		var x := rx[head]
		var y := ry[head]
		var z := rz[head]
		var ol := rl[head]
		head += 1
		for d in range(6):
			var nx := x + ndx[d]
			var ny := y + ndy[d]
			var nz := z + ndz[d]
			if ny < 0 or ny >= HEIGHT:
				continue
			if not is_loaded(nx >> 4, nz >> 4):
				continue
			var ni := lidx(nx, ny, nz)
			var nl := get_l(ni, ch)
			if nl == 0:
				continue
			var dep := nl < ol
			if ch == 0 and d == 3 and ol == 15 and nl == 15:
				dep = true
			if dep:
				set_l(ni, ch, 0)
				rx.append(nx)
				ry.append(ny)
				rz.append(nz)
				rl.append(nl)
				if track:
					mark_cell(nx, nz)
			else:
				eq.push(nx, ny, nz)
	while not spread_n(eq, ch, 1000000):
		pass

func seed_from_neighbors(x: int, y: int, z: int, ch: int):
	eq.clear()
	for d in range(6):
		var nx := x + ndx[d]
		var ny := y + ndy[d]
		var nz := z + ndz[d]
		if ny < 0 or ny >= HEIGHT:
			continue
		if not is_loaded(nx >> 4, nz >> 4):
			continue
		if get_l(lidx(nx, ny, nz), ch) > 1:
			eq.push(nx, ny, nz)
	while not spread_n(eq, ch, 1000000):
		pass

func update_top(x: int, z: int):
	var c := cidx(x, z)
	var base := c * HEIGHT
	var y := HEIGHT - 1
	while y >= 0:
		var t := blocks[base + y]
		if t != 0 and t != GLASS and t != TORCH:
			break
		y -= 1
	tops[c] = y

func mark_cell(x: int, z: int):
	var cx := x >> 4
	var cz := z >> 4
	changed[Vector2i(cx, cz)] = true
	var lx := x & 15
	var lz := z & 15
	if lx == 0:
		changed[Vector2i(cx - 1, cz)] = true
	if lx == 15:
		changed[Vector2i(cx + 1, cz)] = true
	if lz == 0:
		changed[Vector2i(cx, cz - 1)] = true
	if lz == 15:
		changed[Vector2i(cx, cz + 1)] = true

func flush_changed():
	for k in changed.keys():
		var key: Vector2i = k
		if is_loaded(key.x, key.y):
			build_chunk_now(key.x, key.y)
	changed.clear()

func edit_block(x: int, y: int, z: int, new_t: int):
	var cx := x >> 4
	var cz := z >> 4
	if not is_loaded(cx, cz):
		return
	var i := lidx(x, y, z)
	var old_t := int(blocks[i])
	var was_t := old_t == 0 or old_t == GLASS or old_t == TORCH
	var now_t := new_t == 0 or new_t == GLASS or new_t == TORCH
	track = true
	changed.clear()
	mark_cell(x, z)
	set_block(x, y, z, new_t)
	modified[Vector2i(cx, cz)] = true
	update_top(x, z)
	if old_t == TORCH:
		torch_cells.erase(Vector3i(x, y, z))
		torches_dirty = true
		if get_l(i, 1) > 0:
			unspread(x, y, z, 1)
	if new_t == TORCH:
		torch_cells[Vector3i(x, y, z)] = true
		torches_dirty = true
	if was_t and not now_t:
		for ch in range(2):
			if get_l(i, ch) > 0:
				unspread(x, y, z, ch)
	elif (not was_t) and now_t:
		for ch in range(2):
			seed_from_neighbors(x, y, z, ch)
	if new_t == TORCH:
		set_l(i, 1, 14)
		eq.clear()
		eq.push(x, y, z)
		while not spread_n(eq, 1, 1000000):
			pass
	track = false
	flush_changed()

func save_world():
	for k in modified.keys():
		var key: Vector2i = k
		if is_loaded(key.x, key.y):
			saved_chunks[key] = extract_chunk(key.x, key.y)
	var f := FileAccess.open_compressed(SAVE_TMP, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_32(SAVE_VERSION)
	f.store_32(world_seed)
	f.store_float(pos.x)
	f.store_float(pos.y)
	f.store_float(pos.z)
	f.store_float(yaw)
	f.store_float(pitch)
	f.store_32(selected)
	f.store_float(day_time)
	f.store_var(saved_chunks)
	f.close()
	var d := DirAccess.open("user://")
	if d:
		var err := d.rename("world3.tmp", "world3.dat")
		if err != OK:
			d.remove("world3.dat")
			d.rename("world3.tmp", "world3.dat")
	dirty = false
	save_timer = 0.0

func load_world_file() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open_compressed(SAVE_PATH, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	if f.get_32() != SAVE_VERSION:
		f.close()
		return false
	world_seed = f.get_32()
	var px := f.get_float()
	var py := f.get_float()
	var pz := f.get_float()
	yaw = f.get_float()
	pitch = f.get_float()
	selected = clampi(f.get_32(), 0, hotbar.size() - 1)
	day_time = f.get_float()
	var d = f.get_var()
	f.close()
	if not (d is Dictionary):
		return false
	saved_chunks = d
	for k in saved_chunks.keys():
		modified[k] = true
	pos = Vector3(px, py, pz)
	return true

func unload_chunk(key: Vector2i, snapshot: bool):
	if snapshot and modified.has(key):
		saved_chunks[key] = extract_chunk(key.x, key.y)
	lstate[lkey(key.x, key.y)] = 0
	loaded_keys.erase(key)
	for store in [chunks, gchunks, wchunks]:
		if store.has(key):
			store[key].queue_free()
			store.erase(key)
	mesh_set.erase(key)
	for k in torch_cells.keys():
		var c: Vector3i = k
		if (c.x >> 4) == key.x and (c.z >> 4) == key.y:
			torch_cells.erase(k)
			torches_dirty = true

func unload_far(pc: Vector2i):
	for k in loaded_keys.keys():
		var key: Vector2i = k
		if maxi(absi(key.x - pc.x), absi(key.y - pc.y)) > UNLOAD:
			unload_chunk(key, true)

func new_world():
	for k in loaded_keys.keys():
		var key: Vector2i = k
		unload_chunk(key, false)
	saved_chunks.clear()
	modified.clear()
	torch_cells.clear()
	mesh_set.clear()
	job_type = 0
	world_seed = randi() & 0x3fffffff
	init_noise(world_seed)
	day_time = DAY_LEN * 0.08
	yaw = 0.0
	pitch = 0.0
	pos = find_spawn()
	begin_world()
	save_world()

func refresh_want(pc: Vector2i, radius: int):
	want.clear()
	want_i = 0
	var r2 := (radius + 0.5) * (radius + 0.5)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz <= r2:
				var key := Vector2i(pc.x + dx, pc.y + dz)
				if not is_loaded(key.x, key.y):
					want.append(key)
	want.sort_custom(func(a, b): return a.distance_squared_to(pc) < b.distance_squared_to(pc))

func run_jobs(budget_us: int):
	var t0 := Time.get_ticks_usec()
	while true:
		if job_type == 0:
			if not pick_job():
				break
			if job_type == 0:
				continue
		var done := false
		if job_type == J_GEN:
			done = gen_step()
		else:
			done = mesh_step()
		if done:
			job_type = 0
		if Time.get_ticks_usec() - t0 > budget_us:
			break

func pick_job() -> bool:
	var best := Vector2i.ZERO
	var best_d := 1 << 30
	var have := false
	var low_best := Vector2i.ZERO
	var low_d := 1 << 30
	var have_low := false
	for k in mesh_set.keys():
		var key: Vector2i = k
		var d: int = key.distance_squared_to(last_pc)
		if int(mesh_set[key]) == 0:
			if d < best_d:
				best_d = d
				best = key
				have = true
		else:
			if d < low_d:
				low_d = d
				low_best = key
				have_low = true
	if have:
		start_mesh(best)
		return true
	while want_i < want.size():
		var wk := want[want_i]
		want_i += 1
		if not is_loaded(wk.x, wk.y):
			start_gen(wk)
			return true
	if have_low:
		start_mesh(low_best)
		return true
	return false

func start_gen(key: Vector2i):
	job_type = J_GEN
	job_key = key
	job_stage = 0
	job_step = 0
	job_saved = saved_chunks.has(key)

func start_mesh(key: Vector2i):
	mesh_set.erase(key)
	if not is_loaded(key.x, key.y):
		return
	job_type = J_MESH
	job_key = key
	job_stage = 0
	job_step = 0
	j_pos = []
	j_col = []
	j_lit = []
	j_gpos = []
	j_gcol = []
	j_glit = []

func gen_step() -> bool:
	var cx := job_key.x
	var cz := job_key.y
	match job_stage:
		0:
			if job_saved:
				load_saved(cx, cz, saved_chunks[job_key])
				job_stage = 2
				job_step = 0
			else:
				gen_range(cx, cz, job_step * 2, job_step * 2 + 2)
				job_step += 1
				if job_step >= 8:
					job_stage = 1
					job_step = 0
		1:
			gen_trees(cx, cz)
			job_stage = 2
			job_step = 0
		2:
			lstate[lkey(cx, cz)] = 1
			loaded_keys[job_key] = true
			light_init_chunk(cx, cz)
			job_stage = 3
			job_step = 0
		3:
			if spread_n(jq, 0, SPREAD_N):
				job_stage = 4
				job_step = 0
		4:
			if job_step == 0:
				seed_torches(cx, cz)
				job_step = 1
			elif spread_n(jq, 1, SPREAD_N):
				job_stage = 5
				job_step = 0
		5:
			if job_step == 0:
				relax_border(cx, cz, 0)
				job_step = 1
			elif spread_n(jq, 0, SPREAD_N):
				job_stage = 6
				job_step = 0
		6:
			if job_step == 0:
				relax_border(cx, cz, 1)
				job_step = 1
			elif spread_n(jq, 1, SPREAD_N):
				finish_gen(cx, cz)
				return true
	return false

func finish_gen(cx: int, cz: int):
	mesh_set[job_key] = 0
	var nbs := [Vector2i(cx - 1, cz), Vector2i(cx + 1, cz), Vector2i(cx, cz - 1), Vector2i(cx, cz + 1)]
	for nk in nbs:
		if chunks.has(nk) and not mesh_set.has(nk):
			mesh_set[nk] = 1

func shade(x: int, y: int, z: int) -> float:
	return 0.88 + 0.12 * fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)

func clear_light(x: int, y: int, z: int, cxk: int, czk: int) -> int:
	if y < 0:
		return -1
	if y >= HEIGHT:
		return 15
	if (x >> 4) != cxk or (z >> 4) != czk:
		if not is_loaded(x >> 4, z >> 4):
			return 15
	var i := lidx(x, y, z)
	var t := blocks[i]
	if t == 0 or t == GLASS or t == TORCH:
		return light[i]
	return -1

func air_light(x: int, y: int, z: int, cxk: int, czk: int) -> int:
	if y < 0:
		return -1
	if y >= HEIGHT:
		return 15
	if (x >> 4) != cxk or (z >> 4) != czk:
		if not is_loaded(x >> 4, z >> 4):
			return 15
	var i := lidx(x, y, z)
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

func mesh_range(cx: int, cz: int, lx0: int, lx1: int, pos_a: Array[Vector3], col_a: Array[Color], lit_a: Array[Color], gpos_a: Array[Vector3], gcol_a: Array[Color], glit_a: Array[Color]):
	for lx in range(lx0, lx1):
		for lz in range(CHUNK):
			var x := cx * CHUNK + lx
			var z := cz * CHUNK + lz
			var c := cidx(x, z)
			var base := c * HEIGHT
			var top := col_top[c]
			for y in range(top + 1):
				var t := blocks[base + y]
				if t == 0 or t == TORCH:
					continue
				if t == GLASS:
					var g1 := air_light(x - 1, y, z, cx, cz)
					var g2 := air_light(x + 1, y, z, cx, cz)
					var g3 := air_light(x, y - 1, z, cx, cz)
					var g4 := air_light(x, y + 1, z, cx, cz)
					var g5 := air_light(x, y, z - 1, cx, cz)
					var g6 := air_light(x, y, z + 1, cx, cz)
					if g1 < 0 and g2 < 0 and g3 < 0 and g4 < 0 and g5 < 0 and g6 < 0:
						continue
					gpos_a.append(Vector3(x, y, z))
					gcol_a.append(Color(0.8, 0.92, 1.0, 0.35))
					glit_a.append(Color(lmax(g1, g2, g3, g4, g5, g6, 0) / 15.0, lmax(g1, g2, g3, g4, g5, g6, 4) / 15.0, 0.0, 0.0))
				else:
					var l1 := clear_light(x - 1, y, z, cx, cz)
					var l2 := clear_light(x + 1, y, z, cx, cz)
					var l3 := clear_light(x, y - 1, z, cx, cz)
					var l4 := clear_light(x, y + 1, z, cx, cz)
					var l5 := clear_light(x, y, z - 1, cx, cz)
					var l6 := clear_light(x, y, z + 1, cx, cz)
					if l1 < 0 and l2 < 0 and l3 < 0 and l4 < 0 and l5 < 0 and l6 < 0:
						continue
					var bc: Color = palette[t]
					var s := shade(x, y, z)
					pos_a.append(Vector3(x, y, z))
					col_a.append(Color(bc.r * s, bc.g * s, bc.b * s))
					lit_a.append(Color(lmax(l1, l2, l3, l4, l5, l6, 0) / 15.0, lmax(l1, l2, l3, l4, l5, l6, 4) / 15.0, 0.0, 0.0))

func new_mm(count: int, custom: bool, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = custom
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func fill_mm(mm: MultiMesh, p: Array[Vector3], c: Array[Color], l: Array[Color], a: int, b: int):
	for i in range(a, b):
		mm.set_instance_transform(i, Transform3D(Basis(), p[i]))
		mm.set_instance_color(i, c[i])
		mm.set_instance_custom_data(i, l[i])

func make_water_mm(cx: int, cz: int) -> MultiMesh:
	var wp: Array[Vector3] = []
	for lx in range(CHUNK):
		for lz in range(CHUNK):
			var x := cx * CHUNK + lx
			var z := cz * CHUNK + lz
			if heights[cidx(x, z)] < WATER:
				wp.append(Vector3(x, WL, z))
	var mm := new_mm(wp.size(), false, plane_mesh)
	for i in range(wp.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), wp[i]))
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

func attach_mesh(key: Vector2i, mo: MultiMesh, mg: MultiMesh, mw: MultiMesh):
	set_chunk_node(chunks, key, mo, block_mat)
	set_chunk_node(gchunks, key, mg, glass_mat)
	set_chunk_node(wchunks, key, mw, water_mat)

func build_chunk_now(cx: int, cz: int):
	var p: Array[Vector3] = []
	var c: Array[Color] = []
	var l: Array[Color] = []
	var gp: Array[Vector3] = []
	var gc: Array[Color] = []
	var gl: Array[Color] = []
	mesh_range(cx, cz, 0, CHUNK, p, c, l, gp, gc, gl)
	var mo := new_mm(p.size(), true, box_mesh)
	fill_mm(mo, p, c, l, 0, p.size())
	var mg := new_mm(gp.size(), true, box_mesh)
	fill_mm(mg, gp, gc, gl, 0, gp.size())
	attach_mesh(Vector2i(cx, cz), mo, mg, make_water_mm(cx, cz))

func mesh_step() -> bool:
	var cx := job_key.x
	var cz := job_key.y
	if not is_loaded(cx, cz):
		return true
	match job_stage:
		0:
			mesh_range(cx, cz, job_step * 2, job_step * 2 + 2, j_pos, j_col, j_lit, j_gpos, j_gcol, j_glit)
			job_step += 1
			if job_step >= 8:
				job_stage = 1
				job_step = 0
				j_mm = new_mm(j_pos.size(), true, box_mesh)
		1:
			var a := job_step * FILL_N
			var b := mini(a + FILL_N, j_pos.size())
			fill_mm(j_mm, j_pos, j_col, j_lit, a, b)
			job_step += 1
			if b >= j_pos.size():
				job_stage = 2
				job_step = 0
				j_gmm = new_mm(j_gpos.size(), true, box_mesh)
		2:
			var a2 := job_step * FILL_N
			var b2 := mini(a2 + FILL_N, j_gpos.size())
			fill_mm(j_gmm, j_gpos, j_gcol, j_glit, a2, b2)
			job_step += 1
			if b2 >= j_gpos.size():
				job_stage = 3
				job_step = 0
		3:
			attach_mesh(job_key, j_mm, j_gmm, make_water_mm(cx, cz))
			return true
	return false

func build_torches():
	torches_dirty = false
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = torch_mesh
	mm.instance_count = torch_cells.size()
	var i := 0
	for k in torch_cells.keys():
		var c: Vector3i = k
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x, c.y - 0.2, c.z)))
		i += 1
	if torch_node == null:
		torch_node = MultiMeshInstance3D.new()
		torch_node.material_override = torch_mat
		add_child(torch_node)
	torch_node.multimesh = mm

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
	if p.y < 0 or p.y >= HEIGHT:
		return
	if not is_loaded(p.x >> 4, p.z >> 4):
		return
	if get_type(p.x, p.y, p.z) != 0:
		return
	var t: int = hotbar[selected]
	var i := lidx(p.x, p.y, p.z)
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
	hud.info = "FPS %d  чанков %d  очередь %d" % [Engine.get_frames_per_second(), loaded_keys.size(), want.size() - want_i + mesh_set.size()]
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

	var pc := player_chunk()
	if pc != last_pc:
		last_pc = pc
		unload_far(pc)
		refresh_want(pc, VIEW)
	run_jobs(FRAME_BUDGET_US)
	if torches_dirty:
		build_torches()

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

class BQ:
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var zs := PackedInt32Array()
	var head := 0

	func clear():
		xs.clear()
		ys.clear()
		zs.clear()
		head = 0

	func push(x: int, y: int, z: int):
		xs.append(x)
		ys.append(y)
		zs.append(z)

class Hud extends Control:
	var joy_active := false
	var joy_base := Vector2.ZERO
	var joy_knob := Vector2.ZERO
	var jump_pos := Vector2.ZERO
	var break_pos := Vector2.ZERO
	var place_pos := Vector2.ZERO
	var pause_pos := Vector2.ZERO
	var underwater := false
	var info := ""
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
		draw_string(ThemeDB.fallback_font, Vector2(h * 0.22, h * 0.06), info, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.032), Color(1, 1, 1, 0.55))