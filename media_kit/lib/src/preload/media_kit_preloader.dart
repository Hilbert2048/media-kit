/// MediaKit video preloading functionality
///
/// This library provides APIs to preload video data before playback,
/// improving startup time for video players.
library;

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'package:media_kit/generated/libmpv/preload_bindings.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';

export 'package:media_kit/generated/libmpv/preload_bindings.dart' show MpvPreloadStatus;

/// Configuration options for preloading
class PreloadOptions {
  /// Maximum bytes to preload (default: 10MB)
  final int maxBytes;

  /// Readahead seconds (default: 10)
  final double readaheadSecs;

  const PreloadOptions({
    this.maxBytes = 10 * 1024 * 1024, // 10MB
    this.readaheadSecs = 10.0,
  });
}

/// Preload info with progress details
/// Used for both callback events (has url) and getInfo() results
class PreloadInfo {
  /// URL that was preloaded (set in callback events, null in getInfo results)
  final String? url;

  /// Current preload status
  final MpvPreloadStatus status;

  /// Forward cached bytes (from current position)
  final int fwBytes;

  /// Total bytes in buffer
  final int totalBytes;

  /// Total file size (-1 if unknown)
  final int fileSize;

  /// Duration buffered in seconds
  final double bufferedSecs;

  /// True if entire file is cached
  final bool eofCached;

  const PreloadInfo({
    this.url,
    required this.status,
    this.fwBytes = 0,
    this.totalBytes = 0,
    this.fileSize = -1,
    this.bufferedSecs = 0,
    this.eofCached = false,
  });

  /// Returns true if demuxer is usable (may still be caching)
  bool get isReady => status == MpvPreloadStatus.ready;

  /// Returns true if cache target reached
  bool get isCached => status == MpvPreloadStatus.cached;

  bool get isError => status == MpvPreloadStatus.error;
  bool get isLoading => status == MpvPreloadStatus.loading;
  bool get isNone => status == MpvPreloadStatus.none;

  /// Whether a demuxer is available (loading or ready or cached)
  bool get hasData => isLoading || isReady || isCached;

  @override
  String toString() =>
      'PreloadInfo(status: $status, fw: ${(fwBytes / 1024 / 1024).toStringAsFixed(2)}MB, total: ${(totalBytes / 1024 / 1024).toStringAsFixed(2)}MB, fileSize: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB, eof: $eofCached)';
}

/// Media preloader for preloading video data before playback
///
/// Uses lightweight demux-based preloading. Each preload creates
/// an independent context and begins prefetching data. The preloaded
/// demuxer can be used even while still loading.
///
/// Usage:
/// ```dart
/// final preloader = MediaKitPreloader();
/// await preloader.ensureInitialized();
///
/// // Listen for completion events
/// preloader.stream.listen((event) {
///   print('Preload ${event.isReady ? 'ready' : 'failed'}: ${event.url}');
/// });
///
/// // Start preloading with custom buffer size
/// preloader.start('https://example.com/video.mp4',
///   options: PreloadOptions(maxBytes: 5 * 1024 * 1024));
///
/// // When playing the same URL, preloaded data is used automatically
/// player.open(Media('https://example.com/video.mp4'));
/// ```
class MediaKitPreloader {
  static MediaKitPreloader? _instance;

  MPVPreload? _bindings;
  bool _initialized = false;

  // Stream for preload completion events
  final StreamController<PreloadInfo> _eventController = StreamController<PreloadInfo>.broadcast();

  // NativeCallable for C callback
  ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<MpvPreloadInfo>)>? _nativeCallback;

  /// Stream of preload completion events
  Stream<PreloadInfo> get stream => _eventController.stream;

  /// Get the shared instance
  factory MediaKitPreloader() {
    return _instance ??= MediaKitPreloader._();
  }

  MediaKitPreloader._();

  /// Initialize the preloader. Must be called before using other methods.
  Future<void> ensureInitialized() async {
    if (_initialized) return;

    // Get the mpv dynamic library using the same path as the player
    final libmpv = ffi.DynamicLibrary.open(NativeLibrary.path);
    _bindings = MPVPreload(libmpv);

    // Set up callback
    _nativeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<MpvPreloadInfo>)>.listener(
      _onPreloadCallback,
    );
    _bindings!.mpv_preload_set_callback(_nativeCallback!.nativeFunction);

    _initialized = true;
  }

  // Callback invoked from C when preload status changes
  void _onPreloadCallback(ffi.Pointer<ffi.Char> urlPtr, ffi.Pointer<MpvPreloadInfo> infoPtr) {
    try {
      final url = urlPtr.cast<Utf8>().toDartString();
      final info = infoPtr.ref;
      final status = MpvPreloadStatus.fromValue(info.status);
      _eventController.add(PreloadInfo(
        url: url,
        status: status,
        fwBytes: info.fw_bytes,
        totalBytes: info.total_bytes,
        fileSize: info.file_size,
        bufferedSecs: info.buffered_secs,
        eofCached: info.eof_cached,
      ));
    } catch (e) {
      // Ignore callback errors (can happen when entry is evicted during callback)
    }
  }

  void _checkInitialized() {
    if (!_initialized || _bindings == null) {
      throw StateError(
        'MediaKitPreloader not initialized. Call ensureInitialized() first.',
      );
    }
  }

  /// Start preloading data for a URL
  bool start(String url, {PreloadOptions options = const PreloadOptions()}) {
    _checkInitialized();

    final urlPtr = url.toNativeUtf8().cast<ffi.Char>();
    final optsPtr = calloc<MpvPreloadOptions>();

    try {
      optsPtr.ref.max_bytes = options.maxBytes;
      optsPtr.ref.readahead_secs = options.readaheadSecs;

      final result = _bindings!.mpv_preload_start(urlPtr, optsPtr);
      return result == 0;
    } finally {
      calloc.free(urlPtr);
      calloc.free(optsPtr);
    }
  }

  /// Get detailed preload info including progress
  PreloadInfo getInfo(String url) {
    _checkInitialized();

    final urlPtr = url.toNativeUtf8().cast<ffi.Char>();
    final infoPtr = calloc<MpvPreloadInfo>();

    try {
      _bindings!.mpv_preload_get_info(urlPtr, infoPtr);
      return PreloadInfo(
        status: MpvPreloadStatus.fromValue(infoPtr.ref.status),
        fwBytes: infoPtr.ref.fw_bytes,
        totalBytes: infoPtr.ref.total_bytes,
        fileSize: infoPtr.ref.file_size,
        bufferedSecs: infoPtr.ref.buffered_secs,
        eofCached: infoPtr.ref.eof_cached,
      );
    } finally {
      calloc.free(urlPtr);
      calloc.free(infoPtr);
    }
  }

  /// Cancel an ongoing preload
  bool cancel(String url) {
    _checkInitialized();

    final urlPtr = url.toNativeUtf8().cast<ffi.Char>();
    try {
      final result = _bindings!.mpv_preload_cancel(urlPtr);
      return result == 0;
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Clear all cached preload data
  void clearAll() {
    _checkInitialized();
    _bindings!.mpv_preload_clear_all();
  }

  /// Set maximum number of preload entries.
  ///
  /// **IMPORTANT**: Must be called BEFORE any preload starts.
  /// Once preload has started, this returns false and has no effect.
  /// Call [clearAll] first if you need to change the limit after preloading.
  ///
  /// Returns true on success, false on error.
  bool setMaxEntries(int newMax) {
    _checkInitialized();
    return _bindings!.mpv_preload_set_max_entries(newMax) == 0;
  }

  /// Get current maximum number of preload entries
  int getMaxEntries() {
    _checkInitialized();
    return _bindings!.mpv_preload_get_max_entries();
  }

  /// Get number of currently active preload entries
  int getActiveCount() {
    _checkInitialized();
    return _bindings!.mpv_preload_get_active_count();
  }
}
