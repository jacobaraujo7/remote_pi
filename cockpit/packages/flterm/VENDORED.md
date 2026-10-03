This package is copied from `jacobaraujo7/libghostty` at the immutable
`cockpit-pin-flterm-upstream-2026-10` tag (commit `735e10d`). Its original license is
in `LICENSE`. The native `libghostty` package remains pinned to that tag in
`cockpit/pubspec.yaml`.

Local change: `TerminalView.presentationActive` keeps a hidden view attached
while suppressing renderer invalidations. Reactivation forces one full layout
and paint. Keep this patch when updating the package or remove the local copy
once the upstream package exposes equivalent behavior.
