import 'dart:typed_data';

/// Uma entrada de diretório (árvore de arquivos remota).
class FileEntry {
  const FileEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
  });

  final String name;
  final bool isDirectory;
  final int size;

  Map<String, Object?> toJson() => {
    'name': name,
    'dir': isDirectory,
    'size': size,
  };

  factory FileEntry.fromJson(Map<String, Object?> j) => FileEntry(
    name: j['name'] as String,
    isDirectory: j['dir'] as bool,
    size: (j['size'] as num?)?.toInt() ?? 0,
  );
}

enum FileErrorKind { notFound, notADirectory, permission, tooLarge, io }

class FileException implements Exception {
  const FileException(this.kind, [this.detail]);
  final FileErrorKind kind;
  final String? detail;

  @override
  String toString() => 'FileException(${kind.name}: $detail)';
}

/// Sistema de arquivos do servidor (plano 58, Wave 3). Paths são do
/// filesystem do host que serve; o cliente nunca toca disco.
abstract interface class FileService {
  /// Lista [path] (pastas primeiro, ordenado). Ocultos incluídos; a UI filtra.
  Future<List<FileEntry>> list(String path);

  /// Conteúdo de um arquivo (limite [maxBytes] — acima disso, [FileException]
  /// tooLarge, o viewer decide o que fazer).
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024});

  Future<void> write(String path, Uint8List bytes);

  /// Diretório HOME do usuário do host (ponto de partida do picker de pasta —
  /// melhor que `/`). Vazio se o host não expõe HOME.
  Future<String> home();
}

/// Optional creation capability. Existing FileService implementations and write
/// behavior remain unchanged. False means an existing path was left untouched.
abstract interface class ExclusiveFileCreator {
  Future<bool> createNew(String path, Uint8List bytes);
}
