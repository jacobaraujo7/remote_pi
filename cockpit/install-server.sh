#!/usr/bin/env bash
#
# Remote Pi Cockpit — cockpit-server installer for Linux hosts (VPS)
# ==================================================================
#
#   curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash
#   curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash -s -- --service
#   COCKPIT_VERSION=1.28.33 curl -fsSL ... | bash
#
# Canonical file: cockpit/install-server.sh in the repo; the site URL above
# redirects to the GitHub raw of this file:
#   https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh
#
# What it does (user-space, NO sudo, idempotent):
#   1. Detects the architecture (x86_64 or arm64; Linux only).
#   2. Resolves the version: $COCKPIT_VERSION, else the latest
#      `cockpit-server-v*` GitHub release.
#   3. Downloads cockpit-server-<version>-linux-<arch>.zip + SHA256SUMS from
#      that release and verifies the checksum.
#   4. Unzips (unzip, else python3, else installs unzip via the package
#      manager when sudo is passwordless) and runs the install.sh inside,
#      which installs to ~/.cockpit/server (same layout the desktop app uses).
#   --service: also registers a systemd --user unit so the server starts at
#      boot (`cockpit-server service install`; may print one sudo command for
#      `loginctl enable-linger`). Without it the app starts the server on
#      demand over SSH, which is enough for most hosts.
#
# The server version must match the Cockpit app you connect from.
# Trust: plain readable script, no privileges. Read it before piping to bash.
set -euo pipefail

REPO="${COCKPIT_REPO:-jacobaraujo7/remote_pi}"
GH_API="https://api.github.com/repos/$REPO"
GH_DL="https://github.com/$REPO/releases/download"
INSTALL_ARGS=()
for a in "$@"; do
  case "$a" in
    --service) INSTALL_ARGS+=("--service") ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
else
  BOLD=""; RED=""; GRN=""; RST=""
fi
step() { printf '%s\n' "${BOLD}==> $*${RST}"; }
ok()   { printf '%s\n' "    ${GRN}ok${RST} $*"; }
die()  { printf '%s\n' "${RED}${BOLD}error:${RST} $*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] || die "cockpit-server runs on Linux hosts only (macOS hosts are set up by the app over SSH)"
case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "unsupported architecture: $(uname -m) (x86_64 and arm64 only)" ;;
esac
for tool in curl sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required"
done

# Extracting the zip: prefer `unzip`; fall back to python3's zipfile module
# (present on nearly every distro); as a last resort install `unzip` with the
# package manager when sudo works without a password (cloud images, OrbStack,
# containers). Otherwise stop with the exact command to run.
extract_zip() { # <zip> <dest dir>
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$1" -d "$2"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$1" "$2" <<'PY'
import os, sys, zipfile
src, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        target = z.extract(info, dest)
        mode = (info.external_attr >> 16) & 0o777
        if mode and not info.is_dir():
            os.chmod(target, mode)
PY
  else
    return 1
  fi
}
ensure_extractor() {
  command -v unzip >/dev/null 2>&1 && return 0
  command -v python3 >/dev/null 2>&1 && return 0
  local pm=""
  if command -v apt-get >/dev/null 2>&1; then pm="apt-get install -y unzip"
  elif command -v dnf >/dev/null 2>&1; then pm="dnf install -y unzip"
  elif command -v yum >/dev/null 2>&1; then pm="yum install -y unzip"
  elif command -v apk >/dev/null 2>&1; then pm="apk add unzip"
  elif command -v pacman >/dev/null 2>&1; then pm="pacman -S --noconfirm unzip"
  elif command -v zypper >/dev/null 2>&1; then pm="zypper install -y unzip"
  fi
  [ -n "$pm" ] || die "neither 'unzip' nor 'python3' found; install unzip and re-run"
  if [ "$(id -u)" = 0 ]; then
    step "Installing unzip"; $pm >/dev/null || die "could not install unzip ($pm)"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    step "Installing unzip (sudo)"; sudo -n $pm >/dev/null || die "could not install unzip (sudo $pm)"
  else
    die "'unzip' is required and sudo needs a password here. Run:  sudo $pm   then re-run this installer"
  fi
}
ensure_extractor

step "Resolving version"
if [ -n "${COCKPIT_VERSION:-}" ]; then
  VERSION="${COCKPIT_VERSION#v}"
else
  # Latest cockpit-server-v* tag (the repo has other release families).
  VERSION="$(curl -fsSL "$GH_API/releases?per_page=30" \
    | grep -o '"tag_name": *"cockpit-server-v[^"]*"' \
    | head -1 | sed 's/.*cockpit-server-v//; s/"//')"
  [ -n "$VERSION" ] || die "could not find a cockpit-server release on GitHub; set COCKPIT_VERSION=x.y.z"
fi
TAG="cockpit-server-v$VERSION"
ZIP="cockpit-server-$VERSION-linux-$ARCH.zip"
ok "cockpit-server $VERSION ($ARCH)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
step "Downloading $ZIP"
curl -fsSL --retry 3 -o "$TMP/$ZIP" "$GH_DL/$TAG/$ZIP" \
  || die "download failed: $GH_DL/$TAG/$ZIP"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$GH_DL/$TAG/SHA256SUMS" \
  || die "download failed: SHA256SUMS"
( cd "$TMP" && grep " $ZIP\$" SHA256SUMS | sha256sum -c --quiet ) \
  || die "checksum mismatch for $ZIP"
ok "checksum verified"

step "Installing"
extract_zip "$TMP/$ZIP" "$TMP" || die "could not extract $ZIP"
"$TMP/cockpit-server/install.sh" "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
