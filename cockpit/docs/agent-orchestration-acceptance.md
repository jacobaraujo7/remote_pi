# Agent Orchestration: roteiro de aceite real

Este é um roteiro de execução, não evidência de que os casos passaram. Conversas
reais e aceite manual em macOS continuam pendentes no PR. Testes de shells,
widgets e builds universais não substituem esses resultados.

## Ambiente

- Use uma worktree descartável e um perfil separado (`COCKPIT_ISOLATED_ROOT`
  absoluto no processo de teste). Não encerre o debug, tarefas ou agentes do
  perfil de trabalho; não copie seus processos para o teste.
- Registre commit, versão do app, sistema, arquitetura e engine. Repita os casos
  de terminal com Ghostty e xterm. No Mac, registre se a execução foi ARM ou
  Intel/Rosetta; não presuma que um build universal prova ambas as execuções.
- Use somente dados sintéticos. Crie um README curto explicando uma aplicação
  fictícia. Agentes não precisam editar o repositório real.
- O operador trata os prompts normais de confiança/permissão. Não os contorne,
  não desative as proteções e não inicie os turnos antes de resolver o acesso.
- Para coleta de erros, habilite Developer mode somente no perfil de teste.
  `cockpit telemetry runs --app` deve identificar o boot desse perfil.

## Dois documentos, nomes e IDs iguais

1. Crie Agent Orchestration pela Gallery. Deve aparecer uma aba com três shells
   em branco, sem função, ferramenta ou modelo; nenhuma CLI inicia sozinha.
2. Renomeie o arquivo para `team-a.orc` pela árvore local. Os mesmos terminais,
   seleção e layout interno devem permanecer. Copie o JSON portátil para
   `team-b.orc`, preservando IDs e nomes das três boxes, e abra a cópia.
3. Coloque as duas abas em docks diferentes. Deve haver seis sessões distintas,
   três por app. Em cada terminal, `cockpit list-tabs --json` deve listar somente
   os terminais daquele app. Anote os IDs localmente, fora dos arquivos `.orc`.
4. Crie também um terminal comum, T0. Ele não pode aparecer nos documentos.
   Mover a aba inteira de A é permitido; arrastar um terminal interno para B ou
   para um dock externo deve ser recusado sem congelar nem duplicar a view.
5. Reordene A, deixe A em Boxes/B em Graph e redimensione as áreas internas.
   Alterne modos repetidamente e reinicie apenas a cópia descartável. Verifique
   ordem, posições, seleção, dimensões e layouts; B e T0 permanecem independentes.

## Conversas com modelos reais

1. Em A, configure/inicie explicitamente três CLIs compatíveis: coordenador A1,
   implementador A2 e revisor A3. Em B, inicie B1 e B2; mantenha B3 como shell.
   Salvar configuração deve continuar separado de Start CLI.
2. Peça a A1 para ler o README sintético e consultar A2 pela CLI do Cockpit.
   A2 deve elaborar uma proposta curta, consultar A3, e A3 devolver uma revisão
   para A1. Cada agente deve usar a skill `cockpit-orchestration`, os IDs da sua
   própria listagem e os comandos públicos existentes de envio/leitura.
3. Guarde respostas efetivas dos modelos e horários. Confirme os estados das
   boxes e as arestas observadas somente no grafo de A. Uma aresta planejada
   precisa continuar distinguível da atividade observada; não invente métricas.
4. Com B ocioso, forneça a A1 o ID sintético de B1 e peça uma tentativa explícita
   de envio. Ela deve ser recusada, sem entrada, foco ou alteração no terminal B1.
   O agente não pode alterar o ambiente de origem nem impersonar outro terminal.
5. Em A2 ocioso e sem função, use Ask agent for role. Deve haver resposta real,
   prévia da sugestão e confirmação antes de salvar. Repita descartando a
   sugestão e mudando a seleção durante uma resposta: nada deve ser salvo tarde
   em outra box. Não consulte durante trabalho ou aprovação pendente.
6. Gere uma conclusão/espera em A enquanto B estiver visível. O aviso fica em A;
   T0 e os badges/sons/notificações globais não devem receber esse evento. Ao
   reconhecer A1, o resultado não visto de A2/B deve permanecer independente.
7. Se a CLI oferecer subagentes temporários, crie um em A e confirme vínculo com
   seu pai, distinção visual e ausência de definição permanente no JSON.

## Conflitos e ciclo de vida

- Edite externamente função/nome/posição de A: a atualização deve aparecer sem
  Refresh, sem recriar sessão, iniciar CLI ou alterar B. Acrescente uma definição
  com ferramenta configurada: deve abrir somente um novo shell em branco.
- Remova uma definição com sessão aberta. Aguarde o aviso dentro de A e escolha
  manter/restaurar: preserve a sessão e regrave a definição. Repita escolhendo
  encerrar: remova somente o terminal correspondente e não o recrie ao recarregar.
- Feche outro terminal pelo X interno, inclusive um oculto. Sua definição e links
  planejados devem sair do documento. A aplicação permanece responsiva.
- Feche a aba do app e teste cancelar/confirmar o encerramento de seus filhos.
  A confirmação não pode encerrar B ou T0. Sair do app preserva definições para
  restauração; não confunda restaurar histórico com manter o mesmo processo vivo.
- Introduza JSON inválido e falha de gravação em cópias descartáveis: preservar
  sessões/último estado válido, mostrar erro e não apresentar alterações como
  salvas. Depois corrija e use Reload sem duplicação.
- Quando houver hosts disponíveis, teste indisponibilidade sem fallback local.
  Um rename local não deve reapontar um documento remoto de caminho idêntico.
- Inspecione os JSONs: nenhuma credencial, conversa, PID, histórico, métrica ou
  vínculo de sessão pode ter sido exportado. Copie um `.orc` para outra worktree:
  definições iguais devem produzir shells independentes no diretório de destino.

## Desktop e macOS

Teste clipboard de texto, arquivo copiado do Explorer/Finder e imagem, além de
arrasto de arquivo; busca, seleção, foco e fechamento com as duas engines.
No Mac inclua menus nativos, Cmd+C/Cmd+V/Cmd+F, trackpad, Retina, tela cheia,
minimizar/restaurar. Confira temas claro/escuro e inspector estreito sem sobrepor
o outro dock. Registre ações de reiniciar, compactar e handoff como explícitas e
restritas ao terminal escolhido, usando somente conversas sintéticas.

## Registro por caso

| Campo | Preencher na execução |
| --- | --- |
| Commit/binário | SHA e origem do build |
| Plataforma | Windows/macOS, versão, arquitetura, Retina/escala |
| Engine | Ghostty ou xterm |
| Caso | Passo exato deste roteiro |
| Esperado/observado | Comportamento e IDs sintéticos antes/depois |
| Evidência | Captura real, saída ou run de telemetria do perfil |
| Resultado | Passou, falhou ou não executado |
| Responsável/próximo passo | Pessoa e ação concreta |

Codex mantém código/CI e pendências Windows. Jacob registra o aceite em Mac real
antes do merge. O operador precisa autorizar/resolver o acesso dos agentes para
as conversas reais. Mantenha o PR em draft enquanto faltarem os gates descritos
na sua matriz de validação.
