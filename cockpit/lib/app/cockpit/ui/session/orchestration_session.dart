import 'pane_item.dart';
import 'package:path/path.dart' as paths;
import '../services/orchestration_controller.dart';

class OrchestrationSession extends PaneItem {
  OrchestrationSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.controller,
  }) {
    controller.addListener(notifyListeners);
  }
  @override
  final String id;
  @override
  final String projectId;
  String path;
  final OrchestrationController controller;
  @override
  String get title => 'Agent Orchestration';
  @override
  String get workingDirectory => paths.dirname(path);
  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    controller.dispose();
    super.dispose();
  }
}
