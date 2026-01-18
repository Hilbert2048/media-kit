import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PreloadTest extends StatefulWidget {
  const PreloadTest({super.key});

  @override
  State<PreloadTest> createState() => _PreloadTestState();
}

class _PreloadTestState extends State<PreloadTest> {
  MediaKitPreloader? _preloader;
  Player? _player;
  VideoController? _videoController;
  String _status = 'Not initialized';
  String _log = '';
  DateTime? _playStartTime;
  final _logScrollController = ScrollController();

  final _testUrls = [
    'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
    'https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4',
    // HLS m3u8 test stream
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];

  @override
  void initState() {
    super.initState();
    _initPreloader();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    _log += message;
    setState(() {});
  }

  Future<void> _initPreloader() async {
    try {
      _addLog('Initializing preloader...\n');

      _preloader = MediaKitPreloader();
      await _preloader!.ensureInitialized();

      // Listen for preload completion events
      _preloader!.stream.listen((event) {
        _addLog('📢 CALLBACK: $event\n');
      });

      _status = 'Initialized';
      _addLog('Preloader initialized successfully!\n');
    } catch (e) {
      _status = 'Error: $e';
      _addLog('Error initializing: $e\n');
    }
  }

  void _startPreload(String url) {
    if (_preloader == null) return;

    try {
      _addLog('Starting preload: ${url.length > 50 ? '${url.substring(0, 50)}...' : url}\n');
      final success = _preloader!.start(url);
      _addLog('Start result: $success\n');
    } catch (e) {
      _addLog('Error starting preload: $e\n');
    }
  }

  void _checkStatus(String url) {
    if (_preloader == null) return;

    try {
      final info = _preloader!.getInfo(url);
      _log += 'Status: ${info.status}\n';
      _log += 'Buffered: ${info.bufferedSecs.toStringAsFixed(1)}s\n';
      _log +=
          'fw: ${(info.fwBytes / 1024 / 1024).toStringAsFixed(2)}MB, total: ${(info.totalBytes / 1024 / 1024).toStringAsFixed(2)}MB\n';
      _log += 'EOF: ${info.eofCached}\n';
      setState(() {});
    } catch (e) {
      _log += 'Error getting status: $e\n';
      setState(() {});
    }
  }

  void _cancelPreload(String url) {
    if (_preloader == null) return;

    try {
      final success = _preloader!.cancel(url);
      _log += 'Cancel result: $success\n';
      setState(() {});
    } catch (e) {
      _log += 'Error canceling: $e\n';
      setState(() {});
    }
  }

  void _clearAll() {
    if (_preloader == null) return;

    try {
      _preloader!.clearAll();
      _log += 'Cleared all preload cache\n';
      setState(() {});
    } catch (e) {
      _log += 'Error clearing: $e\n';
      setState(() {});
    }
  }

  Future<void> _playUrl(String url, {Duration? start}) async {
    try {
      _log += '\n--- PLAYING VIDEO ---\n';
      _log += 'URL: ${url.length > 50 ? '${url.substring(0, 50)}...' : url}\n';
      _log += 'Start position: ${start?.inSeconds ?? "not set"}s\n';
      _playStartTime = DateTime.now();
      _log += 'Play start time: ${_playStartTime}\n';

      // Dispose previous player if any
      await _player?.dispose();

      // Create new player
      _player = Player();
      _videoController = VideoController(_player!);

      // Listen for first frame
      _player!.stream.playing.listen((playing) {
        if (playing && _playStartTime != null) {
          final elapsed = DateTime.now().difference(_playStartTime!);
          _log += '▶ Playing started! Elapsed: ${elapsed.inMilliseconds}ms\n';
          setState(() {});
        }
      });

      _player!.stream.buffering.listen((buffering) {
        if (!buffering && _playStartTime != null) {
          final elapsed = DateTime.now().difference(_playStartTime!);
          _log += '⏱ Buffering complete! Elapsed: ${elapsed.inMilliseconds}ms\n';
          setState(() {});
        }
      });

      // Open and play with optional start position
      await _player!.open(Media(url, start: start));

      setState(() {});

      // Show video dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Video Player'),
            content: SizedBox(
              width: 400,
              height: 300,
              child: Video(controller: _videoController!),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _player?.dispose();
                  _player = null;
                  _videoController = null;
                },
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _log += 'Error playing: $e\n';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-scroll log to bottom on every rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preload Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Test URLs:', style: TextStyle(fontWeight: FontWeight.bold)),
            for (int i = 0; i < _testUrls.length; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'URL ${i + 1}: ${_testUrls[i].length > 50 ? '${_testUrls[i].substring(0, 50)}...' : _testUrls[i]}',
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () => _startPreload(_testUrls[i]),
                            child: const Text('Preload'),
                          ),
                          ElevatedButton(
                            onPressed: () => _checkStatus(_testUrls[i]),
                            child: const Text('Status'),
                          ),
                          ElevatedButton(
                            onPressed: () => _cancelPreload(_testUrls[i]),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _playUrl(_testUrls[i]),
                            child: const Text('▶ Play'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _playUrl(_testUrls[i], start: Duration.zero),
                            child: const Text('▶ @0s'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _playUrl(_testUrls[i], start: const Duration(seconds: 5)),
                            child: const Text('▶ @5s'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Max Entries: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_preloader?.getMaxEntries() ?? "N/A"}'),
                const SizedBox(width: 8),
                const Text('Active: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_preloader?.getActiveCount() ?? "N/A"}'),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    final result = _preloader?.setMaxEntries(2) ?? false;
                    _log += 'Set max entries to 2: ${result ? "OK" : "FAILED"}\n';
                    setState(() {});
                  },
                  child: const Text('2'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    final result = _preloader?.setMaxEntries(4) ?? false;
                    _log += 'Set max entries to 4: ${result ? "OK" : "FAILED"}\n';
                    setState(() {});
                  },
                  child: const Text('4'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    final result = _preloader?.setMaxEntries(8) ?? false;
                    _log += 'Set max entries to 8: ${result ? "OK" : "FAILED"}\n';
                    setState(() {});
                  },
                  child: const Text('8'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    final result = _preloader?.setMaxEntries(16) ?? false;
                    _log += 'Set max entries to 16: ${result ? "OK" : "FAILED"}\n';
                    setState(() {});
                  },
                  child: const Text('16'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _clearAll,
              child: const Text('Clear All Cache'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Test: 1) Preload URL → 2) Wait complete → 3) Play\n'
              'Compare startup time with/without preload!',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                child: SingleChildScrollView(
                  controller: _logScrollController,
                  child: SelectableText(_log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
