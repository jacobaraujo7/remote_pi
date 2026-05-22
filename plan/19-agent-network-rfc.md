# RFC 19 — Agent Network (sessão local + relay no mesmo `/remote-pi`)

> **Status**: PROPOSTA — análise pós-MVP.
> **Não executar antes do MVP atual ter sido shippado, dogfooded, e validado.**
>
> **Renumerado em 2026-05-21**: era plano 17, colidia com `17-rooms.md` (executado). Movido pra 19. Plano 18 = model no tile (executado).
>
> **Restrições adicionais fechadas com o usuário (2026-05-21)**:
> - **(a)** README/docs só atualizados **quando estiver pronto** — não bloqueia execução
> - **(b)** **Sem migração de storage** — mantém `~/.pi/remote/`. Se executado, sessões/broker ficam **dentro de `~/.pi/remote/sessions/`**. Passo 1 do plano cai
> - **(c)** **Features de relay ficam intactas** (zero refactor em pareamento/presence/rooms/etc do plano 17). Esta proposta atua **apenas em adicionar a camada agent-network local (UDS) + refatorar nomes dos comandos `/remote-pi`**

Este documento captura a motivação e o contexto da conversa que originou o
[`Plano 19`](./19-agent-network.md). Aqui vai o **porquê**; no plano vai o **como**.

---

## TL;DR

Adicionar ao `remote-pi` um segundo eixo: **rede local de agentes** (Pis na mesma
máquina conversando via Unix Domain Socket), mantendo o eixo atual (relay mobile)
como capacidade complementar. Tudo orbitando o conceito de **sessão**.

```
remote-pi = sessão (rede local de agentes) + relay opcional (acesso mobile)
```

---

## Contexto da conversa

A discussão começou de uma fricção real do orquestrador-de-orquestradores
(arquitetura `.orchestration/` aplicada em remote_pi e backoffice): o transporte
atual entre agentes é `cmux send` (PTY keystroke injection) + `cmux events`
(agent.hook.Stop) + arquivos `.orchestration/results/<id>.md`. Funcional, mas:

- `cmux send` às vezes "perde Enter" (race entre send e send-key)
- `agent.hook.Stop` requer filtro por `session_id` e fase (received/completed)
- Resultado vive em arquivo, sinal vive em evento, mensagem chega via teclado —
  três mecanismos pra fazer 1 coisa (despachar e esperar resposta)
- Quando wave é paralela (FE+BE), correlacionar respostas via arquivo é fácil
  perder rastro de "qual reply é qual"

Exploramos várias opções de transporte: WebSocket/TCP, MCP, file-watching, NATS,
Postgres LISTEN/NOTIFY, CRDTs, ZeroMQ, Git como bus, signals POSIX. Convergimos
em **Unix Domain Socket** como o melhor compromisso pra coding agents locais:

- Latência sub-ms
- Sem rede, sem porta TCP
- Permissions via filesystem (chmod 600)
- Atomic delivery (kernel buffer)
- Sem proliferação de arquivos (1 `.sock` por agente é endpoint, não storage)
- Portável Linux/macOS/BSD/WSL/Windows nativo
- Já provado em produção em Docker, PostgreSQL, systemd, D-Bus, X11

Disler (`pi-vs-claude-code/coms`) também usa UDS no transporte local — sinal
empírico que o caminho é razoável.

---

## A oportunidade que isso destranca pro remote_pi

Hoje `remote-pi` faz **uma coisa**: pareia celular via QR e roteia mensagens via
relay WebSocket E2E. Excelente, mas escopo único.

Se trouxermos o conceito de **sessão de agentes locais**, o produto vira:

> "Controle remoto + rede local pra times de Pi agents — celular ou outros Pi
> processes na mesma máquina conversam entre si pelo mesmo protocolo conceitual."

Casos de uso novos que ficam viáveis:

1. **Orquestração de agentes Pi**: 1 Pi como orquestrador, 2-3 Pi workers em
   subprojetos, conversando via UDS local. Tipo o `.orchestration/` que fazemos
   manualmente hoje, mas nativo do remote-pi.
2. **Pi colaborativo no monorepo**: dev abre 3 terminais Pi em pastas diferentes
   do mesmo repo; todos automaticamente entram na mesma "sessão" e veem peers.
3. **Mobile + agent network combinados**: celular pareia → fala com 1 Pi → esse
   Pi pode despachar a tarefa pra outro Pi local sem o celular ter que saber.
   Mobile é UM peer da sessão, não o ÚNICO peer.

Nenhum dos competidores (Telepi, MuxAgent, OpenCode mobile apps, Claude Code
Remote Control) tem essa combinação. Posicionamento único.

---

## A decisão de escopo que isso força

Hoje em `00-decisions.md` o MVP é definido como pareamento mobile + relay. Esta
proposta **não muda o MVP** — adiciona feature pós-MVP.

Risco honesto a registrar antes de executar: ao adicionar agent-network como
"segundo pilar", a positionado do produto muda. README atual diz "remote control
para sessões do Pi a partir do celular". Vira algo como "remote control + agent
mesh para sessões do Pi". Branding/comunicação fica mais largo, potencialmente
diluído.

**Decisão a tomar pós-MVP, conscientemente** (registrar em `00-decisions.md`):

- Opção A: agent-network entra como **feature equivalente ao relay**. Produto
  reposicionado pra "remote control + agent network".
- Opção B: agent-network entra como **feature menor**, relay continua sendo a
  cara do produto. README só ganha uma seção.
- Opção C: agent-network vira **produto separado** (`pi-mesh`?) compartilhando
  binário com `remote-pi` mas com positioning isolado.

Não decidir aqui. Esperar dados de uso real.

---

## Resumo do desenho técnico (detalhes no plano)

### Arquitetura

```
~/.pi/remote-pi/
├── settings.json              # GLOBAL: relay_url
├── identity.json              # GLOBAL: Ed25519 keypair (singleton)
└── sessions/
    └── <session-name>/        # 1 pasta por sessão
        ├── broker.sock        # UDS endpoint
        ├── session.json       # metadata (created_at, owner)
        ├── peers.json         # celulares pareados nesta sessão (mobile)
        └── audit.jsonl        # log append-only de mensagens
```

```
<cwd>/.pi/remote-pi/
└── config.json     # LOCAL: { agent_name, session_name }
```

### Modelo de execução

1. Primeiro Pi em uma sessão **vira líder** (auto-elect via bind race do socket)
2. Pis subsequentes conectam como **clientes** ao broker.sock
3. **API simétrica**: aplicação não sabe se é líder ou cliente
4. Se líder cai, próximo Pi assume via re-eleição transparente

### Protocolo (5 campos)

```json
{
  "from": "backend",
  "to": "orchestrator",     // ou "broadcast", ou ["fe","be"]
  "id": "uuid-v7",
  "re": "uuid|null",        // correlation id (id da msg que esta responde)
  "body": "<conteúdo>"      // string ou objeto, livre
}
```

### Roteamento

**Broker filtra antes de entregar**. Agentes só recebem o que é endereçado a
eles (por nome em `to`) ou broadcast. **Não precisam fazer filtragem
client-side**. Esta é a propriedade-chave que enxuga a skill e zera ambiguidade.

### Comandos `/remote-pi` propostos

```bash
# Sessão (agent network local)
/remote-pi                       # status (não-destrutivo)
/remote-pi join                  # wizard interativo
/remote-pi join <name>           # upsert: existe → entra; não existe → cria
/remote-pi leave                 # sai da sessão
/remote-pi rename <novo-nome>    # renomeia agente
/remote-pi sessions              # lista sessões globais

# Relay (mobile, opt-in)
/remote-pi relay                 # TOGGLE start/stop
/remote-pi relay url <url>       # configura URL (global, persistente)
/remote-pi relay status          # opcional, status detalhado

# Pareamento mobile
/remote-pi pair                  # QR (requer relay started)
/remote-pi devices               # lista celulares pareados na sessão
/remote-pi revoke <shortid>      # revoga celular
```

Comandos antigos (`/remote-pi start`, `pair`, `stop`, `list`, `add-relay`,
`revoke`) ficam como **aliases temporários** durante 1 release, deprecados em
seguida, removidos no release seguinte. Migração gradual sem breaking change
imediato.

### Indicadores visuais no footer do Pi

Pi tem API nativa `ctx.ui.setStatus(key, text)` no footer. Usar pra exibir
sempre:

```
... main · 📡 backoffice (3) · 🟢 relay (📱 iPhone)
```

3 status keys: `remote-pi:session`, `remote-pi:relay`, opcional
`remote-pi:peer-active`. Atualizadas em todos transitions.

Também `ctx.ui.setTitle()` espelhando estado pra aba do terminal.

---

## Decisões abertas (FECHADAS 2026-05-21 — exec começou)

| # | Decisão | Resolução |
|---|---|---|
| Q1 | Toggle no `/remote-pi join`? | **NÃO**. Toggle só em `relay`. `join`/`leave` explícitos pra evitar `leave` por acidente |
| Q2 | Default name = `basename(cwd)`? | **SIM** |
| Q3 | Colisão de nome → auto-suffix `#N`? | **SIM**, broker decide |
| Q4 | Pareamento mobile = 1 sessão (Opção A original) ou multi-sessão? | **Mantém A** (já decidido em `00-decisions.md`) |
| Q5 | Relay config = global ou per-session? | **GLOBAL** (uma URL pra instalação inteira) |
| Q6 | Sessão sem relay é caso válido? | **SIM** (modo agent-network puro, sem mobile) |
| Q7 | Migração `~/.pi/remote/` → `~/.pi/remote-pi/`? | ~~One-shot~~ **NÃO migrar**. Mantém `~/.pi/remote/`. Sessões/broker viram subdirs (`~/.pi/remote/sessions/`, `~/.pi/remote/skills/`). Zero risco de perda de dados existente |
| Q8 | Skill ships junto da extensão ou instala em `~/.pi/skills/`? | **Embedded na extension**, exposta via `pi.on("resources_discover")` apontando pra `pi-extension/skills/` |
| Posicionamento (A/B/C) | Reposicionar README pra "mobile + mesh"? | **Adiado** — decidir só após dogfood real do agent-network |

---

## O que NÃO está em escopo

- **Cross-machine agent network**: continua sendo relay (mobile/remoto). Agent
  network é local-only via UDS por design. Cross-machine vira outra discussão.
- **Channels MCP**: explorado, descartado pra MVP. Complexidade alta, ganho
  marginal pra coding workflows locais. Reavaliar só se aparecer requisito que
  UDS não cobre.
- **Persistência durável de fila**: mensagens em flight ficam no kernel buffer
  do UDS, sumirão em crash do líder. Audit em `audit.jsonl` paralelo cobre
  reconstrução; mensagens não-entregues no momento do crash são perdidas
  conscientemente.
- **Multi-orquestrador**: 1 sessão tem 1 líder por vez. Multi-líder com
  consensus (Raft etc.) é overengineering pra coding agents locais.
- **Per-session relay URL**: relay é global. Não há sessão "com relay próprio".
  Se aparecer caso, é override pontual, não primeira-classe.

---

## Riscos honestos

1. **Reposicionamento sutil do produto** — README e site mudam de tom. Pode
   confundir early users que entraram pela história "mobile remote control".
2. **Complexidade no Pi extension** — código mais que dobra de tamanho. State
   machine fica `idle → joined → (relay_started → (paired))`.
3. **Migração de storage** — usuários existentes precisam que `~/.pi/remote/`
   migre limpo. Single bug aqui = perde keypairs e pareamentos antigos.
4. **Self-elect bugs** — leader election via bind race tem edge cases (stale
   sock, double-bind window). Precisa testes específicos.
5. **Footer status pode poluir** — 3 status keys ao mesmo tempo pode espremer
   git branch e outros statuses no footer. Validar com tema dark + linha estreita.

Mitigações:
- Manter relay como caminho default no README inicial; agent network como
  "advanced feature" até consolidar
- Aliases temporários nos comandos antigos por 2 releases antes de remover
- Testes específicos pra leader election (bind race simulation)
- Migration script com backup automático antes de mover arquivos

---

## Sinais que validariam executar

Executar este plano só faz sentido se, pós-MVP:

- [ ] Pelo menos 1 user real (não o autor) reportou que quer "ter mais de um Pi
      conversando entre si"
- [ ] OU autor próprio sente a dor diariamente no orquestrador-de-orquestradores
      (cmux send fragility recorrente)
- [ ] MVP atual está dogfooded por 2+ semanas sem regressões severas
- [ ] Existe banda mental pra ~3 semanas de implementação (escopo grande)

Se nenhum desses sinais, **arquivar este RFC e revisitar em 3 meses**.

---

## Próximas ações (todas pós-MVP)

1. Reler este RFC com olhos frescos depois do MVP shippado
2. Decidir Q1-Q8 explicitamente, registrar em `00-decisions.md`
3. Se aprovado, executar [`Plano 17`](./17-agent-network.md) com a skill
   [`17-agent-network-skill.md`](./17-agent-network-skill.md)
4. Atualizar README + posicionamento conforme decisão de Q de reposicionamento

---

## Referências da conversa origem

- Conversa de design (2026-05): UDS, broker leader election, protocolo enxuto, skill como tool
- `~/pc/ORCHESTRATION.md`: arquitetura `.orchestration/` aplicada em remote_pi
- `~/.claude/skills/claude-cmux/SKILL.md`: skill que documenta o transporte cmux
  atual (será complementada por esta — UDS pra Pi, cmux pra Claude)
- `plan/00-decisions.md`: decisões fechadas que esta proposta respeita
