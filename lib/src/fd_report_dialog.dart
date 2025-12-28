import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flutter_fd_utils.dart';

/// A simple dialog that periodically refreshes and displays the current FD report.
///
/// This widget is intentionally self-contained so host apps can reuse it without
/// additional dependencies.
class FdReportDialog extends StatefulWidget {
  const FdReportDialog({
    super.key,
    this.api = const FlutterFdUtils(),
    this.refreshInterval = const Duration(seconds: 5),
    this.titleText = 'FD Debug Report',
    this.copyText = 'Copy',
    this.closeText = 'Close',
    this.onCopied,
  });

  /// The API instance used to fetch the report.
  final FlutterFdUtils api;

  /// How often to refresh the report.
  final Duration refreshInterval;

  final String titleText;
  final String copyText;
  final String closeText;

  /// Optional callback invoked after copying.
  ///
  /// If not provided, a SnackBar will be shown when possible.
  final VoidCallback? onCopied;

  /// Shows the dialog via [showDialog].
  static Future<void> show(
    BuildContext context, {
    FlutterFdUtils api = const FlutterFdUtils(),
    Duration refreshInterval = const Duration(seconds: 5),
    String titleText = 'FD Debug Report',
    String copyText = 'Copy',
    String closeText = 'Close',
    VoidCallback? onCopied,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FdReportDialog(
        api: api,
        refreshInterval: refreshInterval,
        titleText: titleText,
        copyText: copyText,
        closeText: closeText,
        onCopied: onCopied,
      ),
    );
  }

  @override
  State<FdReportDialog> createState() => _FdReportDialogState();
}

class _FdReportDialogState extends State<FdReportDialog> {
  Timer? _timer;
  String _report = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.refreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    String nextReport;
    try {
      nextReport = await widget.api.getFdReport();
    } on PlatformException catch (e) {
      nextReport = 'PlatformException: ${e.code}\n${e.message ?? ''}\n${e.details ?? ''}';
    } catch (e) {
      nextReport = 'Error: $e';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _report = nextReport.isEmpty ? 'No data' : nextReport;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));

    if (!mounted) {
      return;
    }

    if (widget.onCopied != null) {
      widget.onCopied!();
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AlertDialog(
      title: Text(widget.titleText),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.6,
          maxWidth: screenSize.width * 0.9,
        ),
        child: SingleChildScrollView(
          child: SelectableText(_loading ? 'Loading...' : _report),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _copy,
          child: Text(widget.copyText),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(widget.closeText),
        ),
      ],
    );
  }
}
