import 'package:cockpit/app/cockpit/domain/contracts/db_connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Senhas de conexão no cofre nativo do SO via `flutter_secure_storage`
/// (Keychain / Credential Manager / Secret Service). Erros do cofre propagam
/// — o chamador degrada pro prompt com aviso, nunca em silêncio (lição do
/// Keychain no pareamento).
class DbSecretsImpl implements DbSecrets {
  const DbSecretsImpl();

  static const _storage = FlutterSecureStorage(
    // `useDataProtectionKeyChain: false` = Keychain file-based clássico. O
    // Data Protection Keychain (default) exige entitlement de Keychain
    // Sharing/assinatura de loja — sem ele o write falha silencioso
    // (errSecMissingEntitlement) e a senha "salva" volta vazia (bug
    // 2026-07-18). Sandbox OFF → o clássico funciona em dev e release.
    mOptions: MacOsOptions(
      synchronizable: false,
      useDataProtectionKeyChain: false,
    ),
  );

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
