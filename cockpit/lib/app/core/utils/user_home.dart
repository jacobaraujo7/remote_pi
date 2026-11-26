import 'dart:io';

/// Diretório home do usuário, resolvido por plataforma:
/// - **Windows**: `%USERPROFILE%`, com fallback `%HOMEDRIVE%%HOMEPATH%`.
/// - **macOS / Linux**: `$HOME`.
///
/// Retorna `null` quando nenhuma das variáveis está definida (ambiente mínimo).
/// [environment] e [isWindows] existem pra teste; por padrão vêm do processo.
String? userHome({Map<String, String>? environment, bool? isWindows}) {
  final env = environment ?? Platform.environment;
  if (isWindows ?? Platform.isWindows) {
    final profile = env['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) return profile;
    final drive = env['HOMEDRIVE'];
    final path = env['HOMEPATH'];
    if (drive != null && path != null && (drive + path).isNotEmpty) {
      return drive + path;
    }
    return null;
  }
  final home = env['HOME'];
  return (home != null && home.isNotEmpty) ? home : null;
}
