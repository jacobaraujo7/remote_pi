import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import '../../../core/domain/result.dart';
import '../../domain/entities/workspace_graph.dart';
import '../session/pane_item.dart';

/// Rendering/actions for an explicit graph context. It deliberately exposes no
/// workspace terminal inventory: a renderer can only resolve its saved boxes.
abstract interface class WorkspaceGraphContext implements Listenable {
  String? get selectedProjectId;
  String? get selectedDisplayTitle;
  bool get selectedRemoteDisconnected;
  List<GraphBox> get graphBoxes;
  List<GraphLink> get graphLinks;
  List<GraphObservedLink> get graphTraffic;
  List<GraphUnresolvedPeer> get graphUnresolvedPeers;
  List<GraphSubagent> get graphSubagents;
  PaneItem? session(String id);
  GraphBox? graphBoxForTab(String tabId);
  String ensureGraphBoxForTab(PaneItem session, Offset position);
  void moveGraphBox(String boxId, Offset position);
  void addGraphLink(String from, String to);
  void removeGraphLink(String from, String to);
  void selectWorkspaceBox(String boxId, {bool configure = false});
  void openBoxInTerminals(String boxId);
  Future<Result<String, String>> openBoxShell(
    String boxId, {
    String? workspaceId,
  });
  FutureOr<Result<String, String>> createGraphBox({
    required String title,
    required String role,
    required String harness,
    required String model,
    required Offset position,
  });
  FutureOr<Result<String, String>> configureGraphBox({
    required String boxId,
    String? title,
    required String role,
    required String harness,
    required String model,
  });
  FutureOr<Result<String, String>> relaunchGraphBox(
    String boxId, {
    String? workspaceId,
  });
  FutureOr<Result<String, String>> startGraphHandoff(
    String boxId, {
    String? workspaceId,
  });
}
