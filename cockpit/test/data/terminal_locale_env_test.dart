import 'package:cockpit/app/cockpit/data/terminal/terminal_locale_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const installed = {'pt_BR.UTF-8', 'en_US.UTF-8', 'zh_CN.UTF-8'};
  bool exists(String locale) => installed.contains(locale);

  Map<String, String> run(
    Map<String, String> env, {
    bool isMacOS = true,
    String localeName = 'pt-BR',
  }) => withUtf8Locale(
    env,
    isMacOS: isMacOS,
    localeName: localeName,
    localeExists: exists,
  );

  group('withUtf8Locale', () {
    test('não mexe fora do macOS', () {
      expect(run({'PATH': '/bin'}, isMacOS: false), {'PATH': '/bin'});
    });

    for (final key in ['LANG', 'LC_ALL', 'LC_CTYPE']) {
      test('respeita $key já definido', () {
        final env = {'PATH': '/bin', key: 'fr_FR.UTF-8'};
        expect(run(env), env);
      });
    }

    test('sem locale herdado, usa o idioma do usuário em UTF-8', () {
      expect(run({'PATH': '/bin'}), {'PATH': '/bin', 'LANG': 'pt_BR.UTF-8'});
    });

    test('troca o encoding legado do localeName por UTF-8', () {
      expect(run({}, localeName: 'pt_BR.ISO8859-1')['LANG'], 'pt_BR.UTF-8');
    });

    test('descarta o script do localeName (zh-Hans-CN → zh_CN)', () {
      expect(run({}, localeName: 'zh-Hans-CN')['LANG'], 'zh_CN.UTF-8');
    });

    test('variável vazia conta como ausente', () {
      expect(run({'LANG': '', 'LC_ALL': ''})['LANG'], 'pt_BR.UTF-8');
    });

    for (final name in ['xx-YY', 'pt', '']) {
      test('locale inexistente ("$name") cai em en_US.UTF-8', () {
        expect(run({}, localeName: name)['LANG'], 'en_US.UTF-8');
      });
    }
  });
}
