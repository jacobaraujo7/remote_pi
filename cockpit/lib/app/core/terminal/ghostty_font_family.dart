import 'system_monospace_resolver_stub.dart'
    if (dart.library.io) 'system_monospace_resolver_io.dart';

/// Resolve o alias genérico usado pela configuração padrão do Ghostty.
///
/// O Ghostty nativo entrega `monospace` ao resolvedor de fontes da plataforma
/// (Fontconfig no Linux). O Flutter pode tratar esse texto como uma família
/// literal e então medir a célula com uma fonte diferente da usada para pintar
/// os glifos. Converter apenas o alias mantém fonte e métricas alinhadas sem
/// alterar famílias escolhidas explicitamente pelo usuário.
String resolveGhosttyFontFamily(
  String requested, {
  String? Function()? systemMonospaceResolver,
}) {
  final family = requested.trim();
  if (family.toLowerCase() != 'monospace') return family;

  final resolved = (systemMonospaceResolver ?? resolveSystemMonospaceFamily)()
      ?.trim();
  return resolved == null || resolved.isEmpty ? family : resolved;
}
