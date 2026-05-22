# Plano 20 — Tools nativos `agent_send` e `agent_request` (LLM-facing)

## Contexto

Plano 19 implementou agent network (UDS broker + SessionPeer JS API +
CLI commands + skill). Mas a `SessionPeer.send/request` só é acessível
via código JS — **LLM Pi não tem como invocar**. Quando user pede "fala
com o backend", o Pi responde "ok, vou mandar" mas não tem ferramenta
pra executar.

Plano 20 fecha o gap registrando 2 tools nativos no Pi SDK que o LLM vê
na lista de tools (igual Bash/Read/Edit):

- `agent_send(to, body)` — fire-and-forget
- `agent_request(to, body, timeout_ms?)` — request/reply síncrono

Skill `agent-network` já deployada (plano 19) orienta uso.

## Decisões fixadas

| Decisão | Valor |
|---|---|
| **Nomes** | `agent_send` e `agent_request` (não `peer_*` — "agent" alinha com a skill `agent-network`) |
| **Visibilidade** | Tools sempre registradas, **mas só funcionais quando in-session**. Se LLM chamar fora de sessão, tool retorna erro claro: "Not in a session. Run /remote-pi join first" |
| **Schema body** | `unknown` (JSON-serializable livre). LLM passa string ou objeto |
| **Resposta de `agent_request`** | Retorna apenas `body` da resposta (não envelope completo). Mais útil pro LLM consumir |
| **Timeout default** | 30s. `agent_request` aceita override via param `timeout_ms` |
| **`agent_send` semântica** | Fire-and-forget. Retorna `{ ok: true }` imediato após enfileirar |
| **Erro** | Tool retorna `{ error: "<motivo>" }` em vez de throw — LLM lida melhor com strings que com stack |

## Estrutura esperada

### Pi-extension

- `src/session/tools.ts` (NOVO):
  - `registerAgentTools(pi: ExtensionAPI, getSessionPeer: () => SessionPeer | null)` 
  - Registra 2 tools via `pi.registerTool(...)` (ou método análogo do SDK)
  - Cada tool tem schema (typebox / zod conforme SDK) + handler
- `src/index.ts`:
  - Chama `registerAgentTools(pi, () => _sessionPeer)` no init
  - `_sessionPeer` é a variável module-level já existente (do plano 19)
- Tests: `src/session/tools.test.ts`:
  - `agent_send` → SessionPeer.send chamado
  - `agent_request` → SessionPeer.request chamado, retorna body
  - Fora de sessão → tool retorna erro estruturado
  - Timeout custom respeitado
  - Body livre (string + object)

### App, Relay, Contracts
- **Zero mudança.** Tools são internas ao Pi SDK; não trafegam no protocolo wire.

## Schema dos tools

```typescript
agent_send: {
  description: "Send a message to another agent in the current session (fire-and-forget). Requires you to be joined to a session (/remote-pi join).",
  input: {
    to: string,        // peer name (or "broadcast", or array of names — array TODO se SDK suportar)
    body: unknown,     // JSON-serializable payload
  },
  output: { ok: boolean, error?: string }
}

agent_request: {
  description: "Send a message to another agent and wait for their reply. Use for asking questions mid-task. Max 1 hop — don't chain through other agents.",
  input: {
    to: string,
    body: unknown,
    timeout_ms?: number,   // default 30000
  },
  output: unknown | { error: string }    // body da resposta, ou erro
}
```

## Passos

### Passo 1 — Investigar API exata do Pi SDK pra registrar tools

Ler `node_modules/@mariozechner/pi-coding-agent/dist/core/extensions/types.d.ts`:
- `ExtensionAPI.registerTool(...)` ou similar?
- Schema format (typebox? zod? raw JSON schema?)
- Como tool handler recebe input/retorna output

Anotar API exata antes de codar.

### Passo 2 — Implementar `registerAgentTools`

Em `src/session/tools.ts`. 2 tools conforme schema acima.

Handler de `agent_send`:
```typescript
async (input) => {
  const peer = getSessionPeer();
  if (!peer) return { ok: false, error: "Not in a session. Run /remote-pi join first." };
  try {
    await peer.send(input.to, input.body);
    return { ok: true };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}
```

Handler de `agent_request`:
```typescript
async (input) => {
  const peer = getSessionPeer();
  if (!peer) return { error: "Not in a session. Run /remote-pi join first." };
  try {
    const reply = await peer.request(input.to, input.body, input.timeout_ms ?? 30_000);
    return reply.body;  // só o body, não envelope inteiro
  } catch (e) {
    return { error: String(e) };
  }
}
```

### Passo 3 — Wire em `src/index.ts`

No factory da extension:
```typescript
const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  _pi = pi;
  // ... handlers existentes ...
  registerAgentTools(pi, () => _sessionPeer);
};
```

### Passo 4 — Tests

`src/session/tools.test.ts`:
1. `agent_send` chama SessionPeer.send com args corretos → `{ok:true}`
2. `agent_send` fora de sessão → `{ok:false, error:"Not in a session..."}`
3. `agent_request` chama SessionPeer.request → retorna `reply.body`
4. `agent_request` com timeout custom respeita o valor
5. `agent_request` fora de sessão → `{error:"Not in a session..."}`
6. SessionPeer throw (network error) → erro estruturado retornado
7. body como string passa intacto
8. body como object aninhado passa intacto

### Passo 5 — Atualizar skill (opcional)

Skill `19-agent-network-skill.md` (já em inglês, deployada) menciona
"`peer.request()`" — substituir por "`agent_request` tool" pra LLM
saber o nome real da tool quando lê a skill.

Marcar como mudança mínima — só rename de `peer.request` → `agent_request`
e `peer.send` → `agent_send` nas seções "Asking multiple agents in
parallel" e "Pattern 1-4".

### Passo 6 — Demo manual

```bash
# Terminal 1
cd ~/projeto-a
pi -e ~/Projects/remote_pi/pi-extension/dist/index.js
/remote-pi join meu-time
# user prompt: "envie ping pra backend e me mostre a resposta"
# LLM deveria chamar agent_request("backend", "ping", 30000)
# LLM responde com o que voltou

# Terminal 2 (cwd diferente)
cd ~/projeto-b
pi -e ~/Projects/remote_pi/pi-extension/dist/index.js
/remote-pi join meu-time
/remote-pi rename backend
# user prompt: "responda qualquer mensagem que chegar com 'pong'"
# LLM aciona mensagem entrante via auto-listener da SessionPeer
# (skill orienta sobre o protocolo de resposta)
```

## Definition of Done

- [x] `src/session/tools.ts` criado com 2 tools registrados
- [x] Wire em `index.ts` (1 linha no factory)
- [x] tests passando (163 totais, +9)
- [x] Skill atualizada com nomes reais das tools (peer.request → agent_request)
- [x] Demo manual valida pelo user

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| API exata do `registerTool` no Pi SDK desconhecida | Passo 1 investiga antes de codar |
| LLM tenta chamar tool fora de sessão | Erro estruturado claro orienta a fazer `/remote-pi join` primeiro |
| `body` muito grande quebra serialização | Pi SDK provavelmente já tem limite — herdamos. Se quebrar, documentar |
| Tool name colide com SDK Pi ou outras extensions | `agent_*` prefix razoavelmente único; checar no Passo 1 |
| LLM não descobre tools via skill | Skill já orienta a fazer perguntas via outro agente; rename ajuda LLM associar |

## Próximos planos

- **Plano 07** — relay deploy (com lembrete throttle/jitter da memory)
- **Reposicionamento README** (orquestrador-only, ~1h)
