import 'package:cockpit/app/cockpit/domain/contracts/workspace_window_service.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Sentence for a [WorkspaceWindowError]. Exhaustive switch: a new `kind`
/// without a translation does not compile.
String workspaceWindowErrorMessage(
  BuildContext context,
  WorkspaceWindowError error,
) {
  final tr = context.t.cockpit.cockpitPage;
  final detail = error.detail ?? '';
  return switch (error.kind) {
    WorkspaceWindowErrorKind.unsupported => tr.openWindowUnsupported,
    WorkspaceWindowErrorKind.seedFailed => tr.openWindowFailedSeed(
      detail: detail,
    ),
    WorkspaceWindowErrorKind.launchFailed => tr.openWindowFailedLaunch(
      detail: detail,
    ),
  }.trim();
}
