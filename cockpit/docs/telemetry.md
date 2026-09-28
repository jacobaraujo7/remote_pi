# Telemetry (plano 66): arquitetura interna

Base local, por workspace, do que os processos do workspace imprimem. O humano
vê casos agrupados na aba Telemetry (painel direito) e abre cada um numa aba do
pane central; o agente consulta a mesma base via `cockpit telemetry ...`.
Produção continua no Sentry/Datadog: isto é o loop de dev.

## Unidade: o run

`run` = a vida de um processo observado. Chave estável `(cwd, comando)` ou
`--name`/nome da task (`name:<label>`), o que permite comparar runs do mesmo
comando ao longo dos dias (é daí que saem `new` e `regressão`).

| Origem | Como entra | `source` |
|---|---|---|
| Task (`.cockpit/tasks.json`) | `PtyTaskRunner` abre a sessão antes do spawn, alimenta cada chunk, fecha com o exit code. Default ligado; `"telemetry": false` desliga | `task` |
| Terminal solto / Bash do agente | wrapper `cockpit telemetry <cmd>` (crate `cli/`, `telemetry.rs`): PTY aninhado com TTY, pipes sem TTY; manda linhas em lotes via socket (`telemetry-open/ingest/close`) | `wrapper` |
| Proxy HTTP | `.cockpit/telemetry.json` com `proxy` → run `name:proxy` por workspace | `wrapper` |

Nada é capturado automaticamente de terminais: a intenção é explícita (decisão
3 do plano). O Bash do Claude sai por pipe, fora do PTY, por isso o wrapper é a
única cobertura desse caso.

## Camadas

```
domain/
  entities/telemetry_{run,event,case}.dart      run, evento (LogRecord-like), caso + triagem
  contracts/telemetry_store.dart                 TelemetryStore, TelemetryStoreProvider, TelemetryQuery
  contracts/telemetry_line_parser.dart           parser incremental por run + config
  contracts/telemetry_ingest.dart                sessão de run, registro de workspace, notices, replay
data/telemetry/
  line_parser/{ansi,prefix_unwrap,frames,jsonl,telemetry_line_parser_impl}.dart
  fingerprint.dart  redaction.dart  telemetry_codec.dart
  telemetry_db.dart                              sqlite3 síncrono (DDL, FTS5, ring buffer, casos)
  sqlite_telemetry_store.dart                    TelemetryStore hospedando o TelemetryDb num Isolate
  telemetry_store_registry.dart                  um store por workspace em <applicationSupport>/telemetry/
  telemetry_ingest_impl.dart                     resolve workspace pelo cwd, sessão (chunks → linhas → lotes), dedup, OTLP sink, proxy
  vm_service_ingest.dart                         Dart VM Service (Logging, Flutter.Error, PauseException)
  otlp_receiver.dart                             OTLP/HTTP JSON em loopback, porta efêmera
  http_proxy.dart                                proxy local + replay
  telemetry_workspace_config.dart                .cockpit/telemetry.json
ui/
  widgets/telemetry_panel.dart                   modo do painel direito
  widgets/telemetry_case_view.dart               corpo da aba de caso
  session/telemetry_case_session.dart            aba (não persiste no layout)
  viewmodels/telemetry_viewmodel.dart            page-scoped; poll 2 s enquanto visível; blame
  viewmodels/telemetry_cli_handler.dart          verbos telemetry-* da CLI
```

## Parser (ordem fixa por linha)

1. Strip ANSI; tudo em alt-screen (`?1049h..l`) é descartado.
2. Unwrap de prefixos: `flutter: `, logcat, docker compose `svc | `, concurrently
   `[0] `, timestamps; extras do `telemetry.json` (`unwrap`).
3. JSON Lines: apelidos `level|severity|lvl` (níveis numéricos do pino),
   `msg|message`, `time|ts|timestamp`, `err|error|stack`, `service|name`,
   `trace_id`, `reqId`; o resto vira `attrs`.
4. Blocos de erro por runtime (Flutter `EXCEPTION CAUGHT`, `Another exception`,
   Dart `Unhandled exception`, Node, Python, Rust, Go, `flutter test [E]`, jest,
   pytest). Um bloco vira UM evento com `error{type,message,stack,frames}`.
5. Linha crua com severidade chutada (sem falso positivo em `0 errors`).

Conservador de propósito: ruído estruturado é pior que ruído cru.

## Fingerprint e casos

`sha1(type + mensagem normalizada + primeiro frame do projeto)`. A
normalização troca por `*` uuid/ulid, caminhos absolutos, strings entre aspas e
qualquer token com dígito. Caso = fingerprint dentro de uma chave de run.

Triagem por fingerprint (`open|resolved|ignored`, por humano ou agente):
`resolved` que reaparece depois da triagem volta `open` com `regression`;
`ignored` some da aba e da CLI (salvo `--include-ignored`); `clear` apaga
eventos, não regras. `new` = só aparece no run mais recente da chave.

## Base

`<applicationSupport>/telemetry/<workspaceId>.sqlite` (cache local, nunca no
repo, não segue o override de storage). WAL, FTS5 com fallback `LIKE`. Redação
de segredos na escrita (`Authorization`, cookies, `password|token|secret|apiKey`,
JWT, `Bearer`). Retenção: 256 MB / 7 dias, apagando runs encerrados mais
antigos primeiro (`vacuum`).

## Dedup stdout × VM Service × OTLP

A sessão guarda `fingerprint → última vez visto`; um erro com o mesmo
fingerprint dentro de 1,5 s conta uma vez (o `Flutter.Error` do VM Service é o
mesmo bloco que sai no console).

## Erros do próprio app (plano 68)

O Cockpit é também uma fonte: um run por boot (`source: app`, nome
"Cockpit"), num store fixo (`__cockpit__`, fora dos workspaces). O
`DiagnosticsLog` espelha nele o que os handlers globais capturam
(`FlutterError.onError`, `PlatformDispatcher.onError`, zona, isolates) e os
`warn` que os fallbacks do código passaram a emitir no lugar do antigo
`catch (_) {}` mudo. Frames `package:cockpit/` viram `lib/...` e são "do
projeto": fingerprint e location apontam pro nosso código.

Ligado só com **Settings → General → Developer mode** (desligado por
padrão: serve a quem mantém o app). Consulta: chip **Cockpit** no painel
Telemetry, ou `cockpit telemetry errors --app` (`--app` vale pra qualquer
verbo). Sem envio para fora.

## Métricas de performance (dev, opt-in)

`PerformanceDiagnostics` (`core/data/diagnostics/`) liga junto com o
**Developer mode** (ou por `COCKPIT_PERF=1`, alias legado
`COCKPIT_PERF_DIAGNOSTICS=1`, para quem sobe pelo terminal) em qualquer SO e
grava, no run do app, eventos `info` com `metric` + campos numéricos (só
enums fechados: nenhum path, comando ou output). Desligada por padrão por
decisão: sem Datadog, o número só serve a quem lê, e quem lê é o dono na
própria máquina.

| Métrica | Campos | Como |
|---|---|---|
| `frame` | frames, jankFrames (> 16,7 ms), p95Us, maxUs | resumo por janela de 30 s |
| `slowFrame` | durationUs, buildUs, rasterUs | cada frame ≥ 50 ms |
| `eventLoop` | delayUs | watchdog de 1 s |
| `memory` | rssBytes | a cada 1 s (throttle) |
| `pty` | durationUs, pending, sources | drain do scheduler |
| `processScan` | durationUs, sessions | monitor de harness |
| `gitRefresh` | durationUs, active, queued, failed | painel SC |
| `boot` | durationUs | `start()` → workspace pronto |
| `restore` | durationUs, tabs | por workspace restaurado |
| `workspaceSwitch` / `tabSwitch` | durationUs | até o próximo frame pintado |
| `spawn` | durationUs, failed | `Process.start` do shell (exec, painéis) |

`cockpit telemetry perf [--run r_xx] [--metric m]` agrega P50/P95/máx por
campo. Baseline oficial: medido no `.dmg` instalado (nunca em `debug`, o JIT
distorce), registrado no plano 68.

## Push turn-aware (REMOVIDO em 2026-09-27)

O push da linha "telemetry: N new cases" no terminal do agente ao fim do
turno foi removido: o agente consulta a base quando quer.


`TelemetryIngest.notices` emite os fingerprints de erro de cada lote gravado.
O `CockpitViewModel` filtra os novos/regressões, enfileira por pane (wrapper:
o pane do run; task: os terminais do workspace com agente) e entrega UMA linha
quando o agente não está `working` (status hooks), com throttle de 30 s por
pane. Setting `telemetryPush` (General → "Notify agents about new errors").

## CLI

Ver `cli/text/telemetry_help.txt` e a seção Telemetry de `cli/text/skill.md`.
Saída JSON de uma linha, ids estáveis (`e_` caso, `ev_` evento, `r_` run),
teto de 16 KiB com `truncated` + `hint`.

## O que ainda não existe

- Remoto (plano 58): ingest/store no host via `cockpit-server` (o parser e o
  store precisam migrar pro `cockpit_core` antes).
- OTLP protobuf (só JSON hoje).
- Badge de erros na linha da task e na aba do terminal de origem.
- Sondas ao vivo (logpoints via CDP/VM Service) e waterfall de trace.
