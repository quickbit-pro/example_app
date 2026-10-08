import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_speech_recognizer.dart';
// Exercise the exact transitive platform used by the production plugin.
// ignore: depend_on_referenced_packages
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

class _DelayedSpeechPlatform extends SpeechToTextPlatform {
  int initializations = 0;
  int listens = 0;
  int cancels = 0;

  @override
  Future<bool> initialize(
      {debugLogging = false, List<SpeechConfigOption>? options}) async {
    initializations++;
    return true;
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listens++;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  void emitWords(String words) => onTextRecognition?.call(jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'confidence': 1.0}
        ],
        'resultType': 0,
      }));
}

void main() {
  testWidgets('shared native recognizer drains old session before new listener',
      (tester) async {
    final platform = _DelayedSpeechPlatform();
    final previous = SpeechToTextPlatform.instance;
    SpeechToTextPlatform.instance = platform;
    addTearDown(() => SpeechToTextPlatform.instance = previous);
    final first = DeviceAssistantSpeechRecognizer();
    final second = DeviceAssistantSpeechRecognizer();
    final firstWords = <String>[];
    final secondWords = <String>[];
    var secondErrors = 0;
    expect(platform.initializations, 0);
    await first.start(onWords: firstWords.add, onDone: () {}, onError: () {});
    expect(platform.initializations, 1);

    final cancelling = first.cancel();
    final restarting = second.start(
      onWords: secondWords.add,
      onDone: () {},
      onError: () => secondErrors++,
    );
    await tester.pump();
    expect(platform.listens, 1);
    platform.emitWords('late old transcript');
    // Web can emit done before its actual onend/notListening event.
    platform.onStatus?.call('doneNoResult');
    await tester.pump(const Duration(milliseconds: 200));
    expect(platform.listens, 1);
    expect(secondWords, isEmpty);
    expect(secondErrors, 0);
    platform.onStatus?.call('notListening');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await cancelling;
    expect(await restarting, true);
    expect(platform.listens, 2);
    expect(platform.initializations, 1);
    platform.emitWords('new session');
    expect(firstWords, isEmpty);
    expect(secondWords, ['new session']);

    // If native shutdown never completes, fail closed instead of allowing
    // callbacks or audio from an uncertain previous session into a new one.
    // Reusing the same adapter starts a fire-and-forget cancellation first.
    // Its timeout must be handled, as must the subsequent start timeout.
    final blockedStart =
        second.start(onWords: (_) {}, onDone: () {}, onError: () {});
    final startFailed =
        expectLater(blockedStart, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await startFailed;
    expect(platform.listens, 2);
    final detachThird = second.cancel();
    await tester.pump();
    await detachThird;
    platform.onStatus?.call('notListening');
    final third = DeviceAssistantSpeechRecognizer();
    final recovery = third.start(onWords: (_) {}, onDone: () {}, onError: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(await recovery, true);
    final cleanup = third.cancel();
    await tester.pump();
    platform.onStatus?.call('notListening');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await cleanup;
  });
}
