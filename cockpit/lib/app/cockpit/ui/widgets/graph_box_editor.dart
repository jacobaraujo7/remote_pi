import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

typedef GraphBoxEditDraft = ({
  String role,
  String harness,
  String model,
  bool start,
});

Future<GraphBoxEditDraft?> showGraphBoxEditor(
  BuildContext context,
  GraphBox box, {
  required bool canStart,
}) async {
  final role = TextEditingController(text: box.role);
  final model = TextEditingController(text: box.model);
  var harness = box.harness == 'claudeCode' ? 'claude' : box.harness;
  if (!const {'claude', 'codex', 'pi'}.contains(harness)) harness = '';
  try {
    return await showDialog<GraphBoxEditDraft>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar função e CLI'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Função'),
                TextField(controller: role, maxLines: 6),
                const SizedBox(height: 12),
                const Text('Ferramenta'),
                Row(
                  children: [
                    for (final option in const ['claude', 'codex', 'pi'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlineButton(
                          onPressed: () =>
                              setDialogState(() => harness = option),
                          child: Text(harness == option ? '● $option' : option),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Modelo (vazio = padrão da ferramenta)'),
                TextField(controller: model),
              ],
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            OutlineButton(
              onPressed: () {
                Navigator.of(dialogContext).pop((
                  role: role.text.trim(),
                  harness: harness,
                  model: model.text.trim(),
                  start: false,
                ));
              },
              child: const Text('Salvar'),
            ),
            if (canStart && harness.isNotEmpty)
              PrimaryButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop((
                    role: role.text.trim(),
                    harness: harness,
                    model: model.text.trim(),
                    start: true,
                  ));
                },
                child: const Text('Salvar e iniciar CLI'),
              ),
          ],
        ),
      ),
    );
  } finally {
    role.dispose();
    model.dispose();
  }
}
