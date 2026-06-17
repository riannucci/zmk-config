#!/usr/bin/env bash
set -euo pipefail

ZMK_APP="/workspace/zmk/app"
CONFIG="/zmk-config"
OUTPUT="/firmware"

# Board names — change these for Path B (Zephyr 4.1)
XIAO_BOARD="seeeduino_xiao_ble"
NANO_BOARD="nice_nano_v2"

# Copy build outputs to $OUTPUT and, when adafruit-nrfutil is available, also
# generate an Adafruit serial-DFU .zip package. The .zip is flashable over the
# bootloader's USB CDC serial interface (browser via WebSerial, or the
# adafruit-nrfutil CLI) on machines where the USB mass-storage / UF2 drag-drop
# path is blocked.
#   $1 = output base name (e.g. "dongle")
#   $2 = west build directory (contains zephyr/zmk.{uf2,hex})
# Output basenames are prefixed with the recommended flashing order, matching the
# GitHub Actions artifacts: 00a/00b settings_reset, 01 dongle (central), 02/03 halves.
export_artifacts() {
	local name="$1" build_dir="$2"
	cp "$build_dir/zephyr/zmk.uf2" "$OUTPUT/$name.uf2"
	cp "$build_dir/zephyr/zmk.hex" "$OUTPUT/$name.hex"
	if command -v adafruit-nrfutil >/dev/null 2>&1; then
		adafruit-nrfutil dfu genpkg --dev-type 0x0052 \
			--application "$OUTPUT/$name.hex" "$OUTPUT/$name.zip"
		echo "    → $OUTPUT/$name.{uf2,hex,zip}"
	else
		echo "    → $OUTPUT/$name.{uf2,hex}  (adafruit-nrfutil missing; .zip skipped)"
	fi
}

build_dongle() {
	echo "==> Building dongle (central + YADS screen)..."
	west build -p -s "$ZMK_APP" -d "$ZMK_APP/build/dongle" \
		-b "$XIAO_BOARD" \
		-- -DSHIELD="corne_dongle dongle_screen" \
		-DZMK_CONFIG="$CONFIG"
	export_artifacts 01-dongle "$ZMK_APP/build/dongle"
}

build_left() {
	echo "==> Building left half (peripheral)..."
	west build -p -s "$ZMK_APP" -d "$ZMK_APP/build/left" \
		-b "$NANO_BOARD" \
		-- -DSHIELD="corne_left" \
		-DCONFIG_ZMK_SPLIT=y \
		-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n \
		-DZMK_CONFIG="$CONFIG"
	export_artifacts 02-left "$ZMK_APP/build/left"
}

build_right() {
	echo "==> Building right half (peripheral)..."
	west build -p -s "$ZMK_APP" -d "$ZMK_APP/build/right" \
		-b "$NANO_BOARD" \
		-- -DSHIELD="corne_right" \
		-DCONFIG_ZMK_SPLIT=y \
		-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n \
		-DZMK_CONFIG="$CONFIG"
	export_artifacts 03-right "$ZMK_APP/build/right"
}

build_reset() {
	echo "==> Building settings_reset (XIAO)..."
	west build -p -s "$ZMK_APP" -d "$ZMK_APP/build/reset_xiao" \
		-b "$XIAO_BOARD" \
		-- -DSHIELD="settings_reset"
	export_artifacts 00a-reset_xiao "$ZMK_APP/build/reset_xiao"

	echo "==> Building settings_reset (nice!nano)..."
	west build -p -s "$ZMK_APP" -d "$ZMK_APP/build/reset_nano" \
		-b "$NANO_BOARD" \
		-- -DSHIELD="settings_reset"
	export_artifacts 00b-reset_nano "$ZMK_APP/build/reset_nano"
}

# Default to building everything if no arguments given
TARGETS=("${@:-all}")

for target in "${TARGETS[@]}"; do
	case "$target" in
	dongle) build_dongle ;;
	left) build_left ;;
	right) build_right ;;
	reset) build_reset ;;
	all)
		build_dongle
		build_left
		build_right
		build_reset
		;;
	*)
		echo "Unknown target: $target"
		echo "Usage: docker compose run --rm make [dongle|left|right|reset|all]"
		exit 1
		;;
	esac
done

echo ""
echo "==> Done. Firmware files:"
ls -la "$OUTPUT"/*.uf2 "$OUTPUT"/*.hex "$OUTPUT"/*.zip 2>/dev/null || true
