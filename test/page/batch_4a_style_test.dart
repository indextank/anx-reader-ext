import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('batch 4a contains no hard-coded style literals', () {
    final root = Directory.current;
    final files = <File>[
      File(p.join(root.path, 'lib/page/home_page/statistics_page.dart')),
      File(p.join(root.path, 'lib/page/iap_page.dart')),
      File(p.join(root.path, 'lib/widgets/tips/statistic_tips.dart')),
      ...Directory(p.join(root.path, 'lib/widgets/statistic'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
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

    for (final file in files) {
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

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
