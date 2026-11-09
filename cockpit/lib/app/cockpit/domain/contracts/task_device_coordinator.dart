import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_device_snapshot.dart';

/// Device selection exposed to the UI and the internal CLI.
abstract class TaskDeviceCoordinator {
  bool offers(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  });

  TaskRunAction? sessionAction(
    TaskDefinition def, {
    required String? profileName,
    required String sessionUrl,
    required bool remote,
  });

  TaskDeviceSnapshot snapshot(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  });

  Future<bool> refresh(TaskDefinition def, {required String? profileName});

  Future<void> select(TaskDefinition def, String deviceId);

  List<String> previewArgs(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  });

  Future<TaskLaunchPlan> plan(
    TaskDefinition def, {
    required String? profileName,
    required bool remote,
  });
}
