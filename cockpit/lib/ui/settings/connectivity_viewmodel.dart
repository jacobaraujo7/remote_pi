import 'package:cockpit/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/domain/contracts/relay_gateway.dart';
import 'package:cockpit/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/domain/entities/paired_device.dart';
import 'package:cockpit/ui/settings/pairing_controller.dart';
import 'package:cockpit/ui/settings/revoke_controller.dart';
import 'package:flutter/foundation.dart';

/// Estado de carregamento de uma seção da Conectividade.
enum ConnLoad { idle, loading, ready, error }

/// Resultado do "Verificar" do relay (`GET /health`).
enum HealthState { unknown, checking, healthy, unhealthy }

/// Estado da aba **Conectividade** das Configurações: relay global (ler/definir)
/// + aparelhos pareados (listar) via [RelayGateway] (CLI `remote-pi`). Pareamento
/// e revoke sobem um `pi --mode rpc` efêmero via as factories de [PairingGateway]
/// / [RevokeGateway] (cada dialog tem sua instância). Carregado sob demanda.
class ConnectivityViewModel extends ChangeNotifier {
  ConnectivityViewModel(
    this._relay,
    this._pairingGatewayFactory,
    this._revokeGatewayFactory,
  );

  final RelayGateway _relay;
  final PairingGateway Function() _pairingGatewayFactory;
  final RevokeGateway Function() _revokeGatewayFactory;

  /// Controller pro dialog de pareamento — instância nova por dialog (cada uma
  /// dona do seu processo efêmero).
  PairingController newPairingController() =>
      PairingController(_pairingGatewayFactory);

  /// Controller pro dialog de revoke — instância nova por dialog.
  RevokeController newRevokeController() =>
      RevokeController(_revokeGatewayFactory());

  // ---- relay ----------------------------------------------------------------
  ConnLoad relayLoad = ConnLoad.idle;
  String? relayUrl;
  String? relayError;
  bool savingRelay = false;

  // saúde do relay (`GET /health`)
  HealthState healthState = HealthState.unknown;
  String? healthMessage;

  // ---- aparelhos ------------------------------------------------------------
  ConnLoad devicesLoad = ConnLoad.idle;
  List<PairedDevice> devices = const <PairedDevice>[];
  String? devicesError;

  bool _disposed = false;

  /// Carrega relay + aparelhos em paralelo. Chamado quando a aba abre.
  Future<void> load() => Future.wait(<Future<void>>[loadRelay(), loadDevices()]);

  Future<void> loadRelay() async {
    relayLoad = ConnLoad.loading;
    relayError = null;
    _notify();
    final result = await _relay.currentRelay();
    result.fold(
      (url) {
        relayUrl = url;
        relayLoad = ConnLoad.ready;
      },
      (error) {
        relayError = error.message;
        relayLoad = ConnLoad.error;
      },
    );
    _notify();
  }

  /// Define a URL do relay. Retorna `true` no sucesso (a view limpa o "dirty").
  Future<bool> setRelay(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == relayUrl) return false;
    savingRelay = true;
    relayError = null;
    _notify();
    final result = await _relay.setRelay(trimmed);
    final ok = result.fold((_) => true, (error) {
      relayError = error.message;
      return false;
    });
    if (ok) {
      relayUrl = trimmed;
      // O check anterior valia pra outra URL → reseta.
      healthState = HealthState.unknown;
      healthMessage = null;
    }
    savingRelay = false;
    _notify();
    return ok;
  }

  /// Verifica se o relay em [url] está no ar (`GET /health`).
  Future<void> checkRelay(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      healthState = HealthState.unhealthy;
      healthMessage = 'Set the relay URL first.';
      _notify();
      return;
    }
    healthState = HealthState.checking;
    healthMessage = null;
    _notify();
    final result = await _relay.checkHealth(trimmed);
    result.fold(
      (_) {
        healthState = HealthState.healthy;
        healthMessage = null;
      },
      (error) {
        healthState = HealthState.unhealthy;
        healthMessage = error.message;
      },
    );
    _notify();
  }

  /// Zera o resultado do check (ex.: usuário começou a editar a URL).
  void clearHealth() {
    if (healthState == HealthState.unknown && healthMessage == null) return;
    healthState = HealthState.unknown;
    healthMessage = null;
    _notify();
  }

  Future<void> loadDevices() async {
    devicesLoad = ConnLoad.loading;
    devicesError = null;
    _notify();
    final result = await _relay.listDevices();
    result.fold(
      (list) {
        devices = list;
        devicesLoad = ConnLoad.ready;
      },
      (error) {
        devicesError = error.message;
        devicesLoad = ConnLoad.error;
      },
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
