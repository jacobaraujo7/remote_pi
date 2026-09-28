# Plano 66: Cockpit Telemetry

**Status:** implementado em 2026-09-23 (passos 1 a 11; 45 testes novos; analyze/clippy limpos). Pendente: E2E manual no app, passo 12 (remoto) adiado, badges nas abas de task/terminal
**Subprojetos:** `cockpit/` (app Flutter, crate `cli/`, `packages/cockpit_server`), `site/` (docs)
**Mockup aprovado:** [`mockups/66-telemetry.html`](./mockups/66-telemetry.html) (abrir no navegador; usa os tokens reais do `AppColors.dark`)

## Contexto

Hoje o agente que roda dentro do Cockpit só tem o terminal pra descobrir o que
aconteceu com o app que está depurando: `read-tab` devolve milhares de linhas
misturando log de framework, warning de lib, redraw de TUI e o erro que importa.
Isso gasta contexto, esconde o bug e faz o agente alucinar causa.

O Cockpit está numa posição que nenhuma outra ferramenta tem: ele **é o pai do
processo** (task ou terminal), **conhece o repo** (git, arquivo salvo agora),
**fala com o agente** (CLI interna + socket) e **sabe se o agente está no meio
de um turno** (status hooks). A telemetria vale pelo cruzamento dessas quatro
coisas, não pela coleta em si.

Este plano cria o **Telemetry**: os processos do workspace alimentam uma base
local estruturada; o humano vê os erros agrupados numa aba nova do painel
direito (ao lado de Files/Search/DB/Tasks) e abre cada caso numa aba do pane
central; o agente consulta a mesma base pela CLI (`cockpit telemetry ...`) em
vez de ler terminal. Produção continua no Sentry/Datadog: aqui é o **loop de
dev**.

## Decisões fechadas (na conversa de 2026-09-23)

| # | Decisão | Por quê |
|---|---|---|
| 1 | **Unidade é o `run`**: vida de um processo observado, chave estável `(cwd, comando)` ou `--name`. Task = run com nome e botões | "isso é novo?" precisa comparar runs do mesmo comando ao longo dos dias |
| 2 | **Task é telemetria por padrão** (o runner já é o pai do processo). `"telemetry": false` no `tasks.json` desliga por task | Zero atrito no caminho feliz; caso barulhento tem escape |
| 3 | **Terminal solto e Bash do agente entram pelo wrapper `cockpit telemetry <cmd>`**. Nenhuma captura automática de PTY, nenhuma detecção de processo em primeiro plano | Atribuição exata por construção; o Bash do Claude sai por pipe (fora do PTY), só o wrapper cobre esse caso; intenção explícita = sem badge surpresa |
| 4 | **Sem suporte a processo fora do Cockpit** | Escopo |
| 5 | **Base SQLite por workspace no cache global do Cockpit**, nunca na `.cockpit/` do repo. Fork/worktree = workspace próprio = base própria | Volátil, pode conter segredo, multi-root não tem "a" `.cockpit/`; runs de código diferente não devem se misturar |
| 6 | **Monorepo divide por coluna, não por base**: `project` (root multi-root resolvida pelo cwd), `source` (task/tab), `service` | A graça é ver front e back lado a lado |
| 7 | **stdout não tem padrão próprio**: linha crua entra com nível chutado; stack trace por runtime e **JSON Lines** entram estruturados. JSONL é o formato recomendado ao projeto e o que o agente usa pra sondas | Não inventar protocolo; todo ecossistema já emite JSON |
| 8 | **O app se comporta igual dentro e fora do Cockpit**: nada de gate por `COCKPIT=1`. Verbosidade em dev usa o knob do projeto (`LOG_LEVEL`, `kReleaseMode`), acionado via `env` da task. Sondas não vão pra commit (`probes` lista) | Env não chega no celular/container; acopla a dev tool; gera heisenbug |
| 9 | **UI = aba Telemetry no painel direito** (árvore projeto → run → casos) + **aba de caso no pane central**. Aba de task/terminal só ganha badge. Nenhum split dentro da aba de task | Simples, cross-project, nada de mexer na aba de task |
| 10 | **Triagem com dois estados + limpar**: Resolvido (volta como **regressão** se reaparecer), Ignorado (some da aba e da CLI por padrão), Limpar (apaga ocorrências, regras ficam). Estados por fingerprint, sobrevivem a runs; **a CLI respeita a triagem** | A triagem do humano define o que o agente vê; ruído diminui com o tempo |
| 11 | Warnings na mesma lista, filtráveis por chip; workspace de raiz única **achata** o nível de projeto | Igual à árvore de arquivos multi-root |
| 12 | Parser mora **no app (Dart)**, compartilhado por task, wrapper, VM Service e OTLP. O wrapper Rust é burro: bytes → linhas → socket | Uma implementação, uma tabela |
| 13 | UI em inglês (regra do cockpit), chaves nas três `i18n/*.i18n.json`. Saída da CLI em inglês, JSON de uma linha, sem tradução | Convenções vigentes |

## Fora de escopo

- Dashboards, métricas agregadas, alertas, retenção longa, nuvem, multiusuário
- Capturar processos que não passaram por task nem pelo wrapper
- SDK próprio em qualquer linguagem (um pacote Dart opcional de 50 linhas pra
  padronizar `postEvent` pode vir depois, não é requisito)
- Substituir Sentry/Datadog em produção

## Estrutura esperada

```
cockpit/
├── cli/src/
│   ├── telemetry.rs                 # wrapper: spawn (PTY aninhado ou pipes), stream de linhas, resumo
│   └── commands.rs                  # verbos de consulta/triagem (proxy pro socket, como `db`)
├── cli/text/
│   ├── telemetry_help.txt
│   └── skill.md                     # seção "Telemetry" (ver passo 11)
├── lib/app/cockpit/
│   ├── domain/
│   │   ├── entities/telemetry_{run,event,case}.dart   # FEITO (triagem vive em telemetry_case)
│   │   ├── contracts/telemetry_store.dart              # FEITO (query + write + triagem + marcas)
│   │   ├── contracts/telemetry_line_parser.dart        # FEITO (parser incremental por run)
│   │   └── contracts/telemetry_ingest.dart             # FEITO (sessão de run + registro de workspace)
│   ├── data/telemetry/
│   │   ├── telemetry_db.dart                       # FEITO: sqlite3 síncrono (DDL, FTS5, ring buffer, casos)
│   │   ├── sqlite_telemetry_store.dart             # FEITO: TelemetryStore hospedando o TelemetryDb num Isolate
│   │   ├── telemetry_codec.dart                    # FEITO: entidades ↔ mapas sendable
│   │   ├── line_parser/                            # FEITO: ansi, prefix_unwrap, frames, jsonl, telemetry_line_parser_impl
│   │   ├── fingerprint.dart                        # FEITO
│   │   ├── redaction.dart                          # FEITO
│   │   ├── telemetry_ingest_impl.dart              # FEITO: resolve workspace pelo cwd, sessão por run (chunks → linhas → lotes)
│   │   ├── telemetry_store_registry.dart           # FEITO: um store por workspace em <applicationSupport>/telemetry/
│   │   ├── vm_service_ingest.dart                  # passo 8
│   │   ├── otlp_receiver.dart                      # passo 9
│   │   └── http_proxy.dart                         # passo 10
│   └── ui/
│       ├── widgets/telemetry_panel.dart            # modo do painel direito
│       ├── widgets/telemetry_case_view.dart        # corpo da aba de caso
│       ├── session/telemetry_case_session.dart     # tipo de aba no pane central
│       └── viewmodels/telemetry_viewmodel.dart     # page-scoped, provido no cockpit_module
├── lib/app/cockpit/ui/viewmodels/cockpit_cli_handler.dart   # verbos `telemetry*`
├── packages/cockpit_server/lib/src/remote_server.dart        # passo 12 (ingest/store no host)
└── docs/telemetry.md

site/src/app/docs/cockpit/telemetry/                         # passo 11
```

## Contrato

### Run

```
run_id        ulid
key           "(cwd, comando)" normalizado, ou --name / nome da task
project       root multi-root resolvida pelo cwd (raiz única: nome do workspace)
source        {kind: task|wrapper, task_key?, pane_id?, pid}
started_at    ended_at?   exit_code?
```

Fronteiras: task = start/stop do runner; wrapper = spawn/exit do filho.
Restart da task = run novo com a mesma `key` (é isso que permite `--new` e regressão).

### Evento (tabela única, formato inspirado no LogRecord do OTel)

```
event_id, run_id, ts, stream (out|err|vm|otlp|proxy), severity (trace..fatal),
body, attrs (json), error {type, message, stack, file, line, frames[]},
fingerprint?, trace_id?, span_id?, request_id?, raw_line_offset?
```

- `raw_line_offset` = índice da linha no scrollback da aba (para "ver no terminal").
- Segredos são redigidos **na entrada** (`Authorization`, `Cookie`, `Set-Cookie`,
  campos `password|token|secret|apiKey`, JWT por regex). Nunca chegam na base.

### Parser (ordem fixa, por linha)

1. Strip ANSI; descartar o que estiver em alt-screen (CSI ?1049h ... ?1049l).
2. **Unwrap de prefixos** conhecidos: `flutter: `, `I/flutter ( 1234): `,
   `<svc> | ` (docker compose), `[0] ` (concurrently), timestamp ISO à esquerda.
   Extras vêm de `.cockpit/telemetry.json` (`unwrap: [regex]`).
3. **JSONL**: linha que é um objeto JSON vira evento. Apelidos:
   `level|severity|lvl` (aceita número do pino: 30=info, 40=warn, 50=error),
   `msg|message`, `time|ts|timestamp|@timestamp`, `err|error|exception|stack`,
   `service|name`, `trace_id|traceId`, `probe`. O resto vira `attrs`.
4. **Bloco de erro por runtime** (linhas consecutivas viram um evento):
   Dart (`#0  Fn (package:x/a.dart:87:22)`), Flutter (`══╡ EXCEPTION CAUGHT BY ... ╞══` até `════`),
   Node (`Error: ...` + `    at fn (/path:12:5)`), Python (`Traceback` até a linha da exceção),
   Rust (`thread 'main' panicked at src/x.rs:12:5`), Go (`panic:` + `goroutine`),
   test runners (`flutter test` `[E]`, jest `●`, pytest `FAILED`).
5. **Linha crua**: severidade por regex (`ERROR|FATAL|WARN|Exception|Unhandled|failed`), senão `info`.

Repetição suprimida pelo Flutter ("repetido N×") incrementa a contagem do último fingerprint.

### Fingerprint

`sha1(error.type + mensagem normalizada + primeiro frame do projeto (arquivo:linha))`

Normalização da mensagem: números, hex, UUID, ULID, caminhos absolutos e strings
entre aspas viram `*`. Frame "do projeto" = caminho sob uma root do workspace
(exclui `package:flutter`, `node_modules`, `dart:`, `node:`).

### Casos e triagem

Caso = fingerprint + `key` do run. Estado por fingerprint: `open | resolved | ignored`,
com `by (human|agent)`, `at`, `reason?`. Regras:

- `resolved` + nova ocorrência em run posterior ao `at` → volta `open` com flag `regression`.
- `ignored` nunca volta sozinho; `--include-ignored` mostra.
- `new` = fingerprint sem ocorrência em nenhum run anterior da mesma `key`.
- `clear` apaga eventos (de um caso, run ou projeto); não toca em triagem.

### Wrapper `cockpit telemetry <cmd>`

```
cockpit telemetry flutter run
cockpit telemetry --name api npm run dev
cockpit telemetry -q -- ./script
```

- Verbos reservados: `errors logs events runs show wait mark resolve ignore clear probes`.
  Primeiro argumento fora dessa lista = comando a executar. `--` força.
- stdin/stdout é TTY → filho roda num **PTY aninhado** (forkpty no POSIX, ConPTY
  no Windows): cores, teclas interativas (`r`/`R`/`q`), SIGWINCH e Ctrl-C
  preservados. Sem TTY (Bash do agente) → **pipes**, stdout e stderr separados.
- Bytes passam **intocados** pra saída do wrapper. Em paralelo: linhas em
  batches (≤ 64 KiB ou 100 ms) pro socket da CLI (`type:"cmd"`, verbo
  `telemetry-ingest`, envelope `{run_id, seq, stream, lines[]}`); `telemetry-open`
  no início (cwd, argv, name, pane_id, env de interesse) e `telemetry-close`
  no fim (exit code).
- Env injetado só no filho: `COCKPIT_RUN_ID`, `COCKPIT_PANE_ID` (já herdado),
  `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME=<name|comando>`,
  `OTEL_RESOURCE_ATTRIBUTES=cockpit.run=<id>,cockpit.project=<p>`.
- Exit code do filho é devolvido. Última linha (stderr, `-q` desliga):
  `telemetry: run r_42 · 3 errors · 12 warnings · cockpit telemetry errors --run r_42`
- Se o socket não existe (fora do Cockpit) o wrapper só executa o comando e avisa uma vez.

Dependências novas no crate (registrar no plano 37): `libc` (forkpty/termios) no
POSIX e `windows-sys` (ConPTY) no Windows. Manter o binário pequeno é requisito
(ele é empacotado duas vezes no macOS).

### CLI de consulta (via socket handler no app; JSON de uma linha, como `cockpit db`)

```
cockpit telemetry errors   [filtros]            # casos abertos, agrupados (default: --level error)
cockpit telemetry logs     [filtros] [--level]  # eventos não-erro
cockpit telemetry events   [filtros]            # tudo, cru
cockpit telemetry runs     [--project] [--key]
cockpit telemetry show <case|event|run|trace id> [--context 20]
cockpit telemetry wait     --fingerprint <id> --absent 30s | --route "POST /orders" [--timeout 60]
cockpit telemetry mark     start|end <nome>
cockpit telemetry resolve|ignore <id> [--reason "..."]
cockpit telemetry clear    --case <id> | --run <id> | --project <p>
cockpit telemetry probes   [--project]          # linhas do diff do working tree com campo "probe"
```

Filtros comuns: `--project --task --run --key --tab --level --since 10m
--since-edit --since-run --before <id> 5s --mark <nome> --new --include-ignored
--include-resolved --limit`.

Regras de saída: resumo antes de detalhe (contagens + ids estáveis `e_3f2a`,
`r_42`, `req_91c`); teto de 200 linhas/16 KiB por resposta com `truncated:true`
e dica do próximo comando; ordenação determinística; nunca corpo de request sem
`show`.

### `tasks.json` e `.cockpit/telemetry.json`

```jsonc
// tasks.json (existente) ganha:
{ "key": "api", "command": {...}, "telemetry": false }          // default true

// .cockpit/telemetry.json (novo, opcional, versionável)
{
  "unwrap": ["^api-1\\s*\\| "],
  "ignore": ["DeprecationWarning: The `punycode`"],            // vira triagem ignored automática
  "projectFrames": ["packages/"],                                 // extras além das roots
  "proxy": { "listen": 3100, "upstream": "http://127.0.0.1:3000" } // passo 10
}
```

## Passos e critérios de aceite

### 1. Domínio + parser

Entidades e contratos em `domain/`; parser puro em `data/telemetry/line_parser/`
com fixtures reais (saída de `flutter run` iOS/Android, `flutter test`, Next
dev, pino, structlog, cargo, go test, docker compose, concurrently).

**Aceite:** testes unitários cobrem strip ANSI, alt-screen, todos os unwraps,
apelidos JSONL (inclusive nível numérico do pino), cada bloco de erro por
runtime (Dart/Flutter/Node/Python/Rust/Go/test runners), "repetido N×",
fingerprint estável sob variação de ids/números/caminhos e diferente sob frame
diferente. `flutter analyze` limpo.

### 2. Store SQLite por workspace

`sqlite3` (pub) com conexão própria num Isolate dedicado (o `anaki_sqlite` tem slot global por dylib e serializaria com a aba de DB), arquivo em
`<cache do Cockpit>/telemetry/<workspaceId>.sqlite`. Schema `runs`, `events`,
`triage`, `marks`, índices por `(run_id, ts)`, `(fingerprint)`. FTS5 sobre
`body`/`attrs` se o build do sqlite embarcado tiver a extensão (verificar;
fallback `LIKE`). Ring buffer: teto por tamanho (default 256 MB) e idade
(default 7 dias), apagando runs inteiros mais antigos primeiro. Redação na
escrita.

**Aceite:** testes de inserção em lote (10k linhas < 1 s no Isolate), retenção,
regressão (`resolved` → nova ocorrência → `open + regression`), `new` por `key`,
redação de `Authorization`/JWT/`password` em `attrs` e `body`. Base nunca é
criada dentro de uma root do workspace.

### 3. Ingest de tasks (telemetria por padrão)

`task_ingest_bridge.dart` liga `PtyTaskRunner.output(taskId)` ao parser; start/stop
abrem/fecham run; `telemetry:false` no `tasks.json` desliga; env de task ganha
`COCKPIT_RUN_ID` e as `OTEL_*`. `raw_line_offset` é registrado pra cada evento.

**Aceite:** task `flutter run` real: exceção aparece como um caso com contagem,
`arquivo:linha` e fingerprint; `R` (restart) ou stop/start cria run novo com a
mesma `key`; segundo run marca `new` só para fingerprints inéditos; JSON
impresso pelo app (`print(jsonEncode(...))`, prefixo `flutter: `) vira evento com
`attrs`. Task com `telemetry:false` não gera run.

### 4. Wrapper `cockpit telemetry <cmd>` (crate Rust)

`telemetry.rs` per contrato acima: PTY aninhado com TTY, pipes sem TTY, stream
batched pro socket, env injection, exit code, resumo, `-q`, `--name`, `--`.
Handler `telemetry-open|ingest|close` no `cockpit_cli_handler.dart` e no
`remote_server.dart` (passo 12 completa o remoto).

**Aceite:** (a) numa aba do Cockpit, `cockpit telemetry flutter run` mostra
cores, aceita `r`/`q`, respeita resize e Ctrl-C, e o run aparece na aba
Telemetry com `source: wrapper`; (b) rodado pelo Bash do Claude,
`cockpit telemetry flutter test` registra o run, separa stderr, devolve exit 1
e imprime o resumo com o id; (c) `cockpit telemetry errors --run <id>` traz as
falhas de teste com `arquivo:linha`; (d) sem socket, o comando roda normalmente
e avisa uma vez; (e) tamanho do binário cresce < 300 KB por arquitetura.

### 5. CLI de consulta e triagem

Verbos, filtros e janelas do contrato, implementados no handler do app sobre o
store; `--since-edit` usa o último save do editor por projeto; `wait` faz
polling interno e devolve `{ok|hit, observed_runs, elapsed}`; `probes` roda
`git diff` do working tree e filtra linhas com `"probe"`/`'probe'`;
`telemetry_help.txt` documenta tudo.

**Aceite:** testes do handler pra cada verbo; resposta nunca excede o teto e
sempre traz `truncated` + próximo comando; `--include-ignored` é a única forma
de ver ignorados; `resolve` pelo agente registra `by: agent`; `wait --absent`
retorna `ok` só se houve pelo menos um run/ocorrência observável no período
(senão `inconclusive`).

### 6. Aba Telemetry + aba de caso (conforme mockup)

Painel direito ganha o modo Telemetry (ícone de pulso com contador de novos):
cabeçalho (runs ativos, tamanho da base, busca, chips Open/New/Resolved/Ignored/⚠),
árvore projeto → run (tag task|wrapper, spinner se vivo, `run #N`) → casos
(severidade, mensagem, `×N`, `arquivo:linha`, tags new/regression/resolved/ignored,
chip de blame, quick actions no hover). Clique abre `TelemetryCaseSession` no
pane central: cabeçalho (origem, tipo, mensagem, id, status, blame), ações
(abrir arquivo, ver no terminal, copiar `cockpit telemetry show <id>`, resolver,
ignorar, limpar), stats, seções Stack (frames do projeto clicáveis), Log
correlacionado (JSON mais próximo antes do erro no mesmo run), Ocorrências por
run, Contexto cru. Badges de erros abertos nas abas de task/terminal de origem e
na linha da task no painel de Tasks. Raiz única achata o nível de projeto.
Blame via `git blame` do working tree (chip "changed 4 min ago · uncommitted").

**Aceite:** widget tests da árvore (filtros, triagem, contadores) e da aba de
caso com `TranslationProvider`; "ver no terminal" foca a aba e rola até
`raw_line_offset` destacando a linha; abrir frame abre o arquivo na linha;
strings nas três `i18n/*.i18n.json` + `strings.g.dart` regenerado; layout
utilizável a 360 px de largura do painel; `flutter analyze` limpo. E2E manual
com o monorepo de exemplo do mockup (`app` + `backend`).

### 7. Push turn-aware pro agente

Fingerprint novo ou regressão num run cujo `pane_id` tem agente com status
hook: enfileira; quando `working` vira `false`, entrega **uma** mensagem
agregada via `send` ("telemetry: 2 new cases in run r_42 (app): e_3f2a ×14,
e_77b1 ×1 · cockpit telemetry errors --new"). Setting em Settings → General
(default on), com throttle (máx. 1 push/30 s por pane).

**Aceite:** com o agente no meio de um turno nada é enviado; ao terminar chega
uma única mensagem; setting off silencia; nunca envia pra pane sem agente.

### 8. Adaptador Dart VM Service (Flutter zero-code)

Detectar `A Dart VM Service ... is available at: <uri>` no stdout de um run
(task ou wrapper), conectar como cliente adicional (`vm_service`), assinar
`Stdout`, `Stderr`, `Logging`, `Extension` e `Isolate` (PauseException se
`pause-on-exceptions` estiver ligado, sem alterar) e converter em eventos
`stream: vm` com stack completa. Dedup: exceção que também saiu pelo stdout é
uma ocorrência só (mesmo fingerprint em janela de 500 ms).

**Aceite:** erro capturado só pelo VM Service (ex.: `runZonedGuarded` sem
print) aparece com stack; `dart:developer log()` vira evento com `attrs`; não
há duplicata da exceção impressa; desconexão do VM Service não derruba o run.

### 9. Receptor OTLP/HTTP (JSON, depois protobuf)

Servidor HTTP em `127.0.0.1:<porta efêmera>` por instância do app, rotas
`/v1/logs` e `/v1/traces` (JSON; protobuf via `protobuf` + protos vendorados,
segunda etapa). Resource attrs `cockpit.run` associam ao run (fallback:
`service.name` = `key`). Spans viram eventos `stream: otlp` com `trace_id`;
`show <trace_id>` devolve a árvore resumida (só spans com erro ou acima do p95
do próprio trace).

**Aceite:** app Node com `@opentelemetry/auto-instrumentations-node` e as env do
wrapper envia sem configurar nada; log JSON do backend com `trace_id` e o span
HTTP aparecem no mesmo `show`; porta não é fixa nem exposta fora do loopback.

### 10. Proxy HTTP local + marcas + replay

`http_proxy.dart` sobe quando `.cockpit/telemetry.json` tem `proxy`: captura
método, rota, status, duração, corpos (redigidos, teto 64 KB), injeta
`traceparent` e `x-request-id`, correlaciona com eventos do backend pelo
`request_id`. `mark start|end` delimita janelas; `replay --mark <nome>` reenvia
os requests da janela (só métodos e hosts do próprio proxy; confirmação se houver
método não idempotente).

**Aceite:** front → proxy → back: erro 500 aparece com o request que o causou;
`replay` reproduz a janela e o `wait --route` detecta o resultado; nenhum
`Authorization`/cookie aparece em `show`.

### 11. Skill, docs e changelog

Seção **Telemetry** no `cli/text/skill.md` (embutida via `install-skill`):
quando usar (se existe task use `run-task`; senão prefixe com
`cockpit telemetry`; nunca `read-tab` quando há run), o loop (run → resumo →
`errors --run` → fix → rerun ou `wait --absent`), receitas por stack pra o
logger emitir JSONL (Flutter/Dart `logging` + `FlutterError.onError` +
`PlatformDispatcher.onError`; Node pino; Python structlog; Rust
tracing-subscriber json; Go slog), formato canônico e apelidos, regra do
fingerprint (mensagem fixa, dado variável em campos), sondas com campo `probe`
e `probes` antes de commitar, triagem pela CLI, e a regra "não gate por
`COCKPIT_*`" (use `LOG_LEVEL`/`kReleaseMode` via `env` da task).
Docs humanas em `site/src/app/docs/cockpit/telemetry/` (o que é, aba, triagem,
wrapper, `telemetry.json`, proxy, privacidade/retenção) e `cockpit/docs/telemetry.md`
(arquitetura interna). Entrada no `CHANGELOG.md`.

**Aceite:** `cockpit install-skill` traz a seção; teste manual: agente numa aba
nova sem contexto prévio, pedido "roda os testes", usa o wrapper e consulta a
base em vez de ler a saída; `pnpm lint && pnpm build` no site.

### 12. Remoto (plano 58)

`cockpit_server` recebe `telemetry-open|ingest|close` no socket do host, roda o
mesmo parser (pacote compartilhado `cockpit_core`) e mantém a base no cache do
host; tasks remotas alimentam pelo `RemoteTaskRunner`; consultas e a aba
atravessam o canal existente. VM Service/OTLP/proxy remotos escutam no host.

**Aceite:** workspace remoto: task e wrapper geram casos na aba; triagem
persiste no host; base não é copiada pro desktop.

## Definition of Done

- [x] Parser com fixtures reais de Flutter/Dart/Node/Python/Rust/Go/test runners, JSONL e unwraps (passo 1)
- [x] Store SQLite por workspace com ring buffer, triagem, regressão e redação (passo 2)
- [x] Tasks alimentam telemetria por padrão; `telemetry:false` desliga; restart = run novo (passo 3)
- [x] `cockpit telemetry <cmd>` funciona em aba (PTY) e no Bash do agente (pipes), com resumo e exit code (passo 4; E2E manual no app pendente)
- [x] Verbos de consulta/triagem/janelas com teto de saída e ids estáveis; `wait`, `mark`, `probes` (passo 5)
- [x] Aba Telemetry + aba de caso conforme mockup, blame, i18n en/pt-BR/es (passo 6; pendente: badge na aba de task/terminal, "ver no terminal" hoje foca a aba da task sem rolar até a linha, widget tests)
- [x] Push agregado ao agente só com turno encerrado, com setting (passo 7; E2E manual pendente)
- [x] VM Service com dedup contra stdout (passo 8; dedup testado, conexão real ao `flutter run` pendente de E2E)
- [x] Receptor OTLP JSON em loopback com porta efêmera (passo 9; protobuf fora, responde 415)
- [x] Proxy HTTP com redação, marcas e replay (passo 10; `wait --route` incluso; E2E manual pendente)
- [x] Skill embutida, tutorial no Site (`/tutorials/cockpit-telemetry`), `cockpit/docs/telemetry.md` (passo 11). CHANGELOG entra na release (a primeira seção `##` tem que bater com a tag; ver `deploy-cockpit`)
- [ ] Remoto: ingest/store no host, aba e CLI funcionando (passo 12) **ADIADO**: parser/store vivem no app; precisam migrar pro `cockpit_core` antes. Painel só aparece em workspace local
- [x] Dependências novas (`sqlite3`, `sqlite3_flutter_libs`, `vm_service`, `libc`) registradas no plano 37 (`windows-sys`/ConPTY não entrou: Windows usa pipes)
- [ ] `flutter analyze`, `flutter test`, `cargo clippy` limpos (OK em 2026-09-23); E2E manual com o monorepo de exemplo PENDENTE (build do app com o novo código)

## Ordem sugerida de implementação

Não é faseamento de produto (a demanda é o conjunto), é só dependência técnica:
1 → 2 → 3 → 4 → 5 → 6 (já usável no dia a dia) → 7 → 8 → 11 → 9 → 10 → 12.
O passo 11 (skill) entra assim que 4 e 5 fecharem, porque sem ele o agente não
descobre a feature.

## Riscos e checagens

- **FTS5**: confirmado disponível no `sqlite3` (macOS, teste `fts=true`); fallback `LIKE` mantido pra builds sem a extensão.
- **PTY aninhado no Windows (ConPTY)**: NÃO implementado; no Windows o wrapper
  usa pipes mesmo com TTY (captura ok, perde cores/teclas interativas). Task
  não é afetada.
- **Volume**: dev server verboso pode gerar milhares de linhas/s; o batch no
  wrapper e o Isolate do store existem por isso; medir no passo 2/4.
- **Ruído estruturado é pior que ruído cru**: o parser deve ser conservador;
  quando não tiver certeza, linha crua `info`.
- **Duplicidade stdout × VM Service × OTLP** do mesmo erro: dedup por
  fingerprint + janela, testado no passo 8/9.

## Próximos planos (futuro, fora deste)

- Pacote Dart opcional `cockpit_telemetry` (eventos custom via `postEvent`)
- Sondas ao vivo sem editar código (logpoints via CDP/VM Service)
- Painel de trace waterfall completo
- "Run as task" a partir de um terminal com comando reconhecido
