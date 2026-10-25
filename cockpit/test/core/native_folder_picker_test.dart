import 'package:cockpit/app/core/utils/native_folder_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lastPathLine descarta aviso de driver antes do caminho', () {
    expect(
      NativeFolderPicker.lastPathLine(
        'Invalid value (0) for DRI_PRIME. Should be > 0\n'
        '/home/u/projetos/Coachkit\n',
      ),
      '/home/u/projetos/Coachkit',
    );
    expect(NativeFolderPicker.lastPathLine('/a/b'), '/a/b');
  });
}
