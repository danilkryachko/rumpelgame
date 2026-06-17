#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_scheduler_tie_probe_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-scheduler-tie-probe-summary.txt"
SOURCE_MATRIX_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt"}"
SOURCE_MATRIX_CASES="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_MATRIX_CASES:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-cases.txt"}"
RUN_WORKLOADS="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_RUN_WORKLOADS:-0}"
MOTION="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_MOTION:-chunk_fly_snap_back}"
MODES="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_MODES:-nearest directional_tie_preview directional_tie}"
REQUIRE_RUNTIME_SIGNAL="${RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_REQUIRE_RUNTIME_SIGNAL:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_streaming_scheduler_tie_probe: $*" >&2
  exit 1
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
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

require_field() {
  label="$1"
  key="$2"
  expected="$3"
  path="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  test "$value" = "$expected" || fail "$label $key=$value, expected $expected"
  printf '%s\n' "$value"
}

mode_active_expected() {
  case "$1" in
    nearest|directional_tie_preview) printf '0\n' ;;
    directional_tie) printf '1\n' ;;
    *) fail "unsupported scheduler mode $1" ;;
  esac
}

if [ "$RUN_WORKLOADS" = "1" ]; then
  matrix_dir="$OUT_DIR/workload-matrix"
  RUMPELMC_STREAMING_SCHEDULER_MATRIX_RUN_WORKLOADS=1 \
    RUMPELMC_STREAMING_SCHEDULER_MATRIX_MOTIONS="$MOTION" \
    RUMPELMC_STREAMING_SCHEDULER_MATRIX_MODES="$MODES" \
    RUMPELMC_STREAMING_SCHEDULER_MATRIX_REQUIRE_RUNTIME_SIGNAL="$REQUIRE_RUNTIME_SIGNAL" \
    sh "$ROOT_DIR/scripts/gpu_streaming_scheduler_workload_matrix.sh" "$matrix_dir"
  SOURCE_MATRIX_SUMMARY="$matrix_dir/gpu-streaming-scheduler-workload-matrix-summary.txt"
  SOURCE_MATRIX_CASES="$matrix_dir/gpu-streaming-scheduler-workload-matrix-cases.txt"
fi

SOURCE_MATRIX_SUMMARY="$(normalize_path "$SOURCE_MATRIX_SUMMARY")"
SOURCE_MATRIX_CASES="$(normalize_path "$SOURCE_MATRIX_CASES")"

test -s "$SOURCE_MATRIX_SUMMARY" || fail "missing scheduler workload matrix summary $SOURCE_MATRIX_SUMMARY"
test -s "$SOURCE_MATRIX_CASES" || fail "missing scheduler workload matrix cases $SOURCE_MATRIX_CASES"

matrix_status="$(require_field workload_matrix status pass "$SOURCE_MATRIX_SUMMARY")"
matrix_scheduler_change_allowed="$(require_field workload_matrix scheduler_change_allowed 0 "$SOURCE_MATRIX_SUMMARY")"
matrix_default_runtime_change_allowed="$(require_field workload_matrix default_runtime_change_allowed 0 "$SOURCE_MATRIX_SUMMARY")"
matrix_requires_profiler="$(require_field workload_matrix requires_external_profiler_before_default 1 "$SOURCE_MATRIX_SUMMARY")"
matrix_requires_validation="$(require_field workload_matrix requires_mac_windows_validation 1 "$SOURCE_MATRIX_SUMMARY")"

expected_cases=0
for mode in $MODES; do
  mode_active_expected "$mode" >/dev/null
  expected_cases=$((expected_cases + 1))
done

awk \
  -v motion="$MOTION" \
  -v modes="$MODES" \
  -v expected_cases="$expected_cases" \
  -v require_runtime_signal="$REQUIRE_RUNTIME_SIGNAL" \
  -v matrix_status="$matrix_status" \
  -v matrix_scheduler_change_allowed="$matrix_scheduler_change_allowed" \
  -v matrix_default_runtime_change_allowed="$matrix_default_runtime_change_allowed" \
  -v matrix_requires_profiler="$matrix_requires_profiler" \
  -v matrix_requires_validation="$matrix_requires_validation" \
  -v matrix_summary="$(relative_path "$SOURCE_MATRIX_SUMMARY")" \
  -v matrix_cases="$(relative_path "$SOURCE_MATRIX_CASES")" '
  function reset_fields(  i) {
    for (i in f) {
      delete f[i]
    }
  }
  function parse_fields(  i, pair, pos, key, value) {
    reset_fields()
    for (i = 2; i <= NF; i++) {
      pair = $i
      pos = index(pair, "=")
      if (pos > 0) {
        key = substr(pair, 1, pos - 1)
        value = substr(pair, pos + 1)
        gsub(/^"/, "", value)
        gsub(/"$/, "", value)
        f[key] = value
      }
    }
  }
  function mode_expected_active(mode) {
    return mode == "directional_tie" ? 1 : 0
  }
  function numeric(value) {
    return value ~ /^-?[0-9]+([.][0-9]+)?$/
  }
  function max_update(value, name) {
    if (numeric(value)) {
      if (!(name in max_seen) || value + 0 > max_value[name]) {
        max_value[name] = value + 0
        max_seen[name] = 1
      }
    }
  }
  function max_int(name) {
    return (name in max_seen) ? sprintf("%d", max_value[name]) : "0"
  }
  function max_ms(name) {
    return (name in max_seen) ? sprintf("%.3f", max_value[name]) : "0.000"
  }
  function fail_case(reason) {
    failed_cases++
    if (first_failure == "") {
      first_failure = reason
    }
  }
  BEGIN {
    split(modes, mode_list, " ")
    for (i in mode_list) {
      if (mode_list[i] != "") {
        expected_mode[mode_list[i]] = 1
      }
    }
  }
  $1 == "streaming_scheduler_matrix_case" {
    parse_fields()
    if (f["motion"] != motion) {
      next
    }
    mode = f["mode"]
    if (!(mode in expected_mode)) {
      next
    }
    seen[mode]++
    completed_cases++
    expected_active = mode_expected_active(mode)
    if (seen[mode] > 1) {
      fail_case("duplicate_mode_" mode)
    }
    if (f["status"] != "pass") {
      fail_case("case_status_" mode)
    } else {
      pass_cases++
    }
    if (f["scheduler_mode"] != mode) {
      fail_case("scheduler_mode_" mode)
    }
    if (f["scheduler_active"] + 0 != expected_active || f["expected_scheduler_active"] + 0 != expected_active) {
      fail_case("scheduler_active_" mode)
    }
    if (f["expected_chunk"] == "" || f["current_chunk"] != f["expected_chunk"]) {
      fail_case("current_chunk_" mode)
    }
    if (f["current_chunk_loaded"] + 0 != 1 || f["current_render_ready"] + 0 != 1 || f["current_collision_ready"] + 0 != 1) {
      fail_case("readiness_" mode)
    }
    if (f["ground_misses"] + 0 != 0 || f["gpu_upload_fail"] + 0 != 0 || f["gpu_upload_fail_injected"] + 0 != 0) {
      fail_case("failure_counter_" mode)
    }
    if (f["chunk_unload_total"] + 0 != 0 || f["chunk_unload_neighbor_refreshes"] + 0 != 0) {
      fail_case("unload_churn_" mode)
    }
    if (f["lane_exit_code"] + 0 != 0) {
      fail_case("lane_exit_code_" mode)
    }
    signal = f["preview_mismatch"] + f["mesh_directional_ties"] + f["collision_directional_ties"]
    runtime_signal += signal
    max_update(f["preview_mismatch"], "preview_mismatch")
    max_update(f["mesh_directional_ties"], "mesh_directional_ties")
    max_update(f["collision_directional_ties"], "collision_directional_ties")
    max_update(f["fifo_fallbacks"], "fifo_fallbacks")
    max_update(f["popin_missing_chunks"], "popin_missing_chunks")
    max_update(f["popin_collision_missing_chunks"], "popin_collision_missing_chunks")
    max_update(f["terrain_queue_max_ms"], "terrain_queue_max_ms")
    max_update(f["process_wall_p95_ms"], "process_wall_p95_ms")
    max_update(f["gpu_compositor_submit_max_ms"], "gpu_compositor_submit_ms")
    max_update(f["packet_queue_lag_max_ms"], "packet_queue_lag_ms")
  }
  END {
    for (mode in expected_mode) {
      if (!(mode in seen)) {
        fail_case("missing_mode_" mode)
      }
    }
    if (completed_cases != expected_cases) {
      fail_case("case_count")
    }
    if (require_runtime_signal + 0 == 1 && runtime_signal + 0 <= 0) {
      fail_case("missing_runtime_signal")
    }
    status = failed_cases == 0 ? "pass" : "fail"
    reason = failed_cases == 0 ? "ok" : first_failure
    candidate_status = "stable_tie_probe_external_profiler_required"
    printf("gpu_streaming_scheduler_tie_probe status=%s reason=%s motion=%s modes=\"%s\" expected_cases=%d completed_cases=%d pass_cases=%d failed_cases=%d runtime_signal=%d matrix_status=%s max_stream_scheduler_preview_mismatch=%s max_mesh_scheduler_directional_ties=%s max_collision_scheduler_directional_ties=%s max_stream_scheduler_fifo_fallbacks=%s max_popin_missing_chunks=%s max_popin_collision_missing_chunks=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_packet_queue_lag_ms=%s scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=%s external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 matrix_scheduler_change_allowed=%s matrix_default_runtime_change_allowed=%s matrix_requires_external_profiler_before_default=%s matrix_requires_mac_windows_validation=%s matrix_summary=%s matrix_cases=%s\n", status, reason, motion, modes, expected_cases, completed_cases, pass_cases, failed_cases, runtime_signal, matrix_status, max_int("preview_mismatch"), max_int("mesh_directional_ties"), max_int("collision_directional_ties"), max_int("fifo_fallbacks"), max_int("popin_missing_chunks"), max_int("popin_collision_missing_chunks"), max_ms("terrain_queue_max_ms"), max_ms("process_wall_p95_ms"), max_ms("gpu_compositor_submit_ms"), max_ms("packet_queue_lag_ms"), candidate_status, matrix_scheduler_change_allowed, matrix_default_runtime_change_allowed, matrix_requires_profiler, matrix_requires_validation, matrix_summary, matrix_cases)
    if (status != "pass") {
      exit 1
    }
  }
' "$SOURCE_MATRIX_CASES" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "streaming scheduler tie probe failed"
}

cat "$SUMMARY_PATH"
