import 'dart:async';
import 'dart:io';

// Hosts remotos (plano 58): RemoteHostsController é infra compartilhada (como
// AutomationController), provida app-scoped no bootstrapper. A aba os gerencia.
import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart'
    show RemoteHostPhase;
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/cockpit/ui/remote/add_remote_host_dialog.dart';
import 'package:cockpit/app/cockpit/ui/remote/remote_hosts_controller.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/domain/services/automation_model_catalog.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:cockpit/app/core/ui/automation_error_message.dart';
import 'package:cockpit/app/core/ui/widgets/macos_notification_instructions_dialog.dart';
import 'package:cockpit/app/settings/domain/cron_schedule.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/ui/widgets/error_report_dialog.dart';
import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:flutter/services.dart';
import 'package:cockpit/app/core/utils/native_folder_picker.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart'
    show terminalEngineIsSelectable;
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
import 'package:cockpit/app/settings/ui/shortcut_catalog.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/theme_store_error_message.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:path/path.dart' as p;
import 'package:cockpit/app/core/ui/font_catalog.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/settings/ui/font_picker_dialog.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tela cheia de Configurações (push). Categorias à esquerda (Aparência ·
/// Conectividade) e o conteúdo à direita. Por ora só **Aparência** está
/// implementada; Conectividade chega na próxima fase.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialTab});

  /// Aba a abrir de cara (deep-link via `pushNamed(arguments:)`). `null` = padrão.
  final SettingsTab? initialTab;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _Category {
  general,
  appearance,
  terminal,
  languages,
  automations,
  shortcuts,
  notifications,
  remoteHosts,
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

  /// Abas escondidas no mobile (plano 59): motor-local ou desktop-only. Sobram
  /// General, Appearance, Shortcuts, Notifications e Remote hosts.
  bool get hiddenOnMobile =>
      this == _Category.terminal ||
      this == _Category.languages ||
      this == _Category.automations ||
      isRemote;
}

class _SettingsPageState extends State<SettingsPage> {
  _Category _category = _Category.general;

  /// Abaixo desta largura (mobile portrait) o nav de categorias vira DRAWER —
  /// senão a lista à esquerda espreme o painel e fica ilegível (plano 60).
  static const double _drawerBreakpoint = 600;
  bool _navOpen = false;

  @override
  void initState() {
    super.initState();
    // Deep-link: abrir já numa aba (ex.: WelcomeView do mobile → Remote hosts,
    // onde mora a chave do device). O argumento vem do pushNamed.
    if (widget.initialTab == SettingsTab.remoteHosts) {
      _category = _Category.remoteHosts;
    }
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
    // No mobile, abas motor-local/desktop-only não existem → cai pra General.
    final category = (isMobilePlatform && _category.hiddenOnMobile)
        ? _Category.general
        : (!remoteReady && _category.isRemote)
        ? _Category.appearance
        : _category;
    final narrow =
        isMobilePlatform &&
        MediaQuery.sizeOf(context).width < _drawerBreakpoint;

    final Widget panel = switch (category) {
      _Category.general => const _GeneralPanel(),
      _Category.appearance => const _AppearancePanel(),
      _Category.terminal => const _TerminalPanel(),
      _Category.languages => const _LanguagesPanel(),
      _Category.automations => const _AutomationsPanel(),
      _Category.shortcuts => const _ShortcutsPanel(),
      _Category.notifications => const _NotificationsPanel(),
      _Category.remoteHosts => const _RemoteHostsPanel(),
      _Category.connectivity => const _ConnectivityPanel(),
      _Category.daemons => const _DaemonsPanel(),
      _Category.scheduling => const _AgendamentosPanel(),
    };

    final nav = _CategoryNav(
      selected: category,
      remoteReady: remoteReady,
      // No estreito, escolher categoria fecha o drawer (revela o painel).
      onSelect: (c) => setState(() {
        _category = c;
        _navOpen = false;
      }),
    );

    return Scaffold(
      backgroundColor: colors.bg,
      child: Column(
        children: [
          _SettingsHeader(
            onToggleNav: narrow
                ? () => setState(() => _navOpen = !_navOpen)
                : null,
          ),
          Expanded(
            child: narrow
                ? Stack(
                    children: [
                      Positioned.fill(child: panel),
                      if (_navOpen) ...[
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _navOpen = false),
                            child: ColoredBox(color: colors.scrim),
                          ),
                        ),
                        Positioned(left: 0, top: 0, bottom: 0, child: nav),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nav,
                      Expanded(child: panel),
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
  const _SettingsHeader({this.onToggleNav});

  /// Mobile portrait: abre/fecha o drawer de categorias. `null` = layout largo
  /// (nav inline), sem botão.
  final VoidCallback? onToggleNav;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WindowTitleBar(
      children: [
        const WindowControls(),
        const SizedBox(width: 14),
        AppTooltip(
          message: context.t.settings.page.header.back,
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
          context.t.settings.page.header.title,
          style: context.typo.title.copyWith(fontSize: 14, color: colors.text),
        ),
        if (onToggleNav != null) ...[
          const SizedBox(width: 10),
          HoverTap(
            borderRadius: BorderRadius.circular(6),
            onTap: onToggleNav,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(Icons.menu, size: 18, color: colors.text2),
            ),
          ),
        ],
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
      // Fundo opaco: no drawer (mobile portrait) o nav fica SOBRE o painel —
      // sem cor, o painel apareceria através dele. No layout largo é a mesma cor
      // do Scaffold, então nada muda.
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          _NavItem(
            icon: Icons.tune,
            label: context.t.settings.page.nav.general,
            selected: selected == _Category.general,
            onTap: () => onSelect(_Category.general),
          ),
          _NavItem(
            icon: Icons.palette_outlined,
            label: context.t.settings.page.nav.appearance,
            selected: selected == _Category.appearance,
            onTap: () => onSelect(_Category.appearance),
          ),
          // Terminal / Languages / Automations: motor-local, ocultos no mobile.
          if (!isMobilePlatform) ...[
            _NavItem(
              icon: Icons.terminal_outlined,
              label: context.t.settings.page.nav.terminal,
              selected: selected == _Category.terminal,
              onTap: () => onSelect(_Category.terminal),
            ),
            _NavItem(
              icon: Icons.code,
              label: context.t.settings.page.nav.language,
              selected: selected == _Category.languages,
              onTap: () => onSelect(_Category.languages),
            ),
            _NavItem(
              icon: Icons.auto_awesome_outlined,
              label: context.t.settings.page.nav.automations,
              selected: selected == _Category.automations,
              onTap: () => onSelect(_Category.automations),
            ),
          ],
          _NavItem(
            icon: Icons.keyboard_outlined,
            label: context.t.settings.page.nav.shortcuts,
            selected: selected == _Category.shortcuts,
            onTap: () => onSelect(_Category.shortcuts),
          ),
          _NavItem(
            icon: Icons.notifications_outlined,
            label: context.t.settings.page.nav.notifications,
            selected: selected == _Category.notifications,
            onTap: () => onSelect(_Category.notifications),
          ),
          // Hosts remotos (plano 58, SSH) — sempre disponível, não depende do
          // ambiente remote-pi (extensão/supervisor).
          _NavItem(
            icon: Icons.cloud_outlined,
            label: context.t.settings.page.nav.remoteHosts,
            selected: selected == _Category.remoteHosts,
            onTap: () => onSelect(_Category.remoteHosts),
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
              label: context.t.settings.page.nav.connectivity,
              selected: selected == _Category.connectivity,
              onTap: () => onSelect(_Category.connectivity),
            ),
            _NavItem(
              icon: Icons.dns_outlined,
              label: context.t.settings.page.nav.daemonAgents,
              selected: selected == _Category.daemons,
              onTap: () => onSelect(_Category.daemons),
            ),
            _NavItem(
              icon: Icons.schedule_outlined,
              label: context.t.settings.page.nav.schedules,
              selected: selected == _Category.scheduling,
              onTap: () => onSelect(_Category.scheduling),
            ),
          ],
          // Empurra a versão pro rodapé do nav (identificação visual da build).
          const Spacer(),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

/// Rodapé do nav: "Cockpit `version`" no canto inferior esquerdo, pra
/// identificar visualmente qual build está rodando. A versão vem do
/// `PackageInfo` (mesma fonte do self-update), carregada de forma assíncrona.
class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _version == null ? 'Cockpit' : 'Cockpit $_version',
          style: context.typo.label.copyWith(color: colors.text4),
        ),
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
// General
// ---------------------------------------------------------------------------
class _GeneralPanel extends StatelessWidget {
  const _GeneralPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    // `agentTabsInUse` é publicado pelo shell (cross-route) via bridge app-scoped.
    final agentsInUse = context.watch<WorkspaceMenuBridge>().agentTabsInUse;
    final tr = context.t.settings.page.general;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Agent / Cockpit / Updates: motor-local + self-update = desktop.
              // No mobile some tudo; sobram Idioma/Storage/Diagnostics.
              if (!isMobilePlatform) ...[
                _Section(
                  label: tr.sectionAgent,
                  child: _Card(
                    children: [
                      _Row(
                        title: tr.enableAgentsTitle,
                        description: tr.enableAgentsDesc,
                        // Mantém o switch clicável: tentar DESLIGAR com um agente
                        // em uso mostra um erro explicando o porquê (em vez de um
                        // switch inerte, sem feedback). Ligar é sempre permitido.
                        trailing: Switch(
                          value: s.enableAgent,
                          onChanged: (value) {
                            if (!value && agentsInUse) {
                              _notifyAgentsInUse(context);
                              return;
                            }
                            controller.setEnableAgent(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                _Section(
                  label: 'Cockpit',
                  child: _Card(
                    children: [
                      _Row(
                        title: tr.showCockpitTitle,
                        description: tr.showCockpitDesc,
                        trailing: Switch(
                          value: s.showCockpit,
                          onChanged: controller.setShowCockpit,
                        ),
                      ),
                      _Row(
                        title: tr.launchAtStartupTitle,
                        description: tr.launchAtStartupDesc,
                        trailing: Switch(
                          value: s.launchAtStartup,
                          onChanged: controller.setLaunchAtStartup,
                        ),
                      ),
                    ],
                  ),
                ),
                _Section(
                  label: tr.sectionUpdates,
                  child: _Card(
                    children: [
                      _Row(
                        title: tr.checkUpdatesTitle,
                        description: tr.checkUpdatesDesc,
                        trailing: _UpdateCheckDropdown(
                          value: s.updateCheckFrequency,
                          onChanged: controller.setUpdateCheckFrequency,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _Section(
                label: context.t.settings.language.title,
                child: _Card(
                  children: [
                    _Row(
                      title: context.t.settings.language.title,
                      trailing: _LocaleDropdown(
                        value: s.locale,
                        onChanged: controller.setLocale,
                      ),
                    ),
                  ],
                ),
              ),
              // Local de Armazenamento: escolher pasta/relocar não se aplica ao
              // mobile (sandbox do app, sem pastas do usuário como no desktop).
              if (!isMobilePlatform) const _StorageSection(),
              const _DiagnosticsSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// Erro ao tentar desligar agentes com uma aba de agente aberta.
  void _notifyAgentsInUse(BuildContext context) {
    final colors = context.colors;
    showToast(
      context: context,
      location: ToastLocation.bottomRight,
      builder: (context, overlay) => SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 18, color: colors.error),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  context.t.settings.page.general.agentsInUseError,
                  style: context.typo.label.copyWith(color: colors.text),
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
// Automations
// ---------------------------------------------------------------------------

class _AutomationsPanel extends StatefulWidget {
  const _AutomationsPanel();

  @override
  State<_AutomationsPanel> createState() => _AutomationsPanelState();
}

class _AutomationsPanelState extends State<_AutomationsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_discoverAndReconcile());
    });
  }

  Future<void> _discoverAndReconcile({bool force = false}) async {
    final automation = context.read<AutomationController>();
    final settings = context.read<SettingsController>();
    if (force) {
      await automation.refresh();
    } else {
      await automation.ensureInitialized();
    }
    if (!mounted) return;
    automation.reconcileStaleModel(
      harnessId: settings.settings.automationHarnessId,
      modelId: settings.settings.selectedAutomationModelId,
      clearToCliDefault: () => settings.setAutomationModel(null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final automation = context.watch<AutomationController>();
    final settings = context.watch<SettingsController>();
    final selected = automation.harnessFor(
      settings.settings.automationHarnessId,
    );
    final selectedId = settings.settings.automationHarnessId;
    final modelId = settings.settings.selectedAutomationModelId;
    final colors = context.colors;
    final tr = context.t.settings.page.automations;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: tr.sectionCommitMessages,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.harness,
                      description: automation.discovering
                          ? tr.harnessDiscovering
                          : automation.harnesses.isEmpty
                          ? tr.harnessNoneFound
                          : selected == null && selectedId != null
                          ? tr.harnessConfiguredUnavailable(
                              harness: selectedId.label,
                            )
                          : selected == null
                          ? tr.harnessChoose
                          : selected.executablePath,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AutomationHarnessDropdown(
                            selected: selectedId,
                            harnesses: automation.harnesses,
                            onChanged: settings.setAutomationHarness,
                          ),
                          const SizedBox(width: 8),
                          AppTooltip(
                            message: tr.harnessRefresh,
                            child: IconButton.outline(
                              onPressed: automation.discovering
                                  ? null
                                  : () => unawaited(
                                      _discoverAndReconcile(force: true),
                                    ),
                              icon: automation.discovering
                                  ? const CircularProgressIndicator(size: 14)
                                  : const Icon(Icons.refresh, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selectedId != null)
                      _Row(
                        title: tr.model,
                        description: selected == null
                            ? tr.modelUnavailable
                            : selectedId.pinnedModelId != null
                            ? tr.modelAutoRouted
                            : selected.models.isEmpty
                            ? tr.modelCliOnly
                            : tr.modelAccountOnly,
                        trailing: _AutomationModelDropdown(
                          value: modelId,
                          harness: selected,
                          onChanged: settings.setAutomationModel,
                        ),
                      ),
                    _Row(
                      title: tr.generateFromSourceControl,
                      description: tr.generateFromSourceControlDescription,
                      trailing: Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: selected == null ? colors.text4 : colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (automation.error != null)
                Text(
                  automationErrorMessage(context, automation.error!),
                  style: context.typo.label.copyWith(color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomationHarnessDropdown extends StatelessWidget {
  const _AutomationHarnessDropdown({
    required this.selected,
    required this.harnesses,
    required this.onChanged,
  });

  final HarnessKind? selected;
  final List<AutomationHarness> harnesses;
  final ValueChanged<HarnessKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _DropdownChip(
      label:
          selected?.label ?? context.t.settings.page.automations.notConfigured,
      leading: selected == null ? null : _HarnessIcon(selected!),
      onTap: () async {
        final picked = await showAppMenu<Object>(
          context,
          minWidth: 190,
          items: <AppMenuItem<Object>>[
            AppMenuItem<Object>(
              value: 'disabled',
              label: context.t.settings.page.automations.notConfigured,
              selected: selected == null,
            ),
            for (final harness in harnesses)
              AppMenuItem<Object>(
                value: harness.id,
                label: harness.label,
                leading: _HarnessIcon(harness.id),
                selected: selected == harness.id,
              ),
          ],
        );
        if (picked == 'disabled') onChanged(null);
        if (picked is HarnessKind) onChanged(picked);
      },
    );
  }
}

class _AutomationModelDropdown extends StatelessWidget {
  const _AutomationModelDropdown({
    required this.value,
    required this.harness,
    required this.onChanged,
  });

  final String? value;
  final AutomationHarness? harness;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.page.automations;
    final models = harness?.models ?? const <AutomationModel>[];
    final defaultId = harness?.defaultModelId;
    final known = models.where((model) => model.id == value).firstOrNull;
    // Sem escolha explícita o rótulo mostra para onde o harness vai cair:
    // "Auto" quando ele roteia sozinho, "CLI default" quando não.
    final fallbackLabel = defaultId == kAutomationAutoModelId
        ? tr.modelAuto
        : tr.modelCliDefault;
    return _DropdownChip(
      label: known?.label ?? value ?? fallbackLabel,
      // Harness com modelo fixo (Copilot em `auto`) não oferece escolha.
      onTap: harness?.allowsModelChoice != true
          ? null
          : () async {
              final picked = await showAppMenu<String>(
                context,
                minWidth: 220,
                searchHint: tr.modelSearch(count: models.length),
                collapsedLimit: AutomationModelCatalog.curatedLimit,
                items: [
                  AppMenuItem<String>(
                    value: '',
                    label: fallbackLabel,
                    selected: value == null,
                  ),
                  for (final model in models)
                    AppMenuItem<String>(
                      value: model.id,
                      // O "· Recomendado" é texto de UI, não faz parte do nome
                      // do modelo — por isso mora aqui e não no label da
                      // entidade.
                      label: model.id == defaultId
                          ? '${model.label} · ${tr.recommendedSuffix}'
                          : model.label,
                      selected: value == model.id,
                    ),
                ],
              );
              if (picked != null) onChanged(picked.isEmpty ? null : picked);
            },
    );
  }
}

/// Logo do harness — o mesmo SVG que a aba de terminal usa (catálogo único).
class _HarnessIcon extends StatelessWidget {
  const _HarnessIcon(this.kind);

  final HarnessKind kind;

  @override
  Widget build(BuildContext context) {
    final spec = kind.spec;
    return SvgPicture.asset(
      spec.assetPath,
      width: 15,
      height: 15,
      colorFilter: spec.isMonochrome
          ? ColorFilter.mode(context.colors.text3, BlendMode.srcIn)
          : null,
    );
  }
}

// Storage (General) — pasta de dados escolhível + reset
// ---------------------------------------------------------------------------

/// Seção "Storage": mostra onde o Cockpit guarda seu estado, deixa o usuário
/// apontar pra outra pasta (ex.: um diretório sincronizado) e oferece um reset
/// de fábrica. Trocar a pasta ou resetar **exige reiniciar** — a UI informa e
/// oferece fechar o app na hora.
/// Diagnóstico: acesso ao log e caminho para reportar um problema sem depender
/// de um erro estar acontecendo agora — é como o usuário abre issue de um bug
/// que já passou (o log do dia continua lá).
class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection();

  @override
  Widget build(BuildContext context) {
    final dir = DiagnosticsLog.instance.directory;
    final tr = context.t.settings.page.diagnostics;
    return _Section(
      label: tr.sectionTitle,
      child: _Card(
        children: [
          _Row(
            title: tr.logFileTitle,
            description: tr.logFileDesc(
              days: DiagnosticsLog.retentionDays,
              path: dir?.path ?? tr.unavailable,
            ),
            trailing: OutlineButton(
              onPressed: dir == null ? null : () => _revealFolder(dir.path),
              child: Text(tr.reveal),
            ),
          ),
          _Row(
            title: tr.reportTitle,
            description: tr.reportDesc,
            trailing: OutlineButton(
              onPressed: () => showErrorReportDialog(
                context,
                title: tr.reportDialogTitle,
                error: tr.reportDialogError,
                description: tr.reportDialogDescription,
              ),
              child: Text(tr.reportButton),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre a pasta no gerenciador de arquivos do SO.
  ///
  /// **Windows**: o Explorer só entende `\` — passar `C:/Users/...` faz ele
  /// abrir a pasta Documentos em silêncio, sem erro. Como os caminhos internos
  /// do Cockpit são montados com `/`, a conversão precisa acontecer aqui, na
  /// fronteira com o SO. (O Explorer também sai com código != 0 mesmo quando dá
  /// certo, então o exit code é ignorado de propósito.)
  Future<void> _revealFolder(String path) async {
    final (command, target) = switch (Platform.operatingSystem) {
      'macos' => ('open', path),
      'windows' => ('explorer', path.replaceAll('/', r'\')),
      _ => ('xdg-open', path),
    };
    try {
      await Process.run(command, [target]);
    } on ProcessException catch (e) {
      DiagnosticsLog.instance.logError('settings', e, null);
    }
  }
}

class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  String? _root; // raiz efetiva (pasta que o usuário "vê")
  bool _custom = false;
  bool _loading = true;
  bool _busy = false; // durante copy/pick, evita cliques repetidos

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final root = await StorageLocation.effectiveRoot();
    final custom = await StorageLocation.isCustom();
    if (!mounted) return;
    setState(() {
      _root = root;
      _custom = custom;
      _loading = false;
    });
  }

  Future<void> _changeFolder() async {
    if (_busy) return;
    final tr = context.t.settings.page.storage;
    final picked = await NativeFolderPicker.pick(
      dialogTitle: tr.chooseFolderDialogTitle,
      initialDirectory: _root, // abre na pasta atual do Cockpit
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    // Copia os dados atuais pra nova pasta (se estiver vazia) — evita a
    // surpresa de "meus projetos sumiram" após o restart.
    await StorageLocation.migrateStateTo(picked);
    await StorageLocation.setOverrideRoot(picked);
    if (!mounted) return;
    setState(() => _busy = false);
    await _promptRestart(tr.restartChangeFolderMessage(path: picked));
  }

  Future<void> _useDefault() async {
    if (_busy) return;
    await StorageLocation.setOverrideRoot(null);
    if (!mounted) return;
    await _promptRestart(
      context.t.settings.page.storage.restartUseDefaultMessage,
    );
  }

  Future<void> _reset() async {
    final confirmed = await _confirmReset();
    if (confirmed != true || !mounted) return;
    await StorageLocation.resetAll();
    if (!mounted) return;
    await _promptRestart(
      context.t.settings.page.storage.restartResetMessage,
      quitOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.settings.page.storage;
    return _Section(
      label: tr.sectionTitle,
      child: _Card(
        children: [
          _Row(
            title: tr.locationTitle,
            description: _loading
                ? context.t.common.loading
                : tr.locationDesc(root: _root ?? '—'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_custom) ...[
                  GhostButton(
                    onPressed: _loading || _busy ? null : _useDefault,
                    child: Text(tr.useDefault),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlineButton(
                  onPressed: _loading || _busy ? null : _changeFolder,
                  child: Text(_busy ? tr.working : tr.change),
                ),
              ],
            ),
          ),
          _Row(
            title: tr.resetTitle,
            description: tr.resetDesc,
            trailing: DestructiveButton(
              onPressed: _loading ? null : _reset,
              child: Text(
                tr.resetButton,
                style: TextStyle(color: colors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmação destrutiva do reset.
  Future<bool?> _confirmReset() {
    return showDialog<bool>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (context) {
        final colors = context.colors;
        final tr = context.t.settings.page.storage;
        return AlertDialog(
          title: Text(
            tr.resetDialogTitle,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              tr.resetDialogContent,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text2,
              ),
            ),
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.cancel),
            ),
            DestructiveButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                tr.resetConfirm,
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Informa que a mudança só vale no próximo boot e oferece fechar agora.
  /// [quitOnly] esconde o "Later" (reset já apagou tudo — continuar seria
  /// esquisito), mas nunca força o fechamento sem o clique do usuário.
  Future<void> _promptRestart(String message, {bool quitOnly = false}) {
    return showDialog<void>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (context) {
        final colors = context.colors;
        final tr = context.t.settings.page.storage;
        return AlertDialog(
          title: Text(
            tr.restartRequiredTitle,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              message,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text2,
              ),
            ),
          ),
          actions: [
            if (!quitOnly)
              GhostButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr.later),
              ),
            PrimaryButton(
              // Encerra abrupto de propósito: descarta escritas pendentes nas
              // boxes antigas (já migradas/apagadas), sem recriar arquivos no
              // caminho velho via o save de window_state no onWindowClose.
              // Marca saída limpa antes: `exit()` não dispara o
              // `onExitRequested`, e sem isso o próximo boot acusaria crash.
              onPressed: () {
                DiagnosticsLog.instance.markCleanExit();
                exit(0);
              },
              child: Text(tr.quitCockpit),
            ),
          ],
        );
      },
    );
  }
}

// Aparência
// ---------------------------------------------------------------------------
/// **Terminal** — escolhe o motor VT e, no Windows, o shell padrão.
///
/// O padrão é gravado **por id** (`defaultTerminalProfileId`), nunca o objeto:
/// os perfis são re-descobertos a cada boot. Sem escolha (ou com um id que
/// sumiu — uma distro WSL desinstalada), o `effectiveDefault` cai no fallback da
/// plataforma, que é o PowerShell — e é ele que aparece marcado aqui, porque é o
/// que de fato vai abrir.
class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    // `inject` e não construtor: este painel não é um ViewModel, e o resolver é
    // um bind root-owned do core (sem estado de página). Cache já aquecido no
    // boot — `cachedProfiles` é síncrono.
    final resolver = inject<TerminalProfileResolver>();
    final profiles = resolver.cachedProfiles;
    // O que o `+` abre HOJE — já resolve config ausente/inválida no fallback.
    final effective = resolver.effectiveDefault(
      controller.settings.defaultTerminalProfileId,
    );
    final tr = context.t.settings.page.terminal;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: tr.sectionDefaultTerminal,
                child: _Card(
                  children: [
                    // O seletor de engine some no Windows: Ghostty ainda engole
                    // teclas lá (bug do flterm), então a plataforma fica travada
                    // no xterm (ver `terminalEngineIsSelectable`).
                    if (terminalEngineIsSelectable)
                      _Row(
                        title: tr.engineTitle,
                        description: tr.engineDesc,
                        trailing: _TerminalEngineDropdown(
                          value: controller.settings.terminalEngine,
                          onChanged: controller.setTerminalEngine,
                        ),
                      ),
                    if (Platform.isWindows)
                      _Row(
                        title: tr.shellTitle,
                        description: tr.shellDesc,
                        trailing: _TerminalProfileDropdown(
                          profiles: profiles,
                          value: effective,
                          onChanged: (p) =>
                              controller.setDefaultTerminalProfileId(p.id),
                        ),
                      ),
                  ],
                ),
              ),
              // Sem WSL instalado a lista tem só PowerShell e cmd. Dizer isso é
              // melhor que deixar o usuário achar que a detecção falhou.
              if (!profiles.any(
                (p) => p.id.startsWith(TerminalProfile.wslPrefix),
              ))
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: Text(
                    tr.noWslMessage,
                    style: context.typo.label.copyWith(
                      color: context.colors.text3,
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

class _TerminalEngineDropdown extends StatelessWidget {
  const _TerminalEngineDropdown({required this.value, required this.onChanged});

  final TerminalEngine value;
  final ValueChanged<TerminalEngine> onChanged;

  @override
  Widget build(BuildContext context) {
    String label(TerminalEngine engine) => switch (engine) {
      TerminalEngine.ghostty => 'Ghostty',
      TerminalEngine.xterm => 'xterm',
    };

    return _DropdownChip(
      icon: Icons.terminal,
      label: label(value),
      onTap: () async {
        final picked = await showAppMenu<TerminalEngine>(
          context,
          minWidth: 180,
          items: [
            for (final engine in TerminalEngine.values)
              AppMenuItem(value: engine, label: label(engine)),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TerminalWeightDropdown extends StatelessWidget {
  const _TerminalWeightDropdown({required this.value, required this.onChanged});

  final TerminalFontWeight value;
  final ValueChanged<TerminalFontWeight> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.page.appearance;
    String label(TerminalFontWeight weight) => switch (weight) {
      TerminalFontWeight.auto => tr.terminalWeightAuto,
      TerminalFontWeight.light => tr.terminalWeightLight,
      TerminalFontWeight.normal => tr.terminalWeightNormal,
      TerminalFontWeight.medium => tr.terminalWeightMedium,
      TerminalFontWeight.semiBold => tr.terminalWeightSemiBold,
    };

    return _DropdownChip(
      icon: Icons.format_bold,
      label: label(value),
      onTap: () async {
        final picked = await showAppMenu<TerminalFontWeight>(
          context,
          minWidth: 200,
          items: [
            for (final weight in TerminalFontWeight.values)
              AppMenuItem(value: weight, label: label(weight)),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TerminalProfileDropdown extends StatelessWidget {
  const _TerminalProfileDropdown({
    required this.profiles,
    required this.value,
    required this.onChanged,
  });

  final List<TerminalProfile> profiles;
  final TerminalProfile value;
  final ValueChanged<TerminalProfile> onChanged;

  /// Mesmo mapa do seletor do `+` — `IconData` é do Flutter, então não mora no
  /// `TerminalProfile` (agnóstico de UI por design).
  static IconData _iconFor(TerminalProfile p) {
    if (p.id.startsWith(TerminalProfile.wslPrefix)) return Icons.dns_outlined;
    if (p.id == TerminalProfile.cmdId) return Icons.terminal_outlined;
    return Icons.code;
  }

  @override
  Widget build(BuildContext context) {
    return _DropdownChip(
      icon: _iconFor(value),
      label: value.label,
      onTap: () async {
        final picked = await showAppMenu<String>(
          context,
          minWidth: 200,
          items: [
            for (final p in profiles)
              AppMenuItem(
                value: p.id,
                label: p.label,
                icon: _iconFor(p),
                selected: p.id == value.id,
              ),
          ],
        );
        if (picked == null) return;
        final profile = profiles.where((p) => p.id == picked).firstOrNull;
        if (profile != null) onChanged(profile);
      },
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel();

  /// Descrição da linha "Modo". Um tema pode trazer só um dos dois variants;
  /// nesse caso escolher claro/escuro não muda nada, e é melhor dizer isso do
  /// que deixar o usuário achar que o controle está quebrado.
  String _modeDescription(BuildContext context, SettingsController controller) {
    final tr = context.t.settings.page.appearance;
    final theme = controller.activeTheme;
    if (theme.hasDark && theme.hasLight) return tr.modeDesc;
    return theme.hasDark
        ? tr.modeOnlyDark(theme: theme.name)
        : tr.modeOnlyLight(theme: theme.name);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final tr = context.t.settings.page.appearance;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tema e modo claro/escuro moram na MESMA seção: "modo" é uma
              // faceta do tema (qual variant dele usar), não uma preferência
              // paralela. Separados, a tela mostrava duas coisas chamadas
              // "Theme" e o usuário tinha de adivinhar qual era qual.
              _Section(
                label: tr.sectionTheme,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Card(
                      children: [
                        _Row(
                          title: tr.themeTitle,
                          description: tr.themeDesc,
                          // `activeTheme.id` e não `s.themeId`: um id salvo que
                          // não existe mais (tema removido do disco, ou built-in
                          // que saiu numa atualização) resolve pro default, e o
                          // seletor tem que mostrar o que está pintando a tela.
                          trailing: _ThemeDropdown(
                            value: controller.activeTheme.id,
                            onChanged: controller.setThemeId,
                          ),
                        ),
                        _Row(
                          title: tr.modeTitle,
                          description: _modeDescription(context, controller),
                          trailing: _ThemeModeDropdown(
                            value: s.themeMode,
                            onChanged: controller.setThemeMode,
                          ),
                        ),
                        const _ThemeFileRow(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const _ThemePreview(),
                  ],
                ),
              ),
              _Section(
                label: tr.sectionFonts,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.interfaceFontTitle,
                      description: tr.interfaceFontDesc,
                      trailing: _FontField(
                        value: s.interfaceFont,
                        hint: 'Space Grotesk · Hanken',
                        onChanged: controller.setInterfaceFont,
                      ),
                    ),
                    _Row(
                      title: tr.interfaceSizeTitle,
                      trailing: _SizeStepper(
                        value: s.interfaceSize,
                        min: 11,
                        max: 22,
                        onChanged: controller.setInterfaceSize,
                      ),
                    ),
                    _Row(
                      title: tr.codeFontTitle,
                      description: tr.codeFontDesc,
                      trailing: _FontField(
                        value: s.codeFont,
                        hint: 'JetBrains Mono',
                        monospacedOnly: true,
                        onChanged: controller.setCodeFont,
                      ),
                    ),
                    _Row(
                      title: tr.codeSizeTitle,
                      trailing: _SizeStepper(
                        value: s.codeSize,
                        min: 9,
                        max: 20,
                        onChanged: controller.setCodeSize,
                      ),
                    ),
                    _Row(
                      title: tr.terminalFontTitle,
                      description: tr.terminalFontDesc,
                      trailing: _FontField(
                        value: s.terminalFont,
                        hint: 'Menlo · monospace',
                        monospacedOnly: true,
                        onChanged: controller.setTerminalFont,
                      ),
                    ),
                    _Row(
                      title: tr.terminalSizeTitle,
                      description: tr.terminalSizeDesc,
                      trailing: _OptionalSizeStepper(
                        value: s.terminalSize,
                        inherited: s.codeSize,
                        min: 9,
                        max: 24,
                        onChanged: controller.setTerminalSize,
                      ),
                    ),
                    _Row(
                      title: tr.terminalWeightTitle,
                      description: tr.terminalWeightDesc,
                      trailing: _TerminalWeightDropdown(
                        value: s.terminalFontWeight,
                        onChanged: controller.setTerminalFontWeight,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                label: tr.sectionConversation,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.pinUserMessageTitle,
                      description: tr.pinUserMessageDesc,
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
    final tr = context.t.settings.page.notifications;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: tr.sectionTitle,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.enableTitle,
                      description: tr.enableDesc,
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
              _Section(
                label: tr.soundsTitle,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.soundVolumeTitle,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Slider(
                              value: SliderValue.single(s.soundVolume),
                              min: 0,
                              max: 100,
                              onChanged: (v) =>
                                  controller.setSoundVolume(v.value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${s.soundVolume.round()}%',
                              textAlign: TextAlign.right,
                              style: context.typo.label.copyWith(
                                color: context.colors.text3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final event in SoundEvent.values)
                      _SoundEventRow(event: event),
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

/// Linha de um [SoundEvent]: toggle + áudio custom (`.wav`/`.mp3`) com
/// preview e volta ao padrão. O arquivo escolhido é **copiado** pro storage
/// pelo controller ([SettingsController.importSoundOverride]); "reset" apaga a
/// cópia e volta ao som embarcado.
class _SoundEventRow extends StatefulWidget {
  const _SoundEventRow({required this.event});
  final SoundEvent event;

  @override
  State<_SoundEventRow> createState() => _SoundEventRowState();
}

class _SoundEventRowState extends State<_SoundEventRow> {
  /// Player do preview, criado no primeiro uso (re-`open` reinicia o som).
  Player? _player;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _preview(String? customPath, double volume) async {
    final player = _player ??= Player();
    final media = customPath != null && File(customPath).existsSync()
        ? Media(customPath)
        : Media('asset:///assets/sounds/${widget.event.defaultAsset}');
    try {
      await player.setVolume(volume.clamp(0, 100));
      await player.open(media);
    } catch (_) {
      // preview é best-effort; o fallback pro embarcado acontece em runtime
    }
  }

  Future<void> _choose() async {
    final controller = context.read<SettingsController>();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3'],
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;
    await controller.importSoundOverride(widget.event, path);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final tr = context.t.settings.page.notifications;
    final colors = context.colors;

    final (title, description) = switch (widget.event) {
      SoundEvent.turnDone => (tr.soundTurnDone, tr.soundTurnDoneDesc),
      SoundEvent.actionRequired => (
        tr.soundActionRequired,
        tr.soundActionRequiredDesc,
      ),
      SoundEvent.agentError => (tr.soundAgentError, tr.soundAgentErrorDesc),
    };
    final customPath = s.soundOverrides[widget.event];
    final enabled = s.soundEvents[widget.event] ?? true;
    final onActiveTab = s.soundOnActiveTab[widget.event] ?? false;
    // `agentError` sempre toca (inclusive na aba ativa) — sem toggle.
    final hasActiveTabToggle = widget.event != SoundEvent.agentError;

    return _Row(
      title: title,
      description: customPath == null
          ? description
          : tr.soundCustom(name: p.basename(customPath)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTooltip(
            message: tr.soundPreview,
            child: IconButton.ghost(
              icon: Icon(Icons.volume_up_outlined, size: 16),
              onPressed: () => unawaited(_preview(customPath, s.soundVolume)),
            ),
          ),
          AppTooltip(
            message: tr.soundChooseFile,
            child: IconButton.ghost(
              icon: Icon(Icons.folder_open_outlined, size: 16),
              onPressed: () => unawaited(_choose()),
            ),
          ),
          if (customPath != null)
            AppTooltip(
              message: tr.soundReset,
              child: IconButton.ghost(
                icon: Icon(Icons.replay, size: 16, color: colors.text3),
                onPressed: () => unawaited(
                  context.read<SettingsController>().clearSoundOverride(
                    widget.event,
                  ),
                ),
              ),
            ),
          if (hasActiveTabToggle)
            AppTooltip(
              message: tr.soundOnActiveTab,
              child: IconButton.ghost(
                icon: Icon(
                  Icons.tab,
                  size: 16,
                  color: onActiveTab ? colors.accent : colors.text3,
                ),
                onPressed: () =>
                    controller.setSoundOnActiveTab(widget.event, !onActiveTab),
              ),
            ),
          const SizedBox(width: 8),
          Switch(
            value: enabled,
            onChanged: (v) => controller.setSoundEventEnabled(widget.event, v),
          ),
        ],
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
    final tr = context.t.settings.page.notifications;
    return _Row(
      title: tr.systemPermissionTitle,
      description: granted ? tr.grantedDesc : tr.notGrantedDesc,
      trailing: granted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.online),
                const SizedBox(width: 6),
                Text(
                  tr.granted,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              ],
            )
          : SecondaryButton(
              onPressed: _request,
              child: Text(tr.requestPermission),
            ),
    );
  }
}

/// Amostra de código realçada com o tema de syntax atual (atualiza ao trocar o
/// dropdown). Usa o `context.syntax` (fundo + cores) e o `buildCodeSpan`.
/// Preview do tema: como o **código** e o **terminal** vão aparecer, no mesmo
/// campo em que aparecem no app.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

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
    final colors = context.colors;
    final tr = context.t.settings.page.appearance;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // O MESMO campo para código e terminal — é o que a unificação faz, e o
        // preview só prova isso se os dois dividirem um retângulo só, sem
        // costura no meio. `syntax.background` já é este valor; ler daqui
        // deixa a intenção explícita.
        color: colors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewSection(
            label: tr.previewCode,
            child: span == null ? Text(_sample, style: base) : Text.rich(span),
          ),
          // Divisor fino, não uma borda: o campo continua; o que muda é o que
          // está desenhado em cima dele.
          Container(height: 1, color: colors.border),
          _PreviewSection(
            label: tr.previewTerminal,
            child: _TerminalPreviewLines(mono: base),
          ),
        ],
      ),
    );
  }
}

/// Um bloco rotulado dentro do preview. O rótulo é discreto de propósito: quem
/// olha aqui quer ver as cores, não ler.
class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.typo.label.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.8,
              color: context.colors.text4,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

/// Amostra da paleta **ANSI** do tema: prompt, caminho, saída e cursor. Antes
/// nenhuma tela mostrava isso — o terminal entrou no tema junto com a UI, mas
/// só dava para conferir abrindo uma aba e trocando de tema no escuro.
class _TerminalPreviewLines extends StatelessWidget {
  const _TerminalPreviewLines({required this.mono});
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final term = context.terminalTheme;
    TextSpan span(String text, Color color) => TextSpan(
      text: text,
      style: mono.copyWith(color: color),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              span('➜  ', term.green),
              span('cockpit ', term.blue),
              span('git:', term.brightBlack),
              span('(main) ', term.magenta),
              span('flutter test', term.foreground),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              span('00:18 ', term.brightBlack),
              span('+814', term.green),
              span(': ', term.brightBlack),
              span('All tests passed!', term.foreground),
              // Cursor como bloco: é a peça do terminal que mais depende do
              // tema e a que some primeiro num tema mal calibrado.
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Container(
                    width: 7,
                    height: (mono.fontSize ?? 12.5) * 1.15,
                    color: term.cursor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Blocos reutilizáveis
// ---------------------------------------------------------------------------
// Shortcuts (read-only)
// ---------------------------------------------------------------------------

/// Aba **Shortcuts**: lista os atalhos de teclado do app, agrupados por área,
/// só pra consulta — customização fica pra uma fase futura (exigiria um
/// registry central que as camadas de handlers consultem). Fonte:
/// [buildShortcutCatalog], que resolve ⌘/Ctrl pela plataforma.
class _ShortcutsPanel extends StatelessWidget {
  const _ShortcutsPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sections = buildShortcutCatalog();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 20),
                child: Text(
                  context.t.settings.page.shortcuts.notCustomizable,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ),
              for (final section in sections)
                _Section(
                  label: section.title,
                  child: _Card(
                    children: [
                      for (final shortcut in section.items)
                        _Row(
                          title: shortcut.label,
                          description: shortcut.note,
                          trailing: _ShortcutKeys(keys: shortcut.keys),
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

/// Fileira de "keycaps": um chip por tecla do atalho.
class _ShortcutKeys extends StatelessWidget {
  const _ShortcutKeys({required this.keys});
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colors.panel3,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              keys[i],
              style: context.typo.mono.copyWith(
                fontSize: 12,
                color: colors.text2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Remote hosts (plano 58)
// ---------------------------------------------------------------------------

class _RemoteHostsPanel extends StatelessWidget {
  const _RemoteHostsPanel();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteHostsController>();
    final tr = context.t.settings.remoteHosts;
    final colors = context.colors;
    final hosts = controller.hosts;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ajuda: a pessoa precisa saber que o host tem que ter o Cockpit
              // (desktop) ou o cockpit-server instalado + a chave autorizada.
              _Section(
                label: tr.helpTitle,
                child: _Card(
                  children: [
                    _Row(title: tr.helpTitle, description: tr.helpBody),
                  ],
                ),
              ),
              // Chave do dispositivo (mobile): o iPad/Android não tem ~/.ssh,
              // então mostramos a pública gerada pra o usuário autorizar no host.
              if (isMobilePlatform) _DeviceKeySection(controller: controller),
              _Section(
                label: tr.title,
                child: _Card(
                  children: [
                    _Row(
                      title: tr.title,
                      description: tr.description,
                      trailing: PrimaryButton(
                        onPressed: () => _add(context, controller),
                        child: Text(tr.add),
                      ),
                    ),
                  ],
                ),
              ),
              if (hosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    tr.empty,
                    textAlign: TextAlign.center,
                    style: context.typo.body.copyWith(color: colors.text3),
                  ),
                )
              else
                _Card(
                  children: [
                    for (final h in hosts)
                      _Row(
                        title: h.name,
                        description:
                            '${h.sshTarget}  ·  ${_statusLabel(context, controller.phaseOf(h.id))}'
                            '  ·  ${tr.workspacesCount(count: controller.pins.where((p) => p.hostId == h.id).length)}',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Host fora do ar: atalho pra tentar já. O retry
                            // automático segue rodando em paralelo (backoff até
                            // 30s); este botão só antecipa a próxima tentativa.
                            if (controller.isDisconnected(h.id)) ...[
                              GhostButton(
                                onPressed: () => controller.reconnect(h.id),
                                child: Text(tr.reconnect),
                              ),
                              const SizedBox(width: 4),
                            ],
                            GhostButton(
                              onPressed: () => _edit(context, controller, h),
                              child: Text(tr.edit),
                            ),
                            const SizedBox(width: 4),
                            GhostButton(
                              onPressed: () => _remove(context, controller, h),
                              child: Text(
                                tr.remove,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, RemoteHostPhase phase) {
    final tr = context.t.settings.remoteHosts;
    return switch (phase) {
      RemoteHostPhase.connected => tr.statusConnected,
      RemoteHostPhase.openingTunnel ||
      RemoteHostPhase.installingServer ||
      RemoteHostPhase.connecting => tr.statusConnecting,
      // Reconectando tem rótulo PRÓPRIO: dizer "conectando" aqui escondia a
      // diferença entre uma abertura em curso e um host que caiu e está no
      // ciclo de retry — os dois pareciam a mesma coisa presa para sempre.
      RemoteHostPhase.reconnecting => tr.statusReconnecting,
      RemoteHostPhase.failed => tr.statusOffline,
      RemoteHostPhase.idle => tr.statusIdle,
    };
  }

  Future<void> _add(
    BuildContext context,
    RemoteHostsController controller,
  ) async {
    final draft = await showAddRemoteHostDialog(context);
    if (draft == null) return;
    await controller.addHost(
      name: draft.name,
      sshTarget: draft.sshTarget,
      port: draft.port,
      auth: draft.auth,
      password: draft.password,
      identityFile: draft.identityFile,
    );
  }

  Future<void> _edit(
    BuildContext context,
    RemoteHostsController controller,
    RemoteHost host,
  ) async {
    final hasPassword = await controller.hasStoredPassword(host.id);
    if (!context.mounted) return;
    final draft = await showAddRemoteHostDialog(
      context,
      initialName: host.name,
      initialSshTarget: host.sshTarget,
      initialPort: host.port,
      initialAuth: host.auth,
      initialIdentityFile: host.identityFile,
      hasStoredPassword: hasPassword,
      edit: true,
    );
    if (draft == null) return;
    await controller.editHost(
      host.id,
      name: draft.name,
      sshTarget: draft.sshTarget,
      port: draft.port,
      auth: draft.auth,
      password: draft.password,
      identityFile: draft.identityFile,
    );
  }

  Future<void> _remove(
    BuildContext context,
    RemoteHostsController controller,
    RemoteHost host,
  ) async {
    final tr = context.t.settings.remoteHosts;
    final ok = await showConfirmDialog(
      context,
      title: tr.removeTitle,
      message: tr.removeMessage(name: host.name),
      confirmLabel: context.t.common.remove,
      danger: true,
    );
    if (!ok) return;
    await controller.removeHost(host.id);
  }
}

/// Chave pública deste dispositivo (mobile): mono-box + copiar. Gera a chave na
/// 1ª renderização (via controller → MobileSshKeyStore, guardada no Keychain).
class _DeviceKeySection extends StatelessWidget {
  const _DeviceKeySection({required this.controller});

  final RemoteHostsController controller;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.remoteHosts;
    final colors = context.colors;
    return _Section(
      label: tr.deviceKeyTitle,
      child: _Card(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr.deviceKeyDesc,
                  style: context.typo.body.copyWith(color: colors.text2),
                ),
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: controller.devicePublicKey(),
                  builder: (context, snap) {
                    final key = snap.data ?? '';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.panel3,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.border),
                          ),
                          child: SelectableText(
                            key.isEmpty ? '…' : key,
                            style: context.typo.mono.copyWith(
                              fontSize: 12,
                              color: colors.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SecondaryButton(
                            onPressed: key.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: key),
                                    );
                                    if (!context.mounted) return;
                                    showToast(
                                      context: context,
                                      location: ToastLocation.bottomRight,
                                      builder: (context, _) => SurfaceCard(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(tr.deviceKeyCopied),
                                        ),
                                      ),
                                    );
                                  },
                            leading: const Icon(Icons.copy, size: 15),
                            child: Text(tr.deviceKeyCopy),
                          ),
                        ),
                      ],
                    );
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
  const _Row({required this.title, this.trailing, this.description});
  final String title;
  final String? description;
  final Widget? trailing;

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
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

/// Gatilho de dropdown (rótulo + chevron) que abre o `showAppMenu`.
class _DropdownChip extends StatelessWidget {
  const _DropdownChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
  });
  final String label;
  final IconData? icon;

  /// Ícone rico à esquerda (ex.: logo SVG do harness). Vence [icon].
  final Widget? leading;

  /// `null` desabilita o gatilho: o valor está fixo e não há o que escolher
  /// (harness com roteamento automático obrigatório).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return HoverTap(
      color: enabled ? colors.panel3 : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 7),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: colors.text2),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: enabled ? colors.text : colors.text3,
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 16, color: colors.text3),
          ],
        ],
      ),
    );
  }
}

class _ThemeModeDropdown extends StatelessWidget {
  const _ThemeModeDropdown({required this.value, required this.onChanged});
  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.page.appearance;
    final meta = <AppThemeMode, ({String label, IconData icon})>{
      AppThemeMode.system: (
        label: tr.themeSystem,
        icon: Icons.desktop_windows_outlined,
      ),
      AppThemeMode.light: (
        label: tr.themeLight,
        icon: Icons.light_mode_outlined,
      ),
      AppThemeMode.dark: (label: tr.themeDark, icon: Icons.dark_mode_outlined),
    };
    final current = meta[value]!;
    return _DropdownChip(
      icon: current.icon,
      label: current.label,
      onTap: () async {
        final picked = await showAppMenu<AppThemeMode>(
          context,
          minWidth: 180,
          items: [
            for (final e in meta.entries)
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

/// Opções de idioma da interface. `system` = seguir o locale do SO
/// (`AppSettings.locale == null`); as demais mapeiam pro código raw persistido
/// e repassado ao `slang` (`LocaleSettings.setLocaleRaw`).
enum _LocaleOption { system, en, es, ptBr }

class _LocaleDropdown extends StatelessWidget {
  const _LocaleDropdown({required this.value, required this.onChanged});

  /// Código raw persistido (`null` = System). Ver [AppSettings.locale].
  final String? value;
  final ValueChanged<String?> onChanged;

  static const _codes = <_LocaleOption, String?>{
    _LocaleOption.system: null,
    _LocaleOption.en: 'en',
    _LocaleOption.es: 'es',
    _LocaleOption.ptBr: 'pt-BR',
  };

  _LocaleOption _optionOf(String? code) => switch (code) {
    'en' => _LocaleOption.en,
    'es' => _LocaleOption.es,
    'pt-BR' => _LocaleOption.ptBr,
    _ => _LocaleOption.system,
  };

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.language;
    final labels = <_LocaleOption, ({String label, IconData icon})>{
      _LocaleOption.system: (
        label: tr.system,
        icon: Icons.desktop_windows_outlined,
      ),
      _LocaleOption.en: (label: tr.english, icon: Icons.language),
      _LocaleOption.es: (label: tr.spanish, icon: Icons.language),
      _LocaleOption.ptBr: (label: tr.portugueseBr, icon: Icons.language),
    };
    final current = _optionOf(value);
    final currentMeta = labels[current]!;
    return _DropdownChip(
      icon: currentMeta.icon,
      label: currentMeta.label,
      onTap: () async {
        final picked = await showAppMenu<_LocaleOption>(
          context,
          minWidth: 180,
          items: [
            for (final e in labels.entries)
              AppMenuItem(
                value: e.key,
                label: e.value.label,
                icon: e.value.icon,
                selected: e.key == current,
              ),
          ],
        );
        if (picked != null) onChanged(_codes[picked]);
      },
    );
  }
}

/// Importar / exportar / remover tema. Fica logo abaixo do seletor porque as
/// três ações operam sobre a mesma escolha.
///
/// Import/export de arquivo vem antes de um editor visual de propósito: resolve
/// portabilidade entre máquinas e permite editar o tema no editor de código
/// (com `$schema` ligando o autocomplete), que é o fluxo de quem faz tema.
class _ThemeFileRow extends StatelessWidget {
  const _ThemeFileRow();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final tr = context.t.settings.page.appearance;
    final isCustom = controller.isCustomTheme(controller.activeTheme.id);
    return _Row(
      title: tr.themeFileTitle,
      description: tr.themeFileDesc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlineButton(
            onPressed: () => _import(context),
            child: Text(tr.importTheme),
          ),
          const SizedBox(width: 8),
          OutlineButton(
            onPressed: () => _export(context),
            child: Text(tr.exportTheme),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            OutlineButton(
              onPressed: () => _delete(context),
              child: Text(tr.deleteTheme),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final controller = context.read<SettingsController>();
    final tr = context.t.settings.page.appearance;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: tr.importThemeDialog,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final result = await controller.importTheme(File(path));
    if (!context.mounted) return;
    result.fold(
      (theme) => _toast(context, tr.themeImported(name: theme.name)),
      (error) => _toast(
        context,
        themeStoreErrorMessage(context, error),
        isError: true,
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final controller = context.read<SettingsController>();
    final tr = context.t.settings.page.appearance;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: tr.exportThemeDialog,
      fileName: '${controller.activeTheme.id}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null) return;

    final result = await controller.exportActiveTheme(path);
    if (!context.mounted) return;
    result.fold(
      (_) => _toast(context, tr.themeExported),
      (error) => _toast(
        context,
        themeStoreErrorMessage(context, error),
        isError: true,
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final controller = context.read<SettingsController>();
    final tr = context.t.settings.page.appearance;
    final result = await controller.deleteTheme(controller.activeTheme.id);
    if (!context.mounted) return;
    result.fold(
      (_) => _toast(context, tr.themeDeleted),
      (error) => _toast(
        context,
        themeStoreErrorMessage(context, error),
        isError: true,
      ),
    );
  }

  void _toast(BuildContext context, String message, {bool isError = false}) {
    final colors = context.colors;
    showToast(
      context: context,
      location: ToastLocation.bottomRight,
      builder: (context, overlay) => SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 18,
                color: isError ? colors.error : colors.ok,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message,
                  style: context.typo.label.copyWith(color: colors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seletor do tema ativo. Escolher um tema é a mesma ação seja ele nativo ou
/// importado, então os dois convivem numa lista só — mas a **origem** é
/// distinguível: os importados vêm depois de um divisor e com ícone.
///
/// Isso importa na hora de remover: o botão "Remover" só aparece para tema
/// importado, e sem a marca o usuário não teria como prever quando ele some.
/// (Não confundir com o `_ThemeModeDropdown`, que escolhe qual **variant** do
/// tema usar.)
class _ThemeDropdown extends StatelessWidget {
  const _ThemeDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final themes = controller.availableThemes;
    final current = themes.firstWhere(
      (t) => t.id == value,
      orElse: () => cockpitDefaultTheme,
    );
    // `availableThemes` já entrega os nativos primeiro; separar aqui mantém
    // essa ordem sendo a única fonte da divisão.
    final builtIn = themes.where((t) => !controller.isCustomTheme(t.id));
    final imported = themes.where((t) => controller.isCustomTheme(t.id));

    AppMenuItem<String> itemFor(CockpitThemeSpec theme, {required bool own}) =>
        AppMenuItem(
          value: theme.id,
          label: theme.name,
          // Só o importado leva ícone: marcar os dois grupos gastaria atenção
          // para dizer o que o divisor já diz. O `trailing` segue livre para a
          // marca de seleção.
          icon: own ? Icons.file_download_outlined : null,
          selected: theme.id == value,
        );

    return _DropdownChip(
      label: current.name,
      onTap: () async {
        final picked = await showAppMenu<String>(
          context,
          minWidth: 200,
          items: [
            for (final theme in builtIn) itemFor(theme, own: false),
            if (imported.isNotEmpty) const AppMenuItem<String>.divider(),
            for (final theme in imported) itemFor(theme, own: true),
          ],
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _UpdateCheckDropdown extends StatelessWidget {
  const _UpdateCheckDropdown({required this.value, required this.onChanged});
  final UpdateCheckFrequency value;
  final ValueChanged<UpdateCheckFrequency> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.settings.page.general.updateFrequency;
    final labels = <UpdateCheckFrequency, String>{
      UpdateCheckFrequency.daily: tr.daily,
      UpdateCheckFrequency.weekly: tr.weekly,
      UpdateCheckFrequency.monthly: tr.monthly,
      UpdateCheckFrequency.never: tr.never,
    };
    return _DropdownChip(
      label: labels[value]!,
      onTap: () async {
        final picked = await showAppMenu<UpdateCheckFrequency>(
          context,
          minWidth: 180,
          items: [
            for (final e in labels.entries)
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
/// Seleção de família de fonte.
///
/// Substituiu um campo de texto livre que falhava em silêncio: nome com erro de
/// digitação ou fonte não instalada caíam no fallback sem nenhum aviso. Agora a
/// escolha sai de uma lista do que a máquina realmente tem (ver
/// [showFontPickerDialog]), o nome escolhido é desenhado **na própria fonte**, e
/// uma família que não resolve é sinalizada aqui no chip.
class _FontField extends StatelessWidget {
  const _FontField({
    required this.value,
    required this.hint,
    required this.onChanged,
    this.monospacedOnly = false,
  });

  final String? value;

  /// Descrição do padrão do design, mostrada quando não há escolha.
  final String hint;
  final ValueChanged<String?> onChanged;
  final bool monospacedOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = value;
    final missing = family != null && !isFontAvailable(family);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (missing) ...[
          AppTooltip(
            message: context.t.settings.page.appearance.fontMissing,
            child: Icon(Icons.warning_amber, size: 15, color: colors.warn),
          ),
          const SizedBox(width: 6),
        ],
        HoverTap(
          color: colors.panel3,
          borderRadius: BorderRadius.circular(7),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          onTap: () async {
            final choice = await showFontPickerDialog(
              context,
              current: family,
              defaultLabel: hint,
              monospacedOnly: monospacedOnly,
            );
            // Dialog dispensado devolve null; só uma escolha real muda algo.
            if (choice != null) onChanged(choice.family);
          },
          child: SizedBox(
            width: 218,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    family ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: family == null
                        ? context.typo.body.copyWith(
                            fontSize: 13,
                            color: colors.text3,
                          )
                        : TextStyle(
                            fontFamily: family,
                            fontSize: 13,
                            color: colors.text,
                          ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 16, color: colors.text3),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Stepper de tamanho que aceita "sem valor próprio", herdando de outro ajuste.
///
/// Sem override, mostra o valor herdado esmaecido; mexer nos botões passa a
/// definir um valor explícito, e o terceiro botão desfaz o override.
class _OptionalSizeStepper extends StatelessWidget {
  const _OptionalSizeStepper({
    required this.value,
    required this.inherited,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  /// `null` = herdando [inherited].
  final double? value;
  final double inherited;
  final double min;
  final double max;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overridden = value != null;
    final effective = value ?? inherited;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (overridden)
          AppTooltip(
            message: context.t.settings.page.appearance.terminalSizeInherit,
            child: HoverTap(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onChanged(null),
              child: SizedBox(
                width: 30,
                height: 32,
                child: Icon(Icons.link, size: 15, color: colors.text2),
              ),
            ),
          ),
        _SizeStepper(
          value: effective,
          min: min,
          max: max,
          onChanged: onChanged,
          muted: !overridden,
        ),
      ],
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
    this.muted = false,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Esmaece o número quando ele é apenas herdado, e não uma escolha.
  final bool muted;

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
                color: muted ? colors.text2 : colors.text,
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
    final tr = context.t.settings.page.languages;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            label: tr.sectionFormatting,
            child: _Card(
              children: [
                _Row(
                  title: tr.formatOnSaveTitle,
                  description: tr.formatOnSaveDesc,
                  trailing: Switch(
                    value: settings.formatOnSave,
                    onChanged: ctrl.setFormatOnSave,
                  ),
                ),
              ],
            ),
          ),
          _Section(
            label: tr.sectionLanguageServers,
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
            tr.footerNote,
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
                _fieldLabel(
                  context,
                  context.t.settings.page.languages.serverCommandLabel,
                ),
                const SizedBox(height: 6),
                _commandField(context, _serverCtrl, _default),
                const SizedBox(height: 14),
                _fieldLabel(
                  context,
                  context.t.settings.page.languages.formatterCommandLabel,
                ),
                const SizedBox(height: 6),
                _commandField(
                  context,
                  _formatterCtrl,
                  'prettier --write %FILE%',
                ),
                const SizedBox(height: 4),
                Text(
                  context.t.settings.page.languages.formatterHint,
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
                        context.t.settings.page.languages.resetToDefault,
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
                        context.t.settings.page.languages.saveAndRestart,
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
    final tr = context.t.settings.page.languages;
    final (Color color, String tip) = switch (available) {
      true => (colors.online, tr.statusResponds),
      false => (colors.text4, tr.statusNotFound),
      null => (colors.border, context.t.common.checking),
    };
    return AppTooltip(
      message: tip,
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
    final tr = context.t.settings.page.connectivity;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr.revokeDialogTitle,
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          tr.revokeDialogContent(name: name),
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.t.common.cancel,
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              tr.revoke,
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
    final tr = context.t.settings.page.connectivity;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                label: tr.sectionRelay,
                child: const _Card(children: [_RelayEditor()]),
              ),
              _Section(
                label: tr.sectionPairedDevices,
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
    final tr = context.t.settings.page.connectivity;

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
              context.t.common.loading,
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
          vm.devicesError ?? tr.failedToListDevices,
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
          tr.noPairedDevices,
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
    final tr = context.t.settings.page.connectivity;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.relayAddressTitle,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tr.relayAddressDesc,
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
                child: Text(vm.savingRelay ? tr.saving : context.t.common.save),
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
                child: Text(tr.check),
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
    final tr = context.t.settings.page.connectivity;

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
            context.t.common.checking,
            style: context.typo.label.copyWith(color: colors.text3),
          ),
        ],
      );
    }

    final (Color dot, String label, Color text) = switch (vm.healthState) {
      HealthState.healthy => (colors.online, tr.healthOnline, colors.text2),
      HealthState.unhealthy => (
        colors.error,
        vm.healthMessage ?? tr.healthNoResponse,
        colors.error,
      ),
      _ => (colors.text4, tr.healthNotChecked, colors.text3),
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
                  device.label.isEmpty
                      ? context.t.settings.page.connectivity.deviceDefaultLabel
                      : device.label,
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
          AppTooltip(
            message: context.t.settings.page.connectivity.revoke,
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
    return AppTooltip(
      message: context.t.settings.page.connectivity.reloadTooltip,
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
            context.t.settings.page.connectivity.pairNewDevice,
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
    final tr = context.t.settings.page.schedules;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr.removeScheduleDialogTitle,
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          tr.removeScheduleDialogContent(
            schedule: job.schedule,
            daemon: vm.daemonName(job.daemonId),
          ),
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.t.common.cancel,
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.t.common.remove,
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
                label:
                    context.t.settings.page.schedules.sectionScheduledPrompts,
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
    final tr = context.t.settings.page.schedules;
    return Row(
      children: [
        PrimaryButton(
          onPressed: vm.hasDaemons ? () => _openEditor() : null,
          leading: const Icon(Icons.add, size: 16),
          child: Text(tr.createSchedule),
        ),
        if (!vm.hasDaemons) ...[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              tr.createDaemonFirst,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context, CronViewModel vm) {
    final colors = context.colors;
    final tr = context.t.settings.page.schedules;

    if (!vm.online && vm.load != CronLoad.loading) {
      return _MessageCard(
        child: Text(
          tr.supervisorOffline,
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
              context.t.common.loading,
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
          vm.error ?? tr.failedToListSchedules,
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
          tr.noSchedules,
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
            _cronAct(
              context,
              Icons.play_arrow,
              context.t.settings.page.schedules.runNow,
              onRun,
            ),
            _cronAct(
              context,
              Icons.history,
              context.t.settings.page.schedules.viewLog,
              onLog,
            ),
            _cronAct(
              context,
              Icons.delete_outline,
              context.t.common.remove,
              onRemove,
            ),
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
    return AppTooltip(
      message: tip,
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
    final tr = context.t.settings.page.schedules;
    final children = <Widget>[];

    if (!job.enabled) {
      children.add(
        Text(
          tr.disabled,
          style: context.typo.label.copyWith(color: colors.text4),
        ),
      );
    } else if (job.nextRun != null) {
      children.add(
        Text(
          tr.nextRun(when: _fmtIso(job.nextRun)),
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
        Text(
          tr.lastRun(label: label),
          style: context.typo.label.copyWith(color: color),
        ),
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
    final tr = context.t.settings.page.schedules;
    final expr = _expr.text.trim();
    if (expr.isEmpty) return tr.previewPlaceholder;
    final next = nextCronRun(expr, DateTime.now());
    if (next == null) return tr.previewComputed;
    return tr.previewNext(when: _fmtDateTime(next));
  }

  Future<void> _submit() async {
    final expr = _expr.text.trim();
    final prompt = _prompt.text.trim();
    if (expr.isEmpty || prompt.isEmpty) {
      setState(
        () => _localError = context.t.settings.page.schedules.fillRequiredError,
      );
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
        _localError =
            widget.vm.actionError ??
            context.t.settings.page.schedules.failedToCreateSchedule;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.vm;
    final tr = context.t.settings.page.schedules;
    final examples = <(String, String)>[
      ('0 9 * * *', tr.exampleEveryDay9am),
      ('0 * * * *', tr.exampleHourly),
      ('*/15 * * * *', tr.exampleEvery15Min),
      ('0 18 * * 1-5', tr.exampleWeekdays6pm),
    ];

    return AlertDialog(
      title: Text(
        tr.newScheduleTitle,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(context, tr.daemonLabel),
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
              _fieldLabel(context, tr.whenLabel),
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
                  for (final (expr, label) in examples)
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
              _fieldLabel(context, tr.promptLabel),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _prompt,
                'e.g. Summarize the new PRs',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _fieldLabel(context, tr.timezoneLabel),
              const SizedBox(height: 6),
              _dialogField(
                context,
                _tz,
                'e.g. America/Sao_Paulo (empty = system)',
                mono: true,
              ),
              const SizedBox(height: 12),
              _CronOptionSwitch(
                label: tr.skipIfBusy,
                value: _skipIfBusy,
                onChanged: (v) => setState(() => _skipIfBusy = v),
              ),
              _CronOptionSwitch(
                label: tr.wakeIfStopped,
                value: _wake,
                onChanged: (v) => setState(() => _wake = v),
              ),
              _CronOptionSwitch(
                label: tr.catchup,
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
            context.t.common.cancel,
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _saving ? null : _submit,
          child: Text(
            _saving ? tr.creating : context.t.common.create,
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
          ? (widget.vm.actionError ??
                context.t.settings.page.schedules.failedToReadLog)
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        context.t.settings.page.schedules.historyTitle(
          schedule: widget.job.schedule,
        ),
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(width: 460, child: _content(context)),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            context.t.common.close,
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
        context.t.settings.page.schedules.noRecordsYet,
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
  final tr = context.t.settings.page.schedules;
  return switch (r) {
    CronResult.delivered => (colors.online, tr.cronDelivered),
    CronResult.wokeAndDelivered => (colors.online, tr.cronWokeDelivered),
    CronResult.deliverFailed => (colors.error, tr.cronFailed),
    CronResult.skippedBusy => (colors.warn, tr.cronSkippedBusy),
    CronResult.skippedDown => (colors.text4, tr.cronSkippedStopped),
    CronResult.skippedDisabled => (colors.text4, tr.cronSkippedDisabled),
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
    final tr = context.t.settings.page.daemons;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr.restartSupervisorDialogTitle,
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          tr.restartSupervisorDialogContent,
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.t.common.cancel,
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.t.common.restart,
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
    final tr = context.t.settings.page.daemons;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr.removeDaemonDialogTitle,
          style: ctx.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: Text(
          tr.removeDaemonDialogContent(name: daemon.name),
          style: ctx.typo.body.copyWith(fontSize: 13.5, color: colors.text2),
        ),
        actions: [
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              context.t.common.cancel,
              style: ctx.typo.body.copyWith(fontSize: 13, color: colors.text2),
            ),
          ),
          GhostButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.t.common.remove,
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
                label: context.t.settings.page.daemons.sectionAlwaysOnAgents,
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
    final tr = context.t.settings.page.daemons;

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
                  tr.supervisorOfflineTitle,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr.supervisorOfflineDesc,
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
              context.t.common.loading,
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
          vm.error ?? tr.failedToListDaemons,
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
          tr.noRegisteredAgents,
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
    final tr = context.t.settings.page.daemons;
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
          child: Text(tr.createDaemon),
        ),
        if (vm.busyAll)
          CircularProgressIndicator(
            size: 15,
            strokeWidth: 2,
            color: colors.text3,
          ),
        _FleetButton(
          label: tr.startAll,
          icon: Icons.play_arrow,
          onTap: fleetEnabled ? vm.startAll : null,
        ),
        _FleetButton(
          label: tr.stopAll,
          icon: Icons.stop,
          onTap: fleetEnabled ? vm.stopAll : null,
        ),
        _FleetButton(
          label: tr.restartAll,
          icon: Icons.restart_alt,
          onTap: fleetEnabled ? vm.restartAll : null,
        ),
        _FleetButton(
          label: tr.restartSupervisor,
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
                  running
                      ? context.t.settings.page.daemons.stop
                      : context.t.settings.page.daemons.start,
                  running ? onStop : onStart,
                ),
                if (running)
                  _act(
                    context,
                    Icons.restart_alt,
                    context.t.common.restart,
                    onRestart,
                  ),
                _act(
                  context,
                  Icons.edit_outlined,
                  context.t.settings.page.daemons.edit,
                  onEdit,
                ),
                _act(
                  context,
                  Icons.delete_outline,
                  context.t.common.remove,
                  onRemove,
                ),
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
    final tr = context.t.settings.page.daemons;
    return switch (state) {
      DaemonState.running => (colors.online, tr.stateRunning),
      DaemonState.starting => (colors.warn, tr.stateStarting),
      DaemonState.stopped => (colors.text4, tr.stateStopped),
      DaemonState.crashed => (colors.error, tr.stateFailed),
      DaemonState.unknown => (colors.text4, '—'),
    };
  }

  Widget _act(
    BuildContext context,
    IconData icon,
    String tip,
    Future<void> Function() onTap,
  ) {
    return AppTooltip(
      message: tip,
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
    final picked = await NativeFolderPicker.pick(
      dialogTitle: context.t.settings.page.daemons.pickFolderDialogTitle,
      initialDirectory: _cwd, // reabre onde já estava, se já escolhido
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
    final tr = context.t.settings.page.daemons;
    String? nameError;
    String? pathError;

    if (name.isEmpty) {
      nameError = tr.nameRequiredError;
    } else if (widget.existingNames.contains(name.toLowerCase())) {
      nameError = tr.nameDuplicateError;
    }
    if (!_isEdit) {
      if (_cwd == null) {
        pathError = tr.folderRequiredError;
      } else if (widget.existingCwds.contains(_cwd)) {
        pathError = tr.folderDuplicateError;
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
    final tr = context.t.settings.page.daemons;

    return AlertDialog(
      title: Text(
        _isEdit ? tr.editDaemonTitle : tr.newDaemonTitle,
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, tr.nameLabel),
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
              placeholder: Text(tr.namePlaceholder),
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
            _label(context, tr.folderLabel),
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
                      _cwd ?? tr.noFolderChosen,
                      enabled: _cwd != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    onPressed: () => _pickFolder(),
                    child: Text(_cwd == null ? tr.choose : tr.changeFolder),
                  ),
                ],
              ),
            if (_isEdit) ...[
              const SizedBox(height: 6),
              Text(
                tr.folderCannotBeChanged,
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
            context.t.common.cancel,
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _submit,
          child: Text(
            _isEdit ? context.t.common.save : context.t.common.create,
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
