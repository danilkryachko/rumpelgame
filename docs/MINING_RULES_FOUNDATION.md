# Mining Rules Foundation

This document records the first server-owned mining rule checkpoint for the gameplay track.

## Technical Brief

Goal:

Add a server-authoritative mining interval for counted/survival sessions without changing protocol shape, storage formats, world generation, chunk serialization, or default creative placement behavior.

Scope:

- Keep `BlockAction_DESTROY` on the existing packet shape.
- Add a server mining cooldown configuration boundary.
- Keep creative sessions at zero mining cooldown by default.
- Give counted/survival sessions target-block mining durations.
- Reject destroy actions that arrive before the session cooldown has elapsed.
- Record cooldown only after a successful destroy of a placeable previous block.
- Guard cooldown parsing and runtime behavior with Go network tests.
- Add a reproducible gate for this contract.

Out of scope:

- No new packets, item entities, client mining animation, tool tiers, tool durability, block-specific mining durations, storage migration, chunk serialization changes, world generation changes, Godot scene/resource/import changes, or renderer changes.

## Current Contract

- `RUMPELMC_SERVER_MINING_COOLDOWN_MS` configures server mining cooldown in milliseconds.
- Empty `RUMPELMC_SERVER_MINING_COOLDOWN_MS` keeps creative mode at `0ms`.
- Empty `RUMPELMC_SERVER_MINING_COOLDOWN_MS` gives counted/survival mode target-block durations from server block registry metadata.
- Explicit `RUMPELMC_SERVER_MINING_COOLDOWN_MS=0` disables the cooldown for all placeable blocks in operator-controlled checks.
- Explicit valid `RUMPELMC_SERVER_MINING_COOLDOWN_MS=<n>` applies the same override duration to all placeable blocks.
- Invalid or negative cooldown values fall back to the mode's target-block defaults.
- Cooldown is checked after block-action reach validation and before world mutation.
- The server reads the current target block with `World.BlockAtGlobal` before the destroy mutation, then chooses the mining duration from that block ID.
- The source duration for known placeable blocks is `world.BlockDefinition.MiningDurationMS`; network code applies it as milliseconds.
- Cooldown rejection emits no chunk update, no inventory mutation, no player inventory save, and no inventory snapshot.
- Cooldown is recorded only after `World.ReplaceBlockGlobal` succeeds and the previous block was placeable.
- Destroying Air keeps the existing no-drop behavior and does not start the mining cooldown.
- `BlockAction_PLACE` is not governed by this mining cooldown.

## Compatibility Rules

- Keep `Packet.block_action = 3` and the current `BlockAction` fields.
- Do not add mining packet fields without a separate protocol compatibility task.
- Do not change RocksDB chunk keys, chunk payload bytes, player inventory records, chunk serialization, or world generation.
- Keep default creative sessions behavior-compatible with zero server mining cooldown.
- Keep counted/survival cooldown server-authoritative; client-side timing may become UI feedback later but cannot be the authority.

## Gate

Use:

```sh
sh scripts/mining_rules_foundation_gate.sh logs/mining_rules_foundation_current
```

The expected current result is `status=pass`, `mining_rules_status=cooldown_guarded`, `creative_default=unchanged`, `counted_mining_cooldown=server_guarded`, `active_protocol_change=0`, and `go_tests=pass`.
The summary also reports `mining_block_durations=target_block_guarded`.

The gate checks that:

- This document records current contract and compatibility rules.
- Server source contains the mining cooldown env, counted target-block metadata consumption, parser, session cooldown state, read-only target block lookup, and destroy cooldown methods.
- Network tests cover mode defaults, env override, invalid env fallback, target-block duration selection, cooldown rejection, and cooldown expiry.
- World tests cover `World.BlockAtGlobal` read behavior without save-side effects.
- Protocol docs still keep mining on the existing `BlockAction` packet shape.
- Protocol schema/generated files are unchanged.
- Focused Go world and network tests pass.

## Current Status

This checkpoint is complete when the gate reports `mining_rules_status=cooldown_guarded` and `mining_block_durations=target_block_guarded`. It is the first server-owned mining-time rule: counted/survival sessions cannot instantly mine multiple placeable blocks, target block IDs choose the required interval, and default creative sessions remain unrestricted. Tool tiers, tool durability, item entities, pickup behavior, and client mining feedback remain separate gameplay checkpoints.
