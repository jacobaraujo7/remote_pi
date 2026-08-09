import 'dart:async';

import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Quick-open por **nome** de arquivo (Cmd+P), estilo VSCode: palette flutuante
/// centrada no topo. Digita pra filtrar (fuzzy via [search]), ↑/↓ navega, Enter
/// abre, Esc fecha. [search] devolve caminhos **relativos** à raiz do projeto.
Future<void> showFileFinderPalette(
  BuildContext context, {
  required Future<List<String>> Function(String query) search,
  required void Function(String relativePath) onPick,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => _FileFinderPalette(search: search, onPick: onPick),
  );
}

class _FileFinderPalette extends StatefulWidget {
  const _FileFinderPalette({required this.search, required this.onPick});

  final Future<List<String>> Function(String query) search;
  final void Function(String relativePath) onPick;

  @override
  State<_FileFinderPalette> createState() => _FileFinderPaletteState();
}

class _FileFinderPaletteState extends State<_FileFinderPalette> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  int _reqId = 0;
  List<String> _results = const <String>[];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _query(''); // carrega os primeiros arquivos já de cara
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _query(value));
  }

  Future<void> _query(String value) async {
    final id = ++_reqId;
    final results = await widget.search(value);
    if (!mounted || id != _reqId) return; // resultado obsoleto
    setState(() {
      _results = results;
      _selected = 0;
    });
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, _results.length - 1);
    });
    _ensureVisible();
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const itemHeight = 34.0;
    final target = _selected * itemHeight;
    final top = _scroll.offset;
    final bottom = top + _scroll.position.viewportDimension;
    if (target < top) {
      _scroll.jumpTo(target);
    } else if (target + itemHeight > bottom) {
      _scroll.jumpTo(target + itemHeight - _scroll.position.viewportDimension);
    }
  }

  void _pick(int index) {
    if (index < 0 || index >= _results.length) return;
    final path = _results[index];
    Navigator.of(context).pop();
    widget.onPick(path);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _pick(_selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Focus(
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  placeholder: Text(
                    'Go to file…',
                    style: context.typo.body.copyWith(color: colors.text4),
                  ),
                  style: context.typo.body.copyWith(color: colors.text),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  onChanged: _onChanged,
                ),
              ),
              Flexible(
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No files.',
                            style: context.typo.label.copyWith(
                              color: colors.text4,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: _results.length,
                        itemBuilder: (context, i) => _row(context, i),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final colors = context.colors;
    final typo = context.typo;
    final path = _results[index];
    final name = path.split('/').last;
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    final selected = index == _selected;

    return HoverTap(
      color: selected ? colors.panel2 : null,
      hoverColor: colors.panel2,
      onTap: () => _pick(index),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          FileTypeIcon.file(name, size: 16),
          const SizedBox(width: 8),
          Text(
            name,
            style: typo.body.copyWith(fontSize: 13, color: colors.text),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dir,
              overflow: TextOverflow.ellipsis,
              style: typo.label.copyWith(fontSize: 11, color: colors.text4),
            ),
          ),
        ],
      ),
    );
  }
}
