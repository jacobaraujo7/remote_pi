/// Catálogo único dos agentes de CLI que o Cockpit conhece.
///
/// Mesma lista serve a dois consumidores: a **detecção de processo** (ícone na
/// aba do terminal, via [HarnessSpec.allEntryPoints]) e as **automações** (gerar
/// mensagem de commit, ver `automation.dart`). Antes eram dois enums paralelos
/// que divergiam — um tinha `gemini`, o outro `cursor`/`antigravity`.
enum HarnessKind {
  antigravity,
  claudeCode,
  codex,
  cursor,
  gitHubCopilot,
  openCode,
  pi,
}

class HarnessSpec {
  final HarnessKind kind;
  final String label;
  final String primaryEntryPoint;
  final List<String> aliases;
  final String assetPath;
  final bool isMonochrome;

  const HarnessSpec({
    required this.kind,
    required this.label,
    required this.primaryEntryPoint,
    required this.aliases,
    required this.assetPath,
    required this.isMonochrome,
  });

  /// All entry point names that can trigger this harness.
  List<String> get allEntryPoints => [primaryEntryPoint, ...aliases];
}

abstract class HarnessCatalog {
  static const Map<HarnessKind, HarnessSpec> specs = {
    HarnessKind.antigravity: HarnessSpec(
      kind: HarnessKind.antigravity,
      label: 'Antigravity',
      primaryEntryPoint: 'agy',
      aliases: ['antigravity'],
      assetPath: 'assets/harness_icons/antigravity.svg',
      isMonochrome: false,
    ),
    HarnessKind.claudeCode: HarnessSpec(
      kind: HarnessKind.claudeCode,
      label: 'Claude Code',
      primaryEntryPoint: 'claude',
      aliases: ['claude-code'],
      assetPath: 'assets/harness_icons/claudecode.svg',
      isMonochrome: true,
    ),
    HarnessKind.codex: HarnessSpec(
      kind: HarnessKind.codex,
      label: 'Codex',
      primaryEntryPoint: 'codex',
      aliases: [],
      assetPath: 'assets/harness_icons/codex.svg',
      isMonochrome: false,
    ),
    HarnessKind.cursor: HarnessSpec(
      kind: HarnessKind.cursor,
      label: 'Cursor',
      primaryEntryPoint: 'cursor-agent',
      // `agent` is the published symlink/launcher name (`exec -a` keeps it in argv0).
      aliases: ['cursor', 'agent'],
      assetPath: 'assets/harness_icons/cursor.svg',
      isMonochrome: true,
    ),
    HarnessKind.gitHubCopilot: HarnessSpec(
      kind: HarnessKind.gitHubCopilot,
      label: 'GitHub Copilot',
      primaryEntryPoint: 'copilot',
      aliases: ['github-copilot'],
      assetPath: 'assets/harness_icons/githubcopilot.svg',
      isMonochrome: true,
    ),
    HarnessKind.openCode: HarnessSpec(
      kind: HarnessKind.openCode,
      label: 'OpenCode',
      primaryEntryPoint: 'opencode',
      aliases: [],
      assetPath: 'assets/harness_icons/opencode.svg',
      isMonochrome: true,
    ),
    HarnessKind.pi: HarnessSpec(
      kind: HarnessKind.pi,
      label: 'Pi',
      primaryEntryPoint: 'pi',
      aliases: [],
      assetPath: 'assets/harness_icons/pi.svg',
      isMonochrome: true,
    ),
  };

  static HarnessSpec? getSpec(HarnessKind kind) => specs[kind];
}
