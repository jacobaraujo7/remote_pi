/// Chave/valor persistido simples, para dados NÃO-sensíveis (preferências de
/// UI). Contrato no domínio; impl em `data/`.
///
/// NÃO usar para segredos — pares pareados e owner key ficam em storage
/// seguro (Keychain/Keystore). Este contrato só cobre leitura/escrita/apagar
/// de strings; tipos booleanos/enums são serializados pelo chamador.
abstract class KeyValueStore {
  /// Lê o valor de [key], ou `null` se a chave estiver ausente.
  Future<String?> read(String key);

  /// Escreve [value] (não-null) sob [key].
  Future<void> write(String key, String value);

  /// Apaga [key]. Único caminho para remover uma chave — não há
  /// "escrever null" ambíguo.
  Future<void> delete(String key);
}
