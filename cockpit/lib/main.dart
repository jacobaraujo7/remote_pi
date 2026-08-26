import 'dart:io';

import 'package:cockpit/app/bootstrapper.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/data/diagnostics/error_handlers.dart';
import 'package:cockpit/app/core/ui/widgets/app_error_view.dart';
import 'package:cockpit/app/core/ui/widgets/error_report_dialog.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Bootstrap real (Hive, shell, cleanup de órfãos, hooks, AppModule) mora no
/// [CockpitBootstrapper]: a janela abre imediatamente com tela de loading e o
/// setup lento roda atrás, com tela de erro + retry se algo falhar.
///
/// Aqui fica só o que precisa envolver *tudo*: a captura global de erros. Um app
/// GUI não tem stdout visível, então sem isso qualquer falha em produção some
/// sem deixar rastro — inclusive as que fecham o app sozinho.
Future<void> main() async {
  await runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // O terminal Ghostty mede a grade antes de montar seu atlas de glifos. Se
    // JetBrains Mono ainda estiver sendo registrada assincronamente pelo
    // google_fonts, a primeira medida usa o fallback proporcional e cada
    // caractere ganha uma celula larga demais ate alguma configuracao de fonte
    // forcar novo layout. Carregue previamente todos os pesos que o terminal
    // oferece para que medida e rasterizacao usem a mesma face desde o primeiro
    // frame.
    await GoogleFonts.pendingFonts([
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w300),
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w400),
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w500),
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w600),
    ]);

    // Mobile (iPad/Android): todas as orientações liberadas (plano 60, Wave F).
    // Em telas estreitas (portrait de celular) o shell colapsa as panes laterais
    // em drawers por breakpoint de largura; landscape/tablet seguem inline.
    // Desktop não tem orientação; o guard evita chamar o canal onde não há.
    if (Platform.isIOS || Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // ShadcnApp delegates to WidgetsApp but does not expose the inspector HUD
    // builders. Disable WidgetsApp's automatic inspector insertion so AppRoot
    // can provide one manually with the same DevTools selection semantics and
    // shadcn-compatible controls.
    assert(() {
      WidgetsBinding.instance.debugExcludeRootWidgetInspector = true;
      return true;
    }());

    // Versão primeiro: alimenta o log e os relatórios de issue.
    final version = await _resolveVersion();
    setDiagnosticsAppVersion(version);
    await DiagnosticsLog.instance.init(appVersion: version);

    // Erro de build vira painel legível em vez da caixa cinza do Flutter.
    AppErrorView.install();

    // Plano 46 — inicializa o media_kit (libmpv) antes de qualquer Player.
    MediaKit.ensureInitialized();

    // i18n: fallback inicial = locale do SO. O `SettingsController.load()`
    // (dentro do bootstrapper) sobrescreve com a preferência salva, se houver.
    await LocaleSettings.useDeviceLocale();

    // `TranslationProvider` fica acima de tudo — é ele quem reconstrói a árvore
    // quando `LocaleSettings.setLocale()` é chamado (troca de idioma em runtime).
    runApp(TranslationProvider(child: const CockpitBootstrapper()));
  });
}

/// Versão do pubspec via `PackageInfo`. Falha aqui não pode impedir o boot — o
/// diagnóstico degrada para "unknown" e o app abre normalmente.
Future<String> _resolveVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } on Object catch (_) {
    return 'unknown';
  }
}
