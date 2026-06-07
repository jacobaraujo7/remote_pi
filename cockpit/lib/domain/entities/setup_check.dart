/// Estado de uma checagem de ambiente/permissão na tela de onboarding.
enum CheckStatus {
  /// Rodando a verificação.
  checking,

  /// Tudo certo (verdinho).
  ok,

  /// Falta instalar/conceder (x vermelho-claro).
  missing,

  /// Não se aplica neste SO (ex.: permissões de macOS no Linux/Windows) — conta
  /// como satisfeito pro gate, mas é exibido como dispensado.
  notApplicable,
}

extension CheckStatusX on CheckStatus {
  /// Satisfaz o gate de "Criar Workspace"? `notApplicable` conta como sim.
  bool get satisfied =>
      this == CheckStatus.ok || this == CheckStatus.notApplicable;
}
