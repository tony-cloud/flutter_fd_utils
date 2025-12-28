import 'package:flutter/material.dart';
import 'package:flutter_fd_utils/flutter_fd_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _api = FlutterFdUtils();
  String _reportPreview = '';
  String _rlimitStatus = '';
  String _fdListStatus = '';

  @override
  void initState() {
    super.initState();
    _refreshOnce();
    _refreshLimits();
  }

  Future<void> _refreshOnce() async {
    final report = await _api.getFdReport();
    if (!mounted) {
      return;
    }
    setState(() {
      _reportPreview = report.isEmpty ? 'No data' : report;
    });
  }

  Future<void> _setSoftLimit(int value) async {
    final result = await _api.setNofileSoftLimit(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _rlimitStatus = result.success
          ? 'RLIMIT_NOFILE soft updated: ${result.previousSoft} -> ${result.appliedSoft} (hard=${result.hard})'
          : 'Failed to set RLIMIT_NOFILE soft to ${result.requestedSoft}: errno=${result.errno} ${result.errorMessage}';
    });
  }

  Future<void> _refreshLimits() async {
    final limit = await _api.getNofileLimit();
    if (!mounted) return;
    setState(() {
      _rlimitStatus = 'RLIMIT_NOFILE: soft=${limit.soft} hard=${limit.hard}';
    });
  }

  Future<void> _refreshFdList() async {
    final list = await _api.getFdList();
    if (!mounted) return;
    setState(() {
      _fdListStatus = 'FD list size: ${list.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_fd_utils example'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => FdReportDialog.show(context, api: _api),
                child: const Text('Show FD report dialog'),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _setSoftLimit(8192),
                child: const Text('Set soft nofile to 8192'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _setSoftLimit(16384),
                child: const Text('Set soft nofile to 16384'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refreshLimits,
                child: const Text('Refresh nofile limits'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _refreshFdList,
                child: const Text('Fetch FD list (count only)'),
              ),
              if (_fdListStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_fdListStatus),
              ],
              const SizedBox(height: 12),
              if (_rlimitStatus.isNotEmpty) ...[
                Text(_rlimitStatus),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: _refreshOnce,
                child: const Text('Fetch once'),
              ),
              const SizedBox(height: 12),
              const Text('Preview:'),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(_reportPreview),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
