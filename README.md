# flutter_fd_utils

An iOS-only Flutter plugin that returns a human-readable report of the current process file descriptors (FDs).

This is primarily intended for debugging issues like "too many open files".

## Features

- `getFdReport()`: returns a formatted text report.
- `getNofileLimit()` / `getNofileSoftLimit()` / `getNofileHardLimit()`: read current `RLIMIT_NOFILE`.
- `getFdList()`: returns a structured list of file descriptors (sockets, vnodes, flags, paths, etc.).
- `setNofileSoftLimit()`: attempts to update the process soft `RLIMIT_NOFILE`.
- `FdReportDialog`: a reusable Material dialog that auto-refreshes and supports copying to clipboard.

## Platform support

- iOS: ✅
- Android / desktop / web: not implemented (calls may throw `MissingPluginException`).

## Usage

```dart
import 'package:flutter_fd_utils/flutter_fd_utils.dart';

final api = FlutterFdUtils();
final report = await api.getFdReport();
```

Update the soft nofile limit:

```dart
final api = FlutterFdUtils();
final result = await api.setNofileSoftLimit(8192);
if (!result.success) {
	// errno + strerror from iOS
	print('Failed: ${result.errno} ${result.errorMessage}');
}
```

To show the built-in dialog:

```dart
await FdReportDialog.show(context);
```

## Notes

The iOS implementation uses libproc APIs (`proc_pidinfo` / `proc_pidfdpath`) when available.

