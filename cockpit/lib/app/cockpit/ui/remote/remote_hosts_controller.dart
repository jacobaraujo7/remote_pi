import 'package:cockpit_core/cockpit_core.dart';
import 'dart:async';

import 'package:cockpit/app/cockpit/data/remote/mobile_ssh_key_store.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/app/core/utils/remote_path.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_host_password_store.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_host_terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/remote_hosts_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_workspace_pin.dart';
import 'package:cockpit/app/cockpit/data/terminal/sidecar/sidecar_terminal_connector.dart';
import 'package:cockpit_remote/cockpit_remote.dart';
import 'package:flutter/foundation.dart';

/// Estado app-scoped dos hosts remotos (plano 58, Wave 2/fecho): dono do
/// registro persistido + um [RemoteHostConnector] por host (uma conexão SSH
/// por host, reusada por todos os terminais daquele workspace).
///
/// A UI (rail) observa este controller pra listar os pins e o badge de estado;
/// o [CockpitViewModel] pede o gateway de terminal de um host por aqui.
class RemoteHostsController extends ChangeNotifier {
  RemoteHostsController(this._store);

  final RemoteHostsStore _store;

  /// Pergunta ao humano se confia na host key de um destino novo. A página
  /// pluga o dialog aqui no boot (mesmo padrão do prompt do túnel de banco);
  /// `null` = ninguém pra perguntar → host novo falha em vez de ser aceito
  /// em silêncio.
  HostKeyPrompt? hostKeyPrompt;
  final Map<String, RemoteHostConnector> _connectors = {};
  final MobileSshKeyStore _deviceKeys = MobileSshKeyStore();
  RemoteHostPasswordStore _passwords = RemoteHostPasswordStore();

  /// Troca o store de senhas. Só os testes usam: o construtor é registrado por
  /// tear-off no módulo (`RemoteHostsController.new`), e o auto_injector
  /// resolve parâmetros pelo grafo — acrescentar um aqui só para o teste
  /// cobraria um bind que não existe.
  @visibleForTesting
  set passwordStoreForTest(RemoteHostPasswordStore store) => _passwords = store;

  /// Linha `authorized_keys` da chave deste dispositivo (mobile): o usuário cola
  /// no `~/.ssh/authorized_keys` do host pra autorizar o iPad/Android. Gera a
  /// chave na 1ª chamada (guardada no Keychain).
  Future<String> devicePublicKey() => _deviceKeys.publicKeyLine();

  List<RemoteHost> get hosts => _store.hosts();

  /// Status de turno (spinner/chime) de TODOS os hosts remotos, mesclado. A VM
  /// assina e roteia por `paneId` pro mesmo caminho do status local (Wave G).
  final _turnStatus = StreamController<RemoteTurnStatus>.broadcast();
  Stream<RemoteTurnStatus> get turnStatus => _turnStatus.stream;

  /// Comandos da CLI `cockpit` de TODOS os hosts, mesclados — a VM assina e
  /// devolve ao `CockpitCliHandler`, o mesmo que atende a CLI local.
  final _cliCommands = StreamController<RemoteCliCommand>.broadcast();
  Stream<RemoteCliCommand> get cliCommands => _cliCommands.stream;

  RemoteHostConnector _connectorFor(
    RemoteHost host,
  ) => _connectors.putIfAbsent(host.id, () {
    final connector = RemoteHostConnector(
      host,
      localServerBinaryResolver: _resolveLocalServerBinary,
      // Senha (auth por senha) lida do Keychain sob demanda; null pra auth por
      // chave. Fica fora do JSON de hosts (decisão A).
      passwordResolver: host.auth == RemoteHostAuth.password
          ? () => _passwords.read(host.id)
          : null,
      // Indireção proposital: o prompt é plugado DEPOIS que os connectors já
      // podem ter nascido, então lê-lo na hora do uso (e não capturá-lo no
      // construtor) evita connector antigo com prompt nulo.
      hostKeyPrompt: (endpoint, fingerprint) async =>
          await hostKeyPrompt?.call(endpoint, fingerprint) ??
          HostKeyVerdict.reject,
    );
    connector.turnStatus.listen(_turnStatus.add);
    connector.cliCommands.listen(_cliCommands.add);
    // Fases notificam AQUI (e não só em terminalGateway): o badge e o botão
    // de reconectar precisam repintar mesmo em host sem aba de terminal
    // aberta — por exemplo enquanto o retry automático roda em segundo plano.
    connector.phases.listen((_) => notifyListeners());
    return connector;
  });

  /// Reconecta um host AGORA, ignorando o backoff em curso (botão da UI).
  ///
  /// A reconexão também acontece sozinha (o connector insiste indefinidamente,
  /// com intervalo crescente até 30s); isto é o atalho pra quando o usuário sabe
  /// que a rede/VPN já voltou e não quer esperar o próximo tique.
  Future<void> reconnect(String hostId) async {
    final connector = _connectors[hostId];
    if (connector == null) return;
    await connector.reconnectNow();
    notifyListeners();
  }

  /// O host NÃO está pronto para uso? Gate da faixa e do botão na UI.
  ///
  /// Cobre tudo que não é `connected` nem `idle`, e não só reconnecting/failed:
  /// uma abertura que fica pendurada em `connecting` (host inalcançável cujo
  /// socket não recusa, servidor remoto que não responde) é indistinguível de
  /// queda para quem está olhando a tela, e era justamente o estado que ficava
  /// sem aviso nenhum.
  bool isDisconnected(String hostId) => switch (phaseOf(hostId)) {
    RemoteHostPhase.connected || RemoteHostPhase.idle => false,
    _ => true,
  };

  /// Fase de conexão atual de um host (pro badge do rail). `idle` se nunca
  /// conectou.
  RemoteHostPhase phaseOf(String hostId) =>
      _connectors[hostId]?.phase ?? RemoteHostPhase.idle;

  Stream<RemoteHostPhase>? phasesOf(String hostId) =>
      _connectors[hostId]?.phases;

  /// Gateway de terminal ligado ao [host] (via SSH). Reusa o connector do
  /// host; a UI é notificada das fases pra pintar loading/erro.
  TerminalGateway terminalGateway(RemoteHost host) =>
      // A assinatura de `phases` vive no _connectorFor (uma por host). Assinar
      // aqui somava um listener NUNCA cancelado a cada aba aberta.
      RemoteHostTerminalGateway(_connectorFor(host));

  /// Serviço de arquivos do host (picker de pasta remota). Conecta se preciso.
  Future<RemoteFileService> fileServiceFor(RemoteHost host) =>
      _connectorFor(host).fileService();

  /// Serviço git do host (source control remoto). Conecta se preciso.
  Future<RemoteGitService> gitServiceFor(RemoteHost host) =>
      _connectorFor(host).gitService();

  /// Serviço de terminal do host (Task Run remoto, plano 58). Conecta se
  /// preciso; mesma conexão SSH dos demais serviços.
  Future<RemoteTerminalService> terminalServiceFor(RemoteHost host) =>
      _connectorFor(host).ensure();

  /// Serviço de DB do host (queries remotas). Conecta se preciso.
  Future<RemoteDbService> dbServiceFor(RemoteHost host) =>
      _connectorFor(host).dbService();

  Future<void> addHost({
    required String name,
    required String sshTarget,
    int port = 22,
    RemoteHostAuth auth = RemoteHostAuth.key,
    String? password,
    String? identityFile,
  }) async {
    final id = _nextId();
    final host = RemoteHost(
      id: id,
      name: name,
      sshTarget: sshTarget,
      port: port,
      auth: auth,
      identityFile: identityFile,
    );
    if (auth == RemoteHostAuth.password) {
      await _passwords.write(id, password);
    }
    await _store.save(host);
    notifyListeners();
  }

  /// Há senha guardada no Keychain para este host? (pro dialog de edição saber
  /// se pode manter a atual sem re-digitar.)
  Future<bool> hasStoredPassword(String hostId) async =>
      (await _passwords.read(hostId))?.isNotEmpty ?? false;

  /// Pins de workspace remoto (pastas fixadas).
  List<RemoteWorkspacePin> get pins => _store.pins();

  /// Fixa uma pasta [path] do host [hostId] como workspace (idempotente por
  /// (host, pasta)); devolve o pin.
  Future<RemoteWorkspacePin> addPin({
    required String hostId,
    required String path,
    String realmId = 'default',
    int order = 0,
  }) async {
    final name = _basename(path);
    final pin = RemoteWorkspacePin(
      id: RemoteWorkspacePin.idFor(hostId, path),
      hostId: hostId,
      path: path,
      name: name.isEmpty ? path : name,
      realmId: realmId,
      order: order,
    );
    await _store.savePin(pin);
    notifyListeners();
    return pin;
  }

  Future<void> removePin(String id) async {
    await _store.removePin(id);
    notifyListeners();
  }

  /// Atualiza a personalização de um pin (nome/cor/imagem de fundo) — o que as
  /// Configurações do workspace remoto editam. Nome vazio é ignorado; passar
  /// `imagePath: null` **remove** a imagem (a sentinela do copyWith distingue
  /// "não mexer" de "limpar"). Pin inexistente = no-op silencioso.
  Future<void> updatePin(
    String id, {
    String? name,
    int? colorValue,
    Object? imagePath = RemoteWorkspacePin.unsetImage,
    String? realmId,
    int? order,
  }) async {
    RemoteWorkspacePin? pin;
    for (final p in _store.pins()) {
      if (p.id == id) {
        pin = p;
        break;
      }
    }
    if (pin == null) return;
    final cleanName = name?.trim();
    await _store.savePin(
      pin.copyWith(
        name: (cleanName != null && cleanName.isNotEmpty) ? cleanName : null,
        colorValue: colorValue,
        imagePath: imagePath,
        realmId: realmId,
        order: order,
      ),
    );
    notifyListeners();
  }

  /// Nome do pin a partir do caminho do HOST — que pode ser Windows.
  /// Procurar só por `/` fazia `C:\\Users\\jacob\\projeto` virar o nome inteiro
  /// do workspace, em vez de `projeto`.
  static String _basename(String path) => remotePathBasename(path);

  /// Edita nome, endpoint (host/porta) e/ou auth de um host (mesmo id). Qualquer
  /// mudança de endpoint/auth derruba a conexão viva (recriada no próximo uso).
  /// [password] `null` mantém a senha guardada; string nova a substitui.
  Future<void> editHost(
    String id, {
    String? name,
    String? sshTarget,
    int? port,
    RemoteHostAuth? auth,
    String? password,
    String? identityFile,
  }) async {
    RemoteHost? host;
    for (final h in _store.hosts()) {
      if (h.id == id) {
        host = h;
        break;
      }
    }
    if (host == null) return;
    final newName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : host.name;
    final newTarget = (sshTarget?.trim().isNotEmpty ?? false)
        ? sshTarget!.trim()
        : host.sshTarget;
    final newPort = port ?? host.port;
    final newAuth = auth ?? host.auth;
    // Trocar pra senha limpa a chave: guardá-la seria estado morto que
    // reaparece se o usuário voltar pra auth por chave.
    final newIdentity = newAuth == RemoteHostAuth.password
        ? null
        : (identityFile ?? host.identityFile);

    if (newTarget != host.sshTarget ||
        newPort != host.port ||
        newAuth != host.auth ||
        newIdentity != host.identityFile) {
      // Endpoint/auth mudou → a conexão atual não vale mais.
      await _connectors.remove(id)?.dispose();
    }
    await _store.save(
      host.copyWith(
        name: newName,
        sshTarget: newTarget,
        port: newPort,
        auth: newAuth,
        identityFile: newIdentity,
      ),
    );
    notifyListeners();

    // Senha DEPOIS do save, e sem segurar a operação: o Keychain é acessório
    // (a fonte da verdade dos hosts é o JSON) e é IPC com um serviço do
    // sistema, que pode falhar ou não responder. Quando ele vinha ANTES e
    // travava, editar simplesmente não salvava — sem erro na tela, porque o
    // future do onPressed é descartado.
    unawaited(
      newAuth == RemoteHostAuth.password
          ? (password != null && password.isNotEmpty
                ? _passwords.write(id, password)
                : Future<void>.value())
          : _passwords.remove(id),
    );
  }

  /// Remove o host, seus workspaces (pins) e encerra a conexão.
  Future<void> removeHost(String id) async {
    for (final pin in _store.pins().where((p) => p.hostId == id).toList()) {
      await _store.removePin(pin.id);
    }
    await _connectors.remove(id)?.dispose();
    await _store.remove(id);
    notifyListeners();
    // Limpeza da senha por último e sem esperar — ver editHost.
    unawaited(_passwords.remove(id));
  }

  // id determinístico simples (Date.now/Random não estão disponíveis em alguns
  // caminhos; aqui é UI, mas mantemos previsível): maior sufixo + 1.
  String _nextId() {
    final existing = hosts
        .map((h) => int.tryParse(h.id) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return '${existing + 1}';
  }

  /// Fonte local do bootstrap remoto. [arch] vem do `uname -sm` do HOST, não
  /// desta máquina — o bundle macOS traz as duas fatias do servidor.
  String? _resolveLocalServerBinary({String? arch}) =>
      SidecarTerminalConnector.resolveServerBundleBinary(arch: arch);

  @override
  void dispose() {
    for (final connector in _connectors.values) {
      connector.dispose();
    }
    _connectors.clear();
    unawaited(_turnStatus.close());
    unawaited(_cliCommands.close());
    super.dispose();
  }
}
