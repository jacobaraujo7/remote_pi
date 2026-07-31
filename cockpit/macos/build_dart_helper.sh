#!/bin/bash
# Funções compartilhadas para os executáveis Dart incluídos no bundle macOS.
#
# `dart compile exe` gera código para a arquitetura do SDK que o executa. Em
# Apple Silicon, Rosetta permite executar um SDK x64 e, portanto, gerar ambas
# as fatias localmente. Em Intel, os helpers são somente x64: esse fluxo não
# produz uma release compatível com Apple Silicon.

set -euo pipefail

resolve_dart() {
  if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
    echo "$FLUTTER_ROOT/bin/dart"
    return
  fi
  if command -v dart >/dev/null 2>&1; then
    command -v dart
    return
  fi
  if command -v flutter >/dev/null 2>&1; then
    echo "$(dirname "$(command -v flutter)")/dart"
    return
  fi
  echo "[cockpit helper] erro: 'dart' não encontrado (defina FLUTTER_ROOT)" >&2
  exit 1
}

dart_version() {
  "$@" --version 2>&1 | sed -nE 's/^Dart SDK version: ([^ ]+).*/\1/p'
}

require_same_dart_version() {
  local dart_arm="$1"
  local dart_x64="$2"
  local arm_version x64_version
  arm_version="$(dart_version "$dart_arm")"
  x64_version="$(dart_version arch -x86_64 "$dart_x64")"

  if [ -z "$arm_version" ] || [ -z "$x64_version" ] || [ "$arm_version" != "$x64_version" ]; then
    echo "[cockpit helper] erro: os SDKs Dart arm64 ($arm_version) e x64 ($x64_version) devem ter a mesma versão" >&2
    exit 1
  fi
}

# Para `flutter run`/testes locais: uma fatia do host é suficiente.
compile_dart_helper_for_host() {
  local source="$1"
  local output="$2"
  local dart
  dart="$(resolve_dart)"
  mkdir -p "$(dirname "$output")"
  "$dart" compile exe "$source" -o "$output"
  chmod +x "$output"
}

# Produz um executável universal para ser incluído num bundle de release.
#
# Ambiente em Apple Silicon:
#   COCKPIT_DART_X64=/caminho/para/flutter-x64/bin/dart
#
compile_universal_dart_helper() {
  local source="$1"
  local output="$2"
  local artifact_name="$3"
  local dart host_arch temp arm_slice x64_slice
  dart="$(resolve_dart)"
  host_arch="$(uname -m)"
  mkdir -p "$(dirname "$output")"

  case "$host_arch" in
    arm64)
      : "${COCKPIT_DART_X64:?Defina COCKPIT_DART_X64 com um SDK Dart/Flutter x64 para Rosetta}"
      if ! arch -x86_64 "$COCKPIT_DART_X64" --version >/dev/null 2>&1; then
        echo "[cockpit helper] erro: não foi possível executar o SDK x64; instale Rosetta e confira COCKPIT_DART_X64" >&2
        exit 1
      fi
      require_same_dart_version "$dart" "$COCKPIT_DART_X64"
      temp="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-helper.XXXXXX")"
      arm_slice="$temp/$artifact_name-arm64"
      x64_slice="$temp/$artifact_name-x86_64"
      "$dart" compile exe "$source" -o "$arm_slice"
      arch -x86_64 "$COCKPIT_DART_X64" compile exe "$source" -o "$x64_slice"
      ;;
    x86_64)
      echo "[cockpit helper] build Intel: gerando $artifact_name apenas para x86_64" >&2
      "$dart" compile exe "$source" -o "$output"
      chmod +x "$output"
      return
      ;;
    *)
      echo "[cockpit helper] erro: arquitetura de host macOS não suportada: $host_arch" >&2
      exit 1
      ;;
  esac

  /usr/bin/lipo -create "$arm_slice" "$x64_slice" -output "$output"
  chmod +x "$output"
  /usr/bin/lipo -verify_arch arm64 x86_64 "$output"
  rm -rf "$temp"
}
