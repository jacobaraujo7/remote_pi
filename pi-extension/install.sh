#!/usr/bin/env bash
#
# Remote Pi — zero-to-running bootstrap installer
# ================================================
#
#   curl -fsSL https://remote-pi.jacobmoura.work/install.sh | bash
#
# What it does (all user-space, NO sudo, idempotent):
#   1. Node      — uses the system Node if it's >= 22.19.0; otherwise installs
#                  it via nvm under ~/.nvm (never touches the system Node).
#   2. Pi        — installs the Pi coding agent (npm package
#                  @earendil-works/pi-coding-agent) into a user-space prefix
#                  (~/.local) so `pi` lands on ~/.local/bin without root.
#   3. remote-pi — installs this plugin into Pi (`pi install npm:@hk_net/remote-pi`).
#   4. CLI link  — symlinks the `remote-pi` CLI into ~/.local/bin.
#   5. Supervisor— installs the per-user service (launchd GUI agent on macOS,
#                  `systemd --user` on Linux) via `remote-pi install`.
#   6. Stops.    — does NOT pair. Prints the next step (pair your phone).
#
# OS support: macOS and native Linux. Windows is asked to use WSL and exits
# cleanly. Re-running is a no-op once everything is in place.
#
# Trust: this script is plain, readable, and asks for no privileges. Read it
# before piping it to bash — same etiquette as nvm / rustup.
#
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

MIN_NODE="22.19.0"              # Pi 0.84.3 requires Node >= 22.19.0
MIN_PI="0.84.3"                  # Remote Pi's minimum host peer version
NODE_LTS="22"                   # what we install via nvm when Node is missing
PI_PKG="@earendil-works/pi-coding-agent"
PI_SPEC="${PI_PKG}@latest"
PLUGIN_PACKAGE="@hk_net/remote-pi"
PLUGIN_SPEC="npm:${PLUGIN_PACKAGE}"
PLUGIN_NAME="remote-pi"
USER_PREFIX="$HOME/.local"      # user-space npm global prefix (sudo-free)
LOCAL_BIN="$USER_PREFIX/bin"

# Resolved at runtime by ensure_plugin() — `pi install npm:@hk_net/remote-pi` runs
# `npm install -g`, so the plugin lands under `npm root -g`, NOT in
# ~/.pi/agent/npm. We can't hardcode it: it depends on the effective npm
# prefix (nvm dir, ~/.local, a user .npmrc, …). Always ask `npm root -g`.
PLUGIN_DIST=""

# ── Pretty output ────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

step()  { printf '%s\n' "${BLU}${BOLD}==>${RST} ${BOLD}$*${RST}"; }
info()  { printf '%s\n' "    $*"; }
ok()    { printf '%s\n' "    ${GRN}✓${RST} $*"; }
warn()  { printf '%s\n' "    ${YLW}!${RST} $*"; }
die()   { printf '%s\n' "${RED}${BOLD}error:${RST} $*" >&2; exit 1; }

# Versions we actually installed/found, printed in the summary at the end.
SUMMARY=()
record() { SUMMARY+=("$1"); }

# ── 0. OS detection ──────────────────────────────────────────────────────────

detect_os() {
  # Windows shells (Git Bash / MSYS / Cygwin) report MINGW*/MSYS*/CYGWIN*.
  case "${OS:-}" in Windows_NT) echo "windows"; return ;; esac
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin)                 echo "macos" ;;
    Linux)                  echo "linux" ;;   # WSL reports Linux — fully supported
    MINGW*|MSYS*|CYGWIN*)   echo "windows" ;;
    *)                      echo "unknown" ;;
  esac
}

OS="$(detect_os)"

if [ "$OS" = "windows" ]; then
  cat <<EOF
${BOLD}Remote Pi${RST} doesn't run natively on Windows.

Please use ${BOLD}WSL${RST} (Windows Subsystem for Linux) and re-run this
installer inside your WSL shell — it's treated as Linux and works the same:

  ${DIM}# in PowerShell, one time:${RST}
  wsl --install

  ${DIM}# then, inside the WSL (Ubuntu) shell:${RST}
  curl -fsSL https://remote-pi.jacobmoura.work/install.sh | bash

EOF
  exit 0
fi

if [ "$OS" = "unknown" ]; then
  die "unsupported platform '$(uname -s 2>/dev/null)'. Only macOS and Linux are supported."
fi

printf '%s\n' "${BOLD}Remote Pi installer${RST} ${DIM}(${OS}, user-space, no sudo)${RST}"
echo

# ── helpers ──────────────────────────────────────────────────────────────────

# Return 0 if $1 (semver) >= $2 (semver).
version_gte() {
  [ "$1" = "$2" ] && return 0
  # smallest of the two equals $2  ⇒  $1 >= $2
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

ensure_local_bin_on_path() {
  mkdir -p "$LOCAL_BIN"
  case ":$PATH:" in
    *":$LOCAL_BIN:"*) : ;;                  # already there
    *) export PATH="$LOCAL_BIN:$PATH" ;;    # for the rest of this run
  esac
}

# Resolve the global node_modules root that `npm install -g` (and therefore
# `pi install npm:…`) writes to, honoring the effective npm config. We point
# it at our user-space prefix by default so global installs stay sudo-free —
# but whatever prefix actually wins, pi and this script read the SAME config,
# so they can never disagree on where the plugin lands.
npm_global_root() { npm root -g 2>/dev/null; }

# Whether the active Node is provided by nvm (we installed it, or the user
# already had an nvm Node on PATH). Set by ensure_node(). This gates whether
# we may touch npm_config_prefix at all — see configure_npm_prefix().
NODE_FROM_NVM=0

# GOLDEN RULE: never export npm_config_prefix while nvm is (or might be) in
# play — nvm flat-out refuses to run with that env var set and aborts. So we
# decide the prefix AFTER Node is settled, and only for the system-Node case:
#
#   • nvm Node      → its global root (`npm root -g`) is already user-writable.
#                     Leave npm_config_prefix UNSET (setting it breaks nvm).
#   • system Node   → if `npm root -g` isn't writable without sudo, redirect
#                     global installs into ~/.local via npm_config_prefix.
#
# Either way resolve_plugin_dist() finds the plugin via `npm root -g`, since
# pi and this script read the same effective npm config.
configure_npm_prefix() {
  if [ "$NODE_FROM_NVM" = "1" ]; then
    unset npm_config_prefix 2>/dev/null || true   # must stay unset for nvm Node
    return 0
  fi
  # System Node: is the global node_modules root writable without sudo?
  local groot gparent
  groot="$(npm_global_root)"
  [ -n "$groot" ] || return 0
  gparent="$(dirname "$groot")"
  while [ -n "$gparent" ] && [ ! -e "$gparent" ]; do gparent="$(dirname "$gparent")"; done
  if [ -n "$gparent" ] && [ ! -w "$gparent" ]; then
    info "system npm global root '$groot' is not writable — redirecting global installs to $USER_PREFIX (sudo-free)"
    export npm_config_prefix="$USER_PREFIX"
  fi
}

# Append an `export PATH` line to the user's shell rc (idempotent) so the bins
# survive a new shell. We never rewrite existing lines — only add if missing.
persist_path_in_rc() {
  case ":$PATH:" in *":$LOCAL_BIN:"*) : ;; *) return 0 ;; esac
  local rc=""
  case "${SHELL:-}" in
    */zsh)  rc="$HOME/.zshrc" ;;
    */bash) rc="$HOME/.bashrc" ;;
    *)      rc="$HOME/.profile" ;;
  esac
  [ -n "$rc" ] || return 0
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if [ -f "$rc" ] && grep -qF '.local/bin' "$rc"; then
    return 0
  fi
  {
    printf '\n# Added by Remote Pi installer\n%s\n' "$line"
  } >> "$rc"
  warn "added ~/.local/bin to PATH in $rc — open a new shell or 'source $rc'"
}

# ── 1. Node ──────────────────────────────────────────────────────────────────

ensure_node() {
  step "Checking Node.js (need >= $MIN_NODE)"

  if command -v node >/dev/null 2>&1; then
    local have; have="$(node -v 2>/dev/null | sed 's/^v//')"
    if [ -n "$have" ] && version_gte "$have" "$MIN_NODE"; then
      # Classify by path: an nvm Node lives under ~/.nvm, even if it was
      # already on PATH when we started.
      case "$(command -v node)" in
        "$HOME/.nvm/"*) NODE_FROM_NVM=1; ok "using existing nvm Node v$have"; record "Node:       v$have (nvm)" ;;
        *)              NODE_FROM_NVM=0; ok "using system Node v$have";       record "Node:       v$have (system)" ;;
      esac
      return 0
    fi
    warn "system Node v${have:-?} is older than $MIN_NODE — installing a private one via nvm"
  else
    info "no Node found — installing a private one via nvm (user-space)"
  fi

  install_node_via_nvm
}

install_node_via_nvm() {
  # nvm is INCOMPATIBLE with npm_config_prefix and aborts if it's set (whether
  # we set it or the user's environment did). Clear it before any nvm call.
  unset npm_config_prefix 2>/dev/null || true
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    info "installing nvm into $NVM_DIR"
    # Pinned, well-known nvm installer. Runs entirely in $HOME, no sudo.
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null
  else
    info "nvm already present in $NVM_DIR"
  fi

  # shellcheck disable=SC1091
  \. "$NVM_DIR/nvm.sh"

  if ! nvm ls "$NODE_LTS" >/dev/null 2>&1; then
    info "installing Node $NODE_LTS via nvm"
    nvm install "$NODE_LTS" >/dev/null
  fi
  nvm use "$NODE_LTS" >/dev/null

  command -v node >/dev/null 2>&1 || die "nvm install finished but 'node' is still not on PATH"
  local have; have="$(node -v | sed 's/^v//')"
  version_gte "$have" "$MIN_NODE" || die "installed Node v$have is still < $MIN_NODE"
  NODE_FROM_NVM=1
  ok "installed Node v$have via nvm"
  record "Node:       v$have (nvm)"
}

# ── 2. Pi coding agent ───────────────────────────────────────────────────────

ensure_pi() {
  step "Installing the Pi coding agent"

  if command -v pi >/dev/null 2>&1; then
    local v; v="$(pi --version 2>/dev/null | head -n1 || true)"
    if [ -n "$v" ] && version_gte "$v" "$MIN_PI"; then
      ok "Pi already installed (${v}) — skipping"
      record "Pi:         ${v} (pre-existing)"
      return 0
    fi
    warn "Pi ${v:-version unknown} is below the required $MIN_PI — upgrading"
  fi

  # Guard the no-sudo promise: the global node_modules root must be writable.
  # On a clean box (nvm Node, or ~/.local prefix) it is. If it points at a
  # root-owned dir (e.g. system Node's /usr/local), fail with a clear hint
  # instead of triggering an EACCES / sudo prompt mid-install.
  local groot; groot="$(npm_global_root)"
  if [ -n "$groot" ]; then
    local gparent; gparent="$(dirname "$groot")"   # …/lib  (created on first install)
    while [ -n "$gparent" ] && [ ! -e "$gparent" ]; do gparent="$(dirname "$gparent")"; done
    if [ -n "$gparent" ] && [ ! -w "$gparent" ]; then
      die "npm global prefix '$groot' is not writable without sudo.
    This installer never uses sudo. Fix it user-space, then re-run:
      npm config set prefix \"\$HOME/.local\"
    (or install Node via nvm, which uses a writable prefix automatically)."
    fi
  fi

  # User-space global install: --prefix keeps `pi` in ~/.local/bin, no sudo.
  info "npm install -g --prefix $USER_PREFIX $PI_SPEC"
  npm install -g --prefix "$USER_PREFIX" "$PI_SPEC" >/dev/null

  command -v pi >/dev/null 2>&1 || die "Pi installed but 'pi' is not on PATH (expected $LOCAL_BIN/pi)"
  local v; v="$(pi --version 2>/dev/null | head -n1 || true)"
  [ -n "$v" ] && version_gte "$v" "$MIN_PI" \
    || die "installed Pi ${v:-version unknown} is still < $MIN_PI"
  ok "installed Pi (${v})"
  record "Pi:         ${v} (${PI_PKG})"
}

# ── 3. remote-pi plugin ──────────────────────────────────────────────────────

# Locate the plugin's compiled entry. Pi's install path CHANGED across versions:
#   • Pi >= 0.78 (@earendil-works): installs into ~/.pi/agent/npm/node_modules/
#   • Pi  = 0.73 (@mariozechner):   ran `npm install -g` → lands in `npm root -g`
# We check both, current-behavior first, and use whichever exists. Sets the
# global PLUGIN_DIST. Returns 1 if neither is found.
plugin_dist_candidates() {
  printf '%s\n' "$HOME/.pi/agent/npm/node_modules/$PLUGIN_PACKAGE/dist/index.js"
  local root; root="$(npm_global_root)"
  [ -n "$root" ] && printf '%s\n' "$root/$PLUGIN_PACKAGE/dist/index.js"
}

resolve_plugin_dist() {
  local cand
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    if [ -f "$cand" ]; then PLUGIN_DIST="$cand"; return 0; fi
  done < <(plugin_dist_candidates)
  return 1
}

ensure_plugin() {
  step "Installing the remote-pi plugin into Pi"

  if resolve_plugin_dist; then
    ok "plugin already installed ($(dirname "$(dirname "$PLUGIN_DIST")")) — skipping"
    record "Plugin:     remote-pi (pre-existing)"
    return 0
  fi

  info "pi install $PLUGIN_SPEC"
  pi install "$PLUGIN_SPEC" >/dev/null

  # Pi may install into ~/.pi/agent/npm (>= 0.78) or `npm root -g` (0.73).
  # resolve_plugin_dist() checks both — never a single hardcoded path.
  if ! resolve_plugin_dist; then
    die "plugin install ran but $PLUGIN_PACKAGE/dist/index.js was not found.
    Looked in:
      $HOME/.pi/agent/npm/node_modules/$PLUGIN_PACKAGE/dist/index.js
      $(npm_global_root)/$PLUGIN_PACKAGE/dist/index.js
    Check the 'pi install $PLUGIN_SPEC' output above."
  fi
  local pkg_json; pkg_json="$(dirname "$(dirname "$PLUGIN_DIST")")/package.json"
  local v; v="$(node -p "require('$pkg_json').version" 2>/dev/null || true)"
  ok "installed remote-pi plugin${v:+ v$v} → $PLUGIN_DIST"
  record "Plugin:     remote-pi${v:+ v$v}"
}

# ── 4. Link the remote-pi CLI into ~/.local/bin ──────────────────────────────
#
# `pi install npm:@hk_net/remote-pi` makes the slash command available inside Pi, but it
# does NOT put the `remote-pi` CLI on $PATH. We symlink it ourselves (the same
# thing `/remote-pi install` does from inside Pi's TUI, which we can't run from a
# headless installer).

link_cli() {
  step "Linking the remote-pi CLI into $LOCAL_BIN"
  mkdir -p "$LOCAL_BIN"
  local target="$PLUGIN_DIST"
  local link="$LOCAL_BIN/$PLUGIN_NAME"

  chmod +x "$target" 2>/dev/null || true   # tsc strips the +x bit; shebang is present

  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    ok "symlink already points at the plugin — skipping"
  else
    ln -sf "$target" "$link"
    ok "symlinked $link → $target"
  fi
  record "CLI:        $link"
}

# ── 5. Supervisor (per-user service) ─────────────────────────────────────────
#
# `remote-pi install` writes a launchd GUI agent (macOS) or `systemd --user`
# unit (Linux) and activates it. It's idempotent (re-running refreshes the
# unit) and never asks for sudo — it only touches per-user paths.

install_supervisor() {
  step "Installing the user supervisor service ($OS)"
  # Run via the CLI we just linked. PATH already includes ~/.local/bin.
  if remote-pi install; then
    ok "supervisor installed and activated"
    record "Supervisor: installed (${OS})"
  else
    warn "supervisor install reported an error — see the output above"
    warn "you can re-run it any time with:  remote-pi install"
    record "Supervisor: FAILED — re-run 'remote-pi install'"
  fi
}

# ── 6. Next steps (no pairing) ───────────────────────────────────────────────

print_next_steps() {
  echo
  printf '%s\n' "${GRN}${BOLD}Remote Pi is installed.${RST} Here's what's on disk:"
  echo
  local entry
  for entry in "${SUMMARY[@]}"; do
    printf '    %s\n' "$entry"
  done
  echo
  printf '%s\n' "${BOLD}Next step — pair your phone:${RST}"
  cat <<EOF

    1. Install the ${BOLD}Remote Pi${RST} app on your phone.
    2. In any terminal, open Pi and start Remote Pi:

         ${BOLD}pi${RST}
         ${BOLD}/remote-pi${RST}

       (the first run shows a short wizard, then prints a QR code)
    3. Scan the QR with the app to pair.

    Manage the always-on daemon later with ${BOLD}remote-pi${RST} (now on your PATH).
    Docs: ${DIM}https://remote-pi.jacobmoura.work${RST}

EOF
  case ":$PATH:" in
    *":$LOCAL_BIN:"*) : ;;
    *) warn "Open a new shell (or 'source' your shell rc) so 'pi' and 'remote-pi' are on PATH." ;;
  esac
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  ensure_local_bin_on_path
  ensure_node            # may use nvm — must run BEFORE we touch npm_config_prefix
  configure_npm_prefix   # only sets npm_config_prefix for the system-Node case
  ensure_pi
  ensure_plugin
  link_cli
  install_supervisor
  persist_path_in_rc
  print_next_steps
}

main "$@"
