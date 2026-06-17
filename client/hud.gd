extends CanvasLayer

const MAX_LOG_LINES = 12
const DEV_UPDATE_INTERVAL = 0.15
const PERF_LOG_INTERVAL = 1.0
const PERF_LOG_MAX_BYTES = 2 * 1024 * 1024
const PERF_LOG_PATH = "res://../logs/perf.log"
const RUN_ID_ENV = "RUMPELMC_RUN_ID"
const DEV_TABS = ["Summary", "Streaming", "Render", "Events", "Logs"]
const CHARACTER_MENU_UPDATE_INTERVAL = 0.2

var selected_block: int = 1
var block_names = {
	1: "Stone",
	2: "Dirt",
	3: "Grass",
	4: "Wood",
	5: "Leaves"
}
var labels = []
var hotbar_labels = []
var fps_label: Label
var tool_label: Label
var dev_panel: PanelContainer
var dev_info_label: Label
var dev_log_label: Label
var dev_tab_buttons = {}
var dev_logs: Array[String] = []
var selected_dev_tab: String = "Summary"
var dev_update_timer: float = 0.0
var character_panel: PanelContainer
var character_appearance_row: HBoxContainer
var character_appearance_buttons = []
var character_animation_option: OptionButton
var character_preview_toggle: CheckBox
var character_third_person_toggle: CheckBox
var character_status_label: Label
var character_update_timer: float = 0.0
var character_known_appearance_count: int = -1
var character_known_animation_count: int = -1
var perf_log_timer: float = 0.0
var perf_log_path: String = ""
var perf_run_id: String = ""
var last_window_size: Vector2i = Vector2i.ZERO
var mouse_mode_before_dev_menu: int = Input.MOUSE_MODE_VISIBLE
var mouse_mode_before_character_menu: int = Input.MOUSE_MODE_VISIBLE

func _ready():
	setup_perf_log()
	create_fps_counter()
	create_dev_menu()
	create_character_menu()
	add_log("HUD initialized")

	# Crosshair (Прицел)
	var crosshair = ColorRect.new()
	crosshair.custom_minimum_size = Vector2(4, 4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.color = Color(1, 1, 1, 0.8)
	add_child(crosshair)

	# Хотбар
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hbox.set_offset(SIDE_BOTTOM, -20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var tool_panel = PanelContainer.new()
	tool_panel.custom_minimum_size = Vector2(140, 60)

	tool_label = Label.new()
	tool_label.text = get_authoritative_tool_text()
	tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tool_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tool_label.add_theme_font_size_override("font_size", 13)

	tool_panel.add_child(tool_label)
	hbox.add_child(tool_panel)

	for i in range(1, 6):
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(100, 60)

		var label = Label.new()
		label.text = str(i) + ": " + block_names[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)

		panel.add_child(label)
		hbox.add_child(panel)
		labels.append(panel)
		hotbar_labels.append(label)

	add_child(hbox)
	update_ui()

func _process(delta):
	update_fps_counter()
	update_ui()
	dev_update_timer -= delta
	if dev_update_timer <= 0.0:
		dev_update_timer = DEV_UPDATE_INTERVAL
		update_dev_menu()

	character_update_timer -= delta
	if character_update_timer <= 0.0:
		character_update_timer = CHARACTER_MENU_UPDATE_INTERVAL
		update_character_menu()

	perf_log_timer -= delta
	if perf_log_timer <= 0.0:
		perf_log_timer = PERF_LOG_INTERVAL
		write_perf_log_sample()

	var window_size = get_window().size
	if window_size != last_window_size:
		last_window_size = window_size
		add_log("Window resized: %dx%d" % [window_size.x, window_size.y])

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I or event.physical_keycode == KEY_I:
			toggle_dev_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C or event.physical_keycode == KEY_C:
			toggle_character_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_T or event.physical_keycode == KEY_T:
			toggle_texture_debug_stand()
			get_viewport().set_input_as_handled()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			selected_block = event.keycode - KEY_0
			add_log("Selected block: %s" % get_block_name(selected_block))
			update_ui()

func create_fps_counter():
	var panel = PanelContainer.new()
	panel.name = "FPS"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 118
	panel.offset_bottom = 46
	panel.add_theme_stylebox_override("panel", make_panel_style(Color(0, 0, 0, 0.56), 5))

	fps_label = Label.new()
	fps_label.text = "FPS --"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	panel.add_child(fps_label)
	add_child(panel)

func create_dev_menu():
	dev_panel = PanelContainer.new()
	dev_panel.name = "DevMenu"
	dev_panel.visible = false
	dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dev_panel.offset_left = 12
	dev_panel.offset_top = 56
	dev_panel.offset_right = 652
	dev_panel.offset_bottom = 596
	dev_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.02, 0.025, 0.03, 0.82), 6))

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	dev_panel.add_child(root)

	var title = Label.new()
	title.text = "DEV"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.98))
	root.add_child(title)

	create_dev_tabs(root)
	create_dev_actions(root)

	var info_scroll = ScrollContainer.new()
	info_scroll.custom_minimum_size = Vector2(0, 250)
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(info_scroll)

	dev_info_label = Label.new()
	dev_info_label.add_theme_font_size_override("font_size", 13)
	dev_info_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.92, 0.96))
	dev_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_scroll.add_child(dev_info_label)

	var log_title = Label.new()
	log_title.text = "LOG"
	log_title.add_theme_font_size_override("font_size", 12)
	log_title.add_theme_color_override("font_color", Color(0.65, 0.78, 0.9, 0.92))
	root.add_child(log_title)

	var log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 120)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(log_scroll)

	dev_log_label = Label.new()
	dev_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev_log_label.add_theme_font_size_override("font_size", 12)
	dev_log_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.86, 0.94))
	log_scroll.add_child(dev_log_label)

	add_child(dev_panel)
	update_dev_menu()

func create_character_menu():
	character_panel = PanelContainer.new()
	character_panel.name = "CharacterCreator"
	character_panel.visible = false
	character_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	character_panel.offset_left = -430
	character_panel.offset_top = 56
	character_panel.offset_right = -12
	character_panel.offset_bottom = 408
	character_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.025, 0.026, 0.03, 0.88), 6))

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	character_panel.add_child(root)

	var title = Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.98))
	root.add_child(title)

	var camera_row = HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 10)
	root.add_child(camera_row)

	character_third_person_toggle = CheckBox.new()
	character_third_person_toggle.text = "Third person"
	character_third_person_toggle.focus_mode = Control.FOCUS_NONE
	character_third_person_toggle.toggled.connect(Callable(self, "set_character_third_person"))
	camera_row.add_child(character_third_person_toggle)

	character_preview_toggle = CheckBox.new()
	character_preview_toggle.text = "Preview"
	character_preview_toggle.focus_mode = Control.FOCUS_NONE
	character_preview_toggle.toggled.connect(Callable(self, "set_character_animation_preview"))
	camera_row.add_child(character_preview_toggle)

	var appearance_title = Label.new()
	appearance_title.text = "APPEARANCE"
	appearance_title.add_theme_font_size_override("font_size", 12)
	appearance_title.add_theme_color_override("font_color", Color(0.66, 0.78, 0.88, 0.94))
	root.add_child(appearance_title)

	character_appearance_row = HBoxContainer.new()
	character_appearance_row.add_theme_constant_override("separation", 6)
	root.add_child(character_appearance_row)

	var animation_title = Label.new()
	animation_title.text = "ANIMATION"
	animation_title.add_theme_font_size_override("font_size", 12)
	animation_title.add_theme_color_override("font_color", Color(0.66, 0.78, 0.88, 0.94))
	root.add_child(animation_title)

	character_animation_option = OptionButton.new()
	character_animation_option.custom_minimum_size = Vector2(388, 34)
	character_animation_option.focus_mode = Control.FOCUS_NONE
	character_animation_option.item_selected.connect(Callable(self, "select_character_animation_clip"))
	root.add_child(character_animation_option)

	character_status_label = Label.new()
	character_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_status_label.add_theme_font_size_override("font_size", 12)
	character_status_label.add_theme_color_override("font_color", Color(0.82, 0.87, 0.90, 0.95))
	root.add_child(character_status_label)

	add_child(character_panel)
	update_character_menu(true)

func create_dev_tabs(root: VBoxContainer):
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	root.add_child(tabs)

	for tab in DEV_TABS:
		var button = Button.new()
		button.text = tab
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(Callable(self, "select_dev_tab").bind(tab))
		tabs.add_child(button)
		dev_tab_buttons[tab] = button
	update_dev_tab_buttons()

func create_dev_actions(root: VBoxContainer):
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	root.add_child(actions)

	actions.add_child(make_dev_action_button("Texture Stand", "toggle_texture_debug_stand"))
	actions.add_child(make_dev_action_button("Character", "toggle_character_menu"))
	actions.add_child(make_dev_action_button("Copy Snapshot", "copy_dev_snapshot"))
	actions.add_child(make_dev_action_button("Open Perf Log", "open_perf_log"))
	actions.add_child(make_dev_action_button("Clear Log", "clear_dev_log"))

func make_dev_action_button(label: String, method: String) -> Button:
	var button = Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(Callable(self, method))
	return button

func update_ui():
	var selected_slot = get_authoritative_inventory_selected_slot()
	var selected_inventory_block = get_authoritative_inventory_selected_block()
	if selected_inventory_block > 0:
		selected_block = selected_inventory_block
	if tool_label:
		tool_label.text = get_authoritative_tool_text()

	for i in range(labels.size()):
		var panel = labels[i]
		if i < hotbar_labels.size():
			hotbar_labels[i].text = get_hotbar_slot_text(i)

		var slot_selected = false
		if selected_slot >= 0:
			slot_selected = i == selected_slot
		else:
			slot_selected = i + 1 == selected_block

		if slot_selected:
			panel.modulate = Color(1, 1, 0)
		else:
			panel.modulate = Color(1, 1, 1)

func update_fps_counter():
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()

func update_dev_menu():
	if not dev_panel.visible:
		return

	var window_size = get_window().size
	var viewport_size = get_viewport().get_visible_rect().size
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / max(float(fps), 1.0)

	dev_info_label.text = "\n".join(dev_tab_lines(fps, frame_ms, window_size, viewport_size))
	dev_log_label.text = "\n".join(dev_logs)

func update_character_menu(force_rebuild: bool = false):
	if not character_panel.visible and not force_rebuild:
		return

	var player = get_character_player()
	if not player:
		character_status_label.text = "Player: not spawned"
		character_animation_option.disabled = true
		character_preview_toggle.disabled = true
		character_third_person_toggle.disabled = true
		return

	character_animation_option.disabled = false
	character_preview_toggle.disabled = false
	character_third_person_toggle.disabled = false

	var appearance_count = get_player_int(player, "character_appearance_preset_count", 0)
	if force_rebuild or appearance_count != character_known_appearance_count:
		rebuild_character_appearance_buttons(player, appearance_count)
		character_known_appearance_count = appearance_count

	var animation_count = get_player_int(player, "character_animation_clip_count", 0)
	if force_rebuild or animation_count != character_known_animation_count:
		rebuild_character_animation_options(player, animation_count)
		character_known_animation_count = animation_count

	var selected_appearance = get_player_int(player, "character_appearance_preset_index", -1)
	for i in range(character_appearance_buttons.size()):
		character_appearance_buttons[i].button_pressed = i == selected_appearance

	var selected_clip = get_player_int(player, "selected_character_animation_clip_index", -1)
	if selected_clip >= 0 and selected_clip < character_animation_option.get_item_count():
		if character_animation_option.selected != selected_clip:
			character_animation_option.select(selected_clip)

	var third_person_enabled = false
	if player.has_method("is_third_person_camera_enabled"):
		third_person_enabled = bool(player.is_third_person_camera_enabled())
	if character_third_person_toggle.button_pressed != third_person_enabled:
		character_third_person_toggle.button_pressed = third_person_enabled

	var preview_enabled = false
	if player.has_method("is_character_animation_preview_enabled"):
		preview_enabled = bool(player.is_character_animation_preview_enabled())
	if character_preview_toggle.button_pressed != preview_enabled:
		character_preview_toggle.button_pressed = preview_enabled

	var clip_name = get_player_text(player, "selected_character_animation_clip_name", "n/a")
	var clip_duration = get_player_float(player, "selected_character_animation_clip_duration", 0.0)
	character_status_label.text = "Appearance: %s\nAnimation: %s (%.2fs)\nClips: %d" % [
		get_player_text(player, "character_appearance_label", "n/a"),
		clip_name,
		clip_duration,
		animation_count
	]

func rebuild_character_appearance_buttons(player: Node, appearance_count: int):
	for child in character_appearance_row.get_children():
		character_appearance_row.remove_child(child)
		child.queue_free()
	character_appearance_buttons.clear()

	for index in range(appearance_count):
		var button = Button.new()
		button.text = get_player_text_arg(player, "character_appearance_preset_label", index, "Preset %d" % [index + 1])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(92, 32)
		button.pressed.connect(Callable(self, "select_character_appearance_preset").bind(index))
		character_appearance_row.add_child(button)
		character_appearance_buttons.append(button)

func rebuild_character_animation_options(player: Node, animation_count: int):
	character_animation_option.clear()
	for index in range(animation_count):
		var clip_name = get_player_text_arg(player, "character_animation_clip_name", index, "Clip %d" % [index + 1])
		var duration = 0.0
		if player.has_method("character_animation_clip_duration"):
			duration = float(player.character_animation_clip_duration(index))
		character_animation_option.add_item("%02d  %s  %.2fs" % [index + 1, clip_name, duration], index)

func toggle_dev_menu():
	dev_panel.visible = not dev_panel.visible
	if dev_panel.visible:
		mouse_mode_before_dev_menu = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(mouse_mode_before_dev_menu)
	add_log("Dev menu %s" % ("opened" if dev_panel.visible else "closed"))
	update_dev_menu()

func toggle_character_menu():
	character_panel.visible = not character_panel.visible
	if character_panel.visible:
		mouse_mode_before_character_menu = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		var player = get_character_player()
		if player and player.has_method("set_third_person_camera_enabled"):
			player.set_third_person_camera_enabled(true)
	else:
		Input.set_mouse_mode(mouse_mode_before_character_menu)
	add_log("Character menu %s" % ("opened" if character_panel.visible else "closed"))
	update_character_menu(true)

func select_character_appearance_preset(index: int):
	var player = get_character_player()
	if player and player.has_method("select_character_appearance_preset"):
		player.select_character_appearance_preset(index)
		add_log("Character appearance: %s" % get_player_text(player, "character_appearance_label", "n/a"))
	update_character_menu(true)

func select_character_animation_clip(index: int):
	var player = get_character_player()
	if player and player.has_method("select_character_animation_clip"):
		player.select_character_animation_clip(index)
		add_log("Character animation: %s" % get_player_text(player, "selected_character_animation_clip_name", "n/a"))
	update_character_menu(true)

func set_character_animation_preview(enabled: bool):
	var player = get_character_player()
	if player and player.has_method("set_character_animation_preview_enabled"):
		player.set_character_animation_preview_enabled(enabled)
	update_character_menu(true)

func set_character_third_person(enabled: bool):
	var player = get_character_player()
	if player and player.has_method("set_third_person_camera_enabled"):
		player.set_third_person_camera_enabled(enabled)
	update_character_menu(true)

func select_dev_tab(tab: String):
	selected_dev_tab = tab
	update_dev_tab_buttons()
	update_dev_menu()

func update_dev_tab_buttons():
	for tab in dev_tab_buttons.keys():
		dev_tab_buttons[tab].button_pressed = tab == selected_dev_tab

func dev_tab_lines(fps: int, frame_ms: float, window_size: Vector2i, viewport_size: Vector2) -> Array[String]:
	match selected_dev_tab:
		"Streaming":
			return [
				"Current chunk: %s" % get_client_text("get_current_chunk_text", "n/a"),
				"Chunks: %s" % get_chunk_debug_text(),
				"Loaded chunks: %s" % get_client_text("get_loaded_chunk_count", "n/a"),
				"Rendered submeshes: %s" % get_client_text("get_rendered_chunk_count", "n/a"),
				"Collision bodies: %s" % get_client_text("get_chunk_collision_count", "n/a"),
				"Last chunk event: %s" % get_client_text("get_last_chunk_event_text", "n/a"),
				"Player: %s" % get_player_position_text(),
			]
		"Render":
			return [
				"FPS: %d (%.2f ms)" % [fps, frame_ms],
				"Window: %dx%d" % [window_size.x, window_size.y],
				"Viewport: %dx%d" % [int(viewport_size.x), int(viewport_size.y)],
				"Texture stand: %s" % get_texture_debug_stand_text(),
				"GPU/render overlay:",
				get_debug_overlay_text(),
				"Perf:",
				get_client_text("get_perf_text", "n/a"),
			]
		"Events":
			return [
				"Last chunk event: %s" % get_client_text("get_last_chunk_event_text", "n/a"),
				"Last block action: %s" % get_client_text("get_last_block_action_text", "n/a"),
				"Last save: %s" % get_client_text("get_last_save_text", "n/a"),
				"Selected: %d %s" % [selected_block, get_block_name(selected_block)],
				"Tool: %s" % get_authoritative_tool_text().replace("\n", " "),
				"Inventory: %s" % get_authoritative_inventory_text(),
				"Fly: %s" % get_player_fly_text(),
				"Mouse: %s" % get_mouse_mode_text(),
			]
		"Logs":
			return [
				"Perf log: %s" % perf_log_path,
				"Run id: %s" % perf_run_id,
				"Samples every %.1fs, rotate above %.1f MB" % [PERF_LOG_INTERVAL, float(PERF_LOG_MAX_BYTES) / (1024.0 * 1024.0)],
				"Use Copy Snapshot to capture the current HUD state.",
			]
		_:
			return [
				"FPS: %d (%.2f ms)" % [fps, frame_ms],
				"State: %s" % get_lifecycle_state_text(),
				"Current chunk: %s" % get_client_text("get_current_chunk_text", "n/a"),
				"Chunks: %s" % get_chunk_debug_text(),
				"Player: %s" % get_player_position_text(),
				"Fly: %s" % get_player_fly_text(),
				"Texture stand: %s" % get_texture_debug_stand_text(),
				"Selected: %d %s" % [selected_block, get_block_name(selected_block)],
				"Tool: %s" % get_authoritative_tool_text().replace("\n", " "),
				"Inventory: %s" % get_authoritative_inventory_text(),
			]

func add_log(message: String):
	var seconds = Time.get_ticks_msec() / 1000.0
	dev_logs.append("[%06.2f] %s" % [seconds, message])
	while dev_logs.size() > MAX_LOG_LINES:
		dev_logs.pop_front()
	if dev_log_label:
		dev_log_label.text = "\n".join(dev_logs)

func clear_dev_log():
	dev_logs.clear()
	add_log("Dev log cleared")

func copy_dev_snapshot():
	DisplayServer.clipboard_set(get_dev_snapshot_text())
	add_log("Dev snapshot copied")

func open_perf_log():
	if perf_log_path.is_empty():
		add_log("Perf log path unavailable")
		return
	OS.shell_open(perf_log_path)
	add_log("Opening perf log")

func toggle_texture_debug_stand():
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("toggle_texture_debug_stand"):
		client.toggle_texture_debug_stand()
	else:
		add_log("Texture debug stand unavailable")

func get_character_player():
	return get_tree().root.find_child("Player", true, false)

func get_player_int(player: Node, method: String, fallback: int) -> int:
	if player and player.has_method(method):
		return int(player.call(method))
	return fallback

func get_player_float(player: Node, method: String, fallback: float) -> float:
	if player and player.has_method(method):
		return float(player.call(method))
	return fallback

func get_player_text(player: Node, method: String, fallback: String) -> String:
	if player and player.has_method(method):
		return str(player.call(method))
	return fallback

func get_player_text_arg(player: Node, method: String, index: int, fallback: String) -> String:
	if player and player.has_method(method):
		return str(player.call(method, index))
	return fallback

func get_player_position_text() -> String:
	var player = get_tree().root.find_child("Player", true, false)
	if player and player is Node3D:
		var pos = player.global_position
		return "%.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z]
	return "not spawned"

func get_player_fly_text() -> String:
	var player = get_tree().root.find_child("Player", true, false)
	if player and player.has_method("is_fly_mode_enabled"):
		return "on" if player.is_fly_mode_enabled() else "off"
	return "n/a"

func get_texture_debug_stand_text() -> String:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("is_texture_debug_stand_visible"):
		return "shown" if client.is_texture_debug_stand_visible() else "hidden"
	return "n/a"

func get_chunk_debug_text() -> String:
	var client = get_tree().root.find_child("GameClient", true, false)
	if not client:
		return "n/a"

	if client.has_method("get_loaded_chunk_count") and client.has_method("get_rendered_chunk_count") and client.has_method("get_chunk_collision_count"):
		return "%d loaded, %d submeshes, %d collision" % [
			client.get_loaded_chunk_count(),
			client.get_rendered_chunk_count(),
			client.get_chunk_collision_count()
		]

	var chunks := 0
	var collision_bodies := 0
	for child in client.get_children():
		if child is MeshInstance3D and child.name.begins_with("SubchunkMesh_"):
			chunks += 1
			for grandchild in child.get_children():
				if grandchild is StaticBody3D:
					collision_bodies += 1
	return "%d submeshes, %d collision" % [chunks, collision_bodies]

func get_client_text(method: String, fallback: String) -> String:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method(method):
		return str(client.call(method))
	return fallback

func get_authoritative_inventory_selected_slot() -> int:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("get_authoritative_inventory_selected_slot"):
		return int(client.get_authoritative_inventory_selected_slot())
	return -1

func get_authoritative_inventory_selected_block() -> int:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("get_authoritative_inventory_selected_block"):
		return int(client.get_authoritative_inventory_selected_block())
	return 0

func get_authoritative_inventory_text() -> String:
	return get_client_text("get_authoritative_inventory_text", "selected=none slots=")

func get_authoritative_tool_selected_slot() -> int:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("get_authoritative_tool_selected_slot"):
		return int(client.get_authoritative_tool_selected_slot())
	return -1

func get_authoritative_tool_text() -> String:
	return get_client_text("get_authoritative_tool_text", "Tool 1\nHand")

func get_hotbar_slot_text(slot_index: int) -> String:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("get_authoritative_inventory_slot_text"):
		var text = str(client.get_authoritative_inventory_slot_text(slot_index))
		if not text.is_empty():
			return text

	var block_id = slot_index + 1
	return "%d\n%s" % [slot_index + 1, get_block_name(block_id)]

func get_lifecycle_state_text() -> String:
	var overlay = get_debug_overlay_text()
	for line in overlay.split("\n"):
		if line.begins_with("State: "):
			return line.substr("State: ".length())
	return "n/a"

func get_dev_snapshot_text() -> String:
	var window_size = get_window().size
	var viewport_size = get_viewport().get_visible_rect().size
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / max(float(fps), 1.0)
	var lines: Array[String] = [
		"RUMPELMC dev snapshot",
		"tab=%s run_id=%s" % [selected_dev_tab, perf_run_id],
	]
	lines.append_array(dev_tab_lines(fps, frame_ms, window_size, viewport_size))
	lines.append("Recent log:")
	lines.append_array(dev_logs)
	return "\n".join(lines)

func get_debug_overlay_text() -> String:
	var overlay = get_client_text("get_debug_overlay_text", "")
	if not overlay.is_empty():
		return overlay

	return "\n".join([
		"Streaming: chunks=%s current=%s" % [
			get_chunk_debug_text(),
			get_client_text("get_current_chunk_text", "n/a")
		],
		"Perf: %s" % get_client_text("get_perf_text", "n/a"),
		"Events: chunk=%s block=%s save=%s" % [
			get_client_text("get_last_chunk_event_text", "n/a"),
			get_client_text("get_last_block_action_text", "n/a"),
			get_client_text("get_last_save_text", "n/a")
		]
	])

func get_block_name(block_id: int) -> String:
	var client = get_tree().root.find_child("GameClient", true, false)
	if client and client.has_method("get_block_name"):
		return str(client.get_block_name(block_id))
	return block_names.get(block_id, "Unknown")

func get_mouse_mode_text() -> String:
	match Input.get_mouse_mode():
		Input.MOUSE_MODE_VISIBLE:
			return "visible"
		Input.MOUSE_MODE_HIDDEN:
			return "hidden"
		Input.MOUSE_MODE_CAPTURED:
			return "captured"
		Input.MOUSE_MODE_CONFINED:
			return "confined"
		Input.MOUSE_MODE_CONFINED_HIDDEN:
			return "confined hidden"
		_:
			return str(Input.get_mouse_mode())

func make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func get_selected_block() -> int:
	return selected_block

func setup_perf_log():
	perf_log_path = ProjectSettings.globalize_path(PERF_LOG_PATH)
	perf_run_id = observability_run_id()
	var dir_path = perf_log_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	if not FileAccess.file_exists(perf_log_path):
		var file = FileAccess.open(perf_log_path, FileAccess.WRITE)
		if file:
			file.store_line("# RUMPELMC perf log started at %.2f run_id=%s" % [
				Time.get_ticks_msec() / 1000.0,
				perf_run_id
			])
		return

	var size = FileAccess.get_file_as_bytes(perf_log_path).size()
	if size > PERF_LOG_MAX_BYTES:
		var file = FileAccess.open(perf_log_path, FileAccess.WRITE)
		if file:
			file.store_line("# RUMPELMC perf log rotated at %.2f run_id=%s" % [
				Time.get_ticks_msec() / 1000.0,
				perf_run_id
			])

func write_perf_log_sample():
	if perf_log_path.is_empty():
		return

	var client = get_tree().root.find_child("GameClient", true, false)
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / max(float(fps), 1.0)
	var line = "run_id=%s t=%.2f fps=%d frame_ms=%.2f chunks=\"%s\" overlay=\"%s\" perf=\"%s\" current_chunk=\"%s\" player=\"%s\"" % [
		perf_run_id,
		Time.get_ticks_msec() / 1000.0,
		fps,
		frame_ms,
		get_chunk_debug_text(),
		get_debug_overlay_text().replace("\n", " | "),
		get_client_text("get_perf_text", "n/a"),
		get_client_text("get_current_chunk_text", "n/a"),
		get_player_position_text()
	]
	if client:
		line += " chunk_event=\"%s\" block_action=\"%s\" save=\"%s\"" % [
			get_client_text("get_last_chunk_event_text", "n/a"),
			get_client_text("get_last_block_action_text", "n/a"),
			get_client_text("get_last_save_text", "n/a")
		]

	var file = FileAccess.open(perf_log_path, FileAccess.READ_WRITE)
	if not file:
		return
	file.seek_end()
	file.store_line(line)

func observability_run_id() -> String:
	var env_run_id = OS.get_environment(RUN_ID_ENV).strip_edges()
	if not env_run_id.is_empty():
		return sanitize_observability_token(env_run_id)
	return "godot-%d" % int(Time.get_unix_time_from_system())

func sanitize_observability_token(value: String) -> String:
	var sanitized = value
	for token in [" ", "\t", "\n", "\r", "\"", "'", "\\"]:
		sanitized = sanitized.replace(token, "_")
	return sanitized
