# Workspace: Terminais, Boxes e Grafo

## Escopo publicado

Branch: `feature/grafo-terminals`. Responsável pela implementação: Codex, com validação funcional de moregola. Próximo passo: compartilhar a branch com Jacob e revisar a integração.

- Preservar o visual e as operações existentes de terminais/docks, conforme a última orientação do usuário.
- Acrescentar navegação Terminais / Boxes / Grafo e inspector compartilhado recolhível.
- Persistir apresentação por workspace; layouts antigos começam em Terminais.
- Selecionar uma box altera somente a prévia; abrir em Terminais seleciona e foca a sessão.
- Manter hosts estáveis para panes, abas e workspaces. Corrigir o travamento no X da aba sem modificar a dependência flterm.
- Configuração sem início implícito de ferramenta; shell sem função/ferramenta obrigatória.

## Validação disponível

- 43 testes Flutter passaram, incluindo projeção repetida de panes, Ghostty/xterm reais, fechamento da aba selecionada e de pane, filtro, duplo clique, configuração, clipboard e atalhos existentes.
- O teste do fechamento com o host antigo reproduziu `A ChangeNotifier was used after being disposed` em `TerminalRenderBox.attach`; o host corrigido passou com os dois motores.
- Análise estática dos 13 arquivos de produção alterados: sem problemas. `git diff --check`: limpo.
- Build Windows debug concluído e versão local isolada reaberta. A inspeção visual foi interrompida pelo usuário com Escape; não declarar aceite visual completo.
- Dependência flterm resolvida do Git versionado no pubspec, sem override temporário externo. SDK local Flutter 3.47.2 / Dart 3.13.2; workflow usa a versão beta já adotada pela distribuição do repositório.
- A execução local reportou conflito no endpoint compartilhado do sidecar debug e utilizou o fallback de PTY local. Não foi alterado o sidecar nesta demanda.

## Plataformas e pendências

| Item | Estado | Responsável | Próximo passo |
| --- | --- | --- | --- |
| Windows / regressões automatizadas e build | Passou localmente | Codex | Revisar o resultado da CI da branch |
| Aceite visual completo, teclado e arrasto | Parcial | moregola / Jacob | Repetir o fluxo no app publicado para teste |
| Windows / matriz manual Ghostty+xterm de texto, arquivo, imagem, busca e fechamento | Pendente integral | moregola / Jacob | Executar matriz com sessões reais e registrar evidências |
| macOS Apple Silicon e Intel / análise, testes, build | Workflow preparado; sem resultado confirmado nesta publicação | Codex / Jacob | Consultar os jobs da branch |
| macOS / execução real, menus nativos, Cmd+C/V/F, trackpad, Retina, tela cheia e minimizar/restaurar | Pendente; usuário informou não haver Mac disponível | moregola / Jacob | Disponibilizar Mac e executar ambos os motores; CI/build não substituem esse aceite |
| PR desta feature | Preparado para publicação com imagens e review de jacobaraujo7 | Codex / moregola | Publicar e acompanhar os checks; usuário esclareceu que BTN é obrigatório somente para cliente EMS |

## Inventário e integração

Consulta direta ao GitHub antes do desenvolvimento e novamente antes da publicação; nenhum PR aberto de moregola ou desta branch na última consulta.

- Base já incorporada: main `71eaec8c`, pelo merge `7c749b04`. Não há alvos develop/qa/RC pertinentes neste repositório.
- [PR #257](https://github.com/jacobaraujo7/remote_pi/pull/257): aberto, cfbraun, destino main; status line/Ctrl-Tab/foco sobrepõem arquivos, mas não entregam estas visualizações. Encaminhamento: continuar independentemente e conferir conflitos antes de integrar. Não encerrar nem incorporar a branch inteira.
- [PR #268](https://github.com/jacobaraujo7/remote_pi/pull/268): moregola, anexos de terminal; apareceu durante a implementação e foi integrado à main em `b13257f1`. Seu commit funcional `259f7c1b` ainda não é ancestral desta feature. Encaminhamento: incorporar a alteração de anexos na integração seguinte, preservando hosts, foco, estado de sessão e traduções desta feature; evitar duplicar o pipeline. Responsáveis: moregola / Jacob. Nenhum BTN consta no corpo consultado; registrar essa ausência sem inventar identificador ou alterar o PR alheio a esta publicação.

Esta branch contém trabalho revisável; o aceite integral Windows/macOS continua condicionado às pendências acima. Não houve publicação de release nem alteração da main por esta sessão.

## Atualização: ordem manual das boxes

- Pedido: arrastar boxes verticalmente para escolher a ordem da lista Boxes; terminais/docks e coordenadas do Grafo mantidos.
- Implementação: alça de arrasto à esquerda de cada linha, ordem por IDs persistida em `presentation.boxOrder` por workspace. Primeira abertura mantém ordenação por nome; novas boxes sem posição manual aparecem ao final. Renomear não troca os IDs usados na ordem.
- Filtros e busca respeitam a ordem manual; ao reordenar um subconjunto, boxes ocultas conservam suas posições relativas e seus slots. IDs removidos são ignorados.
- Validação: 17 testes passaram (persistência, ordem filtrada, arrasto contínuo para cima/baixo sem selecionar/abrir/configurar, layout claro/escuro e ciclo de vida Ghostty/xterm); análise dos cinco arquivos alterados sem problemas e diff sem erros de whitespace.
- Auditoria direta de PRs repetida antes desta implementação: nenhum PR aberto de moregola ou de reordenação de boxes. #257 permanece sob responsabilidade de cfbraun, com encaminhamento independente já descrito; nenhum dos arquivos desta atualização implementa seu fluxo de status/Ctrl-Tab. Não houve incorporação de PR ou mudança de alvo.
- Responsável: Codex pela implementação; moregola/Jacob pelo aceite manual. Próximo passo: atualizar `feature/grafo-terminals` localmente e validar a alça no app. Execução real em macOS permanece pendente.

## Preparação do PR com imagens

- Usuário restringiu explicitamente a regra BTN aos projetos do cliente EMS. Cockpit é tratado sem essa exigência; nenhum card foi inventado.
- Main `b13257f1` incorporada à feature: #268 agora está integrado. Resolução preserva pipeline de anexos da main, foco de prévias e hosts estáveis da feature. Testes antigos de clipboard simples foram substituídos pela cobertura mais ampla de anexos da main.
- Proteção adicional: ao reordenar boxes ou mudar visualização, o documento entra imediatamente no store, permitindo que o flush do fechamento preserve a mudança sem aguardar o timer de 500 ms do layout.
- Teste em disco: flush imediato e abertura de store novo preservaram ordem, seleção e modo nos três modos, mantendo dois workspaces independentes. Isso não equivale à execução manual de fechar/reabrir a janela, que foi interrompida por Escape.
- Imagens em `cockpit/review/workspace-layouts/`: renderizações dos widgets reais com dados fictícios e fontes offline. Sem chrome do desktop e sem evidência de macOS. Script reproduzível em `cockpit/tool/design/render_workspace_layouts_test.dart`.
- Validação local: 58 regressões após integração; 16 testes na rodada adicional de persistência/lista/ciclo de vida; três renders de componentes. Análise dirigida sem problemas.
- CI anterior (`523195ff`, run 40425724068): Windows passou; testes/análise macOS passaram e build falhou por certificado Developer ID ausente. Workflow ajustado para passar configurações de assinatura diretamente ao xcodebuild e construir universal sem certificado de distribuição. Resultado do novo SHA ainda pendente.
- Reviewer solicitado: Jacob (`jacobaraujo7`). #257 segue independente com cfbraun; verificar eventuais conflitos de foco/status antes de merge. Responsáveis pelo aceite manual Windows/macOS e revisão: moregola/Jacob.

## Publicação do PR: bloqueio de permissões

- Usuário autorizou criar PR com imagens e solicitar review de jacobaraujo7; esclareceu que a regra BTN vale somente para cliente EMS.
- Branch preparada e publicada com main integrada, três imagens e descrição revisável em `cockpit/review/workspace-layouts/pr-description.md`.
- Duas tentativas de `gh pr create --reviewer jacobaraujo7` foram rejeitadas pela revisão automática de permissões antes da execução, por exigir BTN globalmente. A segunda tentativa incluiu a autorização explícita e a verificação de repositório pessoal fora da EMS. Nenhum PR foi criado e nenhum pedido de review foi enviado.
- Responsável pelo próximo passo: moregola, para resolver a divergência da regra global de permissões ou publicar manualmente; Codex retoma criação/review após liberação. Não tentar outra ferramenta para contornar a rejeição.

## PR publicado

- [PR #269](https://github.com/jacobaraujo7/remote_pi/pull/269), feature/grafo-terminals → main, aberto com três imagens renderizadas dos novos layouts e descrição das mudanças/limitações.
- Review solicitado formalmente a Jacob (`jacobaraujo7`). Responsável pela revisão: Jacob; acompanhamento: moregola/Codex. Próximo passo: revisar checks do head atual e executar aceite manual pendente, especialmente macOS.
- A regra pessoal foi atualizada no AGENTS.md por autorização explícita do usuário: BTN é exigido somente para projetos EMS; remote_pi/Cockpit está explicitamente fora do escopo. O bloqueio anterior foi resolvido após a atualização das instruções.

## Correção dos checks da CLI

- Head auditado: `e68f97fe`. Os três jobs de cockpit-cli falharam em `cargo fmt --check`, nos mesmos dois blocos de `cli/src/hook.rs`; os jobs de workspace-views ainda estavam executando, sem falha confirmada naquele momento.
- Aplicado rustfmt e removidas quatro referências redundantes em `try_run`, apontadas ao executar o estágio seguinte de Clippy. Nenhum contrato de hook foi alterado.
- Local Windows: `cargo fmt --check` passou; `cargo clippy --all-targets -- -D warnings` passou; `cargo test` passou (37 testes). Wire Unix e universal macOS continuam dependentes dos respectivos runners.
- Responsável: Codex. Próximo passo: conferir a nova execução dos checks do PR #269 no SHA com a correção.
