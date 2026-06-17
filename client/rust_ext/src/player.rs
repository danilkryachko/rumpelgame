use godot::classes::{
    ArrayMesh, BoxMesh, Camera3D, CharacterBody3D, ICharacterBody3D, Input, InputEvent,
    InputEventKey, InputEventMouseButton, InputEventMouseMotion, MeshInstance3D, Node3D,
    StandardMaterial3D, base_material_3d,
};
use godot::global::{Key, MouseButton};
use godot::prelude::*;

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
const CREATIVE_HOTBAR_STACK_COUNT: u32 = 999;
const PLAYER_CHARACTER_VISUAL_NAME: &str = "PlayerVoxelCharacter";
const THIRD_PERSON_CAMERA_DISTANCE: f32 = 4.0;
const THIRD_PERSON_BLOCK_REACH_PADDING: f32 = 0.5;
const CHARACTER_RUN_SPEED_THRESHOLD: f32 = 0.25;
const CHARACTER_JUMP_SPEED_THRESHOLD: f32 = 0.5;
const CHARACTER_ANIMATION_WRAP_SECONDS: f32 = 4096.0;
const CHARACTER_IDLE_ANIMATION_RATE: f32 = 2.0;
const CHARACTER_RUN_ANIMATION_RATE: f32 = 9.0;
const CHARACTER_JUMP_ANIMATION_RATE: f32 = 4.0;
const CHARACTER_ROOT_YAW_DEGREES: f32 = 180.0;
const CHARACTER_HEAD_Y: f32 = 1.62;
const CHARACTER_CHEST_Y: f32 = 1.12;
const CHARACTER_BELT_Y: f32 = 0.74;
const CHARACTER_SHOULDER_Y: f32 = 1.34;
const CHARACTER_HIP_Y: f32 = 0.78;
const CHARACTER_LIMB_X: f32 = 0.43;
const CHARACTER_LEG_X: f32 = 0.18;

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
    Run,
    Jump,
}

struct VoxelCharacterVisual {
    root: Gd<Node3D>,
    head: Gd<Node3D>,
    chest: Gd<Node3D>,
    belt: Gd<Node3D>,
    hand_l: Gd<Node3D>,
    hand_r: Gd<Node3D>,
    foot_l: Gd<Node3D>,
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
    hotbar: [InventorySlot; PLAYER_HOTBAR_SLOTS],
    fly_mode: bool,
    third_person_camera: bool,
    character_motion_state: CharacterMotionState,
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
            hotbar,
            fly_mode: false,
            third_person_camera: false,
            character_motion_state: CharacterMotionState::Idle,
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
        shape.set_radius(0.4);
        shape.set_height(1.8);
        collision.set_shape(&shape.upcast::<godot::classes::Shape3D>());
        collision.set_position(Vector3::new(0.0, 0.9, 0.0));
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

        if let Some(mouse_button) = mouse_button_event
            && mouse_button.is_pressed()
        {
            match mouse_button.get_button_index() {
                MouseButton::LEFT => {
                    if let Some(hit) = self.aimed_block_hit() {
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
        self.update_character_visual(velocity_after_slide, on_floor, delta as f32);
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

    fn attach_character_visual(&mut self) {
        let visual = create_voxel_character_visual();
        self.base_mut()
            .add_child(&visual.root.clone().upcast::<godot::classes::Node>());
        self.character_visual = Some(visual);
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

    fn update_character_visual(&mut self, velocity: Vector3, on_floor: bool, delta_sec: f32) {
        let motion_state = character_motion_state_for_velocity(velocity, on_floor);
        self.character_motion_state = motion_state;

        self.character_animation_time_sec =
            next_character_animation_time(self.character_animation_time_sec, delta_sec);

        if let Some(visual) = &mut self.character_visual {
            apply_voxel_character_pose(visual, motion_state, self.character_animation_time_sec);
        }
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

fn first_person_camera_position() -> Vector3 {
    Vector3::new(0.0, 1.6, 0.0)
}

fn third_person_camera_position() -> Vector3 {
    Vector3::new(0.0, 2.2, THIRD_PERSON_CAMERA_DISTANCE)
}

fn block_raycast_target(third_person_camera: bool) -> Vector3 {
    let reach = if third_person_camera {
        BLOCK_REACH + THIRD_PERSON_CAMERA_DISTANCE + THIRD_PERSON_BLOCK_REACH_PADDING
    } else {
        BLOCK_REACH
    };
    Vector3::new(0.0, 0.0, -reach)
}

fn character_motion_state_for_velocity(velocity: Vector3, on_floor: bool) -> CharacterMotionState {
    let horizontal_speed = (velocity.x * velocity.x + velocity.z * velocity.z).sqrt();
    if !on_floor && velocity.y.abs() > CHARACTER_JUMP_SPEED_THRESHOLD {
        CharacterMotionState::Jump
    } else if horizontal_speed > CHARACTER_RUN_SPEED_THRESHOLD {
        CharacterMotionState::Run
    } else {
        CharacterMotionState::Idle
    }
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

fn create_voxel_character_visual() -> VoxelCharacterVisual {
    let mut root = Node3D::new_alloc();
    root.set_name(&StringName::from(PLAYER_CHARACTER_VISUAL_NAME));
    root.set_position(Vector3::ZERO);
    root.set_rotation_degrees(Vector3::new(0.0, CHARACTER_ROOT_YAW_DEGREES, 0.0));
    root.set_visible(false);

    let head = create_voxel_character_part(
        "Head",
        Vector3::new(0.0, CHARACTER_HEAD_Y, 0.0),
        Vector3::new(0.46, 0.46, 0.46),
        Vector3::ZERO,
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let chest = create_voxel_character_part(
        "Chest",
        Vector3::new(0.0, CHARACTER_CHEST_Y, 0.0),
        Vector3::new(0.68, 0.68, 0.34),
        Vector3::ZERO,
        Color::from_rgb(0.18, 0.45, 0.78),
    );
    let belt = create_voxel_character_part(
        "Belt",
        Vector3::new(0.0, CHARACTER_BELT_Y, 0.0),
        Vector3::new(0.58, 0.28, 0.34),
        Vector3::ZERO,
        Color::from_rgb(0.12, 0.16, 0.20),
    );
    let hand_l = create_voxel_character_part(
        "HandL",
        Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
        Vector3::new(0.20, 0.62, 0.20),
        Vector3::new(0.0, -0.31, 0.0),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let hand_r = create_voxel_character_part(
        "HandR",
        Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y, 0.0),
        Vector3::new(0.20, 0.62, 0.20),
        Vector3::new(0.0, -0.31, 0.0),
        Color::from_rgb(0.78, 0.55, 0.38),
    );
    let foot_l = create_voxel_character_part(
        "FootL",
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y, 0.0),
        Vector3::new(0.22, 0.72, 0.24),
        Vector3::new(0.0, -0.36, 0.0),
        Color::from_rgb(0.16, 0.22, 0.32),
    );
    let foot_r = create_voxel_character_part(
        "FootR",
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y, 0.0),
        Vector3::new(0.22, 0.72, 0.24),
        Vector3::new(0.0, -0.36, 0.0),
        Color::from_rgb(0.16, 0.22, 0.32),
    );

    root.add_child(&head.clone().upcast::<godot::classes::Node>());
    root.add_child(&chest.clone().upcast::<godot::classes::Node>());
    root.add_child(&belt.clone().upcast::<godot::classes::Node>());
    root.add_child(&hand_l.clone().upcast::<godot::classes::Node>());
    root.add_child(&hand_r.clone().upcast::<godot::classes::Node>());
    root.add_child(&foot_l.clone().upcast::<godot::classes::Node>());
    root.add_child(&foot_r.clone().upcast::<godot::classes::Node>());

    let mut visual = VoxelCharacterVisual {
        root,
        head,
        chest,
        belt,
        hand_l,
        hand_r,
        foot_l,
        foot_r,
    };
    apply_voxel_character_pose(&mut visual, CharacterMotionState::Idle, 0.0);
    visual
}

fn create_voxel_character_part(
    name: &str,
    pivot_position: Vector3,
    mesh_size: Vector3,
    mesh_offset: Vector3,
    color: Color,
) -> Gd<Node3D> {
    let mut pivot = Node3D::new_alloc();
    pivot.set_name(&StringName::from(name));
    pivot.set_position(pivot_position);

    let mut box_mesh = BoxMesh::new_gd();
    box_mesh.set_size(mesh_size);

    let mut mesh = MeshInstance3D::new_alloc();
    mesh.set_position(mesh_offset);
    mesh.set_mesh(&box_mesh.upcast::<godot::classes::Mesh>());
    mesh.set_material_override(&create_voxel_character_material(color));

    pivot.add_child(&mesh.upcast::<godot::classes::Node>());
    pivot
}

fn create_voxel_character_material(color: Color) -> Gd<godot::classes::Material> {
    let mut material = StandardMaterial3D::new_gd();
    material.set_albedo(color);
    material.set_shading_mode(base_material_3d::ShadingMode::UNSHADED);
    material.upcast::<godot::classes::Material>()
}

fn apply_voxel_character_pose(
    visual: &mut VoxelCharacterVisual,
    motion_state: CharacterMotionState,
    animation_time_sec: f32,
) {
    match motion_state {
        CharacterMotionState::Idle => apply_voxel_idle_pose(visual, animation_time_sec),
        CharacterMotionState::Run => apply_voxel_run_pose(visual, animation_time_sec),
        CharacterMotionState::Jump => apply_voxel_jump_pose(visual, animation_time_sec),
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
        &mut visual.belt,
        Vector3::new(0.0, CHARACTER_BELT_Y + bob * 0.5, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, -3.0 + wave * 1.2),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + bob, 0.0),
        Vector3::new(0.0, 0.0, 3.0 - wave * 1.2),
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y, 0.0),
        Vector3::ZERO,
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y, 0.0),
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
        &mut visual.belt,
        Vector3::new(0.0, CHARACTER_BELT_Y + bob * 0.6, 0.0),
        Vector3::new(-3.0, 0.0, swing * 1.4),
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + bob, 0.0),
        Vector3::new(counter_swing * 44.0, 0.0, -5.0),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + bob, 0.0),
        Vector3::new(swing * 44.0, 0.0, 5.0),
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + bob * 0.25, 0.0),
        Vector3::new(swing * 34.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + bob * 0.25, 0.0),
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
        &mut visual.belt,
        Vector3::new(0.0, CHARACTER_BELT_Y + 0.02 + float, 0.0),
        Vector3::new(3.0, 0.0, 0.0),
    );
    set_node_transform(
        &mut visual.hand_l,
        Vector3::new(-CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + 0.02 + float, 0.0),
        Vector3::new(-34.0, 0.0, -8.0),
    );
    set_node_transform(
        &mut visual.hand_r,
        Vector3::new(CHARACTER_LIMB_X, CHARACTER_SHOULDER_Y + 0.02 + float, 0.0),
        Vector3::new(-34.0, 0.0, 8.0),
    );
    set_node_transform(
        &mut visual.foot_l,
        Vector3::new(-CHARACTER_LEG_X, CHARACTER_HIP_Y + float, 0.0),
        Vector3::new(18.0, 0.0, -2.0),
    );
    set_node_transform(
        &mut visual.foot_r,
        Vector3::new(CHARACTER_LEG_X, CHARACTER_HIP_Y + float, 0.0),
        Vector3::new(18.0, 0.0, 2.0),
    );
}

fn set_node_transform(node: &mut Gd<Node3D>, position: Vector3, rotation_degrees: Vector3) {
    node.set_position(position);
    node.set_rotation_degrees(rotation_degrees);
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

    #[signal]
    fn block_broken(x: i32, y: i32, z: i32);

    #[signal]
    fn block_placed(x: i32, y: i32, z: i32, block_id: i32);

    #[signal]
    fn hotbar_selected(slot: i32, block_id: i32);

    #[signal]
    fn debug_log(message: GString);
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn third_person_raycast_extends_reach_by_camera_offset() {
        assert_eq!(block_raycast_target(false), Vector3::new(0.0, 0.0, -5.0));
        assert_eq!(block_raycast_target(true), Vector3::new(0.0, 0.0, -9.5));
    }

    #[test]
    fn camera_positions_are_mode_specific() {
        assert_eq!(first_person_camera_position(), Vector3::new(0.0, 1.6, 0.0));
        assert_eq!(
            third_person_camera_position(),
            Vector3::new(0.0, 2.2, THIRD_PERSON_CAMERA_DISTANCE)
        );
    }

    #[test]
    fn character_motion_state_follows_velocity() {
        assert_eq!(
            character_motion_state_for_velocity(Vector3::ZERO, true),
            CharacterMotionState::Idle
        );
        assert_eq!(
            character_motion_state_for_velocity(Vector3::new(1.0, 0.0, 0.0), true),
            CharacterMotionState::Run
        );
        assert_eq!(
            character_motion_state_for_velocity(Vector3::new(0.0, 2.0, 0.0), false),
            CharacterMotionState::Jump
        );
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
}
