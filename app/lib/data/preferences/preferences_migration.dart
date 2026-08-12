import 'package:app/domain/contracts/key_value_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Migração one-time das preferências de UI do `flutter_secure_storage`
/// (onde todas as prefs viviam) para o `shared_preferences` (KeyValueStore).
///
/// Por quê: dados não-sensíveis (tema, fonte, idioma, relay URL, peer
/// selecionado, onboarding) não pertencem ao Keychain/Keystore — é
/// lento/flaky em alguns Androids. Segredos (pares pareados, owner key)
/// NÃO migram e continuam em storage seguro.
///
/// Responsabilidade explícita e testável; invocada UMA vez no boot antes do
/// primeiro `load()` do [Preferences]. Cada chave é copiada apenas se o alvo
/// ainda não a possui (nunca sobrescreve um valor já migrado pelo usuário) e,
/// em seguida, removida do armazenamento legado. Quando não há mais usuários
/// com dados no SecureStorage, esta função pode ser removida.

/// As chaves que viviam no `flutter_secure_storage`. Mantidas aqui (e não
/// expostas pelo [Preferences]) porque são um detalhe transitório do passo de
/// migração — serão removidas junto com esta função. Se o [Preferences] mudar
/// o nome de uma chave nova, as chaves LEGADAS aqui não mudam (elas refletem
/// o que estava persistido antes desta migração).
const List<String> _legacyKeys = [
  'prefs.hide_tool_calls',
  'prefs.selected_peer_epk',
  'prefs.relay_url',
  'prefs.onboarding_completed',
  'prefs.theme_mode',
  'prefs.font_scale',
  'prefs.locale',
];

/// Copia cada chave legada do [legacy] (SecureStorage) para o [target]
/// (KeyValueStore) e, só após a cópia confirmada, remove do [legacy].
///
/// A migração roda em duas fases para nunca apagar antes de copiar (caso
/// uma leitura/escrita falhe no meio — Keychain pode ser flaky — nada foi
/// removido do legado, e a próxima execução completa sem perda graças à
/// idempotência: chaves já copiadas são puladas, e apagar chave ausente é
/// no-op).
Future<void> migrateLegacySecurePrefs(
  FlutterSecureStorage legacy,
  KeyValueStore target,
) async {
  // Fase 1 — copy-only: nada é apagado até todas as chaves com valor terem
  // sido copiadas (ou constatadas já presentes no target).
  for (final key in _legacyKeys) {
    final value = await legacy.read(key: key);
    if (value == null || value.isEmpty) continue;
    final existing = await target.read(key);
    if (existing == null) {
      await target.write(key, value);
    }
  }

  // Fase 2 — cleanup: só remove do legado após a cópia confirmada. Idempotente
  // (apagar chave ausente é no-op no FlutterSecureStorage), seguro de rodar
  // mesmo pra chaves já removidas numa execução anterior.
  for (final key in _legacyKeys) {
    await legacy.delete(key: key);
  }
}
