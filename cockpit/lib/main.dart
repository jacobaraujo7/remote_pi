import 'package:cockpit/app/bootstrapper.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Bootstrap real (Hive, shell, cleanup de órfãos, hooks, AppModule) mora no
/// [CockpitBootstrapper]: a janela abre imediatamente com tela de loading e o
/// setup lento roda atrás, com tela de erro + retry se algo falhar.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Plano 46 — inicializa o media_kit (libmpv) antes de qualquer Player.
  MediaKit.ensureInitialized();

  runApp(const CockpitBootstrapper());
}
