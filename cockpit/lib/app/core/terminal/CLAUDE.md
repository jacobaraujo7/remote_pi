# `core/terminal/` — módulo de terminal (emulador + render)

Tudo de terminal num lugar só:

- **`xterm/`** — emulador VT **absorvido** (2026-07-19) do fork
  `jacobaraujo7/xterm.dart` (upstream TerminalStudio/xterm.dart 4.0.0, parado).
  Dart puro, zero nativo. Razões da absorção: upstream sem manutenção, o app já
  importava internals (`src/`), e o repo já mantinha view/render forkados. O
  LICENSE (MIT) original está em `xterm/LICENSE` — preserve-o. Mudanças que
  vieram do fork: glifos Block/Box-Drawing procedurais (`builtin_glyphs.dart`),
  SGR com primeiro parâmetro vazio, DSR-CPR 1-based, `viewId` no IME
  (`custom_text_edit.dart`). Removidos na absorção (não usados): zmodem,
  suggestion, debugger_view.
- **`cockpit_terminal*.dart`** — view/render próprios (cache de `ui.Picture`
  por linha, gesture, painter), que consomem o emulador acima.

Testes do emulador: `test/core/terminal/xterm/` (suíte do upstream adaptada;
2 casos de `getText()` com wrap já falhavam no fork e estão `skip: true`).

O PTY (nativo) continua fora: `kyroon_pty` (fork git com PR aberto upstream).
