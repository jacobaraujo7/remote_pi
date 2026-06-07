import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/cockpit/widgets/window_controls.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
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

enum _Category { appearance, connectivity }

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
                    _Category.connectivity => const _ComingSoonPanel(
                      title: 'Conectividade',
                      message:
                          'Relay, status online e pareamento de aparelhos '
                          'chegam na próxima etapa.',
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
                          'Código, diffs e terminal. Vazio = padrão do sistema.',
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
                  ],
                ),
              ),
              _Section(
                label: 'Syntax',
                child: _Card(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              style: context.typo.title.copyWith(
                fontSize: 15,
                color: colors.text2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blocos reutilizáveis
// ---------------------------------------------------------------------------
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: context.typo.label.copyWith(color: colors.text3),
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
