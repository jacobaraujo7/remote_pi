import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Aba do **collection browser Mongo** (plano 53): documentos de uma
/// collection com filter bar + CRUD. Sem arquivo (decisão A — o estado é
/// conn + collection + filtro efêmero); o estado de view vive no side-car do
/// `DatabaseViewModel`.
class MongoBrowserSession extends PaneItem {
  MongoBrowserSession({
    required this.id,
    required this.projectId,
    required this.connName,
    required this.collection,
    required this.workingDirectory,
  });

  @override
  final String id;
  @override
  final String projectId;

  final String connName;
  final String collection;

  @override
  final String workingDirectory;

  @override
  String get title => '$collection ($connName)';

  /// Filtro semeado de fora (CLI `cockpit mongo browse --filter`, decisão E):
  /// cai na filter bar visível — o widget montado escuta a sessão e aplica;
  /// no mount, o initState consome o valor pendente.
  String? seedFilter;

  void requestFilter(String filter) {
    seedFilter = filter;
    notifyListeners();
  }

  /// Consome o seed pendente (uma vez).
  String? takeSeedFilter() {
    final f = seedFilter;
    seedFilter = null;
    return f;
  }
}
