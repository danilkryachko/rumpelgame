use godot::classes::ProjectSettings;
use godot::prelude::*;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use crate::vox::{SceneColoredVoxel, VoxModel, VoxRotation, VoxSceneModel};

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
const WEARABLE_BASE_OCCLUSION_RADIUS: i32 = 4;
#[allow(dead_code)]
pub(crate) const BIOMES_CHARACTER_ANIMATIONS_PATH: &str =
    "res://assets/biomes/animations/character-animations.gltf";
const SKIN_PALETTE_START: u8 = 241;
const SKIN_PALETTE_LEN: u8 = 8;
const HAIR_PALETTE_START: u8 = 233;
const HAIR_PALETTE_LEN: u8 = 8;
const EYE_PALETTE_START: u8 = 249;
const EYE_PALETTE_LEN: u8 = 7;
const BIOMES_BASE_SCENE_CENTER_X: f32 = 0.0;
const BIOMES_BASE_SCENE_CENTER_Y: f32 = 0.5;
const BIOMES_BASE_SCENE_MIN_Z: f32 = -0.5;
pub(crate) const BIOMES_ANIMATION_VOX_TO_POSE_SCALE: f32 = 0.1;

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

    pub(crate) fn skeleton_parent(self) -> Option<Self> {
        match self {
            Self::Head | Self::LArm | Self::RArm => Some(Self::Chest),
            Self::LForearm => Some(Self::LArm),
            Self::LHand => Some(Self::LForearm),
            Self::RForearm => Some(Self::RArm),
            Self::RHand => Some(Self::RForearm),
            Self::LThigh | Self::RThigh => Some(Self::Waist),
            Self::LLeg => Some(Self::LThigh),
            Self::LFoot => Some(Self::LLeg),
            Self::RLeg => Some(Self::RThigh),
            Self::RFoot => Some(Self::RLeg),
            Self::Chest | Self::Waist => None,
        }
    }

    #[allow(dead_code)]
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

    fn base_scene_translation(self) -> (i32, i32, i32) {
        match self {
            Self::LForearm => (-2, 18, 35),
            Self::LArm => (-2, 10, 35),
            Self::LFoot => (1, 5, 1),
            Self::LLeg => (-1, 5, 5),
            Self::LThigh => (-1, 5, 14),
            Self::LHand => (-2, 24, 35),
            Self::RForearm => (-2, -17, 35),
            Self::RArm => (-2, -9, 35),
            Self::RFoot => (1, -4, 1),
            Self::RLeg => (-1, -4, 5),
            Self::RThigh => (-1, -4, 14),
            Self::Waist => (-1, 0, 19),
            Self::Chest => (-1, 0, 29),
            Self::Head => (0, 0, 47),
            Self::RHand => (-2, -23, 35),
        }
    }

    fn base_model_voxel_count(self) -> usize {
        match self {
            Self::LForearm => 140,
            Self::LArm => 149,
            Self::LFoot => 99,
            Self::LLeg => 175,
            Self::LThigh => 275,
            Self::LHand => 95,
            Self::RForearm => 140,
            Self::RArm => 149,
            Self::RFoot => 99,
            Self::RLeg => 175,
            Self::RThigh => 275,
            Self::Waist => 351,
            Self::Chest => 1914,
            Self::Head => 3786,
            Self::RHand => 95,
        }
    }
}

pub(crate) fn avatar_joint_bind_position(joint: BiomesAvatarJoint, scale: f32) -> [f32; 3] {
    let (x, y, z) = joint.base_scene_translation();
    [
        -((y as f32) - BIOMES_BASE_SCENE_CENTER_Y) * scale,
        ((z as f32) - BIOMES_BASE_SCENE_MIN_Z) * scale,
        -((x as f32) - BIOMES_BASE_SCENE_CENTER_X) * scale,
    ]
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BiomesAvatarAppearance {
    pub(crate) skin_color_id: String,
    pub(crate) eye_color_id: String,
    pub(crate) hair_color_id: String,
    pub(crate) head_id: String,
    pub(crate) hair_id: Option<String>,
    pub(crate) face_id: Option<String>,
    pub(crate) ears_id: Option<String>,
    pub(crate) hat_id: Option<String>,
    pub(crate) neck_id: Option<String>,
    pub(crate) top_id: Option<String>,
    pub(crate) bottoms_id: Option<String>,
    pub(crate) outerwear_id: Option<String>,
    pub(crate) hands_id: Option<String>,
    pub(crate) feet_id: Option<String>,
    pub(crate) robot_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesAnimationClip {
    pub(crate) file_animation_name: String,
    pub(crate) duration_sec: f32,
    pub(crate) sampler_count: usize,
    pub(crate) channel_count: usize,
    tracks: Vec<BiomesAnimationTrack>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BiomesAnimationTransformPath {
    Translation,
    Rotation,
    Scale,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesAnimationTrack {
    pub(crate) node_index: usize,
    pub(crate) node_name: String,
    pub(crate) path: BiomesAnimationTransformPath,
    times: Vec<f32>,
    values: Vec<[f32; 4]>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesSampledNodeTransform {
    pub(crate) node_index: usize,
    pub(crate) node_name: String,
    pub(crate) translation: Option<[f32; 3]>,
    pub(crate) rotation: Option<[f32; 4]>,
    pub(crate) scale: Option<[f32; 3]>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesSampledJointPose {
    pub(crate) joint: BiomesAvatarJoint,
    pub(crate) node_name: String,
    pub(crate) local_translation: [f32; 3],
    pub(crate) local_rotation: [f32; 4],
    pub(crate) local_scale: [f32; 3],
    pub(crate) translation_delta: [f32; 3],
    pub(crate) rotation_delta: [f32; 4],
    pub(crate) scale: [f32; 3],
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesSampledPose {
    pub(crate) nodes: Vec<BiomesSampledNodeTransform>,
    pub(crate) joints: Vec<BiomesSampledJointPose>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct BiomesTransform {
    pub(crate) translation: [f32; 3],
    pub(crate) rotation: [f32; 4],
    pub(crate) scale: [f32; 3],
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct BiomesJointRestPose {
    pub(crate) joint: BiomesAvatarJoint,
    pub(crate) parent_joint: Option<BiomesAvatarJoint>,
    pub(crate) local: BiomesTransform,
    pub(crate) global: BiomesTransform,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct BiomesAnimationCatalog {
    clips: Vec<BiomesAnimationClip>,
    nodes: Vec<GltfNode>,
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

    pub(crate) fn sample_clip_pose(
        &self,
        file_animation_name: &str,
        time_sec: f32,
    ) -> Option<BiomesSampledPose> {
        self.clip_by_file_animation_name(file_animation_name)
            .map(|clip| clip.sample_pose(time_sec, &self.nodes))
    }

    pub(crate) fn armature_rest_pose(&self) -> Option<BiomesTransform> {
        self.nodes
            .iter()
            .find(|node| node.name == "Armature")
            .map(GltfNodeTransform::from_node)
            .map(BiomesTransform::from)
    }

    pub(crate) fn joint_rest_poses(&self) -> Vec<BiomesJointRestPose> {
        let rest_local_transforms = self
            .nodes
            .iter()
            .map(GltfNodeTransform::from_node)
            .collect::<Vec<_>>();
        let rest_global_transforms =
            compute_gltf_global_transforms(&self.nodes, &rest_local_transforms);

        BIOMES_CHARACTER_JOINT_ORDERING
            .into_iter()
            .filter_map(|joint| {
                let node_index = self.skeleton_node_index_for_joint(joint)?;
                let local = rest_local_transforms.get(node_index).copied()?;
                let global = rest_global_transforms.get(node_index).copied()?;
                Some(BiomesJointRestPose {
                    joint,
                    parent_joint: joint.skeleton_parent(),
                    local: local.into(),
                    global: global.into(),
                })
            })
            .collect()
    }

    fn skeleton_node_index_for_joint(&self, joint: BiomesAvatarJoint) -> Option<usize> {
        let expected_parent_name = joint.skeleton_parent().map(BiomesAvatarJoint::name);
        self.nodes
            .iter()
            .enumerate()
            .find_map(|(node_index, node)| {
                if node.name != joint.name() {
                    return None;
                }
                let parent_name = node
                    .parent
                    .and_then(|parent_index| self.nodes.get(parent_index))
                    .map(|parent| parent.name.as_str());
                match (expected_parent_name, parent_name) {
                    (Some(expected), Some(actual)) if expected == actual => Some(node_index),
                    (None, Some("Armature")) => Some(node_index),
                    _ => None,
                }
            })
    }
}

impl BiomesAnimationClip {
    pub(crate) fn track_count(&self) -> usize {
        self.tracks.len()
    }

    fn sample_pose(&self, time_sec: f32, gltf_nodes: &[GltfNode]) -> BiomesSampledPose {
        let sample_time = if self.duration_sec.is_finite() && self.duration_sec > 0.0 {
            time_sec.rem_euclid(self.duration_sec)
        } else {
            0.0
        };
        let mut local_transforms = gltf_nodes
            .iter()
            .map(GltfNodeTransform::from_node)
            .collect::<Vec<_>>();
        let mut nodes = Vec::<BiomesSampledNodeTransform>::new();
        for track in &self.tracks {
            let value = track.sample_value(sample_time);
            let node_index = nodes
                .iter()
                .position(|node| node.node_index == track.node_index)
                .unwrap_or_else(|| {
                    nodes.push(BiomesSampledNodeTransform {
                        node_index: track.node_index,
                        node_name: track.node_name.clone(),
                        translation: None,
                        rotation: None,
                        scale: None,
                    });
                    nodes.len() - 1
                });
            if let Some(local_transform) = local_transforms.get_mut(track.node_index) {
                local_transform.set_path_value(track.path, value);
            }
            match track.path {
                BiomesAnimationTransformPath::Translation => {
                    nodes[node_index].translation = Some([value[0], value[1], value[2]]);
                }
                BiomesAnimationTransformPath::Rotation => {
                    nodes[node_index].rotation = Some(normalize_quaternion(value));
                }
                BiomesAnimationTransformPath::Scale => {
                    nodes[node_index].scale = Some([value[0], value[1], value[2]]);
                }
            }
        }
        let rest_local_transforms = gltf_nodes
            .iter()
            .map(GltfNodeTransform::from_node)
            .collect::<Vec<_>>();
        let sampled_global_transforms =
            compute_gltf_global_transforms(gltf_nodes, &local_transforms);
        let rest_global_transforms =
            compute_gltf_global_transforms(gltf_nodes, &rest_local_transforms);
        let joints = self.sampled_joint_poses(
            gltf_nodes,
            &local_transforms,
            &sampled_global_transforms,
            &rest_global_transforms,
        );
        BiomesSampledPose { nodes, joints }
    }

    fn sampled_joint_poses(
        &self,
        gltf_nodes: &[GltfNode],
        local_transforms: &[GltfNodeTransform],
        sampled_global_transforms: &[GltfNodeTransform],
        rest_global_transforms: &[GltfNodeTransform],
    ) -> Vec<BiomesSampledJointPose> {
        BIOMES_CHARACTER_JOINT_ORDERING
            .into_iter()
            .filter_map(|joint| {
                let node_index = self.animated_node_index_for_name(joint.name())?;
                let node = gltf_nodes.get(node_index)?;
                let local = local_transforms.get(node_index)?;
                let sampled = sampled_global_transforms.get(node_index)?;
                let rest = rest_global_transforms.get(node_index)?;
                Some(BiomesSampledJointPose {
                    joint,
                    node_name: node.name.clone(),
                    local_translation: local.translation,
                    local_rotation: local.rotation,
                    local_scale: local.scale,
                    translation_delta: subtract_vec3(sampled.translation, rest.translation),
                    rotation_delta: quaternion_mul(
                        sampled.rotation,
                        quaternion_inverse(rest.rotation),
                    ),
                    scale: divide_vec3(sampled.scale, rest.scale),
                })
            })
            .collect()
    }

    fn animated_node_index_for_name(&self, node_name: &str) -> Option<usize> {
        self.tracks
            .iter()
            .find(|track| track.node_name == node_name)
            .map(|track| track.node_index)
    }
}

impl BiomesAnimationTrack {
    fn sample_value(&self, time_sec: f32) -> [f32; 4] {
        if self.times.is_empty() || self.values.is_empty() {
            return [0.0, 0.0, 0.0, 1.0];
        }
        if self.times.len() == 1 || time_sec <= self.times[0] {
            return self.values[0];
        }
        for index in 0..self.times.len().saturating_sub(1) {
            let start = self.times[index];
            let end = self.times[index + 1];
            if time_sec <= end {
                let span = end - start;
                let t = if span.abs() > f32::EPSILON {
                    ((time_sec - start) / span).clamp(0.0, 1.0)
                } else {
                    0.0
                };
                return match self.path {
                    BiomesAnimationTransformPath::Rotation => {
                        slerp_quaternion(self.values[index], self.values[index + 1], t)
                    }
                    BiomesAnimationTransformPath::Translation
                    | BiomesAnimationTransformPath::Scale => {
                        lerp_value4(self.values[index], self.values[index + 1], t)
                    }
                };
            }
        }
        *self.values.last().unwrap_or(&self.values[0])
    }
}

pub(crate) fn default_avatar_appearance() -> BiomesAvatarAppearance {
    BiomesAvatarAppearance {
        skin_color_id: "skin_color_3".to_string(),
        eye_color_id: "eye_color_0".to_string(),
        hair_color_id: "hair_color_8".to_string(),
        head_id: "androgenous".to_string(),
        hair_id: Some("clean".to_string()),
        face_id: None,
        ears_id: None,
        hat_id: None,
        neck_id: None,
        top_id: Some("t_shirt".to_string()),
        bottoms_id: Some("jeans".to_string()),
        outerwear_id: None,
        hands_id: None,
        feet_id: Some("laced_low_tops".to_string()),
        robot_id: None,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BiomesAvatarOptionCategory {
    SkinColor,
    EyeColor,
    HairStyle,
    HairColor,
    HeadStyle,
    Face,
    Ears,
    Hat,
    Neck,
    Top,
    Bottoms,
    Outerwear,
    Hands,
    Feet,
    Robot,
}

impl BiomesAvatarOptionCategory {
    const ALL: [Self; 15] = [
        Self::SkinColor,
        Self::EyeColor,
        Self::HairStyle,
        Self::HairColor,
        Self::HeadStyle,
        Self::Face,
        Self::Ears,
        Self::Hat,
        Self::Neck,
        Self::Top,
        Self::Bottoms,
        Self::Outerwear,
        Self::Hands,
        Self::Feet,
        Self::Robot,
    ];

    fn from_index(index: usize) -> Option<Self> {
        Self::ALL.get(index).copied()
    }

    pub(crate) fn key(self) -> &'static str {
        match self {
            Self::SkinColor => "skin_color",
            Self::EyeColor => "eye_color",
            Self::HairStyle => "hair_style",
            Self::HairColor => "hair_color",
            Self::HeadStyle => "head_style",
            Self::Face => "face",
            Self::Ears => "ears",
            Self::Hat => "hat",
            Self::Neck => "neck",
            Self::Top => "top",
            Self::Bottoms => "bottoms",
            Self::Outerwear => "outerwear",
            Self::Hands => "hands",
            Self::Feet => "feet",
            Self::Robot => "robot",
        }
    }

    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::SkinColor => "Skin",
            Self::EyeColor => "Eyes",
            Self::HairStyle => "Hair",
            Self::HairColor => "Hair Color",
            Self::HeadStyle => "Head",
            Self::Face => "Face",
            Self::Ears => "Ears",
            Self::Hat => "Hat",
            Self::Neck => "Neck",
            Self::Top => "Top",
            Self::Bottoms => "Bottoms",
            Self::Outerwear => "Outerwear",
            Self::Hands => "Hands",
            Self::Feet => "Feet",
            Self::Robot => "Robot",
        }
    }

    fn slot(self) -> Option<BiomesWearableSlot> {
        match self {
            Self::HairStyle => Some(BiomesWearableSlot::Hair),
            Self::HeadStyle => Some(BiomesWearableSlot::Head),
            Self::Face => Some(BiomesWearableSlot::Face),
            Self::Ears => Some(BiomesWearableSlot::Ears),
            Self::Hat => Some(BiomesWearableSlot::Hat),
            Self::Neck => Some(BiomesWearableSlot::Neck),
            Self::Top => Some(BiomesWearableSlot::Top),
            Self::Bottoms => Some(BiomesWearableSlot::Bottoms),
            Self::Outerwear => Some(BiomesWearableSlot::Outerwear),
            Self::Hands => Some(BiomesWearableSlot::Hands),
            Self::Feet => Some(BiomesWearableSlot::Feet),
            Self::Robot => Some(BiomesWearableSlot::Robot),
            Self::SkinColor | Self::EyeColor | Self::HairColor => None,
        }
    }

    fn has_none_option(self) -> bool {
        matches!(
            self,
            Self::HairStyle
                | Self::Face
                | Self::Ears
                | Self::Hat
                | Self::Neck
                | Self::Top
                | Self::Bottoms
                | Self::Outerwear
                | Self::Hands
                | Self::Feet
                | Self::Robot
        )
    }
}

const BIOMES_SKIN_COLOR_IDS: [&str; 18] = [
    "skin_color_0",
    "skin_color_1",
    "skin_color_2",
    "skin_color_3",
    "skin_color_4",
    "skin_color_5",
    "skin_color_6",
    "skin_color_7",
    "skin_color_8",
    "skin_color_9",
    "skin_color_10",
    "skin_color_11",
    "skin_color_12",
    "skin_color_13",
    "skin_color_14",
    "skin_color_15",
    "skin_color_16",
    "skin_color_17",
];
const BIOMES_EYE_COLOR_IDS: [&str; 18] = [
    "eye_color_0",
    "eye_color_1",
    "eye_color_2",
    "eye_color_3",
    "eye_color_4",
    "eye_color_5",
    "eye_color_6",
    "eye_color_7",
    "eye_color_8",
    "eye_color_9",
    "eye_color_10",
    "eye_color_11",
    "eye_color_12",
    "eye_color_13",
    "eye_color_14",
    "eye_color_15",
    "eye_color_16",
    "eye_color_17",
];
const BIOMES_HAIR_COLOR_IDS: [&str; 18] = [
    "hair_color_0",
    "hair_color_1",
    "hair_color_2",
    "hair_color_3",
    "hair_color_4",
    "hair_color_5",
    "hair_color_6",
    "hair_color_7",
    "hair_color_8",
    "hair_color_9",
    "hair_color_10",
    "hair_color_11",
    "hair_color_12",
    "hair_color_13",
    "hair_color_14",
    "hair_color_15",
    "hair_color_16",
    "hair_color_17",
];

pub(crate) fn avatar_creator_category_count() -> usize {
    BiomesAvatarOptionCategory::ALL.len()
}

pub(crate) fn avatar_creator_category_key(index: usize) -> Option<&'static str> {
    BiomesAvatarOptionCategory::from_index(index).map(BiomesAvatarOptionCategory::key)
}

pub(crate) fn avatar_creator_category_label(index: usize) -> Option<&'static str> {
    BiomesAvatarOptionCategory::from_index(index).map(BiomesAvatarOptionCategory::label)
}

pub(crate) fn avatar_creator_option_count(category_index: usize) -> usize {
    let Some(category) = BiomesAvatarOptionCategory::from_index(category_index) else {
        return 0;
    };
    match category {
        BiomesAvatarOptionCategory::SkinColor => BIOMES_SKIN_COLOR_IDS.len(),
        BiomesAvatarOptionCategory::EyeColor => BIOMES_EYE_COLOR_IDS.len(),
        BiomesAvatarOptionCategory::HairColor => BIOMES_HAIR_COLOR_IDS.len(),
        _ => {
            let base = usize::from(category.has_none_option());
            category
                .slot()
                .map(|slot| base + available_wearable_ids(slot).len())
                .unwrap_or(0)
        }
    }
}

pub(crate) fn avatar_creator_option_label(
    category_index: usize,
    option_index: usize,
) -> Option<String> {
    let category = BiomesAvatarOptionCategory::from_index(category_index)?;
    if category.has_none_option() && option_index == 0 {
        return Some("None".to_string());
    }
    match category {
        BiomesAvatarOptionCategory::SkinColor => BIOMES_SKIN_COLOR_IDS
            .get(option_index)
            .map(|id| color_option_label("Skin", id)),
        BiomesAvatarOptionCategory::EyeColor => BIOMES_EYE_COLOR_IDS
            .get(option_index)
            .map(|id| color_option_label("Eye", id)),
        BiomesAvatarOptionCategory::HairColor => BIOMES_HAIR_COLOR_IDS
            .get(option_index)
            .map(|id| color_option_label("Hair", id)),
        _ => {
            let offset = usize::from(category.has_none_option());
            category
                .slot()
                .and_then(|slot| {
                    available_wearable_ids(slot)
                        .get(option_index - offset)
                        .cloned()
                })
                .map(|id| humanize_biomes_id(&id))
        }
    }
}

pub(crate) fn avatar_creator_option_color(
    category_index: usize,
    option_index: usize,
) -> Option<Color> {
    let category = BiomesAvatarOptionCategory::from_index(category_index)?;
    match category {
        BiomesAvatarOptionCategory::SkinColor => BIOMES_SKIN_COLOR_IDS
            .get(option_index)
            .map(|id| skin_icon_color(id)),
        BiomesAvatarOptionCategory::EyeColor => BIOMES_EYE_COLOR_IDS
            .get(option_index)
            .map(|id| eye_icon_color(id)),
        BiomesAvatarOptionCategory::HairColor => BIOMES_HAIR_COLOR_IDS
            .get(option_index)
            .map(|id| hair_icon_color(id)),
        _ => None,
    }
}

pub(crate) fn avatar_creator_option_thumbnail_path(
    category_index: usize,
    option_index: usize,
) -> Option<String> {
    let category = BiomesAvatarOptionCategory::from_index(category_index)?;
    if category.has_none_option() && option_index == 0 {
        return None;
    }
    match category {
        BiomesAvatarOptionCategory::SkinColor
        | BiomesAvatarOptionCategory::EyeColor
        | BiomesAvatarOptionCategory::HairColor => None,
        _ => {
            let slot = category.slot()?;
            let option_offset = usize::from(category.has_none_option());
            let id_index = option_index.checked_sub(option_offset)?;
            let id = available_wearable_ids(slot).get(id_index)?.clone();
            Some(format!(
                "res://assets/biomes/thumbnails/{}/{}.png",
                slot.name(),
                id
            ))
        }
    }
}

pub(crate) fn avatar_creator_selected_option_index(
    appearance: &BiomesAvatarAppearance,
    category_index: usize,
) -> i32 {
    let Some(category) = BiomesAvatarOptionCategory::from_index(category_index) else {
        return -1;
    };
    let index = match category {
        BiomesAvatarOptionCategory::SkinColor => {
            find_id_index(&BIOMES_SKIN_COLOR_IDS, &appearance.skin_color_id)
        }
        BiomesAvatarOptionCategory::EyeColor => {
            find_id_index(&BIOMES_EYE_COLOR_IDS, &appearance.eye_color_id)
        }
        BiomesAvatarOptionCategory::HairColor => {
            find_id_index(&BIOMES_HAIR_COLOR_IDS, &appearance.hair_color_id)
        }
        BiomesAvatarOptionCategory::HeadStyle => category
            .slot()
            .and_then(|slot| find_dynamic_id_index(slot, Some(&appearance.head_id), false)),
        _ => category.slot().and_then(|slot| {
            find_dynamic_id_index(
                slot,
                appearance.wearable_id_for_slot(slot),
                category.has_none_option(),
            )
        }),
    };
    index.map(|value| value as i32).unwrap_or(-1)
}

pub(crate) fn avatar_creator_select_option(
    appearance: &mut BiomesAvatarAppearance,
    category_index: usize,
    option_index: usize,
) -> bool {
    let Some(category) = BiomesAvatarOptionCategory::from_index(category_index) else {
        return false;
    };
    match category {
        BiomesAvatarOptionCategory::SkinColor => set_string_from_ids(
            &mut appearance.skin_color_id,
            &BIOMES_SKIN_COLOR_IDS,
            option_index,
        ),
        BiomesAvatarOptionCategory::EyeColor => set_string_from_ids(
            &mut appearance.eye_color_id,
            &BIOMES_EYE_COLOR_IDS,
            option_index,
        ),
        BiomesAvatarOptionCategory::HairColor => set_string_from_ids(
            &mut appearance.hair_color_id,
            &BIOMES_HAIR_COLOR_IDS,
            option_index,
        ),
        _ => {
            let Some(slot) = category.slot() else {
                return false;
            };
            let ids = available_wearable_ids(slot);
            if category.has_none_option() && option_index == 0 {
                appearance.set_wearable_id_for_slot(slot, None);
                return true;
            }
            let offset = usize::from(category.has_none_option());
            let Some(id) = ids.get(option_index.saturating_sub(offset)).cloned() else {
                return false;
            };
            appearance.set_wearable_id_for_slot(slot, Some(id));
            true
        }
    }
}

pub(crate) fn avatar_appearance_label(appearance: &BiomesAvatarAppearance) -> String {
    format!(
        "{} / {} / {}",
        humanize_biomes_id(&appearance.skin_color_id),
        appearance
            .hair_id
            .as_deref()
            .map(humanize_biomes_id)
            .unwrap_or_else(|| "No Hair".to_string()),
        humanize_biomes_id(&appearance.head_id)
    )
}

impl BiomesAvatarAppearance {
    fn wearable_id_for_slot(&self, slot: BiomesWearableSlot) -> Option<&String> {
        match slot {
            BiomesWearableSlot::Head => Some(&self.head_id),
            BiomesWearableSlot::Hair => self.hair_id.as_ref(),
            BiomesWearableSlot::Face => self.face_id.as_ref(),
            BiomesWearableSlot::Ears => self.ears_id.as_ref(),
            BiomesWearableSlot::Hat => self.hat_id.as_ref(),
            BiomesWearableSlot::Neck => self.neck_id.as_ref(),
            BiomesWearableSlot::Top => self.top_id.as_ref(),
            BiomesWearableSlot::Bottoms => self.bottoms_id.as_ref(),
            BiomesWearableSlot::Outerwear => self.outerwear_id.as_ref(),
            BiomesWearableSlot::Hands => self.hands_id.as_ref(),
            BiomesWearableSlot::Feet => self.feet_id.as_ref(),
            BiomesWearableSlot::Robot => self.robot_id.as_ref(),
            BiomesWearableSlot::Base | BiomesWearableSlot::HairWithHat => None,
        }
    }

    fn set_wearable_id_for_slot(&mut self, slot: BiomesWearableSlot, id: Option<String>) {
        match slot {
            BiomesWearableSlot::Head => {
                if let Some(id) = id {
                    self.head_id = id;
                }
            }
            BiomesWearableSlot::Hair => self.hair_id = id,
            BiomesWearableSlot::Face => self.face_id = id,
            BiomesWearableSlot::Ears => self.ears_id = id,
            BiomesWearableSlot::Hat => self.hat_id = id,
            BiomesWearableSlot::Neck => self.neck_id = id,
            BiomesWearableSlot::Top => self.top_id = id,
            BiomesWearableSlot::Bottoms => self.bottoms_id = id,
            BiomesWearableSlot::Outerwear => self.outerwear_id = id,
            BiomesWearableSlot::Hands => self.hands_id = id,
            BiomesWearableSlot::Feet => self.feet_id = id,
            BiomesWearableSlot::Robot => self.robot_id = id,
            BiomesWearableSlot::Base | BiomesWearableSlot::HairWithHat => {}
        }
    }
}

pub(crate) fn load_avatar_joint_mesh(
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
    scale: f32,
) -> Result<Gd<godot::classes::Mesh>, String> {
    let base_scene_model = base_joint_scene_model(joint)?;
    let mut base_voxels =
        scene_colored_voxels_from_biomes_scene_model(&base_scene_model, appearance, joint);
    if joint == BiomesAvatarJoint::Head {
        let head_voxels = wearable_joint_voxels(
            BiomesWearableSlot::Head,
            &appearance.head_id,
            joint,
            appearance,
        );
        if !head_voxels.is_empty() {
            base_voxels = head_voxels;
        }
    }
    let wearable_layers = selected_wearable_voxel_layers_for_joint(joint, appearance);
    let voxels = compose_avatar_joint_voxels(base_voxels, joint, wearable_layers);
    let voxels = dedupe_scene_colored_voxels(voxels);
    Ok(
        crate::vox::build_scene_colored_voxels_mesh(&voxels, scale)
            .upcast::<godot::classes::Mesh>(),
    )
}

fn base_joint_scene_model(joint: BiomesAvatarJoint) -> Result<VoxSceneModel, String> {
    let scene_models = crate::vox::load_vox_scene_models_from_res(BIOMES_BASE_MODEL_PATH)?;
    scene_models
        .into_iter()
        .find(|scene_model| is_joint_base_scene_model(scene_model, joint))
        .ok_or_else(|| format!("Biomes base model is missing joint {}", joint.name()))
}

fn selected_wearable_voxel_layers_for_joint(
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
) -> Vec<(BiomesWearableSlot, Vec<SceneColoredVoxel>)> {
    let mut layers = Vec::new();
    for (slot, id) in selected_wearables_in_biomes_order(appearance) {
        let voxels = wearable_joint_voxels(slot, &id, joint, appearance);
        if !voxels.is_empty() {
            layers.push((slot, voxels));
        }
    }
    layers
}

fn compose_avatar_joint_voxels(
    mut voxels: Vec<SceneColoredVoxel>,
    joint: BiomesAvatarJoint,
    wearable_layers: Vec<(BiomesWearableSlot, Vec<SceneColoredVoxel>)>,
) -> Vec<SceneColoredVoxel> {
    for (slot, wearable_voxels) in wearable_layers {
        if wearable_slot_masks_lower_layers(slot, joint) {
            voxels = mask_voxels_under_wearable_shell(voxels, &wearable_voxels);
        }
        voxels.extend(wearable_voxels);
    }
    voxels
}

fn mask_voxels_under_wearable_shell(
    lower_voxels: Vec<SceneColoredVoxel>,
    wearable_voxels: &[SceneColoredVoxel],
) -> Vec<SceneColoredVoxel> {
    let occluders = wearable_voxels
        .iter()
        .map(|voxel| voxel.center)
        .collect::<BTreeSet<_>>();
    if occluders.is_empty() {
        return lower_voxels;
    }
    lower_voxels
        .into_iter()
        .filter(|voxel| !wearable_occludes_lower_voxel(voxel.center, &occluders))
        .collect()
}

fn wearable_slot_masks_lower_layers(slot: BiomesWearableSlot, joint: BiomesAvatarJoint) -> bool {
    match slot {
        BiomesWearableSlot::Hair | BiomesWearableSlot::HairWithHat | BiomesWearableSlot::Hat => {
            joint == BiomesAvatarJoint::Head
        }
        BiomesWearableSlot::Top | BiomesWearableSlot::Outerwear => matches!(
            joint,
            BiomesAvatarJoint::Chest
                | BiomesAvatarJoint::Waist
                | BiomesAvatarJoint::LArm
                | BiomesAvatarJoint::RArm
                | BiomesAvatarJoint::LForearm
                | BiomesAvatarJoint::RForearm
        ),
        BiomesWearableSlot::Bottoms => matches!(
            joint,
            BiomesAvatarJoint::Waist
                | BiomesAvatarJoint::LThigh
                | BiomesAvatarJoint::RThigh
                | BiomesAvatarJoint::LLeg
                | BiomesAvatarJoint::RLeg
        ),
        BiomesWearableSlot::Hands => matches!(
            joint,
            BiomesAvatarJoint::LForearm
                | BiomesAvatarJoint::RForearm
                | BiomesAvatarJoint::LHand
                | BiomesAvatarJoint::RHand
        ),
        BiomesWearableSlot::Feet => matches!(
            joint,
            BiomesAvatarJoint::LLeg
                | BiomesAvatarJoint::RLeg
                | BiomesAvatarJoint::LFoot
                | BiomesAvatarJoint::RFoot
        ),
        BiomesWearableSlot::Robot => true,
        BiomesWearableSlot::Neck => {
            matches!(joint, BiomesAvatarJoint::Head | BiomesAvatarJoint::Chest)
        }
        BiomesWearableSlot::Base
        | BiomesWearableSlot::Head
        | BiomesWearableSlot::Face
        | BiomesWearableSlot::Ears => false,
    }
}

fn wearable_occludes_lower_voxel(
    lower_center: (i32, i32, i32),
    occluders: &BTreeSet<(i32, i32, i32)>,
) -> bool {
    occluders.iter().any(|center| {
        (center.0 - lower_center.0).abs() <= WEARABLE_BASE_OCCLUSION_RADIUS
            && (center.1 - lower_center.1).abs() <= WEARABLE_BASE_OCCLUSION_RADIUS
            && (center.2 - lower_center.2).abs() <= WEARABLE_BASE_OCCLUSION_RADIUS
    })
}

fn selected_wearables_in_biomes_order(
    appearance: &BiomesAvatarAppearance,
) -> Vec<(BiomesWearableSlot, String)> {
    let mut selected = Vec::new();
    let selected_hair = selected_hair_slot(appearance);

    for slot in BIOMES_CHARACTER_WEARABLE_SLOTS {
        match slot {
            BiomesWearableSlot::Base | BiomesWearableSlot::Head => {}
            BiomesWearableSlot::Hair | BiomesWearableSlot::HairWithHat => {
                if selected_hair
                    .as_ref()
                    .is_some_and(|(hair_slot, _)| *hair_slot == slot)
                {
                    if let Some((hair_slot, id)) = selected_hair.as_ref() {
                        selected.push((*hair_slot, id.clone()));
                    }
                }
            }
            _ => {
                if let Some(id) = appearance.wearable_id_for_slot(slot) {
                    selected.push((slot, id.clone()));
                }
            }
        }
    }

    selected
}

fn selected_hair_slot(appearance: &BiomesAvatarAppearance) -> Option<(BiomesWearableSlot, String)> {
    let hair_id = appearance.hair_id.as_deref()?;
    if appearance.hat_id.is_some() {
        let with_hat_id = format!("{hair_id}_with_hat");
        if wearable_asset_exists(BiomesWearableSlot::HairWithHat, &with_hat_id) {
            return Some((BiomesWearableSlot::HairWithHat, with_hat_id));
        }
    }
    Some((BiomesWearableSlot::Hair, hair_id.to_string()))
}

fn wearable_joint_voxels(
    slot: BiomesWearableSlot,
    id: &str,
    joint: BiomesAvatarJoint,
    appearance: &BiomesAvatarAppearance,
) -> Vec<SceneColoredVoxel> {
    let path = wearable_asset_res_path(slot, id);
    let Ok(scene_models) = crate::vox::load_vox_scene_models_from_res(&path) else {
        return Vec::new();
    };
    let base_translation = joint.base_scene_translation();
    let mut voxels = Vec::new();
    for scene_model in scene_models {
        if !scene_model_is_visible_joint_layer(&scene_model, joint) {
            continue;
        }
        let offset = (
            scene_model.translation.0 - base_translation.0,
            scene_model.translation.1 - base_translation.1,
            scene_model.translation.2 - base_translation.2,
        );
        voxels.extend(scene_colored_voxels_from_biomes_model_transform(
            &scene_model.model,
            appearance,
            scene_model.rotation,
            offset,
        ));
    }
    voxels
}

fn scene_model_is_visible_joint_layer(
    scene_model: &VoxSceneModel,
    joint: BiomesAvatarJoint,
) -> bool {
    !scene_model.hidden && scene_model.layer_name.as_deref() == Some(joint.name())
}

#[allow(dead_code)]
fn nearest_joint_for_scene_translation(translation: (i32, i32, i32)) -> BiomesAvatarJoint {
    BIOMES_CHARACTER_JOINT_ORDERING
        .iter()
        .copied()
        .min_by_key(|joint| {
            let base = joint.base_scene_translation();
            let dx = translation.0 - base.0;
            let dy = translation.1 - base.1;
            let dz = translation.2 - base.2;
            dx * dx + dy * dy + dz * dz
        })
        .unwrap_or(BiomesAvatarJoint::Head)
}

#[allow(dead_code)]
fn is_base_scene_model(scene_model: &VoxSceneModel) -> bool {
    BIOMES_CHARACTER_JOINT_ORDERING
        .iter()
        .any(|joint| is_joint_base_scene_model(scene_model, *joint))
}

fn is_joint_base_scene_model(scene_model: &VoxSceneModel, joint: BiomesAvatarJoint) -> bool {
    scene_model.layer_name.as_deref() == Some(joint.name())
        && scene_model.translation == joint.base_scene_translation()
        && scene_model.model.voxels.len() == joint.base_model_voxel_count()
}

fn dedupe_scene_colored_voxels(voxels: Vec<SceneColoredVoxel>) -> Vec<SceneColoredVoxel> {
    let mut by_position = BTreeMap::new();
    for voxel in voxels {
        by_position.insert(voxel.center, voxel.color);
    }
    by_position
        .into_iter()
        .map(|(center, color)| SceneColoredVoxel { center, color })
        .collect()
}

fn available_wearable_ids(slot: BiomesWearableSlot) -> Vec<String> {
    let Some(path) = wearable_slot_absolute_path(slot) else {
        return Vec::new();
    };
    let Ok(entries) = std::fs::read_dir(path) else {
        return Vec::new();
    };
    let mut ids = entries
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("vox") {
                return None;
            }
            if !wearable_asset_has_visible_joint_layer(&path) {
                return None;
            }
            path.file_stem()?.to_str().map(str::to_string)
        })
        .collect::<Vec<_>>();
    ids.sort();
    ids
}

fn wearable_asset_has_visible_joint_layer(path: &Path) -> bool {
    let Ok(scene_models) = crate::vox::load_vox_scene_models_from_path(path) else {
        return false;
    };
    scene_models.iter().any(|scene_model| {
        !scene_model.hidden
            && scene_model
                .layer_name
                .as_deref()
                .is_some_and(is_biomes_joint_layer_name)
    })
}

fn is_biomes_joint_layer_name(name: &str) -> bool {
    BIOMES_CHARACTER_JOINT_ORDERING
        .iter()
        .any(|joint| joint.name() == name)
}

fn wearable_asset_exists(slot: BiomesWearableSlot, id: &str) -> bool {
    wearable_slot_absolute_path(slot)
        .map(|dir| {
            let path = dir.join(format!("{id}.vox"));
            path.is_file() && wearable_asset_has_visible_joint_layer(&path)
        })
        .unwrap_or(false)
}

fn wearable_asset_res_path(slot: BiomesWearableSlot, id: &str) -> String {
    format!("res://assets/biomes/wearables/{}/{}.vox", slot.name(), id)
}

fn wearable_slot_absolute_path(slot: BiomesWearableSlot) -> Option<PathBuf> {
    biomes_res_absolute_path(&format!("res://assets/biomes/wearables/{}", slot.name()))
}

fn biomes_res_absolute_path(res_path: &str) -> Option<PathBuf> {
    let relative = res_path.strip_prefix("res://")?;
    let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../")
        .join(relative);
    if manifest_path.exists() {
        return Some(manifest_path);
    }
    #[cfg(test)]
    {
        return None;
    }
    #[cfg(not(test))]
    Some(PathBuf::from(
        ProjectSettings::singleton()
            .globalize_path(res_path)
            .to_string(),
    ))
}

fn color_option_label(prefix: &str, id: &str) -> String {
    let suffix = id.rsplit('_').next().unwrap_or("0");
    let number = suffix.parse::<usize>().unwrap_or(0) + 1;
    format!("{prefix} {number:02}")
}

fn skin_icon_color(id: &str) -> Color {
    skin_palette(id)[2]
}

fn eye_icon_color(id: &str) -> Color {
    eye_palette(id)[2]
}

fn hair_icon_color(id: &str) -> Color {
    hair_palette(id)[2]
}

fn humanize_biomes_id(id: &str) -> String {
    id.split('_')
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn find_id_index(ids: &[&str], id: &str) -> Option<usize> {
    ids.iter().position(|candidate| *candidate == id)
}

fn find_dynamic_id_index(
    slot: BiomesWearableSlot,
    selected_id: Option<&String>,
    has_none_option: bool,
) -> Option<usize> {
    let Some(selected_id) = selected_id else {
        return has_none_option.then_some(0);
    };
    let offset = usize::from(has_none_option);
    available_wearable_ids(slot)
        .iter()
        .position(|candidate| candidate == selected_id)
        .map(|index| index + offset)
}

fn set_string_from_ids(target: &mut String, ids: &[&str], index: usize) -> bool {
    let Some(id) = ids.get(index) else {
        return false;
    };
    *target = (*id).to_string();
    true
}

pub(crate) fn load_biomes_animation_catalog_from_res() -> Result<BiomesAnimationCatalog, String> {
    let absolute_path =
        ProjectSettings::singleton().globalize_path(BIOMES_CHARACTER_ANIMATIONS_PATH);
    let source = std::fs::read_to_string(absolute_path.to_string())
        .map_err(|err| format!("failed to read {BIOMES_CHARACTER_ANIMATIONS_PATH}: {err}"))?;
    parse_biomes_animation_catalog(&source)
}

pub(crate) fn parse_biomes_animation_catalog(
    source: &str,
) -> Result<BiomesAnimationCatalog, String> {
    let nodes = parse_gltf_nodes(source)?;
    let buffer_views = parse_gltf_buffer_views(source)?;
    let accessors = parse_gltf_accessors(source)?;
    let buffer = parse_gltf_embedded_buffer(source)?;
    let animations = extract_json_array_field(source, "animations")?;
    let mut clips = Vec::new();
    for animation in split_top_level_json_objects(animations)? {
        let file_animation_name = parse_json_string_field(animation, "name")?;
        let samplers = extract_json_array_field(animation, "samplers")?;
        let channels = extract_json_array_field(animation, "channels")?;
        let sampler_objects = split_top_level_json_objects(samplers)?;
        let channel_objects = split_top_level_json_objects(channels)?;
        let gltf_samplers = sampler_objects
            .iter()
            .map(|sampler| parse_gltf_animation_sampler(sampler))
            .collect::<Result<Vec<_>, _>>()?;
        let channel_count = channel_objects.len();
        let mut duration_sec = 0.0f32;
        let mut tracks = Vec::new();
        for channel in &channel_objects {
            let track = parse_gltf_animation_track(
                channel,
                &gltf_samplers,
                &nodes,
                &accessors,
                &buffer_views,
                &buffer,
            )?;
            if let Some(last_time) = track.times.last().copied() {
                duration_sec = duration_sec.max(last_time);
            }
            tracks.push(track);
        }
        if tracks.is_empty() {
            return Err(format!(
                "Biomes animation {file_animation_name} has no sampled tracks"
            ));
        }
        clips.push(BiomesAnimationClip {
            file_animation_name,
            duration_sec,
            sampler_count: sampler_objects.len(),
            channel_count,
            tracks,
        });
    }
    if clips.is_empty() {
        return Err("Biomes animation GLTF has no animations".to_string());
    }
    Ok(BiomesAnimationCatalog { clips, nodes })
}

#[derive(Clone, Debug, PartialEq)]
struct GltfNode {
    name: String,
    parent: Option<usize>,
    children: Vec<usize>,
    translation: [f32; 3],
    rotation: [f32; 4],
    scale: [f32; 3],
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct GltfNodeTransform {
    translation: [f32; 3],
    rotation: [f32; 4],
    scale: [f32; 3],
}

#[derive(Clone, Debug, PartialEq)]
struct GltfBufferView {
    byte_offset: usize,
    byte_length: usize,
    byte_stride: Option<usize>,
}

#[derive(Clone, Debug, PartialEq)]
struct GltfAccessor {
    buffer_view: usize,
    byte_offset: usize,
    component_type: usize,
    count: usize,
    component_count: usize,
}

#[derive(Clone, Debug, PartialEq)]
struct GltfAnimationSampler {
    input: usize,
    output: usize,
}

impl GltfNodeTransform {
    fn identity() -> Self {
        Self {
            translation: [0.0, 0.0, 0.0],
            rotation: [0.0, 0.0, 0.0, 1.0],
            scale: [1.0, 1.0, 1.0],
        }
    }

    fn from_node(node: &GltfNode) -> Self {
        Self {
            translation: node.translation,
            rotation: node.rotation,
            scale: node.scale,
        }
    }

    fn set_path_value(&mut self, path: BiomesAnimationTransformPath, value: [f32; 4]) {
        match path {
            BiomesAnimationTransformPath::Translation => {
                self.translation = [value[0], value[1], value[2]];
            }
            BiomesAnimationTransformPath::Rotation => {
                self.rotation = normalize_quaternion(value);
            }
            BiomesAnimationTransformPath::Scale => {
                self.scale = [value[0], value[1], value[2]];
            }
        }
    }
}

impl From<GltfNodeTransform> for BiomesTransform {
    fn from(value: GltfNodeTransform) -> Self {
        Self {
            translation: value.translation,
            rotation: value.rotation,
            scale: value.scale,
        }
    }
}

fn parse_gltf_nodes(source: &str) -> Result<Vec<GltfNode>, String> {
    let nodes = extract_json_array_field(source, "nodes")?;
    let mut parsed_nodes = split_top_level_json_objects(nodes)?
        .into_iter()
        .map(|node| {
            Ok(GltfNode {
                name: parse_json_string_field(node, "name").unwrap_or_default(),
                parent: None,
                children: parse_json_optional_usize_array_field(node, "children")?,
                translation: parse_json_optional_f32_array_field(
                    node,
                    "translation",
                    [0.0, 0.0, 0.0],
                )?,
                rotation: normalize_quaternion(parse_json_optional_f32_array_field(
                    node,
                    "rotation",
                    [0.0, 0.0, 0.0, 1.0],
                )?),
                scale: parse_json_optional_f32_array_field(node, "scale", [1.0, 1.0, 1.0])?,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    for parent_index in 0..parsed_nodes.len() {
        let children = parsed_nodes[parent_index].children.clone();
        for child_index in children {
            let child = parsed_nodes.get_mut(child_index).ok_or_else(|| {
                format!("Biomes GLTF node {parent_index} references missing child {child_index}")
            })?;
            child.parent = Some(parent_index);
        }
    }

    Ok(parsed_nodes)
}

fn parse_gltf_buffer_views(source: &str) -> Result<Vec<GltfBufferView>, String> {
    let buffer_views = extract_json_array_field(source, "bufferViews")?;
    split_top_level_json_objects(buffer_views)?
        .into_iter()
        .map(|buffer_view| {
            Ok(GltfBufferView {
                byte_offset: parse_json_usize_field_or(buffer_view, "byteOffset", 0)?,
                byte_length: parse_json_usize_field(buffer_view, "byteLength")?,
                byte_stride: parse_json_optional_usize_field(buffer_view, "byteStride")?,
            })
        })
        .collect()
}

fn parse_gltf_accessors(source: &str) -> Result<Vec<GltfAccessor>, String> {
    let accessors = extract_json_array_field(source, "accessors")?;
    split_top_level_json_objects(accessors)?
        .into_iter()
        .map(|accessor| {
            let accessor_type = parse_json_string_field(accessor, "type")?;
            Ok(GltfAccessor {
                buffer_view: parse_json_usize_field(accessor, "bufferView")?,
                byte_offset: parse_json_usize_field_or(accessor, "byteOffset", 0)?,
                component_type: parse_json_usize_field(accessor, "componentType")?,
                count: parse_json_usize_field(accessor, "count")?,
                component_count: gltf_accessor_component_count(&accessor_type)?,
            })
        })
        .collect()
}

fn parse_gltf_embedded_buffer(source: &str) -> Result<Vec<u8>, String> {
    let buffers = extract_json_array_field(source, "buffers")?;
    let buffer_objects = split_top_level_json_objects(buffers)?;
    let Some(buffer) = buffer_objects.first() else {
        return Err("Biomes GLTF has no buffers".to_string());
    };
    let uri = parse_json_string_field(buffer, "uri")?;
    let prefix = "data:application/octet-stream;base64,";
    let Some(encoded) = uri.strip_prefix(prefix) else {
        return Err("Biomes GLTF buffer is not an embedded base64 octet stream".to_string());
    };
    decode_base64(encoded)
}

fn parse_gltf_animation_sampler(source: &str) -> Result<GltfAnimationSampler, String> {
    Ok(GltfAnimationSampler {
        input: parse_json_usize_field(source, "input")?,
        output: parse_json_usize_field(source, "output")?,
    })
}

fn parse_gltf_animation_track(
    source: &str,
    samplers: &[GltfAnimationSampler],
    nodes: &[GltfNode],
    accessors: &[GltfAccessor],
    buffer_views: &[GltfBufferView],
    buffer: &[u8],
) -> Result<BiomesAnimationTrack, String> {
    let sampler_index = parse_json_usize_field(source, "sampler")?;
    let sampler = samplers
        .get(sampler_index)
        .ok_or_else(|| format!("Biomes GLTF channel references missing sampler {sampler_index}"))?;
    let target = extract_json_object_field(source, "target")?;
    let node_index = parse_json_usize_field(target, "node")?;
    let node_name = nodes
        .get(node_index)
        .map(|node| node.name.clone())
        .ok_or_else(|| format!("Biomes GLTF channel references missing node {node_index}"))?;
    let path = parse_gltf_transform_path(&parse_json_string_field(target, "path")?)?;
    let times = read_gltf_accessor_f32_components(sampler.input, accessors, buffer_views, buffer)?
        .into_iter()
        .map(|value| value[0])
        .collect::<Vec<_>>();
    let values =
        read_gltf_accessor_f32_components(sampler.output, accessors, buffer_views, buffer)?;
    if times.len() != values.len() {
        return Err(format!(
            "Biomes GLTF track {node_name}/{path:?} has {} time keys and {} values",
            times.len(),
            values.len()
        ));
    }
    Ok(BiomesAnimationTrack {
        node_index,
        node_name,
        path,
        times,
        values,
    })
}

fn parse_gltf_transform_path(path: &str) -> Result<BiomesAnimationTransformPath, String> {
    match path {
        "translation" => Ok(BiomesAnimationTransformPath::Translation),
        "rotation" => Ok(BiomesAnimationTransformPath::Rotation),
        "scale" => Ok(BiomesAnimationTransformPath::Scale),
        _ => Err(format!("Biomes GLTF unsupported animation path '{path}'")),
    }
}

fn compute_gltf_global_transforms(
    nodes: &[GltfNode],
    local_transforms: &[GltfNodeTransform],
) -> Vec<GltfNodeTransform> {
    let mut global_transforms = vec![GltfNodeTransform::identity(); nodes.len()];
    let mut resolved = vec![false; nodes.len()];
    for node_index in 0..nodes.len() {
        compute_gltf_global_transform_at(
            node_index,
            nodes,
            local_transforms,
            &mut global_transforms,
            &mut resolved,
        );
    }
    global_transforms
}

fn compute_gltf_global_transform_at(
    node_index: usize,
    nodes: &[GltfNode],
    local_transforms: &[GltfNodeTransform],
    global_transforms: &mut [GltfNodeTransform],
    resolved: &mut [bool],
) -> GltfNodeTransform {
    if resolved.get(node_index).copied().unwrap_or(false) {
        return global_transforms[node_index];
    }
    let local = local_transforms
        .get(node_index)
        .copied()
        .unwrap_or_else(GltfNodeTransform::identity);
    let global = if let Some(parent_index) = nodes.get(node_index).and_then(|node| node.parent) {
        let parent = compute_gltf_global_transform_at(
            parent_index,
            nodes,
            local_transforms,
            global_transforms,
            resolved,
        );
        compose_gltf_transform(parent, local)
    } else {
        local
    };
    if let Some(target) = global_transforms.get_mut(node_index) {
        *target = global;
    }
    if let Some(target) = resolved.get_mut(node_index) {
        *target = true;
    }
    global
}

fn compose_gltf_transform(
    parent: GltfNodeTransform,
    child: GltfNodeTransform,
) -> GltfNodeTransform {
    let scaled_child_translation = multiply_vec3(child.translation, parent.scale);
    let rotated_child_translation =
        rotate_vec3_by_quaternion(parent.rotation, scaled_child_translation);
    GltfNodeTransform {
        translation: add_vec3(parent.translation, rotated_child_translation),
        rotation: quaternion_mul(parent.rotation, child.rotation),
        scale: multiply_vec3(parent.scale, child.scale),
    }
}

fn read_gltf_accessor_f32_components(
    accessor_index: usize,
    accessors: &[GltfAccessor],
    buffer_views: &[GltfBufferView],
    buffer: &[u8],
) -> Result<Vec<[f32; 4]>, String> {
    let accessor = accessors
        .get(accessor_index)
        .ok_or_else(|| format!("Biomes GLTF missing accessor {accessor_index}"))?;
    if accessor.component_type != 5126 {
        return Err(format!(
            "Biomes GLTF accessor {accessor_index} uses unsupported componentType {}",
            accessor.component_type
        ));
    }
    let buffer_view = buffer_views.get(accessor.buffer_view).ok_or_else(|| {
        format!(
            "Biomes GLTF accessor {accessor_index} references missing bufferView {}",
            accessor.buffer_view
        )
    })?;
    let element_bytes = accessor.component_count * std::mem::size_of::<f32>();
    if accessor.component_count > 4 {
        return Err(format!(
            "Biomes GLTF accessor {accessor_index} has unsupported animated component count {}",
            accessor.component_count
        ));
    }
    let stride = buffer_view.byte_stride.unwrap_or(element_bytes);
    if stride < element_bytes {
        return Err(format!(
            "Biomes GLTF accessor {accessor_index} stride {stride} is smaller than element size {element_bytes}"
        ));
    }

    let start = buffer_view.byte_offset + accessor.byte_offset;
    let mut values = Vec::with_capacity(accessor.count);
    for element_index in 0..accessor.count {
        let element_start = start + element_index * stride;
        let mut value = [0.0, 0.0, 0.0, 1.0];
        for component in 0..accessor.component_count {
            let byte_index = element_start + component * std::mem::size_of::<f32>();
            let bytes = buffer.get(byte_index..byte_index + 4).ok_or_else(|| {
                format!(
                    "Biomes GLTF accessor {accessor_index} reads past embedded buffer at byte {byte_index}"
                )
            })?;
            value[component] = f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        }
        values.push(value);
    }

    let byte_end = start + accessor.count.saturating_sub(1) * stride + element_bytes;
    let view_end = buffer_view.byte_offset + buffer_view.byte_length;
    if byte_end > view_end {
        return Err(format!(
            "Biomes GLTF accessor {accessor_index} exceeds bufferView bounds"
        ));
    }
    Ok(values)
}

fn gltf_accessor_component_count(accessor_type: &str) -> Result<usize, String> {
    match accessor_type {
        "SCALAR" => Ok(1),
        "VEC2" => Ok(2),
        "VEC3" => Ok(3),
        "VEC4" => Ok(4),
        "MAT2" => Ok(4),
        "MAT3" => Ok(9),
        "MAT4" => Ok(16),
        _ => Err(format!(
            "Biomes GLTF unsupported accessor type '{accessor_type}'"
        )),
    }
}

fn lerp_value4(a: [f32; 4], b: [f32; 4], t: f32) -> [f32; 4] {
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    ]
}

fn add_vec3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn subtract_vec3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn multiply_vec3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] * b[0], a[1] * b[1], a[2] * b[2]]
}

fn divide_vec3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        safe_divide_scale(a[0], b[0]),
        safe_divide_scale(a[1], b[1]),
        safe_divide_scale(a[2], b[2]),
    ]
}

fn safe_divide_scale(value: f32, divisor: f32) -> f32 {
    if value.is_finite() && divisor.is_finite() && divisor.abs() > f32::EPSILON {
        (value / divisor).clamp(0.25, 4.0)
    } else {
        1.0
    }
}

fn normalize_quaternion(value: [f32; 4]) -> [f32; 4] {
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

fn quaternion_inverse(value: [f32; 4]) -> [f32; 4] {
    let normalized = normalize_quaternion(value);
    [
        -normalized[0],
        -normalized[1],
        -normalized[2],
        normalized[3],
    ]
}

fn quaternion_mul(a: [f32; 4], b: [f32; 4]) -> [f32; 4] {
    normalize_quaternion(quaternion_mul_raw(a, b))
}

fn quaternion_mul_raw(a: [f32; 4], b: [f32; 4]) -> [f32; 4] {
    [
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    ]
}

fn rotate_vec3_by_quaternion(rotation: [f32; 4], value: [f32; 3]) -> [f32; 3] {
    let q = normalize_quaternion(rotation);
    let vector_quaternion = [value[0], value[1], value[2], 0.0];
    let rotated = quaternion_mul_raw(
        quaternion_mul_raw(q, vector_quaternion),
        quaternion_inverse(q),
    );
    [rotated[0], rotated[1], rotated[2]]
}

fn slerp_quaternion(a: [f32; 4], b: [f32; 4], t: f32) -> [f32; 4] {
    let a = normalize_quaternion(a);
    let mut b = normalize_quaternion(b);
    let mut dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
    if dot < 0.0 {
        dot = -dot;
        b = [-b[0], -b[1], -b[2], -b[3]];
    }
    if dot > 0.9995 {
        return normalize_quaternion(lerp_value4(a, b, t));
    }
    let theta_0 = dot.clamp(-1.0, 1.0).acos();
    let theta = theta_0 * t;
    let sin_theta = theta.sin();
    let sin_theta_0 = theta_0.sin();
    if sin_theta_0.abs() <= f32::EPSILON {
        return a;
    }
    let scale_a = theta.cos() - dot * sin_theta / sin_theta_0;
    let scale_b = sin_theta / sin_theta_0;
    normalize_quaternion([
        a[0] * scale_a + b[0] * scale_b,
        a[1] * scale_a + b[1] * scale_b,
        a[2] * scale_a + b[2] * scale_b,
        a[3] * scale_a + b[3] * scale_b,
    ])
}

fn decode_base64(source: &str) -> Result<Vec<u8>, String> {
    let mut output = Vec::with_capacity(source.len() * 3 / 4);
    let mut chunk = [0u8; 4];
    let mut chunk_len = 0usize;
    for byte in source.bytes().filter(|byte| !byte.is_ascii_whitespace()) {
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => 64,
            _ => return Err("Biomes GLTF buffer contains invalid base64 data".to_string()),
        };
        chunk[chunk_len] = value;
        chunk_len += 1;
        if chunk_len == 4 {
            if chunk[0] == 64 || chunk[1] == 64 {
                return Err("Biomes GLTF buffer has invalid base64 padding".to_string());
            }
            output.push((chunk[0] << 2) | (chunk[1] >> 4));
            if chunk[2] != 64 {
                output.push((chunk[1] << 4) | (chunk[2] >> 2));
            }
            if chunk[3] != 64 {
                output.push((chunk[2] << 6) | chunk[3]);
            }
            chunk_len = 0;
        }
    }
    if chunk_len != 0 {
        return Err("Biomes GLTF buffer has incomplete base64 data".to_string());
    }
    Ok(output)
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

fn extract_json_object_field<'a>(source: &'a str, field_name: &str) -> Result<&'a str, String> {
    let colon = find_json_field_colon(source, field_name)
        .ok_or_else(|| format!("Biomes GLTF JSON object field '{field_name}' is missing"))?;
    let open = skip_json_ws(source, colon + 1);
    if source.as_bytes().get(open).copied() != Some(b'{') {
        return Err(format!(
            "Biomes GLTF JSON field '{field_name}' is not an object"
        ));
    }
    let (inner, _) = extract_balanced_json(source, open, b'{', b'}')?;
    Ok(inner)
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

fn parse_json_usize_field_or(
    source: &str,
    field_name: &str,
    default: usize,
) -> Result<usize, String> {
    parse_json_optional_usize_field(source, field_name).map(|value| value.unwrap_or(default))
}

fn parse_json_optional_usize_field(
    source: &str,
    field_name: &str,
) -> Result<Option<usize>, String> {
    let Some(colon) = find_json_field_colon(source, field_name) else {
        return Ok(None);
    };
    let start = skip_json_ws(source, colon + 1);
    let (number, _) = parse_json_number_at(source, start)?;
    if number < 0.0 || number.fract() != 0.0 {
        return Err(format!(
            "Biomes GLTF JSON field '{field_name}' must be a non-negative integer"
        ));
    }
    Ok(Some(number as usize))
}

fn parse_json_optional_usize_array_field(
    source: &str,
    field_name: &str,
) -> Result<Vec<usize>, String> {
    let Some(array) = try_extract_json_array_field(source, field_name)? else {
        return Ok(Vec::new());
    };
    parse_top_level_json_numbers(array)?
        .into_iter()
        .map(|number| {
            if number < 0.0 || number.fract() != 0.0 {
                return Err(format!(
                    "Biomes GLTF JSON array field '{field_name}' must contain non-negative integers"
                ));
            }
            Ok(number as usize)
        })
        .collect()
}

fn parse_json_optional_f32_array_field<const N: usize>(
    source: &str,
    field_name: &str,
    default: [f32; N],
) -> Result<[f32; N], String> {
    let Some(array) = try_extract_json_array_field(source, field_name)? else {
        return Ok(default);
    };
    let values = parse_top_level_json_numbers(array)?;
    if values.len() != N {
        return Err(format!(
            "Biomes GLTF JSON array field '{field_name}' has {} values, expected {N}",
            values.len()
        ));
    }
    let mut output = default;
    output.copy_from_slice(&values);
    Ok(output)
}

fn parse_top_level_json_numbers(source: &str) -> Result<Vec<f32>, String> {
    let bytes = source.as_bytes();
    let mut values = Vec::new();
    let mut idx = 0usize;
    while idx < bytes.len() {
        idx = skip_json_ws_and_commas(source, idx);
        if idx >= bytes.len() {
            break;
        }
        let (number, end) = parse_json_number_at(source, idx)?;
        values.push(number);
        idx = end;
    }
    Ok(values)
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
    let bytes = source.as_bytes();
    let root_depth = if bytes.get(skip_json_ws(source, 0)).copied() == Some(b'{') {
        1
    } else {
        0
    };
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;
    let mut idx = 0usize;
    while idx < bytes.len() {
        let byte = bytes[idx];
        if in_string {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                in_string = false;
            }
            idx += 1;
            continue;
        }

        if byte == b'"' {
            if depth == root_depth && source[idx..].starts_with(&target) {
                let key_end = idx + target.len();
                let colon = skip_json_ws(source, key_end);
                if bytes.get(colon).copied() == Some(b':') {
                    return Some(colon);
                }
            }
            in_string = true;
            idx += 1;
            continue;
        }
        if byte == b'{' || byte == b'[' {
            depth += 1;
        } else if byte == b'}' || byte == b']' {
            depth = depth.saturating_sub(1);
        }
        idx += 1;
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

fn scene_colored_voxels_from_biomes_scene_model(
    scene_model: &VoxSceneModel,
    appearance: &BiomesAvatarAppearance,
    joint: BiomesAvatarJoint,
) -> Vec<SceneColoredVoxel> {
    let base_translation = joint.base_scene_translation();
    let offset = (
        scene_model.translation.0 - base_translation.0,
        scene_model.translation.1 - base_translation.1,
        scene_model.translation.2 - base_translation.2,
    );
    scene_colored_voxels_from_biomes_model_transform(
        &scene_model.model,
        appearance,
        scene_model.rotation,
        offset,
    )
}

fn scene_colored_voxels_from_biomes_model_transform(
    model: &VoxModel,
    appearance: &BiomesAvatarAppearance,
    rotation: VoxRotation,
    offset: (i32, i32, i32),
) -> Vec<SceneColoredVoxel> {
    let size = (
        model.size.0 as i32,
        model.size.1 as i32,
        model.size.2 as i32,
    );
    model
        .voxels
        .iter()
        .map(|voxel| {
            let local_center = (
                voxel.coord.x as i32 * 2 + 1 - size.0,
                voxel.coord.y as i32 * 2 + 1 - size.1,
                voxel.coord.z as i32 * 2 + 1 - size.2,
            );
            let rotated = apply_vox_rotation_to_center(rotation, local_center);
            SceneColoredVoxel {
                center: (
                    rotated.0 + offset.0 * 2,
                    rotated.1 + offset.1 * 2,
                    rotated.2 + offset.2 * 2,
                ),
                color: biomes_palette_color(model, voxel.color_index, appearance),
            }
        })
        .collect()
}

fn apply_vox_rotation_to_center(
    rotation: VoxRotation,
    local_center: (i32, i32, i32),
) -> (i32, i32, i32) {
    let values = [local_center.0, local_center.1, local_center.2];
    (
        rotation[0][0] * values[0] + rotation[0][1] * values[1] + rotation[0][2] * values[2],
        rotation[1][0] * values[0] + rotation[1][1] * values[1] + rotation[1][2] * values[2],
        rotation[2][0] * values[0] + rotation[2][1] * values[1] + rotation[2][2] * values[2],
    )
}

fn biomes_palette_color(
    model: &VoxModel,
    color_index: u8,
    appearance: &BiomesAvatarAppearance,
) -> Color {
    if let Some(offset) = palette_offset(color_index, SKIN_PALETTE_START, SKIN_PALETTE_LEN) {
        return skin_palette(&appearance.skin_color_id)[offset];
    }
    if let Some(offset) = palette_offset(color_index, HAIR_PALETTE_START, HAIR_PALETTE_LEN) {
        return hair_palette(&appearance.hair_color_id)[offset];
    }
    if let Some(offset) = palette_offset(color_index, EYE_PALETTE_START, EYE_PALETTE_LEN) {
        return eye_palette(&appearance.eye_color_id)[offset];
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
        "skin_color_3" => palette8([
            "#6e3636", "#c7a68d", "#b28667", "#99725b", "#876455", "#825b4f", "#755145", "#4b4b4b",
        ]),
        "skin_color_4" => palette8([
            "#441a21", "#936c5a", "#835e4b", "#6d4538", "#5f372e", "#532d24", "#4d2822", "#4b4b4b",
        ]),
        "skin_color_5" => palette8([
            "#350e13", "#815b4e", "#694135", "#56322a", "#492923", "#40251e", "#3a1f1a", "#4b4b4b",
        ]),
        "skin_color_6" => palette8([
            "#662e71", "#c086ff", "#a66fee", "#8b60cd", "#7a4fd1", "#7145c2", "#593c9d", "#4b4b4b",
        ]),
        "skin_color_7" => palette8([
            "#b84065", "#ffbdd5", "#fda6ce", "#ef8ebb", "#e479a2", "#d9698c", "#b45d7a", "#4b4b4b",
        ]),
        "skin_color_8" => palette8([
            "#6e1934", "#ff7464", "#e75045", "#b9342f", "#9d242e", "#8d212a", "#7d1e26", "#4b4b4b",
        ]),
        "skin_color_9" => palette8([
            "#842c2d", "#ffb372", "#fca054", "#ee8146", "#de694c", "#d35b45", "#b24d3b", "#4b4b4b",
        ]),
        "skin_color_10" => palette8([
            "#403c18", "#75cb50", "#50ae31", "#38862d", "#20722e", "#116925", "#185d23", "#4b4b4b",
        ]),
        "skin_color_11" => palette8([
            "#542b7d", "#61cef3", "#3ca9e8", "#498bdd", "#3672cb", "#1868b7", "#1f5da0", "#4b4b4b",
        ]),
        "skin_color_12" => palette8([
            "#8c5336", "#f4dfa9", "#efcf96", "#ecbd7a", "#cb9d62", "#b88956", "#a3754d", "#4b4b4b",
        ]),
        "skin_color_13" => palette8([
            "#424242", "#a0aca8", "#869a95", "#788482", "#637475", "#53676c", "#49595c", "#4b4b4b",
        ]),
        "skin_color_14" => palette8([
            "#2e1b21", "#554548", "#48383b", "#3b2c2e", "#332527", "#301f22", "#2a1a1e", "#4b4b4b",
        ]),
        "skin_color_15" => palette8([
            "#43596e", "#bbfdde", "#a2edcc", "#7dd6ad", "#59bb92", "#44a27f", "#3c907b", "#4b4b4b",
        ]),
        "skin_color_16" => palette8([
            "#514034", "#b7aa6f", "#a89c56", "#908d50", "#7f8146", "#6b7338", "#5e6433", "#4b4b4b",
        ]),
        "skin_color_17" => palette8([
            "#5d375b", "#c294ac", "#a97590", "#855670", "#734a63", "#5c3b50", "#4f3146", "#4b4b4b",
        ]),
        _ => palette8([
            "#6e3636", "#c7a68d", "#b28667", "#99725b", "#876455", "#825b4f", "#755145", "#4b4b4b",
        ]),
    }
}

fn eye_palette(id: &str) -> [Color; 7] {
    match id {
        "eye_color_0" => palette7([
            "#bbd8de", "#4b4b4b", "#6f3d2a", "#502a1d", "#3b1f1b", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_1" => palette7([
            "#bbd8de", "#4b4b4b", "#8b471d", "#6d2f0e", "#4c1905", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_2" => palette7([
            "#bbd8de", "#4b4b4b", "#bf7126", "#9a4b11", "#6f2b0c", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_3" => palette7([
            "#bbd8de", "#4b4b4b", "#b29400", "#8f5f00", "#593500", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_4" => palette7([
            "#bbd8de", "#4b4b4b", "#fc8a2b", "#d95508", "#a02e09", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_5" => palette7([
            "#bbd8de", "#4b4b4b", "#73828e", "#5a6775", "#404555", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_6" => palette7([
            "#bbd8de", "#4b4b4b", "#4d6f42", "#40441d", "#40241b", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_7" => palette7([
            "#bbd8de", "#4b4b4b", "#3f7d30", "#2a631f", "#2c3c2a", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_8" => palette7([
            "#bbd8de", "#4b4b4b", "#10b62c", "#18823a", "#1a5736", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_9" => palette7([
            "#bbd8de", "#4b4b4b", "#0bc2b6", "#178b96", "#1e606d", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_10" => palette7([
            "#bbd8de", "#4b4b4b", "#1c90c1", "#0a67a3", "#233f61", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_11" => palette7([
            "#bbd8de", "#4b4b4b", "#4863e3", "#3b37ad", "#2d2b5a", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_12" => palette7([
            "#bbd8de", "#4b4b4b", "#8b40b2", "#6f2f9d", "#3a254f", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_13" => palette7([
            "#bbd8de", "#4b4b4b", "#cb479f", "#9d2e89", "#632258", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_14" => palette7([
            "#e4dde9", "#4b4b4b", "#f18db6", "#c56083", "#95334c", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_15" => palette7([
            "#dcdbd4", "#4b4b4b", "#f8363a", "#ca1d29", "#8f1c30", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_16" => palette7([
            "#bbd8de", "#4b4b4b", "#89202d", "#6b1c29", "#441724", "#4b4b4b", "#4b4b4b",
        ]),
        "eye_color_17" => palette7([
            "#bbd8de", "#4b4b4b", "#2f2f44", "#232333", "#191919", "#4b4b4b", "#4b4b4b",
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
        "hair_color_1" => palette8([
            "#a4ef73", "#8ed860", "#7cc94f", "#6cbc43", "#52a72b", "#388e38", "#1a6e33", "#12522d",
        ]),
        "hair_color_2" => palette8([
            "#ce9ce4", "#bd8fd9", "#ac83cf", "#9b76c4", "#8969b9", "#67568e", "#4a446a", "#35305d",
        ]),
        "hair_color_3" => palette8([
            "#71dadd", "#59ccd1", "#41bec5", "#29b1b9", "#19a6ae", "#108b9e", "#266b7b", "#235464",
        ]),
        "hair_color_4" => palette8([
            "#e6f2f3", "#deeeef", "#d9ebed", "#d4e8eb", "#cee3e7", "#bad2d9", "#a4bac0", "#96a8ac",
        ]),
        "hair_color_5" => palette8([
            "#cce0e3", "#bfd6da", "#b3cad1", "#a3b8c0", "#98aab4", "#7f8c99", "#676f7b", "#4e545c",
        ]),
        "hair_color_6" => palette8([
            "#4d4c59", "#444450", "#3b3b4d", "#353546", "#2d2d3f", "#242434", "#1b1b26", "#141414",
        ]),
        "hair_color_7" => palette8([
            "#926757", "#8b5b4d", "#854f44", "#7f423e", "#7c3737", "#6d2f31", "#59232c", "#4d202c",
        ]),
        "hair_color_8" => palette8([
            "#a4693c", "#955b38", "#864f31", "#75452e", "#623a29", "#513123", "#3d251e", "#2e1c18",
        ]),
        "hair_color_9" => palette8([
            "#c7925b", "#c1824e", "#ba713f", "#a8663d", "#915c36", "#7e4a2e", "#683a28", "#503028",
        ]),
        "hair_color_10" => palette8([
            "#dbbd54", "#cfaf4b", "#c5a043", "#b88f3d", "#a87f2f", "#946c34", "#775535", "#5b3d25",
        ]),
        "hair_color_11" => palette8([
            "#feef9d", "#f7e48f", "#eed680", "#e6ca72", "#debd64", "#d0a853", "#b78b55", "#986e42",
        ]),
        "hair_color_12" => palette8([
            "#bba267", "#ab8f5f", "#977d5c", "#836d55", "#715b4b", "#5d4b42", "#4a3b36", "#3b2e2b",
        ]),
        "hair_color_13" => palette8([
            "#d6735c", "#c7604b", "#bf4939", "#b63b32", "#a62f2c", "#8d2225", "#7c1d2b", "#6b192c",
        ]),
        "hair_color_14" => palette8([
            "#d39950", "#ca8a48", "#c1753e", "#b86537", "#b5562f", "#a44529", "#8c3221", "#7a241e",
        ]),
        "hair_color_15" => palette8([
            "#ffce41", "#faba27", "#f8a50d", "#f09305", "#d77703", "#be5c00", "#a34300", "#903402",
        ]),
        "hair_color_16" => palette8([
            "#ccebfd", "#bad4f2", "#aec6eb", "#95a8e0", "#7d8bd5", "#6973cb", "#5255b1", "#4a448d",
        ]),
        "hair_color_17" => palette8([
            "#e0f58d", "#d3eb76", "#c8e351", "#b4db26", "#97cd10", "#7aba0c", "#56960f", "#427c0f",
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
        assert_eq!(BiomesAvatarJoint::Chest.skeleton_parent(), None);
        assert_eq!(BiomesAvatarJoint::Waist.skeleton_parent(), None);
        assert_eq!(
            BiomesAvatarJoint::LHand.skeleton_parent(),
            Some(BiomesAvatarJoint::LForearm)
        );
        assert_eq!(
            BiomesAvatarJoint::RHand.skeleton_parent(),
            Some(BiomesAvatarJoint::RForearm)
        );
        assert_eq!(
            BiomesAvatarJoint::LFoot.skeleton_parent(),
            Some(BiomesAvatarJoint::LLeg)
        );
        assert_eq!(
            BiomesAvatarJoint::RFoot.skeleton_parent(),
            Some(BiomesAvatarJoint::RLeg)
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
    fn selected_wearables_follow_biomes_slot_order() {
        let mut appearance = default_avatar_appearance();
        appearance.hair_id = Some("hair".to_string());
        appearance.face_id = Some("face".to_string());
        appearance.ears_id = Some("ears".to_string());
        appearance.hat_id = Some("hat".to_string());
        appearance.neck_id = Some("neck".to_string());
        appearance.top_id = Some("top".to_string());
        appearance.bottoms_id = Some("bottoms".to_string());
        appearance.outerwear_id = Some("outerwear".to_string());
        appearance.hands_id = Some("hands".to_string());
        appearance.feet_id = Some("feet".to_string());
        appearance.robot_id = Some("robot".to_string());

        let selected_slots: Vec<&str> = selected_wearables_in_biomes_order(&appearance)
            .into_iter()
            .map(|(slot, _)| slot.name())
            .collect();

        assert_eq!(
            selected_slots,
            [
                "hair",
                "hat",
                "bottoms",
                "face",
                "top",
                "neck",
                "outerwear",
                "ears",
                "hands",
                "feet",
                "robot",
            ]
        );
    }

    #[test]
    fn wearable_body_mask_removes_base_voxels_under_clothing_shells() {
        let base_voxels = vec![
            SceneColoredVoxel {
                center: (0, 0, 0),
                color: Color::WHITE,
            },
            SceneColoredVoxel {
                center: (20, 0, 0),
                color: Color::WHITE,
            },
        ];
        let wearable_layers = vec![(
            BiomesWearableSlot::Top,
            vec![SceneColoredVoxel {
                center: (2, 0, 0),
                color: Color::BLACK,
            }],
        )];

        let composed =
            compose_avatar_joint_voxels(base_voxels, BiomesAvatarJoint::Chest, wearable_layers);

        assert!(composed.iter().any(|voxel| voxel.center == (20, 0, 0)));
        assert!(composed.iter().any(|voxel| voxel.center == (2, 0, 0)));
        assert!(!composed.iter().any(|voxel| voxel.center == (0, 0, 0)));
    }

    #[test]
    fn wearable_body_mask_ignores_cosmetic_slots_and_unmatched_joints() {
        let base_voxels = vec![SceneColoredVoxel {
            center: (0, 0, 0),
            color: Color::WHITE,
        }];
        let face_layer = vec![(
            BiomesWearableSlot::Face,
            vec![SceneColoredVoxel {
                center: (0, 0, 0),
                color: Color::BLACK,
            }],
        )];
        let top_on_foot_layer = vec![(
            BiomesWearableSlot::Top,
            vec![SceneColoredVoxel {
                center: (0, 0, 0),
                color: Color::BLACK,
            }],
        )];

        assert_eq!(
            compose_avatar_joint_voxels(base_voxels.clone(), BiomesAvatarJoint::Head, face_layer,)
                .len(),
            2
        );
        assert_eq!(
            compose_avatar_joint_voxels(base_voxels, BiomesAvatarJoint::LFoot, top_on_foot_layer,)
                .len(),
            2
        );
    }

    #[test]
    fn hair_and_hat_layers_mask_lower_head_layers() {
        let head_voxels = vec![
            SceneColoredVoxel {
                center: (0, 0, 0),
                color: Color::WHITE,
            },
            SceneColoredVoxel {
                center: (20, 0, 0),
                color: Color::WHITE,
            },
        ];
        let layers = vec![
            (
                BiomesWearableSlot::Hair,
                vec![SceneColoredVoxel {
                    center: (2, 0, 0),
                    color: Color::BLACK,
                }],
            ),
            (
                BiomesWearableSlot::Hat,
                vec![SceneColoredVoxel {
                    center: (4, 0, 0),
                    color: Color::WHITE,
                }],
            ),
        ];

        let composed = compose_avatar_joint_voxels(head_voxels, BiomesAvatarJoint::Head, layers);

        assert!(composed.iter().any(|voxel| voxel.center == (20, 0, 0)));
        assert!(composed.iter().any(|voxel| voxel.center == (4, 0, 0)));
        assert!(!composed.iter().any(|voxel| voxel.center == (0, 0, 0)));
        assert!(!composed.iter().any(|voxel| voxel.center == (2, 0, 0)));
    }

    #[test]
    fn creator_visual_options_expose_thumbnail_paths() {
        let hair_category = BiomesAvatarOptionCategory::ALL
            .iter()
            .position(|category| *category == BiomesAvatarOptionCategory::HairStyle)
            .unwrap();
        let skin_category = BiomesAvatarOptionCategory::ALL
            .iter()
            .position(|category| *category == BiomesAvatarOptionCategory::SkinColor)
            .unwrap();

        assert!(avatar_creator_option_thumbnail_path(skin_category, 0).is_none());
        assert!(avatar_creator_option_thumbnail_path(hair_category, 0).is_none());

        if avatar_creator_option_count(hair_category) > 1 {
            let thumbnail = avatar_creator_option_thumbnail_path(hair_category, 1).unwrap();
            assert!(thumbnail.starts_with("res://assets/biomes/thumbnails/hair/"));
            assert!(thumbnail.ends_with(".png"));
        }
    }

    #[test]
    fn base_model_indices_match_biomes_vox_layers() {
        assert_eq!(BiomesAvatarJoint::LForearm.base_model_index(), 0);
        assert_eq!(BiomesAvatarJoint::Chest.base_model_index(), 12);
        assert_eq!(BiomesAvatarJoint::Head.base_model_index(), 13);
        assert_eq!(BiomesAvatarJoint::RHand.base_model_index(), 14);
    }

    #[test]
    fn base_hand_scene_models_keep_source_mirrored_rotations() {
        let base_model_path = biomes_res_absolute_path(BIOMES_BASE_MODEL_PATH).unwrap();
        let scene_models = crate::vox::load_vox_scene_models_from_path(&base_model_path).unwrap();
        let left = scene_models
            .iter()
            .find(|scene_model| is_joint_base_scene_model(scene_model, BiomesAvatarJoint::LHand))
            .unwrap();
        let right = scene_models
            .iter()
            .find(|scene_model| is_joint_base_scene_model(scene_model, BiomesAvatarJoint::RHand))
            .unwrap();

        assert_eq!(left.layer_name.as_deref(), Some("L_Hand"));
        assert_eq!(right.layer_name.as_deref(), Some("R_Hand"));
        assert_eq!(left.rotation[0], right.rotation[0]);
        assert_eq!(left.rotation[2], right.rotation[2]);
        assert_ne!(left.rotation[1], right.rotation[1]);
    }

    #[test]
    fn avatar_joint_bind_positions_use_biomes_pose_depth_axis() {
        let left_arm = avatar_joint_bind_position(BiomesAvatarJoint::LArm, 1.0);
        let right_arm = avatar_joint_bind_position(BiomesAvatarJoint::RArm, 1.0);

        assert!(left_arm[0] < 0.0);
        assert!(right_arm[0] > 0.0);
        assert!(left_arm[2] > 0.0);
        assert!(right_arm[2] > 0.0);
    }

    #[test]
    fn base_joint_scene_voxels_are_local_to_their_joint() {
        let appearance = default_avatar_appearance();
        let base_model_path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/biomes/wearables/base_model.vox");
        let scene_models = crate::vox::load_vox_scene_models_from_path(&base_model_path).unwrap();
        let head_model = scene_models
            .iter()
            .find(|scene_model| is_joint_base_scene_model(scene_model, BiomesAvatarJoint::Head))
            .unwrap();
        let voxels = scene_colored_voxels_from_biomes_scene_model(
            head_model,
            &appearance,
            BiomesAvatarJoint::Head,
        );

        let max_abs_z = voxels
            .iter()
            .map(|voxel| voxel.center.2.abs())
            .max()
            .unwrap_or(0);
        assert!(
            max_abs_z < 40,
            "head voxels must be local to the head joint, not full scene-space: max_abs_z={max_abs_z}"
        );
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
        assert_eq!(running.track_count(), 48);
        assert_eq!(
            catalog.duration_for_animation(BiomesPlayerAnimation::Run),
            Some(running.duration_sec)
        );
        assert_eq!(
            catalog.duration_for_animation(BiomesPlayerAnimation::Wave),
            Some(2.0)
        );

        let waving_pose = catalog
            .sample_clip_pose("Waving", 0.25)
            .expect("Waving sampled pose must exist");
        assert_eq!(
            waving_pose.joints.len(),
            BIOMES_CHARACTER_JOINT_ORDERING.len()
        );
        assert_eq!(
            waving_pose
                .joints
                .iter()
                .map(|joint_pose| joint_pose.joint)
                .collect::<Vec<_>>(),
            BIOMES_CHARACTER_JOINT_ORDERING.to_vec()
        );
        assert!(waving_pose.nodes.iter().any(|node| {
            node.node_name == "R_Hand"
                && node.translation.is_some()
                && node.rotation.is_some()
                && node.scale.is_some()
        }));
        assert!(
            waving_pose
                .nodes
                .iter()
                .any(|node| node.node_name == "Head")
        );
        assert!(
            !waving_pose
                .joints
                .iter()
                .any(|joint_pose| { joint_pose.node_name == "Tool" })
        );
    }

    #[test]
    fn biomes_animation_catalog_preserves_source_skeleton_for_retargeting() {
        let animations = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/animations/character-animations.gltf");
        let gltf = std::fs::read_to_string(&animations)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", animations.display()));
        let catalog = parse_biomes_animation_catalog(&gltf)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", animations.display()));

        assert_eq!(
            catalog.nodes[0]
                .parent
                .map(|index| catalog.nodes[index].name.as_str()),
            Some("Chest")
        );
        assert_eq!(
            catalog.nodes[15]
                .children
                .iter()
                .map(|index| catalog.nodes[*index].name.as_str())
                .collect::<Vec<_>>(),
            vec!["R_Thigh", "L_Thigh"]
        );
        assert_eq!(
            catalog.nodes[32]
                .children
                .iter()
                .take(2)
                .map(|index| catalog.nodes[*index].name.as_str())
                .collect::<Vec<_>>(),
            vec!["Chest", "Hair"]
        );
        let rest_poses = catalog.joint_rest_poses();
        assert_eq!(rest_poses.len(), BIOMES_CHARACTER_JOINT_ORDERING.len());
        assert_eq!(
            rest_poses
                .iter()
                .find(|pose| pose.joint == BiomesAvatarJoint::LHand)
                .map(|pose| pose.parent_joint),
            Some(Some(BiomesAvatarJoint::LForearm))
        );
        assert_eq!(
            rest_poses
                .iter()
                .find(|pose| pose.joint == BiomesAvatarJoint::RFoot)
                .map(|pose| pose.parent_joint),
            Some(Some(BiomesAvatarJoint::RLeg))
        );
    }

    #[test]
    fn biomes_animation_samples_all_source_clips_into_bounded_joint_poses() {
        let animations = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../assets/biomes/animations/character-animations.gltf");
        let gltf = std::fs::read_to_string(&animations)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", animations.display()));
        let catalog = parse_biomes_animation_catalog(&gltf)
            .unwrap_or_else(|err| panic!("failed to parse {}: {err}", animations.display()));

        for clip in catalog.clips() {
            for time_sec in [
                0.0,
                clip.duration_sec * 0.5,
                (clip.duration_sec - 0.001).max(0.0),
            ] {
                let pose = catalog
                    .sample_clip_pose(&clip.file_animation_name, time_sec)
                    .unwrap_or_else(|| panic!("{} did not sample", clip.file_animation_name));
                assert_eq!(
                    pose.joints.len(),
                    BIOMES_CHARACTER_JOINT_ORDERING.len(),
                    "{} did not retarget every character joint",
                    clip.file_animation_name
                );
                for joint_pose in &pose.joints {
                    assert!(
                        joint_pose
                            .translation_delta
                            .iter()
                            .all(|value| value.is_finite() && value.abs() < 6.0),
                        "{} {:?} has invalid translation delta {:?}",
                        clip.file_animation_name,
                        joint_pose.joint,
                        joint_pose.translation_delta
                    );
                    let rotation_len = joint_pose
                        .rotation_delta
                        .iter()
                        .map(|value| value * value)
                        .sum::<f32>()
                        .sqrt();
                    assert!(
                        (rotation_len - 1.0).abs() < 0.001,
                        "{} {:?} has non-normalized rotation {:?}",
                        clip.file_animation_name,
                        joint_pose.joint,
                        joint_pose.rotation_delta
                    );
                    assert!(
                        joint_pose
                            .scale
                            .iter()
                            .all(|value| value.is_finite() && (0.25..=4.0).contains(value)),
                        "{} {:?} has invalid scale {:?}",
                        clip.file_animation_name,
                        joint_pose.joint,
                        joint_pose.scale
                    );
                }
            }
        }
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

    #[test]
    fn wearable_scene_model_filter_uses_visible_joint_layers() {
        let model = VoxModel {
            size: (1, 1, 1),
            voxels: Vec::new(),
            palette: [Color::WHITE; 256],
        };
        let left_foot = VoxSceneModel {
            model: model.clone(),
            translation: BiomesAvatarJoint::LFoot.base_scene_translation(),
            rotation: crate::vox::VOX_IDENTITY_ROTATION,
            layer_name: Some("L_Foot".to_string()),
            hidden: false,
        };
        let reference = VoxSceneModel {
            model: model.clone(),
            translation: BiomesAvatarJoint::LFoot.base_scene_translation(),
            rotation: crate::vox::VOX_IDENTITY_ROTATION,
            layer_name: Some("reference".to_string()),
            hidden: false,
        };
        let hidden_left_foot = VoxSceneModel {
            model: model.clone(),
            translation: BiomesAvatarJoint::LFoot.base_scene_translation(),
            rotation: crate::vox::VOX_IDENTITY_ROTATION,
            layer_name: Some("L_Foot".to_string()),
            hidden: true,
        };
        let no_layer = VoxSceneModel {
            model,
            translation: (0, 0, 0),
            rotation: crate::vox::VOX_IDENTITY_ROTATION,
            layer_name: None,
            hidden: false,
        };

        assert!(scene_model_is_visible_joint_layer(
            &left_foot,
            BiomesAvatarJoint::LFoot
        ));
        assert!(!scene_model_is_visible_joint_layer(
            &left_foot,
            BiomesAvatarJoint::RFoot
        ));
        assert!(!scene_model_is_visible_joint_layer(
            &reference,
            BiomesAvatarJoint::LFoot
        ));
        assert!(!scene_model_is_visible_joint_layer(
            &hidden_left_foot,
            BiomesAvatarJoint::LFoot
        ));
        assert!(!scene_model_is_visible_joint_layer(
            &no_layer,
            BiomesAvatarJoint::Head
        ));
    }

    #[test]
    fn available_wearables_exclude_reference_only_assets() {
        if wearable_slot_absolute_path(BiomesWearableSlot::Ears).is_none() {
            assert!(available_wearable_ids(BiomesWearableSlot::Ears).is_empty());
            assert!(available_wearable_ids(BiomesWearableSlot::Face).is_empty());
            assert!(available_wearable_ids(BiomesWearableSlot::Neck).is_empty());
            assert!(available_wearable_ids(BiomesWearableSlot::Robot).is_empty());
            return;
        }

        let ears = available_wearable_ids(BiomesWearableSlot::Ears);
        assert!(ears.contains(&"drops".to_string()));
        assert!(!ears.contains(&"drops_with_gem".to_string()));
        assert!(!ears.contains(&"hoops_with_gem".to_string()));
        assert!(!ears.contains(&"studs_with_gem".to_string()));

        let face = available_wearable_ids(BiomesWearableSlot::Face);
        assert!(face.contains(&"aviator_glasses".to_string()));
        assert!(!face.contains(&"nose_ring".to_string()));

        let neck = available_wearable_ids(BiomesWearableSlot::Neck);
        assert!(neck.contains(&"chain".to_string()));
        assert!(!neck.contains(&"chain_with_gem".to_string()));
        assert!(!neck.contains(&"chains_with_gem".to_string()));

        assert!(available_wearable_ids(BiomesWearableSlot::Robot).is_empty());
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
