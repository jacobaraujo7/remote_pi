import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import '../session/orchestration_session.dart';
import 'terminal_session_view.dart';

/// Shows the terminal of the selected definition. There are no internal tabs:
/// the list and the graph are the navigation. Every owned terminal stays
/// mounted (offstage) so switching never recreates a native session.
class OrchestrationTerminalsView extends StatelessWidget {
  const OrchestrationTerminalsView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
  });
  final OrchestrationSession session;
  final bool active, focused;

  void _focus(String tabId) {
    session.onFocus?.call();
    session.context.focusTerminalTab(tabId);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session.terminals, session.context]),
    builder: (context, _) {
      final mux = session.terminals;
      final box = session.context.selectedWorkspaceBox;
      final shownId = box?.tabId != null && mux.contains(box!.tabId!)
          ? box.tabId
          : null;
      final ids = mux.sessions.keys.toList();
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final tabId in ids)
              Offstage(
                offstage: tabId != shownId,
                child: TerminalSessionView(
                  key: ValueKey((session.id, tabId)),
                  session: mux.session(tabId)!,
                  active: active && tabId == shownId,
                  focused:
                      tabId == shownId && focused && mux.keyboardTabId == tabId,
                  focusRevision: mux.focusRevision,
                  onFocus: () => _focus(tabId),
                  onOpenFile: (path, {line}) =>
                      unawaited(session.openFile(tabId, path, line: line)),
                  ownerShortcuts: {
                    const SingleActivator(
                      LogicalKeyboardKey.tab,
                      control: true,
                    ): () =>
                        session.context.cycleTerminalTab(1),
                    const SingleActivator(
                      LogicalKeyboardKey.tab,
                      control: true,
                      shift: true,
                    ): () =>
                        session.context.cycleTerminalTab(-1),
                  },
                ),
              ),
            if (shownId == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      box == null
                          ? context.t.orchestration.noBoxSelected
                          : context.t.workspaceView.noSession,
                      style: context.typo.body.copyWith(
                        color: context.colors.text3,
                      ),
                    ),
                    if (box != null) ...[
                      const SizedBox(height: 12),
                      OutlineButton(
                        onPressed:
                            session.closing ||
                                session.context.selectedRemoteDisconnected
                            ? null
                            : () => session.context.openBoxShell(box.id),
                        child: Text(context.t.workspaceView.startShell),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
