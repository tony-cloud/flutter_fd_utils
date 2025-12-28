import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fd_utils/flutter_fd_utils.dart';
import 'package:flutter_fd_utils/flutter_fd_utils_platform_interface.dart';
import 'package:flutter_fd_utils/flutter_fd_utils_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterFdUtilsPlatform
    with MockPlatformInterfaceMixin
  implements FlutterFdUtilsPlatform {

  @override
  Future<String> getFdReport() => Future.value('42');

  @override
  Future<NofileLimit> getNofileLimit() {
    return Future.value(const NofileLimit(soft: 123, hard: 99999));
  }

  @override
  Future<int> getNofileSoftLimit() {
    return Future.value(123);
  }

  @override
  Future<int> getNofileHardLimit() {
    return Future.value(99999);
  }

  @override
  Future<List<FdInfo>> getFdList() {
    return Future.value(
      const [
        FdInfo(fd: 3, fdType: 1, fdTypeName: 'VNODE'),
      ],
    );
  }

  @override
  Future<NofileLimitResult> setNofileSoftLimit(
    int softLimit, {
    bool clampToHardLimit = true,
  }) {
    return Future.value(
      NofileLimitResult(
        requestedSoft: softLimit,
        appliedSoft: softLimit,
        hard: 99999,
        previousSoft: 123,
        previousHard: 99999,
        clampedToHard: false,
        success: true,
        errno: 0,
        errorMessage: '',
      ),
    );
  }
}

void main() {
  final FlutterFdUtilsPlatform initialPlatform = FlutterFdUtilsPlatform.instance;

  test('$MethodChannelFlutterFdUtils is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterFdUtils>());
  });

  test('getFdReport', () async {
    const FlutterFdUtils plugin = FlutterFdUtils();
    MockFlutterFdUtilsPlatform fakePlatform = MockFlutterFdUtilsPlatform();
    FlutterFdUtilsPlatform.instance = fakePlatform;

    expect(await plugin.getFdReport(), '42');
  });

  test('setNofileSoftLimit', () async {
    const FlutterFdUtils plugin = FlutterFdUtils();
    MockFlutterFdUtilsPlatform fakePlatform = MockFlutterFdUtilsPlatform();
    FlutterFdUtilsPlatform.instance = fakePlatform;

    final result = await plugin.setNofileSoftLimit(4096);
    expect(result.success, true);
    expect(result.requestedSoft, 4096);
    expect(result.appliedSoft, 4096);
  });

  test('getNofileLimit/getNofileSoftLimit/getNofileHardLimit', () async {
    const FlutterFdUtils plugin = FlutterFdUtils();
    MockFlutterFdUtilsPlatform fakePlatform = MockFlutterFdUtilsPlatform();
    FlutterFdUtilsPlatform.instance = fakePlatform;

    final limit = await plugin.getNofileLimit();
    expect(limit.soft, 123);
    expect(limit.hard, 99999);

    expect(await plugin.getNofileSoftLimit(), 123);
    expect(await plugin.getNofileHardLimit(), 99999);
  });

  test('getFdList', () async {
    const FlutterFdUtils plugin = FlutterFdUtils();
    MockFlutterFdUtilsPlatform fakePlatform = MockFlutterFdUtilsPlatform();
    FlutterFdUtilsPlatform.instance = fakePlatform;

    final list = await plugin.getFdList();
    expect(list.length, 1);
    expect(list.first.fd, 3);
  });
}
