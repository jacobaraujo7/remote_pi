import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../session/file_viewer_session.dart';
import 'board_view.dart';
import 'file_viewer.dart';

/// Both hosts use the same file session and the same source editor.
class BoardDocumentView extends StatelessWidget {
  const BoardDocumentView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.allowLocalFileSystem,
    required this.onSave,
    required this.onReload,
    this.showModeSwitch = false,
  });
  final FileViewerSession session;
  final bool active, focused, allowLocalFileSystem, showModeSwitch;
  final Future<bool> Function(String) onSave;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final editor = session.rawSource
          ? FileViewer(
              session: session,
              active: active,
              focused: focused,
              allowLocalFileSystem: allowLocalFileSystem,
              onSave: onSave,
            )
          : BoardView(session: session, onSave: onSave, onReload: onReload);
      if (!showModeSwitch) return editor;
      final tr = context.t.cockpit.paneView;
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: GhostButton(
              size: ButtonSize.small,
              onPressed: session.switchBoardMode,
              child: Text(
                session.rawSource ? tr.openAsBoard : tr.openAsMarkdown,
              ),
            ),
          ),
          Expanded(child: editor),
        ],
      );
    },
  );
}
