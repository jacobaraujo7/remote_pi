import 'package:cockpit/app/cockpit/domain/validators/git_clone_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isGitCloneUrl', () {
    test('aceita HTTPS, ssh:// e scp-like', () {
      for (final url in [
        'https://github.com/org/repo.git',
        'https://github.com/org/repo',
        'http://gitlab.local/group/sub/repo.git',
        'ssh://git@github.com/org/repo.git',
        'git@github.com:org/repo.git',
        'git@bitbucket.org:team/repo',
        '  git@github.com:org/repo.git  ',
      ]) {
        expect(isGitCloneUrl(url), isTrue, reason: url);
      }
    });

    test('recusa vazio, texto solto, só host e transports locais', () {
      for (final url in [
        '',
        'repo',
        'https://github.com',
        'https://github.com/',
        'file:///tmp/repo',
        'ext::sh -c touch% /tmp/pwned',
        'git@github.com:org/repo.git extra',
        '/Users/me/repo',
        r'C:\Users\me\repo',
        'C:/Users/me/repo',
        r'\\server\share\repo.git',
        r'git@github.com:org\repo.git',
      ]) {
        expect(isGitCloneUrl(url), isFalse, reason: url);
      }
    });
  });

  group('repoNameFromGitUrl', () {
    test('extrai o último segmento sem .git', () {
      expect(repoNameFromGitUrl('https://github.com/org/repo.git'), 'repo');
      expect(repoNameFromGitUrl('https://github.com/org/repo/'), 'repo');
      expect(repoNameFromGitUrl('git@github.com:org/my-app.git'), 'my-app');
      expect(repoNameFromGitUrl('git@host:repo.git'), 'repo');
      expect(repoNameFromGitUrl('https://h.com/org/repo.git?x=1#f'), 'repo');
    });

    test('null quando não há nome', () {
      expect(repoNameFromGitUrl(''), isNull);
      expect(repoNameFromGitUrl('https://h.com/.git'), isNull);
    });
  });
}
