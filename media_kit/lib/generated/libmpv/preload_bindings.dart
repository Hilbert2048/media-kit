// ignore_for_file: non_constant_identifier_names, constant_identifier_names, camel_case_types

// Preload API bindings for mpv
//
// FFI bindings for the lightweight demux-based preload API.
// Uses demux_open_url + demux_start_prefetch internally.

import 'dart:ffi' as ffi;

/// Preload status enum (matches mpv_preload_status in preload.h)
enum MpvPreloadStatus {
  none(0),
  loading(1),
  ready(2),
  error(3),
  cached(4);

  const MpvPreloadStatus(this.value);
  final int value;

  static MpvPreloadStatus fromValue(int value) {
    return MpvPreloadStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => MpvPreloadStatus.none,
    );
  }
}

/// Preload options for mpv_preload_start (matches mpv_preload_options in preload.h)
final class MpvPreloadOptions extends ffi.Struct {
  /// Demuxer cache size in bytes (0 = default 10MB)
  @ffi.Int64()
  external int max_bytes;

  /// Readahead seconds (0 = default 10s)
  @ffi.Double()
  external double readahead_secs;
}

/// Preload info structure (matches mpv_preload_info in preload.h)
final class MpvPreloadInfo extends ffi.Struct {
  /// Current status (mpv_preload_status value)
  @ffi.Int64()
  external int status;

  /// Forward cached bytes (from current position)
  @ffi.Int64()
  external int fw_bytes;

  /// Total bytes in buffer
  @ffi.Int64()
  external int total_bytes;

  /// Total file size (-1 if unknown)
  @ffi.Int64()
  external int file_size;

  /// Duration buffered in seconds
  @ffi.Double()
  external double buffered_secs;

  /// True if entire file is cached
  @ffi.Bool()
  external bool eof_cached;
}

/// Typedef for native function signatures
typedef _MpvPreloadStartC = ffi.Int32 Function(
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<MpvPreloadOptions> options,
);
typedef _MpvPreloadStartDart = int Function(
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<MpvPreloadOptions> options,
);

typedef _MpvPreloadGetInfoC = ffi.Int32 Function(
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<MpvPreloadInfo> info,
);
typedef _MpvPreloadGetInfoDart = int Function(
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<MpvPreloadInfo> info,
);

typedef _MpvPreloadCancelC = ffi.Int32 Function(ffi.Pointer<ffi.Char> url);
typedef _MpvPreloadCancelDart = int Function(ffi.Pointer<ffi.Char> url);

typedef _MpvPreloadClearAllC = ffi.Void Function();
typedef _MpvPreloadClearAllDart = void Function();

/// MPV Preload API bindings
class MPVPreload {
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) _lookup;

  MPVPreload(ffi.DynamicLibrary dynamicLibrary) : _lookup = dynamicLibrary.lookup;

  MPVPreload.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  /// Start preloading data for a URL
  int mpv_preload_start(
    ffi.Pointer<ffi.Char> url,
    ffi.Pointer<MpvPreloadOptions> options,
  ) {
    return _mpv_preload_start(url, options);
  }

  late final _mpv_preload_start =
      _lookup<ffi.NativeFunction<_MpvPreloadStartC>>('mpv_preload_start').asFunction<_MpvPreloadStartDart>();

  /// Get detailed preload info
  int mpv_preload_get_info(
    ffi.Pointer<ffi.Char> url,
    ffi.Pointer<MpvPreloadInfo> info,
  ) {
    return _mpv_preload_get_info(url, info);
  }

  late final _mpv_preload_get_info =
      _lookup<ffi.NativeFunction<_MpvPreloadGetInfoC>>('mpv_preload_get_info').asFunction<_MpvPreloadGetInfoDart>();

  /// Cancel an ongoing preload
  int mpv_preload_cancel(ffi.Pointer<ffi.Char> url) {
    return _mpv_preload_cancel(url);
  }

  late final _mpv_preload_cancel =
      _lookup<ffi.NativeFunction<_MpvPreloadCancelC>>('mpv_preload_cancel').asFunction<_MpvPreloadCancelDart>();

  /// Clear all cached preload data
  void mpv_preload_clear_all() {
    return _mpv_preload_clear_all();
  }

  late final _mpv_preload_clear_all =
      _lookup<ffi.NativeFunction<_MpvPreloadClearAllC>>('mpv_preload_clear_all').asFunction<_MpvPreloadClearAllDart>();

  /// Set callback for preload status events
  /// Callback receives: url (Pointer<Char>), info (Pointer<MpvPreloadInfo>)
  void mpv_preload_set_callback(
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<MpvPreloadInfo>)>> callback) {
    return _mpv_preload_set_callback(callback);
  }

  late final _mpv_preload_set_callback = _lookup<
              ffi.NativeFunction<
                  ffi.Void Function(
                      ffi.Pointer<
                          ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<MpvPreloadInfo>)>>)>>(
          'mpv_preload_set_callback')
      .asFunction<
          void Function(
              ffi.Pointer<
                  ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>, ffi.Pointer<MpvPreloadInfo>)>>)>();
}
