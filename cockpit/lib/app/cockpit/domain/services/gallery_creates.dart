import '../entities/gallery_template.dart';

/// Double-clicks share the pending creation until the document opens.
class GalleryCreates<T> {
  final _pending = <(String, GalleryTemplate), Future<T>>{};

  Future<T> run(
    String? project,
    GalleryTemplate template,
    Future<T> Function() create,
  ) {
    if (project == null ||
        (template != GalleryTemplate.board &&
            template != GalleryTemplate.orchestration)) {
      return create();
    }
    final key = (project, template);
    return _pending.putIfAbsent(
      key,
      () => Future.sync(create).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }
}
