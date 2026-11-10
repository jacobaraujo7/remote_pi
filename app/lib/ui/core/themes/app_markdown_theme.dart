import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'package:app/ui/core/themes/app_typography.dart';

/// Heading styles for markdown rendered in the chat transcript (issue #184).
///
/// `gpt_markdown` draws `#`…`######` from its own [GptMarkdownThemeData]. When
/// the host provides none — as this app did — it falls back to Material's
/// `TextTheme`: `h1: headlineLarge (32)`, `h2: headlineMedium (28)`,
/// `h3: headlineSmall (24)`, `h4: titleLarge (22)`… Those sizes are absolute,
/// not derived from the `style` handed to `GptMarkdown`, so against this app's
/// 12.5pt mono body a `##` was already 2.24× the prose around it.
///
/// The text-size setting from #114 applies a single linear `TextScaler` to the
/// whole tree (correctly — it has to reach the per-widget `copyWith(fontSize:)`
/// call sites too), so that pre-existing ratio scaled *absolutely*: at XL a
/// `##` rendered at 36.4pt next to 16.25pt body text.
///
/// Deriving every heading from [AppTypography.mono] instead keeps them in the
/// app's font, bounded to 1.0×–1.36× of the body, and still scalable —
/// `TextScaler` multiplies `fontSize`, so the headings follow the user's preset
/// without an absolute gap opening up.
GptMarkdownThemeData buildMarkdownTheme({
  required AppTypography typo,
  required Brightness brightness,
}) {
  TextStyle heading(double size, FontWeight weight) =>
      typo.mono.copyWith(fontSize: size, fontWeight: weight);

  return GptMarkdownThemeData(
    brightness: brightness,
    h1: heading(17.0, FontWeight.w700),
    h2: heading(15.5, FontWeight.w700),
    h3: heading(14.5, FontWeight.w600),
    h4: heading(13.5, FontWeight.w600),
    h5: heading(13.0, FontWeight.w600),
    h6: heading(12.5, FontWeight.w600),
  );
}
