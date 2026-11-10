import 'package:flutter/services.dart';

/// Android hardware volume keys as a text-size control.
///
/// The keys are **consumed** by the platform side ([MainActivity.onKeyDown])
/// rather than merely observed, so pressing them steps the app's text size
/// instead of changing media volume. That decision has to be made natively and
/// synchronously — before the system handles the key — which is why the
/// enablement is pushed down with [setEnabled] instead of being queried.
///
/// Therefore the feature is opt-out: Settings → Display carries the toggle, and
/// turning it off gives the volume keys back to the system.
///
/// iOS is untouched: the channel does not exist there, so [setEnabled] is a
/// no-op and no key events ever arrive.
class VolumeKeys {
  static const MethodChannel _channel = MethodChannel(
    'work.jacobmoura.remotepi/volume_keys',
  );

  /// Called with `up` or `down` when a volume key is pressed while enabled.
  void Function(String direction)? onKey;

  /// Push the current enablement to the platform. Never throws: on iOS and in
  /// tests the channel simply isn't registered.
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // No native side (iOS/desktop/tests) — nothing to enable.
    }
  }

  /// Start listening for key events. Call once; calling again replaces the
  /// handler.
  void attach() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey' && call.arguments is String) {
        onKey?.call(call.arguments as String);
      }
      return null;
    });
  }
}
