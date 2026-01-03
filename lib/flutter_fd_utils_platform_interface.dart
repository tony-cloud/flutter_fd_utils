import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_fd_utils_method_channel.dart';
import 'src/fd_info.dart';
import 'src/nofile_limit.dart';
import 'src/nofile_limit_result.dart';

abstract class FlutterFdUtilsPlatform extends PlatformInterface {
  /// Constructs a FlutterFdUtilsPlatform.
  FlutterFdUtilsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFdUtilsPlatform _instance = MethodChannelFlutterFdUtils();

  /// The default instance of [FlutterFdUtilsPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterFdUtils].
  static FlutterFdUtilsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFdUtilsPlatform] when
  /// they register themselves.
  static set instance(FlutterFdUtilsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns a human-readable report of the current process file descriptors.
  ///
  /// On unsupported platforms this may throw a [PlatformException] / [MissingPluginException].
  Future<String> getFdReport() {
    throw UnimplementedError('getFdReport() has not been implemented.');
  }

  /// Returns the current process RLIMIT_NOFILE limits.
  Future<NofileLimit> getNofileLimit() {
    throw UnimplementedError('getNofileLimit() has not been implemented.');
  }

  /// Returns the current process soft RLIMIT_NOFILE limit.
  Future<int> getNofileSoftLimit() {
    throw UnimplementedError('getNofileSoftLimit() has not been implemented.');
  }

  /// Returns the current process hard RLIMIT_NOFILE limit.
  Future<int> getNofileHardLimit() {
    throw UnimplementedError('getNofileHardLimit() has not been implemented.');
  }

  /// Returns a structured list of current process file descriptors.
  Future<List<FdInfo>> getFdList() {
    throw UnimplementedError('getFdList() has not been implemented.');
  }

  /// Attempts to update the soft RLIMIT_NOFILE (nofile) limit.
  Future<NofileLimitResult> setNofileSoftLimit(int softLimit, {bool clampToHardLimit = true}) {
    throw UnimplementedError('setNofileSoftLimit() has not been implemented.');
  }
}
