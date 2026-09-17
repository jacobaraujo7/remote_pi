#!/usr/bin/env bash
# Empacota o cockpit-server para distribuição avulsa (plano 2.0, k25):
#
#   cockpit-server-<versão>-linux-<arch>.zip
#   └── cockpit-server/
#       ├── bin/{cockpit-server,cockpit}
#       ├── lib/{libcockpit_pty.so,libanaki_*.so}
#       ├── bundle.manifest   # sha256sum -c, mesmo formato que o cliente grava
#       ├── VERSION           # linha 1: versão; linha 2: arch (x86_64|arm64)
#       └── install.sh        # packages/cockpit_server/install.sh
#
# Build NATIVO (dart build cli não cross-compila): roda no runner Linux de cada
# arquitetura. Reusa tool/build-sidecar.sh, que já produz bin/ + lib/ com os
# native assets do anaki, a lib do PTY e a CLI Rust.
#
# Uso: tool/build-server-zip.sh <dir de saída>
# Env: VERSION (default: `version:` do pubspec.yaml, sem o +build)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="${1:?output dir is required}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

[ "$(uname -s)" = Linux ] || { echo "[server-zip] Linux only" >&2; exit 1; }
case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "[server-zip] unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
VERSION="${VERSION:-$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)}"
[ -n "$VERSION" ] || { echo "[server-zip] could not resolve VERSION" >&2; exit 1; }

./tool/build-sidecar.sh
BUNDLE="$ROOT/build/server-bundle"
[ -x "$BUNDLE/bin/cockpit-server" ] || { echo "[server-zip] bin/cockpit-server missing" >&2; exit 1; }
[ -f "$BUNDLE/lib/libcockpit_pty.so" ] || { echo "[server-zip] lib/libcockpit_pty.so missing" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/cockpit-server"
mkdir -p "$PKG"
cp -R "$BUNDLE/bin" "$BUNDLE/lib" "$PKG/"
chmod +x "$PKG"/bin/*
printf '%s\n%s\n' "$VERSION" "$ARCH" > "$PKG/VERSION"
cp "$ROOT/packages/cockpit_server/install.sh" "$PKG/install.sh"
chmod +x "$PKG/install.sh"

# Manifesto no formato exato do cliente (host_shell.dart buildManifest):
# "<sha256>  <caminho relativo>", só bin/ e lib/, ordenado pelo caminho.
( cd "$PKG" && find bin lib -type f | LC_ALL=C sort | xargs sha256sum ) > "$PKG/bundle.manifest"

# Smoke: o zip só sai se o servidor sobe nesta máquina.
SOCK="$STAGE/smoke.sock"
COCKPIT_PTY_DYLIB="$PKG/lib/libcockpit_pty.so" \
  "$PKG/bin/cockpit-server" --socket "$SOCK" --exit-on-idle 1 >"$STAGE/smoke.log" 2>&1 &
for _ in $(seq 1 40); do [ -S "$SOCK" ] && break; sleep 0.25; done
[ -S "$SOCK" ] || { echo "[server-zip] smoke failed:" >&2; cat "$STAGE/smoke.log" >&2; exit 1; }
wait || true
GOT="$("$PKG/bin/cockpit-server" --version 2>&1 || true)"; [ "$GOT" = "$VERSION" ] || {
  echo "[server-zip] --version reported '$GOT', expected $VERSION" >&2; exit 1; }

ZIP="$OUT/cockpit-server-$VERSION-linux-$ARCH.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -qr "$ZIP" cockpit-server )
echo "[server-zip] ok -> $ZIP"
