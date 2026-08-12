import 'dart:io';

import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:path/path.dart' as p;

/// Guarda as **cópias** dos áudios custom escolhidos pelo usuário
/// (`<dataDir>/sounds/<evento>.<ext>`). Copiar em vez de referenciar o
/// original evita o som sumir em silêncio quando o usuário move/apaga o
/// arquivo — e a pasta de dados já é a que ele escolheu sincronizar.
class SoundLibrary {
  const SoundLibrary._();

  static Future<String> _dir() async {
    final dir = p.join(await StorageLocation.dataDir(), 'sounds');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// Copia [sourcePath] para o storage como o áudio custom de [event] e
  /// devolve o caminho da cópia. Remove antes qualquer cópia anterior do
  /// evento (a extensão pode ter mudado entre um pick e outro).
  static Future<String> import(SoundEvent event, String sourcePath) async {
    final dir = await _dir();
    await _removeCopies(dir, event);
    final dest = p.join(dir, '${event.name}${p.extension(sourcePath)}');
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// Apaga a cópia custom de [event] (volta ao som embarcado).
  static Future<void> clear(SoundEvent event) async {
    await _removeCopies(await _dir(), event);
  }

  static Future<void> _removeCopies(String dir, SoundEvent event) async {
    await for (final entity in Directory(dir).list(followLinks: false)) {
      if (entity is File &&
          p.basenameWithoutExtension(entity.path) == event.name) {
        try {
          await entity.delete();
        } catch (_) {
          // best-effort: arquivo travado é sobrescrito/ignorado depois
        }
      }
    }
  }
}
