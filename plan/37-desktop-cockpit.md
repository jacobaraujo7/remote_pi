# 37 — Desktop Cockpit: cliente visual do Pi via RPC

> **✅ ENCERRADO (2026-07-19).** O plano cumpriu seu papel — o Cockpit existe,
> roda em produção (1.13.0) e as Waves 1–4 estão entregues. **Mas a identidade
> mudou no caminho**: o plano descrevia um cockpit *agent-centric* (grid de N
> agentes `pi --mode rpc`); o produto virou um **multiplexador terminal-first**
> (flag `enableAgent` default OFF, workspace de sistema terminal-only, e o
> crescimento real foi em ambiente de trabalho: terminal/PTY, git, DB browsers,
> tasks, LSP, CLI interna, realms). A Wave 2 foi implementada com escopo
> diferente do previsto — árvore de `SplitPane`/`LeafPane` com tabs multiplexando
> 7 tipos de conteúdo (agente, terminal, file viewer, diff, task output, Mongo,
> Redis), não grid de agentes RPC. A parte agent-centric que sobrou órfã
> (crash→restart por pane, seletor de modelo, `packages/pi_core`) migrou pra
> seção "Próximos planos / evolução" — não é pendência deste plano.

## Contexto

Hoje a tese do Remote Pi é "seus agentes no seu bolso" — o **mobile é o gateway
remoto** (App → relay → Pi). Falta o complemento natural: quando você *está* na
máquina, não quer um multiplexador de terminal (cmux), quer uma **GUI densa,
multi-pane, local-first** sobre o motor do Pi: projetos à esquerda, N agentes
lado a lado no centro, árvore de arquivos à direita. Cada agente é um
`pi --mode rpc` que o app spawna e dirige.

É uma **superfície nova** (5ª, junto de `app/` `relay/` `pi-extension/` `site/`),
não uma feature de um subprojeto existente. Este plano define stack, escopo de
MVP e onde o código mora.

### Relação com planos/decisões existentes

- **`00-decisions.md:133`** ("Apps nativos em vez de Flutter — provavelmente
  nunca; reconsiderar só se Flutter travar feature crítica"). Foi escrito pro
  mobile, mas o princípio vale aqui. Este plano **reconsidera explicitamente pro
  desktop e mantém Flutter** (razões em "Stack" abaixo). Passo final atualiza essa
  linha.
- **Plano 26 (daemon mode)** já resolveu a parte difícil: spawn de `pi --mode
  rpc`, protocolo RPC (**wire real = `{"type":"prompt","message":…}`** — o
  `sendUserMessage` que os planos 26/37 assumiam estava desatualizado; corrigido
  no spike, ver `cockpit/docs/rpc-protocol.md`), CWD
  lock (UDS em `~/.pi/remote/locks/<roomId>.sock`, 1 Pi por pasta), config local
  em `<cwd>/.pi/remote-pi/config.json`. O cockpit é um **gerenciador de processos
  paralelo** ao supervisor: o supervisor serve daemons headless 24/7
  (fire-and-forget, sem streaming); o cockpit serve agentes **interativos com
  streaming na UI**. Coexistem (pastas diferentes); convergência fica pra futuro.
- **Malha de agentes (broker, planos 19/25 + 34)** é o caminho pra duas evoluções
  futuras (reachability remota + attach a Pi já rodando). Fora do MVP — ver
  "Próximos". (O redesign leaderless da 35, antes citado aqui, foi descontinuado
  em 2026-06-05 — ver `plan/35-mesh-leaderless-redesign.md`.)
- **CWD lock (1 Pi por pasta)** é construto da extensão remote-pi, não do Pi puro.
  Importa só quando o cockpit spawna **com** a extensão (ver decisão B).

### A parte difícil não é a UI — é o ciclo de vida do processo

O risco real não é desenhar tela: é **spawnar, streamar stdout, detectar crash,
recuperar e multiplexar N instâncias de `pi --mode rpc`**. Isso é idêntico em
qualquer stack de UI. Por isso o **passo 0 é um spike** que prova o lifecycle e
documenta o schema RPC exato **antes** de qualquer tela.

## Stack — decidido

**Flutter desktop (macOS first).** Razão (pra solo dev mantendo já Flutter
`app/` + Rust `relay/` + Node `pi-extension/` + Next `site/`):

| Critério | Flutter desktop | Swift/SwiftUI nativo |
|---|---|---|
| Stacks mantidos | +0 (reusa a #1) | +1 (5º stack) |
| Reuso do `app/` | tema, client Pi, modelos, widgets | ~zero |
| UI do mock (dark custom, sem chrome) | onde Flutter brilha | vantagem nativa marginal |
| Cross-platform | Windows/Linux de graça depois | macOS-only pra sempre |
| Integração SO (menu bar, Spotlight) | suficiente | melhor — mas não é o diferencial aqui |

O design do mock é 100% custom (balões + painéis, não grid de terminal): é o caso
em que a força do nativo quase não aparece e a do Flutter (UI custom + reuso)
aparece inteira. Pegadinha conhecida do Flutter desktop — multi-window — é
desviada porque o layout é **single-window com panes internos**. Subprocesso
(`Process.start` do `dart:io`) e menu nativo (`PlatformMenuBar`) cobrem o resto.

**Refutados:** Swift nativo (sem reuso, +1 stack, macOS-only); Tauri (tentador
pelo Rust do `relay/`, mas a UI seria construída do zero num stack de *app web*
que não existe — o `site/` é Next de marketing); Electron (oposto de consolidar).

## Decisões fechadas (2026-06-05)

A/B/C confirmadas pelo usuário ("por enquanto vamo testar o conceito").

| # | Decisão | Valor | Por quê |
|---|---|---|---|
| **A** | Onde mora o app | **Pasta própria `cockpit/`** (não dentro de `app/`). `packages/pi_core` (protocolo + modelos + tema compartilhados com `app/`) é **extração futura — ainda não feita** | UI mobile ≠ UI desktop (não compartilhar `lib/ui`). No MVP, `cockpit/` é projeto Flutter standalone; o reuso real com `app/` vem depois, quando doer duplicação |
| **B** | MVP carrega a extensão remote-pi? | **Não** — spawna `pi --mode rpc` puro (local, sem relay) | Desacopla o MVP de config de relay/mesh. Sem extensão, sem CWD lock cross-process; dedup é interno ao cockpit. Quando carregar a extensão (futuro), agentes do cockpit ficam alcançáveis do celular **de graça** |
| **C** | Cockpit reusa o supervisor (plano 26) ou spawna próprio? | **Spawna próprio** | Supervisor é fire-and-forget sem streaming (plano 26:285); o cockpit precisa de stdout streaming pra renderizar. São gerenciadores paralelos; convergência depois se valer |
| **D** | Como o Cockpit injeta config no Pi | **Via env `REMOTE_PI_DIRECT_CONFIG`** (JSON do `LocalConfig` inteiro inline; precedência sobre o `config.json`; espelha `REMOTE_PI_RELAY`) — **committado+pushado** (bundled em `af66d04`, mensagem enganosa; ver "higiene" abaixo) | Cockpit spawna `pi --mode rpc` e injeta config sem escrever arquivo na pasta do usuário. Carrega `agent_name`/`workspace`/`worktree`/`auto_start_relay` do plano 38 de graça |
| **E** | Update de config em runtime? | **NÃO** — sem `/remote-pi ctl` via stdin. Updates vão por **env no (re)spawn**: Cockpit re-spawna com o env atualizado | Restart-only de fato (o único campo imutável é `cwd`); evita um canal de controle paralelo e mantém o env como fonte única no modo Cockpit |
| **F** | Como o celular pareia/revoga com um agente do Cockpit | **Caminho A — pelo agente RPC vivo** (`/remote-pi pair` e `/remote-pi revoke` no Pi que já roda; reusam a conexão de relay; sem 2º processo) — **pi-ext feito**: pair `054b16c`, revoke `fe79759` (locais, **não pushados**) | O relay rejeita 2ª conexão lado-Pi com mesmo `(pubkey, roomId)` (`RoomAlreadyOpenError`) e o token vive na memória do **ocupante da room** → quem emite token / recebe `pair_request` / derruba o canal no revoke tem que ser o agente vivo, não um 2º processo |

### Pareamento + revoke RPC-friendly — contrato pro Cockpit (pi-ext feito; lado cockpit = próximo)

O Cockpit gerencia pareamento pela própria UI mandando comandos pelo stdin do
`pi --mode rpc` e reagindo aos eventos estruturados.

**Parear** (`054b16c`) — renderiza o QR a partir dos eventos:
```
dispara: {"type":"prompt","message":"/remote-pi pair --ttl 120"}
recebe:  remote-pi:pair-code  → details { uri, token, expiresAt, roomId, name }  → renderiza QR de `uri`
         remote-pi:paired     → details { name, peerId, pairedAt }               → fecha QR, mostra device
         (relay-down/erro → extension_ui_request method `notify`)
```

**Revogar** (`fe79759`) — espelha o pair:
```
dispara: {"type":"prompt","message":"/remote-pi revoke <remote_epk-completo>"}
confirma: relendo ~/.pi/remote/peers.json (peer some)
```

Detalhes (pi-ext, feito): `/remote-pi pair` aceita `--ttl <s>` (default 60s, faixa
10–600s via `clampPairTtlMs`). **Ambos** (`_cmdPair` e `_cmdRevoke`) **auto-sobem
o mesh+relay quando ocioso e RECUSAM se o relay não conectar** — usam
`localConfigExists` (honra `REMOTE_PI_DIRECT_CONFIG`) e o `ctx` ganhou `cwd`. No
revoke isso garante revoke **real**: o device revogado recebe o `bye` e tem o canal
vivo derrubado (não é só edição offline do `peers.json`). TUI inalterado; 457/457.

> **⚠️ Mudança de comportamento do `/remote-pi revoke` in-agent**: antes editava o
> `peers.json` offline; agora **recusa quando ocioso/relay-down**. O **`remote-pi
> revoke` CLI standalone** (caminho offline/sem-agente) ficou **inalterado** — é o
> escape pra revogar sem relay. Consistente com a propagação implícita do plano 08
> Q5 (o `bye` é entrega ativa best-effort; o `error{unknown_peer}` segue de fallback).

**Lado Cockpit (renderizar o QR + fechar no `paired` + UI de revoke) é o próximo
passo** — e é o que transforma a decisão B ("MVP sem extensão") na evolução
"extensão carregada → alcançável/gerenciável do celular".

> **Foco imediato** (pedido do usuário): provar que o `--mode rpc` se comporta no
> Flutter desktop — **spike + layout básico**. **Panes/multiplexação adiados**
> ("não precisa criar as panes ainda, vamos rever isso") → Wave 2 fica em espera
> até o conceito fechar.

## Estrutura esperada (decisão A — espelha as camadas do `app/`)

`cockpit/` segue a **mesma arquitetura em camadas do `app/`**, com `CLAUDE.md` por
camada (já scaffoldado). A diferença real está em `data/`, que aqui gerencia
processos RPC + filesystem em vez de mesh/relay/crypto.

```
remote_pi/
├── cockpit/                            ← NOVO: app Flutter desktop (pkg `cockpit`, macOS)
│   ├── CLAUDE.md                       ← persona raiz (orquestração + camadas)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/   (+ utils/)        ← DI, bootstrap, path do `pi`     → config/CLAUDE.md
│   │   ├── domain/   (+ contracts/)    ← Project, Agent, RpcEvent, FileNode → domain/CLAUDE.md
│   │   ├── data/                       ← rpc/ (Process.start) · filesystem/ · adapters/ → data/CLAUDE.md
│   │   ├── routing/                    ← GoRouter                         → routing/CLAUDE.md
│   │   └── ui/  (+ core/themes, core/viewmodel) ← features + ViewModels   → ui/CLAUDE.md
│   ├── macos/                          ← runner (flutter create já rodado)
│   └── pubspec.yaml
├── app/                                ← inalterado por enquanto
└── packages/pi_core/                   ← FUTURO: extração de protocolo/modelos/tema; ainda não feita
```

> O `PiRpcProcess` (spawn/stream/send/kill) mora em `cockpit/lib/data/rpc/`
> enquanto `pi_core` não existir. Quando a extração acontecer, ele migra pra lá e
> `app/` passa a depender do mesmo pacote.

## Passo 0 — Spike de lifecycle  ✅ FEITO (2026-06-05)

> **Resultado**: o lifecycle fecha. `dart run tool/rpc_smoke.dart` fez spawn →
> `prompt` → streaming → `agent_end` → kill com exit 0 e **zero processo órfão**.
> A descoberta empírica virou código real (não throwaway): `PiRpcProcess` em
> `cockpit/lib/data/rpc/` + schema em `cockpit/docs/rpc-protocol.md`. Detalhes em
> `.orchestration/results/37-rpc-spike.md`.

O que era pra provar (tudo verde):

- Spawnar `pi --mode rpc` numa pasta via `Process.start` (`dart:io`). ✓
- Mandar o comando pelo stdin (linha JSON). **Wire real: `{"type":"prompt",
  "message":…}`** — não `sendUserMessage` (suposição corrigida). ✓
- Parsear o **stream de eventos** do stdout: `message_update` com `text_delta`/
  `thinking_delta`/`text_end`, `tool_execution_start/end`, `agent_start/end`,
  `turn_start/end`, `response`. ✓ (renderizar por `delta`, não reparsear `partial`)
- Matar o processo limpo: **fechar stdin = shutdown gracioso (code 0)**; só escala
  pra SIGTERM se não sair em 3s. ✓

**Schema exato vem do Pi SDK** (`rpc-types.js`/`rpc-mode.js` em
`node_modules/@mariozechner/pi-coding-agent` — mesma fonte citada no plano
26:158). O entregável do spike é **esse schema documentado** (comandos que
mandamos + eventos que recebemos), porque toda a UI de streaming depende dele.

**Aceite:** 1 botão sobe `pi --mode rpc`, manda "liste os arquivos", o stream
aparece cru na tela, kill não deixa processo órfão (`pgrep` limpo). Schema RPC
escrito em `plan/37-desktop-cockpit.md` ou doc anexo. **Se isso não fechar, o
resto é fachada — não avançar.**

## Waves (com critério de aceite)

### Wave 1 — Esqueleto + 1 agente

- `cockpit/` Flutter roda no macOS com tema dark próprio (`ui/core/themes`).
- `PiRpcProcess` (em `cockpit/lib/data/rpc/`): spawn/stream/send/kill com base no
  schema do spike.
- UI single-pane: escolher pasta → ver o agente bootar → mandar prompt → stream
  renderiza (texto + tool calls). Sem multiplexação ainda.
- Dedup interno: cockpit não abre a **mesma pasta** em dois panes (decisão B —
  sem lock cross-process por enquanto).

*Aceite:* abrir pasta → agente sobe → "liste os arquivos" → stream renderizado;
fechar o pane mata o child (sem órfão); tentar abrir a mesma pasta de novo é
bloqueado com aviso.

### Wave 2 — Multiplexador (N panes) + projetos  ⏸️ EM ESPERA

> **Adiada por decisão do usuário** (2026-06-05): "não precisa criar as panes
> ainda, vamos rever isso". Só começa após o conceito (spike + Wave 1) fechar.

- Sidebar esquerda: lista de pastas-projeto (adicionar pasta → aparece).
- Grid central de panes; cada pane = um `PiRpcProcess` independente numa pasta.
- Lifecycle por pane: spawn/kill isolado; crash → estado `crashed` + botão
  restart (espelha o tratamento de crash do plano 26:168).
- Seletor de modelo por pane (mock mostra "Opus 4.8"): expor se o RPC aceitar set
  de modelo em runtime; senão, flag no spawn. Reasoning-effort/approval-mode do
  mock ficam pra polish.

*Aceite:* 2+ panes em pastas diferentes rodando ao mesmo tempo, streams
independentes; fechar um pane mata só o child dele; matar um child por fora →
pane mostra `crashed` e restart resobe.

### Wave 3 — Árvore de arquivos + viewer (direita)

- Painel direito: árvore **read-only** da pasta do pane ativo. Clique no arquivo →
  viewer read-only. (Editar é trabalho do agente, não do cockpit — a árvore é pra
  você *inspecionar* o que o agente toca.)
- Destacar arquivos modificados recentemente (watch de fs ou derivado dos
  `tool_result` de Write/Edit do stream).

*Aceite:* árvore reflete a pasta do pane ativo; clicar abre o conteúdo;
modificação do agente aparece após refresh; troca de pane troca a árvore.

### Wave 4 — Persistência + layout + atalhos

- Persistir lista de projetos/panes entre reinícios (mesma stack de storage do
  `app/`, ou config local).
- Navegação por teclado entre panes; estado de janela/layout.
- Menu nativo macOS (`PlatformMenuBar`): novo agente, fechar pane, etc.

*Aceite:* reabrir o app restaura projetos; atalho alterna panes; layout persiste.

## DoD

- [x] 0 — Spike: spawn/stream/kill de `pi --mode rpc` validado (headless `dart run
      tool/rpc_smoke.dart`, exit 0, sem órfão) + **schema RPC documentado** em
      `cockpit/docs/rpc-protocol.md`
- [x] A/B/C — decisões confirmadas pelo usuário (2026-06-05; registradas acima)
- [x] Scaffold — `cockpit/` criado (Flutter, pkg `cockpit`) + camadas espelhadas
      do `app/` com `CLAUDE.md` por camada; `scout-cockpit` + pane registrados
- [x] 1 — `cockpit/` roda no macOS; `PiRpcProcess` em `data/rpc/`; single-pane com
      streaming. Aceite visual cumprido pelo uso diário em produção
- [x] 2 — Multiplexador entregue **com escopo diferente do planejado** (ver banner
      de encerramento): árvore `SplitPane`/`LeafPane` + tabs multiplexando 7 tipos
      de conteúdo, sidebar de projetos (rail + realms). Crash→restart por pane e
      seletor de modelo por agente **não entraram** — migrados pra "Próximos"
- [x] 3 — Árvore de arquivos + viewer entregues (e além: diff viewer, media view,
      file finder, content search)
- [x] 4 — Persistência (Hive, projetos/panes/layout), atalhos de teclado e menu
      nativo (`PlatformMenuBar` + Menubar Win/Linux) entregues
- [→] 5 — `packages/pi_core` compartilhado com `app/` — **movido pra "Próximos"**
      (só faz sentido se/quando o modo agente RPC voltar ao centro)
- [x] 6 — `00-decisions.md` atualizado (2026-07-19): desktop = Flutter, decidido

## Achados do spike (2026-06-05) — atenção pra Waves seguintes

Do `.orchestration/results/37-rpc-spike.md`. Já incorporados onde dava; o resto é
contexto pras próximas waves:

- **Protocolo** (canônico em `cockpit/docs/rpc-protocol.md`): framing JSONL
  (LF-only, sem U+2028/29); comando `prompt` (+`streamingBehavior`); `message_update`
  **repete o `partial` inteiro a cada delta** → renderizar por `delta` (senão
  O(n²)); modelos com reasoning streamam `thinking_*` mesmo com thinking oculto na
  TUI; **stderr ≠ protocolo** (warnings → canal `RpcDiagnostic` separado, senão
  quebra o parser).
- **macOS — duas pegadinhas de ambiente**:
  1. App **não herda o PATH do shell** → `pi` resolvido por caminhos conhecidos ou
     `--dart-define=COCKPIT_PI_PATH`.
  2. **App-sandbox bloqueia spawn de processo + leitura de pasta arbitrária** → o
     agente **desligou o app-sandbox** nas duas entitlements (`DebugProfile`/
     `Release`). Coerente com decisão B (dev tool local, fora da App Store).
     **⚠️ DECISÃO PENDENTE DE CONFIRMAÇÃO** — é a de maior superfície; revisar se um
     dia for distribuir pela loja.
- **Provider/model de demo**: default da máquina é `ollama` (estava fora no teste).
  Rodar a demo com `--dart-define=COCKPIT_PI_PROVIDER=deepseek
  --dart-define=COCKPIT_PI_MODEL=deepseek-chat` (chaves já em `~/.pi/agent/auth.json`).
- **Dep nova não prevista no plano**: `file_picker` (seleção de pasta no macOS).
  provider/auto_injector/go_router já eram a stack declarada.

## Trade-offs explícitos

- **Cockpit e supervisor (plano 26) são gerenciadores paralelos.** Um agente está
  no cockpit **ou** é daemon do supervisor, não os dois (CWD lock, 1 Pi por
  pasta). Convergir (cockpit "adota" um daemon) é evolução, não MVP.
- **MVP é local-only (decisão B).** Agentes do cockpit **não** são alcançáveis do
  celular até a wave futura que carrega a extensão remote-pi no spawn. Aceito pra
  desacoplar o MVP do relay/mesh.
- **`send` é streaming, mas a árvore é read-only.** O cockpit não edita arquivos;
  só observa. Editor embutido é não-objetivo (o agente edita).
- **Sem multi-window no MVP.** Single-window com panes internos (desvia a parte
  fraca do Flutter desktop).
- **macOS first.** Windows/Linux são possíveis (Flutter), mas não testados no MVP.

## Não-objetivos

- Editor de código embutido (o agente edita; o cockpit observa).
- Reachability remota / mesh no MVP (decisão B → wave futura).
- Reuso do supervisor do plano 26 (decisão C → spawn próprio).
- Multi-máquina / multi-window.

## Próximos planos / evolução

- **Restos agent-centric da Wave 2** (órfãos do encerramento, 2026-07-19):
  crash→restart por pane de agente, seletor de modelo por agente, e
  `packages/pi_core` (DoD 5). Reabrir só se o modo agente RPC (`enableAgent`)
  voltar ao centro do produto.
- **Reachability remota** — spawnar `pi --mode rpc -e <remote-pi dist>`: o agente
  do cockpit também entra no relay e fica alcançável do celular **de graça**
  (stdout pro cockpit, socket de relay pra mobile — canais distintos no mesmo
  child). Acopla a config de relay; reusa a malha de agentes (broker, planos
  19/25 + 34). O **pareamento** desse caminho já tem o lado pi-ext pronto
  (decisão F + contrato acima); falta o lado Cockpit renderizar o QR.
- **Attach a Pi já rodando** — em vez de recusar pasta com Pi ativo (terminal ou
  daemon), o cockpit *anexa* via malha e observa/dirige o agente existente,
  resolvendo o CWD lock por adoção, não por recusa. (O mecanismo exato fica em
  aberto: a abordagem UDS-direta da 35 foi descontinuada; reavaliar sobre o broker
  atual quando esta evolução entrar.)
- **Convergência cockpit ↔ supervisor** — "promover" um pane do cockpit a daemon
  24/7 (e o inverso: abrir um daemon existente num pane).
