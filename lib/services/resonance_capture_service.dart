import 'dart:async';
import 'dart:developer' as developer;
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

class ResonanceCandidate {
  const ResonanceCandidate({
    required this.hz,
    required this.score,
    required this.label,
  });

  final double hz;
  final double score; // 0..1
  final String label;
}

class ResonanceCaptureResult {
  const ResonanceCaptureResult({
    required this.hz,
    required this.correlation,
    required this.candidates,
  });

  final double hz;
  final double correlation;
  final List<ResonanceCandidate> candidates;
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

  // Continuous audition tone: we generate a seamlessly-looping sine at the
  // EXACT requested frequency and play it on loop. This guarantees the pitch
  // you hear matches the displayed frequency (audioplayers' setPlaybackRate is
  // unreliable for pitch on iOS, which previously caused mismatches).
  static const int _toneSampleRate = 44100;
  bool _continuousPlaying = false;
  Future<void> _playbackSerial = Future<void>.value();
  final Map<int, File> _toneFileCache = {};
  int? _currentAuditionKey;
  double? _pendingAuditionHz;
  bool _isApplyingAudition = false;
  bool _auditionActive = false;
  int _auditionGeneration = 0;

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
      onError: (error) {
        developer.log(
          'Live capture stream error: $error',
          name: 'ResonanceCaptureService',
        );
      },
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
  Future<ResonanceCaptureResult?> stopLiveCapture() async {
    _analyzeTimer?.cancel();
    _analyzeTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _recorder.stop();
    } catch (error) {
      developer.log(
        'Recorder stop error during analysis: $error',
        name: 'ResonanceCaptureService',
      );
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

    final result = _analyzeResonanceCandidates(samples, _liveSampleRate);
    if (result == null) {
      return null;
    }
    return result;
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
    try {
      await _player.stop();
    } catch (error) {
      developer.log(
        'Failed to stop player before short tone: $error',
        name: 'ResonanceCaptureService',
      );
    }
    try {
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setPlaybackRate(1.0);
    } catch (error) {
      developer.log(
        'Failed to configure player for short tone: $error',
        name: 'ResonanceCaptureService',
      );
    }
    try {
      await _player.play(DeviceFileSource(file.path));
    } catch (error) {
      developer.log(
        'Failed to play short tone at ${hz.toStringAsFixed(1)} Hz: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  /// Starts (or retunes) a seamless looping sine tone at the EXACT [hz] so the
  /// slider audition always matches the displayed frequency. Rapid updates are
  /// coalesced so dragging stays responsive without audio cutting out.
  Future<void> auditionToneHz(double hz) async {
    if (hz <= 0 || hz.isNaN || hz.isInfinite) {
      return;
    }
    _auditionActive = true;
    final generation = _auditionGeneration;
    _pendingAuditionHz = hz;
    if (_isApplyingAudition) {
      return;
    }

    _isApplyingAudition = true;
    try {
      while (_pendingAuditionHz != null && _auditionActive && generation == _auditionGeneration) {
        final next = _pendingAuditionHz!;
        _pendingAuditionHz = null;
        await _applyAudition(next, generation);
      }
    } finally {
      _isApplyingAudition = false;
    }
  }

  Future<void> _applyAudition(double hz, int generation) async {
    if (!_auditionActive || generation != _auditionGeneration) {
      return;
    }

    final key = hz.round();
    if (_currentAuditionKey == key && _continuousPlaying) {
      return;
    }

    final File file;
    try {
      file = await _ensureToneFile(key.toDouble());
    } catch (error) {
      developer.log(
        'Failed to prepare audition tone for $key Hz: $error',
        name: 'ResonanceCaptureService',
      );
      return;
    }

    if (!_auditionActive || generation != _auditionGeneration) {
      return;
    }

    try {
      if (!_continuousPlaying) {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.6);
        await _player.setPlaybackRate(1.0);
      }

      if (!_auditionActive || generation != _auditionGeneration) {
        return;
      }

      await _player.play(DeviceFileSource(file.path));

      if (!_auditionActive || generation != _auditionGeneration) {
        try {
          await _player.stop();
        } catch (_) {}
        return;
      }

      _continuousPlaying = true;
      _currentAuditionKey = key;
    } catch (error) {
      developer.log(
        'Failed to play audition tone at $key Hz: $error',
        name: 'ResonanceCaptureService',
      );
      _continuousPlaying = false;
      _currentAuditionKey = null;
    }
  }

  Future<void> stopContinuousTone() async {
    _auditionActive = false;
    _auditionGeneration++;
    _pendingAuditionHz = null;
    await _serializePlayback(() async {
      if (!_continuousPlaying) return;
      _continuousPlaying = false;
      _currentAuditionKey = null;
      try {
        await _player.setReleaseMode(ReleaseMode.release);
        await _player.stop();
      } catch (error) {
        developer.log(
          'Failed to stop continuous tone cleanly: $error',
          name: 'ResonanceCaptureService',
        );
      }
    });
  }

  Future<File> _ensureToneFile(double hz) async {
    final key = hz.round();
    final cached = _toneFileCache[key];
    if (cached != null && await cached.exists()) {
      return cached;
    }
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/audit_loop_${key}hz.wav');
    if (!await file.exists()) {
      final bytes = _buildLoopableSineWav(
        key.toDouble(),
        const Duration(milliseconds: 400),
        sampleRate: _toneSampleRate,
      );
      await file.writeAsBytes(bytes, flush: true);
    }
    _toneFileCache[key] = file;
    return file;
  }

  Future<void> stopPlayback() async {
    _auditionActive = false;
    _auditionGeneration++;
    _continuousPlaying = false;
    _pendingAuditionHz = null;
    try {
      await _player.stop();
    } catch (error) {
      developer.log(
        'Failed to stop playback: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  Future<void> dispose() async {
    await _disposeStreaming();
    await stopContinuousTone();
    try {
      await _recorder.dispose();
    } catch (error) {
      developer.log(
        'Failed to dispose recorder: $error',
        name: 'ResonanceCaptureService',
      );
    }
    try {
      await _player.dispose();
    } catch (error) {
      developer.log(
        'Failed to dispose player: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  Future<void> _serializePlayback(Future<void> Function() action) {
    _playbackSerial = _playbackSerial
        .catchError((_) {})
        .then((_) => action());
    return _playbackSerial;
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
    const sampleRate = _toneSampleRate;
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

  ResonanceCaptureResult? _analyzeResonanceCandidates(
    List<double> samples,
    int sampleRate,
  ) {
    if (samples.length < 2048) {
      return null;
    }

    final trimmed = _trimLeadingSilence(samples, threshold: 0.02);
    if (trimmed.length < 2048) {
      return null;
    }

    final analysis = _selectSteadyWindow(trimmed, sampleRate);
    if (analysis.length < 2048) {
      return null;
    }

    final spectralCandidates = _findSpectralCandidates(
      analysis,
      sampleRate,
      minHz: 900,
      maxHz: 2000,
      stepHz: 5,
      top: 7,
    );
    final acCandidates = _findAutocorrelationCandidates(
      analysis,
      sampleRate,
      minFrequencyHz: 900,
      maxFrequencyHz: 2000,
      top: 5,
    );

    final merged = _mergeCandidates(
      spectralCandidates: spectralCandidates,
      acCandidates: acCandidates,
      top: 5,
    );
    if (merged.isEmpty) {
      return null;
    }

    final strongest = merged.first;
    return ResonanceCaptureResult(
      hz: strongest.hz,
      correlation: strongest.score,
      candidates: merged,
    );
  }

  List<double> _selectSteadyWindow(List<double> input, int sampleRate) {
    final skipSamples = (sampleRate * 0.10).round();
    final windowSamples = (sampleRate * 0.25).round();
    if (input.length <= skipSamples + 2048) {
      return input;
    }

    final from = math.min(skipSamples, input.length - 2048);
    final to = math.min(from + windowSamples, input.length);
    return input.sublist(from, to);
  }

  List<ResonanceCandidate> _findSpectralCandidates(
    List<double> input,
    int sampleRate, {
    required double minHz,
    required double maxHz,
    required double stepHz,
    required int top,
  }) {
    final n = math.min(input.length, 8192);
    if (n < 1024) {
      return const [];
    }

    final start = input.length - n;
    final windowed = List<double>.generate(n, (index) {
      final w = 0.5 - 0.5 * math.cos((2 * math.pi * index) / (n - 1));
      return input[start + index] * w;
    });

    final bins = <_SpectralBin>[];
    for (double hz = minHz; hz <= maxHz; hz += stepHz) {
      final mag = _magnitudeAtFrequency(windowed, sampleRate, hz);
      bins.add(_SpectralBin(hz: hz, magnitude: mag));
    }

    if (bins.length < 3) {
      return const [];
    }

    final localPeaks = <_SpectralBin>[];
    for (int i = 1; i < bins.length - 1; i++) {
      final prev = bins[i - 1];
      final curr = bins[i];
      final next = bins[i + 1];
      if (curr.magnitude > prev.magnitude && curr.magnitude > next.magnitude) {
        localPeaks.add(curr);
      }
    }

    localPeaks.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    if (localPeaks.isEmpty) {
      return const [];
    }

    final peakRef = localPeaks.first.magnitude <= 0 ? 1.0 : localPeaks.first.magnitude;
    return localPeaks.take(top).map((peak) {
      final harmonicScore = _harmonicConsistency(windowed, sampleRate, peak.hz);
      final spectralScore = (peak.magnitude / peakRef).clamp(0.0, 1.0);
      return ResonanceCandidate(
        hz: peak.hz,
        score: (spectralScore * 0.7 + harmonicScore * 0.3).clamp(0.0, 1.0),
        label: 'spectral',
      );
    }).toList();
  }

  double _magnitudeAtFrequency(List<double> samples, int sampleRate, double hz) {
    double real = 0;
    double imag = 0;
    final omega = 2 * math.pi * hz / sampleRate;
    for (int i = 0; i < samples.length; i++) {
      final angle = omega * i;
      final value = samples[i];
      real += value * math.cos(angle);
      imag -= value * math.sin(angle);
    }
    return math.sqrt(real * real + imag * imag);
  }

  double _harmonicConsistency(List<double> samples, int sampleRate, double fundamental) {
    if (fundamental <= 0) {
      return 0;
    }
    final m1 = _magnitudeAtFrequency(samples, sampleRate, fundamental);
    if (m1 <= 1e-9) {
      return 0;
    }
    final m2 = _magnitudeAtFrequency(samples, sampleRate, fundamental * 2);
    final m3 = _magnitudeAtFrequency(samples, sampleRate, fundamental * 3);
    final ratio = ((m2 + m3) / (2 * m1)).clamp(0.0, 1.0);
    return ratio;
  }

  List<ResonanceCandidate> _findAutocorrelationCandidates(
    List<double> input,
    int sampleRate, {
    required int minFrequencyHz,
    required int maxFrequencyHz,
    required int top,
  }) {
    final n = math.min(input.length, 8192);
    if (n < 2048) {
      return const [];
    }

    final start = input.length - n;
    final windowed = List<double>.generate(n, (index) {
      final w = 0.5 - 0.5 * math.cos((2 * math.pi * index) / (n - 1));
      return input[start + index] * w;
    });

    final minLag = (sampleRate / maxFrequencyHz).floor().clamp(1, n - 1);
    final maxLag = (sampleRate / minFrequencyHz).floor().clamp(minLag + 1, n - 1);

    final peaks = <_AcfPeak>[];
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
      if (norm <= 1e-9) {
        continue;
      }

      final normalized = correlation / norm;
      peaks.add(_AcfPeak(lag: lag, correlation: normalized));
    }

    if (peaks.length < 3) {
      return const [];
    }

    final localPeaks = <_AcfPeak>[];
    for (int i = 1; i < peaks.length - 1; i++) {
      final prev = peaks[i - 1];
      final curr = peaks[i];
      final next = peaks[i + 1];
      if (curr.correlation > prev.correlation && curr.correlation > next.correlation) {
        localPeaks.add(curr);
      }
    }

    localPeaks.sort((a, b) => b.correlation.compareTo(a.correlation));
    return localPeaks.take(top).map((peak) {
      final hz = sampleRate / peak.lag;
      return ResonanceCandidate(
        hz: hz,
        score: peak.correlation.clamp(0.0, 1.0),
        label: 'autocorrelation',
      );
    }).toList();
  }

  List<ResonanceCandidate> _mergeCandidates({
    required List<ResonanceCandidate> spectralCandidates,
    required List<ResonanceCandidate> acCandidates,
    required int top,
  }) {
    final all = <ResonanceCandidate>[
      ...spectralCandidates,
      ...acCandidates,
    ].where((candidate) => candidate.hz >= 900 && candidate.hz <= 2000).toList();

    if (all.isEmpty) {
      return const [];
    }

    all.sort((a, b) => a.hz.compareTo(b.hz));
    const toleranceHz = 12.0;

    final clusters = <List<ResonanceCandidate>>[];
    for (final candidate in all) {
      if (clusters.isEmpty) {
        clusters.add([candidate]);
        continue;
      }
      final lastCluster = clusters.last;
      final center =
          lastCluster.fold<double>(0, (sum, c) => sum + c.hz) / lastCluster.length;
      if ((candidate.hz - center).abs() <= toleranceHz) {
        lastCluster.add(candidate);
      } else {
        clusters.add([candidate]);
      }
    }

    final merged = clusters.map((cluster) {
      final scoreWeight = cluster.fold<double>(0, (sum, c) => sum + c.score);
      final safeWeight = scoreWeight <= 1e-9 ? cluster.length.toDouble() : scoreWeight;
      final weightedHz = cluster.fold<double>(
            0,
            (sum, c) => sum + c.hz * (c.score <= 1e-9 ? 1 : c.score),
          ) /
          safeWeight;

      final spectralBoost = cluster.where((c) => c.label == 'spectral').length * 0.10;
      final acBoost = cluster.where((c) => c.label == 'autocorrelation').length * 0.08;
      final confidence = (scoreWeight / cluster.length + spectralBoost + acBoost)
          .clamp(0.0, 1.0);

      return ResonanceCandidate(
        hz: weightedHz,
        score: confidence,
        label: 'merged',
      );
    }).toList();

    merged.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.hz.compareTo(b.hz);
    });

    return merged.take(top).toList();
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

class _SpectralBin {
  const _SpectralBin({required this.hz, required this.magnitude});

  final double hz;
  final double magnitude;
}

class _AcfPeak {
  const _AcfPeak({required this.lag, required this.correlation});

  final int lag;
  final double correlation;
}
