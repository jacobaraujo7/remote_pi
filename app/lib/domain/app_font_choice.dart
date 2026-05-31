enum AppFontChoice {
  systemDefault('system_default'),
  robotoMono('roboto_mono'),
  jetBrainsMono('jetbrains_mono'),
  sans('sans'),
  serif('serif'),
  mono('mono');

  const AppFontChoice(this.storageKey);

  final String storageKey;

  static AppFontChoice fromStorage(String? raw) {
    for (final value in AppFontChoice.values) {
      if (value.storageKey == raw) return value;
    }
    return AppFontChoice.mono;
  }
}
