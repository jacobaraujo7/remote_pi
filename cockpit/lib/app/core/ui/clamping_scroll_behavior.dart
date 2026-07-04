import 'package:shadcn_flutter/shadcn_flutter.dart';

/// `ScrollBehavior` global do app: força [ClampingScrollPhysics] em **todos** os
/// scrollables (ListView, SingleChildScrollView, Scrollable…). Estende o
/// [ShadcnScrollBehavior] (mantém scrollbar + overscroll indicator do shadcn) e
/// só troca a física — o default do shadcn é [BouncingScrollPhysics], cujo
/// bounce/overscroll no desktop parece uma "animação estranha" no fim da lista.
///
/// Aplicado uma vez em `ShadcnApp.router(scrollBehavior: ...)`; qualquer novo
/// scrollable herda daqui sem precisar setar `physics:` na mão. Widgets que já
/// fazem `ScrollConfiguration.of(context).copyWith(...)` preservam esta física
/// (o copyWith não mexe em `getScrollPhysics`).
class ClampingScrollBehavior extends ShadcnScrollBehavior {
  const ClampingScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
