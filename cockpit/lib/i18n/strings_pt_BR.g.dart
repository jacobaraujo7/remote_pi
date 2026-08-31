///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsPtBr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsPtBr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ptBr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <pt-BR>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsPtBr _root = this; // ignore: unused_field

	@override 
	TranslationsPtBr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsPtBr(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$core$pt_BR core = _Translations$core$pt_BR._(_root);
	@override late final _Translations$common$pt_BR common = _Translations$common$pt_BR._(_root);
	@override late final _Translations$cockpit$pt_BR cockpit = _Translations$cockpit$pt_BR._(_root);
	@override late final _Translations$settings$pt_BR settings = _Translations$settings$pt_BR._(_root);
	@override late final _Translations$automation$pt_BR automation = _Translations$automation$pt_BR._(_root);
	@override late final _Translations$fileOperation$pt_BR fileOperation = _Translations$fileOperation$pt_BR._(_root);
	@override late final _Translations$theme$pt_BR theme = _Translations$theme$pt_BR._(_root);
}

// Path: core
class _Translations$core$pt_BR extends Translations$core$en {
	_Translations$core$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$core$bootstrapError$pt_BR bootstrapError = _Translations$core$bootstrapError$pt_BR._(_root);
	@override late final _Translations$core$macosNotifications$pt_BR macosNotifications = _Translations$core$macosNotifications$pt_BR._(_root);
	@override late final _Translations$core$appErrorView$pt_BR appErrorView = _Translations$core$appErrorView$pt_BR._(_root);
	@override late final _Translations$core$errorReportDialog$pt_BR errorReportDialog = _Translations$core$errorReportDialog$pt_BR._(_root);
	@override late final _Translations$core$windowControls$pt_BR windowControls = _Translations$core$windowControls$pt_BR._(_root);
	@override late final _Translations$core$crash$pt_BR crash = _Translations$core$crash$pt_BR._(_root);
	@override late final _Translations$core$menu$pt_BR menu = _Translations$core$menu$pt_BR._(_root);
}

// Path: common
class _Translations$common$pt_BR extends Translations$common$en {
	_Translations$common$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get confirm => 'Confirmar';
	@override String get create => 'Criar';
	@override String get gotIt => 'Entendi';
	@override String get save => 'Salvar';
	@override String get close => 'Fechar';
	@override String get delete => 'Excluir';
	@override String get done => 'Concluído';
	@override String get add => 'Adicionar';
	@override String get test => 'Testar';
	@override String get ok => 'OK';
	@override String get loading => 'Carregando…';
	@override String get checking => 'Verificando…';
	@override String get remove => 'Remover';
	@override String get restart => 'Reiniciar';
	@override String get settings => 'Configurações';
	@override String get send => 'Enviar';
	@override String get open => 'Abrir';
	@override String get dismiss => 'Dispensar';
	@override String get report => 'Reportar';
	@override String get copyCode => 'Copiar código';
	@override String get search => 'Buscar';
	@override String get noResults => 'Nenhum resultado';
}

// Path: cockpit
class _Translations$cockpit$pt_BR extends Translations$cockpit$en {
	_Translations$cockpit$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$cockpit$confirmDialog$pt_BR confirmDialog = _Translations$cockpit$confirmDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$neovim$pt_BR neovim = _Translations$cockpit$neovim$pt_BR._(_root);
	@override late final _Translations$cockpit$historyDialog$pt_BR historyDialog = _Translations$cockpit$historyDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$worktreeCreateDialog$pt_BR worktreeCreateDialog = _Translations$cockpit$worktreeCreateDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$subfolderDialog$pt_BR subfolderDialog = _Translations$cockpit$subfolderDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$commitMessageDialog$pt_BR commitMessageDialog = _Translations$cockpit$commitMessageDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$agentEditDialog$pt_BR agentEditDialog = _Translations$cockpit$agentEditDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$agentSetupChecklist$pt_BR agentSetupChecklist = _Translations$cockpit$agentSetupChecklist$pt_BR._(_root);
	@override late final _Translations$cockpit$agentComposer$pt_BR agentComposer = _Translations$cockpit$agentComposer$pt_BR._(_root);
	@override late final _Translations$cockpit$tasksPanel$pt_BR tasksPanel = _Translations$cockpit$tasksPanel$pt_BR._(_root);
	@override late final _Translations$cockpit$cockpitPage$pt_BR cockpitPage = _Translations$cockpit$cockpitPage$pt_BR._(_root);
	@override late final _Translations$cockpit$welcomeView$pt_BR welcomeView = _Translations$cockpit$welcomeView$pt_BR._(_root);
	@override late final _Translations$cockpit$modelPicker$pt_BR modelPicker = _Translations$cockpit$modelPicker$pt_BR._(_root);
	@override late final _Translations$cockpit$paneView$pt_BR paneView = _Translations$cockpit$paneView$pt_BR._(_root);
	@override late final _Translations$cockpit$fileTreePanel$pt_BR fileTreePanel = _Translations$cockpit$fileTreePanel$pt_BR._(_root);
	@override late final _Translations$cockpit$fileViewer$pt_BR fileViewer = _Translations$cockpit$fileViewer$pt_BR._(_root);
	@override late final _Translations$cockpit$workspaceSettingsDialog$pt_BR workspaceSettingsDialog = _Translations$cockpit$workspaceSettingsDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$realmDialogs$pt_BR realmDialogs = _Translations$cockpit$realmDialogs$pt_BR._(_root);
	@override late final _Translations$cockpit$dbRedisTable$pt_BR dbRedisTable = _Translations$cockpit$dbRedisTable$pt_BR._(_root);
	@override late final _Translations$cockpit$dbQueryView$pt_BR dbQueryView = _Translations$cockpit$dbQueryView$pt_BR._(_root);
	@override late final _Translations$cockpit$httpView$pt_BR httpView = _Translations$cockpit$httpView$pt_BR._(_root);
	@override late final _Translations$cockpit$dbPanel$pt_BR dbPanel = _Translations$cockpit$dbPanel$pt_BR._(_root);
	@override late final _Translations$cockpit$dbMongoView$pt_BR dbMongoView = _Translations$cockpit$dbMongoView$pt_BR._(_root);
	@override late final _Translations$cockpit$dbConnectionDialog$pt_BR dbConnectionDialog = _Translations$cockpit$dbConnectionDialog$pt_BR._(_root);
	@override late final _Translations$cockpit$sshPrompts$pt_BR sshPrompts = _Translations$cockpit$sshPrompts$pt_BR._(_root);
	@override late final _Translations$cockpit$projectsRail$pt_BR projectsRail = _Translations$cockpit$projectsRail$pt_BR._(_root);
	@override late final _Translations$cockpit$findBar$pt_BR findBar = _Translations$cockpit$findBar$pt_BR._(_root);
	@override late final _Translations$cockpit$contentSearch$pt_BR contentSearch = _Translations$cockpit$contentSearch$pt_BR._(_root);
	@override late final _Translations$cockpit$emptyPane$pt_BR emptyPane = _Translations$cockpit$emptyPane$pt_BR._(_root);
	@override late final _Translations$cockpit$topbar$pt_BR topbar = _Translations$cockpit$topbar$pt_BR._(_root);
	@override late final _Translations$cockpit$transcript$pt_BR transcript = _Translations$cockpit$transcript$pt_BR._(_root);
	@override late final _Translations$cockpit$tasks$pt_BR tasks = _Translations$cockpit$tasks$pt_BR._(_root);
	@override late final _Translations$cockpit$notifications$pt_BR notifications = _Translations$cockpit$notifications$pt_BR._(_root);
	@override late final _Translations$cockpit$terminal$pt_BR terminal = _Translations$cockpit$terminal$pt_BR._(_root);
	@override late final _Translations$cockpit$remoteHost$pt_BR remoteHost = _Translations$cockpit$remoteHost$pt_BR._(_root);
	@override late final _Translations$cockpit$browserPane$pt_BR browserPane = _Translations$cockpit$browserPane$pt_BR._(_root);
}

// Path: settings
class _Translations$settings$pt_BR extends Translations$settings$en {
	_Translations$settings$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$language$pt_BR language = _Translations$settings$language$pt_BR._(_root);
	@override late final _Translations$settings$revokeDialog$pt_BR revokeDialog = _Translations$settings$revokeDialog$pt_BR._(_root);
	@override late final _Translations$settings$pairingDialog$pt_BR pairingDialog = _Translations$settings$pairingDialog$pt_BR._(_root);
	@override late final _Translations$settings$page$pt_BR page = _Translations$settings$page$pt_BR._(_root);
	@override late final _Translations$settings$remoteHosts$pt_BR remoteHosts = _Translations$settings$remoteHosts$pt_BR._(_root);
}

// Path: automation
class _Translations$automation$pt_BR extends Translations$automation$en {
	_Translations$automation$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$automation$error$pt_BR error = _Translations$automation$error$pt_BR._(_root);
}

// Path: fileOperation
class _Translations$fileOperation$pt_BR extends Translations$fileOperation$en {
	_Translations$fileOperation$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$fileOperation$error$pt_BR error = _Translations$fileOperation$error$pt_BR._(_root);
}

// Path: theme
class _Translations$theme$pt_BR extends Translations$theme$en {
	_Translations$theme$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$theme$error$pt_BR error = _Translations$theme$error$pt_BR._(_root);
}

// Path: core.bootstrapError
class _Translations$core$bootstrapError$pt_BR extends Translations$core$bootstrapError$en {
	_Translations$core$bootstrapError$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Falha ao inicializar o Cockpit';
	@override String get retry => 'Tentar novamente';
}

// Path: core.macosNotifications
class _Translations$core$macosNotifications$pt_BR extends Translations$core$macosNotifications$en {
	_Translations$core$macosNotifications$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ativar notificações no macOS';
	@override String get intro => 'As notificações estão desativadas nas configurações do sistema. Siga os passos abaixo para ativá-las:';
	@override String get step1 => 'Abra as Configurações do Sistema no seu Mac.';
	@override String get step2 => 'Acesse a seção Notificações na barra lateral esquerda.';
	@override String get step3 => 'Encontre e selecione o aplicativo Cockpit na lista.';
	@override String get step4 => 'Ative a opção Permitir Notificações.';
	@override String get tip => 'Dica: se o aplicativo não aparecer na lista, feche e reabra-o para acionar seu registro no sistema.';
	@override String get gotIt => 'Entendi';
}

// Path: core.appErrorView
class _Translations$core$appErrorView$pt_BR extends Translations$core$appErrorView$en {
	_Translations$core$appErrorView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get renderFailed => 'Esta parte do aplicativo falhou ao renderizar';
	@override String get details => 'Detalhes';
	@override String get renderErrorTitle => 'Erro de renderização';
}

// Path: core.errorReportDialog
class _Translations$core$errorReportDialog$pt_BR extends Translations$core$errorReportDialog$en {
	_Translations$core$errorReportDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get defaultDescription => 'Algo deu errado. Os detalhes abaixo foram salvos no log — você pode reportá-los para que isso seja corrigido.';
	@override String get copyDetails => 'Copiar detalhes';
	@override String get reportIssue => 'Reportar problema';
}

// Path: core.windowControls
class _Translations$core$windowControls$pt_BR extends Translations$core$windowControls$en {
	_Translations$core$windowControls$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get minimize => 'Minimizar';
	@override String get maximize => 'Maximizar';
	@override String get close => 'Fechar';
}

// Path: core.crash
class _Translations$core$crash$pt_BR extends Translations$core$crash$en {
	_Translations$core$crash$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Encerramento inesperado';
	@override String get bannerTitle => 'O Cockpit fechou inesperadamente';
	@override String get report => 'Reportar';
	@override String get dismiss => 'Dispensar';
	@override String crashMessage({required Object version}) => 'A sessão anterior (versão ${version}) terminou sem encerrar corretamente. Quer reportar? O log vai junto e você pode revisar tudo antes de enviar.';
	@override String crashError({required Object startedAt, required Object pid}) => 'A sessão iniciada em ${startedAt} (pid ${pid}) terminou sem encerramento limpo.';
	@override String get crashDescription => 'Nenhum erro foi capturado: o app foi encerrado pelo sistema. O log abaixo é dessa sessão e é a parte mais útil.';
}

// Path: core.menu
class _Translations$core$menu$pt_BR extends Translations$core$menu$en {
	_Translations$core$menu$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get settings => 'Configurações…';
	@override String get checkForUpdates => 'Verificar Atualizações…';
	@override String get file => 'Arquivo';
	@override String get newAgent => 'Novo Agente';
	@override String get newTerminal => 'Novo Terminal';
	@override String get openWorkspace => 'Abrir Workspace';
	@override String get save => 'Salvar';
	@override String get discard => 'Descartar';
	@override String get format => 'Formatar';
	@override String get view => 'Exibir';
	@override String get toggleWorkspacePanel => 'Alternar Painel de Workspaces';
	@override String get toggleFiles => 'Alternar Arquivos';
	@override String get splitRight => 'Dividir à Direita';
	@override String get splitDown => 'Dividir Abaixo';
	@override String get focusPane => 'Focar Painel';
	@override String get focusLeft => 'Esquerda  (⌘⌥←)';
	@override String get focusRight => 'Direita  (⌘⌥→)';
	@override String get focusUp => 'Acima  (⌘⌥↑)';
	@override String get focusDown => 'Abaixo  (⌘⌥↓)';
	@override String get selectTab => 'Selecionar Aba';
	@override String tabN({required Object n}) => 'Aba ${n}';
	@override String get lastTab => 'Última Aba';
	@override String get zoomIn => 'Aumentar Zoom';
	@override String get zoomOut => 'Diminuir Zoom';
	@override String get actualSize => 'Tamanho Real';
	@override String get window => 'Janela';
	@override String get quit => 'Sair';
	@override String get minimize => 'Minimizar';
	@override String get zoom => 'Zoom';
}

// Path: cockpit.confirmDialog
class _Translations$cockpit$confirmDialog$pt_BR extends Translations$cockpit$confirmDialog$en {
	_Translations$cockpit$confirmDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unsavedChangesTitle => 'Alterações não salvas';
	@override String unsavedChangesMessage({required Object fileName}) => '“${fileName}” tem alterações não salvas. Salvar antes de fechar?';
	@override String get dontSave => 'Não salvar';
	@override String get saveAndClose => 'Salvar e fechar';
}

// Path: cockpit.neovim
class _Translations$cockpit$neovim$pt_BR extends Translations$cockpit$neovim$en {
	_Translations$cockpit$neovim$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unavailable => 'O Neovim não está disponível. Abrindo no Cockpit.';
	@override String get openFailed => 'Não foi possível acessar o Neovim. Abrindo no Cockpit.';
	@override String get unsavedTitle => 'Buffers não salvos no Neovim';
	@override String get unsavedMessage => 'O Neovim tem buffers modificados. Fechar a aba e descartar essas alterações?';
	@override String get closeAnyway => 'Fechar mesmo assim';
}

// Path: cockpit.historyDialog
class _Translations$cockpit$historyDialog$pt_BR extends Translations$cockpit$historyDialog$en {
	_Translations$cockpit$historyDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Histórico de sessões';
	@override String get subtitle => 'Abrir uma substitui a transcrição atual deste agente';
	@override String get empty => 'Nenhuma sessão salva nesta pasta.';
	@override String get untitledSession => 'Sessão sem título';
	@override String get justNow => 'agora';
	@override String minutesAgo({required Object n}) => '${n} min atrás';
	@override String hoursAgo({required Object n}) => '${n} h atrás';
	@override String daysAgo({required Object n}) => '${n} d atrás';
}

// Path: cockpit.worktreeCreateDialog
class _Translations$cockpit$worktreeCreateDialog$pt_BR extends Translations$cockpit$worktreeCreateDialog$en {
	_Translations$cockpit$worktreeCreateDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get forkTitle => 'Fork da worktree';
	@override String get createTitle => 'Criar worktree';
	@override String forkSubtitle({required Object root}) => 'Nova worktree ramificada a partir de ${root}.';
	@override String createSubtitle({required Object root}) => 'Nova feature em ${root} — novo branch a partir do HEAD atual.';
	@override String get namePlaceholder => 'feat/minha-feature';
	@override String get errorWhitespace => 'Sem espaços no nome.';
	@override String get errorInvalidChar => 'Caractere inválido para nome de branch.';
	@override String get errorInvalidSequence => 'Sequência inválida (ex.: "..", "//", começar/terminar com "/").';
	@override String get errorReserved => 'Posição reservada (não comece com "-"/"." nem termine com ".lock").';
	@override String get errorDuplicateBranch => 'Já existe um branch com esse nome.';
	@override String get errorDuplicateWorktree => 'Já existe uma worktree com esse nome.';
	@override String errorBranchHierarchyConflict({required Object target, required Object existing}) => 'Não é possível criar o branch \'${target}\' porque ele conflita com o branch \'${existing}\' já existente.';
	@override String get errorBranchHierarchicalConflictGeneral => 'Já existe um branch com uma hierarquia conflitante.';
	@override String get fork => 'Fork';
	@override String get postCheckoutHint => 'Este repositório tem um hook post-checkout.';
	@override String get running => 'Executando…';
	@override String get advancedSettings => 'Configurações Avançadas';
	@override String get copyIgnored => 'Copiar arquivos ignorados (.gitignore)';
	@override String get copyIgnoredDesc => 'Copia arquivos ignorados pelo .gitignore (ex: .env, chaves locais) para a nova pasta.';
	@override String get copyUntracked => 'Copiar arquivos não rastreados';
	@override String get copyUntrackedDesc => 'Copia arquivos novos ou modificados que ainda não foram adicionados ao stage.';
	@override String get baseBranch => 'Branch base';
	@override String get baseBranchDesc => 'O branch de onde a nova worktree e branch serão ramificados.';
	@override String get fetchRemote => 'Sincronizar branch remota (fetch)';
	@override String get fetchRemoteDesc => 'Roda git fetch para garantir que a branch base esteja confirmada antes de criar a worktree.';
	@override String get searchBranch => 'Buscar branch...';
	@override String get back => 'Voltar';
}

// Path: cockpit.subfolderDialog
class _Translations$cockpit$subfolderDialog$pt_BR extends Translations$cockpit$subfolderDialog$en {
	_Translations$cockpit$subfolderDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Onde trabalhar?';
	@override String get empty => 'Nenhuma subpasta aqui.';
	@override String useRoot({required Object project}) => 'Usar a raiz de ${project}';
	@override String usePath({required Object project, required Object rel}) => 'Usar ${project}/${rel}';
	@override String get useThisFolder => 'Usar esta pasta';
}

// Path: cockpit.commitMessageDialog
class _Translations$cockpit$commitMessageDialog$pt_BR extends Translations$cockpit$commitMessageDialog$en {
	_Translations$cockpit$commitMessageDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get commitTitle => 'Commit';
	@override String get stageAndCommitTitle => 'Stage e Commit';
	@override String scopeNote({required Object fileName}) => 'Commit apenas de "${fileName}".';
	@override String get placeholder => 'fix: resumo curto da mudança';
	@override String get errorEmptySubject => 'A primeira linha (assunto) não pode ficar vazia.';
	@override String errorTooShort({required Object min}) => 'Assunto muito curto (mín. ${min} caracteres).';
	@override String errorTooLong({required Object max}) => 'Assunto muito longo (máx. ${max} caracteres).';
	@override String get errorTrailingPeriod => 'O assunto não deve terminar com ponto.';
	@override String get errorControlChars => 'O assunto contém caracteres de controle.';
	@override String get errorBlankSecondLine => 'Deixe a segunda linha em branco (separador entre assunto e corpo do git).';
	@override String get generate => 'Gerar mensagem de commit';
	@override String generateWith({required Object harness}) => 'Gerar com ${harness}';
	@override String get generating => 'Gerando…';
	@override String get cancelGeneration => 'Cancelar geração';
}

// Path: cockpit.agentEditDialog
class _Translations$cockpit$agentEditDialog$pt_BR extends Translations$cockpit$agentEditDialog$en {
	_Translations$cockpit$agentEditDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Editar agente';
	@override String get agentName => 'Nome do agente';
	@override String get relaySection => 'Relay (remote-pi)';
	@override String get autoConnect => 'Conectar automaticamente ao iniciar';
	@override String get informationSection => 'Informações';
	@override String get folder => 'Pasta';
	@override String get model => 'Modelo';
	@override String get state => 'Estado';
	@override String get context => 'Contexto';
	@override String get statusEmpty => 'vazio';
	@override String get statusStarting => 'iniciando';
	@override String get statusReady => 'pronto';
	@override String get statusStreaming => 'transmitindo';
	@override String get statusEnded => 'encerrado';
}

// Path: cockpit.agentSetupChecklist
class _Translations$cockpit$agentSetupChecklist$pt_BR extends Translations$cockpit$agentSetupChecklist$en {
	_Translations$cockpit$agentSetupChecklist$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Configurar o ambiente do agente';
	@override String get intro => 'Rodar um agente exige o Pi instalado. Complete os passos abaixo — terminais e arquivos funcionam sem nada disso.';
	@override String get step1Title => 'Pi Code instalado';
	@override String get step1Description => 'O binário `pi` precisa estar acessível.';
	@override String get step2Title => 'Extensão remote-pi no Pi';
	@override String get step2Description => 'Registrada em ~/.pi/agent/settings.json.';
	@override String get step3Title => 'Supervisor instalado';
	@override String get step3Description => 'Serviço pi-supervisord (remote-pi install).';
	@override String get install => 'Instalar';
	@override String get installExtensionTitle => 'Instalar extensão remote-pi';
	@override String get installSupervisorTitle => 'Instalar supervisor';
	@override String get createAgent => 'Criar agente';
	@override String get back => 'Voltar';
	@override String get checkAgain => 'Verificar novamente';
	@override String get notRequired => 'Não obrigatório nesta configuração';
	@override String get installing => 'Instalando…';
	@override String get installedSuccessfully => 'Instalado com sucesso.';
}

// Path: cockpit.agentComposer
class _Translations$cockpit$agentComposer$pt_BR extends Translations$cockpit$agentComposer$en {
	_Translations$cockpit$agentComposer$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cmdNewDescription => 'Nova sessão — limpa a conversa';
	@override String get cmdCompactDescription => 'Compacta o contexto do agente';
	@override String get attachFile => 'Anexar arquivo';
	@override String maxImages({required Object max}) => 'Máximo de ${max} imagens.';
	@override String get placeholder => 'Mensagem para o agente, use @files ou /commands';
	@override String get stop => 'Parar';
	@override String get send => 'Enviar';
	@override String get relayOnline => 'Relay online';
	@override String get relayReconnecting => 'Relay reconectando...';
	@override String get relayOffline => 'Relay offline';
	@override String contextTooltip({required Object pct}) => 'Contexto: ${pct}% da janela';
	@override String get visionWarning => 'O modelo atual não consegue ver imagens — troque para um com suporte a visão.';
	@override String get modelFallback => 'modelo';
}

// Path: cockpit.tasksPanel
class _Translations$cockpit$tasksPanel$pt_BR extends Translations$cockpit$tasksPanel$en {
	_Translations$cockpit$tasksPanel$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get reloadTasksTooltip => 'Recarregar tasks';
	@override String get restartTooltip => 'Reiniciar';
	@override String get stopTooltip => 'Parar';
	@override String get runTooltip => 'Executar';
	@override String sendsKeyTooltip({required Object label, required Object key}) => '${label} (envia \'${key}\')';
	@override String get startingTooltip => 'Iniciando…';
	@override String get stoppingTooltip => 'Parando…';
	@override String get switchProfileTooltip => 'Trocar perfil';
	@override String get moreKeysTooltip => 'Mais teclas';
	@override String get sectionTasks => 'TAREFAS';
	@override String get noTasks => 'Nenhuma tarefa detectada neste projeto.';
	@override String get createTasksJson => 'Criar tasks.json';
}

// Path: cockpit.cockpitPage
class _Translations$cockpit$cockpitPage$pt_BR extends Translations$cockpit$cockpitPage$en {
	_Translations$cockpit$cockpitPage$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get chooseProjectFolderDialogTitle => 'Escolha a pasta do projeto';
	@override String get chooseWorkspaceFolderDialogTitle => 'Escolha a pasta do workspace';
	@override String get workspaceRenamedTitle => 'Workspace renomeado';
	@override String workspaceRenamedMessage({required Object name}) => 'O novo nome "${name}" só será enviado aos agentes após reiniciar o workspace ou o aplicativo.';
	@override String syncTitle({required Object label}) => 'Sync — ${label}';
	@override String pullTitle({required Object label}) => 'Pull — ${label}';
	@override String pushTitle({required Object label}) => 'Push — ${label}';
	@override String updateFromParentTitle({required Object name}) => 'Atualizar a partir do Pai — ${name}';
	@override String mergeToParentTitle({required Object name}) => 'Merge para o Pai — ${name}';
	@override String get worktreeMergedAndRemoved => 'Worktree mesclada e removida.';
	@override String get nothingWasChanged => 'Nada foi alterado.';
	@override String get newRealmTitle => 'Novo realm';
	@override String get closeWorkspaceTitle => 'Fechar workspace';
	@override String closeWorkspaceMessage({required Object name}) => 'Fechar "${name}"? Os agentes deste workspace serão encerrados. A pasta no disco é mantida.';
	@override String get closeAction => 'Fechar';
	@override String get removeWorktreeTitle => 'Remover worktree';
	@override String removeWorktreeMessage({required Object name, required Object warn}) => 'Remover "${name}"? A pasta da worktree e o branch serão excluídos e os agentes deste fork serão encerrados.${warn}';
	@override String removeWorktreeWarning({required Object name}) => '\n\nAviso: o branch "${name}" ainda não foi mesclado — removê-lo (git branch -D) descarta o trabalho não mesclado.';
	@override String get failedToRemoveWorktreeTitle => 'Falha ao remover a worktree';
	@override String get openLayoutTitle => 'Abrir layout';
	@override String get restartServerTooltip => 'Reiniciar servidor';
	@override String get noLspAvailable => 'Nenhum LSP disponível';
	@override String get lspRunning => 'em execução';
	@override String get lspStopped => 'parado';
}

// Path: cockpit.welcomeView
class _Translations$cockpit$welcomeView$pt_BR extends Translations$cockpit$welcomeView$en {
	_Translations$cockpit$welcomeView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bem-vindo ao Cockpit';
	@override String get subtitle => 'Abra uma pasta ou conecte a um host remoto para começar.';
	@override String get createWorkspace => 'Criar workspace';
	@override String get openLocalFolder => 'Abrir pasta local';
	@override String get connectHost => 'Conectar a um host';
	@override String get configureHost => 'Configurar host';
	@override String get addWorkspace => 'Adicionar workspace';
}

// Path: cockpit.modelPicker
class _Translations$cockpit$modelPicker$pt_BR extends Translations$cockpit$modelPicker$en {
	_Translations$cockpit$modelPicker$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String search({required Object count}) => 'Buscar modelo (${count})';
}

// Path: cockpit.paneView
class _Translations$cockpit$paneView$pt_BR extends Translations$cockpit$paneView$en {
	_Translations$cockpit$paneView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get closePaneTitle => 'Fechar painel?';
	@override String closePaneMessage({required Object count}) => 'Isso fecha todas as ${count} aba(s) deste painel e encerra os agentes/terminais nele.';
	@override String get close => 'Fechar';
	@override String get allTabs => 'Todas as abas';
	@override String get pinTab => 'Fixar aba';
	@override String get rename => 'Renomear';
	@override String get resetTitle => 'Redefinir título';
	@override String get copyId => 'Copiar Id';
	@override String get autoRelay => 'Auto-relay';
	@override String get history => 'Histórico';
	@override String get newTab => 'Nova aba';
	@override String get newTerminal => 'Novo terminal…';
	@override String get splitRight => 'Dividir à direita';
	@override String get splitDown => 'Dividir abaixo';
	@override String get closePane => 'Fechar painel';
	@override String get dropHereToMove => 'Solte aqui para mover a aba';
	@override String get dockAsTab => 'Encaixar como aba';
	@override String get openBrowser => 'Abrir navegador';
	@override String get openTerminal => 'Abrir terminal';
}

// Path: cockpit.fileTreePanel
class _Translations$cockpit$fileTreePanel$pt_BR extends Translations$cockpit$fileTreePanel$en {
	_Translations$cockpit$fileTreePanel$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get viewDiff => 'Ver Diff';
	@override String get commit => 'Commit';
	@override String get stageAndCommit => 'Stage e Commit';
	@override String get unstage => 'Tirar do stage';
	@override String get stageChanges => 'Colocar no stage';
	@override String get discardChanges => 'Descartar alterações';
	@override String get enterCommitMessage => 'Digite uma mensagem de commit.';
	@override String get commitUnavailable => 'Commit indisponível para este workspace.';
	@override String get gitErrorTitle => 'Erro do Git';
	@override String get deleteNewFileTitle => 'Excluir arquivo novo?';
	@override String get discardChangesTitle => 'Descartar alterações?';
	@override String deleteNewFileMessage({required Object name}) => '"${name}" é um arquivo novo e não pode ser restaurado. Excluir?';
	@override String discardOneMessage({required Object name}) => 'Descartar todas as alterações em "${name}"? Arquivos excluídos serão restaurados.';
	@override String get discard => 'Descartar';
	@override String get deleteAllNewFilesTitle => 'Excluir todos os arquivos novos?';
	@override String allNewFilesMessage({required Object count}) => 'Todos os ${count} arquivos são novos e serão excluídos. Isso não pode ser desfeito.';
	@override String discardTrackedMessage({required Object count, required Object extra}) => 'Descartar alterações em ${count} arquivo(s) rastreado(s)?${extra}';
	@override String discardTrackedExtra({required Object count}) => ' ${count} arquivo(s) novo(s) será(ão) mantido(s).';
	@override String get deleteAll => 'Excluir tudo';
	@override String get deleteQuestionTitle => 'Excluir?';
	@override String moveToTrash({required Object name}) => 'Mover “${name}” para a Lixeira?';
	@override String permanentlyDelete({required Object name}) => 'Excluir “${name}” permanentemente? Isso não pode ser desfeito.';
	@override String get couldNotDeleteTitle => 'Não foi possível excluir';
	@override String get moveQuestionTitle => 'Mover?';
	@override String moveMessage({required Object name, required Object dest}) => 'Mover “${name}” para “${dest}”?';
	@override String get moveAction => 'Mover';
	@override String get couldNotMoveTitle => 'Não foi possível mover';
	@override String get couldNotPasteTitle => 'Não foi possível colar';
	@override String get filesTooltip => 'Arquivos';
	@override String get searchTooltip => 'Buscar';
	@override String get sourceControlTooltip => 'Controle de versão';
	@override String get databaseTooltip => 'Banco de dados';
	@override String get sectionFiles => 'ARQUIVOS';
	@override String get newFile => 'Novo arquivo';
	@override String get newFolder => 'Nova pasta';
	@override String get refreshTooltip => 'Atualizar';
	@override String get sectionSourceControl => 'CONTROLE DE VERSÃO';
	@override String get viewAsList => 'Ver como lista';
	@override String get viewAsTree => 'Ver como árvore';
	@override String get noFolderMessage => 'Nenhuma pasta — abra um workspace.';
	@override String get amend => 'Amend';
	@override String get commitMessagePlaceholder => 'Mensagem do commit';
	@override String get amendCommit => 'Amend do commit';
	@override String get lastCommit => 'último commit';
	@override String get openInFinder => 'Abrir no Finder';
	@override String get openInExplorer => 'Abrir no Explorer';
	@override String get openInFileManager => 'Abrir no gerenciador de arquivos';
	@override String get open => 'Abrir';
	@override String get openWith => 'Abrir com';
	@override String get openLayout => 'Abrir layout';
	@override String get showGitDiff => 'Mostrar diff do git';
	@override String get createAgent => 'Criar agente';
	@override String get createTerminal => 'Criar terminal';
	@override String get rename => 'Renomear';
	@override String get copy => 'Copiar';
	@override String get cut => 'Recortar';
	@override String get paste => 'Colar';
	@override String get copyRelativePath => 'Copiar caminho relativo';
	@override String get copyAbsolutePath => 'Copiar caminho absoluto';
	@override String get renameFailed => 'Falha ao renomear.';
	@override String get noChanges => 'Nenhuma alteração.';
	@override String stagedChangesHeader({required Object count}) => 'ALTERAÇÕES EM STAGE (${count})';
	@override String changesHeader({required Object count}) => 'ALTERAÇÕES (${count})';
	@override String get discardAllChanges => 'Descartar todas as alterações';
	@override String get unstageAllChanges => 'Tirar tudo do stage';
	@override String get stageAllChanges => 'Colocar tudo no stage';
	@override String get discardFolderChanges => 'Descartar alterações da pasta';
	@override String get unstageFolderChanges => 'Tirar pasta do stage';
	@override String get stageFolderChanges => 'Colocar pasta no stage';
	@override String get generateCommitMessage => 'Gerar mensagem de commit';
	@override String generateWith({required Object harness}) => 'Gerar com ${harness}';
	@override String get generateUnavailableWhileAmending => 'Indisponível durante o amend de um commit';
	@override String get cancelGeneration => 'Cancelar geração';
	@override String get changes => 'Alteracoes';
	@override String get history => 'Historico';
	@override String get historyRepository => 'Repositorio';
	@override String get historyNoRepository => 'Nenhum repositorio Git disponivel.';
	@override String get historyEmpty => 'Nenhum commit encontrado.';
	@override String get historyLoadFailed => 'Nao foi possivel carregar o historico Git.';
	@override String get historyUntitledCommit => 'Commit sem titulo';
	@override String get historyNow => 'agora';
	@override String historyMinutesAgo({required Object count}) => 'ha ${count} min';
	@override String historyHoursAgo({required Object count}) => 'ha ${count} h';
	@override String get historyYesterday => 'ontem';
	@override String get historyDayAgo => 'ha 1 dia';
	@override String historyDaysAgo({required Object count}) => 'ha ${count} dias';
	@override String get historyFiles => 'Arquivos alterados';
	@override String get historyFilesEmpty => 'Nenhum arquivo alterado.';
	@override String get historyFilesLoadFailed => 'Nao foi possivel carregar os arquivos alterados.';
	@override String get diffEmptyTree => 'Arvore vazia';
	@override String diffOriginal({required Object ref}) => 'Original ${ref}';
	@override String diffModified({required Object ref}) => 'Modificado ${ref}';
	@override String get diffWorkingTree => 'Diretorio de trabalho';
	@override String get diffBinaryFile => 'Arquivo binario - sem diff de texto.';
	@override String get diffNoChanges => 'Sem alteracoes.';
}

// Path: cockpit.fileViewer
class _Translations$cockpit$fileViewer$pt_BR extends Translations$cockpit$fileViewer$en {
	_Translations$cockpit$fileViewer$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cantOpen => 'Não é possível abrir este arquivo.';
	@override String get couldNotLoadImage => 'Não foi possível carregar a imagem.';
	@override String get preview => 'Pré-visualização';
	@override String get source => 'Código-fonte';
}

// Path: cockpit.workspaceSettingsDialog
class _Translations$cockpit$workspaceSettingsDialog$pt_BR extends Translations$cockpit$workspaceSettingsDialog$en {
	_Translations$cockpit$workspaceSettingsDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get choosePhotoTitle => 'Escolher foto do workspace';
	@override String get title => 'Configurações do workspace';
	@override String get namePlaceholder => 'Nome do workspace';
	@override String get addPhoto => 'Adicionar foto';
	@override String get changePhoto => 'Alterar foto';
	@override String get remove => 'Remover';
	@override String get color => 'Cor';
	@override String get host => 'Host';
	@override String get folder => 'Pasta';
}

// Path: cockpit.realmDialogs
class _Translations$cockpit$realmDialogs$pt_BR extends Translations$cockpit$realmDialogs$en {
	_Translations$cockpit$realmDialogs$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get namePlaceholder => 'Nome do realm';
	@override String get duplicateName => 'Já existe um realm com esse nome.';
	@override String get newRealmTitle => 'Novo realm';
	@override String get renameRealmTitle => 'Renomear realm';
	@override String get rename => 'Renomear';
	@override String get deleteRealmTitle => 'Excluir realm';
	@override String deleteMessage({required Object name, required Object suffix}) => 'Excluir "${name}"? Nenhum workspace é excluído — só a lista de pastas muda.${suffix}';
	@override String get deleteSuffixOne => ' O workspace dele irá para o Padrão.';
	@override String deleteSuffixMany({required Object count}) => ' Os ${count} workspaces dele irão para o Padrão.';
	@override String get manageRealmsTitle => 'Gerenciar realms';
	@override String workspaceCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 workspace',
		other: '${n} workspaces',
	);
}

// Path: cockpit.dbRedisTable
class _Translations$cockpit$dbRedisTable$pt_BR extends Translations$cockpit$dbRedisTable$en {
	_Translations$cockpit$dbRedisTable$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get deleteKeyTitle => 'Excluir chave';
	@override String deleteKeyMessage({required Object key}) => 'Excluir "${key}" deste banco Redis?';
	@override String get refresh => 'Atualizar';
	@override String get newKey => 'Nova chave';
	@override String get columnKey => 'CHAVE';
	@override String get columnValue => 'VALOR';
	@override String get columnType => 'TIPO';
	@override String get columnTtl => 'TTL';
	@override String keyCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 chave',
		other: '${n} chaves',
	);
	@override String get noKeys => 'Nenhuma chave neste banco de dados.';
	@override String noKeysMatch({required Object pattern}) => 'Nenhuma chave corresponde a "${pattern}".';
	@override String get loadMore => 'Carregar mais';
	@override String get loadingFullValue => 'Carregando valor completo…';
	@override String get ttlMustBeNumber => 'TTL deve ser um número de segundos.';
	@override String get addKey => 'Adicionar chave';
	@override String get keyFieldHint => 'chave';
	@override String get ttlFieldHint => 'ttl (s, opcional)';
	@override String get valueFieldHint => 'valor';
	@override String get searchHint => 'Buscar — padrão, ex.: user:*';
}

// Path: cockpit.dbQueryView
class _Translations$cockpit$dbQueryView$pt_BR extends Translations$cockpit$dbQueryView$en {
	_Translations$cockpit$dbQueryView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get saveQueryAs => 'Salvar query como';
	@override String get couldNotSave => 'Não foi possível salvar';
	@override String get selectDatabase => 'Selecionar banco de dados';
	@override String get noSqlConnections => 'Nenhuma conexão SQL — adicione uma no painel Database';
	@override String get running => 'Executando…';
	@override String get runSelection => 'Executar seleção';
	@override String get run => 'Executar';
	@override String get pickDatabaseHint => 'Escolha um banco de dados acima e depois Executar (⌘↵).';
	@override String get runQueryHint => 'Execute a query (⌘↵) para ver os resultados aqui.';
	@override String get noRows => 'Nenhuma linha.';
	@override String rowsAffected({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 linha afetada',
		other: '${n} linhas afetadas',
	);
	@override String rowsFooter({required Object n}) => '${n} linhas';
	@override String get truncatedSuffix => ' · truncado (aumente -- limit)';
	@override String get table => 'Tabela';
	@override String get json => 'JSON';
	@override String get unsaved => 'não salvo';
	@override String get saved => 'salvo';
	@override String get copied => 'Copiado';
	@override String get copy => 'Copiar';
}

// Path: cockpit.httpView
class _Translations$cockpit$httpView$pt_BR extends Translations$cockpit$httpView$en {
	_Translations$cockpit$httpView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get saveRequestAs => 'Salvar request como';
	@override String get couldNotSave => 'Não foi possível salvar';
	@override String get run => 'Executar';
	@override String get running => 'Executando…';
	@override String get noRequests => 'Nenhum request neste arquivo — escreva um, ex.: GET https://example.com';
	@override String get selectRequest => 'Selecionar request';
	@override String requestCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 request',
		other: '${n} requests',
	);
	@override String get runHint => 'Execute o request (⌘↵) para ver a resposta aqui.';
	@override String get emptyBody => 'Corpo da resposta vazio.';
	@override String get body => 'JSON';
	@override String get headers => 'Headers';
	@override String get raw => 'Text';
	@override String get truncatedSuffix => ' · truncado (resposta grande demais)';
	@override late final _Translations$cockpit$httpView$error$pt_BR error = _Translations$cockpit$httpView$error$pt_BR._(_root);
}

// Path: cockpit.dbPanel
class _Translations$cockpit$dbPanel$pt_BR extends Translations$cockpit$dbPanel$en {
	_Translations$cockpit$dbPanel$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionDatabase => 'BANCO DE DADOS';
	@override String get edit => 'Editar…';
	@override String get copyName => 'Copiar nome';
	@override String get newQuery => 'Nova query';
	@override String get browseKeys => 'Ver chaves';
	@override String get deleteConnectionTitle => 'Excluir conexão';
	@override String deleteConnectionMessage({required Object name}) => 'Remover "${name}" deste workspace? Qualquer senha salva será descartada. Arquivos .dbq que fazem referência a ela não são afetados.';
	@override String footer({required Object n}) => '.cockpit/databases.json · ${n} conexões';
	@override String get footerOne => '.cockpit/databases.json · 1 conexão';
	@override String get noConnections => 'Nenhuma conexão ainda.';
	@override String get passwordRequired => 'Senha não encontrada no host. Abra esta conexão e digite-a de novo — ela fica salva na máquina que executa o banco, não nesta.';
}

// Path: cockpit.dbMongoView
class _Translations$cockpit$dbMongoView$pt_BR extends Translations$cockpit$dbMongoView$en {
	_Translations$cockpit$dbMongoView$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get deleteDocumentTitle => 'Excluir documento';
	@override String deleteDocumentMessage({required Object id, required Object collection}) => 'Excluir o documento com _id ${id} de "${collection}"?';
	@override String get filterHint => 'Filtro — JSON, ex.: {"status": "active"}';
	@override String docCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 doc',
		other: '${n} docs',
	);
	@override String get refresh => 'Atualizar';
	@override String get insertDocument => 'Inserir documento';
	@override String get noDocuments => 'Nenhum documento nesta coleção.';
	@override String get noDocumentsMatch => 'Nenhum documento corresponde a este filtro.';
	@override String get loadMore => 'Carregar mais';
	@override String get edit => 'Editar';
	@override String get insert => 'Inserir';
}

// Path: cockpit.dbConnectionDialog
class _Translations$cockpit$dbConnectionDialog$pt_BR extends Translations$cockpit$dbConnectionDialog$en {
	_Translations$cockpit$dbConnectionDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get chooseFileTitle => 'Escolher banco SQLite';
	@override String get file => 'Arquivo';
	@override String get chooseFilePlaceholder => 'Escolha um arquivo SQLite…';
	@override String get name => 'Nome';
	@override String get password => 'Senha';
	@override String get savePassword => 'Salvar senha';
	@override String get allowWrites => 'Permitir escrita (agentes)';
	@override String get allowWritesHint => 'desligado = agentes só leem via CLI';
	@override String get visibleToAgents => 'Visível para agentes';
	@override String get visibleToAgentsHint => 'desligado = oculto da CLI, só na GUI';
	@override String get testing => 'Testando conexão…';
	@override String get connectionOk => 'Conexão OK';
	@override String get connectionFailed => 'Falha na conexão';
	@override String get editTitle => 'Editar conexão';
	@override String get newTitle => 'Nova conexão';
	@override String get connectionString => 'Connection string';
	@override String get invalidUrl => 'URL de conexão inválida.';
	@override String get sshTunnel => 'Túnel SSH';
	@override String get sshHost => 'Host SSH';
	@override String get sshPort => 'Porta SSH';
	@override String get sshUser => 'Usuário SSH';
	@override String get privateKey => 'Chave privada';
	@override String get choosePrivateKeyPlaceholder => 'Escolha uma chave privada…';
	@override String get choosePrivateKeyDialogTitle => 'Escolher chave privada SSH';
	@override String get keyPassphrase => 'Senha da chave';
	@override String get savePassphrase => 'Salvar senha da chave';
	@override String get passwordOnHost => 'A senha fica salva no host, não nesta máquina.';
}

// Path: cockpit.sshPrompts
class _Translations$cockpit$sshPrompts$pt_BR extends Translations$cockpit$sshPrompts$en {
	_Translations$cockpit$sshPrompts$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unknownSshHostTitle => 'Host SSH desconhecido';
	@override String neverConnected({required Object endpoint}) => 'O Cockpit nunca se conectou a ${endpoint} antes.';
	@override String get trustHint => 'Confie apenas se esta fingerprint corresponder ao servidor. Você pode verificar no servidor com:';
	@override String get trust => 'Confiar';
	@override String get sshKeyPassphraseTitle => 'Senha da chave SSH';
	@override String unlockMessage({required Object keyPath, required Object connectionName}) => 'Desbloqueie ${keyPath} para conectar "${connectionName}".';
	@override String get keptInMemoryHint => 'Mantida em memória até o Cockpit fechar. Para permitir que agentes usem esta conexão, ative "Salvar senha da chave" na conexão.';
	@override String get unlock => 'Desbloquear';
}

// Path: cockpit.projectsRail
class _Translations$cockpit$projectsRail$pt_BR extends Translations$cockpit$projectsRail$en {
	_Translations$cockpit$projectsRail$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get workspaces => 'Workspaces';
	@override String get newWorkspace => 'Novo workspace';
	@override String get settings => 'Configurações';
	@override String get mergeToParent => 'Mesclar no pai';
	@override String get updateFromParent => 'Atualizar a partir do pai';
	@override String get forkWorktree => 'Criar worktree derivada';
	@override String get copyBranch => 'Copiar branch';
	@override String get remove => 'Remover';
	@override String get moveToRealm => 'Mover para realm';
	@override String get copyWorkspaceId => 'Copiar id do workspace';
	@override String get rename => 'Renomear';
	@override String get close => 'Fechar';
	@override String get newRealm => 'Novo realm…';
	@override String get manageRealms => 'Gerenciar realms…';
	@override String get noWorkspaces => 'Nenhum workspace ainda.';
	@override String get sync => 'Sincronizar';
	@override String get pull => 'Pull';
	@override String get push => 'Push';
	@override String get createWorktree => 'Criar worktree';
	@override String worktreeCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n,
		one: '1 worktree',
		other: '${n} worktrees',
	);
	@override String get expandWorktrees => 'Expandir worktrees';
	@override String get collapseWorktrees => 'Recolher worktrees';
}

// Path: cockpit.findBar
class _Translations$cockpit$findBar$pt_BR extends Translations$cockpit$findBar$en {
	_Translations$cockpit$findBar$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get find => 'Buscar';
	@override String get matchCase => 'Diferenciar maiúsculas';
	@override String get wholeWord => 'Palavra inteira';
	@override String get useRegex => 'Usar expressão regular';
	@override String get previous => 'Anterior (⇧⏎)';
	@override String get next => 'Próximo (⏎)';
	@override String get close => 'Fechar (Esc)';
	@override String get badPattern => 'Padrão inválido';
	@override String get noResults => 'Nenhum resultado';
}

// Path: cockpit.contentSearch
class _Translations$cockpit$contentSearch$pt_BR extends Translations$cockpit$contentSearch$en {
	_Translations$cockpit$contentSearch$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionSearch => 'BUSCA';
	@override String get searchInFiles => 'Buscar nos arquivos';
	@override String get matchCase => 'Diferenciar maiúsculas';
	@override String get wholeWord => 'Palavra inteira';
	@override String get useRegex => 'Usar expressão regular';
	@override String get invalidRegex => 'Expressão regular inválida.';
	@override String get typeToSearch => 'Digite para buscar em todos os arquivos.';
	@override String get searching => 'Buscando…';
	@override String get noResults => 'Nenhum resultado.';
}

// Path: cockpit.emptyPane
class _Translations$cockpit$emptyPane$pt_BR extends Translations$cockpit$emptyPane$en {
	_Translations$cockpit$emptyPane$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get newAgent => 'Novo agente';
	@override String get newAgentDescription => 'Roda um pi na pasta que você escolher';
	@override String get newTerminal => 'Novo terminal';
	@override String get newTerminalDescription => 'Abre um shell na pasta que você escolher';
}

// Path: cockpit.topbar
class _Translations$cockpit$topbar$pt_BR extends Translations$cockpit$topbar$en {
	_Translations$cockpit$topbar$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get collapseSidebar => 'Recolher barra lateral';
	@override String get toggleFiles => 'Mostrar/ocultar arquivos';
	@override String get filesUnavailable => 'Arquivos indisponíveis no Cockpit';
	@override String get hideKeyboard => 'Baixar teclado';
}

// Path: cockpit.transcript
class _Translations$cockpit$transcript$pt_BR extends Translations$cockpit$transcript$en {
	_Translations$cockpit$transcript$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get send => 'Enviar';
	@override String get typeYourAnswer => 'Digite sua resposta';
	@override String get startHint => 'Envie um prompt para o agente começar.';
	@override String workedFor({required Object duration}) => 'Trabalhou por ${duration}';
}

// Path: cockpit.tasks
class _Translations$cockpit$tasks$pt_BR extends Translations$cockpit$tasks$en {
	_Translations$cockpit$tasks$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get hotReload => 'Hot reload';
	@override String get hotRestart => 'Hot restart';
	@override String get toggleDebugPaint => 'Alternar debug paint';
	@override String get togglePlatform => 'Alternar plataforma';
	@override String get quit => 'Sair';
}

// Path: cockpit.notifications
class _Translations$cockpit$notifications$pt_BR extends Translations$cockpit$notifications$en {
	_Translations$cockpit$notifications$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get agentFinished => 'Agente terminou';
	@override String get open => 'Abrir';
	@override String get agentNeedsAction => 'Agente precisa de você';
	@override String get agentCrashed => 'Agente parou inesperadamente';
}

// Path: cockpit.terminal
class _Translations$cockpit$terminal$pt_BR extends Translations$cockpit$terminal$en {
	_Translations$cockpit$terminal$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String cwdFallbackWarning({required Object requested, required Object path}) => 'Aviso: a pasta "${requested}" não existe. Este terminal abriu em "${path}".';
}

// Path: cockpit.remoteHost
class _Translations$cockpit$remoteHost$pt_BR extends Translations$cockpit$remoteHost$en {
	_Translations$cockpit$remoteHost$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get addHost => 'Adicionar host remoto';
	@override String get hostName => 'Nome';
	@override String get sshTarget => 'Destino SSH (usuário@host)';
	@override String connecting({required Object host}) => 'Conectando a ${host}…';
	@override String get openingTunnel => 'Túnel SSH';
	@override String get installingServer => 'Instalando servidor';
	@override String handshake({required Object version}) => 'Servidor ${version}';
	@override String get loadingWorkspace => 'Carregando workspace…';
	@override String reconnecting({required Object host}) => 'Reconectando a ${host}…';
	@override String offline({required Object host}) => '${host} offline';
	@override String get remove => 'Remover';
	@override String get reconnect => 'Reconectar';
	@override String get installServer => 'Instalar servidor';
	@override String errSshUnreachable({required Object host}) => 'Não foi possível alcançar ${host} via SSH. Está ligado e com o Login Remoto ativado?';
	@override String errInstallFailed({required Object host}) => 'Não foi possível instalar o servidor em ${host}.';
	@override String get errVersionMismatch => 'Versão do servidor incompatível; atualize-o.';
	@override String errDetail({required Object detail}) => 'Detalhes: ${detail}';
	@override String pickFolderTitle({required Object host}) => 'Abrir pasta em ${host}';
	@override String get openHere => 'Abrir aqui';
	@override String get emptyFolder => 'Sem subpastas';
	@override String get newLocal => 'Local';
	@override String get newRemote => 'Remoto';
	@override String get chooseHost => 'Escolher um host';
	@override String get newHostEntry => 'Novo host…';
	@override String get editHost => 'Editar host';
	@override String get userLabel => 'Usuário';
	@override String get hostLabel => 'Host / IP';
	@override String get portLabel => 'Porta';
	@override String get authLabel => 'Autenticação';
	@override String get authKey => 'Chave SSH';
	@override String get authPassword => 'Senha';
	@override String get passwordLabel => 'Senha';
	@override String get passwordKeep => 'Deixe em branco para manter a atual';
	@override String get errUser => 'Usuário obrigatório';
	@override String get errHost => 'Host obrigatório';
	@override String get errPassword => 'Senha obrigatória';
	@override String get identityChoose => 'Escolher…';
	@override String get identityEmpty => 'Nenhuma chave selecionada';
	@override String get identityDialogTitle => 'Selecione a chave privada SSH';
	@override String get errIdentity => 'Escolha a chave privada para autenticar.';
	@override String errHostKeyUnknown({required Object host}) => 'O Cockpit ainda não confia em ${host}. Conecte de novo e confirme o fingerprint.';
	@override String errHostKeyChanged({required Object host}) => '${host} está apresentando uma chave SSH diferente da guardada. Se você não reinstalou essa máquina, pare e verifique — se reinstalou, remova a entrada antiga do ~/.ssh/known_hosts.';
	@override String errHostBundleMissing({required Object host}) => '${host} é Windows mas não tem o Cockpit instalado. O servidor remoto é instalado a partir do bundle do Cockpit que já está naquela máquina — instale o Cockpit lá e tente de novo.';
	@override String errHostUnknownOs({required Object host}) => 'Não foi possível identificar o sistema de ${host}. A conta pode ter shell restrito, ou nenhum shell.';
	@override String get errIdentityPublic => 'Só a chave pública está aqui. Isso só funciona se a privada estiver no seu agente SSH; senão, escolha a privada (mesmo nome, sem .pub).';
	@override String get errIdentityNotKey => 'Esse arquivo não parece uma chave privada.';
	@override String get errIdentityMissingFile => 'Esse arquivo não existe mais.';
	@override String get errIdentityUnreadable => 'Não foi possível ler esse arquivo.';
}

// Path: cockpit.browserPane
class _Translations$cockpit$browserPane$pt_BR extends Translations$cockpit$browserPane$en {
	_Translations$cockpit$browserPane$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get back => 'Voltar';
	@override String get forward => 'Avançar';
	@override String get reload => 'Recarregar';
	@override String get urlHint => 'Digite a URL ou endereço';
	@override String get go => 'Ir';
}

// Path: settings.language
class _Translations$settings$language$pt_BR extends Translations$settings$language$en {
	_Translations$settings$language$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Idioma';
	@override String get system => 'Sistema';
	@override String get english => 'Inglês';
	@override String get portugueseBr => 'Português (BR)';
	@override String get spanish => 'Espanhol';
}

// Path: settings.revokeDialog
class _Translations$settings$revokeDialog$pt_BR extends Translations$settings$revokeDialog$en {
	_Translations$settings$revokeDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get deviceRemoved => 'Dispositivo removido.';
	@override String get failedToRevoke => 'Falha ao revogar o dispositivo.';
	@override String get revoking => 'Revogando…';
	@override String revokingDevice({required Object name}) => 'Revogando ${name}…';
	@override String get connectingMessage => 'Conectando ao relay e removendo o acesso.';
	@override String get ok => 'Ok';
}

// Path: settings.pairingDialog
class _Translations$settings$pairingDialog$pt_BR extends Translations$settings$pairingDialog$en {
	_Translations$settings$pairingDialog$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Parear dispositivo';
	@override String get connectingToRelay => 'Conectando ao relay…';
	@override String get step1 => 'Abra o app Remote Pi no seu celular.';
	@override String get step2 => 'Toque em adicionar / parear dispositivo.';
	@override String get step3 => 'Aponte a câmera para o QR abaixo.';
	@override String get qrGenerationFailed => 'Não foi possível gerar o QR.';
	@override String get autoRefreshHint => 'O código se atualiza sozinho. Mantenha esta janela aberta.';
	@override String get pairingFailed => 'Falha no pareamento.';
	@override String get tryAgain => 'Tentar novamente';
	@override String get copied => 'Copiado!';
	@override String get copyData => 'Copiar dados';
}

// Path: settings.page
class _Translations$settings$page$pt_BR extends Translations$settings$page$en {
	_Translations$settings$page$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$page$header$pt_BR header = _Translations$settings$page$header$pt_BR._(_root);
	@override late final _Translations$settings$page$nav$pt_BR nav = _Translations$settings$page$nav$pt_BR._(_root);
	@override late final _Translations$settings$page$general$pt_BR general = _Translations$settings$page$general$pt_BR._(_root);
	@override late final _Translations$settings$page$diagnostics$pt_BR diagnostics = _Translations$settings$page$diagnostics$pt_BR._(_root);
	@override late final _Translations$settings$page$storage$pt_BR storage = _Translations$settings$page$storage$pt_BR._(_root);
	@override late final _Translations$settings$page$terminal$pt_BR terminal = _Translations$settings$page$terminal$pt_BR._(_root);
	@override late final _Translations$settings$page$appearance$pt_BR appearance = _Translations$settings$page$appearance$pt_BR._(_root);
	@override late final _Translations$settings$page$notifications$pt_BR notifications = _Translations$settings$page$notifications$pt_BR._(_root);
	@override late final _Translations$settings$page$shortcuts$pt_BR shortcuts = _Translations$settings$page$shortcuts$pt_BR._(_root);
	@override late final _Translations$settings$page$languages$pt_BR languages = _Translations$settings$page$languages$pt_BR._(_root);
	@override late final _Translations$settings$page$connectivity$pt_BR connectivity = _Translations$settings$page$connectivity$pt_BR._(_root);
	@override late final _Translations$settings$page$schedules$pt_BR schedules = _Translations$settings$page$schedules$pt_BR._(_root);
	@override late final _Translations$settings$page$daemons$pt_BR daemons = _Translations$settings$page$daemons$pt_BR._(_root);
	@override late final _Translations$settings$page$automations$pt_BR automations = _Translations$settings$page$automations$pt_BR._(_root);
}

// Path: settings.remoteHosts
class _Translations$settings$remoteHosts$pt_BR extends Translations$settings$remoteHosts$en {
	_Translations$settings$remoteHosts$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Hosts remotos';
	@override String get description => 'Máquinas que você acessa por SSH. Adicionar um host aqui é o mesmo que adicionar pelo menu "+" do workspace.';
	@override String get empty => 'Nenhum host remoto ainda.';
	@override String get add => 'Adicionar host';
	@override String get edit => 'Editar';
	@override String get reconnect => 'Reconectar';
	@override String get remove => 'Remover';
	@override String get removeTitle => 'Remover host';
	@override String removeMessage({required Object name}) => 'Remover "${name}" e todos os workspaces dele? Nada é apagado no host.';
	@override String workspacesCount({required Object count}) => '${count} workspace(s)';
	@override String get deviceKeyTitle => 'Chave deste dispositivo';
	@override String get deviceKeyDesc => 'Adicione esta chave pública ao ~/.ssh/authorized_keys do host para este dispositivo poder conectar.';
	@override String get deviceKeyCopy => 'Copiar chave pública';
	@override String get deviceKeyCopied => 'Chave pública copiada';
	@override String get statusConnected => 'Conectado';
	@override String get statusConnecting => 'Conectando…';
	@override String get statusReconnecting => 'Reconectando…';
	@override String get statusOffline => 'Offline';
	@override String get statusIdle => 'Não conectado';
	@override String get helpTitle => 'Como funciona';
	@override String get helpBody => 'O Cockpit conecta na sua máquina por SSH e fala com um servidor pequeno que roda os terminais, arquivos e git lá. O host precisa ter o Cockpit (desktop) ou o cockpit-server instalado e rodando, e a chave pública deste dispositivo adicionada no ~/.ssh/authorized_keys dele.';
}

// Path: automation.error
class _Translations$automation$error$pt_BR extends Translations$automation$error$en {
	_Translations$automation$error$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String unavailable({required Object harness}) => '${harness} não está instalado ou não está no PATH.';
	@override String modelUnavailable({required Object model, required Object harness}) => 'O modelo "${model}" não está disponível para ${harness}. Escolha outro modelo em Configurações.';
	@override String authentication({required Object harness, required Object detail}) => '${harness}: ${detail}';
	@override String timeout({required Object harness, required Object seconds}) => '${harness} não respondeu em ${seconds} segundos.';
	@override String get cancelled => 'A geração da mensagem de commit foi cancelada.';
	@override String process({required Object harness, required Object detail}) => '${harness}: ${detail}';
	@override String processNoDetail({required Object harness}) => '${harness} não conseguiu gerar uma mensagem de commit.';
	@override String get invalidResponse => 'A automação devolveu uma mensagem de commit vazia.';
	@override String get busy => 'Já há uma mensagem de commit sendo gerada.';
	@override String get unknown => 'A automação não conseguiu gerar uma mensagem de commit.';
	@override String get noWorkspace => 'Nenhum workspace selecionado.';
	@override String get fileOutsideWorkspace => 'O arquivo está fora das raízes do workspace.';
	@override String fileUnreadable({required Object detail}) => 'Não foi possível ler o arquivo: ${detail}';
	@override String get binaryFile => 'Não é possível gerar mensagem de commit para um arquivo binário.';
	@override String get noFileChanges => 'Não há mudanças a descrever neste arquivo.';
	@override String get noStagedChanges => 'Não há mudanças no stage a descrever.';
	@override String get multipleRepositories => 'As mudanças no stage pertencem a repositórios diferentes. Gere uma de cada vez.';
	@override String get diffUnavailable => 'Não foi possível ler o diff.';
	@override String get notConfigured => 'Configure um harness de mensagem de commit em Configurações.';
}

// Path: fileOperation.error
class _Translations$fileOperation$error$pt_BR extends Translations$fileOperation$error$en {
	_Translations$fileOperation$error$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String alreadyExists({required Object name}) => 'Já existe: “${name}”.';
	@override String notFound({required Object name}) => 'Não encontrado: “${name}”.';
	@override String get invalidPath => 'Caminho inválido.';
	@override String get emptyName => 'O nome não pode ficar vazio.';
	@override String get noWorkspace => 'Nenhum workspace selecionado.';
	@override String get cannotMoveIntoItself => 'Não é possível mover uma pasta para dentro dela mesma.';
	@override String get clipboardEmpty => 'A área de transferência está vazia.';
	@override String get notScratchTab => 'Esta aba não é um arquivo temporário.';
	@override String get writeFailed => 'Não foi possível gravar o arquivo.';
	@override String get formatterEmptyCommand => 'Comando de formatação vazio.';
	@override String get formatterMissingPlaceholder => 'O comando de formatação precisa incluir o placeholder %FILE%.';
	@override String get formatterTimeout => 'O formatador excedeu o tempo limite.';
	@override String formatterExitCode({required Object code}) => 'O formatador saiu com código ${code}.';
	@override String get formatterFailed => 'Não foi possível executar o formatador.';
	@override String osFailure({required Object detail}) => '${detail}';
	@override String get nameHasSlash => 'O nome não pode conter “/”.';
	@override String get invalidName => 'Nome inválido.';
}

// Path: theme.error
class _Translations$theme$error$pt_BR extends Translations$theme$error$en {
	_Translations$theme$error$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get io => 'Não foi possível ler ou gravar o arquivo do tema.';
	@override String ioDetail({required Object detail}) => 'Não foi possível ler ou gravar o arquivo do tema: ${detail}';
	@override String malformedJson({required Object detail}) => 'Este arquivo não é um JSON válido: ${detail}';
	@override String get invalidTheme => 'Este arquivo não é um tema válido.';
	@override String get reservedId => 'Este tema usa o id de um tema nativo. Mude o "id" no arquivo e importe de novo.';
	@override String notAnObject({required Object field}) => 'Esperava um objeto em "${field}".';
	@override String missingField({required Object field}) => 'Falta o campo obrigatório "${field}".';
	@override String badColor({required Object value, required Object field}) => '"${value}" em "${field}" não é uma cor. Use #RGB, #RRGGBB ou #RRGGBBAA.';
	@override String unknownBase({required Object value}) => 'Tema base "${value}" desconhecido em "extends".';
	@override String get noVariants => 'O tema não declara nenhum variant. Adicione "dark", "light" ou os dois em "variants".';
}

// Path: cockpit.httpView.error
class _Translations$cockpit$httpView$error$pt_BR extends Translations$cockpit$httpView$error$en {
	_Translations$cockpit$httpView$error$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Falha no request';
	@override String get noRequest => 'Nenhum request encontrado na posição do cursor.';
	@override String invalidUrl({required Object url}) => 'URL inválida: ${url}';
	@override String unresolvedVariable({required Object name}) => 'A variável {{${name}}} não tem valor. Declare com @${name} = … neste arquivo.';
	@override String bodyFileMissing({required Object path}) => 'Arquivo de corpo não encontrado: ${path}';
	@override String bodyFileUnreadable({required Object path, required Object detail}) => 'Não foi possível ler o arquivo de corpo ${path}: ${detail}';
	@override String connectionFailed({required Object detail}) => 'Não foi possível alcançar o servidor: ${detail}';
	@override String get connectionFailedNoDetail => 'Não foi possível alcançar o servidor.';
	@override String timeout({required Object seconds}) => 'O request estourou o tempo limite de ${seconds}s.';
	@override String responseTooLarge({required Object bytes}) => 'A resposta passou do limite de ${bytes} bytes.';
}

// Path: settings.page.header
class _Translations$settings$page$header$pt_BR extends Translations$settings$page$header$en {
	_Translations$settings$page$header$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get back => 'Voltar';
	@override String get title => 'Configurações';
}

// Path: settings.page.nav
class _Translations$settings$page$nav$pt_BR extends Translations$settings$page$nav$en {
	_Translations$settings$page$nav$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get general => 'Geral';
	@override String get appearance => 'Aparência';
	@override String get terminal => 'Terminal';
	@override String get language => 'Linguagem';
	@override String get shortcuts => 'Atalhos';
	@override String get notifications => 'Notificações';
	@override String get connectivity => 'Conectividade';
	@override String get daemonAgents => 'Agentes Daemon';
	@override String get schedules => 'Agendamentos';
	@override String get automations => 'Automações';
	@override String get remoteHosts => 'Hosts remotos';
}

// Path: settings.page.general
class _Translations$settings$page$general$pt_BR extends Translations$settings$page$general$en {
	_Translations$settings$page$general$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionAgent => 'Agente';
	@override String get sectionEditor => 'Editor';
	@override String get neovimTitle => 'Abrir arquivos no Neovim';
	@override String get neovimChecking => 'Procurando o Neovim…';
	@override String get neovimNotFound => 'O Neovim não foi encontrado na PATH do seu shell.';
	@override String get neovimRefresh => 'Verificar novamente';
	@override String get enableAgentsTitle => 'Ativar agentes';
	@override String get enableAgentsDesc => 'Mostra a opção de abrir abas de agente (pi). Quando desligado, o Cockpit funciona apenas como workspace de terminal.';
	@override String get showCockpitTitle => 'Mostrar terminal do Cockpit';
	@override String get showCockpitDesc => 'Mantém um workspace sem pasta, só de terminal, fixado no topo da barra lateral. Desligar fecha seus terminais.';
	@override String get launchAtStartupTitle => 'Iniciar ao ligar';
	@override String get launchAtStartupDesc => 'Inicia o Cockpit automaticamente quando você faz login no computador.';
	@override String get sectionUpdates => 'Atualizações';
	@override String get checkUpdatesTitle => 'Verificar atualizações';
	@override String get checkUpdatesDesc => 'Com que frequência o Cockpit deve procurar novas versões.';
	@override String get agentsInUseError => 'Não é possível desligar os agentes com uma aba de agente aberta. Feche todas as abas de agente primeiro e depois desative.';
	@override late final _Translations$settings$page$general$updateFrequency$pt_BR updateFrequency = _Translations$settings$page$general$updateFrequency$pt_BR._(_root);
}

// Path: settings.page.diagnostics
class _Translations$settings$page$diagnostics$pt_BR extends Translations$settings$page$diagnostics$en {
	_Translations$settings$page$diagnostics$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Diagnóstico';
	@override String get logFileTitle => 'Arquivo de log';
	@override String logFileDesc({required Object days, required Object path}) => 'Erros e eventos de inicialização são registrados aqui, mantidos por ${days} dias.\n${path}';
	@override String get unavailable => 'indisponível';
	@override String get reveal => 'Revelar';
	@override String get reportTitle => 'Reportar um problema';
	@override String get reportDesc => 'Abre uma issue pré-preenchida com sua versão, SO e log recente. Nada é enviado automaticamente — você revisa antes.';
	@override String get reportButton => 'Reportar…';
	@override String get reportDialogTitle => 'Relatório de problema';
	@override String get reportDialogError => 'Reportado manualmente pelas Configurações.';
	@override String get reportDialogDescription => 'Descreva o que deu errado na issue. O log recente está incluído abaixo e em "Copiar detalhes".';
}

// Path: settings.page.storage
class _Translations$settings$page$storage$pt_BR extends Translations$settings$page$storage$en {
	_Translations$settings$page$storage$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Armazenamento';
	@override String get locationTitle => 'Local de armazenamento';
	@override String locationDesc({required Object root}) => 'O Cockpit guarda seus projetos, layouts e configurações aqui. Aponte para uma pasta sincronizada para fazer backup.\n${root}';
	@override String get useDefault => 'Usar padrão';
	@override String get working => 'Trabalhando…';
	@override String get change => 'Alterar…';
	@override String get resetTitle => 'Redefinir o Cockpit';
	@override String get resetDesc => 'Exclui todos os dados locais — projetos, layouts, configurações e histórico do terminal — e volta ao local padrão.';
	@override String get resetButton => 'Redefinir…';
	@override String get resetConfirm => 'Redefinir';
	@override String get resetDialogTitle => 'Redefinir o Cockpit?';
	@override String get resetDialogContent => 'Isso exclui permanentemente todos os dados locais do Cockpit — projetos, layouts, configurações e histórico do terminal. Isso não pode ser desfeito. O Cockpit será fechado para você começar do zero.';
	@override String get restartRequiredTitle => 'Reinicialização necessária';
	@override String restartChangeFolderMessage({required Object path}) => 'O Cockpit usará esta pasta a partir da próxima abertura:\n${path}';
	@override String get restartUseDefaultMessage => 'O Cockpit usará o local padrão do sistema a partir da próxima abertura. Seus dados na pasta personalizada permanecem intactos.';
	@override String get restartResetMessage => 'Todos os dados do Cockpit foram apagados. Reinicie para começar do zero.';
	@override String get later => 'Mais tarde';
	@override String get quitCockpit => 'Sair do Cockpit';
	@override String get chooseFolderDialogTitle => 'Escolha uma pasta para os dados do Cockpit';
}

// Path: settings.page.terminal
class _Translations$settings$page$terminal$pt_BR extends Translations$settings$page$terminal$en {
	_Translations$settings$page$terminal$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionDefaultTerminal => 'Terminal padrão';
	@override String get engineTitle => 'Motor';
	@override String get engineDesc => 'Usado por novas abas de terminal e buffers de saída de tasks. Abas abertas mantêm o motor atual.';
	@override String get shellTitle => 'Shell';
	@override String get shellDesc => 'Qual shell novas abas de terminal abrem. A seta ao lado do + ainda abre qualquer outro, só para aquela aba.';
	@override String get noWslMessage => 'Nenhuma distro WSL encontrada. Instale uma (wsl.exe --install) e reinicie o Cockpit para vê-la listada aqui.';
}

// Path: settings.page.appearance
class _Translations$settings$page$appearance$pt_BR extends Translations$settings$page$appearance$en {
	_Translations$settings$page$appearance$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTheme => 'Tema';
	@override String get themeTitle => 'Tema';
	@override String get themeDesc => 'Cores do app, realce de código e paleta do terminal.';
	@override String get modeTitle => 'Modo';
	@override String get modeDesc => 'Qual variante do tema usar.';
	@override String modeOnlyDark({required Object theme}) => '"${theme}" só traz a variante escura, então isto não tem efeito.';
	@override String modeOnlyLight({required Object theme}) => '"${theme}" só traz a variante clara, então isto não tem efeito.';
	@override String get themeFileTitle => 'Arquivo de tema';
	@override String get themeFileDesc => 'Importe um tema de um arquivo JSON, ou exporte o tema ativo.';
	@override String get previewCode => 'Código';
	@override String get previewTerminal => 'Terminal';
	@override String get themeSystem => 'Sistema';
	@override String get themeLight => 'Claro';
	@override String get themeDark => 'Escuro';
	@override String get sectionFonts => 'Fontes';
	@override String get interfaceFontTitle => 'Fonte da interface';
	@override String get interfaceFontDesc => 'Usada em todo o aplicativo. Vazio = padrão do sistema.';
	@override String get interfaceSizeTitle => 'Tamanho da interface';
	@override String get codeFontTitle => 'Fonte do código';
	@override String get codeFontDesc => 'Código e diffs. Vazio = padrão do sistema.';
	@override String get codeSizeTitle => 'Tamanho do código';
	@override String get terminalFontTitle => 'Fonte do terminal';
	@override String get terminalFontDesc => 'Só o terminal. Vazio = padrão do sistema.';
	@override String get terminalSizeTitle => 'Tamanho do terminal';
	@override String get terminalSizeDesc => 'Desligado = segue o tamanho do código.';
	@override String get terminalSizeInherit => 'Seguir o código';
	@override String get terminalWeightTitle => 'Peso do terminal';
	@override String get terminalWeightDesc => 'Telas de baixa densidade engrossam os traços. O automático afina só nelas e não mexe no Retina.';
	@override String get terminalWeightAuto => 'Automático (pela tela)';
	@override String get terminalWeightLight => 'Fino';
	@override String get terminalWeightNormal => 'Normal';
	@override String get terminalWeightMedium => 'Médio';
	@override String get terminalWeightSemiBold => 'Seminegrito';
	@override String get sectionConversation => 'Conversa';
	@override String get pinUserMessageTitle => 'Fixar mensagem do usuário';
	@override String get pinUserMessageDesc => 'A pergunta fica fixa no topo enquanto a resposta rola.';
	@override String get importTheme => 'Importar…';
	@override String get exportTheme => 'Exportar…';
	@override String get deleteTheme => 'Remover';
	@override String get importThemeDialog => 'Escolha um arquivo de tema';
	@override String get exportThemeDialog => 'Salvar tema como';
	@override String themeImported({required Object name}) => 'Tema "${name}" importado.';
	@override String get themeExported => 'Tema salvo.';
	@override String get themeDeleted => 'Tema removido.';
	@override String get fontPickerTitle => 'Escolher uma fonte';
	@override String get fontPickerSearch => 'Buscar fontes';
	@override String get fontPickerEmpty => 'Nenhuma fonte correspondente nesta máquina.';
	@override String get fontPickerBundled => 'inclusa';
	@override String get fontPickerCustom => 'Não está na lista? Digite o nome exato da família.';
	@override String get fontPickerCustomHint => 'Nome da família';
	@override String get fontPickerUse => 'Usar';
	@override String get fontPickerDefault => 'Padrão';
	@override String get fontMissing => 'Não encontrada nesta máquina — usando o fallback.';
	@override String get sectionLayout => 'Layout';
	@override String get swapPanelsTitle => 'Inverter panes';
	@override String get swapPanelsDesc => 'Coloca os workspaces à direita e arquivos, busca, git e banco à esquerda.';
}

// Path: settings.page.notifications
class _Translations$settings$page$notifications$pt_BR extends Translations$settings$page$notifications$en {
	_Translations$settings$page$notifications$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Notificações';
	@override String get enableTitle => 'Ativar notificações';
	@override String get enableDesc => 'Avisar quando um agente terminar uma resposta e a janela não estiver em foco.';
	@override String get systemPermissionTitle => 'Permissão do sistema';
	@override String get grantedDesc => 'O Cockpit tem permissão para enviar notificações.';
	@override String get notGrantedDesc => 'O macOS ainda não concedeu acesso a notificações.';
	@override String get granted => 'Concedido';
	@override String get requestPermission => 'Solicitar permissão';
	@override String get soundsTitle => 'Sons';
	@override String get soundVolumeTitle => 'Volume';
	@override String get soundTurnDone => 'Turno concluído';
	@override String get soundTurnDoneDesc => 'Um agente terminou o turno.';
	@override String get soundActionRequired => 'Ação necessária';
	@override String get soundActionRequiredDesc => 'Um agente está esperando sua aprovação ou resposta.';
	@override String get soundAgentError => 'Erro do agente';
	@override String get soundAgentErrorDesc => 'O processo de um agente parou inesperadamente.';
	@override String get soundDefault => 'Padrão';
	@override String soundCustom({required Object name}) => 'Personalizado: ${name}';
	@override String get soundChooseFile => 'Escolher arquivo';
	@override String get soundReset => 'Voltar ao padrão';
	@override String get soundOnActiveTab => 'Tocar também com a aba ativa';
	@override String get soundPreview => 'Ouvir';
}

// Path: settings.page.shortcuts
class _Translations$settings$page$shortcuts$pt_BR extends Translations$settings$page$shortcuts$en {
	_Translations$settings$page$shortcuts$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get notCustomizable => 'Os atalhos de teclado ainda não são personalizáveis.';
}

// Path: settings.page.languages
class _Translations$settings$page$languages$pt_BR extends Translations$settings$page$languages$en {
	_Translations$settings$page$languages$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionFormatting => 'FORMATAÇÃO';
	@override String get formatOnSaveTitle => 'Formatar ao salvar';
	@override String get formatOnSaveDesc => 'Formata o arquivo automaticamente ao salvar (⌘S).';
	@override String get sectionLanguageServers => 'SERVIDORES DE LINGUAGEM';
	@override String get footerNote => 'Erros e formatação usam o language server de cada linguagem. O Cockpit não instala servidores — ele usa o que já está na sua máquina. ● responde · ○ não encontrado ou comando inválido (instale o servidor ou ajuste o comando).';
	@override String get serverCommandLabel => 'Comando do language server';
	@override String get formatterCommandLabel => 'Comando do formatador (opcional)';
	@override String get formatterHint => 'Formatador externo com o placeholder %FILE%. Tem prioridade sobre o formatador do LSP quando definido.';
	@override String get resetToDefault => 'Redefinir para o padrão';
	@override String get saveAndRestart => 'Salvar e reiniciar';
	@override String get statusResponds => 'Servidor responde';
	@override String get statusNotFound => 'Servidor não encontrado ou comando inválido';
}

// Path: settings.page.connectivity
class _Translations$settings$page$connectivity$pt_BR extends Translations$settings$page$connectivity$en {
	_Translations$settings$page$connectivity$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionRelay => 'Relay';
	@override String get sectionPairedDevices => 'Dispositivos pareados';
	@override String get reloadTooltip => 'Recarregar';
	@override String get failedToListDevices => 'Falha ao listar dispositivos.';
	@override String get noPairedDevices => 'Nenhum dispositivo pareado.';
	@override String get relayAddressTitle => 'Endereço do relay';
	@override String get relayAddressDesc => 'Servidor que conecta seus agentes ao celular. Aplica-se a todo agente com o relay ativado.';
	@override String get saving => 'Salvando…';
	@override String get check => 'Verificar';
	@override String get healthOnline => 'Online';
	@override String get healthNoResponse => 'Sem resposta';
	@override String get healthNotChecked => 'Não verificado';
	@override String get deviceDefaultLabel => 'Dispositivo';
	@override String get revoke => 'Revogar';
	@override String get pairNewDevice => 'Parear novo dispositivo';
	@override String get revokeDialogTitle => 'Revogar dispositivo?';
	@override String revokeDialogContent({required Object name}) => '"${name}" perderá o acesso aos seus agentes e precisará parear novamente.\n\nVocê precisa estar conectado ao relay — o app conectará automaticamente para revogar.';
}

// Path: settings.page.schedules
class _Translations$settings$page$schedules$pt_BR extends Translations$settings$page$schedules$en {
	_Translations$settings$page$schedules$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionScheduledPrompts => 'Prompts agendados';
	@override String get createSchedule => 'Criar agendamento';
	@override String get createDaemonFirst => 'Crie um Agente Daemon primeiro.';
	@override String get supervisorOffline => 'Supervisor offline. Agendamentos precisam do pi-supervisord em execução (`remote-pi install`).';
	@override String get failedToListSchedules => 'Falha ao listar agendamentos.';
	@override String get noSchedules => 'Nenhum agendamento. Crie um prompt recorrente para um daemon.';
	@override String get runNow => 'Executar agora';
	@override String get viewLog => 'Ver log';
	@override String get disabled => 'desativado';
	@override String nextRun({required Object when}) => 'próximo ${when}';
	@override String lastRun({required Object label}) => 'último: ${label}';
	@override String get removeScheduleDialogTitle => 'Remover agendamento?';
	@override String removeScheduleDialogContent({required Object schedule, required Object daemon}) => 'O job "${schedule}" de ${daemon} é excluído. Suas execuções param.';
	@override String get newScheduleTitle => 'Novo agendamento';
	@override String get daemonLabel => 'Daemon';
	@override String get whenLabel => 'Quando (expressão cron)';
	@override String get previewPlaceholder => 'A próxima execução aparece aqui';
	@override String get previewComputed => 'Próximo: calculado ao salvar';
	@override String previewNext({required Object when}) => 'Próximo: ${when}';
	@override String get exampleEveryDay9am => 'todo dia às 9h';
	@override String get exampleHourly => 'a cada hora';
	@override String get exampleEvery15Min => 'a cada 15 min';
	@override String get exampleWeekdays6pm => 'dias úteis às 18h';
	@override String get promptLabel => 'Prompt';
	@override String get timezoneLabel => 'Fuso horário (opcional)';
	@override String get skipIfBusy => 'Pular se o agente estiver ocupado';
	@override String get wakeIfStopped => 'Acordar o daemon se estiver parado';
	@override String get catchup => 'Recuperar 1 execução perdida (catchup)';
	@override String get fillRequiredError => 'Preencha a expressão e o prompt.';
	@override String get creating => 'Criando…';
	@override String get failedToCreateSchedule => 'Falha ao criar o agendamento.';
	@override String historyTitle({required Object schedule}) => 'Histórico — ${schedule}';
	@override String get failedToReadLog => 'Falha ao ler o log.';
	@override String get noRecordsYet => 'Nenhum registro ainda.';
	@override String get cronDelivered => 'entregue';
	@override String get cronWokeDelivered => 'acordou + entregue';
	@override String get cronFailed => 'falhou';
	@override String get cronSkippedBusy => 'pulado (ocupado)';
	@override String get cronSkippedStopped => 'pulado (parado)';
	@override String get cronSkippedDisabled => 'pulado (desativado)';
}

// Path: settings.page.daemons
class _Translations$settings$page$daemons$pt_BR extends Translations$settings$page$daemons$en {
	_Translations$settings$page$daemons$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionAlwaysOnAgents => 'Agentes sempre ativos';
	@override String get createDaemon => 'Criar daemon';
	@override String get startAll => 'Iniciar todos';
	@override String get stopAll => 'Parar todos';
	@override String get restartAll => 'Reiniciar todos';
	@override String get restartSupervisor => 'Reiniciar supervisor';
	@override String get restartSupervisorDialogTitle => 'Reiniciar o supervisor?';
	@override String get restartSupervisorDialogContent => 'Reinicia o processo do supervisor (recarrega o código). Todos os daemons reiniciam junto e ficam offline por alguns segundos.';
	@override String get removeDaemonDialogTitle => 'Remover daemon?';
	@override String removeDaemonDialogContent({required Object name}) => '"${name}" para de rodar e sai do registro. A pasta e sua configuração local são mantidas — você pode recriá-lo depois.';
	@override String get supervisorOfflineTitle => 'Supervisor offline';
	@override String get supervisorOfflineDesc => 'O pi-supervisord não está em execução. Instale-o com `remote-pi install` para gerenciar agentes 24/7.';
	@override String get failedToListDaemons => 'Falha ao listar daemons.';
	@override String get noRegisteredAgents => 'Nenhum agente registrado. Crie um a partir de uma pasta.';
	@override String get start => 'Iniciar';
	@override String get stop => 'Parar';
	@override String get edit => 'Editar';
	@override String get stateRunning => 'em execução';
	@override String get stateStarting => 'iniciando';
	@override String get stateStopped => 'parado';
	@override String get stateFailed => 'falhou';
	@override String get newDaemonTitle => 'Novo daemon';
	@override String get editDaemonTitle => 'Editar daemon';
	@override String get nameLabel => 'Nome';
	@override String get namePlaceholder => 'ex.: PC, Servidor, Casa';
	@override String get nameRequiredError => 'Digite um nome.';
	@override String get nameDuplicateError => 'Já existe um agente com esse nome.';
	@override String get folderLabel => 'Pasta';
	@override String get noFolderChosen => 'Nenhuma pasta escolhida';
	@override String get choose => 'Escolher';
	@override String get changeFolder => 'Alterar';
	@override String get folderCannotBeChanged => 'A pasta não pode ser alterada.';
	@override String get folderRequiredError => 'Escolha uma pasta.';
	@override String get folderDuplicateError => 'Já existe um agente nesta pasta.';
	@override String get pickFolderDialogTitle => 'Escolha a pasta do Agente Daemon';
}

// Path: settings.page.automations
class _Translations$settings$page$automations$pt_BR extends Translations$settings$page$automations$en {
	_Translations$settings$page$automations$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionCommitMessages => 'Mensagens de commit';
	@override String get harness => 'Harness';
	@override String get harnessDiscovering => 'Procurando harnesses de linha de comando instalados…';
	@override String get harnessNoneFound => 'Nenhum harness compatível foi encontrado no PATH.';
	@override String harnessConfiguredUnavailable({required Object harness}) => '${harness} está configurado, mas indisponível.';
	@override String get harnessChoose => 'Escolha a CLI usada para gerar mensagens de commit.';
	@override String get harnessRefresh => 'Atualizar harnesses instalados';
	@override String get notConfigured => 'Não configurado';
	@override String get model => 'Modelo';
	@override String get modelUnavailable => 'A lista de modelos fica indisponível até o harness ser encontrado.';
	@override String get modelCliOnly => 'Este harness usa o modelo padrão da própria CLI.';
	@override String get modelCliDefault => 'Padrão da CLI';
	@override String get modelAuto => 'Auto';
	@override String modelSearch({required Object count}) => 'Buscar entre ${count} modelos…';
	@override String get modelAutoRouted => 'Este harness escolhe o modelo automaticamente.';
	@override String get modelAccountOnly => 'Só aparecem os modelos liberados na sua conta.';
	@override String get generateFromSourceControl => 'Gerar pelo Controle de Versão';
	@override String get generateFromSourceControlDescription => 'O Cockpit envia apenas o diff selecionado e os assuntos dos commits recentes. Padrões comuns de credenciais e arquivos sensíveis são redigidos antes de o harness rodar.';
	@override String get discoveryFailed => 'Não foi possível descobrir os harnesses de automação instalados.';
	@override String staleModel({required Object model, required Object harness}) => 'O modelo "${model}" não está mais disponível para ${harness}. Usando o padrão da CLI; escolha outro modelo em Configurações se precisar.';
	@override String get recommendedSuffix => 'Recomendado';
}

// Path: settings.page.general.updateFrequency
class _Translations$settings$page$general$updateFrequency$pt_BR extends Translations$settings$page$general$updateFrequency$en {
	_Translations$settings$page$general$updateFrequency$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get daily => 'Diariamente';
	@override String get weekly => 'Semanalmente';
	@override String get monthly => 'Mensalmente';
	@override String get never => 'Nunca';
}

/// The flat map containing all translations for locale <pt-BR>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsPtBr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'core.bootstrapError.title' => 'Falha ao inicializar o Cockpit',
			'core.bootstrapError.retry' => 'Tentar novamente',
			'core.macosNotifications.title' => 'Ativar notificações no macOS',
			'core.macosNotifications.intro' => 'As notificações estão desativadas nas configurações do sistema. Siga os passos abaixo para ativá-las:',
			'core.macosNotifications.step1' => 'Abra as Configurações do Sistema no seu Mac.',
			'core.macosNotifications.step2' => 'Acesse a seção Notificações na barra lateral esquerda.',
			'core.macosNotifications.step3' => 'Encontre e selecione o aplicativo Cockpit na lista.',
			'core.macosNotifications.step4' => 'Ative a opção Permitir Notificações.',
			'core.macosNotifications.tip' => 'Dica: se o aplicativo não aparecer na lista, feche e reabra-o para acionar seu registro no sistema.',
			'core.macosNotifications.gotIt' => 'Entendi',
			'core.appErrorView.renderFailed' => 'Esta parte do aplicativo falhou ao renderizar',
			'core.appErrorView.details' => 'Detalhes',
			'core.appErrorView.renderErrorTitle' => 'Erro de renderização',
			'core.errorReportDialog.defaultDescription' => 'Algo deu errado. Os detalhes abaixo foram salvos no log — você pode reportá-los para que isso seja corrigido.',
			'core.errorReportDialog.copyDetails' => 'Copiar detalhes',
			'core.errorReportDialog.reportIssue' => 'Reportar problema',
			'core.windowControls.minimize' => 'Minimizar',
			'core.windowControls.maximize' => 'Maximizar',
			'core.windowControls.close' => 'Fechar',
			'core.crash.title' => 'Encerramento inesperado',
			'core.crash.bannerTitle' => 'O Cockpit fechou inesperadamente',
			'core.crash.report' => 'Reportar',
			'core.crash.dismiss' => 'Dispensar',
			'core.crash.crashMessage' => ({required Object version}) => 'A sessão anterior (versão ${version}) terminou sem encerrar corretamente. Quer reportar? O log vai junto e você pode revisar tudo antes de enviar.',
			'core.crash.crashError' => ({required Object startedAt, required Object pid}) => 'A sessão iniciada em ${startedAt} (pid ${pid}) terminou sem encerramento limpo.',
			'core.crash.crashDescription' => 'Nenhum erro foi capturado: o app foi encerrado pelo sistema. O log abaixo é dessa sessão e é a parte mais útil.',
			'core.menu.settings' => 'Configurações…',
			'core.menu.checkForUpdates' => 'Verificar Atualizações…',
			'core.menu.file' => 'Arquivo',
			'core.menu.newAgent' => 'Novo Agente',
			'core.menu.newTerminal' => 'Novo Terminal',
			'core.menu.openWorkspace' => 'Abrir Workspace',
			'core.menu.save' => 'Salvar',
			'core.menu.discard' => 'Descartar',
			'core.menu.format' => 'Formatar',
			'core.menu.view' => 'Exibir',
			'core.menu.toggleWorkspacePanel' => 'Alternar Painel de Workspaces',
			'core.menu.toggleFiles' => 'Alternar Arquivos',
			'core.menu.splitRight' => 'Dividir à Direita',
			'core.menu.splitDown' => 'Dividir Abaixo',
			'core.menu.focusPane' => 'Focar Painel',
			'core.menu.focusLeft' => 'Esquerda  (⌘⌥←)',
			'core.menu.focusRight' => 'Direita  (⌘⌥→)',
			'core.menu.focusUp' => 'Acima  (⌘⌥↑)',
			'core.menu.focusDown' => 'Abaixo  (⌘⌥↓)',
			'core.menu.selectTab' => 'Selecionar Aba',
			'core.menu.tabN' => ({required Object n}) => 'Aba ${n}',
			'core.menu.lastTab' => 'Última Aba',
			'core.menu.zoomIn' => 'Aumentar Zoom',
			'core.menu.zoomOut' => 'Diminuir Zoom',
			'core.menu.actualSize' => 'Tamanho Real',
			'core.menu.window' => 'Janela',
			'core.menu.quit' => 'Sair',
			'core.menu.minimize' => 'Minimizar',
			'core.menu.zoom' => 'Zoom',
			'common.cancel' => 'Cancelar',
			'common.confirm' => 'Confirmar',
			'common.create' => 'Criar',
			'common.gotIt' => 'Entendi',
			'common.save' => 'Salvar',
			'common.close' => 'Fechar',
			'common.delete' => 'Excluir',
			'common.done' => 'Concluído',
			'common.add' => 'Adicionar',
			'common.test' => 'Testar',
			'common.ok' => 'OK',
			'common.loading' => 'Carregando…',
			'common.checking' => 'Verificando…',
			'common.remove' => 'Remover',
			'common.restart' => 'Reiniciar',
			'common.settings' => 'Configurações',
			'common.send' => 'Enviar',
			'common.open' => 'Abrir',
			'common.dismiss' => 'Dispensar',
			'common.report' => 'Reportar',
			'common.copyCode' => 'Copiar código',
			'common.search' => 'Buscar',
			'common.noResults' => 'Nenhum resultado',
			'cockpit.confirmDialog.unsavedChangesTitle' => 'Alterações não salvas',
			'cockpit.confirmDialog.unsavedChangesMessage' => ({required Object fileName}) => '“${fileName}” tem alterações não salvas. Salvar antes de fechar?',
			'cockpit.confirmDialog.dontSave' => 'Não salvar',
			'cockpit.confirmDialog.saveAndClose' => 'Salvar e fechar',
			'cockpit.neovim.unavailable' => 'O Neovim não está disponível. Abrindo no Cockpit.',
			'cockpit.neovim.openFailed' => 'Não foi possível acessar o Neovim. Abrindo no Cockpit.',
			'cockpit.neovim.unsavedTitle' => 'Buffers não salvos no Neovim',
			'cockpit.neovim.unsavedMessage' => 'O Neovim tem buffers modificados. Fechar a aba e descartar essas alterações?',
			'cockpit.neovim.closeAnyway' => 'Fechar mesmo assim',
			'cockpit.historyDialog.title' => 'Histórico de sessões',
			'cockpit.historyDialog.subtitle' => 'Abrir uma substitui a transcrição atual deste agente',
			'cockpit.historyDialog.empty' => 'Nenhuma sessão salva nesta pasta.',
			'cockpit.historyDialog.untitledSession' => 'Sessão sem título',
			'cockpit.historyDialog.justNow' => 'agora',
			'cockpit.historyDialog.minutesAgo' => ({required Object n}) => '${n} min atrás',
			'cockpit.historyDialog.hoursAgo' => ({required Object n}) => '${n} h atrás',
			'cockpit.historyDialog.daysAgo' => ({required Object n}) => '${n} d atrás',
			'cockpit.worktreeCreateDialog.forkTitle' => 'Fork da worktree',
			'cockpit.worktreeCreateDialog.createTitle' => 'Criar worktree',
			'cockpit.worktreeCreateDialog.forkSubtitle' => ({required Object root}) => 'Nova worktree ramificada a partir de ${root}.',
			'cockpit.worktreeCreateDialog.createSubtitle' => ({required Object root}) => 'Nova feature em ${root} — novo branch a partir do HEAD atual.',
			'cockpit.worktreeCreateDialog.namePlaceholder' => 'feat/minha-feature',
			'cockpit.worktreeCreateDialog.errorWhitespace' => 'Sem espaços no nome.',
			'cockpit.worktreeCreateDialog.errorInvalidChar' => 'Caractere inválido para nome de branch.',
			'cockpit.worktreeCreateDialog.errorInvalidSequence' => 'Sequência inválida (ex.: "..", "//", começar/terminar com "/").',
			'cockpit.worktreeCreateDialog.errorReserved' => 'Posição reservada (não comece com "-"/"." nem termine com ".lock").',
			'cockpit.worktreeCreateDialog.errorDuplicateBranch' => 'Já existe um branch com esse nome.',
			'cockpit.worktreeCreateDialog.errorDuplicateWorktree' => 'Já existe uma worktree com esse nome.',
			'cockpit.worktreeCreateDialog.errorBranchHierarchyConflict' => ({required Object target, required Object existing}) => 'Não é possível criar o branch \'${target}\' porque ele conflita com o branch \'${existing}\' já existente.',
			'cockpit.worktreeCreateDialog.errorBranchHierarchicalConflictGeneral' => 'Já existe um branch com uma hierarquia conflitante.',
			'cockpit.worktreeCreateDialog.fork' => 'Fork',
			'cockpit.worktreeCreateDialog.postCheckoutHint' => 'Este repositório tem um hook post-checkout.',
			'cockpit.worktreeCreateDialog.running' => 'Executando…',
			'cockpit.worktreeCreateDialog.advancedSettings' => 'Configurações Avançadas',
			'cockpit.worktreeCreateDialog.copyIgnored' => 'Copiar arquivos ignorados (.gitignore)',
			'cockpit.worktreeCreateDialog.copyIgnoredDesc' => 'Copia arquivos ignorados pelo .gitignore (ex: .env, chaves locais) para a nova pasta.',
			'cockpit.worktreeCreateDialog.copyUntracked' => 'Copiar arquivos não rastreados',
			'cockpit.worktreeCreateDialog.copyUntrackedDesc' => 'Copia arquivos novos ou modificados que ainda não foram adicionados ao stage.',
			'cockpit.worktreeCreateDialog.baseBranch' => 'Branch base',
			'cockpit.worktreeCreateDialog.baseBranchDesc' => 'O branch de onde a nova worktree e branch serão ramificados.',
			'cockpit.worktreeCreateDialog.fetchRemote' => 'Sincronizar branch remota (fetch)',
			'cockpit.worktreeCreateDialog.fetchRemoteDesc' => 'Roda git fetch para garantir que a branch base esteja confirmada antes de criar a worktree.',
			'cockpit.worktreeCreateDialog.searchBranch' => 'Buscar branch...',
			'cockpit.worktreeCreateDialog.back' => 'Voltar',
			'cockpit.subfolderDialog.title' => 'Onde trabalhar?',
			'cockpit.subfolderDialog.empty' => 'Nenhuma subpasta aqui.',
			'cockpit.subfolderDialog.useRoot' => ({required Object project}) => 'Usar a raiz de ${project}',
			'cockpit.subfolderDialog.usePath' => ({required Object project, required Object rel}) => 'Usar ${project}/${rel}',
			'cockpit.subfolderDialog.useThisFolder' => 'Usar esta pasta',
			'cockpit.commitMessageDialog.commitTitle' => 'Commit',
			'cockpit.commitMessageDialog.stageAndCommitTitle' => 'Stage e Commit',
			'cockpit.commitMessageDialog.scopeNote' => ({required Object fileName}) => 'Commit apenas de "${fileName}".',
			'cockpit.commitMessageDialog.placeholder' => 'fix: resumo curto da mudança',
			'cockpit.commitMessageDialog.errorEmptySubject' => 'A primeira linha (assunto) não pode ficar vazia.',
			'cockpit.commitMessageDialog.errorTooShort' => ({required Object min}) => 'Assunto muito curto (mín. ${min} caracteres).',
			'cockpit.commitMessageDialog.errorTooLong' => ({required Object max}) => 'Assunto muito longo (máx. ${max} caracteres).',
			'cockpit.commitMessageDialog.errorTrailingPeriod' => 'O assunto não deve terminar com ponto.',
			'cockpit.commitMessageDialog.errorControlChars' => 'O assunto contém caracteres de controle.',
			'cockpit.commitMessageDialog.errorBlankSecondLine' => 'Deixe a segunda linha em branco (separador entre assunto e corpo do git).',
			'cockpit.commitMessageDialog.generate' => 'Gerar mensagem de commit',
			'cockpit.commitMessageDialog.generateWith' => ({required Object harness}) => 'Gerar com ${harness}',
			'cockpit.commitMessageDialog.generating' => 'Gerando…',
			'cockpit.commitMessageDialog.cancelGeneration' => 'Cancelar geração',
			'cockpit.agentEditDialog.title' => 'Editar agente',
			'cockpit.agentEditDialog.agentName' => 'Nome do agente',
			'cockpit.agentEditDialog.relaySection' => 'Relay (remote-pi)',
			'cockpit.agentEditDialog.autoConnect' => 'Conectar automaticamente ao iniciar',
			'cockpit.agentEditDialog.informationSection' => 'Informações',
			'cockpit.agentEditDialog.folder' => 'Pasta',
			'cockpit.agentEditDialog.model' => 'Modelo',
			'cockpit.agentEditDialog.state' => 'Estado',
			'cockpit.agentEditDialog.context' => 'Contexto',
			'cockpit.agentEditDialog.statusEmpty' => 'vazio',
			'cockpit.agentEditDialog.statusStarting' => 'iniciando',
			'cockpit.agentEditDialog.statusReady' => 'pronto',
			'cockpit.agentEditDialog.statusStreaming' => 'transmitindo',
			'cockpit.agentEditDialog.statusEnded' => 'encerrado',
			'cockpit.agentSetupChecklist.title' => 'Configurar o ambiente do agente',
			'cockpit.agentSetupChecklist.intro' => 'Rodar um agente exige o Pi instalado. Complete os passos abaixo — terminais e arquivos funcionam sem nada disso.',
			'cockpit.agentSetupChecklist.step1Title' => 'Pi Code instalado',
			'cockpit.agentSetupChecklist.step1Description' => 'O binário `pi` precisa estar acessível.',
			'cockpit.agentSetupChecklist.step2Title' => 'Extensão remote-pi no Pi',
			'cockpit.agentSetupChecklist.step2Description' => 'Registrada em ~/.pi/agent/settings.json.',
			'cockpit.agentSetupChecklist.step3Title' => 'Supervisor instalado',
			'cockpit.agentSetupChecklist.step3Description' => 'Serviço pi-supervisord (remote-pi install).',
			'cockpit.agentSetupChecklist.install' => 'Instalar',
			'cockpit.agentSetupChecklist.installExtensionTitle' => 'Instalar extensão remote-pi',
			'cockpit.agentSetupChecklist.installSupervisorTitle' => 'Instalar supervisor',
			'cockpit.agentSetupChecklist.createAgent' => 'Criar agente',
			'cockpit.agentSetupChecklist.back' => 'Voltar',
			'cockpit.agentSetupChecklist.checkAgain' => 'Verificar novamente',
			'cockpit.agentSetupChecklist.notRequired' => 'Não obrigatório nesta configuração',
			'cockpit.agentSetupChecklist.installing' => 'Instalando…',
			'cockpit.agentSetupChecklist.installedSuccessfully' => 'Instalado com sucesso.',
			'cockpit.agentComposer.cmdNewDescription' => 'Nova sessão — limpa a conversa',
			'cockpit.agentComposer.cmdCompactDescription' => 'Compacta o contexto do agente',
			'cockpit.agentComposer.attachFile' => 'Anexar arquivo',
			'cockpit.agentComposer.maxImages' => ({required Object max}) => 'Máximo de ${max} imagens.',
			'cockpit.agentComposer.placeholder' => 'Mensagem para o agente, use @files ou /commands',
			'cockpit.agentComposer.stop' => 'Parar',
			'cockpit.agentComposer.send' => 'Enviar',
			'cockpit.agentComposer.relayOnline' => 'Relay online',
			'cockpit.agentComposer.relayReconnecting' => 'Relay reconectando...',
			'cockpit.agentComposer.relayOffline' => 'Relay offline',
			'cockpit.agentComposer.contextTooltip' => ({required Object pct}) => 'Contexto: ${pct}% da janela',
			'cockpit.agentComposer.visionWarning' => 'O modelo atual não consegue ver imagens — troque para um com suporte a visão.',
			'cockpit.agentComposer.modelFallback' => 'modelo',
			'cockpit.tasksPanel.reloadTasksTooltip' => 'Recarregar tasks',
			'cockpit.tasksPanel.restartTooltip' => 'Reiniciar',
			'cockpit.tasksPanel.stopTooltip' => 'Parar',
			'cockpit.tasksPanel.runTooltip' => 'Executar',
			'cockpit.tasksPanel.sendsKeyTooltip' => ({required Object label, required Object key}) => '${label} (envia \'${key}\')',
			'cockpit.tasksPanel.startingTooltip' => 'Iniciando…',
			'cockpit.tasksPanel.stoppingTooltip' => 'Parando…',
			'cockpit.tasksPanel.switchProfileTooltip' => 'Trocar perfil',
			'cockpit.tasksPanel.moreKeysTooltip' => 'Mais teclas',
			'cockpit.tasksPanel.sectionTasks' => 'TAREFAS',
			'cockpit.tasksPanel.noTasks' => 'Nenhuma tarefa detectada neste projeto.',
			'cockpit.tasksPanel.createTasksJson' => 'Criar tasks.json',
			'cockpit.cockpitPage.chooseProjectFolderDialogTitle' => 'Escolha a pasta do projeto',
			'cockpit.cockpitPage.chooseWorkspaceFolderDialogTitle' => 'Escolha a pasta do workspace',
			'cockpit.cockpitPage.workspaceRenamedTitle' => 'Workspace renomeado',
			'cockpit.cockpitPage.workspaceRenamedMessage' => ({required Object name}) => 'O novo nome "${name}" só será enviado aos agentes após reiniciar o workspace ou o aplicativo.',
			'cockpit.cockpitPage.syncTitle' => ({required Object label}) => 'Sync — ${label}',
			'cockpit.cockpitPage.pullTitle' => ({required Object label}) => 'Pull — ${label}',
			'cockpit.cockpitPage.pushTitle' => ({required Object label}) => 'Push — ${label}',
			'cockpit.cockpitPage.updateFromParentTitle' => ({required Object name}) => 'Atualizar a partir do Pai — ${name}',
			'cockpit.cockpitPage.mergeToParentTitle' => ({required Object name}) => 'Merge para o Pai — ${name}',
			'cockpit.cockpitPage.worktreeMergedAndRemoved' => 'Worktree mesclada e removida.',
			'cockpit.cockpitPage.nothingWasChanged' => 'Nada foi alterado.',
			'cockpit.cockpitPage.newRealmTitle' => 'Novo realm',
			'cockpit.cockpitPage.closeWorkspaceTitle' => 'Fechar workspace',
			'cockpit.cockpitPage.closeWorkspaceMessage' => ({required Object name}) => 'Fechar "${name}"? Os agentes deste workspace serão encerrados. A pasta no disco é mantida.',
			'cockpit.cockpitPage.closeAction' => 'Fechar',
			'cockpit.cockpitPage.removeWorktreeTitle' => 'Remover worktree',
			'cockpit.cockpitPage.removeWorktreeMessage' => ({required Object name, required Object warn}) => 'Remover "${name}"? A pasta da worktree e o branch serão excluídos e os agentes deste fork serão encerrados.${warn}',
			'cockpit.cockpitPage.removeWorktreeWarning' => ({required Object name}) => '\n\nAviso: o branch "${name}" ainda não foi mesclado — removê-lo (git branch -D) descarta o trabalho não mesclado.',
			'cockpit.cockpitPage.failedToRemoveWorktreeTitle' => 'Falha ao remover a worktree',
			'cockpit.cockpitPage.openLayoutTitle' => 'Abrir layout',
			'cockpit.cockpitPage.restartServerTooltip' => 'Reiniciar servidor',
			'cockpit.cockpitPage.noLspAvailable' => 'Nenhum LSP disponível',
			'cockpit.cockpitPage.lspRunning' => 'em execução',
			'cockpit.cockpitPage.lspStopped' => 'parado',
			'cockpit.welcomeView.title' => 'Bem-vindo ao Cockpit',
			'cockpit.welcomeView.subtitle' => 'Abra uma pasta ou conecte a um host remoto para começar.',
			'cockpit.welcomeView.createWorkspace' => 'Criar workspace',
			'cockpit.welcomeView.openLocalFolder' => 'Abrir pasta local',
			'cockpit.welcomeView.connectHost' => 'Conectar a um host',
			'cockpit.welcomeView.configureHost' => 'Configurar host',
			'cockpit.welcomeView.addWorkspace' => 'Adicionar workspace',
			'cockpit.modelPicker.search' => ({required Object count}) => 'Buscar modelo (${count})',
			'cockpit.paneView.closePaneTitle' => 'Fechar painel?',
			'cockpit.paneView.closePaneMessage' => ({required Object count}) => 'Isso fecha todas as ${count} aba(s) deste painel e encerra os agentes/terminais nele.',
			'cockpit.paneView.close' => 'Fechar',
			'cockpit.paneView.allTabs' => 'Todas as abas',
			'cockpit.paneView.pinTab' => 'Fixar aba',
			'cockpit.paneView.rename' => 'Renomear',
			'cockpit.paneView.resetTitle' => 'Redefinir título',
			'cockpit.paneView.copyId' => 'Copiar Id',
			'cockpit.paneView.autoRelay' => 'Auto-relay',
			'cockpit.paneView.history' => 'Histórico',
			'cockpit.paneView.newTab' => 'Nova aba',
			'cockpit.paneView.newTerminal' => 'Novo terminal…',
			'cockpit.paneView.splitRight' => 'Dividir à direita',
			'cockpit.paneView.splitDown' => 'Dividir abaixo',
			'cockpit.paneView.closePane' => 'Fechar painel',
			'cockpit.paneView.dropHereToMove' => 'Solte aqui para mover a aba',
			'cockpit.paneView.dockAsTab' => 'Encaixar como aba',
			'cockpit.paneView.openBrowser' => 'Abrir navegador',
			'cockpit.paneView.openTerminal' => 'Abrir terminal',
			'cockpit.fileTreePanel.viewDiff' => 'Ver Diff',
			'cockpit.fileTreePanel.commit' => 'Commit',
			'cockpit.fileTreePanel.stageAndCommit' => 'Stage e Commit',
			'cockpit.fileTreePanel.unstage' => 'Tirar do stage',
			'cockpit.fileTreePanel.stageChanges' => 'Colocar no stage',
			'cockpit.fileTreePanel.discardChanges' => 'Descartar alterações',
			'cockpit.fileTreePanel.enterCommitMessage' => 'Digite uma mensagem de commit.',
			'cockpit.fileTreePanel.commitUnavailable' => 'Commit indisponível para este workspace.',
			'cockpit.fileTreePanel.gitErrorTitle' => 'Erro do Git',
			'cockpit.fileTreePanel.deleteNewFileTitle' => 'Excluir arquivo novo?',
			'cockpit.fileTreePanel.discardChangesTitle' => 'Descartar alterações?',
			'cockpit.fileTreePanel.deleteNewFileMessage' => ({required Object name}) => '"${name}" é um arquivo novo e não pode ser restaurado. Excluir?',
			'cockpit.fileTreePanel.discardOneMessage' => ({required Object name}) => 'Descartar todas as alterações em "${name}"? Arquivos excluídos serão restaurados.',
			'cockpit.fileTreePanel.discard' => 'Descartar',
			'cockpit.fileTreePanel.deleteAllNewFilesTitle' => 'Excluir todos os arquivos novos?',
			'cockpit.fileTreePanel.allNewFilesMessage' => ({required Object count}) => 'Todos os ${count} arquivos são novos e serão excluídos. Isso não pode ser desfeito.',
			'cockpit.fileTreePanel.discardTrackedMessage' => ({required Object count, required Object extra}) => 'Descartar alterações em ${count} arquivo(s) rastreado(s)?${extra}',
			'cockpit.fileTreePanel.discardTrackedExtra' => ({required Object count}) => ' ${count} arquivo(s) novo(s) será(ão) mantido(s).',
			'cockpit.fileTreePanel.deleteAll' => 'Excluir tudo',
			'cockpit.fileTreePanel.deleteQuestionTitle' => 'Excluir?',
			'cockpit.fileTreePanel.moveToTrash' => ({required Object name}) => 'Mover “${name}” para a Lixeira?',
			'cockpit.fileTreePanel.permanentlyDelete' => ({required Object name}) => 'Excluir “${name}” permanentemente? Isso não pode ser desfeito.',
			'cockpit.fileTreePanel.couldNotDeleteTitle' => 'Não foi possível excluir',
			'cockpit.fileTreePanel.moveQuestionTitle' => 'Mover?',
			'cockpit.fileTreePanel.moveMessage' => ({required Object name, required Object dest}) => 'Mover “${name}” para “${dest}”?',
			'cockpit.fileTreePanel.moveAction' => 'Mover',
			'cockpit.fileTreePanel.couldNotMoveTitle' => 'Não foi possível mover',
			'cockpit.fileTreePanel.couldNotPasteTitle' => 'Não foi possível colar',
			'cockpit.fileTreePanel.filesTooltip' => 'Arquivos',
			'cockpit.fileTreePanel.searchTooltip' => 'Buscar',
			'cockpit.fileTreePanel.sourceControlTooltip' => 'Controle de versão',
			'cockpit.fileTreePanel.databaseTooltip' => 'Banco de dados',
			'cockpit.fileTreePanel.sectionFiles' => 'ARQUIVOS',
			'cockpit.fileTreePanel.newFile' => 'Novo arquivo',
			'cockpit.fileTreePanel.newFolder' => 'Nova pasta',
			'cockpit.fileTreePanel.refreshTooltip' => 'Atualizar',
			'cockpit.fileTreePanel.sectionSourceControl' => 'CONTROLE DE VERSÃO',
			'cockpit.fileTreePanel.viewAsList' => 'Ver como lista',
			'cockpit.fileTreePanel.viewAsTree' => 'Ver como árvore',
			'cockpit.fileTreePanel.noFolderMessage' => 'Nenhuma pasta — abra um workspace.',
			'cockpit.fileTreePanel.amend' => 'Amend',
			'cockpit.fileTreePanel.commitMessagePlaceholder' => 'Mensagem do commit',
			'cockpit.fileTreePanel.amendCommit' => 'Amend do commit',
			'cockpit.fileTreePanel.lastCommit' => 'último commit',
			'cockpit.fileTreePanel.openInFinder' => 'Abrir no Finder',
			'cockpit.fileTreePanel.openInExplorer' => 'Abrir no Explorer',
			'cockpit.fileTreePanel.openInFileManager' => 'Abrir no gerenciador de arquivos',
			'cockpit.fileTreePanel.open' => 'Abrir',
			'cockpit.fileTreePanel.openWith' => 'Abrir com',
			'cockpit.fileTreePanel.openLayout' => 'Abrir layout',
			'cockpit.fileTreePanel.showGitDiff' => 'Mostrar diff do git',
			'cockpit.fileTreePanel.createAgent' => 'Criar agente',
			'cockpit.fileTreePanel.createTerminal' => 'Criar terminal',
			'cockpit.fileTreePanel.rename' => 'Renomear',
			'cockpit.fileTreePanel.copy' => 'Copiar',
			'cockpit.fileTreePanel.cut' => 'Recortar',
			'cockpit.fileTreePanel.paste' => 'Colar',
			'cockpit.fileTreePanel.copyRelativePath' => 'Copiar caminho relativo',
			'cockpit.fileTreePanel.copyAbsolutePath' => 'Copiar caminho absoluto',
			'cockpit.fileTreePanel.renameFailed' => 'Falha ao renomear.',
			'cockpit.fileTreePanel.noChanges' => 'Nenhuma alteração.',
			'cockpit.fileTreePanel.stagedChangesHeader' => ({required Object count}) => 'ALTERAÇÕES EM STAGE (${count})',
			'cockpit.fileTreePanel.changesHeader' => ({required Object count}) => 'ALTERAÇÕES (${count})',
			'cockpit.fileTreePanel.discardAllChanges' => 'Descartar todas as alterações',
			'cockpit.fileTreePanel.unstageAllChanges' => 'Tirar tudo do stage',
			'cockpit.fileTreePanel.stageAllChanges' => 'Colocar tudo no stage',
			'cockpit.fileTreePanel.discardFolderChanges' => 'Descartar alterações da pasta',
			'cockpit.fileTreePanel.unstageFolderChanges' => 'Tirar pasta do stage',
			'cockpit.fileTreePanel.stageFolderChanges' => 'Colocar pasta no stage',
			'cockpit.fileTreePanel.generateCommitMessage' => 'Gerar mensagem de commit',
			'cockpit.fileTreePanel.generateWith' => ({required Object harness}) => 'Gerar com ${harness}',
			'cockpit.fileTreePanel.generateUnavailableWhileAmending' => 'Indisponível durante o amend de um commit',
			'cockpit.fileTreePanel.cancelGeneration' => 'Cancelar geração',
			'cockpit.fileTreePanel.changes' => 'Alteracoes',
			'cockpit.fileTreePanel.history' => 'Historico',
			'cockpit.fileTreePanel.historyRepository' => 'Repositorio',
			'cockpit.fileTreePanel.historyNoRepository' => 'Nenhum repositorio Git disponivel.',
			'cockpit.fileTreePanel.historyEmpty' => 'Nenhum commit encontrado.',
			'cockpit.fileTreePanel.historyLoadFailed' => 'Nao foi possivel carregar o historico Git.',
			'cockpit.fileTreePanel.historyUntitledCommit' => 'Commit sem titulo',
			'cockpit.fileTreePanel.historyNow' => 'agora',
			'cockpit.fileTreePanel.historyMinutesAgo' => ({required Object count}) => 'ha ${count} min',
			'cockpit.fileTreePanel.historyHoursAgo' => ({required Object count}) => 'ha ${count} h',
			'cockpit.fileTreePanel.historyYesterday' => 'ontem',
			'cockpit.fileTreePanel.historyDayAgo' => 'ha 1 dia',
			'cockpit.fileTreePanel.historyDaysAgo' => ({required Object count}) => 'ha ${count} dias',
			'cockpit.fileTreePanel.historyFiles' => 'Arquivos alterados',
			'cockpit.fileTreePanel.historyFilesEmpty' => 'Nenhum arquivo alterado.',
			'cockpit.fileTreePanel.historyFilesLoadFailed' => 'Nao foi possivel carregar os arquivos alterados.',
			'cockpit.fileTreePanel.diffEmptyTree' => 'Arvore vazia',
			'cockpit.fileTreePanel.diffOriginal' => ({required Object ref}) => 'Original ${ref}',
			'cockpit.fileTreePanel.diffModified' => ({required Object ref}) => 'Modificado ${ref}',
			'cockpit.fileTreePanel.diffWorkingTree' => 'Diretorio de trabalho',
			'cockpit.fileTreePanel.diffBinaryFile' => 'Arquivo binario - sem diff de texto.',
			'cockpit.fileTreePanel.diffNoChanges' => 'Sem alteracoes.',
			'cockpit.fileViewer.cantOpen' => 'Não é possível abrir este arquivo.',
			'cockpit.fileViewer.couldNotLoadImage' => 'Não foi possível carregar a imagem.',
			'cockpit.fileViewer.preview' => 'Pré-visualização',
			'cockpit.fileViewer.source' => 'Código-fonte',
			'cockpit.workspaceSettingsDialog.choosePhotoTitle' => 'Escolher foto do workspace',
			'cockpit.workspaceSettingsDialog.title' => 'Configurações do workspace',
			'cockpit.workspaceSettingsDialog.namePlaceholder' => 'Nome do workspace',
			'cockpit.workspaceSettingsDialog.addPhoto' => 'Adicionar foto',
			'cockpit.workspaceSettingsDialog.changePhoto' => 'Alterar foto',
			'cockpit.workspaceSettingsDialog.remove' => 'Remover',
			'cockpit.workspaceSettingsDialog.color' => 'Cor',
			'cockpit.workspaceSettingsDialog.host' => 'Host',
			'cockpit.workspaceSettingsDialog.folder' => 'Pasta',
			'cockpit.realmDialogs.namePlaceholder' => 'Nome do realm',
			'cockpit.realmDialogs.duplicateName' => 'Já existe um realm com esse nome.',
			'cockpit.realmDialogs.newRealmTitle' => 'Novo realm',
			'cockpit.realmDialogs.renameRealmTitle' => 'Renomear realm',
			'cockpit.realmDialogs.rename' => 'Renomear',
			'cockpit.realmDialogs.deleteRealmTitle' => 'Excluir realm',
			'cockpit.realmDialogs.deleteMessage' => ({required Object name, required Object suffix}) => 'Excluir "${name}"? Nenhum workspace é excluído — só a lista de pastas muda.${suffix}',
			'cockpit.realmDialogs.deleteSuffixOne' => ' O workspace dele irá para o Padrão.',
			'cockpit.realmDialogs.deleteSuffixMany' => ({required Object count}) => ' Os ${count} workspaces dele irão para o Padrão.',
			'cockpit.realmDialogs.manageRealmsTitle' => 'Gerenciar realms',
			'cockpit.realmDialogs.workspaceCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 workspace', other: '${n} workspaces', ), 
			'cockpit.dbRedisTable.deleteKeyTitle' => 'Excluir chave',
			'cockpit.dbRedisTable.deleteKeyMessage' => ({required Object key}) => 'Excluir "${key}" deste banco Redis?',
			'cockpit.dbRedisTable.refresh' => 'Atualizar',
			'cockpit.dbRedisTable.newKey' => 'Nova chave',
			'cockpit.dbRedisTable.columnKey' => 'CHAVE',
			'cockpit.dbRedisTable.columnValue' => 'VALOR',
			'cockpit.dbRedisTable.columnType' => 'TIPO',
			'cockpit.dbRedisTable.columnTtl' => 'TTL',
			'cockpit.dbRedisTable.keyCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 chave', other: '${n} chaves', ), 
			'cockpit.dbRedisTable.noKeys' => 'Nenhuma chave neste banco de dados.',
			'cockpit.dbRedisTable.noKeysMatch' => ({required Object pattern}) => 'Nenhuma chave corresponde a "${pattern}".',
			'cockpit.dbRedisTable.loadMore' => 'Carregar mais',
			'cockpit.dbRedisTable.loadingFullValue' => 'Carregando valor completo…',
			'cockpit.dbRedisTable.ttlMustBeNumber' => 'TTL deve ser um número de segundos.',
			'cockpit.dbRedisTable.addKey' => 'Adicionar chave',
			'cockpit.dbRedisTable.keyFieldHint' => 'chave',
			'cockpit.dbRedisTable.ttlFieldHint' => 'ttl (s, opcional)',
			'cockpit.dbRedisTable.valueFieldHint' => 'valor',
			'cockpit.dbRedisTable.searchHint' => 'Buscar — padrão, ex.: user:*',
			'cockpit.dbQueryView.saveQueryAs' => 'Salvar query como',
			'cockpit.dbQueryView.couldNotSave' => 'Não foi possível salvar',
			'cockpit.dbQueryView.selectDatabase' => 'Selecionar banco de dados',
			'cockpit.dbQueryView.noSqlConnections' => 'Nenhuma conexão SQL — adicione uma no painel Database',
			'cockpit.dbQueryView.running' => 'Executando…',
			'cockpit.dbQueryView.runSelection' => 'Executar seleção',
			'cockpit.dbQueryView.run' => 'Executar',
			'cockpit.dbQueryView.pickDatabaseHint' => 'Escolha um banco de dados acima e depois Executar (⌘↵).',
			'cockpit.dbQueryView.runQueryHint' => 'Execute a query (⌘↵) para ver os resultados aqui.',
			'cockpit.dbQueryView.noRows' => 'Nenhuma linha.',
			'cockpit.dbQueryView.rowsAffected' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 linha afetada', other: '${n} linhas afetadas', ), 
			'cockpit.dbQueryView.rowsFooter' => ({required Object n}) => '${n} linhas',
			'cockpit.dbQueryView.truncatedSuffix' => ' · truncado (aumente -- limit)',
			'cockpit.dbQueryView.table' => 'Tabela',
			'cockpit.dbQueryView.json' => 'JSON',
			'cockpit.dbQueryView.unsaved' => 'não salvo',
			'cockpit.dbQueryView.saved' => 'salvo',
			'cockpit.dbQueryView.copied' => 'Copiado',
			'cockpit.dbQueryView.copy' => 'Copiar',
			'cockpit.httpView.saveRequestAs' => 'Salvar request como',
			'cockpit.httpView.couldNotSave' => 'Não foi possível salvar',
			'cockpit.httpView.run' => 'Executar',
			'cockpit.httpView.running' => 'Executando…',
			'cockpit.httpView.noRequests' => 'Nenhum request neste arquivo — escreva um, ex.: GET https://example.com',
			'cockpit.httpView.selectRequest' => 'Selecionar request',
			'cockpit.httpView.requestCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 request', other: '${n} requests', ), 
			'cockpit.httpView.runHint' => 'Execute o request (⌘↵) para ver a resposta aqui.',
			'cockpit.httpView.emptyBody' => 'Corpo da resposta vazio.',
			'cockpit.httpView.body' => 'JSON',
			'cockpit.httpView.headers' => 'Headers',
			'cockpit.httpView.raw' => 'Text',
			'cockpit.httpView.truncatedSuffix' => ' · truncado (resposta grande demais)',
			'cockpit.httpView.error.title' => 'Falha no request',
			'cockpit.httpView.error.noRequest' => 'Nenhum request encontrado na posição do cursor.',
			'cockpit.httpView.error.invalidUrl' => ({required Object url}) => 'URL inválida: ${url}',
			'cockpit.httpView.error.unresolvedVariable' => ({required Object name}) => 'A variável {{${name}}} não tem valor. Declare com @${name} = … neste arquivo.',
			'cockpit.httpView.error.bodyFileMissing' => ({required Object path}) => 'Arquivo de corpo não encontrado: ${path}',
			'cockpit.httpView.error.bodyFileUnreadable' => ({required Object path, required Object detail}) => 'Não foi possível ler o arquivo de corpo ${path}: ${detail}',
			'cockpit.httpView.error.connectionFailed' => ({required Object detail}) => 'Não foi possível alcançar o servidor: ${detail}',
			'cockpit.httpView.error.connectionFailedNoDetail' => 'Não foi possível alcançar o servidor.',
			'cockpit.httpView.error.timeout' => ({required Object seconds}) => 'O request estourou o tempo limite de ${seconds}s.',
			'cockpit.httpView.error.responseTooLarge' => ({required Object bytes}) => 'A resposta passou do limite de ${bytes} bytes.',
			'cockpit.dbPanel.sectionDatabase' => 'BANCO DE DADOS',
			'cockpit.dbPanel.edit' => 'Editar…',
			'cockpit.dbPanel.copyName' => 'Copiar nome',
			'cockpit.dbPanel.newQuery' => 'Nova query',
			'cockpit.dbPanel.browseKeys' => 'Ver chaves',
			'cockpit.dbPanel.deleteConnectionTitle' => 'Excluir conexão',
			'cockpit.dbPanel.deleteConnectionMessage' => ({required Object name}) => 'Remover "${name}" deste workspace? Qualquer senha salva será descartada. Arquivos .dbq que fazem referência a ela não são afetados.',
			'cockpit.dbPanel.footer' => ({required Object n}) => '.cockpit/databases.json · ${n} conexões',
			'cockpit.dbPanel.footerOne' => '.cockpit/databases.json · 1 conexão',
			'cockpit.dbPanel.noConnections' => 'Nenhuma conexão ainda.',
			'cockpit.dbPanel.passwordRequired' => 'Senha não encontrada no host. Abra esta conexão e digite-a de novo — ela fica salva na máquina que executa o banco, não nesta.',
			'cockpit.dbMongoView.deleteDocumentTitle' => 'Excluir documento',
			'cockpit.dbMongoView.deleteDocumentMessage' => ({required Object id, required Object collection}) => 'Excluir o documento com _id ${id} de "${collection}"?',
			'cockpit.dbMongoView.filterHint' => 'Filtro — JSON, ex.: {"status": "active"}',
			'cockpit.dbMongoView.docCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 doc', other: '${n} docs', ), 
			'cockpit.dbMongoView.refresh' => 'Atualizar',
			'cockpit.dbMongoView.insertDocument' => 'Inserir documento',
			'cockpit.dbMongoView.noDocuments' => 'Nenhum documento nesta coleção.',
			'cockpit.dbMongoView.noDocumentsMatch' => 'Nenhum documento corresponde a este filtro.',
			'cockpit.dbMongoView.loadMore' => 'Carregar mais',
			'cockpit.dbMongoView.edit' => 'Editar',
			'cockpit.dbMongoView.insert' => 'Inserir',
			'cockpit.dbConnectionDialog.chooseFileTitle' => 'Escolher banco SQLite',
			'cockpit.dbConnectionDialog.file' => 'Arquivo',
			'cockpit.dbConnectionDialog.chooseFilePlaceholder' => 'Escolha um arquivo SQLite…',
			'cockpit.dbConnectionDialog.name' => 'Nome',
			'cockpit.dbConnectionDialog.password' => 'Senha',
			'cockpit.dbConnectionDialog.savePassword' => 'Salvar senha',
			'cockpit.dbConnectionDialog.allowWrites' => 'Permitir escrita (agentes)',
			'cockpit.dbConnectionDialog.allowWritesHint' => 'desligado = agentes só leem via CLI',
			'cockpit.dbConnectionDialog.visibleToAgents' => 'Visível para agentes',
			'cockpit.dbConnectionDialog.visibleToAgentsHint' => 'desligado = oculto da CLI, só na GUI',
			'cockpit.dbConnectionDialog.testing' => 'Testando conexão…',
			'cockpit.dbConnectionDialog.connectionOk' => 'Conexão OK',
			'cockpit.dbConnectionDialog.connectionFailed' => 'Falha na conexão',
			'cockpit.dbConnectionDialog.editTitle' => 'Editar conexão',
			'cockpit.dbConnectionDialog.newTitle' => 'Nova conexão',
			'cockpit.dbConnectionDialog.connectionString' => 'Connection string',
			'cockpit.dbConnectionDialog.invalidUrl' => 'URL de conexão inválida.',
			'cockpit.dbConnectionDialog.sshTunnel' => 'Túnel SSH',
			'cockpit.dbConnectionDialog.sshHost' => 'Host SSH',
			'cockpit.dbConnectionDialog.sshPort' => 'Porta SSH',
			'cockpit.dbConnectionDialog.sshUser' => 'Usuário SSH',
			'cockpit.dbConnectionDialog.privateKey' => 'Chave privada',
			'cockpit.dbConnectionDialog.choosePrivateKeyPlaceholder' => 'Escolha uma chave privada…',
			'cockpit.dbConnectionDialog.choosePrivateKeyDialogTitle' => 'Escolher chave privada SSH',
			'cockpit.dbConnectionDialog.keyPassphrase' => 'Senha da chave',
			'cockpit.dbConnectionDialog.savePassphrase' => 'Salvar senha da chave',
			'cockpit.dbConnectionDialog.passwordOnHost' => 'A senha fica salva no host, não nesta máquina.',
			'cockpit.sshPrompts.unknownSshHostTitle' => 'Host SSH desconhecido',
			'cockpit.sshPrompts.neverConnected' => ({required Object endpoint}) => 'O Cockpit nunca se conectou a ${endpoint} antes.',
			'cockpit.sshPrompts.trustHint' => 'Confie apenas se esta fingerprint corresponder ao servidor. Você pode verificar no servidor com:',
			'cockpit.sshPrompts.trust' => 'Confiar',
			'cockpit.sshPrompts.sshKeyPassphraseTitle' => 'Senha da chave SSH',
			'cockpit.sshPrompts.unlockMessage' => ({required Object keyPath, required Object connectionName}) => 'Desbloqueie ${keyPath} para conectar "${connectionName}".',
			'cockpit.sshPrompts.keptInMemoryHint' => 'Mantida em memória até o Cockpit fechar. Para permitir que agentes usem esta conexão, ative "Salvar senha da chave" na conexão.',
			'cockpit.sshPrompts.unlock' => 'Desbloquear',
			'cockpit.projectsRail.workspaces' => 'Workspaces',
			'cockpit.projectsRail.newWorkspace' => 'Novo workspace',
			'cockpit.projectsRail.settings' => 'Configurações',
			'cockpit.projectsRail.mergeToParent' => 'Mesclar no pai',
			'cockpit.projectsRail.updateFromParent' => 'Atualizar a partir do pai',
			'cockpit.projectsRail.forkWorktree' => 'Criar worktree derivada',
			'cockpit.projectsRail.copyBranch' => 'Copiar branch',
			'cockpit.projectsRail.remove' => 'Remover',
			'cockpit.projectsRail.moveToRealm' => 'Mover para realm',
			'cockpit.projectsRail.copyWorkspaceId' => 'Copiar id do workspace',
			'cockpit.projectsRail.rename' => 'Renomear',
			'cockpit.projectsRail.close' => 'Fechar',
			'cockpit.projectsRail.newRealm' => 'Novo realm…',
			'cockpit.projectsRail.manageRealms' => 'Gerenciar realms…',
			'cockpit.projectsRail.noWorkspaces' => 'Nenhum workspace ainda.',
			'cockpit.projectsRail.sync' => 'Sincronizar',
			'cockpit.projectsRail.pull' => 'Pull',
			'cockpit.projectsRail.push' => 'Push',
			'cockpit.projectsRail.createWorktree' => 'Criar worktree',
			'cockpit.projectsRail.worktreeCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('pt'))(n, one: '1 worktree', other: '${n} worktrees', ), 
			'cockpit.projectsRail.expandWorktrees' => 'Expandir worktrees',
			'cockpit.projectsRail.collapseWorktrees' => 'Recolher worktrees',
			'cockpit.findBar.find' => 'Buscar',
			'cockpit.findBar.matchCase' => 'Diferenciar maiúsculas',
			'cockpit.findBar.wholeWord' => 'Palavra inteira',
			'cockpit.findBar.useRegex' => 'Usar expressão regular',
			'cockpit.findBar.previous' => 'Anterior (⇧⏎)',
			_ => null,
		} ?? switch (path) {
			'cockpit.findBar.next' => 'Próximo (⏎)',
			'cockpit.findBar.close' => 'Fechar (Esc)',
			'cockpit.findBar.badPattern' => 'Padrão inválido',
			'cockpit.findBar.noResults' => 'Nenhum resultado',
			'cockpit.contentSearch.sectionSearch' => 'BUSCA',
			'cockpit.contentSearch.searchInFiles' => 'Buscar nos arquivos',
			'cockpit.contentSearch.matchCase' => 'Diferenciar maiúsculas',
			'cockpit.contentSearch.wholeWord' => 'Palavra inteira',
			'cockpit.contentSearch.useRegex' => 'Usar expressão regular',
			'cockpit.contentSearch.invalidRegex' => 'Expressão regular inválida.',
			'cockpit.contentSearch.typeToSearch' => 'Digite para buscar em todos os arquivos.',
			'cockpit.contentSearch.searching' => 'Buscando…',
			'cockpit.contentSearch.noResults' => 'Nenhum resultado.',
			'cockpit.emptyPane.newAgent' => 'Novo agente',
			'cockpit.emptyPane.newAgentDescription' => 'Roda um pi na pasta que você escolher',
			'cockpit.emptyPane.newTerminal' => 'Novo terminal',
			'cockpit.emptyPane.newTerminalDescription' => 'Abre um shell na pasta que você escolher',
			'cockpit.topbar.collapseSidebar' => 'Recolher barra lateral',
			'cockpit.topbar.toggleFiles' => 'Mostrar/ocultar arquivos',
			'cockpit.topbar.filesUnavailable' => 'Arquivos indisponíveis no Cockpit',
			'cockpit.topbar.hideKeyboard' => 'Baixar teclado',
			'cockpit.transcript.cancel' => 'Cancelar',
			'cockpit.transcript.send' => 'Enviar',
			'cockpit.transcript.typeYourAnswer' => 'Digite sua resposta',
			'cockpit.transcript.startHint' => 'Envie um prompt para o agente começar.',
			'cockpit.transcript.workedFor' => ({required Object duration}) => 'Trabalhou por ${duration}',
			'cockpit.tasks.hotReload' => 'Hot reload',
			'cockpit.tasks.hotRestart' => 'Hot restart',
			'cockpit.tasks.toggleDebugPaint' => 'Alternar debug paint',
			'cockpit.tasks.togglePlatform' => 'Alternar plataforma',
			'cockpit.tasks.quit' => 'Sair',
			'cockpit.notifications.agentFinished' => 'Agente terminou',
			'cockpit.notifications.open' => 'Abrir',
			'cockpit.notifications.agentNeedsAction' => 'Agente precisa de você',
			'cockpit.notifications.agentCrashed' => 'Agente parou inesperadamente',
			'cockpit.terminal.cwdFallbackWarning' => ({required Object requested, required Object path}) => 'Aviso: a pasta "${requested}" não existe. Este terminal abriu em "${path}".',
			'cockpit.remoteHost.addHost' => 'Adicionar host remoto',
			'cockpit.remoteHost.hostName' => 'Nome',
			'cockpit.remoteHost.sshTarget' => 'Destino SSH (usuário@host)',
			'cockpit.remoteHost.connecting' => ({required Object host}) => 'Conectando a ${host}…',
			'cockpit.remoteHost.openingTunnel' => 'Túnel SSH',
			'cockpit.remoteHost.installingServer' => 'Instalando servidor',
			'cockpit.remoteHost.handshake' => ({required Object version}) => 'Servidor ${version}',
			'cockpit.remoteHost.loadingWorkspace' => 'Carregando workspace…',
			'cockpit.remoteHost.reconnecting' => ({required Object host}) => 'Reconectando a ${host}…',
			'cockpit.remoteHost.offline' => ({required Object host}) => '${host} offline',
			'cockpit.remoteHost.remove' => 'Remover',
			'cockpit.remoteHost.reconnect' => 'Reconectar',
			'cockpit.remoteHost.installServer' => 'Instalar servidor',
			'cockpit.remoteHost.errSshUnreachable' => ({required Object host}) => 'Não foi possível alcançar ${host} via SSH. Está ligado e com o Login Remoto ativado?',
			'cockpit.remoteHost.errInstallFailed' => ({required Object host}) => 'Não foi possível instalar o servidor em ${host}.',
			'cockpit.remoteHost.errVersionMismatch' => 'Versão do servidor incompatível; atualize-o.',
			'cockpit.remoteHost.errDetail' => ({required Object detail}) => 'Detalhes: ${detail}',
			'cockpit.remoteHost.pickFolderTitle' => ({required Object host}) => 'Abrir pasta em ${host}',
			'cockpit.remoteHost.openHere' => 'Abrir aqui',
			'cockpit.remoteHost.emptyFolder' => 'Sem subpastas',
			'cockpit.remoteHost.newLocal' => 'Local',
			'cockpit.remoteHost.newRemote' => 'Remoto',
			'cockpit.remoteHost.chooseHost' => 'Escolher um host',
			'cockpit.remoteHost.newHostEntry' => 'Novo host…',
			'cockpit.remoteHost.editHost' => 'Editar host',
			'cockpit.remoteHost.userLabel' => 'Usuário',
			'cockpit.remoteHost.hostLabel' => 'Host / IP',
			'cockpit.remoteHost.portLabel' => 'Porta',
			'cockpit.remoteHost.authLabel' => 'Autenticação',
			'cockpit.remoteHost.authKey' => 'Chave SSH',
			'cockpit.remoteHost.authPassword' => 'Senha',
			'cockpit.remoteHost.passwordLabel' => 'Senha',
			'cockpit.remoteHost.passwordKeep' => 'Deixe em branco para manter a atual',
			'cockpit.remoteHost.errUser' => 'Usuário obrigatório',
			'cockpit.remoteHost.errHost' => 'Host obrigatório',
			'cockpit.remoteHost.errPassword' => 'Senha obrigatória',
			'cockpit.remoteHost.identityChoose' => 'Escolher…',
			'cockpit.remoteHost.identityEmpty' => 'Nenhuma chave selecionada',
			'cockpit.remoteHost.identityDialogTitle' => 'Selecione a chave privada SSH',
			'cockpit.remoteHost.errIdentity' => 'Escolha a chave privada para autenticar.',
			'cockpit.remoteHost.errHostKeyUnknown' => ({required Object host}) => 'O Cockpit ainda não confia em ${host}. Conecte de novo e confirme o fingerprint.',
			'cockpit.remoteHost.errHostKeyChanged' => ({required Object host}) => '${host} está apresentando uma chave SSH diferente da guardada. Se você não reinstalou essa máquina, pare e verifique — se reinstalou, remova a entrada antiga do ~/.ssh/known_hosts.',
			'cockpit.remoteHost.errHostBundleMissing' => ({required Object host}) => '${host} é Windows mas não tem o Cockpit instalado. O servidor remoto é instalado a partir do bundle do Cockpit que já está naquela máquina — instale o Cockpit lá e tente de novo.',
			'cockpit.remoteHost.errHostUnknownOs' => ({required Object host}) => 'Não foi possível identificar o sistema de ${host}. A conta pode ter shell restrito, ou nenhum shell.',
			'cockpit.remoteHost.errIdentityPublic' => 'Só a chave pública está aqui. Isso só funciona se a privada estiver no seu agente SSH; senão, escolha a privada (mesmo nome, sem .pub).',
			'cockpit.remoteHost.errIdentityNotKey' => 'Esse arquivo não parece uma chave privada.',
			'cockpit.remoteHost.errIdentityMissingFile' => 'Esse arquivo não existe mais.',
			'cockpit.remoteHost.errIdentityUnreadable' => 'Não foi possível ler esse arquivo.',
			'cockpit.browserPane.back' => 'Voltar',
			'cockpit.browserPane.forward' => 'Avançar',
			'cockpit.browserPane.reload' => 'Recarregar',
			'cockpit.browserPane.urlHint' => 'Digite a URL ou endereço',
			'cockpit.browserPane.go' => 'Ir',
			'settings.language.title' => 'Idioma',
			'settings.language.system' => 'Sistema',
			'settings.language.english' => 'Inglês',
			'settings.language.portugueseBr' => 'Português (BR)',
			'settings.language.spanish' => 'Espanhol',
			'settings.revokeDialog.deviceRemoved' => 'Dispositivo removido.',
			'settings.revokeDialog.failedToRevoke' => 'Falha ao revogar o dispositivo.',
			'settings.revokeDialog.revoking' => 'Revogando…',
			'settings.revokeDialog.revokingDevice' => ({required Object name}) => 'Revogando ${name}…',
			'settings.revokeDialog.connectingMessage' => 'Conectando ao relay e removendo o acesso.',
			'settings.revokeDialog.ok' => 'Ok',
			'settings.pairingDialog.title' => 'Parear dispositivo',
			'settings.pairingDialog.connectingToRelay' => 'Conectando ao relay…',
			'settings.pairingDialog.step1' => 'Abra o app Remote Pi no seu celular.',
			'settings.pairingDialog.step2' => 'Toque em adicionar / parear dispositivo.',
			'settings.pairingDialog.step3' => 'Aponte a câmera para o QR abaixo.',
			'settings.pairingDialog.qrGenerationFailed' => 'Não foi possível gerar o QR.',
			'settings.pairingDialog.autoRefreshHint' => 'O código se atualiza sozinho. Mantenha esta janela aberta.',
			'settings.pairingDialog.pairingFailed' => 'Falha no pareamento.',
			'settings.pairingDialog.tryAgain' => 'Tentar novamente',
			'settings.pairingDialog.copied' => 'Copiado!',
			'settings.pairingDialog.copyData' => 'Copiar dados',
			'settings.page.header.back' => 'Voltar',
			'settings.page.header.title' => 'Configurações',
			'settings.page.nav.general' => 'Geral',
			'settings.page.nav.appearance' => 'Aparência',
			'settings.page.nav.terminal' => 'Terminal',
			'settings.page.nav.language' => 'Linguagem',
			'settings.page.nav.shortcuts' => 'Atalhos',
			'settings.page.nav.notifications' => 'Notificações',
			'settings.page.nav.connectivity' => 'Conectividade',
			'settings.page.nav.daemonAgents' => 'Agentes Daemon',
			'settings.page.nav.schedules' => 'Agendamentos',
			'settings.page.nav.automations' => 'Automações',
			'settings.page.nav.remoteHosts' => 'Hosts remotos',
			'settings.page.general.sectionAgent' => 'Agente',
			'settings.page.general.sectionEditor' => 'Editor',
			'settings.page.general.neovimTitle' => 'Abrir arquivos no Neovim',
			'settings.page.general.neovimChecking' => 'Procurando o Neovim…',
			'settings.page.general.neovimNotFound' => 'O Neovim não foi encontrado na PATH do seu shell.',
			'settings.page.general.neovimRefresh' => 'Verificar novamente',
			'settings.page.general.enableAgentsTitle' => 'Ativar agentes',
			'settings.page.general.enableAgentsDesc' => 'Mostra a opção de abrir abas de agente (pi). Quando desligado, o Cockpit funciona apenas como workspace de terminal.',
			'settings.page.general.showCockpitTitle' => 'Mostrar terminal do Cockpit',
			'settings.page.general.showCockpitDesc' => 'Mantém um workspace sem pasta, só de terminal, fixado no topo da barra lateral. Desligar fecha seus terminais.',
			'settings.page.general.launchAtStartupTitle' => 'Iniciar ao ligar',
			'settings.page.general.launchAtStartupDesc' => 'Inicia o Cockpit automaticamente quando você faz login no computador.',
			'settings.page.general.sectionUpdates' => 'Atualizações',
			'settings.page.general.checkUpdatesTitle' => 'Verificar atualizações',
			'settings.page.general.checkUpdatesDesc' => 'Com que frequência o Cockpit deve procurar novas versões.',
			'settings.page.general.agentsInUseError' => 'Não é possível desligar os agentes com uma aba de agente aberta. Feche todas as abas de agente primeiro e depois desative.',
			'settings.page.general.updateFrequency.daily' => 'Diariamente',
			'settings.page.general.updateFrequency.weekly' => 'Semanalmente',
			'settings.page.general.updateFrequency.monthly' => 'Mensalmente',
			'settings.page.general.updateFrequency.never' => 'Nunca',
			'settings.page.diagnostics.sectionTitle' => 'Diagnóstico',
			'settings.page.diagnostics.logFileTitle' => 'Arquivo de log',
			'settings.page.diagnostics.logFileDesc' => ({required Object days, required Object path}) => 'Erros e eventos de inicialização são registrados aqui, mantidos por ${days} dias.\n${path}',
			'settings.page.diagnostics.unavailable' => 'indisponível',
			'settings.page.diagnostics.reveal' => 'Revelar',
			'settings.page.diagnostics.reportTitle' => 'Reportar um problema',
			'settings.page.diagnostics.reportDesc' => 'Abre uma issue pré-preenchida com sua versão, SO e log recente. Nada é enviado automaticamente — você revisa antes.',
			'settings.page.diagnostics.reportButton' => 'Reportar…',
			'settings.page.diagnostics.reportDialogTitle' => 'Relatório de problema',
			'settings.page.diagnostics.reportDialogError' => 'Reportado manualmente pelas Configurações.',
			'settings.page.diagnostics.reportDialogDescription' => 'Descreva o que deu errado na issue. O log recente está incluído abaixo e em "Copiar detalhes".',
			'settings.page.storage.sectionTitle' => 'Armazenamento',
			'settings.page.storage.locationTitle' => 'Local de armazenamento',
			'settings.page.storage.locationDesc' => ({required Object root}) => 'O Cockpit guarda seus projetos, layouts e configurações aqui. Aponte para uma pasta sincronizada para fazer backup.\n${root}',
			'settings.page.storage.useDefault' => 'Usar padrão',
			'settings.page.storage.working' => 'Trabalhando…',
			'settings.page.storage.change' => 'Alterar…',
			'settings.page.storage.resetTitle' => 'Redefinir o Cockpit',
			'settings.page.storage.resetDesc' => 'Exclui todos os dados locais — projetos, layouts, configurações e histórico do terminal — e volta ao local padrão.',
			'settings.page.storage.resetButton' => 'Redefinir…',
			'settings.page.storage.resetConfirm' => 'Redefinir',
			'settings.page.storage.resetDialogTitle' => 'Redefinir o Cockpit?',
			'settings.page.storage.resetDialogContent' => 'Isso exclui permanentemente todos os dados locais do Cockpit — projetos, layouts, configurações e histórico do terminal. Isso não pode ser desfeito. O Cockpit será fechado para você começar do zero.',
			'settings.page.storage.restartRequiredTitle' => 'Reinicialização necessária',
			'settings.page.storage.restartChangeFolderMessage' => ({required Object path}) => 'O Cockpit usará esta pasta a partir da próxima abertura:\n${path}',
			'settings.page.storage.restartUseDefaultMessage' => 'O Cockpit usará o local padrão do sistema a partir da próxima abertura. Seus dados na pasta personalizada permanecem intactos.',
			'settings.page.storage.restartResetMessage' => 'Todos os dados do Cockpit foram apagados. Reinicie para começar do zero.',
			'settings.page.storage.later' => 'Mais tarde',
			'settings.page.storage.quitCockpit' => 'Sair do Cockpit',
			'settings.page.storage.chooseFolderDialogTitle' => 'Escolha uma pasta para os dados do Cockpit',
			'settings.page.terminal.sectionDefaultTerminal' => 'Terminal padrão',
			'settings.page.terminal.engineTitle' => 'Motor',
			'settings.page.terminal.engineDesc' => 'Usado por novas abas de terminal e buffers de saída de tasks. Abas abertas mantêm o motor atual.',
			'settings.page.terminal.shellTitle' => 'Shell',
			'settings.page.terminal.shellDesc' => 'Qual shell novas abas de terminal abrem. A seta ao lado do + ainda abre qualquer outro, só para aquela aba.',
			'settings.page.terminal.noWslMessage' => 'Nenhuma distro WSL encontrada. Instale uma (wsl.exe --install) e reinicie o Cockpit para vê-la listada aqui.',
			'settings.page.appearance.sectionTheme' => 'Tema',
			'settings.page.appearance.themeTitle' => 'Tema',
			'settings.page.appearance.themeDesc' => 'Cores do app, realce de código e paleta do terminal.',
			'settings.page.appearance.modeTitle' => 'Modo',
			'settings.page.appearance.modeDesc' => 'Qual variante do tema usar.',
			'settings.page.appearance.modeOnlyDark' => ({required Object theme}) => '"${theme}" só traz a variante escura, então isto não tem efeito.',
			'settings.page.appearance.modeOnlyLight' => ({required Object theme}) => '"${theme}" só traz a variante clara, então isto não tem efeito.',
			'settings.page.appearance.themeFileTitle' => 'Arquivo de tema',
			'settings.page.appearance.themeFileDesc' => 'Importe um tema de um arquivo JSON, ou exporte o tema ativo.',
			'settings.page.appearance.previewCode' => 'Código',
			'settings.page.appearance.previewTerminal' => 'Terminal',
			'settings.page.appearance.themeSystem' => 'Sistema',
			'settings.page.appearance.themeLight' => 'Claro',
			'settings.page.appearance.themeDark' => 'Escuro',
			'settings.page.appearance.sectionFonts' => 'Fontes',
			'settings.page.appearance.interfaceFontTitle' => 'Fonte da interface',
			'settings.page.appearance.interfaceFontDesc' => 'Usada em todo o aplicativo. Vazio = padrão do sistema.',
			'settings.page.appearance.interfaceSizeTitle' => 'Tamanho da interface',
			'settings.page.appearance.codeFontTitle' => 'Fonte do código',
			'settings.page.appearance.codeFontDesc' => 'Código e diffs. Vazio = padrão do sistema.',
			'settings.page.appearance.codeSizeTitle' => 'Tamanho do código',
			'settings.page.appearance.terminalFontTitle' => 'Fonte do terminal',
			'settings.page.appearance.terminalFontDesc' => 'Só o terminal. Vazio = padrão do sistema.',
			'settings.page.appearance.terminalSizeTitle' => 'Tamanho do terminal',
			'settings.page.appearance.terminalSizeDesc' => 'Desligado = segue o tamanho do código.',
			'settings.page.appearance.terminalSizeInherit' => 'Seguir o código',
			'settings.page.appearance.terminalWeightTitle' => 'Peso do terminal',
			'settings.page.appearance.terminalWeightDesc' => 'Telas de baixa densidade engrossam os traços. O automático afina só nelas e não mexe no Retina.',
			'settings.page.appearance.terminalWeightAuto' => 'Automático (pela tela)',
			'settings.page.appearance.terminalWeightLight' => 'Fino',
			'settings.page.appearance.terminalWeightNormal' => 'Normal',
			'settings.page.appearance.terminalWeightMedium' => 'Médio',
			'settings.page.appearance.terminalWeightSemiBold' => 'Seminegrito',
			'settings.page.appearance.sectionConversation' => 'Conversa',
			'settings.page.appearance.pinUserMessageTitle' => 'Fixar mensagem do usuário',
			'settings.page.appearance.pinUserMessageDesc' => 'A pergunta fica fixa no topo enquanto a resposta rola.',
			'settings.page.appearance.importTheme' => 'Importar…',
			'settings.page.appearance.exportTheme' => 'Exportar…',
			'settings.page.appearance.deleteTheme' => 'Remover',
			'settings.page.appearance.importThemeDialog' => 'Escolha um arquivo de tema',
			'settings.page.appearance.exportThemeDialog' => 'Salvar tema como',
			'settings.page.appearance.themeImported' => ({required Object name}) => 'Tema "${name}" importado.',
			'settings.page.appearance.themeExported' => 'Tema salvo.',
			'settings.page.appearance.themeDeleted' => 'Tema removido.',
			'settings.page.appearance.fontPickerTitle' => 'Escolher uma fonte',
			'settings.page.appearance.fontPickerSearch' => 'Buscar fontes',
			'settings.page.appearance.fontPickerEmpty' => 'Nenhuma fonte correspondente nesta máquina.',
			'settings.page.appearance.fontPickerBundled' => 'inclusa',
			'settings.page.appearance.fontPickerCustom' => 'Não está na lista? Digite o nome exato da família.',
			'settings.page.appearance.fontPickerCustomHint' => 'Nome da família',
			'settings.page.appearance.fontPickerUse' => 'Usar',
			'settings.page.appearance.fontPickerDefault' => 'Padrão',
			'settings.page.appearance.fontMissing' => 'Não encontrada nesta máquina — usando o fallback.',
			'settings.page.appearance.sectionLayout' => 'Layout',
			'settings.page.appearance.swapPanelsTitle' => 'Inverter panes',
			'settings.page.appearance.swapPanelsDesc' => 'Coloca os workspaces à direita e arquivos, busca, git e banco à esquerda.',
			'settings.page.notifications.sectionTitle' => 'Notificações',
			'settings.page.notifications.enableTitle' => 'Ativar notificações',
			'settings.page.notifications.enableDesc' => 'Avisar quando um agente terminar uma resposta e a janela não estiver em foco.',
			'settings.page.notifications.systemPermissionTitle' => 'Permissão do sistema',
			'settings.page.notifications.grantedDesc' => 'O Cockpit tem permissão para enviar notificações.',
			'settings.page.notifications.notGrantedDesc' => 'O macOS ainda não concedeu acesso a notificações.',
			'settings.page.notifications.granted' => 'Concedido',
			'settings.page.notifications.requestPermission' => 'Solicitar permissão',
			'settings.page.notifications.soundsTitle' => 'Sons',
			'settings.page.notifications.soundVolumeTitle' => 'Volume',
			'settings.page.notifications.soundTurnDone' => 'Turno concluído',
			'settings.page.notifications.soundTurnDoneDesc' => 'Um agente terminou o turno.',
			'settings.page.notifications.soundActionRequired' => 'Ação necessária',
			'settings.page.notifications.soundActionRequiredDesc' => 'Um agente está esperando sua aprovação ou resposta.',
			'settings.page.notifications.soundAgentError' => 'Erro do agente',
			'settings.page.notifications.soundAgentErrorDesc' => 'O processo de um agente parou inesperadamente.',
			'settings.page.notifications.soundDefault' => 'Padrão',
			'settings.page.notifications.soundCustom' => ({required Object name}) => 'Personalizado: ${name}',
			'settings.page.notifications.soundChooseFile' => 'Escolher arquivo',
			'settings.page.notifications.soundReset' => 'Voltar ao padrão',
			'settings.page.notifications.soundOnActiveTab' => 'Tocar também com a aba ativa',
			'settings.page.notifications.soundPreview' => 'Ouvir',
			'settings.page.shortcuts.notCustomizable' => 'Os atalhos de teclado ainda não são personalizáveis.',
			'settings.page.languages.sectionFormatting' => 'FORMATAÇÃO',
			'settings.page.languages.formatOnSaveTitle' => 'Formatar ao salvar',
			'settings.page.languages.formatOnSaveDesc' => 'Formata o arquivo automaticamente ao salvar (⌘S).',
			'settings.page.languages.sectionLanguageServers' => 'SERVIDORES DE LINGUAGEM',
			'settings.page.languages.footerNote' => 'Erros e formatação usam o language server de cada linguagem. O Cockpit não instala servidores — ele usa o que já está na sua máquina. ● responde · ○ não encontrado ou comando inválido (instale o servidor ou ajuste o comando).',
			'settings.page.languages.serverCommandLabel' => 'Comando do language server',
			'settings.page.languages.formatterCommandLabel' => 'Comando do formatador (opcional)',
			'settings.page.languages.formatterHint' => 'Formatador externo com o placeholder %FILE%. Tem prioridade sobre o formatador do LSP quando definido.',
			'settings.page.languages.resetToDefault' => 'Redefinir para o padrão',
			'settings.page.languages.saveAndRestart' => 'Salvar e reiniciar',
			'settings.page.languages.statusResponds' => 'Servidor responde',
			'settings.page.languages.statusNotFound' => 'Servidor não encontrado ou comando inválido',
			'settings.page.connectivity.sectionRelay' => 'Relay',
			'settings.page.connectivity.sectionPairedDevices' => 'Dispositivos pareados',
			'settings.page.connectivity.reloadTooltip' => 'Recarregar',
			'settings.page.connectivity.failedToListDevices' => 'Falha ao listar dispositivos.',
			'settings.page.connectivity.noPairedDevices' => 'Nenhum dispositivo pareado.',
			'settings.page.connectivity.relayAddressTitle' => 'Endereço do relay',
			'settings.page.connectivity.relayAddressDesc' => 'Servidor que conecta seus agentes ao celular. Aplica-se a todo agente com o relay ativado.',
			'settings.page.connectivity.saving' => 'Salvando…',
			'settings.page.connectivity.check' => 'Verificar',
			'settings.page.connectivity.healthOnline' => 'Online',
			'settings.page.connectivity.healthNoResponse' => 'Sem resposta',
			'settings.page.connectivity.healthNotChecked' => 'Não verificado',
			'settings.page.connectivity.deviceDefaultLabel' => 'Dispositivo',
			'settings.page.connectivity.revoke' => 'Revogar',
			'settings.page.connectivity.pairNewDevice' => 'Parear novo dispositivo',
			'settings.page.connectivity.revokeDialogTitle' => 'Revogar dispositivo?',
			'settings.page.connectivity.revokeDialogContent' => ({required Object name}) => '"${name}" perderá o acesso aos seus agentes e precisará parear novamente.\n\nVocê precisa estar conectado ao relay — o app conectará automaticamente para revogar.',
			'settings.page.schedules.sectionScheduledPrompts' => 'Prompts agendados',
			'settings.page.schedules.createSchedule' => 'Criar agendamento',
			'settings.page.schedules.createDaemonFirst' => 'Crie um Agente Daemon primeiro.',
			'settings.page.schedules.supervisorOffline' => 'Supervisor offline. Agendamentos precisam do pi-supervisord em execução (`remote-pi install`).',
			'settings.page.schedules.failedToListSchedules' => 'Falha ao listar agendamentos.',
			'settings.page.schedules.noSchedules' => 'Nenhum agendamento. Crie um prompt recorrente para um daemon.',
			'settings.page.schedules.runNow' => 'Executar agora',
			'settings.page.schedules.viewLog' => 'Ver log',
			'settings.page.schedules.disabled' => 'desativado',
			'settings.page.schedules.nextRun' => ({required Object when}) => 'próximo ${when}',
			'settings.page.schedules.lastRun' => ({required Object label}) => 'último: ${label}',
			'settings.page.schedules.removeScheduleDialogTitle' => 'Remover agendamento?',
			'settings.page.schedules.removeScheduleDialogContent' => ({required Object schedule, required Object daemon}) => 'O job "${schedule}" de ${daemon} é excluído. Suas execuções param.',
			'settings.page.schedules.newScheduleTitle' => 'Novo agendamento',
			'settings.page.schedules.daemonLabel' => 'Daemon',
			'settings.page.schedules.whenLabel' => 'Quando (expressão cron)',
			'settings.page.schedules.previewPlaceholder' => 'A próxima execução aparece aqui',
			'settings.page.schedules.previewComputed' => 'Próximo: calculado ao salvar',
			'settings.page.schedules.previewNext' => ({required Object when}) => 'Próximo: ${when}',
			'settings.page.schedules.exampleEveryDay9am' => 'todo dia às 9h',
			'settings.page.schedules.exampleHourly' => 'a cada hora',
			'settings.page.schedules.exampleEvery15Min' => 'a cada 15 min',
			'settings.page.schedules.exampleWeekdays6pm' => 'dias úteis às 18h',
			'settings.page.schedules.promptLabel' => 'Prompt',
			'settings.page.schedules.timezoneLabel' => 'Fuso horário (opcional)',
			'settings.page.schedules.skipIfBusy' => 'Pular se o agente estiver ocupado',
			'settings.page.schedules.wakeIfStopped' => 'Acordar o daemon se estiver parado',
			'settings.page.schedules.catchup' => 'Recuperar 1 execução perdida (catchup)',
			'settings.page.schedules.fillRequiredError' => 'Preencha a expressão e o prompt.',
			'settings.page.schedules.creating' => 'Criando…',
			'settings.page.schedules.failedToCreateSchedule' => 'Falha ao criar o agendamento.',
			'settings.page.schedules.historyTitle' => ({required Object schedule}) => 'Histórico — ${schedule}',
			'settings.page.schedules.failedToReadLog' => 'Falha ao ler o log.',
			'settings.page.schedules.noRecordsYet' => 'Nenhum registro ainda.',
			'settings.page.schedules.cronDelivered' => 'entregue',
			'settings.page.schedules.cronWokeDelivered' => 'acordou + entregue',
			'settings.page.schedules.cronFailed' => 'falhou',
			'settings.page.schedules.cronSkippedBusy' => 'pulado (ocupado)',
			'settings.page.schedules.cronSkippedStopped' => 'pulado (parado)',
			'settings.page.schedules.cronSkippedDisabled' => 'pulado (desativado)',
			'settings.page.daemons.sectionAlwaysOnAgents' => 'Agentes sempre ativos',
			'settings.page.daemons.createDaemon' => 'Criar daemon',
			'settings.page.daemons.startAll' => 'Iniciar todos',
			'settings.page.daemons.stopAll' => 'Parar todos',
			'settings.page.daemons.restartAll' => 'Reiniciar todos',
			'settings.page.daemons.restartSupervisor' => 'Reiniciar supervisor',
			'settings.page.daemons.restartSupervisorDialogTitle' => 'Reiniciar o supervisor?',
			'settings.page.daemons.restartSupervisorDialogContent' => 'Reinicia o processo do supervisor (recarrega o código). Todos os daemons reiniciam junto e ficam offline por alguns segundos.',
			'settings.page.daemons.removeDaemonDialogTitle' => 'Remover daemon?',
			'settings.page.daemons.removeDaemonDialogContent' => ({required Object name}) => '"${name}" para de rodar e sai do registro. A pasta e sua configuração local são mantidas — você pode recriá-lo depois.',
			'settings.page.daemons.supervisorOfflineTitle' => 'Supervisor offline',
			'settings.page.daemons.supervisorOfflineDesc' => 'O pi-supervisord não está em execução. Instale-o com `remote-pi install` para gerenciar agentes 24/7.',
			'settings.page.daemons.failedToListDaemons' => 'Falha ao listar daemons.',
			'settings.page.daemons.noRegisteredAgents' => 'Nenhum agente registrado. Crie um a partir de uma pasta.',
			'settings.page.daemons.start' => 'Iniciar',
			'settings.page.daemons.stop' => 'Parar',
			'settings.page.daemons.edit' => 'Editar',
			'settings.page.daemons.stateRunning' => 'em execução',
			'settings.page.daemons.stateStarting' => 'iniciando',
			'settings.page.daemons.stateStopped' => 'parado',
			'settings.page.daemons.stateFailed' => 'falhou',
			'settings.page.daemons.newDaemonTitle' => 'Novo daemon',
			'settings.page.daemons.editDaemonTitle' => 'Editar daemon',
			'settings.page.daemons.nameLabel' => 'Nome',
			'settings.page.daemons.namePlaceholder' => 'ex.: PC, Servidor, Casa',
			'settings.page.daemons.nameRequiredError' => 'Digite um nome.',
			'settings.page.daemons.nameDuplicateError' => 'Já existe um agente com esse nome.',
			'settings.page.daemons.folderLabel' => 'Pasta',
			'settings.page.daemons.noFolderChosen' => 'Nenhuma pasta escolhida',
			'settings.page.daemons.choose' => 'Escolher',
			'settings.page.daemons.changeFolder' => 'Alterar',
			'settings.page.daemons.folderCannotBeChanged' => 'A pasta não pode ser alterada.',
			'settings.page.daemons.folderRequiredError' => 'Escolha uma pasta.',
			'settings.page.daemons.folderDuplicateError' => 'Já existe um agente nesta pasta.',
			'settings.page.daemons.pickFolderDialogTitle' => 'Escolha a pasta do Agente Daemon',
			'settings.page.automations.sectionCommitMessages' => 'Mensagens de commit',
			'settings.page.automations.harness' => 'Harness',
			'settings.page.automations.harnessDiscovering' => 'Procurando harnesses de linha de comando instalados…',
			'settings.page.automations.harnessNoneFound' => 'Nenhum harness compatível foi encontrado no PATH.',
			'settings.page.automations.harnessConfiguredUnavailable' => ({required Object harness}) => '${harness} está configurado, mas indisponível.',
			'settings.page.automations.harnessChoose' => 'Escolha a CLI usada para gerar mensagens de commit.',
			'settings.page.automations.harnessRefresh' => 'Atualizar harnesses instalados',
			'settings.page.automations.notConfigured' => 'Não configurado',
			'settings.page.automations.model' => 'Modelo',
			'settings.page.automations.modelUnavailable' => 'A lista de modelos fica indisponível até o harness ser encontrado.',
			'settings.page.automations.modelCliOnly' => 'Este harness usa o modelo padrão da própria CLI.',
			'settings.page.automations.modelCliDefault' => 'Padrão da CLI',
			'settings.page.automations.modelAuto' => 'Auto',
			'settings.page.automations.modelSearch' => ({required Object count}) => 'Buscar entre ${count} modelos…',
			'settings.page.automations.modelAutoRouted' => 'Este harness escolhe o modelo automaticamente.',
			'settings.page.automations.modelAccountOnly' => 'Só aparecem os modelos liberados na sua conta.',
			'settings.page.automations.generateFromSourceControl' => 'Gerar pelo Controle de Versão',
			'settings.page.automations.generateFromSourceControlDescription' => 'O Cockpit envia apenas o diff selecionado e os assuntos dos commits recentes. Padrões comuns de credenciais e arquivos sensíveis são redigidos antes de o harness rodar.',
			'settings.page.automations.discoveryFailed' => 'Não foi possível descobrir os harnesses de automação instalados.',
			'settings.page.automations.staleModel' => ({required Object model, required Object harness}) => 'O modelo "${model}" não está mais disponível para ${harness}. Usando o padrão da CLI; escolha outro modelo em Configurações se precisar.',
			'settings.page.automations.recommendedSuffix' => 'Recomendado',
			'settings.remoteHosts.title' => 'Hosts remotos',
			'settings.remoteHosts.description' => 'Máquinas que você acessa por SSH. Adicionar um host aqui é o mesmo que adicionar pelo menu "+" do workspace.',
			'settings.remoteHosts.empty' => 'Nenhum host remoto ainda.',
			'settings.remoteHosts.add' => 'Adicionar host',
			'settings.remoteHosts.edit' => 'Editar',
			'settings.remoteHosts.reconnect' => 'Reconectar',
			'settings.remoteHosts.remove' => 'Remover',
			'settings.remoteHosts.removeTitle' => 'Remover host',
			'settings.remoteHosts.removeMessage' => ({required Object name}) => 'Remover "${name}" e todos os workspaces dele? Nada é apagado no host.',
			'settings.remoteHosts.workspacesCount' => ({required Object count}) => '${count} workspace(s)',
			'settings.remoteHosts.deviceKeyTitle' => 'Chave deste dispositivo',
			'settings.remoteHosts.deviceKeyDesc' => 'Adicione esta chave pública ao ~/.ssh/authorized_keys do host para este dispositivo poder conectar.',
			'settings.remoteHosts.deviceKeyCopy' => 'Copiar chave pública',
			'settings.remoteHosts.deviceKeyCopied' => 'Chave pública copiada',
			'settings.remoteHosts.statusConnected' => 'Conectado',
			'settings.remoteHosts.statusConnecting' => 'Conectando…',
			'settings.remoteHosts.statusReconnecting' => 'Reconectando…',
			'settings.remoteHosts.statusOffline' => 'Offline',
			'settings.remoteHosts.statusIdle' => 'Não conectado',
			'settings.remoteHosts.helpTitle' => 'Como funciona',
			'settings.remoteHosts.helpBody' => 'O Cockpit conecta na sua máquina por SSH e fala com um servidor pequeno que roda os terminais, arquivos e git lá. O host precisa ter o Cockpit (desktop) ou o cockpit-server instalado e rodando, e a chave pública deste dispositivo adicionada no ~/.ssh/authorized_keys dele.',
			'automation.error.unavailable' => ({required Object harness}) => '${harness} não está instalado ou não está no PATH.',
			'automation.error.modelUnavailable' => ({required Object model, required Object harness}) => 'O modelo "${model}" não está disponível para ${harness}. Escolha outro modelo em Configurações.',
			'automation.error.authentication' => ({required Object harness, required Object detail}) => '${harness}: ${detail}',
			'automation.error.timeout' => ({required Object harness, required Object seconds}) => '${harness} não respondeu em ${seconds} segundos.',
			'automation.error.cancelled' => 'A geração da mensagem de commit foi cancelada.',
			'automation.error.process' => ({required Object harness, required Object detail}) => '${harness}: ${detail}',
			'automation.error.processNoDetail' => ({required Object harness}) => '${harness} não conseguiu gerar uma mensagem de commit.',
			'automation.error.invalidResponse' => 'A automação devolveu uma mensagem de commit vazia.',
			'automation.error.busy' => 'Já há uma mensagem de commit sendo gerada.',
			'automation.error.unknown' => 'A automação não conseguiu gerar uma mensagem de commit.',
			'automation.error.noWorkspace' => 'Nenhum workspace selecionado.',
			'automation.error.fileOutsideWorkspace' => 'O arquivo está fora das raízes do workspace.',
			'automation.error.fileUnreadable' => ({required Object detail}) => 'Não foi possível ler o arquivo: ${detail}',
			'automation.error.binaryFile' => 'Não é possível gerar mensagem de commit para um arquivo binário.',
			'automation.error.noFileChanges' => 'Não há mudanças a descrever neste arquivo.',
			'automation.error.noStagedChanges' => 'Não há mudanças no stage a descrever.',
			'automation.error.multipleRepositories' => 'As mudanças no stage pertencem a repositórios diferentes. Gere uma de cada vez.',
			'automation.error.diffUnavailable' => 'Não foi possível ler o diff.',
			'automation.error.notConfigured' => 'Configure um harness de mensagem de commit em Configurações.',
			'fileOperation.error.alreadyExists' => ({required Object name}) => 'Já existe: “${name}”.',
			'fileOperation.error.notFound' => ({required Object name}) => 'Não encontrado: “${name}”.',
			'fileOperation.error.invalidPath' => 'Caminho inválido.',
			'fileOperation.error.emptyName' => 'O nome não pode ficar vazio.',
			'fileOperation.error.noWorkspace' => 'Nenhum workspace selecionado.',
			'fileOperation.error.cannotMoveIntoItself' => 'Não é possível mover uma pasta para dentro dela mesma.',
			'fileOperation.error.clipboardEmpty' => 'A área de transferência está vazia.',
			'fileOperation.error.notScratchTab' => 'Esta aba não é um arquivo temporário.',
			'fileOperation.error.writeFailed' => 'Não foi possível gravar o arquivo.',
			'fileOperation.error.formatterEmptyCommand' => 'Comando de formatação vazio.',
			'fileOperation.error.formatterMissingPlaceholder' => 'O comando de formatação precisa incluir o placeholder %FILE%.',
			'fileOperation.error.formatterTimeout' => 'O formatador excedeu o tempo limite.',
			'fileOperation.error.formatterExitCode' => ({required Object code}) => 'O formatador saiu com código ${code}.',
			'fileOperation.error.formatterFailed' => 'Não foi possível executar o formatador.',
			'fileOperation.error.osFailure' => ({required Object detail}) => '${detail}',
			'fileOperation.error.nameHasSlash' => 'O nome não pode conter “/”.',
			'fileOperation.error.invalidName' => 'Nome inválido.',
			'theme.error.io' => 'Não foi possível ler ou gravar o arquivo do tema.',
			'theme.error.ioDetail' => ({required Object detail}) => 'Não foi possível ler ou gravar o arquivo do tema: ${detail}',
			'theme.error.malformedJson' => ({required Object detail}) => 'Este arquivo não é um JSON válido: ${detail}',
			'theme.error.invalidTheme' => 'Este arquivo não é um tema válido.',
			'theme.error.reservedId' => 'Este tema usa o id de um tema nativo. Mude o "id" no arquivo e importe de novo.',
			'theme.error.notAnObject' => ({required Object field}) => 'Esperava um objeto em "${field}".',
			'theme.error.missingField' => ({required Object field}) => 'Falta o campo obrigatório "${field}".',
			'theme.error.badColor' => ({required Object value, required Object field}) => '"${value}" em "${field}" não é uma cor. Use #RGB, #RRGGBB ou #RRGGBBAA.',
			'theme.error.unknownBase' => ({required Object value}) => 'Tema base "${value}" desconhecido em "extends".',
			'theme.error.noVariants' => 'O tema não declara nenhum variant. Adicione "dark", "light" ou os dois em "variants".',
			_ => null,
		};
	}
}
