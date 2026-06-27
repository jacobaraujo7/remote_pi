import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tela inicial quando ainda não há workspace. Diferente do antigo onboarding,
/// **não** força instalar nada: o Cockpit serve como multiplexador de terminal
/// sem o Pi. O checklist do ambiente de agente vive agora dentro da aba de
/// agente (ver `AgentSetupChecklist`). Aqui só convidamos a criar um workspace.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.onCreateWorkspace});

  /// Dispara o fluxo de criação (escolher pasta → dialog → criar).
  final Future<void> Function() onCreateWorkspace;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/branding/cockpit_logo.png',
                  width: 64,
                  height: 64,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome to Cockpit',
                style: context.typo.title.copyWith(
                  fontSize: 20,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a folder to start a workspace.',
                textAlign: TextAlign.center,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                onPressed: () => onCreateWorkspace(),
                leading: const Icon(Icons.add, size: 16),
                child: const Text('Create workspace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
