use godot::classes::{
    ArrayMesh, Camera3D, CharacterBody3D, ICharacterBody3D, Input, InputEvent, InputEventKey,
    InputEventMouseButton, InputEventMouseMotion, MeshInstance3D, StandardMaterial3D,
    base_material_3d,
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

struct BlockHit {
    block: (i32, i32, i32),
    adjacent: (i32, i32, i32),
}

#[derive(GodotClass)]
#[class(base=CharacterBody3D)]
pub struct Player {
    base: Base<CharacterBody3D>,
    camera: Option<Gd<Camera3D>>,
    selection_outline: Option<Gd<MeshInstance3D>>,
    mouse_sensitivity: f32,
    selected_block: i32,
    fly_mode: bool,
    default_collision_layer: u32,
    default_collision_mask: u32,
}

#[godot_api]
impl ICharacterBody3D for Player {
    fn init(base: Base<CharacterBody3D>) -> Self {
        Self {
            base,
            camera: None,
            selection_outline: None,
            mouse_sensitivity: 0.002,
            selected_block: 1,
            fly_mode: false,
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
        camera.set_position(Vector3::new(0.0, 1.6, 0.0)); // Рост персонажа
        camera.set_current(true);

        // Добавляем RayCast3D для разрушения блоков
        let mut raycast = godot::classes::RayCast3D::new_alloc();
        raycast.set_target_position(Vector3::new(0.0, 0.0, -BLOCK_REACH));
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
                        if !crate::blocks::is_placeable(block_id as u32) {
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

    fn update_selected_block_from_hotbar(&mut self, input: &Gd<Input>) {
        for (slot, block_id) in crate::blocks::PLACEABLE_BLOCKS.iter().enumerate() {
            let key = match slot {
                0 => Key::KEY_1,
                1 => Key::KEY_2,
                2 => Key::KEY_3,
                3 => Key::KEY_4,
                4 => Key::KEY_5,
                _ => continue,
            };

            if input.is_physical_key_pressed(key) {
                self.selected_block = *block_id as i32;
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

    #[signal]
    fn block_broken(x: i32, y: i32, z: i32);

    #[signal]
    fn block_placed(x: i32, y: i32, z: i32, block_id: i32);

    #[signal]
    fn debug_log(message: GString);
}
