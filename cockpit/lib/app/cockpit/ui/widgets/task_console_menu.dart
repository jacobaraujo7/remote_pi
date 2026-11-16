import 'package:cockpit/app/cockpit/ui/session/task_output_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/terminal/terminal_context_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

enum _TaskConsoleAction { copy, copyAll, clear }

Future<void> showTaskConsoleMenu(
  BuildContext context,
  TaskOutputSession session,
  TerminalContextMenuRequest request,
) async {
  final selected = request.selectedText;
  final line = request.line?.text ?? '';
  final all = session.terminal.plainText();
  final taskTerminals = context.read<CockpitViewModel>().taskTerminals;
  final picked = await showAppMenu<_TaskConsoleAction>(
    context,
    globalPosition: request.globalPosition,
    minWidth: 180,
    items: [
      AppMenuItem(
        value: _TaskConsoleAction.copy,
        label: context.t.cockpit.tasksPanel.copy,
        icon: Icons.copy_outlined,
        enabled: selected.isNotEmpty || line.isNotEmpty,
      ),
      AppMenuItem(
        value: _TaskConsoleAction.copyAll,
        label: context.t.cockpit.tasksPanel.copyAll,
        icon: Icons.content_copy,
        enabled: all.isNotEmpty,
      ),
      const AppMenuItem.divider(),
      AppMenuItem(
        value: _TaskConsoleAction.clear,
        label: context.t.cockpit.tasksPanel.clearConsole,
        icon: Icons.delete_sweep_outlined,
        enabled: all.isNotEmpty,
      ),
    ],
  );
  switch (picked) {
    case _TaskConsoleAction.copy:
      await Clipboard.setData(
        ClipboardData(text: selected.isNotEmpty ? selected : line),
      );
      break;
    case _TaskConsoleAction.copyAll:
      await Clipboard.setData(ClipboardData(text: all));
      break;
    case _TaskConsoleAction.clear:
      await taskTerminals.clear(session.taskId);
      break;
    case null:
      break;
  }
}
