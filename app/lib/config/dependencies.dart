import 'dart:async';
import 'dart:io' show Platform;

import 'package:app/config/utils/injector.dart';
import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/notifications/local_notifier.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/home_read_repository.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart'; // IChannel
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/data/update/secure_dismissed_update_store.dart';
import 'package:app/data/update/update_checker_impl.dart';
import 'package:app/data/update/url_launcher_opener.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/domain/contracts/dismissed_update_store.dart';
import 'package:app/domain/contracts/notifier.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  // Plan 31 — local SSOT box facade (boxes already opened + runtime wiped in
  // bootstrap before this runs).
  _injector.addInstance<LocalBoxes>(LocalBoxes());

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

  // Plan 29 — on-device speech-to-text. Singleton: it owns a broadcast
  // sound-level stream that must survive across chat navigations; the
  // injector disposes it at app teardown. VoiceInputViewModel never
  // disposes it (it only stops/cancels sessions).
  _injector.addService<SpeechService>(() => SpeechToTextService());

  // Plan 30 — image picker + on-device JPEG compression. Stateless, no
  // dispose hook needed.
  _injector.addOther<IImagePickerService>(() => ImagePickerService());

  _injector.addOther<Notifier>(() => LocalNotifier());

  // Plan 31 — SSOT writer + read-only repos. SyncService is the SINGLE
  // mutator of the message/index/runtime boxes; the read repos only watch.
  _injector.addService<SyncService>(
    () => SyncService(
      _injector.get<ConnectionManager>(),
      _injector.get<LocalBoxes>(),
      _injector.get<Notifier>(),
    ),
  );
  _injector.addRepository<SessionReadRepository>(
    () => SessionReadRepository(_injector.get<LocalBoxes>()),
  );
  _injector.addRepository<HomeReadRepository>(
    () => HomeReadRepository(_injector.get<LocalBoxes>()),
  );

  // Repositories
  _injector.addRepository<IActionsRepository>(
    () => ActionsRepository(_injector.get<ConnectionManager>()),
  );

  // ViewModels
  _injector.addViewModel<ChatViewModel>(
    () => ChatViewModel(
      _injector.get<SessionReadRepository>(),
      _injector.get<SyncService>(),
      _injector.get<ConnectionManager>(),
      _injector.get<Preferences>(),
      _injector.get<PairingStorage>(),
    ),
  );
  _injector.addViewModel<HomeViewModel>(
    () => HomeViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
    ),
  );
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
      _injector.get<ConnectionManager>(),
      _injector.get<Preferences>(),
      _injector.get<OwnerIdentityBridge>(),
    ),
  );
  _injector.addViewModel<OnboardingViewModel>(OnboardingViewModel.new);
  _injector.addViewModel<QuickActionsViewModel>(
    () => QuickActionsViewModel(_injector.get<IActionsRepository>()),
  );
  // Plan 29 — voice input. New instance per chat mount; reuses the shared
  // SpeechService singleton (which it stops/cancels but never disposes).
  _injector.addViewModel<VoiceInputViewModel>(
    () => VoiceInputViewModel(_injector.get<SpeechService>()),
  );
  // Plan 30 — image attachment. New instance per chat mount; resolves model
  // vision via the shared ActionsRepository catalogue cache.
  _injector.addViewModel<AttachmentViewModel>(
    () => AttachmentViewModel(
      _injector.get<IImagePickerService>(),
      _injector.get<IActionsRepository>(),
    ),
  );

  // Plan/tablet — app-global UI selection (which session the tablet's
  // detail pane shows + which list tile is highlighted). Starts null so
  // the app opens with no chat pre-selected.
  _injector.addInstance<SessionSelection>(SessionSelection());

  // Plan/tablet — shell layout state (zero-state collapse). Set by Home so
  // the adaptive shell drops the split when there's nothing to list.
  _injector.addInstance<ShellLayout>(ShellLayout());

  // Plan 44 — Android-only in-app update notice. The running version comes
  // from package_info; the manifest fetch + gating live in the ViewModel
  // (silent on iOS via `enabled` and on any fetch failure). Stateless
  // collaborators → addOther (lazy singleton, no dispose hook).
  final packageInfo = await PackageInfo.fromPlatform();
  final appVersion = packageInfo.version;
  _injector.addOther<UpdateChecker>(() => UpdateCheckerImpl());
  _injector.addOther<DismissedUpdateStore>(() => SecureDismissedUpdateStore());
  _injector.addOther<UrlOpener>(() => const UrlLauncherOpener());
  _injector.addViewModel<UpdateBannerViewModel>(
    () => UpdateBannerViewModel(
      _injector.get<UpdateChecker>(),
      _injector.get<DismissedUpdateStore>(),
      _injector.get<UrlOpener>(),
      currentVersion: appVersion,
      enabled: Platform.isAndroid,
    ),
  );

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

  return PlainPeerChannel(transport: transport);
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
