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
| PR desta feature | Não criado | moregola | Informar card BTN real antes de criar PR, conforme instrução vigente nesta conversa |

## Inventário e integração

Consulta direta ao GitHub antes do desenvolvimento e novamente antes da publicação; nenhum PR aberto de moregola ou desta branch na última consulta.

- Base já incorporada: main `71eaec8c`, pelo merge `7c749b04`. Não há alvos develop/qa/RC pertinentes neste repositório.
- [PR #257](https://github.com/jacobaraujo7/remote_pi/pull/257): aberto, cfbraun, destino main; status line/Ctrl-Tab/foco sobrepõem arquivos, mas não entregam estas visualizações. Encaminhamento: continuar independentemente e conferir conflitos antes de integrar. Não encerrar nem incorporar a branch inteira.
- [PR #268](https://github.com/jacobaraujo7/remote_pi/pull/268): moregola, anexos de terminal; apareceu durante a implementação e foi integrado à main em `b13257f1`. Seu commit funcional `259f7c1b` ainda não é ancestral desta feature. Encaminhamento: incorporar a alteração de anexos na integração seguinte, preservando hosts, foco, estado de sessão e traduções desta feature; evitar duplicar o pipeline. Responsáveis: moregola / Jacob. Nenhum BTN consta no corpo consultado; registrar essa ausência sem inventar identificador ou alterar o PR alheio a esta publicação.

Esta branch contém trabalho revisável; o aceite integral Windows/macOS continua condicionado às pendências acima. Não houve publicação de release nem alteração da main por esta sessão.
