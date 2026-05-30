import 'dart:convert';

import 'package:app/protocol/protocol.dart' show PiHarness;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kPeersService = 'dev.remotepi.peers';
const _kRoomsService = 'dev.remotepi.rooms';

/// Plan-17 follow-up — persisted snapshot of every room we have ever
/// learned about for a peer (relay-announced via `room_announced` /
/// `rooms` push). Allows Home to keep showing the same tiles after a
/// cold start while the relay is still warming up + lets the user
/// open a chat offline and read history.
class PersistedRoom {
  final String roomId;
  final String? name;
  final String? cwd;
  final int startedAt;
  /// Local-only override for [name]. When non-null, takes precedence
  /// in UI (long-press rename).
  final String? localName;
  /// Plan 18 — last-known model the Pi-extension is running with.
  /// Persisted so the subtitle survives cold starts.
  final String? model;

  const PersistedRoom({
    required this.roomId,
    required this.startedAt,
    this.name,
    this.cwd,
    this.localName,
    this.model,
  });

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'name': name,
    'cwd': cwd,
    'started_at': startedAt,
    'local_name': localName,
    'model': model,
  };

  factory PersistedRoom.fromJson(Map<String, dynamic> j) => PersistedRoom(
    roomId: j['room_id'] as String,
    name: j['name'] as String?,
    cwd: j['cwd'] as String?,
    startedAt: (j['started_at'] as num).toInt(),
    localName: j['local_name'] as String?,
    model: j['model'] as String?,
  );

  PersistedRoom copyWith({
    String? name,
    String? cwd,
    int? startedAt,
    Object? localName = _unset,
    Object? model = _unset,
  }) => PersistedRoom(
    roomId: roomId,
    name: name ?? this.name,
    cwd: cwd ?? this.cwd,
    startedAt: startedAt ?? this.startedAt,
    localName: identical(localName, _unset)
        ? this.localName
        : localName as String?,
    model: identical(model, _unset)
        ? this.model
        : model as String?,
  );
}

// ---------------------------------------------------------------------------
// PeerRecord — persisted per pairing
// ---------------------------------------------------------------------------

// Sentinel for nullable copyWith parameters that need to distinguish
// "keep current" (omit) from "set to null" (pass `null` explicitly).
const Object _unset = Object();

class PeerRecord {
  // base64 Ed25519 pubkey of the Pi — the only peer identifier post-rollback.
  final String remoteEpk;
  final String sessionName;
  final String relayUrl;
  final String pairedAt; // ISO-8601
  // Local-only display label (Pi does not know about this). Renders in
  // place of [sessionName] when set; null = use sessionName everywhere.
  final String? nickname;
  /// Plan 17 fix — Pi-side room id (cwd-session) this pairing is bound
  /// to. Set from `PairOk.roomId` on pair, or discovered lazily via
  /// `subscribe_rooms` for legacy peers persisted before this fix.
  /// `null` = not yet discovered; outbound sends fall back to 'main'
  /// while ConnectionManager runs the discovery once.
  final String? roomId;
  /// Plan/27 Wave A — agent harness reported by the PC at pair time.
  /// Surfaced as the "via Pi coding agent" subtitle on the PiCard.
  /// `null` for PeerRecords saved before the field existed; consumers
  /// fall back to [PiHarness.piCodingAgentUnknown] so the UI never
  /// renders an empty subtitle.
  final PiHarness? harness;
  /// Owner signing public key proven during pair_request_v2.
  final String? ownerPk;
  /// Relay-authenticated app peer key bound into pair_request_v2.
  final String? appPeerPk;

  const PeerRecord({
    required this.remoteEpk,
    required this.sessionName,
    required this.relayUrl,
    required this.pairedAt,
    this.nickname,
    this.roomId,
    this.harness,
    this.ownerPk,
    this.appPeerPk,
  });

  Map<String, dynamic> toJson() => {
    'remote_epk': remoteEpk,
    'session_name': sessionName,
    'relay_url': relayUrl,
    'paired_at': pairedAt,
    'nickname': nickname,
    'room_id': roomId,
    if (harness != null) 'harness': harness!.toJson(),
    if (ownerPk != null) 'owner_pk': ownerPk,
    if (appPeerPk != null) 'app_peer_pk': appPeerPk,
  };

  factory PeerRecord.fromJson(Map<String, dynamic> j) {
    final harnessJson = j['harness'];
    return PeerRecord(
      remoteEpk: j['remote_epk'] as String,
      sessionName: j['session_name'] as String,
      relayUrl: j['relay_url'] as String,
      pairedAt: j['paired_at'] as String,
      // Legacy records (saved before plan 10.3) have no 'nickname' field.
      nickname: j['nickname'] as String?,
      // Legacy records (saved before plan 17 fix) have no 'room_id'.
      // Stays null until ConnectionManager discovers it via subscribe_rooms.
      roomId: j['room_id'] as String?,
      // Plan/27 Wave A — harness was added later. Records saved before
      // it lack the field; null falls back to the default at consumer
      // side.
      harness: harnessJson is Map<String, dynamic>
          ? PiHarness.fromJson(harnessJson)
          : null,
      ownerPk: j['owner_pk'] as String?,
      appPeerPk: j['app_peer_pk'] as String?,
    );
  }

  PeerRecord copyWith({
    String? sessionName,
    // Sentinel-typed so the caller can pass `nickname: null` to clear.
    Object? nickname = _unset,
    Object? roomId = _unset,
    Object? harness = _unset,
    Object? ownerPk = _unset,
    Object? appPeerPk = _unset,
  }) => PeerRecord(
    remoteEpk: remoteEpk,
    sessionName: sessionName ?? this.sessionName,
    relayUrl: relayUrl,
    pairedAt: pairedAt,
    nickname: identical(nickname, _unset)
        ? this.nickname
        : nickname as String?,
    roomId: identical(roomId, _unset)
        ? this.roomId
        : roomId as String?,
    harness: identical(harness, _unset)
        ? this.harness
        : harness as PiHarness?,
    ownerPk: identical(ownerPk, _unset)
        ? this.ownerPk
        : ownerPk as String?,
    appPeerPk: identical(appPeerPk, _unset)
        ? this.appPeerPk
        : appPeerPk as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is PeerRecord &&
      other.remoteEpk == remoteEpk &&
      other.sessionName == sessionName &&
      other.relayUrl == relayUrl &&
      other.pairedAt == pairedAt &&
      other.nickname == nickname &&
      other.roomId == roomId &&
      other.harness == harness &&
      other.ownerPk == ownerPk &&
      other.appPeerPk == appPeerPk;

  @override
  int get hashCode => Object.hash(
        remoteEpk,
        sessionName,
        relayUrl,
        pairedAt,
        nickname,
        roomId,
        harness,
        ownerPk,
        appPeerPk,
      );
}

// ---------------------------------------------------------------------------
// PairingStorage
// ---------------------------------------------------------------------------

/// Pairing storage with change notification.
///
/// Mutations to the peer set (`savePeer`, `deletePeer`) and to the
/// per-peer rooms cache (`saveRooms`, `deleteRooms`) call
/// `notifyListeners()` so any UI watching the storage (HomeViewModel,
/// SettingsViewModel) can refresh without manual plumbing between
/// screens. Read methods do not notify.
class PairingStorage extends ChangeNotifier {
  final FlutterSecureStorage _store;

  /// Plan 24 — optional fire-and-forget hook that runs after every
  /// peer mutation (`savePeer` / `deletePeer`). The `MeshSyncService`
  /// registers this so changes propagate to the relay's
  /// `mesh_versions` row in the background. Failures of the hook are
  /// the hook's problem — local mutation is already committed and
  /// observers were notified by the time the hook fires.
  ///
  /// Room mutations are intentionally NOT hooked — rooms are a
  /// per-device cache, not synced membership.
  void Function()? _onPeersMutated;

  PairingStorage([FlutterSecureStorage? store])
    : _store = store ?? const FlutterSecureStorage();

  /// Plug the mesh-publish callback. The hook fires after the local
  /// write completes and after [notifyListeners], so UI sees the
  /// change before the relay does. Pass `null` to detach.
  void attachPeerMutationHook(void Function()? hook) {
    _onPeersMutated = hook;
  }

  // ---- Peer records --------------------------------------------------------

  String _peerKey(String remoteEpk) => '$_kPeersService:$remoteEpk';

  Future<void> savePeer(PeerRecord record) async {
    await _writePeer(record);
    _onPeersMutated?.call();
  }

  /// Same as [savePeer] but skips the mutation hook. Used by the
  /// MeshSyncService when applying a verified mesh blob to the local
  /// cache — without this we'd round-trip back to the relay
  /// (pull→apply→savePeer→hook→publish) and a race could publish an
  /// empty members list (see plan/24-fix-app-publish-race).
  Future<void> savePeerSilent(PeerRecord record) => _writePeer(record);

  Future<PeerRecord?> loadPeer(String remoteEpk) async {
    final raw = await _store.read(key: _peerKey(remoteEpk));
    if (raw == null) return null;
    return PeerRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deletePeer(String remoteEpk) async {
    await _erasePeer(remoteEpk);
    _onPeersMutated?.call();
  }

  /// Same as [deletePeer] but skips the mutation hook — see
  /// [savePeerSilent] for the rationale.
  Future<void> deletePeerSilent(String remoteEpk) => _erasePeer(remoteEpk);

  Future<void> _writePeer(PeerRecord record) async {
    await _store.write(
      key: _peerKey(record.remoteEpk),
      value: jsonEncode(record.toJson()),
    );
    notifyListeners();
  }

  Future<void> _erasePeer(String remoteEpk) async {
    await _store.delete(key: _peerKey(remoteEpk));
    notifyListeners();
  }

  Future<List<PeerRecord>> listPeers() async {
    final all = await _store.readAll();
    final prefix = '$_kPeersService:';
    return all.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => PeerRecord.fromJson(
          jsonDecode(e.value) as Map<String, dynamic>,
        ))
        .toList();
  }

  /// Wipe every peer + every persisted room map. Used by the
  /// Owner-key bridge when iCloud / Backup sync brings a different
  /// Owner-pk — the previous device's peer list is meaningless for
  /// the newly-synced identity, so we start clean rather than risk
  /// connecting against stale `remote_epk`s.
  Future<void> wipeAll() async {
    final all = await _store.readAll();
    final prefixes = ['$_kPeersService:', '$_kRoomsService:'];
    for (final key in all.keys) {
      if (prefixes.any(key.startsWith)) {
        await _store.delete(key: key);
      }
    }
    notifyListeners();
  }

  // ---- Rooms (plan 17 follow-up) -----------------------------------------

  String _roomsKey(String remoteEpk) => '$_kRoomsService:$remoteEpk';

  /// Persist the full set of known rooms for a peer. Replaces any
  /// previously stored set. Called on every room-state change in
  /// ConnectionManager so a cold start can reflect the same view.
  Future<void> saveRooms(String remoteEpk, List<PersistedRoom> rooms) async {
    await _store.write(
      key: _roomsKey(remoteEpk),
      value: jsonEncode(rooms.map((r) => r.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<List<PersistedRoom>> loadRooms(String remoteEpk) async {
    final raw = await _store.read(key: _roomsKey(remoteEpk));
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PersistedRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteRooms(String remoteEpk) async {
    await _store.delete(key: _roomsKey(remoteEpk));
    notifyListeners();
  }
}
