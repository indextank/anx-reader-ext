import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('AI widget styles use centralized theme tokens', () {
    final root = Directory.current;
    final source = Directory(p.join(root.path, 'lib', 'widgets', 'ai'));
    final patterns = <RegExp>[
      RegExp(r'\bColor\s*\(\s*0x[0-9a-fA-F]+'),
      RegExp(r'\bColors\.[A-Za-z_]'),
      RegExp(r'\bfontSize\s*:\s*-?\d'),
      RegExp(
        r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\s*\(',
      ),
      RegExp(r'\bBorderRadius\.(?:circular|vertical|horizontal|only)\s*\('),
    ];
    final violations = <String>[];

    for (final file in source.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.trimLeft().startsWith('//')) continue;
        if (patterns.any((pattern) => pattern.hasMatch(line))) {
          violations.add(
            '${p.relative(file.path, from: root.path)}:${index + 1}: '
            '${line.trim()}',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '${violations.length} AI style occurrences found:\n'
          '${violations.join('\n')}',
    );
  });
}
