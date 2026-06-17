use godot::classes::ProjectSettings;
use godot::prelude::*;
use std::collections::HashMap;

use crate::vox::{ColoredVoxel, VoxModel};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum VelorenHumanoidPart {
    Head,
    Chest,
    Belt,
    Pants,
    LeftHand,
    RightHand,
    LeftFoot,
    RightFoot,
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum Species {
    Danari,
    Dwarf,
    Elf,
    Human,
    Orc,
    Draugr,
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum BodyType {
    Female,
    Male,
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum EyeColor {
    AmberOrange,
    AmberYellow,
    BrightBrown,
    CornflowerBlue,
    CuriousGreen,
    EmeraldGreen,
    ExoticPurple,
    FrozenBlue,
    GhastlyYellow,
    LoyalBrown,
    MagicPurple,
    NobleBlue,
    PineGreen,
    PumpkinOrange,
    RubyRed,
    RegalPurple,
    RustBrown,
    SapphireBlue,
    SulfurYellow,
    ToxicGreen,
    ViciousRed,
    VigorousBlack,
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum Skin {
    HumanOne,
    HumanTwo,
    HumanThree,
    HumanFour,
    HumanFive,
    HumanSix,
    HumanSeven,
    HumanEight,
    HumanNine,
    HumanTen,
    HumanEleven,
    HumanTwelve,
    HumanThirteen,
    HumanFourteen,
    HumanFifteen,
    HumanSixteen,
    HumanSeventeen,
    HumanEighteen,
    DwarfOne,
    DwarfTwo,
    DwarfThree,
    DwarfFour,
    DwarfFive,
    DwarfSix,
    DwarfSeven,
    DwarfEight,
    DwarfNine,
    DwarfTen,
    DwarfEleven,
    DwarfTwelve,
    DwarfThirteen,
    DwarfFourteen,
    ElfOne,
    ElfTwo,
    ElfThree,
    ElfFour,
    ElfFive,
    ElfSix,
    ElfSeven,
    ElfEight,
    ElfNine,
    ElfTen,
    ElfEleven,
    ElfTwelve,
    ElfThirteen,
    ElfFourteen,
    ElfFifteen,
    ElfSixteen,
    ElfSeventeen,
    ElfEighteen,
    OrcOne,
    OrcTwo,
    OrcThree,
    OrcFour,
    OrcFive,
    OrcSix,
    OrcSeven,
    OrcEight,
    DanariOne,
    DanariTwo,
    DanariThree,
    DanariFour,
    DanariFive,
    DanariSix,
    DanariSeven,
    DraugrOne,
    DraugrTwo,
    DraugrThree,
    DraugrFour,
    DraugrFive,
    DraugrSix,
    DraugrSeven,
    DraugrEight,
    DraugrNine,
}

const DANARI_SKIN_COLORS: [Skin; 7] = [
    Skin::DanariOne,
    Skin::DanariTwo,
    Skin::DanariThree,
    Skin::DanariFour,
    Skin::DanariFive,
    Skin::DanariSix,
    Skin::DanariSeven,
];
const DWARF_SKIN_COLORS: [Skin; 14] = [
    Skin::DwarfOne,
    Skin::DwarfTwo,
    Skin::DwarfThree,
    Skin::DwarfFour,
    Skin::DwarfFive,
    Skin::DwarfSix,
    Skin::DwarfSeven,
    Skin::DwarfEight,
    Skin::DwarfNine,
    Skin::DwarfTen,
    Skin::DwarfEleven,
    Skin::DwarfTwelve,
    Skin::DwarfThirteen,
    Skin::DwarfFourteen,
];
const ELF_SKIN_COLORS: [Skin; 18] = [
    Skin::ElfOne,
    Skin::ElfTwo,
    Skin::ElfThree,
    Skin::ElfFour,
    Skin::ElfFive,
    Skin::ElfSix,
    Skin::ElfSeven,
    Skin::ElfEight,
    Skin::ElfNine,
    Skin::ElfTen,
    Skin::ElfEleven,
    Skin::ElfTwelve,
    Skin::ElfThirteen,
    Skin::ElfFourteen,
    Skin::ElfFifteen,
    Skin::ElfSixteen,
    Skin::ElfSeventeen,
    Skin::ElfEighteen,
];
const HUMAN_SKIN_COLORS: [Skin; 18] = [
    Skin::HumanOne,
    Skin::HumanTwo,
    Skin::HumanThree,
    Skin::HumanFour,
    Skin::HumanFive,
    Skin::HumanSix,
    Skin::HumanSeven,
    Skin::HumanEight,
    Skin::HumanNine,
    Skin::HumanTen,
    Skin::HumanEleven,
    Skin::HumanTwelve,
    Skin::HumanThirteen,
    Skin::HumanFourteen,
    Skin::HumanFifteen,
    Skin::HumanSixteen,
    Skin::HumanSeventeen,
    Skin::HumanEighteen,
];
const ORC_SKIN_COLORS: [Skin; 8] = [
    Skin::OrcOne,
    Skin::OrcTwo,
    Skin::OrcThree,
    Skin::OrcFour,
    Skin::OrcFive,
    Skin::OrcSix,
    Skin::OrcSeven,
    Skin::OrcEight,
];
const DRAUGR_SKIN_COLORS: [Skin; 9] = [
    Skin::DraugrOne,
    Skin::DraugrTwo,
    Skin::DraugrThree,
    Skin::DraugrFour,
    Skin::DraugrFive,
    Skin::DraugrSix,
    Skin::DraugrSeven,
    Skin::DraugrEight,
    Skin::DraugrNine,
];

const DANARI_EYE_COLORS: [EyeColor; 4] = [
    EyeColor::EmeraldGreen,
    EyeColor::LoyalBrown,
    EyeColor::RegalPurple,
    EyeColor::ViciousRed,
];
const DWARF_EYE_COLORS: [EyeColor; 6] = [
    EyeColor::AmberYellow,
    EyeColor::CornflowerBlue,
    EyeColor::LoyalBrown,
    EyeColor::NobleBlue,
    EyeColor::PineGreen,
    EyeColor::RustBrown,
];
const ELF_EYE_COLORS: [EyeColor; 7] = [
    EyeColor::AmberYellow,
    EyeColor::BrightBrown,
    EyeColor::EmeraldGreen,
    EyeColor::NobleBlue,
    EyeColor::SapphireBlue,
    EyeColor::RegalPurple,
    EyeColor::RubyRed,
];
const HUMAN_EYE_COLORS: [EyeColor; 5] = [
    EyeColor::NobleBlue,
    EyeColor::CornflowerBlue,
    EyeColor::CuriousGreen,
    EyeColor::LoyalBrown,
    EyeColor::VigorousBlack,
];
const ORC_EYE_COLORS: [EyeColor; 6] = [
    EyeColor::AmberYellow,
    EyeColor::CornflowerBlue,
    EyeColor::ExoticPurple,
    EyeColor::LoyalBrown,
    EyeColor::PineGreen,
    EyeColor::RustBrown,
];
const DRAUGR_EYE_COLORS: [EyeColor; 6] = [
    EyeColor::FrozenBlue,
    EyeColor::GhastlyYellow,
    EyeColor::MagicPurple,
    EyeColor::PumpkinOrange,
    EyeColor::ToxicGreen,
    EyeColor::ViciousRed,
];

impl Species {
    fn skin_color(self, index: usize) -> Skin {
        let colors = match self {
            Species::Danari => DANARI_SKIN_COLORS.as_slice(),
            Species::Dwarf => DWARF_SKIN_COLORS.as_slice(),
            Species::Elf => ELF_SKIN_COLORS.as_slice(),
            Species::Human => HUMAN_SKIN_COLORS.as_slice(),
            Species::Orc => ORC_SKIN_COLORS.as_slice(),
            Species::Draugr => DRAUGR_SKIN_COLORS.as_slice(),
        };
        colors.get(index).copied().unwrap_or(Skin::HumanThree)
    }

    fn eye_color(self, index: usize) -> EyeColor {
        let colors = match self {
            Species::Danari => DANARI_EYE_COLORS.as_slice(),
            Species::Dwarf => DWARF_EYE_COLORS.as_slice(),
            Species::Elf => ELF_EYE_COLORS.as_slice(),
            Species::Human => HUMAN_EYE_COLORS.as_slice(),
            Species::Orc => ORC_EYE_COLORS.as_slice(),
            Species::Draugr => DRAUGR_EYE_COLORS.as_slice(),
        };
        colors.get(index).copied().unwrap_or(EyeColor::NobleBlue)
    }
}

#[derive(Clone, Copy)]
struct HumanoidBody {
    species: Species,
    body_type: BodyType,
    hair_style: usize,
    beard: usize,
    eyes: usize,
    accessory: usize,
    hair_color: usize,
    skin: usize,
    eye_color: usize,
}

impl HumanoidBody {
    fn default_human_male() -> Self {
        Self {
            species: Species::Human,
            body_type: BodyType::Male,
            hair_style: 17,
            beard: 5,
            eyes: 0,
            accessory: 0,
            hair_color: 8,
            skin: 0,
            eye_color: 1,
        }
    }
}

#[derive(Clone, Debug)]
struct VoxSpec<T>(String, [T; 3], u32);

#[derive(Clone, Debug)]
struct HumHeadSubSpec {
    offset: [f32; 3],
    head: VoxSpec<i32>,
    eyes: Vec<Option<VoxSpec<i32>>>,
    hair: Vec<Option<VoxSpec<i32>>>,
    beard: Vec<Option<VoxSpec<i32>>>,
    accessory: Vec<Option<VoxSpec<i32>>>,
}

#[derive(Clone, Debug)]
struct HumHeadSpec(HashMap<(Species, BodyType), HumHeadSubSpec>);

#[derive(Clone, Debug)]
struct HumColorSpec {
    hair_colors: SpeciesHairColorSpec,
    eye_colors_light: EyeColorSpec,
    eye_colors_dark: EyeColorSpec,
    eye_white: [u8; 3],
    skin_colors_plain: SkinColorSpec,
    skin_colors_light: SkinColorSpec,
    skin_colors_dark: SkinColorSpec,
}

#[derive(Clone, Debug)]
struct SpeciesHairColorSpec(HashMap<String, Vec<[u8; 3]>>);

impl SpeciesHairColorSpec {
    fn color(&self, species: Species, index: usize) -> Option<Color> {
        self.0
            .get(&format!("{species:?}"))
            .and_then(|values| values.get(index))
            .copied()
            .map(color_from_rgb_array)
    }
}

#[derive(Clone, Debug)]
struct EyeColorSpec(HashMap<String, [u8; 3]>);

impl EyeColorSpec {
    fn color(&self, eye: EyeColor) -> Option<Color> {
        self.0
            .get(&format!("{eye:?}"))
            .copied()
            .map(color_from_rgb_array)
    }
}

#[derive(Clone, Debug)]
struct SkinColorSpec(HashMap<String, [u8; 3]>);

impl SkinColorSpec {
    fn color(&self, skin: Skin) -> Option<Color> {
        self.0
            .get(&format!("{skin:?}"))
            .copied()
            .map(color_from_rgb_array)
    }
}

#[derive(Clone, Debug)]
struct ArmorVoxSpec {
    vox_spec: VoxSpec<f32>,
    color: Option<[u8; 3]>,
}

#[derive(Clone, Debug)]
struct SidedArmorVoxSpec {
    left: ArmorVoxSpec,
    right: ArmorVoxSpec,
}

#[derive(Clone, Debug)]
struct ArmorVoxSpecMap<S> {
    default: S,
    map: HashMap<String, S>,
}

impl<S> ArmorVoxSpecMap<S> {
    fn spec<'a>(&'a self, item_key: Option<&str>, manifest_path: &str) -> Result<&'a S, String> {
        match item_key {
            Some(key) => self
                .map
                .get(key)
                .ok_or_else(|| format!("{manifest_path} has no armor spec for {key}")),
            None => Ok(&self.default),
        }
    }
}

#[derive(Clone, Debug)]
struct ArmorManifest<S>(ArmorVoxSpecMap<S>);

#[derive(Clone, Copy)]
enum Fill {
    Filled,
    Hollow,
    Override,
}

#[derive(Clone, Copy)]
struct Cell {
    fill: Fill,
    color: Color,
}

impl Cell {
    fn filled(color: Color) -> Self {
        Self {
            fill: Fill::Filled,
            color,
        }
    }

    fn override_hollow(color: Color) -> Self {
        Self {
            fill: Fill::Override,
            color,
        }
    }

    fn hollow() -> Self {
        Self {
            fill: Fill::Hollow,
            color: Color::from_rgba8(0, 0, 0, 0),
        }
    }

    fn is_filled(self) -> bool {
        matches!(self.fill, Fill::Filled | Fill::Override)
    }

    fn is_override_hollow(self) -> bool {
        matches!(self.fill, Fill::Override)
    }

    fn is_hollowing(self) -> bool {
        matches!(self.fill, Fill::Hollow)
    }
}

#[derive(Clone, Default)]
struct Segment {
    cells: HashMap<(i32, i32, i32), Cell>,
}

impl Segment {
    fn map_rgb(mut self, transform: impl Fn(Color) -> Color) -> Self {
        for cell in self.cells.values_mut() {
            if cell.is_filled() {
                cell.color = transform(cell.color);
            }
        }
        self
    }
}

#[derive(Clone, Copy)]
struct MaterialPalette {
    skin: Color,
    skin_dark: Color,
    skin_light: Color,
    hair: Color,
    eye_dark: Color,
    eye_light: Color,
    eye_white: Color,
}

impl MaterialPalette {
    fn for_body(color_spec: &HumColorSpec, body: HumanoidBody) -> Result<Self, String> {
        let skin = body.species.skin_color(body.skin);
        let eye = body.species.eye_color(body.eye_color);
        Ok(Self {
            skin: color_spec.skin_colors_plain.color(skin).ok_or_else(|| {
                format!("Veloren humanoid color manifest missing plain skin color for {skin:?}")
            })?,
            skin_dark: color_spec.skin_colors_dark.color(skin).ok_or_else(|| {
                format!("Veloren humanoid color manifest missing dark skin color for {skin:?}")
            })?,
            skin_light: color_spec.skin_colors_light.color(skin).ok_or_else(|| {
                format!("Veloren humanoid color manifest missing light skin color for {skin:?}")
            })?,
            hair: color_spec
                .hair_colors
                .color(body.species, body.hair_color)
                .ok_or_else(|| {
                    format!(
                        "Veloren humanoid color manifest missing hair color {} for {:?}",
                        body.hair_color, body.species
                    )
                })?,
            eye_dark: color_spec.eye_colors_dark.color(eye).ok_or_else(|| {
                format!("Veloren humanoid color manifest missing dark eye color for {eye:?}")
            })?,
            eye_light: color_spec.eye_colors_light.color(eye).ok_or_else(|| {
                format!("Veloren humanoid color manifest missing light eye color for {eye:?}")
            })?,
            eye_white: color_from_rgb_array(color_spec.eye_white),
        })
    }

    fn material_color(self, index: u8) -> Option<Color> {
        match index {
            0 => Some(self.skin),
            1 => Some(self.hair),
            2 => Some(self.eye_dark),
            3 => Some(self.eye_light),
            4 => Some(self.skin_dark),
            5 => Some(self.skin_light),
            7 => Some(self.eye_white),
            _ => None,
        }
    }
}

pub(crate) fn load_default_humanoid_part_mesh(
    part: VelorenHumanoidPart,
    scale: f32,
) -> Result<Gd<godot::classes::Mesh>, String> {
    let body = HumanoidBody::default_human_male();
    let color_spec = load_hum_color_manifest("humanoid_color_manifest.ron")?;
    let palette = MaterialPalette::for_body(&color_spec, body)?;
    let segment = match part {
        VelorenHumanoidPart::Head => compose_head(body, palette)?,
        VelorenHumanoidPart::Chest => compose_center_armor_part(
            "humanoid_armor_chest_manifest.ron",
            palette,
            true,
            None,
            None,
        )?,
        VelorenHumanoidPart::Belt => compose_center_armor_part(
            "humanoid_armor_belt_manifest.ron",
            palette,
            false,
            None,
            None,
        )?,
        VelorenHumanoidPart::Pants => compose_center_armor_part(
            "humanoid_armor_pants_manifest.ron",
            palette,
            true,
            None,
            Some(rgb8(28, 66, 109)),
        )?,
        VelorenHumanoidPart::LeftHand => {
            compose_sided_armor_part("humanoid_armor_hand_manifest.ron", palette, None, true)?
        }
        VelorenHumanoidPart::RightHand => {
            compose_sided_armor_part("humanoid_armor_hand_manifest.ron", palette, None, false)?
        }
        VelorenHumanoidPart::LeftFoot => {
            compose_flipped_armor_part("humanoid_armor_foot_manifest.ron", palette, None, true)?
        }
        VelorenHumanoidPart::RightFoot => {
            compose_flipped_armor_part("humanoid_armor_foot_manifest.ron", palette, None, false)?
        }
    };
    let voxels = segment_to_colored_voxels(&segment);
    Ok(crate::vox::build_colored_voxels_mesh(&voxels, scale).upcast::<godot::classes::Mesh>())
}

fn compose_head(body: HumanoidBody, palette: MaterialPalette) -> Result<Segment, String> {
    let manifest = load_head_manifest("humanoid_head_manifest.ron")?;
    let spec = manifest
        .0
        .get(&(body.species, body.body_type))
        .ok_or_else(|| "Veloren humanoid head spec missing for default Human/Male".to_string())?;

    let mut parts = Vec::new();
    parts.push((
        load_segment(&spec.head.0, spec.head.2 as usize, false, true, palette)?,
        vec3_i32(spec.head.1),
    ));
    maybe_push_indexed_part(&mut parts, &spec.eyes, body.eyes, false, true, palette)?;
    maybe_push_indexed_part(
        &mut parts,
        &spec.hair,
        body.hair_style,
        false,
        false,
        palette,
    )?;
    maybe_push_indexed_part(&mut parts, &spec.beard, body.beard, false, false, palette)?;
    maybe_push_indexed_part(
        &mut parts,
        &spec.accessory,
        body.accessory,
        false,
        false,
        palette,
    )?;

    let _veloren_head_origin = spec.offset;
    Ok(union_segments(parts))
}

fn compose_center_armor_part(
    manifest_path: &str,
    palette: MaterialPalette,
    include_bare: bool,
    item_key: Option<&str>,
    color_override: Option<Color>,
) -> Result<Segment, String> {
    let manifest = load_armor_manifest(manifest_path)?;
    let spec = manifest.0.spec(item_key, manifest_path)?;
    let mut armor = load_segment(
        &spec.vox_spec.0,
        spec.vox_spec.2 as usize,
        false,
        true,
        palette,
    )?;
    if let Some(color) = spec.color.map(color_from_rgb_array).or(color_override) {
        armor = armor.map_rgb(|rgb| recolor_grey(rgb, color));
    }
    if include_bare {
        let bare = load_segment("armor.empty", 0, false, true, palette)?;
        Ok(union_segments(vec![(bare, (0, 0, 0)), (armor, (0, 0, 0))]))
    } else {
        Ok(armor)
    }
}

fn compose_sided_armor_part(
    manifest_path: &str,
    palette: MaterialPalette,
    item_key: Option<&str>,
    left: bool,
) -> Result<Segment, String> {
    let manifest = load_sided_armor_manifest(manifest_path)?;
    let spec = manifest.0.spec(item_key, manifest_path)?;
    let side = if left { &spec.left } else { &spec.right };
    let mut segment = load_segment(
        &side.vox_spec.0,
        side.vox_spec.2 as usize,
        left,
        true,
        palette,
    )?;
    if let Some(color) = side.color.map(color_from_rgb_array) {
        segment = segment.map_rgb(|rgb| recolor_grey(rgb, color));
    }
    Ok(segment)
}

fn compose_flipped_armor_part(
    manifest_path: &str,
    palette: MaterialPalette,
    item_key: Option<&str>,
    left: bool,
) -> Result<Segment, String> {
    let manifest = load_armor_manifest(manifest_path)?;
    let spec = manifest.0.spec(item_key, manifest_path)?;
    let mut segment = load_segment(
        &spec.vox_spec.0,
        spec.vox_spec.2 as usize,
        left,
        true,
        palette,
    )?;
    if let Some(color) = spec.color.map(color_from_rgb_array) {
        segment = segment.map_rgb(|rgb| recolor_grey(rgb, color));
    }
    Ok(segment)
}

fn maybe_push_indexed_part(
    parts: &mut Vec<(Segment, (i32, i32, i32))>,
    specs: &[Option<VoxSpec<i32>>],
    index: usize,
    flipped: bool,
    material: bool,
    palette: MaterialPalette,
) -> Result<(), String> {
    let Some(Some(spec)) = specs.get(index) else {
        return Ok(());
    };
    parts.push((
        load_segment(&spec.0, spec.2 as usize, flipped, material, palette)?,
        vec3_i32(spec.1),
    ));
    Ok(())
}

fn load_segment(
    spec_name: &str,
    model_index: usize,
    flipped: bool,
    material: bool,
    palette: MaterialPalette,
) -> Result<Segment, String> {
    let path = veloren_vox_res_path(spec_name);
    let model = crate::vox::load_vox_model_from_res(&path, model_index)?;
    Ok(segment_from_model(&model, flipped, material, palette))
}

fn segment_from_model(
    model: &VoxModel,
    flipped: bool,
    material: bool,
    palette: MaterialPalette,
) -> Segment {
    let mut segment = Segment::default();
    for voxel in &model.voxels {
        let x = if flipped {
            model.size.0 as i32 - 1 - voxel.coord.x as i32
        } else {
            voxel.coord.x as i32
        };
        let position = (x, voxel.coord.y as i32, voxel.coord.z as i32);
        let cell = if material {
            material_cell(voxel.color_index, model, palette)
        } else {
            normal_cell(voxel.color_index, model)
        };
        if cell.is_filled() || cell.is_hollowing() {
            segment.cells.insert(position, cell);
        }
    }
    segment
}

fn material_cell(index: u8, model: &VoxModel, palette: MaterialPalette) -> Cell {
    if let Some(color) = palette.material_color(index) {
        Cell::filled(color)
    } else {
        normal_cell(index, model)
    }
}

fn normal_cell(index: u8, model: &VoxModel) -> Cell {
    let color = crate::vox::model_palette_color(model, index);
    match index {
        16 => Cell::hollow(),
        17..=21 => Cell::override_hollow(color),
        _ => Cell::filled(color),
    }
}

fn union_segments(parts: Vec<(Segment, (i32, i32, i32))>) -> Segment {
    let mut output = Segment::default();
    for (segment, offset) in parts {
        for (position, cell) in segment.cells {
            let target = (
                position.0 + offset.0,
                position.1 + offset.1,
                position.2 + offset.2,
            );
            let old = output.cells.get(&target).copied();
            if old.is_some_and(Cell::is_override_hollow) {
                continue;
            }
            if cell.is_hollowing() {
                if !old.is_some_and(Cell::is_override_hollow) {
                    output.cells.remove(&target);
                }
            } else if cell.is_filled() {
                output.cells.insert(target, cell);
            }
        }
    }
    output
}

fn segment_to_colored_voxels(segment: &Segment) -> Vec<ColoredVoxel> {
    segment
        .cells
        .iter()
        .filter_map(|(position, cell)| {
            cell.is_filled().then_some(ColoredVoxel {
                position: *position,
                color: cell.color,
            })
        })
        .collect()
}

fn load_manifest_source(path: &str) -> Result<String, String> {
    let res_path = format!("res://assets/veloren/voxygen/voxel/{path}");
    let absolute_path = ProjectSettings::singleton().globalize_path(&res_path);
    std::fs::read_to_string(absolute_path.to_string())
        .map_err(|err| format!("failed to read {res_path}: {err}"))
}

fn load_hum_color_manifest(path: &str) -> Result<HumColorSpec, String> {
    parse_hum_color_manifest(&load_manifest_source(path)?)
}

fn load_head_manifest(path: &str) -> Result<HumHeadSpec, String> {
    parse_head_manifest(&load_manifest_source(path)?)
}

fn load_armor_manifest(path: &str) -> Result<ArmorManifest<ArmorVoxSpec>, String> {
    parse_armor_manifest(&load_manifest_source(path)?)
}

fn load_sided_armor_manifest(path: &str) -> Result<ArmorManifest<SidedArmorVoxSpec>, String> {
    parse_sided_armor_manifest(&load_manifest_source(path)?)
}

fn parse_hum_color_manifest(source: &str) -> Result<HumColorSpec, String> {
    let source = strip_ron_line_comments(source);
    let hair_colors = extract_named_balanced(&source, "hair_colors", b'(')?;
    let eye_colors_light = extract_named_balanced(&source, "eye_colors_light", b'(')?;
    let eye_colors_dark = extract_named_balanced(&source, "eye_colors_dark", b'(')?;
    let skin_colors_plain = extract_named_balanced(&source, "skin_colors_plain", b'(')?;
    let skin_colors_light = extract_named_balanced(&source, "skin_colors_light", b'(')?;
    let skin_colors_dark = extract_named_balanced(&source, "skin_colors_dark", b'(')?;
    Ok(HumColorSpec {
        hair_colors: SpeciesHairColorSpec(parse_color_tuple_list_map(hair_colors)?),
        eye_colors_light: EyeColorSpec(parse_color_tuple_map(eye_colors_light)?),
        eye_colors_dark: EyeColorSpec(parse_color_tuple_map(eye_colors_dark)?),
        eye_white: parse_named_color_tuple(&source, "eye_white")?,
        skin_colors_plain: SkinColorSpec(parse_color_tuple_map(skin_colors_plain)?),
        skin_colors_light: SkinColorSpec(parse_color_tuple_map(skin_colors_light)?),
        skin_colors_dark: SkinColorSpec(parse_color_tuple_map(skin_colors_dark)?),
    })
}

fn parse_head_manifest(source: &str) -> Result<HumHeadSpec, String> {
    let source = strip_ron_line_comments(source);
    let entry = extract_balanced_after_token(&source, "(Human, Male):", b'(')?;
    let mut map = HashMap::new();
    map.insert(
        (Species::Human, BodyType::Male),
        HumHeadSubSpec {
            offset: parse_named_f32_tuple(entry, "offset")?,
            head: parse_named_vox_spec_i32(entry, "head")?,
            eyes: parse_named_vox_spec_i32_list(entry, "eyes")?,
            hair: parse_named_vox_spec_i32_list(entry, "hair")?,
            beard: parse_named_vox_spec_i32_list(entry, "beard")?,
            accessory: parse_named_vox_spec_i32_list(entry, "accessory")?,
        },
    );
    Ok(HumHeadSpec(map))
}

fn parse_armor_manifest(source: &str) -> Result<ArmorManifest<ArmorVoxSpec>, String> {
    let source = strip_ron_line_comments(source);
    let default = parse_armor_vox_spec(extract_named_balanced(&source, "default", b'(')?)?;
    let map = parse_armor_spec_map(extract_named_balanced(&source, "map", b'{')?)?;
    Ok(ArmorManifest(ArmorVoxSpecMap { default, map }))
}

fn parse_sided_armor_manifest(source: &str) -> Result<ArmorManifest<SidedArmorVoxSpec>, String> {
    let source = strip_ron_line_comments(source);
    let default = parse_sided_armor_vox_spec(extract_named_balanced(&source, "default", b'(')?)?;
    let map = parse_sided_armor_spec_map(extract_named_balanced(&source, "map", b'{')?)?;
    Ok(ArmorManifest(ArmorVoxSpecMap { default, map }))
}

fn parse_named_vox_spec_i32(source: &str, name: &str) -> Result<VoxSpec<i32>, String> {
    parse_vox_spec_i32(extract_named_balanced(source, name, b'(')?)
}

fn parse_named_vox_spec_i32_list(
    source: &str,
    name: &str,
) -> Result<Vec<Option<VoxSpec<i32>>>, String> {
    parse_vox_spec_i32_list(extract_named_balanced(source, name, b'[')?)
}

fn parse_vox_spec_i32_list(source: &str) -> Result<Vec<Option<VoxSpec<i32>>>, String> {
    let mut values = Vec::new();
    let mut offset = 0;
    while offset < source.len() {
        offset = skip_ws_and_commas(source, offset);
        if offset >= source.len() {
            break;
        }
        if source[offset..].starts_with("None") {
            values.push(None);
            offset += "None".len();
            continue;
        }
        if source[offset..].starts_with("Some") {
            let open = skip_ws(source, offset + "Some".len());
            let (inner, end) = extract_balanced_at(source, open, b'(')?;
            values.push(Some(parse_vox_spec_i32(trim_outer_balanced(inner, b'(')?)?));
            offset = end;
            continue;
        }
        return Err(format!(
            "unsupported Veloren manifest list item near '{}'",
            source[offset..].chars().take(32).collect::<String>()
        ));
    }
    Ok(values)
}

fn parse_armor_spec_map(source: &str) -> Result<HashMap<String, ArmorVoxSpec>, String> {
    parse_quoted_key_map(source, parse_armor_vox_spec)
}

fn parse_sided_armor_spec_map(source: &str) -> Result<HashMap<String, SidedArmorVoxSpec>, String> {
    parse_quoted_key_map(source, parse_sided_armor_vox_spec)
}

fn parse_quoted_key_map<T>(
    source: &str,
    parse_value: fn(&str) -> Result<T, String>,
) -> Result<HashMap<String, T>, String> {
    let mut map = HashMap::new();
    let mut offset = 0;
    while offset < source.len() {
        offset = skip_ws_and_commas(source, offset);
        if offset >= source.len() {
            break;
        }
        let (key, key_end) = parse_quoted_string(&source[offset..])?;
        let key_end = offset + key_end;
        let colon = find_byte(source, key_end, b':')?;
        let open = skip_ws(source, colon + 1);
        let (value, end) = extract_balanced_at(source, open, b'(')?;
        map.insert(key, parse_value(value)?);
        offset = end;
    }
    Ok(map)
}

fn parse_sided_armor_vox_spec(source: &str) -> Result<SidedArmorVoxSpec, String> {
    Ok(SidedArmorVoxSpec {
        left: parse_armor_vox_spec(extract_named_balanced(source, "left", b'(')?)?,
        right: parse_armor_vox_spec(extract_named_balanced(source, "right", b'(')?)?,
    })
}

fn parse_armor_vox_spec(source: &str) -> Result<ArmorVoxSpec, String> {
    Ok(ArmorVoxSpec {
        vox_spec: parse_vox_spec_f32(extract_named_balanced(source, "vox_spec", b'(')?)?,
        color: parse_named_optional_color(source, "color")?,
    })
}

fn parse_named_optional_color(source: &str, name: &str) -> Result<Option<[u8; 3]>, String> {
    let token = format!("{name}:");
    let start = source
        .find(&token)
        .ok_or_else(|| format!("Veloren manifest field '{name}' is missing"))?;
    let value_start = skip_ws(source, start + token.len());
    if source[value_start..].starts_with("None") {
        return Ok(None);
    }
    if source[value_start..].starts_with("Some") {
        let open = skip_ws(source, value_start + "Some".len());
        let (inner, _) = extract_balanced_at(source, open, b'(')?;
        return Ok(Some(parse_u8_tuple3(trim_outer_balanced(inner, b'(')?)?));
    }
    Err(format!("unsupported Veloren color value for '{name}'"))
}

fn parse_vox_spec_i32(source: &str) -> Result<VoxSpec<i32>, String> {
    let (name, name_end) = parse_quoted_string(source)?;
    let tuple_open = find_byte(source, name_end, b'(')?;
    let (tuple, tuple_end) = extract_balanced_at(source, tuple_open, b'(')?;
    Ok(VoxSpec(
        name,
        parse_i32_tuple3(tuple)?,
        parse_optional_model_index(&source[tuple_end..])? as u32,
    ))
}

fn parse_vox_spec_f32(source: &str) -> Result<VoxSpec<f32>, String> {
    let (name, name_end) = parse_quoted_string(source)?;
    let tuple_open = find_byte(source, name_end, b'(')?;
    let (tuple, tuple_end) = extract_balanced_at(source, tuple_open, b'(')?;
    Ok(VoxSpec(
        name,
        parse_f32_tuple3(tuple)?,
        parse_optional_model_index(&source[tuple_end..])? as u32,
    ))
}

fn parse_named_f32_tuple(source: &str, name: &str) -> Result<[f32; 3], String> {
    parse_f32_tuple3(extract_named_balanced(source, name, b'(')?)
}

fn parse_named_color_tuple(source: &str, name: &str) -> Result<[u8; 3], String> {
    parse_u8_tuple3(extract_named_balanced(source, name, b'(')?)
}

fn parse_color_tuple_map(source: &str) -> Result<HashMap<String, [u8; 3]>, String> {
    let mut map = HashMap::new();
    let mut offset = 0;
    while offset < source.len() {
        offset = skip_ws_and_commas(source, offset);
        if offset >= source.len() {
            break;
        }
        let (key, key_end) = parse_identifier(source, offset)?;
        let colon = find_byte(source, key_end, b':')?;
        let open = skip_ws(source, colon + 1);
        let (tuple, end) = extract_balanced_at(source, open, b'(')?;
        map.insert(key, parse_u8_tuple3(tuple)?);
        offset = end;
    }
    Ok(map)
}

fn parse_color_tuple_list_map(source: &str) -> Result<HashMap<String, Vec<[u8; 3]>>, String> {
    let mut map = HashMap::new();
    let mut offset = 0;
    while offset < source.len() {
        offset = skip_ws_and_commas(source, offset);
        if offset >= source.len() {
            break;
        }
        let (key, key_end) = parse_identifier(source, offset)?;
        let colon = find_byte(source, key_end, b':')?;
        let open = skip_ws(source, colon + 1);
        let (list, end) = extract_balanced_at(source, open, b'[')?;
        map.insert(key, parse_color_tuple_list(list)?);
        offset = end;
    }
    Ok(map)
}

fn parse_color_tuple_list(list: &str) -> Result<Vec<[u8; 3]>, String> {
    let mut colors = Vec::new();
    let mut offset = 0;
    while offset < list.len() {
        offset = skip_ws_and_commas(list, offset);
        if offset >= list.len() {
            break;
        }
        let (tuple, end) = extract_balanced_at(list, offset, b'(')?;
        colors.push(parse_u8_tuple3(tuple)?);
        offset = end;
    }
    Ok(colors)
}

fn parse_identifier(source: &str, start: usize) -> Result<(String, usize), String> {
    let start = skip_ws(source, start);
    let bytes = source.as_bytes();
    let mut end = start;
    while end < bytes.len() {
        let byte = bytes[end];
        if byte.is_ascii_alphanumeric() || byte == b'_' {
            end += 1;
        } else {
            break;
        }
    }
    if end == start {
        return Err(format!(
            "Veloren manifest identifier is missing near '{}'",
            source[start..].chars().take(32).collect::<String>()
        ));
    }
    Ok((source[start..end].to_string(), end))
}

fn parse_optional_model_index(source: &str) -> Result<usize, String> {
    let source = source.trim_start();
    if !source.starts_with(',') {
        return Ok(0);
    }
    let source = source[1..].trim_start();
    let end = source
        .find(|ch: char| !ch.is_ascii_digit())
        .unwrap_or(source.len());
    if end == 0 {
        return Ok(0);
    }
    source[..end]
        .parse::<usize>()
        .map_err(|err| format!("invalid Veloren model index: {err}"))
}

fn parse_i32_tuple3(source: &str) -> Result<[i32; 3], String> {
    let values = split_tuple3(source)?;
    Ok([
        parse_number(values[0], "i32")?,
        parse_number(values[1], "i32")?,
        parse_number(values[2], "i32")?,
    ])
}

fn parse_f32_tuple3(source: &str) -> Result<[f32; 3], String> {
    let values = split_tuple3(source)?;
    Ok([
        parse_number(values[0], "f32")?,
        parse_number(values[1], "f32")?,
        parse_number(values[2], "f32")?,
    ])
}

fn parse_u8_tuple3(source: &str) -> Result<[u8; 3], String> {
    let values = split_tuple3(source)?;
    Ok([
        parse_number(values[0], "u8")?,
        parse_number(values[1], "u8")?,
        parse_number(values[2], "u8")?,
    ])
}

fn parse_number<T>(source: &str, label: &str) -> Result<T, String>
where
    T: std::str::FromStr,
    T::Err: std::fmt::Display,
{
    source
        .trim()
        .parse::<T>()
        .map_err(|err| format!("invalid Veloren {label} tuple value: {err}"))
}

fn split_tuple3(source: &str) -> Result<Vec<&str>, String> {
    let values: Vec<&str> = source.split(',').map(str::trim).collect();
    if values.len() != 3 {
        return Err(format!("expected 3 tuple values, got {}", values.len()));
    }
    Ok(values)
}

fn extract_named_balanced<'a>(source: &'a str, name: &str, opener: u8) -> Result<&'a str, String> {
    let token = format!("{name}:");
    extract_balanced_after_token(source, &token, opener)
}

fn extract_balanced_after_token<'a>(
    source: &'a str,
    token: &str,
    opener: u8,
) -> Result<&'a str, String> {
    let token_start = source
        .find(token)
        .ok_or_else(|| format!("Veloren manifest token '{token}' is missing"))?;
    let open = skip_ws(source, token_start + token.len());
    let (inner, _) = extract_balanced_at(source, open, opener)?;
    Ok(inner)
}

fn extract_balanced_at(source: &str, open: usize, opener: u8) -> Result<(&str, usize), String> {
    let bytes = source.as_bytes();
    if bytes.get(open).copied() != Some(opener) {
        return Err(format!("expected '{}' in Veloren manifest", opener as char));
    }
    let closer = matching_closer(opener)?;
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
                .ok_or_else(|| "Veloren manifest balance underflow".to_string())?;
            if depth == 0 {
                return Ok((&source[open + 1..idx], idx + 1));
            }
        }
    }
    Err(format!(
        "unclosed '{}' block in Veloren manifest",
        opener as char
    ))
}

fn matching_closer(opener: u8) -> Result<u8, String> {
    match opener {
        b'(' => Ok(b')'),
        b'[' => Ok(b']'),
        b'{' => Ok(b'}'),
        _ => Err(format!(
            "unsupported Veloren manifest opener '{}'",
            opener as char
        )),
    }
}

fn trim_outer_balanced(source: &str, opener: u8) -> Result<&str, String> {
    let source = source.trim();
    if source.as_bytes().first().copied() != Some(opener) {
        return Ok(source);
    }
    let (inner, end) = extract_balanced_at(source, 0, opener)?;
    if source[end..].trim().is_empty() {
        Ok(inner)
    } else {
        Ok(source)
    }
}

fn parse_quoted_string(source: &str) -> Result<(String, usize), String> {
    let bytes = source.as_bytes();
    let start = bytes
        .iter()
        .position(|byte| *byte == b'"')
        .ok_or_else(|| "Veloren manifest string is missing".to_string())?;
    let mut escaped = false;
    let mut value = String::new();
    for (idx, byte) in bytes.iter().enumerate().skip(start + 1) {
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
    Err("unterminated Veloren manifest string".to_string())
}

fn find_byte(source: &str, start: usize, byte: u8) -> Result<usize, String> {
    source.as_bytes()[start..]
        .iter()
        .position(|candidate| *candidate == byte)
        .map(|idx| idx + start)
        .ok_or_else(|| format!("Veloren manifest byte '{}' is missing", byte as char))
}

fn skip_ws(source: &str, start: usize) -> usize {
    source.as_bytes()[start..]
        .iter()
        .position(|byte| !byte.is_ascii_whitespace())
        .map(|idx| idx + start)
        .unwrap_or(source.len())
}

fn skip_ws_and_commas(source: &str, start: usize) -> usize {
    source.as_bytes()[start..]
        .iter()
        .position(|byte| !byte.is_ascii_whitespace() && *byte != b',')
        .map(|idx| idx + start)
        .unwrap_or(source.len())
}

fn strip_ron_line_comments(source: &str) -> String {
    let mut output = String::with_capacity(source.len());
    let bytes = source.as_bytes();
    let mut idx = 0;
    let mut in_string = false;
    let mut escaped = false;
    while idx < bytes.len() {
        let byte = bytes[idx];
        if in_string {
            output.push(byte as char);
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
            in_string = true;
            output.push(byte as char);
            idx += 1;
            continue;
        }
        if byte == b'/' && bytes.get(idx + 1).copied() == Some(b'/') {
            idx += 2;
            while idx < bytes.len() && bytes[idx] != b'\n' {
                idx += 1;
            }
            if idx < bytes.len() {
                output.push('\n');
                idx += 1;
            }
            continue;
        }
        output.push(byte as char);
        idx += 1;
    }
    output
}

fn veloren_vox_res_path(spec_name: &str) -> String {
    format!(
        "res://assets/veloren/voxygen/voxel/{}.vox",
        spec_name.replace('.', "/")
    )
}

fn vec3_i32(value: [i32; 3]) -> (i32, i32, i32) {
    (value[0], value[1], value[2])
}

fn color_from_rgb_array(value: [u8; 3]) -> Color {
    rgb8(value[0], value[1], value[2])
}

fn recolor_grey(color: Color, target: Color) -> Color {
    let color_rgba = rgba8(color);
    if color_rgba.0 != color_rgba.1 || color_rgba.1 != color_rgba.2 {
        return color;
    }
    let target_rgba = rgba8(target);
    let factor = color_rgba.0 as f32 / 178.0;
    rgb8(
        ((target_rgba.0 as f32 * factor).clamp(0.0, 255.0)) as u8,
        ((target_rgba.1 as f32 * factor).clamp(0.0, 255.0)) as u8,
        ((target_rgba.2 as f32 * factor).clamp(0.0, 255.0)) as u8,
    )
}

fn rgb8(r: u8, g: u8, b: u8) -> Color {
    Color::from_rgba8(r, g, b, 255)
}

fn rgba8(color: Color) -> (u8, u8, u8, u8) {
    (
        (color.r.clamp(0.0, 1.0) * 255.0).round() as u8,
        (color.g.clamp(0.0, 1.0) * 255.0).round() as u8,
        (color.b.clamp(0.0, 1.0) * 255.0).round() as u8,
        (color.a.clamp(0.0, 1.0) * 255.0).round() as u8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    #[test]
    fn veloren_spec_paths_match_github_layout() {
        assert_eq!(
            veloren_vox_res_path("figure.head.human.male"),
            "res://assets/veloren/voxygen/voxel/figure/head/human/male.vox"
        );
        assert_eq!(
            veloren_vox_res_path("armor.misc.chest.none"),
            "res://assets/veloren/voxygen/voxel/armor/misc/chest/none.vox"
        );
    }

    #[test]
    fn material_palette_uses_official_color_manifest() {
        let body = HumanoidBody::default_human_male();
        let color_spec = parse_hum_color_manifest(&read_manifest_source_from_repo(
            "humanoid_color_manifest.ron",
        ))
        .expect("humanoid color manifest should parse");
        let palette =
            MaterialPalette::for_body(&color_spec, body).expect("default body colors should load");

        assert_eq!(palette.skin, rgb8(228, 173, 146));
        assert_eq!(palette.hair, rgb8(64, 32, 18));
        assert_eq!(palette.eye_dark, rgb8(13, 47, 64));
        assert_eq!(palette.eye_light, rgb8(18, 66, 90));
        assert_eq!(palette.eye_white, rgb8(255, 255, 255));
    }

    #[test]
    fn armor_manifest_named_lookup_reads_map_entries() {
        let manifest = parse_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_chest_manifest.ron",
        ))
        .expect("chest armor manifest should parse");
        let blue = manifest
            .0
            .spec(Some("Blue"), "humanoid_armor_chest_manifest.ron")
            .expect("named armor entries should be available");

        assert_eq!(blue.vox_spec.0, "armor.misc.chest.grayscale");
        assert_eq!(blue.color, Some([44, 74, 109]));
    }

    #[test]
    fn union_segments_matches_veloren_head_overlay_rules() {
        let mut base = Segment::default();
        base.cells.insert((0, 0, 0), Cell::filled(rgb8(1, 2, 3)));
        let mut hollow = Segment::default();
        hollow.cells.insert((0, 0, 0), Cell::hollow());
        let mut replacement = Segment::default();
        replacement
            .cells
            .insert((0, 0, 0), Cell::filled(rgb8(9, 8, 7)));

        let result = union_segments(vec![
            (base, (0, 0, 0)),
            (hollow, (0, 0, 0)),
            (replacement, (0, 0, 0)),
        ]);

        assert_eq!(result.cells.len(), 1);
        assert_eq!(result.cells.get(&(0, 0, 0)).unwrap().color, rgb8(9, 8, 7));

        let mut protected = Segment::default();
        protected
            .cells
            .insert((0, 0, 0), Cell::override_hollow(rgb8(2, 2, 2)));
        let mut later_hollow = Segment::default();
        later_hollow.cells.insert((0, 0, 0), Cell::hollow());
        let result = union_segments(vec![(protected, (0, 0, 0)), (later_hollow, (0, 0, 0))]);

        assert_eq!(result.cells.len(), 1);
        assert_eq!(result.cells.get(&(0, 0, 0)).unwrap().color, rgb8(2, 2, 2));
    }

    #[test]
    fn default_human_male_composer_assets_are_local() {
        let body = HumanoidBody::default_human_male();
        let head_manifest = parse_head_manifest(&read_manifest_source_from_repo(
            "humanoid_head_manifest.ron",
        ))
        .expect("head manifest should parse");
        let head_spec = head_manifest
            .0
            .get(&(body.species, body.body_type))
            .expect("default Human/Male head spec must be present");

        assert_vox_asset_exists(&head_spec.head.0);
        assert_indexed_vox_asset_exists(&head_spec.eyes, body.eyes);
        assert_indexed_vox_asset_exists(&head_spec.hair, body.hair_style);
        assert_indexed_vox_asset_exists(&head_spec.beard, body.beard);
        assert!(head_spec.accessory[body.accessory].is_none());

        let chest = parse_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_chest_manifest.ron",
        ))
        .expect("chest armor manifest should parse");
        assert_vox_asset_exists(&chest.0.default.vox_spec.0);
        let belt = parse_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_belt_manifest.ron",
        ))
        .expect("belt armor manifest should parse");
        assert_vox_asset_exists(&belt.0.default.vox_spec.0);
        let pants = parse_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_pants_manifest.ron",
        ))
        .expect("pants armor manifest should parse");
        assert_vox_asset_exists(&pants.0.default.vox_spec.0);
        let foot = parse_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_foot_manifest.ron",
        ))
        .expect("foot armor manifest should parse");
        assert_vox_asset_exists(&foot.0.default.vox_spec.0);

        let hand = parse_sided_armor_manifest(&read_manifest_source_from_repo(
            "humanoid_armor_hand_manifest.ron",
        ))
        .expect("hand armor manifest should parse");
        assert_vox_asset_exists(&hand.0.default.left.vox_spec.0);
        assert_vox_asset_exists(&hand.0.default.right.vox_spec.0);
        assert!(repo_asset_root().join("armor/empty.vox").is_file());
    }

    fn read_manifest_source_from_repo(path: &str) -> String {
        let path = repo_asset_root().join(path);
        std::fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()))
    }

    fn assert_indexed_vox_asset_exists(specs: &[Option<VoxSpec<i32>>], index: usize) {
        let spec = specs[index]
            .as_ref()
            .expect("default indexed composer part must be present");
        assert_vox_asset_exists(&spec.0);
    }

    fn assert_vox_asset_exists(spec_name: &str) {
        let path = repo_asset_root().join(format!("{}.vox", spec_name.replace('.', "/")));
        assert!(
            path.is_file(),
            "missing local Veloren asset {}",
            path.display()
        );
    }

    fn repo_asset_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../assets/veloren/voxygen/voxel")
    }
}
