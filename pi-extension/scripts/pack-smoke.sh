#!/usr/bin/env bash
# Verify the artifact, not just the source tree. Requires a Pi binary on PATH.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# CI can point this at a globally installed latest Pi; otherwise use the
# ordinary PATH lookup. This avoids pnpm's local dev fixture shadowing it.
pi_bin="${REMOTE_PI_PI_BIN:-pi}"
command -v "$pi_bin" >/dev/null || {
  echo "pack smoke requires Pi on PATH (or REMOTE_PI_PI_BIN)" >&2
  exit 1
}

scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT
mkdir -p "$scratch/pack" "$scratch/extract" "$scratch/home" "$scratch/work"

npm pack --pack-destination "$scratch/pack" --json > "$scratch/pack.json"
tarball="$(node - "$scratch/pack.json" "$scratch/pack" <<'NODE'
const result = require(process.argv[2]);
const metadata = Array.isArray(result)
  ? result[0]
  : result["remote-pi"] ?? Object.values(result)[0];
if (!metadata?.filename) throw new Error("npm pack did not return a tarball filename");
process.stdout.write(`${process.argv[3]}/${metadata.filename}`);
NODE
)"
tar -xzf "$tarball" -C "$scratch/extract"
pkg="$scratch/extract/package"

# This simulates Pi's production install, which omits dev dependencies. Audit
# the unpacked tree too: workspace overrides do not accompany an npm tarball.
(
  cd "$pkg"
  npm install --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null
  npm audit --omit=dev
)

node - "$pkg/package.json" <<'NODE'
const pkg = require(process.argv[2]);
if (pkg.main !== "dist/extension.js" || pkg.types !== "dist/extension.d.ts") {
  throw new Error("package root must expose the Pi extension entry");
}
if (!pkg.pi?.extensions?.includes("./dist/extension.js")) {
  throw new Error("Pi manifest must load dist/extension.js");
}
for (const name of [
  "@earendil-works/pi-coding-agent",
  "@earendil-works/pi-tui",
  "typebox",
]) {
  if (!pkg.peerDependencies?.[name] || pkg.peerDependenciesMeta?.[name]?.optional !== true) {
    throw new Error(`missing optional Pi peer: ${name}`);
  }
}
NODE

for peer in '@earendil-works/pi-coding-agent' '@earendil-works/pi-tui' typebox; do
  test ! -e "$pkg/node_modules/$peer" || {
    echo "production install unexpectedly bundled peer $peer" >&2
    exit 1
  }
done

# The standalone entry and supervisor must work without the Pi peers installed
# beneath the packed package.
node "$pkg/dist/index.js" >/dev/null
node "$pkg/dist/bin/supervisord.js" --version | grep -q '^pi-supervisord (remote-pi)$'

run_pi_smoke() {
  local target="$1" output="$2" status
  set +e
  HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data" \
    node "$root/scripts/run-with-timeout.mjs" 60 "$pi_bin" -e "$target" -p '/remote-pi status' > "$output" 2>&1
  status=$?
  set -e
  [ "$status" -eq 0 ] || {
    cat "$output" >&2
    return "$status"
  }
  ! grep -q 'Extension error\|Cannot find package\|Remote Pi extension runtime was not configured' "$output"
}

# Cover both the package manifest path and the raw -e path used by the supervisor.
run_pi_smoke "$pkg" "$scratch/pi-package.out"
run_pi_smoke "$pkg/dist/extension.js" "$scratch/pi-raw-extension.out"

version="$(node -p "require('$pkg/package.json').version")"
set +e
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"pack-smoke","version":"1.0.0"}}}' \
  | HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data" \
    node "$root/scripts/run-with-timeout.mjs" 12 node "$pkg/dist/mcp/mesh_server.js" --cwd "$scratch/work" --no-bridge \
    > "$scratch/mcp.out" 2> "$scratch/mcp.err"
mcp_status=$?
set -e
[ "$mcp_status" -eq 0 ] || [ "$mcp_status" -eq 124 ] || exit "$mcp_status"
grep -Fq "\"version\":\"$version\"" "$scratch/mcp.out"

echo "packed artifact smoke test passed (remote-pi@$version)"
