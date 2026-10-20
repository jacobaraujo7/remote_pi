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
class TranslationsZh extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsZh({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zh,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsZh _root = this; // ignore: unused_field

	@override 
	TranslationsZh $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsZh(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$core$zh core = _Translations$core$zh._(_root);
	@override late final _Translations$common$zh common = _Translations$common$zh._(_root);
	@override late final _Translations$cockpit$zh cockpit = _Translations$cockpit$zh._(_root);
	@override late final _Translations$settings$zh settings = _Translations$settings$zh._(_root);
	@override late final _Translations$automation$zh automation = _Translations$automation$zh._(_root);
	@override late final _Translations$fileOperation$zh fileOperation = _Translations$fileOperation$zh._(_root);
	@override late final _Translations$theme$zh theme = _Translations$theme$zh._(_root);
}

// Path: core
class _Translations$core$zh extends Translations$core$en {
	_Translations$core$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$core$bootstrapError$zh bootstrapError = _Translations$core$bootstrapError$zh._(_root);
	@override late final _Translations$core$macosNotifications$zh macosNotifications = _Translations$core$macosNotifications$zh._(_root);
	@override late final _Translations$core$appErrorView$zh appErrorView = _Translations$core$appErrorView$zh._(_root);
	@override late final _Translations$core$errorReportDialog$zh errorReportDialog = _Translations$core$errorReportDialog$zh._(_root);
	@override late final _Translations$core$windowControls$zh windowControls = _Translations$core$windowControls$zh._(_root);
	@override late final _Translations$core$crash$zh crash = _Translations$core$crash$zh._(_root);
	@override late final _Translations$core$menu$zh menu = _Translations$core$menu$zh._(_root);
}

// Path: common
class _Translations$common$zh extends Translations$common$en {
	_Translations$common$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get cancel => '取消';
	@override String get confirm => '确认';
	@override String get create => '创建';
	@override String get gotIt => '知道了';
	@override String get save => '保存';
	@override String get close => '关闭';
	@override String get delete => '删除';
	@override String get done => '完成';
	@override String get add => '添加';
	@override String get test => '测试';
	@override String get ok => '好';
	@override String get loading => '加载中…';
	@override String get checking => '检查中…';
	@override String get remove => '移除';
	@override String get restart => '重启';
	@override String get settings => '设置';
	@override String get send => '发送';
	@override String get open => '打开';
	@override String get dismiss => '忽略';
	@override String get report => '报告';
	@override String get copyCode => '复制代码';
	@override String get search => '搜索';
	@override String get noResults => '无结果';
}

// Path: cockpit
class _Translations$cockpit$zh extends Translations$cockpit$en {
	_Translations$cockpit$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$cockpit$confirmDialog$zh confirmDialog = _Translations$cockpit$confirmDialog$zh._(_root);
	@override late final _Translations$cockpit$neovim$zh neovim = _Translations$cockpit$neovim$zh._(_root);
	@override late final _Translations$cockpit$worktreeCreateDialog$zh worktreeCreateDialog = _Translations$cockpit$worktreeCreateDialog$zh._(_root);
	@override late final _Translations$cockpit$commitMessageDialog$zh commitMessageDialog = _Translations$cockpit$commitMessageDialog$zh._(_root);
	@override late final _Translations$cockpit$tasksPanel$zh tasksPanel = _Translations$cockpit$tasksPanel$zh._(_root);
	@override late final _Translations$cockpit$cockpitPage$zh cockpitPage = _Translations$cockpit$cockpitPage$zh._(_root);
	@override late final _Translations$cockpit$welcomeView$zh welcomeView = _Translations$cockpit$welcomeView$zh._(_root);
	@override late final _Translations$cockpit$paneView$zh paneView = _Translations$cockpit$paneView$zh._(_root);
	@override late final _Translations$cockpit$fileTreePanel$zh fileTreePanel = _Translations$cockpit$fileTreePanel$zh._(_root);
	@override late final _Translations$cockpit$fileViewer$zh fileViewer = _Translations$cockpit$fileViewer$zh._(_root);
	@override late final _Translations$cockpit$workspaceSettingsDialog$zh workspaceSettingsDialog = _Translations$cockpit$workspaceSettingsDialog$zh._(_root);
	@override late final _Translations$cockpit$realmDialogs$zh realmDialogs = _Translations$cockpit$realmDialogs$zh._(_root);
	@override late final _Translations$cockpit$dbRedisTable$zh dbRedisTable = _Translations$cockpit$dbRedisTable$zh._(_root);
	@override late final _Translations$cockpit$dbQueryView$zh dbQueryView = _Translations$cockpit$dbQueryView$zh._(_root);
	@override late final _Translations$cockpit$httpView$zh httpView = _Translations$cockpit$httpView$zh._(_root);
	@override late final _Translations$cockpit$kanbanView$zh kanbanView = _Translations$cockpit$kanbanView$zh._(_root);
	@override late final _Translations$cockpit$dbPanel$zh dbPanel = _Translations$cockpit$dbPanel$zh._(_root);
	@override late final _Translations$cockpit$dbMongoView$zh dbMongoView = _Translations$cockpit$dbMongoView$zh._(_root);
	@override late final _Translations$cockpit$dbConnectionDialog$zh dbConnectionDialog = _Translations$cockpit$dbConnectionDialog$zh._(_root);
	@override late final _Translations$cockpit$sshPrompts$zh sshPrompts = _Translations$cockpit$sshPrompts$zh._(_root);
	@override late final _Translations$cockpit$projectsRail$zh projectsRail = _Translations$cockpit$projectsRail$zh._(_root);
	@override late final _Translations$cockpit$findBar$zh findBar = _Translations$cockpit$findBar$zh._(_root);
	@override late final _Translations$cockpit$contentSearch$zh contentSearch = _Translations$cockpit$contentSearch$zh._(_root);
	@override late final _Translations$cockpit$topbar$zh topbar = _Translations$cockpit$topbar$zh._(_root);
	@override late final _Translations$cockpit$tasks$zh tasks = _Translations$cockpit$tasks$zh._(_root);
	@override late final _Translations$cockpit$notifications$zh notifications = _Translations$cockpit$notifications$zh._(_root);
	@override late final _Translations$cockpit$terminalLink$zh terminalLink = _Translations$cockpit$terminalLink$zh._(_root);
	@override late final _Translations$cockpit$terminal$zh terminal = _Translations$cockpit$terminal$zh._(_root);
	@override late final _Translations$cockpit$remoteHost$zh remoteHost = _Translations$cockpit$remoteHost$zh._(_root);
	@override late final _Translations$cockpit$browserPane$zh browserPane = _Translations$cockpit$browserPane$zh._(_root);
	@override late final _Translations$cockpit$documentWindow$zh documentWindow = _Translations$cockpit$documentWindow$zh._(_root);
	@override late final _Translations$cockpit$gallery$zh gallery = _Translations$cockpit$gallery$zh._(_root);
	@override late final _Translations$cockpit$notebook$zh notebook = _Translations$cockpit$notebook$zh._(_root);
	@override late final _Translations$cockpit$layoutPreview$zh layoutPreview = _Translations$cockpit$layoutPreview$zh._(_root);
	@override late final _Translations$cockpit$telemetry$zh telemetry = _Translations$cockpit$telemetry$zh._(_root);
	@override late final _Translations$cockpit$panelView$zh panelView = _Translations$cockpit$panelView$zh._(_root);
}

// Path: settings
class _Translations$settings$zh extends Translations$settings$en {
	_Translations$settings$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$language$zh language = _Translations$settings$language$zh._(_root);
	@override late final _Translations$settings$page$zh page = _Translations$settings$page$zh._(_root);
	@override late final _Translations$settings$remoteHosts$zh remoteHosts = _Translations$settings$remoteHosts$zh._(_root);
}

// Path: automation
class _Translations$automation$zh extends Translations$automation$en {
	_Translations$automation$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$automation$error$zh error = _Translations$automation$error$zh._(_root);
}

// Path: fileOperation
class _Translations$fileOperation$zh extends Translations$fileOperation$en {
	_Translations$fileOperation$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$fileOperation$error$zh error = _Translations$fileOperation$error$zh._(_root);
}

// Path: theme
class _Translations$theme$zh extends Translations$theme$en {
	_Translations$theme$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$theme$error$zh error = _Translations$theme$error$zh._(_root);
}

// Path: core.bootstrapError
class _Translations$core$bootstrapError$zh extends Translations$core$bootstrapError$en {
	_Translations$core$bootstrapError$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cockpit 初始化失败';
	@override String get retry => '重试';
}

// Path: core.macosNotifications
class _Translations$core$macosNotifications$zh extends Translations$core$macosNotifications$en {
	_Translations$core$macosNotifications$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '在 macOS 上启用通知';
	@override String get intro => '系统设置中当前已禁用通知。请按以下步骤启用：';
	@override String get step1 => '打开 Mac 上的系统设置。';
	@override String get step2 => '在左侧边栏中找到「通知」一节。';
	@override String get step3 => '在列表中找到并选中 Cockpit 应用。';
	@override String get step4 => '打开「允许通知」开关。';
	@override String get tip => '提示：如果列表中没有出现该应用，请关闭并重新打开它，以触发系统注册。';
	@override String get gotIt => '知道了';
}

// Path: core.appErrorView
class _Translations$core$appErrorView$zh extends Translations$core$appErrorView$en {
	_Translations$core$appErrorView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get renderFailed => '应用的这一部分渲染失败';
	@override String get details => '详细信息';
	@override String get renderErrorTitle => '渲染错误';
}

// Path: core.errorReportDialog
class _Translations$core$errorReportDialog$zh extends Translations$core$errorReportDialog$en {
	_Translations$core$errorReportDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get defaultDescription => '出错了。以下详细信息已保存到日志——你可以上报它们以便修复。';
	@override String get copyDetails => '复制详细信息';
	@override String get reportIssue => '报告问题';
}

// Path: core.windowControls
class _Translations$core$windowControls$zh extends Translations$core$windowControls$en {
	_Translations$core$windowControls$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get minimize => '最小化';
	@override String get maximize => '最大化';
	@override String get close => '关闭';
}

// Path: core.crash
class _Translations$core$crash$zh extends Translations$core$crash$en {
	_Translations$core$crash$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '意外退出';
	@override String get bannerTitle => 'Cockpit 意外关闭';
	@override String get report => '报告';
	@override String get dismiss => '忽略';
	@override String crashMessage({required Object version}) => '上一个会话（版本 ${version}）未能正常关闭。要报告吗？日志已附带，发送前你可以先查看全部内容。';
	@override String crashError({required Object startedAt, required Object pid}) => '会话开始于 ${startedAt}（pid ${pid}），未能正常关闭。';
	@override String get crashDescription => '未捕获到错误——应用被系统终止。下面的日志来自该会话，是最有用的部分。';
}

// Path: core.menu
class _Translations$core$menu$zh extends Translations$core$menu$en {
	_Translations$core$menu$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get settings => '设置…';
	@override String get checkForUpdates => '检查更新…';
	@override String get file => '文件';
	@override String get newTerminal => '新建终端';
	@override String get openWorkspace => '打开工作区';
	@override String get goToFile => '转到文件…';
	@override String get save => '保存';
	@override String get discard => '放弃';
	@override String get format => '格式化';
	@override String get view => '显示';
	@override String get toggleWorkspacePanel => '切换工作区面板';
	@override String get toggleFiles => '切换文件面板';
	@override String get splitRight => '向右拆分';
	@override String get splitDown => '向下拆分';
	@override String get focusPane => '聚焦窗格';
	@override String get focusLeft => '左侧  (⌘⌥←)';
	@override String get focusRight => '右侧  (⌘⌥→)';
	@override String get focusUp => '上方  (⌘⌥↑)';
	@override String get focusDown => '下方  (⌘⌥↓)';
	@override String get selectTab => '选择标签页';
	@override String tabN({required Object n}) => '标签页 ${n}';
	@override String get lastTab => '最后一个标签页';
	@override String get previousWorkspace => '上一个工作区';
	@override String get nextWorkspace => '下一个工作区';
	@override String get zoomIn => '放大';
	@override String get zoomOut => '缩小';
	@override String get actualSize => '实际大小';
	@override String get window => '窗口';
	@override String get quit => '退出';
	@override String get minimize => '最小化';
	@override String get zoom => '缩放';
}

// Path: cockpit.confirmDialog
class _Translations$cockpit$confirmDialog$zh extends Translations$cockpit$confirmDialog$en {
	_Translations$cockpit$confirmDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get unsavedChangesTitle => '未保存的更改';
	@override String unsavedChangesMessage({required Object fileName}) => '「${fileName}」有未保存的更改。关闭前要保存吗？';
	@override String get dontSave => '不保存';
	@override String get saveAndClose => '保存并关闭';
}

// Path: cockpit.neovim
class _Translations$cockpit$neovim$zh extends Translations$cockpit$neovim$en {
	_Translations$cockpit$neovim$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get unavailable => 'Neovim 不可用。改为在 Cockpit 中打开。';
	@override String get openFailed => '无法连接 Neovim。改为在 Cockpit 中打开。';
	@override String get unsavedTitle => 'Neovim 有未保存的缓冲区';
	@override String get unsavedMessage => 'Neovim 有已修改的缓冲区。关闭标签页并放弃这些更改？';
	@override String get closeAnyway => '仍要关闭';
}

// Path: cockpit.worktreeCreateDialog
class _Translations$cockpit$worktreeCreateDialog$zh extends Translations$cockpit$worktreeCreateDialog$en {
	_Translations$cockpit$worktreeCreateDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get forkTitle => '派生 worktree';
	@override String get createTitle => '创建 worktree';
	@override String forkSubtitle({required Object root}) => '从 ${root} 分支出来的新 worktree。';
	@override String createSubtitle({required Object root}) => '在 ${root} 中开发新功能——从当前 HEAD 新建分支。';
	@override String get namePlaceholder => 'feat/minha-feature';
	@override String get errorWhitespace => '名称中不能包含空格。';
	@override String get errorInvalidChar => '分支名称中包含无效字符。';
	@override String get errorInvalidSequence => '无效序列（如 ".."、"//"、以 "/" 开头或结尾）。';
	@override String get errorReserved => '保留位置（不要以 "-"/"." 开头，也不要以 ".lock" 结尾）。';
	@override String get errorDuplicateBranch => '同名分支已存在。';
	@override String get errorDuplicateWorktree => '同名 worktree 已存在。';
	@override String errorBranchHierarchyConflict({required Object target, required Object existing}) => '无法创建分支 \'${target}\'，因为它与现有分支 \'${existing}\' 冲突。';
	@override String get errorBranchHierarchicalConflictGeneral => '已存在层次冲突的分支。';
	@override String get fork => '派生';
	@override String get postCheckoutHint => '此仓库带有 post-checkout 钩子。';
	@override String get running => '执行中…';
	@override String get advancedSettings => '高级设置';
	@override String get copyIgnored => '复制被忽略的文件（.gitignore）';
	@override String get copyIgnoredDesc => '将 .gitignore 忽略的文件（如 .env、本地密钥）复制到新 worktree。';
	@override String get copyUntracked => '复制未跟踪的文件';
	@override String get copyUntrackedDesc => '复制尚未暂存的新文件或已修改的文件。';
	@override String get baseBranch => '基准分支';
	@override String get baseBranchDesc => '新 worktree 和分支将从这个分支创建。';
	@override String get fetchRemote => '拉取远程分支';
	@override String get fetchRemoteDesc => '在创建 worktree 前先运行 git fetch，确保基准分支已确认存在。';
	@override String get searchBranch => '搜索分支…';
	@override String get back => '返回';
}

// Path: cockpit.commitMessageDialog
class _Translations$cockpit$commitMessageDialog$zh extends Translations$cockpit$commitMessageDialog$en {
	_Translations$cockpit$commitMessageDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get commitTitle => '提交';
	@override String get stageAndCommitTitle => '暂存并提交';
	@override String scopeNote({required Object fileName}) => '仅提交「${fileName}」。';
	@override String get placeholder => 'fix: 简要说明这次更改';
	@override String get errorEmptySubject => '第一行（主题）不能为空。';
	@override String errorTooShort({required Object min}) => '主题太短（最少 ${min} 个字符）。';
	@override String errorTooLong({required Object max}) => '主题太长（最多 ${max} 个字符）。';
	@override String get errorTrailingPeriod => '主题不应以句号结尾。';
	@override String get errorControlChars => '主题包含控制字符。';
	@override String get errorBlankSecondLine => '第二行请留空（git 主题与正文的分隔行）。';
	@override String get generate => '生成提交信息';
	@override String generateWith({required Object harness}) => '使用 ${harness} 生成';
	@override String get generating => '生成中…';
	@override String get cancelGeneration => '取消生成';
}

// Path: cockpit.tasksPanel
class _Translations$cockpit$tasksPanel$zh extends Translations$cockpit$tasksPanel$en {
	_Translations$cockpit$tasksPanel$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get reloadTasksTooltip => '重新加载任务';
	@override String get restartTooltip => '重启';
	@override String get stopTooltip => '停止';
	@override String get runTooltip => '运行';
	@override String sendsKeyTooltip({required Object label, required Object key}) => '${label}（发送 \'${key}\'）';
	@override String get startingTooltip => '启动中…';
	@override String get stoppingTooltip => '正在停止…';
	@override String get switchProfileTooltip => '切换配置';
	@override String get moreKeysTooltip => '更多按键';
	@override String get sectionTasks => '任务';
	@override String get noTasks => '在此项目中未检测到任务。';
	@override String get createTasksJson => '创建 tasks.json';
	@override String get generateComposeTasks => '生成 Compose 任务';
	@override String get selectComposeEngine => '选择 Compose 引擎';
	@override String get noComposeEngine => '未找到 Docker Compose 或 Podman Compose。';
	@override String get invalidComposeFile => '当前文件不是包含服务的有效 Compose 文件。';
	@override String get invalidTasksJson => 'tasks.json 无效。未写入任何更改。';
	@override String composeConflicts({required Object labels}) => '保留了与 Compose 标签冲突的非 Compose 任务：${labels}';
}

// Path: cockpit.cockpitPage
class _Translations$cockpit$cockpitPage$zh extends Translations$cockpit$cockpitPage$en {
	_Translations$cockpit$cockpitPage$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get chooseProjectFolderDialogTitle => '选择项目文件夹';
	@override String get chooseWorkspaceFolderDialogTitle => '选择工作区文件夹';
	@override String get workspaceRenamedTitle => '工作区已重命名';
	@override String workspaceRenamedMessage({required Object name}) => '新名称「${name}」只会在重启工作区或应用后才发送给智能体。';
	@override String syncTitle({required Object label}) => '同步 — ${label}';
	@override String pullTitle({required Object label}) => '拉取 — ${label}';
	@override String pushTitle({required Object label}) => '推送 — ${label}';
	@override String updateFromParentTitle({required Object name}) => '从父级更新 — ${name}';
	@override String mergeToParentTitle({required Object name}) => '合并到父级 — ${name}';
	@override String get worktreeMergedAndRemoved => 'worktree 已合并并移除。';
	@override String get nothingWasChanged => '没有任何更改。';
	@override String get newRealmTitle => '新建领域';
	@override String get closeWorkspaceTitle => '关闭工作区';
	@override String closeWorkspaceMessage({required Object name}) => '关闭「${name}」？此工作区中的智能体将被终止。磁盘上的文件夹会保留。';
	@override String get closeAction => '关闭';
	@override String get removeWorktreeTitle => '移除 worktree';
	@override String removeWorktreeMessage({required Object name, required Object warn}) => '移除「${name}」？worktree 文件夹和分支将被删除，此派生中的智能体将被终止。${warn}';
	@override String removeWorktreeWarning({required Object name}) => '\n\n警告：分支「${name}」尚未合并——移除它（git branch -D）会丢弃未合并的工作。';
	@override String get failedToRemoveWorktreeTitle => '移除 worktree 失败';
	@override String get openLayoutTitle => '打开布局';
	@override String get replaceLayoutTitle => '替换当前布局？';
	@override String replaceLayoutMessage({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '将关闭 1 个标签页，其中有正在运行的进程。',
		other: '将关闭 ${n} 个标签页，其中有正在运行的进程。',
	);
	@override String get replaceLayoutConfirm => '替换';
	@override String get restartServerTooltip => '重启服务器';
	@override String get noLspAvailable => '无可用 LSP';
	@override String get lspRunning => '运行中';
	@override String get lspStopped => '已停止';
}

// Path: cockpit.welcomeView
class _Translations$cockpit$welcomeView$zh extends Translations$cockpit$welcomeView$en {
	_Translations$cockpit$welcomeView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '欢迎使用 Cockpit';
	@override String get subtitle => '打开一个文件夹或连接到远程主机即可开始。';
	@override String get createWorkspace => '创建工作区';
	@override String get openLocalFolder => '打开本地文件夹';
	@override String get connectHost => '连接主机';
	@override String get configureHost => '配置主机';
	@override String get addWorkspace => '添加工作区';
}

// Path: cockpit.paneView
class _Translations$cockpit$paneView$zh extends Translations$cockpit$paneView$en {
	_Translations$cockpit$paneView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get closePaneTitle => '关闭窗格？';
	@override String closePaneMessage({required Object count}) => '这将关闭此窗格中的全部 ${count} 个标签页，并终止其中的智能体/终端。';
	@override String get close => '关闭';
	@override String get closeOtherTabs => '关闭其他标签页';
	@override String get closeTabsToTheRight => '关闭右侧标签页';
	@override String get closeAllTabs => '关闭全部';
	@override String get closeTabsTitle => '关闭标签页？';
	@override String closeTabsMessage({required Object count}) => '这将关闭 ${count} 个标签页，并终止其中的智能体/终端。';
	@override String get allTabs => '全部标签页';
	@override String get pinTab => '固定标签页';
	@override String get openInNewWindow => '在新窗口中打开';
	@override String get rename => '重命名';
	@override String get openAsMarkdown => '以 Markdown 打开';
	@override String get openAsBoard => '以看板打开';
	@override String get resetTitle => '重置标题';
	@override String get copyId => '复制 ID';
	@override String get restartTab => '重启';
	@override String get newTab => '新建标签页';
	@override String get newTerminal => '新建终端…';
	@override String get splitRight => '向右拆分';
	@override String get splitDown => '向下拆分';
	@override String get closePane => '关闭窗格';
	@override String get dropHereToMove => '拖放到此处以移动标签页';
	@override String get dockAsTab => '停靠为标签页';
	@override String get openBrowser => '打开浏览器';
	@override String get openTerminal => '打开终端';
	@override String get openAsLayout => '以布局打开';
	@override String get openAsYaml => '以 YAML 打开';
	@override String get openAsPanel => '以面板打开';
	@override String get openAsHtml => '以 HTML 打开';
}

// Path: cockpit.fileTreePanel
class _Translations$cockpit$fileTreePanel$zh extends Translations$cockpit$fileTreePanel$en {
	_Translations$cockpit$fileTreePanel$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get viewDiff => '查看差异';
	@override String get commit => '提交';
	@override String get stageAndCommit => '暂存并提交';
	@override String get unstage => '取消暂存';
	@override String get stageChanges => '暂存更改';
	@override String get discardChanges => '放弃更改';
	@override String get enterCommitMessage => '请输入提交信息。';
	@override String get commitUnavailable => '此工作区无法提交。';
	@override String get gitErrorTitle => 'Git 错误';
	@override String get deleteNewFileTitle => '删除新文件？';
	@override String get discardChangesTitle => '放弃更改？';
	@override String deleteNewFileMessage({required Object name}) => '「${name}」是新文件，无法恢复。要删除吗？';
	@override String discardOneMessage({required Object name}) => '放弃「${name}」中的全部更改？已删除的文件将被恢复。';
	@override String get discard => '放弃';
	@override String get deleteAllNewFilesTitle => '删除全部新文件？';
	@override String allNewFilesMessage({required Object count}) => '全部 ${count} 个文件都是新文件，将被删除。此操作无法撤销。';
	@override String discardTrackedMessage({required Object count, required Object extra}) => '放弃 ${count} 个已跟踪文件中的更改？${extra}';
	@override String discardTrackedExtra({required Object count}) => ' ${count} 个新文件将被保留。';
	@override String get deleteAll => '全部删除';
	@override String get deleteQuestionTitle => '删除？';
	@override String moveToTrash({required Object name}) => '将「${name}」移到废纸篓？';
	@override String permanentlyDelete({required Object name}) => '永久删除「${name}」？此操作无法撤销。';
	@override String get couldNotDeleteTitle => '无法删除';
	@override String get moveQuestionTitle => '移动？';
	@override String moveMessage({required Object name, required Object dest}) => '将「${name}」移动到「${dest}」？';
	@override String get moveAction => '移动';
	@override String get couldNotMoveTitle => '无法移动';
	@override String get couldNotPasteTitle => '无法粘贴';
	@override String get filesTooltip => '文件';
	@override String get searchTooltip => '搜索';
	@override String get sourceControlTooltip => '源代码管理';
	@override String get databaseTooltip => '数据库';
	@override String get sectionFiles => '文件';
	@override String get newFile => '新建文件';
	@override String get newFolder => '新建文件夹';
	@override String get refreshTooltip => '刷新';
	@override String get collapseAll => '折叠全部文件夹';
	@override String get sectionSourceControl => '源代码管理';
	@override String get viewAsList => '以列表查看';
	@override String get viewAsTree => '以树状查看';
	@override String get noFolderMessage => '没有文件夹——请打开一个工作区。';
	@override String get amend => '修补';
	@override String get commitMessagePlaceholder => '提交信息';
	@override String get amendCommit => '修补提交';
	@override String get lastCommit => '上次提交';
	@override String get openInFinder => '在 Finder 中打开';
	@override String get openInExplorer => '在资源管理器中打开';
	@override String get openInFileManager => '在文件管理器中打开';
	@override String get open => '打开';
	@override String get openWith => '打开方式';
	@override String get openInNewWindow => '在新窗口中打开';
	@override String get openLayout => '打开布局';
	@override String get openAsMarkdown => '以 Markdown 打开';
	@override String get showGitDiff => '显示 git 差异';
	@override String get createTerminal => '打开终端';
	@override String get rename => '重命名';
	@override String get copy => '复制';
	@override String get cut => '剪切';
	@override String get paste => '粘贴';
	@override String get copyRelativePath => '复制相对路径';
	@override String get copyAbsolutePath => '复制绝对路径';
	@override String get renameFailed => '重命名失败。';
	@override String get noChanges => '没有更改。';
	@override String stagedChangesHeader({required Object count}) => '已暂存的更改（${count}）';
	@override String changesHeader({required Object count}) => '更改（${count}）';
	@override String get discardAllChanges => '放弃全部更改';
	@override String get unstageAllChanges => '全部取消暂存';
	@override String get stageAllChanges => '全部暂存';
	@override String get discardFolderChanges => '放弃文件夹更改';
	@override String get unstageFolderChanges => '取消暂存文件夹更改';
	@override String get stageFolderChanges => '暂存文件夹更改';
	@override String get generateCommitMessage => '生成提交信息';
	@override String generateWith({required Object harness}) => '使用 ${harness} 生成';
	@override String get generateUnavailableWhileAmending => '修补提交时不可用';
	@override String get cancelGeneration => '取消生成';
	@override String get changes => '更改';
	@override String get history => '历史';
	@override String get historyRepository => '仓库';
	@override String get historyNoRepository => '没有可用的 Git 仓库。';
	@override String get historyEmpty => '未找到提交。';
	@override String get historyLoadFailed => '无法加载 Git 历史。';
	@override String get historyUntitledCommit => '无标题提交';
	@override String get historyNow => '刚刚';
	@override String historyMinutesAgo({required Object count}) => '${count} 分钟前';
	@override String historyHoursAgo({required Object count}) => '${count} 小时前';
	@override String get historyYesterday => '昨天';
	@override String get historyDayAgo => '1 天前';
	@override String historyDaysAgo({required Object count}) => '${count} 天前';
	@override String get historyFiles => '已更改的文件';
	@override String get historyFilesEmpty => '没有文件更改。';
	@override String get historyFilesLoadFailed => '无法加载已更改的文件。';
	@override String get diffEmptyTree => '空树';
	@override String diffOriginal({required Object ref}) => '原始 ${ref}';
	@override String diffModified({required Object ref}) => '修改后 ${ref}';
	@override String get diffWorkingTree => '工作树';
	@override String get diffBinaryFile => '二进制文件——没有文本差异。';
	@override String get diffNoChanges => '没有更改。';
	@override String diffError({required Object detail}) => '无法读取差异：${detail}';
	@override String get galleryTooltip => '画廊';
	@override String get sectionGallery => '画廊';
	@override String get openAsHtml => '以 HTML 打开';
	@override String get importQuestionTitle => '复制到此处？';
	@override String importMessage({required Object count, required Object dest}) => '将 ${count} 项复制到「${dest}」？';
	@override String get importAction => '复制';
	@override String get couldNotImportTitle => '无法复制';
	@override String openInAgent({required Object harness}) => '在 ${harness} 中打开';
}

// Path: cockpit.fileViewer
class _Translations$cockpit$fileViewer$zh extends Translations$cockpit$fileViewer$en {
	_Translations$cockpit$fileViewer$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get cantOpen => '无法打开此文件。';
	@override String get couldNotLoadImage => '无法加载图片。';
	@override String get preview => '预览';
	@override String get source => '源代码';
	@override String get reload => '重新加载';
}

// Path: cockpit.workspaceSettingsDialog
class _Translations$cockpit$workspaceSettingsDialog$zh extends Translations$cockpit$workspaceSettingsDialog$en {
	_Translations$cockpit$workspaceSettingsDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get choosePhotoTitle => '选择工作区照片';
	@override String get title => '工作区设置';
	@override String get namePlaceholder => '工作区名称';
	@override String get addPhoto => '添加照片';
	@override String get changePhoto => '更换照片';
	@override String get remove => '移除';
	@override String get color => '颜色';
	@override String get host => '主机';
	@override String get folder => '文件夹';
}

// Path: cockpit.realmDialogs
class _Translations$cockpit$realmDialogs$zh extends Translations$cockpit$realmDialogs$en {
	_Translations$cockpit$realmDialogs$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get namePlaceholder => '领域名称';
	@override String get duplicateName => '同名领域已存在。';
	@override String get newRealmTitle => '新建领域';
	@override String get renameRealmTitle => '重命名领域';
	@override String get rename => '重命名';
	@override String get deleteRealmTitle => '删除领域';
	@override String deleteMessage({required Object name, required Object suffix}) => '删除「${name}」？不会删除任何工作区——只是更改文件夹列表。${suffix}';
	@override String get deleteSuffixOne => ' 其工作区将移动到 Default。';
	@override String deleteSuffixMany({required Object count}) => ' 其 ${count} 个工作区将移动到 Default。';
	@override String get manageRealmsTitle => '管理领域';
	@override String workspaceCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 个工作区',
		other: '${n} 个工作区',
	);
}

// Path: cockpit.dbRedisTable
class _Translations$cockpit$dbRedisTable$zh extends Translations$cockpit$dbRedisTable$en {
	_Translations$cockpit$dbRedisTable$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get deleteKeyTitle => '删除键';
	@override String deleteKeyMessage({required Object key}) => '从此 Redis 数据库中删除「${key}」？';
	@override String get refresh => '刷新';
	@override String get newKey => '新建键';
	@override String get columnKey => '键';
	@override String get columnValue => '值';
	@override String get columnType => '类型';
	@override String get columnTtl => 'TTL';
	@override String keyCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 个键',
		other: '${n} 个键',
	);
	@override String get noKeys => '此数据库中没有键。';
	@override String noKeysMatch({required Object pattern}) => '没有匹配「${pattern}」的键。';
	@override String get loadMore => '加载更多';
	@override String get loadingFullValue => '正在加载完整值…';
	@override String get ttlMustBeNumber => 'TTL 必须是秒数。';
	@override String get addKey => '添加键';
	@override String get keyFieldHint => '键';
	@override String get ttlFieldHint => 'ttl（秒，可选）';
	@override String get valueFieldHint => '值';
	@override String get searchHint => '搜索——模式，如 user:*';
}

// Path: cockpit.dbQueryView
class _Translations$cockpit$dbQueryView$zh extends Translations$cockpit$dbQueryView$en {
	_Translations$cockpit$dbQueryView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get saveQueryAs => '查询另存为';
	@override String get couldNotSave => '无法保存';
	@override String get selectDatabase => '选择数据库';
	@override String get noSqlConnections => '没有 SQL 连接';
	@override String get running => '运行中…';
	@override String get runSelection => '运行选中部分';
	@override String get run => '运行';
	@override String get pickDatabaseHint => '先在上方选择数据库，然后运行（⌘↵）。';
	@override String get runQueryHint => '运行查询（⌘↵）后结果将显示在这里。';
	@override String get noRows => '没有行。';
	@override String rowsAffected({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '影响 1 行',
		other: '影响 ${n} 行',
	);
	@override String rowsFooter({required Object n}) => '${n} 行';
	@override String get truncatedSuffix => ' · 已截断（调高 -- limit）';
	@override String get table => '表格';
	@override String get json => 'JSON';
	@override String get unsaved => '未保存';
	@override String get saved => '已保存';
	@override String get copied => '已复制';
	@override String get copy => '复制';
}

// Path: cockpit.httpView
class _Translations$cockpit$httpView$zh extends Translations$cockpit$httpView$en {
	_Translations$cockpit$httpView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get saveRequestAs => '请求另存为';
	@override String get couldNotSave => '无法保存';
	@override String get run => '运行';
	@override String get running => '运行中…';
	@override String get noRequests => '此文件中没有请求——写一个，如 GET https://example.com';
	@override String get selectRequest => '选择请求';
	@override String requestCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 个请求',
		other: '${n} 个请求',
	);
	@override String get runHint => '运行请求（⌘↵）后响应将显示在这里。';
	@override String get emptyBody => '响应体为空。';
	@override String get body => 'JSON';
	@override String get headers => '标头';
	@override String get raw => '文本';
	@override String get truncatedSuffix => ' · 已截断（响应过大）';
	@override late final _Translations$cockpit$httpView$error$zh error = _Translations$cockpit$httpView$error$zh._(_root);
}

// Path: cockpit.kanbanView
class _Translations$cockpit$kanbanView$zh extends Translations$cockpit$kanbanView$en {
	_Translations$cockpit$kanbanView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get filter => '筛选';
	@override String get filterTitlePlaceholder => '搜索标题';
	@override String get filterLabels => '标签';
	@override String get filterClear => '清除';
	@override String get filterDependencies => '依赖';
	@override String get filterBlocked => '被阻塞';
	@override String get filterReady => '就绪';
	@override String get blockedBy => '被…阻塞';
	@override String get addBlocker => '添加阻塞卡片';
	@override String get searchCards => '搜索卡片';
	@override String get unknownCard => '未知';
	@override String get boardView => '看板';
	@override String get listView => '列表';
	@override String get refresh => '从磁盘刷新';
	@override String get manageLabels => '标签';
	@override String get labelsTitle => '此看板中的标签';
	@override String get labelNamePlaceholder => '标签名称';
	@override String labelUsage({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 张卡片',
		other: '${n} 张卡片',
	);
	@override String get deleteLabel => '删除标签';
	@override String get newCard => '新建卡片';
	@override String get newCardTitle => '新建卡片';
	@override String get newColumn => '新建列';
	@override String get columnNameTitle => '列名称';
	@override String get dragColumn => '拖动列';
	@override String get columnOptions => '列选项';
	@override String get renameColumn => '重命名列';
	@override String get moveColumnLeft => '左移';
	@override String get moveColumnRight => '右移';
	@override String get deleteColumn => '删除列';
	@override String get newCardHere => '在此新建卡片';
	@override String get duplicateCard => '复制';
	@override String get cardLabels => '标签';
	@override String get deleteCard => '删除卡片';
	@override String get advance => '移到下一列';
	@override String get advanceHold => '移到下一列（长按：移到最后一列）';
	@override String get advanceBack => '移回上一列';
	@override String get emptyColumn => '没有卡片';
	@override String cardCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 张卡片',
		other: '${n} 张卡片',
	);
	@override String get notes => '备注';
	@override String get notesPlaceholder => '写个备注';
	@override String get comments => '评论';
	@override String get addComment => '添加评论';
	@override String get commentPlaceholder => '写条评论';
	@override String get noComments => '暂无评论';
	@override String get closeDetail => '关闭';
	@override String get notABoard => '此文件还没有 ## 列——将以 Markdown 打开。';
	@override String get startBoard => '创建看板';
	@override String get couldNotSave => '无法保存看板';
	@override String get unrecognizedBlock => '解析器无法识别——只能整体拖动，不支持内联编辑。';
	@override late final _Translations$cockpit$kanbanView$deleteColumnDialog$zh deleteColumnDialog = _Translations$cockpit$kanbanView$deleteColumnDialog$zh._(_root);
}

// Path: cockpit.dbPanel
class _Translations$cockpit$dbPanel$zh extends Translations$cockpit$dbPanel$en {
	_Translations$cockpit$dbPanel$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionDatabase => '数据库';
	@override String get edit => '编辑…';
	@override String get copyName => '复制名称';
	@override String get newQuery => '新建查询';
	@override String get browseKeys => '浏览键';
	@override String get deleteConnectionTitle => '删除连接';
	@override String deleteConnectionMessage({required Object name}) => '从此工作区移除「${name}」？已保存的密码将被丢弃。引用它的 .dbq 文件不受影响。';
	@override String footer({required Object n}) => '.cockpit/databases.json · ${n} 个连接';
	@override String get footerOne => '.cockpit/databases.json · 1 个连接';
	@override String get noConnections => '还没有连接。';
	@override String get passwordRequired => '在主机上未找到密码。请打开此连接并重新输入——密码保存在运行数据库的那台机器上，而不是这台。';
}

// Path: cockpit.dbMongoView
class _Translations$cockpit$dbMongoView$zh extends Translations$cockpit$dbMongoView$en {
	_Translations$cockpit$dbMongoView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get deleteDocumentTitle => '删除文档';
	@override String deleteDocumentMessage({required Object collection, required Object id}) => '从「${collection}」中删除 _id 为 ${id} 的文档？';
	@override String get filterHint => '筛选——JSON，如 {"status": "active"}';
	@override String docCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 个文档',
		other: '${n} 个文档',
	);
	@override String get refresh => '刷新';
	@override String get insertDocument => '插入文档';
	@override String get noDocuments => '此集合中没有文档。';
	@override String get noDocumentsMatch => '没有符合此筛选条件的文档。';
	@override String get loadMore => '加载更多';
	@override String get edit => '编辑';
	@override String get insert => '插入';
}

// Path: cockpit.dbConnectionDialog
class _Translations$cockpit$dbConnectionDialog$zh extends Translations$cockpit$dbConnectionDialog$en {
	_Translations$cockpit$dbConnectionDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get chooseFileTitle => '选择 SQLite 数据库';
	@override String get file => '文件';
	@override String get chooseFilePlaceholder => '选择一个 SQLite 文件…';
	@override String get name => '名称';
	@override String get password => '密码';
	@override String get savePassword => '保存密码';
	@override String get allowWrites => '允许写入（智能体）';
	@override String get allowWritesHint => '关闭 = 智能体只能通过 CLI 读取';
	@override String get visibleToAgents => '对智能体可见';
	@override String get visibleToAgentsHint => '关闭 = 对 CLI 隐藏，仅在 GUI 中可用';
	@override String get testing => '正在测试连接…';
	@override String get connectionOk => '连接正常';
	@override String get connectionFailed => '连接失败';
	@override String get editTitle => '编辑连接';
	@override String get newTitle => '新建连接';
	@override String get connectionString => '连接字符串';
	@override String get invalidUrl => '不是有效的连接 URL。';
	@override String get sshTunnel => 'SSH 隧道';
	@override String get sshHost => 'SSH 主机';
	@override String get sshPort => 'SSH 端口';
	@override String get sshUser => 'SSH 用户';
	@override String get privateKey => '私钥';
	@override String get choosePrivateKeyPlaceholder => '选择一个私钥…';
	@override String get choosePrivateKeyDialogTitle => '选择 SSH 私钥';
	@override String get keyPassphrase => '密钥口令';
	@override String get savePassphrase => '保存口令';
	@override String get passwordOnHost => '密码保存在主机上，而不是这台机器上。';
}

// Path: cockpit.sshPrompts
class _Translations$cockpit$sshPrompts$zh extends Translations$cockpit$sshPrompts$en {
	_Translations$cockpit$sshPrompts$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get unknownSshHostTitle => '未知的 SSH 主机';
	@override String neverConnected({required Object endpoint}) => 'Cockpit 从未连接过 ${endpoint}。';
	@override String get trustHint => '仅当此指纹与服务器匹配时才信任。你可以在服务器上用以下命令核对：';
	@override String get trust => '信任';
	@override String get sshKeyPassphraseTitle => 'SSH 密钥口令';
	@override String unlockMessage({required Object keyPath, required Object connectionName}) => '解锁 ${keyPath} 以连接「${connectionName}」。';
	@override String get keptInMemoryHint => '口令在 Cockpit 退出前保留在内存中。要让智能体使用此连接，请在连接设置中启用「保存口令」。';
	@override String get unlock => '解锁';
}

// Path: cockpit.projectsRail
class _Translations$cockpit$projectsRail$zh extends Translations$cockpit$projectsRail$en {
	_Translations$cockpit$projectsRail$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get workspaces => '工作区';
	@override String get keepAwakeOn => '正在保持此电脑唤醒以便远程访问。点击可让它重新睡眠。';
	@override String get keepAwakeOff => '保持此电脑唤醒以便远程访问。Cockpit 重启后自动关闭。';
	@override String get keepAwakeBattery => '正在用电池供电并保持唤醒。这会消耗电量。';
	@override String get keepAwakeLid => '合上笔记本盖子仍会使其睡眠。';
	@override String get newWorkspace => '新建工作区';
	@override String get settings => '设置';
	@override String get mergeToParent => '合并到父级';
	@override String get updateFromParent => '从父级更新';
	@override String get forkWorktree => '派生 worktree';
	@override String get copyBranch => '复制分支';
	@override String get remove => '移除';
	@override String get moveToRealm => '移动到领域';
	@override String get copyWorkspaceId => '复制工作区 ID';
	@override String get rename => '重命名';
	@override String get close => '关闭';
	@override String get newRealm => '新建领域…';
	@override String get manageRealms => '管理领域…';
	@override String get noWorkspaces => '还没有工作区。';
	@override String get sync => '同步';
	@override String get pull => '拉取';
	@override String get push => '推送';
	@override String get createWorktree => '创建 worktree';
	@override String worktreeCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n,
		one: '1 个 worktree',
		other: '${n} 个 worktree',
	);
	@override String get expandWorktrees => '展开 worktree';
	@override String get collapseWorktrees => '折叠 worktree';
}

// Path: cockpit.findBar
class _Translations$cockpit$findBar$zh extends Translations$cockpit$findBar$en {
	_Translations$cockpit$findBar$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get find => '查找';
	@override String get matchCase => '区分大小写';
	@override String get wholeWord => '全字匹配';
	@override String get useRegex => '使用正则表达式';
	@override String get previous => '上一个 (⇧⏎)';
	@override String get next => '下一个 (⏎)';
	@override String get close => '关闭 (Esc)';
	@override String get badPattern => '无效的模式';
	@override String counter({required Object current, required Object total}) => '第 ${current} 个，共 ${total} 个';
	@override String get noResults => '无结果';
}

// Path: cockpit.contentSearch
class _Translations$cockpit$contentSearch$zh extends Translations$cockpit$contentSearch$en {
	_Translations$cockpit$contentSearch$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionSearch => '搜索';
	@override String get searchInFiles => '在文件中搜索';
	@override String get matchCase => '区分大小写';
	@override String get wholeWord => '全字匹配';
	@override String get useRegex => '使用正则表达式';
	@override String get invalidRegex => '无效的正则表达式。';
	@override String get typeToSearch => '输入以在文件中搜索。';
	@override String get searching => '搜索中…';
	@override String get noResults => '无结果。';
}

// Path: cockpit.topbar
class _Translations$cockpit$topbar$zh extends Translations$cockpit$topbar$en {
	_Translations$cockpit$topbar$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get collapseSidebar => '折叠侧边栏';
	@override String get toggleFiles => '显示/隐藏文件';
	@override String get filesUnavailable => 'Cockpit 中文件功能不可用';
	@override String get hideKeyboard => '隐藏键盘';
}

// Path: cockpit.tasks
class _Translations$cockpit$tasks$zh extends Translations$cockpit$tasks$en {
	_Translations$cockpit$tasks$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get hotReload => '热重载';
	@override String get hotRestart => '热重启';
	@override String get toggleDebugPaint => '切换调试绘制';
	@override String get togglePlatform => '切换平台';
	@override String get quit => '退出';
}

// Path: cockpit.notifications
class _Translations$cockpit$notifications$zh extends Translations$cockpit$notifications$en {
	_Translations$cockpit$notifications$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get agentFinished => '智能体已完成';
	@override String get open => '打开';
	@override String get agentNeedsAction => '智能体需要你的输入';
}

// Path: cockpit.terminalLink
class _Translations$cockpit$terminalLink$zh extends Translations$cockpit$terminalLink$en {
	_Translations$cockpit$terminalLink$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get open => '打开';
	@override String get revealFinder => '在 Finder 中显示';
	@override String get revealExplorer => '在资源管理器中显示';
	@override String get revealFolder => '打开所在文件夹';
	@override String get copyPath => '复制路径';
	@override String get openLink => '打开链接';
	@override String get copyLink => '复制链接';
}

// Path: cockpit.terminal
class _Translations$cockpit$terminal$zh extends Translations$cockpit$terminal$en {
	_Translations$cockpit$terminal$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String cwdFallbackWarning({required Object requested, required Object path}) => '警告：文件夹「${requested}」不存在。此终端在「${path}」中打开。';
	@override String workspaceEnvTracked({required Object keys}) => '注意：.env.cockpit 被 git 跟踪（它随仓库一起提供）。已注入：${keys}';
}

// Path: cockpit.remoteHost
class _Translations$cockpit$remoteHost$zh extends Translations$cockpit$remoteHost$en {
	_Translations$cockpit$remoteHost$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get addHost => '添加远程主机';
	@override String get hostName => '名称';
	@override String get sshTarget => 'SSH 目标（user@host）';
	@override String connecting({required Object host}) => '正在连接 ${host}…';
	@override String get openingTunnel => 'SSH 隧道';
	@override String get installingServer => '正在安装服务器';
	@override String handshake({required Object version}) => '服务器 ${version}';
	@override String get loadingWorkspace => '正在加载工作区…';
	@override String reconnecting({required Object host}) => '正在重新连接 ${host}…';
	@override String offline({required Object host}) => '${host} 离线';
	@override String get remove => '移除';
	@override String get reconnect => '重新连接';
	@override String get installServer => '安装服务器';
	@override String errSshUnreachable({required Object host}) => '无法通过 SSH 连到 ${host}。它开机了吗？远程登录是否已启用？';
	@override String errInstallFailed({required Object host}) => '无法在 ${host} 上安装服务器。';
	@override String get errVersionMismatch => '服务器版本不兼容；请更新。';
	@override String errDetail({required Object detail}) => '详细信息：${detail}';
	@override String pickFolderTitle({required Object host}) => '在 ${host} 上打开文件夹';
	@override String get openHere => '在此打开';
	@override String get emptyFolder => '没有子文件夹';
	@override String get newLocal => '本地';
	@override String get newRemote => '远程';
	@override String get chooseHost => '选择主机';
	@override String get newHostEntry => '新建主机…';
	@override String get editHost => '编辑主机';
	@override String get userLabel => '用户名';
	@override String get hostLabel => '主机 / IP';
	@override String get portLabel => '端口';
	@override String get authLabel => '身份验证';
	@override String get authKey => 'SSH 密钥';
	@override String get authPassword => '密码';
	@override String get passwordLabel => '密码';
	@override String get passwordKeep => '留空则保留当前密码';
	@override String get errUser => '需要用户名';
	@override String get errHost => '需要主机';
	@override String get errPassword => '需要密码';
	@override String get identityChoose => '选择…';
	@override String get identityEmpty => '未选择密钥';
	@override String get identityDialogTitle => '选择 SSH 私钥';
	@override String get errIdentity => '请选择用于身份验证的私钥。';
	@override String errHostKeyUnknown({required Object host}) => 'Cockpit 尚不信任 ${host}。请再次连接并确认指纹。';
	@override String errHostKeyChanged({required Object host}) => '${host} 提供的 SSH 密钥与已存储的不一致。如果你没有重装那台机器，请停下来检查——否则从 ~/.ssh/known_hosts 中删除旧条目。';
	@override String errHostBundleMissing({required Object host}) => '${host} 是 Windows，但没有安装 Cockpit。远程服务器是从该机器上已有的 Cockpit 套件安装的，请先在那边安装 Cockpit 再试。';
	@override String errHostUnknownOs({required Object host}) => '无法识别 ${host} 的操作系统。该账户可能使用了受限 shell，或根本没有 shell。';
	@override String get errIdentityPublic => '这里只有公钥。仅当私钥在你的 SSH agent 中时才能使用；否则请选择对应的私钥文件（同名，不带 .pub）。';
	@override String get errIdentityNotKey => '该文件看起来不是私钥。';
	@override String get errIdentityMissingFile => '该文件已不存在。';
	@override String get errIdentityUnreadable => '该文件无法读取。';
}

// Path: cockpit.browserPane
class _Translations$cockpit$browserPane$zh extends Translations$cockpit$browserPane$en {
	_Translations$cockpit$browserPane$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get back => '后退';
	@override String get forward => '前进';
	@override String get reload => '重新加载';
	@override String get urlHint => '输入 URL 或地址';
	@override String get go => '前往';
}

// Path: cockpit.documentWindow
class _Translations$cockpit$documentWindow$zh extends Translations$cockpit$documentWindow$en {
	_Translations$cockpit$documentWindow$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get mediaNotSupported => '音频和视频将在 Cockpit 主窗口中打开。';
	@override String fileNotFound({required Object path}) => '未找到文件：${path}';
}

// Path: cockpit.gallery
class _Translations$cockpit$gallery$zh extends Translations$cockpit$gallery$en {
	_Translations$cockpit$gallery$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get intro => 'Cockpit 的特殊文档，让你直观地看到 AI 智能体在做什么。';
	@override String get createErrorTitle => '无法创建文件';
	@override late final _Translations$cockpit$gallery$dbQuery$zh dbQuery = _Translations$cockpit$gallery$dbQuery$zh._(_root);
	@override late final _Translations$cockpit$gallery$kanban$zh kanban = _Translations$cockpit$gallery$kanban$zh._(_root);
	@override late final _Translations$cockpit$gallery$layout$zh layout = _Translations$cockpit$gallery$layout$zh._(_root);
	@override late final _Translations$cockpit$gallery$httpRequest$zh httpRequest = _Translations$cockpit$gallery$httpRequest$zh._(_root);
	@override late final _Translations$cockpit$gallery$html$zh html = _Translations$cockpit$gallery$html$zh._(_root);
	@override late final _Translations$cockpit$gallery$tasks$zh tasks = _Translations$cockpit$gallery$tasks$zh._(_root);
	@override late final _Translations$cockpit$gallery$notebook$zh notebook = _Translations$cockpit$gallery$notebook$zh._(_root);
	@override late final _Translations$cockpit$gallery$workspaceEnv$zh workspaceEnv = _Translations$cockpit$gallery$workspaceEnv$zh._(_root);
	@override late final _Translations$cockpit$gallery$panel$zh panel = _Translations$cockpit$gallery$panel$zh._(_root);
}

// Path: cockpit.notebook
class _Translations$cockpit$notebook$zh extends Translations$cockpit$notebook$en {
	_Translations$cockpit$notebook$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get notes => '笔记';
	@override String get newNote => '新建笔记';
	@override String get searchPlaceholder => '搜索笔记';
	@override String get empty => '还没有笔记。创建一个，或让智能体在这里写。';
	@override String get noMatch => '没有匹配的笔记。';
	@override String get selectNote => '选择笔记';
	@override String get reload => '从磁盘重新加载';
	@override String get untagged => '无标签';
	@override String get saveFailed => '无法保存笔记';
	@override String get createFailed => '无法创建笔记';
	@override String get addTag => '添加标签';
	@override String get untitled => '无标题';
	@override String get deleteNote => '删除笔记';
	@override String deleteConfirm({required Object name}) => '将「${name}」移到废纸篓？';
	@override String get imageFailed => '无法保存图片';
	@override late final _Translations$cockpit$notebook$format$zh format = _Translations$cockpit$notebook$format$zh._(_root);
	@override String get backlinks => '被链接自';
	@override String get renameTag => '重命名标签';
	@override String get deleteTag => '删除标签';
	@override String deleteTagConfirm({required Object count, required Object name}) => '从 ${count} 条笔记中移除「${name}」？笔记本身会保留。';
	@override String get showList => '显示笔记列表';
	@override String get hideList => '隐藏笔记列表';
}

// Path: cockpit.layoutPreview
class _Translations$cockpit$layoutPreview$zh extends Translations$cockpit$layoutPreview$en {
	_Translations$cockpit$layoutPreview$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get applyFailedTitle => '无法应用布局';
	@override String get applyInCockpit => '在 Cockpit 中应用';
	@override String get applyNewWorkspace => '作为新工作区打开';
	@override String applyTo({required Object workspace}) => '应用到 ${workspace}';
	@override String get autorunWorktree => 'autorun: worktree。当你创建持有它的 worktree 时，此布局也会自动应用。';
	@override String get command => '命令';
	@override String get folder => '文件夹';
	@override String get noCommand => '无命令，打开 shell';
	@override String get replaceConfirm => '替换布局';
	@override String replaceMessage({required Object n}) => '${n} 个此工作区已打开的标签页将被关闭，包括正在运行的工作。';
	@override String replaceTitle({required Object workspace}) => '替换 ${workspace} 的布局？';
	@override String get skippedTitle => '未在此系统上创建';
	@override String get splitDown => '向下拆分';
	@override String get splitRight => '向右拆分';
	@override String get splitTab => '标签页';
	@override String subtitle({required Object n}) => '此布局将打开 ${n} 个终端。应用前请先阅读命令。';
}

// Path: cockpit.telemetry
class _Translations$cockpit$telemetry$zh extends Translations$cockpit$telemetry$en {
	_Translations$cockpit$telemetry$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get tooltip => '遥测';
	@override String get title => '遥测';
	@override String liveRuns({required Object n}) => '${n} 个进行中';
	@override String get noWorkspace => '打开一个工作区以查看其遥测。';
	@override String get empty => '这里还没有内容。';
	@override String get emptyFiltered => '这里还没有内容。';
	@override String get searchHint => '筛选案例';
	@override String get chipOpen => '待处理';
	@override String get chipNew => '新';
	@override String get chipResolved => '已解决';
	@override String get chipIgnored => '已忽略';
	@override String get chipWarnings => '警告';
	@override String get tagNew => '新';
	@override String get tagRegression => '回归';
	@override String get tagResolved => '已解决';
	@override String get tagIgnored => '已忽略';
	@override String get srcTask => '任务';
	@override String get srcWrapper => 'cockpit telemetry';
	@override String run({required Object id}) => '运行 ${id}';
	@override String get resolve => '标记为已解决';
	@override String get ignore => '忽略（智能体也不再看到）';
	@override String get reopen => '重新打开';
	@override String get clear => '清除出现记录';
	@override String get clearRun => '清除此运行';
	@override String get clearProject => '清除项目';
	@override String openFile({required Object location}) => '打开 ${location}';
	@override String get showInTerminal => '在终端中显示';
	@override String get copyCommand => '复制 CLI 命令';
	@override String get copied => '已复制';
	@override String get statusOpen => '待处理';
	@override String get statusResolved => '已解决';
	@override String get statusIgnored => '已忽略';
	@override String get occurrences => '出现记录';
	@override String inRuns({required Object n}) => '在 ${n} 次运行中';
	@override String get first => '首次';
	@override String get last => '最近';
	@override String get origin => '来源';
	@override String get sectionStack => '调用栈';
	@override String get stackHint => '项目帧已高亮 · 点击打开文件';
	@override String get sectionCorrelated => '关联日志';
	@override String get correlatedHint => '错误之前最近的 JSON 日志，同一次运行';
	@override String get none => '无';
	@override String get sectionRuns => '按运行统计的出现记录';
	@override String get runsHint => '相同键（cwd、命令）：新增和回归据此判定';
	@override String get sectionContext => '原始上下文';
	@override String get contextHint => '最后一次出现前后的终端行';
	@override String get current => '当前';
	@override String fingerprintHint({required Object location}) => '指纹 = 类型 + 规范化的消息 + ${location}';
	@override String get blameUncommitted => '在工作树中已更改';
	@override String blameCommit({required Object ago, required Object sha}) => '更改于 ${ago}（${sha}）';
	@override String get justNow => '刚刚';
	@override String minutesAgo({required Object n}) => '${n} 分钟前';
	@override String hoursAgo({required Object n}) => '${n} 小时前';
	@override String daysAgo({required Object n}) => '${n} 天前';
	@override String get resolvedToast => '已解决。如果在之后的运行中再次出现，将重新显示为回归。';
	@override String get ignoredToast => '已忽略。智能体不再看到它（除非 --include-ignored）。';
	@override String get clearedToast => '出现记录已删除。分类规则保留。';
	@override String get byHuman => '由你操作';
	@override String get byAgent => '由智能体操作';
	@override String caseTabTitle({required Object type, required Object file}) => '${type} · ${file}';
	@override String get srcApp => '应用';
	@override String get chipApp => 'Cockpit';
}

// Path: cockpit.panelView
class _Translations$cockpit$panelView$zh extends Translations$cockpit$panelView$en {
	_Translations$cockpit$panelView$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get unavailable => '面板需要内嵌 web 视图，目前在 Linux 上尚不可用。';
	@override String get openInBrowser => '在浏览器中打开';
	@override String get openAsHtml => '以 HTML 打开';
}

// Path: settings.language
class _Translations$settings$language$zh extends Translations$settings$language$en {
	_Translations$settings$language$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '语言';
	@override String get system => '跟随系统';
	@override String get english => 'English';
	@override String get portugueseBr => 'Português (BR)';
	@override String get spanish => 'Español';
}

// Path: settings.page
class _Translations$settings$page$zh extends Translations$settings$page$en {
	_Translations$settings$page$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$page$header$zh header = _Translations$settings$page$header$zh._(_root);
	@override late final _Translations$settings$page$nav$zh nav = _Translations$settings$page$nav$zh._(_root);
	@override late final _Translations$settings$page$general$zh general = _Translations$settings$page$general$zh._(_root);
	@override late final _Translations$settings$page$diagnostics$zh diagnostics = _Translations$settings$page$diagnostics$zh._(_root);
	@override late final _Translations$settings$page$storage$zh storage = _Translations$settings$page$storage$zh._(_root);
	@override late final _Translations$settings$page$terminal$zh terminal = _Translations$settings$page$terminal$zh._(_root);
	@override late final _Translations$settings$page$appearance$zh appearance = _Translations$settings$page$appearance$zh._(_root);
	@override late final _Translations$settings$page$notifications$zh notifications = _Translations$settings$page$notifications$zh._(_root);
	@override late final _Translations$settings$page$shortcuts$zh shortcuts = _Translations$settings$page$shortcuts$zh._(_root);
	@override late final _Translations$settings$page$languages$zh languages = _Translations$settings$page$languages$zh._(_root);
	@override late final _Translations$settings$page$automations$zh automations = _Translations$settings$page$automations$zh._(_root);
}

// Path: settings.remoteHosts
class _Translations$settings$remoteHosts$zh extends Translations$settings$remoteHosts$en {
	_Translations$settings$remoteHosts$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '远程主机';
	@override String get description => '通过 SSH 访问的机器。在这里添加主机与从工作区「+」菜单添加效果相同。';
	@override String get empty => '还没有远程主机。';
	@override String get add => '添加主机';
	@override String get edit => '编辑';
	@override String get reconnect => '重新连接';
	@override String get remove => '移除';
	@override String get removeTitle => '移除主机';
	@override String removeMessage({required Object name}) => '移除「${name}」及其全部工作区？主机本身不会删除任何内容。';
	@override String workspacesCount({required Object count}) => '${count} 个工作区';
	@override String get deviceKeyTitle => '本设备的密钥';
	@override String get deviceKeyDesc => '将此公钥添加到主机的 ~/.ssh/authorized_keys，本设备即可连接。';
	@override String get deviceKeyCopy => '复制公钥';
	@override String get deviceKeyCopied => '公钥已复制';
	@override String get statusConnected => '已连接';
	@override String get statusConnecting => '连接中…';
	@override String get statusReconnecting => '重新连接中…';
	@override String get statusOffline => '离线';
	@override String get statusIdle => '未连接';
	@override String get helpTitle => '工作原理';
	@override String get helpBody => 'Cockpit 通过 SSH 连接到你的机器，并与一个小型服务器通信，由它运行终端、文件和 git。主机必须安装并运行 Cockpit（桌面版）或 cockpit-server，并将本设备的公钥添加到其 ~/.ssh/authorized_keys。';
}

// Path: automation.error
class _Translations$automation$error$zh extends Translations$automation$error$en {
	_Translations$automation$error$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String unavailable({required Object harness}) => '${harness} 未安装或不在 PATH 中。';
	@override String modelUnavailable({required Object model, required Object harness}) => '模型「${model}」在 ${harness} 中不可用。请在设置中选择其他模型。';
	@override String authentication({required Object harness, required Object detail}) => '${harness}：${detail}';
	@override String timeout({required Object harness, required Object seconds}) => '${harness} 在 ${seconds} 秒内未响应。';
	@override String get cancelled => '提交信息生成已取消。';
	@override String process({required Object harness, required Object detail}) => '${harness}：${detail}';
	@override String processNoDetail({required Object harness}) => '${harness} 无法生成提交信息。';
	@override String get invalidResponse => '自动化返回了空的提交信息。';
	@override String get busy => '已有提交信息正在生成。';
	@override String get unknown => '自动化无法生成提交信息。';
	@override String get noWorkspace => '未选择工作区。';
	@override String get fileOutsideWorkspace => '文件在工作区根目录之外。';
	@override String fileUnreadable({required Object detail}) => '无法读取文件：${detail}';
	@override String get binaryFile => '无法为二进制文件生成提交信息。';
	@override String get noFileChanges => '此文件没有可描述的更改。';
	@override String get noStagedChanges => '没有已暂存的更改可描述。';
	@override String get multipleRepositories => '已暂存的更改属于多个仓库。请分别生成。';
	@override String get diffUnavailable => '无法读取差异。';
	@override String get notConfigured => '请在设置中配置提交信息工具。';
}

// Path: fileOperation.error
class _Translations$fileOperation$error$zh extends Translations$fileOperation$error$en {
	_Translations$fileOperation$error$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String alreadyExists({required Object name}) => '已存在：「${name}」。';
	@override String notFound({required Object name}) => '未找到：「${name}」。';
	@override String get invalidPath => '无效的路径。';
	@override String get emptyName => '名称不能为空。';
	@override String get noWorkspace => '未选择工作区。';
	@override String get cannotMoveIntoItself => '无法将文件夹移动到其自身内部。';
	@override String get clipboardEmpty => '剪贴板为空。';
	@override String get notScratchTab => '此标签页不是草稿文件。';
	@override String get writeFailed => '无法写入文件。';
	@override String get formatterEmptyCommand => '格式化器命令为空。';
	@override String get formatterMissingPlaceholder => '格式化器命令必须包含 %FILE% 占位符。';
	@override String get formatterTimeout => '格式化器超时。';
	@override String formatterExitCode({required Object code}) => '格式化器以退出码 ${code} 结束。';
	@override String get formatterFailed => '格式化器无法运行。';
	@override String osFailure({required Object detail}) => '${detail}';
	@override String get nameHasSlash => '名称不能包含「/」。';
	@override String get invalidName => '无效的名称。';
	@override String get remoteDropUnsupported => '尚不支持将文件拖放到远程工作区。';
}

// Path: theme.error
class _Translations$theme$error$zh extends Translations$theme$error$en {
	_Translations$theme$error$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get io => '无法读取或写入主题文件。';
	@override String ioDetail({required Object detail}) => '无法读取或写入主题文件：${detail}';
	@override String malformedJson({required Object detail}) => '此文件不是有效的 JSON：${detail}';
	@override String get invalidTheme => '此文件不是有效的主题。';
	@override String get reservedId => '此主题使用了内置主题的 id。请修改文件中的「id」后重新导入。';
	@override String notAnObject({required Object field}) => '「${field}」处应为对象。';
	@override String missingField({required Object field}) => '缺少必需字段「${field}」。';
	@override String badColor({required Object field, required Object value}) => '「${field}」处的「${value}」不是颜色。请使用 #RGB、#RRGGBB 或 #RRGGBBAA。';
	@override String unknownBase({required Object value}) => '「extends」中的基础主题「${value}」未知。';
	@override String get noVariants => '主题未声明任何变体。请在「variants」下添加「dark」「light」或两者。';
}

// Path: cockpit.httpView.error
class _Translations$cockpit$httpView$error$zh extends Translations$cockpit$httpView$error$en {
	_Translations$cockpit$httpView$error$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '请求失败';
	@override String get noRequest => '光标处未找到请求。';
	@override String invalidUrl({required Object url}) => '无效的 URL：${url}';
	@override String unresolvedVariable({required Object name}) => '变量 {{${name}}} 没有值。请在此文件中用 @${name} = … 声明。';
	@override String bodyFileMissing({required Object path}) => '未找到请求体文件：${path}';
	@override String bodyFileUnreadable({required Object path, required Object detail}) => '无法读取请求体文件 ${path}：${detail}';
	@override String connectionFailed({required Object detail}) => '无法连接服务器：${detail}';
	@override String get connectionFailedNoDetail => '无法连接服务器。';
	@override String timeout({required Object seconds}) => '请求在 ${seconds} 秒后超时。';
	@override String responseTooLarge({required Object bytes}) => '响应超过了 ${bytes} 字节的限制。';
}

// Path: cockpit.kanbanView.deleteColumnDialog
class _Translations$cockpit$kanbanView$deleteColumnDialog$zh extends Translations$cockpit$kanbanView$deleteColumnDialog$en {
	_Translations$cockpit$kanbanView$deleteColumnDialog$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String title({required Object name}) => '删除「${name}」？';
	@override String message({required Object count}) => '此列有 ${count}。请选择它们的去向。';
	@override String get moveCards => '移到上一列';
	@override String get deleteAll => '随列一起删除';
	@override String get emptyMessage => '此列为空。';
}

// Path: cockpit.gallery.dbQuery
class _Translations$cockpit$gallery$dbQuery$zh extends Translations$cockpit$gallery$dbQuery$en {
	_Translations$cockpit$gallery$dbQuery$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '数据库查询';
	@override String get description => 'SQL 编辑器，带结果表格，使用已注册的连接之一。';
}

// Path: cockpit.gallery.kanban
class _Translations$cockpit$gallery$kanban$zh extends Translations$cockpit$gallery$kanban$en {
	_Translations$cockpit$gallery$kanban$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '看板';
	@override String get description => '以纯 Markdown 存储的列和卡片。可拖动、编辑和评论。';
}

// Path: cockpit.gallery.layout
class _Translations$cockpit$gallery$layout$zh extends Translations$cockpit$gallery$layout$en {
	_Translations$cockpit$gallery$layout$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '窗格布局';
	@override String get description => '一键打开的终端和拆分，类似 tmuxinator。可在新建 worktree 时自动运行。';
}

// Path: cockpit.gallery.httpRequest
class _Translations$cockpit$gallery$httpRequest$zh extends Translations$cockpit$gallery$httpRequest$en {
	_Translations$cockpit$gallery$httpRequest$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => 'HTTP 请求';
	@override String get description => '把请求写在文件里运行，响应显示在旁边。';
}

// Path: cockpit.gallery.html
class _Translations$cockpit$gallery$html$zh extends Translations$cockpit$gallery$html$en {
	_Translations$cockpit$gallery$html$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => 'HTML 视图';
	@override String get description => '由智能体编写、Cockpit 直接渲染的页面：思维导图、图表、图形，随你所需。';
}

// Path: cockpit.gallery.tasks
class _Translations$cockpit$gallery$tasks$zh extends Translations$cockpit$gallery$tasks$en {
	_Translations$cockpit$gallery$tasks$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '任务';
	@override String get description => '从任务面板运行的命令，如开发服务器、测试和构建。存储在 .cockpit/tasks.json。';
}

// Path: cockpit.gallery.notebook
class _Translations$cockpit$gallery$notebook$zh extends Translations$cockpit$gallery$notebook$en {
	_Translations$cockpit$gallery$notebook$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '笔记本';
	@override String get description => '带标签的简短笔记文件夹。智能体写，你来读和编辑。也可在 Obsidian 中打开。';
}

// Path: cockpit.gallery.workspaceEnv
class _Translations$cockpit$gallery$workspaceEnv$zh extends Translations$cockpit$gallery$workspaceEnv$en {
	_Translations$cockpit$gallery$workspaceEnv$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '工作区环境变量';
	@override String get description => '注入此工作区每个终端的变量。API 令牌或登录凭据放这里，不要粘贴到智能体的提示里。不会进入 git。';
}

// Path: cockpit.gallery.panel
class _Translations$cockpit$gallery$panel$zh extends Translations$cockpit$gallery$panel$en {
	_Translations$cockpit$gallery$panel$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '面板';
	@override String get description => '带应用桥接的 HTML 页面：它的按钮可在这台机器上运行 Cockpit CLI 和 shell 命令。快速做仪表盘的游乐场。';
}

// Path: cockpit.notebook.format
class _Translations$cockpit$notebook$format$zh extends Translations$cockpit$notebook$format$en {
	_Translations$cockpit$notebook$format$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get bold => '粗体 (⌘B)';
	@override String get italic => '斜体 (⌘I)';
	@override String get strike => '删除线';
	@override String get heading1 => '标题 1';
	@override String get heading2 => '标题 2';
	@override String get heading3 => '标题 3';
	@override String get bullets => '无序列表';
	@override String get numbered => '有序列表';
	@override String get checklist => '任务列表';
	@override String get quote => '引用';
	@override String get code => '行内代码 (⌘E)';
	@override String get codeBlock => '代码块';
	@override String get link => '链接 (⌘K)';
	@override String get rule => '分隔线';
	@override String get noteLink => '链接到笔记（[[…]]）';
	@override String get noteLinkSearch => '搜索笔记';
	@override String get image => '插入图片…';
}

// Path: settings.page.header
class _Translations$settings$page$header$zh extends Translations$settings$page$header$en {
	_Translations$settings$page$header$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get back => '返回';
	@override String get title => '设置';
}

// Path: settings.page.nav
class _Translations$settings$page$nav$zh extends Translations$settings$page$nav$en {
	_Translations$settings$page$nav$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get general => '通用';
	@override String get appearance => '外观';
	@override String get terminal => '终端';
	@override String get language => '语言';
	@override String get shortcuts => '快捷键';
	@override String get notifications => '通知';
	@override String get automations => '自动化';
	@override String get remoteHosts => '远程主机';
}

// Path: settings.page.general
class _Translations$settings$page$general$zh extends Translations$settings$page$general$en {
	_Translations$settings$page$general$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionEditor => '编辑器';
	@override String get editorEngineTitle => '引擎';
	@override String get editorEngineCockpit => 'Cockpit（默认）';
	@override String get editorEngineNeovim => 'Neovim';
	@override String get neovimChecking => '正在查找 Neovim…';
	@override String get neovimNotFound => '在你的 shell PATH 中未找到 Neovim。';
	@override String get neovimRefresh => '重新检查';
	@override String get showCockpitTitle => '显示 Cockpit 终端';
	@override String get showCockpitDesc => '在侧栏顶部固定一个无路径、纯终端的工作区。关闭后它的终端也会关闭。';
	@override String get launchAtStartupTitle => '登录时启动';
	@override String get launchAtStartupDesc => '登录电脑时自动启动 Cockpit。';
	@override String get sectionUpdates => '更新';
	@override String get checkUpdatesTitle => '检查更新';
	@override String get checkUpdatesDesc => 'Cockpit 检查新版本的频率。';
	@override late final _Translations$settings$page$general$updateFrequency$zh updateFrequency = _Translations$settings$page$general$updateFrequency$zh._(_root);
	@override String get developerModeTitle => '开发者模式';
	@override String get developerModeDesc => '将 Cockpit 自身的错误和警告记录到单独的遥测存储（「Cockpit」标签）中，并启用性能指标。只对维护此应用的人有用。';
}

// Path: settings.page.diagnostics
class _Translations$settings$page$diagnostics$zh extends Translations$settings$page$diagnostics$en {
	_Translations$settings$page$diagnostics$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '诊断';
	@override String get logFileTitle => '日志文件';
	@override String logFileDesc({required Object days, required Object path}) => '错误和启动事件记录在这里，保留 ${days} 天。\n${path}';
	@override String get unavailable => '不可用';
	@override String get reveal => '显示';
	@override String get reportTitle => '报告问题';
	@override String get reportDesc => '打开一个预填了你的版本、操作系统和最近日志的 issue。不会自动发送——你先审阅。';
	@override String get reportButton => '报告…';
	@override String get reportDialogTitle => '问题报告';
	@override String get reportDialogError => '从设置中手动报告。';
	@override String get reportDialogDescription => '在 issue 中描述出了什么问题。最近的日志包含在下方和「复制详细信息」中。';
}

// Path: settings.page.storage
class _Translations$settings$page$storage$zh extends Translations$settings$page$storage$en {
	_Translations$settings$page$storage$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '存储';
	@override String get locationTitle => '存储位置';
	@override String locationDesc({required Object root}) => 'Cockpit 把项目、布局和设置保存在这里。指向一个同步文件夹即可备份。\n${root}';
	@override String get useDefault => '使用默认位置';
	@override String get working => '处理中…';
	@override String get change => '更改…';
	@override String get resetTitle => '重置 Cockpit';
	@override String get resetDesc => '删除全部本地数据——项目、布局、设置和终端历史——并恢复到默认位置。';
	@override String get resetButton => '重置…';
	@override String get resetConfirm => '重置';
	@override String get resetDialogTitle => '重置 Cockpit？';
	@override String get resetDialogContent => '这将永久删除所有本地 Cockpit 数据——项目、布局、设置和终端历史。此操作无法撤销。Cockpit 将关闭，以便你重新开始。';
	@override String get restartRequiredTitle => '需要重启';
	@override String restartChangeFolderMessage({required Object path}) => 'Cockpit 将从下次启动起使用此文件夹：\n${path}';
	@override String get restartUseDefaultMessage => 'Cockpit 将从下次启动起使用系统默认位置。自定义文件夹中的数据保持不变。';
	@override String get restartResetMessage => '所有 Cockpit 数据已清除。重启以重新开始。';
	@override String get later => '稍后';
	@override String get quitCockpit => '退出 Cockpit';
	@override String get chooseFolderDialogTitle => '选择 Cockpit 数据文件夹';
}

// Path: settings.page.terminal
class _Translations$settings$page$terminal$zh extends Translations$settings$page$terminal$en {
	_Translations$settings$page$terminal$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionDefaultTerminal => '默认终端';
	@override String get engineTitle => '引擎';
	@override String get engineDesc => '供新的终端标签页和任务输出缓冲区使用。已打开的标签页保持当前引擎。';
	@override String get shellTitle => 'Shell';
	@override String get shellDesc => '新建终端标签页打开的 shell。「+」旁的箭头仍可为单个标签页打开任意其他 shell。';
	@override String get noWslMessage => '未找到 WSL 发行版。安装一个（wsl.exe --install）并重启 Cockpit 后，它会出现在这里。';
	@override String get sectionBehavior => '行为';
	@override String get closeOnExitTitle => 'shell 退出时关闭标签页';
	@override String get closeOnExitDesc => '当 shell 自行结束（exit、Ctrl-D）时，关闭其标签页，而不是留下一个失效的终端。';
}

// Path: settings.page.appearance
class _Translations$settings$page$appearance$zh extends Translations$settings$page$appearance$en {
	_Translations$settings$page$appearance$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionTheme => '主题';
	@override String get themeTitle => '主题';
	@override String get themeDesc => '应用颜色、代码高亮和终端配色。';
	@override String get modeTitle => '模式';
	@override String get modeDesc => '使用主题的哪个变体。';
	@override String modeOnlyDark({required Object theme}) => '「${theme}」只有深色变体，此项不生效。';
	@override String modeOnlyLight({required Object theme}) => '「${theme}」只有浅色变体，此项不生效。';
	@override String get themeFileTitle => '主题文件';
	@override String get themeFileDesc => '从 JSON 文件导入主题，或导出当前主题。';
	@override String get previewCode => '代码';
	@override String get previewTerminal => '终端';
	@override String get themeSystem => '跟随系统';
	@override String get themeLight => '浅色';
	@override String get themeDark => '深色';
	@override String get sectionFonts => '字体';
	@override String get interfaceFontTitle => '界面字体';
	@override String get interfaceFontDesc => '整个应用通用。留空 = 系统默认。';
	@override String get interfaceSizeTitle => '界面字号';
	@override String get codeFontTitle => '代码字体';
	@override String get codeFontDesc => '用于代码和差异。留空 = 系统默认。';
	@override String get codeSizeTitle => '代码字号';
	@override String get terminalFontTitle => '终端字体';
	@override String get terminalFontDesc => '仅用于终端。留空 = 系统默认。';
	@override String get terminalSizeTitle => '终端字号';
	@override String get terminalSizeDesc => '关闭 = 跟随代码字号。';
	@override String get terminalSizeInherit => '跟随代码字号';
	@override String get terminalWeightTitle => '终端字重';
	@override String get terminalWeightDesc => '低密度屏幕渲染笔画偏粗。Auto 会在那种屏幕上减淡，Retina 屏则不受影响。';
	@override String get terminalWeightAuto => '自动（按屏幕）';
	@override String get terminalWeightLight => '细';
	@override String get terminalWeightNormal => '常规';
	@override String get terminalWeightMedium => '中等';
	@override String get terminalWeightSemiBold => '半粗';
	@override String get sectionConversation => '对话';
	@override String get pinUserMessageTitle => '固定用户消息';
	@override String get pinUserMessageDesc => '回答滚动时，问题固定在顶部。';
	@override String get importTheme => '导入…';
	@override String get exportTheme => '导出…';
	@override String get deleteTheme => '移除';
	@override String get importThemeDialog => '选择主题文件';
	@override String get exportThemeDialog => '主题另存为';
	@override String themeImported({required Object name}) => '主题「${name}」已导入。';
	@override String get themeExported => '主题已保存。';
	@override String get themeDeleted => '主题已移除。';
	@override String get fontPickerTitle => '选择字体';
	@override String get fontPickerSearch => '搜索字体';
	@override String get fontPickerEmpty => '这台机器上没有匹配的字体。';
	@override String get fontPickerBundled => '内置';
	@override String get fontPickerCustom => '列表里没有？输入确切的字体族名称。';
	@override String get fontPickerCustomHint => '字体族名称';
	@override String get fontPickerUse => '使用';
	@override String get fontPickerDefault => '默认';
	@override String get fontMissing => '这台机器上未找到——使用回退字体。';
	@override String get sectionLayout => '布局';
	@override String get swapPanelsTitle => '交换侧边面板';
	@override String get swapPanelsDesc => '将工作区放到右侧，文件、搜索、git 和数据库放到左侧。';
}

// Path: settings.page.notifications
class _Translations$settings$page$notifications$zh extends Translations$settings$page$notifications$en {
	_Translations$settings$page$notifications$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '通知';
	@override String get enableTitle => '启用通知';
	@override String get enableDesc => '当智能体完成一轮对话且窗口未聚焦时提醒我。';
	@override String get systemPermissionTitle => '系统权限';
	@override String get grantedDesc => 'Cockpit 已获准发送通知。';
	@override String get notGrantedDesc => 'macOS 尚未授予通知权限。';
	@override String get granted => '已授予';
	@override String get requestPermission => '请求权限';
	@override String get soundsTitle => '声音';
	@override String get soundVolumeTitle => '音量';
	@override String get soundTurnDone => '轮次完成';
	@override String get soundTurnDoneDesc => '智能体完成了它的一轮对话。';
	@override String get soundActionRequired => '需要操作';
	@override String get soundActionRequiredDesc => '智能体正在等待你的批准或回答。';
	@override String get soundDefault => '默认';
	@override String soundCustom({required Object name}) => '自定义：${name}';
	@override String get soundChooseFile => '选择文件';
	@override String get soundReset => '恢复默认';
	@override String get soundOnActiveTab => '此标签页处于活动状态时也播放';
	@override String get soundPreview => '试听';
}

// Path: settings.page.shortcuts
class _Translations$settings$page$shortcuts$zh extends Translations$settings$page$shortcuts$en {
	_Translations$settings$page$shortcuts$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get notCustomizable => '键盘快捷键尚不支持自定义。';
}

// Path: settings.page.languages
class _Translations$settings$page$languages$zh extends Translations$settings$page$languages$en {
	_Translations$settings$page$languages$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionFormatting => '格式化';
	@override String get formatOnSaveTitle => '保存时格式化';
	@override String get formatOnSaveDesc => '保存文件（⌘S）时自动格式化。';
	@override String get sectionLanguageServers => '语言服务器';
	@override String get footerNote => '错误和格式化使用各语言的语言服务器。Cockpit 不会安装服务器——它使用你机器上已有的。● 有响应 · ○ 未找到或命令无效（请安装服务器或调整命令）。';
	@override String get serverCommandLabel => '语言服务器命令';
	@override String get formatterCommandLabel => '格式化器命令（可选）';
	@override String get formatterHint => '带 %FILE% 占位符的外部格式化器。设置后优先于 LSP 格式化器。';
	@override String get resetToDefault => '恢复默认';
	@override String get saveAndRestart => '保存并重启';
	@override String get statusResponds => '服务器有响应';
	@override String get statusNotFound => '未找到服务器或命令无效';
}

// Path: settings.page.automations
class _Translations$settings$page$automations$zh extends Translations$settings$page$automations$en {
	_Translations$settings$page$automations$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get sectionCommitMessages => '提交信息';
	@override String get harness => '工具';
	@override String get harnessDiscovering => '正在查找已安装的命令行工具…';
	@override String get harnessNoneFound => '在 PATH 中未找到受支持的工具。';
	@override String harnessConfiguredUnavailable({required Object harness}) => '${harness} 已配置但不可用。';
	@override String get harnessChoose => '选择用于生成提交信息的 CLI。';
	@override String get harnessRefresh => '刷新已安装的工具';
	@override String get notConfigured => '未配置';
	@override String get model => '模型';
	@override String get modelUnavailable => '在找到工具之前，模型列表不可用。';
	@override String get modelCliOnly => '此工具使用其 CLI 的默认模型。';
	@override String get modelCliDefault => 'CLI 默认';
	@override String get modelAuto => '自动';
	@override String modelSearch({required Object count}) => '在 ${count} 个模型中搜索…';
	@override String get modelAutoRouted => '此工具自动路由模型。';
	@override String get modelAccountOnly => '仅列出你的账户可用的模型。';
	@override String get generateFromSourceControl => '从源代码管理生成';
	@override String get generateFromSourceControlDescription => 'Cockpit 只发送选定的差异和最近的提交主题。常见凭据模式和敏感文件会在工具运行前被脱敏。';
	@override String get discoveryFailed => '无法发现已安装的自动化工具。';
	@override String staleModel({required Object model, required Object harness}) => '模型「${model}」在 ${harness} 中已不可用。改用 CLI 默认模型——如有需要，请在设置中选择其他模型。';
	@override String get recommendedSuffix => '推荐';
}

// Path: settings.page.general.updateFrequency
class _Translations$settings$page$general$updateFrequency$zh extends Translations$settings$page$general$updateFrequency$en {
	_Translations$settings$page$general$updateFrequency$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get daily => '每天';
	@override String get weekly => '每周';
	@override String get monthly => '每月';
	@override String get never => '从不';
}

/// The flat map containing all translations for locale <zh>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsZh {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'core.bootstrapError.title' => 'Cockpit 初始化失败',
			'core.bootstrapError.retry' => '重试',
			'core.macosNotifications.title' => '在 macOS 上启用通知',
			'core.macosNotifications.intro' => '系统设置中当前已禁用通知。请按以下步骤启用：',
			'core.macosNotifications.step1' => '打开 Mac 上的系统设置。',
			'core.macosNotifications.step2' => '在左侧边栏中找到「通知」一节。',
			'core.macosNotifications.step3' => '在列表中找到并选中 Cockpit 应用。',
			'core.macosNotifications.step4' => '打开「允许通知」开关。',
			'core.macosNotifications.tip' => '提示：如果列表中没有出现该应用，请关闭并重新打开它，以触发系统注册。',
			'core.macosNotifications.gotIt' => '知道了',
			'core.appErrorView.renderFailed' => '应用的这一部分渲染失败',
			'core.appErrorView.details' => '详细信息',
			'core.appErrorView.renderErrorTitle' => '渲染错误',
			'core.errorReportDialog.defaultDescription' => '出错了。以下详细信息已保存到日志——你可以上报它们以便修复。',
			'core.errorReportDialog.copyDetails' => '复制详细信息',
			'core.errorReportDialog.reportIssue' => '报告问题',
			'core.windowControls.minimize' => '最小化',
			'core.windowControls.maximize' => '最大化',
			'core.windowControls.close' => '关闭',
			'core.crash.title' => '意外退出',
			'core.crash.bannerTitle' => 'Cockpit 意外关闭',
			'core.crash.report' => '报告',
			'core.crash.dismiss' => '忽略',
			'core.crash.crashMessage' => ({required Object version}) => '上一个会话（版本 ${version}）未能正常关闭。要报告吗？日志已附带，发送前你可以先查看全部内容。',
			'core.crash.crashError' => ({required Object startedAt, required Object pid}) => '会话开始于 ${startedAt}（pid ${pid}），未能正常关闭。',
			'core.crash.crashDescription' => '未捕获到错误——应用被系统终止。下面的日志来自该会话，是最有用的部分。',
			'core.menu.settings' => '设置…',
			'core.menu.checkForUpdates' => '检查更新…',
			'core.menu.file' => '文件',
			'core.menu.newTerminal' => '新建终端',
			'core.menu.openWorkspace' => '打开工作区',
			'core.menu.goToFile' => '转到文件…',
			'core.menu.save' => '保存',
			'core.menu.discard' => '放弃',
			'core.menu.format' => '格式化',
			'core.menu.view' => '显示',
			'core.menu.toggleWorkspacePanel' => '切换工作区面板',
			'core.menu.toggleFiles' => '切换文件面板',
			'core.menu.splitRight' => '向右拆分',
			'core.menu.splitDown' => '向下拆分',
			'core.menu.focusPane' => '聚焦窗格',
			'core.menu.focusLeft' => '左侧  (⌘⌥←)',
			'core.menu.focusRight' => '右侧  (⌘⌥→)',
			'core.menu.focusUp' => '上方  (⌘⌥↑)',
			'core.menu.focusDown' => '下方  (⌘⌥↓)',
			'core.menu.selectTab' => '选择标签页',
			'core.menu.tabN' => ({required Object n}) => '标签页 ${n}',
			'core.menu.lastTab' => '最后一个标签页',
			'core.menu.previousWorkspace' => '上一个工作区',
			'core.menu.nextWorkspace' => '下一个工作区',
			'core.menu.zoomIn' => '放大',
			'core.menu.zoomOut' => '缩小',
			'core.menu.actualSize' => '实际大小',
			'core.menu.window' => '窗口',
			'core.menu.quit' => '退出',
			'core.menu.minimize' => '最小化',
			'core.menu.zoom' => '缩放',
			'common.cancel' => '取消',
			'common.confirm' => '确认',
			'common.create' => '创建',
			'common.gotIt' => '知道了',
			'common.save' => '保存',
			'common.close' => '关闭',
			'common.delete' => '删除',
			'common.done' => '完成',
			'common.add' => '添加',
			'common.test' => '测试',
			'common.ok' => '好',
			'common.loading' => '加载中…',
			'common.checking' => '检查中…',
			'common.remove' => '移除',
			'common.restart' => '重启',
			'common.settings' => '设置',
			'common.send' => '发送',
			'common.open' => '打开',
			'common.dismiss' => '忽略',
			'common.report' => '报告',
			'common.copyCode' => '复制代码',
			'common.search' => '搜索',
			'common.noResults' => '无结果',
			'cockpit.confirmDialog.unsavedChangesTitle' => '未保存的更改',
			'cockpit.confirmDialog.unsavedChangesMessage' => ({required Object fileName}) => '「${fileName}」有未保存的更改。关闭前要保存吗？',
			'cockpit.confirmDialog.dontSave' => '不保存',
			'cockpit.confirmDialog.saveAndClose' => '保存并关闭',
			'cockpit.neovim.unavailable' => 'Neovim 不可用。改为在 Cockpit 中打开。',
			'cockpit.neovim.openFailed' => '无法连接 Neovim。改为在 Cockpit 中打开。',
			'cockpit.neovim.unsavedTitle' => 'Neovim 有未保存的缓冲区',
			'cockpit.neovim.unsavedMessage' => 'Neovim 有已修改的缓冲区。关闭标签页并放弃这些更改？',
			'cockpit.neovim.closeAnyway' => '仍要关闭',
			'cockpit.worktreeCreateDialog.forkTitle' => '派生 worktree',
			'cockpit.worktreeCreateDialog.createTitle' => '创建 worktree',
			'cockpit.worktreeCreateDialog.forkSubtitle' => ({required Object root}) => '从 ${root} 分支出来的新 worktree。',
			'cockpit.worktreeCreateDialog.createSubtitle' => ({required Object root}) => '在 ${root} 中开发新功能——从当前 HEAD 新建分支。',
			'cockpit.worktreeCreateDialog.namePlaceholder' => 'feat/minha-feature',
			'cockpit.worktreeCreateDialog.errorWhitespace' => '名称中不能包含空格。',
			'cockpit.worktreeCreateDialog.errorInvalidChar' => '分支名称中包含无效字符。',
			'cockpit.worktreeCreateDialog.errorInvalidSequence' => '无效序列（如 ".."、"//"、以 "/" 开头或结尾）。',
			'cockpit.worktreeCreateDialog.errorReserved' => '保留位置（不要以 "-"/"." 开头，也不要以 ".lock" 结尾）。',
			'cockpit.worktreeCreateDialog.errorDuplicateBranch' => '同名分支已存在。',
			'cockpit.worktreeCreateDialog.errorDuplicateWorktree' => '同名 worktree 已存在。',
			'cockpit.worktreeCreateDialog.errorBranchHierarchyConflict' => ({required Object target, required Object existing}) => '无法创建分支 \'${target}\'，因为它与现有分支 \'${existing}\' 冲突。',
			'cockpit.worktreeCreateDialog.errorBranchHierarchicalConflictGeneral' => '已存在层次冲突的分支。',
			'cockpit.worktreeCreateDialog.fork' => '派生',
			'cockpit.worktreeCreateDialog.postCheckoutHint' => '此仓库带有 post-checkout 钩子。',
			'cockpit.worktreeCreateDialog.running' => '执行中…',
			'cockpit.worktreeCreateDialog.advancedSettings' => '高级设置',
			'cockpit.worktreeCreateDialog.copyIgnored' => '复制被忽略的文件（.gitignore）',
			'cockpit.worktreeCreateDialog.copyIgnoredDesc' => '将 .gitignore 忽略的文件（如 .env、本地密钥）复制到新 worktree。',
			'cockpit.worktreeCreateDialog.copyUntracked' => '复制未跟踪的文件',
			'cockpit.worktreeCreateDialog.copyUntrackedDesc' => '复制尚未暂存的新文件或已修改的文件。',
			'cockpit.worktreeCreateDialog.baseBranch' => '基准分支',
			'cockpit.worktreeCreateDialog.baseBranchDesc' => '新 worktree 和分支将从这个分支创建。',
			'cockpit.worktreeCreateDialog.fetchRemote' => '拉取远程分支',
			'cockpit.worktreeCreateDialog.fetchRemoteDesc' => '在创建 worktree 前先运行 git fetch，确保基准分支已确认存在。',
			'cockpit.worktreeCreateDialog.searchBranch' => '搜索分支…',
			'cockpit.worktreeCreateDialog.back' => '返回',
			'cockpit.commitMessageDialog.commitTitle' => '提交',
			'cockpit.commitMessageDialog.stageAndCommitTitle' => '暂存并提交',
			'cockpit.commitMessageDialog.scopeNote' => ({required Object fileName}) => '仅提交「${fileName}」。',
			'cockpit.commitMessageDialog.placeholder' => 'fix: 简要说明这次更改',
			'cockpit.commitMessageDialog.errorEmptySubject' => '第一行（主题）不能为空。',
			'cockpit.commitMessageDialog.errorTooShort' => ({required Object min}) => '主题太短（最少 ${min} 个字符）。',
			'cockpit.commitMessageDialog.errorTooLong' => ({required Object max}) => '主题太长（最多 ${max} 个字符）。',
			'cockpit.commitMessageDialog.errorTrailingPeriod' => '主题不应以句号结尾。',
			'cockpit.commitMessageDialog.errorControlChars' => '主题包含控制字符。',
			'cockpit.commitMessageDialog.errorBlankSecondLine' => '第二行请留空（git 主题与正文的分隔行）。',
			'cockpit.commitMessageDialog.generate' => '生成提交信息',
			'cockpit.commitMessageDialog.generateWith' => ({required Object harness}) => '使用 ${harness} 生成',
			'cockpit.commitMessageDialog.generating' => '生成中…',
			'cockpit.commitMessageDialog.cancelGeneration' => '取消生成',
			'cockpit.tasksPanel.reloadTasksTooltip' => '重新加载任务',
			'cockpit.tasksPanel.restartTooltip' => '重启',
			'cockpit.tasksPanel.stopTooltip' => '停止',
			'cockpit.tasksPanel.runTooltip' => '运行',
			'cockpit.tasksPanel.sendsKeyTooltip' => ({required Object label, required Object key}) => '${label}（发送 \'${key}\'）',
			'cockpit.tasksPanel.startingTooltip' => '启动中…',
			'cockpit.tasksPanel.stoppingTooltip' => '正在停止…',
			'cockpit.tasksPanel.switchProfileTooltip' => '切换配置',
			'cockpit.tasksPanel.moreKeysTooltip' => '更多按键',
			'cockpit.tasksPanel.sectionTasks' => '任务',
			'cockpit.tasksPanel.noTasks' => '在此项目中未检测到任务。',
			'cockpit.tasksPanel.createTasksJson' => '创建 tasks.json',
			'cockpit.tasksPanel.generateComposeTasks' => '生成 Compose 任务',
			'cockpit.tasksPanel.selectComposeEngine' => '选择 Compose 引擎',
			'cockpit.tasksPanel.noComposeEngine' => '未找到 Docker Compose 或 Podman Compose。',
			'cockpit.tasksPanel.invalidComposeFile' => '当前文件不是包含服务的有效 Compose 文件。',
			'cockpit.tasksPanel.invalidTasksJson' => 'tasks.json 无效。未写入任何更改。',
			'cockpit.tasksPanel.composeConflicts' => ({required Object labels}) => '保留了与 Compose 标签冲突的非 Compose 任务：${labels}',
			'cockpit.cockpitPage.chooseProjectFolderDialogTitle' => '选择项目文件夹',
			'cockpit.cockpitPage.chooseWorkspaceFolderDialogTitle' => '选择工作区文件夹',
			'cockpit.cockpitPage.workspaceRenamedTitle' => '工作区已重命名',
			'cockpit.cockpitPage.workspaceRenamedMessage' => ({required Object name}) => '新名称「${name}」只会在重启工作区或应用后才发送给智能体。',
			'cockpit.cockpitPage.syncTitle' => ({required Object label}) => '同步 — ${label}',
			'cockpit.cockpitPage.pullTitle' => ({required Object label}) => '拉取 — ${label}',
			'cockpit.cockpitPage.pushTitle' => ({required Object label}) => '推送 — ${label}',
			'cockpit.cockpitPage.updateFromParentTitle' => ({required Object name}) => '从父级更新 — ${name}',
			'cockpit.cockpitPage.mergeToParentTitle' => ({required Object name}) => '合并到父级 — ${name}',
			'cockpit.cockpitPage.worktreeMergedAndRemoved' => 'worktree 已合并并移除。',
			'cockpit.cockpitPage.nothingWasChanged' => '没有任何更改。',
			'cockpit.cockpitPage.newRealmTitle' => '新建领域',
			'cockpit.cockpitPage.closeWorkspaceTitle' => '关闭工作区',
			'cockpit.cockpitPage.closeWorkspaceMessage' => ({required Object name}) => '关闭「${name}」？此工作区中的智能体将被终止。磁盘上的文件夹会保留。',
			'cockpit.cockpitPage.closeAction' => '关闭',
			'cockpit.cockpitPage.removeWorktreeTitle' => '移除 worktree',
			'cockpit.cockpitPage.removeWorktreeMessage' => ({required Object name, required Object warn}) => '移除「${name}」？worktree 文件夹和分支将被删除，此派生中的智能体将被终止。${warn}',
			'cockpit.cockpitPage.removeWorktreeWarning' => ({required Object name}) => '\n\n警告：分支「${name}」尚未合并——移除它（git branch -D）会丢弃未合并的工作。',
			'cockpit.cockpitPage.failedToRemoveWorktreeTitle' => '移除 worktree 失败',
			'cockpit.cockpitPage.openLayoutTitle' => '打开布局',
			'cockpit.cockpitPage.replaceLayoutTitle' => '替换当前布局？',
			'cockpit.cockpitPage.replaceLayoutMessage' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '将关闭 1 个标签页，其中有正在运行的进程。', other: '将关闭 ${n} 个标签页，其中有正在运行的进程。', ), 
			'cockpit.cockpitPage.replaceLayoutConfirm' => '替换',
			'cockpit.cockpitPage.restartServerTooltip' => '重启服务器',
			'cockpit.cockpitPage.noLspAvailable' => '无可用 LSP',
			'cockpit.cockpitPage.lspRunning' => '运行中',
			'cockpit.cockpitPage.lspStopped' => '已停止',
			'cockpit.welcomeView.title' => '欢迎使用 Cockpit',
			'cockpit.welcomeView.subtitle' => '打开一个文件夹或连接到远程主机即可开始。',
			'cockpit.welcomeView.createWorkspace' => '创建工作区',
			'cockpit.welcomeView.openLocalFolder' => '打开本地文件夹',
			'cockpit.welcomeView.connectHost' => '连接主机',
			'cockpit.welcomeView.configureHost' => '配置主机',
			'cockpit.welcomeView.addWorkspace' => '添加工作区',
			'cockpit.paneView.closePaneTitle' => '关闭窗格？',
			'cockpit.paneView.closePaneMessage' => ({required Object count}) => '这将关闭此窗格中的全部 ${count} 个标签页，并终止其中的智能体/终端。',
			'cockpit.paneView.close' => '关闭',
			'cockpit.paneView.closeOtherTabs' => '关闭其他标签页',
			'cockpit.paneView.closeTabsToTheRight' => '关闭右侧标签页',
			'cockpit.paneView.closeAllTabs' => '关闭全部',
			'cockpit.paneView.closeTabsTitle' => '关闭标签页？',
			'cockpit.paneView.closeTabsMessage' => ({required Object count}) => '这将关闭 ${count} 个标签页，并终止其中的智能体/终端。',
			'cockpit.paneView.allTabs' => '全部标签页',
			'cockpit.paneView.pinTab' => '固定标签页',
			'cockpit.paneView.openInNewWindow' => '在新窗口中打开',
			'cockpit.paneView.rename' => '重命名',
			'cockpit.paneView.openAsMarkdown' => '以 Markdown 打开',
			'cockpit.paneView.openAsBoard' => '以看板打开',
			'cockpit.paneView.resetTitle' => '重置标题',
			'cockpit.paneView.copyId' => '复制 ID',
			'cockpit.paneView.restartTab' => '重启',
			'cockpit.paneView.newTab' => '新建标签页',
			'cockpit.paneView.newTerminal' => '新建终端…',
			'cockpit.paneView.splitRight' => '向右拆分',
			'cockpit.paneView.splitDown' => '向下拆分',
			'cockpit.paneView.closePane' => '关闭窗格',
			'cockpit.paneView.dropHereToMove' => '拖放到此处以移动标签页',
			'cockpit.paneView.dockAsTab' => '停靠为标签页',
			'cockpit.paneView.openBrowser' => '打开浏览器',
			'cockpit.paneView.openTerminal' => '打开终端',
			'cockpit.paneView.openAsLayout' => '以布局打开',
			'cockpit.paneView.openAsYaml' => '以 YAML 打开',
			'cockpit.paneView.openAsPanel' => '以面板打开',
			'cockpit.paneView.openAsHtml' => '以 HTML 打开',
			'cockpit.fileTreePanel.viewDiff' => '查看差异',
			'cockpit.fileTreePanel.commit' => '提交',
			'cockpit.fileTreePanel.stageAndCommit' => '暂存并提交',
			'cockpit.fileTreePanel.unstage' => '取消暂存',
			'cockpit.fileTreePanel.stageChanges' => '暂存更改',
			'cockpit.fileTreePanel.discardChanges' => '放弃更改',
			'cockpit.fileTreePanel.enterCommitMessage' => '请输入提交信息。',
			'cockpit.fileTreePanel.commitUnavailable' => '此工作区无法提交。',
			'cockpit.fileTreePanel.gitErrorTitle' => 'Git 错误',
			'cockpit.fileTreePanel.deleteNewFileTitle' => '删除新文件？',
			'cockpit.fileTreePanel.discardChangesTitle' => '放弃更改？',
			'cockpit.fileTreePanel.deleteNewFileMessage' => ({required Object name}) => '「${name}」是新文件，无法恢复。要删除吗？',
			'cockpit.fileTreePanel.discardOneMessage' => ({required Object name}) => '放弃「${name}」中的全部更改？已删除的文件将被恢复。',
			'cockpit.fileTreePanel.discard' => '放弃',
			'cockpit.fileTreePanel.deleteAllNewFilesTitle' => '删除全部新文件？',
			'cockpit.fileTreePanel.allNewFilesMessage' => ({required Object count}) => '全部 ${count} 个文件都是新文件，将被删除。此操作无法撤销。',
			'cockpit.fileTreePanel.discardTrackedMessage' => ({required Object count, required Object extra}) => '放弃 ${count} 个已跟踪文件中的更改？${extra}',
			'cockpit.fileTreePanel.discardTrackedExtra' => ({required Object count}) => ' ${count} 个新文件将被保留。',
			'cockpit.fileTreePanel.deleteAll' => '全部删除',
			'cockpit.fileTreePanel.deleteQuestionTitle' => '删除？',
			'cockpit.fileTreePanel.moveToTrash' => ({required Object name}) => '将「${name}」移到废纸篓？',
			'cockpit.fileTreePanel.permanentlyDelete' => ({required Object name}) => '永久删除「${name}」？此操作无法撤销。',
			'cockpit.fileTreePanel.couldNotDeleteTitle' => '无法删除',
			'cockpit.fileTreePanel.moveQuestionTitle' => '移动？',
			'cockpit.fileTreePanel.moveMessage' => ({required Object name, required Object dest}) => '将「${name}」移动到「${dest}」？',
			'cockpit.fileTreePanel.moveAction' => '移动',
			'cockpit.fileTreePanel.couldNotMoveTitle' => '无法移动',
			'cockpit.fileTreePanel.couldNotPasteTitle' => '无法粘贴',
			'cockpit.fileTreePanel.filesTooltip' => '文件',
			'cockpit.fileTreePanel.searchTooltip' => '搜索',
			'cockpit.fileTreePanel.sourceControlTooltip' => '源代码管理',
			'cockpit.fileTreePanel.databaseTooltip' => '数据库',
			'cockpit.fileTreePanel.sectionFiles' => '文件',
			'cockpit.fileTreePanel.newFile' => '新建文件',
			'cockpit.fileTreePanel.newFolder' => '新建文件夹',
			'cockpit.fileTreePanel.refreshTooltip' => '刷新',
			'cockpit.fileTreePanel.collapseAll' => '折叠全部文件夹',
			'cockpit.fileTreePanel.sectionSourceControl' => '源代码管理',
			'cockpit.fileTreePanel.viewAsList' => '以列表查看',
			'cockpit.fileTreePanel.viewAsTree' => '以树状查看',
			'cockpit.fileTreePanel.noFolderMessage' => '没有文件夹——请打开一个工作区。',
			'cockpit.fileTreePanel.amend' => '修补',
			'cockpit.fileTreePanel.commitMessagePlaceholder' => '提交信息',
			'cockpit.fileTreePanel.amendCommit' => '修补提交',
			'cockpit.fileTreePanel.lastCommit' => '上次提交',
			'cockpit.fileTreePanel.openInFinder' => '在 Finder 中打开',
			'cockpit.fileTreePanel.openInExplorer' => '在资源管理器中打开',
			'cockpit.fileTreePanel.openInFileManager' => '在文件管理器中打开',
			'cockpit.fileTreePanel.open' => '打开',
			'cockpit.fileTreePanel.openWith' => '打开方式',
			'cockpit.fileTreePanel.openInNewWindow' => '在新窗口中打开',
			'cockpit.fileTreePanel.openLayout' => '打开布局',
			'cockpit.fileTreePanel.openAsMarkdown' => '以 Markdown 打开',
			'cockpit.fileTreePanel.showGitDiff' => '显示 git 差异',
			'cockpit.fileTreePanel.createTerminal' => '打开终端',
			'cockpit.fileTreePanel.rename' => '重命名',
			'cockpit.fileTreePanel.copy' => '复制',
			'cockpit.fileTreePanel.cut' => '剪切',
			'cockpit.fileTreePanel.paste' => '粘贴',
			'cockpit.fileTreePanel.copyRelativePath' => '复制相对路径',
			'cockpit.fileTreePanel.copyAbsolutePath' => '复制绝对路径',
			'cockpit.fileTreePanel.renameFailed' => '重命名失败。',
			'cockpit.fileTreePanel.noChanges' => '没有更改。',
			'cockpit.fileTreePanel.stagedChangesHeader' => ({required Object count}) => '已暂存的更改（${count}）',
			'cockpit.fileTreePanel.changesHeader' => ({required Object count}) => '更改（${count}）',
			'cockpit.fileTreePanel.discardAllChanges' => '放弃全部更改',
			'cockpit.fileTreePanel.unstageAllChanges' => '全部取消暂存',
			'cockpit.fileTreePanel.stageAllChanges' => '全部暂存',
			'cockpit.fileTreePanel.discardFolderChanges' => '放弃文件夹更改',
			'cockpit.fileTreePanel.unstageFolderChanges' => '取消暂存文件夹更改',
			'cockpit.fileTreePanel.stageFolderChanges' => '暂存文件夹更改',
			'cockpit.fileTreePanel.generateCommitMessage' => '生成提交信息',
			'cockpit.fileTreePanel.generateWith' => ({required Object harness}) => '使用 ${harness} 生成',
			'cockpit.fileTreePanel.generateUnavailableWhileAmending' => '修补提交时不可用',
			'cockpit.fileTreePanel.cancelGeneration' => '取消生成',
			'cockpit.fileTreePanel.changes' => '更改',
			'cockpit.fileTreePanel.history' => '历史',
			'cockpit.fileTreePanel.historyRepository' => '仓库',
			'cockpit.fileTreePanel.historyNoRepository' => '没有可用的 Git 仓库。',
			'cockpit.fileTreePanel.historyEmpty' => '未找到提交。',
			'cockpit.fileTreePanel.historyLoadFailed' => '无法加载 Git 历史。',
			'cockpit.fileTreePanel.historyUntitledCommit' => '无标题提交',
			'cockpit.fileTreePanel.historyNow' => '刚刚',
			'cockpit.fileTreePanel.historyMinutesAgo' => ({required Object count}) => '${count} 分钟前',
			'cockpit.fileTreePanel.historyHoursAgo' => ({required Object count}) => '${count} 小时前',
			'cockpit.fileTreePanel.historyYesterday' => '昨天',
			'cockpit.fileTreePanel.historyDayAgo' => '1 天前',
			'cockpit.fileTreePanel.historyDaysAgo' => ({required Object count}) => '${count} 天前',
			'cockpit.fileTreePanel.historyFiles' => '已更改的文件',
			'cockpit.fileTreePanel.historyFilesEmpty' => '没有文件更改。',
			'cockpit.fileTreePanel.historyFilesLoadFailed' => '无法加载已更改的文件。',
			'cockpit.fileTreePanel.diffEmptyTree' => '空树',
			'cockpit.fileTreePanel.diffOriginal' => ({required Object ref}) => '原始 ${ref}',
			'cockpit.fileTreePanel.diffModified' => ({required Object ref}) => '修改后 ${ref}',
			'cockpit.fileTreePanel.diffWorkingTree' => '工作树',
			'cockpit.fileTreePanel.diffBinaryFile' => '二进制文件——没有文本差异。',
			'cockpit.fileTreePanel.diffNoChanges' => '没有更改。',
			'cockpit.fileTreePanel.diffError' => ({required Object detail}) => '无法读取差异：${detail}',
			'cockpit.fileTreePanel.galleryTooltip' => '画廊',
			'cockpit.fileTreePanel.sectionGallery' => '画廊',
			'cockpit.fileTreePanel.openAsHtml' => '以 HTML 打开',
			'cockpit.fileTreePanel.importQuestionTitle' => '复制到此处？',
			'cockpit.fileTreePanel.importMessage' => ({required Object count, required Object dest}) => '将 ${count} 项复制到「${dest}」？',
			'cockpit.fileTreePanel.importAction' => '复制',
			'cockpit.fileTreePanel.couldNotImportTitle' => '无法复制',
			'cockpit.fileTreePanel.openInAgent' => ({required Object harness}) => '在 ${harness} 中打开',
			'cockpit.fileViewer.cantOpen' => '无法打开此文件。',
			'cockpit.fileViewer.couldNotLoadImage' => '无法加载图片。',
			'cockpit.fileViewer.preview' => '预览',
			'cockpit.fileViewer.source' => '源代码',
			'cockpit.fileViewer.reload' => '重新加载',
			'cockpit.workspaceSettingsDialog.choosePhotoTitle' => '选择工作区照片',
			'cockpit.workspaceSettingsDialog.title' => '工作区设置',
			'cockpit.workspaceSettingsDialog.namePlaceholder' => '工作区名称',
			'cockpit.workspaceSettingsDialog.addPhoto' => '添加照片',
			'cockpit.workspaceSettingsDialog.changePhoto' => '更换照片',
			'cockpit.workspaceSettingsDialog.remove' => '移除',
			'cockpit.workspaceSettingsDialog.color' => '颜色',
			'cockpit.workspaceSettingsDialog.host' => '主机',
			'cockpit.workspaceSettingsDialog.folder' => '文件夹',
			'cockpit.realmDialogs.namePlaceholder' => '领域名称',
			'cockpit.realmDialogs.duplicateName' => '同名领域已存在。',
			'cockpit.realmDialogs.newRealmTitle' => '新建领域',
			'cockpit.realmDialogs.renameRealmTitle' => '重命名领域',
			'cockpit.realmDialogs.rename' => '重命名',
			'cockpit.realmDialogs.deleteRealmTitle' => '删除领域',
			'cockpit.realmDialogs.deleteMessage' => ({required Object name, required Object suffix}) => '删除「${name}」？不会删除任何工作区——只是更改文件夹列表。${suffix}',
			'cockpit.realmDialogs.deleteSuffixOne' => ' 其工作区将移动到 Default。',
			'cockpit.realmDialogs.deleteSuffixMany' => ({required Object count}) => ' 其 ${count} 个工作区将移动到 Default。',
			'cockpit.realmDialogs.manageRealmsTitle' => '管理领域',
			'cockpit.realmDialogs.workspaceCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 个工作区', other: '${n} 个工作区', ), 
			'cockpit.dbRedisTable.deleteKeyTitle' => '删除键',
			'cockpit.dbRedisTable.deleteKeyMessage' => ({required Object key}) => '从此 Redis 数据库中删除「${key}」？',
			'cockpit.dbRedisTable.refresh' => '刷新',
			'cockpit.dbRedisTable.newKey' => '新建键',
			'cockpit.dbRedisTable.columnKey' => '键',
			'cockpit.dbRedisTable.columnValue' => '值',
			'cockpit.dbRedisTable.columnType' => '类型',
			'cockpit.dbRedisTable.columnTtl' => 'TTL',
			'cockpit.dbRedisTable.keyCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 个键', other: '${n} 个键', ), 
			'cockpit.dbRedisTable.noKeys' => '此数据库中没有键。',
			'cockpit.dbRedisTable.noKeysMatch' => ({required Object pattern}) => '没有匹配「${pattern}」的键。',
			'cockpit.dbRedisTable.loadMore' => '加载更多',
			'cockpit.dbRedisTable.loadingFullValue' => '正在加载完整值…',
			'cockpit.dbRedisTable.ttlMustBeNumber' => 'TTL 必须是秒数。',
			'cockpit.dbRedisTable.addKey' => '添加键',
			'cockpit.dbRedisTable.keyFieldHint' => '键',
			'cockpit.dbRedisTable.ttlFieldHint' => 'ttl（秒，可选）',
			'cockpit.dbRedisTable.valueFieldHint' => '值',
			'cockpit.dbRedisTable.searchHint' => '搜索——模式，如 user:*',
			'cockpit.dbQueryView.saveQueryAs' => '查询另存为',
			'cockpit.dbQueryView.couldNotSave' => '无法保存',
			'cockpit.dbQueryView.selectDatabase' => '选择数据库',
			'cockpit.dbQueryView.noSqlConnections' => '没有 SQL 连接',
			'cockpit.dbQueryView.running' => '运行中…',
			'cockpit.dbQueryView.runSelection' => '运行选中部分',
			'cockpit.dbQueryView.run' => '运行',
			'cockpit.dbQueryView.pickDatabaseHint' => '先在上方选择数据库，然后运行（⌘↵）。',
			'cockpit.dbQueryView.runQueryHint' => '运行查询（⌘↵）后结果将显示在这里。',
			'cockpit.dbQueryView.noRows' => '没有行。',
			'cockpit.dbQueryView.rowsAffected' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '影响 1 行', other: '影响 ${n} 行', ), 
			'cockpit.dbQueryView.rowsFooter' => ({required Object n}) => '${n} 行',
			'cockpit.dbQueryView.truncatedSuffix' => ' · 已截断（调高 -- limit）',
			'cockpit.dbQueryView.table' => '表格',
			'cockpit.dbQueryView.json' => 'JSON',
			'cockpit.dbQueryView.unsaved' => '未保存',
			'cockpit.dbQueryView.saved' => '已保存',
			'cockpit.dbQueryView.copied' => '已复制',
			'cockpit.dbQueryView.copy' => '复制',
			'cockpit.httpView.saveRequestAs' => '请求另存为',
			'cockpit.httpView.couldNotSave' => '无法保存',
			'cockpit.httpView.run' => '运行',
			'cockpit.httpView.running' => '运行中…',
			'cockpit.httpView.noRequests' => '此文件中没有请求——写一个，如 GET https://example.com',
			'cockpit.httpView.selectRequest' => '选择请求',
			'cockpit.httpView.requestCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 个请求', other: '${n} 个请求', ), 
			'cockpit.httpView.runHint' => '运行请求（⌘↵）后响应将显示在这里。',
			'cockpit.httpView.emptyBody' => '响应体为空。',
			'cockpit.httpView.body' => 'JSON',
			'cockpit.httpView.headers' => '标头',
			'cockpit.httpView.raw' => '文本',
			'cockpit.httpView.truncatedSuffix' => ' · 已截断（响应过大）',
			'cockpit.httpView.error.title' => '请求失败',
			'cockpit.httpView.error.noRequest' => '光标处未找到请求。',
			'cockpit.httpView.error.invalidUrl' => ({required Object url}) => '无效的 URL：${url}',
			'cockpit.httpView.error.unresolvedVariable' => ({required Object name}) => '变量 {{${name}}} 没有值。请在此文件中用 @${name} = … 声明。',
			'cockpit.httpView.error.bodyFileMissing' => ({required Object path}) => '未找到请求体文件：${path}',
			'cockpit.httpView.error.bodyFileUnreadable' => ({required Object path, required Object detail}) => '无法读取请求体文件 ${path}：${detail}',
			'cockpit.httpView.error.connectionFailed' => ({required Object detail}) => '无法连接服务器：${detail}',
			'cockpit.httpView.error.connectionFailedNoDetail' => '无法连接服务器。',
			'cockpit.httpView.error.timeout' => ({required Object seconds}) => '请求在 ${seconds} 秒后超时。',
			'cockpit.httpView.error.responseTooLarge' => ({required Object bytes}) => '响应超过了 ${bytes} 字节的限制。',
			'cockpit.kanbanView.filter' => '筛选',
			'cockpit.kanbanView.filterTitlePlaceholder' => '搜索标题',
			'cockpit.kanbanView.filterLabels' => '标签',
			'cockpit.kanbanView.filterClear' => '清除',
			'cockpit.kanbanView.filterDependencies' => '依赖',
			'cockpit.kanbanView.filterBlocked' => '被阻塞',
			'cockpit.kanbanView.filterReady' => '就绪',
			'cockpit.kanbanView.blockedBy' => '被…阻塞',
			'cockpit.kanbanView.addBlocker' => '添加阻塞卡片',
			'cockpit.kanbanView.searchCards' => '搜索卡片',
			'cockpit.kanbanView.unknownCard' => '未知',
			'cockpit.kanbanView.boardView' => '看板',
			'cockpit.kanbanView.listView' => '列表',
			'cockpit.kanbanView.refresh' => '从磁盘刷新',
			'cockpit.kanbanView.manageLabels' => '标签',
			'cockpit.kanbanView.labelsTitle' => '此看板中的标签',
			'cockpit.kanbanView.labelNamePlaceholder' => '标签名称',
			'cockpit.kanbanView.labelUsage' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 张卡片', other: '${n} 张卡片', ), 
			'cockpit.kanbanView.deleteLabel' => '删除标签',
			'cockpit.kanbanView.newCard' => '新建卡片',
			'cockpit.kanbanView.newCardTitle' => '新建卡片',
			'cockpit.kanbanView.newColumn' => '新建列',
			'cockpit.kanbanView.columnNameTitle' => '列名称',
			'cockpit.kanbanView.dragColumn' => '拖动列',
			'cockpit.kanbanView.columnOptions' => '列选项',
			'cockpit.kanbanView.renameColumn' => '重命名列',
			'cockpit.kanbanView.moveColumnLeft' => '左移',
			'cockpit.kanbanView.moveColumnRight' => '右移',
			'cockpit.kanbanView.deleteColumn' => '删除列',
			'cockpit.kanbanView.newCardHere' => '在此新建卡片',
			'cockpit.kanbanView.duplicateCard' => '复制',
			'cockpit.kanbanView.cardLabels' => '标签',
			'cockpit.kanbanView.deleteCard' => '删除卡片',
			'cockpit.kanbanView.advance' => '移到下一列',
			'cockpit.kanbanView.advanceHold' => '移到下一列（长按：移到最后一列）',
			'cockpit.kanbanView.advanceBack' => '移回上一列',
			'cockpit.kanbanView.emptyColumn' => '没有卡片',
			'cockpit.kanbanView.cardCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 张卡片', other: '${n} 张卡片', ), 
			'cockpit.kanbanView.notes' => '备注',
			'cockpit.kanbanView.notesPlaceholder' => '写个备注',
			'cockpit.kanbanView.comments' => '评论',
			'cockpit.kanbanView.addComment' => '添加评论',
			'cockpit.kanbanView.commentPlaceholder' => '写条评论',
			'cockpit.kanbanView.noComments' => '暂无评论',
			'cockpit.kanbanView.closeDetail' => '关闭',
			'cockpit.kanbanView.notABoard' => '此文件还没有 ## 列——将以 Markdown 打开。',
			'cockpit.kanbanView.startBoard' => '创建看板',
			'cockpit.kanbanView.couldNotSave' => '无法保存看板',
			'cockpit.kanbanView.unrecognizedBlock' => '解析器无法识别——只能整体拖动，不支持内联编辑。',
			'cockpit.kanbanView.deleteColumnDialog.title' => ({required Object name}) => '删除「${name}」？',
			'cockpit.kanbanView.deleteColumnDialog.message' => ({required Object count}) => '此列有 ${count}。请选择它们的去向。',
			'cockpit.kanbanView.deleteColumnDialog.moveCards' => '移到上一列',
			'cockpit.kanbanView.deleteColumnDialog.deleteAll' => '随列一起删除',
			'cockpit.kanbanView.deleteColumnDialog.emptyMessage' => '此列为空。',
			'cockpit.dbPanel.sectionDatabase' => '数据库',
			'cockpit.dbPanel.edit' => '编辑…',
			'cockpit.dbPanel.copyName' => '复制名称',
			'cockpit.dbPanel.newQuery' => '新建查询',
			'cockpit.dbPanel.browseKeys' => '浏览键',
			'cockpit.dbPanel.deleteConnectionTitle' => '删除连接',
			'cockpit.dbPanel.deleteConnectionMessage' => ({required Object name}) => '从此工作区移除「${name}」？已保存的密码将被丢弃。引用它的 .dbq 文件不受影响。',
			'cockpit.dbPanel.footer' => ({required Object n}) => '.cockpit/databases.json · ${n} 个连接',
			'cockpit.dbPanel.footerOne' => '.cockpit/databases.json · 1 个连接',
			'cockpit.dbPanel.noConnections' => '还没有连接。',
			'cockpit.dbPanel.passwordRequired' => '在主机上未找到密码。请打开此连接并重新输入——密码保存在运行数据库的那台机器上，而不是这台。',
			'cockpit.dbMongoView.deleteDocumentTitle' => '删除文档',
			'cockpit.dbMongoView.deleteDocumentMessage' => ({required Object collection, required Object id}) => '从「${collection}」中删除 _id 为 ${id} 的文档？',
			'cockpit.dbMongoView.filterHint' => '筛选——JSON，如 {"status": "active"}',
			'cockpit.dbMongoView.docCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 个文档', other: '${n} 个文档', ), 
			'cockpit.dbMongoView.refresh' => '刷新',
			'cockpit.dbMongoView.insertDocument' => '插入文档',
			'cockpit.dbMongoView.noDocuments' => '此集合中没有文档。',
			'cockpit.dbMongoView.noDocumentsMatch' => '没有符合此筛选条件的文档。',
			'cockpit.dbMongoView.loadMore' => '加载更多',
			'cockpit.dbMongoView.edit' => '编辑',
			'cockpit.dbMongoView.insert' => '插入',
			'cockpit.dbConnectionDialog.chooseFileTitle' => '选择 SQLite 数据库',
			'cockpit.dbConnectionDialog.file' => '文件',
			'cockpit.dbConnectionDialog.chooseFilePlaceholder' => '选择一个 SQLite 文件…',
			'cockpit.dbConnectionDialog.name' => '名称',
			'cockpit.dbConnectionDialog.password' => '密码',
			'cockpit.dbConnectionDialog.savePassword' => '保存密码',
			'cockpit.dbConnectionDialog.allowWrites' => '允许写入（智能体）',
			'cockpit.dbConnectionDialog.allowWritesHint' => '关闭 = 智能体只能通过 CLI 读取',
			'cockpit.dbConnectionDialog.visibleToAgents' => '对智能体可见',
			'cockpit.dbConnectionDialog.visibleToAgentsHint' => '关闭 = 对 CLI 隐藏，仅在 GUI 中可用',
			'cockpit.dbConnectionDialog.testing' => '正在测试连接…',
			'cockpit.dbConnectionDialog.connectionOk' => '连接正常',
			'cockpit.dbConnectionDialog.connectionFailed' => '连接失败',
			'cockpit.dbConnectionDialog.editTitle' => '编辑连接',
			'cockpit.dbConnectionDialog.newTitle' => '新建连接',
			'cockpit.dbConnectionDialog.connectionString' => '连接字符串',
			'cockpit.dbConnectionDialog.invalidUrl' => '不是有效的连接 URL。',
			'cockpit.dbConnectionDialog.sshTunnel' => 'SSH 隧道',
			'cockpit.dbConnectionDialog.sshHost' => 'SSH 主机',
			'cockpit.dbConnectionDialog.sshPort' => 'SSH 端口',
			'cockpit.dbConnectionDialog.sshUser' => 'SSH 用户',
			'cockpit.dbConnectionDialog.privateKey' => '私钥',
			'cockpit.dbConnectionDialog.choosePrivateKeyPlaceholder' => '选择一个私钥…',
			'cockpit.dbConnectionDialog.choosePrivateKeyDialogTitle' => '选择 SSH 私钥',
			'cockpit.dbConnectionDialog.keyPassphrase' => '密钥口令',
			'cockpit.dbConnectionDialog.savePassphrase' => '保存口令',
			'cockpit.dbConnectionDialog.passwordOnHost' => '密码保存在主机上，而不是这台机器上。',
			'cockpit.sshPrompts.unknownSshHostTitle' => '未知的 SSH 主机',
			'cockpit.sshPrompts.neverConnected' => ({required Object endpoint}) => 'Cockpit 从未连接过 ${endpoint}。',
			'cockpit.sshPrompts.trustHint' => '仅当此指纹与服务器匹配时才信任。你可以在服务器上用以下命令核对：',
			'cockpit.sshPrompts.trust' => '信任',
			'cockpit.sshPrompts.sshKeyPassphraseTitle' => 'SSH 密钥口令',
			_ => null,
		} ?? switch (path) {
			'cockpit.sshPrompts.unlockMessage' => ({required Object keyPath, required Object connectionName}) => '解锁 ${keyPath} 以连接「${connectionName}」。',
			'cockpit.sshPrompts.keptInMemoryHint' => '口令在 Cockpit 退出前保留在内存中。要让智能体使用此连接，请在连接设置中启用「保存口令」。',
			'cockpit.sshPrompts.unlock' => '解锁',
			'cockpit.projectsRail.workspaces' => '工作区',
			'cockpit.projectsRail.keepAwakeOn' => '正在保持此电脑唤醒以便远程访问。点击可让它重新睡眠。',
			'cockpit.projectsRail.keepAwakeOff' => '保持此电脑唤醒以便远程访问。Cockpit 重启后自动关闭。',
			'cockpit.projectsRail.keepAwakeBattery' => '正在用电池供电并保持唤醒。这会消耗电量。',
			'cockpit.projectsRail.keepAwakeLid' => '合上笔记本盖子仍会使其睡眠。',
			'cockpit.projectsRail.newWorkspace' => '新建工作区',
			'cockpit.projectsRail.settings' => '设置',
			'cockpit.projectsRail.mergeToParent' => '合并到父级',
			'cockpit.projectsRail.updateFromParent' => '从父级更新',
			'cockpit.projectsRail.forkWorktree' => '派生 worktree',
			'cockpit.projectsRail.copyBranch' => '复制分支',
			'cockpit.projectsRail.remove' => '移除',
			'cockpit.projectsRail.moveToRealm' => '移动到领域',
			'cockpit.projectsRail.copyWorkspaceId' => '复制工作区 ID',
			'cockpit.projectsRail.rename' => '重命名',
			'cockpit.projectsRail.close' => '关闭',
			'cockpit.projectsRail.newRealm' => '新建领域…',
			'cockpit.projectsRail.manageRealms' => '管理领域…',
			'cockpit.projectsRail.noWorkspaces' => '还没有工作区。',
			'cockpit.projectsRail.sync' => '同步',
			'cockpit.projectsRail.pull' => '拉取',
			'cockpit.projectsRail.push' => '推送',
			'cockpit.projectsRail.createWorktree' => '创建 worktree',
			'cockpit.projectsRail.worktreeCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, one: '1 个 worktree', other: '${n} 个 worktree', ), 
			'cockpit.projectsRail.expandWorktrees' => '展开 worktree',
			'cockpit.projectsRail.collapseWorktrees' => '折叠 worktree',
			'cockpit.findBar.find' => '查找',
			'cockpit.findBar.matchCase' => '区分大小写',
			'cockpit.findBar.wholeWord' => '全字匹配',
			'cockpit.findBar.useRegex' => '使用正则表达式',
			'cockpit.findBar.previous' => '上一个 (⇧⏎)',
			'cockpit.findBar.next' => '下一个 (⏎)',
			'cockpit.findBar.close' => '关闭 (Esc)',
			'cockpit.findBar.badPattern' => '无效的模式',
			'cockpit.findBar.counter' => ({required Object current, required Object total}) => '第 ${current} 个，共 ${total} 个',
			'cockpit.findBar.noResults' => '无结果',
			'cockpit.contentSearch.sectionSearch' => '搜索',
			'cockpit.contentSearch.searchInFiles' => '在文件中搜索',
			'cockpit.contentSearch.matchCase' => '区分大小写',
			'cockpit.contentSearch.wholeWord' => '全字匹配',
			'cockpit.contentSearch.useRegex' => '使用正则表达式',
			'cockpit.contentSearch.invalidRegex' => '无效的正则表达式。',
			'cockpit.contentSearch.typeToSearch' => '输入以在文件中搜索。',
			'cockpit.contentSearch.searching' => '搜索中…',
			'cockpit.contentSearch.noResults' => '无结果。',
			'cockpit.topbar.collapseSidebar' => '折叠侧边栏',
			'cockpit.topbar.toggleFiles' => '显示/隐藏文件',
			'cockpit.topbar.filesUnavailable' => 'Cockpit 中文件功能不可用',
			'cockpit.topbar.hideKeyboard' => '隐藏键盘',
			'cockpit.tasks.hotReload' => '热重载',
			'cockpit.tasks.hotRestart' => '热重启',
			'cockpit.tasks.toggleDebugPaint' => '切换调试绘制',
			'cockpit.tasks.togglePlatform' => '切换平台',
			'cockpit.tasks.quit' => '退出',
			'cockpit.notifications.agentFinished' => '智能体已完成',
			'cockpit.notifications.open' => '打开',
			'cockpit.notifications.agentNeedsAction' => '智能体需要你的输入',
			'cockpit.terminalLink.open' => '打开',
			'cockpit.terminalLink.revealFinder' => '在 Finder 中显示',
			'cockpit.terminalLink.revealExplorer' => '在资源管理器中显示',
			'cockpit.terminalLink.revealFolder' => '打开所在文件夹',
			'cockpit.terminalLink.copyPath' => '复制路径',
			'cockpit.terminalLink.openLink' => '打开链接',
			'cockpit.terminalLink.copyLink' => '复制链接',
			'cockpit.terminal.cwdFallbackWarning' => ({required Object requested, required Object path}) => '警告：文件夹「${requested}」不存在。此终端在「${path}」中打开。',
			'cockpit.terminal.workspaceEnvTracked' => ({required Object keys}) => '注意：.env.cockpit 被 git 跟踪（它随仓库一起提供）。已注入：${keys}',
			'cockpit.remoteHost.addHost' => '添加远程主机',
			'cockpit.remoteHost.hostName' => '名称',
			'cockpit.remoteHost.sshTarget' => 'SSH 目标（user@host）',
			'cockpit.remoteHost.connecting' => ({required Object host}) => '正在连接 ${host}…',
			'cockpit.remoteHost.openingTunnel' => 'SSH 隧道',
			'cockpit.remoteHost.installingServer' => '正在安装服务器',
			'cockpit.remoteHost.handshake' => ({required Object version}) => '服务器 ${version}',
			'cockpit.remoteHost.loadingWorkspace' => '正在加载工作区…',
			'cockpit.remoteHost.reconnecting' => ({required Object host}) => '正在重新连接 ${host}…',
			'cockpit.remoteHost.offline' => ({required Object host}) => '${host} 离线',
			'cockpit.remoteHost.remove' => '移除',
			'cockpit.remoteHost.reconnect' => '重新连接',
			'cockpit.remoteHost.installServer' => '安装服务器',
			'cockpit.remoteHost.errSshUnreachable' => ({required Object host}) => '无法通过 SSH 连到 ${host}。它开机了吗？远程登录是否已启用？',
			'cockpit.remoteHost.errInstallFailed' => ({required Object host}) => '无法在 ${host} 上安装服务器。',
			'cockpit.remoteHost.errVersionMismatch' => '服务器版本不兼容；请更新。',
			'cockpit.remoteHost.errDetail' => ({required Object detail}) => '详细信息：${detail}',
			'cockpit.remoteHost.pickFolderTitle' => ({required Object host}) => '在 ${host} 上打开文件夹',
			'cockpit.remoteHost.openHere' => '在此打开',
			'cockpit.remoteHost.emptyFolder' => '没有子文件夹',
			'cockpit.remoteHost.newLocal' => '本地',
			'cockpit.remoteHost.newRemote' => '远程',
			'cockpit.remoteHost.chooseHost' => '选择主机',
			'cockpit.remoteHost.newHostEntry' => '新建主机…',
			'cockpit.remoteHost.editHost' => '编辑主机',
			'cockpit.remoteHost.userLabel' => '用户名',
			'cockpit.remoteHost.hostLabel' => '主机 / IP',
			'cockpit.remoteHost.portLabel' => '端口',
			'cockpit.remoteHost.authLabel' => '身份验证',
			'cockpit.remoteHost.authKey' => 'SSH 密钥',
			'cockpit.remoteHost.authPassword' => '密码',
			'cockpit.remoteHost.passwordLabel' => '密码',
			'cockpit.remoteHost.passwordKeep' => '留空则保留当前密码',
			'cockpit.remoteHost.errUser' => '需要用户名',
			'cockpit.remoteHost.errHost' => '需要主机',
			'cockpit.remoteHost.errPassword' => '需要密码',
			'cockpit.remoteHost.identityChoose' => '选择…',
			'cockpit.remoteHost.identityEmpty' => '未选择密钥',
			'cockpit.remoteHost.identityDialogTitle' => '选择 SSH 私钥',
			'cockpit.remoteHost.errIdentity' => '请选择用于身份验证的私钥。',
			'cockpit.remoteHost.errHostKeyUnknown' => ({required Object host}) => 'Cockpit 尚不信任 ${host}。请再次连接并确认指纹。',
			'cockpit.remoteHost.errHostKeyChanged' => ({required Object host}) => '${host} 提供的 SSH 密钥与已存储的不一致。如果你没有重装那台机器，请停下来检查——否则从 ~/.ssh/known_hosts 中删除旧条目。',
			'cockpit.remoteHost.errHostBundleMissing' => ({required Object host}) => '${host} 是 Windows，但没有安装 Cockpit。远程服务器是从该机器上已有的 Cockpit 套件安装的，请先在那边安装 Cockpit 再试。',
			'cockpit.remoteHost.errHostUnknownOs' => ({required Object host}) => '无法识别 ${host} 的操作系统。该账户可能使用了受限 shell，或根本没有 shell。',
			'cockpit.remoteHost.errIdentityPublic' => '这里只有公钥。仅当私钥在你的 SSH agent 中时才能使用；否则请选择对应的私钥文件（同名，不带 .pub）。',
			'cockpit.remoteHost.errIdentityNotKey' => '该文件看起来不是私钥。',
			'cockpit.remoteHost.errIdentityMissingFile' => '该文件已不存在。',
			'cockpit.remoteHost.errIdentityUnreadable' => '该文件无法读取。',
			'cockpit.browserPane.back' => '后退',
			'cockpit.browserPane.forward' => '前进',
			'cockpit.browserPane.reload' => '重新加载',
			'cockpit.browserPane.urlHint' => '输入 URL 或地址',
			'cockpit.browserPane.go' => '前往',
			'cockpit.documentWindow.mediaNotSupported' => '音频和视频将在 Cockpit 主窗口中打开。',
			'cockpit.documentWindow.fileNotFound' => ({required Object path}) => '未找到文件：${path}',
			'cockpit.gallery.intro' => 'Cockpit 的特殊文档，让你直观地看到 AI 智能体在做什么。',
			'cockpit.gallery.createErrorTitle' => '无法创建文件',
			'cockpit.gallery.dbQuery.title' => '数据库查询',
			'cockpit.gallery.dbQuery.description' => 'SQL 编辑器，带结果表格，使用已注册的连接之一。',
			'cockpit.gallery.kanban.title' => '看板',
			'cockpit.gallery.kanban.description' => '以纯 Markdown 存储的列和卡片。可拖动、编辑和评论。',
			'cockpit.gallery.layout.title' => '窗格布局',
			'cockpit.gallery.layout.description' => '一键打开的终端和拆分，类似 tmuxinator。可在新建 worktree 时自动运行。',
			'cockpit.gallery.httpRequest.title' => 'HTTP 请求',
			'cockpit.gallery.httpRequest.description' => '把请求写在文件里运行，响应显示在旁边。',
			'cockpit.gallery.html.title' => 'HTML 视图',
			'cockpit.gallery.html.description' => '由智能体编写、Cockpit 直接渲染的页面：思维导图、图表、图形，随你所需。',
			'cockpit.gallery.tasks.title' => '任务',
			'cockpit.gallery.tasks.description' => '从任务面板运行的命令，如开发服务器、测试和构建。存储在 .cockpit/tasks.json。',
			'cockpit.gallery.notebook.title' => '笔记本',
			'cockpit.gallery.notebook.description' => '带标签的简短笔记文件夹。智能体写，你来读和编辑。也可在 Obsidian 中打开。',
			'cockpit.gallery.workspaceEnv.title' => '工作区环境变量',
			'cockpit.gallery.workspaceEnv.description' => '注入此工作区每个终端的变量。API 令牌或登录凭据放这里，不要粘贴到智能体的提示里。不会进入 git。',
			'cockpit.gallery.panel.title' => '面板',
			'cockpit.gallery.panel.description' => '带应用桥接的 HTML 页面：它的按钮可在这台机器上运行 Cockpit CLI 和 shell 命令。快速做仪表盘的游乐场。',
			'cockpit.notebook.notes' => '笔记',
			'cockpit.notebook.newNote' => '新建笔记',
			'cockpit.notebook.searchPlaceholder' => '搜索笔记',
			'cockpit.notebook.empty' => '还没有笔记。创建一个，或让智能体在这里写。',
			'cockpit.notebook.noMatch' => '没有匹配的笔记。',
			'cockpit.notebook.selectNote' => '选择笔记',
			'cockpit.notebook.reload' => '从磁盘重新加载',
			'cockpit.notebook.untagged' => '无标签',
			'cockpit.notebook.saveFailed' => '无法保存笔记',
			'cockpit.notebook.createFailed' => '无法创建笔记',
			'cockpit.notebook.addTag' => '添加标签',
			'cockpit.notebook.untitled' => '无标题',
			'cockpit.notebook.deleteNote' => '删除笔记',
			'cockpit.notebook.deleteConfirm' => ({required Object name}) => '将「${name}」移到废纸篓？',
			'cockpit.notebook.imageFailed' => '无法保存图片',
			'cockpit.notebook.format.bold' => '粗体 (⌘B)',
			'cockpit.notebook.format.italic' => '斜体 (⌘I)',
			'cockpit.notebook.format.strike' => '删除线',
			'cockpit.notebook.format.heading1' => '标题 1',
			'cockpit.notebook.format.heading2' => '标题 2',
			'cockpit.notebook.format.heading3' => '标题 3',
			'cockpit.notebook.format.bullets' => '无序列表',
			'cockpit.notebook.format.numbered' => '有序列表',
			'cockpit.notebook.format.checklist' => '任务列表',
			'cockpit.notebook.format.quote' => '引用',
			'cockpit.notebook.format.code' => '行内代码 (⌘E)',
			'cockpit.notebook.format.codeBlock' => '代码块',
			'cockpit.notebook.format.link' => '链接 (⌘K)',
			'cockpit.notebook.format.rule' => '分隔线',
			'cockpit.notebook.format.noteLink' => '链接到笔记（[[…]]）',
			'cockpit.notebook.format.noteLinkSearch' => '搜索笔记',
			'cockpit.notebook.format.image' => '插入图片…',
			'cockpit.notebook.backlinks' => '被链接自',
			'cockpit.notebook.renameTag' => '重命名标签',
			'cockpit.notebook.deleteTag' => '删除标签',
			'cockpit.notebook.deleteTagConfirm' => ({required Object count, required Object name}) => '从 ${count} 条笔记中移除「${name}」？笔记本身会保留。',
			'cockpit.notebook.showList' => '显示笔记列表',
			'cockpit.notebook.hideList' => '隐藏笔记列表',
			'cockpit.layoutPreview.applyFailedTitle' => '无法应用布局',
			'cockpit.layoutPreview.applyInCockpit' => '在 Cockpit 中应用',
			'cockpit.layoutPreview.applyNewWorkspace' => '作为新工作区打开',
			'cockpit.layoutPreview.applyTo' => ({required Object workspace}) => '应用到 ${workspace}',
			'cockpit.layoutPreview.autorunWorktree' => 'autorun: worktree。当你创建持有它的 worktree 时，此布局也会自动应用。',
			'cockpit.layoutPreview.command' => '命令',
			'cockpit.layoutPreview.folder' => '文件夹',
			'cockpit.layoutPreview.noCommand' => '无命令，打开 shell',
			'cockpit.layoutPreview.replaceConfirm' => '替换布局',
			'cockpit.layoutPreview.replaceMessage' => ({required Object n}) => '${n} 个此工作区已打开的标签页将被关闭，包括正在运行的工作。',
			'cockpit.layoutPreview.replaceTitle' => ({required Object workspace}) => '替换 ${workspace} 的布局？',
			'cockpit.layoutPreview.skippedTitle' => '未在此系统上创建',
			'cockpit.layoutPreview.splitDown' => '向下拆分',
			'cockpit.layoutPreview.splitRight' => '向右拆分',
			'cockpit.layoutPreview.splitTab' => '标签页',
			'cockpit.layoutPreview.subtitle' => ({required Object n}) => '此布局将打开 ${n} 个终端。应用前请先阅读命令。',
			'cockpit.telemetry.tooltip' => '遥测',
			'cockpit.telemetry.title' => '遥测',
			'cockpit.telemetry.liveRuns' => ({required Object n}) => '${n} 个进行中',
			'cockpit.telemetry.noWorkspace' => '打开一个工作区以查看其遥测。',
			'cockpit.telemetry.empty' => '这里还没有内容。',
			'cockpit.telemetry.emptyFiltered' => '这里还没有内容。',
			'cockpit.telemetry.searchHint' => '筛选案例',
			'cockpit.telemetry.chipOpen' => '待处理',
			'cockpit.telemetry.chipNew' => '新',
			'cockpit.telemetry.chipResolved' => '已解决',
			'cockpit.telemetry.chipIgnored' => '已忽略',
			'cockpit.telemetry.chipWarnings' => '警告',
			'cockpit.telemetry.tagNew' => '新',
			'cockpit.telemetry.tagRegression' => '回归',
			'cockpit.telemetry.tagResolved' => '已解决',
			'cockpit.telemetry.tagIgnored' => '已忽略',
			'cockpit.telemetry.srcTask' => '任务',
			'cockpit.telemetry.srcWrapper' => 'cockpit telemetry',
			'cockpit.telemetry.run' => ({required Object id}) => '运行 ${id}',
			'cockpit.telemetry.resolve' => '标记为已解决',
			'cockpit.telemetry.ignore' => '忽略（智能体也不再看到）',
			'cockpit.telemetry.reopen' => '重新打开',
			'cockpit.telemetry.clear' => '清除出现记录',
			'cockpit.telemetry.clearRun' => '清除此运行',
			'cockpit.telemetry.clearProject' => '清除项目',
			'cockpit.telemetry.openFile' => ({required Object location}) => '打开 ${location}',
			'cockpit.telemetry.showInTerminal' => '在终端中显示',
			'cockpit.telemetry.copyCommand' => '复制 CLI 命令',
			'cockpit.telemetry.copied' => '已复制',
			'cockpit.telemetry.statusOpen' => '待处理',
			'cockpit.telemetry.statusResolved' => '已解决',
			'cockpit.telemetry.statusIgnored' => '已忽略',
			'cockpit.telemetry.occurrences' => '出现记录',
			'cockpit.telemetry.inRuns' => ({required Object n}) => '在 ${n} 次运行中',
			'cockpit.telemetry.first' => '首次',
			'cockpit.telemetry.last' => '最近',
			'cockpit.telemetry.origin' => '来源',
			'cockpit.telemetry.sectionStack' => '调用栈',
			'cockpit.telemetry.stackHint' => '项目帧已高亮 · 点击打开文件',
			'cockpit.telemetry.sectionCorrelated' => '关联日志',
			'cockpit.telemetry.correlatedHint' => '错误之前最近的 JSON 日志，同一次运行',
			'cockpit.telemetry.none' => '无',
			'cockpit.telemetry.sectionRuns' => '按运行统计的出现记录',
			'cockpit.telemetry.runsHint' => '相同键（cwd、命令）：新增和回归据此判定',
			'cockpit.telemetry.sectionContext' => '原始上下文',
			'cockpit.telemetry.contextHint' => '最后一次出现前后的终端行',
			'cockpit.telemetry.current' => '当前',
			'cockpit.telemetry.fingerprintHint' => ({required Object location}) => '指纹 = 类型 + 规范化的消息 + ${location}',
			'cockpit.telemetry.blameUncommitted' => '在工作树中已更改',
			'cockpit.telemetry.blameCommit' => ({required Object ago, required Object sha}) => '更改于 ${ago}（${sha}）',
			'cockpit.telemetry.justNow' => '刚刚',
			'cockpit.telemetry.minutesAgo' => ({required Object n}) => '${n} 分钟前',
			'cockpit.telemetry.hoursAgo' => ({required Object n}) => '${n} 小时前',
			'cockpit.telemetry.daysAgo' => ({required Object n}) => '${n} 天前',
			'cockpit.telemetry.resolvedToast' => '已解决。如果在之后的运行中再次出现，将重新显示为回归。',
			'cockpit.telemetry.ignoredToast' => '已忽略。智能体不再看到它（除非 --include-ignored）。',
			'cockpit.telemetry.clearedToast' => '出现记录已删除。分类规则保留。',
			'cockpit.telemetry.byHuman' => '由你操作',
			'cockpit.telemetry.byAgent' => '由智能体操作',
			'cockpit.telemetry.caseTabTitle' => ({required Object type, required Object file}) => '${type} · ${file}',
			'cockpit.telemetry.srcApp' => '应用',
			'cockpit.telemetry.chipApp' => 'Cockpit',
			'cockpit.panelView.unavailable' => '面板需要内嵌 web 视图，目前在 Linux 上尚不可用。',
			'cockpit.panelView.openInBrowser' => '在浏览器中打开',
			'cockpit.panelView.openAsHtml' => '以 HTML 打开',
			'settings.language.title' => '语言',
			'settings.language.system' => '跟随系统',
			'settings.language.english' => 'English',
			'settings.language.portugueseBr' => 'Português (BR)',
			'settings.language.spanish' => 'Español',
			'settings.page.header.back' => '返回',
			'settings.page.header.title' => '设置',
			'settings.page.nav.general' => '通用',
			'settings.page.nav.appearance' => '外观',
			'settings.page.nav.terminal' => '终端',
			'settings.page.nav.language' => '语言',
			'settings.page.nav.shortcuts' => '快捷键',
			'settings.page.nav.notifications' => '通知',
			'settings.page.nav.automations' => '自动化',
			'settings.page.nav.remoteHosts' => '远程主机',
			'settings.page.general.sectionEditor' => '编辑器',
			'settings.page.general.editorEngineTitle' => '引擎',
			'settings.page.general.editorEngineCockpit' => 'Cockpit（默认）',
			'settings.page.general.editorEngineNeovim' => 'Neovim',
			'settings.page.general.neovimChecking' => '正在查找 Neovim…',
			'settings.page.general.neovimNotFound' => '在你的 shell PATH 中未找到 Neovim。',
			'settings.page.general.neovimRefresh' => '重新检查',
			'settings.page.general.showCockpitTitle' => '显示 Cockpit 终端',
			'settings.page.general.showCockpitDesc' => '在侧栏顶部固定一个无路径、纯终端的工作区。关闭后它的终端也会关闭。',
			'settings.page.general.launchAtStartupTitle' => '登录时启动',
			'settings.page.general.launchAtStartupDesc' => '登录电脑时自动启动 Cockpit。',
			'settings.page.general.sectionUpdates' => '更新',
			'settings.page.general.checkUpdatesTitle' => '检查更新',
			'settings.page.general.checkUpdatesDesc' => 'Cockpit 检查新版本的频率。',
			'settings.page.general.updateFrequency.daily' => '每天',
			'settings.page.general.updateFrequency.weekly' => '每周',
			'settings.page.general.updateFrequency.monthly' => '每月',
			'settings.page.general.updateFrequency.never' => '从不',
			'settings.page.general.developerModeTitle' => '开发者模式',
			'settings.page.general.developerModeDesc' => '将 Cockpit 自身的错误和警告记录到单独的遥测存储（「Cockpit」标签）中，并启用性能指标。只对维护此应用的人有用。',
			'settings.page.diagnostics.sectionTitle' => '诊断',
			'settings.page.diagnostics.logFileTitle' => '日志文件',
			'settings.page.diagnostics.logFileDesc' => ({required Object days, required Object path}) => '错误和启动事件记录在这里，保留 ${days} 天。\n${path}',
			'settings.page.diagnostics.unavailable' => '不可用',
			'settings.page.diagnostics.reveal' => '显示',
			'settings.page.diagnostics.reportTitle' => '报告问题',
			'settings.page.diagnostics.reportDesc' => '打开一个预填了你的版本、操作系统和最近日志的 issue。不会自动发送——你先审阅。',
			'settings.page.diagnostics.reportButton' => '报告…',
			'settings.page.diagnostics.reportDialogTitle' => '问题报告',
			'settings.page.diagnostics.reportDialogError' => '从设置中手动报告。',
			'settings.page.diagnostics.reportDialogDescription' => '在 issue 中描述出了什么问题。最近的日志包含在下方和「复制详细信息」中。',
			'settings.page.storage.sectionTitle' => '存储',
			'settings.page.storage.locationTitle' => '存储位置',
			'settings.page.storage.locationDesc' => ({required Object root}) => 'Cockpit 把项目、布局和设置保存在这里。指向一个同步文件夹即可备份。\n${root}',
			'settings.page.storage.useDefault' => '使用默认位置',
			'settings.page.storage.working' => '处理中…',
			'settings.page.storage.change' => '更改…',
			'settings.page.storage.resetTitle' => '重置 Cockpit',
			'settings.page.storage.resetDesc' => '删除全部本地数据——项目、布局、设置和终端历史——并恢复到默认位置。',
			'settings.page.storage.resetButton' => '重置…',
			'settings.page.storage.resetConfirm' => '重置',
			'settings.page.storage.resetDialogTitle' => '重置 Cockpit？',
			'settings.page.storage.resetDialogContent' => '这将永久删除所有本地 Cockpit 数据——项目、布局、设置和终端历史。此操作无法撤销。Cockpit 将关闭，以便你重新开始。',
			'settings.page.storage.restartRequiredTitle' => '需要重启',
			'settings.page.storage.restartChangeFolderMessage' => ({required Object path}) => 'Cockpit 将从下次启动起使用此文件夹：\n${path}',
			'settings.page.storage.restartUseDefaultMessage' => 'Cockpit 将从下次启动起使用系统默认位置。自定义文件夹中的数据保持不变。',
			'settings.page.storage.restartResetMessage' => '所有 Cockpit 数据已清除。重启以重新开始。',
			'settings.page.storage.later' => '稍后',
			'settings.page.storage.quitCockpit' => '退出 Cockpit',
			'settings.page.storage.chooseFolderDialogTitle' => '选择 Cockpit 数据文件夹',
			'settings.page.terminal.sectionDefaultTerminal' => '默认终端',
			'settings.page.terminal.engineTitle' => '引擎',
			'settings.page.terminal.engineDesc' => '供新的终端标签页和任务输出缓冲区使用。已打开的标签页保持当前引擎。',
			'settings.page.terminal.shellTitle' => 'Shell',
			'settings.page.terminal.shellDesc' => '新建终端标签页打开的 shell。「+」旁的箭头仍可为单个标签页打开任意其他 shell。',
			'settings.page.terminal.noWslMessage' => '未找到 WSL 发行版。安装一个（wsl.exe --install）并重启 Cockpit 后，它会出现在这里。',
			'settings.page.terminal.sectionBehavior' => '行为',
			'settings.page.terminal.closeOnExitTitle' => 'shell 退出时关闭标签页',
			'settings.page.terminal.closeOnExitDesc' => '当 shell 自行结束（exit、Ctrl-D）时，关闭其标签页，而不是留下一个失效的终端。',
			'settings.page.appearance.sectionTheme' => '主题',
			'settings.page.appearance.themeTitle' => '主题',
			'settings.page.appearance.themeDesc' => '应用颜色、代码高亮和终端配色。',
			'settings.page.appearance.modeTitle' => '模式',
			'settings.page.appearance.modeDesc' => '使用主题的哪个变体。',
			'settings.page.appearance.modeOnlyDark' => ({required Object theme}) => '「${theme}」只有深色变体，此项不生效。',
			'settings.page.appearance.modeOnlyLight' => ({required Object theme}) => '「${theme}」只有浅色变体，此项不生效。',
			'settings.page.appearance.themeFileTitle' => '主题文件',
			'settings.page.appearance.themeFileDesc' => '从 JSON 文件导入主题，或导出当前主题。',
			'settings.page.appearance.previewCode' => '代码',
			'settings.page.appearance.previewTerminal' => '终端',
			'settings.page.appearance.themeSystem' => '跟随系统',
			'settings.page.appearance.themeLight' => '浅色',
			'settings.page.appearance.themeDark' => '深色',
			'settings.page.appearance.sectionFonts' => '字体',
			'settings.page.appearance.interfaceFontTitle' => '界面字体',
			'settings.page.appearance.interfaceFontDesc' => '整个应用通用。留空 = 系统默认。',
			'settings.page.appearance.interfaceSizeTitle' => '界面字号',
			'settings.page.appearance.codeFontTitle' => '代码字体',
			'settings.page.appearance.codeFontDesc' => '用于代码和差异。留空 = 系统默认。',
			'settings.page.appearance.codeSizeTitle' => '代码字号',
			'settings.page.appearance.terminalFontTitle' => '终端字体',
			'settings.page.appearance.terminalFontDesc' => '仅用于终端。留空 = 系统默认。',
			'settings.page.appearance.terminalSizeTitle' => '终端字号',
			'settings.page.appearance.terminalSizeDesc' => '关闭 = 跟随代码字号。',
			'settings.page.appearance.terminalSizeInherit' => '跟随代码字号',
			'settings.page.appearance.terminalWeightTitle' => '终端字重',
			'settings.page.appearance.terminalWeightDesc' => '低密度屏幕渲染笔画偏粗。Auto 会在那种屏幕上减淡，Retina 屏则不受影响。',
			'settings.page.appearance.terminalWeightAuto' => '自动（按屏幕）',
			'settings.page.appearance.terminalWeightLight' => '细',
			'settings.page.appearance.terminalWeightNormal' => '常规',
			'settings.page.appearance.terminalWeightMedium' => '中等',
			'settings.page.appearance.terminalWeightSemiBold' => '半粗',
			'settings.page.appearance.sectionConversation' => '对话',
			'settings.page.appearance.pinUserMessageTitle' => '固定用户消息',
			'settings.page.appearance.pinUserMessageDesc' => '回答滚动时，问题固定在顶部。',
			'settings.page.appearance.importTheme' => '导入…',
			'settings.page.appearance.exportTheme' => '导出…',
			'settings.page.appearance.deleteTheme' => '移除',
			'settings.page.appearance.importThemeDialog' => '选择主题文件',
			'settings.page.appearance.exportThemeDialog' => '主题另存为',
			'settings.page.appearance.themeImported' => ({required Object name}) => '主题「${name}」已导入。',
			'settings.page.appearance.themeExported' => '主题已保存。',
			'settings.page.appearance.themeDeleted' => '主题已移除。',
			'settings.page.appearance.fontPickerTitle' => '选择字体',
			'settings.page.appearance.fontPickerSearch' => '搜索字体',
			'settings.page.appearance.fontPickerEmpty' => '这台机器上没有匹配的字体。',
			'settings.page.appearance.fontPickerBundled' => '内置',
			'settings.page.appearance.fontPickerCustom' => '列表里没有？输入确切的字体族名称。',
			'settings.page.appearance.fontPickerCustomHint' => '字体族名称',
			'settings.page.appearance.fontPickerUse' => '使用',
			'settings.page.appearance.fontPickerDefault' => '默认',
			'settings.page.appearance.fontMissing' => '这台机器上未找到——使用回退字体。',
			'settings.page.appearance.sectionLayout' => '布局',
			'settings.page.appearance.swapPanelsTitle' => '交换侧边面板',
			'settings.page.appearance.swapPanelsDesc' => '将工作区放到右侧，文件、搜索、git 和数据库放到左侧。',
			'settings.page.notifications.sectionTitle' => '通知',
			'settings.page.notifications.enableTitle' => '启用通知',
			'settings.page.notifications.enableDesc' => '当智能体完成一轮对话且窗口未聚焦时提醒我。',
			'settings.page.notifications.systemPermissionTitle' => '系统权限',
			'settings.page.notifications.grantedDesc' => 'Cockpit 已获准发送通知。',
			'settings.page.notifications.notGrantedDesc' => 'macOS 尚未授予通知权限。',
			'settings.page.notifications.granted' => '已授予',
			'settings.page.notifications.requestPermission' => '请求权限',
			'settings.page.notifications.soundsTitle' => '声音',
			'settings.page.notifications.soundVolumeTitle' => '音量',
			'settings.page.notifications.soundTurnDone' => '轮次完成',
			'settings.page.notifications.soundTurnDoneDesc' => '智能体完成了它的一轮对话。',
			'settings.page.notifications.soundActionRequired' => '需要操作',
			'settings.page.notifications.soundActionRequiredDesc' => '智能体正在等待你的批准或回答。',
			'settings.page.notifications.soundDefault' => '默认',
			'settings.page.notifications.soundCustom' => ({required Object name}) => '自定义：${name}',
			'settings.page.notifications.soundChooseFile' => '选择文件',
			'settings.page.notifications.soundReset' => '恢复默认',
			'settings.page.notifications.soundOnActiveTab' => '此标签页处于活动状态时也播放',
			'settings.page.notifications.soundPreview' => '试听',
			'settings.page.shortcuts.notCustomizable' => '键盘快捷键尚不支持自定义。',
			'settings.page.languages.sectionFormatting' => '格式化',
			'settings.page.languages.formatOnSaveTitle' => '保存时格式化',
			'settings.page.languages.formatOnSaveDesc' => '保存文件（⌘S）时自动格式化。',
			'settings.page.languages.sectionLanguageServers' => '语言服务器',
			'settings.page.languages.footerNote' => '错误和格式化使用各语言的语言服务器。Cockpit 不会安装服务器——它使用你机器上已有的。● 有响应 · ○ 未找到或命令无效（请安装服务器或调整命令）。',
			'settings.page.languages.serverCommandLabel' => '语言服务器命令',
			'settings.page.languages.formatterCommandLabel' => '格式化器命令（可选）',
			'settings.page.languages.formatterHint' => '带 %FILE% 占位符的外部格式化器。设置后优先于 LSP 格式化器。',
			'settings.page.languages.resetToDefault' => '恢复默认',
			'settings.page.languages.saveAndRestart' => '保存并重启',
			'settings.page.languages.statusResponds' => '服务器有响应',
			'settings.page.languages.statusNotFound' => '未找到服务器或命令无效',
			'settings.page.automations.sectionCommitMessages' => '提交信息',
			'settings.page.automations.harness' => '工具',
			'settings.page.automations.harnessDiscovering' => '正在查找已安装的命令行工具…',
			'settings.page.automations.harnessNoneFound' => '在 PATH 中未找到受支持的工具。',
			'settings.page.automations.harnessConfiguredUnavailable' => ({required Object harness}) => '${harness} 已配置但不可用。',
			'settings.page.automations.harnessChoose' => '选择用于生成提交信息的 CLI。',
			'settings.page.automations.harnessRefresh' => '刷新已安装的工具',
			'settings.page.automations.notConfigured' => '未配置',
			'settings.page.automations.model' => '模型',
			'settings.page.automations.modelUnavailable' => '在找到工具之前，模型列表不可用。',
			'settings.page.automations.modelCliOnly' => '此工具使用其 CLI 的默认模型。',
			'settings.page.automations.modelCliDefault' => 'CLI 默认',
			'settings.page.automations.modelAuto' => '自动',
			'settings.page.automations.modelSearch' => ({required Object count}) => '在 ${count} 个模型中搜索…',
			'settings.page.automations.modelAutoRouted' => '此工具自动路由模型。',
			'settings.page.automations.modelAccountOnly' => '仅列出你的账户可用的模型。',
			'settings.page.automations.generateFromSourceControl' => '从源代码管理生成',
			'settings.page.automations.generateFromSourceControlDescription' => 'Cockpit 只发送选定的差异和最近的提交主题。常见凭据模式和敏感文件会在工具运行前被脱敏。',
			'settings.page.automations.discoveryFailed' => '无法发现已安装的自动化工具。',
			'settings.page.automations.staleModel' => ({required Object model, required Object harness}) => '模型「${model}」在 ${harness} 中已不可用。改用 CLI 默认模型——如有需要，请在设置中选择其他模型。',
			'settings.page.automations.recommendedSuffix' => '推荐',
			'settings.remoteHosts.title' => '远程主机',
			'settings.remoteHosts.description' => '通过 SSH 访问的机器。在这里添加主机与从工作区「+」菜单添加效果相同。',
			'settings.remoteHosts.empty' => '还没有远程主机。',
			'settings.remoteHosts.add' => '添加主机',
			'settings.remoteHosts.edit' => '编辑',
			'settings.remoteHosts.reconnect' => '重新连接',
			'settings.remoteHosts.remove' => '移除',
			'settings.remoteHosts.removeTitle' => '移除主机',
			'settings.remoteHosts.removeMessage' => ({required Object name}) => '移除「${name}」及其全部工作区？主机本身不会删除任何内容。',
			'settings.remoteHosts.workspacesCount' => ({required Object count}) => '${count} 个工作区',
			'settings.remoteHosts.deviceKeyTitle' => '本设备的密钥',
			'settings.remoteHosts.deviceKeyDesc' => '将此公钥添加到主机的 ~/.ssh/authorized_keys，本设备即可连接。',
			'settings.remoteHosts.deviceKeyCopy' => '复制公钥',
			'settings.remoteHosts.deviceKeyCopied' => '公钥已复制',
			'settings.remoteHosts.statusConnected' => '已连接',
			'settings.remoteHosts.statusConnecting' => '连接中…',
			'settings.remoteHosts.statusReconnecting' => '重新连接中…',
			'settings.remoteHosts.statusOffline' => '离线',
			'settings.remoteHosts.statusIdle' => '未连接',
			'settings.remoteHosts.helpTitle' => '工作原理',
			'settings.remoteHosts.helpBody' => 'Cockpit 通过 SSH 连接到你的机器，并与一个小型服务器通信，由它运行终端、文件和 git。主机必须安装并运行 Cockpit（桌面版）或 cockpit-server，并将本设备的公钥添加到其 ~/.ssh/authorized_keys。',
			'automation.error.unavailable' => ({required Object harness}) => '${harness} 未安装或不在 PATH 中。',
			'automation.error.modelUnavailable' => ({required Object model, required Object harness}) => '模型「${model}」在 ${harness} 中不可用。请在设置中选择其他模型。',
			'automation.error.authentication' => ({required Object harness, required Object detail}) => '${harness}：${detail}',
			'automation.error.timeout' => ({required Object harness, required Object seconds}) => '${harness} 在 ${seconds} 秒内未响应。',
			'automation.error.cancelled' => '提交信息生成已取消。',
			'automation.error.process' => ({required Object harness, required Object detail}) => '${harness}：${detail}',
			'automation.error.processNoDetail' => ({required Object harness}) => '${harness} 无法生成提交信息。',
			'automation.error.invalidResponse' => '自动化返回了空的提交信息。',
			'automation.error.busy' => '已有提交信息正在生成。',
			'automation.error.unknown' => '自动化无法生成提交信息。',
			'automation.error.noWorkspace' => '未选择工作区。',
			'automation.error.fileOutsideWorkspace' => '文件在工作区根目录之外。',
			'automation.error.fileUnreadable' => ({required Object detail}) => '无法读取文件：${detail}',
			'automation.error.binaryFile' => '无法为二进制文件生成提交信息。',
			'automation.error.noFileChanges' => '此文件没有可描述的更改。',
			'automation.error.noStagedChanges' => '没有已暂存的更改可描述。',
			'automation.error.multipleRepositories' => '已暂存的更改属于多个仓库。请分别生成。',
			'automation.error.diffUnavailable' => '无法读取差异。',
			'automation.error.notConfigured' => '请在设置中配置提交信息工具。',
			'fileOperation.error.alreadyExists' => ({required Object name}) => '已存在：「${name}」。',
			'fileOperation.error.notFound' => ({required Object name}) => '未找到：「${name}」。',
			'fileOperation.error.invalidPath' => '无效的路径。',
			'fileOperation.error.emptyName' => '名称不能为空。',
			'fileOperation.error.noWorkspace' => '未选择工作区。',
			'fileOperation.error.cannotMoveIntoItself' => '无法将文件夹移动到其自身内部。',
			'fileOperation.error.clipboardEmpty' => '剪贴板为空。',
			'fileOperation.error.notScratchTab' => '此标签页不是草稿文件。',
			'fileOperation.error.writeFailed' => '无法写入文件。',
			'fileOperation.error.formatterEmptyCommand' => '格式化器命令为空。',
			'fileOperation.error.formatterMissingPlaceholder' => '格式化器命令必须包含 %FILE% 占位符。',
			'fileOperation.error.formatterTimeout' => '格式化器超时。',
			'fileOperation.error.formatterExitCode' => ({required Object code}) => '格式化器以退出码 ${code} 结束。',
			'fileOperation.error.formatterFailed' => '格式化器无法运行。',
			'fileOperation.error.osFailure' => ({required Object detail}) => '${detail}',
			'fileOperation.error.nameHasSlash' => '名称不能包含「/」。',
			'fileOperation.error.invalidName' => '无效的名称。',
			'fileOperation.error.remoteDropUnsupported' => '尚不支持将文件拖放到远程工作区。',
			'theme.error.io' => '无法读取或写入主题文件。',
			'theme.error.ioDetail' => ({required Object detail}) => '无法读取或写入主题文件：${detail}',
			'theme.error.malformedJson' => ({required Object detail}) => '此文件不是有效的 JSON：${detail}',
			'theme.error.invalidTheme' => '此文件不是有效的主题。',
			'theme.error.reservedId' => '此主题使用了内置主题的 id。请修改文件中的「id」后重新导入。',
			'theme.error.notAnObject' => ({required Object field}) => '「${field}」处应为对象。',
			'theme.error.missingField' => ({required Object field}) => '缺少必需字段「${field}」。',
			_ => null,
		} ?? switch (path) {
			'theme.error.badColor' => ({required Object field, required Object value}) => '「${field}」处的「${value}」不是颜色。请使用 #RGB、#RRGGBB 或 #RRGGBBAA。',
			'theme.error.unknownBase' => ({required Object value}) => '「extends」中的基础主题「${value}」未知。',
			'theme.error.noVariants' => '主题未声明任何变体。请在「variants」下添加「dark」「light」或两者。',
			_ => null,
		};
	}
}
