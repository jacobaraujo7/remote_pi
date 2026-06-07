import 'package:flutter/foundation.dart';

/// Ponte global pro atalho ⌘L/Ctrl+L. O handler vive em `main.dart` (sempre na
/// cadeia de foco, então dispara mesmo sem nada focado); o `CockpitPage`
/// registra aqui a ação de focar o input do agente focado. `null` quando o
/// shell não está montado.
VoidCallback? requestFocusActiveComposer;
