#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_multi_client_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_PORT="${RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_PORT:-25566}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SMOKE_DB="$OUT_DIR/rocksdb"
SERVER_LOG="$OUT_DIR/server.log"
CLIENT_LOG="$OUT_DIR/client.log"
RESOURCE_SAMPLES="$OUT_DIR/server-resource-samples.tsv"
SUMMARY_PATH="$OUT_DIR/server-multi-client-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_BUILD_SERVER:-1}"
CLIENTS="${RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_CLIENTS:-2}"
CLIENT_TIMEOUT="${RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_TIMEOUT:-5s}"
SERVER_PID=""
RESOURCE_SAMPLER_PID=""
RESOURCE_SAMPLE_INTERVAL="${RUMPELMC_SERVER_MULTI_CLIENT_RESOURCE_SAMPLE_INTERVAL_SEC:-0.1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_multi_client_smoke: $*" >&2
  exit 1
}

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force "$SERVER_BINARY" >/dev/null 2>&1 || true
  fi
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$SMOKE_PORT" -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_server() {
  tries=0
  while [ "$tries" -lt 30 ]; do
    pid="$(listener_pid || true)"
    if [ -n "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  cat "$SERVER_LOG" >&2 || true
  fail "server did not start listening on port $SMOKE_PORT"
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port $SMOKE_PORT is still listening after cleanup"
}

cleanup_server() {
  if [ -n "$RESOURCE_SAMPLER_PID" ] && kill -0 "$RESOURCE_SAMPLER_PID" 2>/dev/null; then
    kill "$RESOURCE_SAMPLER_PID" 2>/dev/null || true
    wait "$RESOURCE_SAMPLER_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    wait_for_port_clear
  fi
}

sample_server_resource() {
  if [ -z "$SERVER_PID" ] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
    return 0
  fi
  ps -o rss= -o pcpu= -p "$SERVER_PID" 2>/dev/null | awk -v epoch="$(date +%s)" -v pid="$SERVER_PID" '
    NF >= 2 {
      gsub(/,/, ".", $2)
      printf("%s\t%s\t%d\t%.1f\n", epoch, pid, $1 + 0, $2 + 0.0)
    }
  ' >> "$RESOURCE_SAMPLES" || true
}

sample_server_resource_loop() {
  while [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; do
    sample_server_resource
    sleep "$RESOURCE_SAMPLE_INTERVAL"
  done
}

resource_summary_fields() {
  awk '
    NR > 1 {
      samples++
      rss = $3 + 0
      cpu = $4 + 0.0
      rss_sum += rss
      cpu_sum += cpu
      if (rss > max_rss) {
        max_rss = rss
      }
      if (cpu > max_cpu) {
        max_cpu = cpu
      }
    }
    END {
      if (samples == 0) {
        printf("server_resource_samples=0 server_rss_kb_max=0 server_rss_kb_avg=0 server_cpu_pct_max=0.0 server_cpu_pct_avg=0.0")
      } else {
        printf("server_resource_samples=%d server_rss_kb_max=%d server_rss_kb_avg=%.1f server_cpu_pct_max=%.1f server_cpu_pct_avg=%.1f", samples, max_rss, rss_sum / samples, max_cpu, cpu_sum / samples)
      }
    }
  ' "$RESOURCE_SAMPLES"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_PORT"
fi
trap cleanup_server EXIT HUP INT TERM

case "$BUILD_SERVER" in
  0) ;;
  1)
    (
      cd "$SERVER_DIR"
      go build -o ./server ./cmd/server
      sign_server_binary_if_possible
    )
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

rm -f "$SERVER_LOG" "$CLIENT_LOG" "$RESOURCE_SAMPLES" "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"
printf 'epoch_s\tpid\trss_kb\tcpu_pct\n' > "$RESOURCE_SAMPLES"

(
  cd "$SERVER_DIR"
  exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
    RUMPELMC_SERVER_ADDRESS=":$SMOKE_PORT" \
    RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
    RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 \
    RUMPELMC_SERVER_CHUNKS_PER_UPDATE=64 \
    RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS=2000 \
    RUMPELMC_SERVER_MAX_CLIENTS="${RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_MAX_CLIENTS:-0}" \
    "$SERVER_BINARY" > "$SERVER_LOG" 2>&1
) &
SERVER_PID="$!"

wait_for_server
sample_server_resource
sample_server_resource_loop &
RESOURCE_SAMPLER_PID="$!"

set +e
(
  cd "$SERVER_DIR"
  go run ./cmd/multi_client_smoke -addr "$SMOKE_ADDR" -timeout "$CLIENT_TIMEOUT" -clients "$CLIENTS"
) > "$CLIENT_LOG" 2>&1
rc=$?
set -e
if [ -n "$RESOURCE_SAMPLER_PID" ] && kill -0 "$RESOURCE_SAMPLER_PID" 2>/dev/null; then
  kill "$RESOURCE_SAMPLER_PID" 2>/dev/null || true
  wait "$RESOURCE_SAMPLER_PID" 2>/dev/null || true
fi
sample_server_resource

if [ "$rc" -ne 0 ]; then
  cat "$CLIENT_LOG" >&2 || true
  cat "$SERVER_LOG" >&2 || true
  fail "multi-client smoke failed with exit code $rc"
fi

summary="$(grep '^server_multi_client_smoke status=pass ' "$CLIENT_LOG" | tail -n 1 || true)"
if [ -z "$summary" ]; then
  cat "$CLIENT_LOG" >&2 || true
  fail "missing passing smoke summary"
fi

resource_fields="$(resource_summary_fields)"
printf '%s %s resource_samples=%s server_log=%s client_log=%s\n' "$summary" "$resource_fields" "$RESOURCE_SAMPLES" "$SERVER_LOG" "$CLIENT_LOG" > "$SUMMARY_PATH"
cat "$SUMMARY_PATH"
