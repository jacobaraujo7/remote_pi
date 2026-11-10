# Cockpit telemetry error triage — 2026-11-10

Base: 2.1.24 (`25af4cd9`). Owner: Codex. This work does not authorize merge, installation or a release.

## Behavior delivered

Text writes owned by Cockpit share a serialized service. Only the specific clipboard-opening error is retried (50 ms, then 150 ms; three attempts total). A newer request supersedes old pending writes/retries. Failure returns false, emits sanitized diagnostics and localized window feedback, and never announces copy success. A whole-line cut waits for a successful write and preserves the document if copying fails or the editor/controller changes. Clipboard reads and binary formats are unchanged.

Scrollback pruning catches asynchronous filesystem errors per directory, preserving other projects, kept sessions and non-cache files. A Windows reproduction showed that a 290-character file could be written/read while enumerating its 279-character directory failed with errno 3. Applying the extended Windows path prefix only during enumeration fixed the failing regression. Cache IDs, filenames and format remain unchanged; symlinks are not followed.

## Eight-case register

| Case | Status | Evidence and next step | Owner |
| --- | --- | --- | --- |
| Clipboard opening error | Corrected and validated by automated tests | Success, limited retry, exhaustion/recovery, concurrent/superseded requests, localized feedback/disposal, and non-destructive cut tested. Native acceptance recorded separately below. | Codex |
| Slow PowerShell spawn | Investigation pending | Forty identical probes completed; no spawn exceeded two seconds. Instrumentation now correlates operation, spawn, first output and completion without command/argument/environment content. Capture a recurrence under the original workload before choosing an optimization. | Codex |
| Null-to-bool pane layout | Historical, not reproduced | Current nullable field retained. Cold widget layouts cover active changes, resizing, preview and tab movement; existing lease/history preservation tests pass. Hot reload remains an unconfirmed hypothesis. | Codex |
| Neovim after dispose | Published protection validated by automated tests | Existing successful and failed late-completion tests pass; no duplicate implementation. Native rapid-close acceptance remains separate. | Codex |
| Missing scrollback directory | Corrected and validated | Deterministic removal/access failures and a real Windows long-path regression pass; cache format preserved. The original event has no stack, so its exact trigger is not claimed proven. | Codex |
| Alt key assertion | Historical, not reproduced | Balanced synthetic Windows Alt/Tab across focus changes passes. This is not proof for real hardware input or the old inconsistent modifiers payload. | Codex + operator for real keyboard |
| Process scan parse failure | Historical, original input unavailable | Current PowerShell detail path remains reachable. Empty/single/list/invalid responses, process failures, native PID retention and cache retry are covered. Invalid JSON remains a diagnosable warning, not a fabricated agent identity. | Codex |
| HTTP GET on CLI socket | Published rejection behavior validated | Actual loopback test rejects HTTP and accepts a following authenticated JSON command on the same listener. HTTP support is not added. Original connection source remains unknown. | Codex |

## Validation

- Windows, Flutter 3.47.2 / Dart 3.13.2.
- Eleven targeted suites: **80 tests passed** in 24 seconds. Includes seven shell metrics tests, delayed inherited-pipe output, eight filesystem cache cases, Neovim and pane lifecycle, process parsing and CLI protocol.
- Changed/new Dart files: analysis passed with no issues.
- Independent static review found two P2 issues (controller lifetime during asynchronous cut and late first-output metric); both fixed and covered by regressions. Final review found no additional actionable issues.
- Benchmark: 20 sequential operations and 20 in batches of four; same harmless command and PowerShell profile. Flutter test/debug evidence, not a Release performance claim.

| Phase | Spawn p50/p95 | First output p50/p95 | Completion p50/p95 |
| --- | --- | --- | --- |
| Sequential | 5.194 / 37.453 ms | 236.680 / 392.854 ms | 256.519 / 420.600 ms |
| Concurrent (4) | 18.453 / 58.144 ms | 370.546 / 418.884 ms | 394.612 / 450.080 ms |

All 40 commands completed, with 120 correlated phase events and no spawn above two seconds. This does not establish a cause for the historical 2–13 second warnings.

Local artifacts are kept in `build/`: `telemetry-regressions-final.log`, `telemetry-analyze.log`, `spawn-metrics-tests.log`, `spawn-benchmark.log`, and `benchmarks/shell-spawn.json`. The first native build failed before tests because the Zig generator's raw path exceeded the Windows process path limit; an identical checkout exposed via a temporary short drive allowed the tests to run without dependency changes.

## PR ownership and delivery

Direct repository PR inventory was refreshed before implementation. No open PR by the implementing user was found. Related open PRs [#267](https://github.com/jacobaraujo7/remote_pi/pull/267) and [#309](https://github.com/jacobaraujo7/remote_pi/pull/309) remain with pretodev; [#257](https://github.com/jacobaraujo7/remote_pi/pull/257) remains with cfbraun. Disposition: continue with their authors; no blocking dependency or delivered coverage of these new fixes is assumed. Existing Neovim protection from merged [#272](https://github.com/jacobaraujo7/remote_pi/pull/272) is reused. This personal repository requires no BTN.

Clipboard/cache corrections and spawn instrumentation are delivered as independent changes targeting main. No PR is closed as superseded. CI, Release build and GUI acceptance are reported only when actually observed; a short error-free window is not sufficient to resolve historical cases.
