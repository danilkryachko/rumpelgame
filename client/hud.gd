extends CanvasLayer

const MAX_LOG_LINES = 12
const DEV_UPDATE_INTERVAL = 0.15
const PERF_LOG_INTERVAL = 1.0
const PERF_LOG_MAX_BYTES = 2 * 1024 * 1024
const PERF_LOG_PATH = "res://../logs/perf.log"
const RUN_ID_ENV = "RUMPELMC_RUN_ID"
const DEV_TABS = ["Summary", "Streaming", "Render", "Events", "Logs"]
const CHARACTER_MENU_UPDATE_INTERVAL = 0.2
const CHARACTER_PREVIEW_VIEWPORT_SIZE = Vector2i(720, 880)
const CHARACTER_OPTION_TILE_SIZE = Vector2(138, 122)
const CHARACTER_OPTION_THUMB_SIZE = Vector2(92, 76)
const CHARACTER_PREVIEW_ROTATE_SPEED = 0.35
const CHARACTER_PREVIEW_BASE_YAW_DEGREES = 180.0

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
var character_category_grid: GridContainer
var character_category_buttons = []
var character_option_scroll: ScrollContainer
var character_option_grid: GridContainer
var character_option_buttons = []
var character_selected_category: int = 0
var character_selected_category_label: Label
var character_animation_option: OptionButton
var character_preview_toggle: CheckBox
var character_third_person_toggle: CheckBox
var character_status_label: Label
var character_preview_viewport: SubViewport
var character_preview_scene_root: Node3D
var character_preview_model: Node3D
var character_preview_signature: String = ""
var character_preview_yaw_degrees: float = 0.0
var character_preview_dragging: bool = false
var character_thumbnail_cache = {}
var character_update_timer: float = 0.0
var character_known_category_count: int = -1
var character_known_option_signature: String = ""
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
	hbox.set_offset(SIDE_TOP, -86)
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
	if character_panel and character_panel.visible:
		update_character_preview_model(false)

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
	if character_preview_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		character_preview_dragging = false

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
	character_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	character_panel.offset_left = 0
	character_panel.offset_top = 0
	character_panel.offset_right = 0
	character_panel.offset_bottom = 0
	character_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	character_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.012, 0.014, 0.017, 0.94), 0))

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	character_panel.add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var title = Label.new()
	title.text = "Character"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.98))
	header.add_child(title)

	var header_spacer = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var close_button = Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(92, 40)
	close_button.pressed.connect(Callable(self, "toggle_character_menu"))
	header.add_child(close_button)

	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(470, 0)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.055, 0.062, 0.068, 0.96), 6))
	body.add_child(preview_panel)

	var preview_root = VBoxContainer.new()
	preview_root.add_theme_constant_override("separation", 10)
	preview_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(preview_root)

	var preview_title = Label.new()
	preview_title.text = "Preview"
	preview_title.add_theme_font_size_override("font_size", 16)
	preview_title.add_theme_color_override("font_color", Color(0.84, 0.89, 0.92, 0.96))
	preview_root.add_child(preview_title)

	var preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(430, 540)
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_container.gui_input.connect(Callable(self, "handle_character_preview_input"))
	preview_root.add_child(preview_container)

	character_preview_viewport = SubViewport.new()
	character_preview_viewport.size = CHARACTER_PREVIEW_VIEWPORT_SIZE
	character_preview_viewport.own_world_3d = true
	character_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(character_preview_viewport)
	create_character_preview_scene()

	var editor_panel = PanelContainer.new()
	editor_panel.custom_minimum_size = Vector2(620, 0)
	editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.026, 0.029, 0.034, 0.98), 6))
	body.add_child(editor_panel)

	var editor_root = VBoxContainer.new()
	editor_root.add_theme_constant_override("separation", 10)
	editor_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_panel.add_child(editor_root)

	var camera_row = HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 10)
	editor_root.add_child(camera_row)

	character_third_person_toggle = CheckBox.new()
	character_third_person_toggle.text = "Third person"
	character_third_person_toggle.focus_mode = Control.FOCUS_NONE
	character_third_person_toggle.toggled.connect(Callable(self, "set_character_third_person"))
	camera_row.add_child(character_third_person_toggle)

	character_preview_toggle = CheckBox.new()
	character_preview_toggle.text = "Animate"
	character_preview_toggle.focus_mode = Control.FOCUS_NONE
	character_preview_toggle.toggled.connect(Callable(self, "set_character_animation_preview"))
	camera_row.add_child(character_preview_toggle)

	var appearance_title = Label.new()
	appearance_title.text = "APPEARANCE"
	appearance_title.add_theme_font_size_override("font_size", 12)
	appearance_title.add_theme_color_override("font_color", Color(0.66, 0.78, 0.88, 0.94))
	editor_root.add_child(appearance_title)

	character_category_grid = GridContainer.new()
	character_category_grid.columns = 5
	character_category_grid.add_theme_constant_override("h_separation", 7)
	character_category_grid.add_theme_constant_override("v_separation", 7)
	editor_root.add_child(character_category_grid)

	character_selected_category_label = Label.new()
	character_selected_category_label.text = ""
	character_selected_category_label.add_theme_font_size_override("font_size", 18)
	character_selected_category_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.98))
	editor_root.add_child(character_selected_category_label)

	character_option_scroll = ScrollContainer.new()
	character_option_scroll.custom_minimum_size = Vector2(0, 280)
	character_option_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_root.add_child(character_option_scroll)

	character_option_grid = GridContainer.new()
	character_option_grid.columns = 4
	character_option_grid.add_theme_constant_override("h_separation", 10)
	character_option_grid.add_theme_constant_override("v_separation", 10)
	character_option_scroll.add_child(character_option_grid)

	var animation_title = Label.new()
	animation_title.text = "ANIMATION"
	animation_title.add_theme_font_size_override("font_size", 12)
	animation_title.add_theme_color_override("font_color", Color(0.66, 0.78, 0.88, 0.94))
	editor_root.add_child(animation_title)

	character_animation_option = OptionButton.new()
	character_animation_option.custom_minimum_size = Vector2(0, 38)
	character_animation_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_animation_option.focus_mode = Control.FOCUS_NONE
	character_animation_option.item_selected.connect(Callable(self, "select_character_animation_clip"))
	editor_root.add_child(character_animation_option)

	character_status_label = Label.new()
	character_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_status_label.add_theme_font_size_override("font_size", 12)
	character_status_label.add_theme_color_override("font_color", Color(0.82, 0.87, 0.90, 0.95))
	editor_root.add_child(character_status_label)

	add_child(character_panel)
	update_character_menu(true)

func create_character_preview_scene():
	if not character_preview_viewport:
		return

	character_preview_scene_root = Node3D.new()
	character_preview_scene_root.name = "CharacterPreviewScene"
	character_preview_viewport.add_child(character_preview_scene_root)

	var world_environment = WorldEnvironment.new()
	world_environment.name = "CharacterPreviewEnvironment"
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.10, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.30, 0.32)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	world_environment.environment = environment
	character_preview_viewport.add_child(world_environment)

	var camera = Camera3D.new()
	camera.name = "CharacterPreviewCamera"
	camera.look_at_from_position(Vector3(0.0, 1.15, 4.25), Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true
	character_preview_viewport.add_child(camera)

	var key_light = DirectionalLight3D.new()
	key_light.name = "CharacterPreviewKeyLight"
	key_light.rotation_degrees = Vector3(-45.0, -28.0, 0.0)
	character_preview_viewport.add_child(key_light)

	var floor_mesh = PlaneMesh.new()
	floor_mesh.size = Vector2(2.8, 2.8)

	var floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.14, 0.15, 1.0)
	floor_material.roughness = 0.9

	var floor = MeshInstance3D.new()
	floor.name = "CharacterPreviewFloor"
	floor.position = Vector3(0.0, -0.01, 0.0)
	floor.mesh = floor_mesh
	floor.material_override = floor_material
	character_preview_scene_root.add_child(floor)

func update_character_preview_model(force_rebuild: bool):
	if not character_preview_scene_root:
		return

	var player = get_character_player()
	var source = null
	var source_id = 0
	if player:
		source = player.find_child("PlayerVoxelCharacter", true, false)
		if source:
			source_id = source.get_instance_id()

	var signature = "%s:%d" % [
		get_player_text(player, "character_appearance_label", "n/a"),
		source_id
	]
	if not force_rebuild and signature == character_preview_signature:
		return
	character_preview_signature = signature

	if character_preview_model and is_instance_valid(character_preview_model):
		character_preview_model.queue_free()
		character_preview_model = null

	if not source:
		return

	var clone = source.duplicate()
	if clone is Node3D:
		character_preview_model = clone
		character_preview_model.name = "CharacterPreviewModel"
		character_preview_model.visible = true
		character_preview_model.position = Vector3.ZERO
		character_preview_model.scale = Vector3.ONE
		apply_character_preview_rotation()
		force_node3d_tree_visible(character_preview_model)
		character_preview_scene_root.add_child(character_preview_model)

func handle_character_preview_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		character_preview_dragging = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and character_preview_dragging:
		character_preview_yaw_degrees = wrapf(
			character_preview_yaw_degrees + event.relative.x * CHARACTER_PREVIEW_ROTATE_SPEED,
			-180.0,
			180.0
		)
		apply_character_preview_rotation()
		get_viewport().set_input_as_handled()

func apply_character_preview_rotation():
	if character_preview_model and is_instance_valid(character_preview_model):
		character_preview_model.rotation_degrees = Vector3(
			0.0,
			CHARACTER_PREVIEW_BASE_YAW_DEGREES + character_preview_yaw_degrees,
			0.0
		)

func force_node3d_tree_visible(node: Node):
	if node is Node3D:
		node.visible = true
	for child in node.get_children():
		force_node3d_tree_visible(child)

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

	var category_count = get_player_int(player, "character_creator_category_count", 0)
	if character_selected_category >= category_count:
		character_selected_category = 0
	if force_rebuild or category_count != character_known_category_count:
		rebuild_character_creator_categories(player, category_count)
		character_known_category_count = category_count
	if character_selected_category_label:
		character_selected_category_label.text = get_player_text_arg(player, "character_creator_category_label", character_selected_category, "")

	var option_count = 0
	if player.has_method("character_creator_option_count"):
		option_count = int(player.character_creator_option_count(character_selected_category))
	var option_signature = "%d:%d" % [character_selected_category, option_count]
	if force_rebuild or option_signature != character_known_option_signature:
		rebuild_character_creator_options(player, character_selected_category, option_count)
		character_known_option_signature = option_signature

	var animation_count = get_player_int(player, "character_animation_clip_count", 0)
	if force_rebuild or animation_count != character_known_animation_count:
		rebuild_character_animation_options(player, animation_count)
		character_known_animation_count = animation_count

	for i in range(character_category_buttons.size()):
		character_category_buttons[i].button_pressed = i == character_selected_category

	var selected_option = get_player_int_arg(player, "character_creator_selected_option_index", character_selected_category, -1)
	for i in range(character_option_buttons.size()):
		character_option_buttons[i].button_pressed = i == selected_option

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
	var sample_tracks = get_player_int(player, "selected_character_animation_sample_track_count", 0)
	character_status_label.text = "Appearance: %s\nAnimation: %s (%.2fs, %d tracks)\nClips: %d" % [
		get_player_text(player, "character_appearance_label", "n/a"),
		clip_name,
		clip_duration,
		sample_tracks,
		animation_count
	]
	update_character_preview_model(force_rebuild)

func rebuild_character_creator_categories(player: Node, category_count: int):
	for child in character_category_grid.get_children():
		character_category_grid.remove_child(child)
		child.queue_free()
	character_category_buttons.clear()

	for index in range(category_count):
		var button = Button.new()
		button.text = get_player_text_arg(player, "character_creator_category_label", index, "Tab %d" % [index + 1])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(112, 34)
		button.add_theme_stylebox_override("normal", make_tab_button_style(false, false))
		button.add_theme_stylebox_override("hover", make_tab_button_style(false, true))
		button.add_theme_stylebox_override("pressed", make_tab_button_style(true, false))
		button.pressed.connect(Callable(self, "select_character_creator_category").bind(index))
		character_category_grid.add_child(button)
		character_category_buttons.append(button)

func rebuild_character_creator_options(player: Node, category_index: int, option_count: int):
	for child in character_option_grid.get_children():
		character_option_grid.remove_child(child)
		child.queue_free()
	character_option_buttons.clear()

	for index in range(option_count):
		var label = get_player_text_arg2(player, "character_creator_option_label", category_index, index, "Option %d" % [index + 1])
		var color = get_player_color_arg2(player, "character_creator_option_color", category_index, index, Color(0, 0, 0, 0))
		var thumbnail_path = get_player_text_arg2(player, "character_creator_option_thumbnail_path", category_index, index, "")
		var button = make_character_option_button(label, color, thumbnail_path)
		button.pressed.connect(Callable(self, "select_character_creator_option").bind(category_index, index))
		character_option_grid.add_child(button)
		character_option_buttons.append(button)

func make_character_option_button(label: String, color: Color, thumbnail_path: String) -> Button:
	var button = Button.new()
	button.text = ""
	button.tooltip_text = label
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = CHARACTER_OPTION_TILE_SIZE
	button.add_theme_stylebox_override("normal", make_tile_button_style(false, false))
	button.add_theme_stylebox_override("hover", make_tile_button_style(false, true))
	button.add_theme_stylebox_override("pressed", make_tile_button_style(true, false))

	var tile = VBoxContainer.new()
	tile.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile.offset_left = 8
	tile.offset_top = 8
	tile.offset_right = -8
	tile.offset_bottom = -8
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 6)
	button.add_child(tile)

	var visual = CenterContainer.new()
	visual.custom_minimum_size = CHARACTER_OPTION_THUMB_SIZE
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(visual)

	if color.a > 0.0:
		var swatch = ColorRect.new()
		swatch.custom_minimum_size = Vector2(82, 58)
		swatch.color = color
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(swatch)
	else:
		var texture = load_character_thumbnail(thumbnail_path)
		if texture:
			var thumbnail = TextureRect.new()
			thumbnail.custom_minimum_size = CHARACTER_OPTION_THUMB_SIZE
			thumbnail.texture = texture
			thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual.add_child(thumbnail)
		else:
			var empty_label = Label.new()
			empty_label.text = "None"
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_label.add_theme_font_size_override("font_size", 15)
			empty_label.add_theme_color_override("font_color", Color(0.76, 0.80, 0.84, 0.86))
			empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual.add_child(empty_label)

	var text_label = Label.new()
	text_label.text = label
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.clip_text = true
	text_label.custom_minimum_size = Vector2(0, 30)
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", Color(0.90, 0.93, 0.95, 0.96))
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(text_label)

	return button

func load_character_thumbnail(path: String):
	if path.is_empty():
		return null
	if character_thumbnail_cache.has(path):
		return character_thumbnail_cache[path]

	var image = Image.new()
	var err = image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		err = image.load(path)
	if err != OK:
		return null

	var texture = ImageTexture.create_from_image(image)
	character_thumbnail_cache[path] = texture
	return texture

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
		if not character_panel.visible:
			Input.set_mouse_mode(mouse_mode_before_dev_menu)
	sync_gameplay_input_blocked()
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
		character_preview_signature = ""
		character_preview_yaw_degrees = 0.0
		character_preview_dragging = false
	else:
		if not dev_panel.visible:
			Input.set_mouse_mode(mouse_mode_before_character_menu)
		character_preview_dragging = false
	sync_gameplay_input_blocked()
	add_log("Character menu %s" % ("opened" if character_panel.visible else "closed"))
	update_character_menu(true)

func sync_gameplay_input_blocked():
	var blocked = false
	if dev_panel and dev_panel.visible:
		blocked = true
	if character_panel and character_panel.visible:
		blocked = true
	var player = get_character_player()
	if player and player.has_method("set_gameplay_input_blocked"):
		player.set_gameplay_input_blocked(blocked)

func select_character_creator_category(index: int):
	character_selected_category = index
	character_known_option_signature = ""
	update_character_menu(true)

func select_character_creator_option(category_index: int, option_index: int):
	var player = get_character_player()
	if player and player.has_method("select_character_creator_option"):
		player.select_character_creator_option(category_index, option_index)
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

func get_player_int_arg(player: Node, method: String, arg: int, fallback: int) -> int:
	if player and player.has_method(method):
		return int(player.call(method, arg))
	return fallback

func get_player_text_arg2(player: Node, method: String, first: int, second: int, fallback: String) -> String:
	if player and player.has_method(method):
		return str(player.call(method, first, second))
	return fallback

func get_player_color_arg2(player: Node, method: String, first: int, second: int, fallback: Color) -> Color:
	if player and player.has_method(method):
		var value = player.call(method, first, second)
		if typeof(value) == TYPE_COLOR:
			return value
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

func make_swatch_style(color: Color, selected: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.95) if selected else Color(0, 0, 0, 0.45)
	return style

func make_tab_button_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.16, 0.19, 0.96) if selected else Color(0.07, 0.08, 0.10, 0.92)
	if hovered and not selected:
		style.bg_color = Color(0.10, 0.12, 0.14, 0.96)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.82, 0.88, 0.92, 0.86) if selected else Color(0.22, 0.26, 0.30, 0.82)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func make_tile_button_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.16, 0.98) if selected else Color(0.055, 0.062, 0.070, 0.95)
	if hovered and not selected:
		style.bg_color = Color(0.075, 0.085, 0.095, 0.98)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.92, 0.96, 1.0, 0.96) if selected else Color(0.18, 0.21, 0.24, 0.92)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
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
