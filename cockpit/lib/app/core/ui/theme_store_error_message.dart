import 'package:cockpit/app/core/data/theme_store.dart';
import 'package:cockpit/app/core/ui/themes/theme_codec.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Traduz um [ThemeStoreError] para a frase mostrada ao usuário.
///
/// Mesma regra do `fileOperationErrorMessage`: `data/` devolve o tipo e o texto
/// nasce aqui. O `switch` é exaustivo sobre os enums, então um kind novo sem
/// tradução quebra a compilação.
String themeStoreErrorMessage(BuildContext context, ThemeStoreError error) {
  final tr = context.t.theme.error;
  final detail = error.detail?.trim() ?? '';

  return switch (error.kind) {
    ThemeStoreErrorKind.io =>
      detail.isEmpty ? tr.io : tr.ioDetail(detail: detail),
    ThemeStoreErrorKind.malformedJson => tr.malformedJson(detail: detail),
    ThemeStoreErrorKind.reservedId => tr.reservedId,
    ThemeStoreErrorKind.invalidTheme => _parseMessage(context, error.parse),
  };
}

String _parseMessage(BuildContext context, ThemeParseError? error) {
  final tr = context.t.theme.error;
  if (error == null) return tr.invalidTheme;
  return switch (error.kind) {
    ThemeParseErrorKind.notAnObject => tr.notAnObject(field: error.path),
    ThemeParseErrorKind.missingField => tr.missingField(field: error.path),
    // O valor cru entra interpolado: `#ggg` é texto de terceiros, não se traduz.
    ThemeParseErrorKind.badColor => tr.badColor(
      field: error.path,
      value: error.value ?? '',
    ),
    ThemeParseErrorKind.unknownBase => tr.unknownBase(value: error.value ?? ''),
    ThemeParseErrorKind.noVariants => tr.noVariants,
  };
}
