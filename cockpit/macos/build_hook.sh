#!/bin/bash
# Compila o helper `cockpit-hook` (tool/cockpit_hook.dart) e o coloca no lugar
# certo, assinado. Dois modos:
#
#   ./macos/build_hook.sh dev
#     Compila para ~/.cockpit/bin/cockpit-hook (para `flutter run` / testes E2E).
#
#   (sem args / rodado pelo Xcode como Run Script phase)
#     Compila e copia para
#       ${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/cockpit-hook
#     e code-signa com ${EXPANDED_CODE_SIGN_IDENTITY} (a mesma da app).
#
# Adicionado como Run Script phase no target Runner (Xcode), depois do
# "Run Script" do Flutter e antes do "Code Sign". Vars BUILT_PRODUCTS_DIR/
# PRODUCT_NAME/EXPANDED_CODE_SIGN_IDENTITY/FLUTTER_ROOT vêm do Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # cockpit/
SRC="$ROOT/tool/cockpit_hook.dart"

source "$ROOT/macos/build_dart_helper.sh"

mode="${1:-bundle}"
if [ "$mode" = "dev" ]; then
  echo "[build_hook] compilando para a arquitetura do host"
  compile_dart_helper_for_host "$SRC" "$HOME/.cockpit/bin/cockpit-hook"
  echo "[build_hook] dev OK"
  exit 0
fi

# Modo bundle (Xcode).
: "${BUILT_PRODUCTS_DIR:?precisa rodar pelo Xcode (BUILT_PRODUCTS_DIR ausente)}"
: "${PRODUCT_NAME:?PRODUCT_NAME ausente}"
DEST="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/cockpit-hook"
echo "[build_hook] compilando helper universal -> $DEST"
compile_universal_dart_helper "$SRC" "$DEST" "cockpit-hook"

# Assinatura: exe AOT do Dart é morto sob hardened runtime ad-hoc. Então:
# - dev/ad-hoc (sem identity ou '-'): assina PLANO (sem --options runtime).
# - produção (Developer ID): hardened runtime + entitlements (allow-jit /
#   allow-unsigned-executable-memory) que o runtime do Dart exige.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  echo "[build_hook] codesign ad-hoc (dev) $DEST"
  codesign --force -s - "$DEST"
else
  echo "[build_hook] codesign ($IDENTITY) + hardened runtime $DEST"
  codesign --force --options runtime \
    --entitlements "$ROOT/macos/cockpit_hook.entitlements" \
    -s "$IDENTITY" "$DEST"
fi
echo "[build_hook] bundle OK -> $DEST"
