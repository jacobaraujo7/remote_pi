///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$notifications$en notifications = Translations$notifications$en._(_root);
	late final Translations$common$en common = Translations$common$en._(_root);
	late final Translations$home$en home = Translations$home$en._(_root);
	late final Translations$chat$en chat = Translations$chat$en._(_root);
	late final Translations$pairing$en pairing = Translations$pairing$en._(_root);
	late final Translations$settings$en settings = Translations$settings$en._(_root);
}

// Path: notifications
class Translations$notifications$en {
	Translations$notifications$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Agent finished'
	String get agentFinished => 'Agent finished';
}

// Path: common
class Translations$common$en {
	Translations$common$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Confirm'
	String get confirm => 'Confirm';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'OK'
	String get ok => 'OK';

	/// en: 'Loading…'
	String get loading => 'Loading…';

	/// en: 'Send'
	String get send => 'Send';

	/// en: 'Submit'
	String get submit => 'Submit';

	/// en: 'Open'
	String get open => 'Open';

	/// en: 'Dismiss'
	String get dismiss => 'Dismiss';

	/// en: 'Settings'
	String get settings => 'Settings';
}

// Path: home
class Translations$home$en {
	Translations$home$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Remote Pi'
	String get title => 'Remote Pi';

	/// en: 'Relay'
	String get relay => 'Relay';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Offline'
	String get offline => 'Offline';

	/// en: 'Awaiting pairing'
	String get awaitingPairing => 'Awaiting pairing';

	/// en: 'No pairings yet'
	String get noPairings => 'No pairings yet';

	/// en: 'Scan a QR from your Mac to start.'
	String get scanQrToStart => 'Scan a QR from your Mac to start.';

	/// en: 'Scan QR'
	String get scanQr => 'Scan QR';

	/// en: 'Nothing here…'
	String get nothingHere => 'Nothing here…';

	/// en: 'When a paired Pi opens a session, it shows up here.'
	String get sessionAppearsHere => 'When a paired Pi opens a session, it shows up here.';

	/// en: 'Rename session'
	String get renameSession => 'Rename session';

	/// en: 'Delete session (local only)'
	String get deleteSession => 'Delete session (local only)';

	/// en: 'Only available when the room is offline'
	String get deleteOnlyOffline => 'Only available when the room is offline';

	/// en: 'Delete session?'
	String get deleteConfirmTitle => 'Delete session?';

	/// en: 'Removes locally only. If the session comes back online on the Pi, it reappears in the list.'
	String get deleteConfirmMessage => 'Removes locally only. If the session comes back online on the Pi, it reappears in the list.';

	/// en: 'Rename session'
	String get renameDialogTitle => 'Rename session';

	/// en: 'Last paired'
	String get lastPaired => 'Last paired';

	/// en: 'All'
	String get all => 'All';

	/// en: 'Online'
	String get online => 'Online';
}

// Path: chat
class Translations$chat$en {
	Translations$chat$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Message…'
	String get placeholder => 'Message…';

	/// en: 'Thinking…'
	String get thinking => 'Thinking…';

	/// en: 'working…'
	String get working => 'working…';

	/// en: 'Stop'
	String get stop => 'Stop';

	/// en: 'Session ended'
	String get sessionEnded => 'Session ended';

	/// en: 'Reconnecting…'
	String get reconnecting => 'Reconnecting…';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Session info'
	String get sessionInfo => 'Session info';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Path'
	String get path => 'Path';

	/// en: 'Owner'
	String get owner => 'Owner';

	/// en: 'Model'
	String get model => 'Model';

	/// en: 'Room'
	String get room => 'Room';

	/// en: 'Paired'
	String get paired => 'Paired';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Nickname'
	String get nickname => 'Nickname';

	/// en: 'Local only — the Mac is not notified.'
	String get nicknameLocalOnly => 'Local only — the Mac is not notified.';

	/// en: 'Remove nickname'
	String get removeNickname => 'Remove nickname';

	/// en: 'Default'
	String get default_ => 'Default';

	/// en: 'No active device'
	String get noActiveDevice => 'No active device';

	/// en: 'Connecting…'
	String get connecting => 'Connecting…';

	/// en: 'Re-pair'
	String get rePair => 'Re-pair';

	/// en: 'Nothing here'
	String get nothingHere => 'Nothing here';

	/// en: 'Camera access is off — enable it in Settings to attach a photo.'
	String get cameraOff => 'Camera access is off — enable it in Settings to attach a photo.';

	/// en: 'Microphone access is off — enable it in Settings to dictate.'
	String get micOff => 'Microphone access is off — enable it in Settings to dictate.';

	/// en: 'Hold the mic to talk'
	String get holdMic => 'Hold the mic to talk';

	/// en: 'Pairing revoked by Mac — re-pair to continue'
	String get pairingRevoked => 'Pairing revoked by Mac — re-pair to continue';

	/// en: 'Quick actions'
	String get quickActions => 'Quick actions';

	/// en: 'Compact context'
	String get compactContext => 'Compact context';

	/// en: 'Summarize old turns to free room.'
	String get compactContextDesc => 'Summarize old turns to free room.';

	/// en: 'Context compacted'
	String get contextCompacted => 'Context compacted';

	/// en: 'RUNNING'
	String get running => 'RUNNING';

	/// en: 'DONE'
	String get done => 'DONE';

	/// en: 'FAILED'
	String get failed => 'FAILED';

	/// en: 'DENIED'
	String get denied => 'DENIED';

	/// en: 'EXPIRED'
	String get expired => 'EXPIRED';

	/// en: '✓ Done'
	String get doneOutcome => '✓ Done';

	/// en: '⏳ Running…'
	String get runningOutcome => '⏳ Running…';

	/// en: 'Failed'
	String get failedOutcome => 'Failed';

	/// en: 'Denied'
	String get deniedOutcome => 'Denied';

	/// en: 'Expired'
	String get expiredOutcome => 'Expired';

	/// en: 'New session'
	String get newSession => 'New session';

	/// en: 'Clears the conversation on the Pi.'
	String get newSessionDesc => 'Clears the conversation on the Pi.';

	/// en: 'Start a new session?'
	String get newSessionConfirm => 'Start a new session?';

	/// en: 'This clears the Pi-side conversation history. The current'
	String get newSessionConfirmDesc => 'This clears the Pi-side conversation history. The current';

	/// en: 'Start new'
	String get startNew => 'Start new';

	/// en: 'Choose a model'
	String get chooseModel => 'Choose a model';

	/// en: 'Switching…'
	String get switching => 'Switching…';

	/// en: 'No models available'
	String get noModels => 'No models available';

	/// en: 'Failed to load models'
	String get failedToLoad => 'Failed to load models';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Select a session'
	String get selectSession => 'Select a session';

	/// en: 'Pick a session on the left to open its chat.'
	String get selectSessionDesc => 'Pick a session on the left to open its chat.';

	/// en: 'Copy code'
	String get copyCode => 'Copy code';

	/// en: 'Clarification needed'
	String get clarificationNeeded => 'Clarification needed';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Camera'
	String get camera => 'Camera';

	/// en: 'Photo Library'
	String get photoLibrary => 'Photo Library';

	/// en: 'Offline…'
	String get offline => 'Offline…';

	/// en: 'Steer current response…'
	String get steerResponse => 'Steer current response…';

	/// en: 'Add a caption…'
	String get addCaption => 'Add a caption…';

	/// en: 'Send a message…'
	String get sendMessage => 'Send a message…';

	/// en: 'Queued. Tap to edit.'
	String get queuedTapToEdit => 'Queued. Tap to edit.';

	/// en: 'Queued follow-up.'
	String get queuedFollowUp => 'Queued follow-up.';

	/// en: 'Clear queued message'
	String get clearQueued => 'Clear queued message';

	/// en: 'Attach image'
	String get attachImage => 'Attach image';

	/// en: 'Quick actions'
	String get quickActionsTooltip => 'Quick actions';

	/// en: 'slide to cancel'
	String get slideToCancel => 'slide to cancel';

	/// en: 'release to cancel'
	String get releaseToCancel => 'release to cancel';
}

// Path: pairing
class Translations$pairing$en {
	Translations$pairing$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Scan QR Code'
	String get scanQrTitle => 'Scan QR Code';

	/// en: 'Point the camera at the QR shown on your Mac'
	String get scanQrSubtitle => 'Point the camera at the QR shown on your Mac';

	/// en: 'Paste QR'
	String get pasteQr => 'Paste QR';

	/// en: 'Paste the QR code content'
	String get pasteQrHint => 'Paste the QR code content';

	/// en: 'Pairing…'
	String get pairing => 'Pairing…';

	/// en: 'Paired!'
	String get paired => 'Paired!';

	/// en: 'Pair device'
	String get pairDevice => 'Pair device';

	/// en: 'Connecting to'
	String get connectingTo => 'Connecting to';

	/// en: 'Point camera at the QR shown in your Mac terminal'
	String get pointCamera => 'Point camera at the QR shown in your Mac terminal';

	/// en: 'Try again'
	String get tryAgain => 'Try again';

	/// en: 'Timed out — make sure /remote-pi is running on your Mac'
	String get timedOut => 'Timed out — make sure /remote-pi is running on your Mac';

	/// en: 'Can't scan? Paste code instead'
	String get cantScan => 'Can\'t scan? Paste code instead';

	/// en: 'Name this PC'
	String get nameThisPC => 'Name this PC';

	/// en: 'Pick a label so this Mac is easy to spot in your list. You can change it later from the home screen.'
	String get nameThisPCDesc => 'Pick a label so this Mac is easy to spot in your list. You can change it later from the home screen.';

	/// en: 'Skip'
	String get skip => 'Skip';

	/// en: 'Paste pairing code'
	String get pastePairingCode => 'Paste pairing code';

	/// en: 'Paste from clipboard'
	String get pasteFromClipboard => 'Paste from clipboard';

	/// en: 'Pair'
	String get pair => 'Pair';
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings'
	String get title => 'Settings';

	/// en: 'Display'
	String get display => 'Display';

	/// en: 'Theme'
	String get theme => 'Theme';

	/// en: 'System'
	String get system => 'System';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Hide tool calls in chat'
	String get hideToolCalls => 'Hide tool calls in chat';

	/// en: 'Only show your messages and the assistant replies.'
	String get hideToolCallsDesc => 'Only show your messages and the assistant replies.';

	/// en: 'Pairings'
	String get pairings => 'Pairings';

	/// en: 'Add new pairing'
	String get addNewPairing => 'Add new pairing';

	/// en: 'Tap + to pair a new Mac.'
	String get tapToPair => 'Tap + to pair a new Mac.';

	/// en: 'Relay'
	String get relay => 'Relay';

	/// en: 'Relay updated'
	String get relayUpdated => 'Relay updated';

	/// en: 'Current'
	String get current => 'Current';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Use default Relay'
	String get useDefaultRelay => 'Use default Relay';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Back'
	String get back => 'Back';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'notifications.agentFinished' => 'Agent finished',
			'common.cancel' => 'Cancel',
			'common.confirm' => 'Confirm',
			'common.save' => 'Save',
			'common.close' => 'Close',
			'common.delete' => 'Delete',
			'common.done' => 'Done',
			'common.ok' => 'OK',
			'common.loading' => 'Loading…',
			'common.send' => 'Send',
			'common.submit' => 'Submit',
			'common.open' => 'Open',
			'common.dismiss' => 'Dismiss',
			'common.settings' => 'Settings',
			'home.title' => 'Remote Pi',
			'home.relay' => 'Relay',
			'home.connected' => 'Connected',
			'home.offline' => 'Offline',
			'home.awaitingPairing' => 'Awaiting pairing',
			'home.noPairings' => 'No pairings yet',
			'home.scanQrToStart' => 'Scan a QR from your Mac to start.',
			'home.scanQr' => 'Scan QR',
			'home.nothingHere' => 'Nothing here…',
			'home.sessionAppearsHere' => 'When a paired Pi opens a session, it shows up here.',
			'home.renameSession' => 'Rename session',
			'home.deleteSession' => 'Delete session (local only)',
			'home.deleteOnlyOffline' => 'Only available when the room is offline',
			'home.deleteConfirmTitle' => 'Delete session?',
			'home.deleteConfirmMessage' => 'Removes locally only. If the session comes back online on the Pi, it reappears in the list.',
			'home.renameDialogTitle' => 'Rename session',
			'home.lastPaired' => 'Last paired',
			'home.all' => 'All',
			'home.online' => 'Online',
			'chat.placeholder' => 'Message…',
			'chat.thinking' => 'Thinking…',
			'chat.working' => 'working…',
			'chat.stop' => 'Stop',
			'chat.sessionEnded' => 'Session ended',
			'chat.reconnecting' => 'Reconnecting…',
			'chat.back' => 'Back',
			'chat.sessionInfo' => 'Session info',
			'chat.name' => 'Name',
			'chat.path' => 'Path',
			'chat.owner' => 'Owner',
			'chat.model' => 'Model',
			'chat.room' => 'Room',
			'chat.paired' => 'Paired',
			'chat.close' => 'Close',
			'chat.nickname' => 'Nickname',
			'chat.nicknameLocalOnly' => 'Local only — the Mac is not notified.',
			'chat.removeNickname' => 'Remove nickname',
			'chat.default_' => 'Default',
			'chat.noActiveDevice' => 'No active device',
			'chat.connecting' => 'Connecting…',
			'chat.rePair' => 'Re-pair',
			'chat.nothingHere' => 'Nothing here',
			'chat.cameraOff' => 'Camera access is off — enable it in Settings to attach a photo.',
			'chat.micOff' => 'Microphone access is off — enable it in Settings to dictate.',
			'chat.holdMic' => 'Hold the mic to talk',
			'chat.pairingRevoked' => 'Pairing revoked by Mac — re-pair to continue',
			'chat.quickActions' => 'Quick actions',
			'chat.compactContext' => 'Compact context',
			'chat.compactContextDesc' => 'Summarize old turns to free room.',
			'chat.contextCompacted' => 'Context compacted',
			'chat.running' => 'RUNNING',
			'chat.done' => 'DONE',
			'chat.failed' => 'FAILED',
			'chat.denied' => 'DENIED',
			'chat.expired' => 'EXPIRED',
			'chat.doneOutcome' => '✓ Done',
			'chat.runningOutcome' => '⏳ Running…',
			'chat.failedOutcome' => 'Failed',
			'chat.deniedOutcome' => 'Denied',
			'chat.expiredOutcome' => 'Expired',
			'chat.newSession' => 'New session',
			'chat.newSessionDesc' => 'Clears the conversation on the Pi.',
			'chat.newSessionConfirm' => 'Start a new session?',
			'chat.newSessionConfirmDesc' => 'This clears the Pi-side conversation history. The current',
			'chat.startNew' => 'Start new',
			'chat.chooseModel' => 'Choose a model',
			'chat.switching' => 'Switching…',
			'chat.noModels' => 'No models available',
			'chat.failedToLoad' => 'Failed to load models',
			'chat.retry' => 'Retry',
			'chat.selectSession' => 'Select a session',
			'chat.selectSessionDesc' => 'Pick a session on the left to open its chat.',
			'chat.copyCode' => 'Copy code',
			'chat.clarificationNeeded' => 'Clarification needed',
			'chat.refresh' => 'Refresh',
			'chat.camera' => 'Camera',
			'chat.photoLibrary' => 'Photo Library',
			'chat.offline' => 'Offline…',
			'chat.steerResponse' => 'Steer current response…',
			'chat.addCaption' => 'Add a caption…',
			'chat.sendMessage' => 'Send a message…',
			'chat.queuedTapToEdit' => 'Queued. Tap to edit.',
			'chat.queuedFollowUp' => 'Queued follow-up.',
			'chat.clearQueued' => 'Clear queued message',
			'chat.attachImage' => 'Attach image',
			'chat.quickActionsTooltip' => 'Quick actions',
			'chat.slideToCancel' => 'slide to cancel',
			'chat.releaseToCancel' => 'release to cancel',
			'pairing.scanQrTitle' => 'Scan QR Code',
			'pairing.scanQrSubtitle' => 'Point the camera at the QR shown on your Mac',
			'pairing.pasteQr' => 'Paste QR',
			'pairing.pasteQrHint' => 'Paste the QR code content',
			'pairing.pairing' => 'Pairing…',
			'pairing.paired' => 'Paired!',
			'pairing.pairDevice' => 'Pair device',
			'pairing.connectingTo' => 'Connecting to',
			'pairing.pointCamera' => 'Point camera at the QR shown in your Mac terminal',
			'pairing.tryAgain' => 'Try again',
			'pairing.timedOut' => 'Timed out — make sure /remote-pi is running on your Mac',
			'pairing.cantScan' => 'Can\'t scan? Paste code instead',
			'pairing.nameThisPC' => 'Name this PC',
			'pairing.nameThisPCDesc' => 'Pick a label so this Mac is easy to spot in your list. You can change it later from the home screen.',
			'pairing.skip' => 'Skip',
			'pairing.pastePairingCode' => 'Paste pairing code',
			'pairing.pasteFromClipboard' => 'Paste from clipboard',
			'pairing.pair' => 'Pair',
			'settings.title' => 'Settings',
			'settings.display' => 'Display',
			'settings.theme' => 'Theme',
			'settings.system' => 'System',
			'settings.light' => 'Light',
			'settings.dark' => 'Dark',
			'settings.language' => 'Language',
			'settings.hideToolCalls' => 'Hide tool calls in chat',
			'settings.hideToolCallsDesc' => 'Only show your messages and the assistant replies.',
			'settings.pairings' => 'Pairings',
			'settings.addNewPairing' => 'Add new pairing',
			'settings.tapToPair' => 'Tap + to pair a new Mac.',
			'settings.relay' => 'Relay',
			'settings.relayUpdated' => 'Relay updated',
			'settings.current' => 'Current',
			'settings.save' => 'Save',
			'settings.useDefaultRelay' => 'Use default Relay',
			'settings.close' => 'Close',
			'settings.back' => 'Back',
			_ => null,
		};
	}
}
