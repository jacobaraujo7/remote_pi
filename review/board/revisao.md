# Canvas Board • revisão de design desktop

Em 14/11/2026, a frente de design percorreu o editor Flutter desta worktree em português, com o tema escuro do Cockpit e uma superfície de 960 × 520 pixels lógicos. As capturas vieram do próprio BoardView em um teste de widget que abriu um fluxo com três etapas e dois conectores.

## Percurso verificado

1. **Selecionar uma etapa — aprovado.** O contorno azul e a alça de conexão identificam “Receber pedido”. O losango e o rótulo “Sim” explicam o caminho também sem cor. Na primeira captura a linha atravessava “Sim”. A frente Flutter abriu espaço em torno do texto e a nova captura confirmou a leitura.

![Etapa selecionada, decisão e legenda Sim com espaço no traço](01-selecao.png)

2. **Abrir a paleta — aprovado.** “Cor do desenho” está visível com a etapa selecionada. Cada opção tem nome e amostra, o visto indica a cor aplicada e “Padrão do tema” permite voltar ao estado inicial. A primeira execução em pt-BR acusou 6,4 px de estouro no menu. Após o ajuste de largura e quebra do texto, o teste concluiu e a captura mostrou os sete itens inteiros.

![Paleta em português com seis cores, opção de tema e marca de seleção](02-paleta.png)

3. **Encontrar uma exportação — aprovado com ressalva.** Ao abrir o menu de intercâmbio, PNG, PDF, HTML e XML ficam juntos na parte superior. As opções específicas de seleção ficam abaixo da dobra nessa altura. Quem quer exportar uma etapa precisa rolar para descobrir a opção. O percurso inspecionou o menu. A validação dos arquivos produzidos pertence aos testes de exportação.

![Menu de intercâmbio aberto com os quatro formatos solicitados visíveis](03-exportar.png)

## Equalização com o padrão do Cockpit

| Prioridade | Evidência e proposta | Responsável e aceite |
| --- | --- | --- |
| Alta | O Kanban e o Canvas usam o mesmo editor na aba e na janela destacada. Preservar essa arquitetura ao ampliar o editor. | Frontend. Abrir o mesmo documento pelos dois caminhos, mover uma forma, salvar, fechar e reabrir com as ligações intactas. |
| Alta | O editor desenha objetos com CustomPainter. A barra tem nomes de ferramentas, mas o widget carece de navegação individual e de leitura das formas por tecnologia assistiva. | Frontend e design. Testar com Narrador no Windows. Navegar por duas etapas, ouvir rótulo e tipo, editar e criar uma conexão usando teclado. |
| Média | O fluxo de exportação mistura o formato e o alcance em uma lista extensa. Usar um controle de alcance com “Documento inteiro” e “Seleção” junto à lista de formatos. Mostrar formatos disponíveis para o alcance escolhido. | Design e frontend. Em um painel dividido, encontrar “Seleção → PNG” com teclado e mouse sem varrer formatos duplicados. |
| Média | O Kanban usa menus e tooltips do shadcn e os tokens comuns. O Canvas já lê context.colors e context.typo, mas usa PopupMenuButton do Material em sua paleta e nas exportações. Avaliar reaproveitamento dos menus existentes. | Frontend. Comparar foco, Escape, densidade e contraste em tema claro, escuro e importado. Validar retorno do foco ao desenho. |
| Média | As capturas do widget verificam composição, seleção e comandos. O relato de atraso pede medição com o Cockpit inteiro em hardware real. | QA desktop. Medir o p95 de construção e rasterização e os frames perdidos a 60 Hz com a cena, a máquina e o modo de compilação identificados. |

O perfil de janela destacada, temas adicionais, leitores de tela, gravação remota e latência física seguem pendentes de validação presencial. O roteiro está no [Kanban de evolução](evolucao-canvas.kanban).

## Registro da demanda

Backend confirmou abertura do JSON v1 e gravação em Markdown v2 com IDs e conexões preservados. A CLI distribuída lista a skill `cockpit-canvas`. Frontend confirmou a integração com `FileViewerSession` e a espera pela fila de gravação antes de fechar uma aba. Para alinhar a leitura de código ao Kanban, a proposta é expor o Markdown na ação de alternar a visualização da aba.

Passaram 26 testes permanentes de Canvas, Gallery e roteamento. Uma verificação adicional produziu o PDF com fonte desktop e conferiu sua leitura após rasterização externa. O analisador Dart concluiu sem apontamentos nos 15 arquivos do Canvas. O teste independente de sincronização do template Dashboard compara LF com CRLF e falha neste checkout Windows.

Responsável local **Canvas Board**, na branch feature/canvas-board do repositório jacobaraujo7/remote_pi. A frente de design concluiu o percurso acima. O próximo passo é validar os itens de teclado, menu de exportação e perfil físico do desktop.

| PR do inventário | Destino | Responsável | Relação e encaminhamento |
| --- | --- | --- | --- |
| [#316](https://github.com/jacobaraujo7/remote_pi/pull/316) | main | moregola | Scrollback do terminal. Continuar com o autor. |
| [#318](https://github.com/jacobaraujo7/remote_pi/pull/318) | main | moregola | Clipboard. Continuar com o autor. |
| [#319](https://github.com/jacobaraujo7/remote_pi/pull/319) | main | moregola | Testes de processos, CLI e painéis. Continuar com o autor. |
