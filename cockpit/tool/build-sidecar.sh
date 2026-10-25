#!/usr/bin/env bash
# Compila o cockpit-server (com os native assets do anaki) + a dylib do PTY
# para o fluxo de DEV (plano 58). Usa `dart build cli` (NÃO `dart compile
# exe`, que não suporta build hooks) → bundle `bin/` + `lib/`. O app encontra
# o resultado em build/server-bundle/bin/cockpit-server; sem ele o app cai no
# PTY in-process sozinho.
#
# Uso:  ./tool/build-sidecar.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build/server-bundle"

./tool/wave0/build_pty_dylib.sh

( cd packages/cockpit_server && dart pub get >/dev/null )
rm -rf "$OUT"
( cd packages/cockpit_server && dart build cli -o "$OUT" >/dev/null )

# `dart build cli` gera <out>/bundle/{bin,lib}. Normaliza para <out>/{bin,lib}
# e batiza o exe como `cockpit-server` (o pacote é `cockpit_server`).
if [ -d "$OUT/bundle" ]; then
  mv "$OUT"/bundle/* "$OUT"/ && rmdir "$OUT/bundle"
fi
if [ -f "$OUT/bin/cockpit_server" ]; then
  mv "$OUT/bin/cockpit_server" "$OUT/bin/cockpit-server"
fi
# Dart >= 3.14 no Linux: o runtime em bin/ acha o snapshot por
# lib/libdartaot<basename do exe>.so, então o .so acompanha o rename
# (ver linux/rename_server_snapshot.cmake). Ausente em Dart < 3.14 e no macOS.
if [ -f "$OUT/lib/libdartaotcockpit_server.so" ]; then
  mv "$OUT/lib/libdartaotcockpit_server.so" "$OUT/lib/libdartaotcockpit-server.so"
fi

# A dylib do PTY vai pra lib/ (o exe resolve @executable_path/../lib).
ext="$([ "$(uname -s)" = Darwin ] && echo dylib || echo so)"
cp "build/wave0/libcockpit_pty.$ext" "$OUT/lib/" 2>/dev/null || true

# CLI `cockpit` AO LADO do server (plano 60, Wave G): o server instala o hook do
# agente apontando pra ela e a acha na mesma pasta bin/.
#
# Tem que sair daqui também, e não só do macos/build_server.sh: no macOS o .app
# é universal, montado pelo lipo entre o bundle arm64 (build_server.sh) e o x64
# (este script, no runner Intel). Quando só um dos lados produzia `bin/cockpit`,
# o lipo abortava com "fatia x64 faltando para bin/cockpit" e derrubava a
# release inteira — foi o que aconteceu na 1.28.0.
CARGO="${CARGO:-cargo}"
command -v "$CARGO" >/dev/null 2>&1 || CARGO="$HOME/.cargo/bin/cargo"
( cd "$ROOT/cli" && "$CARGO" build --release >/dev/null )
cp "$ROOT/cli/target/release/cockpit" "$OUT/bin/cockpit"
chmod +x "$OUT/bin/cockpit"

echo "ok: $OUT/bin/cockpit-server + bin/cockpit (+ lib/: $(ls "$OUT/lib" | tr '\n' ' '))"
