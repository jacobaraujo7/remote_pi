// Modo Telemetry do painel direito (plano 66, passo 6): árvore
// projeto → run → casos, chips de triagem, busca e ações rápidas. Espelha o
// mockup aprovado (plan/mockups/66-telemetry.html).

import 'package:cockpit/app/cockpit/domain/entities/telemetry_case.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_run.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/telemetry_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/telemetry_case_view.dart'
    show telemetryCaseTabTitle, TelemetryTag, TagKind, telemetryRelative;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class TelemetryPanel extends StatefulWidget {
  const TelemetryPanel({
    super.key,
    required this.workspaceId,
    required this.roots,
  });

  final String workspaceId;
  final List<String> roots;

  @override
  State<TelemetryPanel> createState() => _TelemetryPanelState();
}

class _TelemetryPanelState extends State<TelemetryPanel> {
  final _search = TextEditingController();
  final _collapsed = <String>{};

  /// Resolvido no `initState`: o `dispose` não pode mais consultar o
  /// `context` (elemento já desativado → "Looking up a deactivated widget's
  /// ancestor is unsafe", caso e_804c da Telemetria).
  late final TelemetryViewModel _vm;

  /// Chip "App": em vez do workspace, mostra o run do próprio Cockpit
  /// (erros globais, warnings, métricas; plano 68).
  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<TelemetryViewModel>();
    _applyWorkspace();
    _vm.attach();
  }

  @override
  void didUpdateWidget(TelemetryPanel old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId || old.roots != widget.roots) {
      _applyWorkspace();
    }
  }

  void _applyWorkspace() {
    if (_showApp &&
        !context.read<SettingsController>().settings.developerMode) {
      _showApp = false;
    }
    if (_showApp) {
      _vm.setWorkspace(kTelemetryAppWorkspaceId, const []);
    } else {
      _vm.setWorkspace(widget.workspaceId, widget.roots);
    }
  }

  void _toggleApp() {
    setState(() => _showApp = !_showApp);
    _applyWorkspace();
  }

  @override
  void dispose() {
    _vm.detach();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TelemetryViewModel>();
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          vm: vm,
          search: _search,
          showApp: _showApp,
          onToggleApp: _toggleApp,
        ),
        Expanded(
          child: vm.cases.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      vm.query.isNotEmpty || vm.filter != TelemetryFilter.open
                          ? tr.emptyFiltered
                          : tr.empty,
                      textAlign: TextAlign.center,
                      style: context.typo.label.copyWith(color: colors.text4),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  children: _tree(context, vm),
                ),
        ),
      ],
    );
  }

  List<Widget> _tree(BuildContext context, TelemetryViewModel vm) {
    final out = <Widget>[];
    final byProject = <String, Map<String, List<TelemetryCase>>>{};
    for (final c in vm.cases) {
      (byProject[c.project] ??= {}).putIfAbsent(c.runKey, () => []).add(c);
    }
    final projects = byProject.keys.toList()..sort();
    for (final project in projects) {
      final runs = byProject[project]!;
      final pKey = 'p:$project';
      final flat = vm.singleRoot;
      if (!flat) {
        final all = runs.values.expand((x) => x).toList();
        out.add(
          _GroupHeader(
            title: project,
            count: all.length,
            hot: all.any(_isOpenError),
            collapsed: _collapsed.contains(pKey),
            onTap: () => setState(() => _toggle(pKey)),
            indent: 10,
          ),
        );
        if (_collapsed.contains(pKey)) continue;
      }
      final keys = runs.keys.toList()
        ..sort((a, b) {
          final ra = vm.runForKey(a)?.startedAt;
          final rb = vm.runForKey(b)?.startedAt;
          if (ra == null || rb == null) return a.compareTo(b);
          return rb.compareTo(ra);
        });
      for (final key in keys) {
        final cases = runs[key]!;
        final run = vm.runForKey(key);
        final rKey = 'r:$project:$key';
        out.add(
          _RunHeader(
            run: run,
            runKey: key,
            hot: cases.any(_isOpenError),
            collapsed: _collapsed.contains(rKey),
            onTap: () => setState(() => _toggle(rKey)),
            indent: flat ? 10 : 22,
            onClear: run == null ? null : () => vm.clearRun(run.id),
          ),
        );
        if (_collapsed.contains(rKey)) continue;
        for (final c in cases) {
          out.add(_CaseRow(kase: c, indent: flat ? 24 : 36));
        }
      }
    }
    return out;
  }

  void _toggle(String k) =>
      _collapsed.contains(k) ? _collapsed.remove(k) : _collapsed.add(k);

  static bool _isOpenError(TelemetryCase c) =>
      c.status == TelemetryTriageStatus.open &&
      c.severity.index >= TelemetrySeverity.error.index;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.search,
    required this.showApp,
    required this.onToggleApp,
  });
  final TelemetryViewModel vm;
  final TextEditingController search;
  final bool showApp;
  final VoidCallback onToggleApp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                tr.title,
                style: context.typo.title.copyWith(color: colors.text),
              ),
              const SizedBox(width: 8),
              if (vm.liveRuns > 0) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  tr.liveRuns(n: vm.liveRuns),
                  style: context.typo.mono.copyWith(
                    fontSize: 11,
                    color: colors.error,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _size(vm.sizeBytes),
                style: context.typo.mono.copyWith(
                  fontSize: 11,
                  color: colors.text4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          TextField(
            controller: search,
            onChanged: vm.setQuery,
            placeholder: Text(
              tr.searchHint,
              style: context.typo.body.copyWith(
                fontSize: 12.5,
                color: colors.text4,
              ),
            ),
            style: context.typo.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                label: tr.chipOpen,
                count: vm.openCount,
                on: vm.filter == TelemetryFilter.open,
                onTap: () => vm.setFilter(TelemetryFilter.open),
              ),
              _Chip(
                label: tr.chipNew,
                count: vm.newCount,
                on: vm.filter == TelemetryFilter.fresh,
                onTap: () => vm.setFilter(TelemetryFilter.fresh),
              ),
              _Chip(
                label: tr.chipResolved,
                count: vm.resolvedCount,
                on: vm.filter == TelemetryFilter.resolved,
                onTap: () => vm.setFilter(TelemetryFilter.resolved),
              ),
              _Chip(
                label: tr.chipIgnored,
                count: vm.ignoredCount,
                on: vm.filter == TelemetryFilter.ignored,
                onTap: () => vm.setFilter(TelemetryFilter.ignored),
              ),
              _Chip(
                label: '⚠ ${tr.chipWarnings}',
                count: vm.warningCount,
                on: vm.showWarnings,
                onTap: vm.toggleWarnings,
              ),
              if (context.select<SettingsController, bool>(
                (c) => c.settings.developerMode,
              ))
                _Chip(
                  label: tr.chipApp,
                  count: 0,
                  on: showApp,
                  onTap: onToggleApp,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onTap,
      color: on ? colors.panel2 : colors.panel,
      hoverColor: colors.panel3,
      border: Border.all(color: on ? colors.border2 : colors.border),
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.typo.label.copyWith(
              fontSize: 11.5,
              color: on ? colors.text : colors.text3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: context.typo.mono.copyWith(
              fontSize: 11,
              color: on ? colors.text2 : colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.hot,
    required this.collapsed,
    required this.onTap,
    required this.indent,
  });
  final String title;
  final int count;
  final bool hot;
  final bool collapsed;
  final VoidCallback onTap;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.fromLTRB(indent, 6, 10, 5),
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 14,
            color: colors.text4,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: context.typo.title.copyWith(
                fontSize: 11.5,
                color: colors.text2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$count',
            style: context.typo.mono.copyWith(
              fontSize: 11,
              color: hot ? colors.error : colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({
    required this.run,
    required this.runKey,
    required this.hot,
    required this.collapsed,
    required this.onTap,
    required this.indent,
    this.onClear,
  });
  final TelemetryRun? run;
  final String runKey;
  final bool hot;
  final bool collapsed;
  final VoidCallback onTap;
  final double indent;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final label =
        run?.name ??
        run?.command ??
        runKey.replaceFirst(RegExp(r'^(name|cmd):'), '');
    final isTask = run?.source == TelemetryRunSource.task;
    return HoverTap(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.fromLTRB(indent, 4, 10, 4),
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 13,
            color: colors.text4,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: context.typo.mono.copyWith(
                fontSize: 12,
                color: colors.text2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 7),
          _SourcePill(
            text: run?.source == TelemetryRunSource.app
                ? tr.srcApp
                : isTask
                ? tr.srcTask
                : tr.srcWrapper,
            accent: isTask,
          ),
          if (run?.isLive == true) ...[
            const SizedBox(width: 7),
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ],
          const Spacer(),
          if (onClear != null)
            AppTooltip(
              message: tr.clearRun,
              child: HoverTap(
                onTap: onClear,
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.delete_outline,
                  size: 13,
                  color: colors.text4,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Text(
            run == null ? '' : tr.run(id: run!.id),
            style: context.typo.mono.copyWith(
              fontSize: 11,
              color: hot ? colors.error : colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.text, required this.accent});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(
          color: accent
              ? colors.accentText.withValues(alpha: .35)
              : colors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: context.typo.label.copyWith(
          fontSize: 9.5,
          letterSpacing: .4,
          color: accent ? colors.accentText : colors.text4,
        ),
      ),
    );
  }
}

class _CaseRow extends StatefulWidget {
  const _CaseRow({required this.kase, required this.indent});
  final TelemetryCase kase;
  final double indent;

  @override
  State<_CaseRow> createState() => _CaseRowState();
}

class _CaseRowState extends State<_CaseRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.kase;
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final vm = context.read<TelemetryViewModel>();
    final cockpit = context.read<CockpitViewModel>();
    final open = c.status == TelemetryTriageStatus.open;
    final sev = switch (c.status) {
      TelemetryTriageStatus.resolved => colors.ok,
      TelemetryTriageStatus.ignored => colors.text4,
      TelemetryTriageStatus.open =>
        c.severity == TelemetrySeverity.warn ? colors.warn : colors.error,
    };
    final selected = cockpit.isTelemetryCaseOpen(c.fingerprint);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HoverTap(
        onTap: () => cockpit.openTelemetryCase(
          c.fingerprint,
          telemetryCaseTabTitle(context, c),
        ),
        borderRadius: BorderRadius.zero,
        color: selected ? colors.panel2 : Colors.transparent,
        padding: EdgeInsets.fromLTRB(widget.indent, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: sev, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.mono.copyWith(
                      fontSize: 12.5,
                      color: open ? colors.text : colors.text3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (c.isRegression && open)
                        TelemetryTag(
                          text: tr.tagRegression,
                          kind: TagKind.regression,
                        )
                      else if (c.isNew && open)
                        TelemetryTag(text: tr.tagNew, kind: TagKind.fresh),
                      if (c.status == TelemetryTriageStatus.resolved)
                        TelemetryTag(
                          text: tr.tagResolved,
                          kind: TagKind.resolved,
                        ),
                      if (c.status == TelemetryTriageStatus.ignored)
                        TelemetryTag(
                          text: tr.tagIgnored,
                          kind: TagKind.ignored,
                        ),
                      if (c.location != null)
                        Text(
                          c.location!,
                          style: context.typo.mono.copyWith(
                            fontSize: 11,
                            color: colors.text3,
                          ),
                        ),
                      Text(
                        telemetryRelative(context, c.lastAt),
                        style: context.typo.label.copyWith(
                          fontSize: 11,
                          color: colors.text4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (_hover)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (open) ...[
                    _Quick(
                      icon: Icons.check,
                      tooltip: tr.resolve,
                      onTap: () => vm.triage(
                        c.fingerprint,
                        TelemetryTriageStatus.resolved,
                      ),
                    ),
                    _Quick(
                      icon: Icons.visibility_off_outlined,
                      tooltip: tr.ignore,
                      onTap: () => vm.triage(
                        c.fingerprint,
                        TelemetryTriageStatus.ignored,
                      ),
                    ),
                  ] else
                    _Quick(
                      icon: Icons.refresh,
                      tooltip: tr.reopen,
                      onTap: () =>
                          vm.triage(c.fingerprint, TelemetryTriageStatus.open),
                    ),
                  _Quick(
                    icon: Icons.delete_outline,
                    tooltip: tr.clear,
                    onTap: () => vm.clearCase(c.fingerprint),
                  ),
                ],
              )
            else
              Text(
                '×${c.count}',
                style: context.typo.mono.copyWith(
                  fontSize: 11,
                  color: colors.text2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        onTap: onTap,
        color: colors.panel2,
        hoverColor: colors.panel3,
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(5),
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 12, color: colors.text2),
      ),
    );
  }
}
