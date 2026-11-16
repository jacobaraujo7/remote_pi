import 'dart:async';
import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/cockpit/domain/services/gallery_creates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rapid Board activations share only the pending workspace creation',
    () async {
      final creates = GalleryCreates<int>();
      final first = Completer<int>();
      var attempts = 0;
      Future<int> create() {
        attempts++;
        return first.future;
      }

      final pending = creates.run('a', GalleryTemplate.board, create);
      expect(creates.run('a', GalleryTemplate.board, create), same(pending));
      expect(await creates.run('b', GalleryTemplate.board, () async => 2), 2);
      expect(
        await creates.run('a', GalleryTemplate.orchestration, () async => 3),
        3,
      );
      expect(attempts, 1);
      first.completeError(StateError('write failed'));
      await expectLater(pending, throwsStateError);
      expect(await creates.run('a', GalleryTemplate.board, () async => 4), 4);
      expect(await creates.run('a', GalleryTemplate.board, () async => 5), 5);
    },
  );
}
