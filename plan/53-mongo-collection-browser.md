# 53 — Mongo Collection Browser + CLI browse (mongo/redis)

## Contexto

Terceiro modo da tab Database polimórfica por engine (SQL = editor `.dbq`,
Redis = tabela do plano 52, **Mongo = collection browser** estilo Compass).
Decidido em conversa 2026-07-19:

| # | Decisão |
|---|---|
| A | Browser é **tab de sessão**, não arquivo — o estado é reconstituível (conn + collection + filtro efêmero). Formato-arquivo de query salva (find/pipeline sobre a infra `.dbq`) fica pro v2, e servirá de "Save as…" do browser quando existir |
| B | Interface: **filter bar** (JSON) + **documentos como cards JSON** + CRUD por documento ancorado no `_id`. Paginação por skip/limit |
| C | **Extended JSON lossless**: o runner Mongo passa a usar `extendedJsonCodec: false` do anaki — replies mantêm `{"$oid":…}`/`{"$date":…}` como JSON puro. Round-trip de edição sem achatar tipos ("nunca salvar sobre JSON com tipos achatados"). Também conserta o `cockpit mongo` (hoje imprime ObjectId como hex ambíguo) |
| D | **CLI abre a view**: `cockpit mongo browse --db <conn> <collection> [--filter '<json>']` e `cockpit redis browse --db <conn> [--pattern '<glob>']` — o agente investiga via CLI e abre o browser já filtrado pro humano. Abrir view ≠ executar: não devolve documentos (pra isso já existem `cockpit mongo`/`cockpit redis`) |
| E | Filtro passado pelo CLI cai **na filter bar, visível e editável** — sem estado oculto. Tab existente da mesma conn+collection: foca e substitui o filtro |
| F | Paridade agent-first: browser roda sobre o mesmo `runCommand`/`DbQueryService` do CLI |

## Estrutura esperada (cockpit/)

- `domain/services/mongo_browse_service.dart` — listCollections/find/replace/insert/delete via `DbQueryService.mongoCommand`
- `ui/session/mongo_browser_session.dart` — sessão `{conn, collection}`, persiste no layout (`{type:'mongo',conn,collection}`)
- `ui/widgets/db_mongo_view.dart` — filter bar + cards JSON + CRUD
- Painel: conexão Mongo expande **collections** (análogo da árvore de tabelas)
- CLI: subcomando `browse` no `mongo` e `redis` + handlers `mongo-browse`/`redis-browse`
- Skill `cockpit-cli`: comandos novos + noção de como criar `.cockpit/databases.json`

## Passos

1. **Runner lossless**: `extendedJsonCodec: false` no `NoSqlRunnerImpl.mongo`.
   Aceite: `cockpit mongo --command '{"find":…}'` devolve `_id` como `{"$oid":…}`.
2. **MongoBrowseService**: listCollections (nameOnly), find (filter+skip+limit,
   valida JSON do filtro antes de mandar), replaceOne (exige `_id` no doc
   editado), insertOne, deleteOne (por `_id`), todos validando `ok:1`/writeErrors.
   Aceite: testes unitários com runner fake (comandos montados + validação).
3. **Painel**: Mongo ganha chevron → lista de collections (lazy, cacheada como
   as tabelas SQL); clique na collection abre a tab. Aceite: expandir/abrir.
4. **Tab**: cards JSON (highlight do `buildCodeSpan` já usado no `.dbq`),
   filter bar com lupa/X (padrão do Redis), Load more, editar (card expande em
   editor JSON → replaceOne), delete com confirm, `+` insere. Side-car
   `MongoTabState` no DatabaseViewModel; sessão persiste/foca como a Redis.
5. **CLI browse** (mongo e redis): sessão alvo criada/focada com filtro/pattern
   semeado na barra (sessão notifica o widget montado). Erro claro se o filtro
   é JSON inválido ou o workspace não está aberto.
6. **Skill**: documentar `browse` + snippet de `.cockpit/databases.json`
   (`{"databases":[{"name":…,"url":…,"savePassword":false}]}`).

## DoD

- [x] Conexão Mongo expande collections; clique abre o browser (tab persiste/foca)
- [x] find paginado com filtro validado; cards com extended JSON íntegro
- [x] Editar/inserir/deletar documento (replace ancorado no `_id`; confirm no delete)
- [x] `cockpit mongo browse` / `cockpit redis browse` abrem a view filtrada
- [x] Skill atualizada (browse + databases.json) — `~/.claude/skills/cockpit-cli`
      e a cópia embutida do `install-skill` no `cockpit_cli.dart`
- [x] `flutter analyze` zero issues; testes do serviço passando
- [ ] E2E manual contra Mongo local

Implementado 2026-07-19 (cockpit/). Notas: `find` usa `singleBatch` (nunca
deixa cursor aberto); seed de filtro/pattern viaja pela sessão
(`requestFilter`/`requestPattern` → widget montado escuta e aplica).

## Próximos planos

- v2: formato de query salva (find/pipeline) sobre a infra `.dbq` + "Save as…" do browser
- Wave 4 agent-first do DB (`db add`, read-only flag, `--out`) — pendente do plano 52
