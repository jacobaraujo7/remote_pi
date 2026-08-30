import 'dart:convert';
import 'dart:io';

import 'ssh_tunnel.dart';

/// Host keys de bastion confiadas **nesta máquina** (TOFU), em
/// `~/.cockpit/ssh-known-hosts.json`.
///
/// Usado pelo `cockpit-server`: quem abre o túnel é o host, então é o
/// julgamento dele sobre a host key que vale. O cliente tem o seu próprio store
/// para os workspaces locais — são máquinas diferentes confiando em bastions
/// possivelmente diferentes, e misturar seria errado.
///
/// **Não é cifrado de propósito.** Fingerprint de host key é público — o valor
/// dele está em ser comparável e auditável, e um arquivo legível é o que
/// permite conferir à mão o que foi confiado.
///
/// Deliberadamente **não** é o `known_hosts` do sistema: o `dartssh2` não lê
/// aquele formato (decisão C do plano 54), e manter o nosso é o que permite
/// detectar troca de host key.
class FileSshHostKeyStore implements SshHostKeyStore {
  FileSshHostKeyStore({String? path}) : _path = path ?? defaultPath();

  final String _path;

  static String defaultPath() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    return '$home/.cockpit/ssh-known-hosts.json';
  }

  Map<String, String> _load() {
    final file = File(_path);
    if (!file.existsSync()) return <String, String>{};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on Object {
      // Arquivo corrompido vira "nada confiado": o pior que acontece é o
      // usuário reconfirmar a host key, e nunca confiar em algo por engano.
      return <String, String>{};
    }
  }

  void _save(Map<String, String> data) {
    final file = File(_path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(data)}\n', flush: true);
  }

  @override
  String? trusted(String endpoint) => _load()[endpoint];

  @override
  Future<void> trust(String endpoint, String fingerprint) async =>
      _save(_load()..[endpoint] = fingerprint);

  @override
  Future<void> forget(String endpoint) async =>
      _save(_load()..remove(endpoint));
}
