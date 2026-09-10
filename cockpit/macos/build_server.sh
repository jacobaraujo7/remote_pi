#!/bin/bash
# Empacota o cockpit-server (plano 58) no .app via `dart build cli` — que
# SUPORTA build hooks (native assets do anaki), ao contrário do
# `dart compile exe`. O resultado (bin/ + lib/) vai para
#   Resources/cockpit-server-bundle/{bin,lib}
# e o app resolve o binário lá (SidecarTerminalConnector). Além do sidecar
# Darwin, empacota o target de bootstrap remoto em
#   Resources/cockpit-server-bundle/targets/linux-arm64/{bin,lib}.
#
# ATENÇÃO — arquitetura: fatia única (a do host que buildou), no nome sem
# sufixo (`bin/cockpit-server`), que é o fallback do resolver. No CI, o
# tool/lipo-server-bundle.sh troca esse arquivo pelas duas fatias
# `cockpit-server-arm64` e `cockpit-server-x64` — o exe é um AOT do Dart e
# NÃO sobrevive ao `lipo` (o snapshot anexado some do alcance do
# dartaotruntime). Nunca transforme este binário num Mach-O universal.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # cockpit/

resolve_dart() {
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
    echo "$FLUTTER_ROOT/bin/dart"; return
  fi
  if command -v dart >/dev/null 2>&1; then command -v dart; return; fi
  echo "[build_server] erro: 'dart' não encontrado" >&2
  exit 1
}
DART="$(resolve_dart)"

: "${BUILT_PRODUCTS_DIR:?precisa rodar pelo Xcode (BUILT_PRODUCTS_DIR ausente)}"
: "${PRODUCT_NAME:?PRODUCT_NAME ausente}"
DEST="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/cockpit-server-bundle"
rm -rf "$DEST"
mkdir -p "$DEST"

# Dylib do PTY: universal (C compila as duas fatias num comando).
SRC="$ROOT/plugins/cockpit_pty/src"
PTY="$ROOT/build/wave0/libcockpit_pty.dylib"
mkdir -p "$ROOT/build/wave0"
cc -dynamiclib -O2 -DDART_SHARED_LIB -arch arm64 -arch x86_64 \
  -o "$PTY" "$SRC/cockpit_pty.c" -I"$SRC" -lpthread

# Servidor via dart build cli (bundle bin/ + lib/ com os native assets).
( cd "$ROOT/packages/cockpit_server" && "$DART" pub get >/dev/null )
BUNDLE="$(mktemp -d)/out"
( cd "$ROOT/packages/cockpit_server" && "$DART" build cli -o "$BUNDLE" >/dev/null )
# `dart build cli` gera <out>/bundle/{bin,lib}.
mv "$BUNDLE"/bundle/* "$DEST"/
mv "$DEST/bin/cockpit_server" "$DEST/bin/cockpit-server"
cp "$PTY" "$DEST/lib/libcockpit_pty.dylib"
chmod +x "$DEST/bin/cockpit-server"

# Target de bootstrap para os VMs Linux arm64 de workspaces remotos. Fica
# isolado do sidecar macOS para o resolver nunca tentar executar um ELF local.
# O helper também produz libcockpit_pty.so e a CLI Rust para o host remoto.
"$ROOT/tool/build-linux-arm64-server-bundle.sh" \
  "$DEST/targets/linux-arm64"

# CLI `cockpit` embarcada AO LADO do server (plano 60, Wave G): o server instala
# o hook do agente no ~/.claude do host apontando pra `cockpit hook`, e a acha
# via _besideServer (mesma pasta bin/). Fatia única do host, como o server.
CARGO="${CARGO:-cargo}"
command -v "$CARGO" >/dev/null 2>&1 || CARGO="$HOME/.cargo/bin/cargo"
( cd "$ROOT/cli" && "$CARGO" build --release >/dev/null )
cp "$ROOT/cli/target/release/cockpit" "$DEST/bin/cockpit"
chmod +x "$DEST/bin/cockpit"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
sign() {
  if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    codesign --force -s - "$@"
  else
    codesign --force --options runtime \
      --entitlements "$ROOT/macos/cockpit_hook.entitlements" \
      -s "$IDENTITY" "$@"
  fi
}
# Assina as dylibs antes do exe.
for f in "$DEST"/lib/*.dylib; do sign "$f"; done
sign "$DEST/bin/cockpit-server"
[ -f "$DEST/bin/cockpit" ] && sign "$DEST/bin/cockpit"
echo "[build_server] bundle OK -> $DEST"
