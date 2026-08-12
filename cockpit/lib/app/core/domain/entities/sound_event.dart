/// Eventos do app que podem tocar som. Vocabulário **neutro de harness**: o
/// Claude Code (e, no futuro, Codex/OpenCode/...) é traduzido para cá pelo seu
/// adapter de hook — a semântica do som mora no app, nunca no harness.
enum SoundEvent {
  /// Agente terminou o turno (status `idle` vindo de `Stop`).
  turnDone,

  /// Agente parou esperando o usuário (status `waiting`: aprovação de
  /// permissão, `AskUserQuestion`, `ExitPlanMode`).
  actionRequired,

  /// O processo do agente morreu sem ser pedido (crash/exit inesperado).
  agentError,
}

/// Nome do arquivo de som embarcado de cada evento (em `assets/sounds/`).
extension SoundEventAsset on SoundEvent {
  String get defaultAsset => switch (this) {
    SoundEvent.turnDone => 'turn_done.wav',
    SoundEvent.actionRequired => 'action_required.wav',
    SoundEvent.agentError => 'agent_error.wav',
  };
}
