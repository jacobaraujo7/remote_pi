import 'realm.dart';

/// Natureza de um workspace no rail.
///
/// - [project]: um workspace normal ancorado numa pasta.
/// - [systemTerminal]: o workspace sintético "Cockpit" — sem pasta, terminal-only,
///   injetado em runtime (nunca persistido). Serviços de path (git, árvore, tasks,
///   worktrees) não sobem para ele; o terminal abre no `$HOME` do usuário.
/// - [remoteTerminal]: um host remoto (plano 58, Wave 2) — sintético, injetado
///   em runtime a partir do `RemoteHostsStore`; terminal-only por enquanto (o PTY
///   roda no `cockpit-server` do host via SSH). Serviços de path LOCAIS não sobem
///   (fs/git remotos são fiação futura); [remoteHostId] aponta o host.
enum WorkspaceKind { project, systemTerminal, remoteTerminal }

/// Uma pasta que o usuário salvou como projeto (workspace). Os workspaces raiz
/// são persistidos via Hive; as **worktrees** (forks) são `Project`s de runtime
/// com [parentId] preenchido, derivados do git e **não** persistidos (a
/// existência mora no git — ver `plan/42`, decisões 1 e 4).
/// Agentes do Cockpit atuam em subpastas de [path].
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.colorValue,
    required this.createdAt,
    this.realmId = Realm.defaultId,
    this.parentId,
    this.order = 0,
    this.imagePath,
    this.kind = WorkspaceKind.project,
    this.remoteHostId,
    this.remotePath,
  });

  /// Id sentinela do workspace de sistema "Cockpit". Não é um UUID, então nunca
  /// colide com o id de um projeto real, e o repositório Hive nunca o retorna
  /// (só é injetado em runtime).
  static const String cockpitId = '__cockpit__';

  /// Constrói o workspace sintético "Cockpit" (terminal-only, sem pasta).
  factory Project.systemTerminal() => Project(
    id: cockpitId,
    name: 'Cockpit',
    path: '',
    colorValue: 0xFF6B7280,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    kind: WorkspaceKind.systemTerminal,
  );

  /// Prefixo do id de um workspace remoto sintético.
  static const String remotePrefix = '__remote__';

  /// Constrói o workspace sintético de um pin remoto (plano 58): uma PASTA
  /// ([remotePath]) de um host. O id vem do pin (estável por (host, pasta)).
  factory Project.remoteHost({
    required String pinId,
    required String hostId,
    required String name,
    required String remotePath,
    required int colorValue,
  }) => Project(
    id: '$remotePrefix$pinId',
    name: name,
    path: '',
    colorValue: colorValue,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    kind: WorkspaceKind.remoteTerminal,
    remoteHostId: hostId,
    remotePath: remotePath,
  );

  /// Sentinela do [copyWith] para distinguir "não mexer em [imagePath]" de
  /// "limpar [imagePath] (passar null)".
  static const Object unchanged = Object();

  final String id;

  /// Nome de exibição (por padrão, o basename de [path]).
  final String name;

  /// Caminho absoluto da raiz do projeto.
  final String path;

  /// Cor do avatar (ARGB), atribuída na criação.
  final int colorValue;

  final DateTime createdAt;

  /// `null` para um workspace raiz; o id do workspace pai quando este `Project`
  /// é uma worktree (fork). Define o aninhamento no rail.
  final String? parentId;

  /// Realm (conjunto de workspaces) a que este workspace pertence. O rail só
  /// exibe os do realm ativo. O mesmo [path] pode existir como workspaces
  /// distintos em realms diferentes — por isso [id] é um UUID, não o path.
  final String realmId;

  /// Posição manual no rail (drag-drop de workspaces). Só relevante para
  /// workspaces raiz — worktrees herdam a do pai e aninham embaixo dele.
  /// Persistido; default `0` (dados antigos caem na ordem por [createdAt]).
  final int order;

  /// Caminho absoluto de uma imagem (PNG/JPG) que substitui o avatar
  /// quadrado-com-inicial no rail. `null` = sem imagem. Persistido; se o arquivo
  /// sumir/ilegível, a UI cai num placeholder de erro (ver `WorkspaceAvatar`).
  final String? imagePath;

  /// Natureza do workspace (normal vs. terminal de sistema). Não persistido:
  /// projetos carregados do Hive caem no default [WorkspaceKind.project].
  final WorkspaceKind kind;

  /// Id do host remoto quando [kind] == [WorkspaceKind.remoteTerminal]; senão
  /// `null`. O registro do host vive no `RemoteHostsStore`.
  final String? remoteHostId;

  /// Pasta no filesystem do host quando [kind] == [WorkspaceKind.remoteTerminal].
  /// É o "path" do workspace remoto (o terminal abre aqui; a árvore/git remotos
  /// operam sobre ela). `null`/vazio = HOME do host.
  final String? remotePath;

  /// `true` quando este `Project` é uma worktree de outro workspace.
  bool get isWorktree => parentId != null;

  /// `true` quando este é o workspace sintético "Cockpit" (terminal-only).
  bool get isSystemTerminal => kind == WorkspaceKind.systemTerminal;

  /// `true` quando este é um workspace de host remoto (terminal-only via SSH).
  bool get isRemoteTerminal => kind == WorkspaceKind.remoteTerminal;

  /// `true` para qualquer workspace sem pasta local (Cockpit ou remoto): os
  /// serviços de path locais (git/árvore/tasks/worktrees) não sobem.
  bool get isPathless => isSystemTerminal || isRemoteTerminal;

  /// Inicial pro avatar da rail.
  /// Pasta do workspace **na máquina onde ele vive**: [path] num workspace
  /// local, [remotePath] num remoto — onde [path] é vazio de propósito, porque
  /// a pasta não existe no disco do cliente.
  ///
  /// Existe porque confundir os dois já custou caro: a CLI usava [path] direto
  /// e, num workspace remoto, recebia vazio — o que fazia `cockpit db`,
  /// `list-tasks` e `read-task` recusarem a própria aba com "this pane has no
  /// workspace folder". Vazio aqui significa mesmo "não tem pasta" (terminal
  /// de sistema), e só isso.
  String get effectiveRoot =>
      isRemoteTerminal ? (remotePath ?? '') : path;

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  Project copyWith({
    String? name,
    int? colorValue,
    int? order,
    String? realmId,
    Object? imagePath = unchanged,
  }) => Project(
    id: id,
    name: name ?? this.name,
    path: path,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
    realmId: realmId ?? this.realmId,
    parentId: parentId,
    order: order ?? this.order,
    imagePath: imagePath == unchanged ? this.imagePath : imagePath as String?,
    kind: kind,
    remoteHostId: remoteHostId,
    remotePath: remotePath,
  );

  @override
  bool operator ==(Object other) => other is Project && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
