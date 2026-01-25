import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class FFmpegTest extends StatefulWidget {
  const FFmpegTest({super.key});

  @override
  State<FFmpegTest> createState() => _FFmpegTestState();
}

class _FFmpegTestState extends State<FFmpegTest> {
  final TextEditingController _commandController =
      TextEditingController(text: '-version');
  String _log = '';
  final ScrollController _scrollController = ScrollController();
  bool _isExecuting = false;

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _runCommand() async {
    if (_isExecuting) return;

    setState(() {
      _isExecuting = true;
      _log += '\n--- RUNNING: ffmpeg ${_commandController.text} ---\n';
    });

    try {
      // Split command string into arguments
      // Note: This is a simple split and won't handle quoted arguments correctly
      final args = _commandController.text
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();

      await FFmpeg.execute(
        args,
        onLog: (log) {
          if (mounted) {
            setState(() {
              _log += '$log\n';
            });
            // Scroll to bottom
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                // Animate or jump to bottom
                _scrollController
                    .jumpTo(_scrollController.position.maxScrollExtent);
              }
            });
          }
        },
      );

      _log += '--- EXECUTION COMPLETED ---\n';
    } catch (e) {
      _log += 'Error executing command: $e\n';
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
        });
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    }
  }

  void _clearLog() {
    setState(() {
      _log = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FFmpeg CLI Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter FFmpeg arguments (without "ffmpeg"):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '-version',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isExecuting ? null : _runCommand,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isExecuting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('RUN'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('-version'),
                  onPressed: () {
                    _commandController.text = '-version';
                    _runCommand();
                  },
                ),
                ActionChip(
                  label: const Text('-buildconf'),
                  onPressed: () {
                    _commandController.text = '-buildconf';
                    _runCommand();
                  },
                ),
                ActionChip(
                  label: const Text('-protocols'),
                  onPressed: () {
                    _commandController.text = '-protocols';
                    _runCommand();
                  },
                ),
                ActionChip(
                  label: const Text('-demuxers'),
                  onPressed: () {
                    _commandController.text = '-demuxers';
                    _runCommand();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Output Log:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: _clearLog,
                  child: const Text('Clear'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
