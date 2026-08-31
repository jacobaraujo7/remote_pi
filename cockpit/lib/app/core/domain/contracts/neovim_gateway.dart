import '../exceptions/neovim_error.dart';
import '../result.dart';

/// Descoberta e controle das instâncias Neovim usadas pelo Cockpit.
abstract class NeovimGateway {
  /// Caminho absoluto do `nvim`, ou `null` quando não está instalado na PATH do
  /// shell do usuário. [refresh] invalida o cache (botão das Configurações).
  Future<String?> executable({bool refresh = false});

  /// Endereço curto e exclusivo desta execução do Cockpit + workspace.
  String serverAddress(String workspaceId);

  /// Remove um socket POSIX obsoleto antes de iniciar uma nova instância.
  Future<void> prepareServer(String address);

  /// Abre [path] na instância existente usando `:drop` (`--remote`).
  Future<Result<void, NeovimError>> openRemote(
    String executable,
    String address,
    String path, {
    int? line,
  });

  /// `true` quando o servidor no endereço ainda responde.
  Future<bool> isAlive(String executable, String address);

  /// Consulta se há algum buffer modificado. Falha significa que o processo já
  /// não é consultável e, portanto, não há trabalho vivo a proteger na aba.
  Future<Result<bool, NeovimError>> hasModifiedBuffers(
    String executable,
    String address,
  );
}
