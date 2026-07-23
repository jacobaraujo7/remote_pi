# Orchestration overlay

Modo orquestrado dispara quando o prompt começa com `[ORCH:<task-id>]`. Em
modo solo (sem marker), ignore este arquivo — responda como agente do seu
subprojeto.

## Antes de executar

1. Leia este arquivo inteiro.
2. Identifique o `<task-id>` no marker — use no nome do resultado e nas
   notificações.
3. Se o prompt referenciar algo em `contracts/`, leia esse(s) arquivo(s) —
   eles são fonte de verdade pra contratos cross-project.

## Regras de execução

- **Cwd-only**: trabalhe apenas no seu subprojeto (seu próprio cwd).
- **Sem commit**: nunca rode `git commit` ou `git push`. O orquestrador
  consolida e comita por wave.
- **`contracts/` é read-only**: mudanças no contrato vêm de task explícita,
  nunca no meio de outra.
- **Limpe processos**: mate dev servers/watchers que você iniciou antes de
  encerrar.
- **Escrita restrita**: escreva só dentro do seu cwd e dentro de
  `.orchestration/results/` (esse caminho é exceção permitida).

## Reportar resultado

Ao terminar a task, **sempre** execute estes 3 passos, nessa ordem:

### 1. Grave o resultado em arquivo

Caminho: `.orchestration/results/<task-id>.md`. Estrutura mínima:

```markdown
# [ORCH:<task-id>] <título curto>

**Status**: done | partial | blocked
**Arquivos tocados**: <lista relativa ao cwd, ou "nenhum">

## Resumo
<2-5 linhas: o que foi feito; se partial/blocked, por que parou aqui>

## Notas pro orquestrador
<opcional: decisões em aberto, riscos, próximos passos sugeridos>
```

### 2. Ecoe no chat

Sua resposta interativa começa com `[ORCH:<task-id>] <status>` + 1 linha
de resumo. Permite ao humano e ao orquestrador correlacionarem
visualmente sem abrir o arquivo. Exemplo:

> `[ORCH:03-ts-codec] done` — codec + tipos implementados, 12 fixtures
> passam, vitest configurado.

### 3. Notifique o orquestrador

**Caminho preferido — push via Cockpit.** Se o prompt contém um marker
`[ORCH-REPLY:<tab-id>]`, o orquestrador está num pane do Cockpit esperando
push. Mande a conclusão direto pro pane dele (Enter em comando separado —
`\n` no send vira newline no prompt, não submit):

```bash
cockpit send --tab-id <tab-id> "[ORCH:<task-id>] <status> — <1 linha do resumo>"
cockpit send-key --tab-id <tab-id> Enter
```

Faça isso **depois** de gravar o result file (passo 1) — o push é o aviso;
o arquivo é o relatório. Se o `cockpit send` falhar (pane sumiu, socket
indisponível), siga em frente: o orquestrador tem o polling do result file
como fallback.

**Fallback — sem marker de reply (dispatch via cmux).** Notifique via cmux:

```bash
cmux notify --title "[ORCH:<task-id>] <status>" \
            --body "<1 linha do resumo>"
```

O orquestrador escuta `cmux events --category notification` e sabe que
você terminou sem precisar de polling.

## Contratos cross-project

Quando `.orchestration/contracts/` existir, carrega specs canônicas
compartilhadas (ex: `protocol.md`, `fixtures/*.jsonl`). **Read-only** —
leia, não edite. Mudanças vêm de task explícita do orquestrador.

## Paralelismo

Outros workers podem estar rodando em paralelo no mesmo monorepo. **Não
assuma exclusividade** sobre arquivos fora do seu cwd, nem sobre o
diretório `.orchestration/results/` (cada um escreve no seu `<task-id>.md`,
sem conflito).
