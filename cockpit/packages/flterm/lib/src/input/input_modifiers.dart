import 'package:flutter/services.dart';
import 'package:libghostty/libghostty.dart' show Mods;
import 'package:meta/meta.dart';

@internal
Mods consumedModifiersFor(
  String? character, {
  required int unshiftedCodepoint,
  required Mods mods,
}) {
  if (character == null || unshiftedCodepoint == 0) return const .none();

  final codepoints = character.runes.iterator;
  if (!codepoints.moveNext()) return const .none();
  final codepoint = codepoints.current;
  if (codepoints.moveNext() || codepoint == unshiftedCodepoint) {
    return const .none();
  }

  var consumedMods = const Mods.none();
  if (mods.hasShift) consumedMods |= const .shift();

  final keyboard = HardwareKeyboard.instance;
  final rightAltPressed = keyboard.isLogicalKeyPressed(.altRight);
  if (mods.hasAlt && rightAltPressed) {
    consumedMods |= const .alt();
    if (keyboard.isControlPressed) consumedMods |= const .ctrl();
  }
  return consumedMods;
}

@internal
Mods readPointerModifiers(Mods virtualMods) {
  var mods = virtualMods;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed) mods |= const .shift();
  if (keyboard.isControlPressed) mods |= const .ctrl();
  if (keyboard.isAltPressed) mods |= const .alt();
  if (keyboard.isMetaPressed) mods |= const .superKey();
  return mods;
}
