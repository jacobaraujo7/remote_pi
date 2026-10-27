import '../../domain/entities/orchestration_document.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../session/pane_item.dart';
import '../viewmodels/orchestration_multiplexer.dart';

/// Validated local runtime metadata. Portable documents never use this decoder.
/// Validation completes before any native process is constructed.
class OrchestrationRestoreState {
  OrchestrationRestoreState._({
    required this.document,
    required this.pendingRemovals,
    required this.bindings,
    required this.sessions,
    required this.multiplexer,
    required this.presentation,
    required this.dirty,
  });

  final OrchestrationDocument? document;
  final OrchestrationDocument? pendingRemovals;
  final Map<String, String> bindings;
  final Map<String, Map<String, dynamic>> sessions;
  final Map<String, dynamic> multiplexer;
  final OrchestrationPresentation presentation;
  final bool dirty;

  factory OrchestrationRestoreState.parse(
    Map<String, dynamic> raw, {
    required String instanceId,
    required String projectId,
  }) {
    if (raw['ownershipVersion'] != 2) {
      throw const FormatException('Unsupported local orchestration version');
    }
    OrchestrationDocument? documentOf(String key) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! String) throw FormatException('Invalid $key snapshot');
      return OrchestrationDocument.parse(value);
    }

    final document = documentOf('document');
    final pending = documentOf('pendingRemovals');
    final rawSessions = raw['sessions'];
    final rawBindings = raw['bindings'];
    final rawMux = raw['multiplexer'];
    if (rawSessions is! Map || rawBindings is! Map || rawMux is! Map) {
      throw const FormatException('Missing owned session metadata');
    }
    final sessions = <String, Map<String, dynamic>>{};
    for (final entry in rawSessions.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid owned session descriptor');
      }
      final desc = Map<String, dynamic>.from(entry.value as Map);
      if (desc['type'] != 'terminal') {
        throw const FormatException(
          'Only terminals belong to an orchestration',
        );
      }
      for (final key in [
        'cwd',
        'sub',
        'title',
        'label',
        'claude_sid',
        'transcriptPath',
        'harness',
        'engine',
      ]) {
        if (desc[key] != null && desc[key] is! String) {
          throw FormatException('Invalid terminal $key');
        }
      }
      sessions[entry.key as String] = desc;
    }
    final definitions = {
      for (final b in document?.boxes ?? const <OrchestrationBox>[]) b.box.id,
    };
    for (final b in pending?.boxes ?? const <OrchestrationBox>[]) {
      if (!definitions.add(b.box.id)) {
        throw const FormatException('Duplicate pending definition');
      }
    }
    final bindings = <String, String>{};
    final bound = <String>{};
    for (final entry in rawBindings.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          !definitions.contains(entry.key) ||
          !sessions.containsKey(entry.value) ||
          !bound.add(entry.value as String)) {
        throw const FormatException('Foreign or duplicate local binding');
      }
      bindings[entry.key as String] = entry.value as String;
    }
    if (bound.length != sessions.length ||
        (raw['dirty'] == true && document == null)) {
      throw const FormatException('Unrepresented owned session');
    }
    final multiplexer = Map<String, dynamic>.from(rawMux);
    final probe = OrchestrationMultiplexer<PaneItem>(
      instanceId: instanceId,
      projectId: projectId,
    );
    try {
      for (final id in sessions.keys) {
        probe.attach(_SavedTerminal(id, projectId, instanceId));
      }
      probe.restoreLayout(multiplexer);
    } finally {
      probe.dispose();
    }
    return OrchestrationRestoreState._(
      document: document,
      pendingRemovals: pending,
      bindings: bindings,
      sessions: sessions,
      multiplexer: multiplexer,
      presentation: OrchestrationPresentation.fromJson(raw['presentation']),
      dirty: raw['dirty'] == true,
    );
  }
}

class _SavedTerminal extends PaneItem {
  _SavedTerminal(this.id, this.projectId, String instanceId)
    : owner = TerminalOwner.orchestration(instanceId);
  @override
  final String id;
  @override
  final String projectId;
  @override
  final TerminalOwner owner;
  @override
  String get title => id;
  @override
  String get workingDirectory => '.';
}
