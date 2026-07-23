import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Subpane de Tasks na coluna direita (abaixo da árvore de arquivos). Lista as
/// tasks detectadas do projeto com badge de estado e controles de ciclo de vida
/// **dirigidos por dados** — botões vêm dos [InteractiveKey] da task, sem
/// nenhum `if (flutter)` aqui.
class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.cwd,
    required this.listHeight,
    required this.onResizeDelta,
    required this.onResizeEnd,
  });

  /// Pasta do projeto selecionado. Trocar dispara nova descoberta.
  final String cwd;

  /// Altura da área de lista (redimensionável, espelha o painel de SEARCH).
  final double listHeight;
  final ValueChanged<double> onResizeDelta;
  final VoidCallback onResizeEnd;

  @override
  State<TasksPanel> createState() => _TasksPanelState();
}

class _TasksPanelState extends State<TasksPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TasksViewModel>().loadFor(widget.cwd);
    });
  }

  @override
  void didUpdateWidget(covariant TasksPanel old) {
    super.didUpdateWidget(old);
    if (old.cwd != widget.cwd) {
      context.read<TasksViewModel>().loadFor(widget.cwd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<TasksViewModel>();

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resizeHandle(context),
          _header(context, vm),
          SizedBox(
            height: widget.listHeight,
            child: vm.tasks.isEmpty && !vm.loading
                ? _empty(context, vm)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 6),
                    children: [
                      for (final def in vm.tasks)
                        _TaskRow(
                      key: ValueKey(def.id),
                      def: def,
                      run: vm.stateOf(def.id),
                      profileName: vm.selectedProfile(def),
                      canCycleProfile: def.profiles.length >= 2,
                      commandPreview: vm.commandPreview(def),
                      // Clicar abre a aba read-only de output no pane central.
                      onTap: () => context
                          .read<CockpitViewModel>()
                          .openTaskOutput(def.id, def.label),
                      // Play também já abre a aba dos logs.
                      onStart: () {
                        vm.start(def);
                        context
                            .read<CockpitViewModel>()
                            .openTaskOutput(def.id, def.label);
                      },
                      onStop: () => vm.stop(def.id),
                      onRestart: () => vm.restart(def.id),
                      onCycleProfile: () => vm.cycleProfile(def),
                      onKey: (k) => vm.sendKey(def.id, k),
                    ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Estado vazio: mensagem + (se não há `.cockpit/tasks.json`) um botão que
  /// cria um modelo de exemplo no projeto.
  Widget _empty(BuildContext context, TasksViewModel vm) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No tasks detected in this project.',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
          if (vm.hasProject && !vm.hasConfig) ...[
            const SizedBox(height: 10),
            HoverTap(
              borderRadius: BorderRadius.circular(6),
              onTap: vm.createExampleConfig,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.panel3,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: colors.text2),
                    const SizedBox(width: 6),
                    Text(
                      'Create tasks.json',
                      style: context.typo.label.copyWith(color: colors.text),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Alça de arraste no topo (igual ao painel de SEARCH): arrastar pra cima
  /// aumenta a lista; pra baixo diminui. A página clampa e persiste.
  Widget _resizeHandle(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => widget.onResizeDelta(d.delta.dy),
        onVerticalDragEnd: (_) => widget.onResizeEnd(),
        child: SizedBox(
          height: 9,
          child: Center(
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, TasksViewModel vm) {
    final colors = context.colors;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, size: 14, color: colors.text3),
          const SizedBox(width: 8),
          Text(
            'TASKS',
            style: context.typo.label.copyWith(
              fontSize: 11,
              letterSpacing: 0.6,
              color: colors.text3,
            ),
          ),
          const Spacer(),
          if (vm.loading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(size: 12),
            )
          else
            _IconAction(
              tooltip: 'Reload tasks',
              icon: Icons.refresh,
              onTap: vm.reload,
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.def,
    required this.run,
    required this.profileName,
    required this.canCycleProfile,
    required this.commandPreview,
    required this.onTap,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onCycleProfile,
    required this.onKey,
  });

  final TaskDefinition def;
  final TaskRun run;
  final String? profileName;
  final bool canCycleProfile;
  final String commandPreview;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onCycleProfile;
  final void Function(String key) onKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = run.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          _StatusDot(status: run.status),
          const SizedBox(width: 8),
          Expanded(
            // Só abre a aba de output quando a task está viva (tem buffer);
            // parada → não clicável.
            child: AppTooltip(
              message: commandPreview,
              child: HoverTap(
                onTap: active ? onTap : null,
                child: Opacity(
                  opacity: active ? 1 : 0.85,
                  child: Text(
                    def.label,
                    style: context.typo.label.copyWith(color: colors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (active) ...[
            for (final k in def.interactiveKeys.where((k) => k.primary))
              _IconAction(
                tooltip: "${k.label} (sends '${k.key}')",
                icon: _iconFor(k.icon),
                fallback: k.key,
                onTap: () => onKey(k.key),
              ),
            if (def.interactiveKeys.any((k) => !k.primary))
              _OverflowKeys(
                keys: def.interactiveKeys.where((k) => !k.primary).toList(),
                onKey: onKey,
              ),
            // Esconde o restart da task quando já há uma tecla primária com o
            // ícone de restart (ex.: Flutter "Hot restart") — evita 2 ícones iguais.
            if (!def.interactiveKeys.any((k) => k.primary && k.icon == 'restart'))
              _IconAction(
                tooltip: 'Restart',
                icon: Icons.restart_alt,
                onTap: onRestart,
              ),
            _IconAction(
              tooltip: 'Stop',
              icon: Icons.stop,
              color: colors.error,
              onTap: onStop,
            ),
          ] else if (run.isTransitioning) ...[
            // Starting/stopping: nada clicável — evita play/stop empilhados
            // enquanto o spawn prepara ou o processo morre.
            AppTooltip(
              message: run.status == TaskRunStatus.starting
                  ? 'Starting…'
                  : 'Stopping…',
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: CircularProgressIndicator(size: 12),
              ),
            ),
          ] else ...[
            if (profileName != null)
              _ProfileChip(
                name: profileName!,
                canCycle: canCycleProfile,
                onTap: onCycleProfile,
              ),
            _IconAction(
              tooltip: 'Run',
              icon: Icons.play_arrow,
              color: colors.online,
              onTap: onStart,
            ),
          ],
        ],
      ),
    );
  }

  IconData? _iconFor(String? token) => switch (token) {
    'refresh' => Icons.refresh,
    'restart' => Icons.restart_alt,
    'stop' => Icons.stop,
    'bolt' => Icons.bolt,
    _ => null,
  };
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final TaskRunStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (status) {
      TaskRunStatus.idle => colors.text4,
      TaskRunStatus.starting => colors.warn,
      TaskRunStatus.stopping => colors.warn,
      TaskRunStatus.building => colors.warn,
      TaskRunStatus.running => colors.accent,
      TaskRunStatus.success => colors.online,
      TaskRunStatus.failed => colors.error,
      TaskRunStatus.stopped => colors.text3,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.fallback,
    this.color,
  });

  final String tooltip;
  final VoidCallback onTap;
  final IconData? icon;
  final String? fallback;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: icon != null
              ? Icon(icon, size: 15, color: color ?? colors.text2)
              : Center(
                  child: Text(
                    fallback ?? '?',
                    style: context.typo.mono.copyWith(
                      fontSize: 11,
                      color: color ?? colors.text2,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Chip que mostra o profile selecionado e cicla pro próximo ao clicar (quando
/// há 2+). Some o `▾` se não dá pra ciclar (profile único).
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.name,
    required this.canCycle,
    required this.onTap,
  });

  final String name;
  final bool canCycle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: context.typo.mono.copyWith(fontSize: 10, color: colors.text2),
          ),
          if (canCycle)
            Icon(Icons.arrow_drop_down, size: 14, color: colors.text3),
        ],
      ),
    );
    if (!canCycle) return Padding(padding: const EdgeInsets.only(right: 2), child: chip);
    return AppTooltip(
      message: 'Switch profile',
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

/// Botão `⌨` que reúne as teclas interativas **secundárias** (não-primárias)
/// num menu — evita poluir a linha. Selecionar envia a tecla.
class _OverflowKeys extends StatelessWidget {
  const _OverflowKeys({required this.keys, required this.onKey});

  final List<InteractiveKey> keys;
  final void Function(String key) onKey;

  @override
  Widget build(BuildContext context) {
    return _IconAction(
      tooltip: 'More keys',
      icon: Icons.keyboard,
      onTap: () async {
        final chosen = await showAppMenu<String>(
          context,
          minWidth: 180,
          items: [
            for (final k in keys)
              AppMenuItem(value: k.key, label: '${k.label}  (${k.key})'),
          ],
        );
        if (chosen != null) onKey(chosen);
      },
    );
  }
}
