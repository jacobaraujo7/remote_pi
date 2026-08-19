import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Lê e classifica um arquivo para o viewer (markdown / texto / imagem /
/// não-suportado). Contrato no domínio; impl (dart:io) em `data/filesystem/`.
abstract class FileReader {
  Future<FileView> read(String path);

  /// Grava [content] em [path] com o [encoding] informado, sobrescrevendo.
  /// Retorna `true` no sucesso, `false` se o IO falhar (sem permissão, disco
  /// cheio, path sumiu). Não há merge nem trava: escrita simultânea do agente
  /// é last-write-wins (escopo MVP).
  ///
  /// Passe o [encoding] da [FileView] original para preservar o encoding do
  /// arquivo no disco (evita diffs artificiais em arquivos não-UTF-8).
  /// Arquivos novos (scratch) usam [utf8] como padrão.
  Future<bool> write(String path, String content, {Encoding encoding = utf8});

  /// Emite (`void`) sempre que [path] muda no disco (modify/delete), pra o viewer
  /// reler o conteúdo ao vivo. Stream de longa duração — o consumidor cancela ao
  /// fechar a aba. Se o watch falhar, devolve um stream vazio (sem live-reload,
  /// sem crash).
  Stream<void> watch(String path);
}
