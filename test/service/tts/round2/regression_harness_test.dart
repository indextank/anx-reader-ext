// Round-2 deterministic regression harness: reported-symptom scenarios driven
// through the real engine classes (OnlineTts / SystemTts) with fake text
// source, fake synthesis engines, fake audio output and a virtual clock.
//
// Scope (see docs/tts-round2/01-verification-harness.md):
// A. 8+ consecutive lines across 2+ paragraphs/pages: no stall, no
//    duplicate/missing characters.
// B. pause mid-line -> resume continues the same unread text (no skip to the
//    next line), for cloud engines (player pause) and the system engine
//    (native pause / simulated pause).
// E. sentence-final bracket annotations `[12]`, `[345]`, `[12][13]` are not
//    spoken; display text/ranges still cover them; no extra segments/waits.
// F. engine switch/rate smoke (mid-playback rate, anchor migration).
// G. engine-switch cold start: warm-up units are synthesized before the first
//    audible segment and prefetch starts before the playback path blocks
//    (field log: 4859 ms silent gap after a MiMo→StepAudio switch).
//
// Auto page turn scenarios (C/D) live in `page_turn_harness_test.dart` because
// they need the TtsPageTurnCapable bridge from lib/service/tts/pipeline/
// tts_page_break.dart; see docs/tts-round2/01-verification-harness.md.
//
// Run: flutter test test/service/tts/round2

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/tts_round2/round2_event_log.dart';
import '../../../support/tts_round2/round2_harness.dart';
import '../../../support/tts_round2/round2_text_source.dart';

/// Maximum acceptable virtual gap, in ms, between the end of one audio segment
/// and the start of the next when the two are on the same page. A larger gap
/// is the "playback stalls between lines/paragraphs" symptom.
const int _maxSamePageStallMs = 200;

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ttsRate': 0.6,
    'ttsVolume': 0.8,
    'ttsPitch': 1.0,
  });
  await Prefs().initPrefs();
}

/// Waits until at least [count] segments (audio segments / native speak calls)
/// have started.
Future<void> _untilStarted(Round2Session session, int count) {
  return session.scheduler.runUntil(
    () => session.startedCount >= count,
    reason: 'segment #$count starts (started: ${session.startedCount})',
  );
}

int _unitIndexById(List<TtsUtterance> units, String id) {
  final index = units.indexWhere((unit) => unit.id == id);
  expect(index, greaterThanOrEqualTo(0),
      reason: 'observed utterance $id must be one of the expected units');
  return index;
}

TtsUtterance _expectedUnit(List<TtsUtterance> units, int index) {
  expect(index, lessThan(units.length),
      reason: 'expected a following unit after index $index');
  return units[index];
}

/// Index of the slice that produced [utterance], from its slice index.
Round2SliceSpec _sliceOf(List<Round2SliceSpec> specs, TtsUtterance utterance) =>
    specs[utterance.sliceIndex.clamp(0, specs.length - 1)];

String _sliceTextForCfi(List<Round2SliceSpec> specs, String cfi) =>
    specs.firstWhere((spec) => spec.cfi == cfi).text;

/// Reconstructs the highlighted text from the sentence text and the painted
/// sentence-relative spans. This is the exact contract the reader bridge gets:
/// joining the substrings must reproduce the spoken text verbatim (annotations
/// such as `[12]` therefore never appear).
String _joinedHighlightText(
  List<Round2SliceSpec> specs,
  Round2HighlightRecord record,
) {
  final text = _sliceTextForCfi(specs, record.cfi);
  final buffer = StringBuffer();
  for (final range in record.ranges) {
    buffer.write(text.substring(range.start, range.end));
  }
  return buffer.toString();
}

/// Spoken texts in playback order: engine request text for cloud engines,
/// native speak text for the system engine.
List<String> _playedTexts(Round2Session session) {
  if (session.isSystem) {
    return List<String>.of(session.nativeEngine!.spokenTexts);
  }
  final byUtterance = <String, String>{};
  for (final request in session.onlineEngine!.requests) {
    final utteranceId = request.utteranceId;
    if (utteranceId != null && utteranceId.isNotEmpty) {
      byUtterance[utteranceId] = request.text;
    }
  }
  return <String>[
    for (final start in session.audio!.starts)
      byUtterance[start.utteranceId] ?? '<missing:${start.utteranceId}>',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_initPrefs);

  // ===========================================================================
  // A. No stall for 8+ consecutive lines / 2+ paragraphs.
  // ===========================================================================
  group('A. no stall: 10 lines / 3 pages / 3 paragraphs', () {
    for (final engine in Round2Engine.values) {
      test(
          '[${engine.label}] every line is synthesized once, in order, without '
          'queue starvation', () async {
        final specs = round2NoStallSpecs();
        final session = await Round2Session.open(engine: engine, specs: specs);
        addTearDown(session.dispose);

        final expectedUnits =
            round2ExpectedUnits(specs, session.profile.maxRequestChars);
        final expectedText = specs.map((spec) => spec.text).join();

        await session.start();
        await session.runToEnd(reason: 'no-stall playback must terminate');

        expect(session.state.phase, TtsPlaybackPhase.stopped,
            reason: 'playback must end cleanly, not error/empty/hang '
                '(state: ${session.state})');
        expect(session.state.hasError, isFalse,
            reason: 'no typed playback error expected: '
                '${session.state.error}');
        expect(session.engineCallCount, expectedUnits.length,
            reason: 'one engine request per utterance; no duplicate/missing '
                'requests. Actual: ${session.engineTexts}');
        expect(session.engineTexts,
            expectedUnits.map((unit) => unit.text).toList(growable: false),
            reason: 'request texts must match the splitter output exactly');
        expect(session.joinedEngineTexts, expectedText,
            reason: 'no character may be lost, duplicated or reordered');

        if (!session.isSystem) {
          final starts = session.audio!.starts;
          expect(starts.length, expectedUnits.length,
              reason: 'each utterance must produce exactly one audio segment');
          expect(
            starts.map((start) => start.utteranceId).toList(growable: false),
            expectedUnits.map((unit) => unit.id).toList(growable: false),
            reason: 'audio segments must be played in utterance order',
          );

          var worstGapMs = 0;
          var maxSamePageGapMs = 0;
          var worstGap = '';
          for (var i = 1; i < starts.length; i++) {
            final gap = starts[i].atMs -
                (starts[i - 1].atMs + kRound2SegmentDuration.inMilliseconds);
            final previousPage =
                _sliceOf(specs, expectedUnits[i - 1]).pageToken;
            final currentPage = _sliceOf(specs, expectedUnits[i]).pageToken;
            final crossesPage = previousPage != currentPage;
            final allowed = crossesPage
                ? kRound2PageTurnAnimation.inMilliseconds + 120
                : _maxSamePageStallMs;
            if (!crossesPage && gap > maxSamePageGapMs) {
              maxSamePageGapMs = gap;
            }
            if (gap > allowed && gap > worstGapMs) {
              worstGapMs = gap;
              worstGap = 'between segment ${i - 1} and $i '
                  '(pages: $previousPage -> $currentPage, allowed ${allowed}ms)';
            }
          }
          expect(worstGapMs, lessThanOrEqualTo(0),
              reason: 'playback stalled between segments: '
                  'gap ${worstGapMs}ms $worstGap');
          // Measured metric quoted by docs/tts-round2/02-regression-report.md.
          // ignore: avoid_print
          print(
              '[metric][A][${engine.label}] utterances=${expectedUnits.length} '
              'segments=${starts.length} maxSamePageGapMs=$maxSamePageGapMs '
              'stallBudgetMs=$_maxSamePageStallMs');
        } else {
          // ignore: avoid_print
          print(
              '[metric][A][${engine.label}] utterances=${expectedUnits.length} '
              'nativeSpeaks=${session.engineCallCount}');
        }
      });
    }
  });

  // ===========================================================================
  // B. Pause mid-line -> resume continues the same unread text (no skip).
  // ===========================================================================
  group('B. pause mid-line -> resume does not skip the current text', () {
    for (final engine in Round2Engine.values) {
      test(
          '[${engine.label}] paused segment does not advance, resume stays in '
          'the same utterance', () async {
        final specs = round2NoStallSpecs().take(4).toList(growable: false);
        final session = await Round2Session.open(
          engine: engine,
          specs: specs,
          autoComplete: false,
        );
        addTearDown(session.dispose);

        final expectedUnits =
            round2ExpectedUnits(specs, session.profile.maxRequestChars);

        await session.start();
        await _untilStarted(session, 1);
        await session.scheduler.flush();
        expect(session.state.phase, TtsPlaybackPhase.playing);

        final pausedCursor = session.cursor;
        final pausedUtterance = session.utterance;
        expect(pausedCursor, isNotNull);
        expect(pausedUtterance, isNotNull);
        final pausedIndex = _unitIndexById(expectedUnits, pausedUtterance!.id);
        final startedAtPause = session.startedCount;

        await session.tts.pause();
        await session.scheduler.flush();
        expect(session.state.phase, TtsPlaybackPhase.paused,
            reason: 'pause must reach the paused phase');
        expect(session.cursor?.utteranceId, pausedCursor!.utteranceId,
            reason: 'pausing must keep the current utterance as cursor');

        // A completion delivered while paused is stale and must not advance.
        session.completeActiveSegment();
        await session.scheduler.flush();
        expect(session.state.phase, TtsPlaybackPhase.paused,
            reason: 'stale completion during pause must not restart playback');
        expect(session.startedCount, startedAtPause,
            reason: 'paused playback must not start a new segment');

        await session.tts.resume();
        await session.scheduler.flush();
        expect(session.state.phase, TtsPlaybackPhase.playing,
            reason: 'resume must return to playing');

        if (session.isSystem) {
          // Native pause was interrupted by the stale completion, so the
          // system engine re-speaks the current utterance from the calibrated
          // cursor. The first text after resume MUST be inside that utterance.
          await _untilStarted(session, startedAtPause + 1);
          final reSpoken = session.nativeEngine!.spokenTexts.last;
          final startInPaused = pausedUtterance.text.indexOf(reSpoken);
          expect(startInPaused, greaterThanOrEqualTo(0),
              reason: 'system resume re-spoke "$reSpoken" which is not part of '
                  'the paused utterance "${pausedUtterance.text}" (skipped '
                  'current text)');
          expect(startInPaused, lessThanOrEqualTo(pausedCursor.charOffset),
              reason: 'resume must start at or before the pause cursor '
                  '($startInPaused > ${pausedCursor.charOffset})');
          session.completeNativeSpeak();
        } else {
          // The audio player was paused in place: no new segment may start
          // before the paused segment finishes.
          expect(session.audio!.resumeCalls, greaterThanOrEqualTo(1),
              reason: 'cloud engine pause must be resumed on the player');
          expect(session.startedCount, startedAtPause,
              reason: 'resumed player must continue the paused segment, not '
                  'start a new one');
          expect(session.cursor?.utteranceId, pausedCursor.utteranceId);
          expect(session.cursor?.charOffset ?? 0,
              lessThanOrEqualTo(pausedCursor.charOffset));
          session.completeAudioSegment();
        }

        // The segment that follows must be the very next unit, proving the
        // paused text was completed rather than skipped.
        final nextIndex = pausedIndex + 1;
        if (nextIndex < expectedUnits.length) {
          // System re-speaks the current utterance after resume (one segment
          // before the following unit), cloud engines resume the player in
          // place (the following unit is the next segment).
          final targetStarted =
              session.isSystem ? startedAtPause + 2 : startedAtPause + 1;
          await _untilStarted(session, targetStarted);
          final nextStart = session.audio != null
              ? session.audio!.starts[startedAtPause].utteranceId
              : null;
          if (nextStart != null) {
            expect(nextStart, _expectedUnit(expectedUnits, nextIndex).id,
                reason: 'after resume/complete the next segment must be unit '
                    '#$nextIndex, not a later line');
          } else {
            expect(session.nativeEngine!.spokenTexts.last,
                _expectedUnit(expectedUnits, nextIndex).text,
                reason: 'after resume/complete the next spoken text must be '
                    'unit #$nextIndex, not a later line');
          }
          // Measured metric quoted by the regression report.
          // ignore: avoid_print
          print('[metric][B][${engine.label}] pausedUnitIndex=$pausedIndex '
              'nextUnitIndex=$nextIndex '
              'resumeMode=${session.isSystem ? 'native-replay-suffix-or-same' : 'player-in-place'} '
              'startedAtPause=$startedAtPause');
        }

        await session.tts.stop();
      });
    }
  });

  // ===========================================================================
  // E. Sentence-final bracket annotations must not be spoken.
  // ===========================================================================
  group('E. sentence-final bracket annotations are not synthesized', () {
    for (final engine in Round2Engine.values) {
      test(
          '[${engine.label}] [12]/[345]/[12][13] dropped from requests while '
          'display ranges stay raw', () async {
        final annotatedSpecs = round2AnnotationSpecs();
        final session = await Round2Session.open(
          engine: engine,
          specs: annotatedSpecs,
        );
        addTearDown(session.dispose);

        final rawText = annotatedSpecs.map((spec) => spec.text).join();
        final expectedSpeech = stripRound2Annotations(rawText);
        final expectedUnits = round2ExpectedUnits(
            annotatedSpecs, session.profile.maxRequestChars);

        await session.start();
        await session.runToEnd(reason: 'annotation playback must terminate');
        expect(session.state.hasError, isFalse,
            reason: 'no error expected: ${session.state.error}');

        final annotationPattern = RegExp(r'\[\d+\]');
        for (final text in session.engineTexts) {
          expect(text.contains(annotationPattern), isFalse,
              reason: 'engine request must not contain a footnote annotation: '
                  '"$text"');
        }
        expect(session.joinedEngineTexts, expectedSpeech,
            reason: 'everything except the [n] annotations must be spoken '
                'verbatim; nothing may be dropped or duplicated');
        expect(session.engineCallCount, expectedUnits.length,
            reason: 'annotation removal must not add engine requests or silent '
                'segments');

        // Display text/ranges stay raw: every unit text/range still covers the
        // annotation characters, and the units of each paragraph reconstruct
        // the untouched display text.
        final unitsByParagraph = <String, List<TtsUtterance>>{};
        for (final unit in session.observedUtterances) {
          unitsByParagraph.putIfAbsent(unit.paragraphId, () => []).add(unit);
        }
        expect(unitsByParagraph.length, annotatedSpecs.length,
            reason: 'every annotated slice must be read; observed paragraphs: '
                '${unitsByParagraph.keys}');
        for (final spec in annotatedSpecs) {
          final units = unitsByParagraph[spec.cfi];
          expect(units, isNotNull,
              reason: 'slice ${spec.cfi} produced no utterance');
          units!.sort((a, b) => a.range.start.compareTo(b.range.start));
          expect(units.first.range.start, 0,
              reason: '${spec.cfi}: first range must start at 0');
          expect(units.last.range.end, spec.text.length,
              reason: '${spec.cfi}: last range must cover the raw slice '
                  'including annotations');
          var cursor = 0;
          final rebuilt = StringBuffer();
          for (final unit in units) {
            expect(unit.range.start, cursor,
                reason: '${spec.cfi}: ranges must stay contiguous over raw '
                    'display text');
            rebuilt
                .write(spec.text.substring(unit.range.start, unit.range.end));
            cursor = unit.range.end;
          }
          expect(rebuilt.toString(), spec.text,
              reason: '${spec.cfi}: display ranges must still cover the raw '
                  'text including the annotation');
          expect(units.map((unit) => unit.text).join(), spec.text,
              reason: '${spec.cfi}: TtsUtterance.text stays the raw display '
                  'text (only engine requests are sanitized)');
        }

        // No extra waits: the annotated run must cost exactly the same number
        // of segments and virtual time as the annotation-free run.
        final cleanSession = await Round2Session.open(
          engine: engine,
          specs: round2AnnotationFreeSpecs(),
        );
        addTearDown(cleanSession.dispose);
        await cleanSession.start();
        await cleanSession.runToEnd(reason: 'clean baseline must terminate');
        expect(cleanSession.state.hasError, isFalse);
        expect(session.engineCallCount, cleanSession.engineCallCount,
            reason: 'annotation removal must not add/remove segments');
        expect(session.clock.ms, cleanSession.clock.ms,
            reason: 'annotation removal must not add waits/delays');
        // Measured metric quoted by the regression report.
        // ignore: avoid_print
        print(
            '[metric][E][${engine.label}] requests=${session.engineCallCount} '
            'cleanRequests=${cleanSession.engineCallCount} '
            'virtualMs=${session.clock.ms} '
            'cleanVirtualMs=${cleanSession.clock.ms} '
            'annotationCharsRemoved=${rawText.length - expectedSpeech.length}');
      });
    }
  });

  // ===========================================================================
  // F. Engine switch / rate smoke.
  // ===========================================================================
  group('F. engine switch and mid-playback rate', () {
    test('engine switch migrates the anchor instead of restarting at page top',
        () async {
      final specs = round2NoStallSpecs().take(4).toList(growable: false);
      final first = await Round2Session.open(
        engine: Round2Engine.aliyun,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(first.dispose);
      await first.start();
      await _untilStarted(first, 1);

      // Play the first sentence to completion, then pause during the second
      // one: the migrated anchor must point at the second sentence.
      first.completeAudioSegment();
      await _untilStarted(first, 2);
      await first.scheduler.flush();
      final anchor =
          first.tts.captureResumeAnchor(reason: TtsResumeReason.engineSwitched);
      expect(anchor, isNotNull);
      expect(anchor!.cfi, specs[1].cfi,
          reason: 'anchor must point at the sentence being read');
      await first.tts.stop();

      final second = await Round2Session.open(
        engine: Round2Engine.mimo,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(second.dispose);
      await second.initialize();
      await second.tts.speak(anchor: anchor);
      await _untilStarted(second, 1);

      expect(second.source.locateAnchors.first, anchor.cfi,
          reason: 'new engine must locate at the migrated anchor');
      final secondUnits =
          round2ExpectedUnits(specs, second.profile.maxRequestChars);
      expect(_unitIndexById(secondUnits, second.observedUtterances.first.id), 1,
          reason: 'new engine must continue at sentence #1, not sentence #0');
      expect(second.engineTexts.first,
          secondUnits.map((unit) => unit.text).elementAt(1),
          reason: 'first request after switch must be the migrated sentence');
      // ignore: avoid_print
      print('[metric][F][switch] anchorCfi=${anchor.cfi} '
          'newEngineFirstUnitIndex=1 locateAnchor='
          '${second.source.locateAnchors.first}');
      await second.tts.stop();
    });

    test('MiMo player-side rate applies to current and following segments',
        () async {
      final specs = round2NoStallSpecs().take(3).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.mimo,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(session.dispose);
      await session.start();
      await _untilStarted(session, 1);
      final requestsBefore = session.engineCallCount;
      final rateChangesBefore = session.audio!.playbackRateChanges.length;

      await session.tts.changeRate(1.0);
      await session.scheduler.flush();
      expect(session.state.rate, 1.0);
      expect(session.audio!.playbackRateChanges.length,
          greaterThan(rateChangesBefore),
          reason: 'MiMo has no server rate: the player rate must change');
      expect(session.audio!.playbackRateChanges.last, closeTo(2.0, 1e-9));
      expect(session.engineCallCount, requestsBefore,
          reason: 'player-side rate change must not invalidate/duplicate the '
              'current synthesis');

      session.completeAudioSegment();
      await _untilStarted(session, 2);
      expect(session.audio!.starts[1].playbackRate, closeTo(2.0, 1e-9),
          reason: 'following segments must keep the new speed');
      expect(session.audio!.starts[1].applyRate, isTrue);
      // ignore: avoid_print
      print('[metric][F][mimo-rate] playerRate=2.0 '
          'requestsBefore=$requestsBefore '
          'requestsAfter=${session.engineCallCount} '
          'nextSegmentRate=${session.audio!.starts[1].playbackRate}');
      await session.tts.stop();
    });

    test('server-side rate is applied to following synthesis requests',
        () async {
      final specs = round2NoStallSpecs().take(3).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.aliyun,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(session.dispose);
      await session.start();
      await _untilStarted(session, 1);

      await session.tts.changeRate(1.0);
      await session.scheduler.flush();
      session.completeAudioSegment();
      await _untilStarted(session, 2);
      expect(session.engineTexts.length, greaterThan(1));
      expect(
          session.onlineEngine!.requests.last.config.rate, closeTo(1.0, 1e-9),
          reason: 'server-side engines must synthesize following requests with '
              'the new rate');
      expect(session.audio!.starts[1].applyRate, isFalse);
      // ignore: avoid_print
      print('[metric][F][aliyun-rate] nextRequestRate=1.0 '
          'nextSegmentApplyRate=${session.audio!.starts[1].applyRate}');
      await session.tts.stop();
    });

    test('system rate change applies to the next utterance, not the current',
        () async {
      final specs = round2NoStallSpecs().take(3).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.system,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(session.dispose);
      await session.start();
      await _untilStarted(session, 1);
      final spokenBefore = session.nativeEngine!.spokenTexts.length;

      await session.tts.changeRate(1.0);
      await session.scheduler.flush();
      expect(session.state.rate, 1.0);
      expect(session.nativeEngine!.spokenTexts.length, spokenBefore,
          reason: 'rate change must not restart the current utterance');
      expect(session.nativeEngine!.configs.last.rate, closeTo(1.0, 1e-9),
          reason: 'the system engine must configure the new rate');

      session.completeNativeSpeak();
      await _untilStarted(session, 2);
      expect(session.nativeEngine!.spokenTexts.length, spokenBefore + 1);
      expect(session.nativeEngine!.configs.last.rate, closeTo(1.0, 1e-9),
          reason: 'the next utterance must be spoken with the new rate');
      // ignore: avoid_print
      print('[metric][F][system-rate] spokenBefore=$spokenBefore '
          'spokenAfter=${session.nativeEngine!.spokenTexts.length} '
          'configuredRate=1.0');
      await session.tts.stop();
    });
  });

  // ===========================================================================
  // G. Engine-switch cold start (field log 2026-11-05 12:23, MiMo→StepAudio).
  // ===========================================================================
  group('G. engine-switch cold start', () {
    test('warm-up synthesizes the first units before audio becomes audible',
        () async {
      final specs = round2NoStallSpecs().take(4).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.stepAudio,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(session.dispose);
      await session.initialize();
      // The engine switch path passes warmUpUnits: 2 (TtsHandler).
      await session.tts.speak(warmUpUnits: 2);
      await session.scheduler.runUntil(
        () => session.audio!.starts.isNotEmpty,
        reason: 'first audible segment after the warm-up',
      );

      final firstStartIndex =
          session.log.indexOfKind(Round2EventKind.audioStarted);
      expect(firstStartIndex, greaterThanOrEqualTo(0));
      final completedBefore = session.log.events
          .take(firstStartIndex)
          .where((event) => event.kind == Round2EventKind.synthesisCompleted)
          .length;
      expect(
        completedBefore,
        greaterThanOrEqualTo(2),
        reason: 'a cold engine switch must synthesize the warm-up units before '
            'the first segment becomes audible; otherwise the queue runs dry '
            'after the first sentence and the player is silent for seconds',
      );
      // The warm-up must not reorder or skip the first utterance.
      expect(
        session.audio!.starts.first.utteranceId,
        session.observedUtterances.first.id,
      );
      // ignore: avoid_print
      print('[metric][G][warmup] completedBeforeAudio=$completedBefore '
          'audioStartMs=${session.audio!.starts.first.atMs}');
      await session.tts.stop();
    });

    test('prefetch starts before the first segment is audible', () async {
      final specs = round2NoStallSpecs().take(4).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.stepAudio,
        specs: specs,
        autoComplete: false,
      );
      addTearDown(session.dispose);
      await session.initialize();
      await session.tts.speak();
      await session.scheduler.runUntil(
        () => session.audio!.starts.isNotEmpty,
        reason: 'first audible segment',
      );

      final firstStartIndex =
          session.log.indexOfKind(Round2EventKind.audioStarted);
      final requestsBefore = session.log.events
          .take(firstStartIndex)
          .where((event) => event.kind == Round2EventKind.synthesisRequested)
          .length;
      expect(
        requestsBefore,
        greaterThanOrEqualTo(2),
        reason: 'prefetch for the following utterances must be requested '
            'before the playback path blocks on the first segment; requests '
            'issued only after the segment starts put their full synthesis '
            'latency on the audible critical path',
      );
      // ignore: avoid_print
      print('[metric][G][early-prefetch] requestsBeforeAudio=$requestsBefore '
          'audioStartMs=${session.audio!.starts.first.atMs}');
      await session.tts.stop();
    });
  });

  // ===========================================================================
  // H. Reader highlight sync.
  //
  // Field reports: (1) after the user manually paged away the highlight was
  // painted on the wrong page and could not be located again; (2) annotations
  // like `[8]` were selected and the selection drifted one sentence behind the
  // audio. The pipeline must repaint exactly the spoken span of every audible
  // segment (annotations excluded) and ask the reader to force-show that page.
  // ===========================================================================
  group('H. highlight sync', () {
    for (final engine in Round2Engine.values) {
      test('[${engine.label}] every audible segment repaints its exact text',
          () async {
        final specs = round2AnnotationSpecs();
        final session = await Round2Session.open(engine: engine, specs: specs);
        addTearDown(session.dispose);
        await session.start();
        await session.runToEnd(reason: 'annotation highlight sync');

        expect(session.state.hasError, isFalse,
            reason: 'no error expected: ${session.state.error}');
        final played = _playedTexts(session);
        final highlights = session.source.highlights;
        expect(
          played,
          isNotEmpty,
          reason: 'the sample must actually play some segments',
        );
        expect(
          highlights.length,
          played.length,
          reason: 'every audible segment (including page-break/oversized '
              'splits) must repaint exactly once before it starts',
        );
        for (var i = 0; i < played.length; i++) {
          final highlighted = _joinedHighlightText(specs, highlights[i]);
          expect(
            highlighted,
            played[i],
            reason: 'highlight #$i must cover exactly the spoken text of the '
                'segment (sentence-final annotations like [12] excluded)',
          );
          expect(RegExp(r'\[\d+\]').hasMatch(highlighted), isFalse);
        }
        // ignore: avoid_print
        print('[metric][H][annotation][${engine.label}] '
            'highlights=${highlights.length} '
            'spanCounts=${highlights.map((h) => h.ranges.length).toList()}');
        await session.tts.stop();
      });
    }

    test('page-break split repaints the first and remainder spans separately',
        () async {
      const text = '　　他走到窗边，看见远处的山，然后停下了脚步。';
      final breakOffset = text.indexOf('远处');
      expect(breakOffset, greaterThan(0));
      final specs = <Round2SliceSpec>[
        Round2SliceSpec(
          cfi: 'cfi-split-0',
          text: text,
          pageToken: 'page-1',
          pageBreakOffset: breakOffset,
          pageAfterBreakToken: 'page-2',
        ),
        const Round2SliceSpec(
          cfi: 'cfi-split-1',
          text: '　　第二页的下一句。',
          pageToken: 'page-2',
        ),
      ];
      final session =
          await Round2Session.open(engine: Round2Engine.aliyun, specs: specs);
      addTearDown(session.dispose);
      await session.start();
      await session.runToEnd(reason: 'page-break split highlight sync');

      final highlights = session.source.highlights
          .where((record) => record.cfi == 'cfi-split-0')
          .toList(growable: false);
      expect(highlights.length, 2,
          reason: 'the split sentence must repaint once for `.a` and once for '
              'the remainder `.b` (which runs after the page turn)');
      expect(
        highlights.first.ranges.map((range) => (range.start, range.end)),
        [(0, breakOffset)],
        reason: '`.a` highlights only the part spoken before the page turn',
      );
      expect(
        highlights[1].ranges.map((range) => (range.start, range.end)),
        [(breakOffset, text.length)],
        reason: '`.b` must replace the `.a` highlight with the remainder span',
      );

      // Ordering: `.a` highlight -> page turn requested -> `.b` highlight.
      final events = session.log.events;
      final notes = <int>[
        for (var i = 0; i < events.length; i++)
          if (events[i].kind == Round2EventKind.note &&
              events[i].label == 'ttsHighlightSpoken' &&
              events[i].data['cfi'] == 'cfi-split-0')
            i,
      ];
      final turn = events.indexWhere((event) =>
          event.kind == Round2EventKind.pageTurnRequested &&
          event.data['source'] == 'pageBreak');
      expect(notes.length, greaterThanOrEqualTo(2));
      expect(turn, greaterThan(notes.first));
      expect(notes.last, greaterThan(turn),
          reason:
              'the remainder highlight must be painted after the page turn');
      // ignore: avoid_print
      print('[metric][H][page-break] breakOffset=$breakOffset '
          'firstSpan=${highlights.first.ranges} '
          'remainderSpan=${highlights[1].ranges}');
      await session.tts.stop();
    });

    test('a reader that cannot show the sentence never stops playback',
        () async {
      final specs = round2NoStallSpecs().take(3).toList(growable: false);
      final session = await Round2Session.open(
        engine: Round2Engine.mimo,
        specs: specs,
      );
      addTearDown(session.dispose);
      session.source.highlightVisible = false;
      await session.start();
      await session.runToEnd(reason: 'unavailable highlight reader');

      expect(session.state.hasError, isFalse,
          reason: 'highlight failures are advisory, never fatal');
      expect(session.startedCount, greaterThanOrEqualTo(3),
          reason: 'audio must keep flowing when the highlight cannot be shown');
      expect(
        session.source.highlights.length,
        session.startedCount,
        reason: 'every audible segment still attempted a repaint',
      );
      // ignore: avoid_print
      print('[metric][H][unavailable] started=${session.startedCount} '
          'highlights=${session.source.highlights.length}');
      await session.tts.stop();
    });
  });
}
