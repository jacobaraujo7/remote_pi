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

O experimento mede o arraste sintético de uma etapa depois do aquecimento. Para concluir sobre escrita livre, custo da primeira pintura ou latência física do mouse à tela, cada cenário precisa de sua própria medição. Uma área de trabalho com aplicações ativas e um único computador limitam a generalização. A medição no monitor de 160 Hz compara também com o orçamento de 60 Hz; o monitor permaneceu em sua configuração original.
