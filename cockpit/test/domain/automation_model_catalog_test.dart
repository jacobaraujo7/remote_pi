import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/services/automation_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _ids(List<AutomationModel> models) =>
    models.map((model) => model.id).toList();

void main() {
  test('drops models that cannot write a commit message', () {
    final curated = AutomationModelCatalog.curate(const [
      AutomationModel(id: 'google/gemini-embedding-001', label: 'Embedding'),
      AutomationModel(id: 'google/veo-3.1-fast', label: 'Veo'),
      AutomationModel(id: 'google/lyria-3', label: 'Lyria'),
      AutomationModel(
        id: 'google/gemini-2.5-flash-preview-tts',
        label: 'Flash TTS',
      ),
      AutomationModel(
        id: 'google/gemini-2.5-computer-use-preview-10-2025',
        label: 'Computer Use',
      ),
      AutomationModel(id: 'google/deep-research-max-preview', label: 'Deep'),
      AutomationModel(id: 'codex-auto-review', label: 'Auto review'),
      AutomationModel(id: 'gpt-reserve', label: 'Reserve'),
      AutomationModel(id: 'google/gemini-2.5-flash', label: 'Flash'),
    ]);

    expect(_ids(curated), ['google/gemini-2.5-flash']);
  });

  test('cheap and automatic models come first', () {
    final curated = AutomationModelCatalog.curate(const [
      AutomationModel(id: 'claude-opus-5', label: 'Opus 5'),
      AutomationModel(id: 'gpt-5.4', label: 'GPT-5.4'),
      AutomationModel(id: 'claude-haiku-4-5', label: 'Haiku'),
      AutomationModel(id: 'auto', label: 'Auto'),
      AutomationModel(id: 'gemini-3.1-pro-high', label: 'Pro'),
      AutomationModel(id: 'gpt-5.4-mini', label: 'Mini'),
    ]);

    expect(_ids(curated), [
      'auto',
      'claude-haiku-4-5',
      'gpt-5.4-mini',
      'gpt-5.4',
      'claude-opus-5',
      'gemini-3.1-pro-high',
    ]);
  });

  test('family wins over the effort suffix', () {
    // `gemini-3.7-flash-high` é da família rápida apesar do `-high`; já
    // `claude-opus-4-6-thinking` é caro apesar de não ter sufixo de esforço.
    final curated = AutomationModelCatalog.curate(const [
      AutomationModel(id: 'claude-opus-4-6-thinking', label: 'Opus thinking'),
      AutomationModel(id: 'gemini-3.7-flash-high', label: 'Flash high'),
    ]);

    expect(_ids(curated), [
      'gemini-3.7-flash-high',
      'claude-opus-4-6-thinking',
    ]);
  });

  test('keeps the CLI order on ties and drops duplicates', () {
    final curated = AutomationModelCatalog.curate(const [
      AutomationModel(id: 'gpt-5.4', label: 'GPT-5.4'),
      AutomationModel(id: 'gpt-5.5', label: 'GPT-5.5'),
      AutomationModel(id: 'gpt-5.4', label: 'GPT-5.4 (dup)'),
    ]);

    expect(_ids(curated), ['gpt-5.4', 'gpt-5.5']);
    expect(curated.first.label, 'GPT-5.4 (dup)');
  });
}
