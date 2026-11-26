import 'dart:io';

import 'package:flutter/services.dart';

/// Activates another Cockpit instance by pid (macOS; see
/// `registerAppActivation` in `MainFlutterWindow.swift`). On the other
/// platforms the `focus-window` command the window itself receives is enough.
class AppActivationChannel {
  AppActivationChannel._();

  static const _channel = MethodChannel('cockpit/app_activation');

  /// `true` when the OS agreed to activate process [pid].
  static Future<bool> activate(int pid) async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('activate', {'pid': pid}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
