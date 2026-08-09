import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/theme_codec.dart';
import 'package:cockpit/app/core/ui/themes/theme_registry.dart';
import 'package:cockpit/app/core/ui/themes/theme_spec.dart';
import 'package:path/path.dart' as p;

/// O que pode dar errado ao importar/exportar um tema. Tipo, não frase — a
/// tradução mora em `core/ui/theme_store_error_message.dart`.
class ThemeStoreError implements Exception {
  const ThemeStoreError(this.kind, {this.detail, this.parse});

  final ThemeStoreErrorKind kind;

  /// Texto cru do SO (mensagem de IO / JSON malformado). Não se traduz.
  final String? detail;

  /// Preenchido quando [kind] é [ThemeStoreErrorKind.invalidTheme]: diz qual
  /// campo do arquivo quebrou.
  final ThemeParseError? parse;

  @override
  String toString() => 'ThemeStoreError($kind, $detail, $parse)';
}

enum ThemeStoreErrorKind {
  /// Não deu para ler/escrever o arquivo (permissão, disco, caminho sumiu).
  io,

  /// O conteúdo não é JSON válido.
  malformedJson,

  /// É JSON, mas não é um tema válido (ver [ThemeStoreError.parse]).
  invalidTheme,

  /// O id do tema colide com um built-in — sobrescrever esconderia um tema que
  /// o app precisa ter.
  reservedId,
}

/// Guarda os temas importados pelo usuário como arquivos JSON soltos numa
/// pasta, um por tema.
///
/// Arquivos soltos (e não uma chave no JSON de preferências) porque é isso que
/// torna tema uma coisa **compartilhável**: instalar = copiar um arquivo pra
/// pasta, e a pasta pode ser aberta no Finder, versionada, sincronizada. É
/// também o formato que um pacote de plugin traria dentro.
class ThemeStore {
  const ThemeStore();

  /// `<dataDir>/themes`. Fica ao lado do `state/` (mesmo destino do "Storage"
  /// escolhido nas Configurações), então trocar a pasta de dados leva os temas
  /// junto.
  static Future<Directory> themesDir() async {
    final dir = Directory(p.join(await StorageLocation.dataDir(), 'themes'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Carrega todos os temas da pasta. Arquivo inválido é **pulado**, não fatal:
  /// um tema quebrado não pode impedir o app de abrir.
  Future<List<CockpitThemeSpec>> loadAll() async {
    final Directory dir;
    try {
      dir = await themesDir();
    } on FileSystemException {
      return const [];
    } on MissingPluginException {
      // Sem path_provider (teste de unidade, headless): não há pasta de dados,
      // então não há tema custom — só os built-in. Não é erro.
      return const [];
    } on FlutterError {
      // Mesma situação, pela outra porta: binding do Flutter não inicializado,
      // que é como o path_provider falha num teste de unidade puro.
      return const [];
    }
    final themes = <CockpitThemeSpec>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || p.extension(entity.path) != '.json') continue;
      final result = _parseFile(entity);
      if (result case Success(:final value)) themes.add(value);
    }
    themes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return themes;
  }

  /// Copia [source] para a pasta de temas e devolve o tema já parseado.
  ///
  /// Valida **antes** de copiar: arquivo inválido nunca chega à pasta, então o
  /// [loadAll] do próximo boot não precisa lidar com lixo que nós mesmos
  /// gravamos.
  Future<Result<CockpitThemeSpec, ThemeStoreError>> import(File source) async {
    final parsed = _parseFile(source);
    if (parsed case Failure(:final error)) return Failure(error);
    final spec = (parsed as Success<CockpitThemeSpec, ThemeStoreError>).value;

    if (builtInThemeById(spec.id) != null) {
      return const Failure(ThemeStoreError(ThemeStoreErrorKind.reservedId));
    }
    try {
      final dir = await themesDir();
      // O nome do arquivo vem do id, não do arquivo de origem: reimportar uma
      // versão nova do mesmo tema substitui em vez de duplicar.
      final target = File(p.join(dir.path, '${_fileSafe(spec.id)}.json'));
      await target.writeAsString(_encode(spec));
      return Success(spec);
    } on FileSystemException catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.io, detail: e.message),
      );
    }
  }

  /// Grava [spec] em [targetPath] (o "Export" das Configurações).
  Future<Result<void, ThemeStoreError>> export(
    CockpitThemeSpec spec,
    String targetPath,
  ) async {
    try {
      await File(targetPath).writeAsString(_encode(spec));
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.io, detail: e.message),
      );
    }
  }

  /// Remove um tema importado. Built-in não é removível (nem chega aqui: a UI
  /// só oferece o botão para tema custom).
  Future<Result<void, ThemeStoreError>> delete(String id) async {
    try {
      final dir = await themesDir();
      final file = File(p.join(dir.path, '${_fileSafe(id)}.json'));
      if (file.existsSync()) await file.delete();
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.io, detail: e.message),
      );
    }
  }

  Result<CockpitThemeSpec, ThemeStoreError> _parseFile(File file) {
    final String raw;
    try {
      raw = file.readAsStringSync();
    } on FileSystemException catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.io, detail: e.message),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.malformedJson, detail: e.message),
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const Failure(
        ThemeStoreError(
          ThemeStoreErrorKind.invalidTheme,
          parse: ThemeParseError(ThemeParseErrorKind.notAnObject, path: r'$'),
        ),
      );
    }

    try {
      return Success(
        CockpitThemeSpec.fromJson(
          decoded,
          resolveBase: builtInThemeById,
          fallbackBase: cockpitDefaultTheme,
        ),
      );
    } on ThemeParseError catch (e) {
      return Failure(
        ThemeStoreError(ThemeStoreErrorKind.invalidTheme, parse: e),
      );
    }
  }

  String _encode(CockpitThemeSpec spec) =>
      const JsonEncoder.withIndent('  ').convert(spec.toJson());

  /// Id → nome de arquivo. Ids são namespaced com ponto (`acme.midnight`), o
  /// que já é seguro; o resto vira `_` para não depender da higiene de quem
  /// escreveu o tema.
  String _fileSafe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
