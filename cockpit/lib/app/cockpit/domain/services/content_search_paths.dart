/// Shared by the content scan and its invalidation watcher.
const contentSearchIgnoredDirectories = <String>{
  'node_modules',
  'build',
  '.dart_tool',
  '.next',
  'dist',
  'out',
  'Pods',
  'DerivedData',
  '.gradle',
  '.venv',
  'venv',
  '__pycache__',
  'target',
  'vendor',
  'coverage',
};

bool contentSearchIncludesDirectory(String name) =>
    !name.startsWith('.') && !contentSearchIgnoredDirectories.contains(name);
