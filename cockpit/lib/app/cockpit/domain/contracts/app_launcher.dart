import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';

/// Detecta IDEs instaladas e abre caminhos nelas.
abstract class AppLauncherGateway {
  /// Retorna os apps disponíveis no sistema (ordem = preferência padrão).
  /// Finder/Explorer é sempre incluído no final.
  Future<List<LaunchableApp>> probe();

  /// Abre [path] no [app]. IDEs usam `open -a`; Finder usa `open`.
  Future<void> launch(LaunchableApp app, String path);

  /// Abre [path] no **app padrão do SO** para aquele tipo de arquivo (macOS
  /// `open`, Linux `xdg-open`, Windows `start`). Funciona para arquivo e pasta.
  Future<void> openWithDefaultApp(String path);

  /// Revela [path] no gerenciador de arquivos do SO (Explorer /select no Windows,
  /// open -R no macOS, xdg-open no Linux).
  Future<void> revealInFileManager(String path);
}
