import 'package:cockpit/app/core/domain/result.dart';

/// Mutação da árvore de arquivos: criar, renomear/mover e mandar pra lixeira.
/// Contraparte de escrita do [FileSystemReader] (leitura). Impl (dart:io +
/// `osascript` no macOS) em `data/filesystem/`. Operações devolvem
/// `Result<void, String>` — a falha traz uma mensagem pronta pra UI.
abstract class FileSystemMutator {
  /// Cria um arquivo **vazio** em [path]. Falha se já existir algo no caminho
  /// ou se a pasta-pai não existir.
  Future<Result<void, String>> createFile(String path);

  /// Cria uma pasta em [path]. Falha se já existir.
  Future<Result<void, String>> createDirectory(String path);

  /// Renomeia/move [from] para [to] (arquivo ou pasta). Falha se [to] já existir.
  Future<Result<void, String>> rename(String from, String to);

  /// Copia [from] para [to] (arquivo ou pasta, recursivo). Falha se [to] já
  /// existir. Usado pelo copiar/colar da árvore de arquivos.
  Future<Result<void, String>> copy(String from, String to);

  /// Move [path] para a lixeira (reversível). No macOS via Finder (`osascript`);
  /// nas demais plataformas, deleção permanente (a confirmação fica na UI).
  /// Idempotente: caminho inexistente é sucesso.
  Future<Result<void, String>> moveToTrash(String path);
}
