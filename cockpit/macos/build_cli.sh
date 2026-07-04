#!/bin/bash
# Compila a CLI interna `cockpit` (tool/cockpit_cli.dart) e a empacota como
# `cockpit-cli` (nome distinto de `cockpit.app`/PRODUCT_NAME) em Resources,
# assinada. Espelha o build_hook.sh. Dois modos:
#
#   ./macos/build_cli.sh dev
#     Compila para ~/.cockpit/bin/cockpit (para `flutter run` / testes E2E).
#
#   (sem args / rodado pelo Xcode como Run Script phase)
#     Compila e copia para
#       ${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/cockpit-cli
#     e code-signa com ${EXPANDED_CODE_SIGN_IDENTITY} (a mesma da app). O app,
#     no boot, materializa essa cópia como ~/.cockpit/bin/cockpit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # cockpit/
SRC="$ROOT/tool/cockpit_cli.dart"

# Resolve o `dart`: 1) Flutter (FLUTTER_ROOT setado pelo Xcode), 2) PATH.
resolve_dart() {
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
    echo "$FLUTTER_ROOT/bin/dart"; return
  fi
  if command -v dart >/dev/null 2>&1; then command -v dart; return; fi
  if command -v flutter >/dev/null 2>&1; then
    echo "$(dirname "$(command -v flutter)")/dart"; return
  fi
  echo "[build_cli] erro: 'dart' não encontrado (defina FLUTTER_ROOT)" >&2
  exit 1
}

compile() {
  local out="$1"
  mkdir -p "$(dirname "$out")"
  echo "[build_cli] compilando $SRC -> $out"
  "$(resolve_dart)" compile exe "$SRC" -o "$out"
  chmod +x "$out"
}

mode="${1:-bundle}"
if [ "$mode" = "dev" ]; then
  compile "$HOME/.cockpit/bin/cockpit"
  echo "[build_cli] dev OK"
  exit 0
fi

# Modo bundle (Xcode).
: "${BUILT_PRODUCTS_DIR:?precisa rodar pelo Xcode (BUILT_PRODUCTS_DIR ausente)}"
: "${PRODUCT_NAME:?PRODUCT_NAME ausente}"
DEST="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/cockpit-cli"
compile "$DEST"

# Assinatura: mesma lógica do build_hook.sh (exe AOT do Dart precisa de
# entitlements allow-jit/allow-unsigned-executable-memory sob hardened runtime).
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  echo "[build_cli] codesign ad-hoc (dev) $DEST"
  codesign --force -s - "$DEST"
else
  echo "[build_cli] codesign ($IDENTITY) + hardened runtime $DEST"
  codesign --force --options runtime \
    --entitlements "$ROOT/macos/cockpit_hook.entitlements" \
    -s "$IDENTITY" "$DEST"
fi
echo "[build_cli] bundle OK -> $DEST"
