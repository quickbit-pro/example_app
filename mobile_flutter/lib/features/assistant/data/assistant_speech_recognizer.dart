import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A factory gives each composer its own cancellable ownership of the shared
/// device recognizer. Creating it never requests microphone permission.
final assistantSpeechRecognizerProvider =
    Provider<AssistantSpeechRecognizer Function()>(
  (ref) => DeviceAssistantSpeechRecognizer.new,
);

abstract class AssistantSpeechRecognizer {
  Future<bool> start({
    required ValueChanged<String> onWords,
    required VoidCallback onDone,
    required VoidCallback onError,
  });

  /// Stops recording and allows the device's final text to arrive.
  Future<void> stop();

  /// Immediately detaches callbacks, then releases the microphone.
  Future<void> cancel();
}

class DeviceAssistantSpeechRecognizer implements AssistantSpeechRecognizer {
  // speech_to_text fixes initialize callbacks for the application lifetime.
  // Keep one native plugin instance and route events to the current owner.
  static final _engine = _SharedSpeechEngine();
  Object? _owner;

  @override
  Future<bool> start({
    required ValueChanged<String> onWords,
    required VoidCallback onDone,
    required VoidCallback onError,
  }) {
    final previous = _owner;
    if (previous != null) {
      unawaited(_engine.cancel(previous).catchError((_) {}));
    }
    final owner = _owner = Object();
    return _engine.start(owner, _SpeechCallbacks(onWords, onDone, onError));
  }

  @override
  Future<void> stop() =>
      _owner == null ? Future.value() : _engine.stop(_owner!);

  @override
  Future<void> cancel() {
    final owner = _owner;
    _owner = null;
    return owner == null ? Future.value() : _engine.cancel(owner);
  }
}

class _SpeechCallbacks {
  _SpeechCallbacks(this.onWords, this.onDone, this.onError);
  final ValueChanged<String> onWords;
  final VoidCallback onDone;
  final VoidCallback onError;
  final finished = Completer<void>();
}

class _SharedSpeechEngine {
  final _speech = SpeechToText();
  Future<void> _queue = Future.value();
  bool _initialized = false;
  Object? _activeOwner;
  Object? _nativeOwner;
  Completer<void>? _nativeEnded;
  bool _draining = false;
  _SpeechCallbacks? _callbacks;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<bool> start(Object owner, _SpeechCallbacks callbacks) {
    _finish();
    _activeOwner = owner;
    _callbacks = callbacks;
    return _serialize(() async {
      if (_activeOwner != owner) return false;
      if (_nativeOwner != null) {
        await _cancelNative();
      }
      if (!_initialized) {
        _initialized = await _speech.initialize(
          onStatus: (status) {
            if (status == SpeechToText.notListeningStatus) {
              final ended = _nativeEnded;
              if (ended != null && !ended.isCompleted) ended.complete();
            }
            // notListening precedes the final transcript; wait for done.
            if (!_draining &&
                _activeOwner != null &&
                _nativeOwner == _activeOwner &&
                status == SpeechToText.doneStatus) {
              _finish();
            }
          },
          onError: (_) {
            final owner = _activeOwner;
            if (_draining || owner == null || _nativeOwner != owner) return;
            _finish(error: true);
            unawaited(cancel(owner).catchError((_) {}));
          },
          // Use the device microphone without requesting Bluetooth access.
          options: [SpeechToText.androidNoBluetooth],
        );
      }
      if (_activeOwner != owner) return false;
      if (!_initialized) {
        _finish(error: true);
        return false;
      }
      _nativeOwner = owner;
      _nativeEnded = Completer<void>();
      try {
        await _speech.listen(
          onResult: (result) {
            if (!_draining && _activeOwner == owner) {
              callbacks.onWords(result.recognizedWords);
            }
          },
          listenOptions: SpeechListenOptions(
            listenFor: const Duration(seconds: 30),
            pauseFor: const Duration(seconds: 4),
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.dictation,
          ),
        );
        return _activeOwner == owner;
      } catch (_) {
        if (_activeOwner == owner) _finish(error: true);
        await _cancelNative();
        return false;
      }
    });
  }

  Future<void> stop(Object owner) => _serialize(() async {
        if (_activeOwner != owner || _nativeOwner != owner) return;
        final callbacks = _callbacks;
        await _speech.stop();
        // Some browsers never report done; always release the session.
        await callbacks?.finished.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
        if (_activeOwner == owner) _finish();
        if (_nativeOwner == owner) {
          await _cancelNative();
        }
      });

  Future<void> cancel(Object owner) {
    if (_activeOwner == owner) _finish();
    return _serialize(() async {
      if (_nativeOwner != owner) return;
      await _cancelNative();
    });
  }

  Future<void> _cancelNative() async {
    _draining = true;
    try {
      await _speech.cancel();
      // Web abort() returns before onend; opening a new session before that
      // event can route the old result/error into the plugin's new listener.
      // Keep ownership detached until a terminal event confirms shutdown.
      await _nativeEnded?.future.timeout(const Duration(seconds: 3));
      // Let terminal events queued by the same native shutdown be delivered.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _nativeOwner = null;
      _nativeEnded = null;
    } finally {
      // A timeout deliberately retains native ownership, so another start
      // cannot proceed until shutdown has actually been confirmed.
      _draining = false;
    }
  }

  void _finish({bool error = false}) {
    final callbacks = _callbacks;
    _activeOwner = null;
    _callbacks = null;
    if (callbacks == null) return;
    if (!callbacks.finished.isCompleted) callbacks.finished.complete();
    if (error) {
      callbacks.onError();
    } else {
      callbacks.onDone();
    }
  }
}
