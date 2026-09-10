# Linux performance review — 2026-09-09

## Environment

- Arch/Omarchy 4.0.3, kernel 7.2.3, Hyprland 0.56.2 on Wayland.
- Intel i5-9300H (4C/8T), 31 GiB RAM, 62 GiB combined zram/swap, NVMe.
- Intel UHD 630 plus NVIDIA GTX 1650 Max-Q, NVIDIA 610.57.04.
- Restored Cockpit state: 31 layouts, 47 tabs, 35 terminal sessions and 12
  project records. State/scrollback size is small and is not a disk-capacity
  bottleneck.

## Confirmed findings

1. `TerminalHarnessMonitor` recursively inspected every registered terminal's
   `/proc` tree every 250 ms. With many agents and nested build processes this
   is persistent CPU and filesystem work on the UI application's schedule.
2. The three-second Git poll refreshed its selected targets while its worktree
   callback independently reconciled every open root. Each Git status read can
   spawn several commands, producing periodic CPU/I/O process bursts.
3. Inactive terminal surfaces were already detached, and PTY output already had
   global frame budgeting/backpressure. However, harness observation ignored
   visibility and the tab strip scheduled overflow work after every parent
   rebuild.
4. Scrollback was bounded, but trimming converted and copied up to 2.5 million
   UTF-16 code units on the UI isolate.
5. The graphical session exports NVIDIA vendor/offload variables globally even
   though Cockpit's installed launcher describes Intel as the default. Recent
   debug cores terminate in `libnvidia-eglcore.so`; another release core is in
   Flutter's GTK loop with an NVIDIA EGL thread. The journal also records NVRM
   heap/channel allocation failures while system memory pressure was low.
6. Older window-manager shutdown cores correspond to a guard already fixed in
   the current source and are separate from the current freeze path.

## Implemented mitigations

- Adaptive, single-flight harness observation: immediate event bursts, 2 s
  visible safety polling, 5 s hidden/idle polling and 10 s inactive-window
  polling. Terminal processes remain alive.
- Globally bounded Git refresh scheduler (two jobs), per-project coalescing with
  one rerun, selected-project priority, and one staggered inactive worktree root
  per tick.
- Visibility signaling from mounted terminal bodies and layout-driven tab-strip
  overflow measurement.
- Chunked scrollback retention without full-buffer copies during trimming.
- Native pre-GTK hybrid-GPU policy: integrated graphics by default, inherited
  NVIDIA variables removed process-locally, and `COCKPIT_USE_NVIDIA=1` opt-in.
- Opt-in fixed-schema performance telemetry and a deterministic 40-terminal PTY
  scheduler workload.

## Validation status

- Focused affected suite: 39 tests passed.
- Linux release bundle: built successfully.
- Changed production Dart files: analyzer clean.
- Full repository suite: 1,245 tests reached; eight unrelated/environmental
  failures remain (xterm golden pixel differences, headless IME injection,
  platform-dependent window-menu expectations, plus the Git coalescing
  regression found during the run). The Git regression was fixed afterward and
  its complete test files pass.
- Repository-wide `flutter analyze lib linux` retains 55 pre-existing
  warning/info diagnostics; none originate in the new performance code.
- The 60-minute interactive GPU/UI soak remains a release-candidate validation
  step because safely exercising Hyprland presentation requires a real desktop
  session and must not silently resume the user's saved agents/cloud commands.
