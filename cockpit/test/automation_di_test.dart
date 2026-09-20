import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/data/terminal/terminal_profile_resolver_impl.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context));
}

void main() {
  testWidgets('AutomationController root instance is observable from routes', (
    tester,
  ) async {
    final core = buildCoreModule(
      terminalProfiles: TerminalProfileResolverImpl(),
    );
    final feature = createModule(
      path: '/',
      register: (c) => c.route(
        '/',
        child: (context, state) =>
            Text('${context.watch<AutomationController>().harnesses.length}'),
      ),
    );
    final app = createModule(
      register: (c) => c
        ..module(core)
        ..module(feature),
    );

    await tester.pumpWidget(
      ModularApp(
        module: app,
        provide: (services) => services.addChangeNotifier<AutomationController>(
          () => inject<AutomationController>(),
        ),
        child: const _Root(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
  });
}
