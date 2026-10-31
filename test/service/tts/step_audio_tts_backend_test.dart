import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/step_audio/step_audio_tts_backend.dart';
import 'package:anx_reader/service/tts/step_audio/step_audio_tts_models.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, dynamic> _baseConfig = {
  'url': 'https://api.stepfun.com/v1/audio/speech',
  'key': 'test-api-key',
  'model': 'step-tts-2',
  'voice': 'cixingnansheng',
  'responseFormat': 'mp3',
  'timeout': 5,
};

Future<void> _initPrefsWith(Map<String, dynamic> config) async {
  SharedPreferences.setMockInitialValues({
    'onlineTtsConfig_stepaudio': jsonEncode(config),
  });
  await Prefs().initPrefs();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('engine registration', () {
    test('stepaudio is a registered TtsService with its provider', () {
      final service = getTtsService('stepaudio');
      expect(service, TtsService.stepaudio);
      expect(service.isOnline, isTrue);
      expect(service.provider, isA<StepAudioTtsProvider>());
      expect(service.provider.serviceId, 'stepaudio');
    });

    test('existing engine ids keep resolving to their own services', () {
      expect(getTtsService('system'), TtsService.system);
      expect(getTtsService('aliyun'), TtsService.aliyun);
      expect(getTtsService('azure'), TtsService.azure);
      expect(getTtsService('openai'), TtsService.openai);
      expect(getTtsService('unknown'), TtsService.system);
    });
  });

  group('StepAudioTtsConfig', () {
    test('fills documented defaults for missing values', () {
      final config = StepAudioTtsConfig.fromMap({});
      expect(config.url, StepAudioTtsConfig.defaultUrl);
      expect(config.model, StepAudioTtsConfig.defaultModel);
      expect(config.voice, StepAudioTtsConfig.defaultVoice);
      expect(config.responseFormat, StepAudioTtsConfig.defaultResponseFormat);
      expect(config.timeoutSeconds, StepAudioTtsConfig.defaultTimeoutSeconds);
      expect(config.apiKey, '');
    });

    test('falls back to the default timeout for invalid values', () {
      expect(StepAudioTtsConfig.fromMap({'timeout': 0}).timeoutSeconds,
          StepAudioTtsConfig.defaultTimeoutSeconds);
      expect(StepAudioTtsConfig.fromMap({'timeout': 'abc'}).timeoutSeconds,
          StepAudioTtsConfig.defaultTimeoutSeconds);
      expect(StepAudioTtsConfig.fromMap({'timeout': 42}).timeoutSeconds, 42);
    });
  });

  group('buildStepAudioHeaders / buildStepAudioRequestBody', () {
    test('uses Bearer auth as documented', () {
      final headers = buildStepAudioHeaders('sk-123');
      expect(headers['Authorization'], 'Bearer sk-123');
      expect(headers['Content-Type'], 'application/json');
    });

    test('builds a body with only documented fields', () {
      final body = buildStepAudioRequestBody(
        model: 'step-tts-2',
        input: '你好世界',
        voice: 'cixingnansheng',
        responseFormat: 'mp3',
        speed: 1.0,
      );
      expect(body.keys.toSet(), {
        'model',
        'input',
        'voice',
        'response_format',
        'speed',
        'text_normalization',
      });
      expect(body['input'], '你好世界');
    });

    test('clamps speed into the documented 0.5-2.0 range', () {
      expect(clampStepAudioSpeed(0.1), 0.5);
      expect(clampStepAudioSpeed(3.0), 2.0);
      expect(clampStepAudioSpeed(1.4), 1.4);
    });
  });

  group('normalizeStepAudioUrl', () {
    test('keeps a full endpoint unchanged', () {
      expect(normalizeStepAudioUrl('https://api.stepfun.com/v1/audio/speech'),
          'https://api.stepfun.com/v1/audio/speech');
    });

    test('appends the path to a base URL', () {
      expect(normalizeStepAudioUrl('https://api.stepfun.com/v1'),
          'https://api.stepfun.com/v1/audio/speech');
    });

    test('strips trailing slashes before appending', () {
      expect(normalizeStepAudioUrl('https://api.stepfun.com/v1/'),
          'https://api.stepfun.com/v1/audio/speech');
    });

    test('falls back to the default endpoint when empty', () {
      expect(normalizeStepAudioUrl(''), StepAudioTtsConfig.defaultUrl);
    });
  });

  group('parseStepAudioResponse', () {
    test('returns the raw binary body on success', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = parseStepAudioResponse(
        statusCode: 200,
        bodyBytes: bytes,
        bodyText: '',
      );
      expect(result, bytes);
    });

    test('treats an empty 200 body as an empty result', () {
      final result = parseStepAudioResponse(
        statusCode: 200,
        bodyBytes: Uint8List(0),
        bodyText: '',
      );
      expect(result, isEmpty);
    });

    test('throws a readable message on auth failure', () {
      expect(
        () => parseStepAudioResponse(
          statusCode: 401,
          bodyBytes: Uint8List(0),
          bodyText: '{"error":"invalid api key"}',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('401'), contains('API key')),
        )),
      );
    });
  });

  group('StepAudioTtsProvider.speak', () {
    setUp(() => _initPrefsWith(_baseConfig));

    test('synthesizes audio and sends a documented request', () async {
      http.Request? captured;
      final audio = Uint8List.fromList(List.filled(64, 7));
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(audio, 200);
      });
      final provider = StepAudioTtsProvider.forTesting(client: client);

      final result = await provider.speak('hello', null, 1.0, 1.0);

      expect(result, audio);
      expect(captured!.url.toString(),
          'https://api.stepfun.com/v1/audio/speech');
      expect(captured!.headers['Authorization'], 'Bearer test-api-key');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], 'step-tts-2');
      expect(body['input'], 'hello');
      expect(body['voice'], 'cixingnansheng');
      expect(body['response_format'], 'mp3');
      expect(body['speed'], 1.0);
      // Long-form reading defaults to the doc-recommended enhanced mode.
      expect(body['text_normalization'], 'enhanced');
      // The API key must never leak into the request body.
      expect(captured!.body.contains('test-api-key'), isFalse);
    });

    test('resolves the voice override over the configured voice', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList([1]), 200);
      });
      final provider = StepAudioTtsProvider.forTesting(client: client);

      await provider.speak('hi', 'customvoice', 1.0, 1.0);

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['voice'], 'customvoice');
    });

    test('throws a readable error on auth failure (401)', () async {
      final client = MockClient((request) async =>
          http.Response('{"error":{"message":"invalid key"}}', 401));
      final provider = StepAudioTtsProvider.forTesting(client: client);

      await expectLater(
        provider.speak('hello', null, 1.0, 1.0),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('StepAudio'), contains('401'), contains('API key')),
        )),
      );
    });

    test('treats an empty audio response as an empty result', () async {
      final client =
          MockClient((request) async => http.Response.bytes(Uint8List(0), 200));
      final provider = StepAudioTtsProvider.forTesting(client: client);

      final result = await provider.speak('hello', null, 1.0, 1.0);
      expect(result, isEmpty);
    });

    test('times out when the server exceeds the configured timeout',
        () async {
      await _initPrefsWith({..._baseConfig, 'timeout': 1});
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return http.Response.bytes(Uint8List.fromList([1]), 200);
      });
      final provider = StepAudioTtsProvider.forTesting(client: client);

      await expectLater(
        provider.speak('hello', null, 1.0, 1.0),
        throwsA(isA<TimeoutException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('throws when the API key is missing', () async {
      await _initPrefsWith({..._baseConfig, 'key': ''});
      final notCalled = MockClient((request) async {
        fail('no HTTP request should be made without a key');
      });
      final provider = StepAudioTtsProvider.forTesting(client: notCalled);

      await expectLater(
        provider.speak('hello', null, 1.0, 1.0),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('StepAudio'), contains('key')),
        )),
      );
    });

    test('returns an empty result for blank text without a request',
        () async {
      final notCalled = MockClient((request) async {
        fail('no HTTP request should be made for blank text');
      });
      final provider = StepAudioTtsProvider.forTesting(client: notCalled);

      final result = await provider.speak('   ', null, 1.0, 1.0);
      expect(result, isEmpty);
    });

    test('getVoices returns the full official voice list', () async {
      final provider = StepAudioTtsProvider.forTesting();
      final voices = await provider.getVoices();

      // The official docs list 36 preset voices.
      expect(voices.length, 36);
      // Every voice ID is unique.
      expect(voices.map((v) => v.shortName).toSet().length, 36);
      // Both documented ID styles are covered (hyphenated and pinyin).
      expect(voices.map((v) => v.shortName),
          containsAll(['vibrant-youth', 'magnetic-voiced-male']));
      // The default voice stays available and is a valid choice.
      expect(voices.map((v) => v.shortName), contains('cixingnansheng'));
      // Display metadata is complete for every entry.
      for (final voice in voices) {
        expect(voice.name, isNotEmpty);
        expect(voice.locale, 'zh');
        expect(voice.description, isNotEmpty);
      }
      expect(provider.getSelectedVoice(), 'cixingnansheng');
    });
  });
}
