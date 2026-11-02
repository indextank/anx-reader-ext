import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'style_audit_rules.dart';

void main() {
  test('design system sources are audited while theme tokens remain exempt',
      () {
    expect(
      _isAllowedStyleSource('lib/design_system/buttons/app_button.dart'),
      isFalse,
    );
    expect(_isAllowedStyleSource('lib/theme/app_spacing.dart'), isTrue);
  });

  test('first-party production styles use centralized tokens', () {
    final root = Directory.current;
    final violations = <String>[];

    final dartFiles = Directory(p.join(root.path, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !_isGeneratedDart(file.path))
        .where((file) => !_isAllowedStyleSource(file.path));
    for (final file in dartFiles) {
      final rel = p.relative(file.path, from: root.path).replaceAll('\\', '/');
      if (dartBusinessAllowlist.containsKey(rel)) continue;
      _collectViolations(
        file: file,
        root: root,
        isViolation: isDartViolation,
        violations: violations,
      );
    }

    final jsSource = Directory(
      p.join(root.path, 'assets', 'foliate-js', 'src'),
    );
    final jsFiles = jsSource
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.js'))
        .where((file) => p.basename(file.path) != jsTokenSource)
        .where((file) =>
            !p.isWithin(jsSource.path, file.path) ||
            !p
                .split(p.relative(file.path, from: jsSource.path))
                .contains('vendor'));
    for (final file in jsFiles) {
      _collectViolations(
        file: file,
        root: root,
        isViolation: isJsViolation,
        violations: violations,
      );
    }

    expect(
      violations,
      isEmpty,
      reason: '${violations.length} hard-coded style occurrences found:\n'
          '${violations.take(200).join('\n')}',
    );
  });
}

bool _isGeneratedDart(String path) {
  final normalized = p.normalize(path);
  return normalized.endsWith('.g.dart') ||
      normalized.endsWith('.freezed.dart') ||
      p.split(normalized).contains('generated');
}

bool _isAllowedStyleSource(String path) {
  final normalized = p.normalize(path);
  final segments = p.split(normalized);
  final libIndex = segments.lastIndexOf('lib');
  if (libIndex < 0 || libIndex + 1 >= segments.length) return false;
  return segments[libIndex + 1] == 'theme';
}

void _collectViolations({
  required File file,
  required Directory root,
  required bool Function(String line) isViolation,
  required List<String> violations,
}) {
  final lines = file.readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.trimLeft().startsWith('//')) continue;
    if (isViolation(line)) {
      violations.add('${p.relative(file.path, from: root.path)}:${index + 1}: '
          '${line.trim()}');
    }
  }
}
