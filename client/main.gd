extends Node

const MANAGE_SERVER_LIFECYCLE_SETTING = "rumpelmc/server/manage_lifecycle"
const SERVER_HOST = "127.0.0.1"
const SERVER_PORT = 25565
const SERVER_CONNECT_TIMEOUT_MS = 250
const VISUAL_SMOKE_PATH_ENV = "RUMPELMC_VISUAL_SMOKE_PATH"
const VISUAL_SMOKE_DELAY_ENV = "RUMPELMC_VISUAL_SMOKE_DELAY_SEC"
const VISUAL_SMOKE_HIDE_HUD_ENV = "RUMPELMC_VISUAL_SMOKE_HIDE_HUD"
const VISUAL_SMOKE_POSE_ENV = "RUMPELMC_VISUAL_SMOKE_POSE"
const VISUAL_SMOKE_MOTION_ENV = "RUMPELMC_VISUAL_SMOKE_MOTION"
const VISUAL_SMOKE_MOTION_STEP_SEC_ENV = "RUMPELMC_VISUAL_SMOKE_MOTION_STEP_SEC"
const VISUAL_SMOKE_MOTION_SETTLE_SEC_ENV = "RUMPELMC_VISUAL_SMOKE_MOTION_SETTLE_SEC"
const VISUAL_SMOKE_BLOCK_EDIT_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT"
const VISUAL_SMOKE_BLOCK_EDIT_X_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_X"
const VISUAL_SMOKE_BLOCK_EDIT_Y_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Y"
const VISUAL_SMOKE_BLOCK_EDIT_Z_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Z"
const VISUAL_SMOKE_BLOCK_EDIT_ID_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_ID"
const VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC_ENV = "RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC"
const VISUAL_SMOKE_FRAME_SAMPLE_SEC_ENV = "RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC"
const VISUAL_SMOKE_FORCE_UNCAPPED_ENV = "RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED"
const VISUAL_SMOKE_MAX_FPS_ENV = "RUMPELMC_VISUAL_SMOKE_MAX_FPS"
const VISUAL_SMOKE_DEFAULT_DELAY_SEC = 6.0
const VISUAL_SMOKE_DEFAULT_FRAME_SAMPLE_SEC = 2.0
const VISUAL_SMOKE_DEFAULT_MOTION_STEP_SEC = 0.55
const VISUAL_SMOKE_DEFAULT_MOTION_SETTLE_SEC = 0.0
const VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_WAIT_SEC = 3.0
const VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_X = 112
const VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_Y = 64
const VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_Z = 80
const VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_ID = 1
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
const VISUAL_SMOKE_CHUNK_SIZE = 32.0

var server_pid: int = -1
var manage_server_lifecycle: bool = false
var pending_dev_logs: Array[String] = []
var visual_smoke_requested: bool = false
var visual_smoke_frame_window_sec: float = VISUAL_SMOKE_DEFAULT_FRAME_SAMPLE_SEC
var visual_smoke_frame_times: Array[float] = []
var visual_smoke_frame_ms: Array[float] = []
var visual_smoke_process_wall_ms: Array[float] = []
var visual_smoke_motion_name: String = "none"
var visual_smoke_motion_steps: int = 0
var visual_smoke_motion_chunks = {}
var visual_smoke_block_edit_name: String = "none"
var visual_smoke_block_edit_dirty_observed: int = 0

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

func _process(delta):
	var process_start_usec = Time.get_ticks_usec()
	record_visual_smoke_frame(delta)
	sync_window_content_size()
	record_visual_smoke_process_wall(float(Time.get_ticks_usec() - process_start_usec) / 1000.0)

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
	configure_visual_smoke_frame_pacing()

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
	visual_smoke_motion_name = normalized_visual_smoke_motion()
	log_event("Visual smoke capture started path=%s pose=\"%s\" motion=\"%s\"" % [
		globalize_smoke_path(screenshot_path),
		pose_name,
		visual_smoke_motion_name
	])
	await run_visual_smoke_motion(visual_smoke_motion_name)
	log_event("Visual smoke motion complete motion=\"%s\" motion_steps=%d motion_chunks=%d current_chunk=\"%s\"" % [
		visual_smoke_motion_name,
		visual_smoke_motion_steps,
		visual_smoke_motion_chunks.size(),
		visual_smoke_client_text("get_current_chunk_text", "n/a")
	])
	await run_visual_smoke_block_edit()
	apply_visual_smoke_pose(pose_name)
	var ground_metrics = visual_smoke_ground_metrics()
	var post_draw_wait_start_usec = Time.get_ticks_usec()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var post_draw_wait_ms = float(Time.get_ticks_usec() - post_draw_wait_start_usec) / 1000.0
	log_event("Visual smoke post draw complete post_draw_wait_ms=%.3f" % post_draw_wait_ms)

	var image_read_start_usec = Time.get_ticks_usec()
	var image = get_viewport().get_texture().get_image()
	var image_read_ms = float(Time.get_ticks_usec() - image_read_start_usec) / 1000.0
	var output_path = globalize_smoke_path(screenshot_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image_save_start_usec = Time.get_ticks_usec()
	var err = image.save_png(output_path)
	var image_save_ms = float(Time.get_ticks_usec() - image_save_start_usec) / 1000.0
	log_event("Visual smoke image saved path=%s save_err=%d image_read_ms=%.3f image_save_ms=%.3f" % [
		output_path,
		err,
		image_read_ms,
		image_save_ms
	])
	var image_metrics_start_usec = Time.get_ticks_usec()
	var metrics = image_visual_metrics(image)
	var image_metrics_ms = float(Time.get_ticks_usec() - image_metrics_start_usec) / 1000.0
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
	var process_metrics = visual_smoke_process_wall_metrics()
	var runtime_metrics = visual_smoke_runtime_metrics()
	var summary = "Visual smoke screenshot saved path=%s pose=\"%s\" motion=\"%s\" motion_steps=%d motion_chunks=%d block_edit=\"%s\" block_edit_dirty_observed=%d size=%dx%d avg_luma=%.4f lit_samples=%d terrain_samples=%d terrain_top_samples=%d terrain_mid_samples=%d terrain_bottom_samples=%d terrain_left_samples=%d terrain_right_samples=%d terrain_color_buckets=%d terrain_chroma_samples=%d terrain_luma_min=%.4f terrain_luma_max=%.4f terrain_luma_range=%.4f samples=%d save_err=%d smoke_err=%d frame_samples=%d frame_avg_ms=%.3f frame_p50_ms=%.3f frame_p95_ms=%.3f frame_p99_ms=%.3f frame_max_ms=%.3f fps_avg=%.1f fps_p05=%.1f fps_min=%.1f process_wall_samples=%d process_wall_avg_ms=%.3f process_wall_p95_ms=%.3f process_wall_max_ms=%.3f post_draw_wait_ms=%.3f image_read_ms=%.3f image_save_ms=%.3f image_metrics_ms=%.3f engine_max_fps=%d vsync_mode=%d screen_refresh_hz=%.3f texture_stand=%d current_chunk_loaded=%d current_chunk_submeshes=%d current_chunk_collision=%d ground_hit=%d ground_distance=%.3f ground_y=%.3f ground_samples=%d ground_hits=%d ground_misses=%d ground_max_distance=%.3f ground_min_y=%.3f perf=\"%s\" chunks=\"%s\" current_chunk=\"%s\"" % [
		output_path,
		pose_name,
		visual_smoke_motion_name,
		visual_smoke_motion_steps,
		visual_smoke_motion_chunks.size(),
		visual_smoke_block_edit_name,
		visual_smoke_block_edit_dirty_observed,
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
		process_metrics["samples"],
		process_metrics["avg_ms"],
		process_metrics["p95_ms"],
		process_metrics["max_ms"],
		post_draw_wait_ms,
		image_read_ms,
		image_save_ms,
		image_metrics_ms,
		runtime_metrics["engine_max_fps"],
		runtime_metrics["vsync_mode"],
		runtime_metrics["screen_refresh_hz"],
		visual_smoke_client_flag("is_texture_debug_stand_visible"),
		visual_smoke_client_int("get_current_chunk_loaded", 0),
		visual_smoke_client_int("get_current_chunk_rendered_count", 0),
		visual_smoke_client_int("get_current_chunk_collision_count", 0),
		ground_metrics["hit"],
		ground_metrics["distance"],
		ground_metrics["y"],
		ground_metrics["samples"],
		ground_metrics["hits"],
		ground_metrics["misses"],
		ground_metrics["max_distance"],
		ground_metrics["min_y"],
		visual_smoke_client_text("get_perf_text", "n/a"),
		visual_smoke_chunk_text(),
		visual_smoke_client_text("get_current_chunk_text", "n/a")
	]
	write_visual_smoke_marker(output_path + ".txt", summary)
	log_event(summary)
	shutdown_visual_smoke_runtime()
	await get_tree().process_frame
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

func visual_smoke_client_int(method: String, fallback: int) -> int:
	var client = get_node_or_null("GameClient")
	if client and client.has_method(method):
		return int(client.call(method))
	return fallback

func visual_smoke_ground_metrics() -> Dictionary:
	var player = get_tree().root.find_child("Player", true, false) as Node3D
	if not player:
		return {
			"hit": 0,
			"distance": -1.0,
			"y": 0.0,
			"samples": 0,
			"hits": 0,
			"misses": 0,
			"max_distance": -1.0,
			"min_y": 0.0
		}
	var center = visual_smoke_ground_sample(player, Vector3.ZERO)
	var samples = 0
	var hits = 0
	var max_distance = 0.0
	var min_y = INF
	for offset_x in [-8.0, 0.0, 8.0]:
		for offset_z in [-8.0, 0.0, 8.0]:
			samples += 1
			var sample = visual_smoke_ground_sample(player, Vector3(offset_x, 0.0, offset_z))
			if sample["hit"] == 0:
				continue
			hits += 1
			max_distance = max(max_distance, sample["distance"])
			min_y = min(min_y, sample["y"])
	if hits == 0:
		min_y = 0.0
	return {
		"hit": center["hit"],
		"distance": center["distance"],
		"y": center["y"],
		"samples": samples,
		"hits": hits,
		"misses": samples - hits,
		"max_distance": max_distance,
		"min_y": min_y
	}

func visual_smoke_ground_sample(player: Node3D, horizontal_offset: Vector3) -> Dictionary:
	var origin = player.global_position + horizontal_offset + Vector3(0.0, 1.0, 0.0)
	var target = origin + Vector3(0.0, -160.0, 0.0)
	var query = PhysicsRayQueryParameters3D.create(origin, target)
	if player.has_method("get_rid"):
		query.exclude = [player.get_rid()]
	var result = player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": 0, "distance": -1.0, "y": 0.0}
	var hit_position: Vector3 = result["position"]
	return {
		"hit": 1,
		"distance": origin.distance_to(hit_position),
		"y": hit_position.y
	}

func visual_smoke_chunk_text() -> String:
	var client = get_node_or_null("GameClient")
	if client and client.has_method("get_loaded_chunk_count") and client.has_method("get_rendered_chunk_count") and client.has_method("get_chunk_collision_count"):
		return "%d loaded, %d submeshes, %d collision" % [
			client.get_loaded_chunk_count(),
			client.get_rendered_chunk_count(),
			client.get_chunk_collision_count()
		]
	return "n/a"

func shutdown_visual_smoke_runtime():
	var client = get_node_or_null("GameClient")
	if client and client.has_method("shutdown_for_quit"):
		log_event("Visual smoke runtime shutdown requested")
		client.shutdown_for_quit()

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
		if not visual_smoke_process_wall_ms.is_empty():
			visual_smoke_process_wall_ms.pop_front()

func record_visual_smoke_process_wall(wall_ms: float):
	if not visual_smoke_requested:
		return

	visual_smoke_process_wall_ms.append(wall_ms)

func visual_smoke_frame_metrics() -> Dictionary:
	if visual_smoke_frame_ms.is_empty():
		var empty_metrics = empty_timing_metrics()
		empty_metrics["fps_avg"] = 0.0
		empty_metrics["fps_p05"] = 0.0
		empty_metrics["fps_min"] = 0.0
		return empty_metrics

	var metrics = timing_metrics(visual_smoke_frame_ms)
	metrics["fps_avg"] = fps_from_frame_ms(metrics["avg_ms"])
	metrics["fps_p05"] = fps_from_frame_ms(metrics["p95_ms"])
	metrics["fps_min"] = fps_from_frame_ms(metrics["max_ms"])
	return metrics

func visual_smoke_process_wall_metrics() -> Dictionary:
	return timing_metrics(visual_smoke_process_wall_ms)

func timing_metrics(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return empty_timing_metrics()

	var sorted_ms = values.duplicate()
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
		"max_ms": max_ms
	}

func empty_timing_metrics() -> Dictionary:
	return {
		"samples": 0,
		"avg_ms": 0.0,
		"p50_ms": 0.0,
		"p95_ms": 0.0,
		"p99_ms": 0.0,
		"max_ms": 0.0
	}

func configure_visual_smoke_frame_pacing():
	var max_fps_value = OS.get_environment(VISUAL_SMOKE_MAX_FPS_ENV).strip_edges()
	if not env_flag_enabled(VISUAL_SMOKE_FORCE_UNCAPPED_ENV) and max_fps_value.is_empty():
		return

	var requested_max_fps = 0
	if max_fps_value.is_valid_int():
		requested_max_fps = max(int(max_fps_value), 0)
	Engine.max_fps = requested_max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	log_event("Visual smoke frame pacing configured: max_fps=%d vsync=disabled" % requested_max_fps)

func visual_smoke_runtime_metrics() -> Dictionary:
	var screen = DisplayServer.window_get_current_screen()
	return {
		"engine_max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(screen)
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

func normalized_visual_smoke_motion() -> String:
	var motion = OS.get_environment(VISUAL_SMOKE_MOTION_ENV).strip_edges().to_lower()
	if motion.is_empty():
		return "none"
	return motion

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

func run_visual_smoke_motion(motion_name: String):
	visual_smoke_motion_steps = 0
	visual_smoke_motion_chunks.clear()
	if motion_name != "chunk_walk" and motion_name != "chunk_walk_long" and motion_name != "chunk_walk_extended" and motion_name != "chunk_fly_out_back":
		return

	var player = get_tree().root.find_child("Player", true, false) as Node3D
	if not player:
		return

	var camera = visual_smoke_player_camera(player)
	var step_sec = max(env_float(VISUAL_SMOKE_MOTION_STEP_SEC_ENV, VISUAL_SMOKE_DEFAULT_MOTION_STEP_SEC), 0.05)
	var positions = visual_smoke_motion_positions(motion_name)
	for position in positions:
		player.global_position = position
		visual_smoke_motion_steps += 1
		visual_smoke_motion_chunks[visual_smoke_chunk_key(position)] = true
		if camera:
			apply_visual_smoke_look_at(player, camera, position, position + Vector3(24.0, -10.0, -28.0))
		await get_tree().process_frame
		await get_tree().create_timer(step_sec).timeout

	var settle_sec = max(env_float(VISUAL_SMOKE_MOTION_SETTLE_SEC_ENV, VISUAL_SMOKE_DEFAULT_MOTION_SETTLE_SEC), 0.0)
	if settle_sec > 0.0:
		await get_tree().create_timer(settle_sec).timeout

func visual_smoke_motion_positions(motion_name: String) -> Array[Vector3]:
	var positions: Array[Vector3] = [
		Vector3(16.0, 74.0, 16.0),
		Vector3(48.0, 74.0, 16.0),
		Vector3(80.0, 74.0, 48.0),
		Vector3(112.0, 74.0, 80.0)
	]
	if motion_name == "chunk_walk_long" or motion_name == "chunk_walk_extended":
		positions.append_array([
			Vector3(144.0, 74.0, 112.0),
			Vector3(176.0, 74.0, 112.0),
			Vector3(208.0, 74.0, 144.0),
			Vector3(240.0, 74.0, 176.0)
		])
	if motion_name == "chunk_walk_extended":
		positions.append_array([
			Vector3(272.0, 74.0, 208.0),
			Vector3(304.0, 74.0, 240.0),
			Vector3(336.0, 74.0, 240.0),
			Vector3(368.0, 74.0, 272.0)
		])
	if motion_name == "chunk_fly_out_back":
		return [
			Vector3(16.0, 84.0, 16.0),
			Vector3(80.0, 84.0, 16.0),
			Vector3(144.0, 84.0, 16.0),
			Vector3(208.0, 84.0, 16.0),
			Vector3(272.0, 84.0, 16.0),
			Vector3(336.0, 84.0, 16.0),
			Vector3(400.0, 84.0, 16.0),
			Vector3(336.0, 84.0, 16.0),
			Vector3(272.0, 84.0, 16.0),
			Vector3(208.0, 84.0, 16.0),
			Vector3(144.0, 84.0, 16.0),
			Vector3(80.0, 84.0, 16.0),
			Vector3(16.0, 74.0, 16.0)
		]
	return positions

func run_visual_smoke_block_edit():
	visual_smoke_block_edit_name = OS.get_environment(VISUAL_SMOKE_BLOCK_EDIT_ENV).strip_edges().to_lower()
	visual_smoke_block_edit_dirty_observed = 0
	if visual_smoke_block_edit_name.is_empty() or visual_smoke_block_edit_name == "none":
		visual_smoke_block_edit_name = "none"
		return

	var client = get_node_or_null("GameClient")
	if not client:
		log_event("Visual smoke block edit skipped: missing GameClient")
		return
	if not client.has_method("on_block_broken") or not client.has_method("on_block_placed"):
		log_event("Visual smoke block edit skipped: missing block edit methods")
		return

	var x = env_int(VISUAL_SMOKE_BLOCK_EDIT_X_ENV, VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_X)
	var y = env_int(VISUAL_SMOKE_BLOCK_EDIT_Y_ENV, VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_Y)
	var z = env_int(VISUAL_SMOKE_BLOCK_EDIT_Z_ENV, VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_Z)
	var block_id = env_int(VISUAL_SMOKE_BLOCK_EDIT_ID_ENV, VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_ID)
	var wait_sec = max(env_float(VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC_ENV, VISUAL_SMOKE_DEFAULT_BLOCK_EDIT_WAIT_SEC), 0.1)
	log_event("Visual smoke block edit started action=%s x=%d y=%d z=%d block_id=%d" % [
		visual_smoke_block_edit_name,
		x,
		y,
		z,
		block_id
	])

	var before_dirty = visual_smoke_perf_int("dirty_blocks", 0)
	match visual_smoke_block_edit_name:
		"break", "destroy":
			client.call("on_block_broken", x, y, z)
		"place":
			client.call("on_block_placed", x, y, z, block_id)
		"toggle":
			client.call("on_block_placed", x, y, z, block_id)
			await wait_for_visual_smoke_dirty_update(before_dirty, wait_sec)
			before_dirty = visual_smoke_perf_int("dirty_blocks", before_dirty)
			client.call("on_block_broken", x, y, z)
		_:
			log_event("Unknown visual smoke block edit: %s" % visual_smoke_block_edit_name)
			visual_smoke_block_edit_name = "unknown"
			return

	var dirty_seen = await wait_for_visual_smoke_dirty_update(before_dirty, wait_sec)
	visual_smoke_block_edit_dirty_observed = 1 if dirty_seen else 0
	log_event("Visual smoke block edit complete action=%s dirty_observed=%d dirty_blocks=%d chunk_replace=%d" % [
		visual_smoke_block_edit_name,
		visual_smoke_block_edit_dirty_observed,
		visual_smoke_perf_int("dirty_blocks", 0),
		visual_smoke_perf_int("chunk_replace", 0)
	])

func wait_for_visual_smoke_dirty_update(before_dirty: int, wait_sec: float) -> bool:
	var deadline_msec = Time.get_ticks_msec() + int(wait_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
		if visual_smoke_perf_int("dirty_blocks", 0) > before_dirty:
			return true
	return false

func visual_smoke_perf_int(key: String, fallback: int) -> int:
	var text = visual_smoke_client_text("get_perf_text", "")
	var prefix = key + "="
	var start = text.find(prefix)
	if start < 0:
		return fallback
	var index = start + prefix.length()
	var end = index
	while end < text.length():
		var code = text.unicode_at(end)
		if code < 48 or code > 57:
			break
		end += 1
	if end == index:
		return fallback
	return int(text.substr(index, end - index))

func visual_smoke_chunk_key(position: Vector3) -> String:
	return "%d,%d" % [
		floori(position.x / VISUAL_SMOKE_CHUNK_SIZE),
		floori(position.z / VISUAL_SMOKE_CHUNK_SIZE)
	]

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

func env_int(name: String, fallback: int) -> int:
	var value = OS.get_environment(name).strip_edges()
	if value.is_valid_int():
		return int(value)
	return fallback
