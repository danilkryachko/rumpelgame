#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SHADOW_ON_DIR="${1:-"$ROOT_DIR/logs/gpu_shadow_xctrace_attach_current"}"
SHADOW_DISABLED_DIR="${2:-"$ROOT_DIR/logs/gpu_shadow_xctrace_shadow_disabled_control"}"
OUT_DIR="${3:-"$ROOT_DIR/logs/gpu_shadow_xctrace_shadow_overhead_current"}"
case "$SHADOW_ON_DIR" in
  /*) ;;
  *) SHADOW_ON_DIR="$ROOT_DIR/$SHADOW_ON_DIR" ;;
esac
case "$SHADOW_DISABLED_DIR" in
  /*) ;;
  *) SHADOW_DISABLED_DIR="$ROOT_DIR/$SHADOW_DISABLED_DIR" ;;
esac
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="${RUMPELMC_SHADOW_XCTRACE_OVERHEAD_SUMMARY:-"$OUT_DIR/shadow-xctrace-shadow-overhead-summary.txt"}"
case "$SUMMARY_PATH" in
  /*) ;;
  *) SUMMARY_PATH="$ROOT_DIR/$SUMMARY_PATH" ;;
esac
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 2>/dev/null || true)}"

fail() {
  echo "gpu_terrain_shadow_xctrace_overhead_summary: $*" >&2
  exit 1
}

test -n "$PYTHON_BIN" || fail "python3 was not found"
mkdir -p "$OUT_DIR" "$(dirname -- "$SUMMARY_PATH")"

"$PYTHON_BIN" - "$ROOT_DIR" "$SHADOW_ON_DIR" "$SHADOW_DISABLED_DIR" "$SUMMARY_PATH" <<'PY'
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean

root_dir = Path(sys.argv[1]).resolve()
shadow_on_dir = Path(sys.argv[2]).resolve()
shadow_disabled_dir = Path(sys.argv[3]).resolve()
summary_path = Path(sys.argv[4]).resolve()

warmup_frame = int(os.environ.get("RUMPELMC_SHADOW_XCTRACE_OVERHEAD_WARMUP_FRAME", "100"))
min_main_frames = int(os.environ.get("RUMPELMC_SHADOW_XCTRACE_OVERHEAD_MIN_MAIN_FRAMES", "10"))


def fail(message):
    raise SystemExit(f"gpu_terrain_shadow_xctrace_overhead_summary: {message}")


def resolve_input(value):
    if not value:
        return None
    path = Path(value)
    if not path.is_absolute():
        path = root_dir / path
    return path.resolve()


def rel(path):
    path = Path(path).resolve()
    try:
        return path.relative_to(root_dir).as_posix()
    except ValueError:
        return path.as_posix()


def token_value(text, key):
    pattern = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(key) + r'=("[^"]*"|\S+)')
    match = pattern.search(text)
    if not match:
        return ""
    value = match.group(1)
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    return value


def require_marker(path, expected_shadow_path):
    if not path or not path.is_file() or path.stat().st_size == 0:
        fail(f"missing marker {path}")
    text = path.read_text(errors="replace")
    if "Visual smoke screenshot saved" not in text:
        fail(f"marker does not record visual smoke screenshot: {path}")
    shadow_path = token_value(text, "shadow_path")
    if shadow_path != expected_shadow_path:
        fail(f"marker shadow_path={shadow_path}, expected {expected_shadow_path}: {path}")
    smoke_err = token_value(text, "smoke_err")
    if smoke_err != "0":
        fail(f"marker smoke_err={smoke_err}, expected 0: {path}")
    upload_fail = token_value(text, "gpu_upload_fail")
    if upload_fail and upload_fail != "0":
        fail(f"marker gpu_upload_fail={upload_fail}, expected 0: {path}")
    return text


def find_shadow_disabled_marker():
    env_path = resolve_input(os.environ.get("RUMPELMC_SHADOW_XCTRACE_DISABLED_MARKER", ""))
    candidates = []
    if env_path:
        candidates.append(env_path)
    candidates.append(shadow_disabled_dir / "gpu-terrain-compact.png.txt")
    candidates.append(Path(f"{shadow_disabled_dir}_marker") / "gpu-terrain-compact.png.txt")
    for candidate in candidates:
        if candidate.is_file() and candidate.stat().st_size > 0:
            return candidate.resolve()
    return candidates[0] if candidates else None


def require_xml_dir(path):
    required = [
        "metal-command-buffer-submissions.xml",
        "metal-application-encoders-list.xml",
        "metal-gpu-intervals.xml",
        "metal-command-buffer-frame-assignment.xml",
    ]
    if not path.is_dir():
        fail(f"missing xctrace XML directory {path}")
    for name in required:
        xml_path = path / name
        if not xml_path.is_file() or xml_path.stat().st_size == 0:
            fail(f"missing required XML export {xml_path}")


def parse_table(path):
    tree = ET.parse(path)
    root = tree.getroot()
    schema = root.find(".//schema")
    if schema is None:
        fail(f"missing schema in {path}")
    cols = [col.findtext("mnemonic") for col in schema.findall("col")]
    idmap = {}
    rows = []

    def capture(element):
        if "ref" in element.attrib:
            return idmap.get(element.attrib["ref"], ("", ""))
        fmt = element.attrib.get("fmt")
        text = "".join(element.itertext()).strip() if (element.text or list(element)) else (element.text or "").strip()
        if fmt is None:
            fmt = text
        if "id" in element.attrib:
            idmap[element.attrib["id"]] = (fmt, text)
        for child in list(element):
            capture(child)
        return fmt, text

    for row in root.findall(".//row"):
        values = [capture(child) for child in list(row)]
        rows.append({cols[index]: values[index] if index < len(values) else ("", "") for index in range(len(cols))})
    return rows


def raw(value):
    if isinstance(value, tuple):
        return (value[1] or value[0] or "").strip()
    return str(value).strip()


def display(value):
    if isinstance(value, tuple):
        return (value[0] or value[1] or "").strip()
    return str(value).strip()


def number(value):
    text = raw(value).replace(",", "").replace("\u00a0", "").strip()
    if not text:
        text = display(value).replace(",", "").replace("\u00a0", "").strip()
    try:
        return float(text)
    except ValueError:
        return 0.0


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def metric(value):
    return f"{value:.3f}"


def label_token(label):
    return re.sub(r"[^A-Za-z0-9_.:-]+", "_", label.strip()) or "none"


def encoder_kind(label):
    if label.startswith("Render"):
        return "Render"
    if label.startswith("Blit"):
        return "Blit"
    if label.startswith("Compute"):
        return "Compute"
    return label.split(" ", 1)[0] if label else "unknown"


def collect_main_buffers(capture_dir):
    submissions = parse_table(capture_dir / "metal-command-buffer-submissions.xml")
    frames = parse_table(capture_dir / "metal-command-buffer-frame-assignment.xml")
    encoders = parse_table(capture_dir / "metal-application-encoders-list.xml")
    gpu_intervals = parse_table(capture_dir / "metal-gpu-intervals.xml")

    frame_by_cb = {}
    for row in frames:
        if "godot" not in display(row.get("process", ("", ""))):
            continue
        cbid = raw(row.get("cmdbuffer-id", ("", "")))
        if cbid:
            frame_by_cb[cbid] = int(number(row.get("frame-number", ("", ""))))

    encoder_count_by_cb = {}
    for row in submissions:
        if "godot" not in display(row.get("process", ("", ""))):
            continue
        cbid = raw(row.get("cmdbuffer-id", ("", "")))
        if cbid:
            encoder_count_by_cb[cbid] = int(number(row.get("num-encoders", ("", ""))))

    gpu_ms_by_encoder = defaultdict(float)
    for row in gpu_intervals:
        if "godot" not in display(row.get("process", ("", ""))):
            continue
        encoder_id = raw(row.get("encoder-id", ("", "")))
        if encoder_id:
            gpu_ms_by_encoder[encoder_id] += number(row.get("duration", ("", ""))) / 1_000_000.0

    encoders_by_cb = defaultdict(list)
    for row in encoders:
        if "godot" not in display(row.get("process", ("", ""))):
            continue
        cbid = raw(row.get("cmdbuffer-id", ("", "")))
        if cbid:
            encoders_by_cb[cbid].append(row)

    main_count_candidates = Counter()
    for cbid, encoder_count in encoder_count_by_cb.items():
        if encoder_count > 1 and frame_by_cb.get(cbid, 0) >= warmup_frame:
            main_count_candidates[encoder_count] += 1
    if not main_count_candidates:
        fail(f"no post-warmup multi-encoder Godot command buffers in {capture_dir}")
    main_encoder_count = main_count_candidates.most_common(1)[0][0]

    rows = []
    encoder_count_pattern = Counter()
    for cbid, encoder_count in encoder_count_by_cb.items():
        frame_number = frame_by_cb.get(cbid, 0)
        if frame_number < warmup_frame:
            continue
        encoder_count_pattern[encoder_count] += 1
        if encoder_count != main_encoder_count:
            continue
        cb_encoders = sorted(encoders_by_cb.get(cbid, []), key=lambda row: number(row.get("start", ("", ""))))
        if len(cb_encoders) != main_encoder_count:
            continue
        labels = [display(row.get("encoder-label", ("", ""))) for row in cb_encoders]
        durations = [gpu_ms_by_encoder[raw(row.get("encoder-id", ("", "")))] for row in cb_encoders]
        rows.append((frame_number, labels, durations))

    if len(rows) < min_main_frames:
        fail(f"only {len(rows)} main command buffers after warmup in {capture_dir}; expected at least {min_main_frames}")
    return {
        "main_encoder_count": main_encoder_count,
        "encoder_count_pattern": encoder_count_pattern,
        "rows": rows,
    }


def summarize(rows):
    totals = [sum(durations) for _, _, durations in rows]
    render_totals = []
    blit_totals = []
    for _, labels, durations in rows:
        render_totals.append(sum(duration for label, duration in zip(labels, durations) if label.startswith("Render")))
        blit_totals.append(sum(duration for label, duration in zip(labels, durations) if label.startswith("Blit")))
    return {
        "frames": len(rows),
        "total_p50": percentile(totals, 0.50),
        "total_p95": percentile(totals, 0.95),
        "total_avg": mean(totals),
        "total_max": max(totals),
        "render_p50": percentile(render_totals, 0.50),
        "render_avg": mean(render_totals),
        "blit_p50": percentile(blit_totals, 0.50),
        "blit_avg": mean(blit_totals),
    }


def infer_alignment(on_rows, off_rows):
    on_labels = on_rows[0][1]
    off_labels = off_rows[0][1]
    on_kinds = [encoder_kind(label) for label in on_labels]
    off_kinds = [encoder_kind(label) for label in off_labels]
    if len(on_kinds) == len(off_kinds) + 1:
        matches = [index for index in range(len(on_kinds)) if on_kinds[:index] + on_kinds[index + 1 :] == off_kinds]
        if len(matches) == 1:
            index = matches[0]
            return "single_missing_encoder", index, on_labels[index]
    return "not_aligned", None, "none"


require_xml_dir(shadow_on_dir)
require_xml_dir(shadow_disabled_dir)

shadow_on_marker = resolve_input(os.environ.get("RUMPELMC_SHADOW_XCTRACE_ON_MARKER", "")) or shadow_on_dir / "gpu-terrain-compact.png.txt"
shadow_disabled_marker = find_shadow_disabled_marker()
require_marker(shadow_on_marker, "godot_proxy")
require_marker(shadow_disabled_marker, "scene_shadows_disabled")

disabled_marker_binding = "same_capture"
if shadow_disabled_marker.parent.resolve() != shadow_disabled_dir:
    disabled_marker_binding = "separate_control_marker"

on_collected = collect_main_buffers(shadow_on_dir)
off_collected = collect_main_buffers(shadow_disabled_dir)
on_summary = summarize(on_collected["rows"])
off_summary = summarize(off_collected["rows"])
alignment_status, missing_position, missing_label = infer_alignment(on_collected["rows"], off_collected["rows"])

p50_delta = on_summary["total_p50"] - off_summary["total_p50"]
avg_delta = on_summary["total_avg"] - off_summary["total_avg"]
p95_delta = on_summary["total_p95"] - off_summary["total_p95"]
max_delta = on_summary["total_max"] - off_summary["total_max"]

summary_path.parent.mkdir(parents=True, exist_ok=True)
with summary_path.open("w", encoding="utf-8") as out:
    out.write(
        "shadow_xctrace_shadow_overhead "
        "status=pass "
        "source=control_delta "
        f"shadow_on_dir={rel(shadow_on_dir)} "
        f"shadow_disabled_dir={rel(shadow_disabled_dir)} "
        f"shadow_on_marker={rel(shadow_on_marker)} "
        f"shadow_disabled_marker={rel(shadow_disabled_marker)} "
        f"shadow_disabled_marker_binding={disabled_marker_binding} "
        f"warmup_frame={warmup_frame} "
        f"shadow_on_main_encoder_count={on_collected['main_encoder_count']} "
        f"shadow_disabled_main_encoder_count={off_collected['main_encoder_count']} "
        f"shadow_on_frames={on_summary['frames']} "
        f"shadow_disabled_frames={off_summary['frames']} "
        f"shadow_on_total_gpu_p50_ms={metric(on_summary['total_p50'])} "
        f"shadow_on_total_gpu_p95_ms={metric(on_summary['total_p95'])} "
        f"shadow_on_total_gpu_avg_ms={metric(on_summary['total_avg'])} "
        f"shadow_disabled_total_gpu_p50_ms={metric(off_summary['total_p50'])} "
        f"shadow_disabled_total_gpu_p95_ms={metric(off_summary['total_p95'])} "
        f"shadow_disabled_total_gpu_avg_ms={metric(off_summary['total_avg'])} "
        f"shadow_overhead_estimate_p50_ms={metric(p50_delta)} "
        f"shadow_overhead_estimate_p95_ms={metric(p95_delta)} "
        f"shadow_overhead_estimate_avg_ms={metric(avg_delta)} "
        f"shadow_overhead_estimate_max_delta_ms={metric(max_delta)} "
        "estimate_is_not_gpu_shadow_pass_ms=1 "
        "result_row_status=not_written\n"
    )
    out.write(
        "encoder_alignment "
        f"status={alignment_status} "
        f"encoder_count_delta={on_collected['main_encoder_count'] - off_collected['main_encoder_count']} "
        f"missing_encoder_position={missing_position if missing_position is not None else 'none'} "
        f"missing_encoder_label={label_token(missing_label)} "
        "alignment_is_navigation_only=1\n"
    )
    out.write(
        "trust_boundary "
        "shadow_overhead_summary_is_not_profiler_result=1 "
        "control_delta_is_not_shadow_pass_row=1 "
        "xctrace_exports_are_not_result_rows=1 "
        "gpu_shadow_pass_ms_status=missing "
        "manual_gpu_shadow_pass_ms_required=1\n"
    )
    out.write(
        "operator_steps=open_trace_identify_shadow_pass_record_positive_row_validate_results_then_campaign_gate\n"
    )
PY

cat "$SUMMARY_PATH"
