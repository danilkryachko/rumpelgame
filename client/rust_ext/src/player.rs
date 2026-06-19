use godot::classes::{
    ArrayMesh, BoxMesh, Camera3D, CharacterBody3D, ICharacterBody3D, Input, InputEvent,
    InputEventKey, InputEventMouseButton, InputEventMouseMotion, MeshInstance3D, Node3D,
    StandardMaterial3D, base_material_3d,
};
use godot::global::{Key, MouseButton};
use godot::prelude::*;

use crate::biomes_avatar::{
    BiomesAnimationCatalog, BiomesAvatarAppearance, BiomesAvatarJoint, BiomesJointRestPose,
    BiomesPlayerAnimation, BiomesSampledJointPose, BiomesSampledPose, BiomesTransform,
};

const BLOCK_REACH: f32 = 5.0;
const SELECTION_OUTLINE_PADDING: f32 = 0.01;
const GRAVITY: f32 = 24.0;
const JUMP_VELOCITY: f32 = 8.0;
const MOVE_SPEED: f32 = 5.0;
const FLY_SPEED: f32 = 12.0;
const BLOCK_PICK_SURFACE_EPSILON: f32 = 0.01;
const FLY_DISABLE_GROUND_CHECK_DISTANCE: f32 = 160.0;
const FLY_DISABLE_MIN_FLOOR_NORMAL_Y: f32 = 0.7;
const GROUND_SAFETY_RAYCAST_NAME: &str = "GroundSafetyRayCast";
const VISUAL_SMOKE_DISABLE_PLAYER_INPUT_ENV: &str = "RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT";
const PLAYER_HOTBAR_SLOTS: usize = 5;
const PLAYER_TOOL_SLOTS: usize = 4;
const CREATIVE_HOTBAR_STACK_COUNT: u32 = 999;
const PLAYER_CHARACTER_VISUAL_NAME: &str = "PlayerVoxelCharacter";
const PLAYER_HEIGHT_METERS: f32 = 1.90;
const PLAYER_EYE_HEIGHT_METERS: f32 = 1.80;
const PLAYER_COLLISION_RADIUS: f32 = 0.4;
const THIRD_PERSON_CAMERA_DISTANCE: f32 = 4.0;
const THIRD_PERSON_CAMERA_HEIGHT: f32 = PLAYER_EYE_HEIGHT_METERS + 0.4;
const THIRD_PERSON_BLOCK_REACH_PADDING: f32 = 0.5;
const CHARACTER_WALK_SPEED_THRESHOLD: f32 = 0.25;
const CHARACTER_JUMP_SPEED_THRESHOLD: f32 = 0.5;
const CHARACTER_ANIMATION_WRAP_SECONDS: f32 = 4096.0;
const CHARACTER_ACTION_FALLBACK_SECONDS: f32 = 0.45;
const CHARACTER_IDLE_ANIMATION_RATE: f32 = 2.0;
const CHARACTER_RUN_ANIMATION_RATE: f32 = 9.0;
const CHARACTER_JUMP_ANIMATION_RATE: f32 = 4.0;
const CHARACTER_ROOT_YAW_DEGREES: f32 = 0.0;
const CHARACTER_VISUAL_HEIGHT_METERS: f32 = 2.10;
const CHARACTER_VOXEL_SCALE: f32 = CHARACTER_VISUAL_HEIGHT_METERS / 56.5;
const CHARACTER_ARM_MESH_OVERLAP_SCALE: f32 = 1.35;
const CHARACTER_HAND_MESH_OVERLAP_SCALE: f32 = 1.18;
const CHARACTER_LEG_MESH_OVERLAP_SCALE: f32 = 1.18;
const CHARACTER_FOOT_MESH_OVERLAP_SCALE: f32 = 1.14;
const CHARACTER_ARM_ROOT_WELD_INSET_METERS: f32 = 0.08;
const CHARACTER_LEFT_LEG_ROOT_WELD_INSET_METERS: f32 = 0.020;
const CHARACTER_RIGHT_LEG_ROOT_WELD_INSET_METERS: f32 = 0.012;
const CHARACTER_ARM_MESH_STITCH_INSET_METERS: f32 = 0.09;
const CHARACTER_LEFT_LEG_MESH_STITCH_INSET_METERS: f32 = 0.045;
const CHARACTER_LEFT_FOOT_MESH_STITCH_INSET_METERS: f32 = 0.040;
const CHARACTER_HEAD_VOXEL_HEIGHT: f32 = 18.0;
const CHARACTER_HEAD_NECK_OVERLAP: f32 = 2.0 * CHARACTER_VOXEL_SCALE;
const CHARACTER_HEAD_Y: f32 = CHARACTER_VISUAL_HEIGHT_METERS
    - CHARACTER_HEAD_VOXEL_HEIGHT * CHARACTER_VOXEL_SCALE * 0.5
    - CHARACTER_HEAD_NECK_OVERLAP;
const CHARACTER_CHEST_Y: f32 = 29.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_BELT_Y: f32 = 19.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_SHOULDER_Y: f32 = 35.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_FOREARM_Y: f32 = 35.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_THIGH_Y: f32 = 14.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_HIP_Y: f32 = CHARACTER_THIGH_Y - 0.23;
const CHARACTER_LIMB_X: f32 = 9.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_FOREARM_X: f32 = 17.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_ARM_REST_X: f32 = 7.7 * CHARACTER_VOXEL_SCALE;
const CHARACTER_FOREARM_REST_X: f32 = 7.9 * CHARACTER_VOXEL_SCALE;
const CHARACTER_HAND_REST_X: f32 = 8.0 * CHARACTER_VOXEL_SCALE;
const CHARACTER_ARM_REST_Y: f32 = 33.8 * CHARACTER_VOXEL_SCALE;
const CHARACTER_FOREARM_REST_Y: f32 = 27.3 * CHARACTER_VOXEL_SCALE;
const CHARACTER_HAND_REST_Y: f32 = 22.2 * CHARACTER_VOXEL_SCALE;
const CHARACTER_LEFT_ARM_REST_Z_DEGREES: f32 = -86.0;
const CHARACTER_RIGHT_ARM_REST_Z_DEGREES: f32 = 86.0;
const CHARACTER_LEG_X: f32 = 4.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_LOWER_LEG_Y: f32 = 5.5 * CHARACTER_VOXEL_SCALE;
const CHARACTER_FOOT_Y: f32 = 1.5 * CHARACTER_VOXEL_SCALE;

struct BlockHit {
    block: (i32, i32, i32),
    adjacent: (i32, i32, i32),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct InventorySlot {
    block_id: crate::blocks::BlockId,
    count: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CharacterMotionState {
    Idle,
    WalkForward,
    RunForward,
    RunBackward,
    StrafeLeftSlow,
    StrafeLeftFast,
    StrafeRightSlow,
    StrafeRightFast,
    Jump,
    Fall,
    FlyIdle,
    FlyForwards,
    FlyBackwards,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CharacterClipPreviewKind {
    Idle,
    Walk,
    Run,
    Jump,
    Crouch,
    Swim,
    Wave,
    Dance,
    Applause,
    Work,
    Fishing,
    Consume,
    Sit,
    Flex,
    Laugh,
    Point,
    Camera,
    Rock,
    Sick,
    Item,
    Craft,
    Watering,
    TPose,
    Fallback,
}

struct VoxelCharacterVisual {
    root: Gd<Node3D>,
    uses_biomes_skeleton_hierarchy: bool,
    head: Gd<Node3D>,
    chest: Gd<Node3D>,
    waist: Gd<Node3D>,
    l_arm: Gd<Node3D>,
    l_forearm: Gd<Node3D>,
    hand_l: Gd<Node3D>,
    r_arm: Gd<Node3D>,
    r_forearm: Gd<Node3D>,
    hand_r: Gd<Node3D>,
    l_thigh: Gd<Node3D>,
    l_leg: Gd<Node3D>,
    foot_l: Gd<Node3D>,
    r_thigh: Gd<Node3D>,
    r_leg: Gd<Node3D>,
    foot_r: Gd<Node3D>,
}

#[derive(GodotClass)]
#[class(base=CharacterBody3D)]
pub struct Player {
    base: Base<CharacterBody3D>,
    camera: Option<Gd<Camera3D>>,
    selection_outline: Option<Gd<MeshInstance3D>>,
    character_visual: Option<VoxelCharacterVisual>,
    mouse_sensitivity: f32,
    selected_block: i32,
    selected_hotbar_slot: usize,
    selected_tool_slot: usize,
    hotbar: [InventorySlot; PLAYER_HOTBAR_SLOTS],
    fly_mode: bool,
    third_person_camera: bool,
    gameplay_input_blocked: bool,
    character_appearance: BiomesAvatarAppearance,
    character_animation_catalog: Option<BiomesAnimationCatalog>,
    character_preview_animation_index: usize,
    character_preview_animation_enabled: bool,
    character_motion_state: CharacterMotionState,
    character_action_animation: Option<BiomesPlayerAnimation>,
    character_action_animation_remaining_sec: f32,
    character_animation_time_sec: f32,
    default_collision_layer: u32,
    default_collision_mask: u32,
}

#[godot_api]
impl ICharacterBody3D for Player {
    fn init(base: Base<CharacterBody3D>) -> Self {
        let hotbar = initial_hotbar_inventory();
        let selected_hotbar_slot = first_placeable_hotbar_slot(&hotbar).unwrap_or(0);
        let selected_block = selected_block_for_hotbar_slot(&hotbar, selected_hotbar_slot)
            .unwrap_or(crate::blocks::STONE) as i32;

        Self {
            base,
            camera: None,
            selection_outline: None,
            character_visual: None,
            mouse_sensitivity: 0.002,
            selected_block,
            selected_hotbar_slot,
            selected_tool_slot: 0,
            hotbar,
            fly_mode: false,
            third_person_camera: false,
            gameplay_input_blocked: false,
            character_appearance: crate::biomes_avatar::default_avatar_appearance(),
            character_animation_catalog: None,
            character_preview_animation_index: 0,
            character_preview_animation_enabled: false,
            character_motion_state: CharacterMotionState::Idle,
            character_action_animation: None,
            character_action_animation_remaining_sec: 0.0,
            character_animation_time_sec: 0.0,
            default_collision_layer: 1,
            default_collision_mask: 1,
        }
    }

    fn ready(&mut self) {
        self.default_collision_layer = self.base().get_collision_layer();
        self.default_collision_mask = self.base().get_collision_mask();

        // Добавляем коллизию игроку
        let mut collision = godot::classes::CollisionShape3D::new_alloc();
        let mut shape = godot::classes::CapsuleShape3D::new_gd();
        shape.set_radius(PLAYER_COLLISION_RADIUS);
        shape.set_height(PLAYER_HEIGHT_METERS);
        collision.set_shape(&shape.upcast::<godot::classes::Shape3D>());
        collision.set_position(Vector3::new(0.0, PLAYER_HEIGHT_METERS * 0.5, 0.0));
        self.base_mut()
            .add_child(&collision.upcast::<godot::classes::Node>());

        // Создаем камеру
        let mut camera = Camera3D::new_alloc();
        camera.set_position(first_person_camera_position());
        camera.set_current(true);

        // Добавляем RayCast3D для разрушения блоков
        let mut raycast = godot::classes::RayCast3D::new_alloc();
        raycast.set_target_position(block_raycast_target(false));
        raycast.set_name(&StringName::from("BlockRayCast"));
        let player_collision = self
            .base()
            .clone()
            .upcast::<godot::classes::CollisionObject3D>();
        raycast.add_exception(&player_collision);
        camera.add_child(&raycast.upcast::<godot::classes::Node>());

        let mut ground_raycast = godot::classes::RayCast3D::new_alloc();
        ground_raycast.set_position(Vector3::new(0.0, 1.0, 0.0));
        ground_raycast.set_target_position(Vector3::new(
            0.0,
            -FLY_DISABLE_GROUND_CHECK_DISTANCE,
            0.0,
        ));
        ground_raycast.set_name(&StringName::from(GROUND_SAFETY_RAYCAST_NAME));
        ground_raycast.add_exception(&player_collision);
        self.base_mut()
            .add_child(&ground_raycast.upcast::<godot::classes::Node>());

        self.base_mut()
            .add_child(&camera.clone().upcast::<godot::classes::Node>());
        self.camera = Some(camera);

        let mut selection_outline = create_selection_outline();
        selection_outline.set_visible(false);
        self.base_mut()
            .add_child(&selection_outline.clone().upcast::<godot::classes::Node>());
        self.selection_outline = Some(selection_outline);

        self.load_character_animation_catalog();
        self.attach_character_visual();
        self.apply_camera_mode();

        if !visual_smoke_player_input_disabled() {
            Input::singleton().set_mouse_mode(godot::classes::input::MouseMode::CAPTURED);
        }
    }

    fn input(&mut self, event: Gd<InputEvent>) {
        if visual_smoke_player_input_disabled() {
            return;
        }

        let input = Input::singleton();
        if self.gameplay_input_blocked {
            if input.get_mouse_mode() == godot::classes::input::MouseMode::CAPTURED {
                Self::release_mouse();
            }
            return;
        }

        if let Ok(key) = event.clone().try_cast::<InputEventKey>()
            && key.is_pressed()
            && !key.is_echo()
        {
            match key.get_physical_keycode() {
                Key::ESCAPE => {
                    Self::release_mouse();
                    return;
                }
                Key::F => {
                    self.set_fly_mode(!self.fly_mode);
                    return;
                }
                Key::V => {
                    self.set_third_person_camera(!self.third_person_camera);
                    return;
                }
                _ => {}
            }
        }

        let mouse_button_event = event.clone().try_cast::<InputEventMouseButton>().ok();
        if let Some(mouse_button) = &mouse_button_event
            && mouse_button.is_pressed()
            && input.get_mouse_mode() != godot::classes::input::MouseMode::CAPTURED
        {
            Self::capture_mouse();
            return;
        }

        if input.get_mouse_mode() != godot::classes::input::MouseMode::CAPTURED {
            return;
        }

        if let Ok(motion) = event.try_cast::<InputEventMouseMotion>() {
            let relative = motion.get_relative();

            // Вращение тела по оси Y (влево/вправо)
            let rot_y = -relative.x * self.mouse_sensitivity;
            self.base_mut().rotate_y(rot_y);

            // Вращение камеры по оси X (вверх/вниз)
            if let Some(camera) = &mut self.camera {
                let mut current_rot = camera.get_rotation();
                current_rot.x -= relative.y * self.mouse_sensitivity;
                // Ограничиваем угол обзора (от -90 до 90 градусов)
                current_rot.x = current_rot.x.clamp(-1.5, 1.5);
                camera.set_rotation(current_rot);
            }
        }

        self.update_selected_block_from_hotbar(&input);
        self.update_selected_tool_from_keys(&input);

        if let Some(mouse_button) = mouse_button_event
            && mouse_button.is_pressed()
        {
            match mouse_button.get_button_index() {
                MouseButton::LEFT => {
                    if let Some(hit) = self.aimed_block_hit() {
                        let animation = if self.selected_tool_slot == 0 {
                            BiomesPlayerAnimation::DiggingHand
                        } else {
                            BiomesPlayerAnimation::DiggingTool
                        };
                        self.trigger_character_action_animation(animation);
                        let (bx, by, bz) = hit.block;
                        godot_print!("Player breaks block at: {}, {}, {}", bx, by, bz);
                        self.base_mut().emit_signal(
                            &StringName::from("block_broken"),
                            &[bx.to_variant(), by.to_variant(), bz.to_variant()],
                        );
                    }
                }
                MouseButton::RIGHT => {
                    if let Some(hit) = self.aimed_block_hit() {
                        let (bx, by, bz) = hit.adjacent;
                        if self.block_intersects_player(bx, by, bz) {
                            self.emit_debug_log("Skipped block place inside player");
                            return;
                        }
                        let block_id = self.selected_block;
                        if !inventory_has_placeable_block(&self.hotbar, block_id as u32) {
                            self.emit_debug_log(&format!("Skipped invalid block id={block_id}"));
                            return;
                        }
                        self.trigger_character_action_animation(BiomesPlayerAnimation::Place);
                        godot_print!(
                            "Player places block at: {}, {}, {} ID: {}",
                            bx,
                            by,
                            bz,
                            block_id
                        );
                        self.base_mut().emit_signal(
                            &StringName::from("block_placed"),
                            &[
                                bx.to_variant(),
                                by.to_variant(),
                                bz.to_variant(),
                                block_id.to_variant(),
                            ],
                        );
                    }
                }
                _ => {}
            }
        }
    }

    fn physics_process(&mut self, delta: f64) {
        if visual_smoke_player_input_disabled() {
            self.base_mut().set_velocity(Vector3::ZERO);
            return;
        }

        self.update_selection_outline();

        let input = Input::singleton();

        // Простое перемещение для MVP (без нормальной физики и прыжков)
        let mut dir = Vector3::ZERO;

        if input.is_physical_key_pressed(Key::W) {
            dir.z -= 1.0;
        }
        if input.is_physical_key_pressed(Key::S) {
            dir.z += 1.0;
        }
        if input.is_physical_key_pressed(Key::A) {
            dir.x -= 1.0;
        }
        if input.is_physical_key_pressed(Key::D) {
            dir.x += 1.0;
        }

        if dir != Vector3::ZERO {
            dir = dir.normalized();
        }
        let mut local_movement_input = dir;
        let sprint_requested = !self.fly_mode && input.is_physical_key_pressed(Key::SHIFT);

        let basis = self.base().get_transform().basis;

        let mut velocity = self.base().get_velocity();

        if self.fly_mode {
            if input.is_physical_key_pressed(Key::SPACE) {
                dir.y += 1.0;
            }
            if input.is_physical_key_pressed(Key::SHIFT) {
                dir.y -= 1.0;
            }
            if dir != Vector3::ZERO {
                dir = dir.normalized();
            }
            local_movement_input = dir;

            let movement = basis * dir * FLY_SPEED;
            velocity = movement;
        } else {
            let movement = basis * dir * MOVE_SPEED;
            velocity.x = movement.x;
            velocity.z = movement.z;

            if self.base().is_on_floor() {
                if input.is_physical_key_pressed(Key::SPACE) {
                    velocity.y = JUMP_VELOCITY;
                } else if velocity.y < 0.0 {
                    velocity.y = 0.0;
                }
            } else {
                velocity.y -= GRAVITY * delta as f32;
            }
        }

        self.base_mut().set_velocity(velocity);
        self.base_mut().move_and_slide();
        let velocity_after_slide = self.base().get_velocity();
        let on_floor = self.base().is_on_floor();
        self.update_character_visual(
            local_movement_input,
            sprint_requested,
            self.fly_mode,
            velocity_after_slide,
            on_floor,
            delta as f32,
        );
    }
}

impl Player {
    fn emit_debug_log(&mut self, message: &str) {
        godot_print!("{}", message);
        self.base_mut()
            .emit_signal(&StringName::from("debug_log"), &[message.to_variant()]);
    }

    fn set_fly_mode(&mut self, enabled: bool) {
        if !enabled && self.fly_mode && !self.has_safe_ground_collision_below() {
            self.emit_debug_log("Fly noclip disable blocked: no ground collision below");
            return;
        }

        self.fly_mode = enabled;
        let layer = if enabled {
            0
        } else {
            self.default_collision_layer
        };
        let mask = if enabled {
            0
        } else {
            self.default_collision_mask
        };

        self.base_mut().set_collision_layer(layer);
        self.base_mut().set_collision_mask(mask);
        self.base_mut().set_velocity(Vector3::ZERO);

        let message = if enabled {
            "Fly noclip enabled"
        } else {
            "Fly noclip disabled"
        };
        godot_print!("{}", message);
        self.base_mut()
            .emit_signal(&StringName::from("debug_log"), &[message.to_variant()]);
    }

    fn has_safe_ground_collision_below(&mut self) -> bool {
        let Some(mut raycast) = self
            .base()
            .try_get_node_as::<godot::classes::RayCast3D>(GROUND_SAFETY_RAYCAST_NAME)
        else {
            return false;
        };

        raycast.force_raycast_update();
        raycast.is_colliding() && raycast.get_collision_normal().y >= FLY_DISABLE_MIN_FLOOR_NORMAL_Y
    }

    fn capture_mouse() {
        Input::singleton().set_mouse_mode(godot::classes::input::MouseMode::CAPTURED);
    }

    fn release_mouse() {
        Input::singleton().set_mouse_mode(godot::classes::input::MouseMode::VISIBLE);
    }

    fn load_character_animation_catalog(&mut self) {
        match crate::biomes_avatar::load_biomes_animation_catalog_from_res() {
            Ok(catalog) => {
                let clip_count = catalog.clip_count();
                self.character_preview_animation_index = catalog
                    .clips()
                    .iter()
                    .position(|clip| clip.file_animation_name == "Idle")
                    .unwrap_or(0);
                self.character_animation_catalog = Some(catalog);
                self.emit_debug_log(&format!("Biomes character animation clips: {clip_count}"));
            }
            Err(err) => {
                godot_print!("Biomes character animation catalog fallback: {err}");
                self.emit_debug_log(&format!(
                    "Biomes character animation catalog unavailable: {err}"
                ));
            }
        }
    }

    fn attach_character_visual(&mut self) {
        let mut visual = create_voxel_character_visual(
            &self.character_appearance,
            self.character_animation_catalog.as_ref(),
        );
        if visual.uses_biomes_skeleton_hierarchy {
            if let Some(pose) = self
                .character_animation_catalog
                .as_ref()
                .and_then(|catalog| catalog.sample_clip_pose("Idle", 0.0))
            {
                apply_biomes_sampled_pose(&mut visual, &pose);
            }
        }
        self.base_mut()
            .add_child(&visual.root.clone().upcast::<godot::classes::Node>());
        self.character_visual = Some(visual);
    }

    fn rebuild_character_visual(&mut self) {
        if let Some(mut visual) = self.character_visual.take() {
            self.base_mut()
                .remove_child(&visual.root.clone().upcast::<godot::classes::Node>());
            visual.root.queue_free();
        }
        self.attach_character_visual();
        self.apply_camera_mode();
    }

    fn set_character_preview_animation_index(&mut self, index: usize, enable_preview: bool) {
        let Some(catalog) = &self.character_animation_catalog else {
            return;
        };
        let clip_count = catalog.clip_count();
        if clip_count == 0 {
            return;
        }

        self.character_preview_animation_index = index.min(clip_count - 1);
        self.character_animation_time_sec = 0.0;
        if enable_preview {
            self.character_preview_animation_enabled = true;
            self.set_third_person_camera(true);
        }

        if let Some(clip_name) = self.selected_character_animation_clip_name_str() {
            self.emit_debug_log(&format!("Character animation preview: {clip_name}"));
        }
    }

    fn selected_character_animation_clip_name_str(&self) -> Option<&str> {
        self.character_animation_catalog
            .as_ref()
            .and_then(|catalog| catalog.clips().get(self.character_preview_animation_index))
            .map(|clip| clip.file_animation_name.as_str())
    }

    fn selected_character_animation_clip_duration_sec(&self) -> f32 {
        self.character_animation_catalog
            .as_ref()
            .and_then(|catalog| catalog.clips().get(self.character_preview_animation_index))
            .map(|clip| clip.duration_sec)
            .unwrap_or(0.0)
    }

    fn set_third_person_camera(&mut self, enabled: bool) {
        if self.third_person_camera == enabled {
            return;
        }

        self.third_person_camera = enabled;
        self.apply_camera_mode();

        let message = if enabled {
            "Third-person camera enabled"
        } else {
            "First-person camera enabled"
        };
        self.emit_debug_log(message);
    }

    fn apply_camera_mode(&mut self) {
        if let Some(camera) = &mut self.camera {
            camera.set_position(if self.third_person_camera {
                third_person_camera_position()
            } else {
                first_person_camera_position()
            });

            if let Some(mut raycast) =
                camera.try_get_node_as::<godot::classes::RayCast3D>("BlockRayCast")
            {
                raycast.set_target_position(block_raycast_target(self.third_person_camera));
            }
        }

        if let Some(visual) = &mut self.character_visual {
            visual.root.set_visible(self.third_person_camera);
        }
    }

    fn update_character_visual(
        &mut self,
        local_movement_input: Vector3,
        sprint_requested: bool,
        fly_mode: bool,
        velocity: Vector3,
        on_floor: bool,
        delta_sec: f32,
    ) {
        let motion_state = character_motion_state_for_velocity(
            local_movement_input,
            sprint_requested,
            fly_mode,
            velocity,
            on_floor,
        );
        self.character_motion_state = motion_state;

        self.character_animation_time_sec =
            next_character_animation_time(self.character_animation_time_sec, delta_sec);
        let preview_clip_name = self
            .character_preview_animation_enabled
            .then(|| {
                self.selected_character_animation_clip_name_str()
                    .map(str::to_string)
            })
            .flatten();
        let active_action_animation =
            if preview_clip_name.is_none() && self.character_action_animation_remaining_sec > 0.0 {
                self.character_action_animation
            } else {
                None
            };
        if self.character_action_animation_remaining_sec > 0.0 {
            self.character_action_animation_remaining_sec =
                (self.character_action_animation_remaining_sec - delta_sec.max(0.0)).max(0.0);
            if self.character_action_animation_remaining_sec <= f32::EPSILON {
                self.character_action_animation = None;
            }
        }
        let gameplay_clip_name = preview_clip_name.is_none().then(|| {
            active_action_animation
                .unwrap_or_else(|| character_motion_biomes_animation(motion_state))
                .file_animation_name()
        });
        let sampled_clip_name = preview_clip_name.as_deref().or(gameplay_clip_name);
        let sampled_pose = sampled_clip_name.and_then(|clip_name| {
            self.character_animation_catalog
                .as_ref()
                .and_then(|catalog| {
                    catalog.sample_clip_pose(clip_name, self.character_animation_time_sec)
                })
        });

        if let Some(visual) = &mut self.character_visual {
            if let Some(pose) = sampled_pose {
                if visual.uses_biomes_skeleton_hierarchy {
                    apply_biomes_sampled_pose(visual, &pose);
                } else {
                    if let Some(clip_name) = sampled_clip_name {
                        apply_voxel_character_clip_pose(
                            visual,
                            clip_name,
                            self.character_animation_time_sec,
                        );
                    } else {
                        apply_voxel_character_pose(
                            visual,
                            motion_state,
                            self.character_animation_time_sec,
                        );
                    }
                    if should_apply_raw_biomes_sampled_pose_to_flat_avatar() {
                        apply_biomes_sampled_pose(visual, &pose);
                    }
                }
            } else if let Some(clip_name) = preview_clip_name {
                apply_voxel_character_clip_pose(
                    visual,
                    &clip_name,
                    self.character_animation_time_sec,
                );
            } else {
                apply_voxel_character_pose(visual, motion_state, self.character_animation_time_sec);
            }
        }
    }

    fn trigger_character_action_animation(&mut self, animation: BiomesPlayerAnimation) {
        self.character_action_animation = Some(animation);
        self.character_action_animation_remaining_sec = character_action_animation_duration(
            self.character_animation_catalog.as_ref(),
            animation,
        );
        self.character_animation_time_sec = 0.0;
    }

    fn update_selected_block_from_hotbar(&mut self, input: &Gd<Input>) {
        for slot in 0..self.hotbar.len() {
            let Some(key) = hotbar_key_for_slot(slot) else {
                continue;
            };

            if input.is_physical_key_pressed(key) {
                let (selected_slot, selected_block) = selected_hotbar_state_after_request(
                    &self.hotbar,
                    self.selected_hotbar_slot,
                    self.selected_block as crate::blocks::BlockId,
                    slot,
                );
                if selected_slot != self.selected_hotbar_slot {
                    self.selected_hotbar_slot = selected_slot;
                    self.selected_block = selected_block as i32;
                    let selected_slot_arg = selected_slot as i32;
                    let selected_block_arg = self.selected_block;
                    self.base_mut().emit_signal(
                        &StringName::from("hotbar_selected"),
                        &[
                            selected_slot_arg.to_variant(),
                            selected_block_arg.to_variant(),
                        ],
                    );
                }
            }
        }
    }

    fn update_selected_tool_from_keys(&mut self, input: &Gd<Input>) {
        for slot in 0..PLAYER_TOOL_SLOTS {
            let Some(key) = tool_key_for_slot(slot) else {
                continue;
            };

            if input.is_physical_key_pressed(key) {
                let selected_slot =
                    selected_tool_state_after_request(self.selected_tool_slot, slot);
                if selected_slot != self.selected_tool_slot {
                    self.selected_tool_slot = selected_slot;
                    self.base_mut().emit_signal(
                        &StringName::from("tool_slot_selected"),
                        &[i32::try_from(selected_slot).unwrap_or(0).to_variant()],
                    );
                }
            }
        }
    }

    fn aimed_block_hit(&mut self) -> Option<BlockHit> {
        let camera = self.camera.as_mut()?;
        let mut raycast = camera.try_get_node_as::<godot::classes::RayCast3D>("BlockRayCast")?;
        raycast.force_raycast_update();

        if !raycast.is_colliding() {
            return None;
        }

        let hit_point = raycast.get_collision_point();
        let normal = raycast.get_collision_normal();
        let block_pos = hit_point - normal * BLOCK_PICK_SURFACE_EPSILON;
        let normal_i = Vector3i::new(
            normal.x.round() as i32,
            normal.y.round() as i32,
            normal.z.round() as i32,
        );
        let block = (
            block_pos.x.floor() as i32,
            block_pos.y.floor() as i32,
            block_pos.z.floor() as i32,
        );

        Some(BlockHit {
            block,
            adjacent: (
                block.0 + normal_i.x,
                block.1 + normal_i.y,
                block.2 + normal_i.z,
            ),
        })
    }

    fn block_intersects_player(&self, x: i32, y: i32, z: i32) -> bool {
        let pos = self.base().get_global_position();
        let player_min = pos + Vector3::new(-0.4, 0.0, -0.4);
        let player_max = pos + Vector3::new(0.4, 1.8, 0.4);
        let block_min = Vector3::new(x as f32, y as f32, z as f32);
        let block_max = block_min + Vector3::ONE;

        player_min.x < block_max.x
            && player_max.x > block_min.x
            && player_min.y < block_max.y
            && player_max.y > block_min.y
            && player_min.z < block_max.z
            && player_max.z > block_min.z
    }

    fn update_selection_outline(&mut self) {
        let target = self.aimed_block_hit().map(|hit| hit.block);
        let Some(outline) = &mut self.selection_outline else {
            return;
        };

        if let Some((x, y, z)) = target {
            outline.set_visible(true);
            outline.set_global_position(Vector3::new(x as f32, y as f32, z as f32));
        } else {
            outline.set_visible(false);
        }
    }
}

fn initial_hotbar_inventory() -> [InventorySlot; PLAYER_HOTBAR_SLOTS] {
    std::array::from_fn(|slot| {
        let block_id = crate::blocks::PLACEABLE_BLOCKS
            .get(slot)
            .copied()
            .unwrap_or(crate::blocks::AIR);
        let count = if crate::blocks::is_placeable(block_id) {
            CREATIVE_HOTBAR_STACK_COUNT
        } else {
            0
        };
        InventorySlot { block_id, count }
    })
}

fn inventory_slot_can_place(slot: &InventorySlot) -> bool {
    slot.count > 0 && crate::blocks::is_placeable(slot.block_id)
}

fn first_placeable_hotbar_slot(hotbar: &[InventorySlot]) -> Option<usize> {
    hotbar.iter().position(inventory_slot_can_place)
}

fn selected_block_for_hotbar_slot(
    hotbar: &[InventorySlot],
    slot: usize,
) -> Option<crate::blocks::BlockId> {
    hotbar
        .get(slot)
        .filter(|item| inventory_slot_can_place(item))
        .map(|item| item.block_id)
}

fn selected_hotbar_state_after_request(
    hotbar: &[InventorySlot],
    current_slot: usize,
    current_block_id: crate::blocks::BlockId,
    requested_slot: usize,
) -> (usize, crate::blocks::BlockId) {
    selected_block_for_hotbar_slot(hotbar, requested_slot)
        .map(|block_id| (requested_slot, block_id))
        .unwrap_or((current_slot, current_block_id))
}

fn selected_tool_state_after_request(current_slot: usize, requested_slot: usize) -> usize {
    if requested_slot < PLAYER_TOOL_SLOTS {
        requested_slot
    } else {
        current_slot
    }
}

fn inventory_has_placeable_block(
    hotbar: &[InventorySlot],
    block_id: crate::blocks::BlockId,
) -> bool {
    hotbar
        .iter()
        .any(|slot| slot.block_id == block_id && inventory_slot_can_place(slot))
}

fn hotbar_key_for_slot(slot: usize) -> Option<Key> {
    match slot {
        0 => Some(Key::KEY_1),
        1 => Some(Key::KEY_2),
        2 => Some(Key::KEY_3),
        3 => Some(Key::KEY_4),
        4 => Some(Key::KEY_5),
        _ => None,
    }
}

fn tool_key_for_slot(slot: usize) -> Option<Key> {
    match slot {
        0 => Some(Key::KEY_6),
        1 => Some(Key::KEY_7),
        2 => Some(Key::KEY_8),
        3 => Some(Key::KEY_9),
        _ => None,
    }
}

fn first_person_camera_position() -> Vector3 {
    Vector3::new(0.0, PLAYER_EYE_HEIGHT_METERS, 0.0)
}

fn third_person_camera_position() -> Vector3 {
    Vector3::new(
        0.0,
        THIRD_PERSON_CAMERA_HEIGHT,
        THIRD_PERSON_CAMERA_DISTANCE,
    )
}

fn block_raycast_target(third_person_camera: bool) -> Vector3 {
    let reach = if third_person_camera {
        BLOCK_REACH + THIRD_PERSON_CAMERA_DISTANCE + THIRD_PERSON_BLOCK_REACH_PADDING
    } else {
        BLOCK_REACH
    };
    Vector3::new(0.0, 0.0, -reach)
}

fn character_motion_state_for_velocity(
    local_movement_input: Vector3,
    sprint_requested: bool,
    fly_mode: bool,
    velocity: Vector3,
    on_floor: bool,
) -> CharacterMotionState {
    let horizontal_speed = (velocity.x * velocity.x + velocity.z * velocity.z).sqrt();
    if fly_mode {
        if local_movement_input.z > 0.35 {
            CharacterMotionState::FlyBackwards
        } else if local_movement_input.z < -0.35
            || local_movement_input.x.abs() > 0.35
            || local_movement_input.y.abs() > 0.35
        {
            CharacterMotionState::FlyForwards
        } else {
            CharacterMotionState::FlyIdle
        }
    } else if !on_floor && velocity.y < -CHARACTER_JUMP_SPEED_THRESHOLD {
        CharacterMotionState::Fall
    } else if !on_floor && velocity.y.abs() > CHARACTER_JUMP_SPEED_THRESHOLD {
        CharacterMotionState::Jump
    } else if horizontal_speed <= CHARACTER_WALK_SPEED_THRESHOLD {
        CharacterMotionState::Idle
    } else if local_movement_input.z > 0.35 {
        CharacterMotionState::RunBackward
    } else if local_movement_input.x < -0.35 {
        if sprint_requested {
            CharacterMotionState::StrafeLeftFast
        } else {
            CharacterMotionState::StrafeLeftSlow
        }
    } else if local_movement_input.x > 0.35 {
        if sprint_requested {
            CharacterMotionState::StrafeRightFast
        } else {
            CharacterMotionState::StrafeRightSlow
        }
    } else if sprint_requested {
        CharacterMotionState::RunForward
    } else {
        CharacterMotionState::WalkForward
    }
}

fn character_motion_biomes_animation(motion_state: CharacterMotionState) -> BiomesPlayerAnimation {
    match motion_state {
        CharacterMotionState::Idle => BiomesPlayerAnimation::Idle,
        CharacterMotionState::WalkForward => BiomesPlayerAnimation::Walk,
        CharacterMotionState::RunForward => BiomesPlayerAnimation::Run,
        CharacterMotionState::RunBackward => BiomesPlayerAnimation::RunBackwards,
        CharacterMotionState::StrafeLeftSlow => BiomesPlayerAnimation::StrafeLeftSlow,
        CharacterMotionState::StrafeLeftFast => BiomesPlayerAnimation::StrafeLeftFast,
        CharacterMotionState::StrafeRightSlow => BiomesPlayerAnimation::StrafeRightSlow,
        CharacterMotionState::StrafeRightFast => BiomesPlayerAnimation::StrafeRightFast,
        CharacterMotionState::Jump => BiomesPlayerAnimation::Jump,
        CharacterMotionState::Fall => BiomesPlayerAnimation::Fall,
        CharacterMotionState::FlyIdle => BiomesPlayerAnimation::FlyIdle,
        CharacterMotionState::FlyForwards => BiomesPlayerAnimation::FlyForwards,
        CharacterMotionState::FlyBackwards => BiomesPlayerAnimation::SwimBackwards,
    }
}

fn character_action_animation_duration(
    catalog: Option<&BiomesAnimationCatalog>,
    animation: BiomesPlayerAnimation,
) -> f32 {
    catalog
        .and_then(|catalog| catalog.duration_for_animation(animation))
        .filter(|duration| duration.is_finite() && *duration > 0.0)
        .unwrap_or(CHARACTER_ACTION_FALLBACK_SECONDS)
}

fn next_character_animation_time(current_time_sec: f32, delta_sec: f32) -> f32 {
    if !current_time_sec.is_finite() {
        return 0.0;
    }
    if !delta_sec.is_finite() || delta_sec <= 0.0 {
        return current_time_sec;
    }
    (current_time_sec + delta_sec) % CHARACTER_ANIMATION_WRAP_SECONDS
}

fn biomes_avatar_joint_bind_position(joint: BiomesAvatarJoint) -> Vector3 {
    let [x, y, z] = crate::biomes_avatar::avatar_joint_bind_position(joint, CHARACTER_VOXEL_SCALE);
    Vector3::new(x, y, z)
}

fn create_voxel_character_visual(
    appearance: &BiomesAvatarAppearance,
    catalog: Option<&BiomesAnimationCatalog>,
) -> VoxelCharacterVisual {
    if let Some(catalog) = catalog {
        if let Some(visual) = create_biomes_skeleton_character_visual(appearance, catalog) {
            return visual;
        }
    }
    create_flat_voxel_character_visual(appearance)
}

fn create_biomes_skeleton_character_visual(
    appearance: &BiomesAvatarAppearance,
    catalog: &BiomesAnimationCatalog,
) -> Option<VoxelCharacterVisual> {
    let armature_rest = catalog.armature_rest_pose()?;
    let rest_poses = catalog.joint_rest_poses();
    if rest_poses.len() != crate::biomes_avatar::BIOMES_CHARACTER_JOINT_ORDERING.len() {
        return None;
    }

    let mut root = Node3D::new_alloc();
    root.set_name(&StringName::from(PLAYER_CHARACTER_VISUAL_NAME));
    root.set_position(Vector3::ZERO);
    root.set_rotation_degrees(Vector3::new(0.0, CHARACTER_ROOT_YAW_DEGREES, 0.0));
    root.set_visible(false);

    let mut armature = Node3D::new_alloc();
    armature.set_name(&StringName::from("Armature"));
    set_node_biomes_transform(&mut armature, armature_rest);

    let head = create_biomes_skeleton_character_part(
        "Head",
        BiomesAvatarJoint::Head,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::Head)?,
        Vector3::new(0.76, 0.44, 0.44),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let mut chest = create_biomes_skeleton_character_part(
        "Chest",
        BiomesAvatarJoint::Chest,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::Chest)?,
        Vector3::new(0.68, 0.68, 0.34),
        Color::from_rgb(0.18, 0.45, 0.78),
    );
    let mut waist = create_biomes_skeleton_character_part(
        "Waist",
        BiomesAvatarJoint::Waist,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::Waist)?,
        Vector3::new(0.58, 0.32, 0.34),
        Color::from_rgb(0.12, 0.16, 0.20),
    );
    let mut l_arm = create_biomes_skeleton_character_part(
        "L_Arm",
        BiomesAvatarJoint::LArm,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LArm)?,
        Vector3::new(0.20, 0.34, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let mut l_forearm = create_biomes_skeleton_character_part(
        "L_Forearm",
        BiomesAvatarJoint::LForearm,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LForearm)?,
        Vector3::new(0.20, 0.34, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let hand_l = create_biomes_skeleton_character_part(
        "L_Hand",
        BiomesAvatarJoint::LHand,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LHand)?,
        Vector3::new(0.20, 0.18, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let mut r_arm = create_biomes_skeleton_character_part(
        "R_Arm",
        BiomesAvatarJoint::RArm,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RArm)?,
        Vector3::new(0.20, 0.34, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let mut r_forearm = create_biomes_skeleton_character_part(
        "R_Forearm",
        BiomesAvatarJoint::RForearm,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RForearm)?,
        Vector3::new(0.20, 0.34, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let hand_r = create_biomes_skeleton_character_part(
        "R_Hand",
        BiomesAvatarJoint::RHand,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RHand)?,
        Vector3::new(0.20, 0.18, 0.20),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let mut l_thigh = create_biomes_skeleton_character_part(
        "L_Thigh",
        BiomesAvatarJoint::LThigh,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LThigh)?,
        Vector3::new(0.22, 0.32, 0.24),
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let mut l_leg = create_biomes_skeleton_character_part(
        "L_Leg",
        BiomesAvatarJoint::LLeg,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LLeg)?,
        Vector3::new(0.22, 0.32, 0.24),
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let foot_l = create_biomes_skeleton_character_part(
        "L_Foot",
        BiomesAvatarJoint::LFoot,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LFoot)?,
        Vector3::new(0.22, 0.14, 0.28),
        Color::from_rgb(0.16, 0.22, 0.32),
    );
    let mut r_thigh = create_biomes_skeleton_character_part(
        "R_Thigh",
        BiomesAvatarJoint::RThigh,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RThigh)?,
        Vector3::new(0.22, 0.32, 0.24),
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let mut r_leg = create_biomes_skeleton_character_part(
        "R_Leg",
        BiomesAvatarJoint::RLeg,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RLeg)?,
        Vector3::new(0.22, 0.32, 0.24),
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let foot_r = create_biomes_skeleton_character_part(
        "R_Foot",
        BiomesAvatarJoint::RFoot,
        appearance,
        biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RFoot)?,
        Vector3::new(0.22, 0.14, 0.28),
        Color::from_rgb(0.16, 0.22, 0.32),
    );

    l_leg.add_child(&foot_l.clone().upcast::<godot::classes::Node>());
    l_thigh.add_child(&l_leg.clone().upcast::<godot::classes::Node>());
    waist.add_child(&l_thigh.clone().upcast::<godot::classes::Node>());
    r_leg.add_child(&foot_r.clone().upcast::<godot::classes::Node>());
    r_thigh.add_child(&r_leg.clone().upcast::<godot::classes::Node>());
    waist.add_child(&r_thigh.clone().upcast::<godot::classes::Node>());

    l_forearm.add_child(&hand_l.clone().upcast::<godot::classes::Node>());
    l_arm.add_child(&l_forearm.clone().upcast::<godot::classes::Node>());
    chest.add_child(&l_arm.clone().upcast::<godot::classes::Node>());
    r_forearm.add_child(&hand_r.clone().upcast::<godot::classes::Node>());
    r_arm.add_child(&r_forearm.clone().upcast::<godot::classes::Node>());
    chest.add_child(&r_arm.clone().upcast::<godot::classes::Node>());
    chest.add_child(&head.clone().upcast::<godot::classes::Node>());

    armature.add_child(&chest.clone().upcast::<godot::classes::Node>());
    armature.add_child(&waist.clone().upcast::<godot::classes::Node>());
    root.add_child(&armature.upcast::<godot::classes::Node>());

    Some(VoxelCharacterVisual {
        root,
        uses_biomes_skeleton_hierarchy: true,
        head,
        chest,
        waist,
        l_arm,
        l_forearm,
        hand_l,
        r_arm,
        r_forearm,
        hand_r,
        l_thigh,
        l_leg,
        foot_l,
        r_thigh,
        r_leg,
        foot_r,
    })
}

fn create_flat_voxel_character_visual(appearance: &BiomesAvatarAppearance) -> VoxelCharacterVisual {
    let mut root = Node3D::new_alloc();
    root.set_name(&StringName::from(PLAYER_CHARACTER_VISUAL_NAME));
    root.set_position(Vector3::ZERO);
    root.set_rotation_degrees(Vector3::new(0.0, CHARACTER_ROOT_YAW_DEGREES, 0.0));
    root.set_visible(false);

    let head = create_biomes_avatar_character_part(
        "Head",
        BiomesAvatarJoint::Head,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::Head),
        Vector3::ZERO,
        Vector3::new(0.76, 0.44, 0.44),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let chest = create_biomes_avatar_character_part(
        "Chest",
        BiomesAvatarJoint::Chest,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::Chest),
        Vector3::ZERO,
        Vector3::new(0.68, 0.68, 0.34),
        Vector3::ZERO,
        Color::from_rgb(0.18, 0.45, 0.78),
    );
    let waist = create_biomes_avatar_character_part(
        "Waist",
        BiomesAvatarJoint::Waist,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::Waist),
        Vector3::ZERO,
        Vector3::new(0.58, 0.32, 0.34),
        Vector3::ZERO,
        Color::from_rgb(0.12, 0.16, 0.20),
    );
    let l_arm = create_biomes_avatar_character_part(
        "L_Arm",
        BiomesAvatarJoint::LArm,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LArm),
        Vector3::ZERO,
        Vector3::new(0.20, 0.34, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let l_forearm = create_biomes_avatar_character_part(
        "L_Forearm",
        BiomesAvatarJoint::LForearm,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LForearm),
        Vector3::ZERO,
        Vector3::new(0.20, 0.34, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let hand_l = create_biomes_avatar_character_part(
        "HandL",
        BiomesAvatarJoint::LHand,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LHand),
        Vector3::ZERO,
        Vector3::new(0.20, 0.18, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let r_arm = create_biomes_avatar_character_part(
        "R_Arm",
        BiomesAvatarJoint::RArm,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RArm),
        Vector3::ZERO,
        Vector3::new(0.20, 0.34, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let r_forearm = create_biomes_avatar_character_part(
        "R_Forearm",
        BiomesAvatarJoint::RForearm,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RForearm),
        Vector3::ZERO,
        Vector3::new(0.20, 0.34, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let hand_r = create_biomes_avatar_character_part(
        "HandR",
        BiomesAvatarJoint::RHand,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RHand),
        Vector3::ZERO,
        Vector3::new(0.20, 0.18, 0.20),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let l_thigh = create_biomes_avatar_character_part(
        "L_Thigh",
        BiomesAvatarJoint::LThigh,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LThigh),
        Vector3::ZERO,
        Vector3::new(0.22, 0.32, 0.24),
        Vector3::ZERO,
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let l_leg = create_biomes_avatar_character_part(
        "L_Leg",
        BiomesAvatarJoint::LLeg,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LLeg),
        Vector3::ZERO,
        Vector3::new(0.22, 0.32, 0.24),
        Vector3::ZERO,
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let foot_l = create_biomes_avatar_character_part(
        "FootL",
        BiomesAvatarJoint::LFoot,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::LFoot),
        Vector3::ZERO,
        Vector3::new(0.22, 0.14, 0.28),
        Vector3::ZERO,
        Color::from_rgb(0.16, 0.22, 0.32),
    );
    let r_thigh = create_biomes_avatar_character_part(
        "R_Thigh",
        BiomesAvatarJoint::RThigh,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RThigh),
        Vector3::ZERO,
        Vector3::new(0.22, 0.32, 0.24),
        Vector3::ZERO,
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let r_leg = create_biomes_avatar_character_part(
        "R_Leg",
        BiomesAvatarJoint::RLeg,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RLeg),
        Vector3::ZERO,
        Vector3::new(0.22, 0.32, 0.24),
        Vector3::ZERO,
        Color::from_rgb(0.10, 0.16, 0.25),
    );
    let foot_r = create_biomes_avatar_character_part(
        "FootR",
        BiomesAvatarJoint::RFoot,
        appearance,
        biomes_avatar_joint_bind_position(BiomesAvatarJoint::RFoot),
        Vector3::ZERO,
        Vector3::new(0.22, 0.14, 0.28),
        Vector3::ZERO,
        Color::from_rgb(0.16, 0.22, 0.32),
    );

    root.add_child(&head.clone().upcast::<godot::classes::Node>());
    root.add_child(&chest.clone().upcast::<godot::classes::Node>());
    root.add_child(&waist.clone().upcast::<godot::classes::Node>());
    root.add_child(&l_arm.clone().upcast::<godot::classes::Node>());
    root.add_child(&l_forearm.clone().upcast::<godot::classes::Node>());
    root.add_child(&hand_l.clone().upcast::<godot::classes::Node>());
    root.add_child(&r_arm.clone().upcast::<godot::classes::Node>());
    root.add_child(&r_forearm.clone().upcast::<godot::classes::Node>());
    root.add_child(&hand_r.clone().upcast::<godot::classes::Node>());
    root.add_child(&l_thigh.clone().upcast::<godot::classes::Node>());
    root.add_child(&l_leg.clone().upcast::<godot::classes::Node>());
    root.add_child(&foot_l.clone().upcast::<godot::classes::Node>());
    root.add_child(&r_thigh.clone().upcast::<godot::classes::Node>());
    root.add_child(&r_leg.clone().upcast::<godot::classes::Node>());
    root.add_child(&foot_r.clone().upcast::<godot::classes::Node>());

    let mut visual = VoxelCharacterVisual {
        root,
        uses_biomes_skeleton_hierarchy: false,
        head,
        chest,
        waist,
        l_arm,
        l_forearm,
        hand_l,
        r_arm,
        r_forearm,
        hand_r,
        l_thigh,
        l_leg,
        foot_l,
        r_thigh,
        r_leg,
        foot_r,
    };
    apply_voxel_character_pose(&mut visual, CharacterMotionState::Idle, 0.0);
    visual
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct BiomesMeshInverseBindTransform {
    position: Vector3,
    rotation: [f32; 4],
    scale: Vector3,
}

fn biomes_joint_rest_pose(
    rest_poses: &[BiomesJointRestPose],
    joint: BiomesAvatarJoint,
) -> Option<BiomesJointRestPose> {
    rest_poses.iter().find(|pose| pose.joint == joint).copied()
}

fn biomes_visual_joint_rest_pose(
    rest_poses: &[BiomesJointRestPose],
    visual_joint: BiomesAvatarJoint,
) -> Option<BiomesJointRestPose> {
    biomes_joint_rest_pose(
        rest_poses,
        biomes_skeleton_joint_for_visual_joint(visual_joint),
    )
}

fn biomes_skeleton_joint_for_visual_joint(visual_joint: BiomesAvatarJoint) -> BiomesAvatarJoint {
    visual_joint
}

fn biomes_visual_joint_for_skeleton_joint(skeleton_joint: BiomesAvatarJoint) -> BiomesAvatarJoint {
    skeleton_joint
}

fn create_biomes_skeleton_character_part(
    name: &str,
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
    rest_pose: BiomesJointRestPose,
    fallback_mesh_size: Vector3,
    fallback_color: Color,
) -> Gd<Node3D> {
    let mut pivot = Node3D::new_alloc();
    pivot.set_name(&StringName::from(name));
    set_biomes_joint_node_transform(&mut pivot, joint, rest_pose.local);

    let mesh_inverse_bind = biomes_joint_mesh_inverse_bind_transform(joint, rest_pose.global);
    let mut mesh = MeshInstance3D::new_alloc();
    mesh.set_position(mesh_inverse_bind.position);
    mesh.set_quaternion(quaternion_from_array(mesh_inverse_bind.rotation));
    mesh.set_scale(mesh_inverse_bind.scale);
    match crate::biomes_avatar::load_avatar_joint_mesh(joint, appearance, CHARACTER_VOXEL_SCALE) {
        Ok(composed_mesh) => {
            mesh.set_mesh(&composed_mesh);
            mesh.set_material_override(&create_vox_vertex_color_material());
        }
        Err(err) => {
            godot_print!(
                "Biomes avatar character part fallback for {name}/{}: {err}",
                joint.name()
            );
            let mut box_mesh = BoxMesh::new_gd();
            box_mesh.set_size(fallback_mesh_size);
            mesh.set_mesh(&box_mesh.upcast::<godot::classes::Mesh>());
            mesh.set_material_override(&create_voxel_character_material(fallback_color));
        }
    }

    pivot.add_child(&mesh.upcast::<godot::classes::Node>());
    pivot
}

fn set_node_biomes_transform(node: &mut Gd<Node3D>, transform: BiomesTransform) {
    node.set_position(biomes_pose_translation_to_godot(transform.translation));
    node.set_quaternion(quaternion_from_array(biomes_pose_rotation_to_godot(
        transform.rotation,
    )));
    node.set_scale(biomes_pose_scale_to_godot(transform.scale));
}

fn set_biomes_joint_node_transform(
    node: &mut Gd<Node3D>,
    joint: BiomesAvatarJoint,
    transform: BiomesTransform,
) {
    node.set_position(
        biomes_pose_translation_to_godot(transform.translation)
            + biomes_joint_root_weld_offset(joint),
    );
    node.set_quaternion(quaternion_from_array(biomes_pose_rotation_to_godot(
        transform.rotation,
    )));
    node.set_scale(biomes_pose_scale_to_godot(transform.scale));
}

fn biomes_joint_mesh_inverse_bind_transform(
    joint: BiomesAvatarJoint,
    rest_global: BiomesTransform,
) -> BiomesMeshInverseBindTransform {
    let rest_position = biomes_pose_translation_to_godot(rest_global.translation);
    let rest_rotation = biomes_pose_rotation_to_godot(rest_global.rotation);
    let rest_scale = biomes_pose_scale_to_godot(rest_global.scale);
    let inverse_rotation = quaternion_inverse4(rest_rotation);
    let mesh_bind_position =
        biomes_avatar_joint_bind_position(joint) + biomes_joint_mesh_stitch_offset(joint);
    let unrotated_offset =
        rotate_vector3_by_quaternion4(inverse_rotation, mesh_bind_position - rest_position);

    BiomesMeshInverseBindTransform {
        position: divide_vector3_components(unrotated_offset, rest_scale),
        rotation: inverse_rotation,
        scale: multiply_vector3_components(
            reciprocal_vector3_components(rest_scale),
            biomes_joint_mesh_overlap_scale(joint),
        ),
    }
}

fn biomes_joint_mesh_overlap_scale(joint: BiomesAvatarJoint) -> Vector3 {
    match joint {
        BiomesAvatarJoint::LArm
        | BiomesAvatarJoint::RArm
        | BiomesAvatarJoint::LForearm
        | BiomesAvatarJoint::RForearm => Vector3::new(CHARACTER_ARM_MESH_OVERLAP_SCALE, 1.0, 1.0),
        BiomesAvatarJoint::LHand | BiomesAvatarJoint::RHand => {
            Vector3::new(CHARACTER_HAND_MESH_OVERLAP_SCALE, 1.0, 1.0)
        }
        BiomesAvatarJoint::LThigh
        | BiomesAvatarJoint::RThigh
        | BiomesAvatarJoint::LLeg
        | BiomesAvatarJoint::RLeg => Vector3::new(1.0, CHARACTER_LEG_MESH_OVERLAP_SCALE, 1.0),
        BiomesAvatarJoint::LFoot | BiomesAvatarJoint::RFoot => {
            Vector3::new(1.0, CHARACTER_FOOT_MESH_OVERLAP_SCALE, 1.0)
        }
        _ => Vector3::ONE,
    }
}

fn biomes_joint_root_weld_offset(joint: BiomesAvatarJoint) -> Vector3 {
    match joint {
        BiomesAvatarJoint::LArm => Vector3::new(CHARACTER_ARM_ROOT_WELD_INSET_METERS, 0.0, 0.0),
        BiomesAvatarJoint::RArm => Vector3::new(-CHARACTER_ARM_ROOT_WELD_INSET_METERS, 0.0, 0.0),
        BiomesAvatarJoint::LThigh => {
            Vector3::new(CHARACTER_LEFT_LEG_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        }
        BiomesAvatarJoint::RThigh => {
            Vector3::new(-CHARACTER_RIGHT_LEG_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        }
        _ => Vector3::ZERO,
    }
}

fn biomes_joint_mesh_stitch_offset(joint: BiomesAvatarJoint) -> Vector3 {
    match joint {
        BiomesAvatarJoint::LArm | BiomesAvatarJoint::LForearm | BiomesAvatarJoint::LHand => {
            Vector3::new(CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        }
        BiomesAvatarJoint::RArm | BiomesAvatarJoint::RForearm | BiomesAvatarJoint::RHand => {
            Vector3::new(-CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        }
        BiomesAvatarJoint::LThigh | BiomesAvatarJoint::LLeg => {
            Vector3::new(CHARACTER_LEFT_LEG_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        }
        BiomesAvatarJoint::LFoot => {
            Vector3::new(CHARACTER_LEFT_FOOT_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        }
        _ => Vector3::ZERO,
    }
}

fn create_biomes_avatar_character_part(
    name: &str,
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
    pivot_position: Vector3,
    mesh_offset: Vector3,
    fallback_mesh_size: Vector3,
    fallback_mesh_offset: Vector3,
    fallback_color: Color,
) -> Gd<Node3D> {
    create_biomes_avatar_character_part_with_mesh_rotation(
        name,
        joint,
        appearance,
        pivot_position,
        mesh_offset,
        Vector3::ZERO,
        fallback_mesh_size,
        fallback_mesh_offset,
        fallback_color,
    )
}

fn create_biomes_avatar_character_part_with_mesh_rotation(
    name: &str,
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
    pivot_position: Vector3,
    mesh_offset: Vector3,
    mesh_rotation_degrees: Vector3,
    fallback_mesh_size: Vector3,
    fallback_mesh_offset: Vector3,
    fallback_color: Color,
) -> Gd<Node3D> {
    let mut pivot = Node3D::new_alloc();
    pivot.set_name(&StringName::from(name));
    pivot.set_position(pivot_position);

    let mut mesh = MeshInstance3D::new_alloc();
    mesh.set_position(mesh_offset);
    mesh.set_rotation_degrees(mesh_rotation_degrees);
    match crate::biomes_avatar::load_avatar_joint_mesh(joint, appearance, CHARACTER_VOXEL_SCALE) {
        Ok(composed_mesh) => {
            mesh.set_mesh(&composed_mesh);
            mesh.set_material_override(&create_vox_vertex_color_material());
        }
        Err(err) => {
            godot_print!(
                "Biomes avatar character part fallback for {name}/{}: {err}",
                joint.name()
            );
            let mut box_mesh = BoxMesh::new_gd();
            box_mesh.set_size(fallback_mesh_size);
            mesh.set_position(fallback_mesh_offset);
            mesh.set_mesh(&box_mesh.upcast::<godot::classes::Mesh>());
            mesh.set_material_override(&create_voxel_character_material(fallback_color));
        }
    }

    pivot.add_child(&mesh.upcast::<godot::classes::Node>());
    pivot
}

fn create_voxel_character_material(color: Color) -> Gd<godot::classes::Material> {
    let mut material = StandardMaterial3D::new_gd();
    material.set_albedo(color);
    material.set_shading_mode(base_material_3d::ShadingMode::UNSHADED);
    material.upcast::<godot::classes::Material>()
}

fn create_vox_vertex_color_material() -> Gd<godot::classes::Material> {
    let mut material = StandardMaterial3D::new_gd();
    material.set_albedo(Color::WHITE);
    material.set_shading_mode(base_material_3d::ShadingMode::UNSHADED);
    material.set_cull_mode(base_material_3d::CullMode::DISABLED);
    material.set_flag(base_material_3d::Flags::ALBEDO_FROM_VERTEX_COLOR, true);
    material.upcast::<godot::classes::Material>()
}

fn apply_voxel_character_pose(
    visual: &mut VoxelCharacterVisual,
    motion_state: CharacterMotionState,
    animation_time_sec: f32,
) {
    match motion_state {
        CharacterMotionState::Idle => apply_voxel_idle_pose(visual, animation_time_sec),
        CharacterMotionState::WalkForward
        | CharacterMotionState::RunForward
        | CharacterMotionState::RunBackward
        | CharacterMotionState::StrafeLeftSlow
        | CharacterMotionState::StrafeLeftFast
        | CharacterMotionState::StrafeRightSlow
        | CharacterMotionState::StrafeRightFast
        | CharacterMotionState::FlyForwards
        | CharacterMotionState::FlyBackwards => apply_voxel_run_pose(visual, animation_time_sec),
        CharacterMotionState::Jump | CharacterMotionState::Fall => {
            apply_voxel_jump_pose(visual, animation_time_sec)
        }
        CharacterMotionState::FlyIdle => apply_voxel_idle_pose(visual, animation_time_sec),
    }
}

fn should_apply_raw_biomes_sampled_pose_to_flat_avatar() -> bool {
    false
}

fn apply_biomes_sampled_pose(visual: &mut VoxelCharacterVisual, pose: &BiomesSampledPose) {
    for joint_pose in &pose.joints {
        let visual_joint = biomes_visual_joint_for_skeleton_joint(joint_pose.joint);
        if let Some(node) = biomes_visual_node_for_joint_mut(visual, visual_joint) {
            apply_biomes_sampled_joint_pose(node, visual_joint, joint_pose);
        }
    }
}

fn biomes_visual_node_for_joint_mut<'a>(
    visual: &'a mut VoxelCharacterVisual,
    joint: BiomesAvatarJoint,
) -> Option<&'a mut Gd<Node3D>> {
    match joint {
        BiomesAvatarJoint::Head => Some(&mut visual.head),
        BiomesAvatarJoint::Chest => Some(&mut visual.chest),
        BiomesAvatarJoint::Waist => Some(&mut visual.waist),
        BiomesAvatarJoint::LArm => Some(&mut visual.l_arm),
        BiomesAvatarJoint::LForearm => Some(&mut visual.l_forearm),
        BiomesAvatarJoint::LHand => Some(&mut visual.hand_l),
        BiomesAvatarJoint::RArm => Some(&mut visual.r_arm),
        BiomesAvatarJoint::RForearm => Some(&mut visual.r_forearm),
        BiomesAvatarJoint::RHand => Some(&mut visual.hand_r),
        BiomesAvatarJoint::LThigh => Some(&mut visual.l_thigh),
        BiomesAvatarJoint::LLeg => Some(&mut visual.l_leg),
        BiomesAvatarJoint::LFoot => Some(&mut visual.foot_l),
        BiomesAvatarJoint::RThigh => Some(&mut visual.r_thigh),
        BiomesAvatarJoint::RLeg => Some(&mut visual.r_leg),
        BiomesAvatarJoint::RFoot => Some(&mut visual.foot_r),
    }
}

fn apply_biomes_sampled_joint_pose(
    node: &mut Gd<Node3D>,
    visual_joint: BiomesAvatarJoint,
    joint_pose: &BiomesSampledJointPose,
) {
    node.set_position(
        biomes_pose_translation_to_godot(joint_pose.local_translation)
            + biomes_joint_root_weld_offset(visual_joint),
    );
    node.set_quaternion(quaternion_from_array(biomes_pose_rotation_to_godot(
        joint_pose.local_rotation,
    )));
    node.set_scale(biomes_pose_scale_to_godot(joint_pose.local_scale));
}

#[allow(dead_code)]
fn biomes_sampled_joint_position(joint: BiomesAvatarJoint, translation_delta: [f32; 3]) -> Vector3 {
    let _source_delta = biomes_pose_translation_delta_to_godot(translation_delta);
    // The source GLTF translations belong to a hierarchical skeleton. This runtime
    // avatar is a flat set of modular voxel parts, so applying those translations
    // to each joint separately pulls arms and legs away from the skin.
    biomes_avatar_joint_bind_position(joint)
}

fn biomes_pose_translation_to_godot(translation: [f32; 3]) -> Vector3 {
    let scale = CHARACTER_VOXEL_SCALE / crate::biomes_avatar::BIOMES_ANIMATION_VOX_TO_POSE_SCALE;
    Vector3::new(
        translation[2] * scale,
        translation[1] * scale,
        -translation[0] * scale,
    )
}

#[allow(dead_code)]
fn biomes_pose_translation_delta_to_godot(delta: [f32; 3]) -> Vector3 {
    biomes_pose_translation_to_godot(delta)
}

fn biomes_pose_rotation_to_godot(rotation: [f32; 4]) -> [f32; 4] {
    let pose_to_godot = [
        0.0,
        std::f32::consts::FRAC_1_SQRT_2,
        0.0,
        std::f32::consts::FRAC_1_SQRT_2,
    ];
    quaternion_mul4(
        quaternion_mul4(pose_to_godot, normalize_quaternion4(rotation)),
        quaternion_inverse4(pose_to_godot),
    )
}

#[allow(dead_code)]
fn biomes_pose_rotation_delta_to_godot(rotation_delta: [f32; 4]) -> [f32; 4] {
    biomes_pose_rotation_to_godot(rotation_delta)
}

fn biomes_pose_scale_to_godot(scale: [f32; 3]) -> Vector3 {
    Vector3::new(
        safe_biomes_pose_scale(scale[2]),
        safe_biomes_pose_scale(scale[1]),
        safe_biomes_pose_scale(scale[0]),
    )
}

fn safe_biomes_pose_scale(value: f32) -> f32 {
    if value.is_finite() {
        value.clamp(0.25, 4.0)
    } else {
        1.0
    }
}

fn quaternion_from_array(value: [f32; 4]) -> Quaternion {
    Quaternion::new(value[0], value[1], value[2], value[3])
}

fn rotate_vector3_by_quaternion4(rotation: [f32; 4], value: Vector3) -> Vector3 {
    let q = normalize_quaternion4(rotation);
    let u = Vector3::new(q[0], q[1], q[2]);
    let uv = u.cross(value);
    let uuv = u.cross(uv);
    value + uv * (2.0 * q[3]) + uuv * 2.0
}

fn divide_vector3_components(value: Vector3, divisor: Vector3) -> Vector3 {
    Vector3::new(
        divide_component(value.x, divisor.x),
        divide_component(value.y, divisor.y),
        divide_component(value.z, divisor.z),
    )
}

fn reciprocal_vector3_components(value: Vector3) -> Vector3 {
    Vector3::new(
        reciprocal_component(value.x),
        reciprocal_component(value.y),
        reciprocal_component(value.z),
    )
}

fn multiply_vector3_components(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x * b.x, a.y * b.y, a.z * b.z)
}

fn divide_component(value: f32, divisor: f32) -> f32 {
    if divisor.is_finite() && divisor.abs() > f32::EPSILON {
        value / divisor
    } else {
        value
    }
}

fn reciprocal_component(value: f32) -> f32 {
    if value.is_finite() && value.abs() > f32::EPSILON {
        1.0 / value
    } else {
        1.0
    }
}

fn normalize_quaternion4(value: [f32; 4]) -> [f32; 4] {
    let length =
        (value[0] * value[0] + value[1] * value[1] + value[2] * value[2] + value[3] * value[3])
            .sqrt();
    if !length.is_finite() || length <= f32::EPSILON {
        return [0.0, 0.0, 0.0, 1.0];
    }
    [
        value[0] / length,
        value[1] / length,
        value[2] / length,
        value[3] / length,
    ]
}

fn quaternion_inverse4(value: [f32; 4]) -> [f32; 4] {
    let normalized = normalize_quaternion4(value);
    [
        -normalized[0],
        -normalized[1],
        -normalized[2],
        normalized[3],
    ]
}

fn quaternion_mul4(a: [f32; 4], b: [f32; 4]) -> [f32; 4] {
    normalize_quaternion4([
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    ])
}

fn apply_voxel_character_clip_pose(
    visual: &mut VoxelCharacterVisual,
    clip_name: &str,
    animation_time_sec: f32,
) {
    match character_clip_preview_kind(clip_name) {
        CharacterClipPreviewKind::Idle | CharacterClipPreviewKind::Fallback => {
            apply_voxel_idle_pose(visual, animation_time_sec)
        }
        CharacterClipPreviewKind::Walk => apply_voxel_run_pose(visual, animation_time_sec * 0.58),
        CharacterClipPreviewKind::Run => apply_voxel_run_pose(visual, animation_time_sec),
        CharacterClipPreviewKind::Jump => apply_voxel_jump_pose(visual, animation_time_sec),
        kind => apply_voxel_upper_body_preview_pose(visual, kind, animation_time_sec),
    }
}

fn character_clip_preview_kind(clip_name: &str) -> CharacterClipPreviewKind {
    match clip_name {
        "Idle" => CharacterClipPreviewKind::Idle,
        "Walking" | "CrouchWalking" | "StrafeLeftWalking" | "StrafeRightWalking" => {
            CharacterClipPreviewKind::Walk
        }
        "Running" | "RunningBackward" | "StrafeLeftRunning" | "StrafeRightRunning" => {
            CharacterClipPreviewKind::Run
        }
        "Jump" | "Fall" => CharacterClipPreviewKind::Jump,
        "Crouch" | "CrouchIdle" => CharacterClipPreviewKind::Crouch,
        "SwimmingBackward" | "SwimmingForward" | "SwimmingIdle" => CharacterClipPreviewKind::Swim,
        "Waving" => CharacterClipPreviewKind::Wave,
        "Dancing" => CharacterClipPreviewKind::Dance,
        "Applause" => CharacterClipPreviewKind::Applause,
        "Attack" | "Attack2" | "DiggingHand" | "DiggingTool" | "DiggingToolOld" | "Tilling" => {
            CharacterClipPreviewKind::Work
        }
        "FishingCastPull" | "FishingCastRelease" | "FishingIdle" | "FishingReel"
        | "FishingShow" => CharacterClipPreviewKind::Fishing,
        "Drink" | "Eat" => CharacterClipPreviewKind::Consume,
        "Sit" => CharacterClipPreviewKind::Sit,
        "Flex" => CharacterClipPreviewKind::Flex,
        "Laugh" => CharacterClipPreviewKind::Laugh,
        "Point" => CharacterClipPreviewKind::Point,
        "HoldingCamera" => CharacterClipPreviewKind::Camera,
        "Rock" => CharacterClipPreviewKind::Rock,
        "Sick" => CharacterClipPreviewKind::Sick,
        "ItemAway" | "ItemPutBack" => CharacterClipPreviewKind::Item,
        "Craft" => CharacterClipPreviewKind::Craft,
        "Watering" => CharacterClipPreviewKind::Watering,
        "TPose" => CharacterClipPreviewKind::TPose,
        _ => CharacterClipPreviewKind::Fallback,
    }
}

fn apply_voxel_upper_body_preview_pose(
    visual: &mut VoxelCharacterVisual,
    kind: CharacterClipPreviewKind,
    animation_time_sec: f32,
) {
    apply_voxel_idle_pose(visual, animation_time_sec);

    let fast_wave = (animation_time_sec * 7.5).sin();
    let slow_wave = (animation_time_sec * 3.0).sin();

    match kind {
        CharacterClipPreviewKind::Crouch => {
            set_node_transform(
                &mut visual.head,
                Vector3::new(0.0, CHARACTER_HEAD_Y - 0.18, 0.02),
                Vector3::new(6.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y - 0.14, 0.02),
                Vector3::new(10.0, 0.0, slow_wave * 2.0),
            );
            set_node_transform(
                &mut visual.waist,
                Vector3::new(0.0, CHARACTER_BELT_Y - 0.08, 0.0),
                Vector3::new(8.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.l_thigh,
                Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.13, 0.02),
                Vector3::new(34.0, 0.0, -3.0),
            );
            set_node_transform(
                &mut visual.r_thigh,
                Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.13, 0.02),
                Vector3::new(34.0, 0.0, 3.0),
            );
        }
        CharacterClipPreviewKind::Swim => {
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y + slow_wave * 0.018, -0.04),
                Vector3::new(-18.0, 0.0, slow_wave * 3.0),
            );
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(78.0 * fast_wave, 0.0, -14.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(-78.0 * fast_wave, 0.0, 14.0),
            );
            set_node_transform(
                &mut visual.l_leg,
                Vector3::new(-CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y, 0.0),
                Vector3::new(-28.0 * fast_wave, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.r_leg,
                Vector3::new(CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y, 0.0),
                Vector3::new(28.0 * fast_wave, 0.0, 0.0),
            );
        }
        CharacterClipPreviewKind::Wave => {
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(-118.0, 0.0, 18.0 + fast_wave * 8.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y + 0.12, 0.0),
                Vector3::new(-128.0, 0.0, 32.0 + fast_wave * 18.0),
            );
            set_node_transform(
                &mut visual.hand_r,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y - 0.04, 0.0),
                Vector3::new(-132.0, 0.0, 38.0 + fast_wave * 20.0),
            );
        }
        CharacterClipPreviewKind::Dance => {
            set_node_transform(
                &mut visual.head,
                Vector3::new(0.0, CHARACTER_HEAD_Y + fast_wave.abs() * 0.025, 0.0),
                Vector3::new(slow_wave * 6.0, fast_wave * 10.0, slow_wave * 4.0),
            );
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y + fast_wave.abs() * 0.035, 0.0),
                Vector3::new(-4.0, fast_wave * 12.0, slow_wave * 9.0),
            );
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(-40.0 + fast_wave * 34.0, 0.0, -28.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(40.0 + fast_wave * 34.0, 0.0, 28.0),
            );
        }
        CharacterClipPreviewKind::Applause | CharacterClipPreviewKind::Craft => {
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.02),
                Vector3::new(-46.0, 0.0, 32.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.02),
                Vector3::new(-46.0, 0.0, -32.0),
            );
            set_node_transform(
                &mut visual.hand_l,
                Vector3::new(
                    -0.10 - fast_wave.abs() * 0.03,
                    CHARACTER_FOREARM_Y - 0.12,
                    -0.18,
                ),
                Vector3::new(-58.0, 0.0, 48.0),
            );
            set_node_transform(
                &mut visual.hand_r,
                Vector3::new(
                    0.10 + fast_wave.abs() * 0.03,
                    CHARACTER_FOREARM_Y - 0.12,
                    -0.18,
                ),
                Vector3::new(-58.0, 0.0, -48.0),
            );
        }
        CharacterClipPreviewKind::Work | CharacterClipPreviewKind::Watering => {
            let swing = -48.0 + fast_wave * 44.0;
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y, -0.02),
                Vector3::new(12.0 + fast_wave.abs() * 4.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.03),
                Vector3::new(swing, 0.0, 10.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y, -0.04),
                Vector3::new(swing - 18.0, 0.0, 10.0),
            );
        }
        CharacterClipPreviewKind::Fishing => {
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y, -0.03),
                Vector3::new(7.0, slow_wave * 3.0, 0.0),
            );
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.04),
                Vector3::new(-34.0 + fast_wave * 5.0, 0.0, 16.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.04),
                Vector3::new(-34.0 - fast_wave * 5.0, 0.0, -16.0),
            );
        }
        CharacterClipPreviewKind::Consume | CharacterClipPreviewKind::Camera => {
            set_node_transform(
                &mut visual.head,
                Vector3::new(0.0, CHARACTER_HEAD_Y, 0.0),
                Vector3::new(-6.0 + fast_wave.abs() * 4.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(-96.0, 0.0, -18.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(
                    CHARACTER_FOREARM_X * 0.72,
                    CHARACTER_FOREARM_Y + 0.10,
                    -0.08,
                ),
                Vector3::new(-118.0, 0.0, -24.0),
            );
            set_node_transform(
                &mut visual.hand_r,
                Vector3::new(
                    CHARACTER_FOREARM_X * 0.55,
                    CHARACTER_FOREARM_Y + 0.12,
                    -0.13,
                ),
                Vector3::new(-122.0, 0.0, -30.0),
            );
        }
        CharacterClipPreviewKind::Sit => {
            set_node_transform(
                &mut visual.head,
                Vector3::new(0.0, CHARACTER_HEAD_Y - 0.32, 0.0),
                Vector3::new(3.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y - 0.30, 0.0),
                Vector3::new(6.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.waist,
                Vector3::new(0.0, CHARACTER_BELT_Y - 0.26, 0.0),
                Vector3::new(6.0, 0.0, 0.0),
            );
            set_node_transform(
                &mut visual.l_thigh,
                Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y - 0.04, -0.10),
                Vector3::new(78.0, 0.0, -4.0),
            );
            set_node_transform(
                &mut visual.r_thigh,
                Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y - 0.04, -0.10),
                Vector3::new(78.0, 0.0, 4.0),
            );
        }
        CharacterClipPreviewKind::Flex => {
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + 0.03, 0.0),
                Vector3::new(-82.0, 0.0, -54.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + 0.03, 0.0),
                Vector3::new(-82.0, 0.0, 54.0),
            );
            set_node_transform(
                &mut visual.l_forearm,
                Vector3::new(-CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y + 0.12, 0.0),
                Vector3::new(-112.0, 0.0, -72.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y + 0.12, 0.0),
                Vector3::new(-112.0, 0.0, 72.0),
            );
        }
        CharacterClipPreviewKind::Laugh | CharacterClipPreviewKind::Sick => {
            set_node_transform(
                &mut visual.head,
                Vector3::new(0.0, CHARACTER_HEAD_Y + slow_wave.abs() * 0.02, 0.0),
                Vector3::new(
                    if kind == CharacterClipPreviewKind::Sick {
                        18.0
                    } else {
                        -14.0
                    },
                    slow_wave * 5.0,
                    fast_wave * 2.0,
                ),
            );
            set_node_transform(
                &mut visual.chest,
                Vector3::new(0.0, CHARACTER_CHEST_Y - slow_wave.abs() * 0.012, 0.0),
                Vector3::new(
                    if kind == CharacterClipPreviewKind::Sick {
                        16.0
                    } else {
                        -6.0
                    },
                    0.0,
                    slow_wave * 4.0,
                ),
            );
        }
        CharacterClipPreviewKind::Point => {
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, -0.05),
                Vector3::new(-88.0, 0.0, -16.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y + 0.02, -0.14),
                Vector3::new(-102.0, 0.0, -18.0),
            );
            set_node_transform(
                &mut visual.hand_r,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y - 0.10, -0.24),
                Vector3::new(-104.0, 0.0, -18.0),
            );
        }
        CharacterClipPreviewKind::Rock | CharacterClipPreviewKind::Item => {
            set_node_transform(
                &mut visual.chest,
                Vector3::new(slow_wave * 0.025, CHARACTER_CHEST_Y, 0.0),
                Vector3::new(0.0, slow_wave * 8.0, fast_wave * 5.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(-18.0 + fast_wave * 18.0, 0.0, 10.0),
            );
        }
        CharacterClipPreviewKind::TPose => {
            set_node_transform(
                &mut visual.l_arm,
                Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(0.0, 0.0, -86.0),
            );
            set_node_transform(
                &mut visual.l_forearm,
                Vector3::new(-CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y, 0.0),
                Vector3::new(0.0, 0.0, -88.0),
            );
            set_node_transform(
                &mut visual.hand_l,
                Vector3::new(-CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y - 0.22, 0.0),
                Vector3::new(0.0, 0.0, -88.0),
            );
            set_node_transform(
                &mut visual.r_arm,
                Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
                Vector3::new(0.0, 0.0, 86.0),
            );
            set_node_transform(
                &mut visual.r_forearm,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y, 0.0),
                Vector3::new(0.0, 0.0, 88.0),
            );
            set_node_transform(
                &mut visual.hand_r,
                Vector3::new(CHARACTER_FOREARM_X, CHARACTER_FOREARM_Y - 0.22, 0.0),
                Vector3::new(0.0, 0.0, 88.0),
            );
        }
        CharacterClipPreviewKind::Idle
        | CharacterClipPreviewKind::Walk
        | CharacterClipPreviewKind::Run
        | CharacterClipPreviewKind::Jump
        | CharacterClipPreviewKind::Fallback => {}
    }
}

fn apply_voxel_idle_pose(visual: &mut VoxelCharacterVisual, animation_time_sec: f32) {
    let wave = (animation_time_sec * CHARACTER_IDLE_ANIMATION_RATE).sin();
    let bob = wave * 0.012;

    set_node_transform(
        &mut visual.head,
        Vector3::new(0.0, CHARACTER_HEAD_Y + bob * 0.5, 0.0),
        Vector3::new(wave * 1.0, wave * 1.5, 0.0),
    );
    set_node_transform(
        &mut visual.chest,
        Vector3::new(0.0, CHARACTER_CHEST_Y + bob, 0.0),
        Vector3::new(wave * 1.4, 0.0, wave * 0.6),
    );
    set_node_transform(
        &mut visual.waist,
        Vector3::new(0.0, CHARACTER_BELT_Y + bob * 0.5, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.l_arm,
        Vector3::new(-CHARACTER_ARM_REST_X, CHARACTER_ARM_REST_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES + wave * 1.0),
    );
    set_node_transform(
        &mut visual.l_forearm,
        Vector3::new(
            -CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + bob,
            0.0,
        ),
        Vector3::new(0.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES + wave * 1.0),
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(-CHARACTER_HAND_REST_X, CHARACTER_HAND_REST_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES + wave * 1.0),
    );
    set_node_transform(
        &mut visual.r_arm,
        Vector3::new(CHARACTER_ARM_REST_X, CHARACTER_ARM_REST_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES - wave * 1.0),
    );
    set_node_transform(
        &mut visual.r_forearm,
        Vector3::new(
            CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + bob,
            0.0,
        ),
        Vector3::new(0.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES - wave * 1.0),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(CHARACTER_HAND_REST_X, CHARACTER_HAND_REST_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES - wave * 1.0),
    );
    set_node_transform(
        &mut visual.l_thigh,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.l_leg,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_FOOT_Y, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.r_thigh,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.r_leg,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_FOOT_Y, 0.0),
        Vector3::ZERO,
    );
}

fn apply_voxel_run_pose(visual: &mut VoxelCharacterVisual, animation_time_sec: f32) {
    let cycle = animation_time_sec * CHARACTER_RUN_ANIMATION_RATE;
    let swing = cycle.sin();
    let counter_swing = -swing;
    let bob = swing.abs() * 0.045;

    set_node_transform(
        &mut visual.head,
        Vector3::new(0.0, CHARACTER_HEAD_Y + bob * 0.35, -0.02),
        Vector3::new(3.0, counter_swing * 2.0, 0.0),
    );
    set_node_transform(
        &mut visual.chest,
        Vector3::new(0.0, CHARACTER_CHEST_Y + bob, -0.02),
        Vector3::new(-7.0, 0.0, counter_swing * 1.8),
    );
    set_node_transform(
        &mut visual.waist,
        Vector3::new(0.0, CHARACTER_BELT_Y + bob * 0.6, 0.0),
        Vector3::new(-3.0, 0.0, swing * 1.4),
    );
    set_node_transform(
        &mut visual.l_arm,
        Vector3::new(-CHARACTER_ARM_REST_X, CHARACTER_ARM_REST_Y + bob, 0.0),
        Vector3::new(
            counter_swing * 34.0,
            0.0,
            CHARACTER_LEFT_ARM_REST_Z_DEGREES - 2.0,
        ),
    );
    set_node_transform(
        &mut visual.l_forearm,
        Vector3::new(
            -CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + bob,
            0.0,
        ),
        Vector3::new(
            counter_swing * 40.0,
            0.0,
            CHARACTER_LEFT_ARM_REST_Z_DEGREES - 2.0,
        ),
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(-CHARACTER_HAND_REST_X, CHARACTER_HAND_REST_Y + bob, 0.0),
        Vector3::new(
            counter_swing * 44.0,
            0.0,
            CHARACTER_LEFT_ARM_REST_Z_DEGREES - 2.0,
        ),
    );
    set_node_transform(
        &mut visual.r_arm,
        Vector3::new(CHARACTER_ARM_REST_X, CHARACTER_ARM_REST_Y + bob, 0.0),
        Vector3::new(swing * 34.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 2.0),
    );
    set_node_transform(
        &mut visual.r_forearm,
        Vector3::new(
            CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + bob,
            0.0,
        ),
        Vector3::new(swing * 40.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 2.0),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(CHARACTER_HAND_REST_X, CHARACTER_HAND_REST_Y + bob, 0.0),
        Vector3::new(swing * 44.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 2.0),
    );
    set_node_transform(
        &mut visual.l_thigh,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23 + bob * 0.25, 0.0),
        Vector3::new(swing * 30.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.l_leg,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y + bob * 0.25, 0.0),
        Vector3::new(swing * 34.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_FOOT_Y + bob * 0.25, 0.0),
        Vector3::new(swing * 34.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.r_thigh,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23 + bob * 0.25, 0.0),
        Vector3::new(counter_swing * 30.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.r_leg,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y + bob * 0.25, 0.0),
        Vector3::new(counter_swing * 34.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_FOOT_Y + bob * 0.25, 0.0),
        Vector3::new(counter_swing * 34.0, 0.0, 0.0),
    );
}

fn apply_voxel_jump_pose(visual: &mut VoxelCharacterVisual, animation_time_sec: f32) {
    let float = (animation_time_sec * CHARACTER_JUMP_ANIMATION_RATE).sin() * 0.01;

    set_node_transform(
        &mut visual.head,
        Vector3::new(0.0, CHARACTER_HEAD_Y + 0.02 + float, 0.0),
        Vector3::new(-2.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.chest,
        Vector3::new(0.0, CHARACTER_CHEST_Y + 0.03 + float, 0.0),
        Vector3::new(-4.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.waist,
        Vector3::new(0.0, CHARACTER_BELT_Y + 0.02 + float, 0.0),
        Vector3::new(3.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.l_arm,
        Vector3::new(
            -CHARACTER_ARM_REST_X,
            CHARACTER_ARM_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-26.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES - 6.0),
    );
    set_node_transform(
        &mut visual.l_forearm,
        Vector3::new(
            -CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-32.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES - 6.0),
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(
            -CHARACTER_HAND_REST_X,
            CHARACTER_HAND_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-34.0, 0.0, CHARACTER_LEFT_ARM_REST_Z_DEGREES - 6.0),
    );
    set_node_transform(
        &mut visual.r_arm,
        Vector3::new(
            CHARACTER_ARM_REST_X,
            CHARACTER_ARM_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-26.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 6.0),
    );
    set_node_transform(
        &mut visual.r_forearm,
        Vector3::new(
            CHARACTER_FOREARM_REST_X,
            CHARACTER_FOREARM_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-32.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 6.0),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(
            CHARACTER_HAND_REST_X,
            CHARACTER_HAND_REST_Y + 0.02 + float,
            0.0,
        ),
        Vector3::new(-34.0, 0.0, CHARACTER_RIGHT_ARM_REST_Z_DEGREES + 6.0),
    );
    set_node_transform(
        &mut visual.l_thigh,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23 + float, 0.0),
        Vector3::new(14.0, 0.0, -2.0),
    );
    set_node_transform(
        &mut visual.l_leg,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y + float, 0.0),
        Vector3::new(18.0, 0.0, -2.0),
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_FOOT_Y + float, 0.0),
        Vector3::new(18.0, 0.0, -2.0),
    );
    set_node_transform(
        &mut visual.r_thigh,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + 0.23 + float, 0.0),
        Vector3::new(14.0, 0.0, 2.0),
    );
    set_node_transform(
        &mut visual.r_leg,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_LOWER_LEG_Y + float, 0.0),
        Vector3::new(18.0, 0.0, 2.0),
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_FOOT_Y + float, 0.0),
        Vector3::new(18.0, 0.0, 2.0),
    );
}

fn set_node_transform(node: &mut Gd<Node3D>, position: Vector3, rotation_degrees: Vector3) {
    node.set_position(position);
    node.set_rotation_degrees(rotation_degrees);
    node.set_scale(Vector3::ONE);
}

fn create_selection_outline() -> Gd<MeshInstance3D> {
    let min = -SELECTION_OUTLINE_PADDING;
    let max = 1.0 + SELECTION_OUTLINE_PADDING;
    let corners = [
        Vector3::new(min, min, min),
        Vector3::new(max, min, min),
        Vector3::new(max, min, max),
        Vector3::new(min, min, max),
        Vector3::new(min, max, min),
        Vector3::new(max, max, min),
        Vector3::new(max, max, max),
        Vector3::new(min, max, max),
    ];
    let edges = [
        (0, 1),
        (1, 2),
        (2, 3),
        (3, 0),
        (4, 5),
        (5, 6),
        (6, 7),
        (7, 4),
        (0, 4),
        (1, 5),
        (2, 6),
        (3, 7),
    ];

    let mut vertices = PackedVector3Array::new();
    for (a, b) in edges {
        vertices.push(corners[a]);
        vertices.push(corners[b]);
    }

    let mut arrays = Array::new();
    arrays.resize(13, &Variant::nil());
    arrays.set(0, &vertices.to_variant());

    let mut mesh = ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::LINES, &arrays);

    let mut material = StandardMaterial3D::new_gd();
    material.set_albedo(Color::from_rgb(1.0, 1.0, 1.0));
    material.set_shading_mode(base_material_3d::ShadingMode::UNSHADED);

    let mut outline = MeshInstance3D::new_alloc();
    outline.set_name(&StringName::from("BlockSelectionOutline"));
    outline.set_as_top_level(true);
    outline.set_mesh(&mesh.upcast::<godot::classes::Mesh>());
    outline.set_material_override(&material.upcast::<godot::classes::Material>());
    outline
}

fn visual_smoke_player_input_disabled() -> bool {
    static DISABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *DISABLED.get_or_init(|| {
        std::env::var(VISUAL_SMOKE_DISABLE_PLAYER_INPUT_ENV).is_ok_and(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
    })
}

#[godot_api]
impl Player {
    #[func]
    fn is_fly_mode_enabled(&self) -> bool {
        self.fly_mode
    }

    #[func]
    fn is_third_person_camera_enabled(&self) -> bool {
        self.third_person_camera
    }

    #[func]
    fn is_gameplay_input_blocked(&self) -> bool {
        self.gameplay_input_blocked
    }

    #[func]
    fn set_gameplay_input_blocked(&mut self, blocked: bool) {
        self.gameplay_input_blocked = blocked;
        if blocked {
            Self::release_mouse();
        }
    }

    #[func]
    fn character_appearance_label(&self) -> GString {
        let label = crate::biomes_avatar::avatar_appearance_label(&self.character_appearance);
        label.as_str().into()
    }

    #[func]
    fn character_creator_category_count(&self) -> i32 {
        crate::biomes_avatar::avatar_creator_category_count() as i32
    }

    #[func]
    fn character_creator_category_key(&self, index: i32) -> GString {
        if index < 0 {
            return GString::new();
        }
        crate::biomes_avatar::avatar_creator_category_key(index as usize)
            .unwrap_or_default()
            .into()
    }

    #[func]
    fn character_creator_category_label(&self, index: i32) -> GString {
        if index < 0 {
            return GString::new();
        }
        crate::biomes_avatar::avatar_creator_category_label(index as usize)
            .unwrap_or_default()
            .into()
    }

    #[func]
    fn character_creator_option_count(&self, category_index: i32) -> i32 {
        if category_index < 0 {
            return 0;
        }
        crate::biomes_avatar::avatar_creator_option_count(category_index as usize) as i32
    }

    #[func]
    fn character_creator_option_label(&self, category_index: i32, option_index: i32) -> GString {
        if category_index < 0 || option_index < 0 {
            return GString::new();
        }
        let label = crate::biomes_avatar::avatar_creator_option_label(
            category_index as usize,
            option_index as usize,
        )
        .unwrap_or_default();
        label.as_str().into()
    }

    #[func]
    fn character_creator_option_color(&self, category_index: i32, option_index: i32) -> Color {
        if category_index < 0 || option_index < 0 {
            return Color::from_rgba(0.0, 0.0, 0.0, 0.0);
        }
        crate::biomes_avatar::avatar_creator_option_color(
            category_index as usize,
            option_index as usize,
        )
        .unwrap_or(Color::from_rgba(0.0, 0.0, 0.0, 0.0))
    }

    #[func]
    fn character_creator_option_thumbnail_path(
        &self,
        category_index: i32,
        option_index: i32,
    ) -> GString {
        if category_index < 0 || option_index < 0 {
            return GString::new();
        }
        crate::biomes_avatar::avatar_creator_option_thumbnail_path(
            category_index as usize,
            option_index as usize,
        )
        .map(|path| path.as_str().into())
        .unwrap_or_else(GString::new)
    }

    #[func]
    fn character_creator_selected_option_index(&self, category_index: i32) -> i32 {
        if category_index < 0 {
            return -1;
        }
        crate::biomes_avatar::avatar_creator_selected_option_index(
            &self.character_appearance,
            category_index as usize,
        )
    }

    #[func]
    fn select_character_creator_option(&mut self, category_index: i32, option_index: i32) {
        if category_index < 0 || option_index < 0 {
            return;
        }
        if crate::biomes_avatar::avatar_creator_select_option(
            &mut self.character_appearance,
            category_index as usize,
            option_index as usize,
        ) {
            self.rebuild_character_visual();
            self.emit_debug_log(&format!(
                "Character appearance: {}",
                crate::biomes_avatar::avatar_appearance_label(&self.character_appearance)
            ));
        }
    }

    #[func]
    fn character_animation_clip_count(&self) -> i32 {
        self.character_animation_catalog
            .as_ref()
            .map(|catalog| catalog.clip_count() as i32)
            .unwrap_or(0)
    }

    #[func]
    fn character_animation_clip_name(&self, index: i32) -> GString {
        if index < 0 {
            return GString::new();
        }
        self.character_animation_catalog
            .as_ref()
            .and_then(|catalog| catalog.clips().get(index as usize))
            .map(|clip| clip.file_animation_name.as_str().into())
            .unwrap_or_else(GString::new)
    }

    #[func]
    fn character_animation_clip_duration(&self, index: i32) -> f32 {
        if index < 0 {
            return 0.0;
        }
        self.character_animation_catalog
            .as_ref()
            .and_then(|catalog| catalog.clips().get(index as usize))
            .map(|clip| clip.duration_sec)
            .unwrap_or(0.0)
    }

    #[func]
    fn selected_character_animation_clip_index(&self) -> i32 {
        self.character_preview_animation_index as i32
    }

    #[func]
    fn selected_character_animation_clip_name(&self) -> GString {
        self.selected_character_animation_clip_name_str()
            .map(Into::into)
            .unwrap_or_else(GString::new)
    }

    #[func]
    fn is_character_animation_preview_enabled(&self) -> bool {
        self.character_preview_animation_enabled
    }

    #[func]
    fn set_character_animation_preview_enabled(&mut self, enabled: bool) {
        if enabled
            && self
                .character_animation_catalog
                .as_ref()
                .is_some_and(|catalog| catalog.clip_count() > 0)
        {
            self.character_preview_animation_enabled = true;
            self.character_animation_time_sec = 0.0;
            self.set_third_person_camera(true);
        } else {
            self.character_preview_animation_enabled = false;
        }
    }

    #[func]
    fn select_character_animation_clip(&mut self, index: i32) {
        if index < 0 {
            return;
        }
        self.set_character_preview_animation_index(index as usize, true);
    }

    #[func]
    fn selected_character_animation_clip_duration(&self) -> f32 {
        self.selected_character_animation_clip_duration_sec()
    }

    #[func]
    fn selected_character_animation_sample_track_count(&self) -> i32 {
        self.character_animation_catalog
            .as_ref()
            .and_then(|catalog| {
                self.selected_character_animation_clip_name_str()
                    .and_then(|name| catalog.clip_by_file_animation_name(name))
            })
            .map(|clip| clip.track_count() as i32)
            .unwrap_or(0)
    }

    #[func]
    fn set_third_person_camera_enabled(&mut self, enabled: bool) {
        self.set_third_person_camera(enabled);
    }

    #[signal]
    fn block_broken(x: i32, y: i32, z: i32);

    #[signal]
    fn block_placed(x: i32, y: i32, z: i32, block_id: i32);

    #[signal]
    fn hotbar_selected(slot: i32, block_id: i32);

    #[signal]
    fn tool_slot_selected(slot: i32);

    #[signal]
    fn debug_log(message: GString);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn initial_hotbar_inventory_contains_placeable_blocks() {
        let hotbar = initial_hotbar_inventory();

        assert_eq!(hotbar.len(), PLAYER_HOTBAR_SLOTS);
        for (slot, block_id) in crate::blocks::PLACEABLE_BLOCKS.iter().copied().enumerate() {
            assert_eq!(hotbar[slot].block_id, block_id);
            assert_eq!(hotbar[slot].count, CREATIVE_HOTBAR_STACK_COUNT);
            assert!(inventory_slot_can_place(&hotbar[slot]));
        }
    }

    #[test]
    fn inventory_slot_can_place_requires_count_and_placeable_block() {
        assert!(!inventory_slot_can_place(&InventorySlot {
            block_id: crate::blocks::STONE,
            count: 0,
        }));
        assert!(!inventory_slot_can_place(&InventorySlot {
            block_id: crate::blocks::AIR,
            count: CREATIVE_HOTBAR_STACK_COUNT,
        }));
        assert!(inventory_slot_can_place(&InventorySlot {
            block_id: crate::blocks::STONE,
            count: 1,
        }));
    }

    #[test]
    fn inventory_has_placeable_block_accepts_only_available_hotbar_blocks() {
        let hotbar = initial_hotbar_inventory();

        assert!(inventory_has_placeable_block(&hotbar, crate::blocks::STONE));
        assert!(inventory_has_placeable_block(
            &hotbar,
            crate::blocks::LEAVES
        ));
        assert!(!inventory_has_placeable_block(&hotbar, crate::blocks::AIR));
        assert!(!inventory_has_placeable_block(&hotbar, u32::MAX));
    }

    #[test]
    fn hotbar_key_mapping_is_bounded_to_inventory_slots() {
        for slot in 0..PLAYER_HOTBAR_SLOTS {
            assert!(hotbar_key_for_slot(slot).is_some());
        }
        assert!(hotbar_key_for_slot(PLAYER_HOTBAR_SLOTS).is_none());
    }

    #[test]
    fn tool_key_mapping_is_bounded_to_tool_slots() {
        assert_eq!(tool_key_for_slot(0), Some(Key::KEY_6));
        assert_eq!(tool_key_for_slot(1), Some(Key::KEY_7));
        assert_eq!(tool_key_for_slot(2), Some(Key::KEY_8));
        assert_eq!(tool_key_for_slot(3), Some(Key::KEY_9));
        assert_eq!(tool_key_for_slot(PLAYER_TOOL_SLOTS), None);
    }

    #[test]
    fn third_person_raycast_extends_reach_by_camera_offset() {
        assert_eq!(block_raycast_target(false), Vector3::new(0.0, 0.0, -5.0));
        assert_eq!(block_raycast_target(true), Vector3::new(0.0, 0.0, -9.5));
    }

    #[test]
    fn camera_positions_are_mode_specific() {
        assert_eq!(
            first_person_camera_position(),
            Vector3::new(0.0, PLAYER_EYE_HEIGHT_METERS, 0.0)
        );
        assert_eq!(
            third_person_camera_position(),
            Vector3::new(
                0.0,
                THIRD_PERSON_CAMERA_HEIGHT,
                THIRD_PERSON_CAMERA_DISTANCE
            )
        );
    }

    #[test]
    fn character_visual_scale_tracks_player_height_and_eye_height() {
        let head_top_y =
            CHARACTER_HEAD_Y + CHARACTER_HEAD_VOXEL_HEIGHT * CHARACTER_VOXEL_SCALE * 0.5;
        let head_bottom_y =
            CHARACTER_HEAD_Y - CHARACTER_HEAD_VOXEL_HEIGHT * CHARACTER_VOXEL_SCALE * 0.5;
        let chest_top_y = CHARACTER_CHEST_Y + 8.5 * CHARACTER_VOXEL_SCALE;

        assert!(
            (head_top_y - (CHARACTER_VISUAL_HEIGHT_METERS - CHARACTER_HEAD_NECK_OVERLAP)).abs()
                < 0.001
        );
        assert!(head_bottom_y < chest_top_y);
        assert!(head_top_y > PLAYER_HEIGHT_METERS);
        assert!(CHARACTER_VISUAL_HEIGHT_METERS > PLAYER_HEIGHT_METERS);
        assert_eq!(first_person_camera_position().y, PLAYER_EYE_HEIGHT_METERS);
    }

    #[test]
    fn character_rest_pose_keeps_arm_segments_proportional() {
        assert!(CHARACTER_ARM_REST_X < CHARACTER_LIMB_X);
        assert!(CHARACTER_ARM_REST_X > 7.0 * CHARACTER_VOXEL_SCALE);
        assert!(CHARACTER_FOREARM_REST_X >= CHARACTER_ARM_REST_X);
        assert!(CHARACTER_FOREARM_REST_X <= CHARACTER_ARM_REST_X + CHARACTER_VOXEL_SCALE);
        assert!(CHARACTER_HAND_REST_X >= CHARACTER_FOREARM_REST_X);
        assert!(CHARACTER_HAND_REST_X <= CHARACTER_FOREARM_REST_X + CHARACTER_VOXEL_SCALE);
        assert!(CHARACTER_FOREARM_REST_Y < CHARACTER_ARM_REST_Y);
        assert!(CHARACTER_HAND_REST_Y < CHARACTER_FOREARM_REST_Y);
        assert!(CHARACTER_LEFT_ARM_REST_Z_DEGREES < -80.0);
        assert!(CHARACTER_RIGHT_ARM_REST_Z_DEGREES > 80.0);
    }

    #[test]
    fn biomes_joint_mesh_overlap_scales_cover_rigid_limb_gaps() {
        let arm_scale = Vector3::new(CHARACTER_ARM_MESH_OVERLAP_SCALE, 1.0, 1.0);
        let hand_scale = Vector3::new(CHARACTER_HAND_MESH_OVERLAP_SCALE, 1.0, 1.0);
        let leg_scale = Vector3::new(1.0, CHARACTER_LEG_MESH_OVERLAP_SCALE, 1.0);
        let foot_scale = Vector3::new(1.0, CHARACTER_FOOT_MESH_OVERLAP_SCALE, 1.0);

        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LArm),
            arm_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RArm),
            arm_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LForearm),
            arm_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RForearm),
            arm_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LHand),
            hand_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RHand),
            hand_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LThigh),
            leg_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RThigh),
            leg_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LLeg),
            leg_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RLeg),
            leg_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::LFoot),
            foot_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::RFoot),
            foot_scale
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::Chest),
            Vector3::ONE
        );
        assert_eq!(
            biomes_joint_mesh_overlap_scale(BiomesAvatarJoint::Head),
            Vector3::ONE
        );
    }

    #[test]
    fn biomes_joint_mesh_stitch_offsets_keep_leg_chain_aligned() {
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LArm),
            Vector3::new(CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LForearm),
            Vector3::new(CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RArm),
            Vector3::new(-CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RForearm),
            Vector3::new(-CHARACTER_ARM_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LThigh),
            Vector3::new(CHARACTER_LEFT_LEG_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RThigh),
            Vector3::ZERO
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LLeg),
            Vector3::new(CHARACTER_LEFT_LEG_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RLeg),
            Vector3::ZERO
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LFoot),
            Vector3::new(CHARACTER_LEFT_FOOT_MESH_STITCH_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RFoot),
            Vector3::ZERO
        );
        assert_eq!(
            biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::Chest),
            Vector3::ZERO
        );
    }

    #[test]
    fn biomes_left_leg_mesh_stitch_pulls_visible_mesh_toward_torso() {
        let left_bind = biomes_avatar_joint_bind_position(BiomesAvatarJoint::LThigh);
        let left_stitched = left_bind + biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::LThigh);
        let right_bind = biomes_avatar_joint_bind_position(BiomesAvatarJoint::RThigh);
        let right_stitched =
            right_bind + biomes_joint_mesh_stitch_offset(BiomesAvatarJoint::RThigh);

        assert!(left_bind.x < 0.0);
        assert!(left_stitched.x > left_bind.x);
        assert_eq!(right_stitched, right_bind);
    }

    #[test]
    fn biomes_leg_visual_joints_keep_source_skeleton_sides() {
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::LThigh),
            BiomesAvatarJoint::LThigh
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::LLeg),
            BiomesAvatarJoint::LLeg
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::LFoot),
            BiomesAvatarJoint::LFoot
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::RThigh),
            BiomesAvatarJoint::RThigh
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::RLeg),
            BiomesAvatarJoint::RLeg
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::RFoot),
            BiomesAvatarJoint::RFoot
        );
        assert_eq!(
            biomes_skeleton_joint_for_visual_joint(BiomesAvatarJoint::LArm),
            BiomesAvatarJoint::LArm
        );
        assert_eq!(
            biomes_visual_joint_for_skeleton_joint(BiomesAvatarJoint::RThigh),
            BiomesAvatarJoint::RThigh
        );
    }

    #[test]
    fn biomes_leg_visual_rest_poses_match_vox_bind_sides() {
        let animations = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/animations/character-animations.gltf");
        let gltf = std::fs::read_to_string(&animations)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", animations.display()));
        let catalog = crate::biomes_avatar::parse_biomes_animation_catalog(&gltf)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", animations.display()));
        let rest_poses = catalog.joint_rest_poses();
        let visual_left_rest =
            biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::LThigh).unwrap();
        let visual_right_rest =
            biomes_visual_joint_rest_pose(&rest_poses, BiomesAvatarJoint::RThigh).unwrap();

        assert!(biomes_pose_translation_to_godot(visual_left_rest.global.translation).x < 0.0);
        assert!(biomes_avatar_joint_bind_position(BiomesAvatarJoint::LThigh).x < 0.0);
        assert!(biomes_pose_translation_to_godot(visual_right_rest.global.translation).x > 0.0);
        assert!(biomes_avatar_joint_bind_position(BiomesAvatarJoint::RThigh).x > 0.0);
    }

    #[test]
    fn biomes_joint_root_weld_offsets_pull_root_limb_chains_toward_torso() {
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::LArm),
            Vector3::new(CHARACTER_ARM_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::RArm),
            Vector3::new(-CHARACTER_ARM_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::LThigh),
            Vector3::new(CHARACTER_LEFT_LEG_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::RThigh),
            Vector3::new(-CHARACTER_RIGHT_LEG_ROOT_WELD_INSET_METERS, 0.0, 0.0)
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::LForearm),
            Vector3::ZERO
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::LFoot),
            Vector3::ZERO
        );
        assert_eq!(
            biomes_joint_root_weld_offset(BiomesAvatarJoint::Chest),
            Vector3::ZERO
        );
    }

    #[test]
    fn third_person_character_root_faces_away_from_camera() {
        assert_eq!(CHARACTER_ROOT_YAW_DEGREES, 0.0);
    }

    #[test]
    fn character_motion_state_follows_velocity() {
        assert_eq!(
            character_motion_state_for_velocity(Vector3::ZERO, false, false, Vector3::ZERO, true),
            CharacterMotionState::Idle
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(0.0, 0.0, -1.0),
                false,
                false,
                Vector3::new(0.0, 0.0, 5.0),
                true,
            ),
            CharacterMotionState::WalkForward
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(0.0, 0.0, -1.0),
                true,
                false,
                Vector3::new(0.0, 0.0, 5.0),
                true,
            ),
            CharacterMotionState::RunForward
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(0.0, 0.0, 1.0),
                false,
                false,
                Vector3::new(0.0, 0.0, 5.0),
                true,
            ),
            CharacterMotionState::RunBackward
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(-1.0, 0.0, 0.0),
                false,
                false,
                Vector3::new(5.0, 0.0, 0.0),
                true,
            ),
            CharacterMotionState::StrafeLeftSlow
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(1.0, 0.0, 0.0),
                true,
                false,
                Vector3::new(5.0, 0.0, 0.0),
                true,
            ),
            CharacterMotionState::StrafeRightFast
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::ZERO,
                false,
                false,
                Vector3::new(0.0, 2.0, 0.0),
                false,
            ),
            CharacterMotionState::Jump
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::ZERO,
                false,
                false,
                Vector3::new(0.0, -2.0, 0.0),
                false,
            ),
            CharacterMotionState::Fall
        );
        assert_eq!(
            character_motion_state_for_velocity(Vector3::ZERO, false, true, Vector3::ZERO, false,),
            CharacterMotionState::FlyIdle
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(0.0, 0.0, -1.0),
                false,
                true,
                Vector3::new(0.0, 0.0, 5.0),
                false,
            ),
            CharacterMotionState::FlyForwards
        );
        assert_eq!(
            character_motion_state_for_velocity(
                Vector3::new(0.0, 1.0, 0.0),
                false,
                true,
                Vector3::new(0.0, 5.0, 0.0),
                false,
            ),
            CharacterMotionState::FlyForwards
        );
    }

    #[test]
    fn biomes_clip_preview_kind_covers_all_source_animation_names() {
        assert_eq!(
            character_clip_preview_kind("Craft"),
            CharacterClipPreviewKind::Craft
        );
        assert_eq!(
            character_clip_preview_kind("FishingReel"),
            CharacterClipPreviewKind::Fishing
        );
        assert_eq!(
            character_clip_preview_kind("TPose"),
            CharacterClipPreviewKind::TPose
        );

        for clip_name in crate::biomes_avatar::BIOMES_CHARACTER_ANIMATION_CLIP_NAMES {
            assert_ne!(
                character_clip_preview_kind(clip_name),
                CharacterClipPreviewKind::Fallback,
                "{clip_name} should have a character preview kind"
            );
        }
    }

    #[test]
    fn voxel_character_visual_name_is_stable_for_godot_smoke() {
        assert_eq!(PLAYER_CHARACTER_VISUAL_NAME, "PlayerVoxelCharacter");
    }

    #[test]
    fn voxel_character_animation_time_wraps_and_ignores_invalid_delta() {
        assert_eq!(next_character_animation_time(1.0, 0.0), 1.0);
        assert_eq!(next_character_animation_time(1.0, f32::NAN), 1.0);
        assert_eq!(next_character_animation_time(f32::NAN, 1.0), 0.0);
        assert_eq!(
            next_character_animation_time(CHARACTER_ANIMATION_WRAP_SECONDS - 0.25, 0.5),
            0.25
        );
    }

    #[test]
    fn character_motion_states_select_biomes_source_animation_clips() {
        let cases = [
            (CharacterMotionState::Idle, "Idle"),
            (CharacterMotionState::WalkForward, "Walking"),
            (CharacterMotionState::RunForward, "Running"),
            (CharacterMotionState::RunBackward, "RunningBackward"),
            (CharacterMotionState::StrafeLeftSlow, "StrafeLeftWalking"),
            (CharacterMotionState::StrafeLeftFast, "StrafeLeftRunning"),
            (CharacterMotionState::StrafeRightSlow, "StrafeRightWalking"),
            (CharacterMotionState::StrafeRightFast, "StrafeRightRunning"),
            (CharacterMotionState::Jump, "Jump"),
            (CharacterMotionState::Fall, "Fall"),
            (CharacterMotionState::FlyIdle, "SwimmingIdle"),
            (CharacterMotionState::FlyForwards, "SwimmingForward"),
            (CharacterMotionState::FlyBackwards, "SwimmingBackward"),
        ];
        for (state, clip_name) in cases {
            assert_eq!(
                character_motion_biomes_animation(state).file_animation_name(),
                clip_name
            );
        }
    }

    #[test]
    fn character_action_animation_duration_uses_bounded_fallback_without_catalog() {
        assert_eq!(
            character_action_animation_duration(None, BiomesPlayerAnimation::DiggingHand),
            CHARACTER_ACTION_FALLBACK_SECONDS
        );
    }

    #[test]
    fn biomes_pose_retarget_converts_animation_axes_to_godot_axes() {
        let scale =
            CHARACTER_VOXEL_SCALE / crate::biomes_avatar::BIOMES_ANIMATION_VOX_TO_POSE_SCALE;
        assert_eq!(
            biomes_pose_translation_delta_to_godot([0.0, 1.0, 0.0]),
            Vector3::new(0.0, scale, 0.0)
        );
        assert_eq!(
            biomes_pose_translation_delta_to_godot([1.0, 0.0, 0.0]),
            Vector3::new(0.0, 0.0, -scale)
        );
        assert_eq!(
            biomes_pose_translation_delta_to_godot([0.0, 0.0, 1.0]),
            Vector3::new(scale, 0.0, 0.0)
        );

        let rotation = biomes_pose_rotation_delta_to_godot([0.0, 0.0, 0.0, 1.0]);
        let length = (rotation[0] * rotation[0]
            + rotation[1] * rotation[1]
            + rotation[2] * rotation[2]
            + rotation[3] * rotation[3])
            .sqrt();
        assert!((length - 1.0).abs() < 0.001);
    }

    #[test]
    fn biomes_sampled_joint_positions_stay_bound_for_modular_skin() {
        let joint = BiomesAvatarJoint::LHand;

        assert_eq!(
            biomes_sampled_joint_position(joint, [3.0, -2.0, 1.0]),
            biomes_avatar_joint_bind_position(joint)
        );
    }

    #[test]
    fn raw_biomes_sampled_pose_is_disabled_for_flat_modular_avatar() {
        assert!(!should_apply_raw_biomes_sampled_pose_to_flat_avatar());
    }

    #[test]
    fn hotbar_first_placeable_slot_picks_available_block() {
        let mut hotbar = [InventorySlot {
            block_id: crate::blocks::AIR,
            count: 0,
        }; PLAYER_HOTBAR_SLOTS];
        hotbar[2] = InventorySlot {
            block_id: crate::blocks::DIRT,
            count: 1,
        };

        assert_eq!(first_placeable_hotbar_slot(&hotbar), Some(2));
    }

    #[test]
    fn selected_hotbar_state_tracks_placeable_slot() {
        let hotbar = initial_hotbar_inventory();

        let (slot, block_id) =
            selected_hotbar_state_after_request(&hotbar, 0, crate::blocks::STONE, 3);

        assert_eq!(slot, 3);
        assert_eq!(block_id, crate::blocks::WOOD);
    }

    #[test]
    fn selected_hotbar_state_ignores_unplaceable_or_empty_slot() {
        let mut hotbar = initial_hotbar_inventory();
        hotbar[1] = InventorySlot {
            block_id: crate::blocks::DIRT,
            count: 0,
        };
        hotbar[2] = InventorySlot {
            block_id: crate::blocks::AIR,
            count: CREATIVE_HOTBAR_STACK_COUNT,
        };

        assert_eq!(
            selected_hotbar_state_after_request(&hotbar, 0, crate::blocks::STONE, 1),
            (0, crate::blocks::STONE)
        );
        assert_eq!(
            selected_hotbar_state_after_request(&hotbar, 0, crate::blocks::STONE, 2),
            (0, crate::blocks::STONE)
        );
        assert_eq!(
            selected_hotbar_state_after_request(
                &hotbar,
                0,
                crate::blocks::STONE,
                PLAYER_HOTBAR_SLOTS
            ),
            (0, crate::blocks::STONE)
        );
    }

    #[test]
    fn selected_tool_state_tracks_bounded_request() {
        assert_eq!(selected_tool_state_after_request(0, 2), 2);
        assert_eq!(selected_tool_state_after_request(2, PLAYER_TOOL_SLOTS), 2);
    }
}
