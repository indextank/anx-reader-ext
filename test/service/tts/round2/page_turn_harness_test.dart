// Round-2 deterministic regression harness: auto page turn scenarios.
//
// C. Page last character mid-sentence: the page must be turned the moment the
//    segment that ends at the page's last character finishes, BEFORE the
//    remainder of the sentence is played (reported MiMo + StepAudio delay).
// D. Page ends exactly at a sentence end: the page must be turned immediately
//    after the last segment of that sentence (reported Aliyun + System TTS
//    "does not auto turn").
//
// Both cases must complete within 1000 virtual ms including the fake page-turn
// animation (default 250ms), measured from the last-character audio segment
// completion to the page-turn completion. The fake text source implements
// TtsPageTurnCapable (lib/service/tts/pipeline/tts_page_break.dart); the fake
// animation advances the shared virtual clock so the measurement is
// deterministic and machine independent.
//
// Run: flutter test test/service/tts/round2

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/tts_round2/round2_event_log.dart';
import '../../../support/tts_round2/round2_harness.dart';
import '../../../support/tts_round2/round2_text_source.dart';

/// Acceptance budget for "last page character -> page turn completed",
/// including the page-turn animation.
const int _pageTurnBudgetMs = 1000;

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ttsRate': 0.6,
    'ttsVolume': 0.8,
    'ttsPitch': 1.0,
  });
  await Prefs().initPrefs();
}

int _eventIndex(
  Round2EventLog log,
  Round2EventKind kind, {
  bool Function(Round2Event event)? where,
}) {
  for (var i = 0; i < log.events.length; i++) {
    final event = log.events[i];
    if (event.kind != kind) continue;
    if (where != null && !where(event)) continue;
    return i;
  }
  return -1;
}

/// Index of the [nth] (0-based) event of [kind].
int _eventIndexNth(Round2EventLog log, Round2EventKind kind, int nth) {
  var seen = 0;
  for (var i = 0; i < log.events.length; i++) {
    if (log.events[i].kind != kind) continue;
    if (seen == nth) return i;
    seen += 1;
  }
  return -1;
}

/// Mid-sentence page break sample: the visible page ends after `看见` while the
/// sentence continues on the next page.
List<Round2SliceSpec> _midSentenceSpecs() {
  const text = '　　他走到窗边，看见远处的山。';
  final breakOffset = text.indexOf('远处的山');
  expect(breakOffset, greaterThan(0), reason: 'sample must contain a break');
  return <Round2SliceSpec>[
    Round2SliceSpec(
      cfi: 'cfi-break-0',
      text: text,
      pageToken: 'page-1',
      pageBreakOffset: breakOffset,
      pageAfterBreakToken: 'page-2',
    ),
    const Round2SliceSpec(
      cfi: 'cfi-break-1',
      text: '　　第二页的第一句。',
      pageToken: 'page-2',
    ),
    const Round2SliceSpec(
      cfi: 'cfi-break-2',
      text: '　　第二页的第二句。',
      pageToken: 'page-2',
    ),
  ];
}

/// Sentence-end page boundary sample: the page ends exactly at `。`.
List<Round2SliceSpec> _sentenceEndSpecs() => const <Round2SliceSpec>[
      Round2SliceSpec(
        cfi: 'cfi-end-0',
        text: '　　页面最后一句。',
        pageToken: 'page-1',
      ),
      Round2SliceSpec(
        cfi: 'cfi-end-1',
        text: '　　第二页第一句。',
        pageToken: 'page-2',
      ),
      Round2SliceSpec(
        cfi: 'cfi-end-2',
        text: '　　第二页第二句。',
        pageToken: 'page-2',
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_initPrefs);

  group('C. page last char mid-sentence: turn before the sentence remainder',
      () {
    for (final engine in Round2Engine.values) {
      test(
          '[${engine.label}] page turn is requested after the page-last-char '
          'segment and before the remainder ist played', () async {
        final specs = _midSentenceSpecs();
        final session = await Round2Session.open(engine: engine, specs: specs);
        addTearDown(session.dispose);

        await session.start();
        await session.runToEnd(reason: 'mid-sentence page turn session');

        expect(session.state.hasError, isFalse,
            reason: 'no error expected: ${session.state.error}');
        expect(session.source.pageBreakTurns, hasLength(1),
            reason: 'the pipeline must request exactly one mid-sentence page '
                'turn (TtsPageTurnCapable.turnPageFromBreak); got '
                '${session.source.pageBreakTurns}');
        final turn = session.source.pageBreakTurns.single;
        expect(turn.pageBreak.charOffsetInSlice, specs.first.pageBreakOffset,
            reason: 'turn must happen at the page-last-character offset');
        expect(session.joinedEngineTexts, specs.map((spec) => spec.text).join(),
            reason: 'splitting the sentence at the page boundary must not lose '
                'or duplicate characters');

        // Ordering: page-last-char segment completed -> turn requested ->
        // sentence remainder started.
        final completedIndex = session.isSystem
            ? _eventIndex(session.log, Round2EventKind.nativeSpeakCompleted)
            : _eventIndex(
                session.log,
                Round2EventKind.audioCompleted,
                where: (event) => event.data['startIndex'] == 0,
              );
        final requestedIndex = _eventIndex(
          session.log,
          Round2EventKind.pageTurnRequested,
          where: (event) => event.data['source'] == 'pageBreak',
        );
        final remainderIndex = session.isSystem
            ? _eventIndexNth(session.log, Round2EventKind.nativeSpeakStarted, 1)
            : _eventIndex(
                session.log,
                Round2EventKind.audioStarted,
                where: (event) => event.data['startIndex'] == 1,
              );
        expect(completedIndex, greaterThanOrEqualTo(0),
            reason: 'page-last-char segment must have completed.\n'
                '${session.log.describe(limit: 40)}');
        expect(requestedIndex, greaterThan(completedIndex),
            reason: 'page turn must be requested AFTER the page-last-char '
                'segment completed.\n${session.log.describe(limit: 40)}');
        expect(remainderIndex, greaterThan(requestedIndex),
            reason: 'the sentence remainder must start AFTER the page turn was '
                'requested (turn completion may overlap it).\n'
                '${session.log.describe(limit: 40)}');

        // Latency: from page-last-char segment completion to turn completion,
        // including the fake animation.
        final endedAt = session.log.events[completedIndex].atMs;
        final completedAt = turn.completedAtMs ?? turn.requestedAtMs;
        final latencyMs = completedAt - endedAt;
        expect(latencyMs, lessThanOrEqualTo(_pageTurnBudgetMs),
            reason: 'page turn took ${latencyMs}ms including '
                '${kRound2PageTurnAnimation.inMilliseconds}ms animation '
                '(budget ${_pageTurnBudgetMs}ms)');
        // The animation must actually be counted (fake advances the clock by
        // [kRound2PageTurnAnimation]); a shorter number would mean the harness
        // is not including the animation in the acceptance budget.
        expect(turn.latencyMs,
            greaterThanOrEqualTo(kRound2PageTurnAnimation.inMilliseconds),
            reason: 'measured latency must include the animation duration');
        // ignore: avoid_print
        print('[metric][C][${engine.label}] pageBreakOffset='
            '${turn.pageBreak.charOffsetInSlice} '
            'turnRequestedAtMs=${turn.requestedAtMs} '
            'turnCompletedAtMs=${turn.completedAtMs} '
            'pageLastCharSegmentEndedAtMs=$endedAt '
            'latencyInclAnimationMs=$latencyMs budgetMs=$_pageTurnBudgetMs');
      });
    }
  });

  group('D. page ends exactly at a sentence end: turn after the last segment',
      () {
    for (final engine in Round2Engine.values) {
      test('[${engine.label}] slice-end page turn completes within the budget',
          () async {
        final specs = _sentenceEndSpecs();
        final session = await Round2Session.open(engine: engine, specs: specs);
        addTearDown(session.dispose);

        await session.start();
        await session.runToEnd(reason: 'sentence-end page turn session');

        expect(session.state.hasError, isFalse,
            reason: 'no error expected: ${session.state.error}');
        expect(session.joinedEngineTexts, specs.map((spec) => spec.text).join(),
            reason: 'page turn must not lose/duplicate text');

        // The fake source performs the page turn inside advance() for a slice
        // that crosses to another page; its start/complete events are the
        // observable "auto page turn" for this case.
        final turnRequestedIndex = _eventIndex(
          session.log,
          Round2EventKind.pageTurnRequested,
          where: (event) => event.data['source'] == 'slice-advance',
        );
        final turnCompletedIndex = _eventIndex(
          session.log,
          Round2EventKind.pageTurnCompleted,
          where: (event) => event.data['source'] == 'slice-advance',
        );
        expect(turnRequestedIndex, greaterThanOrEqualTo(0),
            reason: 'page end at sentence end must trigger a page-turn/slice '
                'advance.\n${session.log.describe(limit: 60)}');
        expect(turnCompletedIndex, greaterThan(turnRequestedIndex));

        // Ordering: last segment of the page completed before the turn, and
        // the next page's first segment starts after the turn completed.
        final lastSegmentIndex = session.isSystem
            ? _eventIndex(session.log, Round2EventKind.nativeSpeakCompleted)
            : _eventIndex(
                session.log,
                Round2EventKind.audioCompleted,
                where: (event) => event.data['startIndex'] == 0,
              );
        final nextPageStartIndex = session.isSystem
            ? _eventIndexNth(session.log, Round2EventKind.nativeSpeakStarted, 1)
            : _eventIndex(
                session.log,
                Round2EventKind.audioStarted,
                where: (event) => event.data['startIndex'] == 1,
              );
        expect(lastSegmentIndex, greaterThanOrEqualTo(0));
        expect(turnRequestedIndex, greaterThan(lastSegmentIndex),
            reason: 'page turn must be requested after the page last segment '
                'finished.\n${session.log.describe(limit: 60)}');
        expect(nextPageStartIndex, greaterThan(turnCompletedIndex),
            reason: 'the next page must start playing after the page turn '
                'completed.\n${session.log.describe(limit: 60)}');

        // Latency from last segment completion to page turn completion,
        // including the fake animation duration.
        final endedAt = session.log.events[lastSegmentIndex].atMs;
        final completedAt = session.log.events[turnCompletedIndex].atMs;
        final latencyMs = completedAt - endedAt;
        expect(latencyMs, lessThanOrEqualTo(_pageTurnBudgetMs),
            reason: 'auto page turn took ${latencyMs}ms including '
                '${kRound2PageTurnAnimation.inMilliseconds}ms animation '
                '(budget ${_pageTurnBudgetMs}ms)');
        expect(latencyMs,
            greaterThanOrEqualTo(kRound2PageTurnAnimation.inMilliseconds),
            reason: 'measured latency must include the animation duration');
        // ignore: avoid_print
        print('[metric][D][${engine.label}] lastSegmentEndedAtMs=$endedAt '
            'turnCompletedAtMs=$completedAt '
            'latencyInclAnimationMs=$latencyMs budgetMs=$_pageTurnBudgetMs');
      });
    }
  });
}
