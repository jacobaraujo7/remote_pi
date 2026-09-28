# 68 — Cockpit: erros do próprio app na Telemetria e métricas de performance (opt-in)

## Contexto

Auditoria de 2026-09-27 (sessão solo no pane Cockpit):

- Os handlers globais de erro (`core/data/diagnostics/error_handlers.dart`:
  `FlutterError.onError`, `PlatformDispatcher.onError`, zona, isolates) gravam
  no `DiagnosticsLog` (arquivo em disco). A Telemetria (plano 66) **nunca vê**.
  Os seis casos resolvidos em 2026-09-27 só apareceram porque o app rodava
  como task do `flutter run` e a saída foi parseada. No `.dmg` instalado o
  mesmo erro cai no `.log` e ninguém consulta.
- `lib/` tem 137 `catch (_) {`, 17 deles `catch (_) {}` vazios, e 117
  `catch (e)` que não logam, não devolvem `Failure` nem `rethrow`. A maioria é
  legítima e comentada (peer sumiu, preferência ilegível, kill em processo
  morto). Os vazios e alguns que mascaram falha real (`pty_task_runner:114`
  spawn falhou vira `exitCode -1` mudo; `cockpit_viewmodel:869/922` leitura
  remota falhou vira árvore vazia/"unsupported"; `cli_handler:1462-1473`
  fallback dentro de fallback) precisam ao menos avisar.
- Já existe `LinuxPerformanceDiagnostics` (frame, event loop, memória, PTY,
  scan de processos, refresh do git), só Linux, atrás de
  `COCKPIT_PERF_DIAGNOSTICS=1`, gravando JSON no `DiagnosticsLog`.

Decisões fechadas em conversa:

| # | Decisão |
|---|---|
| A | Erros e warnings do **próprio app** entram na Telemetria como um run sintético por boot (`source: app`, nome "Cockpit"), local e sem envio externo. **Atrás de Settings → General → Developer mode, desligado por padrão** (decisão de 2026-09-27: só serve a quem mantém o app; o cenário "Cockpit de produção rodando o de debug como task" já cobre o resto) |
| B | `catch (_) {}` vazio fica proibido: ou comenta o motivo do descarte ou chama `DiagnosticsLog.warn`. Lint `avoid_catches_without_on_clauses` ligado como `warning` |
| C | Métricas de performance ligam junto com o **Developer mode** (ou `COCKPIT_PERF=1` para quem sobe pelo terminal). **Desligadas em produção**: sem envio para fora, o número só serve a quem consegue lê-lo, e quem lê é o dono na própria máquina. Baseline medido no `.dmg` instalado com a env ligada (nunca em `debug`, o JIT distorce) |
| D | Métricas são estritamente numéricas e enums fechados (regra herdada do diagnóstico Linux): nada de path, comando ou output |
| E | Agregação em memória (contadores/histograma por janela de 1 min) e flush assíncrono fora do callback de frame; nunca gravar no meio do frame |

## Estrutura esperada

```
cockpit/lib/app/
├── core/data/diagnostics/
│   ├── diagnostics_log.dart              # + warn(tag, message, {error, stack}) + sink de telemetria
│   ├── error_handlers.dart               # inalterado (grava no log; o log espelha na telemetria)
│   ├── performance_diagnostics.dart      # renomeado de linux_performance_diagnostics.dart, 3 SOs
│   └── perf_metric.dart                  # enum PerfMetric/PerfField (ex LinuxPerfMetric/LinuxPerfField)
├── cockpit/domain/contracts/telemetry_ingest.dart   # + openAppRun() / TelemetryRunSource.app
└── cockpit/data/telemetry/telemetry_ingest_impl.dart
```

## Passos

1. **Run sintético do app.** `TelemetryIngest.openAppRun({version, build, os})` cria um run `source: app` no store global (não por workspace: o app não tem cwd), aberto no boot depois do ingest subir e fechado no `dispose`/sinal. O `DiagnosticsLog` ganha um sink opcional: `logError` vira evento `error` (type = classe da exceção, location = primeiro frame `package:cockpit`), `warn` vira `warn`, `log` vira `info` (só quando o run existe; antes disso segue só o arquivo).
   Aceite: matar o app com `Cmd+Q` e reabrir mostra o run "Cockpit" na aba Telemetry; provocar um `FlutterError` (widget de teste em debug) gera caso com fingerprint por location; `cockpit telemetry errors` lista.

2. **`DiagnosticsLog.warn`.** Assinatura `warn(String tag, String message, {Object? error, StackTrace? stack})`. Trocar os 17 `catch (_) {}` vazios por `warn` ou comentário; revisar os três pontos nomeados no contexto (task spawn, leitura remota, fallback da CLI) para emitir `warn` com o motivo (`error.toString()` cru vai em `message`, sem tradução: não é UI).
   Aceite: `grep -rn "catch (_) {}" lib` retorna zero; `flutter analyze` com `avoid_catches_without_on_clauses: warning` no `analysis_options.yaml` sem novos avisos (os existentes recebem `// ignore:` com motivo ou viram `on Object`).

3. **Warnings de comportamento** (sem exceção envolvida): spawn de processo acima de 2 s (`Process.start` do LSP, git, automação, `exec`), `Process.start` falhando por PATH (`ProcessException` com `ENOENT`), socket da CLI recusando linha, restauração de layout descartando aba, task terminando com código diferente de 0 fora do runner.
   Aceite: cada um tem um teste unitário que injeta a condição e verifica o `warn` no sink fake.

4. **`PerformanceDiagnostics` nos três SOs.** Renomear a classe e os enums (sem "Linux"); gate `COCKPIT_PERF=1` (manter `COCKPIT_PERF_DIAGNOSTICS=1` como alias por uma release); em vez de JSON no `.log`, cada flush vira eventos `info` no run do app com `metric` e campos numéricos em `attributes`. Métricas novas além das seis existentes:

   | Métrica | Onde medir | Alvo inicial |
   |---|---|---|
   | `frame` (build, raster, total; jank = total > 16 ms) | `addTimingsCallback` (existe) | < 1% de frames com jank com 10 abas |
   | `eventLoop` (atraso do watchdog) | existe | zero acima de 500 ms |
   | `memory` (RSS) | existe, amostra 30 s | sem crescimento contínuo em 1 h |
   | `pty` (bytes → pintura) | `pty_output_scheduler` (existe) | P95 < 30 ms |
   | `boot` (main → primeiro PTY pronto) | `Stopwatch` no `main` até `onLoadStop` do 1º terminal | < 1,5 s com layout restaurado |
   | `restore` (por aba restaurada) | VM `_restoreLayout` | linear, sem pico |
   | `tabSwitch` / `workspaceSwitch` | VM | < 50 ms |
   | `gitRefresh` | `git_controller` (existe) | < 300 ms em repo médio |
   | `spawn` (Process.start até primeiro byte) | `shell_command`, LSP, git | P95 < 200 ms |

   Aceite: `COCKPIT_PERF=1 open Cockpit.app` popula o run com as métricas; sem a env, `PerformanceDiagnostics.enabled == false` e nenhum callback é registrado (teste).

5. **Consulta.** `cockpit telemetry perf [--run <id>] [--metric <m>]` imprime P50/P95/máx por métrica do run (JSON com `--json`). A aba Telemetry ganha uma seção "Performance" só quando o run tem métricas.
   Aceite: comparar dois runs (release atual vs anterior) sai em uma linha por métrica.

6. **Docs.** `docs/telemetry.md` (ou o existente do plano 66) ganha "Erros do app" e "Métricas de performance (dev)"; skill `cli/text/skill.md` documenta `telemetry perf`.

## Definition of Done

- [x] Run "Cockpit" (`source: app`) por boot, com erros/warnings dos handlers globais e do `warn`
- [x] Zero `catch (_) {}` vazios (`on Object` + comentário, ou `warn`)
- [ ] Lint `avoid_catches_without_on_clauses` como warning: ADIADO (137 sítios `catch (_) {`; apertar para `on Exception` caso a caso)
- [x] Warnings de comportamento: spawn lento/ENOENT (`shell_command`), linha malformada no socket, spawn de task, leitura remota, fallback de home remoto, colisão de id na restauração
- [ ] Testes unitários dos warnings (só o `PerformanceDiagnostics` tem teste)
- [x] `PerformanceDiagnostics` nos 3 SOs, opt-in por `COCKPIT_PERF=1`, agregado e assíncrono, sem dados sensíveis
- [x] Métricas de boot, restore, troca de aba/workspace e spawn além das seis existentes
- [x] `cockpit telemetry perf` + chip "App" na aba (sem seção de performance na UI: consulta é pela CLI)
- [ ] Baseline registrado neste plano, medido no `.dmg` instalado (macOS; Windows quando houver máquina)
- [x] `flutter analyze` limpo, testes, docs e skill

## Baseline (preencher após o passo 4)

| Métrica | macOS (M4 Max) | Windows | Data / versão |
|---|---|---|---|
| frame jank % | | | |
| boot | | | |
| pty P95 | | | |
| tabSwitch | | | |
| gitRefresh | | | |
| RSS após 1 h | | | |

## Estado (2026-09-27)

Implementado em sessão solo (sem commit). Bônus: a investigação da colisão de ids entre workspaces (terminal "assumindo" outro) virou fix em `_restoreProject` (remap + `warn("restore")`), então o próximo caso aparece na Telemetria do app.

## Riscos

- Volume: sem agregação, um evento por frame com jank enche o SQLite numa sessão longa. A agregação por janela é obrigatória, não polimento.
- Ruído: warnings demais viram o mesmo problema dos catches vazios (ninguém lê). Fingerprint por `tag + location` e a triagem existente (`ignore`) seguram isso; revisar após uma semana de uso.
- O run do app não tem workspace: a aba Telemetry mostra por workspace hoje. Precisa de um lugar para "app" (topo da lista ou filtro).

## Próximos planos

- Exportar run (`cockpit telemetry export`) para um usuário mandar o arquivo num report de lentidão.
