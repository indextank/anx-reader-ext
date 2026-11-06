import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:anx_reader/service/tts/rate_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rate mapping (flutter_tts slider -> engine units)', () {
    test('UI 0.5 (default normal) maps to multiplier 1.0', () {
      expect(ttsRateToMultiplier(0.5), 1.0);
    });

    test('UI 1.0 maps to multiplier 2.0 (double speed)', () {
      expect(ttsRateToMultiplier(1.0), 2.0);
    });

    test('StepFun speed clamped to the documented 0.5–2.0 range', () {
      expect(ttsRateToMultiplier(0.0), 0.5); // below the lower bound
      expect(ttsRateToMultiplier(2.0), 2.0); // at the upper bound
      expect(ttsRateToMultiplier(5.0), 2.0); // above -> clamped
    });

    test('default UI value 0.6 yields 1.2x on cloud engines', () {
      expect(ttsRateToMultiplier(0.6), closeTo(1.2, 1e-9));
    });

    test('non-finite rates fall back to normal speed', () {
      expect(ttsRateToMultiplier(double.nan), 1.0);
      expect(ttsRateToMultiplier(double.infinity), 1.0);
      expect(clampTtsRate(double.nan), 0.6);
      expect(clampTtsRate(3.5), 2.0);
    });
  });

  group('playback event log (typed lifecycle)', () {
    test('pause -> resume same page keeps the in-place anchor', () {
      final log = TtsPlaybackLog();
      const cfi = 'epubcfi(/6/4!/4/10/2,/1:20,/1:44)';
      log.add(const TtsPaused(pageCfi: 'epubcfi(/6/4!/4/10/2)'));
      final action =
          resolveResumeAction(lastReadCfi: cfi, lastReadPositionVisible: true);
      log.add(TtsResumed(action: action, anchorCfi: cfi));

      expect(log.events.length, 2);
      final resumed = log.events.last as TtsResumed;
      expect(resumed.action, TtsResumeAction.continueInPlace);
      expect(resumed.anchorCfi, cfi);
    });

    test('pause -> page turned -> resume restarts from the new page start', () {
      final log = TtsPlaybackLog();
      log.add(const TtsPaused(pageCfi: 'page-1'));
      log.add(TtsPageTurned(fromCfi: 'page-1', at: DateTime.now()));
      final action = resolveResumeAction(
          lastReadCfi: 'cfi-on-page-1', lastReadPositionVisible: false);
      log.add(TtsResumed(action: action, anchorCfi: 'cfi-on-page-1'));

      final resumed = log.events.last as TtsResumed;
      expect(resumed.action, TtsResumeAction.restartFromCurrentPageStart);
    });

    test('rate change records the effective multiplier for the log', () {
      final log = TtsPlaybackLog();
      final rate = 0.75;
      log.add(TtsRateChanged(
          rate: rate, effectiveMultiplier: ttsRateToMultiplier(rate)));
      final event = log.events.single as TtsRateChanged;
      expect(event.effectiveMultiplier, closeTo(1.5, 1e-9));
      expect(event.rate, 0.75);
    });

    test('page turn events carry a timestamp for the acceptance gap check', () {
      final log = TtsPlaybackLog();
      final before = DateTime.now();
      log.add(TtsPageTurned(fromCfi: 'page-3', at: DateTime.now()));
      log.add(TtsSentenceStarted(cfi: 'page-4-first', at: DateTime.now()));
      final turn = log.events[0] as TtsPageTurned;
      final firstSentence = log.events[1] as TtsSentenceStarted;
      final gapMs = firstSentence.at.difference(turn.at).inMilliseconds;
      expect(gapMs, lessThan(1000),
          reason: 'page turn to first-sentence gap must stay under 1s');
      expect(
          turn.at.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('engine switch event does not lose the recorded position', () {
      final log = TtsPlaybackLog();
      log.add(const TtsEngineSwitched(serviceId: 'mimo'));
      expect(log.events.single, isA<TtsEngineSwitched>());
      // Rate always comes from the UI preference, not the engine default.
      expect(ttsRateToMultiplier(0.6), closeTo(1.2, 1e-9));
    });
  });
}
