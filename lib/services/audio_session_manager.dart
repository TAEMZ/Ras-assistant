import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum AudioCaptureState {
  idle,
  listening,
  speechDetected,
  finalizing,
  error,
}

class AudioSessionManager {
  AudioRecorder _recorder = AudioRecorder();
  Timer? _pollingTimer;

  final ValueNotifier<double> audioLevelNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<AudioCaptureState> captureStateNotifier =
      ValueNotifier<AudioCaptureState>(AudioCaptureState.idle);

  String? _currentRecordingPath;
  bool _isDisposed = false;

  bool _speechDetectedInTurn = false;
  int _consecutiveSpeechTicks = 0;
  int _consecutiveSilenceTicks = 0;
  int _totalDurationTicks = 0;
  bool _isFinalizing = false;

  void Function(Float32List audioSamples)? onUtteranceComplete;
  void Function()? onTurnRecycled;
  void Function(String error)? onError;

  bool get isRecording => captureStateNotifier.value == AudioCaptureState.listening ||
      captureStateNotifier.value == AudioCaptureState.speechDetected;

  Future<bool> startListening() async {
    if (_isDisposed || _isFinalizing) return false;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        captureStateNotifier.value = AudioCaptureState.error;
        onError?.call('Microphone permission not granted');
        return false;
      }

      // Defensive cleanup: Ensure any previous hardware session is cleanly closed
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {
        // If native recorder instance was corrupted, cleanly recreate it
        try {
          await _recorder.dispose();
        } catch (_) {}
        _recorder = AudioRecorder();
      }

      // Explicit short cooldown for Android HAL hardware buffer release
      await Future.delayed(const Duration(milliseconds: 150));

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/ras_turn_$timestamp.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _speechDetectedInTurn = false;
      _consecutiveSpeechTicks = 0;
      _consecutiveSilenceTicks = 0;
      _totalDurationTicks = 0;
      _isFinalizing = false;

      captureStateNotifier.value = AudioCaptureState.listening;
      audioLevelNotifier.value = 0.0;

      _startVADPollingLoop();
      return true;
    } catch (e) {
      debugPrint('[AudioSessionManager] Start error: $e. Re-initializing recorder...');
      try {
        await _recorder.dispose();
      } catch (_) {}
      _recorder = AudioRecorder();
      captureStateNotifier.value = AudioCaptureState.error;
      onError?.call('Hardware audio reset: $e');
      return false;
    }
  }

  void _startVADPollingLoop() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isDisposed || !isRecording || _isFinalizing) {
        timer.cancel();
        return;
      }

      _totalDurationTicks++;

      try {
        final amp = await _recorder.getAmplitude();
        final currentDb = amp.current;

        // Convert dBFS (-55 dB to 0 dB) to normalized 0.0 to 1.0 for the UI visualizer
        double normalized = 0.0;
        if (currentDb > -55.0) {
          normalized = ((currentDb + 55.0) / 40.0).clamp(0.0, 1.0);
        }

        // Smooth decaying level output for liquid visualizer
        final currentLevel = audioLevelNotifier.value;
        audioLevelNotifier.value = normalized > currentLevel
            ? normalized
            : math.max(0.0, currentLevel * 0.70 + normalized * 0.30);

        // VAD Speech Threshold: -30.0 dBFS (requires deliberate near-mic voice, filters ambient room noise)
        if (currentDb > -30.0) {
          _consecutiveSpeechTicks++;
          // Require 3 consecutive ticks (300ms) of sustained vocal energy to qualify as real speech
          if (_consecutiveSpeechTicks >= 3 && !_speechDetectedInTurn) {
            _speechDetectedInTurn = true;
            captureStateNotifier.value = AudioCaptureState.speechDetected;
          }
          _consecutiveSilenceTicks = 0;
        } else {
          // If speech was never qualified, reset burst counter (filters out 100ms clicks/taps)
          if (!_speechDetectedInTurn) {
            _consecutiveSpeechTicks = 0;
          } else {
            _consecutiveSilenceTicks++;
            // 8 ticks * 100ms = 800ms of conversational trailing silence
            if (_consecutiveSilenceTicks >= 8) {
              timer.cancel();
              await stopAndFinalize();
              return;
            }
          }
        }

        // Watchdog 1: Max speech duration of 5.5 seconds (55 ticks)
        if (_speechDetectedInTurn && _totalDurationTicks >= 55) {
          timer.cancel();
          await stopAndFinalize();
          return;
        }

        // Watchdog 2: After 8 seconds of silence with no speech detected, recycle turn cleanly
        if (!_speechDetectedInTurn && _totalDurationTicks >= 80) {
          timer.cancel();
          await stopAndFinalize(recycleWithoutProcessing: true);
          return;
        }
      } catch (e) {
        debugPrint('[AudioSessionManager] Polling warning: $e');
      }
    });
  }

  Future<void> stopAndFinalize({bool recycleWithoutProcessing = false}) async {
    if (_isFinalizing) return;
    _isFinalizing = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    captureStateNotifier.value = AudioCaptureState.finalizing;
    audioLevelNotifier.value = 0.0;

    String? recordingPath;
    try {
      recordingPath = await _recorder.stop();
    } catch (e) {
      debugPrint('[AudioSessionManager] Stop warning: $e');
    }

    final targetPath = recordingPath ?? _currentRecordingPath;
    if (recycleWithoutProcessing || targetPath == null || !_speechDetectedInTurn) {
      _cleanFile(targetPath);
      _isFinalizing = false;
      captureStateNotifier.value = AudioCaptureState.idle;
      onTurnRecycled?.call();
      return;
    }

    try {
      final file = File(targetPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _cleanFile(targetPath);

        final samples = _extractWavSamples(bytes);
        _isFinalizing = false;
        captureStateNotifier.value = AudioCaptureState.idle;

        // Require at least 0.35s (5600 samples at 16kHz)
        if (samples.length >= 5600) {
          onUtteranceComplete?.call(samples);
        } else {
          onTurnRecycled?.call();
        }
      } else {
        _isFinalizing = false;
        captureStateNotifier.value = AudioCaptureState.idle;
        onTurnRecycled?.call();
      }
    } catch (e) {
      debugPrint('[AudioSessionManager] Extraction error: $e');
      _cleanFile(targetPath);
      _isFinalizing = false;
      captureStateNotifier.value = AudioCaptureState.idle;
      onTurnRecycled?.call();
    }
  }

  void _cleanFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  Float32List _extractWavSamples(Uint8List wavBytes) {
    if (wavBytes.length < 44) return Float32List(0);

    int dataOffset = 44;
    for (int i = 12; i < wavBytes.length - 8; i++) {
      if (wavBytes[i] == 0x64 &&
          wavBytes[i + 1] == 0x61 &&
          wavBytes[i + 2] == 0x74 &&
          wavBytes[i + 3] == 0x61) {
        dataOffset = i + 8;
        break;
      }
    }

    if (dataOffset >= wavBytes.length) return Float32List(0);

    final pcmBytes = wavBytes.sublist(dataOffset);
    final numSamples = pcmBytes.length ~/ 2;
    if (numSamples == 0) return Float32List(0);

    final samples = Float32List(numSamples);
    final byteData = ByteData.sublistView(pcmBytes);

    for (int i = 0; i < numSamples; i++) {
      final sample16 = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sample16 / 32768.0;
    }
    return samples;
  }

  Future<void> cancel() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isFinalizing = false;
    audioLevelNotifier.value = 0.0;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    _cleanFile(_currentRecordingPath);
    captureStateNotifier.value = AudioCaptureState.idle;
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    audioLevelNotifier.dispose();
    captureStateNotifier.dispose();
    try {
      await _recorder.dispose();
    } catch (_) {}
    _cleanFile(_currentRecordingPath);
  }
}
