# Synthetic terminal profile benchmark

From `cockpit/`, run:

```powershell
flutter run --profile -d windows -t benchmark/terminal_profile.dart
```

For a controlled four-way comparison, set `BENCH_RENDER_GATE` and
`BENCH_SCAN_THROTTLE` to `false` for the baseline, then enable each separately,
then both. The environment variables are read at runtime so one profile build
can be reused. `BENCH_RESULT_FILE` writes the JSON to a chosen temporary file
when launching the built Windows executable directly. `BENCH_SWITCH_MS`,
`BENCH_OUTPUT_MS`, and `BENCH_DURATION_MS` adjust the synthetic workload.
`BENCH_HIDDEN_FRAMES=true` restores the previous frame scheduling for output
only in hidden tabs. `BENCH_VISIBLE_OUTPUT=false` sends output only to the nine
hidden tabs at any moment, while tab switching continues.

The standalone entrypoint runs for 30 seconds and prints one `terminal_profile`
JSON line. It creates ten in-memory Ghostty/flterm controllers and sends the
same fixed ANSI output to each every 50 ms. All ten `TerminalView` widgets stay
mounted under a shared `TerminalScope`; one is presented while the others use
the production `Offstage`, `TickerMode`, and `presentationActive` settings. The
benchmark switches tabs every 500 ms by default. The normal app bootstrap, stored terminal
profiles, native PTYs, and installed user data are not used.

`frameP95Us`, `frameMaxUs`, and `jankFrames` come from Flutter's engine frame
timings. Jank means a total frame time over 16,667 microseconds. The
`buildP95Us` and `rasterP95Us` fields separate UI and GPU work from total
frame latency. Tab switch durations run from the state change to the next
post-frame callback. PTY pending
values are the aggregate scheduler queue, not a native PTY pipe. `rssBytes` is
the benchmark process's resident memory at the end. `syntheticProcessScans`
counts calls to a provider with a fixed 20 ms delay, allowing a controlled
comparison of monitor scheduling; it does not measure real Windows CIM cost.

Use the same device, window size, Flutter version, and workload when comparing
two revisions. Profile builds on physical desktop hardware are necessary for
meaningful frame timings; widget tests do not provide comparable raster times.

## Earlier Windows profile result (old flterm tag `891b2af`)

The synthetic workload used ten mounted terminal views, nine receiving output
while hidden, 20 ms output batches, 5 s tab switching, and a 15 s duration.
The fake process provider took 20 ms per scan. `BENCH_VISIBLE_OUTPUT=false`
was set for this workload. Each run parsed all generated characters and ended
with zero characters pending in the PTY scheduler.

| Flags | Jank frames (>16.67 ms) | Process scans |
| --- | ---: | ---: |
| Render gate off, scan throttle off, hidden frames on | 88, 103, 106 | 488, 489, 486 |
| Render gate on only | 84 | 488 |
| Scan throttle on only | 99 | 16 |
| Both on, hidden frames on | 109 | 16 |
| Both on, hidden frames off (normal operation) | 2, 3, 3 | 16 |

The median reduction in jank frames for this hidden-output workload was from
103 to 3 (97%). Most of that difference comes from avoiding Flutter frame
requests when every queued PTY belongs to a hidden tab. The render gate alone
had a smaller and noisy effect on total frame timings. This result does not
predict the same reduction when the selected tab is also receiving heavy
output; earlier visible-output runs had variable frame timings. The measured
tab-switch p95 stayed around 24–32 ms in the repeated baseline and combined
runs. These timings depend on window scheduling and should be rechecked on
other desktop hardware.

After rebasing onto `origin/main` at `a8217149`, the final Windows profile
build succeeded. In a 15 s hidden-output run with process throttling enabled
on both sides, the main-equivalent flags (`renderGate=false`,
`hiddenFrames=true`) produced 64 jank frames and the final flags
(`renderGate=true`, `hiddenFrames=false`) produced 4, a 94% reduction.
Both runs made 16 fake process scans, parsed every generated character, and
finished with zero PTY characters pending. Tab-switch p95 was 26.3 ms and
27.6 ms respectively. These are A/B flags in the final binary that emulate
the relevant rendering and scheduler behavior; they are not a separate build
of the exact `main` source tree.

When the selected tab also received output, results varied widely even in
alternating 10 s runs: main-equivalent flags yielded 114, 6, and 47 jank
frames; final flags yielded 102, 108, and 6. No stable improvement or
regression can be inferred for that workload from this local benchmark.

## Windows profile after rebasing onto main `89ecf2bd`

The final binary uses flterm/libghostty tag `735e10d`, with the presentation
patch ported onto that flterm version. With ten mounted terminals, 20 ms output
batches, 5 s tab switching, a 15 s run, and the 20 ms fake process provider,
the repeated hidden-output comparison was:

| Flags | Jank frames (>16.67 ms) | Frames produced | Scans |
| --- | ---: | ---: | ---: |
| Main-equivalent presentation (`renderGate=false`, `hiddenFrames=true`) | 9, 13 | 386, 394 | 16 each |
| Final presentation (`renderGate=true`, `hiddenFrames=false`) | 2, 1 | 5, 5 | 16 each |

Process throttling was enabled in both variants because current main already
has an activity cooldown. The jank reduction was 78% and 92% in the paired
runs. Every generated character was parsed, the PTY queue ended empty, and
acknowledgements continued. Tab-switch p95 varied from 20.9–37.5 ms in the
main-equivalent runs to 34.2–39.1 ms in the final runs; this sample does not
establish a tab-switch latency improvement.

In one run with output also sent to the visible tab, jank was 17 frames for
main-equivalent flags and 3 for final flags, with all output parsed. Earlier
visible-output runs on the older flterm tag varied widely, so this single
run does not establish a general visible-output gain. The A/B flags emulate
the relevant rendering and scheduler behavior in one final binary; they are
not separate builds of the exact main source tree.

For this local Windows build, Zig's native-asset hook could not execute its
Unicode generator through the long worktree path. The same pinned native
source compiled sequentially through a short temporary path; that ignored
DLL was supplied to the hook cache for the profile build. The temporary build
files are not part of the PR.
