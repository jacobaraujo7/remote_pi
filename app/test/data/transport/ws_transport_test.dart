import 'package:app/data/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('senderRoomFromEnvelope', () {
    test('prefers source_room for legacy raw-forward relay frames', () {
      expect(
        senderRoomFromEnvelope({
          'peer': 'app-peer',
          'room': 'main',
          'source_room': 'pi-room-1',
          'ct': 'AAA=',
        }),
        'pi-room-1',
      );
    });

    test('falls back to relay-rewritten room', () {
      expect(
        senderRoomFromEnvelope({
          'peer': 'pi-peer',
          'room': 'pi-room-2',
          'ct': 'AAA=',
        }),
        'pi-room-2',
      );
    });
  });
}
