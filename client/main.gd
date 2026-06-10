extends Node

const MANAGE_SERVER_LIFECYCLE_SETTING = "rumpelmc/server/manage_lifecycle"
const SERVER_HOST = "127.0.0.1"
const SERVER_PORT = 25565
const SERVER_CONNECT_TIMEOUT_MS = 250
const VISUAL_SMOKE_PATH_ENV = "RUMPELMC_VISUAL_SMOKE_PATH"
const VISUAL_SMOKE_DELAY_ENV = "RUMPELMC_VISUAL_SMOKE_DELAY_SEC"
const VISUAL_SMOKE_HIDE_HUD_ENV = "RUMPELMC_VISUAL_SMOKE_HIDE_HUD"
const VISUAL_SMOKE_POSE_ENV = "RUMPELMC_VISUAL_SMOKE_POSE"
const VISUAL_SMOKE_FRAME_SAMPLE_SEC_ENV = "RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC"
const VISUAL_SMOKE_DEFAULT_DELAY_SEC = 6.0
const VISUAL_SMOKE_DEFAULT_FRAME_SAMPLE_SEC = 2.0
const VISUAL_SMOKE_SKY_COLOR = Color(0.34, 0.43, 0.54)
const VISUAL_SMOKE_SKY_DISTANCE_THRESHOLD = 0.08
const VISUAL_SMOKE_MIN_TERRAIN_SAMPLES = 12
const VISUAL_SMOKE_MIN_TERRAIN_REGION_SAMPLES = 8
const VISUAL_SMOKE_MIN_TERRAIN_COLOR_BUCKETS = 4
const VISUAL_SMOKE_MIN_TERRAIN_CHROMA_SAMPLES = 8
const VISUAL_SMOKE_MIN_TERRAIN_LUMA_RANGE = 0.06
const VISUAL_SMOKE_COLOR_BUCKET_LEVELS = 6
const VISUAL_SMOKE_CHROMA_THRESHOLD = 0.05
const VISUAL_SMOKE_DEFAULT_POSE = "default"

var server_pid: int = -1
var manage_server_lifecycle: bool = false
var pending_dev_logs: Array[String] = []
var visual_smoke_requested: bool = false
var visual_smoke_frame_window_sec: float = VISUAL_SMOKE_DEFAULT_FRAME_SAMPLE_SEC
var visual_smoke_frame_times: Array[float] = []
var visual_smoke_frame_ms: Array[float] = []

func _ready():
	configure_window_stretch()
	configure_world_lighting()
	ensure_server_lifecycle_setting()
	manage_server_lifecycle = ProjectSettings.get_setting(MANAGE_SERVER_LIFECYCLE_SETTING, false)

	if is_server_listening():
		log_event("Go server is already running on %s:%d" % [SERVER_HOST, SERVER_PORT])
	else:
		log_event("Starting local Go server...")
		start_local_server()

	await get_tree().create_timer(1.0).timeout

	log_event("Adding GameClient node...")
	var client = ClassDB.instantiate("GameClient")
	client.name = "GameClient"
	if client.has_signal("debug_log"):
		client.connect("debug_log", Callable(self, "on_debug_log"))
	add_child(client)

	log_event("Adding HUD...")
	var hud_script = load("res://hud.gd")
	if hud_script:
		var hud = hud_script.new()
		hud.name = "HUD"
		add_child(hud)
		for entry in pending_dev_logs:
			hud.add_log(entry)
		pending_dev_logs.clear()
		log_event("HUD added")
	else:
		log_event("Failed to load hud.gd!")

	run_visual_smoke_if_requested()

func _process(_delta):
	record_visual_smoke_frame(_delta)
	sync_window_content_size()

func configure_window_stretch():
	var window = get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	sync_window_content_size()
	if not window.size_changed.is_connected(sync_window_content_size):
		window.size_changed.connect(sync_window_content_size)

func sync_window_content_size():
	var window = get_window()
	var size = window.size
	if size.x > 0 and size.y > 0 and window.content_scale_size != size:
		window.content_scale_size = size

func configure_world_lighting():
	var world_environment = get_node_or_null("WorldEnvironment")
	if not world_environment:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)

	var environment = world_environment.environment
	if not environment:
		environment = Environment.new()
		world_environment.environment = environment

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.34, 0.43, 0.54)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.14, 0.16)
	environment.ambient_light_energy = 0.06
	environment.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	environment.adjustment_enabled = false
	environment.sky = null

	var sun = get_node_or_null("SunLight")
	if not sun:
		sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		add_child(sun)
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -32, 0)

func start_local_server():
	var exe_path = find_server_executable()
	if exe_path.is_empty():
		log_event("Failed to start local Go server! Build the server binary first.")
	else:
		server_pid = OS.create_process(exe_path, [])
		if server_pid == -1:
			log_event("Failed to start local Go server! Is it executable?")
		else:
			log_event("Go server started with PID: %d" % server_pid)

func _exit_tree():
	if manage_server_lifecycle and server_pid != -1:
		OS.kill(server_pid)
		server_pid = -1

func is_server_listening() -> bool:
	var peer = StreamPeerTCP.new()
	var err = peer.connect_to_host(SERVER_HOST, SERVER_PORT)
	if err != OK:
		return false

	var deadline = Time.get_ticks_msec() + SERVER_CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status = peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if status == StreamPeerTCP.STATUS_ERROR:
			return false

	peer.disconnect_from_host()
	return false

func find_server_executable() -> String:
	var candidates = [
		"res://../server/server",
		"res://../server/tmp/main",
		"res://../server/server.exe",
		"res://../server/tmp/main.exe"
	]
	for candidate in candidates:
		var path = ProjectSettings.globalize_path(candidate)
		if FileAccess.file_exists(path):
			return path
	return ""

func ensure_server_lifecycle_setting():
	if not ProjectSettings.has_setting(MANAGE_SERVER_LIFECYCLE_SETTING):
		ProjectSettings.set_setting(MANAGE_SERVER_LIFECYCLE_SETTING, false)

func log_event(message: String):
	print(message)
	append_dev_log(message)

func append_dev_log(message: String):
	var hud = get_node_or_null("HUD")
	if hud and hud.has_method("add_log"):
		hud.add_log(message)
	else:
		pending_dev_logs.append(message)

func on_debug_log(message: String):
	append_dev_log(message)

func run_visual_smoke_if_requested():
	var screenshot_path = OS.get_environment(VISUAL_SMOKE_PATH_ENV)
	if screenshot_path.is_empty():
		return

	visual_smoke_requested = true
	visual_smoke_frame_window_sec = max(
		env_float(VISUAL_SMOKE_FRAME_SAMPLE_SEC_ENV, VISUAL_SMOKE_DEFAULT_FRAME_SAMPLE_SEC),
		0.1
	)

	if env_flag_enabled(VISUAL_SMOKE_HIDE_HUD_ENV):
		var hud = get_node_or_null("HUD")
		if hud:
			hud.visible = false

	var delay_sec = env_float(VISUAL_SMOKE_DELAY_ENV, VISUAL_SMOKE_DEFAULT_DELAY_SEC)
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = delay_sec
	timer.timeout.connect(Callable(self, "capture_visual_smoke").bind(screenshot_path))
	add_child(timer)
	timer.start()

func capture_visual_smoke(screenshot_path: String):
	var pose_name = normalized_visual_smoke_pose()
	apply_visual_smoke_pose(pose_name)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image = get_viewport().get_texture().get_image()
	var output_path = globalize_smoke_path(screenshot_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var err = image.save_png(output_path)
	var metrics = image_visual_metrics(image)
	var smoke_err = err
	if smoke_err == OK and metrics["terrain_samples"] < VISUAL_SMOKE_MIN_TERRAIN_SAMPLES:
		smoke_err = FAILED
	if smoke_err == OK and metrics["terrain_mid_samples"] < VISUAL_SMOKE_MIN_TERRAIN_REGION_SAMPLES:
		smoke_err = FAILED
	if smoke_err == OK and metrics["terrain_bottom_samples"] < VISUAL_SMOKE_MIN_TERRAIN_REGION_SAMPLES:
		smoke_err = FAILED
	if smoke_err == OK and metrics["terrain_color_buckets"] < VISUAL_SMOKE_MIN_TERRAIN_COLOR_BUCKETS:
		smoke_err = FAILED
	if smoke_err == OK and metrics["terrain_chroma_samples"] < VISUAL_SMOKE_MIN_TERRAIN_CHROMA_SAMPLES:
		smoke_err = FAILED
	if smoke_err == OK and metrics["terrain_luma_range"] < VISUAL_SMOKE_MIN_TERRAIN_LUMA_RANGE:
		smoke_err = FAILED
	var frame_metrics = visual_smoke_frame_metrics()
	var summary = "Visual smoke screenshot saved path=%s pose=\"%s\" size=%dx%d avg_luma=%.4f lit_samples=%d terrain_samples=%d terrain_top_samples=%d terrain_mid_samples=%d terrain_bottom_samples=%d terrain_left_samples=%d terrain_right_samples=%d terrain_color_buckets=%d terrain_chroma_samples=%d terrain_luma_min=%.4f terrain_luma_max=%.4f terrain_luma_range=%.4f samples=%d save_err=%d smoke_err=%d frame_samples=%d frame_avg_ms=%.3f frame_p50_ms=%.3f frame_p95_ms=%.3f frame_p99_ms=%.3f frame_max_ms=%.3f fps_avg=%.1f fps_p05=%.1f fps_min=%.1f texture_stand=%d perf=\"%s\" chunks=\"%s\" current_chunk=\"%s\"" % [
		output_path,
		pose_name,
		image.get_width(),
		image.get_height(),
		metrics["avg_luma"],
		metrics["lit_samples"],
		metrics["terrain_samples"],
		metrics["terrain_top_samples"],
		metrics["terrain_mid_samples"],
		metrics["terrain_bottom_samples"],
		metrics["terrain_left_samples"],
		metrics["terrain_right_samples"],
		metrics["terrain_color_buckets"],
		metrics["terrain_chroma_samples"],
		metrics["terrain_luma_min"],
		metrics["terrain_luma_max"],
		metrics["terrain_luma_range"],
		metrics["samples"],
		err,
		smoke_err,
		frame_metrics["samples"],
		frame_metrics["avg_ms"],
		frame_metrics["p50_ms"],
		frame_metrics["p95_ms"],
		frame_metrics["p99_ms"],
		frame_metrics["max_ms"],
		frame_metrics["fps_avg"],
		frame_metrics["fps_p05"],
		frame_metrics["fps_min"],
		visual_smoke_client_flag("is_texture_debug_stand_visible"),
		visual_smoke_client_text("get_perf_text", "n/a"),
		visual_smoke_chunk_text(),
		visual_smoke_client_text("get_current_chunk_text", "n/a")
	]
	write_visual_smoke_marker(output_path + ".txt", summary)
	log_event(summary)
	get_tree().quit(smoke_err)

func write_visual_smoke_marker(marker_path: String, summary: String):
	var file = FileAccess.open(marker_path, FileAccess.WRITE)
	if file:
		file.store_line(summary)

func visual_smoke_client_text(method: String, fallback: String) -> String:
	var client = get_node_or_null("GameClient")
	if client and client.has_method(method):
		return str(client.call(method))
	return fallback

func visual_smoke_client_flag(method: String) -> int:
	var client = get_node_or_null("GameClient")
	if client and client.has_method(method) and bool(client.call(method)):
		return 1
	return 0

func visual_smoke_chunk_text() -> String:
	var client = get_node_or_null("GameClient")
	if client and client.has_method("get_loaded_chunk_count") and client.has_method("get_rendered_chunk_count") and client.has_method("get_chunk_collision_count"):
		return "%d loaded, %d submeshes, %d collision" % [
			client.get_loaded_chunk_count(),
			client.get_rendered_chunk_count(),
			client.get_chunk_collision_count()
		]
	return "n/a"

func record_visual_smoke_frame(delta: float):
	if not visual_smoke_requested:
		return

	var now_sec = Time.get_ticks_msec() / 1000.0
	visual_smoke_frame_times.append(now_sec)
	visual_smoke_frame_ms.append(delta * 1000.0)
	var cutoff_sec = now_sec - visual_smoke_frame_window_sec
	while not visual_smoke_frame_times.is_empty() and visual_smoke_frame_times[0] < cutoff_sec:
		visual_smoke_frame_times.pop_front()
		visual_smoke_frame_ms.pop_front()

func visual_smoke_frame_metrics() -> Dictionary:
	if visual_smoke_frame_ms.is_empty():
		return {
			"samples": 0,
			"avg_ms": 0.0,
			"p50_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"max_ms": 0.0,
			"fps_avg": 0.0,
			"fps_p05": 0.0,
			"fps_min": 0.0
		}

	var sorted_ms = visual_smoke_frame_ms.duplicate()
	sorted_ms.sort()
	var total_ms = 0.0
	for frame_ms in sorted_ms:
		total_ms += frame_ms
	var avg_ms = total_ms / sorted_ms.size()
	var p50_ms = sorted_percentile(sorted_ms, 0.50)
	var p95_ms = sorted_percentile(sorted_ms, 0.95)
	var p99_ms = sorted_percentile(sorted_ms, 0.99)
	var max_ms = sorted_ms[sorted_ms.size() - 1]
	return {
		"samples": sorted_ms.size(),
		"avg_ms": avg_ms,
		"p50_ms": p50_ms,
		"p95_ms": p95_ms,
		"p99_ms": p99_ms,
		"max_ms": max_ms,
		"fps_avg": fps_from_frame_ms(avg_ms),
		"fps_p05": fps_from_frame_ms(p95_ms),
		"fps_min": fps_from_frame_ms(max_ms)
	}

func sorted_percentile(sorted_values: Array, percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx = int(round((sorted_values.size() - 1) * clamp(percentile, 0.0, 1.0)))
	return sorted_values[idx]

func fps_from_frame_ms(frame_ms: float) -> float:
	if frame_ms <= 0.0:
		return 0.0
	return 1000.0 / frame_ms

func globalize_smoke_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

func normalized_visual_smoke_pose() -> String:
	var pose = OS.get_environment(VISUAL_SMOKE_POSE_ENV).strip_edges().to_lower()
	if pose.is_empty():
		return VISUAL_SMOKE_DEFAULT_POSE
	return pose

func apply_visual_smoke_pose(pose_name: String):
	var player = get_tree().root.find_child("Player", true, false) as Node3D
	if not player:
		return

	var camera = visual_smoke_player_camera(player)
	if not camera:
		return

	match pose_name:
		VISUAL_SMOKE_DEFAULT_POSE:
			return
		"atlas_depth":
			apply_visual_smoke_look_at(player, camera, Vector3(16.0, 76.0, 24.0), Vector3(16.0, 62.0, 3.0))
		"lighting_shadow":
			apply_visual_smoke_look_at(player, camera, Vector3(7.0, 78.0, 25.0), Vector3(25.0, 61.0, 5.0))
		"texture_stand":
			var player_position = Vector3(16.0, 74.0, 24.0)
			apply_visual_smoke_look_at(player, camera, player_position, player_position + Vector3(6.3, 0.5, -5.0))
			show_visual_smoke_texture_stand()
		_:
			log_event("Unknown visual smoke pose: %s" % pose_name)

func visual_smoke_player_camera(player: Node) -> Camera3D:
	for child in player.get_children():
		if child is Camera3D:
			return child
	return null

func apply_visual_smoke_look_at(player: Node3D, camera: Camera3D, position: Vector3, target: Vector3):
	player.global_position = position
	player.rotation = Vector3.ZERO
	camera.position = Vector3(0.0, 1.6, 0.0)
	camera.look_at(target, Vector3.UP)

func show_visual_smoke_texture_stand():
	var client = get_node_or_null("GameClient")
	if not client:
		return
	if not client.has_method("is_texture_debug_stand_visible") or not client.has_method("toggle_texture_debug_stand"):
		return
	if not bool(client.call("is_texture_debug_stand_visible")):
		client.call("toggle_texture_debug_stand")

func image_visual_metrics(image: Image) -> Dictionary:
	var width = image.get_width()
	var height = image.get_height()
	var step_x = max(int(width / 32), 1)
	var step_y = max(int(height / 18), 1)
	var samples = 0
	var lit_samples = 0
	var terrain_samples = 0
	var terrain_top_samples = 0
	var terrain_mid_samples = 0
	var terrain_bottom_samples = 0
	var terrain_left_samples = 0
	var terrain_right_samples = 0
	var terrain_chroma_samples = 0
	var terrain_luma_min = 1.0
	var terrain_luma_max = 0.0
	var terrain_color_buckets = {}
	var luma_sum = 0.0
	var y_first_third = int(height / 3)
	var y_second_third = int(height * 2 / 3)
	var x_mid = int(width / 2)

	for y in range(int(step_y / 2), height, step_y):
		for x in range(int(step_x / 2), width, step_x):
			var color = image.get_pixel(x, y)
			var luma = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			luma_sum += luma
			samples += 1
			if color.a > 0.5 and luma > 0.05:
				lit_samples += 1
			if color_distance(color, VISUAL_SMOKE_SKY_COLOR) > VISUAL_SMOKE_SKY_DISTANCE_THRESHOLD:
				terrain_samples += 1
				if y < y_first_third:
					terrain_top_samples += 1
				elif y < y_second_third:
					terrain_mid_samples += 1
				else:
					terrain_bottom_samples += 1

				if x < x_mid:
					terrain_left_samples += 1
				else:
					terrain_right_samples += 1

				var chroma = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b))
				if chroma >= VISUAL_SMOKE_CHROMA_THRESHOLD:
					terrain_chroma_samples += 1
				terrain_luma_min = min(terrain_luma_min, luma)
				terrain_luma_max = max(terrain_luma_max, luma)
				terrain_color_buckets[visual_smoke_color_bucket(color)] = true

	var avg_luma = 0.0
	if samples > 0:
		avg_luma = luma_sum / samples
	if terrain_samples == 0:
		terrain_luma_min = 0.0
	return {
		"avg_luma": avg_luma,
		"lit_samples": lit_samples,
		"terrain_samples": terrain_samples,
		"terrain_top_samples": terrain_top_samples,
		"terrain_mid_samples": terrain_mid_samples,
		"terrain_bottom_samples": terrain_bottom_samples,
		"terrain_left_samples": terrain_left_samples,
		"terrain_right_samples": terrain_right_samples,
		"terrain_color_buckets": terrain_color_buckets.size(),
		"terrain_chroma_samples": terrain_chroma_samples,
		"terrain_luma_min": terrain_luma_min,
		"terrain_luma_max": terrain_luma_max,
		"terrain_luma_range": terrain_luma_max - terrain_luma_min,
		"samples": samples
	}

func visual_smoke_color_bucket(color: Color) -> String:
	return "%d:%d:%d" % [
		visual_smoke_color_bucket_component(color.r),
		visual_smoke_color_bucket_component(color.g),
		visual_smoke_color_bucket_component(color.b)
	]

func visual_smoke_color_bucket_component(value: float) -> int:
	return min(max(int(value * VISUAL_SMOKE_COLOR_BUCKET_LEVELS), 0), VISUAL_SMOKE_COLOR_BUCKET_LEVELS - 1)

func color_distance(a: Color, b: Color) -> float:
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)

func env_flag_enabled(name: String) -> bool:
	var value = OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"

func env_float(name: String, fallback: float) -> float:
	var value = OS.get_environment(name).strip_edges()
	if value.is_valid_float():
		return float(value)
	return fallback
