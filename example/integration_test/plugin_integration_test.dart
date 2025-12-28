// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing


import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_fd_utils/flutter_fd_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getFdReport test', (WidgetTester tester) async {
    const FlutterFdUtils plugin = FlutterFdUtils();
    final String report = await plugin.getFdReport();
    // The report content depends on runtime state; just assert it is not empty.
    expect(report.isNotEmpty, true);
  });
}
