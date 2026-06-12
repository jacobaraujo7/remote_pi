import 'package:cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Seletor de modelo com busca (o catálogo tem centenas). Devolve o [PiModel]
/// escolhido, ou `null` se cancelar.
Future<PiModel?> showModelPicker(
  BuildContext context, {
  required List<PiModel> models,
  PiModel? current,
}) {
  return showDialog<PiModel>(
    context: context,
    builder: (context) => _ModelPicker(models: models, current: current),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.current});
  final List<PiModel> models;
  final PiModel? current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final q = _query.toLowerCase();
    final filtered = widget.models
        .where(
          (m) =>
              q.isEmpty ||
              m.name.toLowerCase().contains(q) ||
              m.id.toLowerCase().contains(q) ||
              m.provider.toLowerCase().contains(q),
        )
        .toList();

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: TextField(
                autofocus: true,
                style: context.typo.body.copyWith(color: colors.text),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.text3),
                  hintText: 'Search model (${widget.models.length})',
                  hintStyle: context.typo.body.copyWith(color: colors.text3),
                  filled: true,
                  fillColor: colors.panel2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final model = filtered[index];
                  final selected = model == widget.current;
                  return Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.of(context).pop(model),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (model.reasoning)
                              Icon(
                                Icons.psychology_outlined,
                                size: 14,
                                color: colors.accentText,
                              )
                            else
                              const SizedBox(width: 14),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.typo.body.copyWith(
                                      fontSize: 13,
                                      color: selected
                                          ? colors.accentText
                                          : colors.text,
                                    ),
                                  ),
                                  Text(
                                    model.provider,
                                    style: context.typo.mono.copyWith(
                                      fontSize: 10.5,
                                      color: colors.text3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check, size: 15, color: colors.accent),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
