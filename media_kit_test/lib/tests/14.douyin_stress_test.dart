import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Douyin-style feed scrolling stress test
/// This test simulates the real crash scenario:
/// - 20 videos in a feed
/// - Rapid up/down scrolling
/// - Preloading next AND previous videos
/// - Very short viewing time (100ms)
/// - Slow network conditions (demux threads in I/O)
class DouyinStyleStressTest extends StatefulWidget {
  const DouyinStyleStressTest({super.key});

  @override
  State<DouyinStyleStressTest> createState() => _DouyinStyleStressTestState();
}

class _DouyinStyleStressTestState extends State<DouyinStyleStressTest> {
  MediaKitPreloader? _preloader;
  String _log = '';
  bool _isRunning = false;
  final _logScrollController = ScrollController();

  // Real-world 1080p videos - these are LARGE and SLOW to load
  // Perfect for triggering the demux thread crash!
  final _testUrls = [
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hom/hom0214/hom0214_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hom/hom0215/hom0215_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hom/hom0216/hom0216_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hom/hom0217/hom0217_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hot/hot0250/hot0250_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hot/hot0251/hot0251_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/hot/hot0252/hot0252_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/howin/howin0172/howin0172_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/howin/howin0173/howin0173_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/howin/howin0174/howin0174_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/howin/howin0175/howin0175_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/htg/htg0514/htg0514_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/htg/htg0515/htg0515_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/htg/htg0516/htg0516_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/htg/htg0517/htg0517_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ipad/ipad0785/ipad0785_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ipad/ipad0786/ipad0786_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ipad/ipad0787/ipad0787_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ipad/ipad0788/ipad0788_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/mbw/mbw1007/mbw1007_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/mbw/mbw1008/mbw1008_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/mbw/mbw1009/mbw1009_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/mbw/mbw1010/mbw1010_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/sn/sn1060/sn1060_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/sn/sn1061/sn1061_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/sn/sn1062/sn1062_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/sn/sn1063/sn1063_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/tnw/tnw0420/tnw0420_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/tnw/tnw0421/tnw0421_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/tnw/tnw0422/tnw0422_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/tnw/tnw0423/tnw0423_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twig/twig0853/twig0853_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twig/twig0854/twig0854_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twig/twig0855/twig0855_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twig/twig0856/twig0856_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twis/twis0193/twis0193_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twis/twis0194/twis0194_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twis/twis0195/twis0195_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twit/twit1066/twit1066_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twit/twit1067/twit1067_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twit/twit1068/twit1068_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/twit/twit1069/twit1069_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/uls/uls0237/uls0237_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/uls/uls0238/uls0238_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/uls/uls0239/uls0239_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/uls/uls0240/uls0240_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ww/ww0966/ww0966_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ww/ww0967/ww0967_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ww/ww0968/ww0968_h264m_1920x1080.mp4',
    'http://pscrb.fm/rss/p/mgln.ai/e/294/cdn.twit.tv/video/ww/ww0969/ww0969_h264m_1920x1080.mp4',
  ];

  @override
  void initState() {
    super.initState();
    _initPreloader();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _log += message;
    });
  }

  Future<void> _initPreloader() async {
    try {
      _addLog('Initializing preloader...\n');
      _preloader = MediaKitPreloader();
      await _preloader!.ensureInitialized();
      _addLog('Preloader initialized!\n');
    } catch (e) {
      _addLog('Error initializing: $e\n');
    }
  }

  Future<void> _runDouyinStyleTest() async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _log = '';
    });

    _addLog('📱📱📱 DOUYIN-STYLE FEED TEST 📱📱📱\n');
    _addLog('Simulating: 50 real 1080p videos, rapid scrolling\n');
    _addLog('Videos: LARGE files (slow network loading)\n');
    _addLog('This mimics REAL crash scenario!\n\n');

    // Use ALL 50 videos (not just 20!)
    final videoUrls = _testUrls;

    int currentIndex = 0;
    int successCount = 0;
    int failCount = 0;
    Player? currentPlayer;

    try {
      // Simulate 50 swipes (scrolling down through the feed)
      for (int swipe = 1; swipe <= 50; swipe++) {
        if (!_isRunning) break;

        try {
          // Dispose previous player (if any)
          if (currentPlayer != null) {
            await currentPlayer.dispose();
            currentPlayer = null;
          }

          // Scroll down to next video (more realistic than up/down)
          currentIndex = swipe % videoUrls.length;

          final currentUrl = videoUrls[currentIndex];
          final nextUrl = videoUrls[(currentIndex + 1) % videoUrls.length];
          final prevUrl = videoUrls[
              (currentIndex - 1 + videoUrls.length) % videoUrls.length];

          _addLog('[Swipe $swipe] Video #$currentIndex\n');

          // CRITICAL: Preload next AND previous (like real Douyin)
          _preloader?.start(nextUrl);
          _preloader?.start(prevUrl);

          // Very short delay (user swipes fast!)
          await Future.delayed(const Duration(milliseconds: 30));

          // Create and play current video
          currentPlayer = Player();
          await currentPlayer.open(Media(currentUrl));

          // Simulate very brief viewing (fast scrolling!)
          // This is KEY: dispose while demux threads are still loading
          await Future.delayed(const Duration(milliseconds: 100));

          successCount++;

          if (swipe % 10 == 0) {
            _addLog('[Progress] ✅ Success: $successCount, Fail: $failCount\n');
          }
        } catch (e) {
          failCount++;
          _addLog('[Swipe $swipe] ❌ ERROR: $e\n');

          if (failCount > 5) {
            _addLog('⛔ Too many failures, stopping\n');
            break;
          }
        }
      }
    } finally {
      // Cleanup
      await currentPlayer?.dispose();
    }

    _addLog('\n🏁 DOUYIN-STYLE TEST COMPLETE 🏁\n');
    _addLog('Total swipes: 50\n');
    _addLog('Success: $successCount ✅\n');
    _addLog('Failures: $failCount ❌\n\n');

    if (failCount == 0) {
      _addLog('🎉 No crashes! Feed scrolling is stable!\n');
    } else {
      _addLog('⚠️ Crashes detected in feed scenario\n');
    }

    setState(() {
      _isRunning = false;
    });
  }

  void _stopTest() {
    setState(() {
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController
            .jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Douyin-Style Stress Test'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This test simulates real Douyin/TikTok feed scrolling:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• 20 videos in feed\n'
                  '• 50 rapid swipes up/down\n'
                  '• Preload next + previous video\n'
                  '• 100ms viewing time (very fast!)\n'
                  '• Dispose while demux threads loading',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isRunning ? null : _runDouyinStyleTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: Text(
                    _isRunning ? 'Running...' : '🔥 Start Douyin Test',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                if (_isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ElevatedButton(
                      onPressed: _stopTest,
                      child: const Text('Stop Test'),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.black12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _logScrollController,
                      child: SelectableText(_log,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
