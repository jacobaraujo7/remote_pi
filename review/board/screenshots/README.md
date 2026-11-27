# Capturas isoladas do Canvas Board — PR #357

Imagens geradas em background a partir do widget real BoardView, no tema escuro, com um fluxo fictício de aprovação de pagamentos. Não são capturas do desktop nem evidência de execução no macOS. Nenhuma janela, sessão ou arquivo pessoal foi utilizado. Conferência visual das quatro imagens concluída em 27/11/2026.

1. `01-resize-handle.png`: forma selecionada e alça inferior direita.
2. `02-resized-shape.png`: a mesma forma ampliada de 136x64 para 216x114; a conexão permanece ligada ao objeto.
3. `03-area-selection.png`: arraste em área vazia para selecionar as duas primeiras formas.
4. `04-grouped-shapes.png`: após Agrupar, ambas permanecem selecionadas; Agrupar, Desagrupar e Alinhar ficam acessíveis na barra normal. O teste confirmou o mesmo identificador de grupo nos dois objetos.

As capturas foram produzidas por um teste Flutter com `matchesGoldenFile`, carregando as fontes e os ícones locais. O teste também verificou a largura após o gesto e o identificador de grupo persistido no Markdown. Resultado: passou. O script temporário e seu log ficam em `cockpit/build/resize-qa/screenshots_test.dart` e `screenshots.log` na worktree de QA.

Jacob Moura foi solicitado como reviewer no GitHub e recebeu o roteiro complementar de macOS: https://github.com/jacobaraujo7/remote_pi/pull/357#issuecomment-7223324153. A validação nativa no Mac permanece pendente; Canvas Board responde por eventuais correções. Nenhum merge foi realizado.
