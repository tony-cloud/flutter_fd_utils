import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fd_utils/flutter_fd_utils_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterFdUtils platform = MethodChannelFlutterFdUtils();
  const MethodChannel channel = MethodChannel('flutter_fd_utils');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getFdReport') {
          return '42';
        }
        if (methodCall.method == 'getNofileLimit') {
          return <String, Object?>{'soft': 123, 'hard': 99999};
        }
        if (methodCall.method == 'getNofileSoftLimit') {
          return 123;
        }
        if (methodCall.method == 'getNofileHardLimit') {
          return 99999;
        }
        if (methodCall.method == 'getFdList') {
          return <Object?>[
            <String, Object?>{
              'fd': 3,
              'fdType': 1,
              'fdTypeName': 'VNODE',
              'openFlags': 0,
              'fdFlags': 0,
              'path': '/tmp/a',
              'vnode': <String, Object?>{'mode': 33188, 'size': 12},
            },
          ];
        }
        if (methodCall.method == 'setNofileSoftLimit') {
          return <String, Object?>{
            'requestedSoft': 4096,
            'appliedSoft': 4096,
            'hard': 99999,
            'previousSoft': 123,
            'previousHard': 99999,
            'clampedToHard': false,
            'success': true,
            'errno': 0,
            'errorMessage': '',
          };
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getFdReport', () async {
    expect(await platform.getFdReport(), '42');
  });

  test('getNofileLimit', () async {
    final limit = await platform.getNofileLimit();
    expect(limit.soft, 123);
    expect(limit.hard, 99999);
  });

  test('getNofileSoftLimit/getNofileHardLimit', () async {
    expect(await platform.getNofileSoftLimit(), 123);
    expect(await platform.getNofileHardLimit(), 99999);
  });

  test('getFdList', () async {
    final list = await platform.getFdList();
    expect(list.length, 1);
    expect(list.first.fdTypeName, 'VNODE');
    expect(list.first.vnode?.size, 12);
  });

  test('setNofileSoftLimit', () async {
    final result = await platform.setNofileSoftLimit(4096);
    expect(result.success, true);
    expect(result.requestedSoft, 4096);
    expect(result.appliedSoft, 4096);
  });
}
