# Linux performance profiling

Cockpit's performance telemetry is disabled by default and records only fixed
metric names and numeric values. Enable it for a profile or release run:

```bash
COCKPIT_PERF_DIAGNOSTICS=1 flutter run -d linux --profile
```

The existing diagnostics log receives bounded `[linux-perf]` JSON batches every
30 seconds. Capture a Flutter DevTools CPU/allocation/timeline trace while using
the following deterministic workload:

1. Restore or create 32–40 terminal tabs across at least four Cockpit workspaces.
2. In eight visible/hidden terminals run
   `yes cockpit-perf | head -c 268435456`; keep agent shells in the others.
3. Open 12 synthetic Git repositories under a temporary directory and add them
   as workspaces. Do not use repositories containing user work.
4. Alternate Cockpit workspace selection and Hyprland workspace selection 100
   times while a Flutter release build and normal agent workload run.
5. Record Cockpit CPU/RSS separately from its child processes, and retain
   `journalctl` GPU messages plus `coredumpctl list cockpit` after the run.

Run the deterministic scheduler load before and after runtime changes:

```bash
flutter test test/performance/linux_terminal_stress_test.dart
```

For the production GPU matrix, use Intel/Wayland by default, then compare
`COCKPIT_USE_NVIDIA=1` and `GDK_BACKEND=x11` independently. Never change the
global Hyprland/Omarchy environment for this comparison.

The acceptance soak is 60 minutes: no freeze/core/GPU allocation failure, p99
input/workspace response below 150 ms, no event-loop stall above 500 ms, bounded
PTY queues, and less than 10% retained-RSS growth after the switch cycle.
