import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class LiveCaptureFrame {
  const LiveCaptureFrame({
    required this.levelDb,
    required this.estimateHz,
    required this.correlation,
    required this.elapsed,
  });

  /// Approximate signal level in dBFS (-80..0).
  final double levelDb;

  /// Live pitch estimate in Hz or null when not yet stable.
  final double? estimateHz;

  /// Normalized autocorrelation strength of the estimate (0..1).
  final double? correlation;

  /// How long the live capture has been running.
  final Duration elapsed;
}

class ResonanceCaptureService {
  ResonanceCaptureService({AudioRecorder? recorder, AudioPlayer? player})
      : _recorder = recorder ?? AudioRecorder(),
        _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;

  static const int _liveSampleRate = 44100;
  static const int _analysisWindow = 4096;
  static const int _maxLiveSamples = _liveSampleRate * 8;

  // Continuous audition tone: a seamlessly-looping base sine that we retune in
  // real time via setPlaybackRate so the slider doesn't have to start/stop
  // short clips (which causes audible glitches).
  static const double _baseToneHz = 1000.0;
  File? _continuousToneFile;
  bool _continuousPlaying = false;

  StreamSubscription<Uint8List>? _streamSubscription;
  StreamController<LiveCaptureFrame>? _frameController;
  Timer? _analyzeTimer;
  final List<double> _liveSamples = [];
  DateTime? _liveStart;

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  /// Starts a live PCM capture and emits periodic [LiveCaptureFrame] updates
  /// containing level meter and rolling pitch estimate.
  Future<Stream<LiveCaptureFrame>> startLiveCapture() async {
    await _disposeStreaming();

    _liveSamples.clear();
    _liveStart = DateTime.now();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _liveSampleRate,
        numChannels: 1,
      ),
    );

    final controller = StreamController<LiveCaptureFrame>.broadcast();
    _frameController = controller;

    _streamSubscription = stream.listen(
      _appendPcm16,
      onError: (_) {},
      cancelOnError: false,
    );

    _analyzeTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final c = _frameController;
      if (c == null || c.isClosed) {
        return;
      }
      final elapsed = _liveStart == null
          ? Duration.zero
          : DateTime.now().difference(_liveStart!);

      if (_liveSamples.isEmpty) {
        c.add(LiveCaptureFrame(
          levelDb: -80,
          estimateHz: null,
          correlation: null,
          elapsed: elapsed,
        ));
        return;
      }

      final length = _liveSamples.length;
      final from = length > _analysisWindow ? length - _analysisWindow : 0;
      final tail = _liveSamples.sublist(from, length);

      double sumSquares = 0;
      for (final s in tail) {
        sumSquares += s * s;
      }
      final rms = math.sqrt(sumSquares / tail.length);
      final levelDb = rms <= 0.000001 ? -80.0 : (20 * math.log(rms) / math.ln10);

      _PitchEstimate? estimate;
      if (tail.length >= 2048 && rms > 0.005) {
        estimate = _estimateFundamental(
          tail,
          _liveSampleRate,
          minFrequencyHz: 60,
          maxFrequencyHz: 2400,
        );
      }

      c.add(LiveCaptureFrame(
        levelDb: levelDb.clamp(-80.0, 0.0),
        estimateHz: estimate?.hz,
        correlation: estimate?.correlation,
        elapsed: elapsed,
      ));
    });

    return controller.stream;
  }

  /// Stops the live capture and returns the final estimate from the full take
  /// along with its normalized autocorrelation strength (0..1).
  Future<({double hz, double correlation})?> stopLiveCapture() async {
    _analyzeTimer?.cancel();
    _analyzeTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {
      // ignore – stop errors should not block analysis
    }

    final c = _frameController;
    _frameController = null;
    if (c != null && !c.isClosed) {
      await c.close();
    }

    final samples = _trimLeadingSilence(_liveSamples, threshold: 0.02);
    _liveSamples.clear();
    if (samples.length < 2048) {
      return null;
    }

    final estimate = _estimateFundamental(
      samples,
      _liveSampleRate,
      minFrequencyHz: 60,
      maxFrequencyHz: 2400,
    );
    if (estimate == null) {
      return null;
    }
    return (hz: estimate.hz, correlation: estimate.correlation);
  }

  /// Plays a short sine tone at [hz] so the operator can audit the chosen
  /// frequency by ear.
  Future<void> playTone(
    double hz, {
    Duration duration = const Duration(milliseconds: 1500),
  }) async {
    if (hz <= 0 || hz.isNaN || hz.isInfinite) {
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/audit_tone_${hz.toStringAsFixed(2)}.wav');
    if (!await file.exists()) {
      final bytes = _buildSineWav(hz, duration);
      await file.writeAsBytes(bytes, flush: true);
    }

    _continuousPlaying = false;
    await _player.stop();
    try {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setPlaybackRate(1.0);
    } catch (_) {}
    await _player.play(DeviceFileSource(file.path));
  }

  /// Starts a seamless looping sine tone whose pitch can be retuned on the fly
  /// via [setContinuousToneHz]. Used by the slider for glitch-free auditioning.
  Future<void> startContinuousTone(double hz) async {
    await _ensureBaseTone();
    if (!_continuousPlaying) {
      try {
        await _player.stop();
      } catch (_) {}
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.5);
      } catch (_) {}
      await _player.play(DeviceFileSource(_continuousToneFile!.path));
      _continuousPlaying = true;
    }
    await setContinuousToneHz(hz);
  }

  /// Retunes the currently-playing continuous tone without restarting it.
  Future<void> setContinuousToneHz(double hz) async {
    if (hz <= 0 || hz.isNaN || hz.isInfinite) {
      return;
    }
    final rate = (hz / _baseToneHz).clamp(0.5, 2.5);
    try {
      await _player.setPlaybackRate(rate);
    } catch (_) {}
  }

  Future<void> stopContinuousTone() async {
    if (!_continuousPlaying) return;
    _continuousPlaying = false;
    try {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setPlaybackRate(1.0);
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _ensureBaseTone() async {
    if (_continuousToneFile != null && await _continuousToneFile!.exists()) {
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/audit_base_tone_${_baseToneHz.toStringAsFixed(0)}.wav',
    );
    if (!await file.exists()) {
      final bytes = _buildLoopableSineWav(
        _baseToneHz,
        const Duration(seconds: 5),
        sampleRate: 48000,
      );
      await file.writeAsBytes(bytes, flush: true);
    }
    _continuousToneFile = file;
  }

  Future<void> stopPlayback() async {
    _continuousPlaying = false;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _disposeStreaming();
    await stopContinuousTone();
    try {
      await _recorder.dispose();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
  }

  Future<void> _disposeStreaming() async {
    _analyzeTimer?.cancel();
    _analyzeTimer = null;
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    final c = _frameController;
    _frameController = null;
    if (c != null && !c.isClosed) {
      await c.close();
    }
  }

  void _appendPcm16(Uint8List chunk) {
    final bd = ByteData.sublistView(chunk);
    for (int i = 0; i + 1 < chunk.length; i += 2) {
      _liveSamples.add(bd.getInt16(i, Endian.little) / 32768.0);
    }
    if (_liveSamples.length > _maxLiveSamples) {
      _liveSamples.removeRange(0, _liveSamples.length - _maxLiveSamples);
    }
  }

  Uint8List _buildSineWav(double hz, Duration duration) {
    const sampleRate = 44100;
    final totalSamples = (sampleRate * duration.inMilliseconds / 1000).round();
    final attack = (sampleRate * 0.02).round();
    final release = (sampleRate * 0.05).round();

    final data = ByteData(totalSamples * 2);
    for (int i = 0; i < totalSamples; i++) {
      double envelope = 1;
      if (i < attack) {
        envelope = i / attack;
      } else if (i > totalSamples - release) {
        envelope = (totalSamples - i) / release;
      }
      final value = math.sin(2 * math.pi * hz * i / sampleRate) * 0.4 * envelope;
      data.setInt16(i * 2, (value * 32767).round().clamp(-32768, 32767), Endian.little);
    }

    final dataBytes = data.buffer.asUint8List();
    final byteRate = sampleRate * 2;
    final header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46); // 'RIFF'
    header.setUint32(4, 36 + dataBytes.length, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45); // 'WAVE'
    header.setUint8(12, 0x66); header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20); // 'fmt '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // channels
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61); // 'data'
    header.setUint32(40, dataBytes.length, Endian.little);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...dataBytes,
    ]);
  }

  /// Builds a click-free, seamlessly-loopable sine WAV. The duration is
  /// rounded so the buffer contains an integer number of cycles at [hz] and
  /// [sampleRate], placing the loop point at a zero-crossing.
  Uint8List _buildLoopableSineWav(
    double hz,
    Duration duration, {
    required int sampleRate,
  }) {
    final samplesPerCycle = sampleRate / hz;
    final approxSamples = (sampleRate * duration.inMilliseconds / 1000).round();
    final cycles = math.max(1, (approxSamples / samplesPerCycle).round());
    final totalSamples = (cycles * samplesPerCycle).round();

    final data = ByteData(totalSamples * 2);
    for (int i = 0; i < totalSamples; i++) {
      final value = math.sin(2 * math.pi * hz * i / sampleRate) * 0.4;
      data.setInt16(
        i * 2,
        (value * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }

    final dataBytes = data.buffer.asUint8List();
    final byteRate = sampleRate * 2;
    final header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46); // 'RIFF'
    header.setUint32(4, 36 + dataBytes.length, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45); // 'WAVE'
    header.setUint8(12, 0x66); header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20); // 'fmt '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // channels
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61); // 'data'
    header.setUint32(40, dataBytes.length, Endian.little);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...dataBytes,
    ]);
  }

  _PitchEstimate? _estimateFundamental(
    List<double> input,
    int sampleRate, {
    required int minFrequencyHz,
    required int maxFrequencyHz,
  }) {
    if (input.length < 2048) {
      return null;
    }

    final n = math.min(input.length, 16384);
    final start = input.length - n;
    final windowed = List<double>.generate(n, (index) {
      final w = 0.5 - 0.5 * math.cos((2 * math.pi * index) / (n - 1));
      return input[start + index] * w;
    });

    final minLag = (sampleRate / maxFrequencyHz).floor().clamp(1, n - 1);
    final maxLag = (sampleRate / minFrequencyHz).floor().clamp(minLag + 1, n - 1);

    double bestCorrelation = -1;
    int bestLag = -1;

    for (int lag = minLag; lag <= maxLag; lag++) {
      double correlation = 0;
      double energyA = 0;
      double energyB = 0;

      for (int i = 0; i < n - lag; i++) {
        final a = windowed[i];
        final b = windowed[i + lag];
        correlation += a * b;
        energyA += a * a;
        energyB += b * b;
      }

      final norm = math.sqrt(energyA * energyB);
      if (norm <= 0) {
        continue;
      }

      final normalized = correlation / norm;
      if (normalized > bestCorrelation) {
        bestCorrelation = normalized;
        bestLag = lag;
      }
    }

    if (bestLag <= 0 || bestCorrelation < 0.2) {
      return null;
    }

    return _PitchEstimate(
      hz: sampleRate / bestLag,
      correlation: bestCorrelation.clamp(0.0, 1.0),
    );
  }

  List<double> _trimLeadingSilence(List<double> input, {required double threshold}) {
    int start = 0;
    while (start < input.length && input[start].abs() < threshold) {
      start++;
    }

    if (start >= input.length) {
      return const [];
    }

    final end = math.min(start + _liveSampleRate, input.length);
    return input.sublist(start, end);
  }
}

class _PitchEstimate {
  const _PitchEstimate({required this.hz, required this.correlation});

  final double hz;
  final double correlation;
}
