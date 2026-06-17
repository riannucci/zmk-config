#!/usr/bin/env bash
# Extracts Zephyr and ZMK trees from the Docker image to the host.
#
# These directories provide DTS bindings, include headers, and board
# definitions that dts-lsp (`devicetree-language-server --stdio`) needs for
# code intelligence in .dts/.dtsi/.keymap/.overlay files.
#
#   .zmk-app/    — ZMK app dir (bindings, behaviors, shields, board metadata)
#   .zephyr-sdk/ — Zephyr tree (SoC DTSIs, core bindings, include headers, boards)
#
# Usage: ./scripts/extract-zephyr-bindings.sh
# Run after: docker compose build
set -euo pipefail

SERVICE="make"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMK_APP_SRC="/workspace/zmk/app"
ZMK_APP_DEST="$REPO_ROOT/.zmk-app"
ZEPHYR_SRC="/workspace/zephyr"
ZEPHYR_DEST="$REPO_ROOT/.zephyr-sdk"

cd "$REPO_ROOT"

# Create a container (not started) from the compose service
docker compose create "$SERVICE"
trap 'docker compose rm -f "$SERVICE" >/dev/null' EXIT

# --- ZMK app (bindings, behaviors, shields, board metadata) ---
echo "==> Extracting $ZMK_APP_SRC -> $ZMK_APP_DEST"
rm -rf "$ZMK_APP_DEST"
mkdir -p "$ZMK_APP_DEST/boards/shields"

for dir in dts include 'boards/shields/corne'; do
	docker compose cp "$SERVICE:$ZMK_APP_SRC/$dir" "$ZMK_APP_DEST/$dir"
done

# --- Zephyr tree (SoC DTSIs, core bindings, include headers, boards) ---
echo "==> Extracting $ZEPHYR_SRC → $ZEPHYR_DEST"
rm -rf "$ZEPHYR_DEST"
mkdir -p "$ZEPHYR_DEST/boards/arm"

for dir in dts include 'boards/arm/seeeduino_xiao_ble'; do
	docker compose cp "$SERVICE:$ZEPHYR_SRC/$dir" "$ZEPHYR_DEST/$dir"
done

du -sh "$ZMK_APP_DEST" "$ZEPHYR_DEST"
