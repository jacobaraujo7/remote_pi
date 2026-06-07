/// Um modelo de LLM que o agente pode usar. Versão de domínio do objeto `Model`
/// do RPC (`get_available_models` / `set_model` / `get_state`).
class PiModel {
  const PiModel({
    required this.provider,
    required this.id,
    required this.name,
    required this.reasoning,
    this.supportsImages = false,
    this.contextWindow,
    this.thinkingLevelMap = const <String, String?>{},
  });

  final String provider;
  final String id;
  final String name;

  /// Suporta thinking/raciocínio (habilita o seletor de effort).
  final bool reasoning;

  /// Aceita imagem na entrada (`input` contém `image`) — habilita anexos de
  /// visão. `false` = modelo text-only (não enxerga imagem).
  final bool supportsImages;

  /// Tamanho da janela de contexto em tokens (pode faltar).
  final int? contextWindow;

  /// O que o modelo aceita de effort (`thinkingLevelMap` do RPC). Mapa de
  /// nível canônico → string que o provider quer (ou `null` = nível **não**
  /// disponível pra este modelo). Chaves ausentes ficam disponíveis por padrão.
  final Map<String, String?> thinkingLevelMap;

  /// Identidade lógica: provider + id (o que `set_model` precisa).
  @override
  bool operator ==(Object other) =>
      other is PiModel && other.provider == provider && other.id == id;

  @override
  int get hashCode => Object.hash(provider, id);
}
