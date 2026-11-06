// Round-2 audit: the page-break split pipeline (`.a` / `.b`) must never lose,
// duplicate, reorder or re-read text when the reader bridge is re-queried.
//
// Field evidence (2026-11-06 09:29 MiMo / 09:30 Aliyun, `anx_reader.log`):
//
//   09:29:21.060 page-break offset=4/55      <- first query, on the 55-char slice
//   09:29:21.061 synthesis.requested #0.a chars=4
//   09:29:21.062 synthesis.requested #0.b chars=51
//   09:29:22.249 audio.completed .a (575ms)
//   09:29:22.250 pageTurn.requested source=pageBreak
//   09:29:22.255 page-break offset=4/55      <- SECOND query, for `.b`, while
//                                               the page-turn animation is in
//                                               flight (lastLocation still old)
//   09:29:22.520 page-turn turned=true ...
//
// OnlineTts._applyPageBreakBeforeSlice() runs for every slice-first unit, and
// the split `.b` keeps `unitIndex == 0` (isFirstUnitOfSlice == true), so the
// pipeline asks the bridge again for the remainder of the SAME sentence. This
// file reproduces that exact double-query deterministically (the stock
// Round2TextSource suppresses repeat queries; the subclass below keeps
// answering with the old page until the turn completed, like the real bridge)
// and asserts:
//   - `.a`/`.b` request text and display ranges still partition the sentence
//     exactly (no lost/duplicated character, no `.b.a`/`.b.b` re-split),
//   - the queue keeps `.b` and every following slice in order,
//   - exactly ONE page turn is requested,
//   - `.b` completion advances to the next slice (never repeats the sentence).
//
// Run: flutter test test/service/tts/round2

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/tts_round2/round2_audio_output.dart';
import '../../../support/tts_round2/round2_clock.dart';
import '../../../support/tts_round2/round2_engine.dart';
import '../../../support/tts_round2/round2_event_log.dart';
import '../../../support/tts_round2/round2_harness.dart';
import '../../../support/tts_round2/round2_native_engine.dart';
import '../../../support/tts_round2/round2_text_source.dart';

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ttsRate': 0.6,
    'ttsVolume': 0.8,
    'ttsPitch': 1.0,
  });
  await Prefs().initPrefs();
}

// ===========================================================================
// Real-bridge text source: keeps answering with the old page break until the
// page-turn animation completed (the field timeline above).
// ===========================================================================

class _PageBreakQuery {
  const _PageBreakQuery({
    required this.atMs,
    required this.cfi,
    required this.offset,
  });

  final int atMs;
  final String cfi;
  final int? offset;

  @override
  String toString() => '@${atMs}ms cfi=$cfi offset=$offset';
}

class _InFlightBridgeTextSource extends Round2TextSource {
  _InFlightBridgeTextSource({
    required super.specs,
    required super.scheduler,
    required super.log,
  });

  /// Every `ttsPageBreak()` answer, in call order (mirrors the field log).
  final List<_PageBreakQuery> pageBreakQueries = <_PageBreakQuery>[];

  final Set<String> _turnedCfi = <String>{};

  @override
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice) async {
    final cfi = slice.cfi ?? '';
    final index = specs.indexWhere((spec) => spec.cfi == slice.cfi);
    final rawOffset = index < 0 ? null : specs[index].pageBreakOffset;
    // The old page is still `lastLocation` until the animation completed, so
    // the bridge keeps answering with the same mid-slice offset (field log).
    if (rawOffset == null || _turnedCfi.contains(cfi)) {
      pageBreakQueries.add(
        _PageBreakQuery(atMs: clock.ms, cfi: cfi, offset: null),
      );
      return null;
    }
    final offset = clampPageBreakOffset(slice.text, rawOffset);
    pageBreakQueries.add(
      _PageBreakQuery(atMs: clock.ms, cfi: cfi, offset: offset),
    );
    if (offset == null) return null;
    return TtsPageBreak(
      charOffsetInSlice: offset,
      pageEndCfi: '$cfi#page-end@$offset',
    );
  }

  @override
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak) async {
    final cfi = currentSpec?.cfi ?? '';
    await super.turnPageFromBreak(pageBreak);
    // Only now does the new page become the visible one, so the next query
    // resolves to null ("whole sentence is on the page").
    _turnedCfi.add(cfi);
  }
}

// ===========================================================================
// Session builders (the stock Round2Session cannot inject a custom source).
// ===========================================================================

class _CloudAuditSession {
  _CloudAuditSession({
    required this.scheduler,
    required this.log,
    required this.source,
    required this.engine,
    required this.audio,
    required this.tts,
    required this.profile,
  });

  final Round2Scheduler scheduler;
  final Round2EventLog log;
  final _InFlightBridgeTextSource source;
  final Round2RecordingEngine engine;
  final Round2AudioOutput audio;
  final OnlineTts tts;
  final Round2EngineProfile profile;

  final List<TtsUtterance> observedUtterances = <TtsUtterance>[];

  TtsPlaybackState get state => tts.playbackState;

  void _observePlaybackState() {
    final utterance = tts.playbackState.utterance;
    if (utterance == null) return;
    if (observedUtterances.any((seen) => seen.id == utterance.id)) return;
    observedUtterances.add(utterance);
  }

  Future<void> start() async {
    tts.playbackStateNotifier.addListener(_observePlaybackState);
    await tts.init(textSource: source);
    await tts.speak();
  }

  Future<void> runToEnd() async {
    await scheduler.runUntilDone(
      tts.currentSession,
      timeout: const Duration(seconds: 15),
      reason: 'page-break pipeline audit session',
    );
    await scheduler.flush();
  }

  Future<void> dispose() async {
    try {
      tts.playbackStateNotifier.removeListener(_observePlaybackState);
    } catch (_) {
      // Notifier already torn down.
    }
    await tts.dispose();
    await scheduler.flush(turns: 1);
  }
}

Future<_CloudAuditSession> _openCloudAudit({
  required List<Round2SliceSpec> specs,
  required Round2EngineProfile profile,
}) async {
  final scheduler = Round2Scheduler();
  final log = Round2EventLog();
  final source = _InFlightBridgeTextSource(
    specs: specs,
    scheduler: scheduler,
    log: log,
  );
  final engine = Round2RecordingEngine(
    profile: profile,
    scheduler: scheduler,
    log: log,
  );
  final audio = Round2AudioOutput(scheduler: scheduler, log: log);
  final tts = OnlineTts.withDependencies(
    engineResolver: () => engine,
    audioOutputFactory: audio,
    engineKindOverride: profile.kind,
    initialRate: 0.6,
    synthesisTimeout: const Duration(seconds: 5),
    maxRetries: 1,
    volumeOverride: 0.8,
    pitchOverride: 1.0,
    pageTurnAnimationMs: kRound2PageTurnAnimation.inMilliseconds,
  );
  return _CloudAuditSession(
    scheduler: scheduler,
    log: log,
    source: source,
    engine: engine,
    audio: audio,
    tts: tts,
    profile: profile,
  );
}

// ===========================================================================
// Expectations shared by online and system engines.
// ===========================================================================

/// Field-like sample: the visible page ends 4 characters inside the sentence
/// (offset 4/55 in the field log), so `.a` is the first 4 characters
/// (`，他很高`) and `.b` is the remaining 20.
List<Round2SliceSpec> _fieldLikeSpecs({int breakOffset = 4}) {
  const text = '，他很高兴地看到远处的山，然后慢慢停下了脚步。';
  expect(text.length, greaterThan(breakOffset + 1));
  return <Round2SliceSpec>[
    Round2SliceSpec(
      cfi: 'cfi-audit-0',
      text: text,
      pageToken: 'page-1',
      pageBreakOffset: breakOffset,
      pageAfterBreakToken: 'page-2',
    ),
    const Round2SliceSpec(
      cfi: 'cfi-audit-1',
      text: '第二页的第一句话。',
      pageToken: 'page-2',
    ),
    const Round2SliceSpec(
      cfi: 'cfi-audit-2',
      text: '第三句话。',
      pageToken: 'page-3',
    ),
  ];
}

/// Engine request texts the pipeline must produce for [specs] after both the
/// regular splitter and the page-break split (same algorithm as
/// `_splitUnitsAtPageBreak`, applied to `splitTtsParagraph` output).
List<String> _expectedPlayedTexts(
  List<Round2SliceSpec> specs,
  int maxRequestChars,
) {
  final units = round2ExpectedUnits(specs, maxRequestChars);
  final texts = <String>[];
  var splitDone = false;
  for (final unit in units) {
    final spec = specs[unit.sliceIndex];
    final offset = splitDone ? null : spec.pageBreakOffset;
    if (offset != null &&
        offset > unit.range.start &&
        offset < unit.range.end) {
      final relative = offset - unit.range.start;
      texts.add(unit.text.substring(0, relative));
      texts.add(unit.text.substring(relative));
      splitDone = true;
    } else if (offset != null && offset == unit.range.end) {
      texts.add(unit.text);
      splitDone = true;
    } else {
      texts.add(unit.text);
    }
  }
  return texts;
}

void _expectDisplayRangesPartition(
  List<TtsUtterance> observed,
  Round2SliceSpec spec,
  int specIndex,
) {
  final units = observed.where((unit) => unit.sliceIndex == specIndex).toList()
    ..sort((a, b) => a.range.start.compareTo(b.range.start));
  expect(units, isNotEmpty, reason: 'no emitted unit for ${spec.cfi}');
  var cursor = 0;
  for (final unit in units) {
    expect(unit.range.start, cursor,
        reason: 'unit ${unit.id} must start where the previous one ended');
    expect(unit.text, spec.text.substring(unit.range.start, unit.range.end),
        reason: 'unit ${unit.id} text must be the verbatim display substring');
    cursor = unit.range.end;
  }
  expect(cursor, spec.text.length,
      reason: 'units of ${spec.cfi} must cover the whole sentence');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_initPrefs);

  // =========================================================================
  // 1. Field case: the `.b` re-query while the page turn is in flight.
  // =========================================================================
  group('A. in-flight page-break re-query (field .a/.b split)', () {
    for (final profile in <Round2EngineProfile>[
      Round2EngineProfile.aliyun,
      Round2EngineProfile.mimo,
      Round2EngineProfile.stepAudio,
    ]) {
      test(
          '[${profile.name}] a repeated pageBreakFor with the same offset does '
          'not re-split, drop or repeat the queue', () async {
        final specs = _fieldLikeSpecs();
        final breakOffset = specs.first.pageBreakOffset!;
        final expectedTexts = _expectedPlayedTexts(
          specs,
          profile.maxRequestChars,
        );
        final session = await _openCloudAudit(specs: specs, profile: profile);
        addTearDown(session.dispose);

        await session.start();
        await session.runToEnd();

        expect(session.state.hasError, isFalse,
            reason: 'no error expected: ${session.state.error}');
        expect(session.state.phase, TtsPlaybackPhase.stopped,
            reason: 'the session must finish instead of stalling');

        // --- 1. Request texts: `.a` + `.b` + following slices, verbatim. ---
        expect(session.engine.requestTexts, expectedTexts,
            reason: 'the `.b` re-query must not re-split the remainder (which '
                'would add `.b.a`/`.b.b` requests) or re-order the queue');
        expect(
          session.engine.requestTexts.join(),
          specs.map((spec) => spec.text).join(),
          reason: 'splitting at the page boundary must not lose or duplicate '
              'a single character',
        );
        final requestIds =
            session.engine.requests.map((request) => request.utteranceId);
        expect(
          requestIds.whereType<String>().where((id) => id.endsWith('.a')),
          hasLength(1),
          reason: '`.a` must be requested exactly once',
        );
        expect(
          requestIds.whereType<String>().where((id) => id.endsWith('.b')),
          hasLength(1),
          reason: '`.b` must be requested exactly once',
        );
        expect(
          requestIds
              .whereType<String>()
              .where((id) => id.contains('.b.a') || id.contains('.b.b')),
          isEmpty,
          reason: 'the second pageBreakFor query must be a no-op, not a '
              're-split of the already emitted `.b`',
        );

        // --- 2. Display ranges: `.a`/`.b` cover the sentence contiguously. ---
        _expectDisplayRangesPartition(session.observedUtterances, specs[0], 0);
        final observedSlice0 = session.observedUtterances
            .where((unit) => unit.sliceIndex == 0)
            .toList(growable: false);
        expect(observedSlice0, hasLength(2),
            reason: 'the 55-char sentence is one unit before the page split, '
                'so exactly `.a` and `.b` must be emitted; got '
                '${observedSlice0.map((unit) => unit.id).toList()}');
        expect(observedSlice0.first.range.start, 0);
        expect(observedSlice0.first.range.end, breakOffset,
            reason: '`.a` must end exactly at the page boundary');
        expect(observedSlice0.last.range.start, breakOffset,
            reason: '`.b` must start exactly at the page boundary');

        // --- 3. The double query really happened, while the turn is in
        //        flight, and both answers carried the same offset. ---
        final queries = session.source.pageBreakQueries
            .where((query) => query.cfi == specs.first.cfi)
            .toList(growable: false);
        final turn = session.source.pageBreakTurns.single;
        expect(queries, hasLength(2),
            reason: 'expected the first query plus the `.b` re-query (field '
                'log: 09:29:21.060 and 09:29:22.255); got $queries');
        expect(queries.first.offset, breakOffset);
        expect(queries[1].offset, breakOffset,
            reason: 'field log: during the animation the bridge still answers '
                'with offset=4/55');
        expect(queries[1].atMs, greaterThanOrEqualTo(turn.requestedAtMs),
            reason: 'the re-query must happen after the page turn was '
                'requested');
        expect(queries[1].atMs, lessThan(turn.completedAtMs!),
            reason: 'the re-query must happen while the page-turn animation '
                'is still in flight (that is when the stale offset is seen)');

        // --- 4. Exactly one page turn, after `.a` finished, once. ---
        expect(session.source.pageBreakTurns, hasLength(1));
        final pageBreakTurnEvents = session.log.events
            .where((event) =>
                event.kind == Round2EventKind.pageTurnRequested &&
                event.data['source'] == 'pageBreak')
            .toList(growable: false);
        expect(pageBreakTurnEvents, hasLength(1),
            reason: '`_pageBreakTurns`/`_turnedBreaks` must not schedule a '
                'second page turn for `.b`');
        final aCompleted = _eventIndex(
          session.log,
          Round2EventKind.audioCompleted,
          where: (event) => event.data['startIndex'] == 0,
        );
        final turnRequested = _eventIndex(
          session.log,
          Round2EventKind.pageTurnRequested,
          where: (event) => event.data['source'] == 'pageBreak',
        );
        final bStarted = _eventIndex(
          session.log,
          Round2EventKind.audioStarted,
          where: (event) => event.data['startIndex'] == 1,
        );
        expect(aCompleted, greaterThanOrEqualTo(0),
            reason: '\n${session.log.describe(limit: 40)}');
        expect(turnRequested, greaterThan(aCompleted),
            reason: 'the page turn must start after the page-last-char `.a` '
                'segment completed');
        expect(bStarted, greaterThan(turnRequested),
            reason: 'the remainder `.b` must only start after the turn was '
                'requested');
        expect(turn.pageBreak.charOffsetInSlice, breakOffset);

        // --- 5. `.b` completion advances to the next slice, never repeats. ---
        final bCompleted = _eventIndex(
          session.log,
          Round2EventKind.audioCompleted,
          where: (event) => event.data['startIndex'] == 1,
        );
        final firstAdvanceRequested =
            _eventIndex(session.log, Round2EventKind.sliceAdvanceRequested);
        expect(firstAdvanceRequested, greaterThan(bCompleted),
            reason: 'the reader must advance only after the remainder `.b` '
                'finished, not after `.a`');
        final advanceCompleted = session.log.events
            .where((event) =>
                event.kind == Round2EventKind.sliceAdvanceCompleted &&
                event.data['endOfSource'] != true)
            .map((event) => event.label)
            .toList(growable: false);
        expect(advanceCompleted, <String>[specs[1].cfi, specs[2].cfi],
            reason: 'slices must be consumed in order, each exactly once');
        expect(session.source.advanceCalls, 3,
            reason: 'one advance per finished slice (the last one ends the '
                'book)');
        expect(
            session.audio.starts
                .where((start) => start.utteranceId.endsWith('.b')),
            hasLength(1),
            reason: '`.b` audio must start exactly once');
        expect(
          session.audio.starts.map((start) => start.utteranceId).toList(),
          <String>[
            '${specs[0].cfi}#0.a',
            '${specs[0].cfi}#0.b',
            '${specs[1].cfi}#0',
            '${specs[2].cfi}#0',
          ],
          reason: 'playback order must be `.a`, `.b`, next slice, next slice',
        );
        // ignore: avoid_print
        print('[metric][A][${profile.name}] queries=$queries '
            'turn=$turn requests=${session.engine.requestTexts}');
      });
    }
  });

  // =========================================================================
  // 2. Multi-unit slice: the page break falls inside the FIRST engine unit,
  //    and the `.b` re-query must not eat the remaining units of the slice.
  // =========================================================================
  group('B. page break inside a multi-unit slice', () {
    const profile = Round2EngineProfile(
      name: 'aliyun-small',
      kind: TtsEngineKind.aliyun,
      maxRequestChars: 20,
      appliesRateOnServer: true,
      synthesisLatency: Duration(milliseconds: 320),
      maxParallelRequests: 2,
    );
    const text = '　　他站在门口望着远处的山，然后慢慢停下了脚步，心里想着明天的事情。';
    const following = <Round2SliceSpec>[
      Round2SliceSpec(
        cfi: 'cfi-multi-1',
        text: '第二页的第一句话。',
        pageToken: 'page-2',
      ),
      Round2SliceSpec(
        cfi: 'cfi-multi-2',
        text: '第三句话。',
        pageToken: 'page-3',
      ),
    ];

    test('pages/multi-unit: split first unit, keep the remaining units',
        () async {
      final baseSpecs = <Round2SliceSpec>[
        const Round2SliceSpec(
          cfi: 'cfi-multi-0',
          text: text,
          pageToken: 'page-1',
        ),
        ...following,
      ];
      final baseUnits = round2ExpectedUnits(baseSpecs, profile.maxRequestChars);
      final firstUnit = baseUnits.first;
      expect(firstUnit.sliceIndex, 0);
      expect(
        baseUnits.where((unit) => unit.sliceIndex == 0).length,
        greaterThan(1),
        reason: 'sample must split into several engine requests, otherwise '
            'this test does not exercise the remaining-unit queue',
      );
      final breakOffset = firstUnit.range.start + firstUnit.range.length ~/ 2;
      expect(breakOffset, greaterThan(firstUnit.range.start));
      expect(breakOffset, lessThan(firstUnit.range.end));
      final specs = <Round2SliceSpec>[
        Round2SliceSpec(
          cfi: baseSpecs[0].cfi,
          text: baseSpecs[0].text,
          pageToken: 'page-1',
          pageBreakOffset: breakOffset,
          pageAfterBreakToken: 'page-2',
        ),
        ...following,
      ];
      final expectedTexts = _expectedPlayedTexts(
        specs,
        profile.maxRequestChars,
      );
      final session = await _openCloudAudit(specs: specs, profile: profile);
      addTearDown(session.dispose);

      await session.start();
      await session.runToEnd();

      expect(session.state.hasError, isFalse,
          reason: 'no error expected: ${session.state.error}');
      expect(session.engine.requestTexts, expectedTexts,
          reason: 'every unit of the split slice must be requested once, in '
              'order (`.a`, `.b`, remaining units, next slices)');
      expect(session.engine.requestTexts.join(),
          specs.map((spec) => spec.text).join());
      _expectDisplayRangesPartition(session.observedUtterances, specs[0], 0);
      expect(session.source.pageBreakTurns, hasLength(1));
      final queries = session.source.pageBreakQueries
          .where((query) => query.cfi == specs.first.cfi)
          .toList(growable: false);
      expect(queries, hasLength(2),
          reason: '`.b` is still `unitIndex == 0`, so the pipeline asks again; '
              'got $queries');
      expect(queries[1].offset, breakOffset,
          reason: 'the stale in-flight answer must be the same offset');
      final turn = session.source.pageBreakTurns.single;
      expect(queries[1].atMs, lessThan(turn.completedAtMs!));
      final advanceCompleted = session.log.events
          .where((event) =>
              event.kind == Round2EventKind.sliceAdvanceCompleted &&
              event.data['endOfSource'] != true)
          .map((event) => event.label)
          .toList(growable: false);
      expect(advanceCompleted, <String>[specs[1].cfi, specs[2].cfi],
          reason: 'the remaining units must all play before the reader '
              'advances; a re-split would drop or duplicate them');
      // ignore: avoid_print
      print('[metric][B] breakOffset=$breakOffset '
          'expected=$expectedTexts queries=$queries');
    });

    test('page ends exactly at the first unit boundary: turn after that unit',
        () async {
      final baseSpecs = <Round2SliceSpec>[
        const Round2SliceSpec(
          cfi: 'cfi-boundary-0',
          text: text,
          pageToken: 'page-1',
        ),
        ...following,
      ];
      final baseUnits = round2ExpectedUnits(baseSpecs, profile.maxRequestChars);
      final firstUnit = baseUnits.first;
      expect(
        baseUnits.where((unit) => unit.sliceIndex == 0).length,
        greaterThan(1),
        reason: 'sample must have a following unit after the page boundary',
      );
      final breakOffset = firstUnit.range.end;
      expect(breakOffset, greaterThan(0));
      expect(breakOffset, lessThan(text.length));
      final specs = <Round2SliceSpec>[
        Round2SliceSpec(
          cfi: baseSpecs[0].cfi,
          text: baseSpecs[0].text,
          pageToken: 'page-1',
          pageBreakOffset: breakOffset,
          pageAfterBreakToken: 'page-2',
        ),
        ...following,
      ];
      final expectedTexts = _expectedPlayedTexts(
        specs,
        profile.maxRequestChars,
      );
      final session = await _openCloudAudit(specs: specs, profile: profile);
      addTearDown(session.dispose);

      await session.start();
      await session.runToEnd();

      expect(session.state.hasError, isFalse,
          reason: 'no error expected: ${session.state.error}');
      expect(session.engine.requestTexts, expectedTexts,
          reason: 'a page boundary exactly at a unit end must not split that '
              'unit or duplicate the following one');
      final queries = session.source.pageBreakQueries
          .where((query) => query.cfi == specs.first.cfi)
          .toList(growable: false);
      expect(queries, hasLength(1),
          reason: 'no `.a`/`.b` unit is created, so the pipeline must not ask '
              'again for this slice; got $queries');
      expect(session.source.pageBreakTurns, hasLength(1));
      final firstUnitCompleted = _eventIndex(
        session.log,
        Round2EventKind.audioCompleted,
        where: (event) => event.data['startIndex'] == 0,
      );
      final turnRequested = _eventIndex(
        session.log,
        Round2EventKind.pageTurnRequested,
        where: (event) => event.data['source'] == 'pageBreak',
      );
      final secondUnitStarted = _eventIndex(
        session.log,
        Round2EventKind.audioStarted,
        where: (event) => event.data['startIndex'] == 1,
      );
      expect(turnRequested, greaterThan(firstUnitCompleted),
          reason: 'the page must turn right after the unit ending at the page '
              'boundary');
      expect(secondUnitStarted, greaterThan(turnRequested),
          reason: 'the following unit must only start after the turn request');
      // ignore: avoid_print
      print('[metric][B-boundary] breakOffset=$breakOffset '
          'expected=$expectedTexts queries=$queries');
    });
  });

  // =========================================================================
  // 3. System TTS: same split contract, but the bridge is queried once per
  //    slice load instead of once per slice-first unit (no double query).
  // =========================================================================
  group('C. system TTS page-break path', () {
    test('queries the page break once per slice and plays `.a`/`.b` in order',
        () async {
      final specs = _fieldLikeSpecs();
      final breakOffset = specs.first.pageBreakOffset!;
      const systemMaxRequestChars = 4000;
      final expectedTexts = _expectedPlayedTexts(
        specs,
        systemMaxRequestChars,
      );
      final scheduler = Round2Scheduler();
      final log = Round2EventLog();
      final source = _InFlightBridgeTextSource(
        specs: specs,
        scheduler: scheduler,
        log: log,
      );
      final native = Round2NativeEngine(scheduler: scheduler, log: log);
      final system = SystemTts.withEngine(native);
      addTearDown(() async {
        await system.dispose();
        await scheduler.flush(turns: 1);
      });

      await system.init(textSource: source);
      await system.speak();
      await scheduler.runUntilDone(
        system.currentSession,
        timeout: const Duration(seconds: 15),
        reason: 'system page-break pipeline audit',
      );
      await scheduler.flush();

      expect(system.playbackState.hasError, isFalse,
          reason: 'no error expected: ${system.playbackState.error}');
      expect(native.spokenTexts, expectedTexts,
          reason: 'system TTS must speak the same `.a`/`.b`/following text as '
              'the online pipeline');
      expect(native.spokenTexts.join(), specs.map((spec) => spec.text).join());
      final queries = source.pageBreakQueries
          .where((query) => query.cfi == specs.first.cfi)
          .toList(growable: false);
      expect(queries, hasLength(1),
          reason: 'SystemTts._loadSlice queries the bridge once per slice; '
              'it must not re-query for `.b` (online does); got $queries');
      expect(queries.single.offset, breakOffset);
      expect(source.pageBreakTurns, hasLength(1));
      final pageBreakTurnEvents = log.events
          .where((event) =>
              event.kind == Round2EventKind.pageTurnRequested &&
              event.data['source'] == 'pageBreak')
          .toList(growable: false);
      expect(pageBreakTurnEvents, hasLength(1));
      final aCompleted = _eventIndex(log, Round2EventKind.nativeSpeakCompleted,
          where: (event) => event.label == expectedTexts[0]);
      final turnRequested = _eventIndex(
        log,
        Round2EventKind.pageTurnRequested,
        where: (event) => event.data['source'] == 'pageBreak',
      );
      final bStarted = _eventIndex(log, Round2EventKind.nativeSpeakStarted,
          where: (event) => event.label == expectedTexts[1]);
      expect(aCompleted, greaterThanOrEqualTo(0),
          reason: '\n${log.describe(limit: 40)}');
      expect(turnRequested, greaterThan(aCompleted),
          reason: 'the page turn must be requested after the `.a` segment');
      expect(bStarted, greaterThan(turnRequested),
          reason: '`.b` must start after the turn request');
      final advanceCompleted = log.events
          .where((event) =>
              event.kind == Round2EventKind.sliceAdvanceCompleted &&
              event.data['endOfSource'] != true)
          .map((event) => event.label)
          .toList(growable: false);
      expect(advanceCompleted, <String>[specs[1].cfi, specs[2].cfi]);
      // ignore: avoid_print
      print(
          '[metric][C][system] queries=$queries spoken=${native.spokenTexts}');
    });
  });
}
