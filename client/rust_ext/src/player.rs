use godot::prelude::*;
use godot::classes::{CharacterBody3D, Camera3D, InputEventMouseMotion, InputEvent, Input, ICharacterBody3D};
use godot::global::{Key, MouseButton};

#[derive(GodotClass)]
#[class(base=CharacterBody3D)]
pub struct Player {
    base: Base<CharacterBody3D>,
    camera: Option<Gd<Camera3D>>,
    mouse_sensitivity: f32,
    selected_block: i32,
}

#[godot_api]
impl ICharacterBody3D for Player {
    fn init(base: Base<CharacterBody3D>) -> Self {
        Self {
            base,
            camera: None,
            mouse_sensitivity: 0.002,
            selected_block: 1,
        }
    }

    fn ready(&mut self) {
        // Создаем камеру
        let mut camera = Camera3D::new_alloc();
        camera.set_position(Vector3::new(0.0, 1.6, 0.0)); // Рост персонажа
        
        // Добавляем RayCast3D для разрушения блоков
        let mut raycast = godot::classes::RayCast3D::new_alloc();
        raycast.set_target_position(Vector3::new(0.0, 0.0, -5.0)); // Длина руки 5 метров
        raycast.set_name(&StringName::from("BlockRayCast"));
        camera.add_child(&raycast.upcast::<godot::classes::Node>());
        
        self.base_mut().add_child(&camera.clone().upcast::<godot::classes::Node>());
        self.camera = Some(camera);

        // Захватываем мышь
        Input::singleton().set_mouse_mode(godot::classes::input::MouseMode::CAPTURED);
    }

    fn input(&mut self, event: Gd<InputEvent>) {
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
        
        // Клик мышкой
        let input = Input::singleton();
        // Left click = MouseButton::LEFT
        if input.is_mouse_button_pressed(MouseButton::LEFT) {
            if let Some(camera) = &mut self.camera {
                if let Some(raycast) = camera.try_get_node_as::<godot::classes::RayCast3D>("BlockRayCast") {
                    if raycast.is_colliding() {
                        let hit_point = raycast.get_collision_point();
                        // Немного углубляемся в блок по нормали, чтобы точно получить его координаты
                        let normal = raycast.get_collision_normal();
                        let block_pos = hit_point - normal * 0.1;
                        
                        let bx = block_pos.x.floor() as i32;
                        let by = block_pos.y.floor() as i32;
                        let bz = block_pos.z.floor() as i32;
                        
                        godot_print!("Player breaks block at: {}, {}, {}", bx, by, bz);
                        self.base_mut().emit_signal(&StringName::from("block_broken"), &[bx.to_variant(), by.to_variant(), bz.to_variant()]);
                    }
                }
            }
        }
        
        if input.is_physical_key_pressed(Key::KEY_1) { self.selected_block = 1; }
        if input.is_physical_key_pressed(Key::KEY_2) { self.selected_block = 2; }
        if input.is_physical_key_pressed(Key::KEY_3) { self.selected_block = 3; }
        if input.is_physical_key_pressed(Key::KEY_4) { self.selected_block = 4; }
        
        // Right click = MouseButton::RIGHT
        if input.is_mouse_button_pressed(MouseButton::RIGHT) {
            if let Some(camera) = &mut self.camera {
                if let Some(raycast) = camera.try_get_node_as::<godot::classes::RayCast3D>("BlockRayCast") {
                    if raycast.is_colliding() {
                        let hit_point = raycast.get_collision_point();
                        // Немного отдаляемся от блока по нормали, чтобы получить координаты соседнего "пустого" блока
                        let normal = raycast.get_collision_normal();
                        let block_pos = hit_point + normal * 0.1;
                        
                        let bx = block_pos.x.floor() as i32;
                        let by = block_pos.y.floor() as i32;
                        let bz = block_pos.z.floor() as i32;
                        
                        let block_id = self.selected_block; 
                        
                        godot_print!("Player places block at: {}, {}, {} ID: {}", bx, by, bz, block_id);
                        self.base_mut().emit_signal(&StringName::from("block_placed"), &[bx.to_variant(), by.to_variant(), bz.to_variant(), block_id.to_variant()]);
                    }
                }
            }
        }
        
        if input.is_physical_key_pressed(Key::ESCAPE) {
            Input::singleton().set_mouse_mode(godot::classes::input::MouseMode::VISIBLE);
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let input = Input::singleton();
        
        // Простое перемещение для MVP (без нормальной физики и прыжков)
        let mut dir = Vector3::ZERO;
        
        if input.is_physical_key_pressed(Key::W) { dir.z -= 1.0; }
        if input.is_physical_key_pressed(Key::S) { dir.z += 1.0; }
        if input.is_physical_key_pressed(Key::A) { dir.x -= 1.0; }
        if input.is_physical_key_pressed(Key::D) { dir.x += 1.0; }
        
        if dir != Vector3::ZERO {
            dir = dir.normalized();
        }
        
        let basis = self.base().get_transform().basis;
        let movement = basis * dir * 5.0; // Скорость 5 м/с
        
        let mut velocity = self.base().get_velocity();
        velocity.x = movement.x;
        velocity.z = movement.z;
        // Гравитация
        velocity.y -= 9.8 * delta as f32;
        
        self.base_mut().set_velocity(velocity);
        self.base_mut().move_and_slide();
    }
}

#[godot_api]
impl Player {
    #[signal]
    fn block_broken(x: i32, y: i32, z: i32);
    
    #[signal]
    fn block_placed(x: i32, y: i32, z: i32, block_id: i32);
}
