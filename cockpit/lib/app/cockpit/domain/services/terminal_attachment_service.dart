import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import '../contracts/terminal_attachments.dart';

enum TerminalAttachmentNotice {
  importing,
  referenced,
  nativeImage,
  failed,
  remoteUnavailable,
}

class TerminalAttachmentFeedback {
  const TerminalAttachmentFeedback(
    this.notice, {
    this.completed = 0,
    this.total = 0,
    this.detail = '',
  });
  final TerminalAttachmentNotice notice;
  final int completed;
  final int total;
  final String detail;
}

class TerminalAttachmentTarget {
  const TerminalAttachmentTarget({
    required this.projectRoot,
    required this.profile,
    this.remote = false,
    this.isWindows = false,
    this.harness,
  });
  final String projectRoot;
  final TerminalProfile profile;
  final bool remote;
  final bool isWindows;
  final HarnessKind? harness;
}

/// One pipeline for both terminal engines, native drops and clipboard input.
/// All effects are bound to the original session through the supplied callbacks.
class TerminalAttachmentService {
  const TerminalAttachmentService(this.clipboard, this.store, this.converter);
  final TerminalClipboardReader clipboard;
  final TerminalAttachmentStore store;
  final TerminalPathConverter converter;

  Future<void> deliver({
    required TerminalClipboardContent content,
    required TerminalAttachmentTarget target,
    required bool Function() isAlive,
    required void Function(String) paste,
    required void Function(List<int>) sendKeys,
    required void Function(TerminalAttachmentFeedback) feedback,
    bool Function()? nativeTargetIsCurrent,
  }) async {
    if (!isAlive()) return;
    if (content.files.isEmpty && !content.hasImage) {
      if (content.text?.isNotEmpty ?? false) paste(content.text!);
      return;
    }
    if (target.remote) {
      feedback(
        const TerminalAttachmentFeedback(
          TerminalAttachmentNotice.remoteUnavailable,
        ),
      );
      return;
    }
    final imported = await store.import(
      projectRoot: target.projectRoot,
      paths: content.files,
      image: content.files.isEmpty ? content.image : null,
      isAlive: isAlive,
      onProgress: (done, total) {
        if (isAlive()) {
          feedback(
            TerminalAttachmentFeedback(
              TerminalAttachmentNotice.importing,
              completed: done,
              total: total,
            ),
          );
        }
      },
    );
    if (!isAlive()) return;
    final errors = [...imported.errors];
    String? nativeWarning;
    // Only a real clipboard bitmap can use clipboard-native input. Never rewrite
    // the system clipboard to turn a dropped file into an image paste.
    final nativeKeys = switch (target.harness) {
      HarnessKind.claudeCode when target.isWindows => const [0x1b, 0x76],
      HarnessKind.claudeCode ||
      HarnessKind.codex ||
      HarnessKind.pi => const [0x16],
      HarnessKind.gitHubCopilot => const [0x1b, 0x76],
      _ => null,
    };
    if (imported.paths.length == 1 &&
        errors.isEmpty &&
        content.files.isEmpty &&
        content.hasImage &&
        target.profile.wslDistro == null &&
        nativeKeys != null) {
      var unchanged = false;
      try {
        unchanged = await clipboard.stillContainsImage(content);
      } catch (error) {
        // Clipboard access is optional after a successful local import.
        nativeWarning = 'Native image paste unavailable: $error';
      }
      if (!isAlive()) return;
      if (unchanged && (nativeTargetIsCurrent?.call() ?? true)) {
        sendKeys(nativeKeys);
        feedback(
          const TerminalAttachmentFeedback(
            TerminalAttachmentNotice.nativeImage,
          ),
        );
        return;
      }
    }
    final formatted = <String>[];
    for (final original in imported.paths) {
      try {
        final distro = target.profile.wslDistro;
        final path = distro == null
            ? original
            : await converter.forWsl(original, distro);
        formatted.add(quoteTerminalPath(path, target.profile));
      } catch (error) {
        errors.add('$original: $error');
      }
      if (!isAlive()) return;
    }
    if (formatted.isNotEmpty) paste('${formatted.join(' ')} ');
    feedback(
      TerminalAttachmentFeedback(
        errors.isNotEmpty
            ? TerminalAttachmentNotice.failed
            : TerminalAttachmentNotice.referenced,
        detail: [...errors, ?nativeWarning].join('\n'),
      ),
    );
  }
}

/// Reject line/control injection even when bracketed paste is not enabled.
String quoteTerminalPath(String path, TerminalProfile profile) {
  if (path.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
    throw const FormatException('Path contains terminal control characters');
  }
  if (profile.id == TerminalProfile.cmdId ||
      RegExp(
        r'(^|[/\\])cmd(\.exe)?$',
        caseSensitive: false,
      ).hasMatch(profile.executable)) {
    // CMD expands percent variables and delayed !variables! even inside quotes.
    // Refuse unrepresentable arguments instead of silently pointing elsewhere.
    if (path.contains('%') || path.contains('!') || path.contains('"')) {
      throw const FormatException(
        'CMD cannot safely paste this path; use PowerShell',
      );
    }
    return '"$path"';
  }
  if (profile.id == TerminalProfile.powershellId ||
      profile.id == TerminalProfile.pwshId ||
      RegExp(
        r'(^|[/\\])(powershell|pwsh)(\.exe)?$',
        caseSensitive: false,
      ).hasMatch(profile.executable)) {
    return "'${path.replaceAll("'", "''")}'";
  }
  return "'${path.replaceAll("'", r"'\''")}'";
}
