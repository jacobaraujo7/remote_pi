import 'dart:async';
import 'dart:convert';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';

class AttachmentTerminalGateway extends TerminalGateway {
  final bytes = <int>[];
  final _output = StreamController<List<int>>();
  String get text => utf8.decode(bytes);
  @override
  Stream<List<int>> get output => _output.stream;
  @override
  void write(List<int> data) => bytes.addAll(data);
  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const {},
  }) {}
  @override
  void resize(int rows, int columns) {}
  @override
  void acknowledgeOutput() {}
  @override
  Future<void> kill() => _output.close();
}
