import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/entities/pair_event.dart';
import 'package:flutter/foundation.dart';

/// Etapa atual do fluxo de pareamento (dirige o que o dialog mostra).
enum PairStage { connecting, showingCode, paired, failed }

/// Estado do dialog de pareamento. Cria uma [PairingGateway] efêmera por
/// tentativa (via a factory injetada), inicia no [start] e mata no [dispose].
/// Traduz os [PairEvent] em [stage] + dados. [retry] reabre uma nova sessão.
class PairingController extends ChangeNotifier {
  PairingController(this._createGateway);

  final PairingGateway Function() _createGateway;

  PairingGateway? _gateway;
  StreamSubscription<PairEvent>? _sub;

  PairStage stage = PairStage.connecting;
  PairCodeReady? code;
  String? error;
  String? pairedName;

  bool _disposed = false;

  /// `true` assim que um aparelho parear — o dialog observa pra fechar sozinho.
  bool get isPaired => stage == PairStage.paired;

  Future<void> start() async {
    // Encerra uma sessão anterior (retry) antes de abrir outra.
    await _sub?.cancel();
    await _gateway?.cancel();

    stage = PairStage.connecting;
    code = null;
    error = null;
    _notify();

    final gateway = _createGateway();
    _gateway = gateway;
    _sub = gateway.events.listen(_onEvent, onError: (Object e) => _fail('$e'));
    await gateway.start(ttl: const Duration(seconds: 120));
  }

  Future<void> retry() => start();

  void _onEvent(PairEvent event) {
    switch (event) {
      case PairCodeReady():
        code = event;
        error = null;
        stage = PairStage.showingCode;
        _notify();
      case PairDevicePaired():
        pairedName = event.name;
        stage = PairStage.paired;
        _notify();
      case PairFailed():
        _fail(event.message);
    }
  }

  void _fail(String message) {
    // Já pareou? Ignora ruído de encerramento do processo.
    if (stage == PairStage.paired) return;
    error = message;
    stage = PairStage.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _gateway?.cancel();
    super.dispose();
  }
}
