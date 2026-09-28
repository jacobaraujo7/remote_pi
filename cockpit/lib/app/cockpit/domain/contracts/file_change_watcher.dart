/// Avisa quando um arquivo (ou o conteúdo de uma pasta) muda no disco, pra os
/// viewers relerem ao vivo: aba de arquivo, janela de documento e caderno
/// (`.notebook`). É o **único** caminho de live-reload do app; ninguém deve
/// chamar `File.watch`/`Directory.watch` direto pra isso.
///
/// O contrato existe porque "vigiar um arquivo" tem armadilhas que cada
/// consumidor errava sozinho:
/// - agentes (Claude Code) e muitos editores gravam **por rename atômico**
///   (`x.tmp` → `x`): o arquivo original some e o `File.watch` encerra o
///   stream, então só a primeira edição aparecia;
/// - o stream do SO pode morrer ou coalescer eventos, e a janela oculta pode
///   perder a vez.
///
/// Os streams são de longa duração, não terminam sozinhos e nunca emitem erro:
/// o consumidor cancela ao fechar a vista.
abstract class FileChangeWatcher {
  /// Emite quando [path] muda: gravado no lugar, substituído por rename,
  /// apagado ou recriado. Rajadas (um save gera vários eventos) chegam como
  /// um aviso só.
  Stream<void> watchFile(String path);

  /// Emite quando o conteúdo **imediato** da pasta [path] muda (arquivo
  /// criado, apagado, renomeado ou gravado). Não desce em subpastas.
  Stream<void> watchFolder(String path);
}
