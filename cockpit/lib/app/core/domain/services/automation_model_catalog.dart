import 'package:cockpit/app/core/domain/entities/automation.dart';

/// Curadoria do catálogo devolvido pelos CLIs.
///
/// Duas coisas acontecem aqui, e nenhuma delas envolve I/O:
///
/// 1. **Descarte** do que não escreve texto (embeddings, TTS, imagem, vídeo) e
///    dos ids internos que os CLIs expõem mas ninguém deve escolher.
/// 2. **Ordenação por custo/velocidade** — escrever uma mensagem de commit é
///    tarefa curta e bem definida; modelo caro só queima cota. `auto` (quando o
///    harness tem) vem primeiro, depois a família rápida, e os pesados no fim.
///
/// A lista devolvida é completa (a busca no menu alcança tudo); a UI mostra só
/// os [curatedLimit] primeiros até o usuário digitar.
abstract class AutomationModelCatalog {
  /// Quantos modelos aparecem no menu antes de o usuário buscar.
  static const int curatedLimit = 12;

  /// Modalidades que não servem para escrever um commit.
  static final RegExp _nonTextual = RegExp(
    r'embedding|embed-|[-/]tts\b|text-to-speech|whisper|transcribe|'
    r'\bimage\b|imagen|dall-?e|sora|veo-|lyria|music|audio|speech|vision|'
    r'computer-use|deep-research|guard|moderation|rerank',
    caseSensitive: false,
  );

  /// Ids que o CLI expõe por implementação, não como escolha de usuário.
  static const Set<String> _internalIds = {
    'codex-auto-review',
    'gpt-reserve',
    'auto-review',
  };

  /// Famílias rápidas/baratas — o alvo certo para uma tarefa curta.
  /// Os `\b` importam: sem eles `mini` casa dentro de "gemini" e um Gemini Pro
  /// entraria como modelo barato.
  static final RegExp _cheap = RegExp(
    r'\b(haiku|flash|mini|lite|nano|small|spark|free|composer)\b|'
    r'-low(-fast)?$|:low$',
    caseSensitive: false,
  );

  /// Famílias caras ou de raciocínio longo — último recurso para um commit.
  static final RegExp _expensive = RegExp(
    r'opus|ultra|-pro\b|pro-|thinking|reasoner|-xhigh|-max|:high$|-high$',
    caseSensitive: false,
  );

  /// Aplica descarte + ordenação. Estável: empates preservam a ordem em que o
  /// CLI devolveu (que costuma ser a preferência do próprio vendor).
  static List<AutomationModel> curate(List<AutomationModel> discovered) {
    final unique = <String, AutomationModel>{};
    for (final model in discovered) {
      final id = model.id.trim();
      if (id.isEmpty) continue;
      if (_internalIds.contains(id.toLowerCase())) continue;
      if (_nonTextual.hasMatch(id) || _nonTextual.hasMatch(model.label)) {
        continue;
      }
      unique[id] = AutomationModel(
        id: id,
        label: model.label.trim().isEmpty ? id : model.label.trim(),
      );
    }

    final ranked = unique.values.toList();
    final order = {for (var i = 0; i < ranked.length; i++) ranked[i].id: i};
    ranked.sort((a, b) {
      final byCost = _cost(a).compareTo(_cost(b));
      if (byCost != 0) return byCost;
      return order[a.id]!.compareTo(order[b.id]!);
    });
    return ranked;
  }

  /// 0 = roteamento automático, 1 = rápido/barato, 2 = intermediário,
  /// 3 = caro/raciocínio longo.
  static int _cost(AutomationModel model) {
    final id = model.id;
    if (id == kAutomationAutoModelId || id.endsWith('/auto')) return 0;
    // "gemini-3.7-flash-high" é barato apesar do sufixo `-high`: a família
    // manda mais que o nível de esforço.
    if (_cheap.hasMatch(id)) return 1;
    if (_expensive.hasMatch(id)) return 3;
    return 2;
  }
}
