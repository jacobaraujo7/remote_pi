/// User-selectable text size (issue #114).
///
/// Why an in-app control at all: every text size in the app is hardcoded
/// (`AppTypography` plus per-widget `copyWith(fontSize: …)`), and Flutter does
/// not participate in iOS's per-app "Text Size" entry — the engine derives its
/// scale factor exclusively from `preferredContentSizeCategory`, which only
/// surfaces for apps supporting UIKit Dynamic Type. So the only OS-level
/// workaround is the *global* Larger Text setting, which resizes every other
/// app on the device. This gives the app its own knob.
///
/// The factor is applied as a `TextScaler` on the `MediaQuery` above the router
/// rather than by multiplying `AppTypography`'s base sizes. That covers the
/// per-widget `copyWith(fontSize: …)` call sites too — multiplying the base
/// styles would leave every one-off size unscaled, which is most of the chat.
enum AppFontScale {
  small('Small', 0.9),
  standard('Default', 1.0),
  large('Large', 1.15),
  extraLarge('XL', 1.3);

  const AppFontScale(this.label, this.factor);

  /// Short label for the Settings segmented control.
  final String label;

  /// Multiplier applied to every text size in the app.
  final double factor;

  /// Parse a persisted value. Unknown/legacy/missing → [standard], so a bad
  /// stored string can never leave the app with unreadable text.
  static AppFontScale fromName(String? raw) {
    for (final v in AppFontScale.values) {
      if (v.name == raw) return v;
    }
    return AppFontScale.standard;
  }
}
