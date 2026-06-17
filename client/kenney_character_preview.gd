extends Node3D

const MODEL_SCENE_PATH = "res://assets/characters/kenney_animated_characters_3/Model/characterMedium.fbx"
const DEFAULT_SKIN_PATH = "res://assets/characters/kenney_animated_characters_3/Skins/humanMaleA.png"
const ANIMATION_LIBRARY_NAME = "kenney"
const ANIMATION_SCENES = {
	"idle": "res://assets/characters/kenney_animated_characters_3/Animations/idle.fbx",
	"run": "res://assets/characters/kenney_animated_characters_3/Animations/run.fbx",
	"jump": "res://assets/characters/kenney_animated_characters_3/Animations/jump.fbx",
}

@export var skin_path: String = DEFAULT_SKIN_PATH
@export var animation_cycle: Array[String] = []
@export var cycle_interval_sec: float = 2.4

var animation_player: AnimationPlayer
var current_motion_state: String = ""
var cycle_index: int = 0
var cycle_timer_sec: float = 0.0

func _ready():
	var model_scene = ResourceLoader.load(MODEL_SCENE_PATH)
	if not model_scene is PackedScene:
		push_warning("Kenney preview model failed to load: %s" % MODEL_SCENE_PATH)
		queue_free()
		return

	var model = model_scene.instantiate()
	model.name = "Model"
	add_child(model)

	apply_skin(model)
	animation_player = create_animation_player(model)
	load_animation_clips(animation_player)
	set_motion_state("idle")

func _process(delta: float):
	if not animation_player or animation_cycle.is_empty():
		return

	cycle_timer_sec += delta
	if cycle_timer_sec < cycle_interval_sec:
		return

	cycle_timer_sec = 0.0
	play_cycle_animation(cycle_index + 1)

func create_animation_player(model: Node) -> AnimationPlayer:
	var player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	player.playback_default_blend_time = 0.12
	model.add_child(player)
	return player

func load_animation_clips(player: AnimationPlayer):
	var library = AnimationLibrary.new()
	for clip_name in ANIMATION_SCENES.keys():
		var animation = load_animation_clip(clip_name, ANIMATION_SCENES[clip_name])
		if not animation:
			continue
		animation.loop_mode = Animation.LOOP_NONE if clip_name == "jump" else Animation.LOOP_LINEAR
		library.add_animation(clip_name, animation)

	var err = player.add_animation_library(ANIMATION_LIBRARY_NAME, library)
	if err != OK:
		push_warning("Kenney preview failed to register animation library: %d" % err)

func load_animation_clip(clip_name: String, scene_path: String) -> Animation:
	var scene = ResourceLoader.load(scene_path)
	if not scene is PackedScene:
		push_warning("Kenney animation scene failed to load: %s" % scene_path)
		return null

	var root = scene.instantiate()
	var source_player = find_animation_player(root)
	if not source_player:
		push_warning("Kenney animation scene has no AnimationPlayer: %s" % scene_path)
		root.queue_free()
		return null

	var source_name = find_source_animation_name(source_player, clip_name)
	if source_name.is_empty():
		push_warning("Kenney animation clip not found: %s" % clip_name)
		root.queue_free()
		return null

	var animation = source_player.get_animation(source_name).duplicate(true)
	root.queue_free()
	return animation

func find_source_animation_name(player: AnimationPlayer, clip_name: String) -> String:
	var normalized_clip = clip_name.to_lower()
	var longest_name = ""
	var longest_length = -1.0
	for animation_name in player.get_animation_list():
		var normalized_name = animation_name.to_lower()
		if normalized_name.contains("targeting"):
			continue
		var animation = player.get_animation(animation_name)
		if normalized_name.contains(normalized_clip):
			return animation_name
		if animation.length > longest_length:
			longest_name = animation_name
			longest_length = animation.length
	return longest_name

func play_cycle_animation(next_index: int):
	for offset in range(animation_cycle.size()):
		var index = (next_index + offset) % animation_cycle.size()
		var clip_name = animation_cycle[index]
		var animation_name = "%s/%s" % [ANIMATION_LIBRARY_NAME, clip_name]
		if animation_player.has_animation(animation_name):
			cycle_index = index
			set_motion_state(clip_name)
			return

func set_motion_state(motion_state: String):
	if not animation_player:
		return

	var animation_name = "%s/%s" % [ANIMATION_LIBRARY_NAME, motion_state]
	if not animation_player.has_animation(animation_name):
		return
	if current_motion_state == motion_state and animation_player.is_playing():
		return

	current_motion_state = motion_state
	animation_player.play(animation_name)

func apply_skin(root: Node):
	var texture = ResourceLoader.load(skin_path) as Texture2D
	if not texture:
		push_warning("Kenney preview skin failed to load: %s" % skin_path)
		return

	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 0.85
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	apply_material_recursive(root, material)

func apply_material_recursive(node: Node, material: Material):
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		var mesh = mesh_instance.mesh
		if mesh:
			for surface_index in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_index, material)

	for child in node.get_children():
		apply_material_recursive(child, material)

func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = find_animation_player(child)
		if found:
			return found
	return null
