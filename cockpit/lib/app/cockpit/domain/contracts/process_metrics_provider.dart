import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';

/// Reads metrics for a process on the machine that owns its PID.
abstract class ProcessMetricsProvider {
  Future<ProcessMetricsSnapshot> read(int pid);
}
