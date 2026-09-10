import 'dart:io';

import 'package:cockpit/app/cockpit/data/terminal/sidecar/sidecar_terminal_connector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressão do bug que deixou toda aba de terminal ~5,8s mais lenta na 1.28.0:
/// o exe do servidor virou um Mach-O universal (lipo), o `dartaotruntime` não
/// achava mais o snapshot anexado e o sidecar nunca subia. O bundle passou a
/// trazer uma fatia por arquitetura, e é o resolver que escolhe.
void main() {
  late Directory bin;

  setUp(() {
    bin = Directory.systemTemp.createTempSync('cockpit-bundle-bin');
  });
  tearDown(() => bin.deleteSync(recursive: true));

  String touch(String name) {
    final f = File('${bin.path}/$name')..writeAsStringSync('x');
    return f.path;
  }

  test('prefere a fatia da arquitetura pedida', () {
    touch(SidecarTerminalConnector.serverExeName);
    final arm = touch(SidecarTerminalConnector.serverExeFor('arm64'));
    final x64 = touch(SidecarTerminalConnector.serverExeFor('x64'));

    expect(
      SidecarTerminalConnector.serverBinaryIn(bin.path, arch: 'arm64'),
      arm,
    );
    expect(SidecarTerminalConnector.serverBinaryIn(bin.path, arch: 'x64'), x64);
  });

  test('cai no nome sem sufixo para a arquitetura nativa', () {
    final plain = touch(SidecarTerminalConnector.serverExeName);

    expect(
      SidecarTerminalConnector.serverBinaryIn(
        bin.path,
        arch: SidecarTerminalConnector.hostArch,
      ),
      plain,
    );
  });

  test('sem binário algum devolve null', () {
    expect(SidecarTerminalConnector.serverBinaryIn(bin.path), isNull);
  });

  test('target de outro OS usa a raiz targets/<os>-<arch>', () {
    final root = bin.path;
    final crossOs = SidecarTerminalConnector.hostOs == 'linux'
        ? 'darwin'
        : 'linux';
    final targetBin = Directory('$root/targets/$crossOs-arm64/bin')
      ..createSync(recursive: true);
    final target = File(
      '${targetBin.path}/${SidecarTerminalConnector.serverExeNameFor(crossOs)}',
    )..writeAsStringSync('cross');

    expect(
      SidecarTerminalConnector.serverBinaryInBundle(
        root,
        os: crossOs,
        arch: 'arm64',
      ),
      target.path,
    );
  });

  test('mesmo OS em outra arquitetura rejeita binário sem sufixo', () {
    final root = bin.path;
    final nativeBin = Directory('$root/bin')..createSync();
    File(
      '${nativeBin.path}/${SidecarTerminalConnector.serverExeName}',
    ).writeAsStringSync('native');
    final otherArch = SidecarTerminalConnector.hostArch == 'arm64'
        ? 'x64'
        : 'arm64';

    expect(
      SidecarTerminalConnector.serverBinaryInBundle(
        root,
        os: SidecarTerminalConnector.hostOs,
        arch: otherArch,
      ),
      isNull,
    );
  });

  test('env override também é rejeitado para outra arquitetura', () {
    final root = bin.path;
    final nativeBin = Directory('$root/bin')..createSync();
    final envBinary = File('$root/from-env')..writeAsStringSync('native');
    final otherArch = SidecarTerminalConnector.hostArch == 'arm64'
        ? 'x64'
        : 'arm64';

    expect(
      SidecarTerminalConnector.resolveServerBundleBinaryFrom(
        os: SidecarTerminalConnector.hostOs,
        arch: otherArch,
        nativeBinDirs: [nativeBin.path],
        environmentBinary: envBinary.path,
      ),
      isNull,
    );
  });

  test('mesmo OS em outra arquitetura aceita fatia explícita', () {
    final root = bin.path;
    final nativeBin = Directory('$root/bin')..createSync();
    final otherArch = SidecarTerminalConnector.hostArch == 'arm64'
        ? 'x64'
        : 'arm64';
    final slice = File(
      '${nativeBin.path}/${SidecarTerminalConnector.serverExeFor(otherArch)}',
    )..writeAsStringSync('slice');

    expect(
      SidecarTerminalConnector.serverBinaryInBundle(
        root,
        os: SidecarTerminalConnector.hostOs,
        arch: otherArch,
      ),
      slice.path,
    );
  });

  test('target de outro OS nunca cai no binário nativo', () {
    final root = bin.path;
    final nativeBin = Directory('$root/bin')..createSync();
    File(
      '${nativeBin.path}/${SidecarTerminalConnector.serverExeName}',
    ).writeAsStringSync('native');
    final crossOs = SidecarTerminalConnector.hostOs == 'linux'
        ? 'darwin'
        : 'linux';

    expect(
      SidecarTerminalConnector.serverBinaryInBundle(
        root,
        os: crossOs,
        arch: 'arm64',
      ),
      isNull,
    );
  });
}
