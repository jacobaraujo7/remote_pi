#!/usr/bin/env bash
set -euo pipefail

# Build and package Cockpit desktop app and the `cockpit` / `ck` internal CLI.
#
# Usage:
#   scripts/build-cockpit.sh [--install] [--dest <path>]
#
# Options:
#   --install       Installs Cockpit.app to ~/Applications/Cockpit.app (with backup)
#   --dest <dir>    Custom destination directory for the installed Cockpit.app
#   --help, -h      Show this help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COCKPIT_DIR="$REPO_ROOT/cockpit"
CLI_DIR="$COCKPIT_DIR/cli"

DO_INSTALL=false
DEST_DIR="$HOME/Applications"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      DO_INSTALL=true
      shift
      ;;
    --dest)
      DEST_DIR="$2"
      DO_INSTALL=true
      shift 2
      ;;
    -h|--help)
      echo "Usage: scripts/build-cockpit.sh [--install] [--dest <path>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

echo "==> Checking prerequisites..."
command -v cargo >/dev/null 2>&1 || { echo "Error: 'cargo' not found in PATH" >&2; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "Error: 'flutter' not found in PATH" >&2; exit 1; }
command -v zig >/dev/null 2>&1 || { echo "Error: 'zig' not found in PATH" >&2; exit 1; }

echo "==> Building Rust CLI (cockpit-cli)..."
cargo build --release --manifest-path "$CLI_DIR/Cargo.toml"
cargo test --manifest-path "$CLI_DIR/Cargo.toml" --quiet

echo "==> Installing CLI to ~/.cockpit/bin..."
mkdir -p "$HOME/.cockpit/bin"
cp "$CLI_DIR/target/release/cockpit" "$HOME/.cockpit/bin/cockpit"
chmod +x "$HOME/.cockpit/bin/cockpit"
ln -sf cockpit "$HOME/.cockpit/bin/ck"

echo "==> Preparing Flutter dependencies..."
cd "$COCKPIT_DIR"
flutter pub get

echo "==> Applying macOS patches (media_kit BSD cut)..."
find "$HOME/.pub-cache" -name "create_framework_symlinks.sh" -exec sed -i '' "s/cut -d '-' -f 1 -f 3/cut -d '-' -f 1,3/g" {} + 2>/dev/null || true
if [ -f "macos/Flutter/ephemeral/.symlinks/plugins/media_kit_libs_macos_video/macos/create_framework_symlinks.sh" ]; then
  sed -i '' "s/cut -d '-' -f 1 -f 3/cut -d '-' -f 1,3/g" "macos/Flutter/ephemeral/.symlinks/plugins/media_kit_libs_macos_video/macos/create_framework_symlinks.sh" 2>/dev/null || true
fi

echo "==> Building macOS release application..."
flutter build macos

BUILT_APP="$COCKPIT_DIR/build/macos/Build/Products/Release/Cockpit.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "Error: Built app not found at $BUILT_APP" >&2
  exit 1
fi

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$BUILT_APP"

echo "==> Build successful: $BUILT_APP"

if [ "$DO_INSTALL" = true ]; then
  TARGET_APP="$DEST_DIR/Cockpit.app"
  BACKUP_APP="$DEST_DIR/Cockpit.app.bak"
  mkdir -p "$DEST_DIR"
  if [ -d "$TARGET_APP" ]; then
    echo "==> Backing up existing app to $BACKUP_APP..."
    rm -rf "$BACKUP_APP"
    cp -R "$TARGET_APP" "$BACKUP_APP"
  fi
  echo "==> Staging install to $TARGET_APP..."
  TEMP_APP="$DEST_DIR/Cockpit.app.tmp.$$"
  rm -rf "$TEMP_APP"
  ditto "$BUILT_APP" "$TEMP_APP"
  rm -rf "$TARGET_APP"
  mv "$TEMP_APP" "$TARGET_APP"
  echo "==> Successfully installed to $TARGET_APP!"
fi
