# Canvas Board • revisão de design desktop

Em 14/11/2026, a frente de design percorreu o editor Flutter desta worktree em português, com o tema escuro do Cockpit e uma superfície de 960 × 520 pixels lógicos. As capturas vieram do próprio BoardView em um teste de widget que abriu um fluxo com três etapas e dois conectores.

## Percurso da primeira revisão

1. **Selecionar uma etapa — aprovado.** O contorno azul e a alça de conexão identificam “Receber pedido”. O losango e o rótulo “Sim” explicam o caminho também sem cor. Na primeira captura a linha atravessava “Sim”. A frente Flutter abriu espaço em torno do texto e a nova captura confirmou a leitura.

![Etapa selecionada, decisão e legenda Sim com espaço no traço](01-selecao.png)

2. **Abrir a paleta — aprovado.** “Cor do desenho” está visível com a etapa selecionada. Cada opção tem nome e amostra, o visto indica a cor aplicada e “Padrão do tema” permite voltar ao estado inicial. A primeira execução em pt-BR acusou 6,4 px de estouro no menu. Após o ajuste de largura e quebra do texto, o teste concluiu e a captura mostrou os sete itens inteiros.

![Paleta em português com seis cores, opção de tema e marca de seleção](02-paleta.png)

3. **Exportar o fluxo ou uma seleção.** A ação Exportar permanece visível no cabeçalho. Primeiro se escolhe o alcance e depois o formato. A captura em português mostra os dois caminhos.

![Menu Exportar com documento inteiro e seleção](03-exportar.png)

![Nove formatos de exportação do documento](04-formatos-documento.png)

![Quatro formatos para uma seleção](05-formatos-selecao.png)

## Propostas da primeira revisão

| Prioridade | Evidência e proposta | Responsável e aceite |
| --- | --- | --- |
| Alta | O Kanban e o Canvas usam o mesmo editor na aba e na janela destacada. Preservar essa arquitetura ao ampliar o editor. | Frontend. Abrir o mesmo documento pelos dois caminhos, mover uma forma, salvar, fechar e reabrir com as ligações intactas. |
| Alta | O editor desenha objetos com CustomPainter. A barra tem nomes de ferramentas, mas o widget carece de navegação individual e de leitura das formas por tecnologia assistiva. | Frontend e design. Testar com Narrador no Windows. Navegar por duas etapas, ouvir rótulo e tipo, editar e criar uma conexão usando teclado. |
| Média | O fluxo de exportação mistura o formato e o alcance em uma lista extensa. Usar um controle de alcance com “Documento inteiro” e “Seleção” junto à lista de formatos. Mostrar formatos disponíveis para o alcance escolhido. | Design e frontend. Em um painel dividido, encontrar “Seleção → PNG” com teclado e mouse sem varrer formatos duplicados. |
| Média | O Kanban usa menus e tooltips do shadcn e os tokens comuns. O Canvas já lê context.colors e context.typo, mas usa PopupMenuButton do Material em sua paleta e nas exportações. Avaliar reaproveitamento dos menus existentes. | Frontend. Comparar foco, Escape, densidade e contraste em tema claro, escuro e importado. Validar retorno do foco ao desenho. |
| Média | As capturas do widget verificam composição, seleção e comandos. O relato de atraso pede medição com o Cockpit inteiro em hardware real. | QA desktop. Medir o p95 de construção e rasterização e os frames perdidos a 60 Hz com a cena, a máquina e o modo de compilação identificados. |

O perfil de janela destacada, temas adicionais, leitores de tela, gravação remota e latência física seguem pendentes de validação presencial. O roteiro está no [Kanban de evolução](evolucao-canvas.kanban).

## Entrega local após a revisão

O editor e o harness trabalham sobre o mesmo arquivo Markdown v3. A Gallery, a aba e a janela destacada usam o fluxo de documentos do Cockpit. O menu da aba e o controle de modo da janela alternam Quadro e Markdown com proteção do rascunho. Um teste em disco usa o arquivo de exemplo da skill, substitui seu conteúdo pelo fluxo de um harness e verifica a recarga pelo watcher e uma edição gráfica posterior.

A paleta e a exportação usam o componente de menu do Cockpit. O botão **Exportar** abre primeiro o alcance e depois o formato. O documento inteiro oferece PNG, PDF, XML, HTML, SVG, Markdown, draw.io, Excalidraw e Mermaid. A seleção oferece PNG, PDF, HTML e SVG. O diálogo sugere o nome do documento com a extensão escolhida.

O teclado percorre as formas e conexões, move a seleção e escolhe origem e destino da seta. Os testes verificam a árvore semântica e a identidade de objetos sobrepostos. O enquadramento acomoda formas com coordenadas negativas e além dos limites iniciais. A paleta e o rodapé foram testados em painéis de 280 e 420 pixels. Validação manual com Narrador, latência física e cinco sessões com pessoas continuam no Kanban.

Passaram 43 testes do domínio, editor, janela de documento, arquivos e Gallery. O teste de exportação escolheu cada um dos nove formatos pelo menu e conferiu sua gravação em disco com o nome do documento. O diálogo de destino foi substituído por um seletor de teste. A análise dos 20 arquivos de Canvas e benchmark terminou sem apontamentos e a compilação Windows Release foi concluída.

O [perfil de arraste](perfil.md) registra três rodadas por versão e tamanho de cena. Na versão atual, nenhum dos 1.440 quadros amostrados excedeu 16,67 ms por fase.

## Registro da demanda

Responsável local **Canvas Board**, branch feature/canvas-board, destino main. Inventário atualizado diretamente no repositório em 14/11/2026. Próximo passo de QA: consolidar o perfil no desktop e os resultados da validação com pessoas.

| PR do inventário | Destino | Responsável | Relação e encaminhamento |
| --- | --- | --- | --- |
| [#316](https://github.com/jacobaraujo7/remote_pi/pull/316) | main | moregola | Scrollback do terminal. Continuar com o autor. |
| [#318](https://github.com/jacobaraujo7/remote_pi/pull/318) | main | moregola | Clipboard. Continuar com o autor. |
| [#319](https://github.com/jacobaraujo7/remote_pi/pull/319) | main | moregola | Testes de processos, CLI e painéis. Continuar com o autor. |
