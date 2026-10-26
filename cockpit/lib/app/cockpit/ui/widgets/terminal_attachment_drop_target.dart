import 'package:cockpit/app/cockpit/domain/services/terminal_attachment_service.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Envolve o terminal e aceita **drops nativos do SO** (Finder/Explorer): ao
/// soltar arquivos ou pastas, injeta os **caminhos absolutos** no PTY como se
/// tivessem sido digitados (caminhos com espaço/aspas são shell-quoted, e vários
/// itens vêm separados por espaço). Mostra uma borda accent enquanto o item
/// paira sobre a área — sinal de que vai aceitar o drop.
class TerminalAttachmentDropTarget extends StatefulWidget {
  const TerminalAttachmentDropTarget({
    super.key,
    required this.session,
    required this.child,
    required this.active,
    this.onDropped,
  });

  /// Chamado depois de injetar os caminhos: o dono do foco devolve o teclado
  /// ao terminal (o drop nativo não gera pointer-down nenhum no Flutter).
  final VoidCallback? onDropped;

  final bool active;
  final TerminalSession session;
  final Widget child;

  @override
  State<TerminalAttachmentDropTarget> createState() =>
      _TerminalAttachmentDropTargetState();
}

class _TerminalAttachmentDropTargetState
    extends State<TerminalAttachmentDropTarget> {
  bool _dragOver = false;

  void _onDrop(List<DropItem> files) {
    final paths = files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    widget.session.importDroppedPaths(paths);
    widget.onDropped?.call();
  }

  /// Este DropTarget é o que está de fato sob o ponto do drop? Faz um hit-test
  /// da posição global na árvore de render: `IndexedStack` só testa o filho
  /// visível, então abas/workspaces empilhados atrás (mesmo rect) não entram no
  /// caminho — desempata o broadcast do `desktop_drop` pro alvo certo.
  bool _isHitTarget(Offset globalPosition) {
    if (!widget.active) return false;
    final ro = context.findRenderObject();
    if (ro == null) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    return result.path.any((entry) => identical(entry.target, ro));
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (detail) {
        if (!_isHitTarget(detail.globalPosition)) return;
        if (!_dragOver) setState(() => _dragOver = true);
      },
      onDragExited: (_) {
        if (_dragOver) setState(() => _dragOver = false);
      },
      onDragDone: (detail) {
        if (_dragOver) setState(() => _dragOver = false);
        // `desktop_drop` emite `onDragDone` em TODO DropTarget cujo box contém
        // o ponto do drop. Como as abas de um pane (e os workspaces) ficam num
        // `IndexedStack` — todas montadas no MESMO rect, só a ativa pintada —, o
        // caminho caía em todos os terminais empilhados. Gate por `_dragOver`
        // (hover) não serve: o enter/exit também dispara em todas as abas
        // empilhadas e é resetado no drop. Um `IndexedStack` só faz hit-test do
        // filho VISÍVEL, então testamos se ESTE alvo está no caminho de hit do
        // ponto — só a aba/worksapce realmente sob o cursor passa.
        if (!_isHitTarget(detail.globalPosition)) return;
        _onDrop(detail.files);
      },
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => Stack(
          children: [
            widget.child,
            if (widget.session.attachmentFeedback case final feedback?)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: _attachmentStatus(context, feedback),
              ),
            if (_dragOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: context.colors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentStatus(
    BuildContext context,
    TerminalAttachmentFeedback feedback,
  ) {
    final tr = context.t.terminalAttachment;
    final message = switch (feedback.notice) {
      TerminalAttachmentNotice.importing => tr.importing(
        completed: feedback.completed,
        total: feedback.total,
      ),
      TerminalAttachmentNotice.nativeImage => tr.nativeImage,
      TerminalAttachmentNotice.referenced =>
        feedback.detail.isEmpty
            ? tr.referenced
            : '${tr.referenced}\n${feedback.detail}',
      TerminalAttachmentNotice.remoteUnavailable => tr.remoteUnavailable,
      TerminalAttachmentNotice.failed => tr.failed(detail: feedback.detail),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.colors.panel2,
          border: Border.all(color: context.colors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (feedback.notice == TerminalAttachmentNotice.importing) ...[
              const CircularProgressIndicator(size: 12),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (feedback.notice != TerminalAttachmentNotice.importing)
              IconButton.ghost(
                icon: const Icon(Icons.close, size: 14),
                onPressed: widget.session.clearAttachmentFeedback,
              ),
          ],
        ),
      ),
    );
  }
}
