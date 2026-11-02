import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('batch 5a contains no hard-coded style literals', () {
    final root = Directory.current;
    final files = <File>[
      File(p.join(root.path, 'lib/page/reading_page.dart')),
      ...Directory(p.join(root.path, 'lib/page/book_player'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory(p.join(root.path, 'lib/widgets/reading_page'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory(p.join(root.path, 'lib/widgets/context_menu'))
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
