# 71 — Colar e arrastar anexos no terminal

Estado: [PR #268](https://github.com/jacobaraujo7/remote_pi/pull/268) aberto para `main`; revisão de jacobaraujo7 solicitada.
Branch: `feature/terminal-attachments`. Responsável: moregola / Codex.
Revisor solicitado pelo usuário: jacobaraujo7.

## Comportamento

- Clipboard e drop passam pela mesma operação de importação por sessão.
- Prioridade: arquivos reais, imagem, texto; texto preserva bracketed paste.
- Arquivos são copiados para `.cockpit/attachments/<operação>/`, mantendo nomes
  e extensões e resolvendo colisões. Imagens do clipboard são salvas como PNG.
- Pastas são referenciadas no local original, sem cópia recursiva.
- Workspaces sem projeto usam a pasta efetiva de spawn do terminal ou sua pasta
  inicial. A raiz de projeto, quando existente, continua prioritária.
- Importações capturam destinatário e clipboard no gesto e preservam a ordem.
  Fechar a sessão impede a entrega; mudar o foco não redireciona conteúdo.
- Não alterar o clipboard, executar comandos ou enviar Enter automaticamente.
- Anexos permanecem em disco, sem limpeza automática.
- Arquivos/imagens em sessões remotas são indisponíveis nesta entrega; texto segue
  disponível. WSL usa conversão por distribuição com verificação de acesso.
- Há progresso e erros por item; falhas parciais preservam os sucessos.

## Integração com agentes

| Situação | Estratégia |
|---|---|
| Claude Code / Windows | Alt+V, após salvar e conferir o clipboard |
| Claude Code / macOS e Linux; Codex; Pi | Ctrl+V sob as mesmas verificações |
| Copilot | Alt+V sob as mesmas verificações |
| OpenCode, Cursor, Antigravity, agente não identificado | Referência à cópia |
| Arquivo de imagem arrastado; clipboard alterado; WSL | Referência à cópia |

O atalho nativo exige agente identificado, sessão viva, bitmap importado sem
falhas e clipboard ainda correspondente à captura. O feedback informa solicitação
nativa ou referência; não presume confirmação do agente.

## Validação

| Cenário | Evidência | Estado |
|---|---|---|
| Texto, prioridade de formatos, escapes PS/CMD/POSIX | Testes Dart | Aprovado |
| Screenshot e drop no projeto | Windows / PowerShell / Ghostty / Claude Code 2.1.311 | Aceito pelo usuário |
| Screenshot e drop na aba Cockpit sem projeto | Reteste após correção de destino vazio | Aceito pelo usuário |
| Conteúdo real da imagem, troca de foco e nomes difíceis | Aceite manual do usuário | Aprovado |
| Falha parcial | Arquivo removido entre seleção e importação; storage real nos dois motores | Aprovado |
| Colagens rápidas | 20 capturas enfileiradas com importação bloqueada; ordem e unicidade nos dois motores | Aprovado |
| Descarte de sessão, clipboard alterado, erro de gravação, colisões | Testes Dart | Aprovado |
| Remotos e conversão WSL | Testes com gateways/processos substituídos | Aprovado automaticamente |
| PNG registrado, DIB e DIBV5 | 17 verificações nativas C++ | Aprovado |
| Persistência independente do original | Testes de storage; aceite manual despriorizado pelo usuário | Coberto automaticamente |
| Outros agentes, xterm real, WSL real, macOS e Linux | Sem ambiente/aceite manual nesta sessão | Pendente; não inferir compatibilidade validada |

Comandos locais executados no subprojeto `cockpit`:

- `flutter test test/session/terminal_attachments_test.dart test/domain/terminal_attachment_service_test.dart test/data/local_terminal_attachments_test.dart test/data/pasteboard_terminal_clipboard_test.dart test/ui/terminal_attachment_drop_target_test.dart test/ui/terminal_attachment_shortcuts_test.dart`: 63 passaram.
- Análise estática direcionada: zero problemas. `flutter analyze` completo encontrou
  apenas o info preexistente `avoid_returning_null_for_void` em
  `test/flutter_test_config.dart:23`, confirmado também na base; nenhum erro/warning novo.
- Teste nativo CMake/CTest: aprovado; executável confirma 17 verificações.
- Build Windows debug: compilado e usado no aceite com hot reload das correções.

## Integração e encaminhamento

Inventário direto dos PRs abertos no repositório: nenhum do usuário moregola.
[PR #257](https://github.com/jacobaraujo7/remote_pi/pull/257), de cfbraun, toca foco
/atalhos, mas não entrega este fluxo; destino `main`, seguir independentemente e
reavaliar sobreposição antes do merge. [PR #267](https://github.com/jacobaraujo7/remote_pi/pull/267),
de pretodev, trata preview/Neovim; não depende desta entrega.

A base remota `main` foi reconferida em `71eaec8c5de065f2c94051bfd3801cff8a930d98`.
O usuário esclareceu expressamente o escopo da regra de BTN: "essa regra é só
pra ems/grupo nc". Este repositório é um projeto pessoal, fora desse escopo;
portanto não exige BTN. Retomar a publicação autorizada do PR para main e a
solicitação de revisão para jacobaraujo7. O debug foi encerrado a pedido do usuário,
preservando dados e anexos.
Ajustes para isolar a instância de debug, backups e estado instalado ficam fora
do PR. As alterações preexistentes do checkout original foram preservadas.

Limites conhecidos: atalhos personalizados do agente não são descobertos;
SSH/container iniciado dentro de um shell local requer validação específica;
sem confirmação de recebimento por RPC. Não declarar aceite universal a partir
do teste de um único agente/sistema.

Próximo passo: acompanhar checks e revisão de jacobaraujo7. Responsável pelo
acompanhamento e ajustes: moregola / Codex; sem autorização de merge.

Publicação: branch enviada para origin; PR #268 criado e aberto, sem draft,
com destino main e revisão de jacobaraujo7 confirmada pela API do GitHub.
Análise direcionada de lib e dos seis testes do PR: zero problemas.
A integração retornou 403 ao criar o PR; GitHub CLI autenticado publicou
o PR autorizado. Descrição remota conferida e idêntica ao texto preparado.
Responsáveis: jacobaraujo7 para revisão solicitada; moregola / Codex para
acompanhar os checks e responder aos achados.
