/// Um conjunto nomeado de workspaces — o recorte de contexto que o rail exibe
/// (ex.: "Trabalho", "Pessoal"). Realm **não isola nada**: settings, tema e
/// sessões são globais; trocar de realm só muda quais workspaces aparecem.
/// Sessões de workspaces de realms ocultos continuam rodando.
class Realm {
  const Realm({
    required this.id,
    required this.name,
    required this.createdAt,
    this.order = 0,
  });

  /// Id do realm implícito "Default". Sempre existe, não pode ser excluído;
  /// workspaces de versões anteriores (sem `realmId`) caem nele na migração.
  static const String defaultId = 'default';

  final String id;
  final String name;
  final DateTime createdAt;

  /// Posição na lista do dropdown (ordem de criação; desempate por [createdAt]).
  final int order;

  bool get isDefault => id == defaultId;

  Realm copyWith({String? name, int? order}) => Realm(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    order: order ?? this.order,
  );

  @override
  bool operator ==(Object other) => other is Realm && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
