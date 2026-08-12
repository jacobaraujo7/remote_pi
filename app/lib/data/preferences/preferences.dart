import 'package:app/domain/contracts/key_value_store.dart';
import 'package:app/ui/core/themes/app_font_scale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// App-wide UI preferences (persisted across launches).
///
/// Extends [ChangeNotifier] so widgets can `context.watch<Preferences>()`
/// and rebuild on toggle. Backed by a [KeyValueStore] (non-sensitive data —
/// `shared_preferences` in production). Call [load] once during bootstrap
/// before the first frame to hydrate the in-memory cache.
class Preferences extends ChangeNotifier {
  final KeyValueStore _store;
  bool _hideToolCalls = false;
  String? _selectedPeerEpk;
  String? _relayUrl;
  bool _onboardingCompleted = false;
  ThemeMode _themeMode = ThemeMode.system;
  AppFontScale _fontScale = AppFontScale.standard;

  Preferences(this._store);

  static const _kHideToolCallsKey = 'prefs.hide_tool_calls';
  static const _kSelectedPeerEpkKey = 'prefs.selected_peer_epk';
  static const _kRelayUrlKey = 'prefs.relay_url';
  static const _kOnboardingCompletedKey = 'prefs.onboarding_completed';
  static const _kThemeModeKey = 'prefs.theme_mode';
  static const _kFontScaleKey = 'prefs.font_scale';

  /// True → chat hides `ToolEvent` rows (only user/assistant text remain).
  bool get hideToolCalls => _hideToolCalls;

  /// Epoch of the peer the user last picked from Home — the one
  /// `/chat` will connect to when it mounts. Null = no peer selected yet
  /// (user is still browsing or hasn't paired). Persisted so reopening
  /// the app right into `/chat` (e.g. via deep-link) knows which peer.
  ///
  /// Plan 17: under the new rooms model the persisted value carries an
  /// optional `:roomId` suffix (e.g. `Bz02uLi…:main` or
  /// `Bz02uLi…:room-uuid-xyz`). The getter returns only the EPK; use
  /// [selectedRoomId] for the room half. Legacy values without the
  /// `:room` suffix transparently fall through (the value is the epk
  /// and `selectedRoomId` returns null → falls back to 'main' at the
  /// caller).
  String? get selectedPeerEpk {
    final raw = _selectedPeerEpk;
    if (raw == null) return null;
    final ix = raw.indexOf(':');
    return ix < 0 ? raw : raw.substring(0, ix);
  }

  /// Plan 17 — the room half of the persisted selected target. Returns
  /// null for legacy values (caller defaults to 'main').
  String? get selectedRoomId {
    final raw = _selectedPeerEpk;
    if (raw == null) return null;
    final ix = raw.indexOf(':');
    if (ix < 0) return null;
    final r = raw.substring(ix + 1);
    return r.isEmpty ? null : r;
  }

  /// Composite raw value (epk[:room]). Tests can inspect.
  String? get selectedRoomRaw => _selectedPeerEpk;

  /// User-configured relay URL override. `null` = use the public default
  /// (`kDefaultRelayUrl` in `relay_config.dart`). Set via Settings or
  /// during onboarding step 2 (custom relay).
  String? get relayUrl => _relayUrl;

  /// `true` after the user completed the 3-step onboarding flow at least
  /// once. Drives `/boot` redirect: false → `/onboarding`, true → `/home`.
  bool get onboardingCompleted => _onboardingCompleted;

  /// Preferred app theme. `ThemeMode.system` (default) follows the OS
  /// light/dark setting; `light` / `dark` pin it. Consumed by `MaterialApp`
  /// in `main.dart` and set from the Settings "Display" section.
  ThemeMode get themeMode => _themeMode;

  /// Preferred text size (issue #114). Applied as a `TextScaler` above the
  /// router in `main.dart`, so it scales the whole UI — including the per-widget
  /// `copyWith(fontSize: …)` overrides that a typography-only change would miss.
  AppFontScale get fontScale => _fontScale;

  /// Hydrate from the key/value store. Safe to call multiple times.
  Future<void> load() async {
    var changed = false;

    final raw = await _store.read(_kHideToolCallsKey);
    final next = raw == 'true';
    if (next != _hideToolCalls) {
      _hideToolCalls = next;
      changed = true;
    }

    final selected = await _store.read(_kSelectedPeerEpkKey);
    final cleaned = (selected != null && selected.isNotEmpty) ? selected : null;
    if (cleaned != _selectedPeerEpk) {
      _selectedPeerEpk = cleaned;
      changed = true;
    }

    final relay = await _store.read(_kRelayUrlKey);
    final relayCleaned = (relay != null && relay.isNotEmpty) ? relay : null;
    if (relayCleaned != _relayUrl) {
      _relayUrl = relayCleaned;
      changed = true;
    }

    final onboarded = await _store.read(_kOnboardingCompletedKey);
    final onboardedBool = onboarded == 'true';
    if (onboardedBool != _onboardingCompleted) {
      _onboardingCompleted = onboardedBool;
      changed = true;
    }

    final theme = await _store.read(_kThemeModeKey);
    final themeMode = _themeModeFromString(theme);
    if (themeMode != _themeMode) {
      _themeMode = themeMode;
      changed = true;
    }

    final scale = AppFontScale.fromName(await _store.read(_kFontScaleKey));
    if (scale != _fontScale) {
      _fontScale = scale;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  Future<void> setHideToolCalls(bool value) async {
    if (_hideToolCalls == value) return;
    _hideToolCalls = value;
    await _store.write(_kHideToolCallsKey, value.toString());
    notifyListeners();
  }

  Future<void> setSelectedPeerEpk(String? value) async {
    final cleaned = (value != null && value.isNotEmpty) ? value : null;
    if (cleaned == _selectedPeerEpk) return;
    _selectedPeerEpk = cleaned;
    if (cleaned == null) {
      await _store.delete(_kSelectedPeerEpkKey);
    } else {
      await _store.write(_kSelectedPeerEpkKey, cleaned);
    }
    notifyListeners();
  }

  /// Plan 17 — persist the composite `epk:roomId` selection. Passing
  /// [roomId] = null falls back to 'main' implicitly via the getter
  /// contract. Null [epk] clears the entire selection.
  Future<void> setSelectedRoom({String? epk, String? roomId}) async {
    if (epk == null || epk.isEmpty) {
      return setSelectedPeerEpk(null);
    }
    final composite = (roomId == null || roomId.isEmpty) ? epk : '$epk:$roomId';
    return setSelectedPeerEpk(composite);
  }

  /// Set the user-configured relay URL. `null` or empty clears the
  /// override so the app falls back to `kDefaultRelayUrl`. Caller should
  /// validate via `isValidRelayUrl` first when [value] is non-null.
  Future<void> setRelayUrl(String? value) async {
    final cleaned = (value != null && value.isNotEmpty) ? value : null;
    if (cleaned == _relayUrl) return;
    _relayUrl = cleaned;
    if (cleaned == null) {
      await _store.delete(_kRelayUrlKey);
    } else {
      await _store.write(_kRelayUrlKey, cleaned);
    }
    notifyListeners();
  }

  Future<void> setOnboardingCompleted(bool value) async {
    if (_onboardingCompleted == value) return;
    _onboardingCompleted = value;
    await _store.write(_kOnboardingCompletedKey, value.toString());
    notifyListeners();
  }

  /// Persist the preferred [ThemeMode]. Stored as a stable string key so the
  /// value survives enum reordering.
  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    await _store.write(_kThemeModeKey, value.name);
    notifyListeners();
  }

  /// Persist the preferred [AppFontScale]. Stored by `name` so the value
  /// survives enum reordering.
  Future<void> setFontScale(AppFontScale value) async {
    if (_fontScale == value) return;
    _fontScale = value;
    await _store.write(_kFontScaleKey, value.name);
    notifyListeners();
  }

  static ThemeMode _themeModeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
