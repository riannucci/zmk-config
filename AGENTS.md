# AGENTS.md — zmk-corne

Operating manual for AI agents working in this repo. **Complements, not duplicates,
`README.md`** — README owns build/flash/file-layout/dts-lsp mechanics; this file owns
the rules, the version-pin policy, and the hard-won landmines.

A global `~/.config/opencode/AGENTS.md` also applies (subagent dispatch, LSP-first
navigation, surgical commits, rebase-over-merge). This file adds project specifics and
takes precedence where they overlap.

## Non-negotiable rules

- **GPG-signed commits are mandatory.** Every commit must show `G` in
  `git log --format="%h %G? %s"`. An unsigned commit is a defect.
- **`main` is protected — change it only via PR.** Branch protection enforces required
  status checks (currently 7). Never push directly to `main`.
- **Surgical commits.** One task = one commit; commit immediately after verification.
  Format: `<type>(<phase>-<task>): <desc>` for plan work, else `<type>: <desc>`.
- **Rebase, never merge** — keep linear history.
- **No home row mods.** Mod-taps on edge columns and thumbs are fine; HRM on the home
  row is not.
- **`.plans/` is gitignored** — durable design/plan docs live there; do not commit them.
- **No nix files** in the repo.

## Pinned versions — do not bump casually (supply-chain hardening)

- **ZMK v0.3.0 / Zephyr 3.5** — SHA-pinned in `config/west.yml` (ZMK `edf5c08`).
- **YADS `zmk-dongle-screen`** — SHA-pinned in `config/west.yml`.
- **`adafruit-nrfutil==0.5.3.post16`** — must match in both `Dockerfile` and
  `requirements.txt`.
- **Apt versions are pinned in `Dockerfile` intentionally** — satisfies Hadolint DL3008.
  Archive drift is an accepted tradeoff; **do not "fix" lint by unpinning.**
- After any `west.yml`/version change, re-run `./scripts/extract-zephyr-bindings.sh`
  to refresh the dts-lsp trees.

## Build / flash / verify (TL;DR — full detail in README)

- Build: `docker compose run --rm make [dongle|left|right|reset|all]` →
  `firmware/NN-*.{uf2,hex,zip}` (numbered by flash order).
- **Only the dongle (`01-dongle`) runs the keymap.** Keymap/behavior changes →
  reflash the dongle only. Debounce/KSCAN (`corne.conf`) → reflash **both halves**.
  See README's "Which board to reflash" table.
- CI: `check.yml` gates PRs (lint + validate-keymap + compile all 5 targets);
  `build.yml` builds + uploads artifacts on push to `main`.
- **Verify before claiming done:** `docker compose run --rm make <target>` green is the
  floor. Changes that affect **runtime listener ordering** are not proven by a green
  build alone — confirm on-device (see landmine #1).
- Flashing path depends on the machine: a work Mac with DLP blocks USB Mass Storage
  (UF2 drag-drop) but CDC serial DFU still enumerates → use the `.zip` via the browser
  flasher or `./scripts/flash.sh`. Personal machine → UF2 drag-drop works.

## Landmines — read before touching

1. **Custom-behavior listener ordering.** A module behavior's CMakeLists **must** use
   `target_sources(app PRIVATE ...)`, **not** `zephyr_library()`. ZMK fills the
   `__event_subscriptions` linker section in **link order**; a standalone library links
   *after* `app`, so its listener runs *after* `hid_listener` — i.e. after the HID
   report is already sent — and silently does nothing (e.g. caps-word fails to
   capitalize). Verify with `nm`: the behavior's `keycode_state_changed` subscription
   must sort **before** `hid_listener`. Full rationale lives in the comment at
   `config/modules/ecaps-word/CMakeLists.txt`.

2. **Debounce floor.** `config/corne.conf` keeps debounce at ZMK defaults (5 ms / 5 ms).
   A previous 1 ms press override let switch bounce through as repeated keys (a single
   press registering twice, e.g. `D`). **Do not re-add an aggressive press override.**
   Chatter at the default means hardware — reseat/replace the hot-swap socket or switch.

3. **Dongle 5-column layout.** Do **not** remove `foostan_corne_5col_layout` / the
   index-alignment placeholder in
   `config/boards/shields/corne_dongle/corne_dongle.overlay`. Removing it re-introduces
   the key scramble. This is a hardware-verified fix.

4. **CMake module hook.** Use `ZMK_EXTRA_MODULES`, **not** `ZEPHYR_EXTRA_MODULES`, for
   v0.3.0. ZMK composes `ZEPHYR_EXTRA_MODULES="${ZMK_EXTRA_MODULES};...;keymap-module"`;
   overriding `ZEPHYR_EXTRA_MODULES` directly drops shield/board discovery. `entrypoint.sh`
   passes `-DZMK_EXTRA_MODULES=$CONFIG/modules/ecaps-word` to all 5 targets, and the CI
   workflows inject the same — keep them in sync.

5. **Display-thread stack vs. roller animation.** The dongle screen runs on a **dedicated
   display thread** (`ZMK_DISPLAY_WORK_QUEUE_DEDICATED`, forced in the fork's
   `boards/shields/dongle_screen/Kconfig.defconfig`). Its stack size is
   `CONFIG_ZMK_DISPLAY_DEDICATED_THREAD_STACK_SIZE` — **ZMK core default 3072**, the fork
   raises it to **4096**; `config/corne_dongle.conf` does not override it. This is a
   **memory** knob, not a timing knob: it does **not** set animation speed/fps. But the
   **layer-roller scroll is the peak stack consumer** — every frame during the scroll runs
   the roller's `mask_event_cb` (LVGL draw masks, `LV_USE_DRAW_MASK`) **plus 40 px Samsung
   Sans anti-aliased glyph rasterization** on that thread's stack. Drop below 4096 and you
   get a stack overflow / freeze that surfaces **precisely during the layer roll**. Do not
   lower it. Tuning levers: roller feel = `anim_time` in the fork's
   `src/widgets/layer_roller.c` (**fork-only** — needs a fork commit + `config/west.yml`
   repoint, then reflash dongle); smoothness/fps = `CONFIG_LV_DISP_DEF_REFR_PERIOD`
   (**locally overridable** in `config/corne_dongle.conf`, but it adds draw cycles on the
   stack-hungry thread and costs RAM — already ~75%).

## Custom Zephyr module conventions (`config/modules/<name>/`)

- **Place modules under `config/`** (not repo root): `config/` is already bind-mounted
  into Docker as `/zmk-config` and listed in the CI `paths:` filters, so no
  docker-compose/path-filter changes are needed.
- **`module.yml`:** `settings: { dts_root: . }` must be nested **under `build:`**
  (Zephyr 3.5 requirement), not top-level.
- **Kconfig:** gate peripheral builds with
  `depends on !ZMK_SPLIT || ZMK_SPLIT_ROLE_CENTRAL` and
  `depends on DT_HAS_<COMPAT>_ENABLED`.
- **Source gating:** wrap in `if(CONFIG_...)` in CMakeLists **and**
  `#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)` in the `.c`.

### `ecaps_word` specifics

- A v0.3.0 backport of upstream **ZMK PR #1742** (`caps_word` + shift-list semantics):
  while active, `-` (MINUS) emits `_` (UNDERSCORE) for `UPPER_SNAKE_CASE`; digits are
  unaffected; Space ends the word.
- `continue-list` is `required: true` in the v0.3.0 caps-word YAML — it must be explicit
  in the keymap binding.
- **Migration path:** when PR #1742 lands upstream, delete this module and switch the
  keymap to `&prog_word`.

## Keymap notes

- Ported from a ZSA Voyager layout; 7 layers in `config/corne.keymap`.
- Corne 42-key positions: `0–35` (3×12 grid) + `36–41` (thumbs).
- Per-thumb tapping terms via `mt_thumb` / `lt_thumb` (no HRM).
- `&ecaps_word` is bound at base-layer position 35 (bottom-right).
