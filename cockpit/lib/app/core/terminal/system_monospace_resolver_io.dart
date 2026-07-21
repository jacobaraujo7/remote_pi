import 'dart:io';

String? resolveSystemMonospaceFamily() => _systemMonospaceFamily;

final String? _systemMonospaceFamily = _resolveSystemMonospaceFamily();

String? _resolveSystemMonospaceFamily() {
  if (Platform.isMacOS) return 'Menlo';
  if (Platform.isWindows) return 'Consolas';
  if (!Platform.isLinux) return null;

  try {
    final result = Process.runSync('fc-match', const [
      '--format=%{family[0]}',
      'monospace',
    ]);
    if (result.exitCode != 0) return null;

    final family = (result.stdout as String).trim();
    return family.isEmpty ? null : family;
  } on ProcessException {
    return null;
  }
}
