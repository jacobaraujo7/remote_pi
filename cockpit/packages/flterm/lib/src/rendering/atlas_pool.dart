import 'atlas/atlas.dart';

/// Keeps a shared [Atlas] alive until [release] is called.
class AtlasLease {
  final AtlasPool _owner;
  final AtlasConfig config;
  final _CachedAtlas _entry;
  var _released = false;

  AtlasLease._(this._owner, this.config, this._entry);

  Atlas get atlas => _entry.atlas;

  /// Releases this lease.
  ///
  /// Repeated calls have no effect.
  void release() {
    if (_released) return;
    _released = true;
    _owner._releaseAtlas(config, _entry);
  }
}

/// Owns render resources that can be shared by compatible terminal views.
///
/// Render boxes derive an [AtlasConfig] from their current
/// theme/metrics/DPR and use it directly as the sharing key.
///
/// This type is internal; public sharing is exposed through `TerminalScope`.
class AtlasPool {
  final _atlases = <AtlasConfig, _CachedAtlas>{};

  /// Acquires the atlas for [config], creating it when necessary.
  ///
  /// The caller must release the returned lease when it no longer uses the
  /// atlas.
  AtlasLease acquireAtlas(AtlasConfig config) {
    final entry = _atlases.putIfAbsent(
      config,
      () => _CachedAtlas(Atlas(config)),
    );
    entry.references++;
    return AtlasLease._(this, config, entry);
  }

  /// Disposes every pooled atlas, including atlases with outstanding leases.
  void dispose() {
    for (final entry in _atlases.values) {
      entry.atlas.dispose();
    }
    _atlases.clear();
  }

  void _releaseAtlas(AtlasConfig config, _CachedAtlas releasedEntry) {
    final entry = _atlases[config];
    if (entry == null) return;
    if (!identical(entry, releasedEntry)) return;

    entry.references--;
    if (entry.references > 0) return;

    _atlases.remove(config);
    entry.atlas.dispose();
  }
}

class _CachedAtlas {
  final Atlas atlas;
  var references = 0;

  _CachedAtlas(this.atlas);
}
