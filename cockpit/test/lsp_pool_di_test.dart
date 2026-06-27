import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Garante que o `LspServerPool` (e a `LspClientFactory` que ele injeta) resolvem
/// pelo grafo de DI a partir de uma feature — o parser do auto_injector não pula
/// parâmetro opcional com default, então o `ProjectRootFinder` NÃO pode estar no
/// construtor do pool (regressão que estourava no build da rota).
void main() {
  testWidgets('LspServerPool resolve via core upward', (tester) async {
    final core = buildCoreModule(
      config: const PiSpawnConfig(executable: 'pi'),
    );
    final feature = createModule(
      path: '/',
      register: (c) => c.route(
        '/',
        child: (ctx, s) =>
            Text('lsp:${inject<LspServerPool>().runtimeType}'),
      ),
    );
    final app = createModule(
      register: (c) => c
        ..module(core)
        ..module(feature),
    );

    final boot = bootstrapModule(app);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: modularRouterConfig(
          boot.routes,
          injector: boot.injector,
          manager: boot.manager,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lsp:LspServerPool'), findsOneWidget);
  });
}
