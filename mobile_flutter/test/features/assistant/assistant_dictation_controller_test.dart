import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_speech_recognizer.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_dictation_controller.dart';

class FakeSpeechRecognizer implements AssistantSpeechRecognizer {
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  bool available = true;
  Completer<bool>? pendingStart;
  ValueChanged<String>? words;
  VoidCallback? done;
  VoidCallback? error;

  @override
  Future<bool> start({
    required ValueChanged<String> onWords,
    required VoidCallback onDone,
    required VoidCallback onError,
  }) async {
    starts++;
    words = onWords;
    done = onDone;
    error = onError;
    return pendingStart == null ? available : await pendingStart!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    done?.call();
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

void main() {
  late FakeSpeechRecognizer recognizer;
  late AssistantDictationController voice;
  late List<String> drafts;

  setUp(() {
    recognizer = FakeSpeechRecognizer();
    drafts = [];
    voice = AssistantDictationController(
      recognizer: recognizer,
      onDraft: drafts.add,
    );
  });

  tearDown(() => voice.dispose());

  test('creating the controller does not activate speech or ask permission',
      () {
    expect(recognizer.starts, 0);
    expect(voice.isActive, false);
    expect(voice.hint, isNull);
  });

  test('partial transcripts replace dictated suffix and retain typed draft',
      () async {
    await voice.start(draft: 'Find a hotel');
    expect(voice.isListening, true);
    recognizer.words!('in');
    recognizer.words!('in Paris');
    expect(drafts, ['Find a hotel in', 'Find a hotel in Paris']);
    expect(recognizer.starts, 1);
    await voice.stop();
    expect(voice.isActive, false);
    expect(voice.hint, 'Review your text, then tap send.');
  });

  test('empty speech leaves the existing draft untouched', () async {
    await voice.start(draft: 'Weekend trip ');
    recognizer.words!('   ');
    expect(drafts, isEmpty);
    recognizer.words!('to London');
    expect(drafts.single, 'Weekend trip to London');
  });

  test('unavailable device or denied permission keeps typing available',
      () async {
    recognizer.available = false;
    await voice.start(draft: 'Existing draft');
    expect(voice.isActive, false);
    expect(voice.hint, contains('You can type'));
    expect(drafts, isEmpty);
  });

  test('recognizer errors end listening without leaking device errors',
      () async {
    await voice.start(draft: '');
    recognizer.error!();
    expect(voice.isActive, false);
    expect(voice.hint, contains('keyboard microphone'));
    recognizer.words!('late text');
    expect(drafts, isEmpty);
  });

  test('full drafts do not request microphone permission', () async {
    await voice.start(draft: 'abc', maxCharacters: 3);
    expect(recognizer.starts, 0);
    expect(voice.hint, contains('Shorten it'));
  });

  test('dictation respects UTF-16 limit without splitting surrogate pair',
      () async {
    await voice.start(draft: '', maxCharacters: 4);
    recognizer.words!('abc😀long');
    expect(drafts.single, 'abc');
    expect(drafts.single.length, lessThanOrEqualTo(4));
    expect(voice.isActive, false);
    expect(recognizer.cancels, 1);
    expect(voice.hint, contains('Message limit reached'));
  });

  test('server limit cannot exceed the 1500 character client ceiling',
      () async {
    await voice.start(draft: '', maxCharacters: 5000);
    recognizer.words!('x' * 1700);
    expect(drafts.single.length, 1500);
    expect(voice.isActive, false);
  });

  test('cancel during permission prompt prevents late start and transcript',
      () async {
    recognizer.pendingStart = Completer<bool>();
    final starting = voice.start(draft: '');
    expect(voice.isStarting, true);
    await voice.cancel();
    recognizer.pendingStart!.complete(true);
    await starting;
    recognizer.words!('late result');
    expect(voice.isActive, false);
    expect(drafts, isEmpty);
    expect(recognizer.cancels, 1);
  });

  test('old callbacks after a new conversation cannot overwrite new draft',
      () async {
    await voice.start(draft: 'old');
    final staleWords = recognizer.words!;
    final staleDone = recognizer.done!;
    final staleError = recognizer.error!;
    await voice.cancel();
    await voice.start(draft: 'new');
    staleWords('incorrect');
    staleDone();
    staleError();
    expect(voice.isListening, true);
    recognizer.words!('Paris');
    expect(drafts, ['new Paris']);
  });

  test('failed old startup cannot cancel a newer listening session', () async {
    final pending = recognizer.pendingStart = Completer<bool>();
    final oldStart = voice.start(draft: 'old');
    await voice.cancel();
    recognizer.pendingStart = null;
    await voice.start(draft: 'new');
    pending.completeError(StateError('old permission request failed'));
    await oldStart;
    expect(voice.isListening, true);
    expect(recognizer.cancels, 1);
    recognizer.words!('London');
    expect(drafts, ['new London']);
  });

  test('repeated microphone taps cannot start overlapping speech', () async {
    await voice.start(draft: '');
    await voice.start(draft: '');
    expect(recognizer.starts, 1);
  });

  testWidgets('hard deadline stops even when speech service never finishes',
      (tester) async {
    await voice.start(draft: '');
    await tester.pump(const Duration(seconds: 30));
    expect(recognizer.stops, 1);
    expect(voice.isActive, false);
  });

  test('dispose suppresses late results and releases microphone', () async {
    final controller = AssistantDictationController(
      recognizer: recognizer,
      onDraft: drafts.add,
    );
    await controller.start(draft: '');
    controller.dispose();
    recognizer.words!('late');
    recognizer.done!();
    recognizer.error!();
    expect(drafts, isEmpty);
    expect(recognizer.cancels, 1);
  });
}
