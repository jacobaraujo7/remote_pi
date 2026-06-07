import 'package:cockpit/domain/entities/launchable_app.dart';

/// Detecta IDEs instaladas e abre caminhos nelas.
abstract class AppLauncherGateway {
  /// Retorna os apps disponíveis no sistema (ordem = preferência padrão).
  /// Finder/Explorer é sempre incluído no final.
  Future<List<LaunchableApp>> probe();

  /// Abre [path] no [app]. IDEs usam `open -a`; Finder usa `open`.
  Future<void> launch(LaunchableApp app, String path);
}
