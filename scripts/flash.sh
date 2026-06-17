#!/usr/bin/env bash
# Flash ZMK firmware to a controller via Adafruit serial DFU.
#
# For machines where USB Mass Storage (UF2 drag-drop) is blocked but the
# bootloader's USB CDC serial port still enumerates (a /dev/cu.usbmodem* on
# macOS, or /dev/ttyACM* on Linux, appears in bootloader mode). No-install
# alternative: the browser flasher at https://opendisplay.org/nrf_web_tools/
# (select the matching firmware/<NN-name>.zip).
#
# Usage:  ./scripts/flash.sh <dongle|left|right|reset_xiao|reset_nano> [serial-port]
# Build first:  docker compose run --rm make all
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_DIR="$REPO_ROOT/firmware"

usage() {
	echo "Usage: $0 <dongle|left|right|reset_xiao|reset_nano> [serial-port]" >&2
	exit 2
}

TARGET="${1:-}"
PORT_OVERRIDE="${2:-}"

# Map the friendly target name to the numbered artifact basename
# (matches the flashing-order prefixes produced by the build / GitHub Actions).
case "$TARGET" in
	dongle) base="01-dongle" ;;
	left) base="02-left" ;;
	right) base="03-right" ;;
	reset_xiao) base="00a-reset_xiao" ;;
	reset_nano) base="00b-reset_nano" ;;
	"") usage ;;
	*) echo "Unknown target: $TARGET" >&2; usage ;;
esac

if ! command -v adafruit-nrfutil >/dev/null 2>&1; then
	echo "ERROR: adafruit-nrfutil not found on PATH." >&2
	echo "       Set up the local venv:  python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt" >&2
	echo "       Or use the no-install browser flasher:" >&2
	echo "       https://opendisplay.org/nrf_web_tools/  (select firmware/$base.zip)" >&2
	exit 1
fi

HEX="$FW_DIR/$base.hex"
ZIP="$FW_DIR/$base.zip"

# Prefer the prebuilt .zip; otherwise derive it from the .hex.
if [[ ! -f "$ZIP" ]]; then
	if [[ -f "$HEX" ]]; then
		echo "==> $base.zip missing; generating from $base.hex ..."
		adafruit-nrfutil dfu genpkg --dev-type 0x0052 --application "$HEX" "$ZIP"
	else
		echo "ERROR: neither $ZIP nor $HEX found." >&2
		echo "       Build firmware first:  docker compose run --rm make $TARGET" >&2
		exit 1
	fi
fi

echo ""
echo "==> Target: $TARGET    package: $ZIP"
echo "    1. Connect the board via USB."
echo "    2. Double-tap reset to enter bootloader (the blocked UF2 drive is expected)."
echo ""
read -r -p "Press ENTER once the board is in bootloader mode... " _unused

# Resolve the bootloader serial port.
if [[ -n "$PORT_OVERRIDE" ]]; then
	port="$PORT_OVERRIDE"
	if [[ ! -e "$port" ]]; then
		echo "ERROR: specified port '$port' does not exist." >&2
		exit 1
	fi
else
	# Auto-detect (macOS: /dev/cu.usbmodem*, Linux: /dev/ttyACM*).
	shopt -s nullglob
	ports=(/dev/cu.usbmodem* /dev/ttyACM*)
	shopt -u nullglob
	if [[ ${#ports[@]} -eq 0 ]]; then
		echo "ERROR: no bootloader serial port found (/dev/cu.usbmodem* or /dev/ttyACM*)." >&2
		echo "       - Re-enter bootloader mode (double-tap reset) and retry, or" >&2
		echo "       - flash in the browser: https://opendisplay.org/nrf_web_tools/" >&2
		exit 1
	fi
	if [[ ${#ports[@]} -gt 1 ]]; then
		echo "ERROR: multiple serial ports found: ${ports[*]}" >&2
		echo "       Flashing the wrong device could brick it. Unplug other USB-serial" >&2
		echo "       devices, or pass the port explicitly:" >&2
		echo "       $0 $TARGET <serial-port>" >&2
		exit 1
	fi
	port="${ports[0]}"
fi

echo "==> Flashing $TARGET ($base) via $port ..."
adafruit-nrfutil --verbose dfu serial --package "$ZIP" -p "$port" -b 115200 --singlebank

echo ""
echo "==> Done. $TARGET rebooting."
