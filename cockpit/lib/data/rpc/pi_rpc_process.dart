import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/data/adapters/rpc_data_mapper.dart';
import 'package:cockpit/data/adapters/rpc_event_mapper.dart';
import 'package:cockpit/data/rpc/jsonl_line_splitter.dart';
import 'package:cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/domain/result.dart';

/// Implementação do [RpcProcessGateway] sobre `dart:io` `Process`.
///
/// Dono do ciclo de vida do child `pi --mode rpc`: spawn, escrita no stdin,
/// parse do stdout (via [JsonlLineSplitter] + [RpcEventMapper]), detecção de
/// saída e kill limpo. **Mata o child no `dispose` (sem órfão).**
///
/// MVP single-pane: um processo por instância. Validado empiricamente no spike
/// do plano 37 — ver `docs/rpc-protocol.md`.
class PiRpcProcess implements RpcProcessGateway {
  PiRpcProcess(this._config);

  final PiSpawnConfig _config;
  final RpcEventMapper _mapper = const RpcEventMapper();
  final RpcDataMapper _dataMapper = const RpcDataMapper();
  final StreamController<RpcEvent> _events = StreamController<RpcEvent>.broadcast();

  /// Requests pendentes aguardando a `response` com o `id` correspondente.
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  int _seq = 0;

  /// Serializa as escritas no stdin. Dois `write`/`flush` concorrentes (ex.:
  /// `_loadControls` do boot + `switch_session` da restauração) estouram
  /// `Bad state: StreamSink is bound to a stream`. Cada escrita espera a
  /// anterior terminar.
  Future<void> _writeChain = Future<void>.value();

  Process? _process;
  String? _cwd;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  @override
  Stream<RpcEvent> get events => _events.stream;

  @override
  bool get isRunning => _process != null;

  @override
  String? get workingDirectory => _cwd;

  @override
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (_process != null) {
      return const Failure(
        RpcError('Um agente já está em execução nesta sessão.'),
      );
    }
    try {
      // Funde com o ambiente do processo pai para preservar PATH/HOME/etc.
      final env = environment != null
          ? {...Platform.environment, ...environment}
          : null;
      final process = await Process.start(
        _config.executable,
        _config.spawnArgs(),
        workingDirectory: workingDirectory,
        environment: env,
      );
      _process = process;
      _cwd = workingDirectory;

      _stdoutSub = process.stdout
          .transform(const JsonlLineSplitter())
          .listen(_onStdoutLine, onError: _onStreamError);

      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: _onStreamError);

      // Detecta saída/crash sem bloquear.
      unawaited(process.exitCode.then(_onExit));

      return const Success(null);
    } catch (error, stackTrace) {
      _process = null;
      _cwd = null;
      return Failure(
        RpcError(
          'Falha ao spawnar "${_config.executable}": $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  }) async {
    final process = _process;
    if (process == null) {
      return const Failure(RpcError('Nenhum agente em execução.'));
    }
    final command = <String, dynamic>{'type': 'prompt', 'message': message};
    if (steerIfBusy) command['streamingBehavior'] = 'steer';
    if (images.isNotEmpty) {
      command['images'] = <Map<String, String>>[
        for (final image in images)
          {'type': 'image', 'data': image.data, 'mimeType': image.mimeType},
      ];
    }
    try {
      await _writeLine('${jsonEncode(command)}\n');
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        RpcError(
          'Falha ao enviar prompt: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> kill() async {
    final process = _process;
    if (process == null) return;

    // Caminho gracioso (provado no spike): fechar o stdin já faz o pi sair 0.
    try {
      await process.stdin.close();
    } catch (_) {
      // stdin pode já estar fechado.
    }

    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    // _onExit cuida da limpeza das refs e emite RpcProcessExit.
  }

  @override
  void dispose() {
    // Rede de segurança síncrona (chamado pelo injector no shutdown). O caminho
    // gracioso de verdade é [kill]; aqui garantimos que nada fica órfão.
    final process = _process;
    if (process != null) {
      try {
        process.stdin.close();
      } catch (_) {}
      process.kill(ProcessSignal.sigterm);
    }
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (!_events.isClosed) _events.close();
  }

  void _onStdoutLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        _emit(RpcUnknown('<non-object>', line));
        return;
      }
      // Resposta de um request nosso (correlacionada por id) → completa o
      // Completer e NÃO emite como evento.
      if (decoded['type'] == 'response') {
        final id = decoded['id'];
        if (id is String) {
          final completer = _pending.remove(id);
          if (completer != null) {
            completer.complete(decoded);
            return;
          }
        }
      }
      _emit(_mapper.fromJson(decoded));
    } catch (_) {
      _emit(RpcUnknown('<parse-error>', line));
    }
  }

  /// Escreve uma linha no stdin, **serializada** com as demais (ver [_writeChain]).
  /// Aguarda a escrita anterior antes de tocar no sink, evitando o
  /// `StreamSink is bound to a stream` de `write`/`flush` concorrentes.
  Future<void> _writeLine(String line) {
    final result = _writeChain.then((_) async {
      final process = _process;
      if (process == null) {
        throw const RpcError('Nenhum agente em execução.');
      }
      process.stdin.write(line);
      await process.stdin.flush();
    });
    // A corrente segue viva mesmo se uma escrita falhar (não propaga o erro
    // pro próximo da fila — quem chamou já recebe a exceção via `result`).
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Envia um comando com `id` e aguarda a `response` correspondente.
  /// Lança [RpcError] em falha/timeout — os métodos públicos embrulham em [Result].
  Future<Map<String, dynamic>> _request(Map<String, dynamic> command) async {
    final process = _process;
    if (process == null) {
      throw const RpcError('Nenhum agente em execução.');
    }
    final id = 'req-${++_seq}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      await _writeLine(
        '${jsonEncode(<String, dynamic>{...command, 'id': id})}\n',
      );
    } catch (error, stackTrace) {
      _pending.remove(id);
      throw RpcError(
        'Falha ao enviar ${command['type']}: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final response = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw RpcError('Timeout aguardando resposta de ${command['type']}.');
      },
    );
    if (response['success'] != true) {
      throw RpcError(
        '${command['type']} falhou: ${response['error'] ?? "erro desconhecido"}',
      );
    }
    return response;
  }

  Future<Result<T, RpcError>> _guard<T>(Future<T> Function() body) async {
    try {
      return Success(await body());
    } on RpcError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(RpcError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<Result<List<PiModel>, RpcError>> availableModels() => _guard(() async {
    final response = await _request({'type': 'get_available_models'});
    return _dataMapper.models(response['data']);
  });

  @override
  Future<Result<List<PiCommand>, RpcError>> commands() => _guard(() async {
    final response = await _request({'type': 'get_commands'});
    return _dataMapper.commands(response['data']);
  });

  @override
  Future<Result<AgentSnapshot, RpcError>> state() => _guard(() async {
    final response = await _request({'type': 'get_state'});
    return _dataMapper.state(response['data']);
  });

  @override
  Future<Result<PiModel, RpcError>> setModel(PiModel model) => _guard(() async {
    final response = await _request({
      'type': 'set_model',
      'provider': model.provider,
      'modelId': model.id,
    });
    return _dataMapper.model(response['data']) ?? model;
  });

  @override
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level) =>
      _guard(() async {
        await _request({'type': 'set_thinking_level', 'level': level.wire});
      });

  @override
  Future<Result<ContextUsage?, RpcError>> sessionStats() => _guard(() async {
    final response = await _request({'type': 'get_session_stats'});
    return _dataMapper.contextUsage(response['data']);
  });

  @override
  Future<Result<void, RpcError>> abort() => _guard(() async {
    await _request({'type': 'abort'});
  });

  @override
  Future<Result<void, RpcError>> newSession() => _guard(() async {
    await _request({'type': 'new_session'});
  });

  @override
  Future<Result<void, RpcError>> compact() => _guard(() async {
    await _request({'type': 'compact'});
  });

  @override
  Future<Result<void, RpcError>> switchSession(String sessionPath) =>
      _guard(() async {
        await _request({
          'type': 'switch_session',
          'sessionPath': sessionPath,
        });
      });

  @override
  Future<Result<List<TranscriptMessage>, RpcError>> getMessages() =>
      _guard(() async {
        final response = await _request({'type': 'get_messages'});
        return _dataMapper.transcriptMessages(response['data']);
      });

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _emit(RpcDiagnostic(line));
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _emit(RpcDiagnostic('stream error: $error'));
  }

  void _onExit(int code) {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _cwd = null;
    // Não deixe requests pendentes pendurados quando o processo morre.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(RpcError('Processo encerrou (code=$code).'));
      }
    }
    _pending.clear();
    _emit(RpcProcessExit(code));
  }

  void _emit(RpcEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
