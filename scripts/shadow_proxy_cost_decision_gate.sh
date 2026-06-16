#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/shadow_proxy_cost_decision"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/shadow-proxy-cost-decision-summary.txt"
SHADOW_QUALITY_SUMMARY="${RUMPELMC_SHADOW_PROXY_COST_QUALITY_SUMMARY:-"$ROOT_DIR/logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt"}"
RADIUS_MATRIX_SUMMARY="${RUMPELMC_SHADOW_PROXY_COST_RADIUS_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-matrix-summary.txt"}"
PROFILER_CAPTURE_PACK="${RUMPELMC_SHADOW_PROXY_COST_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt"}"
PROFILER_RESULTS_SUMMARY="${RUMPELMC_SHADOW_PROXY_COST_RESULTS_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-summary.txt"}"
MIN_RADIUS_ROWS="${RUMPELMC_SHADOW_PROXY_COST_MIN_RADIUS_ROWS:-4}"
MIN_USABLE_RADIUS_ROWS="${RUMPELMC_SHADOW_PROXY_COST_MIN_USABLE_RADIUS_ROWS:-3}"
MIN_EXTERNAL_IMPROVEMENT_PCT="${RUMPELMC_SHADOW_PROXY_COST_MIN_EXTERNAL_IMPROVEMENT_PCT:-5.0}"
REQUIRE_FULL_RESULTS="${RUMPELMC_SHADOW_PROXY_COST_REQUIRE_FULL_RESULTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "shadow_proxy_cost_decision_gate: $*" >&2
  exit 1
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

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

test -s "$SHADOW_QUALITY_SUMMARY" || fail "missing shadow quality summary $SHADOW_QUALITY_SUMMARY"
test -s "$RADIUS_MATRIX_SUMMARY" || fail "missing shadow radius matrix summary $RADIUS_MATRIX_SUMMARY"
test -s "$PROFILER_CAPTURE_PACK" || fail "missing profiler capture pack $PROFILER_CAPTURE_PACK"

quality_status="$(field_metric status "$SHADOW_QUALITY_SUMMARY")"
quality_reason="$(field_metric reason "$SHADOW_QUALITY_SUMMARY")"
active_native_comparison="$(field_metric active_native_comparison "$SHADOW_QUALITY_SUMMARY")"
quality_profiler_status="$(field_metric profiler_status "$SHADOW_QUALITY_SUMMARY")"
quality_profiler_rows="$(field_metric profiler_rows "$SHADOW_QUALITY_SUMMARY")"
native_fallback_delta="$(field_metric native_fallback_avg_luma_delta "$SHADOW_QUALITY_SUMMARY")"
lighting_shadow_delta="$(field_metric lighting_shadow_avg_luma_delta "$SHADOW_QUALITY_SUMMARY")"

radius_stats="$(
  awk '
    $1 ~ /^radius=/ {
      rows++
      row_status = "missing"
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "status") row_status = kv[2]
        if (kv[1] == "shadow_normal_total_savings_evidence" && kv[2] == "usable") usable_rows++
        if (kv[1] == "shadow_normal_total_savings_evidence" && kv[2] == "rejected") rejected_rows++
        if (kv[1] == "full_cpu_proxy" && kv[2] + 0 > max_full_cpu_proxy) max_full_cpu_proxy = kv[2] + 0
        if (kv[1] == "compact_cpu_proxy" && kv[2] + 0 > max_compact_cpu_proxy) max_compact_cpu_proxy = kv[2] + 0
        if (kv[1] == "compact_shadow_proxy" && kv[2] + 0 > max_compact_shadow_proxy) max_compact_shadow_proxy = kv[2] + 0
        if (kv[1] == "compact_shadow_normals_saved" && kv[2] + 0 > max_compact_shadow_normals_saved) max_compact_shadow_normals_saved = kv[2] + 0
        if (kv[1] == "full_mesh_max_ms" && kv[2] + 0 > max_full_mesh_ms) max_full_mesh_ms = kv[2] + 0
        if (kv[1] == "compact_mesh_max_ms" && kv[2] + 0 > max_compact_mesh_ms) max_compact_mesh_ms = kv[2] + 0
      }
      if (row_status == "pass") pass_rows++
    }
    END {
      printf("rows=%d pass_rows=%d usable_rows=%d rejected_rows=%d max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d max_full_mesh_ms=%.3f max_compact_mesh_ms=%.3f\n", rows, pass_rows, usable_rows, rejected_rows, max_full_cpu_proxy, max_compact_cpu_proxy, max_compact_shadow_proxy, max_compact_shadow_normals_saved, max_full_mesh_ms, max_compact_mesh_ms)
    }
  ' "$RADIUS_MATRIX_SUMMARY"
)"

capture_pack_status="$(field_metric capture_pack_status "$PROFILER_CAPTURE_PACK")"
capture_pack_rows="$(field_metric rows "$PROFILER_CAPTURE_PACK")"
results_file_status="$(field_metric results_file_status "$PROFILER_CAPTURE_PACK")"

results_summary_status="missing"
results_external_profile_status="pending_external_profiler"
planned_rows="0"
captured_rows="0"
missing_rows="$capture_pack_rows"
profile_eval="scene_shadow_pass_ms=0.000 best_shadow_pass_ms=0.000 best_radius=none best_improvement_pct=0.000 shadow_cost_decision=defer_runtime_change shadow_proxy_reduction_prototype_allowed=0"

if [ -s "$PROFILER_RESULTS_SUMMARY" ]; then
  results_summary_status="present"
  results_external_profile_status="$(field_metric external_profile_status "$PROFILER_RESULTS_SUMMARY")"
  planned_rows="$(field_metric planned_rows "$PROFILER_RESULTS_SUMMARY")"
  captured_rows="$(field_metric captured_rows "$PROFILER_RESULTS_SUMMARY")"
  missing_rows="$(field_metric missing_rows "$PROFILER_RESULTS_SUMMARY")"
  profile_eval="$(
    awk -v min_improvement_pct="$MIN_EXTERNAL_IMPROVEMENT_PCT" '
      function row_token(key,   i, prefix, value) {
        prefix = key "="
        for (i = 1; i <= NF; i++) {
          if (index($i, prefix) == 1) {
            value = substr($i, length(prefix) + 1)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            return value
          }
        }
        return ""
      }
      /^priority=/ {
        radius = row_token("radius")
        normal_decision = row_token("normal_total_decision")
        pass_ms = row_token("gpu_shadow_pass_ms") + 0.0
        if ((radius == "scene" || row_token("priority") == "1") && scene_ms <= 0.0) {
          scene_ms = pass_ms
        } else if (radius != "scene" && normal_decision != "do_not_cite" && pass_ms > 0.0) {
          if (best_ms <= 0.0 || pass_ms < best_ms) {
            best_ms = pass_ms
            best_radius = radius
          }
        }
      }
      END {
        if (best_radius == "") best_radius = "none"
        improvement_pct = 0.0
        decision = "keep_current_shadow_proxy_until_better_external_candidate"
        prototype_allowed = 0
        if (scene_ms <= 0.0) {
          decision = "external_results_missing_scene_row"
        } else if (best_ms <= 0.0) {
          decision = "external_results_missing_usable_reduction_candidate"
        } else {
          improvement_pct = ((scene_ms - best_ms) / scene_ms) * 100.0
          if (improvement_pct + 0.0 >= min_improvement_pct + 0.0) {
            decision = "advance_shadow_proxy_reduction_prototype"
            prototype_allowed = 1
          }
        }
        printf("scene_shadow_pass_ms=%.3f best_shadow_pass_ms=%.3f best_radius=%s best_improvement_pct=%.3f shadow_cost_decision=%s shadow_proxy_reduction_prototype_allowed=%d\n", scene_ms, best_ms, best_radius, improvement_pct, decision, prototype_allowed)
      }
    ' "$PROFILER_RESULTS_SUMMARY"
  )"
fi

awk \
  -v quality_status="${quality_status:-missing}" \
  -v quality_reason="${quality_reason:-missing}" \
  -v active_native_comparison="${active_native_comparison:-missing}" \
  -v quality_profiler_status="${quality_profiler_status:-missing}" \
  -v quality_profiler_rows="${quality_profiler_rows:-0}" \
  -v native_fallback_delta="${native_fallback_delta:-999}" \
  -v lighting_shadow_delta="${lighting_shadow_delta:-999}" \
  -v radius_stats="$radius_stats" \
  -v min_radius_rows="$MIN_RADIUS_ROWS" \
  -v min_usable_radius_rows="$MIN_USABLE_RADIUS_ROWS" \
  -v capture_pack_status="${capture_pack_status:-missing}" \
  -v capture_pack_rows="${capture_pack_rows:-0}" \
  -v results_file_status="${results_file_status:-missing}" \
  -v results_summary_status="$results_summary_status" \
  -v results_external_profile_status="${results_external_profile_status:-missing}" \
  -v planned_rows="${planned_rows:-0}" \
  -v captured_rows="${captured_rows:-0}" \
  -v missing_rows="${missing_rows:-0}" \
  -v require_full_results="$REQUIRE_FULL_RESULTS" \
  -v profile_eval="$profile_eval" \
  -v quality_summary="$(relative_path "$SHADOW_QUALITY_SUMMARY")" \
  -v radius_matrix_summary="$(relative_path "$RADIUS_MATRIX_SUMMARY")" \
  -v profiler_capture_pack="$(relative_path "$PROFILER_CAPTURE_PACK")" \
  -v profiler_results_summary="$(relative_path "$PROFILER_RESULTS_SUMMARY")" '
  function stat_value(line, key,   parts, i, kv) {
    split(line, parts, " ")
    for (i in parts) {
      split(parts[i], kv, "=")
      if (kv[1] == key) return kv[2]
    }
    return 0
  }
  BEGIN {
    radius_rows = stat_value(radius_stats, "rows") + 0
    radius_pass_rows = stat_value(radius_stats, "pass_rows") + 0
    radius_usable_rows = stat_value(radius_stats, "usable_rows") + 0
    radius_rejected_rows = stat_value(radius_stats, "rejected_rows") + 0
    max_full_cpu_proxy = stat_value(radius_stats, "max_full_cpu_proxy") + 0
    max_compact_cpu_proxy = stat_value(radius_stats, "max_compact_cpu_proxy") + 0
    max_compact_shadow_proxy = stat_value(radius_stats, "max_compact_shadow_proxy") + 0
    max_compact_shadow_normals_saved = stat_value(radius_stats, "max_compact_shadow_normals_saved") + 0
    max_full_mesh_ms = stat_value(radius_stats, "max_full_mesh_ms") + 0.0
    max_compact_mesh_ms = stat_value(radius_stats, "max_compact_mesh_ms") + 0.0
    scene_shadow_pass_ms = stat_value(profile_eval, "scene_shadow_pass_ms") + 0.0
    best_shadow_pass_ms = stat_value(profile_eval, "best_shadow_pass_ms") + 0.0
    best_radius = stat_value(profile_eval, "best_radius")
    best_improvement_pct = stat_value(profile_eval, "best_improvement_pct") + 0.0
    decision = stat_value(profile_eval, "shadow_cost_decision")
    prototype_allowed = stat_value(profile_eval, "shadow_proxy_reduction_prototype_allowed") + 0

    status = "pass"
    reason = "external_profiler_pending"
    default_runtime_change_allowed = 0
    native_shadow_prototype_allowed = 0
    external_profile_status = "pending_external_profiler"

    if (quality_status != "pass") {
      status = "fail"
      reason = "shadow_quality_not_clean"
    } else if (active_native_comparison != "deferred") {
      status = "fail"
      reason = "active_native_shadow_state_changed"
    } else if (radius_rows < min_radius_rows || radius_pass_rows != radius_rows || radius_usable_rows < min_usable_radius_rows) {
      status = "fail"
      reason = "shadow_radius_matrix_not_clean"
    } else if (max_full_cpu_proxy <= 0 || max_compact_cpu_proxy <= 0 || max_compact_shadow_proxy <= 0 || max_compact_shadow_normals_saved <= 0) {
      status = "fail"
      reason = "shadow_proxy_cost_counters_missing"
    } else if (!(capture_pack_status == "pending_external_profiler" && capture_pack_rows + 0 >= radius_rows)) {
      status = "fail"
      reason = "profiler_capture_pack_not_pending"
    } else if (results_summary_status == "present") {
      external_profile_status = results_external_profile_status
      reason = "validated_external_results"
      if (results_external_profile_status != "captured" || captured_rows + 0 <= 0 || planned_rows + 0 <= 0) {
        status = "fail"
        reason = "profiler_results_not_captured"
      } else if (require_full_results == "1" && missing_rows + 0 != 0) {
        status = "fail"
        reason = "profiler_results_missing_planned_rows"
      } else if (decision == "external_results_missing_scene_row" || decision == "external_results_missing_usable_reduction_candidate") {
        status = "fail"
        reason = decision
      }
    }

    if (results_summary_status != "present") {
      decision = "defer_runtime_change"
      prototype_allowed = 0
    }

    printf("shadow_proxy_cost_decision status=%s reason=%s decision=%s default_runtime_change_allowed=%d shadow_proxy_reduction_prototype_allowed=%d native_shadow_prototype_allowed=%d external_profile_status=%s quality_status=%s quality_reason=%s active_native_comparison=%s quality_profiler_status=%s quality_profiler_rows=%d native_fallback_avg_luma_delta=%.4f lighting_shadow_avg_luma_delta=%.4f radius_rows=%d radius_pass_rows=%d radius_usable_rows=%d radius_rejected_rows=%d max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d max_full_mesh_ms=%.3f max_compact_mesh_ms=%.3f capture_pack_status=%s capture_pack_rows=%d results_file_status=%s results_summary_status=%s planned_rows=%d captured_rows=%d missing_rows=%d scene_shadow_pass_ms=%.3f best_shadow_pass_ms=%.3f best_radius=%s best_improvement_pct=%.3f quality_summary=%s radius_matrix_summary=%s profiler_capture_pack=%s profiler_results_summary=%s\n", status, reason, decision, default_runtime_change_allowed, prototype_allowed, native_shadow_prototype_allowed, external_profile_status, quality_status, quality_reason, active_native_comparison, quality_profiler_status, quality_profiler_rows, native_fallback_delta, lighting_shadow_delta, radius_rows, radius_pass_rows, radius_usable_rows, radius_rejected_rows, max_full_cpu_proxy, max_compact_cpu_proxy, max_compact_shadow_proxy, max_compact_shadow_normals_saved, max_full_mesh_ms, max_compact_mesh_ms, capture_pack_status, capture_pack_rows, results_file_status, results_summary_status, planned_rows, captured_rows, missing_rows, scene_shadow_pass_ms, best_shadow_pass_ms, best_radius, best_improvement_pct, quality_summary, radius_matrix_summary, profiler_capture_pack, profiler_results_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "shadow proxy cost decision gate failed"
}

cat "$SUMMARY_PATH"
echo "Shadow proxy cost decision artifacts: $OUT_DIR"
