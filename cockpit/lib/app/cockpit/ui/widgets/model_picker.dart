import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Seletor de modelo com busca (o catálogo tem centenas). Devolve o [PiModel]
/// escolhido, ou `null` se cancelar.
Future<PiModel?> showModelPicker(
  BuildContext context, {
  required List<PiModel> models,
  PiModel? current,
}) {
  return showDialog<PiModel>(
    context: context,
    barrierColor: context.colors.scrim,
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

    return AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              style: context.typo.body.copyWith(color: colors.text),
              onChanged: (v) => setState(() => _query = v),
              placeholder: Text(
                context.t.cockpit.modelPicker.search(
                  count: widget.models.length,
                ),
              ),
              borderRadius: BorderRadius.circular(7),
              features: const [InputFeature.leading(Icon(Icons.search))],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final model = filtered[index];
                  final selected = model == widget.current;
                  return HoverTap(
                    onTap: () => Navigator.of(context).pop(model),
                    borderRadius: BorderRadius.circular(6),
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
