import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/mimo/mimo_tts_backend.dart';
import 'package:anx_reader/service/tts/mimo/mimo_tts_models.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, dynamic> _baseConfig = {
  'url': 'https://api.xiaomimimo.com/v1/chat/completions',
  'key': 'test-api-key',
  'model': 'mimo-v2.5-tts',
  'voice': 'mimo_default',
  'format': 'mp3',
  'instruction': '',
  'timeout': 5,
};

Map<String, dynamic> _successResponse({String base64Data = 'AAAA'}) => {
      'id': 'resp-1',
      'model': 'mimo-v2.5-tts',
      'object': 'chat.completion',
      'created': 1760000000,
      'choices': [
        {
          'index': 0,
          'finish_reason': 'stop',
          'message': {
            'role': 'assistant',
            'content': '',
            'audio': {'id': 'audio-1', 'data': base64Data},
          },
        }
      ],
    };

Future<void> _initPrefsWith(Map<String, dynamic> config) async {
  SharedPreferences.setMockInitialValues({
    'onlineTtsConfig_mimo': jsonEncode(config),
  });
  await Prefs().initPrefs();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('engine registration', () {
    test('mimo is a registered TtsService with its provider', () {
      final service = getTtsService('mimo');
      expect(service, TtsService.mimo);
      expect(service.isOnline, isTrue);
      expect(service.provider, isA<MimoTtsProvider>());
      expect(service.provider.serviceId, 'mimo');
    });
  });

  group('MimoTtsConfig', () {
    test('fills documented defaults for missing values', () {
      final config = MimoTtsConfig.fromMap({});
      expect(config.url, MimoTtsConfig.defaultUrl);
      expect(config.model, MimoTtsConfig.defaultModel);
      expect(config.voice, MimoTtsConfig.defaultVoice);
      expect(config.format, MimoTtsConfig.defaultFormat);
      expect(config.timeoutSeconds, MimoTtsConfig.defaultTimeoutSeconds);
      expect(config.apiKey, '');
      expect(config.instruction, '');
    });

    test('falls back to the default timeout for invalid values', () {
      expect(MimoTtsConfig.fromMap({'timeout': 0}).timeoutSeconds,
          MimoTtsConfig.defaultTimeoutSeconds);
      expect(MimoTtsConfig.fromMap({'timeout': 'x'}).timeoutSeconds,
          MimoTtsConfig.defaultTimeoutSeconds);
      expect(MimoTtsConfig.fromMap({'timeout': 42}).timeoutSeconds, 42);
    });
  });

  group('buildMimoHeaders / buildMimoRequestBody', () {
    test('uses the documented api-key header', () {
      final headers = buildMimoHeaders('mk-123');
      expect(headers['api-key'], 'mk-123');
      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('puts the text into the assistant message by default', () {
      final body = buildMimoRequestBody(
        model: 'mimo-v2.5-tts',
        text: '你好，世界',
        voice: 'mimo_default',
        format: 'mp3',
      );
      expect(body['model'], 'mimo-v2.5-tts');
      expect(body['audio'], {'voice': 'mimo_default', 'format': 'mp3'});

      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect(messages.first, {'role': 'assistant', 'content': '你好，世界'});
      // MiMo documents no speed/pitch parameters, none must be invented.
      expect(body.containsKey('speed'), isFalse);
      expect(body.containsKey('rate'), isFalse);
    });

    test('prepends the optional user message when an instruction is set', () {
      final body = buildMimoRequestBody(
        model: 'mimo-v2.5-tts',
        text: '目标文本',
        voice: 'mimo_default',
        format: 'mp3',
        instruction: ' Bright, bouncy tone ',
      );
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(
          messages.first, {'role': 'user', 'content': 'Bright, bouncy tone'});
      expect(messages.last, {'role': 'assistant', 'content': '目标文本'});
    });
  });

  group('parseMimoResponse', () {
    test('decodes the base64 audio payload', () {
      final payload = base64Encode([9, 9, 9]);
      final result = parseMimoResponse(_successResponse(base64Data: payload));
      expect(result, [9, 9, 9]);
    });

    test('treats empty audio data as an empty result', () {
      final result = parseMimoResponse(_successResponse(base64Data: ''));
      expect(result, isEmpty);
    });

    test('throws a readable error when choices are missing', () {
      expect(
        () => parseMimoResponse({
          'error': {'message': 'bad'}
        }),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('no choices'),
        )),
      );
    });

    test('surfaces the content filter rejection', () {
      final response = _successResponse();
      final choices = response['choices'] as List<dynamic>;
      (choices.first as Map<String, dynamic>)['finish_reason'] =
          'content_filter';
      expect(
        () => parseMimoResponse(response),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('content filter'),
        )),
      );
    });

    test('rejects invalid base64 audio', () {
      final response = _successResponse(base64Data: 'not-valid-base64!!!');
      expect(
        () => parseMimoResponse(response),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('base64'),
        )),
      );
    });
  });

  group('normalizeMimoUrl', () {
    test('keeps a full endpoint unchanged', () {
      expect(normalizeMimoUrl('https://api.xiaomimimo.com/v1/chat/completions'),
          'https://api.xiaomimimo.com/v1/chat/completions');
    });

    test('appends the path to a base URL', () {
      expect(normalizeMimoUrl('https://token-plan-cn.xiaomimimo.com/v1'),
          'https://token-plan-cn.xiaomimimo.com/v1/chat/completions');
      expect(normalizeMimoUrl('https://api.xiaomimimo.com'),
          'https://api.xiaomimimo.com/chat/completions');
    });

    test('strips trailing slashes before appending', () {
      expect(normalizeMimoUrl('https://host.com/v1/'),
          'https://host.com/v1/chat/completions');
      expect(normalizeMimoUrl('https://host.com/v1//'),
          'https://host.com/v1/chat/completions');
    });

    test('falls back to the default endpoint when empty or blank', () {
      expect(normalizeMimoUrl(''), MimoTtsConfig.defaultUrl);
      expect(normalizeMimoUrl('   '), MimoTtsConfig.defaultUrl);
    });
  });

  group('MimoTtsProvider.speak', () {
    setUp(() => _initPrefsWith(_baseConfig));

    test('synthesizes audio and sends a documented request', () async {
      http.Request? captured;
      final audio = base64Encode(List.filled(64, 3));
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode(_successResponse(base64Data: audio)), 200);
      });
      final provider = MimoTtsProvider.forTesting(client: client);

      final result = await provider.speak('你好', null, 1.0, 1.0);

      expect(result, List.filled(64, 3));
      expect(captured!.url.toString(),
          'https://api.xiaomimimo.com/v1/chat/completions');
      expect(captured!.headers['api-key'], 'test-api-key');
      expect(captured!.headers.containsKey('Authorization'), isFalse);

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], 'mimo-v2.5-tts');
      expect(body['audio'], {'voice': 'mimo_default', 'format': 'mp3'});
      final messages = body['messages'] as List<dynamic>;
      expect(messages.last, {'role': 'assistant', 'content': '你好'});
      // The API key must never leak into the request body.
      expect(captured!.body.contains('test-api-key'), isFalse);
    });

    test('accepts a base URL and posts to the full endpoint', () async {
      await _initPrefsWith({
        ..._baseConfig,
        'url': 'https://token-plan-cn.xiaomimimo.com/v1',
      });
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode(_successResponse(base64Data: base64Encode([1, 2]))),
            200);
      });
      final provider = MimoTtsProvider.forTesting(client: client);

      await provider.speak('你好', null, 1.0, 1.0);

      expect(captured!.url.toString(),
          'https://token-plan-cn.xiaomimimo.com/v1/chat/completions');
    });

    test('throws a readable error on auth failure (401)', () async {
      final client = MockClient((request) async =>
          http.Response('{"error":{"message":"invalid api key"}}', 401));
      final provider = MimoTtsProvider.forTesting(client: client);

      await expectLater(
        provider.speak('你好', null, 1.0, 1.0),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('MiMo'), contains('401'), contains('API key')),
        )),
      );
    });

    test('treats empty audio data as an empty result', () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode(_successResponse(base64Data: '')), 200));
      final provider = MimoTtsProvider.forTesting(client: client);

      final result = await provider.speak('你好', null, 1.0, 1.0);
      expect(result, isEmpty);
    });

    test('times out when the server exceeds the configured timeout', () async {
      await _initPrefsWith({..._baseConfig, 'timeout': 1});
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return http.Response(jsonEncode(_successResponse()), 200);
      });
      final provider = MimoTtsProvider.forTesting(client: client);

      await expectLater(
        provider.speak('你好', null, 1.0, 1.0),
        throwsA(isA<TimeoutException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('throws when the API key is missing', () async {
      await _initPrefsWith({..._baseConfig, 'key': ''});
      final notCalled = MockClient((request) async {
        fail('no HTTP request should be made without a key');
      });
      final provider = MimoTtsProvider.forTesting(client: notCalled);

      await expectLater(
        provider.speak('你好', null, 1.0, 1.0),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('MiMo'), contains('key')),
        )),
      );
    });

    test('returns an empty result for blank text without a request', () async {
      final notCalled = MockClient((request) async {
        fail('no HTTP request should be made for blank text');
      });
      final provider = MimoTtsProvider.forTesting(client: notCalled);

      final result = await provider.speak('  ', null, 1.0, 1.0);
      expect(result, isEmpty);
    });

    test('getVoices returns the documented presets', () async {
      final provider = MimoTtsProvider.forTesting();
      final voices = await provider.getVoices();
      expect(
        voices.map((v) => v.shortName),
        containsAll(['mimo_default', '冰糖', '茉莉', 'Mia', 'Dean']),
      );
      expect(provider.getSelectedVoice(), 'mimo_default');
    });
  });
}
