import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:cockpit/app/cockpit/ui/remote/remote_host_error_message.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/remote_path.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Sessão de conexão resolvida pelo picker: o [FileService] do host já
/// conectado + o caminho inicial (HOME remota, ou `/` de fallback).
typedef RemoteFolderConnect =
    Future<({FileService service, String initialPath})> Function();

/// Navega o filesystem REMOTO (via [FileService] do host) e devolve o caminho
/// da pasta escolhida — o "Add remote workspace" do plano 58: fixa uma pasta
/// específica do host, em vez de abrir sempre na HOME.
///
/// O dialog abre **imediatamente** em loading e faz a conexão SSH lá dentro
/// (via [connect]) — em hosts lentos, a tela some da experiência de "nada
/// acontece por segundos" (plano 60, Wave A). Erro de conexão é mostrado no
/// próprio dialog, não num info dialog à parte.
Future<String?> showRemoteFolderPicker(
  BuildContext context, {
  required RemoteFolderConnect connect,
  required String hostName,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) =>
        _RemoteFolderPicker(connect: connect, hostName: hostName),
  );
}

class _RemoteFolderPicker extends StatefulWidget {
  const _RemoteFolderPicker({required this.connect, required this.hostName});

  final RemoteFolderConnect connect;
  final String hostName;

  @override
  State<_RemoteFolderPicker> createState() => _RemoteFolderPickerState();
}

class _RemoteFolderPickerState extends State<_RemoteFolderPicker> {
  FileService? _service;
  String _path = '';
  List<FileEntry>? _entries;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  /// Conecta o host (túnel SSH + HOME remota) com o dialog já visível em
  /// loading; a lista carrega assim que a conexão fecha. Erro tipado vira
  /// frase na borda da UI (mesmo padrão do call-site antigo).
  Future<void> _connect() async {
    try {
      final session = await widget.connect();
      if (!mounted) return;
      _service = session.service;
      await _load(session.initialPath);
    } on RemoteHostException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = remoteHostErrorMessage(context, e, host: widget.hostName);
        _loading = false;
      });
    }
  }

  Future<void> _load(String path) async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await service.list(path);
      // Só pastas visíveis (o workspace é uma pasta).
      final dirs = all
          .where((e) => e.isDirectory && !e.name.startsWith('.'))
          .toList();
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = dirs;
        _loading = false;
      });
    } on FileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.detail ?? e.kind.name;
        _loading = false;
      });
    }
  }

  // Caminhos do HOST (que pode ser de outra família que a do cliente):
  // ver `core/utils/remote_path.dart`. Era tudo POSIX cru aqui — em
  // `C:\\Users\\jacob` o `lastIndexOf('/')` dava -1, então subir uma
  // pasta caía na raiz e a hierarquia se perdia; o join produzia separador
  // misto (`C:\\Users\\jacob/pasta`).
  bool get _atRoot => isRemotePathRoot(_path);
  String get _parent => remotePathParent(_path);
  String _join(String dir, String name) => remotePathJoin(dir, name);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.cockpit.remoteHost;
    // Responsivo: no desktop fica em 460x380; num iPhone encolhe pra caber. O
    // AlertDialog do shadcn empilha [título+conteúdo | ações] numa Column — se o
    // conteúdo for alto demais, a Column estoura a altura máxima e as ações são
    // pintadas POR CIMA do fim da lista. Por isso reservamos ~240px (título +
    // ações + padding do diálogo) da altura da tela antes de dimensionar a lista
    // (plano 60).
    final media = MediaQuery.sizeOf(context);
    final width = (media.width - 80).clamp(280.0, 460.0);
    final height = (media.height - 240).clamp(160.0, 380.0);
    return AlertDialog(
      title: Text(
        tr.pickFolderTitle(host: widget.hostName),
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caminho atual + subir um nível.
            Row(
              children: [
                IconButton.ghost(
                  density: ButtonDensity.compact,
                  onPressed: _atRoot ? null : () => _load(_parent),
                  icon: const Icon(Icons.arrow_upward, size: 15),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _path,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.mono.copyWith(
                      fontSize: 12,
                      color: colors.text2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.panel,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: colors.border),
                ),
                child: _body(colors),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(
          // Abre nesta pasta (desabilitado enquanto conecta/carrega ou se a
          // conexão falhou).
          onPressed: _loading || _service == null
              ? null
              : () => Navigator.of(context).pop(_path),
          child: Text(tr.openHere),
        ),
      ],
    );
  }

  Widget _body(AppColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: context.typo.label.copyWith(color: colors.error),
          ),
        ),
      );
    }
    final entries = _entries ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Text(
          context.t.cockpit.remoteHost.emptyFolder,
          style: context.typo.label.copyWith(color: colors.text2),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return HoverTap(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          onTap: () => _load(_join(_path, e.name)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 15, color: colors.text2),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.body.copyWith(
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 15, color: colors.text2),
              ],
            ),
          ),
        );
      },
    );
  }
}
