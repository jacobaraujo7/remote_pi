import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/core/ui/widgets/macos_notification_instructions_dialog.dart';
import 'package:cockpit/app/settings/domain/cron_schedule.dart';
import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/window_controls.dart';
import 'package:cockpit/app/settings/ui/connectivity_viewmodel.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/daemons_viewmodel.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:cockpit/app/settings/ui/pairing_dialog.dart';
import 'package:cockpit/app/settings/ui/revoke_dialog.dart';
import 'package:cockpit/app/settings/ui/settings_env_gate.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tela cheia de Configurações (push). Categorias à esquerda (Aparência ·
/// Conectividade) e o conteúdo à direita. Por ora só **Aparência** está
/// implementada; Conectividade chega na próxima fase.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _Category {
  appearance,
  languages,
  notifications,
  connectivity,
  daemons,
  scheduling,
}

extension on _Category {
  /// Abas que dependem do ambiente remote-pi (extensão + supervisor).
  bool get isRemote =>
      this == _Category.connectivity ||
      this == _Category.daemons ||
      this == _Category.scheduling;
}

class _SettingsPageState extends State<SettingsPage> {
  _Category _category = _Category.appearance;

  @override
  void initState() {
    super.initState();
    // Sonda o ambiente para decidir se as abas remotas aparecem.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsEnvGate>().check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final remoteReady = context.watch<SettingsEnvGate>().remoteReady;
    // Categoria selecionada caiu (ambiente sumiu) → volta pra Aparência.
    final category = (!remoteReady && _category.isRemote)
        ? _Category.appearance
        : _category;
    return Scaffold(
      backgroundColor: colors.bg,
      child: Column(
        children: [
          const _SettingsHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryNav(
                  selected: category,
                  remoteReady: remoteReady,
                  onSelect: (c) => setState(() => _category = c),
                ),
                Expanded(
                  child: switch (category) {
                    _Category.appearance => const _AppearancePanel(),
                    _Category.languages => const _LanguagesPanel(),
                    _Category.notifications => const _NotificationsPanel(),
                    _Category.connectivity => const _ConnectivityPanel(),
                    _Category.daemons => const _DaemonsPanel(),
                    _Category.scheduling => const _AgendamentosPanel(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header da tela: window controls + voltar + título (a barra arrasta a janela).
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WindowTitleBar(
      children: [
        const WindowControls(),
        const SizedBox(width: 14),
        Tooltip(
          tooltip: (context) => const TooltipContainer(child: Text('Back')),
          child: HoverTap(
            borderRadius: BorderRadius.circular(6),
            onTap: () => context.pop(),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(Icons.arrow_back, size: 18, color: colors.text2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Settings',
          style: context.typo.title.copyWith(fontSize: 14, color: colors.text),
        ),
        const Spacer(),
        const WindowControlsTrailing(),
      ],
    );
  }
}

class _CategoryNav extends StatelessWidget {
  const _CategoryNav({
    required this.selected,
    required this.remoteReady,
    required this.onSelect,
  });
  final _Category selected;

  /// Extensão remote-pi + supervisor instalados → mostra as abas remotas.
  final bool remoteReady;
  final ValueChanged<_Category> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 210,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          _NavItem(
            icon: Icons.palette_outlined,
            label: 'Appearance',
            selected: selected == _Category.appearance,
            onTap: () => onSelect(_Category.appearance),
          ),
          _NavItem(
            icon: Icons.code,
            label: 'Language',
            selected: selected == _Category.languages,
            onTap: () => onSelect(_Category.languages),
          ),
          _NavItem(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            selected: selected == _Category.notifications,
            onTap: () => onSelect(_Category.notifications),
          ),
          // Abas que dependem do ambiente remote-pi — ocultas até instalá-lo
          // (via checklist da aba de agente).
          if (remoteReady) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Divider(height: 1, thickness: 1, color: colors.border),
            ),
            _NavItem(
              icon: Icons.wifi_tethering,
              label: 'Connectivity',
              selected: selected == _Category.connectivity,
              onTap: () => onSelect(_Category.connectivity),
            ),
            _NavItem(
              icon: Icons.dns_outlined,
              label: 'Daemon Agents',
              selected: selected == _Category.daemons,
              onTap: () => onSelect(_Category.daemons),
            ),
            _NavItem(
              icon: Icons.schedule_outlined,
              label: 'Schedules',
              selected: selected == _Category.scheduling,
              onTap: () => onSelect(_Category.scheduling),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? colors.accentText : colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: selected ? colors.text : colors.text2,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aparência
// ---------------------------------------------------------------------------
class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: 'Theme',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Theme',
                      trailing: _ThemeDropdown(
                        value: s.themeMode,
                        onChanged: controller.setThemeMode,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Fonts',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Interface font',
                      description:
                          'Used across the whole app. Empty = system default.',
                      trailing: _FontField(
                        value: s.interfaceFont,
                        hint: 'Space Grotesk · Hanken',
                        onChanged: controller.setInterfaceFont,
                      ),
                    ),
                    _Row(
                      title: 'Interface size',
                      trailing: _SizeStepper(
                        value: s.interfaceSize,
                        min: 11,
                        max: 22,
                        onChanged: controller.setInterfaceSize,
                      ),
                    ),
                    _Row(
                      title: 'Code font',
                      description: 'Code and diffs. Empty = system default.',
                      trailing: _FontField(
                        value: s.codeFont,
                        hint: 'JetBrains Mono',
                        onChanged: controller.setCodeFont,
                      ),
                    ),
                    _Row(
                      title: 'Code size',
                      trailing: _SizeStepper(
                        value: s.codeSize,
                        min: 9,
                        max: 20,
                        onChanged: controller.setCodeSize,
                      ),
                    ),
                    _Row(
                      title: 'Terminal font',
                      description:
                          'Uses the code size. Empty = system default.',
                      trailing: _FontField(
                        value: s.terminalFont,
                        hint: 'Menlo · monospace',
                        onChanged: controller.setTerminalFont,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Syntax',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Card(
                      children: [
                        _Row(
                          title: 'Highlight theme',
                          description:
                              'Code colors, independent of the app theme.',
                          trailing: _SyntaxDropdown(
                            value: s.syntaxTheme,
                            onChanged: controller.setSyntaxTheme,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const _SyntaxPreview(),
                  ],
                ),
              ),
              _Section(
                label: 'Conversation',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Pin user message',
                      description:
                          'The question stays fixed at the top while the answer '
                          'scrolls.',
                      trailing: Switch(
                        value: s.pinUserMessage,
                        onChanged: controller.setPinUserMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// Aba **Notifications** (sempre visível). Liga/desliga as notificações de fim
/// de turno (persistido em `AppSettings`) e, no macOS, mostra o estado da
/// permissão do SO + botão pra pedi-la.
class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: 'Notifications',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Enable notifications',
                      description:
                          'Alert me when an agent finishes a turn and the window '
                          'is not focused.',
                      trailing: Switch(
                        value: s.notificationsEnabled,
                        onChanged: controller.setNotificationsEnabled,
                      ),
                    ),
                    if (Platform.isMacOS && s.notificationsEnabled)
                      const _NotificationPermissionRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado da permissão de notificação do macOS + botão para solicitá-la. Sonda
/// ao montar; ao pedir, dispara uma notificação de teste e, se ainda negada,
/// abre as instruções do System Settings.
class _NotificationPermissionRow extends StatefulWidget {
  const _NotificationPermissionRow();

  @override
  State<_NotificationPermissionRow> createState() =>
      _NotificationPermissionRowState();
}

class _NotificationPermissionRowState
    extends State<_NotificationPermissionRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsViewModel>().check();
    });
  }

  Future<void> _request() async {
    final status = await context.read<NotificationsViewModel>().request();
    if (!mounted) return;
    if (status == CheckStatus.missing) {
      MacosNotificationInstructionsDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final granted =
        context.watch<NotificationsViewModel>().status == CheckStatus.ok;
    return _Row(
      title: 'System permission',
      description: granted
          ? 'Cockpit is allowed to send notifications.'
          : 'macOS has not granted notification access yet.',
      trailing: granted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.online),
                const SizedBox(width: 6),
                Text(
                  'Granted',
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              ],
            )
          : SecondaryButton(
              onPressed: _request,
              child: const Text('Request permission'),
            ),
    );
  }
}

/// Amostra de código realçada com o tema de syntax atual (atualiza ao trocar o
/// dropdown). Usa o `context.syntax` (fundo + cores) e o `buildCodeSpan`.
class _SyntaxPreview extends StatelessWidget {
  const _SyntaxPreview();

  static const String _sample =
      '{\n'
      '  "name": "cockpit",\n'
      '  "version": 2,\n'
      '  "active": true,\n'
      '  "tags": ["dev", "ui"]\n'
      '}';

  @override
  Widget build(BuildContext context) {
    final syntax = context.syntax;
    final base = context.typo.mono.copyWith(
      fontSize: 12.5,
      height: 1.5,
      color: syntax.base,
    );
    final span = buildCodeSpan(
      context,
      source: _sample,
      language: 'json',
      baseStyle: base,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: syntax.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: span == null ? Text(_sample, style: base) : Text.rich(span),
    );
  }
}

// ---------------------------------------------------------------------------
// Blocos reutilizáveis
// ---------------------------------------------------------------------------
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.trailing});
  final String label;
  final Widget child;

  /// Ação opcional à direita do rótulo da seção (ex.: botão de recarregar).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: colors.border));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(children: rows),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.trailing, this.description});
  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }
}

/// Gatilho de dropdown (rótulo + chevron) que abre o `showAppMenu`.
class _DropdownChip extends StatelessWidget {
  const _DropdownChip({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.text2),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
          ),
          const SizedBox(width: 6),
          Icon(Icons.keyboard_arrow_down, size: 16, color: colors.text3),
        ],
      ),
    );
  }
}

class _ThemeDropdown extends StatelessWidget {
  const _ThemeDropdown({required this.value, required this.onChanged});
  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const _meta = <AppThemeMode, ({String label, IconData icon})>{
    AppThemeMode.system: (
      label: 'System',
      icon: Icons.desktop_windows_outlined,
    ),
    AppThemeMode.light: (label: 'Light', icon: Icons.light_mode_outlined),
    AppThemeMode.dark: (label: 'Dark', icon: Icons.dark_mode_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final current = _meta[value]!;
    return _DropdownChip(
      icon: current.icon,
      label: current.label,
      onTap: () async {
        final picked = await showAppMenu<AppThemeMode>(
          context,
          minWidth: 180,
          items: [
            for (final e in _meta.entries)
              AppMenuItem(
                value: e.key,
                label: e.value.label,
                icon: e.value.icon,
                selected: e.key == value,
              ),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _SyntaxDropdown extends StatelessWidget {
  const _SyntaxDropdown({required this.value, required this.onChanged});
  final SyntaxThemeId value;
  final ValueChanged<SyntaxThemeId> onChanged;

  static const _labels = <SyntaxThemeId, String>{
    SyntaxThemeId.one: 'One',
    SyntaxThemeId.dracula: 'Dracula',
    SyntaxThemeId.github: 'GitHub',
  };

  @override
  Widget build(BuildContext context) {
    return _DropdownChip(
      label: _labels[value]!,
      onTap: () async {
        final picked = await showAppMenu<SyntaxThemeId>(
          context,
          minWidth: 180,
          items: [
            for (final e in _labels.entries)
              AppMenuItem(
                value: e.key,
                label: e.value,
                selected: e.key == value,
              ),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Campo de família de fonte (texto livre; vazio = padrão).
class _FontField extends StatefulWidget {
  const _FontField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });
  final String? value;
  final String hint;
  final ValueChanged<String?> onChanged;

  @override
  State<_FontField> createState() => _FontFieldState();
}

class _FontFieldState extends State<_FontField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 240,
      child: TextField(
        controller: _ctrl,
        onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
        placeholder: Text(widget.hint),
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }
}

/// Stepper de tamanho ( − valor + ) com sufixo "px".
class _SizeStepper extends StatelessWidget {
  const _SizeStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, Icons.remove, () {
            if (value > min) onChanged((value - 1).clamp(min, max));
          }),
          SizedBox(
            width: 44,
            child: Text(
              '${value.round()} px',
              textAlign: TextAlign.center,
              style: context.typo.mono.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
            ),
          ),
          _btn(context, Icons.add, () {
            if (value < max) onChanged((value + 1).clamp(min, max));
          }),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) {
    return HoverTap(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 32,
        child: Icon(icon, size: 15, color: context.colors.text2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language (LSP)
// ---------------------------------------------------------------------------

/// Configura o comando do language server (LSP) de cada linguagem. Vem
/// pré-preenchido com o default do catálogo; o usuário pode sobrescrever (ex.:
/// caminho custom do binário). Um indicador mostra se o executável está no PATH
/// — comunica por que uma linguagem mostra erros e outra não, sem prometer
/// mágica (Cockpit não instala servidores; só usa o que está na máquina).
class _LanguagesPanel extends StatelessWidget {
  const _LanguagesPanel();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SettingsController>();
    final settings = ctrl.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            label: 'FORMATTING',
            child: _Card(
              children: [
                _Row(
                  title: 'Format on save',
                  description:
                      'Format the file automatically when you save (⌘S).',
                  trailing: Switch(
                    value: settings.formatOnSave,
                    onChanged: ctrl.setFormatOnSave,
                  ),
                ),
              ],
            ),
          ),
          _Section(
            label: 'LANGUAGE SERVERS',
            child: _Card(
              children: [
                for (final def in kLanguageDefs)
                  _LanguageRow(
                    key: ValueKey(def.id),
                    def: def,
                    overrideCommand: settings.lspCommands[def.id],
                    formatterCommand: settings.lspFormatters[def.id],
                    onChangedCommand: (v) => ctrl.setLspCommand(def.id, v),
                    onChangedFormatter: (v) => ctrl.setLspFormatter(def.id, v),
                  ),
              ],
            ),
          ),
          Text(
            'Errors and formatting use each language\'s language server. '
            'Cockpit does not install servers — it uses what is already on your '
            'machine. ● responds · ○ not found or invalid command (install the '
            'server or adjust the command).',
            style: context.typo.label.copyWith(color: context.colors.text3),
          ),
        ],
      ),
    );
  }
}

/// Linha de uma linguagem (tile expansível): nome + status (●/○) e, ao expandir,
/// o comando do language server + o comando do formatador externo (opcional). A
/// sonda do servidor roda ao montar e ao salvar.
class _LanguageRow extends StatefulWidget {
  const _LanguageRow({
    super.key,
    required this.def,
    required this.overrideCommand,
    required this.formatterCommand,
    required this.onChangedCommand,
    required this.onChangedFormatter,
  });

  final LanguageDef def;
  final String? overrideCommand;
  final String? formatterCommand;
  final ValueChanged<String?> onChangedCommand;
  final ValueChanged<String?> onChangedFormatter;

  @override
  State<_LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends State<_LanguageRow> {
  late final TextEditingController _serverCtrl;
  late final TextEditingController _formatterCtrl;
  bool? _available; // null = checando
  bool _expanded = false;
  bool _dirty = false;

  String get _default => <String>[
    widget.def.defaultExecutable,
    ...widget.def.defaultArgs,
  ].join(' ').trim();

  String get _savedServer => widget.overrideCommand ?? _default;
  String get _savedFormatter => widget.formatterCommand ?? '';

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: _savedServer)
      ..addListener(_onTextChanged);
    _formatterCtrl = TextEditingController(text: _savedFormatter)
      ..addListener(_onTextChanged);
    _detect();
  }

  @override
  void dispose() {
    _serverCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    _formatterCtrl
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final dirty =
        _serverCtrl.text.trim() != _savedServer.trim() ||
        _formatterCtrl.text.trim() != _savedFormatter.trim();
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  /// Sonda o comando do servidor salvo: spawna e verifica se fica vivo como um
  /// LSP de verdade (valida os argumentos, não só o binário no PATH).
  Future<void> _detect() async {
    setState(() => _available = null); // checando
    final ok = await probeLspCommand(_savedServer);
    if (mounted) setState(() => _available = ok);
  }

  /// Persiste comando do servidor + formatador (reinicia o LSP da linguagem via
  /// o listener do shell). Servidor igual ao default → limpa o override.
  void _save() {
    final server = _serverCtrl.text.trim();
    widget.onChangedCommand(
      server.isEmpty || server == _default ? null : server,
    );
    final formatter = _formatterCtrl.text.trim();
    widget.onChangedFormatter(formatter.isEmpty ? null : formatter);
    setState(() => _dirty = false);
    _detect();
  }

  /// Volta o servidor ao default e limpa o formatador (limpa ambos os overrides).
  void _reset() {
    _serverCtrl.text = _default;
    _formatterCtrl.text = '';
    widget.onChangedCommand(null);
    widget.onChangedFormatter(null);
    setState(() => _dirty = false);
    _detect();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabeçalho clicável: chevron + nome + extensões + status.
        HoverTap(
          onTap: () => setState(() => _expanded = !_expanded),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: colors.text3,
              ),
              const SizedBox(width: 8),
              Text(
                widget.def.label,
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '.${widget.def.extensions.join(' · .')}',
                style: context.typo.label.copyWith(color: colors.text4),
              ),
              const Spacer(),
              _StatusDot(available: _available),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel(context, 'Language server command'),
                const SizedBox(height: 6),
                _commandField(context, _serverCtrl, _default),
                const SizedBox(height: 14),
                _fieldLabel(context, 'Formatter command (optional)'),
                const SizedBox(height: 6),
                _commandField(
                  context,
                  _formatterCtrl,
                  'prettier --write %FILE%',
                ),
                const SizedBox(height: 4),
                Text(
                  'External formatter with %FILE% placeholder. Takes precedence '
                  'over the LSP formatter when set.',
                  style: context.typo.label.copyWith(color: colors.text4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    HoverTap(
                      borderRadius: BorderRadius.circular(7),
                      onTap: _reset,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        'Reset to default',
                        style: context.typo.body.copyWith(
                          fontSize: 12.5,
                          color: colors.text2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    HoverTap(
                      color: _dirty ? colors.accent : colors.panel3,
                      borderRadius: BorderRadius.circular(7),
                      onTap: _dirty ? _save : () {},
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      child: Text(
                        'Save & restart',
                        style: context.typo.body.copyWith(
                          fontSize: 12.5,
                          color: _dirty ? colors.accentText : colors.text4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _commandField(
    BuildContext context,
    TextEditingController controller,
    String placeholder,
  ) => TextField(
    controller: controller,
    onSubmitted: (_) => _save(),
    style: context.typo.mono.copyWith(
      fontSize: 12.5,
      color: context.colors.text,
    ),
    placeholder: Text(placeholder),
    borderRadius: BorderRadius.circular(7),
  );
}

/// Bolinha de status do executável: verde (encontrado), cinza vazado (ausente),
/// cinza claro (checando).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.available});
  final bool? available;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color color, String tip) = switch (available) {
      true => (const Color(0xFF22C55E), 'Server responds'),
      false => (colors.text4, 'Server not found or command invalid'),
      null => (colors.border, 'Checking…'),
    };
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: available == false ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: available == false ? Border.all(color: color) : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conectividade
// ---------------------------------------------------------------------------
class _ConnectivityPanel extends StatefulWidget {
  const _ConnectivityPanel();

  @override
  State<_ConnectivityPanel> createState() => _ConnectivityPanelState();
}

class _ConnectivityPanelState extends State<_ConnectivityPanel> {
  @override
  void initState() {
    super.initState();
    // Carrega relay + aparelhos quando a aba abre (lazy — não roda o shell-out
    // do `remote-pi` se o usuário só visita Aparência).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ConnectivityViewModel>().load();
    });
  }

  /// Abre o dialog de pareamento (sobe um `pi --mode rpc` efêmero). Quando um
  /// aparelho parear, o dialog fecha com `true` e a lista é recarregada.
  Future<void> _openPairing() async {
    final vm = context.read<ConnectivityViewModel>();
    // O controller é dono do `pi --mode rpc` efêmero; criado aqui e descartado
    // ao fechar (era o `ChangeNotifierProvider` que fazia esse dispose).
    final ctrl = vm.newPairingController()..start();
    final paired = await showDialog<bool>(
      context: context,
      builder: (_) => PairingDialog(controller: ctrl),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (paired == true) await vm.loadDevices();
  }

  /// Revogar é destrutivo (o aparelho perde acesso) → confirma, depois roda o
  /// revoke (sobe um `pi --mode rpc` que liga o relay) num dialog de progresso,
  /// e recarrega a lista ao fim.
  Future<void> _confirmRevoke(PairedDevice device) async {
    final vm = context.read<ConnectivityViewModel>();
    final colors = context.colors;
    final name = device.label.isEmpty ? device.shortId : device.label;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Revoke device?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"$name" will lose access to your agents and will need to pair again.'
          '\n\nYou must be connected to the relay — the app will connect '
          'automatically to revoke.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Revoke',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Dialog de progresso (não-dismissível): roda o revoke e mostra resultado.
    // O controller é dono do `pi --mode rpc` efêmero; descartado ao fechar.
    final ctrl = vm.newRevokeController()..run(device);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RevokeDialog(controller: ctrl),
    );
    ctrl.dispose();
    if (!mounted) return;
    await vm.loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectivityViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Section(
                label: 'Relay',
                child: _Card(children: [_RelayEditor()]),
              ),
              _Section(
                label: 'Paired devices',
                trailing: _ReloadButton(
                  busy: vm.devicesLoad == ConnLoad.loading,
                  onTap: vm.loadDevices,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _devicesCard(context, vm),
                    const SizedBox(height: 12),
                    _PairButton(onTap: _openPairing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _devicesCard(BuildContext context, ConnectivityViewModel vm) {
    final colors = context.colors;

    // Primeira carga (ainda sem dados).
    if (vm.devicesLoad == ConnLoad.loading && vm.devices.isEmpty) {
      return _MessageCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              'Loading…',
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text3,
              ),
            ),
          ],
        ),
      );
    }

    if (vm.devicesLoad == ConnLoad.error && vm.devices.isEmpty) {
      return _MessageCard(
        child: Text(
          vm.devicesError ?? 'Failed to list devices.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }

    if (vm.devices.isEmpty) {
      return _MessageCard(
        child: Text(
          'No paired devices.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }

    return _Card(
      children: [
        for (final device in vm.devices)
          _DeviceTile(device: device, onRevoke: () => _confirmRevoke(device)),
      ],
    );
  }
}

/// Campo de URL do relay (mono) + botão Salvar. O valor carregado/salvo sincroniza
/// com o campo, mas só enquanto o usuário não estiver digitando.
class _RelayEditor extends StatefulWidget {
  const _RelayEditor();

  @override
  State<_RelayEditor> createState() => _RelayEditorState();
}

class _RelayEditorState extends State<_RelayEditor> {
  final TextEditingController _ctrl = TextEditingController();
  late final ConnectivityViewModel _vm;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<ConnectivityViewModel>();
    _ctrl.text = _vm.relayUrl ?? '';
    _vm.addListener(_syncFromVm);
  }

  void _syncFromVm() {
    if (_edited) return;
    final loaded = _vm.relayUrl ?? '';
    if (_ctrl.text != loaded) {
      _ctrl.text = loaded;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_syncFromVm);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await _vm.setRelay(_ctrl.text);
    if (!mounted) return;
    if (ok) setState(() => _edited = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectivityViewModel>();
    final colors = context.colors;
    final value = _ctrl.text.trim();
    final canSave =
        !vm.savingRelay && value.isNotEmpty && value != (vm.relayUrl ?? '');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Relay address',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Server that connects your agents to the phone. Applies to every '
            'agent with the relay enabled.',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: (_) {
                    setState(() => _edited = true);
                    _vm.clearHealth(); // check anterior não vale mais
                  },
                  onSubmitted: (_) {
                    if (canSave) _save();
                  },
                  style: context.typo.mono.copyWith(
                    fontSize: 12.5,
                    color: colors.text,
                  ),
                  placeholder: const Text('https://relay.example.com'),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton(
                onPressed: canSave ? () => _save() : null,
                child: Text(vm.savingRelay ? 'Saving…' : 'Save'),
              ),
            ],
          ),
          if (vm.relayError != null) ...[
            const SizedBox(height: 8),
            Text(
              vm.relayError!,
              style: context.typo.label.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlineButton(
                onPressed: vm.healthState == HealthState.checking
                    ? null
                    : () => vm.checkRelay(_ctrl.text),
                leading: const Icon(Icons.wifi_tethering, size: 15),
                child: const Text('Check'),
              ),
              const SizedBox(width: 12),
              Expanded(child: _HealthIndicator(vm: vm)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resultado do "Verificar" do relay: ponto colorido + texto.
class _HealthIndicator extends StatelessWidget {
  const _HealthIndicator({required this.vm});
  final ConnectivityViewModel vm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (vm.healthState == HealthState.checking) {
      return Row(
        children: [
          CircularProgressIndicator(
            size: 13,
            strokeWidth: 2,
            color: colors.text3,
          ),
          const SizedBox(width: 8),
          Text(
            'Checking…',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      );
    }

    final (Color dot, String label, Color text) = switch (vm.healthState) {
      HealthState.healthy => (colors.online, 'Online', colors.text2),
      HealthState.unhealthy => (
        colors.error,
        vm.healthMessage ?? 'No response',
        colors.error,
      ),
      _ => (colors.text4, 'Not checked', colors.text3),
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typo.label.copyWith(color: text),
          ),
        ),
      ],
    );
  }
}

/// Uma linha da lista de aparelhos pareados (rótulo + shortId + revogar).
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onRevoke});
  final PairedDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(_deviceIcon(device.label), size: 18, color: colors.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.label.isEmpty ? 'Device' : device.label,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.shortId,
                  style: context.typo.mono.copyWith(
                    fontSize: 11.5,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            tooltip: (context) => const TooltipContainer(child: Text('Revoke')),
            child: HoverTap(
              borderRadius: BorderRadius.circular(6),
              onTap: onRevoke,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Icon(Icons.link_off, size: 16, color: colors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão de recarregar (à direita do rótulo da seção). Vira spinner enquanto carrega.
class _ReloadButton extends StatelessWidget {
  const _ReloadButton({required this.busy, required this.onTap});
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('Reload')),
      child: HoverTap(
        borderRadius: BorderRadius.circular(6),
        onTap: busy ? null : () => onTap(),
        child: SizedBox(
          width: 26,
          height: 22,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(4),
                  child: CircularProgressIndicator(
                    size: 14,
                    strokeWidth: 2,
                    color: colors.text3,
                  ),
                )
              : Icon(Icons.refresh, size: 15, color: colors.text3),
        ),
      ),
    );
  }
}

/// Container com a mesma moldura do `_Card`, para mensagens de estado (vazio /
/// carregando / erro) no lugar da lista.
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// Botão de pareamento (abre o dialog com QR). Tonal accent pra diferenciar do
/// Salvar (primário) sem competir com ele.
class _PairButton extends StatelessWidget {
  const _PairButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 17, color: colors.accentText),
          const SizedBox(width: 8),
          Text(
            'Pair new device',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _deviceIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('iphone') || l.contains('ipad') || l.contains('ios')) {
    return Icons.phone_iphone;
  }
  if (l.contains('android')) return Icons.phone_android;
  return Icons.devices_outlined;
}

// ---------------------------------------------------------------------------
// Agendamentos (cron — plan/39)
// ---------------------------------------------------------------------------
class _AgendamentosPanel extends StatefulWidget {
  const _AgendamentosPanel();

  @override
  State<_AgendamentosPanel> createState() => _AgendamentosPanelState();
}

class _AgendamentosPanelState extends State<_AgendamentosPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CronViewModel>().reload();
    });
    // Sem push do supervisor: refaz o list a cada 10s pra refletir disparos
    // agendados, next_run e last_status que mudam fora da UI.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<CronViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openEditor() async {
    final vm = context.read<CronViewModel>();
    if (vm.daemons.isEmpty) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CronEditorDialog(vm: vm),
    );
    if (created == true && mounted) await vm.reload();
  }

  Future<void> _openLog(CronJob job) async {
    final vm = context.read<CronViewModel>();
    await showDialog<void>(
      context: context,
      builder: (_) => _CronLogDialog(vm: vm, job: job),
    );
  }

  Future<void> _confirmRemove(CronJob job) async {
    final vm = context.read<CronViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove schedule?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          'The job "${job.schedule}" for ${vm.daemonName(job.daemonId)} is deleted. '
          'Its runs stop.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.remove(job);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CronViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.actionError != null) ...[
                _ErrorBanner(message: vm.actionError!),
                const SizedBox(height: 12),
              ],
              if (vm.online) ...[
                _cronActions(context, vm),
                const SizedBox(height: 16),
              ],
              _Section(
                label: 'Scheduled prompts',
                trailing: _ReloadButton(
                  busy: vm.load == CronLoad.loading,
                  onTap: vm.reload,
                ),
                child: _body(context, vm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cronActions(BuildContext context, CronViewModel vm) {
    final colors = context.colors;
    return Row(
      children: [
        PrimaryButton(
          onPressed: vm.hasDaemons ? () => _openEditor() : null,
          leading: const Icon(Icons.add, size: 16),
          child: const Text('Create schedule'),
        ),
        if (!vm.hasDaemons) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Create a Daemon Agent first.',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context, CronViewModel vm) {
    final colors = context.colors;

    if (!vm.online && vm.load != CronLoad.loading) {
      return _MessageCard(
        child: Text(
          'Supervisor offline. Schedules need pi-supervisord running '
          '(`remote-pi install`).',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }
    if (vm.load == CronLoad.loading && vm.jobs.isEmpty) {
      return _MessageCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              'Loading…',
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text3,
              ),
            ),
          ],
        ),
      );
    }
    if (vm.load == CronLoad.error && vm.jobs.isEmpty) {
      return _MessageCard(
        child: Text(
          vm.error ?? 'Failed to list schedules.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }
    if (vm.jobs.isEmpty) {
      return _MessageCard(
        child: Text(
          'No schedules. Create a recurring prompt for a daemon.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }
    return _Card(
      children: [
        for (final job in vm.jobs)
          _CronTile(
            job: job,
            daemonName: vm.daemonName(job.daemonId),
            busy: vm.isBusy(job.id),
            onToggle: (v) => vm.setEnabled(job, v),
            onRun: () => vm.run(job),
            onLog: () => _openLog(job),
            onRemove: () => _confirmRemove(job),
          ),
      ],
    );
  }
}

/// Uma linha de agendamento: alvo + schedule + prompt + estado + ações.
class _CronTile extends StatelessWidget {
  const _CronTile({
    required this.job,
    required this.daemonName,
    required this.busy,
    required this.onToggle,
    required this.onRun,
    required this.onLog,
    required this.onRemove,
  });
  final CronJob job;
  final String daemonName;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onRun;
  final Future<void> Function() onLog;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: colors.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        daemonName,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      job.schedule,
                      style: context.typo.mono.copyWith(
                        fontSize: 11.5,
                        color: colors.accentText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  job.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 12.5,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 3),
                _CronMeta(job: job),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            )
          else ...[
            Switch(value: job.enabled, onChanged: onToggle),
            _cronAct(context, Icons.play_arrow, 'Run now', onRun),
            _cronAct(context, Icons.history, 'View log', onLog),
            _cronAct(context, Icons.delete_outline, 'Remove', onRemove),
          ],
        ],
      ),
    );
  }

  Widget _cronAct(
    BuildContext context,
    IconData icon,
    String tip,
    Future<void> Function() onTap,
  ) {
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onTap(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

/// Linha de metadados do job: próximo disparo + último status.
class _CronMeta extends StatelessWidget {
  const _CronMeta({required this.job});
  final CronJob job;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];

    if (!job.enabled) {
      children.add(
        Text(
          'disabled',
          style: context.typo.label.copyWith(color: colors.text4),
        ),
      );
    } else if (job.nextRun != null) {
      children.add(
        Text(
          'next ${_fmtIso(job.nextRun)}',
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      );
    }

    if (job.lastStatus != null) {
      final (color, label) = _cronResultView(
        context,
        cronResultFromWire(job.lastStatus),
      );
      if (children.isNotEmpty) {
        children.add(
          Text(
            '  ·  ',
            style: context.typo.label.copyWith(color: colors.text4),
          ),
        );
      }
      children.add(
        Text('last: $label', style: context.typo.label.copyWith(color: color)),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Dialog de criar agendamento: daemon + cron-expr (com preview) + prompt +
/// opções. Chama `vm.create` direto pra mostrar erro do servidor sem perder o
/// que foi digitado.
class _CronEditorDialog extends StatefulWidget {
  const _CronEditorDialog({required this.vm});
  final CronViewModel vm;

  @override
  State<_CronEditorDialog> createState() => _CronEditorDialogState();
}

class _CronEditorDialogState extends State<_CronEditorDialog> {
  final TextEditingController _expr = TextEditingController();
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _tz = TextEditingController();
  late String _daemonId;
  bool _skipIfBusy = true;
  bool _wake = false;
  bool _catchup = false;
  bool _saving = false;
  String? _localError;

  static const _examples = <(String, String)>[
    ('0 9 * * *', 'every day 9am'),
    ('0 * * * *', 'hourly'),
    ('*/15 * * * *', 'every 15 min'),
    ('0 18 * * 1-5', 'weekdays 6pm'),
  ];

  @override
  void initState() {
    super.initState();
    _daemonId = widget.vm.daemons.first.id;
    _expr.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _expr.dispose();
    _prompt.dispose();
    _tz.dispose();
    super.dispose();
  }

  String get _previewText {
    final expr = _expr.text.trim();
    if (expr.isEmpty) return 'Next run shows up here';
    final next = nextCronRun(expr, DateTime.now());
    if (next == null) return 'Next: computed on save';
    return 'Next: ${_fmtDateTime(next)}';
  }

  Future<void> _submit() async {
    final expr = _expr.text.trim();
    final prompt = _prompt.text.trim();
    if (expr.isEmpty || prompt.isEmpty) {
      setState(() => _localError = 'Fill in the expression and the prompt.');
      return;
    }
    setState(() {
      _saving = true;
      _localError = null;
    });
    final tz = _tz.text.trim();
    final ok = await widget.vm.create(
      daemonId: _daemonId,
      schedule: expr,
      prompt: prompt,
      tz: tz.isEmpty ? null : tz,
      skipIfBusy: _skipIfBusy,
      wake: _wake,
      catchup: _catchup,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _localError = widget.vm.actionError ?? 'Failed to create the schedule.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.vm;

    return AlertDialog(
      title: Text(
        'New schedule',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(context, 'Daemon'),
              const SizedBox(height: 6),
              // Builder garante um BuildContext cujo RenderBox é o próprio chip,
              // não o do AlertDialog — senão o menu ancora fora do dialog.
              Builder(
                builder: (chipContext) => _DropdownChip(
                  label: vm.daemonName(_daemonId),
                  icon: Icons.dns_outlined,
                  onTap: () async {
                    final picked = await showAppMenu<String>(
                      chipContext,
                      minWidth: 220,
                      items: [
                        for (final d in vm.daemons)
                          AppMenuItem(
                            value: d.id,
                            label: d.name.isEmpty ? d.id : d.name,
                            selected: d.id == _daemonId,
                          ),
                      ],
                    );
                    if (picked != null) setState(() => _daemonId = picked);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'When (cron expression)'),
              const SizedBox(height: 6),
              _dialogField(context, _expr, 'e.g. 0 9 * * *', mono: true),
              const SizedBox(height: 6),
              Text(
                _previewText,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (expr, label) in _examples)
                    _ExampleChip(
                      expr: expr,
                      label: label,
                      onTap: () {
                        _expr.text = expr;
                        _expr.selection = TextSelection.collapsed(
                          offset: expr.length,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'Prompt'),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _prompt,
                'e.g. Summarize the new PRs',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, 'Timezone (optional)'),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _tz,
                'e.g. America/Sao_Paulo (empty = system)',
                mono: true,
              ),
              const SizedBox(height: 12),
              _CronOptionSwitch(
                label: 'Skip if the agent is busy',
                value: _skipIfBusy,
                onChanged: (v) => setState(() => _skipIfBusy = v),
              ),
              _CronOptionSwitch(
                label: 'Wake the daemon if stopped',
                value: _wake,
                onChanged: (v) => setState(() => _wake = v),
              ),
              _CronOptionSwitch(
                label: 'Recover 1 missed run (catchup)',
                value: _catchup,
                onChanged: (v) => setState(() => _catchup = v),
              ),
              if (_localError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _localError!,
                  style: context.typo.label.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _saving ? null : _submit,
          child: Text(
            _saving ? 'Creating…' : 'Create',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _dialogField(
    BuildContext context,
    TextEditingController controller,
    String hint, {
    bool mono = false,
    int maxLines = 1,
  }) {
    final colors = context.colors;
    final style = mono
        ? context.typo.mono.copyWith(fontSize: 12.5, color: colors.text)
        : context.typo.body.copyWith(fontSize: 13.5, color: colors.text);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: style,
      placeholder: Text(hint),
      borderRadius: BorderRadius.circular(7),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({
    required this.expr,
    required this.label,
    required this.onTap,
  });
  final String expr;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: context.typo.label.copyWith(color: colors.text2),
      ),
    );
  }
}

class _CronOptionSwitch extends StatelessWidget {
  const _CronOptionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text2,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Dialog de histórico de um job (lê `cron.jsonl` via `cron_log`).
class _CronLogDialog extends StatefulWidget {
  const _CronLogDialog({required this.vm, required this.job});
  final CronViewModel vm;
  final CronJob job;

  @override
  State<_CronLogDialog> createState() => _CronLogDialogState();
}

class _CronLogDialogState extends State<_CronLogDialog> {
  List<CronLogEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.vm.fetchLog(jobId: widget.job.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _error = entries == null
          ? (widget.vm.actionError ?? 'Failed to read the log.')
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'History — ${widget.job.schedule}',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(width: 460, child: _content(context)),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            size: 22,
            strokeWidth: 2,
            color: colors.text3,
          ),
        ),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.error),
      );
    }
    final entries = _entries ?? const <CronLogEntry>[];
    if (entries.isEmpty) {
      return Text(
        'No records yet.',
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
      );
    }
    // Mais recentes primeiro.
    final ordered = entries.reversed.toList(growable: false);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
        itemBuilder: (context, i) {
          final e = ordered[i];
          final (color, label) = _cronResultView(context, e.result);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: context.typo.body.copyWith(
                              fontSize: 12.5,
                              color: color,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _fmtTs(e.tsMs),
                            style: context.typo.mono.copyWith(
                              fontSize: 11,
                              color: colors.text3,
                            ),
                          ),
                        ],
                      ),
                      if (e.promptPreview.isNotEmpty)
                        Text(
                          e.promptPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.label.copyWith(
                            color: colors.text3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- cron helpers ----------------------------------------------------------

(Color, String) _cronResultView(BuildContext context, CronResult r) {
  final colors = context.colors;
  return switch (r) {
    CronResult.delivered => (colors.online, 'delivered'),
    CronResult.wokeAndDelivered => (colors.online, 'woke + delivered'),
    CronResult.deliverFailed => (colors.error, 'failed'),
    CronResult.skippedBusy => (colors.warn, 'skipped (busy)'),
    CronResult.skippedDown => (colors.text4, 'skipped (stopped)'),
    CronResult.skippedDisabled => (colors.text4, 'skipped (disabled)'),
    CronResult.unknown => (colors.text4, '—'),
  };
}

String _fmt2(int n) => n.toString().padLeft(2, '0');

String _fmtDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${_fmt2(l.day)}/${_fmt2(l.month)} ${_fmt2(l.hour)}:${_fmt2(l.minute)}';
}

String _fmtIso(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  return dt == null ? iso : _fmtDateTime(dt);
}

String _fmtTs(int ms) => _fmtDateTime(DateTime.fromMillisecondsSinceEpoch(ms));

// ---------------------------------------------------------------------------
// Daemon Agents
// ---------------------------------------------------------------------------
class _DaemonsPanel extends StatefulWidget {
  const _DaemonsPanel();

  @override
  State<_DaemonsPanel> createState() => _DaemonsPanelState();
}

class _DaemonsPanelState extends State<_DaemonsPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DaemonsViewModel>().reload();
    });
    // Reflete mudanças de estado feitas fora da UI (crash/restart/uptime).
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<DaemonsViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Abre o editor (criar quando [editing] é null; senão edita só o nome).
  /// Valida pasta-única (criar) e nome-único, depois cria ou renomeia+reinicia.
  Future<void> _openEditor([DaemonInfo? editing]) async {
    final vm = context.read<DaemonsViewModel>();
    final others = vm.daemons.where((d) => d.id != editing?.id);
    final result = await showDialog<_DaemonEditorResult>(
      context: context,
      builder: (_) => _DaemonEditorDialog(
        editing: editing,
        existingNames: others
            .map((d) => d.name.trim().toLowerCase())
            .where((n) => n.isNotEmpty)
            .toSet(),
        existingCwds: others.map((d) => d.cwd).toSet(),
      ),
    );
    if (result == null || !mounted) return;
    if (editing == null) {
      await vm.create(result.cwd, name: result.name);
    } else {
      await vm.rename(editing, result.name);
    }
  }

  /// Reiniciar o supervisor é pesado (derruba todos os daemons) → confirma.
  Future<void> _confirmRestartSupervisor() async {
    final vm = context.read<DaemonsViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Restart the supervisor?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          'Restarts the supervisor process (reloads the code). All daemons '
          'restart with it and go offline for a few seconds.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Restart',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.warn,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.restartSupervisor();
  }

  Future<void> _confirmRemove(DaemonInfo daemon) async {
    final vm = context.read<DaemonsViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove daemon?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"${daemon.name}" stops running and leaves the registry. The folder and '
          'its local config are kept — you can recreate it later.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: ctx.typo.body.copyWith(
                fontSize: 13,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await vm.remove(daemon.id);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DaemonsViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.actionError != null) ...[
                _ErrorBanner(message: vm.actionError!),
                const SizedBox(height: 12),
              ],
              if (vm.online) ...[
                _DaemonActionsBar(
                  vm: vm,
                  onCreate: () => _openEditor(),
                  onRestartSupervisor: _confirmRestartSupervisor,
                ),
                const SizedBox(height: 16),
              ],
              _Section(
                label: 'Always-on agents',
                trailing: _ReloadButton(
                  busy: vm.load == DaemonsLoad.loading,
                  onTap: vm.reload,
                ),
                child: _body(context, vm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DaemonsViewModel vm) {
    final colors = context.colors;

    if (!vm.online && vm.load != DaemonsLoad.loading) {
      return _MessageCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.power_off_outlined, size: 16, color: colors.text3),
                const SizedBox(width: 8),
                Text(
                  'Supervisor offline',
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'pi-supervisord is not running. Install it with '
              '`remote-pi install` to manage 24/7 agents.',
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
      );
    }

    if (vm.load == DaemonsLoad.loading && vm.daemons.isEmpty) {
      return _MessageCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            ),
            const SizedBox(width: 10),
            Text(
              'Loading…',
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text3,
              ),
            ),
          ],
        ),
      );
    }

    if (vm.load == DaemonsLoad.error && vm.daemons.isEmpty) {
      return _MessageCard(
        child: Text(
          vm.error ?? 'Failed to list daemons.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.error,
          ),
        ),
      );
    }

    if (vm.daemons.isEmpty) {
      return _MessageCard(
        child: Text(
          'No registered agents. Create one from a folder.',
          style: context.typo.body.copyWith(
            fontSize: 13.5,
            color: colors.text3,
          ),
        ),
      );
    }

    return _Card(
      children: [
        for (final daemon in vm.daemons)
          _DaemonTile(
            daemon: daemon,
            busy: vm.isBusy(daemon.id),
            onStart: () => vm.start(daemon.id),
            onStop: () => vm.stop(daemon.id),
            onRestart: () => vm.restart(daemon.id),
            onEdit: () => _openEditor(daemon),
            onRemove: () => _confirmRemove(daemon),
          ),
      ],
    );
  }
}

/// Barra de ações: criar daemon + controles da frota + reiniciar supervisor.
class _DaemonActionsBar extends StatelessWidget {
  const _DaemonActionsBar({
    required this.vm,
    required this.onCreate,
    required this.onRestartSupervisor,
  });
  final DaemonsViewModel vm;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRestartSupervisor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDaemons = vm.daemons.isNotEmpty;
    final fleetEnabled = hasDaemons && !vm.busyAll;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PrimaryButton(
          onPressed: () => onCreate(),
          leading: const Icon(Icons.add, size: 16),
          child: const Text('Create daemon'),
        ),
        if (vm.busyAll)
          CircularProgressIndicator(
            size: 15,
            strokeWidth: 2,
            color: colors.text3,
          ),
        _FleetButton(
          label: 'Start all',
          icon: Icons.play_arrow,
          onTap: fleetEnabled ? vm.startAll : null,
        ),
        _FleetButton(
          label: 'Stop all',
          icon: Icons.stop,
          onTap: fleetEnabled ? vm.stopAll : null,
        ),
        _FleetButton(
          label: 'Restart all',
          icon: Icons.restart_alt,
          onTap: fleetEnabled ? vm.restartAll : null,
        ),
        _FleetButton(
          label: 'Restart supervisor',
          icon: Icons.sync,
          tint: colors.warn,
          onTap: vm.busyAll ? null : onRestartSupervisor,
        ),
      ],
    );
  }
}

class _FleetButton extends StatelessWidget {
  const _FleetButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
  });
  final String label;
  final IconData icon;
  final Future<void> Function()? onTap;

  /// Cor opcional (texto + borda) — usada pra destacar ações mais pesadas.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final fg = enabled ? (tint ?? colors.text2) : colors.text4;
    return OutlineButton(
      onPressed: onTap == null ? null : () => onTap!(),
      leading: Icon(icon, size: 14, color: fg),
      child: Text(label, style: TextStyle(fontSize: 12.5, color: fg)),
    );
  }
}

/// Uma linha de daemon: badge de estado + nome + métricas + ações.
class _DaemonTile extends StatelessWidget {
  const _DaemonTile({
    required this.daemon,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onEdit,
    required this.onRemove,
  });
  final DaemonInfo daemon;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRestart;
  final Future<void> Function() onEdit;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final running = daemon.state == DaemonState.running;
    final (Color dotColor, String stateLabel) = _stateView(
      context,
      daemon.state,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  daemon.name.isEmpty ? daemon.id : daemon.name,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(stateLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.mono.copyWith(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            CircularProgressIndicator(
              size: 16,
              strokeWidth: 2,
              color: colors.text3,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botão único iniciar/parar (alterna conforme o estado).
                _act(
                  context,
                  running ? Icons.stop : Icons.play_arrow,
                  running ? 'Stop' : 'Start',
                  running ? onStop : onStart,
                ),
                if (running)
                  _act(context, Icons.restart_alt, 'Restart', onRestart),
                _act(context, Icons.edit_outlined, 'Edit', onEdit),
                _act(context, Icons.delete_outline, 'Remove', onRemove),
              ],
            ),
        ],
      ),
    );
  }

  String _subtitle(String stateLabel) {
    final parts = <String>[stateLabel];
    if (daemon.pid != null) parts.add('pid ${daemon.pid}');
    if (daemon.uptimeSeconds != null) {
      parts.add(_fmtUptime(daemon.uptimeSeconds!));
    }
    if ((daemon.restartCount ?? 0) > 0) parts.add('↻${daemon.restartCount}');
    parts.add(daemon.cwd);
    return parts.join('  ·  ');
  }

  (Color, String) _stateView(BuildContext context, DaemonState state) {
    final colors = context.colors;
    return switch (state) {
      DaemonState.running => (colors.online, 'running'),
      DaemonState.starting => (colors.warn, 'starting'),
      DaemonState.stopped => (colors.text4, 'stopped'),
      DaemonState.crashed => (colors.error, 'failed'),
      DaemonState.unknown => (colors.text4, '—'),
    };
  }

  Widget _act(
    BuildContext context,
    IconData icon,
    String tip,
    Future<void> Function() onTap,
  ) {
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onTap(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.typo.label.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtUptime(int s) {
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  if (h < 24) return '${h}h${m % 60}m';
  final d = h ~/ 24;
  return '${d}d${h % 24}h';
}

/// Resultado do editor de daemon: pasta (fixa na edição) + nome.
class _DaemonEditorResult {
  const _DaemonEditorResult({required this.cwd, required this.name});
  final String cwd;
  final String name;
}

/// Dialog de criar/editar daemon. Na criação escolhe a pasta + nome; na edição
/// (`editing != null`) a pasta fica travada e só o nome muda. Valida nome único
/// (sempre) e pasta única (só na criação) contra os daemons existentes.
class _DaemonEditorDialog extends StatefulWidget {
  const _DaemonEditorDialog({
    required this.editing,
    required this.existingNames,
    required this.existingCwds,
  });
  final DaemonInfo? editing;
  final Set<String> existingNames; // nomes (lowercased) dos OUTROS daemons
  final Set<String> existingCwds; // cwds dos OUTROS daemons

  @override
  State<_DaemonEditorDialog> createState() => _DaemonEditorDialogState();
}

class _DaemonEditorDialogState extends State<_DaemonEditorDialog> {
  late final TextEditingController _nameCtrl;
  String? _cwd;
  String? _nameError;
  String? _pathError;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editing?.name ?? '');
    _cwd = widget.editing?.cwd;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the Daemon Agent folder',
    );
    if (picked == null || !mounted) return;
    // A checagem de pasta-duplicada aqui é best-effort (compara o caminho
    // escolhido com os já registrados). O `remote-pi create` normaliza pra
    // realpath e rejeita duplicata (inclusive via symlink) como backstop.
    setState(() {
      _cwd = picked;
      _pathError = null;
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    String? nameError;
    String? pathError;

    if (name.isEmpty) {
      nameError = 'Enter a name.';
    } else if (widget.existingNames.contains(name.toLowerCase())) {
      nameError = 'An agent with this name already exists.';
    }
    if (!_isEdit) {
      if (_cwd == null) {
        pathError = 'Choose a folder.';
      } else if (widget.existingCwds.contains(_cwd)) {
        pathError = 'An agent already exists in this folder.';
      }
    }

    if (nameError != null || pathError != null) {
      setState(() {
        _nameError = nameError;
        _pathError = pathError;
      });
      return;
    }
    Navigator.of(context).pop(
      _DaemonEditorResult(
        cwd: _isEdit ? widget.editing!.cwd : _cwd!,
        name: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: Text(
        _isEdit ? 'Edit daemon' : 'New daemon',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Name'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => _submit(),
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text,
              ),
              placeholder: const Text('e.g. PC, Server, Home'),
              borderRadius: BorderRadius.circular(7),
            ),
            if (_nameError != null) ...[
              const SizedBox(height: 6),
              Text(
                _nameError!,
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 16),
            _label(context, 'Folder'),
            const SizedBox(height: 6),
            if (_isEdit)
              SizedBox(
                width: double.infinity,
                child: _pathBox(context, _cwd ?? '', enabled: false),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _pathBox(
                      context,
                      _cwd ?? 'No folder chosen',
                      enabled: _cwd != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    onPressed: () => _pickFolder(),
                    child: Text(_cwd == null ? 'Choose' : 'Change'),
                  ),
                ],
              ),
            if (_isEdit) ...[
              const SizedBox(height: 6),
              Text(
                'The folder cannot be changed.',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
            if (_pathError != null) ...[
              const SizedBox(height: 6),
              Text(
                _pathError!,
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _submit,
          child: Text(
            _isEdit ? 'Save' : 'Create',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _pathBox(BuildContext context, String text, {required bool enabled}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.typo.mono.copyWith(
          fontSize: 11.5,
          color: enabled ? colors.text2 : colors.text3,
        ),
      ),
    );
  }
}
