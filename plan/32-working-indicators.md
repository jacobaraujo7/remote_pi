# Plano 32 — Indicadores de atividade (working/thinking) desacoplados do stream

**Objetivo**: fazer o app mostrar que um agente está **trabalhando** de forma
robusta e cross-sessão — não amarrado ao `agent_chunk` (que só chega na conexão
ativa). Dois sintomas que motivaram o plano:

1. **Cursor azul "pensando" sumiu** no chat (regressão do plano 31). → **Parte A** (feita).
2. **Bolinha de working não acende na Home** pra sessões que você não está olhando,
   e **entrar** numa sessão que já trabalha não mostra working. → **Parte B**.

## Diagnóstico (a doença comum)

O visual de atividade estava **amarrado ao `agent_chunk`**:
- O cursor (`StreamingBubble`/`_BlinkingCursor`) só montava quando `streaming != null`,
  e `streaming` só virava non-null no 1º chunk → nada durante o pensamento.
- O `sessions_index.status` (bolinha da Home) é escrito pelos eventos da **conexão
  ativa** (`user_input`/`agent_chunk`) → o `agent_chunk` **nunca chega** pras
  sessões não-ativas (1 conexão por vez), então a Home nunca acende pra elas.

`agent_chunk` é o cano errado pra isso. O cano certo é o **`room_meta`** — o mesmo
que `model`/`thinking` já usam, com **broadcast pra todos os devices pareados** via
relay (não só a conexão ativa).

---

## Parte A — cursor "pensando" (FEITA, commit `8282e4a`)

`SyncService` volta a semear um `StreamingMessage` vazio no início do turno (envio
otimista + echo `user_input`), restaurando o cursor durante o pensamento (pré-31).
In-memory (exceção #7), não escreve no banco. 385 testes, analyze 0. **App-only.**
Cobre o turno que você **vê nascer** estando no chat.

---

## Parte B — working na Home + ao entrar (via `room_meta`)

### Decisões fixadas (entrevista 2026-05-30)

| # | Decisão | Valor |
|---|---|---|
| Q1 | Fonte por camada | **(c) em camadas**: índice durável (Home, todas as sessões) tem **um escritor só = `room_meta.working`**; chat **ativo** usa **eventos locais** como overlay instantâneo. O atraso da bolinha da sessão ativa é invisível (você está no chat). |
| Q2 | Working órfão | **(a) amarrar à presença**: sessão offline/stale → app força `working:false`. Confiável graças ao liveness watchdog do pi-ext (ver dependência). |
| Q3 | Seed-on-entry | **(b)**: entrar numa sessão com `working:true` (sem streaming local) → semeia o cursor piscando na hora + pill na AppBar. |
| Q4 | Anti-flicker | **(b) debounce no app**: pi-ext emite transições cruas; o `SyncService` coalesce (liga na hora, desliga preguiçoso ~Nms) antes de escrever o índice. Toda a lógica de exibição centralizada no app. |

### Arquitetura — 3 projetos (template: o que o `thinking` fez no plano 28 D.6)

`working` vira um **campo de `room_meta`**, end-to-end:

```
pi-ext (turn_start/turn_end → room_meta.working) → relay (campo working, forward) → app (meta.working → sessions_index)
```

---

### Wave 1 — relay (campo `working` no room_meta)

O `RoomMeta`/`RoomMetaPatch` do relay é **struct tipado** (`rooms.rs:8/34`), não
blob — então `working` precisa ser campo explícito, igual `model`/`thinking`:
- `RoomMeta` + `RoomMetaPatch`: add `working: bool` (default `false`).
- `peer.rs`: extrair `meta.working` no **hello** (~`:101-113`) e no handler
  **`room_meta_update`** (~`:261-268`).
- Garantir que o `room_meta_updated` **forward** carrega `working` pros
  subscribers da sala (mesmo caminho do `thinking`).

**Aceite**: cargo test cobrindo merge-patch de `working` (set true/false, ausência
não zera — RFC 7396 já vigente); clippy clean.

### Wave 2 — pi-ext (publicar working)

- `_myRoomMeta` ganha `working?: boolean`.
- `turn_start` → `_myRoomMeta.working = true` + `sendControl({ type:"room_meta_update", room_id, meta:{ working:true } })`.
- `turn_end` → idem com `working:false`.
- **Cru, sem debounce** (Q4 = debounce no app). Reusa o padrão exato de
  `model`/`thinking` (index.ts:970-975).

**Aceite**: vitest — turn_start publica `meta.working:true`; turn_end publica
`false`; mensagem só-texto/sem turno não muda. `pnpm typecheck && pnpm test` verdes.

### Wave 3 — app (consumir + exibir)

- **Índice (Home, todas as sessões)**: `SyncService` lê `meta.working` do
  `roomsStream` (cobre todos os peers, `connection_manager.dart:222`) e escreve
  `sessions_index.status` (working/idle) — **com debounce** (liga na hora, desliga
  com atraso ~Nms; novo `working:true` na janela cancela o off) [Q4].
- **Working órfão** [Q2]: ao ver a sessão **offline/stale** na presença, força
  `status:idle` no índice daquela sessão.
- **Sessão ativa** [Q1c]: o pill/cursor do chat continua nos **eventos locais**
  (overlay instantâneo, Parte A) — o índice pode vir do meta, mas o chat ativo não
  espera o round-trip.
- **Seed-on-entry** [Q3]: ao abrir uma sessão cujo índice diz `working:true` e
  sem streaming local → `_emitStreaming(StreamingMessage(inReplyTo))` vazio
  (cursor) + pill.
- **Home** lê working do índice (fonte única).

**Aceite**: widget/unit — meta.working de uma sessão **não-ativa** acende a bolinha
na Home; sessão fica offline → bolinha apaga; entrar numa sessão working mostra
cursor+pill na hora; turnos colados não piscam (debounce). `flutter analyze` 0;
`flutter test` verde; builds iOS+Android.

---

## Dependência / sinergia — liveness watchdog (pi-ext)

A Q2 (presença limpa o working órfão) **depende de a presença ir offline quando o
Pi morre**. Apareceu no tree um **liveness watchdog** em `relay_client.{ts,test}`
(force-close após ~70s de silêncio → reconnect) — é exatamente o que torna a
presença confiável no caso half-open (daemon dorme/NAT-drop sem close limpo).
**Não é parte deste plano** (WIP separado do pi-ext); registrar como pré-requisito
da robustez da Q2. Se não entrar, a Q2 ainda cobre o caso de close limpo; só o
half-open silencioso fica descoberto.

## Riscos

1. **Tráfego no relay em rajada** (Q4 = debounce no app, não na fonte): pi-ext
   emite toda transição turn_start/turn_end. Rajada = poucos turnos, não por-frame
   → aceitável. Se virar problema, mover a histerese pra fonte (pi-ext) depois.
2. **Shape do `room_meta`** (`room_announced` flat vs `room_meta_updated` nested —
   nota pendente do plano 28 D.6): garantir que `working` é lido nos dois shapes no
   app, senão acende só num caminho.
3. **Sessão ativa: dupla escrita do índice** (meta + local): manter o local como
   overlay do **chat**, e o índice escrito pelo meta — não deixar os dois brigarem
   pelo mesmo registro (Q1c já separa as camadas; vigiar na implementação).

## Definition of Done

- [x] Parte A: cursor "pensando" restaurado (commit `8282e4a`)
- [x] Wave 1 (relay): campo `working` em RoomMeta/RoomMetaPatch + extração + forward; cargo test; clippy — `9e4754b` (deployado)
- [x] Wave 2 (pi-ext): publish `working` no room_meta em turn_start/turn_end (cru); vitest; typecheck — `78eb9d2`
- [ ] Wave 3 (app): meta.working → sessions_index com debounce; presença limpa órfão; seed-on-entry; chat ativo overlay local; Home lê do índice; analyze 0 + test verde + builds — **dono fazendo à mão**
- [ ] Verificação: bolinha acende pra sessão NÃO-ativa; apaga ao ficar offline; entrar mostra working na hora; turnos colados não piscam
- [ ] Smoke manual (device): 2 sessões, uma trabalhando enquanto você olha a outra → bolinha azul na Home da que trabalha
- [x] Commits relay+pi-ext (`9e4754b`, `78eb9d2`); app pendente na Wave 3

---

## Próxima rodada — app polish (preparado, não despachado)

### AppBar subtitle (nome do dispositivo) pisca vazio→preenchido

**Sintoma** (visto em câmera lenta): a linha 2 da AppBar do chat (dispositivo
pareado) aparece vazia/fallback e depois preenche.

**Raiz**: `_peerDisplayName(peer, initialTitle)` (chat_page.dart:279) usa
`peer.nickname` do **`PeerRecord` carregado async** no mount → até carregar,
mostra fallback. O Home **já tem** esse nome (lista os peers). Hoje o `/chat`
só recebe `{'title': title}` (home_page.dart:479 → `initialTitle`,
app_router.dart:311-316).

**Fix** (app-only, sem rede):
1. Home passa o device no `extra`: `extra: {'title': title, 'device': deviceName}`.
2. Router lê `extra['device']` → novo param `initialDevice` no `ChatPage`.
3. `ChatPage` usa `initialDevice` direto na linha 2 da AppBar; remove a
   dependência do `PeerRecord` async pro **subtítulo** (render imediato).
4. `PeerRecord` ainda é usado pelo **dialog de detalhes** (chat_page.dart:204+:
   nickname/relay/safety) — manter, mas carregar **on-demand** no tap do info,
   não no mount (se isso elimina o load no mount).

**Ganho**: sem flicker, sem load async no mount pro subtítulo, sem micro-gestão
de estado da AppBar. **Status**: ✅ feito (`32g`) — 417 testes.

### Fade na troca de chat (tablet detail pane)

**Mecanismo atual**: `_detailPane()` (em refactor → `_DetailPane` widget) monta o
`MultiProvider` keyed por `ValueKey('chat-$epk-$room')` → troca de sessão =
**destroy/recreate**. Estado **não** se perde (SSOT re-lê o box); o transiente é
re-mount + re-apply de histórico + reset de scroll.

**Fix (barato, recomendado)**: envolver o filho keyed num `AnimatedSwitcher`
(~150–200ms, `FadeTransition`) → cross-fade old→new quando a ValueKey muda. Sem
mudar a arquitetura. Encaixa direto no `_DetailPane` widget que já está sendo
extraído.

**Keep-alive (`IndexedStack`)** — opção futura mais pesada: mantém N `ChatPage`s
montados (troca instantânea + scroll preservado), mas exige **gate singleton-sync**
(só a sessão ativa reflete streaming/working do `SyncService`). Só se o fade não
bastar — estado já persiste via SSOT, então é otimização, não correção.

---

## Próximos planos

- Se o tráfego de room_meta em rajada (risco 1) doer, mover a histerese pra fonte
  (pi-ext) — vira aditivo, não muda contrato.
- ~~Status rico (erro/unread) na Home.~~ **Descartado (2026-05-30)** — decisão do dono.
