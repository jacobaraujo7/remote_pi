import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cofre de senhas de banco **desta máquina** (plano 62): o mesmo
/// `~/.cockpit/db-secrets.json` que o `cockpit-server` lê ao atender um
/// cliente remoto.
///
/// Antes eram dois cofres na mesma máquina: workspace local gravava no cofre
/// do SO (Keychain/Credential Manager) e cliente remoto gravava no arquivo.
/// Como o `cockpit-server` é headless — sobe por SSH, sem sessão gráfica — ele
/// nunca teve como ler o cofre do SO, então a senha digitada no host não valia
/// para nenhum cliente. O usuário salvava com sucesso e o remoto continuava
/// dizendo que a senha não existia.
///
/// A regra agora é uma só: **o segredo mora onde a conexão é aberta**, e num
/// workspace local quem abre é esta máquina. Digitar aqui ou de um cliente
/// remoto cai no mesmo lugar.
///
/// A troca aceita conscientemente: o cofre do SO é mais forte que o arquivo
/// (ACL por item, prompt para processo não autorizado, cifrado independente do
/// disco). O arquivo é cifrado, mas com chave do produto — ver a doc do
/// [DbSecretStore]. Coerência ganhou de garantia porque a alternativa era o
/// usuário não ter como configurar de um lado só.
class DbSecretsImpl implements DbSecrets {
  DbSecretsImpl({DbSecretStore? store, FlutterSecureStorage? legacy})
    : _store = store ?? DbSecretStore(),
      _legacy = legacy ?? _defaultLegacy;

  final DbSecretStore _store;

  /// Cofre do SO, mantido **apenas para migração**. Nada novo é escrito nele.
  final FlutterSecureStorage _legacy;

  static const _defaultLegacy = FlutterSecureStorage(
    // `useDataProtectionKeyChain: false` = Keychain file-based clássico, que é
    // onde as senhas anteriores a esta versão foram gravadas. Trocar aqui
    // deixaria a migração sem encontrá-las.
    mOptions: MacOsOptions(
      synchronizable: false,
      useDataProtectionKeyChain: false,
    ),
  );

  @override
  Future<void> write(String key, String value) async =>
      _store.writeKey(key, value);

  @override
  Future<String?> read(String key, {String? legacyKey}) async {
    final current = _store.readKey(key);
    if (current != null) return current;
    if (legacyKey == null) return null;
    return _migrate(legacyKey, key);
  }

  @override
  Future<void> delete(String key) async => _store.deleteKey(key);

  /// Move o segredo do cofre do SO para o cofre único e o apaga de lá.
  ///
  /// Best-effort de propósito: o cofre do SO pode falhar (Keychain trancado,
  /// prompt recusado, Secret Service ausente no Linux) e isso não pode
  /// derrubar a query — quem não migrar apenas redigita a senha, que é o
  /// caminho que já existia.
  Future<String?> _migrate(String legacyKey, String key) async {
    try {
      final legacy = await _legacy.read(key: legacyKey);
      if (legacy == null || legacy.isEmpty) return null;
      _store.writeKey(key, legacy);
      await _legacy.delete(key: legacyKey);
      return legacy;
    } on Object catch (e) {
      debugPrint('db secrets: migração de "$legacyKey" falhou ($e)');
      return null;
    }
  }
}
