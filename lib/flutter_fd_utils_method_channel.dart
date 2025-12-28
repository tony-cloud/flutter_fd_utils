import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_fd_utils_platform_interface.dart';
import 'src/fd_info.dart';
import 'src/nofile_limit.dart';
import 'src/nofile_limit_result.dart';

/// An implementation of [FlutterFdUtilsPlatform] that uses method channels.
class MethodChannelFlutterFdUtils extends FlutterFdUtilsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_fd_utils');

  @override
  Future<String> getFdReport() async {
    final Object? report = await methodChannel.invokeMethod('getFdReport');
    return report?.toString() ?? '';
  }

  @override
  Future<NofileLimit> getNofileLimit() async {
    final Object? raw = await methodChannel.invokeMethod('getNofileLimit');
    if (raw is Map) {
      return NofileLimit.fromMap(raw.cast<Object?, Object?>());
    }
    return const NofileLimit(soft: 0, hard: 0);
  }

  @override
  Future<int> getNofileSoftLimit() async {
    final Object? raw = await methodChannel.invokeMethod('getNofileSoftLimit');
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  @override
  Future<int> getNofileHardLimit() async {
    final Object? raw = await methodChannel.invokeMethod('getNofileHardLimit');
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  @override
  Future<List<FdInfo>> getFdList() async {
    final Object? raw = await methodChannel.invokeMethod('getFdList');
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => FdInfo.fromMap(m.cast<Object?, Object?>()))
          .toList(growable: false);
    }
    return const <FdInfo>[];
  }

  @override
  Future<NofileLimitResult> setNofileSoftLimit(
    int softLimit, {
    bool clampToHardLimit = true,
  }) async {
    final Object? raw = await methodChannel.invokeMethod(
      'setNofileSoftLimit',
      <String, Object?>{
        'softLimit': softLimit,
        'clampToHardLimit': clampToHardLimit,
      },
    );

    if (raw is Map) {
      return NofileLimitResult.fromMap(raw.cast<Object?, Object?>());
    }

    // Fallback for unexpected host responses.
    return const NofileLimitResult(
      requestedSoft: 0,
      appliedSoft: 0,
      hard: 0,
      previousSoft: 0,
      previousHard: 0,
      clampedToHard: false,
      success: false,
      errno: 0,
      errorMessage: 'Unexpected platform response',
    );
  }
}
