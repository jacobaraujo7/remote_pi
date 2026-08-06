import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/git_history_commit.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_history_file_change.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/git_history_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// Visualizacao read-only de commits estruturados de uma root git.
class GitHistoryPanel extends StatefulWidget {
  const GitHistoryPanel({
    super.key,
    required this.roots,
    required this.loadHistory,
    required this.loadFiles,
    required this.onOpenFileDiff,
    required this.refreshToken,
  });

  final List<GitHistoryRoot> roots;
  final Future<Result<List<GitHistoryCommit>, GitHistoryError>> Function(
    String root,
  )
  loadHistory;
  final Future<Result<List<GitHistoryFileChange>, GitHistoryError>> Function(
    String root,
    String commitHash,
  )
  loadFiles;
  final Future<void> Function(
    String root,
    String commitHash,
    GitHistoryFileChange change,
  )
  onOpenFileDiff;
  final int refreshToken;

  @override
  State<GitHistoryPanel> createState() => _GitHistoryPanelState();
}

class GitHistoryRoot {
  const GitHistoryRoot({required this.path, required this.name, this.branch});
  final String path;
  final String name;
  final String? branch;
}

class _GitHistoryPanelState extends State<GitHistoryPanel> {
  String? _root;
  List<GitHistoryCommit>? _commits;
  GitHistoryError? _error;
  final Map<String, List<GitHistoryFileChange>> _filesByHash = {};
  final Map<String, GitHistoryError> _fileErrorsByHash = {};
  GitHistoryCommit? _selectedCommit;
  String? _loadingFilesHash;
  Timer? _autoRefresh;
  var _loading = false;
  var _historyLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _root = widget.roots.firstOrNull?.path;
    _load();
    // `git log` e uma leitura local: atualiza commits feitos fora do Cockpit
    // sem depender de watcher de refs ou de conexao com a internet.
    _autoRefresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GitHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.roots.any((root) => root.path == _root)) {
      _root = widget.roots.firstOrNull?.path;
      _clearSelectedFiles();
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final root = _root;
    if (root == null) return;
    final generation = ++_historyLoadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.loadHistory(root);
    if (!mounted || generation != _historyLoadGeneration || root != _root) {
      return;
    }
    setState(() {
      _loading = false;
      result.fold((commits) => _commits = commits, (error) => _error = error);
    });
  }

  void _clearSelectedFiles() {
    _selectedCommit = null;
    _filesByHash.clear();
    _fileErrorsByHash.clear();
    _loadingFilesHash = null;
  }

  Future<void> _toggleCommit(GitHistoryCommit commit) async {
    final root = _root;
    if (root == null) return;
    if (_selectedCommit?.hash == commit.hash) {
      setState(() => _selectedCommit = null);
      return;
    }
    setState(() => _selectedCommit = commit);
    if (_filesByHash.containsKey(commit.hash) ||
        _fileErrorsByHash.containsKey(commit.hash)) {
      return;
    }
    setState(() => _loadingFilesHash = commit.hash);
    final result = await widget.loadFiles(root, commit.hash);
    if (!mounted || root != _root || _selectedCommit?.hash != commit.hash) {
      return;
    }
    setState(() {
      _loadingFilesHash = null;
      result.fold(
        (files) => _filesByHash[commit.hash] = files,
        (error) => _fileErrorsByHash[commit.hash] = error,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.fileTreePanel;
    final colors = context.colors;
    final roots = widget.roots;
    if (roots.isEmpty) return _EmptyHistory(message: tr.historyNoRepository);
    return Column(
      children: [
        if (roots.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: DropdownButtonFormField<String>(
              initialValue: _root,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr.historyRepository),
              items: [
                for (final root in roots)
                  DropdownMenuItem(value: root.path, child: Text(root.name)),
              ],
              onChanged: (root) {
                if (root == null || root == _root) return;
                setState(() {
                  _root = root;
                  _commits = null;
                  _clearSelectedFiles();
                });
                _load();
              },
            ),
          ),
        if (_root case final root?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 14,
                  color: colors.text3,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    roots
                            .where((candidate) => candidate.path == root)
                            .firstOrNull
                            ?.branch ??
                        '',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final tr = context.t.cockpit.fileTreePanel;
    if (_loading && _commits == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EmptyHistory(
        message: tr.historyLoadFailed,
        detail: _error!.detail,
      );
    }
    final commits = _commits;
    if (commits == null || commits.isEmpty) {
      return _EmptyHistory(message: tr.historyEmpty);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: commits.length,
      itemBuilder: (context, index) {
        final commit = commits[index];
        final selected = _selectedCommit?.hash == commit.hash;
        return _TimelineCommit(
          commit: commit,
          first: index == 0,
          last: index == commits.length - 1,
          selected: selected,
          files: _filesByHash[commit.hash],
          error: _fileErrorsByHash[commit.hash],
          loadingFiles: _loadingFilesHash == commit.hash,
          onTap: () => _toggleCommit(commit),
          onOpenFile: (change) =>
              widget.onOpenFileDiff(_root!, commit.hash, change),
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.message, this.detail});
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, color: context.colors.text3),
          const SizedBox(height: 8),
          Text(
            message,
            style: context.typo.label.copyWith(color: context.colors.text2),
          ),
          if (detail?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              style: context.typo.mono.copyWith(color: context.colors.text3),
            ),
          ],
        ],
      ),
    ),
  );
}

String? _relativeCommitDate(BuildContext context, DateTime? date) {
  if (date == null) return null;

  final localDate = date.toLocal();
  final now = DateTime.now();
  final elapsed = now.difference(localDate);
  final tr = context.t.cockpit.fileTreePanel;
  if (elapsed < const Duration(minutes: 1)) return tr.historyNow;
  if (elapsed < const Duration(hours: 1)) {
    return tr.historyMinutesAgo(count: elapsed.inMinutes);
  }
  if (elapsed < const Duration(days: 1)) {
    return tr.historyHoursAgo(count: elapsed.inHours);
  }

  final today = DateTime(now.year, now.month, now.day);
  final commitDay = DateTime(localDate.year, localDate.month, localDate.day);
  if (commitDay == today.subtract(const Duration(days: 1))) {
    return tr.historyYesterday;
  }
  if (elapsed.inDays == 1) return tr.historyDayAgo;
  if (elapsed < const Duration(days: 7)) {
    return tr.historyDaysAgo(count: elapsed.inDays);
  }
  return MaterialLocalizations.of(context).formatShortDate(localDate);
}

/// Uma timeline deliberadamente linear: relacoes de parentesco nao sao desenhadas
/// ate que exista um grafo real, em vez de sugerir ligacoes imprecisas.
class _TimelineCommit extends StatelessWidget {
  const _TimelineCommit({
    required this.commit,
    required this.first,
    required this.last,
    required this.selected,
    required this.files,
    required this.error,
    required this.loadingFiles,
    required this.onTap,
    required this.onOpenFile,
  });

  final GitHistoryCommit commit;
  final bool first;
  final bool last;
  final bool selected;
  final List<GitHistoryFileChange>? files;
  final GitHistoryError? error;
  final bool loadingFiles;
  final VoidCallback onTap;
  final ValueChanged<GitHistoryFileChange> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subject = commit.subject.trim();
    final relativeDate = _relativeCommitDate(context, commit.authoredAt);
    final metadata = <String>[?relativeDate, commit.author, commit.shortHash];
    return HoverTap(
      onTap: onTap,
      color: selected ? colors.accentSoft : Colors.transparent,
      hoverColor: selected ? colors.accentSoft : colors.panel3,
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 5),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimelineMarker(first: first, last: last, head: commit.isHead),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.isEmpty
                          ? context
                                .t
                                .cockpit
                                .fileTreePanel
                                .historyUntitledCommit
                          : subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.label.copyWith(
                        color: colors.text,
                        fontWeight: commit.isHead ? FontWeight.w700 : null,
                      ),
                    ),
                    if (commit.refs.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        runSpacing: 3,
                        children: [
                          for (final ref in commit.refs)
                            _RefChip(
                              label: ref,
                              head: ref == 'HEAD' || ref.startsWith('HEAD -> '),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      metadata.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.mono.copyWith(
                        fontSize: 10,
                        color: colors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (selected)
            _CommitFiles(
              files: files,
              error: error,
              loading: loadingFiles,
              onFileTap: onOpenFile,
            ),
        ],
      ),
    );
  }
}

class _CommitFiles extends StatelessWidget {
  const _CommitFiles({
    required this.files,
    required this.error,
    required this.loading,
    required this.onFileTap,
  });

  final List<GitHistoryFileChange>? files;
  final GitHistoryError? error;
  final bool loading;
  final ValueChanged<GitHistoryFileChange> onFileTap;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.fileTreePanel;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 23, top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel3,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.historyFiles,
                style: context.typo.label.copyWith(color: colors.text2),
              ),
              const SizedBox(height: 4),
              if (loading)
                const LinearProgressIndicator()
              else if (error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.historyFilesLoadFailed,
                      style: context.typo.mono.copyWith(
                        fontSize: 10,
                        color: colors.text3,
                      ),
                    ),
                    if (error!.detail?.isNotEmpty == true)
                      Text(
                        error!.detail!,
                        style: context.typo.mono.copyWith(
                          fontSize: 10,
                          color: colors.text3,
                        ),
                      ),
                  ],
                )
              else if (files?.isEmpty ?? true)
                Text(
                  tr.historyFilesEmpty,
                  style: context.typo.mono.copyWith(
                    fontSize: 10,
                    color: colors.text3,
                  ),
                )
              else
                for (final change in files!)
                  _HistoryFileChangeRow(
                    change: change,
                    onTap: () => onFileTap(change),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryFileChangeRow extends StatelessWidget {
  const _HistoryFileChangeRow({required this.change, required this.onTap});

  final GitHistoryFileChange change;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final changeColor = _historyChangeColor(colors, change.status);
    return HoverTap(
      onTap: onTap,
      hoverColor: colors.accentSoft,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.only(left: 4),
              width: 32,
              child: Text(
                change.status,
                style: context.typo.mono.copyWith(
                  fontSize: 10,
                  color: changeColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                change.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typo.mono.copyWith(
                  fontSize: 10,
                  color: changeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _historyChangeColor(AppColors colors, String status) {
  if (status.isEmpty) return colors.text3;
  return switch (status[0]) {
    'A' => colors.gitUntracked,
    'D' => colors.gitDeleted,
    'R' || 'C' => colors.accentText,
    _ => colors.text3,
  };
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({
    required this.first,
    required this.last,
    required this.head,
  });

  final bool first;
  final bool last;
  final bool head;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 16,
      height: 44,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: first ? 14 : 0,
            bottom: last ? 30 : 0,
            child: Container(width: 1, color: colors.border2),
          ),
          Positioned(
            top: 10,
            child: Container(
              key: const ValueKey('git-history-timeline-node'),
              width: head ? 10 : 8,
              height: head ? 10 : 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: head ? colors.accent : colors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip({required this.label, required this.head});
  final String label;
  final bool head;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: head ? context.colors.accentSoft : context.colors.panel3,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        label,
        style: context.typo.mono.copyWith(
          fontSize: 9,
          color: head ? context.colors.accentText : context.colors.text2,
        ),
      ),
    ),
  );
}
