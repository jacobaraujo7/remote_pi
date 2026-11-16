# Como o canvas do Board deve responder

## O problema observado

Uma pessoa tentou alterar o texto de uma etapa olhando para o próprio fluxograma. O editor mantinha o campo de edição no rodapé. O teste original digitava nesse campo e passou mesmo quando o fluxo de uso esperado falhava. Em outro gesto, mover uma etapa exigia recalcular o layout dos rótulos das outras etapas. A pessoa percebeu atraso entre o ponteiro e a forma.

Este estudo combina esses dois relatos, inspeção do editor, uma medição local do renderizador e documentação primária de ferramentas comparáveis. A amostra de uso humano é de uma pessoa. As próximas sessões propostas no plano devem avaliar descoberta das ferramentas e operação pelo teclado.

## Referências e decisões para o Cockpit

| Interação | Evidência externa | Decisão de produto |
| --- | --- | --- |
| Conectar duas formas | O draw.io exibe pontos de ação perto da forma e oferece alternativas por teclado. [Manual de conectores](https://www.drawio.com/docs/manual/connectors/connect-shapes/) | Manter a conexão por dois cliques. Destacar o destino válido antes de soltar e oferecer criação a partir da própria forma. |
| Navegar sem perder a seleção | O Miro distingue mouse, trackpad e toque e mantém controles de zoom e enquadramento acessíveis. [Navegação no Miro](https://help.miro.com/hc/en-us/articles/360017731053-Using-Miro-with-a-mouse-trackpad-or-touchscreen) | Manter zoom visível e posição da câmera previsível. Reservar Espaço para navegação temporária quando o foco estiver no desenho. |
| Operar sem arrastar | A orientação WCAG 2.2 descreve alternativas de ponteiro simples para ações de arraste e distingue essa necessidade da acessibilidade por teclado. [W3C, movimentos de arraste](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html) | Preservar o clique para inserir e conectar. Acrescentar “mover para cá” e navegação individual por objeto. Validar ambos separadamente. |
| Diagnosticar atraso | Flutter distingue construção e rasterização e orienta medir em hardware real com código otimizado. [Perfil de desempenho](https://docs.flutter.dev/perf/ui-performance) | Isolar o conteúdo parado durante o arraste. Repetir a medição com o Cockpit inteiro, inclusive com outro painel ativo. |

## Redesign aplicado ao editor Flutter


O nome do documento e as ações sobre o arquivo ficam no cabeçalho. A faixa lateral reúne os instrumentos de desenho. Em painéis baixos ela rola e mantém o canvas no mesmo lugar quando se abrem ferramentas avançadas. O rodapé indica a próxima ação do conector e a escala atual. Os botões de zoom ampliam pelo centro da área visível, e clicar no percentual recupera 100%. A paleta, a tipografia e o foco usam o tema do Cockpit.

Texto e nota abrem um campo no local de inserção. O duplo clique edita um objeto existente. F2 abre o mesmo campo sobre a seleção. O clique fora confirma e Escape descarta. Um teste simula cada gesto e verifica o documento gravado. O desenho de texto preserva a identidade do objeto e das conexões.

## Desempenho e critério de aceite proposto

No ensaio local com 240 formas, 239 conexões e um movimento sintético por frame, o p95 de construção caiu de 25,25 ms para 0,96 ms. O p95 de rasterização caiu de 4,00 ms para 1,62 ms. As duas fases podem trabalhar em paralelo. Somá-las não fornece a latência do ponteiro. O ensaio histórico usou 180 movimentos sintéticos por versão e descartou os 20 primeiros registros. O auxiliar de medição encerrou com erro após coletar as séries. Falta repetir a medição na versão atual.

Para avaliar a experiência real, repetir três vezes em cada máquina, alternando a ordem das versões e aquecendo a cena. Usar cenas vazia, média e densa, incluir traço longo, zoom, movimento de grupo e inserção de um diagrama Mermaid. Registrar frequência do monitor, p95 por fase, proporção de frames acima do orçamento e tempos de gravação. Meta inicial a 60 Hz: p95 de cada fase abaixo de 16,7 ms e menos de 1% dos frames acima desse orçamento após aquecimento. Para latência física usar filmagem de alta velocidade ou instrumentação de entrada e apresentação. Ainda não há uma medição física neste estudo.

### Cor como informação

A paleta no rodapé aplica cor a uma seleção ou aos próximos objetos quando uma ferramenta de desenho está ativa. O fluxo de exemplo usa azul para entrada, âmbar para decisão e verde para o caminho aprovado. Esses significados pertencem ao desenho. Manter “Aprovado?” no losango e “Sim” na seta permite compreender o caminho mesmo quando duas cores parecem iguais. A opção de tema recupera a aparência original; mudar a cor pode ser desfeito como uma única edição.

## Roteiro de observação local

Em cada uma das cinco sessões, abrir um workspace local vazio e entregar a mesma tarefa por escrito. “Desenhe um fluxo que começa com um pedido e termina numa decisão. Renomeie a primeira etapa para ‘Receber pedido’, ligue-a à decisão e salve uma cópia do desenho em PNG.” Deixar a pessoa escolher os gestos. Registrar por tarefa a conclusão sem ajuda, ações equivocadas, perda de seleção e qualquer intervenção. Abrir o PNG ao final. A meta do plano é que pelo menos quatro pessoas concluam as quatro tarefas sem ajuda. Ainda não há resultados de participantes.

Para o percurso assistivo, ativar o Narrador e entrar no desenho pelo teclado. Registrar o que ele anuncia ao selecionar e mover a primeira etapa, renomeá-la, escolher o destino da conexão e voltar do menu de exportação. Para o trackpad, enquadrar o documento, selecionar a decisão, aplicar zoom e enquadrar a seleção. Conferir que o mesmo objeto continua selecionado. A latência física exige registrar o gesto e a primeira resposta visível no mesmo relógio, informando frequência da captura e do monitor.
