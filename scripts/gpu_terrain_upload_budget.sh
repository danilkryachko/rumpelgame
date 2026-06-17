#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_budget_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-upload-budget-summary.txt"
MOVEMENT_SUMMARY="${RUMPELMC_GPU_UPLOAD_BUDGET_MOVEMENT_SUMMARY:-"$ROOT_DIR/logs/gpu_upload_lane_split_movement_current/movement-stress-summary.txt"}"
MOVEMENT_DIR="$(dirname -- "$MOVEMENT_SUMMARY")"
MOVEMENT_MARKER="${RUMPELMC_GPU_UPLOAD_BUDGET_MOVEMENT_MARKER:-"$MOVEMENT_DIR/gpu-terrain-movement-stress.png.txt"}"
IN_PLACE_SUMMARY="${RUMPELMC_GPU_UPLOAD_BUDGET_IN_PLACE_SUMMARY:-"$ROOT_DIR/logs/gpu_upload_lane_split_in_place_current/gpu-in-place-upload-summary.txt"}"

MAX_UPLOADS_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_UPLOADS_PER_FRAME:-1}"
MAX_UPLOAD_KB_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_UPLOAD_KB_PER_FRAME:-2.0}"
MAX_NEW_SLOT_UPLOADS_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_NEW_SLOT_UPLOADS_PER_FRAME:-1}"
MAX_REPLACE_SLOT_UPLOADS_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_REPLACE_SLOT_UPLOADS_PER_FRAME:-1}"
MAX_NEW_SLOT_UPLOAD_KB_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_NEW_SLOT_UPLOAD_KB_PER_FRAME:-2.0}"
MAX_REPLACE_SLOT_UPLOAD_KB_PER_FRAME="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_REPLACE_SLOT_UPLOAD_KB_PER_FRAME:-2.0}"
MAX_UPLOAD_FAIL="${RUMPELMC_GPU_UPLOAD_BUDGET_MAX_UPLOAD_FAIL:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_upload_budget: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

row_field_metric() {
  row="$1"
  key="$2"
  path="$3"
  awk -v row="$row" -v key="$key" '
    $1 == row {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

require_field() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

require_row_field() {
  row="$1"
  key="$2"
  path="$3"
  value="$(row_field_metric "$row" "$key" "$path")"
  test -n "$value" || fail "missing $key in $row row of $(relative_path "$path")"
  printf '%s\n' "$value"
}

test -s "$MOVEMENT_SUMMARY" || fail "missing movement summary $MOVEMENT_SUMMARY"
test -s "$MOVEMENT_MARKER" || fail "missing movement marker $MOVEMENT_MARKER"
test -s "$IN_PLACE_SUMMARY" || fail "missing in-place summary $IN_PLACE_SUMMARY"

movement_budget_status="$(require_row_field movement_terrain_queue budget_status "$MOVEMENT_SUMMARY")"
movement_uploads_max="$(require_row_field movement_terrain_queue queue_uploads_max "$MOVEMENT_SUMMARY")"
movement_upload_kb_max="$(require_row_field movement_terrain_queue queue_upload_kb_max "$MOVEMENT_SUMMARY")"
movement_new_slot_uploads_max="$(require_row_field movement_terrain_queue queue_new_slot_uploads_max "$MOVEMENT_SUMMARY")"
movement_replace_slot_uploads_max="$(require_row_field movement_terrain_queue queue_replace_slot_uploads_max "$MOVEMENT_SUMMARY")"
movement_new_slot_upload_kb_max="$(require_row_field movement_terrain_queue queue_new_slot_upload_kb_max "$MOVEMENT_SUMMARY")"
movement_replace_slot_upload_kb_max="$(require_row_field movement_terrain_queue queue_replace_slot_upload_kb_max "$MOVEMENT_SUMMARY")"
movement_upload_fail="$(require_field gpu_upload_fail "$MOVEMENT_MARKER")"
movement_upload_fail_capacity="$(require_row_field movement_terrain_queue gpu_upload_fail_capacity "$MOVEMENT_SUMMARY")"
movement_upload_fail_fragmented="$(require_row_field movement_terrain_queue gpu_upload_fail_fragmented "$MOVEMENT_SUMMARY")"
movement_upload_retry_policy="$(require_row_field movement_terrain_queue gpu_upload_retry_policy "$MOVEMENT_SUMMARY")"
movement_upload_retry_attempts="$(require_row_field movement_terrain_queue gpu_upload_retry_attempts "$MOVEMENT_SUMMARY")"
movement_upload_retry_success="$(require_row_field movement_terrain_queue gpu_upload_retry_success "$MOVEMENT_SUMMARY")"
movement_upload_retry_giveups="$(require_row_field movement_terrain_queue gpu_upload_retry_giveups "$MOVEMENT_SUMMARY")"
movement_upload_backoff_active="$(require_row_field movement_terrain_queue gpu_upload_backoff_active "$MOVEMENT_SUMMARY")"
movement_upload_backoff_frames="$(require_row_field movement_terrain_queue gpu_upload_backoff_frames "$MOVEMENT_SUMMARY")"
movement_upload_backoff_max_frames="$(require_row_field movement_terrain_queue gpu_upload_backoff_max_frames "$MOVEMENT_SUMMARY")"

in_place_status="$(require_field status "$IN_PLACE_SUMMARY")"
in_place_enabled="$(require_field gpu_in_place_upload_enabled "$IN_PLACE_SUMMARY")"
in_place_uploads="$(require_field gpu_in_place_uploads "$IN_PLACE_SUMMARY")"
in_place_upload_fail="$(require_field gpu_upload_fail "$IN_PLACE_SUMMARY")"
in_place_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$IN_PLACE_SUMMARY")"
in_place_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$IN_PLACE_SUMMARY")"
in_place_upload_retry_policy="$(require_field gpu_upload_retry_policy "$IN_PLACE_SUMMARY")"
in_place_upload_retry_attempts="$(require_field gpu_upload_retry_attempts "$IN_PLACE_SUMMARY")"
in_place_upload_retry_success="$(require_field gpu_upload_retry_success "$IN_PLACE_SUMMARY")"
in_place_upload_retry_giveups="$(require_field gpu_upload_retry_giveups "$IN_PLACE_SUMMARY")"
in_place_upload_backoff_active="$(require_field gpu_upload_backoff_active "$IN_PLACE_SUMMARY")"
in_place_upload_backoff_frames="$(require_field gpu_upload_backoff_frames "$IN_PLACE_SUMMARY")"
in_place_upload_backoff_max_frames="$(require_field gpu_upload_backoff_max_frames "$IN_PLACE_SUMMARY")"
in_place_new_slot_uploads_max="$(require_field terrain_queue_new_slot_uploads_max "$IN_PLACE_SUMMARY")"
in_place_replace_slot_uploads_max="$(require_field terrain_queue_replace_slot_uploads_max "$IN_PLACE_SUMMARY")"
in_place_new_slot_upload_kb_max="$(require_field terrain_queue_new_slot_upload_kb_max "$IN_PLACE_SUMMARY")"
in_place_replace_slot_upload_kb_max="$(require_field terrain_queue_replace_slot_upload_kb_max "$IN_PLACE_SUMMARY")"

awk \
  -v movement_budget_status="$movement_budget_status" \
  -v movement_uploads_max="$movement_uploads_max" \
  -v movement_upload_kb_max="$movement_upload_kb_max" \
  -v movement_new_slot_uploads_max="$movement_new_slot_uploads_max" \
  -v movement_replace_slot_uploads_max="$movement_replace_slot_uploads_max" \
  -v movement_new_slot_upload_kb_max="$movement_new_slot_upload_kb_max" \
  -v movement_replace_slot_upload_kb_max="$movement_replace_slot_upload_kb_max" \
  -v movement_upload_fail="$movement_upload_fail" \
  -v movement_upload_fail_capacity="$movement_upload_fail_capacity" \
  -v movement_upload_fail_fragmented="$movement_upload_fail_fragmented" \
  -v movement_upload_retry_policy="$movement_upload_retry_policy" \
  -v movement_upload_retry_attempts="$movement_upload_retry_attempts" \
  -v movement_upload_retry_success="$movement_upload_retry_success" \
  -v movement_upload_retry_giveups="$movement_upload_retry_giveups" \
  -v movement_upload_backoff_active="$movement_upload_backoff_active" \
  -v movement_upload_backoff_frames="$movement_upload_backoff_frames" \
  -v movement_upload_backoff_max_frames="$movement_upload_backoff_max_frames" \
  -v in_place_status="$in_place_status" \
  -v in_place_enabled="$in_place_enabled" \
  -v in_place_uploads="$in_place_uploads" \
  -v in_place_upload_fail="$in_place_upload_fail" \
  -v in_place_upload_fail_capacity="$in_place_upload_fail_capacity" \
  -v in_place_upload_fail_fragmented="$in_place_upload_fail_fragmented" \
  -v in_place_upload_retry_policy="$in_place_upload_retry_policy" \
  -v in_place_upload_retry_attempts="$in_place_upload_retry_attempts" \
  -v in_place_upload_retry_success="$in_place_upload_retry_success" \
  -v in_place_upload_retry_giveups="$in_place_upload_retry_giveups" \
  -v in_place_upload_backoff_active="$in_place_upload_backoff_active" \
  -v in_place_upload_backoff_frames="$in_place_upload_backoff_frames" \
  -v in_place_upload_backoff_max_frames="$in_place_upload_backoff_max_frames" \
  -v in_place_new_slot_uploads_max="$in_place_new_slot_uploads_max" \
  -v in_place_replace_slot_uploads_max="$in_place_replace_slot_uploads_max" \
  -v in_place_new_slot_upload_kb_max="$in_place_new_slot_upload_kb_max" \
  -v in_place_replace_slot_upload_kb_max="$in_place_replace_slot_upload_kb_max" \
  -v max_uploads="$MAX_UPLOADS_PER_FRAME" \
  -v max_upload_kb="$MAX_UPLOAD_KB_PER_FRAME" \
  -v max_new_uploads="$MAX_NEW_SLOT_UPLOADS_PER_FRAME" \
  -v max_replace_uploads="$MAX_REPLACE_SLOT_UPLOADS_PER_FRAME" \
  -v max_new_upload_kb="$MAX_NEW_SLOT_UPLOAD_KB_PER_FRAME" \
  -v max_replace_upload_kb="$MAX_REPLACE_SLOT_UPLOAD_KB_PER_FRAME" \
  -v max_upload_fail="$MAX_UPLOAD_FAIL" \
  -v movement_summary="$MOVEMENT_SUMMARY" \
  -v movement_marker="$MOVEMENT_MARKER" \
  -v in_place_summary="$IN_PLACE_SUMMARY" '
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  BEGIN {
    status = "pass"
    reason = "within_budget"

    if (movement_budget_status != "pass") {
      set_fail("movement_queue_budget")
    } else if (in_place_status != "pass" || in_place_enabled + 0 != 1 || in_place_uploads + 0 < 1) {
      set_fail("in_place_prerequisite")
    } else if (movement_upload_fail + 0 > max_upload_fail || movement_upload_fail_capacity + 0 > max_upload_fail || movement_upload_fail_fragmented + 0 > max_upload_fail || in_place_upload_fail + 0 > max_upload_fail || in_place_upload_fail_capacity + 0 > max_upload_fail || in_place_upload_fail_fragmented + 0 > max_upload_fail) {
      set_fail("upload_failure_budget")
    } else if (movement_upload_retry_policy != "none" || in_place_upload_retry_policy != "none" || movement_upload_retry_attempts + 0 != 0 || movement_upload_retry_success + 0 != 0 || movement_upload_retry_giveups + 0 != 0 || movement_upload_backoff_active + 0 != 0 || movement_upload_backoff_frames + 0 != 0 || movement_upload_backoff_max_frames + 0 != 0 || in_place_upload_retry_attempts + 0 != 0 || in_place_upload_retry_success + 0 != 0 || in_place_upload_retry_giveups + 0 != 0 || in_place_upload_backoff_active + 0 != 0 || in_place_upload_backoff_frames + 0 != 0 || in_place_upload_backoff_max_frames + 0 != 0) {
      set_fail("upload_retry_backoff_budget")
    } else if (movement_uploads_max + 0 > max_uploads + 0) {
      set_fail("movement_upload_count_budget")
    } else if (movement_upload_kb_max + 0.0 > max_upload_kb + 0.0) {
      set_fail("movement_upload_kb_budget")
    } else if (movement_new_slot_uploads_max + 0 > max_new_uploads + 0 || in_place_new_slot_uploads_max + 0 > max_new_uploads + 0) {
      set_fail("new_slot_upload_count_budget")
    } else if (movement_replace_slot_uploads_max + 0 > max_replace_uploads + 0 || in_place_replace_slot_uploads_max + 0 > max_replace_uploads + 0) {
      set_fail("replace_slot_upload_count_budget")
    } else if (movement_new_slot_upload_kb_max + 0.0 > max_new_upload_kb + 0.0 || in_place_new_slot_upload_kb_max + 0.0 > max_new_upload_kb + 0.0) {
      set_fail("new_slot_upload_kb_budget")
    } else if (movement_replace_slot_upload_kb_max + 0.0 > max_replace_upload_kb + 0.0 || in_place_replace_slot_upload_kb_max + 0.0 > max_replace_upload_kb + 0.0) {
      set_fail("replace_slot_upload_kb_budget")
    }

    printf("gpu_terrain_upload_budget status=%s reason=%s movement_budget_status=%s in_place_status=%s max_uploads_per_frame=%s movement_uploads_max=%s max_upload_kb_per_frame=%.3f movement_upload_kb_max=%.3f max_new_slot_uploads_per_frame=%s movement_new_slot_uploads_max=%s in_place_new_slot_uploads_max=%s max_replace_slot_uploads_per_frame=%s movement_replace_slot_uploads_max=%s in_place_replace_slot_uploads_max=%s max_new_slot_upload_kb_per_frame=%.3f movement_new_slot_upload_kb_max=%.3f in_place_new_slot_upload_kb_max=%.3f max_replace_slot_upload_kb_per_frame=%.3f movement_replace_slot_upload_kb_max=%.3f in_place_replace_slot_upload_kb_max=%.3f max_upload_fail=%s movement_upload_fail=%s movement_upload_fail_capacity=%s movement_upload_fail_fragmented=%s in_place_upload_fail=%s in_place_upload_fail_capacity=%s in_place_upload_fail_fragmented=%s movement_upload_retry_policy=%s movement_upload_retry_attempts=%s movement_upload_retry_success=%s movement_upload_retry_giveups=%s movement_upload_backoff_active=%s movement_upload_backoff_frames=%s movement_upload_backoff_max_frames=%s in_place_upload_retry_policy=%s in_place_upload_retry_attempts=%s in_place_upload_retry_success=%s in_place_upload_retry_giveups=%s in_place_upload_backoff_active=%s in_place_upload_backoff_frames=%s in_place_upload_backoff_max_frames=%s in_place_enabled=%s in_place_uploads=%s movement_summary=%s movement_marker=%s in_place_summary=%s\n", status, reason, movement_budget_status, in_place_status, max_uploads, movement_uploads_max, max_upload_kb + 0.0, movement_upload_kb_max + 0.0, max_new_uploads, movement_new_slot_uploads_max, in_place_new_slot_uploads_max, max_replace_uploads, movement_replace_slot_uploads_max, in_place_replace_slot_uploads_max, max_new_upload_kb + 0.0, movement_new_slot_upload_kb_max + 0.0, in_place_new_slot_upload_kb_max + 0.0, max_replace_upload_kb + 0.0, movement_replace_slot_upload_kb_max + 0.0, in_place_replace_slot_upload_kb_max + 0.0, max_upload_fail, movement_upload_fail, movement_upload_fail_capacity, movement_upload_fail_fragmented, in_place_upload_fail, in_place_upload_fail_capacity, in_place_upload_fail_fragmented, movement_upload_retry_policy, movement_upload_retry_attempts, movement_upload_retry_success, movement_upload_retry_giveups, movement_upload_backoff_active, movement_upload_backoff_frames, movement_upload_backoff_max_frames, in_place_upload_retry_policy, in_place_upload_retry_attempts, in_place_upload_retry_success, in_place_upload_retry_giveups, in_place_upload_backoff_active, in_place_upload_backoff_frames, in_place_upload_backoff_max_frames, in_place_enabled, in_place_uploads, movement_summary, movement_marker, in_place_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU terrain upload budget failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain upload budget artifacts: $OUT_DIR"
