import 'package:cockpit/app/core/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bind de nível de FEATURE que depende de uma dep root-owned do core — o cenário
/// exato do cockpit (RpcGatewayFactory/EnvironmentProbe etc. dependem do
/// PiSpawnConfig que mora no core).
class _RpcLike {
  _RpcLike(this.config);
  final PiSpawnConfig config;
}

/// Prova de runtime do que o flutter_modular 7.1.0 destravou (resolveUpward):
/// um `addLazySingleton<T>(T.new)` num módulo de feature (com `path`) resolve a
/// dep do core UPWARD. Em < 7.1.0 isso estourava "PiSpawnConfig not registered"
/// no build da rota. É o que valida o refactor que tirou os `.new` config-deps
/// do `addInstance(X(config))` threadado para resolução pelo grafo.
void main() {
  testWidgets('feature addLazySingleton(.new) resolve dep do core upward', (
    tester,
  ) async {
    final core = createModule(
      register: (c) =>
          c.addInstance<PiSpawnConfig>(const PiSpawnConfig(executable: 'pi')),
    );
    final feature = createModule(
      path: '/',
      register: (c) => c
        ..addLazySingleton<_RpcLike>(_RpcLike.new)
        ..route(
          '/',
          child: (ctx, s) =>
              Text('exe:${inject<_RpcLike>().config.executable}'),
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

    // Chegar aqui já prova: se a resolução upward falhasse, o build da rota teria
    // estourado "PiSpawnConfig not registered" antes do render.
    expect(find.text('exe:pi'), findsOneWidget);
  });
}
