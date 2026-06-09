extends Node

const MANAGE_SERVER_LIFECYCLE_SETTING = "rumpelmc/server/manage_lifecycle"
const SERVER_HOST = "127.0.0.1"
const SERVER_PORT = 25565
const SERVER_CONNECT_TIMEOUT_MS = 250
const VISUAL_SMOKE_PATH_ENV = "RUMPELMC_VISUAL_SMOKE_PATH"
const VISUAL_SMOKE_DELAY_ENV = "RUMPELMC_VISUAL_SMOKE_DELAY_SEC"
const VISUAL_SMOKE_HIDE_HUD_ENV = "RUMPELMC_VISUAL_SMOKE_HIDE_HUD"
const VISUAL_SMOKE_DEFAULT_DELAY_SEC = 6.0
const VISUAL_SMOKE_SKY_COLOR = Color(0.34, 0.43, 0.54)
const VISUAL_SMOKE_SKY_DISTANCE_THRESHOLD = 0.08
const VISUAL_SMOKE_MIN_TERRAIN_SAMPLES = 12

var server_pid: int = -1
var manage_server_lifecycle: bool = false
var pending_dev_logs: Array[String] = []

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
	var image = get_viewport().get_texture().get_image()
	var output_path = globalize_smoke_path(screenshot_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var err = image.save_png(output_path)
	var metrics = image_visual_metrics(image)
	var smoke_err = err
	if smoke_err == OK and metrics["terrain_samples"] < VISUAL_SMOKE_MIN_TERRAIN_SAMPLES:
		smoke_err = FAILED
	var summary = "Visual smoke screenshot saved path=%s size=%dx%d avg_luma=%.4f lit_samples=%d terrain_samples=%d samples=%d save_err=%d smoke_err=%d perf=\"%s\" chunks=\"%s\" current_chunk=\"%s\"" % [
		output_path,
		image.get_width(),
		image.get_height(),
		metrics["avg_luma"],
		metrics["lit_samples"],
		metrics["terrain_samples"],
		metrics["samples"],
		err,
		smoke_err,
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

func visual_smoke_chunk_text() -> String:
	var client = get_node_or_null("GameClient")
	if client and client.has_method("get_loaded_chunk_count") and client.has_method("get_rendered_chunk_count") and client.has_method("get_chunk_collision_count"):
		return "%d loaded, %d submeshes, %d collision" % [
			client.get_loaded_chunk_count(),
			client.get_rendered_chunk_count(),
			client.get_chunk_collision_count()
		]
	return "n/a"

func globalize_smoke_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

func image_visual_metrics(image: Image) -> Dictionary:
	var width = image.get_width()
	var height = image.get_height()
	var step_x = max(int(width / 32), 1)
	var step_y = max(int(height / 18), 1)
	var samples = 0
	var lit_samples = 0
	var terrain_samples = 0
	var luma_sum = 0.0

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

	var avg_luma = 0.0
	if samples > 0:
		avg_luma = luma_sum / samples
	return {
		"avg_luma": avg_luma,
		"lit_samples": lit_samples,
		"terrain_samples": terrain_samples,
		"samples": samples
	}

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
