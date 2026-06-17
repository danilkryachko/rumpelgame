use godot::classes::ProjectSettings;
use godot::prelude::*;

use crate::vox::{ColoredVoxel, VoxModel};

// Biomes character-system adaptation.
//
// Source concepts: ill-inc/biomes-game, MIT License, commit
// 669da235acbc5ec19720b047889c4aaa1c013ce2.
//
// This keeps the Biomes character data model local to the Rust/Godot client:
// skeleton joints, fixed joint ordering, reserved appearance palette ranges,
// and a base wearable VOX mesh. It intentionally does not import Galois,
// Three.js, GLB generation, or server-side asset APIs.

const BIOMES_BASE_MODEL_PATH: &str = "res://assets/biomes/wearables/base_model.vox";
#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_ANIMATIONS_PATH: &str =
    "res://assets/biomes/animations/character-animations.gltf";
const SKIN_PALETTE_START: u8 = 241;
const SKIN_PALETTE_LEN: u8 = 8;
const HAIR_PALETTE_START: u8 = 233;
const HAIR_PALETTE_LEN: u8 = 8;
const EYE_PALETTE_START: u8 = 249;
const EYE_PALETTE_LEN: u8 = 7;

#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_SKELETON_ROOT: &str = "Armature";
#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_JOINT_ORDERING: [BiomesAvatarJoint; 15] = [
    BiomesAvatarJoint::Head,
    BiomesAvatarJoint::LFoot,
    BiomesAvatarJoint::RFoot,
    BiomesAvatarJoint::LHand,
    BiomesAvatarJoint::RHand,
    BiomesAvatarJoint::Waist,
    BiomesAvatarJoint::Chest,
    BiomesAvatarJoint::LForearm,
    BiomesAvatarJoint::RForearm,
    BiomesAvatarJoint::LLeg,
    BiomesAvatarJoint::RLeg,
    BiomesAvatarJoint::LArm,
    BiomesAvatarJoint::RArm,
    BiomesAvatarJoint::LThigh,
    BiomesAvatarJoint::RThigh,
];

#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_WEARABLE_SLOTS: [BiomesWearableSlot; 14] = [
    BiomesWearableSlot::Base,
    BiomesWearableSlot::Head,
    BiomesWearableSlot::Hair,
    BiomesWearableSlot::HairWithHat,
    BiomesWearableSlot::Hat,
    BiomesWearableSlot::Bottoms,
    BiomesWearableSlot::Face,
    BiomesWearableSlot::Top,
    BiomesWearableSlot::Neck,
    BiomesWearableSlot::Outerwear,
    BiomesWearableSlot::Ears,
    BiomesWearableSlot::Hands,
    BiomesWearableSlot::Feet,
    BiomesWearableSlot::Robot,
];

#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_ANIMATION_CLIP_NAMES: [&str; 44] = [
    "Applause",
    "Attack",
    "Attack2",
    "Craft",
    "Crouch",
    "CrouchIdle",
    "CrouchWalking",
    "Dancing",
    "DiggingHand",
    "DiggingTool",
    "DiggingToolOld",
    "Drink",
    "Eat",
    "Fall",
    "FishingCastPull",
    "FishingCastRelease",
    "FishingIdle",
    "FishingReel",
    "FishingShow",
    "Flex",
    "HoldingCamera",
    "Idle",
    "ItemAway",
    "ItemPutBack",
    "Jump",
    "Laugh",
    "Point",
    "Rock",
    "Running",
    "RunningBackward",
    "Sick",
    "Sit",
    "StrafeLeftRunning",
    "StrafeLeftWalking",
    "StrafeRightRunning",
    "StrafeRightWalking",
    "SwimmingBackward",
    "SwimmingForward",
    "SwimmingIdle",
    "Tilling",
    "TPose",
    "Walking",
    "Watering",
    "Waving",
];

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum BiomesAvatarJoint {
    Head,
    Chest,
    LArm,
    LForearm,
    LHand,
    RArm,
    RForearm,
    RHand,
    Waist,
    LThigh,
    LLeg,
    LFoot,
    RThigh,
    RLeg,
    RFoot,
}

impl BiomesAvatarJoint {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Head => "Head",
            Self::Chest => "Chest",
            Self::LArm => "L_Arm",
            Self::LForearm => "L_Forearm",
            Self::LHand => "L_Hand",
            Self::RArm => "R_Arm",
            Self::RForearm => "R_Forearm",
            Self::RHand => "R_Hand",
            Self::Waist => "Waist",
            Self::LThigh => "L_Thigh",
            Self::LLeg => "L_Leg",
            Self::LFoot => "L_Foot",
            Self::RThigh => "R_Thigh",
            Self::RLeg => "R_Leg",
            Self::RFoot => "R_Foot",
        }
    }

    fn base_model_index(self) -> usize {
        match self {
            Self::LForearm => 0,
            Self::LArm => 1,
            Self::LFoot => 2,
            Self::LLeg => 3,
            Self::LThigh => 4,
            Self::LHand => 5,
            Self::RForearm => 6,
            Self::RArm => 7,
            Self::RFoot => 8,
            Self::RLeg => 9,
            Self::RThigh => 10,
            Self::Waist => 11,
            Self::Chest => 12,
            Self::Head => 13,
            Self::RHand => 14,
        }
    }
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum BiomesWearableSlot {
    Base,
    Head,
    Hair,
    HairWithHat,
    Hat,
    Bottoms,
    Face,
    Top,
    Neck,
    Outerwear,
    Ears,
    Hands,
    Feet,
    Robot,
}

impl BiomesWearableSlot {
    #[allow(dead_code)]
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Base => "base",
            Self::Head => "head",
            Self::Hair => "hair",
            Self::HairWithHat => "hair_with_hat",
            Self::Hat => "hat",
            Self::Bottoms => "bottoms",
            Self::Face => "face",
            Self::Top => "top",
            Self::Neck => "neck",
            Self::Outerwear => "outerwear",
            Self::Ears => "ears",
            Self::Hands => "hands",
            Self::Feet => "feet",
            Self::Robot => "robot",
        }
    }
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum BiomesPlayerAnimation {
    Applause,
    Attack1,
    Attack2,
    Craft,
    Crouch,
    CrouchIdle,
    CrouchWalking,
    Dance,
    DiggingHand,
    DiggingTool,
    DiggingToolOld,
    Destroy,
    Drink,
    Eat,
    Equip,
    Fall,
    FishingCastPull,
    FishingCastRelease,
    FishingIdle,
    FishingReel,
    FishingShow,
    Flex,
    Camera,
    Idle,
    ItemAway,
    Jump,
    Laugh,
    Place,
    Point,
    Rock,
    Run,
    RunBackwards,
    Sick,
    Sit,
    StrafeLeftFast,
    StrafeLeftSlow,
    StrafeRightFast,
    StrafeRightSlow,
    SwimBackwards,
    SwimForwards,
    SwimIdle,
    FlyForwards,
    FlyIdle,
    Tilling,
    TPose,
    Unequip,
    Walk,
    Watering,
    Wave,
}

impl BiomesPlayerAnimation {
    #[allow(dead_code)]
    pub(crate) const SOURCE_CLIP_REPRESENTATIVES: [Self; 44] = [
        Self::Applause,
        Self::Attack1,
        Self::Attack2,
        Self::Craft,
        Self::Crouch,
        Self::CrouchIdle,
        Self::CrouchWalking,
        Self::Dance,
        Self::DiggingHand,
        Self::DiggingTool,
        Self::DiggingToolOld,
        Self::Drink,
        Self::Eat,
        Self::Fall,
        Self::FishingCastPull,
        Self::FishingCastRelease,
        Self::FishingIdle,
        Self::FishingReel,
        Self::FishingShow,
        Self::Flex,
        Self::Camera,
        Self::Idle,
        Self::ItemAway,
        Self::Equip,
        Self::Jump,
        Self::Laugh,
        Self::Point,
        Self::Rock,
        Self::Run,
        Self::RunBackwards,
        Self::Sick,
        Self::Sit,
        Self::StrafeLeftFast,
        Self::StrafeLeftSlow,
        Self::StrafeRightFast,
        Self::StrafeRightSlow,
        Self::SwimBackwards,
        Self::SwimForwards,
        Self::SwimIdle,
        Self::Tilling,
        Self::TPose,
        Self::Walk,
        Self::Watering,
        Self::Wave,
    ];

    #[allow(dead_code)]
    pub(crate) fn file_animation_name(self) -> &'static str {
        match self {
            Self::Applause => "Applause",
            Self::Attack1 => "Attack",
            Self::Attack2 => "Attack2",
            Self::Craft => "Craft",
            Self::Crouch => "Crouch",
            Self::CrouchIdle => "CrouchIdle",
            Self::CrouchWalking => "CrouchWalking",
            Self::Dance => "Dancing",
            Self::Destroy | Self::Place | Self::DiggingTool => "DiggingTool",
            Self::DiggingHand => "DiggingHand",
            Self::DiggingToolOld => "DiggingToolOld",
            Self::Drink => "Drink",
            Self::Eat => "Eat",
            Self::Equip | Self::Unequip => "ItemPutBack",
            Self::Fall => "Fall",
            Self::FishingCastPull => "FishingCastPull",
            Self::FishingCastRelease => "FishingCastRelease",
            Self::FishingIdle => "FishingIdle",
            Self::FishingReel => "FishingReel",
            Self::FishingShow => "FishingShow",
            Self::Flex => "Flex",
            Self::Camera => "HoldingCamera",
            Self::Idle => "Idle",
            Self::ItemAway => "ItemAway",
            Self::Jump => "Jump",
            Self::Laugh => "Laugh",
            Self::Point => "Point",
            Self::Rock => "Rock",
            Self::Run => "Running",
            Self::RunBackwards => "RunningBackward",
            Self::Sick => "Sick",
            Self::Sit => "Sit",
            Self::StrafeLeftFast => "StrafeLeftRunning",
            Self::StrafeLeftSlow => "StrafeLeftWalking",
            Self::StrafeRightFast => "StrafeRightRunning",
            Self::StrafeRightSlow => "StrafeRightWalking",
            Self::SwimBackwards => "SwimmingBackward",
            Self::SwimForwards | Self::FlyForwards => "SwimmingForward",
            Self::SwimIdle | Self::FlyIdle => "SwimmingIdle",
            Self::Tilling => "Tilling",
            Self::TPose => "TPose",
            Self::Walk => "Walking",
            Self::Watering => "Watering",
            Self::Wave => "Waving",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct BiomesAvatarAppearance {
    pub(crate) label: &'static str,
    pub(crate) skin_color_id: &'static str,
    pub(crate) eye_color_id: &'static str,
    pub(crate) hair_color_id: &'static str,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesAnimationClip {
    pub(crate) file_animation_name: String,
    pub(crate) duration_sec: f32,
    pub(crate) sampler_count: usize,
    pub(crate) channel_count: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesAnimationCatalog {
    clips: Vec<BiomesAnimationClip>,
}

impl BiomesAnimationCatalog {
    pub(crate) fn clips(&self) -> &[BiomesAnimationClip] {
        &self.clips
    }

    #[allow(dead_code)]
    pub(crate) fn clip_by_file_animation_name(
        &self,
        file_animation_name: &str,
    ) -> Option<&BiomesAnimationClip> {
        self.clips
            .iter()
            .find(|clip| clip.file_animation_name == file_animation_name)
    }

    #[allow(dead_code)]
    pub(crate) fn duration_for_animation(&self, animation: BiomesPlayerAnimation) -> Option<f32> {
        self.clip_by_file_animation_name(animation.file_animation_name())
            .map(|clip| clip.duration_sec)
    }

    #[allow(dead_code)]
    pub(crate) fn clip_count(&self) -> usize {
        self.clips.len()
    }
}

const AVATAR_APPEARANCE_PRESETS: [BiomesAvatarAppearance; 4] = [
    BiomesAvatarAppearance {
        label: "Biomes default",
        skin_color_id: "skin_color_3",
        eye_color_id: "eye_color_0",
        hair_color_id: "hair_color_8",
    },
    BiomesAvatarAppearance {
        label: "Biomes light",
        skin_color_id: "skin_color_1",
        eye_color_id: "eye_color_2",
        hair_color_id: "hair_color_12",
    },
    BiomesAvatarAppearance {
        label: "Biomes deep",
        skin_color_id: "skin_color_5",
        eye_color_id: "eye_color_1",
        hair_color_id: "hair_color_0",
    },
    BiomesAvatarAppearance {
        label: "Biomes cool",
        skin_color_id: "skin_color_2",
        eye_color_id: "eye_color_3",
        hair_color_id: "hair_color_16",
    },
];

pub(crate) fn avatar_appearance_preset_count() -> usize {
    AVATAR_APPEARANCE_PRESETS.len()
}

pub(crate) fn avatar_appearance_preset(index: usize) -> BiomesAvatarAppearance {
    AVATAR_APPEARANCE_PRESETS[index % AVATAR_APPEARANCE_PRESETS.len()]
}

pub(crate) fn default_avatar_appearance() -> BiomesAvatarAppearance {
    avatar_appearance_preset(0)
}

pub(crate) fn load_avatar_joint_mesh(
    joint: BiomesAvatarJoint,
    appearance: BiomesAvatarAppearance,
    scale: f32,
) -> Result<Gd<godot::classes::Mesh>, String> {
    let model =
        crate::vox::load_vox_model_from_res(BIOMES_BASE_MODEL_PATH, joint.base_model_index())?;
    let voxels = colored_voxels_from_biomes_model(&model, appearance);
    Ok(crate::vox::build_colored_voxels_mesh(&voxels, scale).upcast::<godot::classes::Mesh>())
}

pub(crate) fn load_biomes_animation_catalog_from_res() -> Result<BiomesAnimationCatalog, String> {
    let absolute_path =
        ProjectSettings::singleton().globalize_path(BIOMES_CHARACTER_ANIMATIONS_PATH);
    let source = std::fs::read_to_string(absolute_path.to_string())
        .map_err(|err| format!("failed to read {BIOMES_CHARACTER_ANIMATIONS_PATH}: {err}"))?;
    parse_biomes_animation_catalog(&source)
}

fn parse_biomes_animation_catalog(source: &str) -> Result<BiomesAnimationCatalog, String> {
    let accessor_maxes = parse_gltf_accessor_max_times(source)?;
    let animations = extract_json_array_field(source, "animations")?;
    let mut clips = Vec::new();
    for animation in split_top_level_json_objects(animations)? {
        let file_animation_name = parse_json_string_field(animation, "name")?;
        let samplers = extract_json_array_field(animation, "samplers")?;
        let channels = extract_json_array_field(animation, "channels")?;
        let sampler_objects = split_top_level_json_objects(samplers)?;
        let channel_count = split_top_level_json_objects(channels)?.len();
        let mut duration_sec = 0.0f32;
        for sampler in &sampler_objects {
            let input = parse_json_usize_field(sampler, "input")?;
            let Some(Some(max_time)) = accessor_maxes.get(input) else {
                return Err(format!(
                    "Biomes animation {file_animation_name} references input accessor {input} without max time"
                ));
            };
            duration_sec = duration_sec.max(*max_time);
        }
        clips.push(BiomesAnimationClip {
            file_animation_name,
            duration_sec,
            sampler_count: sampler_objects.len(),
            channel_count,
        });
    }
    if clips.is_empty() {
        return Err("Biomes animation GLTF has no animations".to_string());
    }
    Ok(BiomesAnimationCatalog { clips })
}

fn parse_gltf_accessor_max_times(source: &str) -> Result<Vec<Option<f32>>, String> {
    let accessors = extract_json_array_field(source, "accessors")?;
    split_top_level_json_objects(accessors)?
        .into_iter()
        .map(|accessor| {
            let Some(max_values) = try_extract_json_array_field(accessor, "max")? else {
                return Ok(None);
            };
            parse_first_json_number(max_values).map(Some)
        })
        .collect()
}

fn extract_json_array_field<'a>(source: &'a str, field_name: &str) -> Result<&'a str, String> {
    try_extract_json_array_field(source, field_name)?
        .ok_or_else(|| format!("Biomes GLTF JSON array field '{field_name}' is missing"))
}

fn try_extract_json_array_field<'a>(
    source: &'a str,
    field_name: &str,
) -> Result<Option<&'a str>, String> {
    let Some(colon) = find_json_field_colon(source, field_name) else {
        return Ok(None);
    };
    let open = skip_json_ws(source, colon + 1);
    if source.as_bytes().get(open).copied() != Some(b'[') {
        return Err(format!(
            "Biomes GLTF JSON field '{field_name}' is not an array"
        ));
    }
    let (inner, _) = extract_balanced_json(source, open, b'[', b']')?;
    Ok(Some(inner))
}

fn parse_json_string_field(source: &str, field_name: &str) -> Result<String, String> {
    let colon = find_json_field_colon(source, field_name)
        .ok_or_else(|| format!("Biomes GLTF JSON string field '{field_name}' is missing"))?;
    let open = skip_json_ws(source, colon + 1);
    parse_json_string_at(source, open).map(|(value, _)| value)
}

fn parse_json_usize_field(source: &str, field_name: &str) -> Result<usize, String> {
    let colon = find_json_field_colon(source, field_name)
        .ok_or_else(|| format!("Biomes GLTF JSON number field '{field_name}' is missing"))?;
    let start = skip_json_ws(source, colon + 1);
    let (number, _) = parse_json_number_at(source, start)?;
    if number < 0.0 || number.fract() != 0.0 {
        return Err(format!(
            "Biomes GLTF JSON field '{field_name}' must be a non-negative integer"
        ));
    }
    Ok(number as usize)
}

fn parse_first_json_number(source: &str) -> Result<f32, String> {
    let start = skip_json_ws(source, 0);
    parse_json_number_at(source, start).map(|(value, _)| value)
}

fn split_top_level_json_objects(source: &str) -> Result<Vec<&str>, String> {
    let bytes = source.as_bytes();
    let mut objects = Vec::new();
    let mut idx = 0usize;
    while idx < bytes.len() {
        idx = skip_json_ws_and_commas(source, idx);
        if idx >= bytes.len() {
            break;
        }
        if bytes[idx] != b'{' {
            return Err(format!(
                "Biomes GLTF expected object near '{}'",
                source[idx..].chars().take(32).collect::<String>()
            ));
        }
        let (inner, end) = extract_balanced_json(source, idx, b'{', b'}')?;
        objects.push(inner);
        idx = end;
    }
    Ok(objects)
}

fn find_json_field_colon(source: &str, field_name: &str) -> Option<usize> {
    let target = format!("\"{field_name}\"");
    let mut offset = 0usize;
    while let Some(found) = source[offset..].find(&target) {
        let key_start = offset + found;
        let key_end = key_start + target.len();
        let colon = skip_json_ws(source, key_end);
        if source.as_bytes().get(colon).copied() == Some(b':') {
            return Some(colon);
        }
        offset = key_end;
    }
    None
}

fn extract_balanced_json(
    source: &str,
    open: usize,
    opener: u8,
    closer: u8,
) -> Result<(&str, usize), String> {
    let bytes = source.as_bytes();
    if bytes.get(open).copied() != Some(opener) {
        return Err(format!("Biomes GLTF expected '{}'", opener as char));
    }
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;
    for (idx, byte) in bytes.iter().enumerate().skip(open) {
        if in_string {
            if escaped {
                escaped = false;
            } else if *byte == b'\\' {
                escaped = true;
            } else if *byte == b'"' {
                in_string = false;
            }
            continue;
        }
        if *byte == b'"' {
            in_string = true;
            continue;
        }
        if *byte == opener {
            depth += 1;
        } else if *byte == closer {
            depth = depth
                .checked_sub(1)
                .ok_or_else(|| "Biomes GLTF JSON balance underflow".to_string())?;
            if depth == 0 {
                return Ok((&source[open + 1..idx], idx + 1));
            }
        }
    }
    Err(format!("Biomes GLTF unclosed '{}'", opener as char))
}

fn parse_json_string_at(source: &str, open: usize) -> Result<(String, usize), String> {
    let bytes = source.as_bytes();
    if bytes.get(open).copied() != Some(b'"') {
        return Err("Biomes GLTF expected JSON string".to_string());
    }
    let mut escaped = false;
    let mut value = String::new();
    for (idx, byte) in bytes.iter().enumerate().skip(open + 1) {
        if escaped {
            value.push(*byte as char);
            escaped = false;
        } else if *byte == b'\\' {
            escaped = true;
        } else if *byte == b'"' {
            return Ok((value, idx + 1));
        } else {
            value.push(*byte as char);
        }
    }
    Err("Biomes GLTF unterminated JSON string".to_string())
}

fn parse_json_number_at(source: &str, start: usize) -> Result<(f32, usize), String> {
    let bytes = source.as_bytes();
    let mut end = start;
    while end < bytes.len() {
        let byte = bytes[end];
        if byte.is_ascii_digit() || matches!(byte, b'-' | b'+' | b'.' | b'e' | b'E') {
            end += 1;
        } else {
            break;
        }
    }
    if end == start {
        return Err(format!(
            "Biomes GLTF expected number near '{}'",
            source[start..].chars().take(32).collect::<String>()
        ));
    }
    source[start..end]
        .parse::<f32>()
        .map(|value| (value, end))
        .map_err(|err| format!("Biomes GLTF invalid number: {err}"))
}

fn skip_json_ws(source: &str, start: usize) -> usize {
    source.as_bytes()[start..]
        .iter()
        .position(|byte| !byte.is_ascii_whitespace())
        .map(|idx| idx + start)
        .unwrap_or(source.len())
}

fn skip_json_ws_and_commas(source: &str, start: usize) -> usize {
    source.as_bytes()[start..]
        .iter()
        .position(|byte| !byte.is_ascii_whitespace() && *byte != b',')
        .map(|idx| idx + start)
        .unwrap_or(source.len())
}

fn colored_voxels_from_biomes_model(
    model: &VoxModel,
    appearance: BiomesAvatarAppearance,
) -> Vec<ColoredVoxel> {
    model
        .voxels
        .iter()
        .map(|voxel| ColoredVoxel {
            position: (
                voxel.coord.x as i32,
                voxel.coord.y as i32,
                voxel.coord.z as i32,
            ),
            color: biomes_palette_color(model, voxel.color_index, appearance),
        })
        .collect()
}

fn biomes_palette_color(
    model: &VoxModel,
    color_index: u8,
    appearance: BiomesAvatarAppearance,
) -> Color {
    if let Some(offset) = palette_offset(color_index, SKIN_PALETTE_START, SKIN_PALETTE_LEN) {
        return skin_palette(appearance.skin_color_id)[offset];
    }
    if let Some(offset) = palette_offset(color_index, HAIR_PALETTE_START, HAIR_PALETTE_LEN) {
        return hair_palette(appearance.hair_color_id)[offset];
    }
    if let Some(offset) = palette_offset(color_index, EYE_PALETTE_START, EYE_PALETTE_LEN) {
        return eye_palette(appearance.eye_color_id)[offset];
    }
    crate::vox::model_palette_color(model, color_index)
}

fn palette_offset(color_index: u8, start: u8, len: u8) -> Option<usize> {
    let color_index = color_index as u16;
    let start = start as u16;
    let end = start + len as u16;
    if (start..end).contains(&color_index) {
        Some((color_index - start) as usize)
    } else {
        None
    }
}

fn skin_palette(id: &str) -> [Color; 8] {
    match id {
        "skin_color_0" => palette8([
            "#924450", "#f7e87c", "#efd159", "#ddb723", "#c09321", "#b48016", "#9d6f13", "#4b4b4b",
        ]),
        "skin_color_1" => palette8([
            "#965b56", "#ecdcd3", "#e8cfbf", "#d8b4a1", "#c59d90", "#b2897b", "#a57c6c", "#4b4b4b",
        ]),
        "skin_color_2" => palette8([
            "#8c584e", "#e0cfc0", "#d6b69a", "#b9967e", "#aa8977", "#907563", "#816552", "#4b4b4b",
        ]),
        "skin_color_4" => palette8([
            "#441a21", "#936c5a", "#835e4b", "#6d4538", "#5f372e", "#532d24", "#4d2822", "#4b4b4b",
        ]),
        "skin_color_5" => palette8([
            "#350e13", "#815b4e", "#694135", "#56322a", "#492923", "#40251e", "#3a1f1a", "#4b4b4b",
        ]),
        _ => palette8([
            "#6e3636", "#c7a68d", "#b28667", "#99725b", "#876455", "#825b4f", "#755145", "#4b4b4b",
        ]),
    }
}

fn eye_palette(id: &str) -> [Color; 7] {
    match id {
        "eye_color_1" => palette7([
            "#bbd8de", "#4b4b4b", "#8b471d", "#6d2f0e", "#4c1905", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_2" => palette7([
            "#bbd8de", "#4b4b4b", "#bf7126", "#9a4b11", "#6f2b0c", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_3" => palette7([
            "#bbd8de", "#4b4b4b", "#b29400", "#8f5f00", "#593500", "#4b4b4b", "#4b4b4b",
        ]),
        _ => palette7([
            "#bbd8de", "#4b4b4b", "#6f3d2a", "#502a1d", "#3b1f1b", "#4b4b4b", "#4b4b4b",
        ]),
    }
}

fn hair_palette(id: &str) -> [Color; 8] {
    match id {
        "hair_color_0" => palette8([
            "#f5cfe1", "#ecb3cb", "#e497b6", "#dc7ba1", "#d35e8b", "#ba426c", "#9c3255", "#79283e",
        ]),
        "hair_color_4" => palette8([
            "#e6f2f3", "#deeeef", "#d9ebed", "#d4e8eb", "#cee3e7", "#bad2d9", "#a4bac0", "#96a8ac",
        ]),
        "hair_color_12" => palette8([
            "#bba267", "#ab8f5f", "#977d5c", "#836d55", "#715b4b", "#5d4b42", "#4a3b36", "#3b2e2b",
        ]),
        "hair_color_16" => palette8([
            "#ccebfd", "#bad4f2", "#aec6eb", "#95a8e0", "#7d8bd5", "#6973cb", "#5255b1", "#4a448d",
        ]),
        _ => palette8([
            "#a4693c", "#955b38", "#864f31", "#75452e", "#623a29", "#513123", "#3d251e", "#2e1c18",
        ]),
    }
}

fn palette8(hex: [&str; 8]) -> [Color; 8] {
    [
        hex_color(hex[0]),
        hex_color(hex[1]),
        hex_color(hex[2]),
        hex_color(hex[3]),
        hex_color(hex[4]),
        hex_color(hex[5]),
        hex_color(hex[6]),
        hex_color(hex[7]),
    ]
}

fn palette7(hex: [&str; 7]) -> [Color; 7] {
    [
        hex_color(hex[0]),
        hex_color(hex[1]),
        hex_color(hex[2]),
        hex_color(hex[3]),
        hex_color(hex[4]),
        hex_color(hex[5]),
        hex_color(hex[6]),
    ]
}

fn hex_color(hex: &str) -> Color {
    let hex = hex.trim_start_matches('#');
    if hex.len() != 6 {
        return Color::WHITE;
    }
    let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255);
    let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255);
    let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255);
    Color::from_rgba8(r, g, b, 255)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;
    use std::path::Path;

    #[test]
    fn biomes_skeleton_contract_matches_player_wearable_pipeline() {
        assert_eq!(BIOMES_CHARACTER_SKELETON_ROOT, "Armature");
        assert_eq!(
            BIOMES_CHARACTER_JOINT_ORDERING.map(BiomesAvatarJoint::name),
            [
                "Head",
                "L_Foot",
                "R_Foot",
                "L_Hand",
                "R_Hand",
                "Waist",
                "Chest",
                "L_Forearm",
                "R_Forearm",
                "L_Leg",
                "R_Leg",
                "L_Arm",
                "R_Arm",
                "L_Thigh",
                "R_Thigh",
            ]
        );
    }

    #[test]
    fn biomes_wearable_slots_include_base_and_character_slots() {
        assert_eq!(BIOMES_CHARACTER_WEARABLE_SLOTS[0].name(), "base");
        assert!(
            BIOMES_CHARACTER_WEARABLE_SLOTS
                .iter()
                .any(|slot| slot.name() == "hair_with_hat")
        );
        assert!(
            BIOMES_CHARACTER_WEARABLE_SLOTS
                .iter()
                .any(|slot| slot.name() == "outerwear")
        );
    }

    #[test]
    fn base_model_indices_match_biomes_vox_layers() {
        assert_eq!(BiomesAvatarJoint::LForearm.base_model_index(), 0);
        assert_eq!(BiomesAvatarJoint::Chest.base_model_index(), 12);
        assert_eq!(BiomesAvatarJoint::Head.base_model_index(), 13);
        assert_eq!(BiomesAvatarJoint::RHand.base_model_index(), 14);
    }

    #[test]
    fn appearance_presets_cycle_and_keep_biomes_default_ids() {
        assert_eq!(avatar_appearance_preset_count(), 4);
        assert_eq!(avatar_appearance_preset(0).skin_color_id, "skin_color_3");
        assert_eq!(avatar_appearance_preset(4), avatar_appearance_preset(0));
        assert_eq!(default_avatar_appearance().hair_color_id, "hair_color_8");
    }

    #[test]
    fn reserved_palette_ranges_follow_biomes_character_appearance() {
        assert_eq!(
            palette_offset(241, SKIN_PALETTE_START, SKIN_PALETTE_LEN),
            Some(0)
        );
        assert_eq!(
            palette_offset(248, SKIN_PALETTE_START, SKIN_PALETTE_LEN),
            Some(7)
        );
        assert_eq!(
            palette_offset(233, HAIR_PALETTE_START, HAIR_PALETTE_LEN),
            Some(0)
        );
        assert_eq!(
            palette_offset(249, EYE_PALETTE_START, EYE_PALETTE_LEN),
            Some(0)
        );
        assert_eq!(
            palette_offset(255, EYE_PALETTE_START, EYE_PALETTE_LEN),
            Some(6)
        );
        assert_eq!(palette_offset(0, EYE_PALETTE_START, EYE_PALETTE_LEN), None);
    }

    #[test]
    fn biomes_character_assets_are_checked_in() {
        let asset_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/biomes");
        let base_model = asset_root.join("wearables/base_model.vox");
        let animations = asset_root.join("animations/character-animations.gltf");

        assert!(base_model.is_file(), "missing {}", base_model.display());
        assert!(animations.is_file(), "missing {}", animations.display());

        let gltf = std::fs::read_to_string(&animations)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", animations.display()));
        assert!(gltf.contains("\"name\" : \"Idle\""));
        assert!(gltf.contains("\"name\" : \"Walking\""));
        assert!(gltf.contains("\"name\" : \"Running\""));
    }

    #[test]
    fn biomes_animation_catalog_reads_all_source_clips() {
        let animations = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/animations/character-animations.gltf");
        let gltf = std::fs::read_to_string(&animations)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", animations.display()));
        let catalog = parse_biomes_animation_catalog(&gltf)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", animations.display()));

        assert_eq!(catalog.clip_count(), 44);
        let names = catalog
            .clips()
            .iter()
            .map(|clip| clip.file_animation_name.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            names.as_slice(),
            BIOMES_CHARACTER_ANIMATION_CLIP_NAMES.as_slice()
        );

        assert_clip_duration(&catalog, "Idle", 1.0);
        assert_clip_duration(&catalog, "Running", 0.916_666_7);
        assert_clip_duration(&catalog, "Dancing", 4.5);
        assert_clip_duration(&catalog, "Eat", 3.166_666_7);
        assert_clip_duration(&catalog, "Watering", 1.25);

        let running = catalog
            .clip_by_file_animation_name("Running")
            .expect("Running clip must exist");
        assert_eq!(running.sampler_count, 48);
        assert_eq!(running.channel_count, 48);
        assert_eq!(
            catalog.duration_for_animation(BiomesPlayerAnimation::Run),
            Some(running.duration_sec)
        );
        assert_eq!(
            catalog.duration_for_animation(BiomesPlayerAnimation::Wave),
            Some(2.0)
        );
    }

    #[test]
    fn biomes_player_animation_names_cover_source_clip_catalog() {
        let source_names = BIOMES_CHARACTER_ANIMATION_CLIP_NAMES
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        let representative_names = BiomesPlayerAnimation::SOURCE_CLIP_REPRESENTATIVES
            .iter()
            .map(|animation| animation.file_animation_name())
            .collect::<BTreeSet<_>>();

        assert_eq!(representative_names, source_names);
    }

    fn assert_clip_duration(catalog: &BiomesAnimationCatalog, name: &str, expected: f32) {
        let duration = catalog
            .clip_by_file_animation_name(name)
            .unwrap_or_else(|| panic!("{name} clip must exist"))
            .duration_sec;
        assert!(
            (duration - expected).abs() < 0.0001,
            "{name} duration was {duration}, expected {expected}"
        );
    }
}
