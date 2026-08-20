// Plan/32g — the Chat AppBar's line 2 (paired-device name) must render from the
// `initialDevice` hint Home passes, immediately, WITHOUT waiting for the async
// PeerRecord. With no peer bound (activePeer == null), the device label still
// shows — proving the subtitle no longer depends on the async load (no flicker).

import 'dart:async';
import 'dart:io';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_key_value_store.dart';

class _FakeChannel implements IChannel {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Future<void> send(ClientMessage msg) async {}
  @override
  Future<void> close() => _ctrl.close();
}

/// No peer paired → ChatViewModel stays with activePeer == null (the case we
/// want: the subtitle must come from initialDevice, not the PeerRecord).
class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
  @override
  Future<PeerRecord?> loadPeer(String epk) async => null;
}

class _FakeSpeech implements SpeechService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePicker implements IImagePickerService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('rp_v2_chatpage_');
    await LocalBoxes.initForTest(dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets(
    'AppBar line 2 shows the device from initialDevice immediately — no '
    'PeerRecord needed (plan/32g)',
    (tester) async {
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(FakeKeyValueStore()); // no selected peer
      final actions = ActionsRepository(conn);
      final vm = ChatViewModel(read, sync, conn, prefs, _FakeStorage());
      final voice = VoiceInputViewModel(_FakeSpeech());
      final attach = AttachmentViewModel(_FakePicker(), actions);
      final sel = SessionSelection();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatViewModel>.value(value: vm),
              ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
              ChangeNotifierProvider<AttachmentViewModel>.value(value: attach),
              ChangeNotifierProvider<Preferences>.value(value: prefs),
              ChangeNotifierProvider<SessionSelection>.value(value: sel),
            ],
            child: const ChatPage(
              initialTitle: 'My Project',
              initialDevice: 'MacBook de Jacob',
              initialOnline: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Line 2 = device (from initialDevice, even with no PeerRecord loaded).
      expect(find.text('MacBook de Jacob'), findsOneWidget);
      // Line 1 = room title (from initialTitle) — distinct from the device, so
      // we know the subtitle isn't just echoing the title fallback.
      expect(find.text('My Project'), findsOneWidget);

      // The info button renders immediately — even with no PeerRecord loaded
      // (activePeer == null here) — so it never pops in and shifts the AppBar.
      expect(find.byIcon(LucideIcons.info), findsOneWidget);

      // Status dot uses initialOnline before the runtime resolves → shows
      // "online" immediately instead of flashing offline/reconnecting.
      expect(find.text('online'), findsOneWidget);

      // Unmount + dispose in-body (the framework's pending-timer check runs
      // before addTearDown; conn's watchdog must be cancelled here).
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      attach.dispose();
      voice.dispose();
      actions.dispose();
      sync.dispose();
      sel.dispose();
      conn.dispose();
    },
  );
}
