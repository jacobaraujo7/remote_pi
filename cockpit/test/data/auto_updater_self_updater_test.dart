import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/data/update/auto_updater_self_updater.dart';
import 'package:cockpit/app/cockpit/data/update/noop_self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // O dispose() remove o listener do singleton `autoUpdater` (toca o canal de
  // plataforma via EventChannel) — o binding de teste trata isso sem crashar.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sparkle/macOS (autoDownloads: true) — baixa em background', () {
    late AutoUpdaterSelfUpdater updater;

    setUp(() {
      updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast.xml',
        autoDownloads: true,
      );
    });
    tearDown(() => updater.dispose());

    test('isSupported é true', () {
      expect(updater.isSupported, isTrue);
    });

    test('checking-for-update → phase checking', () {
      updater.onUpdaterCheckingForUpdate(null);
      expect(updater.state.phase, SelfUpdatePhase.checking);
    });

    test('update-available → downloading com versão', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloading);
      expect(updater.state.version, '1.6.0');
      expect(updater.state.hasPendingUpdate, isTrue);
      expect(updater.state.isReadyToInstall, isFalse);
      // Ainda baixando → o clique não deve fazer nada.
      expect(updater.state.isActionable, isFalse);
    });

    test('update-downloaded → pronto pra instalar', () {
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0', versionString: '9'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloaded);
      expect(updater.state.isReadyToInstall, isTrue);
      expect(updater.state.isActionable, isTrue);
      expect(updater.state.version, '1.6.0');
    });

    test('versão cai pra versionString quando displayVersionString é null', () {
      updater.onUpdaterUpdateDownloaded(const AppcastItem(versionString: '9'));
      expect(updater.state.version, '9');
    });

    test('update-not-available → idle (sem pendência)', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateNotAvailable(null);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      expect(updater.state.hasPendingUpdate, isFalse);
    });

    test('error carrega a mensagem', () {
      updater.onUpdaterError(UpdaterError('boom'));
      expect(updater.state.phase, SelfUpdatePhase.error);
      expect(updater.state.message, 'boom');
    });

    test('changes emite as transições na ordem', () {
      expectLater(
        updater.changes.map((s) => s.phase),
        emitsInOrder([
          SelfUpdatePhase.checking,
          SelfUpdatePhase.downloading,
          SelfUpdatePhase.downloaded,
        ]),
      );
      updater.onUpdaterCheckingForUpdate(null);
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
    });
  });

  // Regressão do bug do Windows: o WinSparkle não baixa sozinho e nunca emite
  // "update-downloaded", então tratar os dois motores igual prendia a fase em
  // `downloading` pra sempre e fazia o clique no card ser no-op.
  group('WinSparkle/Windows (autoDownloads: false) — para em available', () {
    late AutoUpdaterSelfUpdater updater;

    setUp(() {
      updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast-windows.xml',
        autoDownloads: false,
      );
    });
    tearDown(() => updater.dispose());

    test('update-available → available (NÃO downloading) e já acionável', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.8.4'),
      );
      expect(updater.state.phase, SelfUpdatePhase.available);
      expect(updater.state.hasPendingUpdate, isTrue);
      // O que destrava o clique no card — era isto que faltava.
      expect(updater.state.isActionable, isTrue);
      // Continua não sendo "restart to install": nada foi baixado ainda.
      expect(updater.state.isReadyToInstall, isFalse);
    });

    test('tolera AppcastItem null (o plugin Windows não repassa o item)', () {
      updater.onUpdaterUpdateAvailable(null);
      expect(updater.state.phase, SelfUpdatePhase.available);
      expect(updater.state.version, isNull);
      expect(updater.state.isActionable, isTrue);
    });

    test('update-not-available → idle', () {
      updater.onUpdaterUpdateAvailable(null);
      updater.onUpdaterUpdateNotAvailable(null);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      expect(updater.state.hasPendingUpdate, isFalse);
      expect(updater.state.isActionable, isFalse);
    });
  });

  // #330: o WinSparkle lança o instalador e só *pede* pro host sair. Sem sair,
  // o instalador silencioso encontra o app vivo e aborta — o update baixava e
  // nunca instalava.
  group('before-quit-for-update encerra o app só onde o motor não encerra', () {
    test('Windows: chama quitForUpdate', () async {
      var quits = 0;
      final updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast-windows.xml',
        autoDownloads: false,
        quitForUpdate: () async => quits++,
      );
      addTearDown(updater.dispose);

      updater.onUpdaterBeforeQuitForUpdate(null);
      await Future<void>.delayed(Duration.zero);

      expect(quits, 1);
    });

    test('macOS: não chama (o Sparkle encerra e relança sozinho)', () async {
      var quits = 0;
      final updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast-macos.xml',
        autoDownloads: true,
        quitForUpdate: () async => quits++,
      );
      addTearDown(updater.dispose);

      updater.onUpdaterBeforeQuitForUpdate(null);
      await Future<void>.delayed(Duration.zero);

      expect(quits, 0);
    });

    test('falha ao encerrar não escapa do callback do motor', () async {
      final updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast-windows.xml',
        autoDownloads: false,
        quitForUpdate: () async => throw StateError('window gone'),
      );
      addTearDown(updater.dispose);

      updater.onUpdaterBeforeQuitForUpdate(null);
      await Future<void>.delayed(Duration.zero);
    });

    test('sem quitForUpdate é inerte', () {
      final updater = AutoUpdaterSelfUpdater(
        feedUrl: 'https://example.test/appcast-windows.xml',
        autoDownloads: false,
      );
      addTearDown(updater.dispose);

      expect(() => updater.onUpdaterBeforeQuitForUpdate(null), returnsNormally);
    });
  });

  group('NoopSelfUpdater (Linux)', () {
    test('não suportado e inerte', () async {
      const updater = NoopSelfUpdater();
      expect(updater.isSupported, isFalse);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      // Métodos são no-op e não lançam.
      await updater.initialize();
      await updater.checkForUpdates();
      await updater.applyUpdate();
      expect(updater.state.isReadyToInstall, isFalse);
      expect(updater.state.isActionable, isFalse);
    });
  });
}
