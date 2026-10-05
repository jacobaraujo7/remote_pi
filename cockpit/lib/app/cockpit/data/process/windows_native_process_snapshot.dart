import 'dart:ffi';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:ffi/ffi.dart';

// PROCESSENTRY32W from tlhelp32.h. The kernel supplies the executable name,
// PID and parent PID without starting PowerShell or querying WMI.
final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int cntUsage;

  @Uint32()
  external int th32ProcessID;

  @IntPtr()
  external int th32DefaultHeapID;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int cntThreads;

  @Uint32()
  external int th32ParentProcessID;

  @Int32()
  external int pcPriClassBase;

  @Uint32()
  external int dwFlags;

  @Array(260)
  external Array<Uint16> szExeFile;
}

typedef _CreateSnapshotNative = IntPtr Function(Uint32, Uint32);
typedef _CreateSnapshotDart = int Function(int, int);
typedef _ProcessFirstNative = Int32 Function(IntPtr, Pointer<_ProcessEntry32W>);
typedef _ProcessFirstDart = int Function(int, Pointer<_ProcessEntry32W>);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

/// Snapshot of the Windows process tree. Only process names are available here;
/// command lines for possible harness descendants are fetched separately.
List<ProcessSnapshot> windowsNativeProcessSnapshot() {
  if (!Platform.isWindows) return const [];
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final create = kernel32
      .lookupFunction<_CreateSnapshotNative, _CreateSnapshotDart>(
        'CreateToolhelp32Snapshot',
      );
  final first = kernel32.lookupFunction<_ProcessFirstNative, _ProcessFirstDart>(
    'Process32FirstW',
  );
  final next = kernel32.lookupFunction<_ProcessFirstNative, _ProcessFirstDart>(
    'Process32NextW',
  );
  final close = kernel32.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
    'CloseHandle',
  );

  const th32csSnapProcess = 0x00000002;
  final handle = create(th32csSnapProcess, 0);
  if (handle == -1 || handle == 0) return const [];
  final entry = calloc<_ProcessEntry32W>();
  try {
    entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
    final snapshots = <ProcessSnapshot>[];
    var found = first(handle, entry);
    while (found != 0) {
      final name = _processName(entry.ref.szExeFile);
      snapshots.add(
        ProcessSnapshot(
          pid: entry.ref.th32ProcessID,
          ppid: entry.ref.th32ParentProcessID,
          executable: name,
          argv: name.isEmpty ? const [] : [name],
        ),
      );
      found = next(handle, entry);
    }
    return snapshots;
  } finally {
    calloc.free(entry);
    close(handle);
  }
}

String _processName(Array<Uint16> buffer) {
  final units = <int>[];
  for (var i = 0; i < 260; i++) {
    final unit = buffer[i];
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}
