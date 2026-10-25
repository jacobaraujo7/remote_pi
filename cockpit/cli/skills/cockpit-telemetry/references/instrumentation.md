# Make the project speak telemetry

### Make the project speak telemetry (permanent instrumentation)

One rule: **the project's logger emits JSON Lines to stdout**. No SDK.

| Stack | Recipe |
|---|---|
| Flutter / Dart | `logging` package with a listener doing `print(jsonEncode({...}))`; also `FlutterError.onError` and `PlatformDispatcher.instance.onError` printing `{"level":"error","msg":..., "err":{"type":..., "message":..., "stack":...}}` |
| Node / TS | `pino` (JSON by default) or `console.log(JSON.stringify({...}))` |
| Python | `structlog` with `JSONRenderer`, or `python-json-logger` |
| Rust | `tracing-subscriber` with `.json()` |
| Go | `slog.NewJSONHandler(os.Stdout, nil)` |

Canonical shape (aliases accepted: `severity`/`lvl`, `message`, `ts`/`timestamp`,
`error`/`stack`; pino's numeric levels work):

```json
{"level":"error","msg":"cart add failed","err":{"type":"RangeError","message":"index 3 of 2","stack":"#0 ..."},"itemId":"abc","total":42}
```

**Write messages that group well**: keep `msg` fixed and put variable data in
fields. `"msg":"order failed","orderId":"91c"` is one case; `"msg":"order 91c
failed"` becomes one case per order.

Do **not** gate logs on `COCKPIT_*` env vars: the app must behave the same
inside and outside Cockpit (the vars never reach a phone or a container
anyway). Control verbosity with the project's own knob (`LOG_LEVEL`,
`kReleaseMode`), set per task via `env` in `.cockpit/tasks.json`.

### Temporary probes while investigating

Sprinkle JSON prints with a `probe` field, e.g.
`print(jsonEncode({'probe':'cart','items':cart.length}))`, then filter with
`cockpit telemetry logs --probe cart`. **Never commit a probe**:
`cockpit telemetry probes` lists added lines in the working tree that still
carry one; remove them before committing.

### Per-task opt-out and config

`"telemetry": false` on a task in `.cockpit/tasks.json` keeps that task out.
`.cockpit/telemetry.json` (optional, versioned) can add `unwrap` regexes for
odd log prefixes and `ignore` patterns.
