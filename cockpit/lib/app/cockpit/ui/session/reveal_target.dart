import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/neovim_session.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/task_output_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';

/// Caminho que "Abrir no Finder/Explorer" do menu da aba revela para [item],
/// ou `null` quando a aba não tem um local em disco (scratch, browser, diff…).
String? revealTargetOf(PaneItem? item) {
  final target = switch (item) {
    final FileViewerSession v => v.scratch ? null : v.path,
    final NotebookSession n => n.path,
    final OrchestrationSession o => o.path,
    final NeovimSession n =>
      n.lastPath.isNotEmpty
          ? n.lastPath
          : (n.currentDirectory ?? n.workingDirectory),
    final TerminalSession t => t.currentDirectory ?? t.workingDirectory,
    final TaskOutputSession task => task.workingDirectory,
    _ => null,
  };
  return (target == null || target.isEmpty) ? null : target;
}
