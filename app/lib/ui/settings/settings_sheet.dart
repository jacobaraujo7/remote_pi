import 'package:app/config/dependencies.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Plan/tablet — open Settings adaptively:
///   • tablet (wide) → modal bottom sheet over the master-detail layout,
///     so the user keeps the chat in context instead of losing the whole
///     screen to a pushed route.
///   • phone        → the existing full-screen `/settings` push.
void openSettings(BuildContext context) {
  if (isWideLayout(context)) {
    showSettingsSheet(context);
  } else {
    context.push('/settings');
  }
}

/// Presents [SettingsPage] (embedded variant) in a tall modal bottom sheet.
/// The page reaches the same `SettingsViewModel` as the route via a fresh
/// [ViewmodelProvider] (injector-backed), so behaviour is identical to the
/// pushed screen.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBg,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    // Clip the embedded Scaffold/AppBar to the rounded top corners.
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: ViewmodelProvider<SettingsViewModel>(
          child: const SettingsPage(embedded: true),
        ),
      );
    },
  );
}
