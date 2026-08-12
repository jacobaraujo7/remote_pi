import 'package:cockpit/app/cockpit/ui/widgets/active_listenable_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ignora mudanças inativas e sincroniza ao reativar', (
    tester,
  ) async {
    final notifier = ChangeNotifier();
    var active = false;
    var builds = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return ActiveListenableBuilder(
              listenable: notifier,
              active: active,
              builder: (_, _) {
                builds++;
                return Text('$builds');
              },
            );
          },
        ),
      ),
    );
    expect(builds, 1);

    notifier.notifyListeners();
    await tester.pump();
    expect(builds, 1);

    setHostState(() => active = true);
    await tester.pump();
    expect(builds, 2);

    notifier.notifyListeners();
    await tester.pump();
    expect(builds, 3);

    setHostState(() => active = false);
    await tester.pump();
    expect(builds, 4);
    notifier.notifyListeners();
    await tester.pump();
    expect(builds, 4);

    notifier.dispose();
  });
}
