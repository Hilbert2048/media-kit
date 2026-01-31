import 'package:test/test.dart';
import 'package:media_kit/src/ffmpeg/ffmpeg.dart';

void main() {
  group('FFmpeg', () {
    test('parseArguments splits simple commands', () {
      final args = FFmpeg.parseArguments('-i input.mp4 output.mp3');
      expect(args, equals(['-i', 'input.mp4', 'output.mp3']));
    });

    test('parseArguments handles quotes', () {
      final args = FFmpeg.parseArguments('-i "input file.mp4" output.mp3');
      expect(args, equals(['-i', 'input file.mp4', 'output.mp3']));
    });

    test('parseArguments handles mixed quotes', () {
      final args =
          FFmpeg.parseArguments("-i 'input file.mp4' \"output file.mp3\"");
      expect(args, equals(['-i', 'input file.mp4', 'output file.mp3']));
    });

    test('parseArguments handles empty string', () {
      expect(FFmpeg.parseArguments(''), isEmpty);
    });
  });
}
