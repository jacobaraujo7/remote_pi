import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_normalizer.dart';

abstract class TerminalHarnessClassifier {
  /// Classifies a process invocation as a supported interactive harness,
  /// or returns null if it is non-interactive, administrative, or unknown.
  static HarnessKind? classify({
    required String executable,
    required List<String> argv,
  }) {
    final normalized = TerminalHarnessNormalizer.normalize(
      executable: executable,
      argv: argv,
    );
    if (normalized == null) return null;

    final spec = _findMatchingSpec(normalized.entryPointName);
    if (spec == null) return null;

    final isInteractive = _isInteractiveInvocation(spec.kind, normalized.harnessArgs);
    return isInteractive ? spec.kind : null;
  }

  static HarnessSpec? _findMatchingSpec(String entryPoint) {
    for (final spec in HarnessCatalog.specs.values) {
      if (spec.allEntryPoints.contains(entryPoint)) {
        return spec;
      }
    }
    return null;
  }

  static bool _isInteractiveInvocation(
    HarnessKind kind,
    List<String> args,
  ) {
    // Universal admin/help/version flags
    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == '-v' || arg == '--version') {
        return false;
      }
    }

    switch (kind) {
      case HarnessKind.antigravity:
        return _checkAntigravity(args);
      case HarnessKind.claudeCode:
        return _checkClaudeCode(args);
      case HarnessKind.codex:
        return _checkCodex(args);
      case HarnessKind.cursor:
        return _checkCursor(args);
      case HarnessKind.gitHubCopilot:
        return _checkGitHubCopilot(args);
      case HarnessKind.openCode:
        return _checkOpenCode(args);
      case HarnessKind.pi:
        return _checkPi(args);
    }
  }

  static bool _checkAntigravity(List<String> args) {
    const adminSubcommands = {'help', 'version', 'config', 'auth', 'models', 'update'};
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-p' || arg == '--print') return false;
      if (i == 0 && adminSubcommands.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkClaudeCode(List<String> args) {
    const adminSubcommands = {
      'mcp',
      'plugin',
      'config',
      'auth',
      'doctor',
      'update',
      'version',
      'help',
    };
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-p' || arg == '--print') return false;
      if (i == 0 && adminSubcommands.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkCodex(List<String> args) {
    const adminSubcommandsOrModes = {'exec', 'auth', 'config', 'version', 'help', 'models'};
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (i == 0 && adminSubcommandsOrModes.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkCursor(List<String> args) {
    const adminSubcommands = {'auth', 'login', 'logout', 'list', 'version', 'help'};
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-p' || arg == '--print') return false;
      if (i == 0 && adminSubcommands.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkGitHubCopilot(List<String> args) {
    const adminSubcommands = {'auth', 'config', 'alias', 'version', 'help'};
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-p' || arg == '--prompt' || arg == '-i' || arg == '--input') return false;
      if (i == 0 && adminSubcommands.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkOpenCode(List<String> args) {
    const adminSubcommandsOrModes = {'run', 'auth', 'config', 'models', 'version', 'help'};
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (i == 0 && adminSubcommandsOrModes.contains(arg.toLowerCase())) return false;
    }
    return true;
  }

  static bool _checkPi(List<String> args) {
    const adminSubcommands = {
      'export',
      'auth',
      'config',
      'models',
      'version',
      'help',
      'doctor',
    };
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-p' || arg == '--print') return false;
      if (arg.startsWith('--mode=')) {
        final modeVal = arg.substring('--mode='.length).toLowerCase();
        if (modeVal == 'text' || modeVal == 'json' || modeVal == 'rpc') return false;
      }
      if (arg == '--mode' && i + 1 < args.length) {
        final modeVal = args[i + 1].toLowerCase();
        if (modeVal == 'text' || modeVal == 'json' || modeVal == 'rpc') return false;
      }
      if (i == 0 && adminSubcommands.contains(arg.toLowerCase())) return false;
    }
    return true;
  }
}
