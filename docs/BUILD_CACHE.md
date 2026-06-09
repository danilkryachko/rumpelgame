# Build Cache

This project uses `sccache` as an optional Rust compiler cache.

## Local Usage

`scripts/check.sh` enables `sccache` automatically for Rust checks when the `sccache` binary is available.

```sh
./scripts/check.sh fast
./scripts/check.sh full
```

To disable it for one run:

```sh
RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full
```

## CI Usage

GitHub Actions enables `sccache` for the Rust lint/test job with:

- `mozilla-actions/sccache-action`
- `RUSTC_WRAPPER=sccache`
- `CARGO_INCREMENTAL=0`
- `SCCACHE_GHA_ENABLED=true`

## Notes

- `sccache` mainly helps Rust and C/C++ style compilation. It does not speed up Go tests directly.
- Rust `cdylib` final linking may not be cacheable, but dependencies and intermediate Rust compilation can still benefit.
- If cache behavior looks suspicious, compare one run with `RUMPELMC_USE_SCCACHE=0`.
