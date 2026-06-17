#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/mining_rules_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/mining-rules-foundation-summary.txt"
DESIGN_DOC="${RUMPELMC_MINING_RULES_DOC:-"$ROOT_DIR/docs/MINING_RULES_FOUNDATION.md"}"
NETWORK_SOURCE="${RUMPELMC_MINING_RULES_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
NETWORK_TEST="${RUMPELMC_MINING_RULES_NETWORK_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
WORLD_BLOCKS="${RUMPELMC_MINING_RULES_WORLD_BLOCKS:-"$ROOT_DIR/server/pkg/world/blocks.go"}"
PROTOCOL_DOC="${RUMPELMC_MINING_RULES_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
RUN_GO_TESTS="${RUMPELMC_MINING_RULES_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "mining_rules_foundation_gate: $*" >&2
  exit 1
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in "$DESIGN_DOC" "$NETWORK_SOURCE" "$NETWORK_TEST" "$WORLD_BLOCKS" "$PROTOCOL_DOC"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Mining Rules Foundation' \
  'Current Contract' \
  'Compatibility Rules' \
  'mining_rules_status=cooldown_guarded' \
  'mining_block_durations=target_block_guarded' \
  'RUMPELMC_SERVER_MINING_COOLDOWN_MS'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'const miningCooldownEnv = "RUMPELMC_SERVER_MINING_COOLDOWN_MS"' \
  'const defaultCountedMiningCooldown' \
  'miningCooldown         time.Duration' \
  'miningCooldownOverride bool' \
  'miningDurations        map[world.BlockID]time.Duration' \
  'lastDestroyAt         time.Time' \
  'BlockAtGlobal' \
  'configuredMiningCooldown' \
  'configuredMiningDurations' \
  'defaultMiningCooldownForMode' \
  'defaultMiningDurationsForMode' \
  'definition.MiningDurationMS' \
  'miningDurationForBlock' \
  'miningDurationForBlockWithTool' \
  'destroyCooldownReady' \
  'recordSuccessfulDestroy' \
  'Ignored mining cooldown block action'; do
  require_token "$NETWORK_SOURCE" "$token"
done

for token in \
  'MiningDurationMS' \
  'StoneBlockMiningMS' \
  'SoftBlockMiningMS' \
  'WoodBlockMiningMS'; do
  require_token "$WORLD_BLOCKS" "$token"
done

for token in \
  'TestConfiguredMiningCooldownUsesModeDefault' \
  'TestConfiguredMiningCooldownUsesEnvOverride' \
  'TestConfiguredMiningCooldownIgnoresInvalidEnv' \
  'TestConfiguredMiningDurationsUseModeDefaults' \
  'TestConfiguredMiningDurationsUseEnvOverride' \
  'TestHandleClientPacketDestroyRejectsMiningCooldown' \
  'TestHandleClientPacketDestroyAllowsAfterMiningCooldown' \
  'TestHandleClientPacketDestroyUsesTargetBlockMiningDuration'; do
  require_token "$NETWORK_TEST" "$token"
done

require_token "$PROTOCOL_DOC" '`Packet.block_action = 3`'
require_token "$PROTOCOL_DOC" 'New `BlockAction` fields must use field numbers greater than `5`.'

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

go_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./pkg/network > "$OUT_DIR/go-test-mining-rules.txt" 2>&1); then
    go_tests="pass"
  else
    cat "$OUT_DIR/go-test-mining-rules.txt" >&2 || true
    go_tests="fail"
  fi
fi

awk \
  -v protocol_diff_count="$protocol_diff_count" \
  -v go_tests="$go_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v network_source="$NETWORK_SOURCE" '
  BEGIN {
    status = "pass"
    reason = "ok"
    mining_rules_status = "cooldown_guarded"
    mining_block_durations = "target_block_guarded"
    creative_default = "unchanged"
    counted_mining_cooldown = "server_guarded"
    go_ok = go_tests == "pass" || go_tests == "skipped"

    if (protocol_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_tests_failed"
    }

    printf("mining_rules_foundation status=%s reason=%s mining_rules_status=%s mining_block_durations=%s creative_default=%s counted_mining_cooldown=%s active_protocol_change=%d go_tests=%s design_doc=%s network_source=%s\n", status, reason, mining_rules_status, mining_block_durations, creative_default, counted_mining_cooldown, protocol_diff_count, go_tests, design_doc, network_source)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "mining rules foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Mining rules foundation artifacts: $OUT_DIR"
