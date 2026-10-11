import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'template "panel" da Galeria == cli/skills/cockpit-design/templates/dashboard.panel',
    () {
      final file = File('cli/skills/cockpit-design/templates/dashboard.panel');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'rode o teste da raiz de cockpit/',
      );
      expect(GalleryTemplate.panel.content, file.readAsStringSync());
    },
  );
}
