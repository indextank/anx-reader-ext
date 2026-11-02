import 'package:flutter_test/flutter_test.dart';
import 'style_audit_rules.dart';

void main() {
  group('JS 规则', () {
    test('结构重置与相对单位豁免', () {
      for (final l in [
        '  padding: 0;',
        '  margin: 0 !important;',
        '  border-radius: 50%;',
        '  margin: -1px;',
        '  padding: 1px;',
        '  font-size: 1em !important;',
        '  margin: 0.5em 0;',
        '  margin: 3em 0;',
        '  padding: 0.2em 0.4em !important;',
      ]) {
        expect(isJsViolation(l), isFalse, reason: l);
      }
    });
    test('设计值判违规', () {
      for (final l in [
        '  border-radius: 6px !important;',
        '  border-radius: 4px 0 0 4px;',
        '  border-radius: 2px;',
        "  color: '#39c5bbaa';",
        '  font-size: 24px;',
        "overlayer.add(value, range, Overlayer.outline, { color: '#39c5bbaa' });",
      ]) {
        expect(isJsViolation(l), isTrue, reason: l);
      }
    });
    test('var() 回退剥离后不判违规', () {
      expect(
          isJsViolation('  border-radius: var(--anx-chrome-radius-sm, 4px);'),
          isFalse);
      expect(isJsViolation('  border-radius: var(--a, 4px) 0 0 var(--a, 4px);'),
          isFalse);
      expect(isJsViolation('  font-size: var(--anx-overlay-font-size, 24px);'),
          isFalse);
    });
    test('calc() 缩放相对值剥离后不判违规', () {
      expect(isJsViolation('  font-size: calc(9px * var(--scale-factor));'),
          isFalse);
      expect(isJsViolation('  border-radius: calc(2px * var(--scale-factor));'),
          isFalse);
      expect(isJsViolation('  padding: calc(6px * var(--scale-factor));'),
          isFalse);
    });
    test('非缩放 calc 内的绝对 px 仍判违规', () {
      expect(isJsViolation('  padding: calc(100% - 16px);'), isTrue);
      expect(isJsViolation('  margin: calc(2px + 1em);'), isTrue);
    });
  });
  group('Dart 规则', () {
    test('字面量判违规、令牌不判', () {
      expect(isDartViolation('padding: const EdgeInsets.all(16),'), isTrue);
      expect(isDartViolation('color: Colors.red,'), isTrue);
      expect(isDartViolation('padding: AppSpacing.all(tokens.cardPadding),'),
          isFalse);
      expect(isDartViolation('color: context.appTheme.colors.error,'), isFalse);
    });
  });
  group('白名单', () {
    test('路径为 lib/ 下且理由非空', () {
      for (final e in dartBusinessAllowlist.entries) {
        expect(e.key, startsWith('lib/'));
        expect(e.value.trim(), isNotEmpty);
      }
    });
  });
}
