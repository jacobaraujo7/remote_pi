import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lista as sessões salvas do pi para a pasta do agente. Devolve a [SessionInfo]
/// escolhida (pra `switch_session`), ou `null` se cancelar.
Future<SessionInfo?> showHistoryDialog(
  BuildContext context, {
  required List<SessionInfo> sessions,
}) {
  return showDialog<SessionInfo>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _HistoryDialog(sessions: sessions),
  );
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.sessions});
  final List<SessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.historyDialog;
    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.title,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr.subtitle,
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 400),
        child: sessions.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  tr.empty,
                  style: context.typo.body.copyWith(color: colors.text3),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) =>
                    _SessionRow(session: sessions[index]),
              ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: () => Navigator.of(context).pop(session),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: colors.text3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title ??
                      context.t.cockpit.historyDialog.untitledSession,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: session.title == null ? colors.text3 : colors.text,
                    fontStyle: session.title == null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                Text(
                  _formatDate(session.modifiedAt),
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.label.copyWith(color: colors.text4),
                ),
              ],
            ),
          ),
          Text(
            _relative(context, session.modifiedAt),
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

  String _relative(BuildContext context, DateTime d) {
    final diff = DateTime.now().difference(d);
    final tr = context.t.cockpit.historyDialog;
    if (diff.inMinutes < 1) return tr.justNow;
    if (diff.inMinutes < 60) return tr.minutesAgo(n: diff.inMinutes);
    if (diff.inHours < 24) return tr.hoursAgo(n: diff.inHours);
    return tr.daysAgo(n: diff.inDays);
  }
}
