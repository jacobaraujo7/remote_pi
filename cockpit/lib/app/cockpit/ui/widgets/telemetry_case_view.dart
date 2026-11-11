// Corpo da aba de caso da Telemetry (plano 66, passo 6): cabeçalho (origem,
// tipo, mensagem, id, status, blame), ações, stats e as seções Stack,
// Log correlacionado, Ocorrências por run e Contexto cru. Espelha o mockup.

import 'package:cockpit/app/cockpit/domain/entities/telemetry_case.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/telemetry_run.dart';
import 'package:cockpit/app/cockpit/ui/session/telemetry_case_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/telemetry_viewmodel.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Título da aba: `RangeError · cart_service.dart:87`.
String telemetryCaseTabTitle(BuildContext context, TelemetryCase c) {
  final file = c.location?.split('/').last ?? c.project;
  return context.t.cockpit.telemetry.caseTabTitle(type: c.type, file: file);
}

/// "há 4 min" / "just now" nas três línguas.
String telemetryRelative(BuildContext context, DateTime at) {
  final tr = context.t.cockpit.telemetry;
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return tr.justNow;
  if (d.inHours < 1) return tr.minutesAgo(n: d.inMinutes);
  if (d.inDays < 1) return tr.hoursAgo(n: d.inHours);
  return tr.daysAgo(n: d.inDays);
}

enum TagKind { fresh, regression, resolved, ignored }

class TelemetryTag extends StatelessWidget {
  const TelemetryTag({super.key, required this.text, required this.kind});
  final String text;
  final TagKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color fg, Color? bg, Color? border) = switch (kind) {
      TagKind.fresh => (colors.accentText, colors.accentSoft, null),
      TagKind.regression => (
        colors.error,
        colors.error.withValues(alpha: .15),
        colors.error.withValues(alpha: .35),
      ),
      TagKind.resolved => (colors.ok, null, colors.ok.withValues(alpha: .35)),
      TagKind.ignored => (colors.text3, null, colors.border2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: border == null ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: context.typo.label.copyWith(
          fontSize: 9.5,
          letterSpacing: .4,
          color: fg,
        ),
      ),
    );
  }
}

class TelemetryCaseView extends StatefulWidget {
  const TelemetryCaseView({super.key, required this.session});
  final TelemetryCaseSession session;

  @override
  State<TelemetryCaseView> createState() => _TelemetryCaseViewState();
}

class _TelemetryCaseViewState extends State<TelemetryCaseView> {
  TelemetryCaseDetail? _detail;
  bool _missing = false;
  int _lastCount = -1;
  TelemetryViewModel? _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<TelemetryViewModel>()
      ..attach()
      ..addListener(_maybeReload);
    _load();
  }

  @override
  void dispose() {
    _vm
      ?..removeListener(_maybeReload)
      ..detach();
    super.dispose();
  }

  /// Recarrega só quando a contagem do caso mudou (o poll do VM roda a cada
  /// 2 s; não vale refazer o blame e o contexto sem motivo).
  void _maybeReload() {
    final vm = _vm;
    if (vm == null) return;
    final c = vm.cases.where(
      (x) => x.fingerprint == widget.session.fingerprint,
    );
    final count = c.isEmpty ? _lastCount : c.first.count;
    if (count != _lastCount) _load();
  }

  Future<void> _load() async {
    final vm = _vm;
    if (vm == null) return;
    final d = await vm.detail(widget.session.fingerprint);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _missing = d == null;
      _lastCount = d?.kase.count ?? _lastCount;
    });
    if (d != null) {
      widget.session.title = telemetryCaseTabTitle(context, d.kase);
    }
  }

  void _openLocation(String location) {
    final loc = _vm?.resolveLocation(location);
    if (loc == null) return;
    context.read<CockpitViewModel>().openFile(loc.path, revealLine: loc.line);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final d = _detail;
    if (d == null) {
      return ColoredBox(
        color: colors.panel,
        child: Center(
          child: _missing
              ? Text(
                  tr.emptyFiltered,
                  style: context.typo.label.copyWith(color: colors.text3),
                )
              : const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      );
    }
    final c = d.kase;
    final vm = context.read<TelemetryViewModel>();
    final cockpit = context.read<CockpitViewModel>();
    final open = c.status == TelemetryTriageStatus.open;
    final repRun = d.runs[c.runs.first.runId];
    final frames = d.last?.error?.frames ?? const <TelemetryFrame>[];
    final topFrame = d.last?.error?.projectFrame;
    final maxRun = c.runs.map((x) => x.count).fold(1, (a, b) => a > b ? a : b);

    return ColoredBox(
      color: colors.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Crumbs(kase: c, run: repRun),
              const SizedBox(height: 10),
              Row(
                children: [
                  _KindPill(
                    type: c.type,
                    warn: c.severity == TelemetrySeverity.warn,
                  ),
                  const SizedBox(width: 10),
                  if (c.isRegression && open)
                    TelemetryTag(
                      text: tr.tagRegression,
                      kind: TagKind.regression,
                    )
                  else if (c.isNew && open)
                    TelemetryTag(text: tr.tagNew, kind: TagKind.fresh),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                c.message,
                style: context.typo.mono.copyWith(
                  fontSize: 17,
                  height: 1.35,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Code(c.shortId),
                  _Status(status: c.status),
                  Text(
                    tr.fingerprintHint(location: c.location ?? '∅'),
                    style: context.typo.label.copyWith(
                      fontSize: 12,
                      color: colors.text3,
                    ),
                  ),
                  if (d.blame != null) _BlameChip(blame: d.blame!),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colors.border),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.location != null)
                    _Btn(
                      primary: true,
                      icon: Icons.open_in_new,
                      label: tr.openFile(location: c.location!),
                      onTap: () => _openLocation(c.location!),
                    ),
                  if (repRun?.taskKey != null)
                    _Btn(
                      icon: Icons.terminal_outlined,
                      label: tr.showInTerminal,
                      onTap: () => cockpit.openTaskOutput(
                        repRun!.taskKey!,
                        repRun.name ?? repRun.command,
                      ),
                    ),
                  _Btn(
                    icon: Icons.copy_outlined,
                    mono: 'cockpit telemetry show ${c.shortId}',
                    label: tr.copyCommand,
                    onTap: () => Clipboard.setData(
                      ClipboardData(
                        text: 'cockpit telemetry show ${c.shortId}',
                      ),
                    ),
                  ),
                  if (open) ...[
                    _Btn(
                      icon: Icons.check,
                      label: tr.resolve,
                      onTap: () => vm.triage(
                        c.fingerprint,
                        TelemetryTriageStatus.resolved,
                      ),
                    ),
                    _Btn(
                      ghost: true,
                      icon: Icons.visibility_off_outlined,
                      label: tr.ignore,
                      onTap: () => vm.triage(
                        c.fingerprint,
                        TelemetryTriageStatus.ignored,
                      ),
                    ),
                  ] else
                    _Btn(
                      icon: Icons.refresh,
                      label: tr.reopen,
                      onTap: () =>
                          vm.triage(c.fingerprint, TelemetryTriageStatus.open),
                    ),
                  _Btn(
                    ghost: true,
                    icon: Icons.delete_outline,
                    label: tr.clear,
                    onTap: () => vm.clearCase(c.fingerprint),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Stats(kase: c, run: repRun),
              const SizedBox(height: 22),
              _Section(
                title: tr.sectionStack,
                hint: tr.stackHint,
                child: frames.isEmpty
                    ? _EmptyCard(text: tr.none)
                    : _Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final f in frames)
                                _FrameRow(
                                  frame: f,
                                  top: identical(f, topFrame),
                                  onOpen: f.location == null || !f.inProject
                                      ? null
                                      : () => _openLocation(f.location!),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 22),
              _Section(
                title: tr.sectionCorrelated,
                hint: tr.correlatedHint,
                child: d.correlated == null
                    ? _EmptyCard(text: tr.none)
                    : _Card(child: _AttrsTable(event: d.correlated!)),
              ),
              const SizedBox(height: 22),
              _Section(
                title: tr.sectionRuns,
                hint: tr.runsHint,
                child: _Card(
                  child: Column(
                    children: [
                      for (final r in c.runs)
                        _RunBar(
                          entry: r,
                          run: d.runs[r.runId],
                          max: maxRun,
                          current: identical(r, c.runs.first),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _Section(
                title: tr.sectionContext,
                hint: tr.contextHint,
                child: d.context.isEmpty
                    ? _EmptyCard(text: tr.none)
                    : _Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final e in d.context)
                                _ContextLine(event: e, hit: e.id == d.last?.id),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- peças -----------------------------------------------------------------

class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.kase, required this.run});
  final TelemetryCase kase;
  final TelemetryRun? run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final s = context.typo.label.copyWith(fontSize: 12, color: colors.text3);
    final b = s.copyWith(color: colors.text2);
    final sep = Text(' › ', style: s.copyWith(color: colors.text4));
    final dot = Text('  ·  ', style: s.copyWith(color: colors.text4));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(kase.project, style: b),
        sep,
        Text(run?.name ?? run?.command ?? kase.runKey, style: b),
        if (run != null) ...[
          sep,
          Text(tr.run(id: run!.id), style: s),
          dot,
          Text(
            run!.source == TelemetryRunSource.app
                ? '${tr.srcApp} ${run!.command}'
                : run!.source == TelemetryRunSource.task
                ? tr.srcTask
                : '${tr.srcWrapper} ${run!.command}',
            style: s,
          ),
          if (run!.paneId != null) ...[dot, Text(run!.paneId!, style: s)],
        ],
      ],
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.type, required this.warn});
  final String type;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = warn ? colors.warn : colors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.toUpperCase(),
        style: context.typo.label.copyWith(
          fontSize: 11,
          letterSpacing: .4,
          color: c,
        ),
      ),
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: SelectableText(
        text,
        style: context.typo.mono.copyWith(fontSize: 12, color: colors.text2),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.status});
  final TelemetryTriageStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final (Color dot, String label) = switch (status) {
      TelemetryTriageStatus.open => (colors.error, tr.statusOpen),
      TelemetryTriageStatus.resolved => (colors.ok, tr.statusResolved),
      TelemetryTriageStatus.ignored => (colors.text4, tr.statusIgnored),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.typo.label.copyWith(fontSize: 12, color: colors.text2),
        ),
      ],
    );
  }
}

class _BlameChip extends StatelessWidget {
  const _BlameChip({required this.blame});
  final TelemetryBlame blame;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final text = blame.uncommitted
        ? tr.blameUncommitted
        : tr.blameCommit(
            ago: blame.at == null ? '?' : telemetryRelative(context, blame.at!),
            sha: blame.sha ?? '',
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: colors.editedBg,
        border: Border.all(color: colors.edited.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, size: 11, color: colors.edited),
          const SizedBox(width: 6),
          Text(
            text,
            style: context.typo.label.copyWith(
              fontSize: 12,
              color: colors.edited,
            ),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.ghost = false,
    this.mono,
  });
  final IconData icon;
  final String label;
  final String? mono;
  final VoidCallback onTap;
  final bool primary;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = primary ? Colors.white : colors.text2;
    return AppTooltip(
      message: label,
      child: HoverTap(
        onTap: onTap,
        color: primary
            ? colors.accent
            : (ghost ? Colors.transparent : colors.panel2),
        hoverColor: primary
            ? colors.accent.withValues(alpha: .85)
            : colors.panel3,
        border: Border.all(color: primary ? colors.accent : colors.border2),
        borderRadius: BorderRadius.circular(7),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 7),
            Text(
              mono ?? label,
              style: mono != null
                  ? context.typo.mono.copyWith(
                      fontSize: 11.5,
                      color: colors.accentText,
                    )
                  : context.typo.label.copyWith(fontSize: 12.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.kase, required this.run});
  final TelemetryCase kase;
  final TelemetryRun? run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    Widget cell(String label, String value, [String? small]) => Expanded(
      child: Container(
        color: colors.panel2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: context.typo.label.copyWith(
                fontSize: 10.5,
                letterSpacing: .6,
                color: colors.text3,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: context.typo.title.copyWith(
                    fontSize: 15,
                    color: colors.text,
                  ),
                ),
                if (small != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    small,
                    style: context.typo.label.copyWith(
                      fontSize: 12,
                      color: colors.text3,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    final origin = run == null
        ? '—'
        : (run!.source == TelemetryRunSource.app
              ? tr.srcApp
              : run!.source == TelemetryRunSource.task
              ? '${tr.srcTask} ${run!.name ?? ''}'
              : tr.srcWrapper);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            cell(
              tr.occurrences,
              '${kase.count}',
              tr.inRuns(n: kase.runs.length),
            ),
            VerticalDivider(width: 1, color: colors.border),
            cell(tr.first, telemetryRelative(context, kase.firstAt)),
            VerticalDivider(width: 1, color: colors.border),
            cell(tr.last, telemetryRelative(context, kase.lastAt)),
            VerticalDivider(width: 1, color: colors.border),
            cell(
              tr.origin,
              origin,
              run?.source == TelemetryRunSource.task ? 'PTY' : 'stdout',
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.child,
  });
  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              title.toUpperCase(),
              style: context.typo.title.copyWith(
                fontSize: 11,
                letterSpacing: .8,
                color: colors.text3,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: context.typo.label.copyWith(
                  fontSize: 11.5,
                  color: colors.text4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text,
        style: context.typo.mono.copyWith(
          fontSize: 12,
          color: context.colors.text4,
        ),
      ),
    ),
  );
}

class _FrameRow extends StatelessWidget {
  const _FrameRow({required this.frame, required this.top, this.onOpen});
  final TelemetryFrame frame;
  final bool top;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.typo.mono.copyWith(
      fontSize: 12,
      height: 1.65,
      color: frame.inProject ? colors.text : colors.text3,
    );
    final text = frame.raw.trim();
    final child = onOpen == null
        ? SelectableText(text, style: style)
        : HoverTap(
            onTap: onOpen,
            borderRadius: BorderRadius.zero,
            padding: EdgeInsets.zero,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: text),
                  if (frame.location != null)
                    TextSpan(
                      text: '  ${frame.location}',
                      style: style.copyWith(
                        color: colors.accentText,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.accentText.withValues(
                          alpha: .35,
                        ),
                      ),
                    ),
                ],
              ),
              style: style,
            ),
          );
    return Container(
      decoration: top
          ? BoxDecoration(
              color: colors.error.withValues(alpha: .08),
              border: Border(left: BorderSide(color: colors.error, width: 2)),
            )
          : null,
      padding: EdgeInsets.fromLTRB(top ? 12 : 14, 0, 14, 0),
      child: child,
    );
  }
}

class _AttrsTable extends StatelessWidget {
  const _AttrsTable({required this.event});
  final TelemetryEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = <MapEntry<String, Object?>>[
      MapEntry('msg', event.body),
      ...event.attrs.entries,
    ];
    final keyW = entries.fold<int>(
      0,
      (m, e) => e.key.length > m ? e.key.length : m,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: (keyW.clamp(4, 24) * 7.5) + 14,
                    child: Text(
                      e.key,
                      style: context.typo.mono.copyWith(
                        fontSize: 12,
                        color: colors.text3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value is String ? '"${e.value}"' : '${e.value}',
                      style: context.typo.mono.copyWith(
                        fontSize: 12,
                        color: e.value is String ? colors.ok : colors.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({
    required this.entry,
    required this.run,
    required this.max,
    required this.current,
  });
  final TelemetryCaseRun entry;
  final TelemetryRun? run;
  final int max;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.telemetry;
    final exit = run?.exitCode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: current ? Colors.transparent : colors.border),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Row(
              children: [
                Text(
                  tr.run(id: entry.runId),
                  style: context.typo.mono.copyWith(
                    fontSize: 12,
                    color: colors.text2,
                  ),
                ),
                if (current) ...[
                  const SizedBox(width: 8),
                  TelemetryTag(text: tr.current, kind: TagKind.fresh),
                ],
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.panel3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: (box.maxWidth * entry.count / max).clamp(
                      6.0,
                      box.maxWidth,
                    ),
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '×${entry.count}',
            style: context.typo.mono.copyWith(
              fontSize: 12,
              color: colors.text2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${telemetryRelative(context, entry.firstAt)}'
            '${entry.live ? ' →' : ''}'
            '${exit != null ? ' · exit $exit' : ''}',
            style: context.typo.label.copyWith(
              fontSize: 11.5,
              color: colors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.event, required this.hit});
  final TelemetryEvent event;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isJson = event.attrs.isNotEmpty && event.error == null;
    final offset = event.rawLineOffset;
    return Container(
      decoration: hit
          ? BoxDecoration(
              color: colors.error.withValues(alpha: .08),
              border: Border(left: BorderSide(color: colors.error, width: 2)),
            )
          : null,
      padding: EdgeInsets.fromLTRB(hit ? 12 : 14, 0, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              offset == null ? '' : '${offset + 1}',
              style: context.typo.mono.copyWith(
                fontSize: 12,
                height: 1.6,
                color: colors.text4,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              event.body,
              maxLines: 3,
              style: context.typo.mono.copyWith(
                fontSize: 12,
                height: 1.6,
                color: hit
                    ? colors.text
                    : (isJson ? colors.accentText : colors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
