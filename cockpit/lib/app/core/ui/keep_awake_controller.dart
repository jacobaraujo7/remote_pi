import 'dart:async';

import 'package:cockpit_keepawake/cockpit_keepawake.dart';
import 'package:flutter/foundation.dart';

/// Estado do botão "Keep awake" do rodapé do rail: segura o sleep por
/// inatividade desta máquina enquanto ligado (host de acesso remoto).
///
/// **Efêmero por decisão**: nada persiste; reabrir o app volta desligado. O
/// pior cenário é esquecer um notebook acordado numa mochila, e "reiniciou,
/// desligou" elimina isso de graça. App-scoped (provido no bootstrapper) porque
/// a assertion é da máquina, não de um workspace nem de uma rota.
///
/// Enquanto ligado, sonda a fonte de energia a cada [pollInterval]: a UI
/// muda de cor quando está queimando bateria.
class KeepAwakeController extends ChangeNotifier {
  KeepAwakeController({
    KeepAwake? keepAwake,
    PowerSourceProbe? powerProbe,
    this.pollInterval = const Duration(seconds: 30),
  }) : _keepAwake = keepAwake ?? KeepAwake.platform(),
       _powerProbe = powerProbe ?? PowerSourceProbe.platform();

  final KeepAwake _keepAwake;
  final PowerSourceProbe _powerProbe;
  final Duration pollInterval;

  Timer? _poll;
  PowerSource _power = PowerSource.unknown;
  bool _busy = false;

  /// `false` = plataforma sem implementação → o botão nem aparece.
  bool get isSupported => _keepAwake.isSupported;

  bool get isActive => _keepAwake.isActive;

  /// Fonte de energia lida na última sonda (só relevante com [isActive]).
  PowerSource get power => _power;

  bool get onBattery => isActive && _power == PowerSource.battery;

  Future<void> toggle() => isActive ? disable() : enable();

  Future<void> enable() async {
    if (_busy || isActive) return;
    _busy = true;
    try {
      final ok = await _keepAwake.acquire();
      if (ok) {
        await _readPower();
        _poll = Timer.periodic(pollInterval, (_) => _readPower());
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disable() async {
    if (_busy || !isActive) return;
    _busy = true;
    try {
      _poll?.cancel();
      _poll = null;
      await _keepAwake.release();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _readPower() async {
    final p = await _powerProbe.read();
    if (p == _power) return;
    _power = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    // Fire-and-forget: o filho também morre com o processo (`caffeinate -w`).
    unawaited(_keepAwake.release());
    super.dispose();
  }
}
