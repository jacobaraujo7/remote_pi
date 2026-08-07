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
class TranslationsEs with BaseTranslations<AppLocale, Translations> implements Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.es,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <es>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key);

	late final TranslationsEs _root = this; // ignore: unused_field

	@override 
	TranslationsEs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEs(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$notifications$es notifications = _Translations$notifications$es._(_root);
	@override late final _Translations$common$es common = _Translations$common$es._(_root);
	@override late final _Translations$home$es home = _Translations$home$es._(_root);
	@override late final _Translations$chat$es chat = _Translations$chat$es._(_root);
	@override late final _Translations$pairing$es pairing = _Translations$pairing$es._(_root);
	@override late final _Translations$settings$es settings = _Translations$settings$es._(_root);
}

// Path: notifications
class _Translations$notifications$es implements Translations$notifications$en {
	_Translations$notifications$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get agentFinished => 'Agente terminó';
}

// Path: common
class _Translations$common$es implements Translations$common$en {
	_Translations$common$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get confirm => 'Confirmar';
	@override String get save => 'Guardar';
	@override String get close => 'Cerrar';
	@override String get delete => 'Eliminar';
	@override String get done => 'Hecho';
	@override String get ok => 'OK';
	@override String get loading => 'Cargando…';
	@override String get send => 'Enviar';
	@override String get submit => 'Enviar';
	@override String get open => 'Abrir';
	@override String get dismiss => 'Descartar';
	@override String get settings => 'Configuración';
}

// Path: home
class _Translations$home$es implements Translations$home$en {
	_Translations$home$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Remote Pi';
	@override String get relay => 'Relay';
	@override String get connected => 'Conectado';
	@override String get offline => 'Sin conexión';
	@override String get awaitingPairing => 'Esperando emparejamiento';
	@override String get noPairings => 'Sin emparejamientos';
	@override String get scanQrToStart => 'Escanea un QR de tu Mac para empezar.';
	@override String get scanQr => 'Escanear QR';
	@override String get nothingHere => 'Nada aquí…';
	@override String get sessionAppearsHere => 'Cuando un Pi emparejado abre una sesión, aparece aquí.';
	@override String get renameSession => 'Renombrar sesión';
	@override String get deleteSession => 'Eliminar sesión (solo local)';
	@override String get deleteOnlyOffline => 'Solo disponible sin conexión';
	@override String get deleteConfirmTitle => '¿Eliminar sesión?';
	@override String get deleteConfirmMessage => 'Solo se elimina localmente. Si la sesión vuelve a estar en línea en el Pi, reaparece en la lista.';
	@override String get renameDialogTitle => 'Renombrar sesión';
	@override String get lastPaired => 'Emparejado';
	@override String get all => 'Todos';
	@override String get online => 'En línea';
}

// Path: chat
class _Translations$chat$es implements Translations$chat$en {
	_Translations$chat$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get placeholder => 'Mensaje…';
	@override String get thinking => 'Pensando…';
	@override String get working => 'trabajando…';
	@override String get stop => 'Detener';
	@override String get sessionEnded => 'Sesión terminada';
	@override String get reconnecting => 'Reconectando…';
	@override String get back => 'Volver';
	@override String get sessionInfo => 'Info de sesión';
	@override String get name => 'Nombre';
	@override String get path => 'Ruta';
	@override String get owner => 'Propietario';
	@override String get model => 'Modelo';
	@override String get room => 'Sala';
	@override String get paired => 'Emparejado';
	@override String get close => 'Cerrar';
	@override String get nickname => 'Apodo';
	@override String get nicknameLocalOnly => 'Solo local — el Mac no recibe notificación.';
	@override String get removeNickname => 'Quitar apodo';
	@override String get default_ => 'Predeterminado';
	@override String get noActiveDevice => 'Sin dispositivo activo';
	@override String get connecting => 'Conectando…';
	@override String get rePair => 'Re-emparejar';
	@override String get nothingHere => 'Nada aquí';
	@override String get cameraOff => 'Acceso a la cámara desactivado — actívalo en Configuración para adjuntar una foto.';
	@override String get micOff => 'Acceso al micrófono desactivado — actívalo en Configuración para dictar.';
	@override String get holdMic => 'Mantén el micrófono para hablar';
	@override String get pairingRevoked => 'Emparejamiento revocado por el Mac — re-empareja para continuar';
	@override String get quickActions => 'Acciones rápidas';
	@override String get compactContext => 'Compactar contexto';
	@override String get compactContextDesc => 'Resumir turnos antiguos para liberar espacio.';
	@override String get contextCompacted => 'Contexto compactado';
	@override String get running => 'EJECUTANDO';
	@override String get done => 'HECHO';
	@override String get failed => 'FALLÓ';
	@override String get denied => 'DENEGADO';
	@override String get expired => 'EXPIRADO';
	@override String get doneOutcome => '✓ Hecho';
	@override String get runningOutcome => '⏳ Ejecutando…';
	@override String get failedOutcome => 'Falló';
	@override String get deniedOutcome => 'Denegado';
	@override String get expiredOutcome => 'Expirado';
	@override String get newSession => 'Nueva sesión';
	@override String get newSessionDesc => 'Limpia la conversación en el Pi.';
	@override String get newSessionConfirm => '¿Iniciar una nueva sesión?';
	@override String get newSessionConfirmDesc => 'Esto limpia el historial de conversación en el Pi.';
	@override String get startNew => 'Iniciar nueva';
	@override String get chooseModel => 'Elegir modelo';
	@override String get switching => 'Cambiando…';
	@override String get noModels => 'Sin modelos disponibles';
	@override String get failedToLoad => 'Error al cargar modelos';
	@override String get retry => 'Reintentar';
	@override String get selectSession => 'Selecciona una sesión';
	@override String get selectSessionDesc => 'Elige una sesión a la izquierda para abrir el chat.';
	@override String get copyCode => 'Copiar código';
	@override String get clarificationNeeded => 'Aclaración necesaria';
	@override String get refresh => 'Actualizar';
	@override String get camera => 'Cámara';
	@override String get photoLibrary => 'Galería de fotos';
	@override String get offline => 'Desconectado…';
	@override String get steerResponse => 'Dirigir respuesta…';
	@override String get addCaption => 'Añadir descripción…';
	@override String get sendMessage => 'Enviar mensaje…';
	@override String get queuedTapToEdit => 'En cola. Toca para editar.';
	@override String get queuedFollowUp => 'Mensaje en cola.';
	@override String get clearQueued => 'Limpiar mensaje en cola';
	@override String get attachImage => 'Adjuntar imagen';
	@override String get quickActionsTooltip => 'Acciones rápidas';
	@override String get slideToCancel => 'desliza para cancelar';
	@override String get releaseToCancel => 'suelta para cancelar';
}

// Path: pairing
class _Translations$pairing$es implements Translations$pairing$en {
	_Translations$pairing$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get scanQrTitle => 'Escanear código QR';
	@override String get scanQrSubtitle => 'Apunta la cámara al QR mostrado en tu Mac';
	@override String get pasteQr => 'Pegar QR';
	@override String get pasteQrHint => 'Pega el contenido del código QR';
	@override String get pairing => 'Emparejando…';
	@override String get paired => '¡Emparejado!';
	@override String get pairDevice => 'Emparejar dispositivo';
	@override String get connectingTo => 'Conectando a';
	@override String get pointCamera => 'Apunta la cámara al QR mostrado en la terminal de tu Mac';
	@override String get tryAgain => 'Intentar de nuevo';
	@override String get timedOut => 'Tiempo agotado — asegúrate de que /remote-pi está corriendo en tu Mac';
	@override String get cantScan => '¿No puedes escanear? Pega el código';
	@override String get nameThisPC => 'Nombrar este PC';
	@override String get nameThisPCDesc => 'Elige un nombre para identificar este Mac en tu lista. Puedes cambiarlo después desde la pantalla de inicio.';
	@override String get skip => 'Saltar';
	@override String get pastePairingCode => 'Pegar código de emparejamiento';
	@override String get pasteFromClipboard => 'Pegar del portapapeles';
	@override String get pair => 'Emparejar';
}

// Path: settings
class _Translations$settings$es implements Translations$settings$en {
	_Translations$settings$es._(this._root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Configuración';
	@override String get display => 'Pantalla';
	@override String get theme => 'Tema';
	@override String get system => 'Sistema';
	@override String get light => 'Claro';
	@override String get dark => 'Oscuro';
	@override String get language => 'Idioma';
	@override String get hideToolCalls => 'Ocultar llamadas de herramientas';
	@override String get hideToolCallsDesc => 'Mostrar solo tus mensajes y las respuestas del asistente.';
	@override String get pairings => 'Emparejamientos';
	@override String get addNewPairing => 'Añadir nuevo emparejamiento';
	@override String get tapToPair => 'Toca + para emparejar un nuevo Mac.';
	@override String get relay => 'Relay';
	@override String get relayUpdated => 'Relay actualizado';
	@override String get current => 'Actual';
	@override String get save => 'Guardar';
	@override String get useDefaultRelay => 'Usar Relay predeterminado';
	@override String get close => 'Cerrar';
	@override String get back => 'Volver';
}

/// The flat map containing all translations for locale <es>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notifications.agentFinished' => 'Agente terminó',
			'common.cancel' => 'Cancelar',
			'common.confirm' => 'Confirmar',
			'common.save' => 'Guardar',
			'common.close' => 'Cerrar',
			'common.delete' => 'Eliminar',
			'common.done' => 'Hecho',
			'common.ok' => 'OK',
			'common.loading' => 'Cargando…',
			'common.send' => 'Enviar',
			'common.submit' => 'Enviar',
			'common.open' => 'Abrir',
			'common.dismiss' => 'Descartar',
			'common.settings' => 'Configuración',
			'home.title' => 'Remote Pi',
			'home.relay' => 'Relay',
			'home.connected' => 'Conectado',
			'home.offline' => 'Sin conexión',
			'home.awaitingPairing' => 'Esperando emparejamiento',
			'home.noPairings' => 'Sin emparejamientos',
			'home.scanQrToStart' => 'Escanea un QR de tu Mac para empezar.',
			'home.scanQr' => 'Escanear QR',
			'home.nothingHere' => 'Nada aquí…',
			'home.sessionAppearsHere' => 'Cuando un Pi emparejado abre una sesión, aparece aquí.',
			'home.renameSession' => 'Renombrar sesión',
			'home.deleteSession' => 'Eliminar sesión (solo local)',
			'home.deleteOnlyOffline' => 'Solo disponible sin conexión',
			'home.deleteConfirmTitle' => '¿Eliminar sesión?',
			'home.deleteConfirmMessage' => 'Solo se elimina localmente. Si la sesión vuelve a estar en línea en el Pi, reaparece en la lista.',
			'home.renameDialogTitle' => 'Renombrar sesión',
			'home.lastPaired' => 'Emparejado',
			'home.all' => 'Todos',
			'home.online' => 'En línea',
			'chat.placeholder' => 'Mensaje…',
			'chat.thinking' => 'Pensando…',
			'chat.working' => 'trabajando…',
			'chat.stop' => 'Detener',
			'chat.sessionEnded' => 'Sesión terminada',
			'chat.reconnecting' => 'Reconectando…',
			'chat.back' => 'Volver',
			'chat.sessionInfo' => 'Info de sesión',
			'chat.name' => 'Nombre',
			'chat.path' => 'Ruta',
			'chat.owner' => 'Propietario',
			'chat.model' => 'Modelo',
			'chat.room' => 'Sala',
			'chat.paired' => 'Emparejado',
			'chat.close' => 'Cerrar',
			'chat.nickname' => 'Apodo',
			'chat.nicknameLocalOnly' => 'Solo local — el Mac no recibe notificación.',
			'chat.removeNickname' => 'Quitar apodo',
			'chat.default_' => 'Predeterminado',
			'chat.noActiveDevice' => 'Sin dispositivo activo',
			'chat.connecting' => 'Conectando…',
			'chat.rePair' => 'Re-emparejar',
			'chat.nothingHere' => 'Nada aquí',
			'chat.cameraOff' => 'Acceso a la cámara desactivado — actívalo en Configuración para adjuntar una foto.',
			'chat.micOff' => 'Acceso al micrófono desactivado — actívalo en Configuración para dictar.',
			'chat.holdMic' => 'Mantén el micrófono para hablar',
			'chat.pairingRevoked' => 'Emparejamiento revocado por el Mac — re-empareja para continuar',
			'chat.quickActions' => 'Acciones rápidas',
			'chat.compactContext' => 'Compactar contexto',
			'chat.compactContextDesc' => 'Resumir turnos antiguos para liberar espacio.',
			'chat.contextCompacted' => 'Contexto compactado',
			'chat.running' => 'EJECUTANDO',
			'chat.done' => 'HECHO',
			'chat.failed' => 'FALLÓ',
			'chat.denied' => 'DENEGADO',
			'chat.expired' => 'EXPIRADO',
			'chat.doneOutcome' => '✓ Hecho',
			'chat.runningOutcome' => '⏳ Ejecutando…',
			'chat.failedOutcome' => 'Falló',
			'chat.deniedOutcome' => 'Denegado',
			'chat.expiredOutcome' => 'Expirado',
			'chat.newSession' => 'Nueva sesión',
			'chat.newSessionDesc' => 'Limpia la conversación en el Pi.',
			'chat.newSessionConfirm' => '¿Iniciar una nueva sesión?',
			'chat.newSessionConfirmDesc' => 'Esto limpia el historial de conversación en el Pi.',
			'chat.startNew' => 'Iniciar nueva',
			'chat.chooseModel' => 'Elegir modelo',
			'chat.switching' => 'Cambiando…',
			'chat.noModels' => 'Sin modelos disponibles',
			'chat.failedToLoad' => 'Error al cargar modelos',
			'chat.retry' => 'Reintentar',
			'chat.selectSession' => 'Selecciona una sesión',
			'chat.selectSessionDesc' => 'Elige una sesión a la izquierda para abrir el chat.',
			'chat.copyCode' => 'Copiar código',
			'chat.clarificationNeeded' => 'Aclaración necesaria',
			'chat.refresh' => 'Actualizar',
			'chat.camera' => 'Cámara',
			'chat.photoLibrary' => 'Galería de fotos',
			'chat.offline' => 'Desconectado…',
			'chat.steerResponse' => 'Dirigir respuesta…',
			'chat.addCaption' => 'Añadir descripción…',
			'chat.sendMessage' => 'Enviar mensaje…',
			'chat.queuedTapToEdit' => 'En cola. Toca para editar.',
			'chat.queuedFollowUp' => 'Mensaje en cola.',
			'chat.clearQueued' => 'Limpiar mensaje en cola',
			'chat.attachImage' => 'Adjuntar imagen',
			'chat.quickActionsTooltip' => 'Acciones rápidas',
			'chat.slideToCancel' => 'desliza para cancelar',
			'chat.releaseToCancel' => 'suelta para cancelar',
			'pairing.scanQrTitle' => 'Escanear código QR',
			'pairing.scanQrSubtitle' => 'Apunta la cámara al QR mostrado en tu Mac',
			'pairing.pasteQr' => 'Pegar QR',
			'pairing.pasteQrHint' => 'Pega el contenido del código QR',
			'pairing.pairing' => 'Emparejando…',
			'pairing.paired' => '¡Emparejado!',
			'pairing.pairDevice' => 'Emparejar dispositivo',
			'pairing.connectingTo' => 'Conectando a',
			'pairing.pointCamera' => 'Apunta la cámara al QR mostrado en la terminal de tu Mac',
			'pairing.tryAgain' => 'Intentar de nuevo',
			'pairing.timedOut' => 'Tiempo agotado — asegúrate de que /remote-pi está corriendo en tu Mac',
			'pairing.cantScan' => '¿No puedes escanear? Pega el código',
			'pairing.nameThisPC' => 'Nombrar este PC',
			'pairing.nameThisPCDesc' => 'Elige un nombre para identificar este Mac en tu lista. Puedes cambiarlo después desde la pantalla de inicio.',
			'pairing.skip' => 'Saltar',
			'pairing.pastePairingCode' => 'Pegar código de emparejamiento',
			'pairing.pasteFromClipboard' => 'Pegar del portapapeles',
			'pairing.pair' => 'Emparejar',
			'settings.title' => 'Configuración',
			'settings.display' => 'Pantalla',
			'settings.theme' => 'Tema',
			'settings.system' => 'Sistema',
			'settings.light' => 'Claro',
			'settings.dark' => 'Oscuro',
			'settings.language' => 'Idioma',
			'settings.hideToolCalls' => 'Ocultar llamadas de herramientas',
			'settings.hideToolCallsDesc' => 'Mostrar solo tus mensajes y las respuestas del asistente.',
			'settings.pairings' => 'Emparejamientos',
			'settings.addNewPairing' => 'Añadir nuevo emparejamiento',
			'settings.tapToPair' => 'Toca + para emparejar un nuevo Mac.',
			'settings.relay' => 'Relay',
			'settings.relayUpdated' => 'Relay actualizado',
			'settings.current' => 'Actual',
			'settings.save' => 'Guardar',
			'settings.useDefaultRelay' => 'Usar Relay predeterminado',
			'settings.close' => 'Cerrar',
			'settings.back' => 'Volver',
			_ => null,
		};
	}
}
