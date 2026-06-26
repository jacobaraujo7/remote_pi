import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prova empírica do que conversamos com o mantenedor do flutter_modular: um
/// bind root-owned registrado via `add<T>(Impl.new)` (factory/lazy, NÃO
/// `addInstance`) resolve uma dep que também é root-owned (`PiSpawnConfig` via
/// `addInstance`) — core→core, mesmo escopo raiz.
///
/// Contraste com o que NÃO funciona (confirmado pelo mantenedor): o MESMO
/// `add<T>(Impl.new)` num módulo de feature (com `path`) estoura
/// "PiSpawnConfig not registered", porque o injector da feature é folha e não
/// enxerga o core. Por isso essas factories moram no core, não no settings.
void main() {
  test(
    'core add<T>(Impl.new) resolve PiSpawnConfig (core→core), incl. create()',
    () {
      const config = PiSpawnConfig(executable: 'pi');
      final boot = bootstrapModule(buildCoreModule(config: config));

      final pairing = boot.injector.get<PairingGatewayFactory>();
      final revoke = boot.injector.get<RevokeGatewayFactory>();

      expect(pairing, isA<PairingGatewayFactory>());
      expect(revoke, isA<RevokeGatewayFactory>());

      // create() constrói o gateway a partir do config injetado — se o construtor
      // não tivesse resolvido o PiSpawnConfig, a resolução acima já teria estourado.
      expect(pairing.create(), isA<PairingGateway>());
      expect(revoke.create(), isA<RevokeGateway>());
    },
  );
}
