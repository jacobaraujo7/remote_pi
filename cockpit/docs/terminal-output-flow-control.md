# Terminal output flow control

## Failure mode

Before this design, output pressure scaled with the number of terminals rather
than with the amount of UI time available. Each interactive terminal owned a
per-terminal frame callback and could pass a 128 KiB batch to its VT parser.
Task terminals bypassed that path completely: they acknowledged each native
read after placing it on an asynchronous Dart stream, before the terminal had
parsed the data.

With several workspaces, task runners and agent terminals, one frame could
therefore contain `terminal count × 128 KiB` of synchronous parsing, model
mutation and render invalidation on Flutter's main isolate. The event queue also
contained task-output deliveries and production `debugPrint` work. Flutter was
still running, but pointer events could not reach application code until that
queue drained. This explains both parts of the observed behavior: the window
froze without a crash, and recovered as soon as producers became quiet.

Host measurements during an incident showed Cockpit as the main CPU consumer
at roughly 22%, with about 353 MiB resident and about 14 GiB still available.
The application was not being killed, swapping heavily or exhausting its
scrollback limits. The binding resource was serialized UI-isolate time.

## Invariants

All local interactive and task PTYs share `PtyOutputScheduler.shared`.

- A 64 Ki UTF-16 code-unit budget is shared by VT parsers in one frame across
  the whole application, not per terminal. Preserving a surrogate pair can
  exceed the remaining budget by one code unit.
- Processing stops after 4 ms of measured synchronous work in that frame.
- One parser call is at most 4 Ki code units (plus the same possible one-unit
  Unicode correction), bounding the unavoidable overrun of a non-preemptible
  parser call.
- Ready terminals advance round-robin, so a single noisy producer cannot
  starve the rest.
- Each source has a 16 Ki high-water mark and an 8 Ki low-water mark. Above the
  high-water mark, native reads stop being acknowledged. Below the low-water
  mark, one acknowledgement resumes the producer.
- ANSI sequences may cross slices because both terminal engines parse streams
  incrementally. UTF-16 surrogate pairs are never split.
- Normal operation does not discard output. If the consumer cannot keep up,
  backpressure propagates through the PTY or ConPTY pipe to the child process.

The time budget includes terminal parsing, task progress matching and task
scrollback capture. Task output uses a synchronous broadcast only inside the
scheduler callback; it no longer moves expensive work to an unbounded event
queue after the native read has already been acknowledged.

## Presentation work

Workspace and tab `IndexedStack`s intentionally keep session state alive, but
they used to keep every terminal render object and every agent transcript
listener alive too. Hidden models would request layout, paint and Markdown
rebuilds even though their pixels could not be shown.

Inactive terminals now detach only their rendering surface. Their process, VT
model, controller, scrollback and enclosing widget state remain alive. Parsing
continues under the global budget, while invisible grids cannot schedule layout
or paint. Reopening a tab reconnects the view to the current model.

Inactive agent transcripts and tab labels in hidden workspaces stop listening
to their sessions. Agent token deltas still update the model, but visible
sessions notify at most once per frame. Hidden sessions do not request frames.
Assistant and thinking text use `StringBuffer` plus a cached snapshot, avoiding
quadratic immutable string copies and repeated Markdown snapshots for long
responses.

## Other sustained-output costs

- Agent JSONL buffering appends chunk tails without repeatedly copying the
  complete partial line.
- Full RPC lines and LSP stderr lines are logged only in debug builds. Release
  builds do not feed Flutter's throttled `debugPrint` queue per token or line.
- Terminal and task scrollback persistence uses a quiet-period debouncer with
  at most one live timer per source, instead of canceling and allocating a timer
  for every output batch.
- Scrollback remains bounded independently of flow control: xterm retains at
  most 10,000 lines, Ghostty retains 10 MiB, interactive replay records retain
  about 2.5 MiB, and task replay records retain 256 KiB.

## Native flow control

Windows already models an acknowledgement as a one-slot semaphore. Unix used
a `pthread_mutex_t` as if it were a semaphore: the native read thread locked it
and the Dart FFI thread unlocked it. POSIX requires a mutex to be unlocked by
its owner, so that behavior was undefined and could differ between Linux and
macOS.

The Unix implementation now uses an owner-correct mutex, condition variable and
one-bit permit. The read thread consumes the permit; the acknowledging thread
publishes the next permit while holding the mutex and signals the condition.
Native worker threads are detached and their option allocations are released.
Windows closes its temporary thread handles and releases the equivalent option
allocations without changing ConPTY's semaphore protocol.

The Dart scheduler and buffering code has no OS or CPU-architecture branch. The
native boundary uses POSIX primitives on Linux and macOS and Win32 primitives
on Windows, covering the release matrix: Linux x64/arm64, macOS x64/arm64, and
Windows x64.

## Regression coverage

The scheduler tests cover aggregate budget enforcement, 32 simultaneously
noisy sources, round-robin fairness, time-budget exhaustion, high/low-water
backpressure, exact Unicode preservation, safe disposal and drain completion.
Widget tests verify that hidden presentations detach listeners while their
models continue to advance, and that inactive agent listeners do not rebuild.
Additional tests cover agent append snapshots, JSONL chunk boundaries and the
low-churn persistence debouncer.

The constants above are deliberately centralized in
`lib/app/core/terminal/pty_output_scheduler.dart`. If profiling on a supported
target warrants tuning, change the aggregate time budget or slice size there;
do not reintroduce per-terminal scheduling or acknowledge output before its
synchronous consumer has completed.
