use godot::classes::{ArrayMesh, ProjectSettings};
use godot::prelude::*;
use std::collections::{HashMap, HashSet};
use std::path::Path;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) struct VoxCoord {
    pub(crate) x: u8,
    pub(crate) y: u8,
    pub(crate) z: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct VoxVoxel {
    pub(crate) coord: VoxCoord,
    pub(crate) color_index: u8,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct VoxModel {
    pub(crate) size: (u32, u32, u32),
    pub(crate) voxels: Vec<VoxVoxel>,
    pub(crate) palette: [Color; 256],
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct VoxSceneModel {
    pub(crate) model: VoxModel,
    pub(crate) translation: (i32, i32, i32),
    pub(crate) rotation: VoxRotation,
    pub(crate) layer_name: Option<String>,
    pub(crate) hidden: bool,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct ColoredVoxel {
    pub(crate) position: (i32, i32, i32),
    pub(crate) color: Color,
}

pub(crate) type VoxRotation = [[i32; 3]; 3];

pub(crate) const VOX_IDENTITY_ROTATION: VoxRotation = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct SceneColoredVoxel {
    pub(crate) center: (i32, i32, i32),
    pub(crate) color: Color,
}

#[derive(Clone, Copy)]
struct VoxFace {
    neighbor: (i32, i32, i32),
    normal: Vector3,
    corners: [(f32, f32, f32); 4],
}

const VOX_FACE_SPECS: [VoxFace; 6] = [
    VoxFace {
        neighbor: (-1, 0, 0),
        normal: Vector3::new(-1.0, 0.0, 0.0),
        corners: [
            (0.0, 0.0, 1.0),
            (0.0, 1.0, 1.0),
            (0.0, 1.0, 0.0),
            (0.0, 0.0, 0.0),
        ],
    },
    VoxFace {
        neighbor: (1, 0, 0),
        normal: Vector3::new(1.0, 0.0, 0.0),
        corners: [
            (1.0, 0.0, 0.0),
            (1.0, 1.0, 0.0),
            (1.0, 1.0, 1.0),
            (1.0, 0.0, 1.0),
        ],
    },
    VoxFace {
        neighbor: (0, -1, 0),
        normal: Vector3::new(0.0, 0.0, -1.0),
        corners: [
            (0.0, 0.0, 0.0),
            (0.0, 1.0, 0.0),
            (1.0, 1.0, 0.0),
            (1.0, 0.0, 0.0),
        ],
    },
    VoxFace {
        neighbor: (0, 1, 0),
        normal: Vector3::new(0.0, 0.0, 1.0),
        corners: [
            (1.0, 0.0, 1.0),
            (1.0, 1.0, 1.0),
            (0.0, 1.0, 1.0),
            (0.0, 0.0, 1.0),
        ],
    },
    VoxFace {
        neighbor: (0, 0, -1),
        normal: Vector3::new(0.0, -1.0, 0.0),
        corners: [
            (0.0, 0.0, 1.0),
            (0.0, 0.0, 0.0),
            (1.0, 0.0, 0.0),
            (1.0, 0.0, 1.0),
        ],
    },
    VoxFace {
        neighbor: (0, 0, 1),
        normal: Vector3::new(0.0, 1.0, 0.0),
        corners: [
            (0.0, 1.0, 0.0),
            (0.0, 1.0, 1.0),
            (1.0, 1.0, 1.0),
            (1.0, 1.0, 0.0),
        ],
    },
];

#[allow(dead_code)]
pub fn load_vox_mesh_from_res(path: &str, scale: f32) -> Result<Gd<godot::classes::Mesh>, String> {
    let model = load_vox_model_from_res(path, 0)?;
    Ok(build_vox_mesh(&model, scale).upcast::<godot::classes::Mesh>())
}

pub(crate) fn load_vox_model_from_res(path: &str, model_index: usize) -> Result<VoxModel, String> {
    let absolute_path = ProjectSettings::singleton().globalize_path(path);
    let bytes = std::fs::read(absolute_path.to_string())
        .map_err(|err| format!("failed to read {path}: {err}"))?;
    parse_vox_model_index(&bytes, model_index)
}

pub(crate) fn load_vox_scene_models_from_res(path: &str) -> Result<Vec<VoxSceneModel>, String> {
    let absolute_path = ProjectSettings::singleton().globalize_path(path);
    let bytes = std::fs::read(absolute_path.to_string())
        .map_err(|err| format!("failed to read {path}: {err}"))?;
    parse_vox_scene_models(&bytes)
}

pub(crate) fn load_vox_scene_models_from_path(path: &Path) -> Result<Vec<VoxSceneModel>, String> {
    let bytes = std::fs::read(path).map_err(|err| format!("failed to read {path:?}: {err}"))?;
    parse_vox_scene_models(&bytes)
}

#[allow(dead_code)]
fn parse_first_vox_model(bytes: &[u8]) -> Result<VoxModel, String> {
    parse_vox_model_index(bytes, 0)
}

fn parse_vox_model_index(bytes: &[u8], model_index: usize) -> Result<VoxModel, String> {
    let models = parse_vox_models(bytes)?;
    models
        .into_iter()
        .nth(model_index)
        .ok_or_else(|| format!("vox file has no XYZI model at index {model_index}"))
}

fn parse_vox_models(bytes: &[u8]) -> Result<Vec<VoxModel>, String> {
    Ok(parse_vox_file(bytes)?.models)
}

fn parse_vox_scene_models(bytes: &[u8]) -> Result<Vec<VoxSceneModel>, String> {
    parse_vox_file(bytes)?.into_scene_models()
}

fn parse_vox_file(bytes: &[u8]) -> Result<VoxParser<'_>, String> {
    if bytes.len() < 20 || &bytes[0..4] != b"VOX " {
        return Err("not a MagicaVoxel VOX file".to_string());
    }

    let main_id = bytes
        .get(8..12)
        .ok_or_else(|| "missing MAIN chunk".to_string())?;
    if main_id != b"MAIN" {
        return Err("VOX MAIN chunk is missing".to_string());
    }

    let main_content_len = read_u32(bytes, 12)? as usize;
    let main_children_len = read_u32(bytes, 16)? as usize;
    let children_start = 20 + main_content_len;
    let children_end = children_start
        .checked_add(main_children_len)
        .ok_or_else(|| "VOX MAIN chunk size overflow".to_string())?;
    if children_end > bytes.len() {
        return Err("VOX MAIN chunk exceeds file length".to_string());
    }

    let mut parser = VoxParser {
        bytes,
        models: Vec::new(),
        transforms: Vec::new(),
        shape_models: HashMap::new(),
        layers: HashMap::new(),
        palette: default_palette(),
        pending_size: None,
    };
    parser.parse_chunks(children_start, children_end)?;
    for model in &mut parser.models {
        model.palette = parser.palette;
    }
    Ok(parser)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct VoxTransformNode {
    child_node_id: i32,
    layer_id: i32,
    hidden: bool,
    translation: (i32, i32, i32),
    rotation: VoxRotation,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct VoxLayer {
    name: Option<String>,
    hidden: bool,
}

struct VoxParser<'a> {
    bytes: &'a [u8],
    models: Vec<VoxModel>,
    transforms: Vec<VoxTransformNode>,
    shape_models: HashMap<i32, Vec<usize>>,
    layers: HashMap<i32, VoxLayer>,
    palette: [Color; 256],
    pending_size: Option<(u32, u32, u32)>,
}

impl VoxParser<'_> {
    fn into_scene_models(self) -> Result<Vec<VoxSceneModel>, String> {
        let mut scene_models = Vec::new();
        for transform in &self.transforms {
            let Some(model_ids) = self.shape_models.get(&transform.child_node_id) else {
                continue;
            };
            let layer = self.layers.get(&transform.layer_id);
            for model_id in model_ids {
                let model = self
                    .models
                    .get(*model_id)
                    .ok_or_else(|| format!("VOX scene references missing model {model_id}"))?;
                scene_models.push(VoxSceneModel {
                    model: model.clone(),
                    translation: transform.translation,
                    rotation: transform.rotation,
                    layer_name: layer.and_then(|layer| layer.name.clone()),
                    hidden: transform.hidden || layer.is_some_and(|layer| layer.hidden),
                });
            }
        }
        if scene_models.is_empty() {
            scene_models.extend(self.models.into_iter().map(|model| VoxSceneModel {
                model,
                translation: (0, 0, 0),
                rotation: VOX_IDENTITY_ROTATION,
                layer_name: None,
                hidden: false,
            }));
        }
        Ok(scene_models)
    }

    fn parse_chunks(&mut self, start: usize, end: usize) -> Result<(), String> {
        let mut offset = start;
        while offset < end {
            if offset + 12 > end || offset + 12 > self.bytes.len() {
                return Err("VOX chunk header exceeds parent bounds".to_string());
            }

            let id = self
                .bytes
                .get(offset..offset + 4)
                .ok_or_else(|| "VOX chunk id out of bounds".to_string())?;
            let content_len = read_u32(self.bytes, offset + 4)? as usize;
            let children_len = read_u32(self.bytes, offset + 8)? as usize;
            let content_start = offset + 12;
            let content_end = content_start
                .checked_add(content_len)
                .ok_or_else(|| "VOX chunk content size overflow".to_string())?;
            let children_end = content_end
                .checked_add(children_len)
                .ok_or_else(|| "VOX chunk child size overflow".to_string())?;
            if children_end > end || children_end > self.bytes.len() {
                return Err("VOX chunk exceeds parent bounds".to_string());
            }

            match id {
                b"SIZE" => self.parse_size(content_start, content_end)?,
                b"XYZI" => self.parse_xyzi(content_start, content_end)?,
                b"RGBA" => self.parse_rgba(content_start, content_end)?,
                b"nTRN" => self.parse_transform_node(content_start, content_end)?,
                b"nSHP" => self.parse_shape_node(content_start, content_end)?,
                b"LAYR" => self.parse_layer(content_start, content_end)?,
                _ => {}
            }

            if children_len > 0 {
                self.parse_chunks(content_end, children_end)?;
            }
            offset = children_end;
        }
        Ok(())
    }

    fn parse_size(&mut self, start: usize, end: usize) -> Result<(), String> {
        if end - start < 12 {
            return Err("VOX SIZE chunk is too short".to_string());
        }
        self.pending_size = Some((
            read_u32(self.bytes, start)?,
            read_u32(self.bytes, start + 4)?,
            read_u32(self.bytes, start + 8)?,
        ));
        Ok(())
    }

    fn parse_xyzi(&mut self, start: usize, end: usize) -> Result<(), String> {
        if end - start < 4 {
            return Err("VOX XYZI chunk is too short".to_string());
        }
        let count = read_u32(self.bytes, start)? as usize;
        let expected_len = 4 + count * 4;
        if end - start < expected_len {
            return Err("VOX XYZI voxel data is truncated".to_string());
        }

        let size = self
            .pending_size
            .take()
            .ok_or_else(|| "VOX XYZI chunk appeared before SIZE".to_string())?;
        let mut voxels = Vec::with_capacity(count);
        let mut offset = start + 4;
        for _ in 0..count {
            let coord = VoxCoord {
                x: self.bytes[offset],
                y: self.bytes[offset + 1],
                z: self.bytes[offset + 2],
            };
            let color_index = self.bytes[offset + 3];
            voxels.push(VoxVoxel { coord, color_index });
            offset += 4;
        }

        self.models.push(VoxModel {
            size,
            voxels,
            palette: self.palette,
        });
        Ok(())
    }

    fn parse_rgba(&mut self, start: usize, end: usize) -> Result<(), String> {
        if end - start < 256 * 4 {
            return Err("VOX RGBA chunk is too short".to_string());
        }
        for idx in 0..256 {
            let offset = start + idx * 4;
            self.palette[idx] = Color::from_rgba8(
                self.bytes[offset],
                self.bytes[offset + 1],
                self.bytes[offset + 2],
                self.bytes[offset + 3],
            );
        }
        Ok(())
    }

    fn parse_transform_node(&mut self, start: usize, end: usize) -> Result<(), String> {
        let mut offset = start;
        let _node_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let (attributes, next) = parse_vox_dict(self.bytes, offset, end)?;
        offset = next;
        let child_node_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let _reserved_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let layer_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let frame_count = read_i32(self.bytes, offset)?;
        offset += 4;
        if frame_count < 0 {
            return Err("VOX nTRN frame count is negative".to_string());
        }

        let mut translation = (0, 0, 0);
        let mut rotation = VOX_IDENTITY_ROTATION;
        for _ in 0..frame_count {
            let (frame, next) = parse_vox_dict(self.bytes, offset, end)?;
            offset = next;
            if let Some(value) = frame.get("_t") {
                translation = parse_vox_translation(value)?;
            }
            if let Some(value) = frame.get("_r") {
                rotation = parse_vox_rotation(value)?;
            }
        }

        self.transforms.push(VoxTransformNode {
            child_node_id,
            layer_id,
            hidden: parse_vox_hidden(&attributes),
            translation,
            rotation,
        });
        Ok(())
    }

    fn parse_shape_node(&mut self, start: usize, end: usize) -> Result<(), String> {
        let mut offset = start;
        let node_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let (_, next) = parse_vox_dict(self.bytes, offset, end)?;
        offset = next;
        let model_count = read_i32(self.bytes, offset)?;
        offset += 4;
        if model_count < 0 {
            return Err("VOX nSHP model count is negative".to_string());
        }

        let mut model_ids = Vec::with_capacity(model_count as usize);
        for _ in 0..model_count {
            let model_id = read_i32(self.bytes, offset)?;
            offset += 4;
            if model_id < 0 {
                return Err("VOX nSHP model id is negative".to_string());
            }
            let (_, next) = parse_vox_dict(self.bytes, offset, end)?;
            offset = next;
            model_ids.push(model_id as usize);
        }
        self.shape_models.insert(node_id, model_ids);
        Ok(())
    }

    fn parse_layer(&mut self, start: usize, end: usize) -> Result<(), String> {
        let mut offset = start;
        let layer_id = read_i32(self.bytes, offset)?;
        offset += 4;
        let (attributes, _) = parse_vox_dict(self.bytes, offset, end)?;
        self.layers.insert(
            layer_id,
            VoxLayer {
                name: attributes.get("_name").cloned(),
                hidden: parse_vox_hidden(&attributes),
            },
        );
        Ok(())
    }
}

fn parse_vox_dict(
    bytes: &[u8],
    start: usize,
    end: usize,
) -> Result<(HashMap<String, String>, usize), String> {
    let mut offset = start;
    let count = read_i32(bytes, offset)?;
    offset += 4;
    if count < 0 {
        return Err("VOX DICT entry count is negative".to_string());
    }

    let mut dict = HashMap::new();
    for _ in 0..count {
        let (key, next) = read_vox_string(bytes, offset, end)?;
        offset = next;
        let (value, next) = read_vox_string(bytes, offset, end)?;
        offset = next;
        dict.insert(key, value);
    }
    Ok((dict, offset))
}

fn read_vox_string(bytes: &[u8], start: usize, end: usize) -> Result<(String, usize), String> {
    let length = read_i32(bytes, start)?;
    if length < 0 {
        return Err("VOX string length is negative".to_string());
    }
    let content_start = start + 4;
    let content_end = content_start
        .checked_add(length as usize)
        .ok_or_else(|| "VOX string size overflow".to_string())?;
    if content_end > end || content_end > bytes.len() {
        return Err("VOX string exceeds chunk bounds".to_string());
    }
    let value = std::str::from_utf8(&bytes[content_start..content_end])
        .map_err(|err| format!("VOX string is not UTF-8: {err}"))?
        .to_string();
    Ok((value, content_end))
}

fn parse_vox_translation(value: &str) -> Result<(i32, i32, i32), String> {
    let parts = value
        .split_whitespace()
        .map(|part| {
            part.parse::<i32>()
                .map_err(|err| format!("VOX translation '{value}' is invalid: {err}"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if parts.len() != 3 {
        return Err(format!(
            "VOX translation '{value}' does not have 3 components"
        ));
    }
    Ok((parts[0], parts[1], parts[2]))
}

fn parse_vox_hidden(attributes: &HashMap<String, String>) -> bool {
    attributes
        .get("_hidden")
        .is_some_and(|value| value == "1" || value.eq_ignore_ascii_case("true"))
}

fn parse_vox_rotation(value: &str) -> Result<VoxRotation, String> {
    let encoded = value
        .parse::<u8>()
        .map_err(|err| format!("VOX rotation '{value}' is invalid: {err}"))?;
    let first_axis = (encoded & 0b0000_0011) as usize;
    let second_axis = ((encoded >> 2) & 0b0000_0011) as usize;
    if first_axis > 2 || second_axis > 2 || first_axis == second_axis {
        return Err(format!("VOX rotation '{value}' has invalid axis indices"));
    }
    let third_axis = (0..3)
        .find(|axis| *axis != first_axis && *axis != second_axis)
        .ok_or_else(|| format!("VOX rotation '{value}' has no remaining axis"))?;
    let axes = [first_axis, second_axis, third_axis];
    let mut rotation = [[0; 3]; 3];
    for row in 0..3 {
        let sign = if (encoded & (1 << (4 + row))) != 0 {
            -1
        } else {
            1
        };
        rotation[row][axes[row]] = sign;
    }
    Ok(rotation)
}

#[allow(dead_code)]
fn build_vox_mesh(model: &VoxModel, scale: f32) -> Gd<ArrayMesh> {
    let mut vertices = PackedVector3Array::new();
    let mut normals = PackedVector3Array::new();
    let mut colors = PackedColorArray::new();
    let occupied: HashSet<VoxCoord> = model.voxels.iter().map(|voxel| voxel.coord).collect();

    for voxel in &model.voxels {
        let color = palette_color(model.palette, voxel.color_index);
        for face in VOX_FACE_SPECS {
            if has_voxel_neighbor(&occupied, voxel.coord, face.neighbor) {
                continue;
            }
            push_vox_face(
                model.size,
                voxel.coord,
                face,
                scale,
                color,
                &mut vertices,
                &mut normals,
                &mut colors,
            );
        }
    }

    let mut arrays = Array::new();
    arrays.resize(13, &Variant::nil());
    arrays.set(0, &vertices.to_variant());
    arrays.set(1, &normals.to_variant());
    arrays.set(3, &colors.to_variant());

    let mut mesh = ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
    mesh
}

#[allow(dead_code)]
pub(crate) fn build_colored_voxels_mesh(voxels: &[ColoredVoxel], scale: f32) -> Gd<ArrayMesh> {
    build_colored_voxels_mesh_with_origin(voxels, scale, colored_voxel_mesh_origin(voxels))
}

pub(crate) fn build_colored_voxels_mesh_with_origin(
    voxels: &[ColoredVoxel],
    scale: f32,
    origin: (f32, f32, f32),
) -> Gd<ArrayMesh> {
    let mut vertices = PackedVector3Array::new();
    let mut normals = PackedVector3Array::new();
    let mut colors = PackedColorArray::new();
    let occupied: HashSet<(i32, i32, i32)> = voxels.iter().map(|voxel| voxel.position).collect();

    for voxel in voxels {
        for face in VOX_FACE_SPECS {
            let neighbor = (
                voxel.position.0 + face.neighbor.0,
                voxel.position.1 + face.neighbor.1,
                voxel.position.2 + face.neighbor.2,
            );
            if occupied.contains(&neighbor) {
                continue;
            }
            push_colored_voxel_face(
                voxel.position,
                origin,
                face,
                scale,
                voxel.color,
                &mut vertices,
                &mut normals,
                &mut colors,
            );
        }
    }

    let mut arrays = Array::new();
    arrays.resize(13, &Variant::nil());
    arrays.set(0, &vertices.to_variant());
    arrays.set(1, &normals.to_variant());
    arrays.set(3, &colors.to_variant());

    let mut mesh = ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
    mesh
}

#[derive(Clone, Copy)]
struct SceneVoxelFace {
    neighbor: (i32, i32, i32),
    normal: Vector3,
    corners: [(i32, i32, i32); 4],
}

const SCENE_VOXEL_FACE_SPECS: [SceneVoxelFace; 6] = [
    SceneVoxelFace {
        neighbor: (-2, 0, 0),
        normal: Vector3::new(0.0, 0.0, 1.0),
        corners: [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)],
    },
    SceneVoxelFace {
        neighbor: (2, 0, 0),
        normal: Vector3::new(0.0, 0.0, -1.0),
        corners: [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
    },
    SceneVoxelFace {
        neighbor: (0, -2, 0),
        normal: Vector3::new(1.0, 0.0, 0.0),
        corners: [(-1, -1, -1), (-1, -1, 1), (1, -1, 1), (1, -1, -1)],
    },
    SceneVoxelFace {
        neighbor: (0, 2, 0),
        normal: Vector3::new(-1.0, 0.0, 0.0),
        corners: [(1, 1, -1), (1, 1, 1), (-1, 1, 1), (-1, 1, -1)],
    },
    SceneVoxelFace {
        neighbor: (0, 0, -2),
        normal: Vector3::new(0.0, -1.0, 0.0),
        corners: [(-1, 1, -1), (-1, -1, -1), (1, -1, -1), (1, 1, -1)],
    },
    SceneVoxelFace {
        neighbor: (0, 0, 2),
        normal: Vector3::new(0.0, 1.0, 0.0),
        corners: [(-1, -1, 1), (-1, 1, 1), (1, 1, 1), (1, -1, 1)],
    },
];

pub(crate) fn build_scene_colored_voxels_mesh(
    voxels: &[SceneColoredVoxel],
    scale: f32,
) -> Gd<ArrayMesh> {
    let mut vertices = PackedVector3Array::new();
    let mut normals = PackedVector3Array::new();
    let mut colors = PackedColorArray::new();
    let occupied: HashSet<(i32, i32, i32)> = voxels.iter().map(|voxel| voxel.center).collect();

    for voxel in voxels {
        for face in SCENE_VOXEL_FACE_SPECS {
            let neighbor = (
                voxel.center.0 + face.neighbor.0,
                voxel.center.1 + face.neighbor.1,
                voxel.center.2 + face.neighbor.2,
            );
            if occupied.contains(&neighbor) {
                continue;
            }
            push_scene_colored_voxel_face(
                voxel.center,
                face,
                scale,
                voxel.color,
                &mut vertices,
                &mut normals,
                &mut colors,
            );
        }
    }

    let mut arrays = Array::new();
    arrays.resize(13, &Variant::nil());
    arrays.set(0, &vertices.to_variant());
    arrays.set(1, &normals.to_variant());
    arrays.set(3, &colors.to_variant());

    let mut mesh = ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
    mesh
}

fn push_scene_colored_voxel_face(
    center: (i32, i32, i32),
    face: SceneVoxelFace,
    scale: f32,
    color: Color,
    vertices: &mut PackedVector3Array,
    normals: &mut PackedVector3Array,
    colors: &mut PackedColorArray,
) {
    let p = |corner: (i32, i32, i32)| -> Vector3 {
        scene_voxel_corner_to_godot(
            (
                center.0 + corner.0,
                center.1 + corner.1,
                center.2 + corner.2,
            ),
            scale,
        )
    };
    let p0 = p(face.corners[0]);
    let p1 = p(face.corners[1]);
    let p2 = p(face.corners[2]);
    let p3 = p(face.corners[3]);
    for point in [p0, p1, p2, p0, p2, p3] {
        vertices.push(point);
        normals.push(face.normal);
        colors.push(color);
    }
}

fn scene_voxel_corner_to_godot(point2: (i32, i32, i32), scale: f32) -> Vector3 {
    Vector3::new(
        -(point2.1 as f32) * 0.5 * scale,
        point2.2 as f32 * 0.5 * scale,
        -(point2.0 as f32) * 0.5 * scale,
    )
}

#[allow(dead_code)]
fn colored_voxel_mesh_origin(voxels: &[ColoredVoxel]) -> (f32, f32, f32) {
    let Some(first) = voxels.first() else {
        return (0.0, 0.0, 0.0);
    };
    let (mut min_x, mut min_y, mut min_z) = first.position;
    let (mut max_x, mut max_y, mut max_z) = first.position;
    for voxel in voxels {
        let (x, y, z) = voxel.position;
        min_x = min_x.min(x);
        min_y = min_y.min(y);
        min_z = min_z.min(z);
        max_x = max_x.max(x);
        max_y = max_y.max(y);
        max_z = max_z.max(z);
    }
    (
        (min_x + max_x + 1) as f32 * 0.5,
        (min_y + max_y + 1) as f32 * 0.5,
        (min_z + max_z + 1) as f32 * 0.5,
    )
}

#[allow(dead_code)]
fn push_vox_face(
    size: (u32, u32, u32),
    coord: VoxCoord,
    face: VoxFace,
    scale: f32,
    color: Color,
    vertices: &mut PackedVector3Array,
    normals: &mut PackedVector3Array,
    colors: &mut PackedColorArray,
) {
    let p =
        |corner: (f32, f32, f32)| -> Vector3 { vox_corner_to_godot(size, coord, corner, scale) };
    let p0 = p(face.corners[0]);
    let p1 = p(face.corners[1]);
    let p2 = p(face.corners[2]);
    let p3 = p(face.corners[3]);
    for point in [p0, p1, p2, p0, p2, p3] {
        vertices.push(point);
        normals.push(face.normal);
        colors.push(color);
    }
}

fn push_colored_voxel_face(
    position: (i32, i32, i32),
    origin: (f32, f32, f32),
    face: VoxFace,
    scale: f32,
    color: Color,
    vertices: &mut PackedVector3Array,
    normals: &mut PackedVector3Array,
    colors: &mut PackedColorArray,
) {
    let p = |corner: (f32, f32, f32)| -> Vector3 {
        let x = position.0 as f32 + corner.0 - origin.0;
        let y = position.1 as f32 + corner.1 - origin.1;
        let z = position.2 as f32 + corner.2 - origin.2;
        Vector3::new(-y * scale, z * scale, x * scale)
    };
    let normal = Vector3::new(
        -(face.neighbor.1 as f32),
        face.neighbor.2 as f32,
        face.neighbor.0 as f32,
    );
    let p0 = p(face.corners[0]);
    let p1 = p(face.corners[1]);
    let p2 = p(face.corners[2]);
    let p3 = p(face.corners[3]);
    for point in [p0, p1, p2, p0, p2, p3] {
        vertices.push(point);
        normals.push(normal);
        colors.push(color);
    }
}

#[allow(dead_code)]
fn vox_corner_to_godot(
    size: (u32, u32, u32),
    coord: VoxCoord,
    corner: (f32, f32, f32),
    scale: f32,
) -> Vector3 {
    let (size_x, size_y, _) = size;
    let x = (coord.x as f32 + corner.0 - size_x as f32 * 0.5) * scale;
    let y = (coord.z as f32 + corner.2) * scale;
    let z = (coord.y as f32 + corner.1 - size_y as f32 * 0.5) * scale;
    Vector3::new(x, y, z)
}

#[allow(dead_code)]
fn has_voxel_neighbor(
    occupied: &HashSet<VoxCoord>,
    coord: VoxCoord,
    neighbor: (i32, i32, i32),
) -> bool {
    let x = coord.x as i32 + neighbor.0;
    let y = coord.y as i32 + neighbor.1;
    let z = coord.z as i32 + neighbor.2;
    if x < 0 || y < 0 || z < 0 || x > u8::MAX as i32 || y > u8::MAX as i32 || z > u8::MAX as i32 {
        return false;
    }
    occupied.contains(&VoxCoord {
        x: x as u8,
        y: y as u8,
        z: z as u8,
    })
}

fn palette_color(palette: [Color; 256], color_index: u8) -> Color {
    palette
        .get(color_index.saturating_sub(1) as usize)
        .copied()
        .unwrap_or(Color::WHITE)
}

#[allow(dead_code)]
pub(crate) fn model_palette_color(model: &VoxModel, color_index: u8) -> Color {
    palette_color(model.palette, color_index)
}

#[allow(dead_code)]
pub(crate) fn model_raw_palette_color(model: &VoxModel, color_index: u8) -> Color {
    model
        .palette
        .get(color_index as usize)
        .copied()
        .unwrap_or(Color::WHITE)
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| "unexpected end of VOX data".to_string())?;
    Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn read_i32(bytes: &[u8], offset: usize) -> Result<i32, String> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| "unexpected end of VOX data".to_string())?;
    Ok(i32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn default_palette() -> [Color; 256] {
    [Color::WHITE; 256]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_vox_models_reads_size_voxels_and_palette() {
        let bytes = test_vox_bytes();

        let models = parse_vox_models(&bytes).expect("test VOX should parse");

        assert_eq!(models.len(), 1);
        assert_eq!(models[0].size, (2, 2, 2));
        assert_eq!(
            models[0].voxels,
            vec![VoxVoxel {
                coord: VoxCoord { x: 1, y: 0, z: 1 },
                color_index: 1,
            }]
        );
        let color = models[0].palette[0];
        assert_eq!(color, Color::from_rgba8(10, 20, 30, 255));
    }

    #[test]
    fn parse_vox_scene_models_reads_biomes_scene_transforms() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/wearables/hair/clean.vox");
        if !path.is_file() {
            let base_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../assets/biomes/wearables/base_model.vox");
            let base_bytes = std::fs::read(&base_path)
                .unwrap_or_else(|err| panic!("failed to read {}: {err}", base_path.display()));
            let base_scene_models = parse_vox_scene_models(&base_bytes)
                .unwrap_or_else(|err| panic!("failed to parse {}: {err}", base_path.display()));
            assert!(base_scene_models.iter().any(|model| {
                model.translation == (0, 0, 47)
                    && model.rotation == [[0, -1, 0], [1, 0, 0], [0, 0, 1]]
                    && model.layer_name.as_deref() == Some("Head")
            }));
            return;
        }
        let bytes = std::fs::read(&path)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));

        let scene_models = parse_vox_scene_models(&bytes)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", path.display()));

        assert_eq!(scene_models.len(), 16);
        assert!(scene_models.iter().any(|model| {
            model.translation == (-1, 0, 50)
                && model.rotation == [[0, -1, 0], [1, 0, 0], [0, 0, 1]]
                && model.layer_name.as_deref() == Some("Head")
                && !model.hidden
                && model.model.voxels.len() == 865
        }));
        assert!(
            scene_models
                .iter()
                .any(|model| model.translation == (0, 0, 47)
                    && model.rotation == [[0, -1, 0], [1, 0, 0], [0, 0, 1]])
        );
        assert!(scene_models.iter().any(|model| {
            model.translation == (-2, 24, 35)
                && model.rotation == [[0, -1, 0], [-1, 0, 0], [0, 0, 1]]
        }));
        assert!(scene_models.iter().any(|model| {
            model.translation == (-2, -23, 35)
                && model.rotation == [[0, -1, 0], [1, 0, 0], [0, 0, 1]]
        }));
    }

    #[test]
    fn parse_vox_scene_models_reads_layers_and_hidden_flags() {
        let slides_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/wearables/feet/slides.vox");
        if !slides_path.is_file() {
            let base_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../assets/biomes/wearables/base_model.vox");
            let base = std::fs::read(&base_path)
                .unwrap_or_else(|err| panic!("failed to read {}: {err}", base_path.display()));
            let base_scene_models = parse_vox_scene_models(&base)
                .unwrap_or_else(|err| panic!("failed to parse {}: {err}", base_path.display()));
            assert!(base_scene_models.iter().any(|model| {
                model.translation == (1, 5, 1)
                    && model.layer_name.as_deref() == Some("L_Foot")
                    && !model.hidden
            }));
            return;
        }
        let slides = std::fs::read(&slides_path)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", slides_path.display()));
        let slides_scene_models = parse_vox_scene_models(&slides)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", slides_path.display()));

        assert!(slides_scene_models.iter().any(|model| {
            model.translation == (0, 4, 1)
                && model.layer_name.as_deref() == Some("L_Foot")
                && !model.hidden
        }));
        assert!(slides_scene_models.iter().any(|model| {
            model.translation == (-2, 0, 3)
                && model.layer_name.as_deref() == Some("hide_standalone")
                && model.hidden
        }));
        assert!(slides_scene_models.iter().any(|model| {
            model.translation == (-2, 18, 35)
                && model.layer_name.as_deref() == Some("reference")
                && model.hidden
        }));

        let robot_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/wearables/robot/robot_viking_helmet.vox");
        let robot = std::fs::read(&robot_path)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", robot_path.display()));
        let robot_scene_models = parse_vox_scene_models(&robot)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", robot_path.display()));

        assert_eq!(robot_scene_models.len(), 1);
        assert_eq!(robot_scene_models[0].layer_name, None);
    }

    #[test]
    fn scene_voxel_axes_match_biomes_pose_to_game_transform() {
        assert_eq!(
            scene_voxel_corner_to_godot((2, 4, 6), 0.5),
            Vector3::new(-1.0, 1.5, -0.5)
        );
        assert_eq!(SCENE_VOXEL_FACE_SPECS[0].normal, Vector3::BACK);
        assert_eq!(SCENE_VOXEL_FACE_SPECS[1].normal, Vector3::FORWARD);
    }

    #[test]
    fn parse_vox_models_rejects_truncated_input() {
        assert!(parse_vox_models(b"VOX ").is_err());
    }

    #[test]
    fn palette_helpers_keep_magica_vox_and_veloren_index_semantics_separate() {
        let mut model = VoxModel {
            size: (1, 1, 1),
            voxels: Vec::new(),
            palette: [Color::BLACK; 256],
        };
        model.palette[0] = Color::from_rgba8(10, 20, 30, 255);
        model.palette[1] = Color::from_rgba8(40, 50, 60, 255);

        assert_eq!(
            model_palette_color(&model, 1),
            Color::from_rgba8(10, 20, 30, 255)
        );
        assert_eq!(
            model_raw_palette_color(&model, 1),
            Color::from_rgba8(40, 50, 60, 255)
        );
    }

    fn test_vox_bytes() -> Vec<u8> {
        let mut children = Vec::new();
        push_chunk(
            &mut children,
            b"SIZE",
            &[2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0],
            &[],
        );
        push_chunk(&mut children, b"XYZI", &[1, 0, 0, 0, 1, 0, 1, 1], &[]);
        let mut rgba = vec![0; 256 * 4];
        rgba[0] = 10;
        rgba[1] = 20;
        rgba[2] = 30;
        rgba[3] = 255;
        push_chunk(&mut children, b"RGBA", &rgba, &[]);

        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"VOX ");
        bytes.extend_from_slice(&150u32.to_le_bytes());
        push_chunk(&mut bytes, b"MAIN", &[], &children);
        bytes
    }

    fn push_chunk(bytes: &mut Vec<u8>, id: &[u8; 4], content: &[u8], children: &[u8]) {
        bytes.extend_from_slice(id);
        bytes.extend_from_slice(&(content.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&(children.len() as u32).to_le_bytes());
        bytes.extend_from_slice(content);
        bytes.extend_from_slice(children);
    }
}
