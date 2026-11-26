import 'dart:io';

import 'package:cockpit/app/cockpit/domain/validators/clone_destination.dart';
import 'package:cockpit/app/cockpit/domain/validators/git_clone_url.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/native_folder_picker.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// O que o dialog "Clonar repositório" devolve: a URL e o caminho final do
/// clone (pasta de destino + nome da pasta).
typedef CloneRequest = ({String url, String targetPath});

/// Dialog "Clonar repositório" (menu do "+" da rail): URL SSH/HTTPS, pasta de
/// destino (picker nativo) e nome da pasta, derivado da URL até o usuário
/// editar. Só valida; o clone em si roda depois, no dialog de processo git.
///
/// [initialParent] é onde o picker começa e o destino pré-preenchido.
/// [clipboardText] existe pra teste; por padrão lê o clipboard do sistema e,
/// se houver uma URL git lá, já entra preenchida.
Future<CloneRequest?> showCloneRepositoryDialog(
  BuildContext context, {
  required String initialParent,
  Future<String?> Function()? clipboardText,
}) {
  return showDialog<CloneRequest>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _CloneRepositoryDialog(
      initialParent: initialParent,
      clipboardText: clipboardText ?? _systemClipboard,
    ),
  );
}

Future<String?> _systemClipboard() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

class _CloneRepositoryDialog extends StatefulWidget {
  const _CloneRepositoryDialog({
    required this.initialParent,
    required this.clipboardText,
  });

  final String initialParent;
  final Future<String?> Function() clipboardText;

  @override
  State<_CloneRepositoryDialog> createState() => _CloneRepositoryDialogState();
}

class _CloneRepositoryDialogState extends State<_CloneRepositoryDialog> {
  final _url = TextEditingController();
  final _folder = TextEditingController();
  late String _parent = widget.initialParent;

  /// `true` quando o usuário mexeu no nome da pasta: aí a URL para de
  /// sobrescrevê-lo.
  bool _folderEdited = false;

  /// `true` depois de um submit inválido — só então os erros aparecem.
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _url.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _prefillFromClipboard() async {
    final text = (await widget.clipboardText())?.trim();
    if (!mounted || text == null || _url.text.isNotEmpty) return;
    if (isGitCloneUrl(text)) _setUrl(text);
  }

  Future<void> _paste() async {
    final text = (await widget.clipboardText())?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    _setUrl(text);
  }

  void _setUrl(String text) {
    _url.text = text;
    _onUrlChanged(text);
  }

  void _onUrlChanged(String value) {
    if (!_folderEdited) _folder.text = repoNameFromGitUrl(value) ?? '';
    setState(() {});
  }

  Future<void> _pickParent() async {
    final picked = await NativeFolderPicker.pick(
      dialogTitle: context.t.cockpit.cloneRepoDialog.chooseParentDialogTitle,
      initialDirectory: _parent,
    );
    if (picked == null || !mounted) return;
    setState(() => _parent = picked);
  }

  String get _urlTrimmed => _url.text.trim();
  String get _folderTrimmed => _folder.text.trim();
  String get _targetPath => cloneTargetPath(_parent, _folderTrimmed);

  bool get _urlInvalid => !isGitCloneUrl(_urlTrimmed);
  bool get _parentInvalid =>
      _parent.isEmpty || !Directory(_parent).existsSync();
  CloneFolderError? get _folderError =>
      validateCloneFolderName(_folder.text, windows: Platform.isWindows);
  bool get _folderInvalid => _folderError != null;

  String _folderErrorText(BuildContext context, CloneFolderError error) {
    final tr = context.t.cockpit.cloneRepoDialog;
    return switch (error) {
      CloneFolderError.empty ||
      CloneFolderError.dotName ||
      CloneFolderError.separator => tr.errFolder,
      CloneFolderError.invalidChar => tr.errFolderChars,
      CloneFolderError.reserved => tr.errFolderReserved(name: _folderTrimmed),
      CloneFolderError.trailingDotOrSpace => tr.errFolderTrailing,
    };
  }

  /// O git só clona numa pasta inexistente ou vazia.
  bool get _targetTaken {
    if (_parentInvalid || _folderInvalid) return false;
    final type = FileSystemEntity.typeSync(_targetPath);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory) return true;
    return Directory(_targetPath).listSync().isNotEmpty;
  }

  void _submit() {
    if (_urlInvalid || _parentInvalid || _folderInvalid || _targetTaken) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(
      context,
    ).pop<CloneRequest>((url: _urlTrimmed, targetPath: _targetPath));
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: context.typo.label.copyWith(color: context.colors.text2),
    ),
  );

  Widget _errorText(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      message,
      style: context.typo.label.copyWith(
        fontSize: 11,
        color: context.colors.error,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.cloneRepoDialog;
    return AlertDialog(
      title: Text(
        tr.title,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, tr.urlLabel),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('clone-url'),
                    controller: _url,
                    autofocus: true,
                    placeholder: Text(tr.urlPlaceholder),
                    style: context.typo.mono.copyWith(fontSize: 12),
                    onChanged: _onUrlChanged,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _paste,
                  child: Text(tr.paste),
                ),
              ],
            ),
            if (_attempted && _urlInvalid) _errorText(context, tr.errUrl),
            const SizedBox(height: 12),
            _label(context, tr.parentLabel),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _parent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.mono.copyWith(
                      fontSize: 11,
                      color: colors.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _pickParent,
                  child: Text(tr.choose),
                ),
              ],
            ),
            if (_attempted && _parentInvalid) _errorText(context, tr.errParent),
            const SizedBox(height: 12),
            _label(context, tr.folderLabel),
            TextField(
              key: const ValueKey('clone-folder'),
              controller: _folder,
              onChanged: (_) => setState(() => _folderEdited = true),
              onSubmitted: (_) => _submit(),
            ),
            if (_attempted && _folderError != null)
              _errorText(context, _folderErrorText(context, _folderError!)),
            if (_attempted && _targetTaken)
              _errorText(context, tr.errExists(path: _targetPath)),
            if (!_folderInvalid && !_parentInvalid) ...[
              const SizedBox(height: 10),
              Text(
                tr.targetPreview(path: _targetPath),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.typo.mono.copyWith(
                  fontSize: 11,
                  color: colors.text3,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(onPressed: _submit, child: Text(tr.cloneAction)),
      ],
    );
  }
}
