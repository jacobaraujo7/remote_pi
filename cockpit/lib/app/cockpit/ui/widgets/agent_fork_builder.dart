import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

String agentForkProblemMessage(BuildContext context, AgentForkProblem problem) {
  final tr = context.t.cockpit.agentFork;
  return switch (problem) {
    AgentForkProblem.identifying => tr.identifying,
    AgentForkProblem.privateServerRequired => tr.privateServerRequired,
    AgentForkProblem.notSaved => tr.notSaved,
    AgentForkProblem.checking => tr.checking,
    AgentForkProblem.unavailable => tr.unavailable,
    AgentForkProblem.incompatible => tr.incompatible,
    AgentForkProblem.unsupportedHost => tr.unsupportedHost,
    AgentForkProblem.staleSession => tr.staleSession,
    AgentForkProblem.busy => tr.busy,
    AgentForkProblem.launchFailed => tr.launchFailed,
  };
}

class AgentForkAction {
  const AgentForkAction({required this.visible, this.problem, this.onInvoke});
  final bool visible;
  final AgentForkProblem? problem;
  final VoidCallback? onInvoke;
  bool get busy => problem == AgentForkProblem.busy;
}

/// Observe only the active terminal. Capability checks run once per process /
/// conversation, not on each turn status update or terminal output frame.
class AgentForkBuilder extends StatefulWidget {
  const AgentForkBuilder({
    super.key,
    required this.vm,
    required this.source,
    required this.builder,
  });
  final CockpitViewModel vm;
  final TerminalSession? source;
  final Widget Function(BuildContext, AgentForkAction) builder;

  @override
  State<AgentForkBuilder> createState() => _AgentForkBuilderState();
}

class _AgentForkBuilderState extends State<AgentForkBuilder> {
  Object? _key;
  int _generation = 0;
  AgentForkProblem? _problem;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.source?.addListener(_changed);
    _refresh();
  }

  @override
  void didUpdateWidget(AgentForkBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.vm != widget.vm) {
      oldWidget.source?.removeListener(_changed);
      widget.source?.addListener(_changed);
      _key = null;
      _refresh();
    }
  }

  void _changed() {
    if (!mounted) return;
    final previous = _key;
    _refresh();
    if (previous != _key) setState(() {});
  }

  void _refresh() {
    final source = widget.source;
    final next = (
      source,
      source?.activeHarness,
      source?.agentProcessId,
      source?.conversationIdentity,
      source?.hasExited,
    );
    if (_key == next) return;
    _key = next;
    final generation = ++_generation;
    _problem = source == null
        ? AgentForkProblem.staleSession
        : widget.vm.agentForkProblem(source);
    if (_problem != null || source == null) return;
    _problem = AgentForkProblem.checking;
    unawaited(_check(source, generation));
  }

  Future<void> _check(TerminalSession source, int generation) async {
    final result = await widget.vm.prepareAgentFork(source);
    if (!mounted || generation != _generation) return;
    setState(() {
      _problem = switch (result) {
        Success() => null,
        Failure(:final error) => error.problem,
      };
    });
  }

  Future<void> _invoke() async {
    final source = widget.source;
    if (_busy || source == null || _problem != null) return;
    setState(() => _busy = true);
    final result = await widget.vm.forkAgentInNewTab(source.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Failure(:final error)) {
      final tr = context.t.cockpit.agentFork;
      await showConfirmDialog(
        context,
        title: tr.errorTitle,
        message: [
          agentForkProblemMessage(context, error.problem),
          if (error.detail != null) error.detail!,
        ].join('\n'),
        confirmLabel: context.t.common.close,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return widget.builder(
      context,
      AgentForkAction(
        visible:
            source != null && !source.hasExited && source.activeHarness != null,
        problem: _busy ? AgentForkProblem.busy : _problem,
        onInvoke: !_busy && _problem == null ? _invoke : null,
      ),
    );
  }

  @override
  void dispose() {
    widget.source?.removeListener(_changed);
    super.dispose();
  }
}
