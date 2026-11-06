import 'dart:typed_data';

import 'package:anx_reader/service/tts/engine/provider_tts_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One expected row of the provider capability matrix.
typedef _CapabilityCase = ({
  TtsService service,
  TtsEngineKind kind,
  String engineId,
  int maxRequestChars,
  bool rateOnServer,
  String limitNoteContains,
});

const List<_CapabilityCase> _capabilityCases = <_CapabilityCase>[
  (
    service: TtsService.system,
    kind: TtsEngineKind.system,
    engineId: 'system',
    maxRequestChars: 800,
    rateOnServer: true,
    limitNoteContains: 'No documented request limit',
  ),
  (
    service: TtsService.aliyun,
    kind: TtsEngineKind.aliyun,
    engineId: 'aliyun',
    // Root cause fix: the Aliyun REST TTS API documents 300 characters.
    maxRequestChars: 300,
    rateOnServer: true,
    limitNoteContains: '300-character',
  ),
  (
    service: TtsService.azure,
    kind: TtsEngineKind.azure,
    engineId: 'azure',
    maxRequestChars: 800,
    rateOnServer: true,
    limitNoteContains: 'No documented request limit',
  ),
  (
    service: TtsService.openai,
    kind: TtsEngineKind.openai,
    engineId: 'openai',
    maxRequestChars: 800,
    rateOnServer: true,
    limitNoteContains: '4096',
  ),
  (
    service: TtsService.stepaudio,
    kind: TtsEngineKind.stepAudio,
    engineId: 'stepaudio',
    maxRequestChars: 1000,
    rateOnServer: true,
    limitNoteContains: '1000-character',
  ),
  (
    service: TtsService.mimo,
    kind: TtsEngineKind.mimo,
    engineId: 'mimo',
    maxRequestChars: 800,
    // MiMo has no documented speed parameter: the audio player applies rate.
    rateOnServer: false,
    limitNoteContains: 'No documented request limit',
  ),
];

TtsSynthesisRequest _request(
  String text, {
  TtsEngineKind engine = TtsEngineKind.aliyun,
  String? voice,
  double rate = 1.0,
  double pitch = 1.0,
  double volume = 1.0,
  String? utteranceId,
}) {
  return TtsSynthesisRequest(
    text: text,
    config: TtsSpeechConfig(
      rate: rate,
      pitch: pitch,
      volume: volume,
      voice: voice,
    ),
    engine: engine,
    utteranceId: utteranceId,
  );
}

class _SpeakCall {
  const _SpeakCall(this.text, this.voice, this.rate, this.pitch);

  final String text;
  final String? voice;
  final double rate;
  final double pitch;
}

/// Provider double that records [speak] arguments and lets a test force a
/// failure, so the adapter can be verified without any network access.
class _FakeTtsProvider extends TtsServiceProvider {
  _FakeTtsProvider({
    this.service = TtsService.aliyun,
    this.maxRequestChars = 300,
    this.supportsRateParameter = true,
    this.supportsNativePause = false,
    this.reportsCharacterProgress = false,
    this.documentedRequestLimitNote = 'Fake engine documents a 300 limit',
    this.maxConcurrentSynthesisRequests = 2,
    this.minSynthesisRequestInterval = Duration.zero,
    Uint8List? audio,
    List<TtsVoice>? availableVoices,
  })  : audio = audio ?? Uint8List.fromList(const <int>[1, 2, 3]),
        availableVoices = availableVoices ??
            const <TtsVoice>[
              TtsVoice(
                shortName: 'fake-voice',
                name: 'Fake Voice',
                locale: 'en',
              )
            ];

  @override
  final TtsService service;

  @override
  final int maxRequestChars;

  @override
  final bool supportsRateParameter;

  @override
  final bool supportsNativePause;

  @override
  final bool reportsCharacterProgress;

  @override
  final String documentedRequestLimitNote;

  @override
  final int maxConcurrentSynthesisRequests;

  @override
  final Duration minSynthesisRequestInterval;

  final Uint8List audio;
  final List<TtsVoice> availableVoices;
  final List<_SpeakCall> calls = <_SpeakCall>[];

  /// When non-null, [speak] throws this instead of returning [audio].
  Object? error;

  @override
  String getLabel(BuildContext context) => 'Fake TTS';

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    calls.add(_SpeakCall(text, voice, rate, pitch));
    final failure = error;
    if (failure != null) throw failure;
    return audio;
  }

  @override
  Future<List<TtsVoice>> getVoices() async => availableVoices;
}

/// Provider whose service is not a [TtsService]; the adapter must reject it.
class _BadServiceProvider extends TtsServiceProvider {
  @override
  dynamic get service => 'not-a-tts-service';

  @override
  String getLabel(BuildContext context) => 'Bad provider';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('provider capability matrix', () {
    for (final testCase in _capabilityCases) {
      test('${testCase.service.name} exposes its documented capabilities', () {
        final provider = testCase.service.provider;

        expect(provider.serviceId, testCase.engineId);
        expect(provider.maxRequestChars, testCase.maxRequestChars);
        expect(provider.supportsRateParameter, testCase.rateOnServer);
        expect(provider.documentedRequestLimitNote, isNotEmpty);
        expect(
          provider.documentedRequestLimitNote,
          contains(testCase.limitNoteContains),
          reason: 'the limit note must carry the documented evidence',
        );
      });
    }

    test('cloud engines never claim native pause / character progress', () {
      for (final service in TtsService.values) {
        final provider = service.provider;
        // Cloud engines pause the audio player; the system engine's native
        // pause capability lives on TtsNativeSpeechEngine, not the provider.
        expect(provider.supportsNativePause, isFalse,
            reason: '$service must not pause natively via the provider');
        expect(provider.reportsCharacterProgress, isFalse,
            reason: '$service must not claim character progress');
      }
    });

    test('the Aliyun provider limit is the documented 300 characters', () {
      expect(TtsService.aliyun.provider.maxRequestChars, 300);
      expect(TtsService.aliyun.provider.supportsRateParameter, isTrue);
    });

    test('MiMo keeps applying the rate on the audio player', () {
      expect(TtsService.mimo.provider.supportsRateParameter, isFalse);
    });

    test('Aliyun spaces synthesis request starts (gateway TOO_MANY_REQUESTS)',
        () {
      // Field evidence: 5-6 simultaneous warm-up/prefetch requests made the
      // Aliyun gateway answer `400 40000005 TOO_MANY_REQUESTS`. The provider
      // adapter gates on these values: 2 concurrent requests (the concurrency
      // the round-2 harness already models for Aliyun) and 250 ms minimum
      // spacing between request starts.
      final aliyun = TtsService.aliyun.provider;
      expect(aliyun.maxConcurrentSynthesisRequests, 2);
      expect(aliyun.minSynthesisRequestInterval,
          const Duration(milliseconds: 250));
    });

    test('other providers keep the shared gate defaults (no rate reduction)',
        () {
      for (final service in TtsService.values) {
        if (service == TtsService.aliyun) continue;
        final provider = service.provider;
        expect(provider.maxConcurrentSynthesisRequests, 2,
            reason: '$service uses the shared concurrency safety cap');
        expect(provider.minSynthesisRequestInterval, Duration.zero,
            reason: '$service must not get extra spacing');
      }
    });
  });

  group('engine kind / id mapping', () {
    for (final testCase in _capabilityCases) {
      test('${testCase.service.name} maps to ${testCase.kind.name}', () {
        final engine = ProviderTtsSynthesisEngine.forService(testCase.service);

        expect(engine.kind, testCase.kind);
        expect(engine.engineId, testCase.engineId);
        expect(engine.capabilities.engine, testCase.kind);
        expect(engine.capabilities.maxRequestChars, testCase.maxRequestChars);
        expect(
          engine.capabilities.appliesRateOnServer,
          testCase.rateOnServer,
        );
        expect(engine.capabilities.supportsNativePause, isFalse);
        expect(engine.capabilities.reportsCharacterProgress, isFalse);
        expect(engine.capabilities.needsOutputWarmup, isFalse);
      });
    }

    test('forServiceId resolves every persisted service id', () {
      for (final testCase in _capabilityCases) {
        final engine = ProviderTtsSynthesisEngine.forServiceId(
          testCase.engineId,
        );
        expect(engine.kind, testCase.kind);
        expect(engine.engineId, testCase.engineId);
      }
    });

    test('forServiceId falls back to system for unknown ids', () {
      final engine = ProviderTtsSynthesisEngine.forServiceId('unknown-engine');
      expect(engine.kind, TtsEngineKind.system);
      expect(engine.engineId, 'system');
    });

    test('forService honours an explicitly supplied provider', () {
      final fake = _FakeTtsProvider(service: TtsService.mimo);
      final engine = ProviderTtsSynthesisEngine.forService(TtsService.mimo,
          provider: fake);

      expect(engine.provider, same(fake));
      expect(engine.kind, TtsEngineKind.mimo);
    });

    test('the request gate resolves the provider gate settings', () {
      final aliyun = ProviderTtsSynthesisEngine.forService(TtsService.aliyun);
      expect(aliyun.requestGate.maxConcurrentRequests, 2);
      expect(aliyun.requestGate.minStartInterval,
          const Duration(milliseconds: 250));

      final fake = _FakeTtsProvider(
        maxConcurrentSynthesisRequests: 3,
        minSynthesisRequestInterval: const Duration(milliseconds: 40),
      );
      final engine = ProviderTtsSynthesisEngine(fake);
      expect(engine.requestGate.maxConcurrentRequests, 3);
      expect(engine.requestGate.minStartInterval,
          const Duration(milliseconds: 40));
    });

    test('rejects a provider that does not expose a TtsService', () {
      expect(
        () => ProviderTtsSynthesisEngine(_BadServiceProvider()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('engine capabilities are provider derived', () {
    test('every getter is forwarded to the provider', () {
      final fake = _FakeTtsProvider(
        maxRequestChars: 123,
        supportsRateParameter: false,
        supportsNativePause: true,
        reportsCharacterProgress: true,
        documentedRequestLimitNote: 'Fake provider documents 123 chars',
      );
      final engine = ProviderTtsSynthesisEngine(fake);

      expect(engine.documentedRequestLimitNote,
          'Fake provider documents 123 chars');
      final capabilities = engine.capabilities;
      expect(capabilities.maxRequestChars, 123);
      expect(capabilities.appliesRateOnServer, isFalse);
      expect(capabilities.supportsNativePause, isTrue);
      expect(capabilities.reportsCharacterProgress, isTrue);
    });
  });

  group('synthesize validation', () {
    test('empty text returns empty bytes without calling the provider',
        () async {
      final fake = _FakeTtsProvider();
      final engine = ProviderTtsSynthesisEngine(fake);

      final result = await engine.synthesize(_request(''));

      expect(result, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('whitespace-only text is a silent segment', () async {
      final fake = _FakeTtsProvider();
      final engine = ProviderTtsSynthesisEngine(fake);

      final result = await engine.synthesize(_request('  \n　 '));

      expect(result, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('text exactly at the limit is accepted', () async {
      final fake = _FakeTtsProvider(maxRequestChars: 300);
      final engine = ProviderTtsSynthesisEngine(fake);
      final text = '字' * 300;

      final result = await engine.synthesize(_request(text));

      expect(result, fake.audio);
      expect(fake.calls.single.text, text);
    });

    test('oversized text throws a typed oversized exception, no request',
        () async {
      final fake = _FakeTtsProvider(maxRequestChars: 300);
      final engine = ProviderTtsSynthesisEngine(fake);

      await expectLater(
        engine.synthesize(_request('字' * 301, utteranceId: 'para#3')),
        throwsA(
          isA<TtsEngineSynthesisException>()
              .having((e) => e.engine, 'engine', TtsEngineKind.aliyun)
              .having((e) => e.isOversized, 'isOversized', isTrue)
              .having((e) => e.cause, 'cause', isNull)
              .having((e) => e.message, 'message', contains('300'))
              .having(
                  (e) => e.context['maxRequestChars'], 'maxRequestChars', '300')
              .having((e) => e.context['textLength'], 'textLength', '301')
              .having((e) => e.context['utteranceId'], 'utteranceId', 'para#3')
              .having((e) => e.context['limitNote'], 'limitNote', isNotEmpty),
        ),
      );
      expect(fake.calls, isEmpty,
          reason: 'oversized text must never reach the provider/HTTP layer');
    });

    test('the real Aliyun engine rejects a 301-char request before config',
        () async {
      final engine = ProviderTtsSynthesisEngine.forService(TtsService.aliyun);

      await expectLater(
        engine.synthesize(_request('字' * 301)),
        throwsA(isA<TtsEngineSynthesisException>()
            .having((e) => e.isOversized, 'isOversized', isTrue)
            .having((e) => e.engine, 'engine', TtsEngineKind.aliyun)),
      );
    });

    test('a non-positive limit means no limit (test engines only)', () async {
      final fake = _FakeTtsProvider(maxRequestChars: 0);
      final engine = ProviderTtsSynthesisEngine(fake);
      final text = 'a' * 5000;

      final result = await engine.synthesize(_request(text));

      expect(result, fake.audio);
      expect(fake.calls.single.text, text);
    });
  });

  group('synthesize forwarding', () {
    test('forwards exact text, voice, rate and pitch to the provider',
        () async {
      final fake = _FakeTtsProvider(maxRequestChars: 1000);
      final engine = ProviderTtsSynthesisEngine(fake);

      final result = await engine.synthesize(_request(
        '你好，世界。',
        voice: 'cixingnansheng',
        rate: 1.5,
        pitch: 0.8,
        volume: 0.6,
      ));

      expect(result, fake.audio);
      final call = fake.calls.single;
      expect(call.text, '你好，世界。');
      expect(call.voice, 'cixingnansheng');
      expect(call.rate, 1.5);
      expect(call.pitch, 0.8);
    });

    test('forwards a null voice so the provider resolves its selection',
        () async {
      final fake = _FakeTtsProvider();
      final engine = ProviderTtsSynthesisEngine(fake);

      await engine.synthesize(_request('短句。'));

      expect(fake.calls.single.voice, isNull);
    });

    test('voices() forwards to the provider voice list', () async {
      final voices = <TtsVoice>[
        const TtsVoice(shortName: 'v1', name: 'Voice 1', locale: 'zh'),
        const TtsVoice(shortName: 'v2', name: 'Voice 2', locale: 'en'),
      ];
      final fake = _FakeTtsProvider(availableVoices: voices);
      final engine = ProviderTtsSynthesisEngine(fake);

      expect(await engine.voices(), same(voices));
    });
  });

  group('synthesize failure wrapping', () {
    test('wraps provider errors in a typed non-oversized exception', () async {
      final fake = _FakeTtsProvider();
      final cause = StateError('boom');
      fake.error = cause;
      final engine = ProviderTtsSynthesisEngine(fake);

      await expectLater(
        engine.synthesize(_request('短句。', voice: 'v1')),
        throwsA(
          isA<TtsEngineSynthesisException>()
              .having((e) => e.engine, 'engine', TtsEngineKind.aliyun)
              .having((e) => e.isOversized, 'isOversized', isFalse)
              .having((e) => e.cause, 'cause', same(cause))
              .having((e) => e.message, 'message', contains('boom'))
              .having((e) => e.context['voice'], 'voice', 'v1')
              .having((e) => e.toString(), 'toString',
                  allOf(contains('aliyun'), contains('boom'))),
        ),
      );
    });

    test('provider exceptions are always wrapped (never leaked raw)', () async {
      final fake = _FakeTtsProvider();
      fake.error = Exception('network down');
      final engine = ProviderTtsSynthesisEngine(fake);

      await expectLater(
        engine.synthesize(_request('短句。')),
        throwsA(isA<TtsEngineSynthesisException>()),
      );
    });
  });

  group('lifecycle', () {
    test('dispose completes and the engine stays usable (shared providers)',
        () async {
      final fake = _FakeTtsProvider();
      final engine = ProviderTtsSynthesisEngine(fake);

      await engine.dispose();
      final result = await engine.synthesize(_request('短句。'));

      expect(result, fake.audio);
    });
  });
}
