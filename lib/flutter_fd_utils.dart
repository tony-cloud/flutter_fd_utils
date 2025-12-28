export 'src/fd_report_dialog.dart';
export 'src/fd_info.dart';
export 'src/nofile_limit.dart';
export 'src/nofile_limit_result.dart';

import 'flutter_fd_utils_platform_interface.dart';
import 'src/fd_info.dart';
import 'src/nofile_limit.dart';
import 'src/nofile_limit_result.dart';

/// A thin Dart wrapper around the platform implementation.
class FlutterFdUtils {
  const FlutterFdUtils();

  /// Returns a human-readable report of the current process file descriptors.
  Future<String> getFdReport() {
    return FlutterFdUtilsPlatform.instance.getFdReport();
  }

  /// Returns the current process RLIMIT_NOFILE limits.
  Future<NofileLimit> getNofileLimit() {
    return FlutterFdUtilsPlatform.instance.getNofileLimit();
  }

  /// Returns the current process soft RLIMIT_NOFILE limit.
  Future<int> getNofileSoftLimit() {
    return FlutterFdUtilsPlatform.instance.getNofileSoftLimit();
  }

  /// Returns the current process hard RLIMIT_NOFILE limit.
  Future<int> getNofileHardLimit() {
    return FlutterFdUtilsPlatform.instance.getNofileHardLimit();
  }

  /// Returns a structured list of current process file descriptors.
  Future<List<FdInfo>> getFdList() {
    return FlutterFdUtilsPlatform.instance.getFdList();
  }

  /// Attempts to update the soft RLIMIT_NOFILE (nofile) limit.
  ///
  /// If [clampToHardLimit] is true, the requested value will be clamped to the
  /// current hard limit to reduce failures.
  Future<NofileLimitResult> setNofileSoftLimit(
    int softLimit, {
    bool clampToHardLimit = true,
  }) {
    return FlutterFdUtilsPlatform.instance.setNofileSoftLimit(
      softLimit,
      clampToHardLimit: clampToHardLimit,
    );
  }
}
