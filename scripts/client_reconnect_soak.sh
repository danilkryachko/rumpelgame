#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/client_reconnect_soak"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/client-reconnect-soak-summary.txt"
SMOKE_SCRIPT="${RUMPELMC_CLIENT_RECONNECT_SOAK_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/client_reconnect_smoke.sh"}"
SMOKE_DIR="${RUMPELMC_CLIENT_RECONNECT_SOAK_SMOKE_DIR:-"$ROOT_DIR/logs/client_reconnect_soak_smoke_artifacts"}"
SOAK_CYCLES="${RUMPELMC_CLIENT_RECONNECT_SOAK_CYCLES:-3}"
SOAK_DELAY_SEC="${RUMPELMC_CLIENT_RECONNECT_SOAK_DELAY_SEC:-13.0}"
SOAK_GODOT_TIMEOUT_SEC="${RUMPELMC_CLIENT_RECONNECT_SOAK_GODOT_TIMEOUT_SEC:-120}"

mkdir -p "$OUT_DIR"

fail() {
  echo "client_reconnect_soak: $*" >&2
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

require_positive_int() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*)
      fail "$name must be a positive integer, got $value"
      ;;
  esac
  if [ "$value" -lt 1 ]; then
    fail "$name must be >= 1, got $value"
  fi
}

require_positive_int RUMPELMC_CLIENT_RECONNECT_SOAK_CYCLES "$SOAK_CYCLES"
test -s "$SMOKE_SCRIPT" || fail "missing smoke script $SMOKE_SCRIPT"

rm -f "$SUMMARY_PATH"
rm -rf "$OUT_DIR/smoke"
rm -rf "$SMOKE_DIR"

RUMPELMC_CLIENT_RECONNECT_SMOKE_CYCLES="$SOAK_CYCLES" \
  RUMPELMC_CLIENT_RECONNECT_SMOKE_DELAY_SEC="$SOAK_DELAY_SEC" \
  GODOT_TIMEOUT_SEC="$SOAK_GODOT_TIMEOUT_SEC" \
  sh "$SMOKE_SCRIPT" "$SMOKE_DIR" > "$OUT_DIR/client-reconnect-smoke-run.txt" 2>&1 || {
    cat "$OUT_DIR/client-reconnect-smoke-run.txt" >&2 || true
    fail "reconnect smoke cycles failed"
  }

SMOKE_SUMMARY="$SMOKE_DIR/client-reconnect-smoke-summary.txt"
test -s "$SMOKE_SUMMARY" || fail "missing smoke summary $SMOKE_SUMMARY"

smoke_status="$(field_metric status "$SMOKE_SUMMARY")"
client_state="$(field_metric client_state "$SMOKE_SUMMARY")"
reconnect_cycles="$(field_metric reconnect_cycles "$SMOKE_SUMMARY")"
reconnect_events="$(field_metric reconnect_events "$SMOKE_SUMMARY")"
reconnect_attempts="$(field_metric reconnect_attempts "$SMOKE_SUMMARY")"
reconnect_successes="$(field_metric reconnect_successes "$SMOKE_SUMMARY")"
network_reader_errors="$(field_metric network_reader_errors "$SMOKE_SUMMARY")"
current_chunk_loaded="$(field_metric current_chunk_loaded "$SMOKE_SUMMARY")"
active_protocol_change="$(field_metric active_protocol_change "$SMOKE_SUMMARY")"

test "$smoke_status" = "pass" || fail "smoke status=$smoke_status"
test "$client_state" = "active" || fail "client_state=$client_state, expected active"
test "${reconnect_cycles:-0}" -ge "$SOAK_CYCLES" || fail "reconnect_cycles=${reconnect_cycles:-0}, expected >= $SOAK_CYCLES"
test "${reconnect_successes:-0}" -ge "$SOAK_CYCLES" || fail "reconnect_successes=${reconnect_successes:-0}, expected >= $SOAK_CYCLES"
test "${network_reader_errors:-0}" -ge "$SOAK_CYCLES" || fail "network_reader_errors=${network_reader_errors:-0}, expected >= $SOAK_CYCLES"
test "${current_chunk_loaded:-0}" -ge 1 || fail "current_chunk_loaded=${current_chunk_loaded:-0}, expected >= 1"
test "${active_protocol_change:-1}" -eq 0 || fail "active_protocol_change=$active_protocol_change"

{
  printf 'client_reconnect_soak status=pass reconnect_cycles=%s client_state=%s reconnect_events=%s reconnect_attempts=%s reconnect_successes=%s network_reader_errors=%s current_chunk_loaded=%s active_protocol_change=%s smoke_summary=%s\n' \
    "$reconnect_cycles" \
    "$client_state" \
    "$reconnect_events" \
    "$reconnect_attempts" \
    "$reconnect_successes" \
    "$network_reader_errors" \
    "$current_chunk_loaded" \
    "$active_protocol_change" \
    "$SMOKE_SUMMARY"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
