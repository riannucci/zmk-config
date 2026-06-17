# zmk-corne

ZMK firmware for a Typeractive Corne 6-column wireless keyboard with a
Prospector dongle (Seeed XIAO BLE) and YADS display.

- ZMK v0.3.0 / Zephyr 3.5
- YADS ([zmk-dongle-screen](https://github.com/janpfischer/zmk-dongle-screen)) on `main`

## Architecture

```
                   ┌────────┐
                   │  Host  │
                   └───┬────┘
                       │
                       │ USB
                       │
 ┌──────┐          ┌───┴────┐          ┌───────┐
 │ Left │ ──BLE──► │ Dongle │ ◄──BLE── │ Right │
 │ nano │          │  XIAO  │          │ nano  │
 └──────┘          └────────┘          └───────┘
```

- **Dongle** — central role, XIAO BLE, connects to host via USB. Runs the
  keymap and YADS display. The only target you rebuild for keymap changes.
- **Left / Right** — peripheral role, nice!nano v2. Forward key presses to
  the dongle over BLE. No keymap, no display.
- **5 firmware targets**: `dongle`, `left`, `right`, `reset_xiao`, `reset_nano`.

## Build

### Local (Docker)

Build the image (first time or after changing `west.yml` / `Dockerfile`):

```sh
docker compose build
```

Build firmware — outputs land in `firmware/`:

```sh
docker compose run --rm make          # all 5 targets
docker compose run --rm make dongle   # just the dongle
docker compose run --rm make left     # just the left half
docker compose run --rm make right    # just the right half
docker compose run --rm make reset    # both settings_reset images
```

Shell access (for debugging west/cmake issues):

```sh
docker compose run --rm --entrypoint bash make
```

### Remote (GitHub Actions)

Two workflows in `.github/workflows/`:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `check.yml` | PR to `main` | Gate: lint (ShellCheck, yamllint) + keymap validation + compile all 5 targets. No artifacts. |
| `build.yml` | Push to `main` / manual | Build all 5 targets in parallel, upload individual + bundled UF2 artifacts. |

To download firmware from a CI build: go to the Actions tab → select the
build run → download the `firmware` artifact (zip with all 5 UF2 files).

### Flashing

`docker compose run --rm make all` writes three files per target into `firmware/`,
prefixed with the recommended flashing order (same names as the GitHub Actions artifacts):

| Basename | Device | `flash.sh` target |
|----------|--------|-------------------|
| `00a-reset_xiao` | Dongle settings reset | `reset_xiao` |
| `00b-reset_nano` | Half settings reset | `reset_nano` |
| `01-dongle` | Dongle (XIAO BLE) | `dongle` |
| `02-left` | Left half (nice!nano) | `left` |
| `03-right` | Right half (nice!nano) | `right` |

Each comes as `.uf2` (drag-and-drop) plus `.hex` and `.zip` (Adafruit serial-DFU package).

#### Standard (personal machine — USB Mass Storage allowed)

1. Enter bootloader:
   - **nice!nano v2** (halves): double-tap the reset button
   - **XIAO BLE** (dongle): double-tap the tiny side button
2. A USB drive appears — drag the matching `NN-*.uf2` file onto it.
3. The board reboots automatically.

#### Work machine (USB Mass Storage blocked)

UF2 drag-drop is blocked, but the Adafruit bootloader's USB **CDC serial** interface still
enumerates (a `/dev/cu.usbmodem*` port appears in bootloader mode), so flash over serial DFU.
The same `NN-*.zip` works for both options.

**Option A — Browser (no install):**

1. Open <https://opendisplay.org/nrf_web_tools/> in Chrome.
2. Select the matching `firmware/NN-*.zip` (e.g. `01-dongle.zip`).
3. Double-tap reset to enter bootloader (ZMK exposes no serial while running, so auto-reset won't fire).
4. Pick the `usbmodem` port and flash.

> `nrf_web_tools` is a third-party, browser-hosted WebSerial tool. It runs client-side and only
> talks to the board over the serial port, but if you'd rather not rely on it, use Option B.

**Option B — CLI (`adafruit-nrfutil` in a local venv):**

`scripts/flash.sh` needs `adafruit-nrfutil` on your PATH. Install it once in a
virtualenv (outside Docker — `requirements.txt` pins the same version the build
image uses):

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

With the venv active, flash:

```sh
./scripts/flash.sh dongle        # left | right | reset_xiao | reset_nano
```

The script resolves the numbered package, auto-detects the serial port
(`/dev/cu.usbmodem*` on macOS, `/dev/ttyACM*` on Linux), and runs `adafruit-nrfutil dfu serial`.
If several serial devices are connected it aborts rather than risk flashing the wrong one — pass
the port explicitly as a second argument (`./scripts/flash.sh dongle /dev/cu.usbmodemXXXX`).

> First-time check: enter bootloader on any board and run `ls /dev/cu.usbmodem*`.
> If a port appears, both options work.

#### Which board to reflash for a given change

| Change | Board(s) | Notes |
|--------|----------|-------|
| Keymap / layer behavior | Dongle (`01-dongle`) | Keymap lives on the central |
| Debounce / KSCAN (`corne.conf`) | Both halves (`02-left`, `03-right`) | Matrix scan runs on the halves |
| YADS display (`corne_dongle.conf`) | Dongle (`01-dongle`) | |
| Bond reset | All three | Flash `reset_*` first, then normal firmware |

**Bond reset** (if halves won't connect to dongle):

1. Flash `reset_xiao` to the dongle, `reset_nano` to both halves.
2. Power-cycle all three boards.
3. Re-flash the normal firmware (`dongle`, `left`, `right`).

## File Layout

```
zmk-corne/
├── config/
│   ├── west.yml                        # West manifest (ZMK v0.3.0 + YADS)
│   ├── corne.keymap                    # Keymap (lives on dongle only)
│   ├── corne.conf                      # Shared ZMK settings (debounce)
│   ├── corne_dongle.conf               # Dongle-specific (YADS display)
│   └── boards/shields/corne_dongle/    # Custom dongle shield overlay
│       ├── Kconfig.shield
│       ├── Kconfig.defconfig
│       └── corne_dongle.overlay
├── Dockerfile                          # Build image (zmk-dev-arm:stable)
├── docker-compose.yml                  # Service definition
├── entrypoint.sh                       # Build orchestrator (targets)
├── requirements.txt                    # Local Python deps (adafruit-nrfutil)
├── scripts/
│   ├── extract-zephyr-bindings.sh      # Extract ZMK/Zephyr trees for dts-lsp
│   └── flash.sh                        # Serial DFU flashing (work machine)
├── .github/workflows/
│   ├── build.yml                       # Post-merge build + artifacts
│   └── check.yml                       # PR gate (lint + compile)
├── firmware/                           # Build outputs (.uf2) — gitignored
├── .zmk-app/                           # Extracted ZMK app — gitignored
└── .zephyr-sdk/                        # Extracted Zephyr tree — gitignored
```

## dts-lsp

[dts-lsp](https://github.com/nickel-lang/dts-lsp) provides code intelligence
(go-to-definition, diagnostics, completions) for `.dts`, `.dtsi`, `.keymap`,
and `.overlay` files.

It needs ZMK and Zephyr source trees on the host for bindings and include
resolution. These are extracted from the Docker image:

```sh
./scripts/extract-zephyr-bindings.sh
```

This creates two gitignored directories:

| Directory | Source in container | Contents |
|-----------|-------------------|----------|
| `.zmk-app/` | `/workspace/zmk/app` | ZMK DTS bindings, behaviors, include headers, upstream corne shield |
| `.zephyr-sdk/` | `/workspace/zephyr` | Zephyr SoC DTSIs, core bindings, include headers, XIAO BLE board DTS |

Re-run after `docker compose build` if you change `west.yml` (new ZMK/Zephyr
version).

Editor config (neovim): `~/.config/nvim/lua/lsp/dts_lsp.lua`
