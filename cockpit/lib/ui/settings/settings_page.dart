import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:cockpit/domain/entities/daemon_info.dart';
import 'package:cockpit/domain/entities/paired_device.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/cockpit/widgets/code_highlight.dart';
import 'package:cockpit/ui/cockpit/widgets/window_controls.dart';
import 'package:cockpit/ui/settings/connectivity_viewmodel.dart';
import 'package:cockpit/ui/settings/daemons_viewmodel.dart';
import 'package:cockpit/ui/settings/pairing_controller.dart';
import 'package:cockpit/ui/settings/pairing_dialog.dart';
import 'package:cockpit/ui/settings/revoke_controller.dart';
import 'package:cockpit/ui/settings/revoke_dialog.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

/// Tela cheia de Configurações (push). Categorias à esquerda (Aparência ·
/// Conectividade) e o conteúdo à direita. Por ora só **Aparência** está
/// implementada; Conectividade chega na próxima fase.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _Category { appearance, connectivity, daemons, scheduling }

class _SettingsPageState extends State<SettingsPage> {
  _Category _category = _Category.appearance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          const _SettingsHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryNav(
                  selected: _category,
                  onSelect: (c) => setState(() => _category = c),
                ),
                Expanded(
                  child: switch (_category) {
                    _Category.appearance => const _AppearancePanel(),
                    _Category.connectivity => const _ConnectivityPanel(),
                    _Category.daemons => const _DaemonsPanel(),
                    _Category.scheduling => const _ComingSoonPanel(
                      title: 'Agendamentos',
                      message:
                          'Agendar prompts e rotinas para os seus agentes '
                          'chega em breve.',
                    ),
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
    return DragToMoveArea(
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 18, right: 12),
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            const WindowControls(),
            const SizedBox(width: 14),
            Tooltip(
              message: 'Voltar',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => context.pop(),
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: colors.text2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Configurações',
              style: context.typo.title.copyWith(
                fontSize: 14,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryNav extends StatelessWidget {
  const _CategoryNav({required this.selected, required this.onSelect});
  final _Category selected;
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
            label: 'Aparência',
            selected: selected == _Category.appearance,
            onTap: () => onSelect(_Category.appearance),
          ),
          _NavItem(
            icon: Icons.wifi_tethering,
            label: 'Conectividade',
            selected: selected == _Category.connectivity,
            onTap: () => onSelect(_Category.connectivity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Divider(height: 1, thickness: 1, color: colors.border),
          ),
          _NavItem(
            icon: Icons.dns_outlined,
            label: 'Daemon Agents',
            selected: selected == _Category.daemons,
            onTap: () => onSelect(_Category.daemons),
          ),
          _NavItem(
            icon: Icons.schedule_outlined,
            label: 'Agendamentos',
            selected: selected == _Category.scheduling,
            onTap: () => onSelect(_Category.scheduling),
          ),
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
      child: Material(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
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
                label: 'Tema',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Tema',
                      trailing: _ThemeDropdown(
                        value: s.themeMode,
                        onChanged: controller.setThemeMode,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                label: 'Fontes',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Fonte da interface',
                      description:
                          'Usada em todo o app. Vazio = padrão do sistema.',
                      trailing: _FontField(
                        value: s.interfaceFont,
                        hint: 'Space Grotesk · Hanken',
                        onChanged: controller.setInterfaceFont,
                      ),
                    ),
                    _Row(
                      title: 'Tamanho da interface',
                      trailing: _SizeStepper(
                        value: s.interfaceSize,
                        min: 11,
                        max: 22,
                        onChanged: controller.setInterfaceSize,
                      ),
                    ),
                    _Row(
                      title: 'Fonte do código',
                      description:
                          'Código e diffs. Vazio = padrão do sistema.',
                      trailing: _FontField(
                        value: s.codeFont,
                        hint: 'JetBrains Mono',
                        onChanged: controller.setCodeFont,
                      ),
                    ),
                    _Row(
                      title: 'Tamanho do código',
                      trailing: _SizeStepper(
                        value: s.codeSize,
                        min: 9,
                        max: 20,
                        onChanged: controller.setCodeSize,
                      ),
                    ),
                    _Row(
                      title: 'Fonte do terminal',
                      description:
                          'Usa o tamanho do código. Vazio = padrão do sistema.',
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
                          title: 'Tema de highlight',
                          description:
                              'Cores do código, independentes do tema do app.',
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
                label: 'Conversa',
                child: _Card(
                  children: [
                    _Row(
                      title: 'Pinar mensagem do usuário',
                      description:
                          'A pergunta fica fixa no topo enquanto a resposta '
                          'rola.',
                      trailing: Switch.adaptive(
                        value: s.pinUserMessage,
                        activeTrackColor: context.colors.accent,
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
      child: span == null
          ? Text(_sample, style: base)
          : Text.rich(span),
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
  const _Row({
    required this.title,
    required this.trailing,
    this.description,
  });
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
    return Material(
      color: colors.panel3,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
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
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down, size: 16, color: colors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeDropdown extends StatelessWidget {
  const _ThemeDropdown({required this.value, required this.onChanged});
  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const _meta = <AppThemeMode, ({String label, IconData icon})>{
    AppThemeMode.system: (label: 'Sistema', icon: Icons.desktop_windows_outlined),
    AppThemeMode.light: (label: 'Claro', icon: Icons.light_mode_outlined),
    AppThemeMode.dark: (label: 'Escuro', icon: Icons.dark_mode_outlined),
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
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: context.typo.body.copyWith(
            fontSize: 13,
            color: colors.text3,
          ),
          filled: true,
          fillColor: colors.panel3,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 9,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
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
    return InkWell(
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
    final paired = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeNotifierProvider<PairingController>(
        create: (_) => vm.newPairingController()..start(),
        child: const PairingDialog(),
      ),
    );
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
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.panel2,
        title: Text(
          'Revogar aparelho?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"$name" perderá o acesso aos seus agentes e precisará parear de novo.'
          '\n\nÉ preciso estar conectado ao relay — o app vai conectar '
          'automaticamente para revogar.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Revogar',
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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<RevokeController>(
        create: (_) => vm.newRevokeController()..run(device),
        child: const RevokeDialog(),
      ),
    );
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
                label: 'Aparelhos pareados',
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
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.text3,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Carregando…',
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
          vm.devicesError ?? 'Falha ao listar os aparelhos.',
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.error),
        ),
      );
    }

    if (vm.devices.isEmpty) {
      return _MessageCard(
        child: Text(
          'Nenhum aparelho pareado.',
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
        ),
      );
    }

    return _Card(
      children: [
        for (final device in vm.devices)
          _DeviceTile(
            device: device,
            onRevoke: () => _confirmRevoke(device),
          ),
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

    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: c),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Endereço do relay',
            style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text),
          ),
          const SizedBox(height: 3),
          Text(
            'Servidor que conecta seus agentes ao celular. Vale para todo agente '
            'com o relay ligado.',
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
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'https://relay.exemplo.com',
                    hintStyle: context.typo.mono.copyWith(
                      fontSize: 12.5,
                      color: colors.text3,
                    ),
                    filled: true,
                    fillColor: colors.panel3,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 11,
                    ),
                    border: border(colors.border),
                    enabledBorder: border(colors.border),
                    focusedBorder: border(colors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  disabledBackgroundColor: colors.panel3,
                  disabledForegroundColor: colors.text4,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed: canSave ? () => _save() : null,
                child: Text(vm.savingRelay ? 'Salvando…' : 'Salvar'),
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
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.text2,
                  side: BorderSide(color: colors.border2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: vm.healthState == HealthState.checking
                    ? null
                    : () => vm.checkRelay(_ctrl.text),
                icon: const Icon(Icons.wifi_tethering, size: 15),
                label: const Text('Verificar'),
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
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.text3),
          ),
          const SizedBox(width: 8),
          Text(
            'Verificando…',
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      );
    }

    final (Color dot, String label, Color text) = switch (vm.healthState) {
      HealthState.healthy => (colors.online, 'Online', colors.text2),
      HealthState.unhealthy => (
        colors.error,
        vm.healthMessage ?? 'Sem resposta',
        colors.error,
      ),
      _ => (colors.text4, 'Não verificado', colors.text3),
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
                  device.label.isEmpty ? 'Aparelho' : device.label,
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
            message: 'Revogar',
            child: InkWell(
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
      message: 'Recarregar',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: busy ? null : () => onTap(),
        child: SizedBox(
          width: 26,
          height: 22,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(4),
                  child: CircularProgressIndicator(
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
    return Material(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2, size: 17, color: colors.accentText),
              const SizedBox(width: 8),
              Text(
                'Parear novo aparelho',
                style: context.typo.body.copyWith(
                  fontSize: 13.5,
                  color: colors.accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
// Placeholder genérico (Agendamentos por ora)
// ---------------------------------------------------------------------------
class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_outlined, size: 28, color: colors.text3),
            const SizedBox(height: 12),
            Text(
              title,
              style: context.typo.title.copyWith(fontSize: 15, color: colors.text2),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daemon Agents
// ---------------------------------------------------------------------------
class _DaemonsPanel extends StatefulWidget {
  const _DaemonsPanel();

  @override
  State<_DaemonsPanel> createState() => _DaemonsPanelState();
}

class _DaemonsPanelState extends State<_DaemonsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DaemonsViewModel>().reload();
    });
  }

  Future<void> _create() async {
    final vm = context.read<DaemonsViewModel>();
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta do Daemon Agent',
    );
    if (dir == null || !mounted) return;
    final name = await _askName(dir);
    if (!mounted || name == null) return; // null = cancelado
    await vm.create(dir, name: name.isEmpty ? null : name);
  }

  Future<String?> _askName(String dir) async {
    final controller = TextEditingController();
    final colors = context.colors;
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.panel2,
          title: Text(
            'Nome do agente',
            style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dir,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ctx.typo.mono.copyWith(fontSize: 11.5, color: colors.text3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Opcional — padrão: nome da pasta',
                  hintStyle: ctx.typo.body.copyWith(fontSize: 13, color: colors.text3),
                  filled: true,
                  fillColor: colors.panel3,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancelar',
                style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(
                'Criar',
                style: ctx.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _confirmRemove(DaemonInfo daemon) async {
    final vm = context.read<DaemonsViewModel>();
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.panel2,
        title: Text(
          'Remover daemon?',
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          '"${daemon.name}" para de rodar e sai do registro. A pasta e o config '
          'local são mantidos — dá pra recriar depois.',
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remover',
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
              _Section(
                label: 'Agentes sempre ativos',
                trailing: _ReloadButton(
                  busy: vm.load == DaemonsLoad.loading,
                  onTap: vm.reload,
                ),
                child: _body(context, vm),
              ),
              if (vm.online) ...[
                _DaemonActionsBar(vm: vm, onCreate: _create),
              ],
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
              'O pi-supervisord não está rodando. Instale-o com '
              '`remote-pi install` para gerenciar agentes 24/7.',
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
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.text3),
            ),
            const SizedBox(width: 10),
            Text(
              'Carregando…',
              style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
            ),
          ],
        ),
      );
    }

    if (vm.load == DaemonsLoad.error && vm.daemons.isEmpty) {
      return _MessageCard(
        child: Text(
          vm.error ?? 'Falha ao listar os daemons.',
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.error),
        ),
      );
    }

    if (vm.daemons.isEmpty) {
      return _MessageCard(
        child: Text(
          'Nenhum agente registrado. Crie um a partir de uma pasta.',
          style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
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
            onRemove: () => _confirmRemove(daemon),
          ),
      ],
    );
  }
}

/// Barra de ações: criar daemon + controles da frota inteira.
class _DaemonActionsBar extends StatelessWidget {
  const _DaemonActionsBar({required this.vm, required this.onCreate});
  final DaemonsViewModel vm;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDaemons = vm.daemons.isNotEmpty;
    final fleetEnabled = hasDaemons && !vm.busyAll;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () => onCreate(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Criar daemon'),
          ),
          const Spacer(),
          if (vm.busyAll)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: colors.text3),
              ),
            ),
          _FleetButton(
            label: 'Iniciar',
            icon: Icons.play_arrow,
            onTap: fleetEnabled ? vm.startAll : null,
          ),
          const SizedBox(width: 8),
          _FleetButton(
            label: 'Parar',
            icon: Icons.stop,
            onTap: fleetEnabled ? vm.stopAll : null,
          ),
          const SizedBox(width: 8),
          _FleetButton(
            label: 'Reiniciar',
            icon: Icons.restart_alt,
            onTap: fleetEnabled ? vm.restartAll : null,
          ),
        ],
      ),
    );
  }
}

class _FleetButton extends StatelessWidget {
  const _FleetButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text2,
        disabledForegroundColor: colors.text4,
        side: BorderSide(color: colors.border2),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap == null ? null : () => onTap!(),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
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
    required this.onRemove,
  });
  final DaemonInfo daemon;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRestart;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final running = daemon.state == DaemonState.running;
    final (Color dotColor, String stateLabel) = _stateView(context, daemon.state);

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
                  style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(stateLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.mono.copyWith(fontSize: 11, color: colors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.text3),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running) ...[
                  _act(context, Icons.stop, 'Parar', onStop),
                  _act(context, Icons.restart_alt, 'Reiniciar', onRestart),
                ] else
                  _act(context, Icons.play_arrow, 'Iniciar', onStart),
                _act(context, Icons.delete_outline, 'Remover', onRemove),
              ],
            ),
        ],
      ),
    );
  }

  String _subtitle(String stateLabel) {
    final parts = <String>[stateLabel];
    if (daemon.pid != null) parts.add('pid ${daemon.pid}');
    if (daemon.uptimeSeconds != null) parts.add(_fmtUptime(daemon.uptimeSeconds!));
    if ((daemon.restartCount ?? 0) > 0) parts.add('↻${daemon.restartCount}');
    parts.add(daemon.cwd);
    return parts.join('  ·  ');
  }

  (Color, String) _stateView(BuildContext context, DaemonState state) {
    final colors = context.colors;
    return switch (state) {
      DaemonState.running => (colors.online, 'rodando'),
      DaemonState.starting => (colors.warn, 'iniciando'),
      DaemonState.stopped => (colors.text4, 'parado'),
      DaemonState.crashed => (colors.error, 'falhou'),
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
      message: tip,
      child: InkWell(
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
