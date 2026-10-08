import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/assistant_speech_recognizer.dart';

enum _DictationState { idle, starting, listening, stopping }

/// Dictation edits a draft only. It never sends a request or consumes AI quota.
class AssistantDictationController extends ChangeNotifier {
  AssistantDictationController({
    required this.onDraft,
    required AssistantSpeechRecognizer recognizer,
  }) : _recognizer = recognizer;

  final ValueChanged<String> onDraft;
  final AssistantSpeechRecognizer _recognizer;
  _DictationState _state = _DictationState.idle;
  Timer? _deadline;
  int _generation = 0;
  bool _disposed = false;
  String? _hint;

  bool get isStarting => _state == _DictationState.starting;
  bool get isListening => _state == _DictationState.listening;
  bool get isStopping => _state == _DictationState.stopping;
  bool get isActive => _state != _DictationState.idle;
  String? get hint => _hint;

  Future<void> start({required String draft, int maxCharacters = 1500}) async {
    if (_disposed || isActive) return;
    final limit = maxCharacters.clamp(1, 1500);
    if (draft.length >= limit) {
      _hint = 'Your message is full. Shorten it before using voice input.';
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    final prefix =
        draft.isEmpty || RegExp(r'\s$').hasMatch(draft) ? draft : '$draft ';
    _state = _DictationState.starting;
    _hint = 'Starting voice input…';
    notifyListeners();
    try {
      final available = await _recognizer.start(
        onWords: (words) {
          if (!_isCurrent(generation) || words.trim().isEmpty) return;
          final combined = '$prefix${words.trim()}';
          final capped = _truncate(combined, limit);
          onDraft(capped);
          if (!_isCurrent(generation)) return;
          if (combined.length >= limit) {
            unawaited(cancel());
            _hint = 'Message limit reached. Review your text before sending.';
            notifyListeners();
          }
        },
        onDone: () => _finish(generation),
        onError: () => _finish(generation, error: true),
      );
      if (!_isCurrent(generation)) return;
      if (!available) {
        _finish(generation, error: true);
      } else if (_state == _DictationState.starting) {
        _state = _DictationState.listening;
        _hint = 'Listening… Tap stop when you are done.';
        // Independent guard even if a browser ignores the plugin time limit.
        _deadline = Timer(const Duration(seconds: 30), () {
          if (_isCurrent(generation)) unawaited(stop());
        });
        notifyListeners();
      }
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _finish(generation, error: true);
      await _cancelSafely();
    }
  }

  Future<void> stop() async {
    if (_disposed || !isActive || isStopping) return;
    if (isStarting) return cancel();
    final generation = _generation;
    _deadline?.cancel();
    _state = _DictationState.stopping;
    _hint = 'Finishing voice input…';
    notifyListeners();
    try {
      await _recognizer.stop();
      _finish(generation);
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _finish(generation, error: true);
      await _cancelSafely();
    }
  }

  Future<void> cancel() async {
    _generation++;
    _deadline?.cancel();
    _deadline = null;
    _state = _DictationState.idle;
    _hint = null;
    if (!_disposed) notifyListeners();
    await _cancelSafely();
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && isActive;

  void _finish(int generation, {bool error = false}) {
    if (!_isCurrent(generation)) return;
    _deadline?.cancel();
    _deadline = null;
    _state = _DictationState.idle;
    _hint = error
        ? 'Voice input is unavailable. You can type or use your keyboard microphone.'
        : 'Review your text, then tap send.';
    notifyListeners();
  }

  Future<void> _cancelSafely() async {
    try {
      await _recognizer.cancel();
    } catch (_) {
      // Typing stays available even if the device speech service fails.
    }
  }

  static String _truncate(String text, int maxCharacters) {
    if (text.length <= maxCharacters) return text;
    var end = maxCharacters;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return text.substring(0, end);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
