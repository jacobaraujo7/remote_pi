# Plano 21 — Setup wizard interativo em `/remote-pi`

## Contexto

`/remote-pi` (sem args) hoje mostra status compacto. Mas na **primeira
vez em um cwd**, o user não tem config local ainda — passa por uma
fricção de comandos manuais (`join`, `relay`, `pair`) sem orientação.

Plano 21 adiciona **wizard interativo de setup** disparado
automaticamente quando `/remote-pi` é chamado em cwd sem config.

Persistido em `<cwd>/.pi/remote-pi/config.json` (já existe desde
plano 19). Schema ganha 1 campo:

```json
{
  "agent_name": "backend",
  "session_name": "meu-time",
  "auto_start_relay": true
}
```

Após save, se `auto_start_relay: true`, **roda automaticamente
`join <session>` + `relay start`**.

## Decisões fixadas

| Decisão | Valor |
|---|---|
| **Trigger do wizard** | `/remote-pi` sem args + config local ausente → wizard. Config presente → status compacto (comportamento atual) |
| **Re-executar wizard** | Comando dedicado `/remote-pi setup` força mesmo com config existente (overwrite) |
| **Campos do wizard** | 3 perguntas: agent_name, session_name, auto_start_relay |
| **Defaults** | `agent_name = basename(cwd)`, `session_name = basename(cwd)`, `auto_start_relay = true` (otimiza pra caso comum) |
| **Auto-start ao salvar** | Sim: imediatamente após config gravado, executa `_cmdJoin(session_name)` + (se auto_start_relay) `_cmdRelayStart()`. User vê resultado em 1 fluxo |
| **Subsequente `/remote-pi`** | Lê config, se `auto_start_relay: true` E sessão não conectada → auto-join + auto-relay sem perguntar. Senão só mostra status |
| **API Pi SDK** | `ctx.ui.input` (texto) e `ctx.ui.select` (escolha) — já usados no `wizard.ts` do plano 19 |
| **Confirmação visual** | Após wizard, mostra resumo + executa em sequência com feedback (`notify`) por etapa |

## Estrutura esperada

### Pi-extension

- `src/session/local_config.ts` (existente do plano 19):
  - Schema atual: `{ agent_name, session_name }`
  - **Adicionar campo**: `auto_start_relay: boolean` (default `true` em new config)
  - Migração silenciosa: configs legacy sem o campo → assume `true` ao carregar
- `src/session/setup_wizard.ts` (NOVO):
  - `runSetupWizard(ctx): Promise<LocalConfig>` — 3 prompts sequenciais
  - Validação inline (nome não vazio, não-empty session)
  - Mostra resumo final + confirmação antes de salvar
- `src/index.ts`:
  - `_cmdStatus` (handler de `/remote-pi` sem args) ganha lógica:
    ```typescript
    const localConfig = loadLocalConfig(cwd);
    if (!localConfig) {
      // primeira vez nesse cwd
      const newConfig = await runSetupWizard(ctx);
      await saveLocalConfig(cwd, newConfig);
      await _cmdJoin(ctx, newConfig.session_name);
      if (newConfig.auto_start_relay) {
        await _cmdRelayStart(ctx);
      }
      return;
    }
    // config existe — aplica auto-start se aplicável
    if (localConfig.auto_start_relay && _state.session === null) {
      await _cmdJoin(ctx, localConfig.session_name);
      await _cmdRelayStart(ctx);
    }
    // mostra status compacto
    _showStatus(ctx);
    ```
  - Novo comando `/remote-pi setup` força wizard mesmo com config existente
  - Registrar no `getArgumentCompletions` do `remote-pi` (sub-commands inclui `setup`)
- Tests: `src/session/setup_wizard.test.ts`:
  - Wizard com defaults aceitos → config OK
  - Validação inline rejeita campos vazios
  - Auto-start após save chama join + relay
  - `/remote-pi setup` força mesmo com config existente
  - `/remote-pi` com config + `auto_start_relay: false` → não dispara auto-start
  - Config legacy (sem campo) → assume `true`

## Passos com critério de aceite

### Passo 1 — Estender LocalConfig schema
- [ ] Campo `auto_start_relay: boolean` em `local_config.ts`
- [ ] Read tolera ausência (default `true`)
- [ ] Write inclui sempre

### Passo 2 — Criar `setup_wizard.ts`
- [ ] 3 prompts: agent_name, session_name, auto_start_relay (sim/não)
- [ ] Usa `ctx.ui.input` e `ctx.ui.select`
- [ ] Validação inline
- [ ] Confirmação final (mostra resumo, user aceita)

### Passo 3 — Trigger automático no `/remote-pi`
- [ ] `_cmdStatus` detecta config ausente → roda wizard
- [ ] Após save, executa `_cmdJoin` + (condicional) `_cmdRelayStart`
- [ ] Feedback via `ctx.ui.notify` em cada etapa

### Passo 4 — Comando `/remote-pi setup`
- [ ] Registrado no `pi.registerCommand`
- [ ] Força wizard mesmo com config existente (overwrite confirmado)

### Passo 5 — Auto-start em runs subsequentes
- [ ] `/remote-pi` com config + `auto_start_relay: true` E sessão inativa → join + relay automático
- [ ] Senão só mostra status compacto

### Passo 6 — Tests
- [ ] 6 tests novos (listed acima)

### Passo 7 — Demo manual
- [ ] Pasta nova: `cd ~/projeto-novo && pi -e dist/index.js && /remote-pi`
- [ ] Wizard aparece, user preenche 3 campos
- [ ] Após save, footer mostra `📡 sessao (1) · 🟢 relay`
- [ ] Sair e reentrar (mesmo cwd): `/remote-pi` reusa config, auto-join + auto-relay sem perguntar
- [ ] `/remote-pi setup` força wizard novamente

## Definition of Done

- [x] LocalConfig estendido com `auto_start_relay`
- [x] `setup_wizard.ts` criado
- [x] `/remote-pi` (sem args) auto-detecta + dispara wizard se necessário
- [x] `/remote-pi setup` força re-config
- [x] Auto-start integrado pós-save
- [x] 7 tests novos passando (170 totais)
- [ ] Demo manual valida

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Wizard dispara errado em status check rápido | Trigger só se config ausente; `setup` explícito pra re-rodar |
| User cancela wizard mid-flow | Sem save, sem auto-start; volta ao estado anterior. Adicionar try/catch que limpa parcial state |
| Config legacy quebra leitura | Default `true` pra `auto_start_relay` ausente; sem migration code |
| Auto-start falha (relay url inválido, etc) | Feedback de erro via notify; user fica em sessão local sem relay (ainda funcional) |
| Wizard polui status compacto | Wizard só roda quando config falta; comportamento padrão preserva legibilidade |

## Próximos planos

- **Plano 07** — relay deploy + env throttle/jitter (memory já registrada)
- **Reposicionamento README** (orquestrador-only, ~1h)
