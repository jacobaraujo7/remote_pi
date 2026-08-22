import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:cockpit/app/cockpit/ui/actions/agent_actions.dart';
import 'package:cockpit/app/cockpit/ui/actions/remote_workspace_actions.dart';
import 'package:cockpit/app/cockpit/ui/actions/workspace_actions.dart';
import 'package:cockpit/app/cockpit/ui/actions/worktree_actions.dart';
import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/automation.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_db_executor.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_task_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/remote_disconnected_banner.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_key_bar.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/gestures.dart' show PointerDownEvent, kBackMouseButton;
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey,
        PhysicalKeyboardKey;
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/domain/contracts/ssh_tunnel.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/database_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/ssh_prompts.dart';

/// Os únicos valores do `CockpitViewModel` de que o shell (top bar + arranjo
/// das panes) depende. Isolados num record pra o `select` comparar por valor.
typedef _ShellState = ({
  bool ready,
  bool railVisible,
  bool treeVisible,
  bool hasFileTree,
  String? title,
  bool terminalActive,
});

/// Shell do Cockpit: top bar + rail de projetos + multiplexador (árvore de
/// splits). Cada folha é uma [PaneView] com abas; cada aba é um agente.
class CockpitPage extends StatefulWidget {
  const CockpitPage({super.key});

  @override
  State<CockpitPage> createState() => _CockpitPageState();
}

class _CockpitPageState extends State<CockpitPage> {
  CockpitViewModel get _vm => context.read<CockpitViewModel>();

  /// Larguras dos painéis laterais (arrastáveis). **Não** são persistidas —
  /// estado só da sessão da janela.
  double _treeWidth = 300;
  static const double _treeMin = 220;
  static const double _treeMax = 620;

  double _railWidth = 252;
  static const double _railMin = 190;
  static const double _railMax = 420;

  /// Abaixo deste valor de largura (mobile) as panes laterais (workspaces e
  /// arquivos) viram DRAWERS sobrepostos, em vez de dividir a Row (plano 60,
  /// Wave F). Cobre portrait de celular; landscape/tablet largo seguem inline.
  static const double _drawerBreakpoint = 600;

  /// Estado dos drawers no modo estreito (default fechados). No modo largo a
  /// visibilidade das panes segue `vm.railVisible`/`vm.treeVisible`.
  bool _leftDrawer = false;
  bool _rightDrawer = false;

  void _dismissDrawers() {
    if (!_leftDrawer && !_rightDrawer) return;
    setState(() {
      _leftDrawer = false;
      _rightDrawer = false;
    });
  }

  /// Preserva o subtree central (terminais/editores) ao alternar entre layout
  /// largo (Row) e estreito (Stack/drawers) — ex.: rotação portrait↔landscape.
  /// Sem um GlobalKey, a troca de tipo de pai REMONTA o subtree, e o novo
  /// TerminalView do flterm faz attach antes do antigo desanexar → "controller
  /// already has an active view". Com a key, o elemento é reparentado (movido).
  final GlobalKey _centerKey = GlobalKey();

  /// Sobe a cada Cmd+Shift+F → o [ContentSearchPanel] foca o campo de busca.
  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);

  /// Altura (arrastável + persistida) da lista de Tasks.
  double _tasksHeight = 200;
  static const double _tasksMin = 100;
  static const double _tasksMax = 520;

  @override
  void initState() {
    super.initState();
    // Discovery de harnesses é lazy (Settings ou primeira geração) — evita
    // spawnar 6 CLIs a cada montagem de workspace.
    // Registra a ponte do ⌘L global (handler em main.dart) → foca o input do
    // agente focado, mesmo quando o foco caiu num espaço vazio do shell.
    requestFocusActiveComposer = _focusActiveComposer;
    // Pontes do menu nativo (PlatformMenuBar vive acima da rota, sem acesso aos
    // ViewModels page-scoped): abrir projeto e verificar atualizações.
    requestOpenProject = () => unawaited(addProject(context));
    // `checkNow()` (não `check()`): o menu é uma checagem pedida pelo usuário →
    // foreground, com resposta visível e ignorando "Skip this version".
    requestCheckForUpdates = () =>
        unawaited(context.read<UpdateViewModel>().checkNow());
    requestOpenSettings = () {
      if (!mounted) return;
      context.pushNamed(RoutePaths.settings);
    };
    // O motor/perfil precisam chegar antes do init: ele já pode restaurar ou
    // criar terminais, e a preferência do usuário deve valer desde o 1º buffer.
    final initialSettings = context.read<SettingsController>().settings;
    _sourceControlViewMode = initialSettings.sourceControlViewMode;
    context.read<CockpitViewModel>()
      ..setDefaultTerminalProfileId(initialSettings.defaultTerminalProfileId)
      ..setDefaultTerminalEngine(initialSettings.terminalEngine);
    // Dispara o carregamento inicial dos ViewModels page-scoped ao montar a rota.
    // Os módulos provêm via `.new`, então não encadeiam mais `..init()`/`..check()`.
    context.read<CockpitViewModel>().init();
    final updateVm = context.read<UpdateViewModel>();
    updateVm.attachSettings(context.read<SettingsController>());
    // Self-update (Sparkle/WinSparkle) é desktop-only; no mobile a loja atualiza.
    // Evita também o notify-durante-build do setLastUpdateCheckTime no boot iOS.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      updateVm.check();
    }
    // Publica o estado do workspace no menu File (New Agent / New Terminal): só
    // habilitam quando há workspace ativo. Re-sincroniza a cada mudança da VM.
    _workspaceMenu = context.read<WorkspaceMenuBridge>();
    _menuVm = context.read<CockpitViewModel>()..addListener(_syncWorkspaceMenu);
    _syncWorkspaceMenu();
    // Navegação direcional entre panes (⌘⌥ + setas). Vai por um handler global
    // do HardwareKeyboard — e NÃO pelo menu — porque no macOS as setas não
    // funcionam como *key equivalent* de menu (o campo/terminal focado consome a
    // seta antes do menu). O handler global vê o evento antes da distribuição por
    // foco, então pega mesmo com um terminal focado. Ver [_handlePaneNavKey].
    HardwareKeyboard.instance.addHandler(_handlePaneNavKey);
    HardwareKeyboard.instance.addHandler(_realmKeyHandler);
    // Mantém os overrides de comando do LSP (tela "Language") em sync com o pool:
    // empurra o estado atual e re-empurra a cada mudança das Configurações.
    _settings = context.read<SettingsController>()
      ..addListener(_syncLspCommands)
      ..addListener(_syncNotifications)
      ..addListener(_syncCockpit)
      ..addListener(_syncSourceControlViewMode)
      ..addListener(_syncAutomationSelection);
    _syncLspCommands();
    _syncNotifications();
    _syncCockpit();
    _syncAutomationSelection();
    // Restaura a visibilidade dos painéis (rail/árvore) salva na sessão anterior
    // e persiste de volta a cada toggle. A VM é a fonte de verdade em runtime.
    final vm = context.read<CockpitViewModel>();
    // Mobile (iPad/Android): layout diferente — rail e painel de arquivos já
    // começam abertos. A pane direita só aparece de fato quando há árvore
    // (o layout gateia por `treeVisible && activeHasFileTree`), então na
    // WelcomeView ela fica oculta até haver workspace com pasta.
    vm.restorePanelVisibility(
      rail: isMobilePlatform || _settings!.settings.railVisible,
      tree: isMobilePlatform || _settings!.settings.treeVisible,
    );
    vm.onPanelVisibilityChanged = (rail, tree) =>
        _settings!.setPanelVisibility(rail: rail, tree: tree);
    _tasksHeight = _settings!.settings.tasksPanelHeight.clamp(
      _tasksMin,
      _tasksMax,
    );
    _wireSshPrompts();
  }

  /// Liga os prompts de SSH (plano 54) ao motor de queries. É aqui e não no
  /// módulo porque eles precisam de `BuildContext` — e é o que separa a GUI
  /// (pode perguntar) da CLI (não pode: prompts nulos → erro honesto).
  void _wireSshPrompts() {
    // Hosts remotos (plano 58): mesmo dialog TOFU do túnel de banco. Sem isto,
    // um host novo no desktop morria em "Host key verification failed" — o ssh
    // roda com BatchMode e não pode perguntar nada por conta própria.
    _vm.remoteHosts.hostKeyPrompt = (endpoint, fingerprint) async {
      if (!mounted) return HostKeyVerdict.reject;
      return showSshHostKeyDialog(
        context,
        endpoint: endpoint,
        fingerprint: fingerprint,
      );
    };
    final service = _dbService = context.read<DatabaseViewModel>().service;
    service
      ..passphrasePrompt = (connectionName, keyPath) async {
        if (!mounted) return null;
        return showSshPassphraseDialog(
          context,
          connectionName: connectionName,
          keyPath: keyPath,
        );
      }
      ..hostKeyPrompt = (endpoint, fingerprint) async {
        if (!mounted) return HostKeyVerdict.reject;
        return showSshHostKeyDialog(
          context,
          endpoint: endpoint,
          fingerprint: fingerprint,
        );
      }
      // DB remoto (plano 58, Wave 4): quando o workspace é de um host remoto,
      // a query roda no cockpit-server do host. Resolvido por workspace pra
      // não confundir workspaces locais e remotos abertos ao mesmo tempo.
      ..remoteExecutorFor = (wsId) {
        final host = _vm.remoteHostForWorkspace(wsId);
        if (host == null) return null;
        return buildRemoteDbExecutor(() => _vm.remoteHosts.dbServiceFor(host));
      }
      // Redis/Mongo remotos: mesmo host, mesmo serviço — só o comando muda.
      ..remoteNoSqlFor = (wsId) {
        final host = _vm.remoteHostForWorkspace(wsId);
        if (host == null) return null;
        return buildRemoteNoSqlRunner(() => _vm.remoteHosts.dbServiceFor(host));
      }
      // As conexões de um workspace remoto vivem no host
      // (.cockpit/databases.json) — resolução da query E leitura do painel.
      ..remoteConnectionsFor = _remoteConnectionsFor;
    context.read<DatabaseViewModel>().remoteConnectionsFor =
        _remoteConnectionsFor;
    // Task Run remoto (plano 58): descoberta via fs.read + execução via terminal
    // do host, roteados quando o workspace ativo é remoto.
    context.read<TasksViewModel>().remoteContextFor = _remoteTaskContextFor;
  }

  /// Contexto de Task remoto do workspace ativo (host resolvido do projeto
  /// selecionado), cacheado por host — o runner precisa sobreviver às trocas de
  /// cwd pra manter as tasks rodando. `null` quando o ativo é local.
  final Map<String, ({TaskDiscovery discovery, TaskRunnerGateway runner})>
  _remoteTaskCtx = {};

  ({TaskDiscovery discovery, TaskRunnerGateway runner})? _remoteTaskContextFor(
    String cwd,
  ) {
    final host = _vm.remoteHostForWorkspace(_vm.selectedProjectId);
    if (host == null) return null;
    return _remoteTaskCtx.putIfAbsent(host.id, () {
      final runner = RemoteTaskRunner(
        () => _vm.remoteHosts.terminalServiceFor(host),
      );
      // Liga o output deste runner ao store de terminais (senão a aba de output
      // da task remota fica vazia — plano 60, Wave D).
      _vm.taskTerminals.registerRunner(runner);
      return (
        discovery: RemoteTaskDiscovery(
          () => _vm.remoteHosts.fileServiceFor(host),
        ),
        runner: runner,
      );
    });
  }

  /// Loader remoto de conexões, compartilhado pelo [DbQueryService] (resolução
  /// da query) e pelo [DatabaseViewModel] (listagem do painel).
  Future<List<DbConnection>>? _remoteConnectionsFor(String wsId, String root) {
    final host = _vm.remoteHostForWorkspace(wsId);
    if (host == null) return null;
    return loadRemoteConnections(
      () => _vm.remoteHosts.fileServiceFor(host),
      root,
    );
  }

  /// Capturado no initState pra uso seguro no dispose (sem `context`).
  DbQueryService? _dbService;

  SettingsController? _settings;
  SourceControlViewMode _sourceControlViewMode = SourceControlViewMode.list;
  Map<String, String> _lastLspCommands = const <String, String>{};

  /// Bridge do menu File (New Agent/Terminal) + a VM que observamos pra saber se
  /// há workspace ativo. Capturados no [initState] pra uso seguro no [dispose].
  WorkspaceMenuBridge? _workspaceMenu;
  CockpitViewModel? _menuVm;

  /// Espelha "há workspace ativo?" no menu; os callbacks abrem uma aba nova no
  /// workspace ativo (root do projeto). `setWorkspace` só notifica quando o
  /// booleano muda, então chamar a cada evento da VM é barato.
  void _syncWorkspaceMenu() {
    final vm = _menuVm;
    if (vm == null) return;
    _workspaceMenu?.setWorkspace(
      hasWorkspace: vm.selectedProject != null,
      agentTabsInUse: vm.hasAgentTabsInUse,
      // Cockpit é terminal-only → sem "New Agent" no menu File.
      agentsAllowed: !vm.isPathless(vm.selectedProjectId),
      // Agente pergunta a subpasta onde vai atuar (igual ao fluxo direto de
      // criar agente); terminal abre direto na raiz do workspace.
      onNewAgent: () => unawaited(
        pickSubfolderThen(context, (sub) => vm.newTabIn(sub, terminal: false)),
      ),
      onNewTerminal: () => vm.newTabIn('', terminal: true),
      onSplitRight: () => _splitFocused(SplitDir.vertical),
      onSplitDown: () => _splitFocused(SplitDir.horizontal),
      onToggleRail: vm.toggleRail,
      onToggleFiles: vm.toggleTree,
      onSelectTab: vm.selectTabByIndex,
      onSelectLastTab: vm.selectLastTab,
      onFocusPaneLeft: () => vm.focusPaneToward(PaneMove.left),
      onFocusPaneRight: () => vm.focusPaneToward(PaneMove.right),
      onFocusPaneUp: () => vm.focusPaneToward(PaneMove.up),
      onFocusPaneDown: () => vm.focusPaneToward(PaneMove.down),
    );
  }

  /// Divide a pane **focada** na direção [dir]. Terminal abre direto na raiz;
  /// agente pergunta a subpasta — mesma regra do menu de split da pane.
  void _splitFocused(SplitDir dir) {
    final vm = _vm;
    final projectId = vm.selectedProject?.id;
    if (projectId == null) return;
    final paneId = vm.focusedPaneId(projectId);
    if (paneId == null) return;
    // Só agente pergunta a subpasta; terminal/browser/viewer/db abrem na raiz.
    if (vm.paneActiveIsEmpty(paneId)) {
      vm.splitPaneEmpty(paneId, dir);
    } else if (vm.paneActiveIsAgent(paneId)) {
      unawaited(
        pickSubfolderThen(context, (sub) => vm.splitPane(paneId, dir, sub)),
      );
    } else {
      vm.splitPane(paneId, dir, '');
    }
  }

  /// Espelha o toggle de Notificações (aba das Configurações) para a VM, que
  /// gateia o disparo de fim de turno. A VM é page-scoped e não vê o
  /// `SettingsController` app-scoped, então a página empurra o valor.
  void _syncNotifications() {
    _vm.setNotificationsEnabled(_settings!.settings.notificationsEnabled);
    _vm.setSoundPrefs(
      events: _settings!.settings.soundEvents,
      overrides: _settings!.settings.soundOverrides,
      onActiveTab: _settings!.settings.soundOnActiveTab,
      volume: _settings!.settings.soundVolume,
    );
    // Plano 50: perfil de terminal padrão do `+` — mesmo motivo (app-scoped →
    // VM page-scoped). Vale pra abas criadas daqui pra frente.
    _vm.setDefaultTerminalProfileId(
      _settings!.settings.defaultTerminalProfileId,
    );
    _vm.setDefaultTerminalEngine(_settings!.settings.terminalEngine);
  }

  /// Espelha o toggle "Show Cockpit terminal" (Configurações › General) para a
  /// VM, que injeta/remove o workspace de sistema em runtime (matando os PTYs no
  /// desligar). A VM é page-scoped e não vê o `SettingsController` app-scoped.
  void _syncCockpit() {
    _vm.setCockpitEnabled(_settings!.settings.showCockpit);
  }

  void _syncSourceControlViewMode() {
    final next = _settings!.settings.sourceControlViewMode;
    if (next == _sourceControlViewMode || !mounted) return;
    setState(() => _sourceControlViewMode = next);
  }

  void _syncAutomationSelection() {
    _vm.setAutomationSelection(_settings!.settings.automationSelection);
  }

  void _syncLspCommands() {
    final next = _settings!.settings.lspCommands;
    _vm.applyLspCommands(next);
    // Reinicia os servidores das linguagens cujo comando mudou (efetiva o novo
    // comando nos já vivos). Na 1ª sincronização não há o que reiniciar.
    final langs = <String>{..._lastLspCommands.keys, ...next.keys};
    for (final id in langs) {
      if (_lastLspCommands[id] != next[id]) {
        unawaited(_vm.restartLspLanguage(id));
      }
    }
    _lastLspCommands = Map<String, String>.of(next);
  }

  /// Handler global de teclado pra navegação direcional entre panes. Roda antes
  /// da distribuição por foco (por isso pega ⌘⌥+seta mesmo com terminal focado,
  /// onde o menu nativo do macOS falharia). Consome (retorna `true`) só o combo
  /// exato ⌘⌥ (macOS) / Ctrl+⌥ (Win/Linux) + seta; qualquer outra tecla passa.
  bool _handlePaneNavKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final move = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => PaneMove.left,
      LogicalKeyboardKey.arrowRight => PaneMove.right,
      LogicalKeyboardKey.arrowUp => PaneMove.up,
      LogicalKeyboardKey.arrowDown => PaneMove.down,
      _ => null,
    };
    if (move == null) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final primary =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final alt =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    if (!primary || !alt) return false;
    _menuVm?.focusPaneToward(move);
    return true;
  }

  @override
  void dispose() {
    // Runners de Task remotos (cacheados por host): mata as tasks e fecha os
    // streams. Não fecha a conexão SSH (compartilhada com os outros serviços).
    for (final ctx in _remoteTaskCtx.values) {
      unawaited(ctx.runner.disposeAll());
    }
    _remoteTaskCtx.clear();
    HardwareKeyboard.instance.removeHandler(_handlePaneNavKey);
    HardwareKeyboard.instance.removeHandler(_realmKeyHandler);
    _settings?.removeListener(_syncLspCommands);
    _settings?.removeListener(_syncNotifications);
    _settings?.removeListener(_syncCockpit);
    _settings?.removeListener(_syncSourceControlViewMode);
    _settings?.removeListener(_syncAutomationSelection);
    _menuVm?.removeListener(_syncWorkspaceMenu);
    _workspaceMenu?.setWorkspace(hasWorkspace: false);
    // Túneis SSH abertos morrem com o shell — e os prompts vão junto, senão
    // ficariam apontando pra um contexto desmontado.
    _vm.remoteHosts.hostKeyPrompt = null;
    _dbService
      ?..passphrasePrompt = null
      ..hostKeyPrompt = null
      ..closeSshTunnels();
    if (requestFocusActiveComposer == _focusActiveComposer) {
      requestFocusActiveComposer = null;
    }
    requestOpenProject = null;
    requestCheckForUpdates = null;
    requestOpenSettings = null;
    _searchFocusSignal.dispose();
    super.dispose();
  }

  /// Cmd+P / Ctrl+P: abre a palette de busca por **nome** de arquivo (quick
  /// open), reusando o índice do `FileSearcher` da VM.
  void _openFileFinder() {
    final vm = _vm;
    final project = vm.selectedProject;
    if (project == null) return;
    showFileFinderPalette(
      context,
      search: (query) => vm.searchFiles(project.path, query),
      onPick: vm.openProjectFile,
    );
  }

  /// Cmd+Shift+F / Ctrl+Shift+F: revela o painel de arquivos e foca a busca por
  /// **conteúdo** (find-in-files).
  void _focusContentSearch() {
    if (_vm.selectedProject == null) return;
    _vm.showTree();
    _searchFocusSignal.value++;
  }

  /// Foca o input do agente focado (no-op se a aba ativa não for um agente).
  void _focusActiveComposer() {
    final agent = _vm.focusedAgent;
    if (agent is AgentSession) agent.requestComposerFocus?.call();
  }

  /// ⌘L (macOS) / Ctrl+L (Win/Linux): foca o input do agente focado quando o
  /// foco está dentro do shell. (Fora dele — clique no vazio — quem dispara é a
  /// ponte global de `main.dart`; ver [requestFocusActiveComposer].)
  Map<ShortcutActivator, VoidCallback>
  _focusComposerBindings() => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
        _focusActiveComposer,
    const SingleActivator(LogicalKeyboardKey.keyL, control: true):
        _focusActiveComposer,
    const SingleActivator(LogicalKeyboardKey.keyP, meta: true): _openFileFinder,
    const SingleActivator(LogicalKeyboardKey.keyP, control: true):
        _openFileFinder,
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
        _focusContentSearch,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
        _focusContentSearch,
  };

  /// ⌘`/Ctrl+` próximo realm; com Shift, anterior. Handler **global** no
  /// [HardwareKeyboard] (registrado no initState), não um `CallbackShortcuts`:
  ///
  /// - `CallbackShortcuts` só recebe teclas com o foco primário DENTRO da
  ///   subtree — ciclar o realm destrói o nó focado (terminal/agente da árvore
  ///   antiga), o foco cai pro scope raiz e o atalho morria após o 1º uso;
  /// - casa pela **physical key**: a logical de ⇧` no macOS vira `~` (e a
  ///   combinação ⌘⇧ não batia com backquote nem tilde de forma confiável) —
  ///   pela física, Shift só decide a direção.
  ///
  /// Só `KeyDownEvent` (repeat não re-dispara); com Alt junto, ignora.
  bool _realmKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.physicalKey != PhysicalKeyboardKey.backquote) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if ((!keys.isMetaPressed && !keys.isControlPressed) || keys.isAltPressed) {
      return false;
    }
    unawaited(_vm.cycleRealm(keys.isShiftPressed ? -1 : 1));
    return true;
  }

  /// Botão lateral "voltar" do mouse (side button, `kBackMouseButton`) reativa
  /// a aba anterior da pane focada — mesma navegação de `goToDefinition`.
  /// `Listener` só observa (não compete na arena de gestos), então não afeta
  /// clique/drag normal de nenhum widget descendente.
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton != 0) _vm.goBackInPane();
  }

  @override
  Widget build(BuildContext context) {
    // `select` e não `watch`: o shell só depende destes cinco escalares. Com
    // `watch`, QUALQUER notify do VM (status de agente, git, output de terminal)
    // reconstruía a página inteira; agora cada painel (`_RailPanel`,
    // `_CenterPanel`, `_TreePanel`) observa o VM por conta própria e o shell só
    // reconstrói quando um destes valores muda de fato.
    final shell = context.select<CockpitViewModel, _ShellState>(
      (vm) => (
        ready: vm.ready,
        railVisible: vm.railVisible,
        treeVisible: vm.treeVisible,
        hasFileTree: vm.activeHasFileTree,
        title: vm.selectedDisplayTitle,
        terminalActive: vm.activeTabIsTerminal,
      ),
    );
    final colors = context.colors;

    if (!shell.ready) {
      return Scaffold(
        backgroundColor: colors.bg,
        child: const Center(child: CircularProgressIndicator(size: 20)),
      );
    }

    // Modo estreito (mobile portrait): panes laterais viram drawers. No largo, a
    // visibilidade segue vm.railVisible/treeVisible (comportamento desktop).
    final narrow =
        isMobilePlatform &&
        MediaQuery.sizeOf(context).width < _drawerBreakpoint;
    final railVisibleEff = narrow ? _leftDrawer : shell.railVisible;
    final treeVisibleEff =
        (narrow ? _rightDrawer : shell.treeVisible) && shell.hasFileTree;

    return Listener(
      onPointerDown: _onPointerDown,
      child: CallbackShortcuts(
        bindings: _focusComposerBindings(),
        // Focus(autofocus) garante que a página esteja na cadeia de foco mesmo
        // antes de clicar em algo — senão o atalho ⌘L não dispara num agente
        // recém-aberto (nada focado ainda).
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: colors.bg,
            child: Column(
              children: [
                CockpitTopbar(
                  projectName: shell.title ?? 'Cockpit',
                  // No modo estreito os toggles abrem/fecham os drawers; no largo
                  // seguem alternando a visibilidade inline da VM.
                  railVisible: railVisibleEff,
                  treeVisible: treeVisibleEff,
                  onToggleRail: narrow
                      ? () => setState(() => _leftDrawer = !_leftDrawer)
                      : _vm.toggleRail,
                  onToggleTree: narrow
                      ? () => setState(() => _rightDrawer = !_rightDrawer)
                      : _vm.toggleTree,
                  // Remoto TEM árvore (a pasta do host); só o Cockpit
                  // (systemTerminal) não. `activeHasFileTree` cobre os dois —
                  // `!isPathless` desabilitava indevidamente o remoto (path='').
                  filesEnabled: shell.hasFileTree,
                ),
                // Host remoto fora do ar: faixa com o estado + botão de
                // reconectar. Não ocupa espaço em workspace local.
                const RemoteDisconnectedBanner(),
                Expanded(
                  child: _PanelScaffold(
                    narrow: narrow,
                    railOpen: railVisibleEff,
                    treeOpen: treeVisibleEff,
                    onDismiss: _dismissDrawers,
                    rail: _RailPanel(
                      width: _railWidth,
                      onDismiss: _dismissDrawers,
                      onResize: (dx) => setState(() {
                        _railWidth = (_railWidth + dx).clamp(
                          _railMin,
                          _railMax,
                        );
                      }),
                    ),
                    center: _CenterPanel(centerKey: _centerKey),
                    tree: _TreePanel(
                      treeWidth: _treeWidth,
                      tasksHeight: _tasksHeight,
                      sourceControlViewMode: _sourceControlViewMode,
                      searchFocusSignal: _searchFocusSignal,
                      onDismiss: _dismissDrawers,
                      onResizeTree: (dx) => setState(() {
                        _treeWidth = (_treeWidth - dx).clamp(
                          _treeMin,
                          _treeMax,
                        );
                      }),
                      onTasksResize: (dy) => setState(() {
                        _tasksHeight = (_tasksHeight - dy).clamp(
                          _tasksMin,
                          _tasksMax,
                        );
                      }),
                      onTasksResizeEnd: () => context
                          .read<SettingsController>()
                          .setTasksPanelHeight(_tasksHeight),
                    ),
                  ),
                ),
                // Barra de teclas do terminal (mobile): aparece acima do teclado
                // virtual quando a aba ativa é terminal (plano 60, Wave F).
                if (isMobilePlatform &&
                    MediaQuery.viewInsetsOf(context).bottom > 0 &&
                    shell.terminalActive)
                  TerminalKeyBar(
                    onKeys: _vm.sendKeysToActiveTerminal,
                    onCopy: _vm.copyFromActiveTerminal,
                    onPaste: _vm.pasteToActiveTerminal,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alça fina pra redimensionar um painel lateral. Hit-area de 8px (cursor de
/// resize); o visual fica por conta da borda do próprio painel. Quem usa decide
/// o sinal do delta (borda esquerda vs direita).
/// Rail de workspaces. Widget próprio (e não um trecho do `build` da página)
/// para que um notify do VM reconstrua só este painel — não a página inteira
/// com o multiplexador e a árvore junto.
class _RailPanel extends StatelessWidget {
  const _RailPanel({
    required this.width,
    required this.onDismiss,
    required this.onResize,
  });

  final double width;
  final VoidCallback onDismiss;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    return Stack(
      children: [
        ProjectsRail(
          width: width,
          projects: vm.rootProjects,
          worktreesOf: vm.worktreesOf,
          worktreesExpanded: vm.worktreesExpanded,
          onWorktreesExpanded: vm.setWorktreesExpanded,
          selectedId: vm.selectedProjectId,
          notificationCounts: vm.notificationCounts,
          gitInfo: vm.gitInfo,
          rootsSummary: vm.rootsGitSummary,
          forkOriginName: vm.forkOriginName,
          rootsOf: (id) => [
            for (final r in vm.rootsOf(id))
              (path: r, name: r.split('/').last, git: vm.gitInfoForRoot(r)),
          ],
          onSelect: (id) {
            vm.selectProject(id);
            onDismiss(); // fecha o drawer no mobile
          },
          onAdd: () => createWorkspace(context),
          onConfigure: (project) => configureProject(context, project),
          onDelete: (project) => deleteProject(context, project),
          onCreateWorktree: (root, rootPath) =>
              createWorktree(context, root, rootPath),
          onRemoveWorktree: (fork) => removeWorktree(context, fork),
          onUpdateWorktree: (fork) => updateWorktree(context, fork),
          onForkWorktree: (base) => forkWorktree(context, base),
          onMergeWorktree: (fork) => mergeWorktree(context, fork),
          onSync: (project, rootPath) =>
              syncProject(context, project, rootPath),
          onPull: (project, rootPath) =>
              pullProject(context, project, rootPath),
          onPush: (project, rootPath) =>
              pushProject(context, project, rootPath),
          onReorder: (moved, target, before) =>
              vm.reorderWorkspace(moved, target, before: before),
          onOpenSettings: () => context.pushNamed(RoutePaths.settings),
          realms: vm.realms,
          activeRealm: vm.activeRealm,
          onSwitchRealm: (id) => unawaited(vm.switchRealm(id)),
          onCreateRealm: () => createRealm(context),
          onManageRealms: () => manageRealms(context),
          moveTargetsOf: (projectId) => moveTargets(vm, projectId),
          onMoveToRealm: (projectId, realmId) =>
              unawaited(vm.moveWorkspaceToRealm(projectId, realmId)),
          cockpit: vm.cockpitWorkspace,
          onSelectCockpit: () {
            vm.selectProject(Project.cockpitId);
            onDismiss();
          },
          onNewWorkspace: (anchor) => newWorkspaceMenu(context, vm, anchor),
          onSelectRemote: (id) {
            vm.selectProject(id);
            onDismiss();
          },
          remoteGitInfoOf: vm.remoteGitInfoOf,
          onRemoteWorkspaceAction: (wsId, action) =>
              handleRemoteWorkspaceAction(context, wsId, action),
        ),
        // Alça de arraste na borda direita (direita = alarga).
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: _ResizeHandle(onDelta: onResize),
        ),
      ],
    );
  }
}

/// Multiplexador (árvore de splits) do workspace ativo — um por projeto, todos
/// montados no `IndexedStack` pra preservar estado ao trocar de workspace.
class _CenterPanel extends StatelessWidget {
  const _CenterPanel({required this.centerKey});

  final GlobalKey centerKey;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    final colors = context.colors;
    return KeyedSubtree(
      key: centerKey,
      child: vm.selectedProjectId == null
          ? WelcomeView(
              hasHosts: vm.remoteHosts.hosts.isNotEmpty,
              onCreateWorkspace: () => createWorkspace(context),
              onConnectHost: (anchor) =>
                  newRemoteWorkspace(context, vm, anchor),
              onConfigureHost: () => context.pushNamed(
                RoutePaths.settings,
                arguments: SettingsTab.remoteHosts,
              ),
            )
          : IndexedStack(
              index: _activeIndex(vm),
              sizing: StackFit.expand,
              children: [
                // Um multiplexador por projeto — todos montados, só
                // o ativo pintado → estado preservado ao trocar.
                for (final project in vm.projects)
                  KeyedSubtree(
                    key: ValueKey(project.id),
                    child: ColoredBox(
                      color: colors.border,
                      child: _multiplexer(
                        context,
                        vm,
                        project.id,
                        active: project.id == vm.selectedProjectId,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  int _activeIndex(CockpitViewModel vm) {
    final index = vm.projects.indexWhere((p) => p.id == vm.selectedProjectId);
    return index < 0 ? 0 : index;
  }

  Widget _multiplexer(
    BuildContext context,
    CockpitViewModel vm,
    String projectId, {
    required bool active,
  }) {
    final tree = vm.tree(projectId);
    if (tree == null) return const SizedBox.shrink();
    return _renderNode(context, vm, projectId, tree, active: active);
  }

  Widget _renderNode(
    BuildContext context,
    CockpitViewModel vm,
    String projectId,
    PaneNode node, {
    required bool active,
  }) {
    if (node is LeafPane) {
      return PaneDropZone(
        key: ValueKey('drop-${node.id}'),
        paneId: node.id,
        vm: vm,
        child: PaneView(
          key: ValueKey(node.id),
          pane: node,
          vm: vm,
          focused: active && node.id == vm.focusedPaneId(projectId),
          active: active,
          onCreateTab: () => vm.newEmptyTab(node.id),
          // Aba placeholder "Novo" (nem agente nem terminal): o novo pane vira
          // outro placeholder com o seletor Agent/Terminal (ou terminal direto
          // se `enableAgent` está off). Terminal abre na raiz; agente pergunta
          // a subpasta.
          onSplit: (dir) {
            if (vm.paneActiveIsEmpty(node.id)) {
              vm.splitPaneEmpty(node.id, dir);
            } else if (vm.paneActiveIsAgent(node.id)) {
              // Só agente pergunta a subpasta; terminal/browser/viewer/db abrem
              // direto na raiz do workspace (sem modal).
              pickSubfolderThen(
                context,
                (sub) => vm.splitPane(node.id, dir, sub),
              );
            } else {
              vm.splitPane(node.id, dir, '');
            }
          },
          onFillEmpty: (emptyId, terminal) => terminal
              ? vm.fillEmpty(node.id, emptyId, '', terminal: true)
              : pickSubfolderThen(
                  context,
                  (sub) => vm.fillEmpty(node.id, emptyId, sub, terminal: false),
                ),
          onHistoryAgent: (agentId) => openAgentHistory(context, agentId),
          onRenameAgent: (agentId, name) => renameAgent(context, agentId, name),
          onToggleRelayAgent: (agentId) => toggleRelayAgent(context, agentId),
        ),
      );
    }
    final split = node as SplitPane;
    final isRow = split.dir == SplitDir.vertical;
    // Largura da região de arraste (a linha visual continua 1px, centralizada).
    const handle = 12.0;

    // Panes dimensionados por PESO (flex), NÃO por LayoutBuilder. Crítico: um
    // LayoutBuilder envolvendo os panes reconstrói a subárvore a cada mudança de
    // constraint (abrir/fechar/redimensionar pane), e a TerminalView do flterm
    // faz attach de view no initState — reconstruir = novo attach antes do
    // detach do antigo → "already has an active view", e no restore (mount
    // simultâneo) cruza a State entre panes → terminais ESPELHADOS. Com Flex os
    // panes são filhos diretos e estáveis; só o RenderFlex recalcula tamanhos.
    final fa = (split.frac * 100000).round().clamp(1, 99999);
    final fb = 100000 - fa;
    final panes = Flex(
      direction: isRow ? Axis.horizontal : Axis.vertical,
      children: [
        Expanded(
          flex: fa,
          child: _renderNode(context, vm, projectId, split.a, active: active),
        ),
        Expanded(
          flex: fb,
          child: _renderNode(context, vm, projectId, split.b, active: active),
        ),
      ],
    );

    return Stack(
      children: [
        // Base: as duas panes adjacentes (a linha vem do handle por cima).
        panes,
        // Overlay do divisor. O LayoutBuilder AQUI é seguro: envolve só o handle
        // (stateless, barato de remontar), NUNCA os panes — precisa do tamanho
        // total pra posicionar a linha e converter o arraste px→fração.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final total = isRow
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final pos = total * split.frac;
              final divider = PaneDivider(
                dir: split.dir,
                onDelta: (delta) {
                  if (total <= 0) return;
                  // Delta incremental → fração, acumulado sobre o frac ATUAL da
                  // árvore. `total` é estável durante o arraste.
                  vm.resizeSplitBy(split.id, delta / total);
                },
              );
              return Stack(
                children: [
                  if (isRow)
                    Positioned(
                      left: pos - handle / 2,
                      width: handle,
                      top: 0,
                      bottom: 0,
                      child: divider,
                    )
                  else
                    Positioned(
                      top: pos - handle / 2,
                      height: handle,
                      left: 0,
                      right: 0,
                      child: divider,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Painel direito: árvore de arquivos, busca, DB e Tasks.
class _TreePanel extends StatelessWidget {
  const _TreePanel({
    required this.treeWidth,
    required this.tasksHeight,
    required this.sourceControlViewMode,
    required this.searchFocusSignal,
    required this.onDismiss,
    required this.onResizeTree,
    required this.onTasksResize,
    required this.onTasksResizeEnd,
  });

  final double treeWidth;
  final double tasksHeight;
  final SourceControlViewMode sourceControlViewMode;
  final ValueNotifier<int> searchFocusSignal;
  final VoidCallback onDismiss;
  final ValueChanged<double> onResizeTree;
  final ValueChanged<double> onTasksResize;
  final VoidCallback onTasksResizeEnd;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    final configuredHarnessId = context
        .watch<SettingsController>()
        .settings
        .automationHarnessId;
    return Stack(
      children: [
        FileTreePanel(
          // Pasta do workspace; reseta ao trocar de workspace.
          key: ValueKey(vm.treeRootPath),
          width: treeWidth,
          rootPath: vm.treeRootPath,
          sourceControlViewMode: sourceControlViewMode,
          onSourceControlViewModeChanged: context
              .read<SettingsController>()
              .setSourceControlViewMode,
          // Roots derivadas (multi-root local = seções por
          // repo; remoto = a pasta do host).
          roots: [
            for (final r in vm.treeRoots)
              WorkspaceRoot(
                path: r,
                name: r.split('/').last,
                git: vm.gitInfoForRoot(r),
              ),
          ],
          onStageFile: vm.stageFile,
          onStageFiles: vm.stageFiles,
          onUnstageFile: vm.unstageFile,
          onUnstageFiles: vm.unstageFiles,
          onDiscardFile: vm.discardFile,
          isNewGitFile: vm.isNewGitFile,
          onCommitFile: vm.commitFile,
          onCommitStaged: vm.commitStaged,
          onLoadCommits: vm.recentCommits,
          onLoadCommitMessage: vm.commitMessage,
          onLoadGitHistory: vm.loadGitHistory,
          onLoadGitHistoryFiles: vm.loadGitHistoryFiles,
          onOpenGitHistoryDiff: vm.openCommitDiff,
          gitHistoryRevision: vm.git.revision,
          commitMessageGeneratorLabel: configuredHarnessId?.label,
          onGenerateCommitMessage: configuredHarnessId != null
              ? vm.generateCommitMessageForFile
              : null,
          onGenerateStagedCommitMessage: configuredHarnessId != null
              ? vm.generateStagedCommitMessage
              : null,
          onCancelCommitMessageGeneration: vm.cancelCommitMessageGeneration,
          revision: vm.fileTreeRevision,
          selectedPath: vm.selectedFileInTree,
          listChildren: vm.listChildren,
          gitStatusOf: vm.gitStatusForPath,
          onOpenFile: (path) {
            vm.openFile(path, isPreview: false);
            onDismiss(); // fecha o drawer no mobile
          },
          onOpenChangedFile: vm.openChangedFile,
          onTapFile: (path) {
            vm.openFile(path); // clique único = preview
            onDismiss();
          },
          onSelectFile: vm.selectFileInTree, // atualiza highlight
          onClearSelection: vm.clearFileSelection,
          revealPath: vm.treeRevealPath,
          revealGen: vm.treeRevealGen,
          onOpenDiff: (path) => vm.openDiff(path, isPreview: false),
          onTapDiff: vm.openDiff, // clique único = preview
          isGitRepo:
              vm.selectedProject != null &&
              vm.isGitRepo(vm.selectedProject!.id),
          changedPaths: vm.changedAbsolutePaths(),
          stagedPaths: vm.stagedAbsolutePaths(),
          unstagedPaths: vm.unstagedAbsolutePaths(),
          onOpenWith: vm.openWithDefaultApp,
          onOpenLayout: (path) async {
            final res = await vm.applyLayoutFile(path);
            if (!context.mounted) return;
            if (res case Failure(:final error)) {
              await showInfoDialog(
                context,
                title: context.t.cockpit.cockpitPage.openLayoutTitle,
                message: error,
              );
            }
          },
          onCreateInFolder: (sub, terminal) =>
              vm.newTabIn(sub, terminal: terminal),
          onCreate: (parentDir, name, isFolder) => isFolder
              ? vm.createDirIn(parentDir, name)
              : vm.createFileIn(parentDir, name),
          onRename: vm.renamePath,
          onDelete: vm.deletePath,
          onMove: vm.movePath,
          onCopy: vm.copyToClipboard,
          onCut: vm.cutToClipboard,
          onPaste: vm.pasteInto,
          canPaste: vm.canPaste,
          searchPanel: vm.selectedProject == null
              ? null
              : ContentSearchPanel(
                  fill: true,
                  search: vm.searchContent,
                  onOpenResult: vm.openSearchResult,
                  focusSignal: searchFocusSignal,
                ),
          searchFocusSignal: searchFocusSignal,
          databasePanel: vm.selectedProject == null
              ? null
              : DbPanel(
                  workspaceId: vm.selectedProject!.id,
                  // Remoto: a root é a pasta do host
                  // (project.path é vazio).
                  workspaceRoot: vm.treeRootPath,
                ),
          // Task Run funciona local E remoto: no remoto a
          // descoberta lê o tasks.json do host (RemoteTask
          // Discovery) e a execução spawna PTY no host
          // (RemoteTaskRunner). É um dos modos do painel
          // direito (Files/Search/DB/Tasks), exposto também
          // no drawer do mobile (plano 60, Wave F3).
          tasksPanel: vm.selectedProject == null
              ? null
              : TasksPanel(
                  // Remoto: a raiz é a pasta do host
                  // (treeRootPath = remotePath); local usa o
                  // path do projeto.
                  cwd: vm.treeRootPath,
                  listHeight: tasksHeight,
                  onResizeDelta: onTasksResize,
                  onResizeEnd: onTasksResizeEnd,
                ),
          footer: const _LspStatusBar(),
        ),
        // Alça de arraste sobre a borda esquerda do painel
        // (esquerda = alarga; direita = estreita).
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _ResizeHandle(onDelta: onResizeTree),
        ),
      ],
    );
  }
}

/// Arranja as três panes (workspaces | centro | arquivos). Largo: uma Row com
/// as laterais inline (comportamento clássico do desktop). Estreito (mobile
/// portrait): as laterais viram DRAWERS sobrepostos ao centro, com um scrim que
/// fecha ao tocar (plano 60, Wave F). As panes já trazem sua própria largura
/// (ProjectsRail/FileTreePanel) e fundo.
class _PanelScaffold extends StatelessWidget {
  const _PanelScaffold({
    required this.narrow,
    required this.railOpen,
    required this.treeOpen,
    required this.rail,
    required this.center,
    required this.tree,
    required this.onDismiss,
  });

  final bool narrow;
  final bool railOpen;
  final bool treeOpen;
  final Widget rail;
  final Widget center;
  final Widget tree;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!narrow) {
      return Row(
        children: [
          if (railOpen) rail,
          Expanded(child: center),
          if (treeOpen) tree,
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: center),
        if (railOpen || treeOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: ColoredBox(color: context.colors.scrim),
            ),
          ),
        // top/bottom = 0 estica a pane em altura total; a largura vem da própria.
        if (railOpen) Positioned(left: 0, top: 0, bottom: 0, child: rail),
        if (treeOpen) Positioned(right: 0, top: 0, bottom: 0, child: tree),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDelta});

  /// Delta horizontal do arraste (px).
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: const SizedBox(width: 8),
      ),
    );
  }
}

/// Barra de status do LSP no rodapé do pane de Files. Reflete o servidor da aba
/// **focada**: linguagem + rodando/parado + botão de reiniciar. Quando a aba não
/// é um arquivo de código (agente/terminal/sem aba), fica vazia — mas mantém a
/// altura, pra não pular o layout. Reage a mudança de aba (watch da VM) e a
/// subida/queda de servidor (stream `lspStatusChanges`).
class _LspStatusBar extends StatefulWidget {
  const _LspStatusBar();

  @override
  State<_LspStatusBar> createState() => _LspStatusBarState();
}

class _LspStatusBarState extends State<_LspStatusBar> {
  StreamSubscription<void>? _sub;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<CockpitViewModel>().lspStatusChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _restart(CockpitViewModel vm) async {
    setState(() => _restarting = true);
    await vm.restartFocusedLsp();
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<CockpitViewModel>();
    final status = vm.focusedLspStatus;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: status == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.t.cockpit.cockpitPage.noLspAvailable,
                style: context.typo.label.copyWith(color: colors.text4),
              ),
            )
          : Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: status.running ? colors.online : colors.text4,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${status.label} LSP · ${status.running ? context.t.cockpit.cockpitPage.lspRunning : context.t.cockpit.cockpitPage.lspStopped}',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                AppTooltip(
                  message: context.t.cockpit.cockpitPage.restartServerTooltip,
                  child: HoverTap(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _restarting ? () {} : () => _restart(vm),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        Icons.refresh,
                        size: 15,
                        color: _restarting ? colors.text4 : colors.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Ações do menu de contexto do cabeçalho de uma root (multi-root).
