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
class TranslationsPtBr with BaseTranslations<AppLocale, Translations> implements Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsPtBr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ptBr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <pt-BR>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key);

	late final TranslationsPtBr _root = this; // ignore: unused_field

	@override 
	TranslationsPtBr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsPtBr(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$notifications$pt_BR notifications = _Translations$notifications$pt_BR._(_root);
	@override late final _Translations$common$pt_BR common = _Translations$common$pt_BR._(_root);
	@override late final _Translations$home$pt_BR home = _Translations$home$pt_BR._(_root);
	@override late final _Translations$chat$pt_BR chat = _Translations$chat$pt_BR._(_root);
	@override late final _Translations$pairing$pt_BR pairing = _Translations$pairing$pt_BR._(_root);
	@override late final _Translations$settings$pt_BR settings = _Translations$settings$pt_BR._(_root);
}

// Path: notifications
class _Translations$notifications$pt_BR implements Translations$notifications$en {
	_Translations$notifications$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get agentFinished => 'Agente terminou';
}

// Path: common
class _Translations$common$pt_BR implements Translations$common$en {
	_Translations$common$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get confirm => 'Confirmar';
	@override String get save => 'Salvar';
	@override String get close => 'Fechar';
	@override String get delete => 'Excluir';
	@override String get done => 'Concluído';
	@override String get ok => 'OK';
	@override String get loading => 'Carregando…';
	@override String get send => 'Enviar';
	@override String get submit => 'Enviar';
	@override String get open => 'Abrir';
	@override String get dismiss => 'Dispensar';
	@override String get settings => 'Configurações';
}

// Path: home
class _Translations$home$pt_BR implements Translations$home$en {
	_Translations$home$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Remote Pi';
	@override String get relay => 'Relay';
	@override String get connected => 'Conectado';
	@override String get offline => 'Offline';
	@override String get awaitingPairing => 'Aguardando pareamento';
	@override String get noPairings => 'Nenhum pareamento';
	@override String get scanQrToStart => 'Escaneie o QR do seu Mac para começar.';
	@override String get scanQr => 'Escanear QR';
	@override String get nothingHere => 'Nada por aqui…';
	@override String get sessionAppearsHere => 'Quando um Pi pareado abrir uma sessão, ela aparece aqui.';
	@override String get renameSession => 'Renomear sessão';
	@override String get deleteSession => 'Excluir sessão (apenas local)';
	@override String get deleteOnlyOffline => 'Disponível apenas offline';
	@override String get deleteConfirmTitle => 'Excluir sessão?';
	@override String get deleteConfirmMessage => 'Remove apenas localmente. Se a sessão voltar online no Pi, ela reaparece na lista.';
	@override String get renameDialogTitle => 'Renomear sessão';
	@override String get lastPaired => 'Pareado em';
	@override String get all => 'Todos';
	@override String get online => 'Online';
}

// Path: chat
class _Translations$chat$pt_BR implements Translations$chat$en {
	_Translations$chat$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get placeholder => 'Mensagem…';
	@override String get thinking => 'Pensando…';
	@override String get working => 'trabalhando…';
	@override String get stop => 'Parar';
	@override String get sessionEnded => 'Sessão encerrada';
	@override String get reconnecting => 'Reconectando…';
	@override String get back => 'Voltar';
	@override String get sessionInfo => 'Info da sessão';
	@override String get name => 'Nome';
	@override String get path => 'Caminho';
	@override String get owner => 'Proprietário';
	@override String get model => 'Modelo';
	@override String get room => 'Sala';
	@override String get paired => 'Pareado';
	@override String get close => 'Fechar';
	@override String get nickname => 'Apelido';
	@override String get nicknameLocalOnly => 'Apenas local — o Mac não é notificado.';
	@override String get removeNickname => 'Remover apelido';
	@override String get default_ => 'Padrão';
	@override String get noActiveDevice => 'Nenhum dispositivo ativo';
	@override String get connecting => 'Conectando…';
	@override String get rePair => 'Reparear';
	@override String get nothingHere => 'Nada aqui';
	@override String get cameraOff => 'Acesso à câmera desativado — ative nas Configurações para anexar uma foto.';
	@override String get micOff => 'Acesso ao microfone desativado — ative nas Configurações para ditar.';
	@override String get holdMic => 'Segure o microfone para falar';
	@override String get pairingRevoked => 'Pareamento revogado pelo Mac — repareie para continuar';
	@override String get quickActions => 'Ações rápidas';
	@override String get compactContext => 'Compactar contexto';
	@override String get compactContextDesc => 'Resumir turnos antigos para liberar espaço.';
	@override String get contextCompacted => 'Contexto compactado';
	@override String get running => 'EXECUTANDO';
	@override String get done => 'CONCLUÍDO';
	@override String get failed => 'FALHOU';
	@override String get denied => 'NEGADO';
	@override String get expired => 'EXPIRADO';
	@override String get doneOutcome => '✓ Concluído';
	@override String get runningOutcome => '⏳ Executando…';
	@override String get failedOutcome => 'Falhou';
	@override String get deniedOutcome => 'Negado';
	@override String get expiredOutcome => 'Expirado';
	@override String get newSession => 'Nova sessão';
	@override String get newSessionDesc => 'Limpa a conversa no Pi.';
	@override String get newSessionConfirm => 'Iniciar uma nova sessão?';
	@override String get newSessionConfirmDesc => 'Isso limpa o histórico da conversa no Pi.';
	@override String get startNew => 'Iniciar nova';
	@override String get chooseModel => 'Escolher modelo';
	@override String get switching => 'Trocando…';
	@override String get noModels => 'Nenhum modelo disponível';
	@override String get failedToLoad => 'Falha ao carregar modelos';
	@override String get retry => 'Tentar novamente';
	@override String get selectSession => 'Selecione uma sessão';
	@override String get selectSessionDesc => 'Escolha uma sessão à esquerda para abrir o chat.';
	@override String get copyCode => 'Copiar código';
	@override String get clarificationNeeded => 'Esclarecimento necessário';
	@override String get refresh => 'Atualizar';
	@override String get camera => 'Câmera';
	@override String get photoLibrary => 'Galeria de fotos';
	@override String get offline => 'Offline…';
	@override String get steerResponse => 'Direcionar resposta…';
	@override String get addCaption => 'Adicionar legenda…';
	@override String get sendMessage => 'Enviar mensagem…';
	@override String get queuedTapToEdit => 'Na fila. Toque para editar.';
	@override String get queuedFollowUp => 'Mensagem na fila.';
	@override String get clearQueued => 'Limpar mensagem na fila';
	@override String get attachImage => 'Anexar imagem';
	@override String get quickActionsTooltip => 'Ações rápidas';
	@override String get slideToCancel => 'deslize para cancelar';
	@override String get releaseToCancel => 'solte para cancelar';
}

// Path: pairing
class _Translations$pairing$pt_BR implements Translations$pairing$en {
	_Translations$pairing$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get scanQrTitle => 'Escanear QR Code';
	@override String get scanQrSubtitle => 'Aponte a câmera para o QR code exibido no Mac';
	@override String get pasteQr => 'Colar QR';
	@override String get pasteQrHint => 'Cole o conteúdo do QR code';
	@override String get pairing => 'Pareando…';
	@override String get paired => 'Pareado!';
	@override String get pairDevice => 'Parear dispositivo';
	@override String get connectingTo => 'Conectando a';
	@override String get pointCamera => 'Aponte a câmera para o QR exibido no terminal do Mac';
	@override String get tryAgain => 'Tentar novamente';
	@override String get timedOut => 'Tempo esgotado — verifique se /remote-pi está rodando no Mac';
	@override String get cantScan => 'Não consegue escanear? Cole o código';
	@override String get nameThisPC => 'Nomeie este PC';
	@override String get nameThisPCDesc => 'Escolha um nome para identificar este Mac na sua lista. Você pode mudar depois na tela inicial.';
	@override String get skip => 'Pular';
	@override String get pastePairingCode => 'Colar código de pareamento';
	@override String get pasteFromClipboard => 'Colar da área de transferência';
	@override String get pair => 'Parear';
}

// Path: settings
class _Translations$settings$pt_BR implements Translations$settings$en {
	_Translations$settings$pt_BR._(this._root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Configurações';
	@override String get display => 'Exibição';
	@override String get theme => 'Tema';
	@override String get system => 'Sistema';
	@override String get light => 'Claro';
	@override String get dark => 'Escuro';
	@override String get language => 'Idioma';
	@override String get hideToolCalls => 'Ocultar chamadas de ferramentas';
	@override String get hideToolCallsDesc => 'Mostrar apenas suas mensagens e as respostas do assistente.';
	@override String get pairings => 'Pareamentos';
	@override String get addNewPairing => 'Adicionar novo pareamento';
	@override String get tapToPair => 'Toque em + para parear um novo Mac.';
	@override String get relay => 'Relay';
	@override String get relayUpdated => 'Relay atualizado';
	@override String get current => 'Atual';
	@override String get save => 'Salvar';
	@override String get useDefaultRelay => 'Usar Relay padrão';
	@override String get close => 'Fechar';
	@override String get back => 'Voltar';
}

/// The flat map containing all translations for locale <pt-BR>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsPtBr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notifications.agentFinished' => 'Agente terminou',
			'common.cancel' => 'Cancelar',
			'common.confirm' => 'Confirmar',
			'common.save' => 'Salvar',
			'common.close' => 'Fechar',
			'common.delete' => 'Excluir',
			'common.done' => 'Concluído',
			'common.ok' => 'OK',
			'common.loading' => 'Carregando…',
			'common.send' => 'Enviar',
			'common.submit' => 'Enviar',
			'common.open' => 'Abrir',
			'common.dismiss' => 'Dispensar',
			'common.settings' => 'Configurações',
			'home.title' => 'Remote Pi',
			'home.relay' => 'Relay',
			'home.connected' => 'Conectado',
			'home.offline' => 'Offline',
			'home.awaitingPairing' => 'Aguardando pareamento',
			'home.noPairings' => 'Nenhum pareamento',
			'home.scanQrToStart' => 'Escaneie o QR do seu Mac para começar.',
			'home.scanQr' => 'Escanear QR',
			'home.nothingHere' => 'Nada por aqui…',
			'home.sessionAppearsHere' => 'Quando um Pi pareado abrir uma sessão, ela aparece aqui.',
			'home.renameSession' => 'Renomear sessão',
			'home.deleteSession' => 'Excluir sessão (apenas local)',
			'home.deleteOnlyOffline' => 'Disponível apenas offline',
			'home.deleteConfirmTitle' => 'Excluir sessão?',
			'home.deleteConfirmMessage' => 'Remove apenas localmente. Se a sessão voltar online no Pi, ela reaparece na lista.',
			'home.renameDialogTitle' => 'Renomear sessão',
			'home.lastPaired' => 'Pareado em',
			'home.all' => 'Todos',
			'home.online' => 'Online',
			'chat.placeholder' => 'Mensagem…',
			'chat.thinking' => 'Pensando…',
			'chat.working' => 'trabalhando…',
			'chat.stop' => 'Parar',
			'chat.sessionEnded' => 'Sessão encerrada',
			'chat.reconnecting' => 'Reconectando…',
			'chat.back' => 'Voltar',
			'chat.sessionInfo' => 'Info da sessão',
			'chat.name' => 'Nome',
			'chat.path' => 'Caminho',
			'chat.owner' => 'Proprietário',
			'chat.model' => 'Modelo',
			'chat.room' => 'Sala',
			'chat.paired' => 'Pareado',
			'chat.close' => 'Fechar',
			'chat.nickname' => 'Apelido',
			'chat.nicknameLocalOnly' => 'Apenas local — o Mac não é notificado.',
			'chat.removeNickname' => 'Remover apelido',
			'chat.default_' => 'Padrão',
			'chat.noActiveDevice' => 'Nenhum dispositivo ativo',
			'chat.connecting' => 'Conectando…',
			'chat.rePair' => 'Reparear',
			'chat.nothingHere' => 'Nada aqui',
			'chat.cameraOff' => 'Acesso à câmera desativado — ative nas Configurações para anexar uma foto.',
			'chat.micOff' => 'Acesso ao microfone desativado — ative nas Configurações para ditar.',
			'chat.holdMic' => 'Segure o microfone para falar',
			'chat.pairingRevoked' => 'Pareamento revogado pelo Mac — repareie para continuar',
			'chat.quickActions' => 'Ações rápidas',
			'chat.compactContext' => 'Compactar contexto',
			'chat.compactContextDesc' => 'Resumir turnos antigos para liberar espaço.',
			'chat.contextCompacted' => 'Contexto compactado',
			'chat.running' => 'EXECUTANDO',
			'chat.done' => 'CONCLUÍDO',
			'chat.failed' => 'FALHOU',
			'chat.denied' => 'NEGADO',
			'chat.expired' => 'EXPIRADO',
			'chat.doneOutcome' => '✓ Concluído',
			'chat.runningOutcome' => '⏳ Executando…',
			'chat.failedOutcome' => 'Falhou',
			'chat.deniedOutcome' => 'Negado',
			'chat.expiredOutcome' => 'Expirado',
			'chat.newSession' => 'Nova sessão',
			'chat.newSessionDesc' => 'Limpa a conversa no Pi.',
			'chat.newSessionConfirm' => 'Iniciar uma nova sessão?',
			'chat.newSessionConfirmDesc' => 'Isso limpa o histórico da conversa no Pi.',
			'chat.startNew' => 'Iniciar nova',
			'chat.chooseModel' => 'Escolher modelo',
			'chat.switching' => 'Trocando…',
			'chat.noModels' => 'Nenhum modelo disponível',
			'chat.failedToLoad' => 'Falha ao carregar modelos',
			'chat.retry' => 'Tentar novamente',
			'chat.selectSession' => 'Selecione uma sessão',
			'chat.selectSessionDesc' => 'Escolha uma sessão à esquerda para abrir o chat.',
			'chat.copyCode' => 'Copiar código',
			'chat.clarificationNeeded' => 'Esclarecimento necessário',
			'chat.refresh' => 'Atualizar',
			'chat.camera' => 'Câmera',
			'chat.photoLibrary' => 'Galeria de fotos',
			'chat.offline' => 'Offline…',
			'chat.steerResponse' => 'Direcionar resposta…',
			'chat.addCaption' => 'Adicionar legenda…',
			'chat.sendMessage' => 'Enviar mensagem…',
			'chat.queuedTapToEdit' => 'Na fila. Toque para editar.',
			'chat.queuedFollowUp' => 'Mensagem na fila.',
			'chat.clearQueued' => 'Limpar mensagem na fila',
			'chat.attachImage' => 'Anexar imagem',
			'chat.quickActionsTooltip' => 'Ações rápidas',
			'chat.slideToCancel' => 'deslize para cancelar',
			'chat.releaseToCancel' => 'solte para cancelar',
			'pairing.scanQrTitle' => 'Escanear QR Code',
			'pairing.scanQrSubtitle' => 'Aponte a câmera para o QR code exibido no Mac',
			'pairing.pasteQr' => 'Colar QR',
			'pairing.pasteQrHint' => 'Cole o conteúdo do QR code',
			'pairing.pairing' => 'Pareando…',
			'pairing.paired' => 'Pareado!',
			'pairing.pairDevice' => 'Parear dispositivo',
			'pairing.connectingTo' => 'Conectando a',
			'pairing.pointCamera' => 'Aponte a câmera para o QR exibido no terminal do Mac',
			'pairing.tryAgain' => 'Tentar novamente',
			'pairing.timedOut' => 'Tempo esgotado — verifique se /remote-pi está rodando no Mac',
			'pairing.cantScan' => 'Não consegue escanear? Cole o código',
			'pairing.nameThisPC' => 'Nomeie este PC',
			'pairing.nameThisPCDesc' => 'Escolha um nome para identificar este Mac na sua lista. Você pode mudar depois na tela inicial.',
			'pairing.skip' => 'Pular',
			'pairing.pastePairingCode' => 'Colar código de pareamento',
			'pairing.pasteFromClipboard' => 'Colar da área de transferência',
			'pairing.pair' => 'Parear',
			'settings.title' => 'Configurações',
			'settings.display' => 'Exibição',
			'settings.theme' => 'Tema',
			'settings.system' => 'Sistema',
			'settings.light' => 'Claro',
			'settings.dark' => 'Escuro',
			'settings.language' => 'Idioma',
			'settings.hideToolCalls' => 'Ocultar chamadas de ferramentas',
			'settings.hideToolCallsDesc' => 'Mostrar apenas suas mensagens e as respostas do assistente.',
			'settings.pairings' => 'Pareamentos',
			'settings.addNewPairing' => 'Adicionar novo pareamento',
			'settings.tapToPair' => 'Toque em + para parear um novo Mac.',
			'settings.relay' => 'Relay',
			'settings.relayUpdated' => 'Relay atualizado',
			'settings.current' => 'Atual',
			'settings.save' => 'Salvar',
			'settings.useDefaultRelay' => 'Usar Relay padrão',
			'settings.close' => 'Fechar',
			'settings.back' => 'Voltar',
			_ => null,
		};
	}
}
