// Plan 17 — HomeList.items() flattens peers × rooms into tile rows.

import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

PeerRecord _peer(String epk, {String name = 'Pi'}) => PeerRecord(
      remoteEpk: epk,
      sessionName: name,
      relayUrl: 'ws://x',
      pairedAt: '2026-01-01T00:00:00Z',
    );

void main() {
  group('HomeList.items()', () {
    test(
      'peer without announced rooms produces ZERO items — Home only '
      'shows what is currently live on the relay (no ghost "main" tile)',
      () {
        final list = HomeList(peers: [_peer('A')]);
        final items = list.items();
        expect(items, isEmpty);
      },
    );

    test('peer with N rooms produces N items (one row per cwd)', () {
      final list = HomeList(
        peers: [_peer('A')],
        roomsByPeer: {
          'A': [
            const RoomInfo(roomId: 'r1', startedAt: 1, cwd: '/one'),
            const RoomInfo(roomId: 'r2', startedAt: 2, cwd: '/two'),
          ],
        },
      );
      final items = list.items();
      expect(items, hasLength(2));
      expect(items.map((i) => i.room.roomId).toList(), ['r1', 'r2']);
    });

    test(
      'multiple peers each contribute their own group of rows; the '
      'flat list keeps peer-order from `peers`',
      () {
        final list = HomeList(
          peers: [_peer('A'), _peer('B')],
          roomsByPeer: {
            'A': [const RoomInfo(roomId: 'a1', startedAt: 1)],
            'B': [
              const RoomInfo(roomId: 'b1', startedAt: 1),
              const RoomInfo(roomId: 'b2', startedAt: 2),
            ],
          },
        );
        final items = list.items();
        expect(items.map((i) => i.peer.remoteEpk).toList(),
            ['A', 'B', 'B']);
        expect(items.map((i) => i.room.roomId).toList(),
            ['a1', 'b1', 'b2']);
      },
    );

    test('HomeItem.displayName prefers local alias → Pi `/name` → mesh name → cwd', () {
      final namedRoom = HomeItem(
        peer: _peer('A'),
        room: const RoomInfo(
          roomId: 'r1',
          startedAt: 1,
          name: 'project-alpha',
          cwd: '/whatever',
        ),
      );
      expect(namedRoom.displayName, 'project-alpha');

      final sessionNamedRoom = HomeItem(
        peer: _peer('A'),
        room: const RoomInfo(
          roomId: 'r1',
          startedAt: 1,
          name: 'mesh-agent',
          sessionDisplayName: 'Review payments',
        ),
      );
      expect(sessionNamedRoom.displayName, 'Review payments');

      final locallyNamedRoom = HomeItem(
        peer: _peer('A'),
        room: const RoomInfo(
          roomId: 'r1',
          startedAt: 1,
          name: 'mesh-agent',
          sessionDisplayName: 'Review payments',
          localName: 'Pinned alias',
        ),
      );
      expect(locallyNamedRoom.displayName, 'Pinned alias');

      final cwdRoom = HomeItem(
        peer: _peer('A'),
        room: const RoomInfo(
          roomId: 'r1',
          startedAt: 1,
          cwd: '/Users/jacob/projects/remote_pi/app',
        ),
      );
      expect(cwdRoom.displayName, 'app');
    });
  });
}
