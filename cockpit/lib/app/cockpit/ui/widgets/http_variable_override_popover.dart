import 'package:cockpit/app/cockpit/domain/entities/http_runtime_variable.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Editor compacto ancorado no placeholder, sem escrever no arquivo HTTP.
class HttpVariableOverridePopover extends StatefulWidget {
  const HttpVariableOverridePopover({
    super.key,
    required this.name,
    required this.effectiveValue,
    required this.origin,
    required this.runtimeOverride,
    required this.onApply,
    required this.onClear,
  });

  final String name;
  final String? effectiveValue;
  final String origin;
  final HttpRuntimeVariable? runtimeOverride;
  final ValueChanged<HttpRuntimeVariable> onApply;
  final VoidCallback onClear;

  @override
  State<HttpVariableOverridePopover> createState() =>
      _HttpVariableOverridePopoverState();
}

class _HttpVariableOverridePopoverState
    extends State<HttpVariableOverridePopover> {
  late final TextEditingController _input;
  final FocusNode _typeFocus = FocusNode();
  late HttpRuntimeValueType _type;
  bool _typesOpen = false;
  HttpRuntimeValidationError? _error;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: widget.runtimeOverride?.input ?? widget.effectiveValue ?? '',
    );
    _type =
        widget.runtimeOverride?.type ??
        HttpRuntimeVariable.inferType(widget.effectiveValue);
  }

  @override
  void didUpdateWidget(HttpVariableOverridePopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Atualizações externas do valor efetivo não apagam um rascunho em edição.
    // Aplicar/restaurar troca a instância do override e sincroniza o campo.
    if (oldWidget.name != widget.name ||
        oldWidget.runtimeOverride != widget.runtimeOverride) {
      _input.text =
          widget.runtimeOverride?.input ?? widget.effectiveValue ?? '';
      _type =
          widget.runtimeOverride?.type ??
          HttpRuntimeVariable.inferType(widget.effectiveValue);
      _error = null;
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  void _apply() {
    final value = HttpRuntimeVariable(_input.text, _type);
    final error = value.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _typesOpen = false;
    });
    widget.onApply(value);
  }

  void _chooseType(HttpRuntimeValueType type) {
    _typeFocus.requestFocus();
    setState(() {
      _type = type;
      _typesOpen = false;
      _error = null;
    });
  }

  Widget _focusableAction(Widget child, VoidCallback action) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space)) {
        action();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Builder(
        builder: (focusContext) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Focus.of(focusContext).requestFocus();
            action();
          },
          child: child,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;
    final errorMessage = switch (_error) {
      HttpRuntimeValidationError.invalidNumber => tr.overrideInvalidNumber,
      HttpRuntimeValidationError.nonFiniteNumber => tr.overrideNonFiniteNumber,
      HttpRuntimeValidationError.invalidBoolean => tr.overrideInvalidBoolean,
      HttpRuntimeValidationError.invalidJson => tr.overrideInvalidJson,
      null => null,
    };
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.mono.copyWith(color: colors.accent, fontSize: 12),
                ),
              ),
              Text(
                widget.runtimeOverride == null
                    ? widget.origin
                    : tr.overrideTemporary,
                style: typo.label.copyWith(
                  color: widget.runtimeOverride == null
                      ? colors.text2
                      : colors.accent,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _input,
            placeholder: const Text('undefined'),
            style: typo.mono.copyWith(fontSize: 12, color: colors.text),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            onSubmitted: (_) => _apply(),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              errorMessage,
              style: typo.label.copyWith(color: colors.error, fontSize: 11),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Focus(
                focusNode: _typeFocus,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    setState(() => _typesOpen = !_typesOpen);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _typeFocus.requestFocus();
                      setState(() => _typesOpen = !_typesOpen);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.border),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _type.name,
                            style: typo.label.copyWith(fontSize: 11),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 13,
                            color: colors.text2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.runtimeOverride != null)
                _focusableAction(
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      tr.overrideRestore,
                      style: typo.label.copyWith(
                        color: colors.text2,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  widget.onClear,
                ),
              _focusableAction(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    tr.overrideApply,
                    style: typo.label.copyWith(
                      color: onColor(colors.accent),
                      fontSize: 11,
                    ),
                  ),
                ),
                _apply,
              ),
            ],
          ),
          if (_typesOpen) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final type in HttpRuntimeValueType.values)
                  _focusableAction(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: type == _type
                            ? colors.accentSoft
                            : colors.panel3,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type.name,
                        style: typo.label.copyWith(fontSize: 11),
                      ),
                    ),
                    () => _chooseType(type),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
