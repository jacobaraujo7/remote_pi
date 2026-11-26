import 'package:cockpit/app/cockpit/data/remote/ssh_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

/// O fallback TCP só pode nascer do sinal certo. Estes são os vereditos do
/// stderr do OpenSSH quando o forward UNIX não abre o canal remoto.
void main() {
  test('Tailscale SSH recusando streamlocal vira fallback', () {
    const detail =
        'channel 1: open failed: unknown channel type: unsupported channel type';

    expect(isStreamlocalUnsupported(detail), isTrue);
    expect(unixFailureSuggestsRendezvous(detail), isFalse);
  });

  test('variação "unsupported channel type" também é reconhecida', () {
    expect(
      isStreamlocalUnsupported(
        'channel 2: open failed: unsupported channel type',
      ),
      isTrue,
    );
  });

  test('socket ausente NÃO troca o transporte', () {
    const detail =
        'channel 1: open failed: connect failed: No such file or directory';

    expect(isStreamlocalUnsupported(detail), isFalse);
    expect(unixFailureSuggestsRendezvous(detail), isFalse);
  });

  test('arquivo no lugar do socket sugere rendezvous TCP', () {
    const detail = 'channel 1: open failed: connect failed: Connection refused';

    expect(isStreamlocalUnsupported(detail), isFalse);
    expect(unixFailureSuggestsRendezvous(detail), isTrue);
  });

  test('sem stderr não há veredito', () {
    expect(unixFailureSuggestsRendezvous(null), isFalse);
    expect(isStreamlocalUnsupported(''), isFalse);
  });
}
