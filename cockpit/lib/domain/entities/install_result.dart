/// Resultado de uma instalação disparada pelo onboarding (extensão / supervisor).
/// [ok] indica sucesso; [detail] traz a mensagem de erro (ou um resumo opcional
/// no sucesso) pra exibir no dialog.
class InstallResult {
  const InstallResult.success([this.detail = '']) : ok = true;
  const InstallResult.failure(this.detail) : ok = false;

  final bool ok;
  final String detail;
}
