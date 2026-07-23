# Decisões já tomadas

Este arquivo é um **registro** (não um plano executável). Lista decisões fechadas em conversa exploratória antes/durante o bootstrap. **Não revisite sem evidência forte de que a decisão estava errada** — proponha re-discutir como tarefa explícita, não silenciosamente.

Numeração `00-` é proposital: este arquivo carrega antes dos planos numerados quando alguém faz `ls plan/`.

---

## Origin / posicionamento

- **Alvo do produto**: ataque o [Pi coding agent](https://github.com/earendil-works/pi). Não Claude Code (já tem Remote Control oficial), não OpenCode (já tem 5+ apps mobile community), não Goose/Aider (mercado pequeno).
  - **Razão**: Pi é o concorrente open-source mais relevante do Claude Code, tem RPC + SDK públicos, e **nenhum app mobile dedicado existe** (só `TelePi` via Telegram).
- **Não copiar MuxAgent**: ele já cobre multi-harness comercial. Brigamos pelo nicho **Pi-only, open source, qualidade**.

## Arquitetura

| Decisão | Razão / nota |
|---|---|
| **Sem daemon no MVP** | Só a extensão `/remote-pi` ativa enquanto Pi roda. Refutamos daemon residente: complexidade alta, ganho moderado. Quando Pi fecha → mobile vê offline |
| **Extensão > wrapper** | Pi tem extension API (TypeScript runtime extensions). Happy fez wrapper só porque Claude Code é closed-source — Pi não precisa repetir isso |
| **Auto-start opcional** | Config `pi-remote.autostart=true` conecta no relay automaticamente quando Pi abre. Sem precisar digitar `/remote-pi` toda vez |
| **Relay stateless** | Sem persistência. Encaminha ciphertext entre dois peers identificados por pubkey. ~200 linhas de Rust |
| **Relay open-source + self-hostável** | Compromisso de credibilidade. Usuário paranoico roda o próprio. Não vira ponto único de comprometimento |

## Pareamento

| Decisão | Razão / nota |
|---|---|
| **Persistente, não efêmero** | Peers salvos em `~/.pi/remote/peers.json` (Mac) + Keychain/Keystore (mobile). Refutamos efêmero por sessão e efêmero por pareamento — UX hostil. Pair-once, reconnect-forever |
| **Sem conta no MVP** | QR só pareamento. Conta opcional fica pra v2 se aparecer demanda real (multi-device sync, recuperação) |
| **QR efêmero (60s, rotaciona)** | Janela curta reduz risco de foto/screenshot vazar. Token single-use |
| **Safety number opcional** | 6 emojis bilateral (estilo Signal), pra confirmar visualmente que pareamento não foi MITM |
| **Forward secrecy** | ECDH efêmero a cada reconexão. Chave de longo prazo (Curve25519) só pra autenticar identidade |
| **Identidade = pubkey** | Sem username. Auth no relay via challenge-response (relay assina nonce, peer responde com assinatura da pubkey privada) |
| **Lifetime do pareamento** | Até alguém revogar. ~~Comando `/remote-pi revoke <nome>`~~ Comando `/remote-pi revoke <shortid>` (8 chars do epk) + tab completion — fechado 2026-05-19 (plano 08 Q3) |
| **Revoke no app (fechado 2026-05-19, plano 08 Q4)** | Lista de peers em Settings com swipe-to-delete + modal de confirmação |
| **Sinalização cross-side ao revogar (fechado 2026-05-19, plano 08 Q5)** | Propagação implícita: lado revogado limpa storage local; outro lado detecta via `error{unknown_peer}` na próxima reconexão. Sem novo tipo `revoke_pair` no protocolo |

## Escopo de visibilidade

| Decisão | Razão / nota |
|---|---|
| ~~**Project scope via git root**~~ | ~~App pareado vê só sessões do projeto onde `/remote-pi` rodou. Detecção: subir a árvore procurando `.git`, `package.json`, `pyproject.toml`, `Cargo.toml`. Fallback: cwd exato~~ |
| ~~**Refutados**: cwd-exato (perde sessões da raiz quando entra `src/`) e Mac-inteiro (vaza projetos pessoais)~~ | |
| ~~**Pareamento global, vista por projeto**~~ | ~~Chave de longo prazo é por Mac (singleton). Lista de sessões filtra por project scope do Pi que tá rodando~~ |
| **Pareamento = 1 sessão (MVP)** | Revertido em 2026-05-18. Razão: enxugar MVP. QR gerado por `/remote-pi` é específico da sessão Pi corrente. App vê apenas essa sessão. Sem project scope, sem session manager, sem listagem multi-sessão por projeto. Multi-sessão volta a ser considerado em v2 (`plan/07-v2-multi-session.md` quando aparecer demanda real) |

## Multi-instância (vários Pi)

| Cenário | Comportamento |
|---|---|
| **App pareado com N Pis (fechado 2026-05-19, plano 08 Q1)** | Sim — `peers.json` (Mac) e Keychain (mobile) já são listas. App mostra todos em Settings com switcher. Só 1 ativo por vez no `ConnectionManager` |
| ~~**Pi pareado com N devices (fechado 2026-05-19, plano 08 Q2)**~~ | ~~Opção C: storage suporta N (`peers.json`), **mas só 1 device conectado simultaneamente** (`_peerChannel` é singleton). Outros pareados ficam dormentes. Modelo broadcast/multi-ativo cortado por complexidade~~ — **revisada 2026-05-23 (plan 23 Wave 2C)**: invariante "1 conn por `(peer, room)`" no relay relaxada pra broadcast. Devices com mesma Owner-key (plan 23) podem coexistir conectados e recebem a mesma mensagem do Pi. `_peerChannel` continua singleton no pi-ext porque o broadcast acontece no relay — pi-ext envia 1 envelope, relay distribui. Skip-sender via `from_conn_id` evita eco |
| 2 terminais Pi na mesma pasta | Cada um gera QR próprio → 2 pareamentos independentes. Zero conflito (mantida — compatível com MVP 1-pareamento-1-sessão) |
| ~~Pi A pediu `switch_session X`, X está LIVE em Pi B~~ | ~~`AgentSessionRuntime.resume(X)` lança `SessionLockedError`. App mostra "em uso em outro terminal"~~ (revertida 2026-05-18: sem switch_session no MVP) |
| ~~Pi numa subpasta (`projeto-a/src`)~~ | ~~Resolve project root = `projeto-a/` via marcador → mesmo conjunto de sessões~~ (revertida 2026-05-18: sem project scope no MVP) |
| App listando pareamentos | Cada item = um pareamento ativo = uma sessão. Estado: **online** (Pi rodando) ou **offline** (Pi fechado/inalcançável). Sem "histórico", sem "em outro Pi", sem cores de estado multi-instância. |

## UI / produto

| Decisão | Razão / nota |
|---|---|
| ~~**Hierarquia Peer → Projeto → Sessão**~~ | ~~Não árvore como home. Inbox de approvals + sessões ativas + recentes~~ (revertida 2026-05-18) |
| **Hierarquia plana: Pareamento ↔ Sessão (1:1)** | Lista de pareamentos = lista de sessões. Sem camada de projeto. Substitui a hierarquia anterior. |
| ~~**Sessão histórica = read-only**~~ | ~~Tap abre histórico completo. Botão "Continuar essa sessão" dispara `switch_session` → vira active no Pi → libera write~~ (revertida 2026-05-18: sem conceito de sessão histórica no MVP) |
| ~~**Mobile pode ativar sessão histórica**~~ | ~~Não precisa o dev resumir no terminal. App envia `switch_session` e Pi process faz `AgentSessionRuntime.resume()`~~ (revertida 2026-05-18: sem switch_session no MVP) |
| ~~**Rename em 3 níveis**~~ | ~~Peer no Keychain (local), Projeto em `~/.pi/remote/projects.json` (sincroniza p/ outros celulares pareados), Sessão no metadata JSONL (sincroniza bidirecionalmente com a CLI)~~ (revertida 2026-05-18) |
| **Rename apenas do pareamento** | Local no Keychain/Keystore do mobile. Nome default = cwd onde o Pi rodou (ex: `remote_pi · feature/protocol`). Sem 3 níveis. |
| **Trabalho paralelo** | Emerge da arquitetura: N Pi processes pareados = N sessões no app. App mostra todas com swipe entre elas |
| **Switcher por gesto** | Recomendação UX: swipe da borda esquerda alterna entre últimos N pareamentos |

## Approval / segurança operacional

| Decisão | Razão / nota |
|---|---|
| **Sem push notification no MVP** | Cortado pra eliminar burocracia APNs ($99/ano cert), FCM SDK, push token mgmt. Reconexão = on-demand quando user abre app |
| ~~**Auto-approve read-only**~~ | ~~`Read`, `Glob`, `Grep` rodam sem prompt. Fluxo do agente não trava em coisa segura~~ Revogada 2026-05-19 (plano 10.2) |
| ~~**Approval obrigatório**~~ | ~~`Bash`, `Edit`, `Write` sempre param. App mostra diff/comando antes de aprovar~~ Revogada 2026-05-19 (plano 10.2) |
| ~~**Timeout default 60s**~~ | ~~`on_timeout=abort`. Conservador: se user não respondeu, não execute~~ Revogada 2026-05-19 (plano 10.2) |
| **Sistema de approval removido do pi-ext (fechado 2026-05-19, plano 10.2 revisado)** | Tool calls executam direto. Razão: SDK do Pi não tem campo nativo `requiresApproval` por tool, e nosso gate hardcoded (Bash/Edit/Write) forçava approval em TODAS as tools custom de packages, gerando ruído e não escalando. Quando o ecossistema Pi padronizar permissions, religar via plano futuro. App mantém infra dormante (`ToolRequest` type + approval card) pra forward-compat. `tool_result` continua sendo enviado pra transparência |
| **Quando push entrar (v2)** | Aditivo. Schema atual não muda. Relay decora `tool_request` com push fire (quando permissions voltarem) |

## Crypto / E2E (resumo — detalhe nos planos 04 e 06)

| Decisão | Razão / nota |
|---|---|
| **libsodium / Noise** | Curve25519 + ChaCha20-Poly1305. Pode ser Noise XX/IK (padrão WireGuard/WhatsApp) ou libsodium direto. **Não inventar protocolo** |
| ~~**Handshake = Noise XX (fechado 2026-05-18)**~~ | ~~Stack: Node usa `noise-protocol` (npm, low-level Noise puro); Dart usa `cryptography` (dint.dev, 309k downloads/sem) + Noise XX implementado seguindo spec literalmente em ~200 LOC; relay só faz challenge-response Ed25519 (`ed25519-dalek`), sem participar do Noise. Validação obrigatória via test vectors oficiais do Noise + roundtrip Node↔Dart no localhost. Razão: não há lib Noise XX madura pura Dart (`noise_protocol_framework` tem 69 dl/sem — risco demais pra cripto).~~ |
| **E2E removido no MVP (fechado 2026-05-19)** | Plano 06 executa rollback de Noise XX. Razão: handshake virou bottleneck depurativo (semanas perdidas em bugs entre Dart e Node), e relay é open-source + self-hostável — usuário paranoico roda o próprio em VPN/Tailscale. MVP roda sobre plaintext + Ed25519 auth + TLS no transporte. Re-ativar Noise é roadmap aditivo (plano 09 opcional), com pré-requisito de ferramental de debug (loopback test + wire dump). Trade-off explícito: operador do relay público vê conteúdo de mensagens — aceito pra MVP beta fechado. |
| **Pacote Dart de cripto (fechado 2026-05-18)** | `cryptography` (dint.dev). Tem X25519, ChaCha20-Poly1305, HKDF, Ed25519. ~~Híbrido platform-crypto + Dart fallback. Substitui `sodium_libs` que era pré-considerado.~~ Após rollback (2026-05-19) usado apenas pra Ed25519 (auth no relay). X25519/ChaCha/HKDF saem do app. |
| **Relay NUNCA decifra** | ~~Vê só `{ peer, ct, tamanho, timestamp }`. Logs proibidos de conter payload (mesmo cifrado)~~ Pós-rollback: relay continua opaco ao `ct` (nunca chama `JSON.parse(ct)`), mas `ct` é base64 do JSON em claro. Logs proibidos de incluir `ct` mesmo assim — princípio mantido. |
| **TLS 1.3 obrigatório** | Camada 1 (transporte). ~~E2E é camada 2. Defesa em profundidade~~ Pós-rollback: TLS é a ÚNICA camada de proteção contra MITM externo até E2E voltar (plano 09 opcional). Cert pinning no app vira mais importante. |
| **Cert pinning no app** | Bloqueia MITM via CA comprometida |
| **Sem quantum-safe** | Curve25519 cai contra computador quântico estável. Trocar pra Kyber quando virar problema real (não 2026) |
| **`ct` no MVP do protocolo (plano 03)** | É base64 do JSON em claro. ~~até o plano 04 ativar cifra real.~~ Permanente após plano 06 (rollback E2E). Permite religar Noise no futuro só trocando geração/parse do `ct` — shape do envelope intacto. |

## Modelo de ameaças — o que NÃO protegemos

Para ser honesto desde o início:

- **Mac comprometido** → atacante é o Pi. Fim de jogo
- **Celular comprometido** → atacante tem Keychain. Fim de jogo
- **Usuário aprovando comando malicioso** → sistema obedece. UI mostra diff, mas se você toca Aprovar sem ler, é problema seu
- **Análise de tráfego** → relay sabe tamanho/timing. ~~Não vaza conteúdo, mas vaza padrões ("Jacob ativo às 22h")~~ Pós-rollback E2E (plano 06): relay vê tamanho/timing **e conteúdo**. Mitigação: self-host trivial + roadmap pra religar E2E (plano 09 opcional)
- **Operador do relay público (pós-rollback E2E)** → vê todo conteúdo das mensagens (código, comandos shell, outputs). Aceito no MVP beta. Usuário sério deve self-hostar o relay (open-source, ~200 LOC Rust)
- **Quantum** → ver linha acima

## Processo / meta

| Princípio | Aplicação |
|---|---|
| **Não criar subagent antes de existir conteúdo** | Reviewers locais foram negados pra agora — só stubs nos subprojetos |
| **Não criar abstração antes de precisar** | YAGNI agressivo. Aplicado em: sem versionamento de protocolo, sem `--persist` flag no `/remote-pi`, sem recovery de pareamento |
| **Subagent só vale com 3 critérios** | Prompt rico + saída estruturada + contexto isolado. Senão é overhead |
| **CLAUDE.md silencioso sobre irmãos** | Persona vive no projeto. Único acoplamento aceitável: gatilho `[ORCH:<id>]` → lê `.orchestration/INSTRUCTIONS.md` |
| **Plan/ é cockpit do orquestrador** | Subagentes não navegam planos altos. Recebem tasks decompostas |

---

## Em aberto — não decidir sem motivo

Estas decisões foram **propositalmente adiadas**. Quando alguém quiser fechar, abrir discussão explícita.

| Item | Quando decidir |
|---|---|
| ~~State management Flutter (Riverpod / bloc / signals_flutter)~~ | ~~Quando 1ª feature do app exigir state compartilhado~~ — fechado 2026-05-18: `ViewModel<T>` custom (single-field emit) + `provider` + `auto_injector`. Infra já existe em `app/lib/ui/core/viewmodel/viewmodel.dart` e `app/lib/config/dependencies.dart`. Convenção: sealed states em `ui/<feature>/states/`, `_injector.addViewModel<T>(T.new)` no setup, `ViewmodelProvider<T>()` no router. |
| ~~Pacote libsodium pra Dart (`sodium_libs`, `cryptography`, outro)~~ | ~~Plano 04 (pareamento)~~ — fechado 2026-05-18: `cryptography` (dint.dev) |
| Onde hospedar o relay | Plano 06 |
| Versionamento de protocolo (`v` field) | Quando v2 do protocolo surgir e exigir migração |
| Conta de usuário opcional | Quando aparecer dor multi-device |
| Push notifications | v2, após MVP validado |
| Multi-relay / federação | Provavelmente nunca. Só se relay público virar gargalo |
| Apps nativos (Swift/Kotlin) em vez de Flutter | Provavelmente nunca. Reconsiderar só se Flutter limitar features críticas (ex: integração profunda iOS Keychain). **Desktop: reconsiderado e mantido Flutter — decidido no plano 37, validado em produção (Cockpit 1.13.0; plano encerrado 2026-07-19)** |

---

## Distribuição (fechado 2026-06-12 — planos 43/44/45)

| Decisão | Razão / nota |
|---|---|
| **App mobile: distribuição DUPLA** | iOS = **App Store**; Android = **Play Store** (AAB) **+ APK direto** (`RemotePi.apk` em GitHub Release `app-v*`, ofertado na `/download` do site). A frase "não precisamos subir pras lojas" significava não *depender* delas — as lojas continuam canais. Artefatos store-ready verificados em `1.1.0+5` (IPA assinado Apple Distribution + AAB assinado release), build manual via agente do App; o CI cobre só o APK direto |
| **Cockpit (desktop): fora de lojas** | DMG notarizado (macOS) + EXE sem assinatura (Windows, SmartScreen documentado) + deb/rpm (Linux x64+arm64) via GitHub Release `cockpit-v*` |
| **Hospedagem de binários** | Assets de GitHub Releases (tags prefixadas por produto; monorepo ok como puro storage). VPS **sem SSH** → `rp-s3` serve só os `latest.json` por produto; usuário posiciona o manifest manualmente = **gate de publicação** |
| **Updates** | ~~Sem auto-update.~~ **(revisto 2026-06-27 — plano 47)**: Cockpit **macOS/Windows** ganham **self-update** via Sparkle/WinSparkle (pacote `auto_updater`): baixa em background, card "reiniciar p/ instalar", troca + relança. **Linux mantém notify manual.** Gate de publicação manual no rp-s3 **continua** (agora cobre também os `appcast-{macos,windows}.xml`). Site (`/download`) + card in-app dispensável (Cockpit e app Android) seguem lendo o `latest.json` como fallback / caminho do Linux+Android; card pode aparecer pra install de loja (sem detecção de origem) |

---

## Como atualizar este arquivo

- **Decisão nova fechada em conversa** → adicione bullet na seção certa
- **Decisão revertida** → não apague o bullet original; **risque** (`~~texto~~`) e adicione a nova abaixo com data e razão
- **Decisão deixada em aberto** → vai pra "Em aberto"
- **Não** edite este arquivo em silêncio durante implementação. Decisões existem em conversa explícita
