import 'dart:io';

import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:flutter/services.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Right-click context menu for a detected terminal link, shared by both
/// terminal engines (ghostty/flterm and xterm).
///
/// Exactly one of [filePath] / [uri] is expected. For a file link, [onOpenFile]
/// opens it in Cockpit's viewer; "Reveal" and "Copy Path" use
/// [resolvedFilePath] when given (the absolute path), else [filePath].
Future<void> showTerminalLinkMenu(
  BuildContext context,
  Offset globalPosition, {
  String? filePath,
  int? fileLine,
  String? resolvedFilePath,
  Uri? uri,
  void Function(String path, {int? line})? onOpenFile,
}) async {
  final tr = context.t.cockpit.terminalLink;
  final items = <AppMenuItem<VoidCallback>>[];
  if (filePath != null) {
    final target = _expandHome(resolvedFilePath ?? filePath);
    items.add(
      AppMenuItem(
        value: () => openTerminalLink(
          filePath: filePath,
          fileLine: fileLine,
          resolvedFilePath: resolvedFilePath,
          onOpenFile: onOpenFile,
        ),
        label: tr.open,
      ),
    );
    if (!isMobilePlatform) {
      items.add(
        AppMenuItem(
          value: () => _revealInFileManager(target),
          label: Platform.isMacOS
              ? tr.revealFinder
              : Platform.isWindows
              ? tr.revealExplorer
              : tr.revealFolder,
        ),
      );
    }
    items.add(
      AppMenuItem(
        value: () => Clipboard.setData(ClipboardData(text: target)),
        label: tr.copyPath,
      ),
    );
  } else if (uri != null) {
    items.add(
      AppMenuItem(
        value: () => openTerminalLink(uri: uri),
        label: tr.openLink,
      ),
    );
    items.add(
      AppMenuItem(
        value: () => Clipboard.setData(ClipboardData(text: uri.toString())),
        label: tr.copyLink,
      ),
    );
  }
  if (items.isEmpty) return;
  final action = await showAppMenu<VoidCallback>(
    context,
    items: items,
    globalPosition: globalPosition,
  );
  action?.call();
}

/// Expands a leading `~` / `~/` to the local home directory. flterm leaves
/// shell-expanded paths unresolved, so the menu's direct file-system actions
/// (Reveal, Copy) must expand them. (Open routes through the terminal path
/// resolver, which already expands `~`.)
String _expandHome(String path) {
  if (path != '~' && !path.startsWith('~/')) return path;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return path;
  return path == '~' ? home : '$home${path.substring(1)}';
}

/// Opens a detected terminal link. A text file opens in Cockpit's viewer; a
/// non-text file (e.g. a .dmg) and URLs open with the OS default app, mirroring
/// Warp's "Open". Shared by the context menu and ⌘/Ctrl-click.
Future<void> openTerminalLink({
  String? filePath,
  int? fileLine,
  String? resolvedFilePath,
  Uri? uri,
  void Function(String path, {int? line})? onOpenFile,
}) async {
  if (filePath != null) {
    final target = _expandHome(resolvedFilePath ?? filePath);
    if (await _looksBinary(target)) {
      _osOpen(target);
    } else {
      onOpenFile?.call(_expandHome(filePath), line: fileLine);
    }
    return;
  }
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// True if the file's first bytes contain a NUL — a reliable binary signal that
/// Cockpit's text viewer can't render, so it should open with the OS instead.
Future<bool> _looksBinary(String path) async {
  try {
    final raf = await File(path).open();
    try {
      final length = await raf.length();
      final bytes = await raf.read(length < 4096 ? length : 4096);
      return bytes.contains(0);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false; // unreadable → let the viewer/resolver try
  }
}

void _osOpen(String path) {
  if (Platform.isMacOS) {
    Process.run('open', [path]);
  } else if (Platform.isWindows) {
    Process.run('explorer', [path]);
  } else {
    Process.run('xdg-open', [path]);
  }
}

void _revealInFileManager(String path) {
  if (Platform.isMacOS) {
    Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    Process.run('explorer', ['/select,', path]);
  } else {
    Process.run('xdg-open', [File(path).parent.path]);
  }
}
