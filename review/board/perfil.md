# Perfil de arraste do Canvas Board no Windows

Em 14 de novembro de 2026 foram comparados o BoardView e o BoardPainter de ad562c19 com os da worktree feature/canvas-board. O teste arrasta a primeira etapa de um fluxo com um conector incidente. A pergunta medida é quanto tempo o Flutter gasta construindo e rasterizando cada quadro durante o gesto contínuo.

## Ambiente

Windows 11 Pro 10.0.26200, AMD Ryzen 7 5700X com 16 processadores lógicos, NVIDIA GeForce RTX 3060 e aproximadamente 32 GiB de RAM. O Windows informou resolução de 3440 × 1440 e 159 Hz. O Flutter informou 160 Hz para o display da janela. Flutter 3.47.2, Dart 3.13.2, app Dart AOT e engine Windows x64 em modo Profile, Impeller desativado pelo runner do Cockpit. O teto observado para esse display é 6,25 ms por fase. O estudo também verifica a meta acordada de 16,67 ms por fase para 60 Hz.

## Método

1. Cada cena contém N etapas rotuladas distribuídas em linhas de 20, N − 1 conectores, um traço de 3.000 pontos e um item Mermaid com miniatura PNG de 1 × 1. N assume os valores 32, 240 e 960. O total é respectivamente 65, 481 e 1.921 objetos. A miniatura exercita a camada de imagem do editor; o renderizador de fonte Mermaid não é executado durante esse gesto.
2. Montar o editor com o tema escuro e um painel estático adjacente de 160 px. Aguardar dois segundos. Injetar um movimento de mouse por quadro durante 180 quadros. O nó termina 84 unidades à direita e quatro abaixo do ponto inicial. A gravação simula 120 ms de espera e ocorre ao soltar. O teste exige exatamente uma gravação e confere as coordenadas persistidas.
3. Usar três execuções de cada versão por cena, alternando a ordem na segunda repetição. Ignorar os primeiros 20 movimentos e cruzar os identificadores dos 160 quadros seguintes com FrameTiming.frameNumber. Desse modo, montar a cena, finalizar o gesto, salvar o documento e aguardar callbacks do motor ficam fora das amostras de arraste.
4. Calcular o p95 de construção e o p95 de rasterização sobre os 160 quadros de cada execução. Resumir as três execuções pela mediana dos seus p95. Na contagem acima do orçamento, computar um quadro uma vez se qualquer fase exceder o limiar. Construção e rasterização podem se sobrepor.

O benchmark local usa somente a aplicação Flutter e a sessão de arquivo em memória. O baseline foi obtido com git show de ad562c19, com imports redirecionados e adaptação do caminho de arquivo do botão de exportação à assinatura atual. Os componentes externos ao editor, o modelo de documento, as fontes e o runner são os mesmos entre as versões. A cópia histórica ficou no diretório temporário de build.

## Resultados

Rodada final com as compilações nativas e AOT encerradas. Na abertura da rodada, a instalação da build Release copiava assets em segundo plano. Cada linha contém 480 quadros. Foram correlacionados todos os 2.880 quadros previstos nas 18 execuções.

| Objetos | Editor | Mediana do p95 de construção (ms) | Mediana do p95 de rasterização (ms) | Quadros acima de 16,67 ms | Quadros acima de 6,25 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 65 | ad562c19 | 0,889 | 2,549 | 0 | 0 |
| 65 | Atual | 0,777 | 1,584 | 0 | 0 |
| 481 | ad562c19 | 0,794 | 1,984 | 0 | 0 |
| 481 | Atual | 0,695 | 1,693 | 0 | 1 |
| 1921 | ad562c19 | 0,704 | 2,148 | 0 | 0 |
| 1921 | Atual | 0,742 | 2,114 | 0 | 0 |

No editor atual, nenhum dos 1.440 quadros ultrapassou 16,67 ms. Em um quadro, uma das fases ultrapassou o orçamento de 6,25 ms do display. O arraste contínuo atende à meta de 60 Hz nestas três cenas. O resultado orienta medir o início do gesto e a primeira pintura de traços e diagramas grandes antes de atribuir o atraso relatado ao Flutter.

### Repetições

| Formas | Editor | Execução | Construção p95 (ms) | Rasterização p95 (ms) | Quadros acima de 6,25 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 32 | ad562c19 | 1 | 0,738 | 1,924 | 0 |
| 32 | Atual | 1 | 0,746 | 1,571 | 0 |
| 32 | Atual | 2 | 0,782 | 1,765 | 0 |
| 32 | ad562c19 | 2 | 0,889 | 2,566 | 0 |
| 32 | ad562c19 | 3 | 0,909 | 2,549 | 0 |
| 32 | Atual | 3 | 0,777 | 1,584 | 0 |
| 240 | ad562c19 | 1 | 0,607 | 1,492 | 0 |
| 240 | Atual | 1 | 0,623 | 1,401 | 0 |
| 240 | Atual | 2 | 0,695 | 1,693 | 0 |
| 240 | ad562c19 | 2 | 0,794 | 1,984 | 0 |
| 240 | ad562c19 | 3 | 0,877 | 2,151 | 0 |
| 240 | Atual | 3 | 0,891 | 1,874 | 1 |
| 960 | ad562c19 | 1 | 0,65 | 1,821 | 0 |
| 960 | Atual | 1 | 0,849 | 2,266 | 0 |
| 960 | Atual | 2 | 0,742 | 2,051 | 0 |
| 960 | ad562c19 | 2 | 0,704 | 2,148 | 0 |
| 960 | ad562c19 | 3 | 0,832 | 2,577 | 0 |
| 960 | Atual | 3 | 0,705 | 2,114 | 0 |

### Encerramento do runner

O executável auxiliar do perfil retornou 0xC0000005 ao finalizar, depois de gravar as 18 séries e validar os 18 salvamentos. O erro ocorreu no piloto com destruição da janela e no ensaio final com exit(0), usado pelo benchmark do terminal. O relatório preserva a ressalva de encerramento. O teste não avalia o ciclo de fechamento do aplicativo distribuído. O runner nativo Profile, a engine x64 Profile do SDK e o AOT final foram usados isoladamente em build/board-profile-review após o alvo INSTALL do CMake falhar durante a cópia conjunta dos artefatos. SHA-256 do AOT medido: 6A76DAAC351C976647ACBB31EA9051407428715EBD72AFDACB44C2B807A1CB30.

## Repetir

Na pasta cockpit, finalizar as compilações da aplicação antes de iniciar a medição. Para medir apenas a revisão em uso, executar flutter run --profile -d windows -t benchmark/board_profile.dart. A variável BOARD_PROFILE_RESULT aceita um caminho absoluto para o TSV. Para o comparativo, um entrypoint temporário passa o construtor histórico a runBoardProfile(baseline: old.BoardView.new). O bloco abaixo ilustra as duas importações quando o entrypoint e a cópia histórica ficam em build/board-profile-review.

```dart
import '../../benchmark/board_profile.dart';
import 'board_view.dart' as old;

Future<void> main() => runBoardProfile(baseline: old.BoardView.new);
```

O experimento mede o arraste sintético de uma etapa depois do aquecimento. Uma área de trabalho com aplicações ativas e um único computador limitam a generalização. A medição no monitor de 160 Hz compara também com o orçamento de 60 Hz; o monitor permaneceu em sua configuração original.

## Escrita livre, zoom e abertura de um documento denso

Em uma segunda rodada, o mesmo processo Profile comparou o editor de `d50628ed` com a camada que limita a pintura estática à área visível mais uma margem de 25% e oito unidades. A cena contém 960 etapas, 959 conectores e uma miniatura de arquitetura PNG de 640 × 320 com rótulos e caminhos. O editor exibe a miniatura em um objeto de 320 × 160. A mesma fonte Mermaid e o mesmo PNG foram usados nas duas versões. A ordem das versões foi invertida na segunda das três repetições.

**Primeira pintura.** Um host Flutter já montado recebe um BoardView novo. O primeiro frame é identificado pelo número do motor. Separadamente, um cronômetro vai da montagem até o primeiro RawImage com a miniatura decodificada. A leitura do arquivo e a preparação dos bytes do PNG antecedem o cronômetro. O cache de imagens foi limpo entre as execuções.

**Gestos.** Escrita livre injeta 16 movimentos por frame, por 180 frames. O primeiro deslocamento mede uma unidade. O teste reabre o `.board` e confere as coordenadas de todos os 2.881 pontos, inclusive o primeiro e o último. O zoom usa 180 pulsos reais do caminho de eventos Flutter da roda, alternando o sentido a cada dez, confere ampliação acima de 1,4×, retorno à escala inicial e arquivo idêntico. O arraste move oito etapas e a miniatura juntas em 84 × 4 unidades. O teste confere todos os objetos, grupos, destinos e origens após reabrir o arquivo. O salvamento introduz 120 ms de espera e faz flush em disco, depois do gesto.

Cada linha da tabela corresponde à mediana das três execuções. Construção e rasterização são os p95 por execução. O primeiro frame tem uma única amostra por abertura. A cadência mede o intervalo de relógio entre duas conclusões de frame com movimento e inclui o processamento síncrono do evento. A duração total dos 180 passos inclui os 20 de aquecimento. O cronômetro de miniatura é apresentado apenas no cenário de abertura.

| Cenário | Versão | Construção (ms) | Rasterização (ms) | Intervalo p95 (ms) | 180 passos (s) | Miniatura disponível (ms) | Fases acima de 16,67 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Primeira pintura | d50628ed | 82,50 | 4,27 | — | — | 513,84 | 3/3 |
| Primeira pintura | Com recorte | 23,67 | 3,46 | — | — | 47,09 | 2/3 |
| Escrita livre | d50628ed | 0,23 | 3,44 | 7,56 | 1,17 | — | 0/480 |
| Escrita livre | Com recorte | 0,27 | 3,57 | 7,49 | 1,13 | — | 0/480 |
| Zoom | d50628ed | 0,81 | 3,67 | 287,91 | 40,53 | — | 0/480 |
| Zoom | Com recorte | 0,71 | 2,44 | 10,35 | 1,23 | — | 0/480 |
| Grupo com miniatura | d50628ed | 0,86 | 1,66 | 7,75 | 1,37 | — | 0/480 |
| Grupo com miniatura | Com recorte | 0,82 | 1,38 | 8,06 | 1,13 | — | 0/480 |

No zoom, o p95 de rasterização da referência ficou baixo apesar de a cadência ultrapassar 250 ms entre passos. O recorte reduziu a duração mediana do mesmo gesto de 40,53 s para 1,23 s. Na abertura, a primeira construção ainda excedeu o orçamento de 16,67 ms em duas das três execuções com recorte. O teste de câmera também exercitou seleção de uma forma inicialmente fora do quadro, enquadramento e retorno após gesto de trackpad, preservando o conteúdo salvo.

Para repetir essa suíte, definir `BOARD_PROFILE_SUITE=interactions` e escolher a saída com `BOARD_PROFILE_RESULT`. A função `runBoardProfile` aceita um construtor histórico para executar as duas variantes no mesmo processo. O TSV inclui as 24 amostras por cenário e repetição, contagens, duração real dos gestos e frequência do display. O benchmark validou todas as 24 séries e as 12 gravações de arquivo antes do erro nativo de encerramento 0xC0000005 no runner auxiliar. SHA-256 do AOT pareado medido: E9777A24498860838F861E6564D0BA171F271087A619E92E605CFBDB960D4051. A latência física de um mouse ou caneta até a apresentação no monitor permanece fora do ensaio.

## Leitura do Markdown e abertura isolada

Em 14/11, um executável Dart AOT comparou o leitor de a467d39d com o leitor que evita cópias intermediárias de propriedades e só procura sequências de escape quando o campo contém barra invertida. O documento tinha 960 formas rotuladas, 959 setas e um objeto Mermaid sem miniatura. As versões alternaram a ordem dentro do mesmo processo. Após dez aquecimentos, 60 amostras por versão mediram a conversão da mesma fonte já lida. A verificação comparou o Markdown regravado e a contagem de 1.920 objetos.

A mediana da conversão passou de 4,20 para 3,04 ms. O p95 passou de 6,36 para 5,39 ms. Ler o arquivo com cache local levou 0,22 ms na mediana. Em uma segunda rodada, calcular os extremos das formas já decodificadas levou 0,028 ms na mediana. Esse cálculo isolado não inclui roteamento das setas nem layout Flutter.

O modo `BOARD_PROFILE_SUITE=opening` executa somente as três aberturas da cena com miniatura representativa no benchmark Flutter. A primeira rodada produziu tempos de construção de 31,35, 16,33 e 10,54 ms. Uma repetição após encerrar a suíte de testes produziu 38,06, 27,57 e 18,64 ms, com a miniatura pronta em 65,48, 69,59 e 45,16 ms. A variação entre processos impede atribuir um ganho de primeira pintura à mudança no leitor. O evento 1000 do Windows registrou o erro de encerramento do runner em coremessaging.dll após a gravação das amostras. Pedir saída pelo ciclo de vida do Flutter também reproduziu esse erro.
## Abertura em um painel já montado

O modo `BOARD_PROFILE_SUITE=pane` mede em quadros distintos a criação do host visual e a inserção do BoardView. O host usa o tema e as traduções do Cockpit com um painel adjacente. Após o quadro do host, o benchmark espera 500 ms e insere o editor com o Markdown já disponível na sessão. O arquivo e a miniatura são os mesmos do modo `opening`. O modo representa a montagem de um painel dentro do Flutter; o cronômetro começa depois da inicialização do processo e da leitura do arquivo.

Quatro processos Profile executaram, na ordem, painel, montagem conjunta, montagem conjunta e painel. Cada processo abriu a cena de 1.920 objetos três vezes. A tabela lista a construção em milissegundos na ordem das aberturas. A coluna do host usa o número do quadro em que ele apareceu vazio.

| Processo | Host vazio | Primeiro quadro com o editor |
| --- | --- | --- |
| Painel 1 | 1,68 / 1,57 / 1,10 | 25,39 / 15,03 / 9,90 |
| Conjunto 1 | — | 26,94 / 14,69 / 16,71 |
| Conjunto 2 | — | 22,02 / 22,28 / 11,89 |
| Painel 2 | 3,33 / 1,39 / 2,37 | 25,11 / 14,42 / 12,02 |

Em painel, a primeira rasterização de cada processo levou 24,60 e 26,82 ms; nas quatro reaberturas ficou entre 2,28 e 3,88 ms. A primeira construção e a primeira rasterização do editor excederam o orçamento mesmo com o host pronto. As quatro reaberturas nessa configuração respeitaram 16,67 ms por fase. Todos os arquivos permaneceram idênticos, e as 12 aberturas produziram amostras antes da falha nativa já documentada no encerramento dos quatro processos. O carregamento de uma janela nativa inteira e a latência física continuam fora deste ensaio.

## Custo dos controles e dos rótulos

No modo `pane`, `BOARD_PROFILE_SCENE` permite escolher `empty` (só os controles e o canvas vazio), `unlabelled` (960 etapas sem texto, 959 setas e uma miniatura Mermaid) ou `full` (o mesmo desenho com os 960 rótulos). Foram abertas três cenas por processo, em seis processos independentes. A sequência foi vazio, sem rótulos, completo, completo, sem rótulos, vazio. Os controles, o tema, a sessão e a validação do arquivo foram os mesmos em todos os casos. A criação da imagem de teste antecedeu o cronômetro em todos os processos.

| Cena | Primeira construção em cada processo (ms) | Primeira rasterização em cada processo (ms) |
| --- | --- | --- |
| Vazio | 14,95 / 19,15 | 15,35 / 14,41 |
| Etapas sem rótulo | 27,83 / 29,37 | 44,20 / 39,40 |
| Completo | 23,96 / 35,51 | 35,43 / 36,41 |

Mesmo o editor vazio ultrapassou 16,67 ms de construção em uma abertura. Tirar os rótulos das etapas também deixou as duas primeiras aberturas acima do orçamento nas duas fases. A amostra permite priorizar a geometria e a miniatura para análise e preservar os rótulos. Ela não separa a contribuição individual desses dois elementos. As 18 aberturas conservaram o arquivo, e os processos auxiliares registraram o erro nativo de encerramento após a coleta.

## Abertura com a mesma geometria e com ou sem miniatura

Em `BOARD_PROFILE_SUITE=pane`, a cena `BOARD_PROFILE_SCENE=noThumbnail` conserva as 960 etapas rotuladas, as 959 setas, o item Mermaid, sua fonte, grupo e posição. Apenas os bytes PNG são omitidos. Em quatro processos Profile, alternamos completo, sem miniatura, sem miniatura e completo. Cada processo montou três vezes o editor. A tabela registra a primeira montagem de cada processo, antes da mudança de reúso dos bytes.

| Cena | Construção (ms) | Rasterização (ms) |
| --- | --- | --- |
| Completa, processo 1 | 46,25 | 45,77 |
| Sem miniatura, processo 2 | 30,83 | 31,54 |
| Sem miniatura, processo 3 | 35,86 | 35,17 |
| Completa, processo 4 | 32,53 | 29,91 |

O editor ultrapassou o orçamento de 16,67 ms nos quatro processos. Os intervalos se sobrepõem. A espera até a imagem decodificada só existe na cena completa, por isso o tempo até a miniatura pronta não é diretamente comparável. As 12 aberturas conservaram o arquivo, e o runner apresentou a falha nativa de saída após gravar as séries. O resultado orienta manter a miniatura e concentrar a próxima medição na quantidade de geometria visível.

## Quantidade de objetos enviados para pintura

O mesmo documento de 1.920 objetos, incluindo a miniatura e os rótulos, foi aberto em quatro processos Profile. O painel adjacente ocupou 160 ou 620 unidades lógicas. O benchmark registra a largura do InteractiveViewer e conta os objetos no BoardPainter do primeiro quadro, incluindo a margem de pintura ao redor da câmera. O modo `BOARD_PROFILE_SUITE=pane` aceita `BOARD_PROFILE_SCENE=narrow` para repetir o painel estreito.

| Largura do canvas | Objetos enviados | Primeira construção (ms) | Primeira rasterização (ms) |
| --- | --- | --- | --- |
| 1.058 | 210 | 32,64 | 30,97 |
| 598 | 109 | 33,11 | 33,15 |
| 598 | 109 | 30,93 | 27,82 |
| 1.058 | 210 | 38,01 | 36,36 |

O recorte diminuiu a lista de pintura em 101 objetos ao estreitar o painel. A primeira abertura permaneceu acima de 16,67 ms nos quatro processos. A redução não foi proporcional ao número de objetos enviados, e os intervalos das duas larguras se sobrepõem. A largura também altera o layout dos controles; o teste não atribui um custo individual a cada forma. As 12 aberturas mantiveram o Markdown intacto. O runner voltou a registrar o erro nativo ao encerrar após a coleta.
