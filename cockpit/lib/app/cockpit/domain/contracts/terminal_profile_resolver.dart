import 'package:cockpit/app/cockpit/domain/entities/terminal_profile.dart';

/// Descobre os [TerminalProfile] disponíveis na plataforma (plano 50).
/// Best-effort e cacheável (vida do processo); nunca lança.
abstract class TerminalProfileResolver {
  /// Descobre (e cacheia) os perfis. Chamadas concorrentes compartilham a mesma
  /// descoberta. Chame no boot pra aquecer o cache — o caminho que cria a aba é
  /// síncrono e lê de [cachedProfiles]/[effectiveDefault].
  Future<List<TerminalProfile>> discover();

  /// Perfis já descobertos. Vazio se [discover] ainda não rodou.
  List<TerminalProfile> get cachedProfiles;

  /// Perfil de [id] entre os descobertos, ou `null`.
  TerminalProfile? profileById(String id);

  /// Perfil padrão **efetivo**, síncrono (o `+` chama no caminho de criação):
  /// 1. [configuredId] setado **e** ainda existente na descoberta → ele;
  /// 2. senão → fallback por plataforma (Windows: PowerShell — cmd no ARM;
  ///    POSIX: login shell).
  ///
  /// Nunca devolve `null`: perfil ausente/inválido jamais bloqueia a abertura
  /// do terminal.
  TerminalProfile effectiveDefault(String? configuredId);
}
