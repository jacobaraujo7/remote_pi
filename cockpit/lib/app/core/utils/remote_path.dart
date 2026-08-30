/// Manipulação de caminhos do **HOST remoto**, que pode ser de outra família
/// que a do cliente.
///
/// Nada aqui usa `dart:io` nem `Platform`: o `path` do pacote e o `Platform`
/// descrevem a máquina LOCAL, e usá-los aqui produziria o separador errado
/// sempre que cliente e host divergem — um iPad navegando um host Windows, um
/// Mac navegando um host Linux.
///
/// A família é inferida do próprio caminho (`C:\…`), e não recebida de fora:
/// o picker só tem a string que o host devolveu, e essa string já carrega a
/// resposta.
library;

/// `true` quando [path] é um caminho Windows (`C:\…`, `D:/…`).
bool isWindowsRemotePath(String path) => RegExp(r'^[A-Za-z]:').hasMatch(path);

String remotePathSeparator(String path) =>
    isWindowsRemotePath(path) ? r'\' : '/';

/// Raiz do host para [path]: `C:\` no Windows, `/` no POSIX.
String remotePathRoot(String path) =>
    isWindowsRemotePath(path) ? '${path.substring(0, 2)}\\' : '/';

/// `true` quando [path] já é a raiz — onde o botão "subir" para de fazer
/// sentido.
bool isRemotePathRoot(String path) {
  if (!isWindowsRemotePath(path)) return path == '/';
  // `C:`, `C:\` e `C:/` são todos a raiz do drive.
  return path.length <= 3;
}

/// Diretório pai de [path]. Devolve a raiz quando não há pai.
///
/// Lê os DOIS separadores: um caminho pode chegar misto (versões anteriores do
/// picker juntavam com `/` mesmo em host Windows), e recusá-lo prenderia o
/// usuário na pasta em que está.
String remotePathParent(String path) {
  final root = remotePathRoot(path);
  var trimmed = path;
  while (trimmed.length > root.length &&
      (trimmed.endsWith('/') || trimmed.endsWith(r'\'))) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf(r'\');
  final idx = slash > backslash ? slash : backslash;
  if (idx <= 0) return root;
  final parent = trimmed.substring(0, idx);
  // `C:` sozinho não é diretório navegável; vira `C:\`.
  return parent.length == 2 && isWindowsRemotePath(path) ? root : parent;
}

/// Junta [dir] e [name] com o separador do HOST.
String remotePathJoin(String dir, String name) {
  if (dir.isEmpty) return name;
  if (dir.endsWith('/') || dir.endsWith(r'\')) return '$dir$name';
  return '$dir${remotePathSeparator(dir)}$name';
}

/// Último componente de [path] — o nome que a UI mostra para um workspace
/// pinado.
///
/// Lê os dois separadores pelo mesmo motivo do [remotePathParent]: em
/// `C:\\Users\\jacob\\projeto`, procurar só por `/` devolvia o caminho INTEIRO
/// como nome do pin.
String remotePathBasename(String path) {
  var trimmed = path;
  while (trimmed.length > 1 &&
      (trimmed.endsWith('/') || trimmed.endsWith(r'\'))) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf(r'\');
  final idx = slash > backslash ? slash : backslash;
  return idx < 0 ? trimmed : trimmed.substring(idx + 1);
}
