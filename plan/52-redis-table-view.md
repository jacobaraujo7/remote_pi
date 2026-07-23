# 52 — Redis Table View (tabela editável na tab Database)

## Contexto

A tab Database (plano 51) hoje é SQL-first: editor de query em cima, resultado
embaixo. Para Redis isso não faz sentido — o uso dominante é browse-and-poke.
Decisão (conversa 2026-07-19): a tab vira **polimórfica por engine** — quando a
conexão é Redis/Valkey/KeyDB, o editor de query some e a **tabela editável é a
interface única**. MongoDB pode ganhar um terceiro modo no futuro (fora deste
plano).

Referência visual: tabela com colunas `key | value | type | ttl`, botão `+`
para nova chave, edição inline por célula.

Decisões fechadas na conversa:

| # | Decisão |
|---|---|
| A | **Sem arquivo `.redis`** — a view abre direto da conexão no painel Database (conexão Redis → tab com a tabela). O artefato é a conexão, não um arquivo. Script reprodutível continua sendo `cockpit redis` (agente) |
| B | **Commit imediato por célula** — cada edição confirmada (Enter/blur) vira um comando Redis atômico (`SET`, `EXPIRE`, `HSET`…). Sem estado sujo, sem botão Save. Esc cancela |
| C | **Inline direto só para STRING e TTL.** Tipos compostos (HASH/SET/ZSET/LIST) expandem a linha/célula mostrando o valor completo antes de permitir salvar — nunca editar sobre preview truncado |
| D | **Type imutável em chave existente** — trocar tipo no Redis é DEL+recreate; o seletor de tipo só existe na linha nova do `+`. Na linha existente, type é indicador/filtro |
| E | **SCAN paginado desde o dia 1** — nunca `KEYS *`. Cursor com count ~100 + "load more"/scroll |
| F | **Mini-toolbar de uma linha** no lugar do editor que sumiu: campo de pattern (`user:*`), refresh, `+`, contador de chaves carregadas |
| G | Paridade agent-first: a UI usa os **mesmos comandos** que `cockpit redis` executaria — comportamento idêntico humano/agente |

## Estrutura esperada (cockpit/)

- `lib/app/cockpit/ui/widgets/db_redis_table.dart` — a tabela + toolbar
- Branch por engine no widget da tab Database existente (onde hoje renderiza
  editor+resultado): `engine == redis → RedisTableView`
- `domain/`: contrato de browse Redis tipado (scan paginado, get/set/del/expire,
  leitura completa de compostos) — sem `Map<String,dynamic>` cru na ui
- `data/`: implementação sobre o driver anaki já existente (mesmo caminho do
  `cockpit redis`)

## Passos

1. **Domain: contrato RedisBrowse**
   - `scan(pattern, cursor) → página {keys: [{key, type, ttl, preview}], nextCursor}`
   - `readFull(key) → valor completo tipado por type`
   - `writeString(key, value)`, `writeComposite(key, type, valor)` (DEL+recreate
     interno, atômico via MULTI se o driver suportar), `setTtl(key, segundos | persist)`,
     `delete(key)`, `create(key, type, valor, ttl?)`
   - Aceite: contrato em `domain/`, impl em `data/` reusando o driver do plano 51;
     nenhum comando novo no wire do CLI (já existe `cockpit redis`).

2. **UI: tabela somente-leitura + toolbar**
   - Branch por engine na tab; colunas key/value/type/ttl; TTL `-1` renderiza
     como `∞`; preview de compostos como JSON truncado.
   - Toolbar: pattern (submit refaz o SCAN do zero), refresh, `+` (desabilitado
     até o passo 4), contador "N keys loaded".
   - Paginação: "Load more" quando `nextCursor != 0`.
   - Aceite: conexão Redis abre a tabela (sem editor de query); pattern filtra;
     Redis com 10k+ chaves não trava a UI (páginas de ~100).

3. **Edição inline: STRING + TTL + delete**
   - Clique na célula value (STRING) → edit inline; Enter/blur commita (`SET`),
     Esc cancela. Clique no TTL → edit numérico (`EXPIRE`/`PERSIST` se vazio/∞).
   - Delete por linha (menu de contexto ou botão hover) com confirm.
   - Feedback de escrita: célula confirma visualmente (flash/check breve);
     falha → vermelho + revert pro valor anterior + erro visível.
   - Aceite: editar STRING e TTL reflete no servidor (conferível via
     `cockpit redis --db X GET/TTL`); falha de comando não deixa a célula
     mentindo valor.

4. **Compostos + criar chave**
   - Clique no value de HASH/SET/ZSET/LIST → linha expande com o valor completo
     (via `readFull`) num editor de texto simples (JSON); salvar valida o JSON
     contra o type antes de escrever (decisão C); JSON inválido nunca chega ao
     servidor.
   - `+` → linha nova: key, seletor de type (só aqui — decisão D), valor, TTL
     opcional; salvar cria a chave e a insere na tabela.
   - Aceite: editar um HASH preserva todos os campos (nada truncado); criar
     chave de cada um dos 5 types funciona; JSON malformado é rejeitado com
     mensagem, sem tocar o servidor.

## DoD

- [x] Conexão Redis abre tabela editável no lugar do editor SQL; SQL segue igual
- [x] SCAN paginado + pattern filter; nunca `KEYS *` no código (coberto por teste)
- [x] STRING/TTL inline, compostos via expansão com valor completo, delete com confirm
- [x] `+` cria chave dos 5 types; type imutável em chave existente
- [x] Escrita = comandos idênticos aos do `cockpit redis` (paridade agent-first —
      `RedisBrowseService` roda sobre o mesmo `DbQueryService`/`NoSqlRunner`)
- [x] `flutter analyze` zero issues; strings user-facing em inglês
- [ ] E2E manual contra Redis local (o mesmo dbtest do anaki serve)

Implementado 2026-07-19 (cockpit/). Extras da implementação: tab persiste no
layout (restore por `{type: 'redis', conn}`), uma tab por conexão (reabrir
foca), lote numa conexão só (`NoSqlRunner.redisMany`) pra página de SCAN não
pagar open/close por comando, testes unitários do serviço
(`test/domain/redis_browse_service_test.dart`).

## Próximos planos (fora de escopo)

- Modo Mongo (collections + documentos) na mesma ramificação por engine
- Wave 4 do DB agent-first: `db add` sem credencial, flag read-only por conexão,
  `--out` para export (conversa 2026-07-19, ainda sem plano)
