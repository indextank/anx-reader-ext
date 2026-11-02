import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('batch 2b settings pages contain no hard-coded style literals', () {
    const files = [
      'lib/page/settings_page/ai.dart',
      'lib/page/settings_page/ai_provider_detail_page.dart',
      'lib/page/settings_page/ai_provider_list_page.dart',
      'lib/page/settings_page/subpage/ai_chat_page.dart',
      'lib/page/settings_page/developer/developer_options_page.dart',
      'lib/page/settings_page/developer/vibration_test_page.dart',
    ];
    final patterns = [
      RegExp(r'\bColor\s*\(\s*0x[0-9a-fA-F]+'),
      RegExp(r'\bColors\.[A-Za-z_]'),
      RegExp(r'\bfontSize\s*:\s*-?\d'),
      RegExp(
        r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\s*\(',
      ),
      RegExp(r'\bBorderRadius\.(?:circular|vertical|horizontal|only)\s*\('),
    ];
    final violations = <String>[];

    for (final fileName in files) {
      final file = File(p.join(Directory.current.path, fileName));
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.trimLeft().startsWith('//')) continue;
        if (patterns.any((pattern) => pattern.hasMatch(line))) {
          violations.add('$fileName:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
