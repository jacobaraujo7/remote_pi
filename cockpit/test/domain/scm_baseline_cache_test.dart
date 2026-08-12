import 'package:cockpit/app/cockpit/domain/contracts/git_head_baseline_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_head_baseline.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_baseline_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeReader implements GitHeadBaselineReader {
  String? head = 'aaa';
  final Map<String, String> blobs = <String, String>{};
  int readCalls = 0;
  int headCalls = 0;

  @override
  Future<String?> resolveHeadIdentity(String repoPath) async {
    headCalls++;
    return head;
  }

  @override
  Future<GitHeadBaseline?> readTrackedText(
    String repoPath,
    String absPath,
  ) async {
    readCalls++;
    final content = blobs[absPath];
    final id = head;
    if (content == null || id == null) return null;
    return GitHeadBaseline(headIdentity: id, content: content);
  }
}

void main() {
  test('cacheia por root/path/head e evita releitura', () async {
    final fake = _FakeReader()..blobs['/repo/a.txt'] = 'v1\n';
    final cache = ScmBaselineCache(fake);

    final first = await cache.baselineFor('/repo', '/repo/a.txt');
    final second = await cache.baselineFor('/repo', '/repo/a.txt');

    expect(first!.content, 'v1\n');
    expect(second, same(first));
    expect(fake.readCalls, 1);
  });

  test('mudança de HEAD invalida reuso da entrada antiga', () async {
    final fake = _FakeReader()..blobs['/repo/a.txt'] = 'v1\n';
    final cache = ScmBaselineCache(fake);

    await cache.baselineFor('/repo', '/repo/a.txt');
    fake.head = 'bbb';
    fake.blobs['/repo/a.txt'] = 'v2\n';
    cache.invalidateRepo('/repo');

    final next = await cache.baselineFor('/repo', '/repo/a.txt');
    expect(next!.content, 'v2\n');
    expect(next.headIdentity, 'bbb');
    expect(fake.readCalls, 2);
  });

  test('retarget/invalidateRepo não reusa entradas da root', () async {
    final fake = _FakeReader()..blobs['/repo/a.txt'] = 'v1\n';
    final cache = ScmBaselineCache(fake);

    await cache.baselineFor('/repo', '/repo/a.txt');
    cache.invalidateRepo('/repo');
    await cache.baselineFor('/repo', '/repo/a.txt');
    expect(fake.readCalls, 2);
  });

  test('HEAD ilegível → null sem cachear', () async {
    final fake = _FakeReader()..head = null;
    final cache = ScmBaselineCache(fake);
    expect(await cache.baselineFor('/repo', '/repo/a.txt'), isNull);
    expect(fake.readCalls, 0);
  });
}
