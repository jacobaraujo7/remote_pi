import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/domain/entities/layout_spec.dart';

/// Sequência de "abrir um layout `.ckp`" (plano 2.0, card k21), isolada do
/// `CockpitViewModel` pra ser testável sem montar o VM:
///
/// 1. **valida** (carrega/parseia o arquivo) — erro aqui não fecha nada;
/// 2. em [LayoutApplyMode.replace], **fecha** todas as abas do workspace
///    (o workspace "vira" o layout);
/// 3. **aplica** os panes do spec.
///
/// Os passos são callbacks porque só o VM sabe fechar/abrir abas; o runner
/// garante a ordem e o contrato "arquivo inválido = workspace intocado".
class LayoutApplyRunner {
  const LayoutApplyRunner();

  Future<Result<LayoutApplyReport, String>> run({
    required LayoutApplyMode mode,
    required Future<Result<LayoutSpec, String>> Function() load,
    required Future<int> Function() closeAll,
    required Future<Result<LayoutApplyReport, String>> Function(LayoutSpec)
    apply,
  }) async {
    final loaded = await load();
    switch (loaded) {
      case Failure(:final error):
        return Failure(error);
      case Success(:final value):
        final closed = mode == LayoutApplyMode.replace ? await closeAll() : 0;
        final applied = await apply(value);
        return switch (applied) {
          Failure(:final error) => Failure(error),
          Success(:final value) => Success(
            LayoutApplyReport(
              created: value.created,
              skipped: value.skipped,
              closed: closed,
            ),
          ),
        };
    }
  }
}
