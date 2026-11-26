import '../document/worktree_document_host.dart';
import 'file_viewer_session.dart';

/// Ephemeral owned presentation; never part of the portable orchestration JSON.
class OrchestrationFilePresentation {
  OrchestrationFilePresentation({
    required this.id,
    required this.path,
    required this.terminalId,
    required this.host,
    this.line,
    this.onPanelCall,
  });
  final String id, path, terminalId;
  final WorktreeDocumentHost host;
  final int? line;
  final Future<Map<String, Object?>> Function(String, String)? onPanelCall;
  FileViewerSession? viewer;
  bool get dirty => viewer?.dirty ?? false;
}
