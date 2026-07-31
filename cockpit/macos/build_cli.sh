#!/bin/bash
# Compila a CLI interna `cockpit` (tool/cockpit_cli.dart) e a empacota como
# `cockpit-cli` (nome distinto de `cockpit.app`/PRODUCT_NAME) em Resources,
# assinada. Espelha o build_hook.sh. Dois modos:
#
#   ./macos/build_cli.sh dev
#     Compila para ~/.cockpit/bin-debug/cockpit (para `flutter run` / testes
#     E2E) — o diretório da CLI é namespaceado por flavor, como o status.sock,
#     pra build de dev e instalada não sobrescreverem a CLI uma da outra.
#
#   (sem args / rodado pelo Xcode como Run Script phase)
#     Compila e copia para
#       ${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/cockpit-cli
#     e code-signa com ${EXPANDED_CODE_SIGN_IDENTITY} (a mesma da app). O app,
#     no boot, materializa essa cópia como ~/.cockpit/bin[-debug]/cockpit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # cockpit/
SRC="$ROOT/tool/cockpit_cli.dart"

source "$ROOT/macos/build_dart_helper.sh"

mode="${1:-bundle}"
if [ "$mode" = "dev" ]; then
  echo "[build_cli] compilando para a arquitetura do host"
  compile_dart_helper_for_host "$SRC" "$HOME/.cockpit/bin-debug/cockpit"
  echo "[build_cli] dev OK"
  exit 0
fi

# Modo bundle (Xcode).
: "${BUILT_PRODUCTS_DIR:?precisa rodar pelo Xcode (BUILT_PRODUCTS_DIR ausente)}"
: "${PRODUCT_NAME:?PRODUCT_NAME ausente}"
DEST="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Resources/cockpit-cli"
echo "[build_cli] compilando helper universal -> $DEST"
compile_universal_dart_helper "$SRC" "$DEST" "cockpit-cli"

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

# Nota (plano 51): os dylibs do anakiORM NÃO são copiados aqui. Os pacotes
# `anaki_*` trazem os binários via **native assets** (hook/build.dart), e o
# Flutter os empacota/assina no `flutter build` automaticamente. Se algum
# engine falhar por binário ausente, é problema do pacote anaki (issue #4) —
# não recriamos staging manual aqui.
