import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Classifica o arquivo por extensão + conteúdo:
/// - vídeo → [FileViewVideo] (só o caminho);
/// - áudio → [FileViewAudio] (só o caminho);
/// - imagem → [FileViewImage] (só o caminho);
/// - markdown → [FileViewMarkdown];
/// - qualquer outra coisa que caiba na memória (≤ 2MB) → [FileViewText].
///
/// **Não** barramos por extensão nem por conteúdo binário: qualquer tipo
/// desconhecido (inclusive sem extensão, tipo `.zprofile`/`Makefile`, e até
/// binário) abre como texto. Os bytes viram UTF-8 tolerante (`allowMalformed`),
/// então bytes inválidos aparecem como U+FFFD — pode "sujar" a tela, mas o
/// arquivo abre. O único limite é o tamanho (proteção de memória/UI):
/// - grande demais (> 2MB) ou não é um arquivo → [FileViewUnsupported].
class FileReaderImpl implements FileReader {
  const FileReaderImpl();

  static const int _maxTextBytes = 2 * 1024 * 1024;
  static const Set<String> _markdown = {'md', 'mdx', 'markdown'};
  static const Set<String> _image = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'ico',
  };
  static const Set<String> _video = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'wmv',
    'flv',
  };
  static const Set<String> _audio = {
    'mp3',
    'wav',
    'aac',
    'm4a',
    'flac',
    'ogg',
    'opus',
  };

  @override
  Future<FileView> read(String path) async {
    final ext = _ext(path);
    // A/V e imagem só passam o caminho — o player/widget carrega (sem ler bytes,
    // sem limite de tamanho). Decisão cedo, antes de qualquer leitura de disco.
    if (_video.contains(ext)) return FileViewVideo(path);
    if (_audio.contains(ext)) return FileViewAudio(path);
    if (_image.contains(ext)) return FileViewImage(path);

    final file = File(path);
    if (!await file.exists()) return const FileViewUnsupported();
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size > _maxTextBytes) {
      return const FileViewUnsupported();
    }

    final bytes = await file.readAsBytes();
    // Banco sqlite (magic header) nunca é texto útil — não abre como viewer;
    // ele aparece como conexão "detected" no painel Database (plano 51).
    if (_isSqlite(bytes)) return const FileViewUnsupported();

    // Detecta o encoding real: tenta UTF-8 estrito primeiro; se falhar (bytes
    // inválidos em UTF-8), usa Latin-1 — que mapeia cada byte 1:1 a um
    // codepoint Unicode, preservando todos os bytes sem perda.
    //
    // Não usamos allowMalformed: isso convertiria bytes inválidos para U+FFFD
    // (3 bytes em UTF-8), e salvar de volta produziria um arquivo diferente
    // mesmo sem nenhuma edição (diff artificial no Git).
    final (text, encoding) = _decodeBytes(bytes);

    if (_markdown.contains(ext)) {
      return FileViewMarkdown(text, encoding: encoding);
    }
    // SVG é texto (XML) que também renderiza — fonte editável + preview.
    if (ext == 'svg') return FileViewSvg(path, text, encoding: encoding);
    return FileViewText(text, language: ext.isEmpty ? null : ext, encoding: encoding);
  }

  /// Decodifica [bytes] detectando o encoding:
  /// - UTF-8 estrito → retorna `(text, utf8)`
  /// - Falhou (bytes inválidos) → Latin-1 → retorna `(text, latin1)`
  ///
  /// Latin-1 é escolhido porque mapeia cada byte `b` ao codepoint `b`
  /// (identidade para 0–255), garantindo roundtrip perfeito ao gravar de volta.
  static (String, Encoding) _decodeBytes(List<int> bytes) {
    try {
      return (utf8.decode(bytes), utf8);
    } on FormatException {
      return (latin1.decode(bytes), latin1);
    }
  }

  @override
  Future<bool> write(String path, String content, {Encoding encoding = utf8}) async {
    try {
      // Tenta gravar com o encoding original do arquivo.
      // Se o conteúdo tiver caracteres fora do alcance do encoding (ex.:
      // usuário digitou emojis num arquivo Latin-1), faz upgrade para UTF-8.
      await File(path).writeAsString(content, encoding: encoding);
      return true;
    } on ArgumentError {
      // Encoding (ex.: Latin-1) não suporta todos os codepoints do conteúdo
      // editado — faz upgrade silencioso para UTF-8.
      try {
        await File(path).writeAsString(content);
        return true;
      } on FileSystemException {
        return false;
      }
    } on FileSystemException {
      return false;
    }
  }

  @override
  Stream<void> watch(String path) {
    try {
      // FSEvents no macOS. Erros do stream (arquivo trocado por rename, etc.)
      // viram fim silencioso — o consumidor (VM) trata via onError.
      return File(path)
          .watch(events: FileSystemEvent.modify | FileSystemEvent.delete)
          .map((_) {});
    } catch (_) {
      return const Stream<void>.empty();
    }
  }

  static const _sqliteMagic = 'SQLite format 3';

  static bool _isSqlite(List<int> bytes) =>
      bytes.length >= _sqliteMagic.length &&
      String.fromCharCodes(bytes.take(_sqliteMagic.length)) == _sqliteMagic;

  String _ext(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}
