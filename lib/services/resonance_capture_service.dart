import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
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
  ResonanceCaptureService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final SoLoud _soloud = SoLoud.instance;

  static const int _liveSampleRate = 44100;
  static const int _analysisWindow = 4096;
  static const int _maxLiveSamples = _liveSampleRate * 8;

  // Real-time audition oscillator. A single sine waveform generator plays
  // continuously; changing its frequency with [SoLoud.setWaveformFreq] bends
  // the pitch live and phase-continuously — like pulling a slide whistle — at
  // the EXACT frequency requested. No file playback, no pitch quantization and
  // no gaps, so dragging the slider glides the tone without ever cutting out.
  static const double _toneVolume = 0.6;
  AudioSource? _oscillator;
  SoundHandle? _toneHandle;
  SoundHandle? _previewHandle;
  bool _continuousActive = false;

  /// Whether the continuous audition tone is currently toggled on.
  bool get isContinuousToneActive => _continuousActive;

  bool _validHz(double hz) => hz > 0 && !hz.isNaN && !hz.isInfinite;

  /// Initializes the audio engine (once per process) and lazily creates the
  /// shared sine oscillator used for both the continuous tone and previews.
  Future<void> _ensureEngine() async {
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
    _oscillator ??= await _soloud.loadWaveform(WaveForm.sin, false, 1.0, 0.0);
  }

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

  /// Plays a short comparison tone at [hz] (for take/candidate previews). The
  /// momentary tone takes over the shared oscillator, so any running continuous
  /// audition tone is stopped first.
  Future<void> playTone(
    double hz, {
    Duration duration = const Duration(milliseconds: 1500),
  }) async {
    if (!_validHz(hz)) {
      return;
    }
    await stopContinuousTone();
    try {
      await _ensureEngine();
      final osc = _oscillator!;
      _soloud.setWaveformFreq(osc, hz);

      final previous = _previewHandle;
      if (previous != null && _soloud.getIsValidVoiceHandle(previous)) {
        await _soloud.stop(previous);
      }

      final handle = await _soloud.play(osc, volume: _toneVolume);
      _previewHandle = handle;
      _soloud.scheduleStop(handle, duration);
    } catch (error) {
      developer.log(
        'Failed to play preview tone at ${hz.toStringAsFixed(1)} Hz: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  /// Turns the continuous audition tone on and starts the sine oscillator at
  /// [hz]. Call [updateContinuousTone] while dragging to bend the pitch and
  /// [stopContinuousTone] to turn it off.
  Future<void> startContinuousTone(double hz) async {
    if (!_validHz(hz)) {
      return;
    }
    _continuousActive = true;
    try {
      await _ensureEngine();
      final osc = _oscillator!;
      _soloud.setWaveformFreq(osc, hz);

      final handle = _toneHandle;
      if (handle == null || !_soloud.getIsValidVoiceHandle(handle)) {
        _toneHandle = await _soloud.play(osc, volume: _toneVolume);
      }
    } catch (error) {
      developer.log(
        'Failed to start audition tone at ${hz.toStringAsFixed(1)} Hz: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  /// Bends the running audition tone to the EXACT [hz] in real time. For a
  /// waveform oscillator this is instantaneous and phase-continuous, so the
  /// pitch glides smoothly with the slider and never cuts out. Does nothing if
  /// the tone is toggled off.
  Future<void> updateContinuousTone(double hz) async {
    if (!_continuousActive || !_validHz(hz)) {
      return;
    }
    final osc = _oscillator;
    if (osc == null) {
      return;
    }
    try {
      _soloud.setWaveformFreq(osc, hz);
      // If the voice was lost (e.g. an audio interruption), restart it.
      final handle = _toneHandle;
      if (handle == null || !_soloud.getIsValidVoiceHandle(handle)) {
        _toneHandle = await _soloud.play(osc, volume: _toneVolume);
      }
    } catch (error) {
      developer.log(
        'Failed to retune audition tone to ${hz.toStringAsFixed(1)} Hz: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  Future<void> stopContinuousTone() async {
    _continuousActive = false;
    final handle = _toneHandle;
    _toneHandle = null;
    if (handle == null) {
      return;
    }
    try {
      if (_soloud.getIsValidVoiceHandle(handle)) {
        await _soloud.stop(handle);
      }
    } catch (error) {
      developer.log(
        'Failed to stop continuous tone cleanly: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  Future<void> stopPlayback() async {
    await stopContinuousTone();
    final preview = _previewHandle;
    _previewHandle = null;
    if (preview == null) {
      return;
    }
    try {
      if (_soloud.getIsValidVoiceHandle(preview)) {
        await _soloud.stop(preview);
      }
    } catch (error) {
      developer.log(
        'Failed to stop playback: $error',
        name: 'ResonanceCaptureService',
      );
    }
  }

  Future<void> dispose() async {
    await _disposeStreaming();
    await stopPlayback();
    final osc = _oscillator;
    _oscillator = null;
    if (osc != null) {
      try {
        await _soloud.disposeSource(osc);
      } catch (error) {
        developer.log(
          'Failed to dispose oscillator: $error',
          name: 'ResonanceCaptureService',
        );
      }
    }
    try {
      await _recorder.dispose();
    } catch (error) {
      developer.log(
        'Failed to dispose recorder: $error',
        name: 'ResonanceCaptureService',
      );
    }
    // The SoLoud engine is a process-wide singleton reused by the next capture
    // sheet, so it is intentionally not deinitialized here.
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
