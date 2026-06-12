import 'package:cockpit/domain/entities/session_info.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Lista as sessões salvas do pi para a pasta do agente. Devolve a [SessionInfo]
/// escolhida (pra `switch_session`), ou `null` se cancelar.
Future<SessionInfo?> showHistoryDialog(
  BuildContext context, {
  required List<SessionInfo> sessions,
}) {
  return showDialog<SessionInfo>(
    context: context,
    builder: (context) => _HistoryDialog(sessions: sessions),
  );
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.sessions});
  final List<SessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              child: Text(
                'Session history',
                style: context.typo.title.copyWith(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                'Opening one replaces this agent\'s current transcript',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Text(
                  'No saved sessions in this folder.',
                  style: context.typo.body.copyWith(color: colors.text3),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) =>
                      _SessionRow(session: sessions[index]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => Navigator.of(context).pop(session),
        child: Padding(
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
                      session.title ?? 'Untitled session',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.body.copyWith(
                        fontSize: 13.5,
                        color: session.title == null
                            ? colors.text3
                            : colors.text,
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
                _relative(session.modifiedAt),
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
