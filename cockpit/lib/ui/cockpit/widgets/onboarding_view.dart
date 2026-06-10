import 'package:cockpit/domain/entities/install_result.dart';
import 'package:cockpit/domain/entities/setup_check.dart';
import 'package:cockpit/ui/cockpit/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Tela inicial (sem workspace): passo-a-passo de preparação do ambiente. Só
/// quando os 5 passos estão satisfeitos o botão "Criar Workspace" habilita.
///
/// Re-checa as permissões quando a janela volta a ter foco (o usuário sai pros
/// Ajustes do Sistema e volta) e oferece re-checagem manual por passo.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onCreateWorkspace});

  /// Dispara o fluxo de criação (escolher pasta → dialog → criar).
  final Future<void> Function() onCreateWorkspace;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SetupViewModel>().recheckAll();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou o foco → permissões podem ter mudado nos Ajustes do Sistema.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SetupViewModel>().recheckPermissions();
    }
  }

  /// Abre o dialog de instalação (spinner → resultado). A re-checagem do passo
  /// acontece dentro do [runner] (no ViewModel), então ao fechar o card já
  /// reflete o novo status.
  Future<void> _install(
    BuildContext context, {
    required String title,
    required Future<InstallResult> Function() runner,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InstallDialog(title: title, runner: runner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<SetupViewModel>();

    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rocket_launch_outlined, color: colors.accentText),
                    const SizedBox(width: 10),
                    Text(
                      'Bem-vindo ao Cockpit',
                      style: context.typo.title.copyWith(
                        fontSize: 20,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Antes de criar um workspace, vamos preparar o ambiente. '
                  'Conclua os passos abaixo.',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 22),
                _StepCard(
                  index: 1,
                  title: 'Pi Code instalado',
                  description: 'O binário `pi` precisa estar acessível.',
                  status: vm.pi,
                  onRecheck: vm.recheckPi,
                ),
                _StepCard(
                  index: 2,
                  title: 'Extensão remote-pi no Pi',
                  description: 'Registrada em ~/.pi/agent/settings.json.',
                  status: vm.extension,
                  onRecheck: vm.recheckExtension,
                  action: _StepAction(
                    label: 'Instalar',
                    onTap: () => _install(
                      context,
                      title: 'Instalar extensão remote-pi',
                      runner: vm.installExtension,
                    ),
                  ),
                ),
                _StepCard(
                  index: 3,
                  title: 'Supervisor instalado',
                  description: 'Serviço pi-supervisord (remote-pi install).',
                  status: vm.supervisor,
                  onRecheck: vm.recheckSupervisor,
                  // Sem a extensão não há index.js pra rodar o instalador.
                  action: vm.extension == CheckStatus.ok
                      ? _StepAction(
                          label: 'Instalar',
                          onTap: () => _install(
                            context,
                            title: 'Instalar supervisor',
                            runner: vm.installSupervisor,
                          ),
                        )
                      : null,
                ),
                _StepCard(
                  index: 4,
                  title: 'Notificações',
                  description: 'Avisos quando um agente termina um turno.',
                  status: vm.notifications,
                  onRecheck: vm.recheckNotifications,
                  action: _StepAction(
                    label: 'Testar',
                    onTap: vm.requestNotifications,
                  ),
                ),
                const SizedBox(height: 22),
                _CreateButton(
                  enabled: vm.canCreate,
                  onTap: widget.onCreateWorkspace,
                ),
                if (!vm.canCreate) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Conclua os passos acima para liberar a criação.',
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação secundária de um passo (ex.: "Testar", "Abrir Ajustes").
class _StepAction {
  const _StepAction({required this.label, required this.onTap});
  final String label;
  final Future<void> Function() onTap;
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.description,
    required this.status,
    required this.onRecheck,
    this.action,
  });

  final int index;
  final String title;
  final String description;
  final CheckStatus status;
  final Future<void> Function() onRecheck;
  final _StepAction? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showAction = action != null && status == CheckStatus.missing;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _StatusDot(status: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$index. $title',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ),
          if (showAction) ...[
            _PillButton(label: action!.label, onTap: action!.onTap),
            const SizedBox(width: 4),
          ],
          if (status != CheckStatus.notApplicable)
            Tooltip(
              message: 'Verificar de novo',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onRecheck(),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.refresh, size: 16, color: colors.text3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Indicador de estado: spinner / check verde / x vermelho-claro / dispensado.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    switch (status) {
      case CheckStatus.checking:
        return const SizedBox(
          width: 18,
          height: 18,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case CheckStatus.ok:
        return Icon(Icons.check_circle, size: 20, color: colors.online);
      case CheckStatus.missing:
        return Icon(
          Icons.cancel,
          size: 20,
          color: colors.error.withValues(alpha: 0.85),
        );
      case CheckStatus.notApplicable:
        return Tooltip(
          message: 'Dispensado nesta configuração',
          child: Icon(
            Icons.remove_circle_outline,
            size: 20,
            color: colors.text4,
          ),
        );
    }
  }
}

/// Botão-pílula matte pras ações de passo (Testar / Abrir Ajustes).
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: context.typo.label.copyWith(
              color: colors.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.enabled, required this.onTap});
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          disabledBackgroundColor: colors.panel3,
          disabledForegroundColor: colors.text4,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: enabled ? () => onTap() : null,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Criar Workspace'),
      ),
    );
  }
}

/// Dialog simples de instalação: dispara o [runner] ao montar, mostra spinner
/// enquanto roda e, ao terminar, o resultado (sucesso/erro). Botão "Fechar" só
/// habilita no fim.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.title, required this.runner});

  final String title;
  final Future<InstallResult> Function() runner;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  InstallResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result = await widget.runner();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = _result;

    return AlertDialog(
      backgroundColor: colors.panel2,
      title: Text(
        widget.title,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 380,
        child: result == null
            ? Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Instalando…',
                    style: context.typo.body.copyWith(
                      fontSize: 13.5,
                      color: colors.text2,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    result.ok ? Icons.check_circle : Icons.error,
                    size: 20,
                    color: result.ok ? colors.online : colors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result.ok
                          ? 'Instalado com sucesso.'
                          : result.detail,
                      style: context.typo.body.copyWith(
                        fontSize: 13.5,
                        color: colors.text2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: result == null ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Fechar',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: result == null ? colors.text4 : colors.text2,
            ),
          ),
        ),
      ],
    );
  }
}
