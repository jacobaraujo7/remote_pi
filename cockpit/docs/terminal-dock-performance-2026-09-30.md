# Terminais, encaixe e resize — investigação de 2026-09-30

## Ensaio controlado

- Base: `main` em `bd5cda24`, Windows, build Flutter **debug**, `COCKPIT_PERF=1`.
- Instância debug e workspace temporário isolados. Abrimos 10 shells PowerShell:
  o primeiro no novo workspace, mais quatro em splits alternados e outros cinco
  como abas. Os dez foram confirmados por `list-workspaces --json`; o workspace
  e a instância de teste foram fechados após a medição.
- As métricas abaixo vêm do log local de performance da instância debug. São
  tempos indicativos de JIT e shells ociosos, não um baseline de release nem
  uma medição de agentes emitindo saída continuamente.

| Medida | Resultado no ensaio de 10 shells |
| --- | --- |
| Criação síncrona da sessão (`terminalOpen`) | 10 amostras: 0,81–1,33 ms |
| Criação → callback pós-frame (`terminalOpenFrame`) | 10 amostras: 59–135 ms |
| Criação → primeiro lote de saída (`terminalFirstOutput`) | 10 amostras: 104–157 ms |
| Frames na janela de atividade | 17 de 31 acima de 16,7 ms; p95 98 ms; máximo 119 ms |
| Frames lentos individuais | vários com build de 56–101 ms e raster de 2–6 ms |

O shell e o gateway não explicam sozinhos o atraso percebido ao abrir uma aba:
o trecho síncrono ficou perto de 1 ms, enquanto o próximo frame frequentemente
levou mais de 60 ms. O primeiro shell após iniciar a instância foi um caso frio:
43,6 ms de criação, 200 ms até o pós-frame e 2,20 s até a primeira saída.

## Onde o trabalho acontece

1. **Abrir terminal.** `CockpitViewModel._buildTerminal` constrói a sessão e
   inicia o gateway; `notifyListeners` reconstrói `_CenterPanel`. O painel
   recorre por workspaces e splits, e cada `PaneView` mantém as abas num
   `IndexedStack`. A diferença entre `terminalOpen` e `terminalOpenFrame`, junto
   dos `slowFrame` dominados por build, aponta para custo de construção/layout
   da interface. A primeira saída é uma medida separada do boot do shell.
2. **Encaixar abas.** `PaneDropZone` atualiza a prévia quando a zona de drop muda;
   o commit chama `moveTabToPane`, `moveTabToNewSplit` ou `moveTabToIndex`. Essas
   operações substituem a árvore e notificam a ViewModel global. Portanto o
   mesmo painel central e as abas mantidas montadas entram no rebuild. As
   métricas `terminalDockFrame` foram instaladas nesses três caminhos, mas não
   houve arraste controlado neste ensaio.
3. **Redimensionar.** Cada delta do divisor chama `resizeSplitBy`, substitui a
   árvore imutável e notifica todos os ouvintes. `_CenterPanel` observa a
   ViewModel inteira; todos os workspaces continuam em `IndexedStack`. No
   Ghostty, a `TerminalView` inativa permanece em `Offstage`, que ainda participa
   do layout quando as constraints mudam. Isso torna o custo por delta
   proporcional à árvore e às views montadas. A métrica
   `terminalResizeFrame` agrupa deltas do mesmo frame, mas ainda precisa de um
   arraste real para quantificar esse caminho.

O monitor de processos levou cerca de 1–1,7 s por varredura em algumas amostras.
Esse tempo inclui `await Process.run(powershell.exe, Get-CimInstance ...)` e
**não** significa que a UI ficou bloqueada por 1 s. É uma fonte possível de
contenção de CPU/processos a investigar separadamente.

## Workspace complexo no Windows

Um segundo ensaio usou dois projetos do repositório e cinco terminais em cada
um (10 shells, mais o terminal interno do Cockpit). Na máquina havia cerca de
838 processos; uma execução isolada da consulta usada pelo monitor levou
842 ms e produziu 324 KiB de JSON. Com a versão anterior, oito trocas reais
entre os projetos levaram 60–97 ms até o próximo frame, enquanto a resposta
da CLI levou 13–21 ms. A janela de 95 frames teve 38 acima de 16,7 ms e p95
de 92 ms; essa janela inclui a preparação do cenário e as trocas. A diferença
entre a resposta da CLI e `workspaceSwitch` mostra que a espera percebida está
principalmente no frame.

O monitor fazia `requestPoll` quando uma sessão se tornava visível. Trocar de
projeto aciona a visibilidade das abas, portanto disparava a consulta CIM mesmo
sem mudança na árvore de processos. O ajuste retira esse disparo e mantém
sondagens por atividade do terminal e uma verificação periódica de segurança.
No Windows, a verificação periódica passa de 2/5/10 s para 8/20/30 s
(visível/ocioso/janela inativa). Os intervalos de outras plataformas não mudam.
Após o ajuste, repetimos oito trocas com os mesmos dez terminais: nenhuma
varredura apareceu na janela da troca. O próximo frame ainda levou 79–104 ms
no build debug. Assim, a sondagem de visibilidade era uma fonte confirmada de
carga extra no Windows, mas sua remoção não eliminou a latência do layout.

O painel central também passa a reutilizar o widget de cada workspace e cada
um observa apenas sua própria árvore/foco. Isso evita reconstruir todas as
árvores montadas em cada notificação global da ViewModel. Os workspaces ainda
ficam montados no `IndexedStack`, portanto a mudança de tamanho pode continuar
a recalcular o layout das views inativas. Não há medição de drag real nesta
sessão; a hipótese de custo de layout por resize continua aberta.

Ao reabrir pela CLI um workspace já cadastrado, `addProject` agora usa
`selectProject`. Antes ele alterava `_selectedProjectId` diretamente, sem a
rotina de ativação/observação e sem emitir `workspaceSwitch`; por isso o
primeiro ensaio de troca pela CLI não media o caminho real da interface.

## Reprodução com cópia do AppData

Copiamos `projects.json`, `layouts.json` e `realms.json` do perfil de produção
para o perfil debug, após fazer backup do estado debug. O perfil de produção
ficou intocado. A cópia contém 9 projetos e 11 layouts; a rail mostra 37
entradas incluindo worktrees. O projeto inicialmente selecionado restaurou 7
terminais, e outro layout salvo restaurou 3. O estado salvo contém 8 abas que
retomam sessões do Claude; por isso restaurar esse workspace também inicia
processos de agente, aproximando o ensaio do uso real.

Na versão com varredura CIM completa, algumas amostras de `processScan`
chegaram a 8 s. Ao alternar entre os layouts de 7 e 3 terminais, o próximo
frame levou tipicamente 62–105 ms; o build debug teve um frame de 249 ms.
Os frames lentos foram dominados por `build` (por exemplo 55–96 ms), com
`raster` na faixa de 2–4 ms. Isso reforça a hipótese de custo de árvore/layout
para troca e resize, além da contenção criada pela observação de processos.

O provedor Windows agora enumera PID, pai e nome nativamente com Toolhelp,
restringe a análise aos descendentes dos terminais e consulta a linha de
comando via CIM apenas para novos candidatos a agente. Detalhes são guardados
por PID e novos candidatos vistos em sequência são agrupados por 3 s. A
enumeração nativa roda em um isolate separado para não ocupar o frame. No
mesmo workspace, as varreduras estáveis caíram para cerca de 23–50 ms. Durante
a restauração ainda ocorreram três consultas CIM acima de 1 s, com pico de
5,6 s: a detecção inicial de agentes continua tendo custo alto, embora não
haja mais varredura CIM completa periódica. O perfil debug original foi
restaurado após o ensaio e conferido por hash.

Depois da inicialização, oito novas trocas entre os layouts reais levaram
54–99 ms até o próximo frame; as varreduras na mesma janela ficaram em
26–43 ms. O custo visual, portanto, permanece mesmo sem uma consulta CIM
longa concorrendo com a troca. O `IndexedStack` ainda mantém todas as árvores
montadas e faz layout das views ocultas quando as constraints mudam.

Codex estava instalado e aberto, mas a amostra de CPU de 5 s não mostrou
carga contínua dos seus processos. A presença dele aumenta o número de
processos que a consulta antiga percorria; os dados não sustentam atribuir
todo o travamento ao Codex.

## Próxima medição visual

Em um build **profile**, iniciar com `COCKPIT_PERF=1`. Repetir com 5 e 10
terminais no mesmo workspace: (a) arrastar uma aba entre panes e encaixá-la;
(b) arrastar o divisor por alguns segundos. Comparar `terminalDockFrame`,
`terminalResizeFrame`, `slowFrame` e `frame`, além de uma captura de CPU no
DevTools. Isso distinguirá o custo do rebuild global do custo de layout das
views ocultas. A automação de interface disponível nesta sessão não permite
controlar aplicativos de terminal, então esse gesto visual não foi medido aqui.

## Refinamento em 2026-10-01: projeto frio, atividade e saída

O relato atualizado distingue a primeira carga dos terminais de outro projeto
da piora com sessões em uso. A métrica anterior `workspaceSwitch` terminava no
primeiro frame após selecionar o projeto, mesmo quando `_activateProject`
ainda restaurava sessões em segundo plano. Portanto os números de troca acima
não representam necessariamente o tempo até os terminais aparecerem. A nova
`workspaceReadyFrame` termina no primeiro frame após a ativação e registra
`cold` (1 = primeira carga, 0 = projeto já montado) e o número de abas.

O scheduler compartilhado continua processando a saída de todos os PTYs,
inclusive os de projetos ocultos. Cada amostra `pty` passa a informar
`processedChars` e `hiddenChars`, além de duração e fila. Isso permitirá
comparar a troca com terminais ociosos e com output contínuo em outros
projetos. É uma amostra de drain, não uma taxa agregada por segundo.

O usuário também relatou demora para fechar e cliques sem efeito nos botões
de fechar, minimizar e maximizar. `windowControl` registra a entrega do clique
(phase 0), o retorno da chamada nativa (phase 1) ou erro (phase 2), com
`action` 1/2/3 respectivamente. O fechamento registra o pedido e o tempo até
`windowManager.destroy()`. Hoje `onWindowClose` admite até 2 s para bounds e
mais 2 s para flush do estado; o callback de saída do app ainda pode aguardar
outro flush e a telemetria. No sidecar, as sessões PTY são encerradas em
sequência; no Windows, cada `pty_kill` enumera a árvore de processos. Estes são
caminhos candidatos à demora, ainda sem medição ao vivo nesta data. A instância
do Cockpit já estava fechada no momento da inspeção, então os botões não foram
reproduzidos neste follow-up.

A build Windows debug atualizada compilou e os testes do scheduler/diagnóstico
passaram, mas o processo iniciado pelo executor desta sessão não expôs janela
principal nem endpoint CLI utilizável. Ele foi encerrado; não houve nova
medição visual de carga, troca ou fechamento pela janela com 10 terminais;
o ensaio headless dos PTYs está abaixo.

Na leitura do caminho lazy, `_activateProject` verificava apenas se a árvore
já estava pronta. Se o usuário saísse e voltasse antes de terminar o restore,
uma segunda chamada ainda via a árvore ausente e iniciava outra restauração do
mesmo layout. As duas podiam abrir sessões PTY duplicadas e disputar os ids
globais. A ativação agora compartilha um único `Future` por projeto enquanto
está em andamento; a contagem de restores simultâneos mantém a gravação de
layout suspensa até todos terminarem. É uma correção de concorrência apoiada
pela leitura do código, ainda sem reprodução visual do sintoma original.

## Ensaio isolado do ciclo de vida dos PTYs em 2026-10-01

O benchmark reproduzível em
`packages/cockpit_engine/tool/benchmark_pty_lifecycle.dart` abre 10
`cmd.exe` pelo mesmo `NativeTerminalService` usado no sidecar Windows,
envia `ping -t 127.0.0.1` a cada PTY, espera saída contínua, redimensiona
cada sessão e chama `dispose()`. O binário `cockpit_pty.dll` veio do build
Windows debug desta branch. O benchmark é headless: não monta Flutter, não
inclui o protocolo do sidecar e não mede a saída completa do aplicativo.

Quatro execuções com 10 sessões vivas e saída contínua levaram 183, 187, 192
e 196 ms para `NativeTerminalService.dispose()`. Na execução do arquivo
versionado, `activeOutput=10`, as aberturas individuais levaram 10–32 ms
e os resizes 6–374 µs. Portanto, nesta máquina, a etapa nativa de encerrar
10 PTYs não reproduziu os vários segundos relatados ao fechar o Cockpit.
A duração do callback da janela, a saída do engine, o encerramento do sidecar
e a verificação independente de processos órfãos ainda precisam de medição.
O ensaio não demonstra que o fechamento completo seja rápido.

No log da última instância debug, um `terminalOpenFrame` levou 349 ms,
`terminalFirstOutput` levou 4,35 s e o maior `slowFrame` registrado levou
342 ms. Esses números são do build debug e não incluem um clique ou gesto
observado visualmente nesta sessão. Eles reforçam que a carga inicial e o
caminho visual precisam ser medidos separadamente do motor PTY.

## Criação de workspace na versão instalada em 2026-10-01

O fluxo local chama `NativeFolderPicker.pick` antes do diálogo de nome/cor.
No Windows, `file_picker` 8.3.7 implementa `getDirectoryPath()` com
`IFileOpenDialog.Show` síncrono, mesmo retornando `Future<String?>`. A
chamada anterior ocorria no isolate da UI. Se a navegação do Explorer ou
algum shell extension demora, esse isolate para de produzir frames e de
responder a cliques até o seletor retornar. A correção executa só a chamada
Win32 em `Isolate.run`, preservando o tratamento atual para pasta inicial
inválida. O mesmo fluxo nas demais plataformas continua no picker próprio.

O diálogo seguinte ainda continha um trace temporário que gravava
`ck_trace.log` com `flush: true` de forma síncrona durante `build`, foco,
salvar e cancelar. Esses writes foram removidos. O arquivo de trace desta
máquina não era atualizado desde 2026-09-23, então não há evidência de que
tenha causado o travamento relatado hoje.

O log da instalação em 2026-10-01 mostra falhas repetidas da varredura
antiga de processos por JSON do PowerShell (`FormatException`). O provedor
Toolhelp deste PR já substitui a varredura principal, mas esses registros
não localizam a etapa exata do travamento de criação. A análise estática dos
dois arquivos passou e o build Windows debug compilou após a mudança do
picker; a remoção do trace passou em análise estática. Ainda falta medir
o gesto na interface instalada ou num build desta branch.
