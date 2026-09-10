#!/usr/bin/env bash
# Cross-compiles the cockpit-server bundle deployed by a macOS client to Linux
# arm64 remote hosts. The Dart AOT executable and anaki native assets are built
# by `dart build cli`; the PTY library and Rust CLI use Zig as the cross linker.
#
# Usage: tool/build-linux-arm64-server-bundle.sh <destination>
# Output: <destination>/{bin,lib}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?destination is required}"
TARGET="aarch64-unknown-linux-gnu"

resolve_tool() {
  local name="$1" fallback="${2:-}"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  elif [ -n "$fallback" ] && [ -x "$fallback" ]; then
    echo "$fallback"
  else
    echo "[linux-server] error: '$name' not found" >&2
    exit 1
  fi
}

if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
  DART="$FLUTTER_ROOT/bin/dart"
else
  DART="$(resolve_tool dart)"
fi
ZIG="$(resolve_tool zig)"
CARGO="$(resolve_tool cargo "$HOME/.cargo/bin/cargo")"
RUSTUP="$(resolve_tool rustup "$HOME/.cargo/bin/rustup")"

if ! "$RUSTUP" target list --installed | grep -qx "$TARGET"; then
  echo "[linux-server] error: Rust target '$TARGET' is not installed" >&2
  echo "[linux-server] run: rustup target add $TARGET" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$DEST"
mkdir -p "$DEST"

(
  cd "$ROOT/packages/cockpit_server"
  "$DART" pub get >/dev/null
  "$DART" build cli \
    --target-os linux \
    --target-arch arm64 \
    -o "$TMP/dart" >/dev/null
)
mv "$TMP/dart/bundle"/* "$DEST"/
mv "$DEST/bin/cockpit_server" "$DEST/bin/cockpit-server"

# cockpit_pty is intentionally not a Dart native asset yet. Build the same C
# source as the native sidecar, but against Zig's Linux aarch64 sysroot.
"$ZIG" cc -target aarch64-linux-gnu -shared -O2 -DDART_SHARED_LIB \
  -o "$DEST/lib/libcockpit_pty.so" \
  "$ROOT/plugins/cockpit_pty/src/cockpit_pty.c" \
  -I"$ROOT/plugins/cockpit_pty/src" -lpthread

# Cargo accepts a linker executable, not a command with arguments, so wrap Zig.
ZIG_LINKER="$TMP/zig-aarch64-linux-gnu-cc"
cat >"$ZIG_LINKER" <<EOF
#!/bin/sh
exec "$ZIG" cc -target aarch64-linux-gnu "\$@"
EOF
chmod +x "$ZIG_LINKER"
(
  cd "$ROOT/cli"
  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="$ZIG_LINKER" \
    "$CARGO" build --release --target "$TARGET" >/dev/null
)
cp "$ROOT/cli/target/$TARGET/release/cockpit" "$DEST/bin/cockpit"
chmod +x "$DEST/bin/cockpit-server" "$DEST/bin/cockpit"

echo "[linux-server] bundle OK -> $DEST"
