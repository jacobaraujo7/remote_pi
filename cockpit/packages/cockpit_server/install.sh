#!/usr/bin/env bash
#
# cockpit-server — installer shipped INSIDE the release zip
# ==========================================================
#
#   unzip cockpit-server-<version>-linux-<arch>.zip
#   ./cockpit-server/install.sh [--service]
#
# Installs this folder as ~/.cockpit/server, exactly where the Cockpit desktop
# client installs the server over SSH, so a host prepared by this script is
# indistinguishable from one prepared by the app (same bundle.manifest, same
# atomic swap). No sudo, no network, idempotent: same version already
# installed = no-op. Re-running with a newer zip = update.
#
# What it does:
#   1. Checks Linux + that `uname -m` matches the ARCH this zip was built for.
#   2. Verifies every file against bundle.manifest (sha256sum -c).
#   3. Stages a copy, swaps it into ~/.cockpit/server (previous install kept
#      as backup until the smoke test passes).
#   4. Smoke test: starts the server on a temp socket with --exit-on-idle 1
#      and waits for the socket. Failure restores the backup and shows the log
#      (this is where a glibc/arch mismatch shows up).
#   5. Symlinks ~/.local/bin/cockpit-server so `cockpit-server service …`
#      works from any shell (~/.local/bin is on PATH by default on most
#      distros once it exists).
#   6. --service: registers a systemd --user unit via
#      `cockpit-server service install` (may ask you to run one sudo command
#      for `loginctl enable-linger`). If a unit already exists, restarts it.
#
# This file is architecture-agnostic: the zip differs only in bin/ and lib/.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.cockpit/server"
WANT_SERVICE=0
for a in "$@"; do
  case "$a" in
    --service) WANT_SERVICE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
else
  BOLD=""; RED=""; GRN=""; YLW=""; RST=""
fi
step() { printf '%s\n' "${BOLD}==> $*${RST}"; }
ok()   { printf '%s\n' "    ${GRN}ok${RST} $*"; }
warn() { printf '%s\n' "    ${YLW}!${RST} $*"; }
die()  { printf '%s\n' "${RED}${BOLD}error:${RST} $*" >&2; exit 1; }

# ── 1. platform ──────────────────────────────────────────────────────────────
[ "$(uname -s)" = Linux ] || die "cockpit-server zips are Linux only (got $(uname -s))"
[ -f "$SRC/VERSION" ] || die "VERSION missing next to install.sh (not a release zip?)"
VERSION="$(sed -n '1p' "$SRC/VERSION" | tr -d '[:space:]')"
ARCH="$(sed -n '2p' "$SRC/VERSION" | tr -d '[:space:]')"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|amd64)  HOST_ARCH=x86_64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
esac
[ -n "$ARCH" ] || die "VERSION has no arch line"
[ "$ARCH" = "$HOST_ARCH" ] || die "this zip is for $ARCH but the host is $HOST_ARCH"
for tool in sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required"
done

# ── 2. integrity ─────────────────────────────────────────────────────────────
step "Verifying cockpit-server $VERSION ($ARCH)"
[ -f "$SRC/bundle.manifest" ] || die "bundle.manifest missing"
( cd "$SRC" && sha256sum -c --quiet bundle.manifest ) || die "checksum mismatch, zip is corrupt"
[ -x "$SRC/bin/cockpit-server" ] || chmod +x "$SRC/bin/cockpit-server"
[ -f "$SRC/lib/libcockpit_pty.so" ] || die "lib/libcockpit_pty.so missing"
ok "manifest matches"

# ── PATH: ~/.local/bin/cockpit-server → the installed binary ─────────────────
# Same convention as the Pi installer. The symlink points at the stable $DEST
# path, so it follows updates by itself. Runs on every invocation (also when
# the version is already installed): a host that lost the link or the PATH
# line gets them back without reinstalling.
ensure_path() {
  LINK_DIR="$HOME/.local/bin"
  mkdir -p "$LINK_DIR"
  ln -sfn "$DEST/bin/cockpit-server" "$LINK_DIR/cockpit-server"
  case ":$PATH:" in
    *":$LINK_DIR:"*) ok "cockpit-server is on PATH ($LINK_DIR)" ;;
    *)
      # Debian/Ubuntu only pick ~/.local/bin up at login when it already exists,
      # so a fresh host never has it in the current session. Add an idempotent
      # line to the shell rc files (same approach as rustup/uv); the running
      # shell still needs a reload.
      PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
      MARK='# added by cockpit-server installer'
      added=""
      for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [ -f "$rc" ] || continue
        grep -qF "$MARK" "$rc" && continue
        printf '\n%s\n%s\n' "$MARK" "$PATH_LINE" >> "$rc"
        added="$added $(basename "$rc")"
      done
      if [ -n "$added" ]; then
        ok "added $LINK_DIR to PATH in:$added"
      fi
      warn "PATH takes effect in a new shell: run  exec \$SHELL -l  (or: $PATH_LINE)"
      ;;
  esac
}

# ── 3. idempotence ───────────────────────────────────────────────────────────
if [ -f "$DEST/VERSION" ] && [ -f "$DEST/bundle.manifest" ] \
   && cmp -s "$DEST/bundle.manifest" "$SRC/bundle.manifest"; then
  ok "already installed at $DEST ($(sed -n '1p' "$DEST/VERSION"))"
  ensure_path
  if [ "$WANT_SERVICE" = 1 ]; then
    step "Registering systemd user service"
    "$DEST/bin/cockpit-server" service install
  fi
  exit 0
fi

# ── 4. stage + smoke + swap ──────────────────────────────────────────────────
step "Installing to $DEST"
mkdir -p "$HOME/.cockpit"
STAGE="$(mktemp -d "$HOME/.cockpit/server.stage.XXXXXX")"
BACKUP="$HOME/.cockpit/server.prev.$$"
LOG="$(mktemp)"
cleanup() { rm -rf "$STAGE"; rm -f "$LOG"; }
trap cleanup EXIT

# tar keeps permissions; the zip may have been extracted by tools that drop them.
( cd "$SRC" && tar cf - bin lib bundle.manifest VERSION install.sh ) | ( cd "$STAGE" && tar xf - )
chmod +x "$STAGE/bin/cockpit-server" "$STAGE/install.sh"
[ -f "$STAGE/bin/cockpit" ] && chmod +x "$STAGE/bin/cockpit"

SOCK="$(mktemp -u "${TMPDIR:-/tmp}/cockpit-server-smoke.XXXXXX.sock")"
COCKPIT_PTY_DYLIB="$STAGE/lib/libcockpit_pty.so" \
  "$STAGE/bin/cockpit-server" --socket "$SOCK" --exit-on-idle 1 >"$LOG" 2>&1 &
SMOKE_PID=$!
for _ in $(seq 1 40); do [ -S "$SOCK" ] && break; sleep 0.25; done
if [ ! -S "$SOCK" ]; then
  kill "$SMOKE_PID" 2>/dev/null || true
  echo "----- cockpit-server output -----" >&2
  cat "$LOG" >&2
  echo "---------------------------------" >&2
  die "cockpit-server did not start on this host (see output above; a glibc too old for this build is the usual cause)"
fi
wait "$SMOKE_PID" 2>/dev/null || true
rm -f "$SOCK"
ok "smoke test passed"

# The desktop client refuses to nest an install inside a stale one; mirror its
# swap: move the old folder aside, move the stage in, drop the old one.
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  mv "$DEST" "$BACKUP"
fi
if mv "$STAGE" "$DEST"; then
  rm -rf "$BACKUP"
else
  [ -e "$BACKUP" ] && mv "$BACKUP" "$DEST"
  die "could not move the new install into place"
fi
trap - EXIT; rm -f "$LOG"
ok "installed cockpit-server $VERSION at $DEST"
ensure_path

# ── 5. service ───────────────────────────────────────────────────────────────
UNIT="$HOME/.config/systemd/user/cockpit-server.service"
if [ "$WANT_SERVICE" = 1 ]; then
  step "Registering systemd user service"
  "$DEST/bin/cockpit-server" service install
elif [ -f "$UNIT" ] && command -v systemctl >/dev/null 2>&1; then
  step "Restarting existing service"
  systemctl --user restart cockpit-server.service && ok "service restarted" \
    || warn "could not restart cockpit-server.service; restart it by hand"
fi

echo
echo "${BOLD}Done.${RST} Next: in Cockpit, add this host under Remote hosts and open a workspace."
echo "The desktop client updates this install over SSH; from mobile, re-run this installer to update."
