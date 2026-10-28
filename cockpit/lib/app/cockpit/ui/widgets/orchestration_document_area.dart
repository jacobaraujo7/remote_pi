import 'dart:math' as math;
import 'package:path/path.dart' as paths;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../actions/tab_actions.dart';
import '../document/document_window_app.dart';
import '../session/orchestration_session.dart';
import 'orchestration_terminals_view.dart';
import '../../../../i18n/strings.g.dart';

/// The private terminal presenter stays at the same element location underneath
/// the document; changing presentation never creates another native terminal.
class OrchestrationDocumentArea extends StatelessWidget {
  const OrchestrationDocumentArea({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
  });
  final OrchestrationSession session;
  final bool active, focused;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final file = session.filePresentation;
      final visible = file != null && session.fileVisible;
      return LayoutBuilder(
        builder: (context, limits) => Column(
          children: [
            SizedBox(
              height: file == null ? 0 : math.min(36, limits.maxHeight),
              child: file == null
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        OutlineButton(
                          onPressed: () {
                            session.onFocus?.call();
                            session.showTerminals();
                            session.context.focusTerminalTab(file.terminalId);
                          },
                          child: Text(context.t.workspaceView.terminals),
                        ),
                        Expanded(
                          child: OutlineButton(
                            onPressed: () {
                              session.onFocus?.call();
                              session.showFile();
                            },
                            child: Text(
                              paths.basename(file.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton.ghost(
                          key: ValueKey('owned-file-close-${session.id}'),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () async {
                            session.onFocus?.call();
                            await requestCloseTab(context, file.viewer, () {
                              if (identical(session.filePresentation, file)) {
                                session.closeFile(discard: true);
                              }
                            });
                          },
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(
                    offstage: visible,
                    child: OrchestrationTerminalsView(
                      session: session,
                      active: active && !visible,
                      focused: focused && !visible,
                    ),
                  ),
                  if (file != null)
                    Offstage(
                      offstage: !visible,
                      child: Listener(
                        onPointerDown: (_) => session.onFocus?.call(),
                        child: DocumentScreen(
                          host: file.host,
                          path: file.path,
                          projectId: session.projectId,
                          sessionId: file.id,
                          revealLine: file.line,
                          active: active && visible,
                          focused: focused && visible,
                          onPanelCall: file.onPanelCall,
                          onSession: (value) => file.viewer = value,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
