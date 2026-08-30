import 'package:cockpit/app/core/utils/remote_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('host POSIX (comportamento preservado)', () {
    test('join usa barra', () {
      expect(remotePathJoin('/Users/jacob', 'projeto'), '/Users/jacob/projeto');
      expect(remotePathJoin('/', 'projeto'), '/projeto');
    });

    test('parent sobe um nível e para na raiz', () {
      expect(remotePathParent('/Users/jacob/projeto'), '/Users/jacob');
      expect(remotePathParent('/Users'), '/');
      expect(remotePathParent('/'), '/');
    });

    test('raiz é /', () {
      expect(isRemotePathRoot('/'), isTrue);
      expect(isRemotePathRoot('/Users'), isFalse);
    });
  });

  group('host Windows', () {
    test('join usa barra invertida', () {
      // Era aqui que nascia o `C:\Users\jacob/pasta` do relato.
      expect(
        remotePathJoin(r'C:\Users\jacob', 'projeto'),
        r'C:\Users\jacob\projeto',
      );
      expect(remotePathJoin(r'C:\', 'projeto'), r'C:\projeto');
    });

    test('parent sobe um nível — não despenca na raiz', () {
      // O bug: `lastIndexOf('/')` num caminho Windows dava -1, então QUALQUER
      // "subir uma pasta" devolvia `/` e a hierarquia inteira se perdia.
      expect(remotePathParent(r'C:\Users\jacob\projeto'), r'C:\Users\jacob');
      expect(remotePathParent(r'C:\Users\jacob'), r'C:\Users');
      expect(remotePathParent(r'C:\Users'), r'C:\');
    });

    test('para na raiz do drive, não em /', () {
      expect(remotePathParent(r'C:\'), r'C:\');
      expect(isRemotePathRoot(r'C:\'), isTrue);
      expect(isRemotePathRoot(r'C:'), isTrue);
      expect(isRemotePathRoot(r'C:\Users'), isFalse);
    });

    test('outro drive preserva a letra', () {
      expect(remotePathParent(r'D:\dev\repo'), r'D:\dev');
      expect(remotePathRoot(r'D:\dev'), r'D:\');
    });

    test('caminho MISTO ainda navega', () {
      // Compatibilidade: pins e layouts salvos por versões anteriores carregam
      // separador misto. Recusá-los prenderia o usuário na pasta.
      expect(remotePathParent(r'C:\Users\jacob/projeto'), r'C:\Users\jacob');
      expect(
        remotePathJoin(r'C:\Users\jacob/projeto', 'sub'),
        r'C:\Users\jacob/projeto\sub',
      );
    });
  });

  group('basename (nome do pin)', () {
    test('host Windows usa o último componente, não o caminho todo', () {
      // Procurar só por `/` fazia o pin aparecer como o caminho inteiro.
      expect(remotePathBasename(r'C:\Users\jacob\projeto'), 'projeto');
      expect(remotePathBasename(r'C:\Users\jacob\projeto\'), 'projeto');
    });

    test('host POSIX segue igual', () {
      expect(remotePathBasename('/Users/jacob/projeto'), 'projeto');
      expect(remotePathBasename('/Users/jacob/projeto/'), 'projeto');
    });

    test('caminho misto também', () {
      expect(remotePathBasename(r'C:\Users\jacob/projeto'), 'projeto');
    });
  });

  test('família vem do caminho, nunca do cliente', () {
    // O picker navega o filesystem do HOST: um iPad abrindo um host Windows
    // precisa de `\`, e um cliente Windows abrindo um host Linux precisa de `/`.
    expect(isWindowsRemotePath(r'C:\Users'), isTrue);
    expect(isWindowsRemotePath('/Users'), isFalse);
    expect(remotePathSeparator('/home/j'), '/');
    expect(remotePathSeparator(r'C:\Users'), r'\');
  });
}
