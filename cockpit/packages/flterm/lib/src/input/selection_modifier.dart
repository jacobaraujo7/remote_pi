import 'package:libghostty/libghostty.dart' show Mods;

import '../foundation/terminal_gesture_settings.dart';

bool isSelectionModifierPressed(GestureModifier? modifier, Mods mods) =>
    switch (modifier) {
      .alt => mods.hasAlt,
      .meta => mods.hasSuper,
      .shift => mods.hasShift,
      .control => mods.hasCtrl,
      null => false,
    };
