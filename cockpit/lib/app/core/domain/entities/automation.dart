import 'package:cockpit/app/core/domain/entities/harness.dart';

// Quem fala de automação fala de [HarnessKind] — reexportado para não obrigar
// dois imports em cada arquivo.
export 'package:cockpit/app/core/domain/entities/harness.dart';

/// Id do modelo de roteamento automático. Quando o harness oferece esse modo,
/// ele é o padrão: é o único id que nunca quebra por diferença de plano.
const String kAutomationAutoModelId = 'auto';

extension AutomationHarnessSupport on HarnessKind {
  HarnessSpec get spec => HarnessCatalog.specs[this]!;

  String get label => spec.label;

  String get executableName => spec.primaryEntryPoint;

  /// Pastas específicas onde procurar o executável além do PATH.
  /// `cursor-agent` e `agy` instalam em `~/.local/bin` e não aparecem no PATH
  /// de um app de janela lançado pelo Finder/launcher do desktop.
  List<String> get unixHomeRelativeCandidates => switch (this) {
    HarnessKind.cursor => const ['.local/bin/cursor-agent'],
    HarnessKind.antigravity => const ['.local/bin/agy'],
    HarnessKind.gitHubCopilot => const ['.local/bin/copilot'],
    HarnessKind.pi => const ['.local/bin/pi'],
    _ => const <String>[],
  };

  /// `false` quando o harness não tem catálogo de modelos vinculado à conta.
  /// Nesses casos o Cockpit não deixa escolher modelo — usa `auto` (Copilot) ou
  /// o modelo que o próprio CLI já tem configurado (Claude Code), que é sempre
  /// compatível com o plano do usuário.
  bool get hasAccountScopedModels => switch (this) {
    HarnessKind.claudeCode || HarnessKind.gitHubCopilot => false,
    _ => true,
  };

  /// Modelo fixo quando não há escolha possível. Copilot roteia com `auto`, que
  /// é obrigatório em planos restritos (ex.: Student).
  String? get pinnedModelId =>
      this == HarnessKind.gitHubCopilot ? kAutomationAutoModelId : null;
}

class AutomationModel {
  const AutomationModel({required this.id, required this.label});

  final String id;
  final String label;
}

class AutomationHarness {
  const AutomationHarness({
    required this.id,
    required this.executablePath,
    this.models = const <AutomationModel>[],
  });

  final HarnessKind id;
  final String executablePath;

  /// Catálogo já filtrado pela conta e curado (ver `AutomationModelCatalog`).
  final List<AutomationModel> models;

  String get label => id.label;

  /// Modelo usado quando o usuário não escolheu nenhum: `auto` quando o harness
  /// oferece roteamento automático, senão `null` (= default do próprio CLI).
  String? get defaultModelId =>
      id.pinnedModelId ??
      (models.any((model) => model.id == kAutomationAutoModelId)
          ? kAutomationAutoModelId
          : null);

  /// `true` quando faz sentido mostrar o seletor de modelo.
  bool get allowsModelChoice => id.pinnedModelId == null && models.isNotEmpty;
}

class AutomationSelection {
  const AutomationSelection({required this.harnessId, this.modelId});

  final HarnessKind harnessId;
  final String? modelId;

  AutomationSelection withModel(String? id) =>
      AutomationSelection(harnessId: harnessId, modelId: id);
}

class AutomationRequest {
  const AutomationRequest({required this.prompt, required this.repositoryPath});

  final String prompt;
  final String repositoryPath;
}

/// Mensagem gerada pelo harness. [warning] é um aviso de convenção (subject
/// longo, ponto final, etc.) — a mensagem ainda é um rascunho editável.
class GeneratedCommitMessage {
  const GeneratedCommitMessage({required this.message, this.warning});

  final String message;
  final String? warning;
}
