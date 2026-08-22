// Entidades da feature **Task Run**. Imutáveis, sem IO/UI. O executor é
// GENÉRICO: conhece só `command`/`args`/`env`. Nada de stack (flavor,
// dart-define, NODE_ENV) mora aqui — isso vira `args`/`env` gerados pelos
// adapters na borda (ver `domain/contracts/task_adapter.dart`).

/// Tarefa de longa duração (watch/dev-server) vs disparo único (build/test).
///
/// - [watch]: o processo fica vivo recompilando (ex.: `vite`, `flutter run`).
/// - [oneShot]: roda até terminar e reporta sucesso/falha (ex.: `flutter build`).
enum TaskKind { watch, oneShot }

/// De onde a [TaskDefinition] veio: detecção automática vs `.cockpit/tasks.json`.
enum TaskSource { detected, manual }

/// Uma tecla interativa enviada ao stdin do PTY da task (ex.: Flutter `r`/`R`).
/// A UI renderiza N controles a partir da lista — sem nenhum `if (flutter)`.
class InteractiveKey {
  const InteractiveKey({
    required this.key,
    required this.label,
    this.icon,
    this.primary = false,
  });

  /// O byte/sequência escrito no PTY ao acionar (ex.: `"r"`, `"R"`, `"q"`).
  final String key;

  /// Rótulo amigável (ex.: "Hot reload").
  final String label;

  /// Token de ícone opcional (resolvido na `ui/`). Sem ícone → chip `[r]`.
  final String? icon;

  /// `true` = botão fixo na linha da task; `false` = vai pro overflow `⌨`.
  final bool primary;
}

/// Observador opcional de arquivos ("reload ao salvar"). O `flutter run` CLI
/// **não** recarrega sozinho — isso é feature de IDE/plugin que o cockpit
/// reimplementa via `Directory.watch`. Dev-servers que já observam (vite/next)
/// têm [TaskDefinition.watch] == null → sem watcher duplo.
class TaskWatch {
  const TaskWatch({
    required this.paths,
    this.ignore = const [],
    required this.onChange,
    this.debounceMs = 300,
  });

  /// Globs relativos ao cwd a observar (ex.: `["lib/**", "assets/**"]`).
  final List<String> paths;

  /// Globs a ignorar (ex.: `["build/**", ".dart_tool/**"]`) — evita loop.
  final List<String> ignore;

  /// Ação ao detectar mudança: o [InteractiveKey.label] a disparar (ex.:
  /// "Hot reload") ou o sentinela [restart].
  final String onChange;

  /// Janela de debounce — um save costuma emitir 2-3 eventos de filesystem.
  final int debounceMs;

  /// Sentinela de [onChange]: mata e re-spawna o processo inteiro.
  static const String restart = '__restart__';
}

/// Par de regexes que detectam início/fim de uma recompilação no output, pro
/// badge oscilar `building → running`. Equivale ao `beginsPattern/endsPattern`
/// do VSCode. Defaults vêm embutidos por adapter.
class ProgressPattern {
  const ProgressPattern({required this.begin, required this.end});

  /// Regex que marca "começou a recompilar" (ex.: `Performing hot reload`).
  final String begin;

  /// Regex que marca "voltou ao idle" (ex.: `Reloaded .* in .*ms`).
  final String end;
}

/// "Launch config": conjunto NOMEADO de args/env extras. Genérico — flavor e
/// dart-define do Flutter viram `args` aqui (`["--flavor","dev",...]`), gerados
/// pelo adapter; o schema não conhece esses conceitos.
class TaskProfile {
  const TaskProfile({
    required this.name,
    this.args = const [],
    this.env = const {},
  });

  /// Nome exibido no dropdown (ex.: "dev", "prod").
  final String name;

  /// Args concatenados **após** [TaskDefinition.args].
  final List<String> args;

  /// Variáveis mescladas sobre o env do processo.
  final Map<String, String> env;
}

/// Quando o link de preview abre sozinho. Restart de um dev-server não deveria
/// jogar uma aba nova na cara de quem já está com a app (ou o Swagger) aberto.
///
/// - [always]: abre em todo start, restart incluso (default — comportamento
///   histórico, preservado para quem não configura nada).
/// - [start]: abre só no start; o botão Restart e o restart do watcher não
///   reabrem. Um stop + start manual conta como start novo e abre.
/// - [never]: nunca abre sozinho.
enum TaskPreviewOpen { always, start, never }

/// Definição estática de uma task (detectada ou do JSON). Tudo aqui é genérico.
class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.label,
    required this.cwd,
    required this.command,
    this.args = const [],
    this.kind = TaskKind.oneShot,
    this.source = TaskSource.detected,
    this.profiles = const [],
    this.interactiveKeys = const [],
    this.watch,
    this.progressPatterns = const [],
    this.previewEnabled = true,
    this.previewUrl,
    this.previewOpen = TaskPreviewOpen.always,
  });

  /// Identidade estável dentro de um projeto (ex.: `"npm:dev"`, `"flutter:run"`).
  final String id;

  /// Rótulo curto exibido na lista (ex.: "dev", "app", "build").
  final String label;

  /// Pasta de trabalho onde a task roda (raiz do projeto). Preenchida pelo
  /// adapter na detecção — a task é self-contained pra execução.
  final String cwd;

  /// Executável base (ex.: `"npm"`, `"flutter"`, `"go"`).
  final String command;

  /// Args base (ex.: `["run", "dev"]`), antes do profile.
  final List<String> args;

  final TaskKind kind;
  final TaskSource source;

  /// Variantes de execução. Vazio = a task roda sem escolha de profile.
  final List<TaskProfile> profiles;

  /// Teclas interativas (vazio = task sem teclas, ex.: vite).
  final List<InteractiveKey> interactiveKeys;

  /// Watcher opcional (null = a ferramenta já observa sozinha).
  final TaskWatch? watch;

  /// Padrões begin/end pro badge building→running (vazio = sem oscilação).
  final List<ProgressPattern> progressPatterns;

  /// Auto-open do navegador (plano 58). `"preview": false` no tasks.json
  /// desliga a detecção de URL local no output desta task.
  final bool previewEnabled;

  /// `"preview": "<url>"` — URL fixa aberta no start, sem depender do output.
  final String? previewUrl;

  /// `"previewOpen"` — em quais execuções o auto-open vale. Default [always]
  /// (retrocompatível). Ignorado quando [previewEnabled] é `false`.
  final TaskPreviewOpen previewOpen;

  /// Este run deve abrir o link sozinho? `preview: false` desliga tudo; fora
  /// isso quem manda é [previewOpen]. [isRestart] é `true` só quando o run
  /// nasceu de um restart (botão ou watcher), nunca de um start.
  bool shouldOpenPreview({required bool isRestart}) {
    if (!previewEnabled) return false;
    return switch (previewOpen) {
      TaskPreviewOpen.always => true,
      TaskPreviewOpen.start => !isRestart,
      TaskPreviewOpen.never => false,
    };
  }

  /// Linha de comando final (preview na UI e execução): base + args do profile.
  List<String> resolveArgs(TaskProfile? profile) => [
    ...args,
    if (profile != null) ...profile.args,
  ];
}
