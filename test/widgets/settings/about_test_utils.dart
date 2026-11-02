import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mockAboutPubspec(
  WidgetTester tester,
  String? content,
) async {
  const channel = 'flutter/assets';
  final messenger = tester.binding.defaultBinaryMessenger;
  rootBundle.evict('pubspec.yaml');
  messenger.setMockMessageHandler(channel, (message) async {
    final key =
        message == null ? null : utf8.decode(message.buffer.asUint8List());
    if (key != 'pubspec.yaml') {
      return messenger.delegate.send(channel, message);
    }
    if (content == null) return null;
    final bytes = Uint8List.fromList(utf8.encode(content));
    return ByteData.sublistView(bytes);
  });
  addTearDown(() {
    messenger.setMockMessageHandler(channel, null);
    rootBundle.evict('pubspec.yaml');
  });
}
