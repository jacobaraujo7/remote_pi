// Contrato do parser de linhas (plano 66, decisão 12): UMA implementação em
// `data/telemetry/line_parser/`, usada por task, wrapper e (depois) VM
// Service. É stateful por run porque blocos de erro (stack trace) atravessam
// várias linhas e "repetido N×" referencia o evento anterior.

import '../entities/telemetry_event.dart';

/// Configuração por workspace (vem do `.cockpit/telemetry.json`, opcional).
class TelemetryParserConfig {
  const TelemetryParserConfig({
    this.unwrap = const [],
    this.projectRoots = const [],
    this.projectFrames = const [],
  });

  /// Regexes extras removidos do início de cada linha (docker compose,
  /// concurrently...), além dos embutidos.
  final List<RegExp> unwrap;

  /// Roots absolutas do workspace; frame cujo caminho cai numa delas é
  /// "do projeto".
  final List<String> projectRoots;

  /// Prefixos relativos extras considerados do projeto (`packages/`).
  final List<String> projectFrames;
}

/// Parser incremental: recebe linhas já separadas de UM run e devolve os
/// eventos prontos. Chame [flush] no fim do run pra fechar bloco pendente.
abstract class TelemetryLineParser {
  /// Processa uma linha (sem `\n`). [offset] é o índice dela no scrollback
  /// da aba, quando conhecido. Pode devolver zero, um ou mais eventos (um
  /// bloco de stack só sai quando termina).
  List<TelemetryEvent> feed(
    String line, {
    required TelemetryStream stream,
    required DateTime at,
    int? offset,
  });

  /// Fecha qualquer bloco pendente e devolve o que faltava.
  List<TelemetryEvent> flush();
}

/// Cria um parser por run (precisa do `runId` pra carimbar os eventos).
abstract class TelemetryLineParserFactory {
  TelemetryLineParser create({
    required String runId,
    TelemetryParserConfig config = const TelemetryParserConfig(),
  });
}
