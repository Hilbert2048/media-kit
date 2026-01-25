/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:ffi';
import 'dart:isolate';
import 'dart:async'; // Added for Completer
import 'package:ffi/ffi.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';

typedef FFmpegExecuteC = Void Function(
    Int64 port, Int32 argc, Pointer<Pointer<Utf8>> argv);
typedef FFmpegExecuteDart = void Function(
    int port, int argc, Pointer<Pointer<Utf8>> argv);

final class _FFToolsLog extends Struct {
  @Int32()
  external int level;

  external Pointer<Utf8> message;
}

final class _FFToolsStatistics extends Struct {
  @Int32()
  external int frameNumber;
  @Float()
  external double fps;
  @Float()
  external double quality;
  @Int64()
  external int size;
  @Int32()
  external int time;
  @Double()
  external double bitrate;
  @Double()
  external double speed;
}

final class _FFToolsData extends Union {
  external _FFToolsLog log_val;
  external _FFToolsStatistics stats_val;
  @Int32()
  external int returnCode;
}

final class _FFToolsMessage extends Struct {
  // 0=RETURN_CODE, 1=LOG, 2=STATS
  @Int32()
  external int type;
  external _FFToolsData data;
}

typedef FFToolsInitializeC = Void Function(Pointer<Void> initFunc);
typedef FFToolsInitializeDart = void Function(Pointer<Void> initFunc);

// Bind the system 'free' to handle C-allocated memory raw.
// Needed because 'package:ffi' calloc.free() might use a different allocator on some platforms
// than the one used by 'fftools-ffi' (system malloc).
final _stdlib = DynamicLibrary.process();
final _free = _stdlib.lookupFunction<Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('free');

/// {@template ffmpeg}
///
/// FFmpeg
/// ------
///
/// Provides access to FFmpeg CLI functionalities through `fftools-ffi`.
/// Check [ffmpeg_kit_flutter](https://pub.dev/packages/ffmpeg_kit_flutter) for a more complete solution.
///
/// {@endtemplate}
abstract class FFmpeg {
  static bool _initialized = false;

  /// Executes an FFmpeg command.
  ///
  /// Returns the exit code of the command.
  ///
  /// Example:
  /// ```dart
  /// await FFmpeg.execute(['-i', 'input.mp4', 'output.mp3']);
  /// ```
  /// [onLog] is an optional callback to receive log messages.
  static Future<int> execute(List<String> args,
      {void Function(String log)? onLog}) async {
    // Ensure native library is initialized.
    try {
      NativeLibrary.ensureInitialized();
    } catch (_) {}

    final libPath = NativeLibrary.path;
    final port = ReceivePort();
    final nativePort = port.sendPort.nativePort;

    return _executeWithPort(libPath, args, nativePort, port, onLog);
  }

  static Future<int> _executeWithPort(String libPath, List<String> args,
      int nativePort, ReceivePort port, void Function(String log)? onLog) {
    final dylib = DynamicLibrary.open(libPath);

    // Initialize Dart API DL if needed
    if (!_initialized) {
      try {
        final initialize =
            dylib.lookupFunction<FFToolsInitializeC, FFToolsInitializeDart>(
                'FFToolsFFIInitialize');
        initialize(NativeApi.postCObject.cast());
        _initialized = true;
      } catch (e) {
        print('FFmpeg: Failed to initialize Dart API DL: $e');
        // Fallback or rethrow? If this fails, next call will crash.
        throw e;
      }
    }

    final execute = dylib.lookupFunction<FFmpegExecuteC, FFmpegExecuteDart>(
        'FFToolsFFIExecuteFFmpeg');

    final fullArgs = ['ffmpeg', ...args];
    final fullArgv = calloc<Pointer<Utf8>>(fullArgs.length);
    for (var i = 0; i < fullArgs.length; i++) {
      fullArgv[i] = fullArgs[i].toNativeUtf8();
    }

    // Launch execution
    execute(nativePort, fullArgs.length, fullArgv);

    final completer = Completer<int>();

    port.listen((message) {
      if (message is int) {
        final ptr = Pointer<_FFToolsMessage>.fromAddress(message);
        try {
          final type = ptr.ref.type;
          if (type == 0) {
            // RETURN_CODE
            final ret = ptr.ref.data.returnCode;
            if (!completer.isCompleted) {
              completer.complete(ret);
            }
            port.close();
            // C takes ownership of argv and frees it. Do NOT free fullArgv here.
          } else if (type == 1) {
            // LOG
            final log = ptr.ref.data.log_val;
            if (log.message != nullptr) {
              final msg = log.message.toDartString();
              String logMsg;
              if (msg.endsWith('\n')) {
                logMsg = msg.substring(0, msg.length - 1);
              } else {
                logMsg = msg;
              }
              print('[FFmpeg] $logMsg');
              onLog?.call(logMsg);

              // Free the message string allocated by C
              _free(log.message.cast());
            }
          } else if (type == 2) {
            // STATS - Ignore for now
          }
        } finally {
          // Free the _FFToolsMessage struct itself using native free
          _free(ptr.cast());
        }
      }
    });

    return completer.future;
  }
}
