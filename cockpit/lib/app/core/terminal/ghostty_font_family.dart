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
  String? Function()? bundledJetBrainsMonoResolver,
}) {
  final family = requested.trim();
  // `google_fonts` registra a fonte com uma familia interna versionada, nao
  // necessariamente com o nome humano "JetBrains Mono". Passar o nome humano
  // diretamente ao flterm pode fazer o Flutter medir a celula com um fallback
  // proporcional (o `M` largo) e pintar os demais glifos com outra face. O
  // resultado visual e um espaco artificial entre todos os caracteres.
  //
  // O caller fornece o resolvedor para este helper continuar independente de
  // google_fonts e permanecer testavel sem carregar assets.
  String resolveBundledJetBrainsMono(String candidate) {
    if (candidate.toLowerCase() != 'jetbrains mono') return candidate;
    final bundled = bundledJetBrainsMonoResolver?.call()?.trim();
    return bundled == null || bundled.isEmpty ? candidate : bundled;
  }

  if (family.toLowerCase() != 'monospace') {
    return resolveBundledJetBrainsMono(family);
  }

  final resolved = (systemMonospaceResolver ?? resolveSystemMonospaceFamily)()
      ?.trim();
  if (resolved == null || resolved.isEmpty) return family;
  return resolveBundledJetBrainsMono(resolved);
}
