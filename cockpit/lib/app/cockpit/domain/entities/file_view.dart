import 'dart:convert';

/// O conteúdo de um arquivo aberto no viewer, já classificado.
sealed class FileView {
  const FileView();
}

/// Markdown (.md/.mdx) — renderizado com gpt_markdown.
final class FileViewMarkdown extends FileView {
  const FileViewMarkdown(this.text, {this.encoding = utf8});
  final String text;

  /// Encoding original do arquivo no disco — preservado no save para evitar
  /// diffs artificiais em arquivos não-UTF-8 (ex.: Latin-1).
  final Encoding encoding;
}

/// Texto legível (.js/.json/…) — texto puro por enquanto (highlight depois).
final class FileViewText extends FileView {
  const FileViewText(this.text, {this.language, this.encoding = utf8});
  final String text;

  /// Dica de linguagem (extensão), para highlight futuro.
  final String? language;

  /// Encoding original do arquivo no disco — preservado no save para evitar
  /// diffs artificiais em arquivos não-UTF-8 (ex.: Latin-1).
  final Encoding encoding;
}

/// Imagem raster (PNG/JPEG/…) — só o caminho; o widget carrega.
final class FileViewImage extends FileView {
  const FileViewImage(this.path);
  final String path;
}

/// SVG — texto (XML) **e** imagem ao mesmo tempo: editável na fonte e
/// renderizável no preview. Carrega [text] (fonte) e [path] (origem do render).
final class FileViewSvg extends FileView {
  const FileViewSvg(this.path, this.text, {this.encoding = utf8});
  final String path;
  final String text;

  /// Encoding original do arquivo no disco — preservado no save para evitar
  /// diffs artificiais em arquivos não-UTF-8 (ex.: Latin-1).
  final Encoding encoding;
}

/// Áudio (mp3/wav/flac/…) — só o caminho; o player (media_kit) carrega. Plano 46.
final class FileViewAudio extends FileView {
  const FileViewAudio(this.path);
  final String path;
}

/// Vídeo (mp4/mov/mkv/…) — só o caminho; o player (media_kit) carrega. Plano 46.
final class FileViewVideo extends FileView {
  const FileViewVideo(this.path);
  final String path;
}

/// Binário/grande demais — **não abre**.
final class FileViewUnsupported extends FileView {
  const FileViewUnsupported();
}
