import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// As fontes da identidade visual vêm empacotadas em `assets/google_fonts/`
/// e o app roda com `allowRuntimeFetching = false` (issue #61: boot offline
/// morria baixando de fonts.gstatic.com). O google_fonts não lança quando uma
/// face falta: ele imprime "Error: google_fonts was unable to load font …".
/// Então o teste captura os prints e exige que nenhum apareça para cada
/// variante que o app usa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every font the app uses loads from bundled assets, offline', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final errors = <String>[];
    await runZoned(
      () => GoogleFonts.pendingFonts([
        for (final w in [
          FontWeight.w100,
          FontWeight.w200,
          FontWeight.w300,
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
        ]) ...[
          GoogleFonts.jetBrainsMono(fontWeight: w),
          GoogleFonts.jetBrainsMono(fontWeight: w, fontStyle: FontStyle.italic),
        ],
        for (final w in [
          FontWeight.w300,
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
        ])
          GoogleFonts.spaceGrotesk(fontWeight: w),
        for (final w in [
          FontWeight.w100,
          FontWeight.w200,
          FontWeight.w300,
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
          FontWeight.w900,
        ])
          GoogleFonts.hankenGrotesk(fontWeight: w),
        GoogleFonts.hankenGrotesk(fontStyle: FontStyle.italic),
      ]),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (line.contains('unable to load font')) errors.add(line);
          parent.print(zone, line);
        },
      ),
    );
    expect(errors, isEmpty);
  });
}
