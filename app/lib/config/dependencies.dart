import 'dart:async';

import 'package:app/config/utils/injector.dart';
import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/repositories/session_history_store.dart';
import 'package:app/data/repositories/session_repository.dart';
import 'package:app/data/transport/channel.dart'; // IChannel
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:provider/provider.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';

final _injector = CustomInjector();

/// Direct injector access — only for bootstrap, tests, and deep-link handlers.
CustomInjector get injector => _injector;

Future<void> setupDependencies() async {
  // Infrastructure singletons
  _injector.addInstance<PairingStorage>(PairingStorage());

  final prefs = Preferences();
  await prefs.load();
  _injector.addInstance<Preferences>(prefs);

  _injector.addInstance<SessionHistoryStore>(SessionHistoryStore());

  // Plan 23 — Owner-key sync. The store talks to the native plugin
  // (iCloud Keychain on iOS, Block Store on Android); the bridge sits
  // between it and the rest of the app, owning boot + watch-for-reset.
  final OwnerIdentityStore ownerStore = MethodChannelOwnerIdentityStore();
  _injector.addInstance<OwnerIdentityStore>(ownerStore);
  final ownerBridge = OwnerIdentityBridge(
    ownerStore,
    _injector.get<PairingStorage>(),
  );
  _injector.addInstance<OwnerIdentityBridge>(ownerBridge);

  // Plan 24 — mesh_versions HTTP client + sync service. Base URL is
  // the user-configured relay verbatim (always http(s):// per the
  // post-Wave-2 URL scheme decision — see plan/24-fix-app-url-scheme).
  // No translation needed: the relay's `/mesh` endpoint shares host +
  // port with the WebSocket.
  final meshClient = MeshClient(baseUrlProvider: () => resolveRelayUrl(prefs));
  _injector.addInstance<MeshClient>(meshClient);
  final meshSync = MeshSyncService(
    meshClient,
    ownerBridge,
    _injector.get<PairingStorage>(),
  );
  _injector.addInstance<MeshSyncService>(meshSync);
  _injector.get<PairingStorage>().attachPeerMutationHook(() {
    // ignore: unawaited_futures
    meshSync.publish();
  });

  // ConnectionManager — factory function injected manually (function typedefs
  // cannot be resolved by auto_injector via Type.new).
  _injector.addService<ConnectionManager>(
    () => ConnectionManager(
      factory: _productionConnectionFactory,
      storage: _injector.get<PairingStorage>(),
    ),
  );

  // Repositories
  _injector.addRepository<ISessionRepository>(SessionRepository.new);

  // ViewModels
  _injector.addViewModel<ChatViewModel>(ChatViewModel.new);
  _injector.addViewModel<HomeViewModel>(HomeViewModel.new);
  _injector.addViewModel<SettingsViewModel>(
    () => SettingsViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
      _injector.get<MeshSyncService>(),
    ),
  );
  _injector.addViewModel<PairingViewModel>(
    () => PairingViewModel(
      _injector.get<PairingStorage>(),
      _productionPairingTransportFactory,
      _injector.get<ISessionRepository>(),
      _injector.get<Preferences>(),
      _injector.get<OwnerIdentityBridge>(),
    ),
  );
  _injector.addViewModel<OnboardingViewModel>(OnboardingViewModel.new);

  _injector.commit();
}

// ---------------------------------------------------------------------------
// Production ConnectionFactory — used by ConnectionManager for reconnection.
// Post-rollback: just open transport + wrap in PlainPeerChannel; Pi recognizes
// the peer via peers.json (no per-reconnect handshake).
// Plan 23: Owner-sk (synced via iCloud Keychain / Block Store) is the
// challenge-response key. OwnerIdentityBridge.boot() is the router's
// responsibility; by the time this factory runs, the identity is loaded.
// ---------------------------------------------------------------------------

Future<IChannel> _productionConnectionFactory(
  PeerRecord peer,
  CancelToken cancel,
) async {
  final bridge = injector.get<OwnerIdentityBridge>();
  final ownerKey = await bridge.requireKeyPair();
  if (cancel.isCancelled) throw _CancelledError();

  // Defensive timeout (plano app-state-normalization): without this the
  // WebSocket connect + Ed25519 challenge round-trip can hang
  // indefinitely if the relay is unreachable — ChatViewModel would sit
  // in `ChatConnecting` forever. Throwing here pushes the manager into
  // its retry/backoff path, which is observable as `StatusRetrying` and
  // renders a "reconnecting" banner rather than an empty spinner.
  const wsConnectTimeout = Duration(seconds: 10);
  // Resolve the GLOBAL relay URL (plan 14): user override > default.
  // `peer.relayUrl` is kept on PeerRecord for legacy QR payloads but is
  // no longer consulted when opening a connection.
  final relayUrl = resolveRelayUrl(_injector.get<Preferences>());
  final transport =
      await WsTransport.connect(
        relayUrl: relayUrl,
        peerPubkey: peer.remoteEpk,
        ed25519Key: ownerKey,
      ).timeout(
        wsConnectTimeout,
        onTimeout: () => throw TimeoutException(
          'WS connect to $relayUrl timed out after '
          '${wsConnectTimeout.inSeconds}s',
        ),
      );

  if (cancel.isCancelled) {
    await transport.close();
    throw _CancelledError();
  }

  return PlainPeerChannel(
    transport: transport,
    signingKey: peer.supportsSignedInnerV1 ? ownerKey : null,
    expectedRemotePubkey: peer.supportsSignedInnerV1 ? peer.remoteEpk : null,
    roomId: peer.supportsSignedInnerV1 ? peer.roomId : null,
    requireSigned: peer.supportsSignedInnerV1,
  );
}

// ---------------------------------------------------------------------------
// Production PairingTransportFactory — used by PairingViewModel for first pair.
// ---------------------------------------------------------------------------

Future<PeerTransport> _productionPairingTransportFactory(
  QrPairPayload qr,
  SimpleKeyPair deviceEd25519,
) async {
  // Plan 14: pairing connects via the GLOBAL relay URL (Preferences),
  // not whatever was embedded in the QR. Mismatch between qr.relayUrl
  // and the user's configured relay is handled upstream by
  // `pair_request_flow.dart` (raises a `relay_mismatch` error that
  // PairingViewModel surfaces as a "trocar relay?" modal).
  final relayUrl = resolveRelayUrl(_injector.get<Preferences>());
  return WsTransport.connect(
    relayUrl: relayUrl,
    peerPubkey: qr.epk,
    ed25519Key: deviceEd25519,
  );
}

// ---------------------------------------------------------------------------

class _CancelledError implements Exception {
  const _CancelledError();
}

void disposeDependencies() => _injector.dispose();

/// Bridges auto_injector and provider: creates a `ChangeNotifierProvider` that
/// asks the injector for a fresh `ViewModel<T>` instance on each route mount.
class ViewmodelProvider<T extends ViewModel> extends ChangeNotifierProvider<T> {
  ViewmodelProvider({super.key, super.child})
    : super(create: (_) => _injector.get<T>());

  ViewmodelProvider.value({super.key, required super.value, super.child})
    : super.value();
}
