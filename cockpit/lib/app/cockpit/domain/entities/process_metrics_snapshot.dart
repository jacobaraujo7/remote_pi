/// A point-in-time observation of one terminal's root process.
/// Null values mean the platform could not measure the metric.
class ProcessMetricsSnapshot {
  final int pid;
  final double? cpuPercent;
  final int? rssBytes;
  final DateTime collectedAt;
  final String source;
  final String? unavailableReason;

  const ProcessMetricsSnapshot({
    required this.pid,
    required this.cpuPercent,
    required this.rssBytes,
    required this.collectedAt,
    required this.source,
    this.unavailableReason,
  });

  bool get hasMeasurements => cpuPercent != null || rssBytes != null;
}
