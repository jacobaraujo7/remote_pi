import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dep root-owned, registrada no core via `addInstance`.
class _CoreDep {
  const _CoreDep(this.name);
  final String name;
}

/// Bind de nível de FEATURE que depende de uma dep root-owned do core — o cenário
/// exato do cockpit (binds `.new` de feature que resolvem algo do core).
class _FeatureBind {
  _FeatureBind(this.dep);
  final _CoreDep dep;
}

/// Prova de runtime do que o flutter_modular 7.1.0 destravou (resolveUpward):
/// um `addLazySingleton<T>(T.new)` num módulo de feature (com `path`) resolve a
/// dep do core UPWARD. Em < 7.1.0 isso estourava "not registered" no build da
/// rota. É o que valida os binds `.new` de feature resolvidos pelo grafo.
void main() {
  testWidgets('feature addLazySingleton(.new) resolve dep do core upward', (
    tester,
  ) async {
    final core = createModule(
      register: (c) => c.addInstance<_CoreDep>(const _CoreDep('core')),
    );
    final feature = createModule(
      path: '/',
      register: (c) => c
        ..addLazySingleton<_FeatureBind>(_FeatureBind.new)
        ..route(
          '/',
          child: (ctx, s) => Text('dep:${inject<_FeatureBind>().dep.name}'),
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
    // estourado "not registered" antes do render.
    expect(find.text('dep:core'), findsOneWidget);
  });
}
