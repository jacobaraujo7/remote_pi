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
class TranslationsEs extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.es,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <es>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsEs _root = this; // ignore: unused_field

	@override 
	TranslationsEs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEs(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$core$es core = _Translations$core$es._(_root);
	@override late final _Translations$common$es common = _Translations$common$es._(_root);
	@override late final _Translations$cockpit$es cockpit = _Translations$cockpit$es._(_root);
	@override late final _Translations$settings$es settings = _Translations$settings$es._(_root);
	@override late final _Translations$automation$es automation = _Translations$automation$es._(_root);
	@override late final _Translations$fileOperation$es fileOperation = _Translations$fileOperation$es._(_root);
	@override late final _Translations$theme$es theme = _Translations$theme$es._(_root);
}

// Path: core
class _Translations$core$es extends Translations$core$en {
	_Translations$core$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$core$bootstrapError$es bootstrapError = _Translations$core$bootstrapError$es._(_root);
	@override late final _Translations$core$macosNotifications$es macosNotifications = _Translations$core$macosNotifications$es._(_root);
	@override late final _Translations$core$appErrorView$es appErrorView = _Translations$core$appErrorView$es._(_root);
	@override late final _Translations$core$errorReportDialog$es errorReportDialog = _Translations$core$errorReportDialog$es._(_root);
	@override late final _Translations$core$windowControls$es windowControls = _Translations$core$windowControls$es._(_root);
	@override late final _Translations$core$crash$es crash = _Translations$core$crash$es._(_root);
	@override late final _Translations$core$menu$es menu = _Translations$core$menu$es._(_root);
}

// Path: common
class _Translations$common$es extends Translations$common$en {
	_Translations$common$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get confirm => 'Confirmar';
	@override String get create => 'Crear';
	@override String get gotIt => 'Entendido';
	@override String get save => 'Guardar';
	@override String get close => 'Cerrar';
	@override String get delete => 'Eliminar';
	@override String get done => 'Listo';
	@override String get add => 'Añadir';
	@override String get test => 'Probar';
	@override String get ok => 'OK';
	@override String get loading => 'Cargando…';
	@override String get checking => 'Comprobando…';
	@override String get remove => 'Quitar';
	@override String get restart => 'Reiniciar';
	@override String get settings => 'Configuración';
	@override String get send => 'Enviar';
	@override String get open => 'Abrir';
	@override String get dismiss => 'Descartar';
	@override String get report => 'Reportar';
	@override String get copyCode => 'Copiar código';
	@override String get search => 'Buscar';
	@override String get noResults => 'Sin resultados';
}

// Path: cockpit
class _Translations$cockpit$es extends Translations$cockpit$en {
	_Translations$cockpit$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$cockpit$confirmDialog$es confirmDialog = _Translations$cockpit$confirmDialog$es._(_root);
	@override late final _Translations$cockpit$historyDialog$es historyDialog = _Translations$cockpit$historyDialog$es._(_root);
	@override late final _Translations$cockpit$worktreeCreateDialog$es worktreeCreateDialog = _Translations$cockpit$worktreeCreateDialog$es._(_root);
	@override late final _Translations$cockpit$subfolderDialog$es subfolderDialog = _Translations$cockpit$subfolderDialog$es._(_root);
	@override late final _Translations$cockpit$commitMessageDialog$es commitMessageDialog = _Translations$cockpit$commitMessageDialog$es._(_root);
	@override late final _Translations$cockpit$agentEditDialog$es agentEditDialog = _Translations$cockpit$agentEditDialog$es._(_root);
	@override late final _Translations$cockpit$agentSetupChecklist$es agentSetupChecklist = _Translations$cockpit$agentSetupChecklist$es._(_root);
	@override late final _Translations$cockpit$agentComposer$es agentComposer = _Translations$cockpit$agentComposer$es._(_root);
	@override late final _Translations$cockpit$tasksPanel$es tasksPanel = _Translations$cockpit$tasksPanel$es._(_root);
	@override late final _Translations$cockpit$cockpitPage$es cockpitPage = _Translations$cockpit$cockpitPage$es._(_root);
	@override late final _Translations$cockpit$welcomeView$es welcomeView = _Translations$cockpit$welcomeView$es._(_root);
	@override late final _Translations$cockpit$modelPicker$es modelPicker = _Translations$cockpit$modelPicker$es._(_root);
	@override late final _Translations$cockpit$paneView$es paneView = _Translations$cockpit$paneView$es._(_root);
	@override late final _Translations$cockpit$fileTreePanel$es fileTreePanel = _Translations$cockpit$fileTreePanel$es._(_root);
	@override late final _Translations$cockpit$fileViewer$es fileViewer = _Translations$cockpit$fileViewer$es._(_root);
	@override late final _Translations$cockpit$workspaceSettingsDialog$es workspaceSettingsDialog = _Translations$cockpit$workspaceSettingsDialog$es._(_root);
	@override late final _Translations$cockpit$realmDialogs$es realmDialogs = _Translations$cockpit$realmDialogs$es._(_root);
	@override late final _Translations$cockpit$dbRedisTable$es dbRedisTable = _Translations$cockpit$dbRedisTable$es._(_root);
	@override late final _Translations$cockpit$dbQueryView$es dbQueryView = _Translations$cockpit$dbQueryView$es._(_root);
	@override late final _Translations$cockpit$httpView$es httpView = _Translations$cockpit$httpView$es._(_root);
	@override late final _Translations$cockpit$dbPanel$es dbPanel = _Translations$cockpit$dbPanel$es._(_root);
	@override late final _Translations$cockpit$dbMongoView$es dbMongoView = _Translations$cockpit$dbMongoView$es._(_root);
	@override late final _Translations$cockpit$dbConnectionDialog$es dbConnectionDialog = _Translations$cockpit$dbConnectionDialog$es._(_root);
	@override late final _Translations$cockpit$sshPrompts$es sshPrompts = _Translations$cockpit$sshPrompts$es._(_root);
	@override late final _Translations$cockpit$projectsRail$es projectsRail = _Translations$cockpit$projectsRail$es._(_root);
	@override late final _Translations$cockpit$findBar$es findBar = _Translations$cockpit$findBar$es._(_root);
	@override late final _Translations$cockpit$contentSearch$es contentSearch = _Translations$cockpit$contentSearch$es._(_root);
	@override late final _Translations$cockpit$emptyPane$es emptyPane = _Translations$cockpit$emptyPane$es._(_root);
	@override late final _Translations$cockpit$topbar$es topbar = _Translations$cockpit$topbar$es._(_root);
	@override late final _Translations$cockpit$transcript$es transcript = _Translations$cockpit$transcript$es._(_root);
	@override late final _Translations$cockpit$tasks$es tasks = _Translations$cockpit$tasks$es._(_root);
	@override late final _Translations$cockpit$notifications$es notifications = _Translations$cockpit$notifications$es._(_root);
	@override late final _Translations$cockpit$terminal$es terminal = _Translations$cockpit$terminal$es._(_root);
	@override late final _Translations$cockpit$remoteHost$es remoteHost = _Translations$cockpit$remoteHost$es._(_root);
	@override late final _Translations$cockpit$browserPane$es browserPane = _Translations$cockpit$browserPane$es._(_root);
}

// Path: settings
class _Translations$settings$es extends Translations$settings$en {
	_Translations$settings$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$language$es language = _Translations$settings$language$es._(_root);
	@override late final _Translations$settings$revokeDialog$es revokeDialog = _Translations$settings$revokeDialog$es._(_root);
	@override late final _Translations$settings$pairingDialog$es pairingDialog = _Translations$settings$pairingDialog$es._(_root);
	@override late final _Translations$settings$page$es page = _Translations$settings$page$es._(_root);
	@override late final _Translations$settings$remoteHosts$es remoteHosts = _Translations$settings$remoteHosts$es._(_root);
}

// Path: automation
class _Translations$automation$es extends Translations$automation$en {
	_Translations$automation$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$automation$error$es error = _Translations$automation$error$es._(_root);
}

// Path: fileOperation
class _Translations$fileOperation$es extends Translations$fileOperation$en {
	_Translations$fileOperation$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$fileOperation$error$es error = _Translations$fileOperation$error$es._(_root);
}

// Path: theme
class _Translations$theme$es extends Translations$theme$en {
	_Translations$theme$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$theme$error$es error = _Translations$theme$error$es._(_root);
}

// Path: core.bootstrapError
class _Translations$core$bootstrapError$es extends Translations$core$bootstrapError$en {
	_Translations$core$bootstrapError$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'No se pudo inicializar Cockpit';
	@override String get retry => 'Reintentar';
}

// Path: core.macosNotifications
class _Translations$core$macosNotifications$es extends Translations$core$macosNotifications$en {
	_Translations$core$macosNotifications$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Activar notificaciones en macOS';
	@override String get intro => 'Las notificaciones están desactivadas en la configuración del sistema. Sigue los pasos a continuación para activarlas:';
	@override String get step1 => 'Abre los Ajustes del Sistema en tu Mac.';
	@override String get step2 => 'Ve a la sección Notificaciones en la barra lateral izquierda.';
	@override String get step3 => 'Busca y selecciona la aplicación Cockpit en la lista.';
	@override String get step4 => 'Activa el interruptor Permitir Notificaciones.';
	@override String get tip => 'Consejo: si la aplicación no aparece en la lista, ciérrala y vuelve a abrirla para activar su registro en el sistema.';
	@override String get gotIt => 'Entendido';
}

// Path: core.appErrorView
class _Translations$core$appErrorView$es extends Translations$core$appErrorView$en {
	_Translations$core$appErrorView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get renderFailed => 'Esta parte de la aplicación no se pudo renderizar';
	@override String get details => 'Detalles';
	@override String get renderErrorTitle => 'Error de renderizado';
}

// Path: core.errorReportDialog
class _Translations$core$errorReportDialog$es extends Translations$core$errorReportDialog$en {
	_Translations$core$errorReportDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get defaultDescription => 'Algo salió mal. Los detalles a continuación se guardaron en el registro — puedes reportarlos para que se solucione.';
	@override String get copyDetails => 'Copiar detalles';
	@override String get reportIssue => 'Reportar problema';
}

// Path: core.windowControls
class _Translations$core$windowControls$es extends Translations$core$windowControls$en {
	_Translations$core$windowControls$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get minimize => 'Minimizar';
	@override String get maximize => 'Maximizar';
	@override String get close => 'Cerrar';
}

// Path: core.crash
class _Translations$core$crash$es extends Translations$core$crash$en {
	_Translations$core$crash$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cierre inesperado';
	@override String get bannerTitle => 'Cockpit se cerró inesperadamente';
	@override String get report => 'Reportar';
	@override String get dismiss => 'Descartar';
	@override String crashMessage({required Object version}) => 'La sesión anterior (versión ${version}) terminó sin cerrarse correctamente. ¿Quieres reportarlo? El log se incluye y puedes revisar todo antes de enviar.';
	@override String crashError({required Object startedAt, required Object pid}) => 'La sesión iniciada el ${startedAt} (pid ${pid}) terminó sin un cierre limpio.';
	@override String get crashDescription => 'No se capturó ningún error: el sistema terminó la app. El log de abajo es de esa sesión y es la parte más útil.';
}

// Path: core.menu
class _Translations$core$menu$es extends Translations$core$menu$en {
	_Translations$core$menu$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get settings => 'Configuración…';
	@override String get checkForUpdates => 'Buscar Actualizaciones…';
	@override String get file => 'Archivo';
	@override String get newAgent => 'Nuevo Agente';
	@override String get newTerminal => 'Nueva Terminal';
	@override String get openWorkspace => 'Abrir Workspace';
	@override String get save => 'Guardar';
	@override String get discard => 'Descartar';
	@override String get format => 'Formatear';
	@override String get view => 'Ver';
	@override String get toggleWorkspacePanel => 'Alternar Panel de Workspaces';
	@override String get toggleFiles => 'Alternar Archivos';
	@override String get splitRight => 'Dividir a la Derecha';
	@override String get splitDown => 'Dividir Abajo';
	@override String get focusPane => 'Enfocar Panel';
	@override String get focusLeft => 'Izquierda  (⌘⌥←)';
	@override String get focusRight => 'Derecha  (⌘⌥→)';
	@override String get focusUp => 'Arriba  (⌘⌥↑)';
	@override String get focusDown => 'Abajo  (⌘⌥↓)';
	@override String get selectTab => 'Seleccionar Pestaña';
	@override String tabN({required Object n}) => 'Pestaña ${n}';
	@override String get lastTab => 'Última Pestaña';
	@override String get zoomIn => 'Acercar';
	@override String get zoomOut => 'Alejar';
	@override String get actualSize => 'Tamaño Real';
	@override String get window => 'Ventana';
	@override String get quit => 'Salir';
	@override String get minimize => 'Minimizar';
	@override String get zoom => 'Zoom';
}

// Path: cockpit.confirmDialog
class _Translations$cockpit$confirmDialog$es extends Translations$cockpit$confirmDialog$en {
	_Translations$cockpit$confirmDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unsavedChangesTitle => 'Cambios sin guardar';
	@override String unsavedChangesMessage({required Object fileName}) => '“${fileName}” tiene cambios sin guardar. ¿Guardarlos antes de cerrar?';
	@override String get dontSave => 'No guardar';
	@override String get saveAndClose => 'Guardar y cerrar';
}

// Path: cockpit.historyDialog
class _Translations$cockpit$historyDialog$es extends Translations$cockpit$historyDialog$en {
	_Translations$cockpit$historyDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Historial de sesiones';
	@override String get subtitle => 'Abrir una reemplaza la transcripción actual de este agente';
	@override String get empty => 'No hay sesiones guardadas en esta carpeta.';
	@override String get untitledSession => 'Sesión sin título';
	@override String get justNow => 'ahora';
	@override String minutesAgo({required Object n}) => 'hace ${n} min';
	@override String hoursAgo({required Object n}) => 'hace ${n} h';
	@override String daysAgo({required Object n}) => 'hace ${n} d';
}

// Path: cockpit.worktreeCreateDialog
class _Translations$cockpit$worktreeCreateDialog$es extends Translations$cockpit$worktreeCreateDialog$en {
	_Translations$cockpit$worktreeCreateDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get forkTitle => 'Fork del worktree';
	@override String get createTitle => 'Crear worktree';
	@override String forkSubtitle({required Object root}) => 'Nueva worktree ramificada desde ${root}.';
	@override String createSubtitle({required Object root}) => 'Nueva feature en ${root} — nueva branch desde el HEAD actual.';
	@override String get namePlaceholder => 'feat/mi-feature';
	@override String get errorWhitespace => 'Sin espacios en el nombre.';
	@override String get errorInvalidChar => 'Carácter inválido para un nombre de branch.';
	@override String get errorInvalidSequence => 'Secuencia inválida (ej.: "..", "//", empezar/terminar con "/").';
	@override String get errorReserved => 'Posición reservada (no empieces con "-"/"." ni termines con ".lock").';
	@override String get errorDuplicateBranch => 'Ya existe una branch con ese nombre.';
	@override String get errorDuplicateWorktree => 'Ya existe un worktree con ese nombre.';
	@override String errorBranchHierarchyConflict({required Object target, required Object existing}) => 'No se puede crear la branch \'${target}\' porque entra en conflicto con la branch \'${existing}\' ya existente.';
	@override String get errorBranchHierarchicalConflictGeneral => 'Ya existe una branch con una jerarquía conflictiva.';
	@override String get fork => 'Fork';
	@override String get postCheckoutHint => 'Este repositorio tiene un hook post-checkout.';
	@override String get running => 'Ejecutando…';
	@override String get advancedSettings => 'Configuración Avanzada';
	@override String get copyIgnored => 'Copiar archivos ignorados (.gitignore)';
	@override String get copyIgnoredDesc => 'Copia los archivos ignorados por .gitignore (ej. .env, claves locales) al nuevo worktree.';
	@override String get copyUntracked => 'Copiar archivos no rastreados';
	@override String get copyUntrackedDesc => 'Copia los archivos nuevos o modificados que aún no se han agregado al stage.';
	@override String get baseBranch => 'Branch base';
	@override String get baseBranchDesc => 'La branch desde la cual se creará el nuevo worktree y branch.';
	@override String get fetchRemote => 'Sincronizar branch remota (fetch)';
	@override String get fetchRemoteDesc => 'Ejecuta git fetch para garantizar que la branch base esté confirmada antes de crear el worktree.';
	@override String get searchBranch => 'Buscar branch...';
	@override String get back => 'Atrás';
}

// Path: cockpit.subfolderDialog
class _Translations$cockpit$subfolderDialog$es extends Translations$cockpit$subfolderDialog$en {
	_Translations$cockpit$subfolderDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => '¿Dónde trabajar?';
	@override String get empty => 'No hay subcarpetas aquí.';
	@override String useRoot({required Object project}) => 'Usar la raíz de ${project}';
	@override String usePath({required Object project, required Object rel}) => 'Usar ${project}/${rel}';
	@override String get useThisFolder => 'Usar esta carpeta';
}

// Path: cockpit.commitMessageDialog
class _Translations$cockpit$commitMessageDialog$es extends Translations$cockpit$commitMessageDialog$en {
	_Translations$cockpit$commitMessageDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get commitTitle => 'Commit';
	@override String get stageAndCommitTitle => 'Stage y Commit';
	@override String scopeNote({required Object fileName}) => 'Commit solo de "${fileName}".';
	@override String get placeholder => 'fix: resumen breve del cambio';
	@override String get errorEmptySubject => 'La primera línea (asunto) no puede estar vacía.';
	@override String errorTooShort({required Object min}) => 'Asunto demasiado corto (mín. ${min} caracteres).';
	@override String errorTooLong({required Object max}) => 'Asunto demasiado largo (máx. ${max} caracteres).';
	@override String get errorTrailingPeriod => 'El asunto no debe terminar con un punto.';
	@override String get errorControlChars => 'El asunto contiene caracteres de control.';
	@override String get errorBlankSecondLine => 'Deja la segunda línea en blanco (separador entre asunto y cuerpo de git).';
	@override String get generate => 'Generar mensaje de commit';
	@override String generateWith({required Object harness}) => 'Generar con ${harness}';
	@override String get generating => 'Generando…';
	@override String get cancelGeneration => 'Cancelar generación';
}

// Path: cockpit.agentEditDialog
class _Translations$cockpit$agentEditDialog$es extends Translations$cockpit$agentEditDialog$en {
	_Translations$cockpit$agentEditDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Editar agente';
	@override String get agentName => 'Nombre del agente';
	@override String get relaySection => 'Relay (remote-pi)';
	@override String get autoConnect => 'Conectar automáticamente al iniciar';
	@override String get informationSection => 'Información';
	@override String get folder => 'Carpeta';
	@override String get model => 'Modelo';
	@override String get state => 'Estado';
	@override String get context => 'Contexto';
	@override String get statusEmpty => 'vacío';
	@override String get statusStarting => 'iniciando';
	@override String get statusReady => 'listo';
	@override String get statusStreaming => 'transmitiendo';
	@override String get statusEnded => 'finalizado';
}

// Path: cockpit.agentSetupChecklist
class _Translations$cockpit$agentSetupChecklist$es extends Translations$cockpit$agentSetupChecklist$en {
	_Translations$cockpit$agentSetupChecklist$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Configurar el entorno del agente';
	@override String get intro => 'Ejecutar un agente requiere tener Pi instalado. Completa los pasos siguientes — las terminales y los archivos funcionan sin nada de esto.';
	@override String get step1Title => 'Pi Code instalado';
	@override String get step1Description => 'El binario `pi` debe estar accesible.';
	@override String get step2Title => 'Extensión remote-pi en Pi';
	@override String get step2Description => 'Registrada en ~/.pi/agent/settings.json.';
	@override String get step3Title => 'Supervisor instalado';
	@override String get step3Description => 'Servicio pi-supervisord (remote-pi install).';
	@override String get install => 'Instalar';
	@override String get installExtensionTitle => 'Instalar extensión remote-pi';
	@override String get installSupervisorTitle => 'Instalar supervisor';
	@override String get createAgent => 'Crear agente';
	@override String get back => 'Atrás';
	@override String get checkAgain => 'Comprobar de nuevo';
	@override String get notRequired => 'No obligatorio en esta configuración';
	@override String get installing => 'Instalando…';
	@override String get installedSuccessfully => 'Instalado correctamente.';
}

// Path: cockpit.agentComposer
class _Translations$cockpit$agentComposer$es extends Translations$cockpit$agentComposer$en {
	_Translations$cockpit$agentComposer$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cmdNewDescription => 'Nueva sesión — borra la conversación';
	@override String get cmdCompactDescription => 'Compacta el contexto del agente';
	@override String get attachFile => 'Adjuntar archivo';
	@override String maxImages({required Object max}) => 'Máximo de ${max} imágenes.';
	@override String get placeholder => 'Mensaje para el agente, usa @files o /commands';
	@override String get stop => 'Detener';
	@override String get send => 'Enviar';
	@override String get relayOnline => 'Relay en línea';
	@override String get relayReconnecting => 'Relay reconectando...';
	@override String get relayOffline => 'Relay sin conexión';
	@override String contextTooltip({required Object pct}) => 'Contexto: ${pct}% de la ventana';
	@override String get visionWarning => 'El modelo actual no puede ver imágenes — cambia a uno con soporte de visión.';
	@override String get modelFallback => 'modelo';
}

// Path: cockpit.tasksPanel
class _Translations$cockpit$tasksPanel$es extends Translations$cockpit$tasksPanel$en {
	_Translations$cockpit$tasksPanel$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get reloadTasksTooltip => 'Recargar tasks';
	@override String get restartTooltip => 'Reiniciar';
	@override String get stopTooltip => 'Detener';
	@override String get runTooltip => 'Ejecutar';
	@override String sendsKeyTooltip({required Object label, required Object key}) => '${label} (envía \'${key}\')';
	@override String get startingTooltip => 'Iniciando…';
	@override String get stoppingTooltip => 'Deteniendo…';
	@override String get switchProfileTooltip => 'Cambiar perfil';
	@override String get moreKeysTooltip => 'Más teclas';
	@override String get sectionTasks => 'TAREAS';
	@override String get noTasks => 'No se detectaron tareas en este proyecto.';
	@override String get createTasksJson => 'Crear tasks.json';
}

// Path: cockpit.cockpitPage
class _Translations$cockpit$cockpitPage$es extends Translations$cockpit$cockpitPage$en {
	_Translations$cockpit$cockpitPage$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get chooseProjectFolderDialogTitle => 'Elige la carpeta del proyecto';
	@override String get chooseWorkspaceFolderDialogTitle => 'Elige la carpeta del workspace';
	@override String get workspaceRenamedTitle => 'Workspace renombrado';
	@override String workspaceRenamedMessage({required Object name}) => 'El nuevo nombre "${name}" solo se enviará a los agentes tras reiniciar el workspace o la aplicación.';
	@override String syncTitle({required Object label}) => 'Sync — ${label}';
	@override String pullTitle({required Object label}) => 'Pull — ${label}';
	@override String pushTitle({required Object label}) => 'Push — ${label}';
	@override String updateFromParentTitle({required Object name}) => 'Actualizar desde el Padre — ${name}';
	@override String mergeToParentTitle({required Object name}) => 'Merge al Padre — ${name}';
	@override String get worktreeMergedAndRemoved => 'Worktree fusionado y eliminado.';
	@override String get nothingWasChanged => 'No se realizaron cambios.';
	@override String get newRealmTitle => 'Nuevo realm';
	@override String get closeWorkspaceTitle => 'Cerrar workspace';
	@override String closeWorkspaceMessage({required Object name}) => '¿Cerrar "${name}"? Los agentes de este workspace se cerrarán. La carpeta en el disco se conserva.';
	@override String get closeAction => 'Cerrar';
	@override String get removeWorktreeTitle => 'Quitar worktree';
	@override String removeWorktreeMessage({required Object name, required Object warn}) => '¿Quitar "${name}"? La carpeta del worktree y la branch se eliminarán y los agentes de este fork se cerrarán.${warn}';
	@override String removeWorktreeWarning({required Object name}) => '\n\nAdvertencia: la branch "${name}" aún no se ha fusionado — eliminarla (git branch -D) descarta el trabajo no fusionado.';
	@override String get failedToRemoveWorktreeTitle => 'No se pudo quitar el worktree';
	@override String get openLayoutTitle => 'Abrir layout';
	@override String get restartServerTooltip => 'Reiniciar servidor';
	@override String get noLspAvailable => 'Ningún LSP disponible';
	@override String get lspRunning => 'en ejecución';
	@override String get lspStopped => 'detenido';
}

// Path: cockpit.welcomeView
class _Translations$cockpit$welcomeView$es extends Translations$cockpit$welcomeView$en {
	_Translations$cockpit$welcomeView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bienvenido a Cockpit';
	@override String get subtitle => 'Abre una carpeta o conéctate a un host remoto para empezar.';
	@override String get createWorkspace => 'Crear workspace';
	@override String get openLocalFolder => 'Abrir carpeta local';
	@override String get connectHost => 'Conectar a un host';
	@override String get configureHost => 'Configurar host';
	@override String get addWorkspace => 'Añadir workspace';
}

// Path: cockpit.modelPicker
class _Translations$cockpit$modelPicker$es extends Translations$cockpit$modelPicker$en {
	_Translations$cockpit$modelPicker$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String search({required Object count}) => 'Buscar modelo (${count})';
}

// Path: cockpit.paneView
class _Translations$cockpit$paneView$es extends Translations$cockpit$paneView$en {
	_Translations$cockpit$paneView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get closePaneTitle => '¿Cerrar panel?';
	@override String closePaneMessage({required Object count}) => 'Esto cierra todas las ${count} pestaña(s) de este panel y finaliza los agentes/terminales en él.';
	@override String get close => 'Cerrar';
	@override String get allTabs => 'Todas las pestañas';
	@override String get pinTab => 'Fijar pestaña';
	@override String get rename => 'Renombrar';
	@override String get resetTitle => 'Restablecer título';
	@override String get copyId => 'Copiar Id';
	@override String get autoRelay => 'Auto-relay';
	@override String get history => 'Historial';
	@override String get newTab => 'Nueva pestaña';
	@override String get newTerminal => 'Nueva terminal…';
	@override String get splitRight => 'Dividir a la derecha';
	@override String get splitDown => 'Dividir abajo';
	@override String get closePane => 'Cerrar panel';
	@override String get dropHereToMove => 'Suelta aquí para mover la pestaña';
	@override String get dockAsTab => 'Acoplar como pestaña';
	@override String get openBrowser => 'Abrir navegador';
	@override String get openTerminal => 'Abrir terminal';
}

// Path: cockpit.fileTreePanel
class _Translations$cockpit$fileTreePanel$es extends Translations$cockpit$fileTreePanel$en {
	_Translations$cockpit$fileTreePanel$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get viewDiff => 'Ver Diff';
	@override String get commit => 'Commit';
	@override String get stageAndCommit => 'Stage y Commit';
	@override String get unstage => 'Quitar del stage';
	@override String get stageChanges => 'Poner en stage';
	@override String get discardChanges => 'Descartar cambios';
	@override String get enterCommitMessage => 'Escribe un mensaje de commit.';
	@override String get commitUnavailable => 'Commit no disponible para este workspace.';
	@override String get gitErrorTitle => 'Error de Git';
	@override String get deleteNewFileTitle => '¿Eliminar archivo nuevo?';
	@override String get discardChangesTitle => '¿Descartar cambios?';
	@override String deleteNewFileMessage({required Object name}) => '"${name}" es un archivo nuevo y no se puede restaurar. ¿Eliminarlo?';
	@override String discardOneMessage({required Object name}) => '¿Descartar todos los cambios en "${name}"? Los archivos eliminados se restaurarán.';
	@override String get discard => 'Descartar';
	@override String get deleteAllNewFilesTitle => '¿Eliminar todos los archivos nuevos?';
	@override String allNewFilesMessage({required Object count}) => 'Los ${count} archivos son nuevos y se eliminarán. Esto no se puede deshacer.';
	@override String discardTrackedMessage({required Object count, required Object extra}) => '¿Descartar cambios en ${count} archivo(s) rastreado(s)?${extra}';
	@override String discardTrackedExtra({required Object count}) => ' Se mantendrán ${count} archivo(s) nuevo(s).';
	@override String get deleteAll => 'Eliminar todo';
	@override String get deleteQuestionTitle => '¿Eliminar?';
	@override String moveToTrash({required Object name}) => '¿Mover “${name}” a la Papelera?';
	@override String permanentlyDelete({required Object name}) => '¿Eliminar “${name}” de forma permanente? Esto no se puede deshacer.';
	@override String get couldNotDeleteTitle => 'No se pudo eliminar';
	@override String get moveQuestionTitle => '¿Mover?';
	@override String moveMessage({required Object name, required Object dest}) => '¿Mover “${name}” a “${dest}”?';
	@override String get moveAction => 'Mover';
	@override String get couldNotMoveTitle => 'No se pudo mover';
	@override String get couldNotPasteTitle => 'No se pudo pegar';
	@override String get filesTooltip => 'Archivos';
	@override String get searchTooltip => 'Buscar';
	@override String get sourceControlTooltip => 'Control de versiones';
	@override String get databaseTooltip => 'Base de datos';
	@override String get sectionFiles => 'ARCHIVOS';
	@override String get newFile => 'Nuevo archivo';
	@override String get newFolder => 'Nueva carpeta';
	@override String get refreshTooltip => 'Actualizar';
	@override String get sectionSourceControl => 'CONTROL DE VERSIONES';
	@override String get viewAsList => 'Ver como lista';
	@override String get viewAsTree => 'Ver como árbol';
	@override String get noFolderMessage => 'Ninguna carpeta — abre un workspace.';
	@override String get amend => 'Amend';
	@override String get commitMessagePlaceholder => 'Mensaje del commit';
	@override String get amendCommit => 'Amend del commit';
	@override String get lastCommit => 'último commit';
	@override String get openInFinder => 'Abrir en Finder';
	@override String get openInExplorer => 'Abrir en el Explorador';
	@override String get openInFileManager => 'Abrir en el gestor de archivos';
	@override String get open => 'Abrir';
	@override String get openWith => 'Abrir con';
	@override String get openLayout => 'Abrir layout';
	@override String get showGitDiff => 'Mostrar diff de git';
	@override String get createAgent => 'Crear agente';
	@override String get createTerminal => 'Crear terminal';
	@override String get rename => 'Renombrar';
	@override String get copy => 'Copiar';
	@override String get cut => 'Cortar';
	@override String get paste => 'Pegar';
	@override String get copyRelativePath => 'Copiar ruta relativa';
	@override String get copyAbsolutePath => 'Copiar ruta absoluta';
	@override String get renameFailed => 'No se pudo renombrar.';
	@override String get noChanges => 'Sin cambios.';
	@override String stagedChangesHeader({required Object count}) => 'CAMBIOS EN STAGE (${count})';
	@override String changesHeader({required Object count}) => 'CAMBIOS (${count})';
	@override String get discardAllChanges => 'Descartar todos los cambios';
	@override String get unstageAllChanges => 'Quitar todo del stage';
	@override String get stageAllChanges => 'Poner todo en stage';
	@override String get discardFolderChanges => 'Descartar cambios de la carpeta';
	@override String get unstageFolderChanges => 'Quitar carpeta del stage';
	@override String get stageFolderChanges => 'Poner carpeta en stage';
	@override String get generateCommitMessage => 'Generar mensaje de commit';
	@override String generateWith({required Object harness}) => 'Generar con ${harness}';
	@override String get generateUnavailableWhileAmending => 'No disponible mientras se enmienda un commit';
	@override String get cancelGeneration => 'Cancelar generación';
	@override String get changes => 'Cambios';
	@override String get history => 'Historial';
	@override String get historyRepository => 'Repositorio';
	@override String get historyNoRepository => 'No hay ningun repositorio Git disponible.';
	@override String get historyEmpty => 'No se encontraron commits.';
	@override String get historyLoadFailed => 'No se pudo cargar el historial de Git.';
	@override String get historyUntitledCommit => 'Commit sin titulo';
	@override String get historyNow => 'ahora';
	@override String historyMinutesAgo({required Object count}) => 'hace ${count} min';
	@override String historyHoursAgo({required Object count}) => 'hace ${count} h';
	@override String get historyYesterday => 'ayer';
	@override String get historyDayAgo => 'hace 1 dia';
	@override String historyDaysAgo({required Object count}) => 'hace ${count} dias';
	@override String get historyFiles => 'Archivos modificados';
	@override String get historyFilesEmpty => 'No hay archivos modificados.';
	@override String get historyFilesLoadFailed => 'No se pudieron cargar los archivos modificados.';
	@override String get diffEmptyTree => 'Arbol vacio';
	@override String diffOriginal({required Object ref}) => 'Original ${ref}';
	@override String diffModified({required Object ref}) => 'Modificado ${ref}';
	@override String get diffWorkingTree => 'Directorio de trabajo';
	@override String get diffBinaryFile => 'Archivo binario - sin diff de texto.';
	@override String get diffNoChanges => 'Sin cambios.';
}

// Path: cockpit.fileViewer
class _Translations$cockpit$fileViewer$es extends Translations$cockpit$fileViewer$en {
	_Translations$cockpit$fileViewer$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cantOpen => 'No se puede abrir este archivo.';
	@override String get couldNotLoadImage => 'No se pudo cargar la imagen.';
	@override String get preview => 'Vista previa';
	@override String get source => 'Código fuente';
}

// Path: cockpit.workspaceSettingsDialog
class _Translations$cockpit$workspaceSettingsDialog$es extends Translations$cockpit$workspaceSettingsDialog$en {
	_Translations$cockpit$workspaceSettingsDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get choosePhotoTitle => 'Elegir foto del workspace';
	@override String get title => 'Configuración del workspace';
	@override String get namePlaceholder => 'Nombre del workspace';
	@override String get addPhoto => 'Añadir foto';
	@override String get changePhoto => 'Cambiar foto';
	@override String get remove => 'Quitar';
	@override String get color => 'Color';
	@override String get host => 'Host';
	@override String get folder => 'Carpeta';
}

// Path: cockpit.realmDialogs
class _Translations$cockpit$realmDialogs$es extends Translations$cockpit$realmDialogs$en {
	_Translations$cockpit$realmDialogs$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get namePlaceholder => 'Nombre del realm';
	@override String get duplicateName => 'Ya existe un realm con ese nombre.';
	@override String get newRealmTitle => 'Nuevo realm';
	@override String get renameRealmTitle => 'Renombrar realm';
	@override String get rename => 'Renombrar';
	@override String get deleteRealmTitle => 'Eliminar realm';
	@override String deleteMessage({required Object name, required Object suffix}) => '¿Eliminar "${name}"? Ningún workspace se elimina — solo cambia la lista de carpetas.${suffix}';
	@override String get deleteSuffixOne => ' Su workspace se moverá a Predeterminado.';
	@override String deleteSuffixMany({required Object count}) => ' Sus ${count} workspaces se moverán a Predeterminado.';
	@override String get manageRealmsTitle => 'Gestionar realms';
	@override String workspaceCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 workspace',
		other: '${n} workspaces',
	);
}

// Path: cockpit.dbRedisTable
class _Translations$cockpit$dbRedisTable$es extends Translations$cockpit$dbRedisTable$en {
	_Translations$cockpit$dbRedisTable$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get deleteKeyTitle => 'Eliminar clave';
	@override String deleteKeyMessage({required Object key}) => '¿Eliminar "${key}" de esta base de datos Redis?';
	@override String get refresh => 'Actualizar';
	@override String get newKey => 'Nueva clave';
	@override String get columnKey => 'CLAVE';
	@override String get columnValue => 'VALOR';
	@override String get columnType => 'TIPO';
	@override String get columnTtl => 'TTL';
	@override String keyCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 clave',
		other: '${n} claves',
	);
	@override String get noKeys => 'No hay claves en esta base de datos.';
	@override String noKeysMatch({required Object pattern}) => 'Ninguna clave coincide con "${pattern}".';
	@override String get loadMore => 'Cargar más';
	@override String get loadingFullValue => 'Cargando valor completo…';
	@override String get ttlMustBeNumber => 'El TTL debe ser un número de segundos.';
	@override String get addKey => 'Añadir clave';
	@override String get keyFieldHint => 'clave';
	@override String get ttlFieldHint => 'ttl (s, opcional)';
	@override String get valueFieldHint => 'valor';
	@override String get searchHint => 'Buscar — patrón, ej.: user:*';
}

// Path: cockpit.dbQueryView
class _Translations$cockpit$dbQueryView$es extends Translations$cockpit$dbQueryView$en {
	_Translations$cockpit$dbQueryView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get saveQueryAs => 'Guardar query como';
	@override String get couldNotSave => 'No se pudo guardar';
	@override String get selectDatabase => 'Seleccionar base de datos';
	@override String get noSqlConnections => 'Sin conexiones SQL — añade una en el panel Database';
	@override String get running => 'Ejecutando…';
	@override String get runSelection => 'Ejecutar selección';
	@override String get run => 'Ejecutar';
	@override String get pickDatabaseHint => 'Elige una base de datos arriba y luego Ejecutar (⌘↵).';
	@override String get runQueryHint => 'Ejecuta la query (⌘↵) para ver los resultados aquí.';
	@override String get noRows => 'Sin filas.';
	@override String rowsAffected({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 fila afectada',
		other: '${n} filas afectadas',
	);
	@override String rowsFooter({required Object n}) => '${n} filas';
	@override String get truncatedSuffix => ' · truncado (aumenta -- limit)';
	@override String get table => 'Tabla';
	@override String get json => 'JSON';
	@override String get unsaved => 'sin guardar';
	@override String get saved => 'guardado';
	@override String get copied => 'Copiado';
	@override String get copy => 'Copiar';
}

// Path: cockpit.httpView
class _Translations$cockpit$httpView$es extends Translations$cockpit$httpView$en {
	_Translations$cockpit$httpView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get saveRequestAs => 'Guardar request como';
	@override String get couldNotSave => 'No se pudo guardar';
	@override String get run => 'Ejecutar';
	@override String get running => 'Ejecutando…';
	@override String get noRequests => 'Ningún request en este archivo — escribe uno, p. ej.: GET https://example.com';
	@override String get selectRequest => 'Seleccionar request';
	@override String requestCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 request',
		other: '${n} requests',
	);
	@override String get runHint => 'Ejecuta el request (⌘↵) para ver la respuesta aquí.';
	@override String get emptyBody => 'Cuerpo de la respuesta vacío.';
	@override String get body => 'JSON';
	@override String get headers => 'Headers';
	@override String get raw => 'Text';
	@override String get truncatedSuffix => ' · truncado (respuesta demasiado grande)';
	@override late final _Translations$cockpit$httpView$error$es error = _Translations$cockpit$httpView$error$es._(_root);
}

// Path: cockpit.dbPanel
class _Translations$cockpit$dbPanel$es extends Translations$cockpit$dbPanel$en {
	_Translations$cockpit$dbPanel$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionDatabase => 'BASE DE DATOS';
	@override String get edit => 'Editar…';
	@override String get copyName => 'Copiar nombre';
	@override String get newQuery => 'Nueva query';
	@override String get browseKeys => 'Ver claves';
	@override String get deleteConnectionTitle => 'Eliminar conexión';
	@override String deleteConnectionMessage({required Object name}) => '¿Quitar "${name}" de este workspace? Cualquier contraseña guardada se descartará. Los archivos .dbq que la referencian no se modifican.';
	@override String footer({required Object n}) => '.cockpit/databases.json · ${n} conexiones';
	@override String get footerOne => '.cockpit/databases.json · 1 conexión';
	@override String get noConnections => 'Aún no hay conexiones.';
	@override String get passwordRequired => 'Contraseña no encontrada en el host. Abre esta conexión y vuelve a escribirla — se guarda en la máquina que ejecuta la base de datos, no en esta.';
}

// Path: cockpit.dbMongoView
class _Translations$cockpit$dbMongoView$es extends Translations$cockpit$dbMongoView$en {
	_Translations$cockpit$dbMongoView$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get deleteDocumentTitle => 'Eliminar documento';
	@override String deleteDocumentMessage({required Object id, required Object collection}) => '¿Eliminar el documento con _id ${id} de "${collection}"?';
	@override String get filterHint => 'Filtro — JSON, ej.: {"status": "active"}';
	@override String docCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 doc',
		other: '${n} docs',
	);
	@override String get refresh => 'Actualizar';
	@override String get insertDocument => 'Insertar documento';
	@override String get noDocuments => 'No hay documentos en esta colección.';
	@override String get noDocumentsMatch => 'Ningún documento coincide con este filtro.';
	@override String get loadMore => 'Cargar más';
	@override String get edit => 'Editar';
	@override String get insert => 'Insertar';
}

// Path: cockpit.dbConnectionDialog
class _Translations$cockpit$dbConnectionDialog$es extends Translations$cockpit$dbConnectionDialog$en {
	_Translations$cockpit$dbConnectionDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get chooseFileTitle => 'Elegir base de datos SQLite';
	@override String get file => 'Archivo';
	@override String get chooseFilePlaceholder => 'Elige un archivo SQLite…';
	@override String get name => 'Nombre';
	@override String get password => 'Contraseña';
	@override String get savePassword => 'Guardar contraseña';
	@override String get allowWrites => 'Permitir escritura (agentes)';
	@override String get allowWritesHint => 'desactivado = los agentes solo leen vía CLI';
	@override String get visibleToAgents => 'Visible para agentes';
	@override String get visibleToAgentsHint => 'desactivado = oculto en la CLI, solo en la GUI';
	@override String get testing => 'Probando conexión…';
	@override String get connectionOk => 'Conexión OK';
	@override String get connectionFailed => 'Fallo en la conexión';
	@override String get editTitle => 'Editar conexión';
	@override String get newTitle => 'Nueva conexión';
	@override String get connectionString => 'Connection string';
	@override String get invalidUrl => 'URL de conexión no válida.';
	@override String get sshTunnel => 'Túnel SSH';
	@override String get sshHost => 'Host SSH';
	@override String get sshPort => 'Puerto SSH';
	@override String get sshUser => 'Usuario SSH';
	@override String get privateKey => 'Clave privada';
	@override String get choosePrivateKeyPlaceholder => 'Elige una clave privada…';
	@override String get choosePrivateKeyDialogTitle => 'Elegir clave privada SSH';
	@override String get keyPassphrase => 'Frase de contraseña de la clave';
	@override String get savePassphrase => 'Guardar frase de contraseña';
	@override String get passwordOnHost => 'La contraseña se guarda en el host, no en esta máquina.';
}

// Path: cockpit.sshPrompts
class _Translations$cockpit$sshPrompts$es extends Translations$cockpit$sshPrompts$en {
	_Translations$cockpit$sshPrompts$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unknownSshHostTitle => 'Host SSH desconocido';
	@override String neverConnected({required Object endpoint}) => 'Cockpit nunca se ha conectado a ${endpoint} antes.';
	@override String get trustHint => 'Confía solo si esta fingerprint coincide con el servidor. Puedes verificarla en el servidor con:';
	@override String get trust => 'Confiar';
	@override String get sshKeyPassphraseTitle => 'Frase de contraseña de la clave SSH';
	@override String unlockMessage({required Object keyPath, required Object connectionName}) => 'Desbloquea ${keyPath} para conectar "${connectionName}".';
	@override String get keptInMemoryHint => 'Se mantiene en memoria hasta que Cockpit se cierre. Para que los agentes usen esta conexión, activa "Guardar frase de contraseña" en la conexión.';
	@override String get unlock => 'Desbloquear';
}

// Path: cockpit.projectsRail
class _Translations$cockpit$projectsRail$es extends Translations$cockpit$projectsRail$en {
	_Translations$cockpit$projectsRail$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get workspaces => 'Workspaces';
	@override String get newWorkspace => 'Nuevo workspace';
	@override String get settings => 'Configuración';
	@override String get mergeToParent => 'Fusionar en el padre';
	@override String get updateFromParent => 'Actualizar desde el padre';
	@override String get forkWorktree => 'Crear worktree derivada';
	@override String get copyBranch => 'Copiar branch';
	@override String get remove => 'Quitar';
	@override String get moveToRealm => 'Mover a realm';
	@override String get copyWorkspaceId => 'Copiar id del workspace';
	@override String get rename => 'Renombrar';
	@override String get close => 'Cerrar';
	@override String get newRealm => 'Nuevo realm…';
	@override String get manageRealms => 'Gestionar realms…';
	@override String get noWorkspaces => 'Aún no hay workspaces.';
	@override String get sync => 'Sincronizar';
	@override String get pull => 'Pull';
	@override String get push => 'Push';
	@override String get createWorktree => 'Crear worktree';
	@override String worktreeCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 worktree',
		other: '${n} worktrees',
	);
	@override String get expandWorktrees => 'Expandir worktrees';
	@override String get collapseWorktrees => 'Contraer worktrees';
}

// Path: cockpit.findBar
class _Translations$cockpit$findBar$es extends Translations$cockpit$findBar$en {
	_Translations$cockpit$findBar$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get find => 'Buscar';
	@override String get matchCase => 'Coincidir mayúsculas';
	@override String get wholeWord => 'Palabra completa';
	@override String get useRegex => 'Usar expresión regular';
	@override String get previous => 'Anterior (⇧⏎)';
	@override String get next => 'Siguiente (⏎)';
	@override String get close => 'Cerrar (Esc)';
	@override String get badPattern => 'Patrón inválido';
	@override String get noResults => 'Sin resultados';
}

// Path: cockpit.contentSearch
class _Translations$cockpit$contentSearch$es extends Translations$cockpit$contentSearch$en {
	_Translations$cockpit$contentSearch$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionSearch => 'BÚSQUEDA';
	@override String get searchInFiles => 'Buscar en los archivos';
	@override String get matchCase => 'Coincidir mayúsculas';
	@override String get wholeWord => 'Palabra completa';
	@override String get useRegex => 'Usar expresión regular';
	@override String get invalidRegex => 'Expresión regular inválida.';
	@override String get typeToSearch => 'Escribe para buscar en todos los archivos.';
	@override String get searching => 'Buscando…';
	@override String get noResults => 'Sin resultados.';
}

// Path: cockpit.emptyPane
class _Translations$cockpit$emptyPane$es extends Translations$cockpit$emptyPane$en {
	_Translations$cockpit$emptyPane$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get newAgent => 'Nuevo agente';
	@override String get newAgentDescription => 'Ejecuta un pi en la carpeta que elijas';
	@override String get newTerminal => 'Nueva terminal';
	@override String get newTerminalDescription => 'Abre un shell en la carpeta que elijas';
}

// Path: cockpit.topbar
class _Translations$cockpit$topbar$es extends Translations$cockpit$topbar$en {
	_Translations$cockpit$topbar$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get collapseSidebar => 'Contraer barra lateral';
	@override String get toggleFiles => 'Mostrar/ocultar archivos';
	@override String get filesUnavailable => 'Archivos no disponibles en Cockpit';
	@override String get hideKeyboard => 'Ocultar teclado';
}

// Path: cockpit.transcript
class _Translations$cockpit$transcript$es extends Translations$cockpit$transcript$en {
	_Translations$cockpit$transcript$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get send => 'Enviar';
	@override String get typeYourAnswer => 'Escribe tu respuesta';
	@override String get startHint => 'Envía un prompt para que el agente empiece.';
	@override String workedFor({required Object duration}) => 'Trabajó ${duration}';
}

// Path: cockpit.tasks
class _Translations$cockpit$tasks$es extends Translations$cockpit$tasks$en {
	_Translations$cockpit$tasks$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get hotReload => 'Hot reload';
	@override String get hotRestart => 'Hot restart';
	@override String get toggleDebugPaint => 'Alternar debug paint';
	@override String get togglePlatform => 'Alternar plataforma';
	@override String get quit => 'Salir';
}

// Path: cockpit.notifications
class _Translations$cockpit$notifications$es extends Translations$cockpit$notifications$en {
	_Translations$cockpit$notifications$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get agentFinished => 'El agente terminó';
	@override String get open => 'Abrir';
	@override String get agentNeedsAction => 'El agente necesita tu acción';
	@override String get agentCrashed => 'El agente se detuvo inesperadamente';
}

// Path: cockpit.terminal
class _Translations$cockpit$terminal$es extends Translations$cockpit$terminal$en {
	_Translations$cockpit$terminal$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String cwdFallbackWarning({required Object requested, required Object path}) => 'Aviso: la carpeta "${requested}" no existe. Esta terminal se abrió en "${path}".';
}

// Path: cockpit.remoteHost
class _Translations$cockpit$remoteHost$es extends Translations$cockpit$remoteHost$en {
	_Translations$cockpit$remoteHost$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get addHost => 'Añadir host remoto';
	@override String get hostName => 'Nombre';
	@override String get sshTarget => 'Destino SSH (usuario@host)';
	@override String connecting({required Object host}) => 'Conectando a ${host}…';
	@override String get openingTunnel => 'Túnel SSH';
	@override String get installingServer => 'Instalando servidor';
	@override String handshake({required Object version}) => 'Servidor ${version}';
	@override String get loadingWorkspace => 'Cargando workspace…';
	@override String reconnecting({required Object host}) => 'Reconectando a ${host}…';
	@override String offline({required Object host}) => '${host} sin conexión';
	@override String get remove => 'Quitar';
	@override String get reconnect => 'Reconectar';
	@override String get installServer => 'Instalar servidor';
	@override String errSshUnreachable({required Object host}) => 'No se puede llegar a ${host} por SSH. ¿Está encendido y con Inicio de sesión remoto activado?';
	@override String errInstallFailed({required Object host}) => 'No se pudo instalar el servidor en ${host}.';
	@override String get errVersionMismatch => 'Versión del servidor incompatible; actualízalo.';
	@override String errDetail({required Object detail}) => 'Detalles: ${detail}';
	@override String pickFolderTitle({required Object host}) => 'Abrir carpeta en ${host}';
	@override String get openHere => 'Abrir aquí';
	@override String get emptyFolder => 'Sin subcarpetas';
	@override String get newLocal => 'Local';
	@override String get newRemote => 'Remoto';
	@override String get chooseHost => 'Elegir un host';
	@override String get newHostEntry => 'Nuevo host…';
	@override String get editHost => 'Editar host';
	@override String get userLabel => 'Usuario';
	@override String get hostLabel => 'Host / IP';
	@override String get portLabel => 'Puerto';
	@override String get authLabel => 'Autenticación';
	@override String get authKey => 'Clave SSH';
	@override String get authPassword => 'Contraseña';
	@override String get passwordLabel => 'Contraseña';
	@override String get passwordKeep => 'Deja en blanco para mantener la actual';
	@override String get errUser => 'Usuario obligatorio';
	@override String get errHost => 'Host obligatorio';
	@override String get errPassword => 'Contraseña obligatoria';
	@override String get identityChoose => 'Elegir…';
	@override String get identityEmpty => 'Ninguna clave seleccionada';
	@override String get identityDialogTitle => 'Selecciona la clave privada SSH';
	@override String get errIdentity => 'Elige la clave privada para autenticarte.';
	@override String errHostKeyUnknown({required Object host}) => 'Cockpit todavía no confía en ${host}. Conecta de nuevo y confirma la huella.';
	@override String errHostKeyChanged({required Object host}) => '${host} presenta una clave SSH distinta de la guardada. Si no reinstalaste esa máquina, detente y compruébalo; si la reinstalaste, elimina la entrada antigua de ~/.ssh/known_hosts.';
	@override String errHostBundleMissing({required Object host}) => '${host} es Windows pero no tiene Cockpit instalado. El servidor remoto se instala desde el bundle de Cockpit que ya está en esa máquina — instálalo allí e inténtalo de nuevo.';
	@override String errHostUnknownOs({required Object host}) => 'No se pudo identificar el sistema de ${host}. La cuenta puede tener un shell restringido, o ninguno.';
	@override String get errIdentityPublic => 'Solo está la clave pública. Eso funciona solo si la privada está en tu agente SSH; si no, elige la privada (mismo nombre, sin .pub).';
	@override String get errIdentityNotKey => 'Ese archivo no parece una clave privada.';
	@override String get errIdentityMissingFile => 'Ese archivo ya no existe.';
	@override String get errIdentityUnreadable => 'No se pudo leer ese archivo.';
}

// Path: cockpit.browserPane
class _Translations$cockpit$browserPane$es extends Translations$cockpit$browserPane$en {
	_Translations$cockpit$browserPane$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get back => 'Atrás';
	@override String get forward => 'Adelante';
	@override String get reload => 'Recargar';
	@override String get urlHint => 'Escribe la URL o dirección';
	@override String get go => 'Ir';
}

// Path: settings.language
class _Translations$settings$language$es extends Translations$settings$language$en {
	_Translations$settings$language$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Idioma';
	@override String get system => 'Sistema';
	@override String get english => 'Inglés';
	@override String get portugueseBr => 'Portugués (BR)';
	@override String get spanish => 'Español';
}

// Path: settings.revokeDialog
class _Translations$settings$revokeDialog$es extends Translations$settings$revokeDialog$en {
	_Translations$settings$revokeDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get deviceRemoved => 'Dispositivo eliminado.';
	@override String get failedToRevoke => 'No se pudo revocar el dispositivo.';
	@override String get revoking => 'Revocando…';
	@override String revokingDevice({required Object name}) => 'Revocando ${name}…';
	@override String get connectingMessage => 'Conectando al relay y quitando el acceso.';
	@override String get ok => 'Ok';
}

// Path: settings.pairingDialog
class _Translations$settings$pairingDialog$es extends Translations$settings$pairingDialog$en {
	_Translations$settings$pairingDialog$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Vincular dispositivo';
	@override String get connectingToRelay => 'Conectando al relay…';
	@override String get step1 => 'Abre la app Remote Pi en tu teléfono.';
	@override String get step2 => 'Toca en añadir / vincular dispositivo.';
	@override String get step3 => 'Apunta la cámara al QR de abajo.';
	@override String get qrGenerationFailed => 'No se pudo generar el QR.';
	@override String get autoRefreshHint => 'El código se actualiza automáticamente. Mantén esta ventana abierta.';
	@override String get pairingFailed => 'Fallo en la vinculación.';
	@override String get tryAgain => 'Intentar de nuevo';
	@override String get copied => '¡Copiado!';
	@override String get copyData => 'Copiar datos';
}

// Path: settings.page
class _Translations$settings$page$es extends Translations$settings$page$en {
	_Translations$settings$page$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$page$header$es header = _Translations$settings$page$header$es._(_root);
	@override late final _Translations$settings$page$nav$es nav = _Translations$settings$page$nav$es._(_root);
	@override late final _Translations$settings$page$general$es general = _Translations$settings$page$general$es._(_root);
	@override late final _Translations$settings$page$diagnostics$es diagnostics = _Translations$settings$page$diagnostics$es._(_root);
	@override late final _Translations$settings$page$storage$es storage = _Translations$settings$page$storage$es._(_root);
	@override late final _Translations$settings$page$terminal$es terminal = _Translations$settings$page$terminal$es._(_root);
	@override late final _Translations$settings$page$appearance$es appearance = _Translations$settings$page$appearance$es._(_root);
	@override late final _Translations$settings$page$notifications$es notifications = _Translations$settings$page$notifications$es._(_root);
	@override late final _Translations$settings$page$shortcuts$es shortcuts = _Translations$settings$page$shortcuts$es._(_root);
	@override late final _Translations$settings$page$languages$es languages = _Translations$settings$page$languages$es._(_root);
	@override late final _Translations$settings$page$connectivity$es connectivity = _Translations$settings$page$connectivity$es._(_root);
	@override late final _Translations$settings$page$schedules$es schedules = _Translations$settings$page$schedules$es._(_root);
	@override late final _Translations$settings$page$daemons$es daemons = _Translations$settings$page$daemons$es._(_root);
	@override late final _Translations$settings$page$automations$es automations = _Translations$settings$page$automations$es._(_root);
}

// Path: settings.remoteHosts
class _Translations$settings$remoteHosts$es extends Translations$settings$remoteHosts$en {
	_Translations$settings$remoteHosts$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Hosts remotos';
	@override String get description => 'Máquinas a las que accedes por SSH. Añadir un host aquí es lo mismo que hacerlo desde el menú "+" del workspace.';
	@override String get empty => 'Aún no hay hosts remotos.';
	@override String get add => 'Añadir host';
	@override String get edit => 'Editar';
	@override String get reconnect => 'Reconectar';
	@override String get remove => 'Eliminar';
	@override String get removeTitle => 'Eliminar host';
	@override String removeMessage({required Object name}) => '¿Eliminar "${name}" y todos sus workspaces? No se borra nada en el host.';
	@override String workspacesCount({required Object count}) => '${count} workspace(s)';
	@override String get deviceKeyTitle => 'Clave de este dispositivo';
	@override String get deviceKeyDesc => 'Añade esta clave pública a ~/.ssh/authorized_keys del host para que este dispositivo pueda conectarse.';
	@override String get deviceKeyCopy => 'Copiar clave pública';
	@override String get deviceKeyCopied => 'Clave pública copiada';
	@override String get statusConnected => 'Conectado';
	@override String get statusConnecting => 'Conectando…';
	@override String get statusReconnecting => 'Reconectando…';
	@override String get statusOffline => 'Sin conexión';
	@override String get statusIdle => 'No conectado';
	@override String get helpTitle => 'Cómo funciona';
	@override String get helpBody => 'Cockpit se conecta a tu máquina por SSH y habla con un pequeño servidor que ejecuta las terminales, archivos y git allí. El host debe tener Cockpit (escritorio) o el cockpit-server instalado y en ejecución, y la clave pública de este dispositivo añadida en su ~/.ssh/authorized_keys.';
}

// Path: automation.error
class _Translations$automation$error$es extends Translations$automation$error$en {
	_Translations$automation$error$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String unavailable({required Object harness}) => '${harness} no está instalado o no está en el PATH.';
	@override String modelUnavailable({required Object model, required Object harness}) => 'El modelo "${model}" no está disponible para ${harness}. Elige otro modelo en Configuración.';
	@override String authentication({required Object harness, required Object detail}) => '${harness}: ${detail}';
	@override String timeout({required Object harness, required Object seconds}) => '${harness} no respondió en ${seconds} segundos.';
	@override String get cancelled => 'Se canceló la generación del mensaje de commit.';
	@override String process({required Object harness, required Object detail}) => '${harness}: ${detail}';
	@override String processNoDetail({required Object harness}) => '${harness} no pudo generar un mensaje de commit.';
	@override String get invalidResponse => 'La automatización devolvió un mensaje de commit vacío.';
	@override String get busy => 'Ya se está generando otro mensaje de commit.';
	@override String get unknown => 'La automatización no pudo generar un mensaje de commit.';
	@override String get noWorkspace => 'Ningún workspace seleccionado.';
	@override String get fileOutsideWorkspace => 'El archivo está fuera de las raíces del workspace.';
	@override String fileUnreadable({required Object detail}) => 'No se pudo leer el archivo: ${detail}';
	@override String get binaryFile => 'No se puede generar un mensaje de commit para un archivo binario.';
	@override String get noFileChanges => 'No hay cambios que describir en este archivo.';
	@override String get noStagedChanges => 'No hay cambios en stage que describir.';
	@override String get multipleRepositories => 'Los cambios en stage pertenecen a varios repositorios. Genéralos por separado.';
	@override String get diffUnavailable => 'No se pudo leer el diff.';
	@override String get notConfigured => 'Configura un harness de mensajes de commit en Configuración.';
}

// Path: fileOperation.error
class _Translations$fileOperation$error$es extends Translations$fileOperation$error$en {
	_Translations$fileOperation$error$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String alreadyExists({required Object name}) => 'Ya existe: “${name}”.';
	@override String notFound({required Object name}) => 'No se encontró: “${name}”.';
	@override String get invalidPath => 'Ruta inválida.';
	@override String get emptyName => 'El nombre no puede estar vacío.';
	@override String get noWorkspace => 'Ningún workspace seleccionado.';
	@override String get cannotMoveIntoItself => 'No se puede mover una carpeta dentro de sí misma.';
	@override String get clipboardEmpty => 'El portapapeles está vacío.';
	@override String get notScratchTab => 'Esta pestaña no es un archivo temporal.';
	@override String get writeFailed => 'No se pudo escribir el archivo.';
	@override String get formatterEmptyCommand => 'Comando de formato vacío.';
	@override String get formatterMissingPlaceholder => 'El comando de formato debe incluir el marcador %FILE%.';
	@override String get formatterTimeout => 'El formateador agotó el tiempo de espera.';
	@override String formatterExitCode({required Object code}) => 'El formateador terminó con el código ${code}.';
	@override String get formatterFailed => 'No se pudo ejecutar el formateador.';
	@override String osFailure({required Object detail}) => '${detail}';
	@override String get nameHasSlash => 'El nombre no puede contener “/”.';
	@override String get invalidName => 'Nombre inválido.';
}

// Path: theme.error
class _Translations$theme$error$es extends Translations$theme$error$en {
	_Translations$theme$error$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get io => 'No se pudo leer o escribir el archivo del tema.';
	@override String ioDetail({required Object detail}) => 'No se pudo leer o escribir el archivo del tema: ${detail}';
	@override String malformedJson({required Object detail}) => 'Este archivo no es JSON válido: ${detail}';
	@override String get invalidTheme => 'Este archivo no es un tema válido.';
	@override String get reservedId => 'Este tema usa el id de un tema nativo. Cambia el "id" en el archivo e impórtalo de nuevo.';
	@override String notAnObject({required Object field}) => 'Se esperaba un objeto en "${field}".';
	@override String missingField({required Object field}) => 'Falta el campo obligatorio "${field}".';
	@override String badColor({required Object value, required Object field}) => '"${value}" en "${field}" no es un color. Usa #RGB, #RRGGBB o #RRGGBBAA.';
	@override String unknownBase({required Object value}) => 'Tema base "${value}" desconocido en "extends".';
	@override String get noVariants => 'El tema no declara ningún variant. Añade "dark", "light" o ambos en "variants".';
}

// Path: cockpit.httpView.error
class _Translations$cockpit$httpView$error$es extends Translations$cockpit$httpView$error$en {
	_Translations$cockpit$httpView$error$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Falló el request';
	@override String get noRequest => 'No se encontró ningún request en la posición del cursor.';
	@override String invalidUrl({required Object url}) => 'URL inválida: ${url}';
	@override String unresolvedVariable({required Object name}) => 'La variable {{${name}}} no tiene valor. Declárala con @${name} = … en este archivo.';
	@override String bodyFileMissing({required Object path}) => 'Archivo de cuerpo no encontrado: ${path}';
	@override String bodyFileUnreadable({required Object path, required Object detail}) => 'No se pudo leer el archivo de cuerpo ${path}: ${detail}';
	@override String connectionFailed({required Object detail}) => 'No se pudo alcanzar el servidor: ${detail}';
	@override String get connectionFailedNoDetail => 'No se pudo alcanzar el servidor.';
	@override String timeout({required Object seconds}) => 'El request superó el tiempo límite de ${seconds}s.';
	@override String responseTooLarge({required Object bytes}) => 'La respuesta superó el límite de ${bytes} bytes.';
}

// Path: settings.page.header
class _Translations$settings$page$header$es extends Translations$settings$page$header$en {
	_Translations$settings$page$header$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get back => 'Atrás';
	@override String get title => 'Configuración';
}

// Path: settings.page.nav
class _Translations$settings$page$nav$es extends Translations$settings$page$nav$en {
	_Translations$settings$page$nav$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get general => 'General';
	@override String get appearance => 'Apariencia';
	@override String get terminal => 'Terminal';
	@override String get language => 'Lenguaje';
	@override String get shortcuts => 'Atajos';
	@override String get notifications => 'Notificaciones';
	@override String get connectivity => 'Conectividad';
	@override String get daemonAgents => 'Agentes Daemon';
	@override String get schedules => 'Programaciones';
	@override String get automations => 'Automatizaciones';
	@override String get remoteHosts => 'Hosts remotos';
}

// Path: settings.page.general
class _Translations$settings$page$general$es extends Translations$settings$page$general$en {
	_Translations$settings$page$general$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionAgent => 'Agente';
	@override String get enableAgentsTitle => 'Activar agentes';
	@override String get enableAgentsDesc => 'Muestra la opción de abrir pestañas de agente (pi). Cuando está desactivado, Cockpit funciona solo como workspace de terminal.';
	@override String get showCockpitTitle => 'Mostrar terminal de Cockpit';
	@override String get showCockpitDesc => 'Mantiene un workspace sin carpeta, solo de terminal, fijado en la parte superior de la barra lateral. Desactivarlo cierra sus terminales.';
	@override String get launchAtStartupTitle => 'Iniciar al arrancar';
	@override String get launchAtStartupDesc => 'Inicia Cockpit automáticamente cuando inicias sesión en tu computadora.';
	@override String get sectionUpdates => 'Actualizaciones';
	@override String get checkUpdatesTitle => 'Buscar actualizaciones';
	@override String get checkUpdatesDesc => 'Con qué frecuencia Cockpit debe buscar nuevas versiones.';
	@override String get agentsInUseError => 'No se pueden desactivar los agentes mientras haya una pestaña de agente abierta. Cierra todas las pestañas de agente primero y luego desactívalo.';
	@override late final _Translations$settings$page$general$updateFrequency$es updateFrequency = _Translations$settings$page$general$updateFrequency$es._(_root);
}

// Path: settings.page.diagnostics
class _Translations$settings$page$diagnostics$es extends Translations$settings$page$diagnostics$en {
	_Translations$settings$page$diagnostics$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Diagnóstico';
	@override String get logFileTitle => 'Archivo de registro';
	@override String logFileDesc({required Object days, required Object path}) => 'Los errores y eventos de inicio se registran aquí, y se conservan durante ${days} días.\n${path}';
	@override String get unavailable => 'no disponible';
	@override String get reveal => 'Mostrar';
	@override String get reportTitle => 'Reportar un problema';
	@override String get reportDesc => 'Abre un issue prellenado con tu versión, SO y registro reciente. Nada se envía automáticamente — lo revisas antes.';
	@override String get reportButton => 'Reportar…';
	@override String get reportDialogTitle => 'Informe de problema';
	@override String get reportDialogError => 'Reportado manualmente desde Configuración.';
	@override String get reportDialogDescription => 'Describe qué salió mal en el issue. El registro reciente está incluido abajo y en "Copiar detalles".';
}

// Path: settings.page.storage
class _Translations$settings$page$storage$es extends Translations$settings$page$storage$en {
	_Translations$settings$page$storage$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Almacenamiento';
	@override String get locationTitle => 'Ubicación de almacenamiento';
	@override String locationDesc({required Object root}) => 'Cockpit guarda aquí sus proyectos, diseños y configuración. Apúntalo a una carpeta sincronizada para respaldarlo.\n${root}';
	@override String get useDefault => 'Usar predeterminado';
	@override String get working => 'Procesando…';
	@override String get change => 'Cambiar…';
	@override String get resetTitle => 'Restablecer Cockpit';
	@override String get resetDesc => 'Elimina todos los datos locales — proyectos, diseños, configuración e historial de terminal — y vuelve a la ubicación predeterminada.';
	@override String get resetButton => 'Restablecer…';
	@override String get resetConfirm => 'Restablecer';
	@override String get resetDialogTitle => '¿Restablecer Cockpit?';
	@override String get resetDialogContent => 'Esto elimina permanentemente todos los datos locales de Cockpit — proyectos, diseños, configuración e historial de terminal. Esto no se puede deshacer. Cockpit se cerrará para que puedas empezar de nuevo.';
	@override String get restartRequiredTitle => 'Reinicio necesario';
	@override String restartChangeFolderMessage({required Object path}) => 'Cockpit usará esta carpeta a partir del próximo inicio:\n${path}';
	@override String get restartUseDefaultMessage => 'Cockpit usará la ubicación predeterminada del sistema a partir del próximo inicio. Tus datos en la carpeta personalizada permanecen intactos.';
	@override String get restartResetMessage => 'Se borraron todos los datos de Cockpit. Reinicia para empezar de nuevo.';
	@override String get later => 'Más tarde';
	@override String get quitCockpit => 'Salir de Cockpit';
	@override String get chooseFolderDialogTitle => 'Elige una carpeta para los datos de Cockpit';
}

// Path: settings.page.terminal
class _Translations$settings$page$terminal$es extends Translations$settings$page$terminal$en {
	_Translations$settings$page$terminal$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionDefaultTerminal => 'Terminal predeterminado';
	@override String get engineTitle => 'Motor';
	@override String get engineDesc => 'Usado por nuevas pestañas de terminal y buffers de salida de tasks. Las pestañas abiertas mantienen su motor actual.';
	@override String get shellTitle => 'Shell';
	@override String get shellDesc => 'Qué shell abren las nuevas pestañas de terminal. La flecha junto al + sigue abriendo cualquier otro, solo para esa pestaña.';
	@override String get noWslMessage => 'No se encontraron distros de WSL. Instala una (wsl.exe --install) y reinicia Cockpit para verla listada aquí.';
}

// Path: settings.page.appearance
class _Translations$settings$page$appearance$es extends Translations$settings$page$appearance$en {
	_Translations$settings$page$appearance$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTheme => 'Tema';
	@override String get themeTitle => 'Tema';
	@override String get themeDesc => 'Colores de la app, resaltado de código y paleta del terminal.';
	@override String get modeTitle => 'Modo';
	@override String get modeDesc => 'Qué variante del tema usar.';
	@override String modeOnlyDark({required Object theme}) => '"${theme}" solo trae la variante oscura, así que esto no tiene efecto.';
	@override String modeOnlyLight({required Object theme}) => '"${theme}" solo trae la variante clara, así que esto no tiene efecto.';
	@override String get themeFileTitle => 'Archivo de tema';
	@override String get themeFileDesc => 'Importa un tema desde un archivo JSON, o exporta el activo.';
	@override String get previewCode => 'Código';
	@override String get previewTerminal => 'Terminal';
	@override String get themeSystem => 'Sistema';
	@override String get themeLight => 'Claro';
	@override String get themeDark => 'Oscuro';
	@override String get sectionFonts => 'Fuentes';
	@override String get interfaceFontTitle => 'Fuente de la interfaz';
	@override String get interfaceFontDesc => 'Se usa en toda la aplicación. Vacío = predeterminado del sistema.';
	@override String get interfaceSizeTitle => 'Tamaño de la interfaz';
	@override String get codeFontTitle => 'Fuente del código';
	@override String get codeFontDesc => 'Código y diffs. Vacío = predeterminado del sistema.';
	@override String get codeSizeTitle => 'Tamaño del código';
	@override String get terminalFontTitle => 'Fuente del terminal';
	@override String get terminalFontDesc => 'Solo la terminal. Vacío = predeterminado del sistema.';
	@override String get terminalSizeTitle => 'Tamaño de la terminal';
	@override String get terminalSizeDesc => 'Apagado = sigue el tamaño del código.';
	@override String get terminalSizeInherit => 'Seguir el código';
	@override String get terminalWeightTitle => 'Grosor de la terminal';
	@override String get terminalWeightDesc => 'Las pantallas de baja densidad engrosan los trazos. El automático los afina solo ahí y no toca la Retina.';
	@override String get terminalWeightAuto => 'Automático (según la pantalla)';
	@override String get terminalWeightLight => 'Fino';
	@override String get terminalWeightNormal => 'Normal';
	@override String get terminalWeightMedium => 'Medio';
	@override String get terminalWeightSemiBold => 'Seminegrita';
	@override String get sectionConversation => 'Conversación';
	@override String get pinUserMessageTitle => 'Fijar mensaje del usuario';
	@override String get pinUserMessageDesc => 'La pregunta permanece fija arriba mientras la respuesta se desplaza.';
	@override String get importTheme => 'Importar…';
	@override String get exportTheme => 'Exportar…';
	@override String get deleteTheme => 'Eliminar';
	@override String get importThemeDialog => 'Elige un archivo de tema';
	@override String get exportThemeDialog => 'Guardar tema como';
	@override String themeImported({required Object name}) => 'Tema "${name}" importado.';
	@override String get themeExported => 'Tema guardado.';
	@override String get themeDeleted => 'Tema eliminado.';
	@override String get fontPickerTitle => 'Elegir una fuente';
	@override String get fontPickerSearch => 'Buscar fuentes';
	@override String get fontPickerEmpty => 'No hay ninguna fuente coincidente en esta máquina.';
	@override String get fontPickerBundled => 'incluida';
	@override String get fontPickerCustom => '¿No está en la lista? Escribe el nombre exacto de la familia.';
	@override String get fontPickerCustomHint => 'Nombre de la familia';
	@override String get fontPickerUse => 'Usar';
	@override String get fontPickerDefault => 'Predeterminada';
	@override String get fontMissing => 'No se encontró en esta máquina — usando el respaldo.';
	@override String get sectionLayout => 'Diseño';
	@override String get swapPanelsTitle => 'Invertir paneles';
	@override String get swapPanelsDesc => 'Coloca los workspaces a la derecha y archivos, búsqueda, git y base de datos a la izquierda.';
}

// Path: settings.page.notifications
class _Translations$settings$page$notifications$es extends Translations$settings$page$notifications$en {
	_Translations$settings$page$notifications$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Notificaciones';
	@override String get enableTitle => 'Activar notificaciones';
	@override String get enableDesc => 'Avisarme cuando un agente termine un turno y la ventana no esté enfocada.';
	@override String get systemPermissionTitle => 'Permiso del sistema';
	@override String get grantedDesc => 'Cockpit tiene permiso para enviar notificaciones.';
	@override String get notGrantedDesc => 'macOS aún no ha concedido acceso a las notificaciones.';
	@override String get granted => 'Concedido';
	@override String get requestPermission => 'Solicitar permiso';
	@override String get soundsTitle => 'Sonidos';
	@override String get soundVolumeTitle => 'Volumen';
	@override String get soundTurnDone => 'Turno completado';
	@override String get soundTurnDoneDesc => 'Un agente terminó su turno.';
	@override String get soundActionRequired => 'Acción requerida';
	@override String get soundActionRequiredDesc => 'Un agente está esperando tu aprobación o respuesta.';
	@override String get soundAgentError => 'Error del agente';
	@override String get soundAgentErrorDesc => 'El proceso de un agente se detuvo inesperadamente.';
	@override String get soundDefault => 'Predeterminado';
	@override String soundCustom({required Object name}) => 'Personalizado: ${name}';
	@override String get soundChooseFile => 'Elegir archivo';
	@override String get soundReset => 'Volver al predeterminado';
	@override String get soundOnActiveTab => 'Reproducir también con la pestaña activa';
	@override String get soundPreview => 'Escuchar';
}

// Path: settings.page.shortcuts
class _Translations$settings$page$shortcuts$es extends Translations$settings$page$shortcuts$en {
	_Translations$settings$page$shortcuts$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get notCustomizable => 'Los atajos de teclado aún no se pueden personalizar.';
}

// Path: settings.page.languages
class _Translations$settings$page$languages$es extends Translations$settings$page$languages$en {
	_Translations$settings$page$languages$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionFormatting => 'FORMATO';
	@override String get formatOnSaveTitle => 'Formatear al guardar';
	@override String get formatOnSaveDesc => 'Formatea el archivo automáticamente al guardar (⌘S).';
	@override String get sectionLanguageServers => 'SERVIDORES DE LENGUAJE';
	@override String get footerNote => 'Los errores y el formato usan el language server de cada lenguaje. Cockpit no instala servidores — usa lo que ya está en tu máquina. ● responde · ○ no encontrado o comando inválido (instala el servidor o ajusta el comando).';
	@override String get serverCommandLabel => 'Comando del language server';
	@override String get formatterCommandLabel => 'Comando del formateador (opcional)';
	@override String get formatterHint => 'Formateador externo con el marcador %FILE%. Tiene prioridad sobre el formateador del LSP cuando está definido.';
	@override String get resetToDefault => 'Restablecer al predeterminado';
	@override String get saveAndRestart => 'Guardar y reiniciar';
	@override String get statusResponds => 'El servidor responde';
	@override String get statusNotFound => 'Servidor no encontrado o comando inválido';
}

// Path: settings.page.connectivity
class _Translations$settings$page$connectivity$es extends Translations$settings$page$connectivity$en {
	_Translations$settings$page$connectivity$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionRelay => 'Relay';
	@override String get sectionPairedDevices => 'Dispositivos vinculados';
	@override String get reloadTooltip => 'Recargar';
	@override String get failedToListDevices => 'No se pudieron listar los dispositivos.';
	@override String get noPairedDevices => 'No hay dispositivos vinculados.';
	@override String get relayAddressTitle => 'Dirección del relay';
	@override String get relayAddressDesc => 'Servidor que conecta tus agentes con el teléfono. Se aplica a todo agente con el relay activado.';
	@override String get saving => 'Guardando…';
	@override String get check => 'Comprobar';
	@override String get healthOnline => 'En línea';
	@override String get healthNoResponse => 'Sin respuesta';
	@override String get healthNotChecked => 'No comprobado';
	@override String get deviceDefaultLabel => 'Dispositivo';
	@override String get revoke => 'Revocar';
	@override String get pairNewDevice => 'Vincular nuevo dispositivo';
	@override String get revokeDialogTitle => '¿Revocar dispositivo?';
	@override String revokeDialogContent({required Object name}) => '"${name}" perderá el acceso a tus agentes y deberá vincularse de nuevo.\n\nDebes estar conectado al relay — la app se conectará automáticamente para revocar.';
}

// Path: settings.page.schedules
class _Translations$settings$page$schedules$es extends Translations$settings$page$schedules$en {
	_Translations$settings$page$schedules$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionScheduledPrompts => 'Prompts programados';
	@override String get createSchedule => 'Crear programación';
	@override String get createDaemonFirst => 'Crea primero un Agente Daemon.';
	@override String get supervisorOffline => 'Supervisor sin conexión. Las programaciones necesitan que pi-supervisord esté en ejecución (`remote-pi install`).';
	@override String get failedToListSchedules => 'No se pudieron listar las programaciones.';
	@override String get noSchedules => 'Sin programaciones. Crea un prompt recurrente para un daemon.';
	@override String get runNow => 'Ejecutar ahora';
	@override String get viewLog => 'Ver registro';
	@override String get disabled => 'desactivado';
	@override String nextRun({required Object when}) => 'próximo ${when}';
	@override String lastRun({required Object label}) => 'último: ${label}';
	@override String get removeScheduleDialogTitle => '¿Quitar programación?';
	@override String removeScheduleDialogContent({required Object schedule, required Object daemon}) => 'El job "${schedule}" de ${daemon} se elimina. Sus ejecuciones se detienen.';
	@override String get newScheduleTitle => 'Nueva programación';
	@override String get daemonLabel => 'Daemon';
	@override String get whenLabel => 'Cuándo (expresión cron)';
	@override String get previewPlaceholder => 'La próxima ejecución aparece aquí';
	@override String get previewComputed => 'Próximo: calculado al guardar';
	@override String previewNext({required Object when}) => 'Próximo: ${when}';
	@override String get exampleEveryDay9am => 'todos los días a las 9h';
	@override String get exampleHourly => 'cada hora';
	@override String get exampleEvery15Min => 'cada 15 min';
	@override String get exampleWeekdays6pm => 'días laborables a las 18h';
	@override String get promptLabel => 'Prompt';
	@override String get timezoneLabel => 'Zona horaria (opcional)';
	@override String get skipIfBusy => 'Omitir si el agente está ocupado';
	@override String get wakeIfStopped => 'Despertar el daemon si está detenido';
	@override String get catchup => 'Recuperar 1 ejecución perdida (catchup)';
	@override String get fillRequiredError => 'Completa la expresión y el prompt.';
	@override String get creating => 'Creando…';
	@override String get failedToCreateSchedule => 'No se pudo crear la programación.';
	@override String historyTitle({required Object schedule}) => 'Historial — ${schedule}';
	@override String get failedToReadLog => 'No se pudo leer el registro.';
	@override String get noRecordsYet => 'Aún no hay registros.';
	@override String get cronDelivered => 'entregado';
	@override String get cronWokeDelivered => 'despertó + entregado';
	@override String get cronFailed => 'falló';
	@override String get cronSkippedBusy => 'omitido (ocupado)';
	@override String get cronSkippedStopped => 'omitido (detenido)';
	@override String get cronSkippedDisabled => 'omitido (desactivado)';
}

// Path: settings.page.daemons
class _Translations$settings$page$daemons$es extends Translations$settings$page$daemons$en {
	_Translations$settings$page$daemons$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionAlwaysOnAgents => 'Agentes siempre activos';
	@override String get createDaemon => 'Crear daemon';
	@override String get startAll => 'Iniciar todos';
	@override String get stopAll => 'Detener todos';
	@override String get restartAll => 'Reiniciar todos';
	@override String get restartSupervisor => 'Reiniciar supervisor';
	@override String get restartSupervisorDialogTitle => '¿Reiniciar el supervisor?';
	@override String get restartSupervisorDialogContent => 'Reinicia el proceso del supervisor (recarga el código). Todos los daemons se reinician con él y quedan sin conexión unos segundos.';
	@override String get removeDaemonDialogTitle => '¿Quitar daemon?';
	@override String removeDaemonDialogContent({required Object name}) => '"${name}" deja de ejecutarse y sale del registro. La carpeta y su configuración local se conservan — puedes recrearlo después.';
	@override String get supervisorOfflineTitle => 'Supervisor sin conexión';
	@override String get supervisorOfflineDesc => 'pi-supervisord no se está ejecutando. Instálalo con `remote-pi install` para gestionar agentes 24/7.';
	@override String get failedToListDaemons => 'No se pudieron listar los daemons.';
	@override String get noRegisteredAgents => 'Sin agentes registrados. Crea uno a partir de una carpeta.';
	@override String get start => 'Iniciar';
	@override String get stop => 'Detener';
	@override String get edit => 'Editar';
	@override String get stateRunning => 'en ejecución';
	@override String get stateStarting => 'iniciando';
	@override String get stateStopped => 'detenido';
	@override String get stateFailed => 'falló';
	@override String get newDaemonTitle => 'Nuevo daemon';
	@override String get editDaemonTitle => 'Editar daemon';
	@override String get nameLabel => 'Nombre';
	@override String get namePlaceholder => 'ej.: PC, Servidor, Casa';
	@override String get nameRequiredError => 'Escribe un nombre.';
	@override String get nameDuplicateError => 'Ya existe un agente con ese nombre.';
	@override String get folderLabel => 'Carpeta';
	@override String get noFolderChosen => 'Ninguna carpeta elegida';
	@override String get choose => 'Elegir';
	@override String get changeFolder => 'Cambiar';
	@override String get folderCannotBeChanged => 'La carpeta no se puede cambiar.';
	@override String get folderRequiredError => 'Elige una carpeta.';
	@override String get folderDuplicateError => 'Ya existe un agente en esta carpeta.';
	@override String get pickFolderDialogTitle => 'Elige la carpeta del Agente Daemon';
}

// Path: settings.page.automations
class _Translations$settings$page$automations$es extends Translations$settings$page$automations$en {
	_Translations$settings$page$automations$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionCommitMessages => 'Mensajes de commit';
	@override String get harness => 'Harness';
	@override String get harnessDiscovering => 'Buscando harnesses de línea de comandos instalados…';
	@override String get harnessNoneFound => 'No se encontró ningún harness compatible en el PATH.';
	@override String harnessConfiguredUnavailable({required Object harness}) => '${harness} está configurado, pero no disponible.';
	@override String get harnessChoose => 'Elige la CLI usada para generar mensajes de commit.';
	@override String get harnessRefresh => 'Actualizar harnesses instalados';
	@override String get notConfigured => 'Sin configurar';
	@override String get model => 'Modelo';
	@override String get modelUnavailable => 'La lista de modelos no está disponible hasta encontrar el harness.';
	@override String get modelCliOnly => 'Este harness usa el modelo predeterminado de su CLI.';
	@override String get modelCliDefault => 'Predeterminado de la CLI';
	@override String get modelAuto => 'Auto';
	@override String modelSearch({required Object count}) => 'Buscar entre ${count} modelos…';
	@override String get modelAutoRouted => 'Este harness elige el modelo automáticamente.';
	@override String get modelAccountOnly => 'Solo se muestran los modelos disponibles en tu cuenta.';
	@override String get generateFromSourceControl => 'Generar desde Control de versiones';
	@override String get generateFromSourceControlDescription => 'Cockpit envía solo el diff seleccionado y los asuntos de los commits recientes. Los patrones habituales de credenciales y los archivos sensibles se redactan antes de ejecutar el harness.';
	@override String get discoveryFailed => 'No se pudieron descubrir los harnesses de automatización instalados.';
	@override String staleModel({required Object model, required Object harness}) => 'El modelo "${model}" ya no está disponible para ${harness}. Se usará el predeterminado de la CLI; elige otro modelo en Configuración si lo necesitas.';
	@override String get recommendedSuffix => 'Recomendado';
}

// Path: settings.page.general.updateFrequency
class _Translations$settings$page$general$updateFrequency$es extends Translations$settings$page$general$updateFrequency$en {
	_Translations$settings$page$general$updateFrequency$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get daily => 'Diariamente';
	@override String get weekly => 'Semanalmente';
	@override String get monthly => 'Mensualmente';
	@override String get never => 'Nunca';
}

/// The flat map containing all translations for locale <es>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'core.bootstrapError.title' => 'No se pudo inicializar Cockpit',
			'core.bootstrapError.retry' => 'Reintentar',
			'core.macosNotifications.title' => 'Activar notificaciones en macOS',
			'core.macosNotifications.intro' => 'Las notificaciones están desactivadas en la configuración del sistema. Sigue los pasos a continuación para activarlas:',
			'core.macosNotifications.step1' => 'Abre los Ajustes del Sistema en tu Mac.',
			'core.macosNotifications.step2' => 'Ve a la sección Notificaciones en la barra lateral izquierda.',
			'core.macosNotifications.step3' => 'Busca y selecciona la aplicación Cockpit en la lista.',
			'core.macosNotifications.step4' => 'Activa el interruptor Permitir Notificaciones.',
			'core.macosNotifications.tip' => 'Consejo: si la aplicación no aparece en la lista, ciérrala y vuelve a abrirla para activar su registro en el sistema.',
			'core.macosNotifications.gotIt' => 'Entendido',
			'core.appErrorView.renderFailed' => 'Esta parte de la aplicación no se pudo renderizar',
			'core.appErrorView.details' => 'Detalles',
			'core.appErrorView.renderErrorTitle' => 'Error de renderizado',
			'core.errorReportDialog.defaultDescription' => 'Algo salió mal. Los detalles a continuación se guardaron en el registro — puedes reportarlos para que se solucione.',
			'core.errorReportDialog.copyDetails' => 'Copiar detalles',
			'core.errorReportDialog.reportIssue' => 'Reportar problema',
			'core.windowControls.minimize' => 'Minimizar',
			'core.windowControls.maximize' => 'Maximizar',
			'core.windowControls.close' => 'Cerrar',
			'core.crash.title' => 'Cierre inesperado',
			'core.crash.bannerTitle' => 'Cockpit se cerró inesperadamente',
			'core.crash.report' => 'Reportar',
			'core.crash.dismiss' => 'Descartar',
			'core.crash.crashMessage' => ({required Object version}) => 'La sesión anterior (versión ${version}) terminó sin cerrarse correctamente. ¿Quieres reportarlo? El log se incluye y puedes revisar todo antes de enviar.',
			'core.crash.crashError' => ({required Object startedAt, required Object pid}) => 'La sesión iniciada el ${startedAt} (pid ${pid}) terminó sin un cierre limpio.',
			'core.crash.crashDescription' => 'No se capturó ningún error: el sistema terminó la app. El log de abajo es de esa sesión y es la parte más útil.',
			'core.menu.settings' => 'Configuración…',
			'core.menu.checkForUpdates' => 'Buscar Actualizaciones…',
			'core.menu.file' => 'Archivo',
			'core.menu.newAgent' => 'Nuevo Agente',
			'core.menu.newTerminal' => 'Nueva Terminal',
			'core.menu.openWorkspace' => 'Abrir Workspace',
			'core.menu.save' => 'Guardar',
			'core.menu.discard' => 'Descartar',
			'core.menu.format' => 'Formatear',
			'core.menu.view' => 'Ver',
			'core.menu.toggleWorkspacePanel' => 'Alternar Panel de Workspaces',
			'core.menu.toggleFiles' => 'Alternar Archivos',
			'core.menu.splitRight' => 'Dividir a la Derecha',
			'core.menu.splitDown' => 'Dividir Abajo',
			'core.menu.focusPane' => 'Enfocar Panel',
			'core.menu.focusLeft' => 'Izquierda  (⌘⌥←)',
			'core.menu.focusRight' => 'Derecha  (⌘⌥→)',
			'core.menu.focusUp' => 'Arriba  (⌘⌥↑)',
			'core.menu.focusDown' => 'Abajo  (⌘⌥↓)',
			'core.menu.selectTab' => 'Seleccionar Pestaña',
			'core.menu.tabN' => ({required Object n}) => 'Pestaña ${n}',
			'core.menu.lastTab' => 'Última Pestaña',
			'core.menu.zoomIn' => 'Acercar',
			'core.menu.zoomOut' => 'Alejar',
			'core.menu.actualSize' => 'Tamaño Real',
			'core.menu.window' => 'Ventana',
			'core.menu.quit' => 'Salir',
			'core.menu.minimize' => 'Minimizar',
			'core.menu.zoom' => 'Zoom',
			'common.cancel' => 'Cancelar',
			'common.confirm' => 'Confirmar',
			'common.create' => 'Crear',
			'common.gotIt' => 'Entendido',
			'common.save' => 'Guardar',
			'common.close' => 'Cerrar',
			'common.delete' => 'Eliminar',
			'common.done' => 'Listo',
			'common.add' => 'Añadir',
			'common.test' => 'Probar',
			'common.ok' => 'OK',
			'common.loading' => 'Cargando…',
			'common.checking' => 'Comprobando…',
			'common.remove' => 'Quitar',
			'common.restart' => 'Reiniciar',
			'common.settings' => 'Configuración',
			'common.send' => 'Enviar',
			'common.open' => 'Abrir',
			'common.dismiss' => 'Descartar',
			'common.report' => 'Reportar',
			'common.copyCode' => 'Copiar código',
			'common.search' => 'Buscar',
			'common.noResults' => 'Sin resultados',
			'cockpit.confirmDialog.unsavedChangesTitle' => 'Cambios sin guardar',
			'cockpit.confirmDialog.unsavedChangesMessage' => ({required Object fileName}) => '“${fileName}” tiene cambios sin guardar. ¿Guardarlos antes de cerrar?',
			'cockpit.confirmDialog.dontSave' => 'No guardar',
			'cockpit.confirmDialog.saveAndClose' => 'Guardar y cerrar',
			'cockpit.historyDialog.title' => 'Historial de sesiones',
			'cockpit.historyDialog.subtitle' => 'Abrir una reemplaza la transcripción actual de este agente',
			'cockpit.historyDialog.empty' => 'No hay sesiones guardadas en esta carpeta.',
			'cockpit.historyDialog.untitledSession' => 'Sesión sin título',
			'cockpit.historyDialog.justNow' => 'ahora',
			'cockpit.historyDialog.minutesAgo' => ({required Object n}) => 'hace ${n} min',
			'cockpit.historyDialog.hoursAgo' => ({required Object n}) => 'hace ${n} h',
			'cockpit.historyDialog.daysAgo' => ({required Object n}) => 'hace ${n} d',
			'cockpit.worktreeCreateDialog.forkTitle' => 'Fork del worktree',
			'cockpit.worktreeCreateDialog.createTitle' => 'Crear worktree',
			'cockpit.worktreeCreateDialog.forkSubtitle' => ({required Object root}) => 'Nueva worktree ramificada desde ${root}.',
			'cockpit.worktreeCreateDialog.createSubtitle' => ({required Object root}) => 'Nueva feature en ${root} — nueva branch desde el HEAD actual.',
			'cockpit.worktreeCreateDialog.namePlaceholder' => 'feat/mi-feature',
			'cockpit.worktreeCreateDialog.errorWhitespace' => 'Sin espacios en el nombre.',
			'cockpit.worktreeCreateDialog.errorInvalidChar' => 'Carácter inválido para un nombre de branch.',
			'cockpit.worktreeCreateDialog.errorInvalidSequence' => 'Secuencia inválida (ej.: "..", "//", empezar/terminar con "/").',
			'cockpit.worktreeCreateDialog.errorReserved' => 'Posición reservada (no empieces con "-"/"." ni termines con ".lock").',
			'cockpit.worktreeCreateDialog.errorDuplicateBranch' => 'Ya existe una branch con ese nombre.',
			'cockpit.worktreeCreateDialog.errorDuplicateWorktree' => 'Ya existe un worktree con ese nombre.',
			'cockpit.worktreeCreateDialog.errorBranchHierarchyConflict' => ({required Object target, required Object existing}) => 'No se puede crear la branch \'${target}\' porque entra en conflicto con la branch \'${existing}\' ya existente.',
			'cockpit.worktreeCreateDialog.errorBranchHierarchicalConflictGeneral' => 'Ya existe una branch con una jerarquía conflictiva.',
			'cockpit.worktreeCreateDialog.fork' => 'Fork',
			'cockpit.worktreeCreateDialog.postCheckoutHint' => 'Este repositorio tiene un hook post-checkout.',
			'cockpit.worktreeCreateDialog.running' => 'Ejecutando…',
			'cockpit.worktreeCreateDialog.advancedSettings' => 'Configuración Avanzada',
			'cockpit.worktreeCreateDialog.copyIgnored' => 'Copiar archivos ignorados (.gitignore)',
			'cockpit.worktreeCreateDialog.copyIgnoredDesc' => 'Copia los archivos ignorados por .gitignore (ej. .env, claves locales) al nuevo worktree.',
			'cockpit.worktreeCreateDialog.copyUntracked' => 'Copiar archivos no rastreados',
			'cockpit.worktreeCreateDialog.copyUntrackedDesc' => 'Copia los archivos nuevos o modificados que aún no se han agregado al stage.',
			'cockpit.worktreeCreateDialog.baseBranch' => 'Branch base',
			'cockpit.worktreeCreateDialog.baseBranchDesc' => 'La branch desde la cual se creará el nuevo worktree y branch.',
			'cockpit.worktreeCreateDialog.fetchRemote' => 'Sincronizar branch remota (fetch)',
			'cockpit.worktreeCreateDialog.fetchRemoteDesc' => 'Ejecuta git fetch para garantizar que la branch base esté confirmada antes de crear el worktree.',
			'cockpit.worktreeCreateDialog.searchBranch' => 'Buscar branch...',
			'cockpit.worktreeCreateDialog.back' => 'Atrás',
			'cockpit.subfolderDialog.title' => '¿Dónde trabajar?',
			'cockpit.subfolderDialog.empty' => 'No hay subcarpetas aquí.',
			'cockpit.subfolderDialog.useRoot' => ({required Object project}) => 'Usar la raíz de ${project}',
			'cockpit.subfolderDialog.usePath' => ({required Object project, required Object rel}) => 'Usar ${project}/${rel}',
			'cockpit.subfolderDialog.useThisFolder' => 'Usar esta carpeta',
			'cockpit.commitMessageDialog.commitTitle' => 'Commit',
			'cockpit.commitMessageDialog.stageAndCommitTitle' => 'Stage y Commit',
			'cockpit.commitMessageDialog.scopeNote' => ({required Object fileName}) => 'Commit solo de "${fileName}".',
			'cockpit.commitMessageDialog.placeholder' => 'fix: resumen breve del cambio',
			'cockpit.commitMessageDialog.errorEmptySubject' => 'La primera línea (asunto) no puede estar vacía.',
			'cockpit.commitMessageDialog.errorTooShort' => ({required Object min}) => 'Asunto demasiado corto (mín. ${min} caracteres).',
			'cockpit.commitMessageDialog.errorTooLong' => ({required Object max}) => 'Asunto demasiado largo (máx. ${max} caracteres).',
			'cockpit.commitMessageDialog.errorTrailingPeriod' => 'El asunto no debe terminar con un punto.',
			'cockpit.commitMessageDialog.errorControlChars' => 'El asunto contiene caracteres de control.',
			'cockpit.commitMessageDialog.errorBlankSecondLine' => 'Deja la segunda línea en blanco (separador entre asunto y cuerpo de git).',
			'cockpit.commitMessageDialog.generate' => 'Generar mensaje de commit',
			'cockpit.commitMessageDialog.generateWith' => ({required Object harness}) => 'Generar con ${harness}',
			'cockpit.commitMessageDialog.generating' => 'Generando…',
			'cockpit.commitMessageDialog.cancelGeneration' => 'Cancelar generación',
			'cockpit.agentEditDialog.title' => 'Editar agente',
			'cockpit.agentEditDialog.agentName' => 'Nombre del agente',
			'cockpit.agentEditDialog.relaySection' => 'Relay (remote-pi)',
			'cockpit.agentEditDialog.autoConnect' => 'Conectar automáticamente al iniciar',
			'cockpit.agentEditDialog.informationSection' => 'Información',
			'cockpit.agentEditDialog.folder' => 'Carpeta',
			'cockpit.agentEditDialog.model' => 'Modelo',
			'cockpit.agentEditDialog.state' => 'Estado',
			'cockpit.agentEditDialog.context' => 'Contexto',
			'cockpit.agentEditDialog.statusEmpty' => 'vacío',
			'cockpit.agentEditDialog.statusStarting' => 'iniciando',
			'cockpit.agentEditDialog.statusReady' => 'listo',
			'cockpit.agentEditDialog.statusStreaming' => 'transmitiendo',
			'cockpit.agentEditDialog.statusEnded' => 'finalizado',
			'cockpit.agentSetupChecklist.title' => 'Configurar el entorno del agente',
			'cockpit.agentSetupChecklist.intro' => 'Ejecutar un agente requiere tener Pi instalado. Completa los pasos siguientes — las terminales y los archivos funcionan sin nada de esto.',
			'cockpit.agentSetupChecklist.step1Title' => 'Pi Code instalado',
			'cockpit.agentSetupChecklist.step1Description' => 'El binario `pi` debe estar accesible.',
			'cockpit.agentSetupChecklist.step2Title' => 'Extensión remote-pi en Pi',
			'cockpit.agentSetupChecklist.step2Description' => 'Registrada en ~/.pi/agent/settings.json.',
			'cockpit.agentSetupChecklist.step3Title' => 'Supervisor instalado',
			'cockpit.agentSetupChecklist.step3Description' => 'Servicio pi-supervisord (remote-pi install).',
			'cockpit.agentSetupChecklist.install' => 'Instalar',
			'cockpit.agentSetupChecklist.installExtensionTitle' => 'Instalar extensión remote-pi',
			'cockpit.agentSetupChecklist.installSupervisorTitle' => 'Instalar supervisor',
			'cockpit.agentSetupChecklist.createAgent' => 'Crear agente',
			'cockpit.agentSetupChecklist.back' => 'Atrás',
			'cockpit.agentSetupChecklist.checkAgain' => 'Comprobar de nuevo',
			'cockpit.agentSetupChecklist.notRequired' => 'No obligatorio en esta configuración',
			'cockpit.agentSetupChecklist.installing' => 'Instalando…',
			'cockpit.agentSetupChecklist.installedSuccessfully' => 'Instalado correctamente.',
			'cockpit.agentComposer.cmdNewDescription' => 'Nueva sesión — borra la conversación',
			'cockpit.agentComposer.cmdCompactDescription' => 'Compacta el contexto del agente',
			'cockpit.agentComposer.attachFile' => 'Adjuntar archivo',
			'cockpit.agentComposer.maxImages' => ({required Object max}) => 'Máximo de ${max} imágenes.',
			'cockpit.agentComposer.placeholder' => 'Mensaje para el agente, usa @files o /commands',
			'cockpit.agentComposer.stop' => 'Detener',
			'cockpit.agentComposer.send' => 'Enviar',
			'cockpit.agentComposer.relayOnline' => 'Relay en línea',
			'cockpit.agentComposer.relayReconnecting' => 'Relay reconectando...',
			'cockpit.agentComposer.relayOffline' => 'Relay sin conexión',
			'cockpit.agentComposer.contextTooltip' => ({required Object pct}) => 'Contexto: ${pct}% de la ventana',
			'cockpit.agentComposer.visionWarning' => 'El modelo actual no puede ver imágenes — cambia a uno con soporte de visión.',
			'cockpit.agentComposer.modelFallback' => 'modelo',
			'cockpit.tasksPanel.reloadTasksTooltip' => 'Recargar tasks',
			'cockpit.tasksPanel.restartTooltip' => 'Reiniciar',
			'cockpit.tasksPanel.stopTooltip' => 'Detener',
			'cockpit.tasksPanel.runTooltip' => 'Ejecutar',
			'cockpit.tasksPanel.sendsKeyTooltip' => ({required Object label, required Object key}) => '${label} (envía \'${key}\')',
			'cockpit.tasksPanel.startingTooltip' => 'Iniciando…',
			'cockpit.tasksPanel.stoppingTooltip' => 'Deteniendo…',
			'cockpit.tasksPanel.switchProfileTooltip' => 'Cambiar perfil',
			'cockpit.tasksPanel.moreKeysTooltip' => 'Más teclas',
			'cockpit.tasksPanel.sectionTasks' => 'TAREAS',
			'cockpit.tasksPanel.noTasks' => 'No se detectaron tareas en este proyecto.',
			'cockpit.tasksPanel.createTasksJson' => 'Crear tasks.json',
			'cockpit.cockpitPage.chooseProjectFolderDialogTitle' => 'Elige la carpeta del proyecto',
			'cockpit.cockpitPage.chooseWorkspaceFolderDialogTitle' => 'Elige la carpeta del workspace',
			'cockpit.cockpitPage.workspaceRenamedTitle' => 'Workspace renombrado',
			'cockpit.cockpitPage.workspaceRenamedMessage' => ({required Object name}) => 'El nuevo nombre "${name}" solo se enviará a los agentes tras reiniciar el workspace o la aplicación.',
			'cockpit.cockpitPage.syncTitle' => ({required Object label}) => 'Sync — ${label}',
			'cockpit.cockpitPage.pullTitle' => ({required Object label}) => 'Pull — ${label}',
			'cockpit.cockpitPage.pushTitle' => ({required Object label}) => 'Push — ${label}',
			'cockpit.cockpitPage.updateFromParentTitle' => ({required Object name}) => 'Actualizar desde el Padre — ${name}',
			'cockpit.cockpitPage.mergeToParentTitle' => ({required Object name}) => 'Merge al Padre — ${name}',
			'cockpit.cockpitPage.worktreeMergedAndRemoved' => 'Worktree fusionado y eliminado.',
			'cockpit.cockpitPage.nothingWasChanged' => 'No se realizaron cambios.',
			'cockpit.cockpitPage.newRealmTitle' => 'Nuevo realm',
			'cockpit.cockpitPage.closeWorkspaceTitle' => 'Cerrar workspace',
			'cockpit.cockpitPage.closeWorkspaceMessage' => ({required Object name}) => '¿Cerrar "${name}"? Los agentes de este workspace se cerrarán. La carpeta en el disco se conserva.',
			'cockpit.cockpitPage.closeAction' => 'Cerrar',
			'cockpit.cockpitPage.removeWorktreeTitle' => 'Quitar worktree',
			'cockpit.cockpitPage.removeWorktreeMessage' => ({required Object name, required Object warn}) => '¿Quitar "${name}"? La carpeta del worktree y la branch se eliminarán y los agentes de este fork se cerrarán.${warn}',
			'cockpit.cockpitPage.removeWorktreeWarning' => ({required Object name}) => '\n\nAdvertencia: la branch "${name}" aún no se ha fusionado — eliminarla (git branch -D) descarta el trabajo no fusionado.',
			'cockpit.cockpitPage.failedToRemoveWorktreeTitle' => 'No se pudo quitar el worktree',
			'cockpit.cockpitPage.openLayoutTitle' => 'Abrir layout',
			'cockpit.cockpitPage.restartServerTooltip' => 'Reiniciar servidor',
			'cockpit.cockpitPage.noLspAvailable' => 'Ningún LSP disponible',
			'cockpit.cockpitPage.lspRunning' => 'en ejecución',
			'cockpit.cockpitPage.lspStopped' => 'detenido',
			'cockpit.welcomeView.title' => 'Bienvenido a Cockpit',
			'cockpit.welcomeView.subtitle' => 'Abre una carpeta o conéctate a un host remoto para empezar.',
			'cockpit.welcomeView.createWorkspace' => 'Crear workspace',
			'cockpit.welcomeView.openLocalFolder' => 'Abrir carpeta local',
			'cockpit.welcomeView.connectHost' => 'Conectar a un host',
			'cockpit.welcomeView.configureHost' => 'Configurar host',
			'cockpit.welcomeView.addWorkspace' => 'Añadir workspace',
			'cockpit.modelPicker.search' => ({required Object count}) => 'Buscar modelo (${count})',
			'cockpit.paneView.closePaneTitle' => '¿Cerrar panel?',
			'cockpit.paneView.closePaneMessage' => ({required Object count}) => 'Esto cierra todas las ${count} pestaña(s) de este panel y finaliza los agentes/terminales en él.',
			'cockpit.paneView.close' => 'Cerrar',
			'cockpit.paneView.allTabs' => 'Todas las pestañas',
			'cockpit.paneView.pinTab' => 'Fijar pestaña',
			'cockpit.paneView.rename' => 'Renombrar',
			'cockpit.paneView.resetTitle' => 'Restablecer título',
			'cockpit.paneView.copyId' => 'Copiar Id',
			'cockpit.paneView.autoRelay' => 'Auto-relay',
			'cockpit.paneView.history' => 'Historial',
			'cockpit.paneView.newTab' => 'Nueva pestaña',
			'cockpit.paneView.newTerminal' => 'Nueva terminal…',
			'cockpit.paneView.splitRight' => 'Dividir a la derecha',
			'cockpit.paneView.splitDown' => 'Dividir abajo',
			'cockpit.paneView.closePane' => 'Cerrar panel',
			'cockpit.paneView.dropHereToMove' => 'Suelta aquí para mover la pestaña',
			'cockpit.paneView.dockAsTab' => 'Acoplar como pestaña',
			'cockpit.paneView.openBrowser' => 'Abrir navegador',
			'cockpit.paneView.openTerminal' => 'Abrir terminal',
			'cockpit.fileTreePanel.viewDiff' => 'Ver Diff',
			'cockpit.fileTreePanel.commit' => 'Commit',
			'cockpit.fileTreePanel.stageAndCommit' => 'Stage y Commit',
			'cockpit.fileTreePanel.unstage' => 'Quitar del stage',
			'cockpit.fileTreePanel.stageChanges' => 'Poner en stage',
			'cockpit.fileTreePanel.discardChanges' => 'Descartar cambios',
			'cockpit.fileTreePanel.enterCommitMessage' => 'Escribe un mensaje de commit.',
			'cockpit.fileTreePanel.commitUnavailable' => 'Commit no disponible para este workspace.',
			'cockpit.fileTreePanel.gitErrorTitle' => 'Error de Git',
			'cockpit.fileTreePanel.deleteNewFileTitle' => '¿Eliminar archivo nuevo?',
			'cockpit.fileTreePanel.discardChangesTitle' => '¿Descartar cambios?',
			'cockpit.fileTreePanel.deleteNewFileMessage' => ({required Object name}) => '"${name}" es un archivo nuevo y no se puede restaurar. ¿Eliminarlo?',
			'cockpit.fileTreePanel.discardOneMessage' => ({required Object name}) => '¿Descartar todos los cambios en "${name}"? Los archivos eliminados se restaurarán.',
			'cockpit.fileTreePanel.discard' => 'Descartar',
			'cockpit.fileTreePanel.deleteAllNewFilesTitle' => '¿Eliminar todos los archivos nuevos?',
			'cockpit.fileTreePanel.allNewFilesMessage' => ({required Object count}) => 'Los ${count} archivos son nuevos y se eliminarán. Esto no se puede deshacer.',
			'cockpit.fileTreePanel.discardTrackedMessage' => ({required Object count, required Object extra}) => '¿Descartar cambios en ${count} archivo(s) rastreado(s)?${extra}',
			'cockpit.fileTreePanel.discardTrackedExtra' => ({required Object count}) => ' Se mantendrán ${count} archivo(s) nuevo(s).',
			'cockpit.fileTreePanel.deleteAll' => 'Eliminar todo',
			'cockpit.fileTreePanel.deleteQuestionTitle' => '¿Eliminar?',
			'cockpit.fileTreePanel.moveToTrash' => ({required Object name}) => '¿Mover “${name}” a la Papelera?',
			'cockpit.fileTreePanel.permanentlyDelete' => ({required Object name}) => '¿Eliminar “${name}” de forma permanente? Esto no se puede deshacer.',
			'cockpit.fileTreePanel.couldNotDeleteTitle' => 'No se pudo eliminar',
			'cockpit.fileTreePanel.moveQuestionTitle' => '¿Mover?',
			'cockpit.fileTreePanel.moveMessage' => ({required Object name, required Object dest}) => '¿Mover “${name}” a “${dest}”?',
			'cockpit.fileTreePanel.moveAction' => 'Mover',
			'cockpit.fileTreePanel.couldNotMoveTitle' => 'No se pudo mover',
			'cockpit.fileTreePanel.couldNotPasteTitle' => 'No se pudo pegar',
			'cockpit.fileTreePanel.filesTooltip' => 'Archivos',
			'cockpit.fileTreePanel.searchTooltip' => 'Buscar',
			'cockpit.fileTreePanel.sourceControlTooltip' => 'Control de versiones',
			'cockpit.fileTreePanel.databaseTooltip' => 'Base de datos',
			'cockpit.fileTreePanel.sectionFiles' => 'ARCHIVOS',
			'cockpit.fileTreePanel.newFile' => 'Nuevo archivo',
			'cockpit.fileTreePanel.newFolder' => 'Nueva carpeta',
			'cockpit.fileTreePanel.refreshTooltip' => 'Actualizar',
			'cockpit.fileTreePanel.sectionSourceControl' => 'CONTROL DE VERSIONES',
			'cockpit.fileTreePanel.viewAsList' => 'Ver como lista',
			'cockpit.fileTreePanel.viewAsTree' => 'Ver como árbol',
			'cockpit.fileTreePanel.noFolderMessage' => 'Ninguna carpeta — abre un workspace.',
			'cockpit.fileTreePanel.amend' => 'Amend',
			'cockpit.fileTreePanel.commitMessagePlaceholder' => 'Mensaje del commit',
			'cockpit.fileTreePanel.amendCommit' => 'Amend del commit',
			'cockpit.fileTreePanel.lastCommit' => 'último commit',
			'cockpit.fileTreePanel.openInFinder' => 'Abrir en Finder',
			'cockpit.fileTreePanel.openInExplorer' => 'Abrir en el Explorador',
			'cockpit.fileTreePanel.openInFileManager' => 'Abrir en el gestor de archivos',
			'cockpit.fileTreePanel.open' => 'Abrir',
			'cockpit.fileTreePanel.openWith' => 'Abrir con',
			'cockpit.fileTreePanel.openLayout' => 'Abrir layout',
			'cockpit.fileTreePanel.showGitDiff' => 'Mostrar diff de git',
			'cockpit.fileTreePanel.createAgent' => 'Crear agente',
			'cockpit.fileTreePanel.createTerminal' => 'Crear terminal',
			'cockpit.fileTreePanel.rename' => 'Renombrar',
			'cockpit.fileTreePanel.copy' => 'Copiar',
			'cockpit.fileTreePanel.cut' => 'Cortar',
			'cockpit.fileTreePanel.paste' => 'Pegar',
			'cockpit.fileTreePanel.copyRelativePath' => 'Copiar ruta relativa',
			'cockpit.fileTreePanel.copyAbsolutePath' => 'Copiar ruta absoluta',
			'cockpit.fileTreePanel.renameFailed' => 'No se pudo renombrar.',
			'cockpit.fileTreePanel.noChanges' => 'Sin cambios.',
			'cockpit.fileTreePanel.stagedChangesHeader' => ({required Object count}) => 'CAMBIOS EN STAGE (${count})',
			'cockpit.fileTreePanel.changesHeader' => ({required Object count}) => 'CAMBIOS (${count})',
			'cockpit.fileTreePanel.discardAllChanges' => 'Descartar todos los cambios',
			'cockpit.fileTreePanel.unstageAllChanges' => 'Quitar todo del stage',
			'cockpit.fileTreePanel.stageAllChanges' => 'Poner todo en stage',
			'cockpit.fileTreePanel.discardFolderChanges' => 'Descartar cambios de la carpeta',
			'cockpit.fileTreePanel.unstageFolderChanges' => 'Quitar carpeta del stage',
			'cockpit.fileTreePanel.stageFolderChanges' => 'Poner carpeta en stage',
			'cockpit.fileTreePanel.generateCommitMessage' => 'Generar mensaje de commit',
			'cockpit.fileTreePanel.generateWith' => ({required Object harness}) => 'Generar con ${harness}',
			'cockpit.fileTreePanel.generateUnavailableWhileAmending' => 'No disponible mientras se enmienda un commit',
			'cockpit.fileTreePanel.cancelGeneration' => 'Cancelar generación',
			'cockpit.fileTreePanel.changes' => 'Cambios',
			'cockpit.fileTreePanel.history' => 'Historial',
			'cockpit.fileTreePanel.historyRepository' => 'Repositorio',
			'cockpit.fileTreePanel.historyNoRepository' => 'No hay ningun repositorio Git disponible.',
			'cockpit.fileTreePanel.historyEmpty' => 'No se encontraron commits.',
			'cockpit.fileTreePanel.historyLoadFailed' => 'No se pudo cargar el historial de Git.',
			'cockpit.fileTreePanel.historyUntitledCommit' => 'Commit sin titulo',
			'cockpit.fileTreePanel.historyNow' => 'ahora',
			'cockpit.fileTreePanel.historyMinutesAgo' => ({required Object count}) => 'hace ${count} min',
			'cockpit.fileTreePanel.historyHoursAgo' => ({required Object count}) => 'hace ${count} h',
			'cockpit.fileTreePanel.historyYesterday' => 'ayer',
			'cockpit.fileTreePanel.historyDayAgo' => 'hace 1 dia',
			'cockpit.fileTreePanel.historyDaysAgo' => ({required Object count}) => 'hace ${count} dias',
			'cockpit.fileTreePanel.historyFiles' => 'Archivos modificados',
			'cockpit.fileTreePanel.historyFilesEmpty' => 'No hay archivos modificados.',
			'cockpit.fileTreePanel.historyFilesLoadFailed' => 'No se pudieron cargar los archivos modificados.',
			'cockpit.fileTreePanel.diffEmptyTree' => 'Arbol vacio',
			'cockpit.fileTreePanel.diffOriginal' => ({required Object ref}) => 'Original ${ref}',
			'cockpit.fileTreePanel.diffModified' => ({required Object ref}) => 'Modificado ${ref}',
			'cockpit.fileTreePanel.diffWorkingTree' => 'Directorio de trabajo',
			'cockpit.fileTreePanel.diffBinaryFile' => 'Archivo binario - sin diff de texto.',
			'cockpit.fileTreePanel.diffNoChanges' => 'Sin cambios.',
			'cockpit.fileViewer.cantOpen' => 'No se puede abrir este archivo.',
			'cockpit.fileViewer.couldNotLoadImage' => 'No se pudo cargar la imagen.',
			'cockpit.fileViewer.preview' => 'Vista previa',
			'cockpit.fileViewer.source' => 'Código fuente',
			'cockpit.workspaceSettingsDialog.choosePhotoTitle' => 'Elegir foto del workspace',
			'cockpit.workspaceSettingsDialog.title' => 'Configuración del workspace',
			'cockpit.workspaceSettingsDialog.namePlaceholder' => 'Nombre del workspace',
			'cockpit.workspaceSettingsDialog.addPhoto' => 'Añadir foto',
			'cockpit.workspaceSettingsDialog.changePhoto' => 'Cambiar foto',
			'cockpit.workspaceSettingsDialog.remove' => 'Quitar',
			'cockpit.workspaceSettingsDialog.color' => 'Color',
			'cockpit.workspaceSettingsDialog.host' => 'Host',
			'cockpit.workspaceSettingsDialog.folder' => 'Carpeta',
			'cockpit.realmDialogs.namePlaceholder' => 'Nombre del realm',
			'cockpit.realmDialogs.duplicateName' => 'Ya existe un realm con ese nombre.',
			'cockpit.realmDialogs.newRealmTitle' => 'Nuevo realm',
			'cockpit.realmDialogs.renameRealmTitle' => 'Renombrar realm',
			'cockpit.realmDialogs.rename' => 'Renombrar',
			'cockpit.realmDialogs.deleteRealmTitle' => 'Eliminar realm',
			'cockpit.realmDialogs.deleteMessage' => ({required Object name, required Object suffix}) => '¿Eliminar "${name}"? Ningún workspace se elimina — solo cambia la lista de carpetas.${suffix}',
			'cockpit.realmDialogs.deleteSuffixOne' => ' Su workspace se moverá a Predeterminado.',
			'cockpit.realmDialogs.deleteSuffixMany' => ({required Object count}) => ' Sus ${count} workspaces se moverán a Predeterminado.',
			'cockpit.realmDialogs.manageRealmsTitle' => 'Gestionar realms',
			'cockpit.realmDialogs.workspaceCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 workspace', other: '${n} workspaces', ), 
			'cockpit.dbRedisTable.deleteKeyTitle' => 'Eliminar clave',
			'cockpit.dbRedisTable.deleteKeyMessage' => ({required Object key}) => '¿Eliminar "${key}" de esta base de datos Redis?',
			'cockpit.dbRedisTable.refresh' => 'Actualizar',
			'cockpit.dbRedisTable.newKey' => 'Nueva clave',
			'cockpit.dbRedisTable.columnKey' => 'CLAVE',
			'cockpit.dbRedisTable.columnValue' => 'VALOR',
			'cockpit.dbRedisTable.columnType' => 'TIPO',
			'cockpit.dbRedisTable.columnTtl' => 'TTL',
			'cockpit.dbRedisTable.keyCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 clave', other: '${n} claves', ), 
			'cockpit.dbRedisTable.noKeys' => 'No hay claves en esta base de datos.',
			'cockpit.dbRedisTable.noKeysMatch' => ({required Object pattern}) => 'Ninguna clave coincide con "${pattern}".',
			'cockpit.dbRedisTable.loadMore' => 'Cargar más',
			'cockpit.dbRedisTable.loadingFullValue' => 'Cargando valor completo…',
			'cockpit.dbRedisTable.ttlMustBeNumber' => 'El TTL debe ser un número de segundos.',
			'cockpit.dbRedisTable.addKey' => 'Añadir clave',
			'cockpit.dbRedisTable.keyFieldHint' => 'clave',
			'cockpit.dbRedisTable.ttlFieldHint' => 'ttl (s, opcional)',
			'cockpit.dbRedisTable.valueFieldHint' => 'valor',
			'cockpit.dbRedisTable.searchHint' => 'Buscar — patrón, ej.: user:*',
			'cockpit.dbQueryView.saveQueryAs' => 'Guardar query como',
			'cockpit.dbQueryView.couldNotSave' => 'No se pudo guardar',
			'cockpit.dbQueryView.selectDatabase' => 'Seleccionar base de datos',
			'cockpit.dbQueryView.noSqlConnections' => 'Sin conexiones SQL — añade una en el panel Database',
			'cockpit.dbQueryView.running' => 'Ejecutando…',
			'cockpit.dbQueryView.runSelection' => 'Ejecutar selección',
			'cockpit.dbQueryView.run' => 'Ejecutar',
			'cockpit.dbQueryView.pickDatabaseHint' => 'Elige una base de datos arriba y luego Ejecutar (⌘↵).',
			'cockpit.dbQueryView.runQueryHint' => 'Ejecuta la query (⌘↵) para ver los resultados aquí.',
			'cockpit.dbQueryView.noRows' => 'Sin filas.',
			'cockpit.dbQueryView.rowsAffected' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 fila afectada', other: '${n} filas afectadas', ), 
			'cockpit.dbQueryView.rowsFooter' => ({required Object n}) => '${n} filas',
			'cockpit.dbQueryView.truncatedSuffix' => ' · truncado (aumenta -- limit)',
			'cockpit.dbQueryView.table' => 'Tabla',
			'cockpit.dbQueryView.json' => 'JSON',
			'cockpit.dbQueryView.unsaved' => 'sin guardar',
			'cockpit.dbQueryView.saved' => 'guardado',
			'cockpit.dbQueryView.copied' => 'Copiado',
			'cockpit.dbQueryView.copy' => 'Copiar',
			'cockpit.httpView.saveRequestAs' => 'Guardar request como',
			'cockpit.httpView.couldNotSave' => 'No se pudo guardar',
			'cockpit.httpView.run' => 'Ejecutar',
			'cockpit.httpView.running' => 'Ejecutando…',
			'cockpit.httpView.noRequests' => 'Ningún request en este archivo — escribe uno, p. ej.: GET https://example.com',
			'cockpit.httpView.selectRequest' => 'Seleccionar request',
			'cockpit.httpView.requestCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 request', other: '${n} requests', ), 
			'cockpit.httpView.runHint' => 'Ejecuta el request (⌘↵) para ver la respuesta aquí.',
			'cockpit.httpView.emptyBody' => 'Cuerpo de la respuesta vacío.',
			'cockpit.httpView.body' => 'JSON',
			'cockpit.httpView.headers' => 'Headers',
			'cockpit.httpView.raw' => 'Text',
			'cockpit.httpView.truncatedSuffix' => ' · truncado (respuesta demasiado grande)',
			'cockpit.httpView.error.title' => 'Falló el request',
			'cockpit.httpView.error.noRequest' => 'No se encontró ningún request en la posición del cursor.',
			'cockpit.httpView.error.invalidUrl' => ({required Object url}) => 'URL inválida: ${url}',
			'cockpit.httpView.error.unresolvedVariable' => ({required Object name}) => 'La variable {{${name}}} no tiene valor. Declárala con @${name} = … en este archivo.',
			'cockpit.httpView.error.bodyFileMissing' => ({required Object path}) => 'Archivo de cuerpo no encontrado: ${path}',
			'cockpit.httpView.error.bodyFileUnreadable' => ({required Object path, required Object detail}) => 'No se pudo leer el archivo de cuerpo ${path}: ${detail}',
			'cockpit.httpView.error.connectionFailed' => ({required Object detail}) => 'No se pudo alcanzar el servidor: ${detail}',
			'cockpit.httpView.error.connectionFailedNoDetail' => 'No se pudo alcanzar el servidor.',
			'cockpit.httpView.error.timeout' => ({required Object seconds}) => 'El request superó el tiempo límite de ${seconds}s.',
			'cockpit.httpView.error.responseTooLarge' => ({required Object bytes}) => 'La respuesta superó el límite de ${bytes} bytes.',
			'cockpit.dbPanel.sectionDatabase' => 'BASE DE DATOS',
			'cockpit.dbPanel.edit' => 'Editar…',
			'cockpit.dbPanel.copyName' => 'Copiar nombre',
			'cockpit.dbPanel.newQuery' => 'Nueva query',
			'cockpit.dbPanel.browseKeys' => 'Ver claves',
			'cockpit.dbPanel.deleteConnectionTitle' => 'Eliminar conexión',
			'cockpit.dbPanel.deleteConnectionMessage' => ({required Object name}) => '¿Quitar "${name}" de este workspace? Cualquier contraseña guardada se descartará. Los archivos .dbq que la referencian no se modifican.',
			'cockpit.dbPanel.footer' => ({required Object n}) => '.cockpit/databases.json · ${n} conexiones',
			'cockpit.dbPanel.footerOne' => '.cockpit/databases.json · 1 conexión',
			'cockpit.dbPanel.noConnections' => 'Aún no hay conexiones.',
			'cockpit.dbPanel.passwordRequired' => 'Contraseña no encontrada en el host. Abre esta conexión y vuelve a escribirla — se guarda en la máquina que ejecuta la base de datos, no en esta.',
			'cockpit.dbMongoView.deleteDocumentTitle' => 'Eliminar documento',
			'cockpit.dbMongoView.deleteDocumentMessage' => ({required Object id, required Object collection}) => '¿Eliminar el documento con _id ${id} de "${collection}"?',
			'cockpit.dbMongoView.filterHint' => 'Filtro — JSON, ej.: {"status": "active"}',
			'cockpit.dbMongoView.docCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 doc', other: '${n} docs', ), 
			'cockpit.dbMongoView.refresh' => 'Actualizar',
			'cockpit.dbMongoView.insertDocument' => 'Insertar documento',
			'cockpit.dbMongoView.noDocuments' => 'No hay documentos en esta colección.',
			'cockpit.dbMongoView.noDocumentsMatch' => 'Ningún documento coincide con este filtro.',
			'cockpit.dbMongoView.loadMore' => 'Cargar más',
			'cockpit.dbMongoView.edit' => 'Editar',
			'cockpit.dbMongoView.insert' => 'Insertar',
			'cockpit.dbConnectionDialog.chooseFileTitle' => 'Elegir base de datos SQLite',
			'cockpit.dbConnectionDialog.file' => 'Archivo',
			'cockpit.dbConnectionDialog.chooseFilePlaceholder' => 'Elige un archivo SQLite…',
			'cockpit.dbConnectionDialog.name' => 'Nombre',
			'cockpit.dbConnectionDialog.password' => 'Contraseña',
			'cockpit.dbConnectionDialog.savePassword' => 'Guardar contraseña',
			'cockpit.dbConnectionDialog.allowWrites' => 'Permitir escritura (agentes)',
			'cockpit.dbConnectionDialog.allowWritesHint' => 'desactivado = los agentes solo leen vía CLI',
			'cockpit.dbConnectionDialog.visibleToAgents' => 'Visible para agentes',
			'cockpit.dbConnectionDialog.visibleToAgentsHint' => 'desactivado = oculto en la CLI, solo en la GUI',
			'cockpit.dbConnectionDialog.testing' => 'Probando conexión…',
			'cockpit.dbConnectionDialog.connectionOk' => 'Conexión OK',
			'cockpit.dbConnectionDialog.connectionFailed' => 'Fallo en la conexión',
			'cockpit.dbConnectionDialog.editTitle' => 'Editar conexión',
			'cockpit.dbConnectionDialog.newTitle' => 'Nueva conexión',
			'cockpit.dbConnectionDialog.connectionString' => 'Connection string',
			'cockpit.dbConnectionDialog.invalidUrl' => 'URL de conexión no válida.',
			'cockpit.dbConnectionDialog.sshTunnel' => 'Túnel SSH',
			'cockpit.dbConnectionDialog.sshHost' => 'Host SSH',
			'cockpit.dbConnectionDialog.sshPort' => 'Puerto SSH',
			'cockpit.dbConnectionDialog.sshUser' => 'Usuario SSH',
			'cockpit.dbConnectionDialog.privateKey' => 'Clave privada',
			'cockpit.dbConnectionDialog.choosePrivateKeyPlaceholder' => 'Elige una clave privada…',
			'cockpit.dbConnectionDialog.choosePrivateKeyDialogTitle' => 'Elegir clave privada SSH',
			'cockpit.dbConnectionDialog.keyPassphrase' => 'Frase de contraseña de la clave',
			'cockpit.dbConnectionDialog.savePassphrase' => 'Guardar frase de contraseña',
			'cockpit.dbConnectionDialog.passwordOnHost' => 'La contraseña se guarda en el host, no en esta máquina.',
			'cockpit.sshPrompts.unknownSshHostTitle' => 'Host SSH desconocido',
			'cockpit.sshPrompts.neverConnected' => ({required Object endpoint}) => 'Cockpit nunca se ha conectado a ${endpoint} antes.',
			'cockpit.sshPrompts.trustHint' => 'Confía solo si esta fingerprint coincide con el servidor. Puedes verificarla en el servidor con:',
			'cockpit.sshPrompts.trust' => 'Confiar',
			'cockpit.sshPrompts.sshKeyPassphraseTitle' => 'Frase de contraseña de la clave SSH',
			'cockpit.sshPrompts.unlockMessage' => ({required Object keyPath, required Object connectionName}) => 'Desbloquea ${keyPath} para conectar "${connectionName}".',
			'cockpit.sshPrompts.keptInMemoryHint' => 'Se mantiene en memoria hasta que Cockpit se cierre. Para que los agentes usen esta conexión, activa "Guardar frase de contraseña" en la conexión.',
			'cockpit.sshPrompts.unlock' => 'Desbloquear',
			'cockpit.projectsRail.workspaces' => 'Workspaces',
			'cockpit.projectsRail.newWorkspace' => 'Nuevo workspace',
			'cockpit.projectsRail.settings' => 'Configuración',
			'cockpit.projectsRail.mergeToParent' => 'Fusionar en el padre',
			'cockpit.projectsRail.updateFromParent' => 'Actualizar desde el padre',
			'cockpit.projectsRail.forkWorktree' => 'Crear worktree derivada',
			'cockpit.projectsRail.copyBranch' => 'Copiar branch',
			'cockpit.projectsRail.remove' => 'Quitar',
			'cockpit.projectsRail.moveToRealm' => 'Mover a realm',
			'cockpit.projectsRail.copyWorkspaceId' => 'Copiar id del workspace',
			'cockpit.projectsRail.rename' => 'Renombrar',
			'cockpit.projectsRail.close' => 'Cerrar',
			'cockpit.projectsRail.newRealm' => 'Nuevo realm…',
			'cockpit.projectsRail.manageRealms' => 'Gestionar realms…',
			'cockpit.projectsRail.noWorkspaces' => 'Aún no hay workspaces.',
			'cockpit.projectsRail.sync' => 'Sincronizar',
			'cockpit.projectsRail.pull' => 'Pull',
			'cockpit.projectsRail.push' => 'Push',
			'cockpit.projectsRail.createWorktree' => 'Crear worktree',
			'cockpit.projectsRail.worktreeCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 worktree', other: '${n} worktrees', ), 
			'cockpit.projectsRail.expandWorktrees' => 'Expandir worktrees',
			'cockpit.projectsRail.collapseWorktrees' => 'Contraer worktrees',
			'cockpit.findBar.find' => 'Buscar',
			'cockpit.findBar.matchCase' => 'Coincidir mayúsculas',
			'cockpit.findBar.wholeWord' => 'Palabra completa',
			'cockpit.findBar.useRegex' => 'Usar expresión regular',
			'cockpit.findBar.previous' => 'Anterior (⇧⏎)',
			'cockpit.findBar.next' => 'Siguiente (⏎)',
			'cockpit.findBar.close' => 'Cerrar (Esc)',
			'cockpit.findBar.badPattern' => 'Patrón inválido',
			'cockpit.findBar.noResults' => 'Sin resultados',
			'cockpit.contentSearch.sectionSearch' => 'BÚSQUEDA',
			_ => null,
		} ?? switch (path) {
			'cockpit.contentSearch.searchInFiles' => 'Buscar en los archivos',
			'cockpit.contentSearch.matchCase' => 'Coincidir mayúsculas',
			'cockpit.contentSearch.wholeWord' => 'Palabra completa',
			'cockpit.contentSearch.useRegex' => 'Usar expresión regular',
			'cockpit.contentSearch.invalidRegex' => 'Expresión regular inválida.',
			'cockpit.contentSearch.typeToSearch' => 'Escribe para buscar en todos los archivos.',
			'cockpit.contentSearch.searching' => 'Buscando…',
			'cockpit.contentSearch.noResults' => 'Sin resultados.',
			'cockpit.emptyPane.newAgent' => 'Nuevo agente',
			'cockpit.emptyPane.newAgentDescription' => 'Ejecuta un pi en la carpeta que elijas',
			'cockpit.emptyPane.newTerminal' => 'Nueva terminal',
			'cockpit.emptyPane.newTerminalDescription' => 'Abre un shell en la carpeta que elijas',
			'cockpit.topbar.collapseSidebar' => 'Contraer barra lateral',
			'cockpit.topbar.toggleFiles' => 'Mostrar/ocultar archivos',
			'cockpit.topbar.filesUnavailable' => 'Archivos no disponibles en Cockpit',
			'cockpit.topbar.hideKeyboard' => 'Ocultar teclado',
			'cockpit.transcript.cancel' => 'Cancelar',
			'cockpit.transcript.send' => 'Enviar',
			'cockpit.transcript.typeYourAnswer' => 'Escribe tu respuesta',
			'cockpit.transcript.startHint' => 'Envía un prompt para que el agente empiece.',
			'cockpit.transcript.workedFor' => ({required Object duration}) => 'Trabajó ${duration}',
			'cockpit.tasks.hotReload' => 'Hot reload',
			'cockpit.tasks.hotRestart' => 'Hot restart',
			'cockpit.tasks.toggleDebugPaint' => 'Alternar debug paint',
			'cockpit.tasks.togglePlatform' => 'Alternar plataforma',
			'cockpit.tasks.quit' => 'Salir',
			'cockpit.notifications.agentFinished' => 'El agente terminó',
			'cockpit.notifications.open' => 'Abrir',
			'cockpit.notifications.agentNeedsAction' => 'El agente necesita tu acción',
			'cockpit.notifications.agentCrashed' => 'El agente se detuvo inesperadamente',
			'cockpit.terminal.cwdFallbackWarning' => ({required Object requested, required Object path}) => 'Aviso: la carpeta "${requested}" no existe. Esta terminal se abrió en "${path}".',
			'cockpit.remoteHost.addHost' => 'Añadir host remoto',
			'cockpit.remoteHost.hostName' => 'Nombre',
			'cockpit.remoteHost.sshTarget' => 'Destino SSH (usuario@host)',
			'cockpit.remoteHost.connecting' => ({required Object host}) => 'Conectando a ${host}…',
			'cockpit.remoteHost.openingTunnel' => 'Túnel SSH',
			'cockpit.remoteHost.installingServer' => 'Instalando servidor',
			'cockpit.remoteHost.handshake' => ({required Object version}) => 'Servidor ${version}',
			'cockpit.remoteHost.loadingWorkspace' => 'Cargando workspace…',
			'cockpit.remoteHost.reconnecting' => ({required Object host}) => 'Reconectando a ${host}…',
			'cockpit.remoteHost.offline' => ({required Object host}) => '${host} sin conexión',
			'cockpit.remoteHost.remove' => 'Quitar',
			'cockpit.remoteHost.reconnect' => 'Reconectar',
			'cockpit.remoteHost.installServer' => 'Instalar servidor',
			'cockpit.remoteHost.errSshUnreachable' => ({required Object host}) => 'No se puede llegar a ${host} por SSH. ¿Está encendido y con Inicio de sesión remoto activado?',
			'cockpit.remoteHost.errInstallFailed' => ({required Object host}) => 'No se pudo instalar el servidor en ${host}.',
			'cockpit.remoteHost.errVersionMismatch' => 'Versión del servidor incompatible; actualízalo.',
			'cockpit.remoteHost.errDetail' => ({required Object detail}) => 'Detalles: ${detail}',
			'cockpit.remoteHost.pickFolderTitle' => ({required Object host}) => 'Abrir carpeta en ${host}',
			'cockpit.remoteHost.openHere' => 'Abrir aquí',
			'cockpit.remoteHost.emptyFolder' => 'Sin subcarpetas',
			'cockpit.remoteHost.newLocal' => 'Local',
			'cockpit.remoteHost.newRemote' => 'Remoto',
			'cockpit.remoteHost.chooseHost' => 'Elegir un host',
			'cockpit.remoteHost.newHostEntry' => 'Nuevo host…',
			'cockpit.remoteHost.editHost' => 'Editar host',
			'cockpit.remoteHost.userLabel' => 'Usuario',
			'cockpit.remoteHost.hostLabel' => 'Host / IP',
			'cockpit.remoteHost.portLabel' => 'Puerto',
			'cockpit.remoteHost.authLabel' => 'Autenticación',
			'cockpit.remoteHost.authKey' => 'Clave SSH',
			'cockpit.remoteHost.authPassword' => 'Contraseña',
			'cockpit.remoteHost.passwordLabel' => 'Contraseña',
			'cockpit.remoteHost.passwordKeep' => 'Deja en blanco para mantener la actual',
			'cockpit.remoteHost.errUser' => 'Usuario obligatorio',
			'cockpit.remoteHost.errHost' => 'Host obligatorio',
			'cockpit.remoteHost.errPassword' => 'Contraseña obligatoria',
			'cockpit.remoteHost.identityChoose' => 'Elegir…',
			'cockpit.remoteHost.identityEmpty' => 'Ninguna clave seleccionada',
			'cockpit.remoteHost.identityDialogTitle' => 'Selecciona la clave privada SSH',
			'cockpit.remoteHost.errIdentity' => 'Elige la clave privada para autenticarte.',
			'cockpit.remoteHost.errHostKeyUnknown' => ({required Object host}) => 'Cockpit todavía no confía en ${host}. Conecta de nuevo y confirma la huella.',
			'cockpit.remoteHost.errHostKeyChanged' => ({required Object host}) => '${host} presenta una clave SSH distinta de la guardada. Si no reinstalaste esa máquina, detente y compruébalo; si la reinstalaste, elimina la entrada antigua de ~/.ssh/known_hosts.',
			'cockpit.remoteHost.errHostBundleMissing' => ({required Object host}) => '${host} es Windows pero no tiene Cockpit instalado. El servidor remoto se instala desde el bundle de Cockpit que ya está en esa máquina — instálalo allí e inténtalo de nuevo.',
			'cockpit.remoteHost.errHostUnknownOs' => ({required Object host}) => 'No se pudo identificar el sistema de ${host}. La cuenta puede tener un shell restringido, o ninguno.',
			'cockpit.remoteHost.errIdentityPublic' => 'Solo está la clave pública. Eso funciona solo si la privada está en tu agente SSH; si no, elige la privada (mismo nombre, sin .pub).',
			'cockpit.remoteHost.errIdentityNotKey' => 'Ese archivo no parece una clave privada.',
			'cockpit.remoteHost.errIdentityMissingFile' => 'Ese archivo ya no existe.',
			'cockpit.remoteHost.errIdentityUnreadable' => 'No se pudo leer ese archivo.',
			'cockpit.browserPane.back' => 'Atrás',
			'cockpit.browserPane.forward' => 'Adelante',
			'cockpit.browserPane.reload' => 'Recargar',
			'cockpit.browserPane.urlHint' => 'Escribe la URL o dirección',
			'cockpit.browserPane.go' => 'Ir',
			'settings.language.title' => 'Idioma',
			'settings.language.system' => 'Sistema',
			'settings.language.english' => 'Inglés',
			'settings.language.portugueseBr' => 'Portugués (BR)',
			'settings.language.spanish' => 'Español',
			'settings.revokeDialog.deviceRemoved' => 'Dispositivo eliminado.',
			'settings.revokeDialog.failedToRevoke' => 'No se pudo revocar el dispositivo.',
			'settings.revokeDialog.revoking' => 'Revocando…',
			'settings.revokeDialog.revokingDevice' => ({required Object name}) => 'Revocando ${name}…',
			'settings.revokeDialog.connectingMessage' => 'Conectando al relay y quitando el acceso.',
			'settings.revokeDialog.ok' => 'Ok',
			'settings.pairingDialog.title' => 'Vincular dispositivo',
			'settings.pairingDialog.connectingToRelay' => 'Conectando al relay…',
			'settings.pairingDialog.step1' => 'Abre la app Remote Pi en tu teléfono.',
			'settings.pairingDialog.step2' => 'Toca en añadir / vincular dispositivo.',
			'settings.pairingDialog.step3' => 'Apunta la cámara al QR de abajo.',
			'settings.pairingDialog.qrGenerationFailed' => 'No se pudo generar el QR.',
			'settings.pairingDialog.autoRefreshHint' => 'El código se actualiza automáticamente. Mantén esta ventana abierta.',
			'settings.pairingDialog.pairingFailed' => 'Fallo en la vinculación.',
			'settings.pairingDialog.tryAgain' => 'Intentar de nuevo',
			'settings.pairingDialog.copied' => '¡Copiado!',
			'settings.pairingDialog.copyData' => 'Copiar datos',
			'settings.page.header.back' => 'Atrás',
			'settings.page.header.title' => 'Configuración',
			'settings.page.nav.general' => 'General',
			'settings.page.nav.appearance' => 'Apariencia',
			'settings.page.nav.terminal' => 'Terminal',
			'settings.page.nav.language' => 'Lenguaje',
			'settings.page.nav.shortcuts' => 'Atajos',
			'settings.page.nav.notifications' => 'Notificaciones',
			'settings.page.nav.connectivity' => 'Conectividad',
			'settings.page.nav.daemonAgents' => 'Agentes Daemon',
			'settings.page.nav.schedules' => 'Programaciones',
			'settings.page.nav.automations' => 'Automatizaciones',
			'settings.page.nav.remoteHosts' => 'Hosts remotos',
			'settings.page.general.sectionAgent' => 'Agente',
			'settings.page.general.enableAgentsTitle' => 'Activar agentes',
			'settings.page.general.enableAgentsDesc' => 'Muestra la opción de abrir pestañas de agente (pi). Cuando está desactivado, Cockpit funciona solo como workspace de terminal.',
			'settings.page.general.showCockpitTitle' => 'Mostrar terminal de Cockpit',
			'settings.page.general.showCockpitDesc' => 'Mantiene un workspace sin carpeta, solo de terminal, fijado en la parte superior de la barra lateral. Desactivarlo cierra sus terminales.',
			'settings.page.general.launchAtStartupTitle' => 'Iniciar al arrancar',
			'settings.page.general.launchAtStartupDesc' => 'Inicia Cockpit automáticamente cuando inicias sesión en tu computadora.',
			'settings.page.general.sectionUpdates' => 'Actualizaciones',
			'settings.page.general.checkUpdatesTitle' => 'Buscar actualizaciones',
			'settings.page.general.checkUpdatesDesc' => 'Con qué frecuencia Cockpit debe buscar nuevas versiones.',
			'settings.page.general.agentsInUseError' => 'No se pueden desactivar los agentes mientras haya una pestaña de agente abierta. Cierra todas las pestañas de agente primero y luego desactívalo.',
			'settings.page.general.updateFrequency.daily' => 'Diariamente',
			'settings.page.general.updateFrequency.weekly' => 'Semanalmente',
			'settings.page.general.updateFrequency.monthly' => 'Mensualmente',
			'settings.page.general.updateFrequency.never' => 'Nunca',
			'settings.page.diagnostics.sectionTitle' => 'Diagnóstico',
			'settings.page.diagnostics.logFileTitle' => 'Archivo de registro',
			'settings.page.diagnostics.logFileDesc' => ({required Object days, required Object path}) => 'Los errores y eventos de inicio se registran aquí, y se conservan durante ${days} días.\n${path}',
			'settings.page.diagnostics.unavailable' => 'no disponible',
			'settings.page.diagnostics.reveal' => 'Mostrar',
			'settings.page.diagnostics.reportTitle' => 'Reportar un problema',
			'settings.page.diagnostics.reportDesc' => 'Abre un issue prellenado con tu versión, SO y registro reciente. Nada se envía automáticamente — lo revisas antes.',
			'settings.page.diagnostics.reportButton' => 'Reportar…',
			'settings.page.diagnostics.reportDialogTitle' => 'Informe de problema',
			'settings.page.diagnostics.reportDialogError' => 'Reportado manualmente desde Configuración.',
			'settings.page.diagnostics.reportDialogDescription' => 'Describe qué salió mal en el issue. El registro reciente está incluido abajo y en "Copiar detalles".',
			'settings.page.storage.sectionTitle' => 'Almacenamiento',
			'settings.page.storage.locationTitle' => 'Ubicación de almacenamiento',
			'settings.page.storage.locationDesc' => ({required Object root}) => 'Cockpit guarda aquí sus proyectos, diseños y configuración. Apúntalo a una carpeta sincronizada para respaldarlo.\n${root}',
			'settings.page.storage.useDefault' => 'Usar predeterminado',
			'settings.page.storage.working' => 'Procesando…',
			'settings.page.storage.change' => 'Cambiar…',
			'settings.page.storage.resetTitle' => 'Restablecer Cockpit',
			'settings.page.storage.resetDesc' => 'Elimina todos los datos locales — proyectos, diseños, configuración e historial de terminal — y vuelve a la ubicación predeterminada.',
			'settings.page.storage.resetButton' => 'Restablecer…',
			'settings.page.storage.resetConfirm' => 'Restablecer',
			'settings.page.storage.resetDialogTitle' => '¿Restablecer Cockpit?',
			'settings.page.storage.resetDialogContent' => 'Esto elimina permanentemente todos los datos locales de Cockpit — proyectos, diseños, configuración e historial de terminal. Esto no se puede deshacer. Cockpit se cerrará para que puedas empezar de nuevo.',
			'settings.page.storage.restartRequiredTitle' => 'Reinicio necesario',
			'settings.page.storage.restartChangeFolderMessage' => ({required Object path}) => 'Cockpit usará esta carpeta a partir del próximo inicio:\n${path}',
			'settings.page.storage.restartUseDefaultMessage' => 'Cockpit usará la ubicación predeterminada del sistema a partir del próximo inicio. Tus datos en la carpeta personalizada permanecen intactos.',
			'settings.page.storage.restartResetMessage' => 'Se borraron todos los datos de Cockpit. Reinicia para empezar de nuevo.',
			'settings.page.storage.later' => 'Más tarde',
			'settings.page.storage.quitCockpit' => 'Salir de Cockpit',
			'settings.page.storage.chooseFolderDialogTitle' => 'Elige una carpeta para los datos de Cockpit',
			'settings.page.terminal.sectionDefaultTerminal' => 'Terminal predeterminado',
			'settings.page.terminal.engineTitle' => 'Motor',
			'settings.page.terminal.engineDesc' => 'Usado por nuevas pestañas de terminal y buffers de salida de tasks. Las pestañas abiertas mantienen su motor actual.',
			'settings.page.terminal.shellTitle' => 'Shell',
			'settings.page.terminal.shellDesc' => 'Qué shell abren las nuevas pestañas de terminal. La flecha junto al + sigue abriendo cualquier otro, solo para esa pestaña.',
			'settings.page.terminal.noWslMessage' => 'No se encontraron distros de WSL. Instala una (wsl.exe --install) y reinicia Cockpit para verla listada aquí.',
			'settings.page.appearance.sectionTheme' => 'Tema',
			'settings.page.appearance.themeTitle' => 'Tema',
			'settings.page.appearance.themeDesc' => 'Colores de la app, resaltado de código y paleta del terminal.',
			'settings.page.appearance.modeTitle' => 'Modo',
			'settings.page.appearance.modeDesc' => 'Qué variante del tema usar.',
			'settings.page.appearance.modeOnlyDark' => ({required Object theme}) => '"${theme}" solo trae la variante oscura, así que esto no tiene efecto.',
			'settings.page.appearance.modeOnlyLight' => ({required Object theme}) => '"${theme}" solo trae la variante clara, así que esto no tiene efecto.',
			'settings.page.appearance.themeFileTitle' => 'Archivo de tema',
			'settings.page.appearance.themeFileDesc' => 'Importa un tema desde un archivo JSON, o exporta el activo.',
			'settings.page.appearance.previewCode' => 'Código',
			'settings.page.appearance.previewTerminal' => 'Terminal',
			'settings.page.appearance.themeSystem' => 'Sistema',
			'settings.page.appearance.themeLight' => 'Claro',
			'settings.page.appearance.themeDark' => 'Oscuro',
			'settings.page.appearance.sectionFonts' => 'Fuentes',
			'settings.page.appearance.interfaceFontTitle' => 'Fuente de la interfaz',
			'settings.page.appearance.interfaceFontDesc' => 'Se usa en toda la aplicación. Vacío = predeterminado del sistema.',
			'settings.page.appearance.interfaceSizeTitle' => 'Tamaño de la interfaz',
			'settings.page.appearance.codeFontTitle' => 'Fuente del código',
			'settings.page.appearance.codeFontDesc' => 'Código y diffs. Vacío = predeterminado del sistema.',
			'settings.page.appearance.codeSizeTitle' => 'Tamaño del código',
			'settings.page.appearance.terminalFontTitle' => 'Fuente del terminal',
			'settings.page.appearance.terminalFontDesc' => 'Solo la terminal. Vacío = predeterminado del sistema.',
			'settings.page.appearance.terminalSizeTitle' => 'Tamaño de la terminal',
			'settings.page.appearance.terminalSizeDesc' => 'Apagado = sigue el tamaño del código.',
			'settings.page.appearance.terminalSizeInherit' => 'Seguir el código',
			'settings.page.appearance.terminalWeightTitle' => 'Grosor de la terminal',
			'settings.page.appearance.terminalWeightDesc' => 'Las pantallas de baja densidad engrosan los trazos. El automático los afina solo ahí y no toca la Retina.',
			'settings.page.appearance.terminalWeightAuto' => 'Automático (según la pantalla)',
			'settings.page.appearance.terminalWeightLight' => 'Fino',
			'settings.page.appearance.terminalWeightNormal' => 'Normal',
			'settings.page.appearance.terminalWeightMedium' => 'Medio',
			'settings.page.appearance.terminalWeightSemiBold' => 'Seminegrita',
			'settings.page.appearance.sectionConversation' => 'Conversación',
			'settings.page.appearance.pinUserMessageTitle' => 'Fijar mensaje del usuario',
			'settings.page.appearance.pinUserMessageDesc' => 'La pregunta permanece fija arriba mientras la respuesta se desplaza.',
			'settings.page.appearance.importTheme' => 'Importar…',
			'settings.page.appearance.exportTheme' => 'Exportar…',
			'settings.page.appearance.deleteTheme' => 'Eliminar',
			'settings.page.appearance.importThemeDialog' => 'Elige un archivo de tema',
			'settings.page.appearance.exportThemeDialog' => 'Guardar tema como',
			'settings.page.appearance.themeImported' => ({required Object name}) => 'Tema "${name}" importado.',
			'settings.page.appearance.themeExported' => 'Tema guardado.',
			'settings.page.appearance.themeDeleted' => 'Tema eliminado.',
			'settings.page.appearance.fontPickerTitle' => 'Elegir una fuente',
			'settings.page.appearance.fontPickerSearch' => 'Buscar fuentes',
			'settings.page.appearance.fontPickerEmpty' => 'No hay ninguna fuente coincidente en esta máquina.',
			'settings.page.appearance.fontPickerBundled' => 'incluida',
			'settings.page.appearance.fontPickerCustom' => '¿No está en la lista? Escribe el nombre exacto de la familia.',
			'settings.page.appearance.fontPickerCustomHint' => 'Nombre de la familia',
			'settings.page.appearance.fontPickerUse' => 'Usar',
			'settings.page.appearance.fontPickerDefault' => 'Predeterminada',
			'settings.page.appearance.fontMissing' => 'No se encontró en esta máquina — usando el respaldo.',
			'settings.page.appearance.sectionLayout' => 'Diseño',
			'settings.page.appearance.swapPanelsTitle' => 'Invertir paneles',
			'settings.page.appearance.swapPanelsDesc' => 'Coloca los workspaces a la derecha y archivos, búsqueda, git y base de datos a la izquierda.',
			'settings.page.notifications.sectionTitle' => 'Notificaciones',
			'settings.page.notifications.enableTitle' => 'Activar notificaciones',
			'settings.page.notifications.enableDesc' => 'Avisarme cuando un agente termine un turno y la ventana no esté enfocada.',
			'settings.page.notifications.systemPermissionTitle' => 'Permiso del sistema',
			'settings.page.notifications.grantedDesc' => 'Cockpit tiene permiso para enviar notificaciones.',
			'settings.page.notifications.notGrantedDesc' => 'macOS aún no ha concedido acceso a las notificaciones.',
			'settings.page.notifications.granted' => 'Concedido',
			'settings.page.notifications.requestPermission' => 'Solicitar permiso',
			'settings.page.notifications.soundsTitle' => 'Sonidos',
			'settings.page.notifications.soundVolumeTitle' => 'Volumen',
			'settings.page.notifications.soundTurnDone' => 'Turno completado',
			'settings.page.notifications.soundTurnDoneDesc' => 'Un agente terminó su turno.',
			'settings.page.notifications.soundActionRequired' => 'Acción requerida',
			'settings.page.notifications.soundActionRequiredDesc' => 'Un agente está esperando tu aprobación o respuesta.',
			'settings.page.notifications.soundAgentError' => 'Error del agente',
			'settings.page.notifications.soundAgentErrorDesc' => 'El proceso de un agente se detuvo inesperadamente.',
			'settings.page.notifications.soundDefault' => 'Predeterminado',
			'settings.page.notifications.soundCustom' => ({required Object name}) => 'Personalizado: ${name}',
			'settings.page.notifications.soundChooseFile' => 'Elegir archivo',
			'settings.page.notifications.soundReset' => 'Volver al predeterminado',
			'settings.page.notifications.soundOnActiveTab' => 'Reproducir también con la pestaña activa',
			'settings.page.notifications.soundPreview' => 'Escuchar',
			'settings.page.shortcuts.notCustomizable' => 'Los atajos de teclado aún no se pueden personalizar.',
			'settings.page.languages.sectionFormatting' => 'FORMATO',
			'settings.page.languages.formatOnSaveTitle' => 'Formatear al guardar',
			'settings.page.languages.formatOnSaveDesc' => 'Formatea el archivo automáticamente al guardar (⌘S).',
			'settings.page.languages.sectionLanguageServers' => 'SERVIDORES DE LENGUAJE',
			'settings.page.languages.footerNote' => 'Los errores y el formato usan el language server de cada lenguaje. Cockpit no instala servidores — usa lo que ya está en tu máquina. ● responde · ○ no encontrado o comando inválido (instala el servidor o ajusta el comando).',
			'settings.page.languages.serverCommandLabel' => 'Comando del language server',
			'settings.page.languages.formatterCommandLabel' => 'Comando del formateador (opcional)',
			'settings.page.languages.formatterHint' => 'Formateador externo con el marcador %FILE%. Tiene prioridad sobre el formateador del LSP cuando está definido.',
			'settings.page.languages.resetToDefault' => 'Restablecer al predeterminado',
			'settings.page.languages.saveAndRestart' => 'Guardar y reiniciar',
			'settings.page.languages.statusResponds' => 'El servidor responde',
			'settings.page.languages.statusNotFound' => 'Servidor no encontrado o comando inválido',
			'settings.page.connectivity.sectionRelay' => 'Relay',
			'settings.page.connectivity.sectionPairedDevices' => 'Dispositivos vinculados',
			'settings.page.connectivity.reloadTooltip' => 'Recargar',
			'settings.page.connectivity.failedToListDevices' => 'No se pudieron listar los dispositivos.',
			'settings.page.connectivity.noPairedDevices' => 'No hay dispositivos vinculados.',
			'settings.page.connectivity.relayAddressTitle' => 'Dirección del relay',
			'settings.page.connectivity.relayAddressDesc' => 'Servidor que conecta tus agentes con el teléfono. Se aplica a todo agente con el relay activado.',
			'settings.page.connectivity.saving' => 'Guardando…',
			'settings.page.connectivity.check' => 'Comprobar',
			'settings.page.connectivity.healthOnline' => 'En línea',
			'settings.page.connectivity.healthNoResponse' => 'Sin respuesta',
			'settings.page.connectivity.healthNotChecked' => 'No comprobado',
			'settings.page.connectivity.deviceDefaultLabel' => 'Dispositivo',
			'settings.page.connectivity.revoke' => 'Revocar',
			'settings.page.connectivity.pairNewDevice' => 'Vincular nuevo dispositivo',
			'settings.page.connectivity.revokeDialogTitle' => '¿Revocar dispositivo?',
			'settings.page.connectivity.revokeDialogContent' => ({required Object name}) => '"${name}" perderá el acceso a tus agentes y deberá vincularse de nuevo.\n\nDebes estar conectado al relay — la app se conectará automáticamente para revocar.',
			'settings.page.schedules.sectionScheduledPrompts' => 'Prompts programados',
			'settings.page.schedules.createSchedule' => 'Crear programación',
			'settings.page.schedules.createDaemonFirst' => 'Crea primero un Agente Daemon.',
			'settings.page.schedules.supervisorOffline' => 'Supervisor sin conexión. Las programaciones necesitan que pi-supervisord esté en ejecución (`remote-pi install`).',
			'settings.page.schedules.failedToListSchedules' => 'No se pudieron listar las programaciones.',
			'settings.page.schedules.noSchedules' => 'Sin programaciones. Crea un prompt recurrente para un daemon.',
			'settings.page.schedules.runNow' => 'Ejecutar ahora',
			'settings.page.schedules.viewLog' => 'Ver registro',
			'settings.page.schedules.disabled' => 'desactivado',
			'settings.page.schedules.nextRun' => ({required Object when}) => 'próximo ${when}',
			'settings.page.schedules.lastRun' => ({required Object label}) => 'último: ${label}',
			'settings.page.schedules.removeScheduleDialogTitle' => '¿Quitar programación?',
			'settings.page.schedules.removeScheduleDialogContent' => ({required Object schedule, required Object daemon}) => 'El job "${schedule}" de ${daemon} se elimina. Sus ejecuciones se detienen.',
			'settings.page.schedules.newScheduleTitle' => 'Nueva programación',
			'settings.page.schedules.daemonLabel' => 'Daemon',
			'settings.page.schedules.whenLabel' => 'Cuándo (expresión cron)',
			'settings.page.schedules.previewPlaceholder' => 'La próxima ejecución aparece aquí',
			'settings.page.schedules.previewComputed' => 'Próximo: calculado al guardar',
			'settings.page.schedules.previewNext' => ({required Object when}) => 'Próximo: ${when}',
			'settings.page.schedules.exampleEveryDay9am' => 'todos los días a las 9h',
			'settings.page.schedules.exampleHourly' => 'cada hora',
			'settings.page.schedules.exampleEvery15Min' => 'cada 15 min',
			'settings.page.schedules.exampleWeekdays6pm' => 'días laborables a las 18h',
			'settings.page.schedules.promptLabel' => 'Prompt',
			'settings.page.schedules.timezoneLabel' => 'Zona horaria (opcional)',
			'settings.page.schedules.skipIfBusy' => 'Omitir si el agente está ocupado',
			'settings.page.schedules.wakeIfStopped' => 'Despertar el daemon si está detenido',
			'settings.page.schedules.catchup' => 'Recuperar 1 ejecución perdida (catchup)',
			'settings.page.schedules.fillRequiredError' => 'Completa la expresión y el prompt.',
			'settings.page.schedules.creating' => 'Creando…',
			'settings.page.schedules.failedToCreateSchedule' => 'No se pudo crear la programación.',
			'settings.page.schedules.historyTitle' => ({required Object schedule}) => 'Historial — ${schedule}',
			'settings.page.schedules.failedToReadLog' => 'No se pudo leer el registro.',
			'settings.page.schedules.noRecordsYet' => 'Aún no hay registros.',
			'settings.page.schedules.cronDelivered' => 'entregado',
			'settings.page.schedules.cronWokeDelivered' => 'despertó + entregado',
			'settings.page.schedules.cronFailed' => 'falló',
			'settings.page.schedules.cronSkippedBusy' => 'omitido (ocupado)',
			'settings.page.schedules.cronSkippedStopped' => 'omitido (detenido)',
			'settings.page.schedules.cronSkippedDisabled' => 'omitido (desactivado)',
			'settings.page.daemons.sectionAlwaysOnAgents' => 'Agentes siempre activos',
			'settings.page.daemons.createDaemon' => 'Crear daemon',
			'settings.page.daemons.startAll' => 'Iniciar todos',
			'settings.page.daemons.stopAll' => 'Detener todos',
			'settings.page.daemons.restartAll' => 'Reiniciar todos',
			'settings.page.daemons.restartSupervisor' => 'Reiniciar supervisor',
			'settings.page.daemons.restartSupervisorDialogTitle' => '¿Reiniciar el supervisor?',
			'settings.page.daemons.restartSupervisorDialogContent' => 'Reinicia el proceso del supervisor (recarga el código). Todos los daemons se reinician con él y quedan sin conexión unos segundos.',
			'settings.page.daemons.removeDaemonDialogTitle' => '¿Quitar daemon?',
			'settings.page.daemons.removeDaemonDialogContent' => ({required Object name}) => '"${name}" deja de ejecutarse y sale del registro. La carpeta y su configuración local se conservan — puedes recrearlo después.',
			'settings.page.daemons.supervisorOfflineTitle' => 'Supervisor sin conexión',
			'settings.page.daemons.supervisorOfflineDesc' => 'pi-supervisord no se está ejecutando. Instálalo con `remote-pi install` para gestionar agentes 24/7.',
			'settings.page.daemons.failedToListDaemons' => 'No se pudieron listar los daemons.',
			'settings.page.daemons.noRegisteredAgents' => 'Sin agentes registrados. Crea uno a partir de una carpeta.',
			'settings.page.daemons.start' => 'Iniciar',
			'settings.page.daemons.stop' => 'Detener',
			'settings.page.daemons.edit' => 'Editar',
			'settings.page.daemons.stateRunning' => 'en ejecución',
			'settings.page.daemons.stateStarting' => 'iniciando',
			'settings.page.daemons.stateStopped' => 'detenido',
			'settings.page.daemons.stateFailed' => 'falló',
			'settings.page.daemons.newDaemonTitle' => 'Nuevo daemon',
			'settings.page.daemons.editDaemonTitle' => 'Editar daemon',
			'settings.page.daemons.nameLabel' => 'Nombre',
			'settings.page.daemons.namePlaceholder' => 'ej.: PC, Servidor, Casa',
			'settings.page.daemons.nameRequiredError' => 'Escribe un nombre.',
			'settings.page.daemons.nameDuplicateError' => 'Ya existe un agente con ese nombre.',
			'settings.page.daemons.folderLabel' => 'Carpeta',
			'settings.page.daemons.noFolderChosen' => 'Ninguna carpeta elegida',
			'settings.page.daemons.choose' => 'Elegir',
			'settings.page.daemons.changeFolder' => 'Cambiar',
			'settings.page.daemons.folderCannotBeChanged' => 'La carpeta no se puede cambiar.',
			'settings.page.daemons.folderRequiredError' => 'Elige una carpeta.',
			'settings.page.daemons.folderDuplicateError' => 'Ya existe un agente en esta carpeta.',
			'settings.page.daemons.pickFolderDialogTitle' => 'Elige la carpeta del Agente Daemon',
			'settings.page.automations.sectionCommitMessages' => 'Mensajes de commit',
			'settings.page.automations.harness' => 'Harness',
			'settings.page.automations.harnessDiscovering' => 'Buscando harnesses de línea de comandos instalados…',
			'settings.page.automations.harnessNoneFound' => 'No se encontró ningún harness compatible en el PATH.',
			'settings.page.automations.harnessConfiguredUnavailable' => ({required Object harness}) => '${harness} está configurado, pero no disponible.',
			'settings.page.automations.harnessChoose' => 'Elige la CLI usada para generar mensajes de commit.',
			'settings.page.automations.harnessRefresh' => 'Actualizar harnesses instalados',
			'settings.page.automations.notConfigured' => 'Sin configurar',
			'settings.page.automations.model' => 'Modelo',
			'settings.page.automations.modelUnavailable' => 'La lista de modelos no está disponible hasta encontrar el harness.',
			'settings.page.automations.modelCliOnly' => 'Este harness usa el modelo predeterminado de su CLI.',
			'settings.page.automations.modelCliDefault' => 'Predeterminado de la CLI',
			'settings.page.automations.modelAuto' => 'Auto',
			'settings.page.automations.modelSearch' => ({required Object count}) => 'Buscar entre ${count} modelos…',
			'settings.page.automations.modelAutoRouted' => 'Este harness elige el modelo automáticamente.',
			'settings.page.automations.modelAccountOnly' => 'Solo se muestran los modelos disponibles en tu cuenta.',
			'settings.page.automations.generateFromSourceControl' => 'Generar desde Control de versiones',
			'settings.page.automations.generateFromSourceControlDescription' => 'Cockpit envía solo el diff seleccionado y los asuntos de los commits recientes. Los patrones habituales de credenciales y los archivos sensibles se redactan antes de ejecutar el harness.',
			'settings.page.automations.discoveryFailed' => 'No se pudieron descubrir los harnesses de automatización instalados.',
			'settings.page.automations.staleModel' => ({required Object model, required Object harness}) => 'El modelo "${model}" ya no está disponible para ${harness}. Se usará el predeterminado de la CLI; elige otro modelo en Configuración si lo necesitas.',
			'settings.page.automations.recommendedSuffix' => 'Recomendado',
			'settings.remoteHosts.title' => 'Hosts remotos',
			'settings.remoteHosts.description' => 'Máquinas a las que accedes por SSH. Añadir un host aquí es lo mismo que hacerlo desde el menú "+" del workspace.',
			'settings.remoteHosts.empty' => 'Aún no hay hosts remotos.',
			'settings.remoteHosts.add' => 'Añadir host',
			'settings.remoteHosts.edit' => 'Editar',
			'settings.remoteHosts.reconnect' => 'Reconectar',
			'settings.remoteHosts.remove' => 'Eliminar',
			'settings.remoteHosts.removeTitle' => 'Eliminar host',
			'settings.remoteHosts.removeMessage' => ({required Object name}) => '¿Eliminar "${name}" y todos sus workspaces? No se borra nada en el host.',
			'settings.remoteHosts.workspacesCount' => ({required Object count}) => '${count} workspace(s)',
			'settings.remoteHosts.deviceKeyTitle' => 'Clave de este dispositivo',
			'settings.remoteHosts.deviceKeyDesc' => 'Añade esta clave pública a ~/.ssh/authorized_keys del host para que este dispositivo pueda conectarse.',
			'settings.remoteHosts.deviceKeyCopy' => 'Copiar clave pública',
			'settings.remoteHosts.deviceKeyCopied' => 'Clave pública copiada',
			'settings.remoteHosts.statusConnected' => 'Conectado',
			'settings.remoteHosts.statusConnecting' => 'Conectando…',
			'settings.remoteHosts.statusReconnecting' => 'Reconectando…',
			'settings.remoteHosts.statusOffline' => 'Sin conexión',
			'settings.remoteHosts.statusIdle' => 'No conectado',
			'settings.remoteHosts.helpTitle' => 'Cómo funciona',
			'settings.remoteHosts.helpBody' => 'Cockpit se conecta a tu máquina por SSH y habla con un pequeño servidor que ejecuta las terminales, archivos y git allí. El host debe tener Cockpit (escritorio) o el cockpit-server instalado y en ejecución, y la clave pública de este dispositivo añadida en su ~/.ssh/authorized_keys.',
			'automation.error.unavailable' => ({required Object harness}) => '${harness} no está instalado o no está en el PATH.',
			'automation.error.modelUnavailable' => ({required Object model, required Object harness}) => 'El modelo "${model}" no está disponible para ${harness}. Elige otro modelo en Configuración.',
			'automation.error.authentication' => ({required Object harness, required Object detail}) => '${harness}: ${detail}',
			'automation.error.timeout' => ({required Object harness, required Object seconds}) => '${harness} no respondió en ${seconds} segundos.',
			'automation.error.cancelled' => 'Se canceló la generación del mensaje de commit.',
			'automation.error.process' => ({required Object harness, required Object detail}) => '${harness}: ${detail}',
			'automation.error.processNoDetail' => ({required Object harness}) => '${harness} no pudo generar un mensaje de commit.',
			'automation.error.invalidResponse' => 'La automatización devolvió un mensaje de commit vacío.',
			'automation.error.busy' => 'Ya se está generando otro mensaje de commit.',
			'automation.error.unknown' => 'La automatización no pudo generar un mensaje de commit.',
			'automation.error.noWorkspace' => 'Ningún workspace seleccionado.',
			'automation.error.fileOutsideWorkspace' => 'El archivo está fuera de las raíces del workspace.',
			'automation.error.fileUnreadable' => ({required Object detail}) => 'No se pudo leer el archivo: ${detail}',
			'automation.error.binaryFile' => 'No se puede generar un mensaje de commit para un archivo binario.',
			'automation.error.noFileChanges' => 'No hay cambios que describir en este archivo.',
			'automation.error.noStagedChanges' => 'No hay cambios en stage que describir.',
			'automation.error.multipleRepositories' => 'Los cambios en stage pertenecen a varios repositorios. Genéralos por separado.',
			'automation.error.diffUnavailable' => 'No se pudo leer el diff.',
			'automation.error.notConfigured' => 'Configura un harness de mensajes de commit en Configuración.',
			'fileOperation.error.alreadyExists' => ({required Object name}) => 'Ya existe: “${name}”.',
			'fileOperation.error.notFound' => ({required Object name}) => 'No se encontró: “${name}”.',
			'fileOperation.error.invalidPath' => 'Ruta inválida.',
			'fileOperation.error.emptyName' => 'El nombre no puede estar vacío.',
			'fileOperation.error.noWorkspace' => 'Ningún workspace seleccionado.',
			'fileOperation.error.cannotMoveIntoItself' => 'No se puede mover una carpeta dentro de sí misma.',
			'fileOperation.error.clipboardEmpty' => 'El portapapeles está vacío.',
			'fileOperation.error.notScratchTab' => 'Esta pestaña no es un archivo temporal.',
			'fileOperation.error.writeFailed' => 'No se pudo escribir el archivo.',
			'fileOperation.error.formatterEmptyCommand' => 'Comando de formato vacío.',
			'fileOperation.error.formatterMissingPlaceholder' => 'El comando de formato debe incluir el marcador %FILE%.',
			'fileOperation.error.formatterTimeout' => 'El formateador agotó el tiempo de espera.',
			'fileOperation.error.formatterExitCode' => ({required Object code}) => 'El formateador terminó con el código ${code}.',
			'fileOperation.error.formatterFailed' => 'No se pudo ejecutar el formateador.',
			'fileOperation.error.osFailure' => ({required Object detail}) => '${detail}',
			'fileOperation.error.nameHasSlash' => 'El nombre no puede contener “/”.',
			'fileOperation.error.invalidName' => 'Nombre inválido.',
			'theme.error.io' => 'No se pudo leer o escribir el archivo del tema.',
			'theme.error.ioDetail' => ({required Object detail}) => 'No se pudo leer o escribir el archivo del tema: ${detail}',
			'theme.error.malformedJson' => ({required Object detail}) => 'Este archivo no es JSON válido: ${detail}',
			'theme.error.invalidTheme' => 'Este archivo no es un tema válido.',
			'theme.error.reservedId' => 'Este tema usa el id de un tema nativo. Cambia el "id" en el archivo e impórtalo de nuevo.',
			'theme.error.notAnObject' => ({required Object field}) => 'Se esperaba un objeto en "${field}".',
			'theme.error.missingField' => ({required Object field}) => 'Falta el campo obligatorio "${field}".',
			'theme.error.badColor' => ({required Object value, required Object field}) => '"${value}" en "${field}" no es un color. Usa #RGB, #RRGGBB o #RRGGBBAA.',
			'theme.error.unknownBase' => ({required Object value}) => 'Tema base "${value}" desconocido en "extends".',
			'theme.error.noVariants' => 'El tema no declara ningún variant. Añade "dark", "light" o ambos en "variants".',
			_ => null,
		};
	}
}
