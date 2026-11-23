# Isolamento de execuções de tasks

Correção desenvolvida na branch `fix/task-execution-isolation`, no worktree
`.cockpit/worktrees/fix/task-execution-isolation`, a partir de `3234007b`.

## Causa confirmada

`TasksJsonLoader` gera identificadores locais como `json:Server`; adapters também
usam IDs locais como `flutter:run`. `TaskDiscoveryImpl` devolvia esses IDs sem
qualificar o projeto. O runner local é compartilhado entre os projetos e usa
`def.id` para processos ativos, preparação do spawn, último estado, watchers,
URLs e Compose. `TasksViewModel` também usa esse ID para estados e profiles;
`TaskTerminalStore` o usa para terminais, subscriptions, runner de origem e logs.

Portanto duas configurações com o mesmo label produziam o mesmo slot global.
O segundo start direto é idempotente e pode nem criar outro processo. O painel
passa a mostrar o estado da primeira execução; stop/restart com esse ID controla
o processo do outro projeto. A CLI com `run-task --restart` também pode parar a
execução anterior ao identificar o slot colidido como já ativo. Não foi encontrado
um mecanismo específico do .NET que mate servidores pelo nome do projeto.

A regressão foi comprovada executando o teste de identidade com a implementação
original de descoberta, restaurada temporariamente com `try/finally`: seis
definições de três raízes resultaram em somente dois IDs (`json:Server` e
`json:Worker`). O teste falhou antes da qualificação e passou com a correção.

`TaskProcessRegistry`/`OwnedProcessRegistry` usam PIDs reais, separados por PID
do Cockpit proprietário, e não nomes de task/worktree. Não precisaram de mudança.

## Estratégia e componentes

`TaskDefinition` centraliza a identidade. Mantém `localId` para o ID da
configuração e expõe `id` como `task-v1-<sha256>`, calculado sobre uma tupla JSON:

```
[hostId, workspaceId, projectRoot, localId]
```

A raiz é a pasta descoberta, não o `cwd` sobrescrito da task nem o basename do
worktree. O UUID do workspace isola inclusive a mesma pasta aberta em realms
diferentes. O host diferencia pastas remotas com caminhos iguais. O hash tem
tamanho fixo para não exceder limites dos nomes de arquivos de scrollback.

A qualificação acontece depois do merge local em `TaskDiscoveryImpl` e na
`RemoteTaskDiscovery`. Painel e CLI passam o mesmo UUID do workspace; a descoberta
remota recebe o ID do host. Todos os mapas existentes continuam usando `def.id`,
sem reconstruir identidades próprias. Descoberta fora do contexto de um workspace
pode omitir o UUID, mantendo isolamento por raiz e host.

`TasksPanel` e `TasksViewModel` reconhecem também a troca de UUID, mesmo sem mudança
de caminho. Seleção de profile, controle do processo, stdin/resize, output,
progresso, previews e recuperação de estado passam a compartilhar a mesma chave.

A reconciliação de Compose agora atualiza apenas o workspace/raiz redescoberto,
preservando as definições e o monitoramento de outros projetos. Entradas ativas
são mantidas mesmo após remoção da configuração para permitir controle posterior.
Há uma dependência injetável de consulta de Compose para testar isso sem Docker.

A parada tardia por SIGKILL confere a instância original antes de agir.
`disposeAll` retira os slots do mapa antes dos awaits de limpeza: o teste com
vários processos revelou que callbacks de saída podiam alterar a coleção durante
a iteração e disparar `Concurrent modification during iteration`.

## Compatibilidade

- Não há mudanças no formato de `.cockpit/tasks.json`, labels, comandos, profiles,
  argumentos, ambiente ou precedência das tasks manuais.
- A CLI continua aceitando IDs curtos, como `json:Server`, dentro do workspace
  emissor, além dos IDs qualificados retornados por `list-tasks`.
- `read-task` resolve aliases curtos no mesmo contexto antes de acessar o terminal.
- Preferências antigas de device continuam sendo lidas pela chave legada;
  novas escolhas são gravadas pela identidade qualificada.
- Continua existindo um slot de execução por task dentro do mesmo workspace e
  raiz. Profiles da mesma task não criam execuções paralelas implicitamente.
- Logs antigos com IDs curtos permanecem acessíveis por descritores de abas
  legadas. Não são copiados automaticamente para novas identidades, pois o
  armazenamento antigo não permite determinar com segurança o projeto de origem.
  Novas execuções e seus históricos usam as identidades isoladas.

## Validação automatizada

`task_execution_isolation_test.dart` cobre nomes iguais entre workspaces e
worktrees, múltiplas tasks com profiles iguais, UUIDs distintos na mesma pasta,
`cwd` absoluto compartilhado, hosts remotos, merge de adapters, seleção de
profiles, preferências legadas de device, terminais, persistência/restauração de
logs e reconciliação de Compose.

O teste nativo cria os repositórios independentes `payments.service` e
`order.service`, worktrees Git reais chamados `shared` em ambos, e um segundo
worktree em payments. As configurações têm tasks `Server` e `Worker` com profiles
`dev`/`prod`. Quatro servidores usam o mesmo comando e argumentos. Cada servidor
escolhe uma porta disponível e responde seu próprio diretório por HTTP.

O teste usa o `PtyTaskRunner` real, confirma quatro PIDs distintos, respostas HTTP,
progresso `building/running`, recuperação do estado ao alternar o projeto,
reinício com novo PID preservando o profile e parada isolada. Confere que os
outros PIDs e respostas permanecem intactos e aguarda o prazo de escalada da
parada antes de verificar novamente o servidor reiniciado.

`task_cli_identity_test.dart` verifica o roteamento real do handler da CLI para
iniciar, ler output, reiniciar e parar usando aliases legados e IDs qualificados,
inclusive com workspaces distintos na mesma pasta.

Para executar no Linux, a partir de `cockpit/`:

```sh
flutter pub get
cmake -S plugins/cockpit_pty/src -B /tmp/cockpit-task-isolation-pty-build
cmake --build /tmp/cockpit-task-isolation-pty-build -j 2

COCKPIT_ISOLATED_ROOT=/tmp/cockpit-task-isolation-state \
COCKPIT_TASK_PTY_TESTS=1 \
COCKPIT_TASK_TEST_DOTNET=/tmp/cockpit-task-dotnet/dotnet \
LD_LIBRARY_PATH=/tmp/cockpit-task-isolation-pty-build \
flutter test --no-pub \
  test/tasks \
  test/session/task_terminal_store_run_ordering_test.dart \
  test/session/task_terminal_store_json_log_test.dart \
  test/ui/tasks_panel_import_test.dart \
  test/ui/task_console_interaction_test.dart \
  test/ui/orchestration_cli_handler_test.dart \
  test/core/process/owned_process_registry_test.dart

flutter analyze --no-pub --no-fatal-infos
git diff --check
```

`COCKPIT_TASK_TEST_DOTNET` deve apontar para um SDK .NET 10. A fixture é um projeto
.NET independente sem pacotes NuGet externos; o teste a compila em cada worktree.
Nesta máquina o SDK foi instalado temporariamente em `/tmp/cockpit-task-dotnet`,
pois havia somente o runtime. Se a variável for omitida, o teste nativo usa um
servidor HTTP Python com o mesmo protocolo. Sem `COCKPIT_TASK_PTY_TESTS=1`, somente
o teste que exige a biblioteca PTY nativa é pulado; os testes de identidade,
estado de seleção, persistência e reconciliação continuam executando.

A consulta a `cockpit telemetry errors --app` retornou `Originating terminal is
no longer available`; por isso as verificações foram executadas diretamente e
os logs foram mantidos em `/tmp/cockpit-task-isolation-*.log`.

## Resultados obtidos

- 137 testes de regressão aprovados na execução integrada com .NET real,
  cobrindo tasks, terminais, importação, interação do console, roteamento de
  orquestração e propriedade dos processos.
- O teste adicional de CLI passou na execução focal final, após ajustar sua
  asserção para decodificar o campo `text` base64 do protocolo existente:
  **138 cenários distintos aprovados** ao todo.
- Quatro processos .NET simultâneos nos repositórios/worktrees temporários,
  com PIDs e respostas HTTP independentes antes e depois de restart/stop.
- `flutter analyze --no-pub --no-fatal-infos`: exit 0, sem erros ou warnings;
  48 avisos informativos de depreciação existentes no projeto.
- `git diff --check`: aprovado. A árvore de trabalho de `main` permaneceu limpa.
- O PTY usado na validação final foi compilado diretamente do código do
  worktree da correção, em `/tmp/cockpit-task-isolation-pty-build`.

Os testes não dependem de dados dos projetos reais do usuário e apagam os
repositórios, worktrees e configurações temporários ao terminar. O SDK temporário
permanece em `/tmp`; nenhuma instalação global do .NET foi alterada.
