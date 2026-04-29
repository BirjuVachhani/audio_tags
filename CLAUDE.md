Goal: docs/MUST_READ.md

# Workspace structure

This is a Dart pub workspace (monorepo). All packages live under `packages/`.

- `packages/audio_tags_interface` — Core models, backend interface, errors. No runtime deps.
- `packages/audio_tags_taglib` — TagLib backend (FFI + C shim + prebuilt binaries). Depends on interface.
- `packages/audio_tags_lofty` — Lofty backend (FFI + Rust cdylib + prebuilt binaries). Depends on interface.
- `packages/audio_tags` — User-facing package. Re-exports interface + taglib. Has service layer and config.

Dependency flow: `audio_tags_interface ← audio_tags_taglib ← audio_tags`
                  `audio_tags_interface ← audio_tags_lofty` (standalone, opt-in)

Run `dart pub get` from workspace root. Run tests per-package: `cd packages/<pkg> && dart test`.
