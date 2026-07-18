import 'package:cockpit/app/cockpit/domain/entities/project.dart';

/// Persistência dos projetos (pastas salvas). Contrato no domínio; a
/// implementação concreta (Hive) mora em `data/`.
abstract class ProjectRepository {
  /// Todos os projetos salvos, ordenados por criação (mais antigo primeiro).
  Future<List<Project>> all();

  /// Cria ou atualiza um projeto.
  Future<void> save(Project project);

  /// Remove um projeto pelo id.
  Future<void> remove(String id);

  /// Id do último workspace selecionado **naquele realm** (pra restaurar ao
  /// trocar de realm / na próxima abertura), ou `null` se nunca salvou.
  Future<String?> loadLastSelected(String realmId);

  /// Persiste o id do último workspace selecionado do realm (`null` limpa).
  Future<void> saveLastSelected(String realmId, String? id);
}
