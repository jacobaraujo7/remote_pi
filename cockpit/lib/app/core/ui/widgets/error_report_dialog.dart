import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/data/diagnostics/issue_report.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mostra um erro de forma legível, com saída para o usuário reportar.
///
/// Três ações, em ordem de esforço: fechar (o erro já está no log), copiar o
/// relatório inteiro, ou abrir a issue já preenchida no GitHub. Nada é enviado
/// automaticamente — ver [IssueReport].
Future<void> showErrorReportDialog(
  BuildContext context, {
  required String title,
  required Object error,
  StackTrace? stack,
  String? description,
}) async {
  final log = DiagnosticsLog.instance;
  final logTail = await log.tail();
  if (!context.mounted) return;

  final report = IssueReport(
    title: '[cockpit] $title',
    error: error,
    stack: stack,
    logTail: logTail,
    appVersion: _appVersion,
  );

  await showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description ??
                    context.t.core.errorReportDialog.defaultDescription,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text2,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.panel2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _preview(error, stack),
                      style: context.typo.mono.copyWith(
                        fontSize: 11.5,
                        color: colors.text2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.close),
          ),
          OutlineButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report.toMarkdown()));
            },
            child: Text(context.t.core.errorReportDialog.copyDetails),
          ),
          PrimaryButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await launchUrl(
                report.toIssueUrl(),
                mode: LaunchMode.externalApplication,
              );
              navigator.pop();
            },
            child: Text(context.t.core.errorReportDialog.reportIssue),
          ),
        ],
      );
    },
  );
}

/// Versão do app para o relatório. Preenchida no boot pelo `main`; sem ela o
/// dialog ainda funciona, só reporta "unknown".
String _appVersion = 'unknown';

// ignore: use_setters_to_change_properties
void setDiagnosticsAppVersion(String version) => _appVersion = version;

String _preview(Object error, StackTrace? stack) {
  final buffer = StringBuffer(error.toString());
  if (stack != null) buffer.write('\n\n$stack');
  return buffer.toString();
}
