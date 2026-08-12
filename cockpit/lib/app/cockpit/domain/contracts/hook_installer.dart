import 'package:cockpit/app/core/domain/result.dart';

/// Instala (idempotente) os hooks de ciclo de vida do Cockpit na configuração
/// de um harness de agente, e garante que a CLI `cockpit` (que absorveu o
/// helper `cockpit-hook`) esteja num caminho estável. Chamado no boot do app
/// (decisão: sem passo de onboarding).
///
/// O helper, invocado pelo harness a cada evento, manda o status de turno
/// (working / waiting / idle) pro Cockpit por socket, roteado pela env
/// `COCKPIT_PANE_ID` que o app injeta na PTY da aba. A aba reflete no spinner /
/// badge / chime.
///
/// Implementações: `ClaudeHookInstallerImpl` (`~/.claude/settings.json`) e
/// `CodexHookInstallerImpl` (`~/.codex/hooks.json` + trust no `config.toml`).
abstract class HookInstaller {
  /// Garante CLI copiada e entries presentes. Idempotente: re-rodar não duplica
  /// nem mexe em hooks de terceiros. Falha é não-fatal (logada).
  Future<Result<void, String>> ensureInstalled();
}
