import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int _sampleRate = 44100;

void main() {
  final output = Directory('assets/audio')..createSync(recursive: true);

  _writeCue(
    output,
    'follow.wav',
    durationMs: 150,
    voices: const <_Voice>[
      _Voice(frequency: 493.88, startMs: 0, endMs: 105, gain: 0.34),
      _Voice(frequency: 739.99, startMs: 42, endMs: 150, gain: 0.28),
      _Voice(frequency: 987.77, startMs: 70, endMs: 145, gain: 0.10),
    ],
  );
  _writeCue(
    output,
    'like.wav',
    durationMs: 118,
    voices: const <_Voice>[
      _Voice(
        frequency: 587.33,
        endFrequency: 783.99,
        startMs: 0,
        endMs: 100,
        gain: 0.34,
      ),
      _Voice(frequency: 1174.66, startMs: 36, endMs: 118, gain: 0.16),
    ],
  );
  _writeCue(
    output,
    'save.wav',
    durationMs: 105,
    voices: const <_Voice>[
      _Voice(frequency: 880, startMs: 0, endMs: 80, gain: 0.30),
      _Voice(frequency: 1320, startMs: 8, endMs: 105, gain: 0.18),
      _Voice(frequency: 1760, startMs: 18, endMs: 78, gain: 0.08),
    ],
  );
  _writeCue(
    output,
    'repost.wav',
    durationMs: 145,
    voices: const <_Voice>[
      _Voice(
        frequency: 440,
        endFrequency: 659.25,
        startMs: 0,
        endMs: 105,
        gain: 0.27,
      ),
      _Voice(
        frequency: 659.25,
        endFrequency: 880,
        startMs: 45,
        endMs: 145,
        gain: 0.22,
      ),
    ],
  );
  _writeCue(
    output,
    'undo.wav',
    durationMs: 105,
    voices: const <_Voice>[
      _Voice(
        frequency: 698.46,
        endFrequency: 392,
        startMs: 0,
        endMs: 105,
        gain: 0.28,
      ),
      _Voice(frequency: 349.23, startMs: 40, endMs: 100, gain: 0.10),
    ],
  );
  _writeCue(
    output,
    'focus.wav',
    durationMs: 92,
    voices: const <_Voice>[
      _Voice(
        frequency: 1046.50,
        endFrequency: 1318.51,
        startMs: 0,
        endMs: 72,
        gain: 0.25,
      ),
      _Voice(frequency: 2093, startMs: 18, endMs: 92, gain: 0.11),
    ],
  );
  _writeCue(
    output,
    'error.wav',
    durationMs: 155,
    voices: const <_Voice>[
      _Voice(
        frequency: 246.94,
        endFrequency: 196,
        startMs: 0,
        endMs: 155,
        gain: 0.30,
      ),
      _Voice(frequency: 146.83, startMs: 34, endMs: 145, gain: 0.12),
    ],
  );
}

void _writeCue(
  Directory output,
  String name, {
  required int durationMs,
  required List<_Voice> voices,
}) {
  final sampleCount = (_sampleRate * durationMs / 1000).round();
  final pcm = Int16List(sampleCount);

  for (var index = 0; index < sampleCount; index++) {
    final milliseconds = index * 1000 / _sampleRate;
    var mixed = 0.0;
    for (final voice in voices) {
      if (milliseconds < voice.startMs || milliseconds >= voice.endMs) {
        continue;
      }
      final progress =
          (milliseconds - voice.startMs) / (voice.endMs - voice.startMs);
      final attack = math.min(1.0, progress / 0.055);
      final release = math.pow(1 - progress, 2.35).toDouble();
      final frequency =
          voice.frequency +
          ((voice.endFrequency ?? voice.frequency) - voice.frequency) *
              progress;
      final seconds = index / _sampleRate;
      mixed +=
          math.sin(2 * math.pi * frequency * seconds) *
          attack *
          release *
          voice.gain;
    }
    final driven = mixed * 1.35;
    final softened = driven / (1 + driven.abs()) * 0.64;
    pcm[index] = (softened * 32767).round().clamp(-32768, 32767);
  }

  final bytes = ByteData(44 + pcm.lengthInBytes);
  _ascii(bytes, 0, 'RIFF');
  bytes.setUint32(4, 36 + pcm.lengthInBytes, Endian.little);
  _ascii(bytes, 8, 'WAVE');
  _ascii(bytes, 12, 'fmt ');
  bytes
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, _sampleRate, Endian.little)
    ..setUint32(28, _sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  _ascii(bytes, 36, 'data');
  bytes.setUint32(40, pcm.lengthInBytes, Endian.little);
  for (var index = 0; index < pcm.length; index++) {
    bytes.setInt16(44 + index * 2, pcm[index], Endian.little);
  }

  File('${output.path}/$name').writeAsBytesSync(bytes.buffer.asUint8List());
}

void _ascii(ByteData bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes.setUint8(offset + index, value.codeUnitAt(index));
  }
}

class _Voice {
  const _Voice({
    required this.frequency,
    required this.startMs,
    required this.endMs,
    required this.gain,
    this.endFrequency,
  });

  final double frequency;
  final double? endFrequency;
  final double startMs;
  final double endMs;
  final double gain;
}
