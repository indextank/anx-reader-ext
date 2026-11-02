import 'package:anx_reader/enums/excerpt_share_template.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/theme/content_style_tokens.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

// 分享图必须像素级一致：令牌值与改造前的字面量逐一相等。
// 用例 2 选 elegant 模板且 chapter 为 null，是因为它是唯一一个
// 横排 `Text` 字号恰为 {bodyFontSize, captionFontSize} 的模板
// （其余模板的标题/作者/Logo 走命名参数默认值 20/14/12，竖排文字是 MongolText）。
void main() {
  group('ShareStyleTokens.palettes', () {
    test('keeps the six legacy palettes bit-for-bit', () {
      // (text, background) —— 值与 lib/theme/content_style_tokens.dart 一致，
      // 即改造前 bottom sheet 里 Colors.* / Color.fromARGB 字面量的 ARGB。
      const expected = <(int, int)>[
        (0xFF000000, 0xFFFFFFFF),
        (0xFFF6D995, 0xFF302C1C),
        (0xFF000000, 0xFFFFECB3),
        (0xFFFFFFFF, 0xFF37474F),
        (0xFF000000, 0xFFFCE4EC),
        (0xFFFFFFFF, 0xFF1A237E),
      ];

      expect(ShareStyleTokens.palettes.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        final (text, background) = expected[i];
        final palette = ShareStyleTokens.palettes[i];
        expect(palette.text, Color(text), reason: 'palette[$i].text');
        expect(
          palette.background,
          Color(background),
          reason: 'palette[$i].background',
        );
      }
    });
  });

  group('ExcerptShareCard', () {
    testWidgets('elegant template renders only token font sizes',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const tokens = ShareStyleTokens();
      final palette = ShareStyleTokens.palettes.first;

      await pumpDesignSystem(
        tester,
        Center(
          child: ExcerptShareCard(
            bookTitle: 'Book',
            author: 'Author',
            excerpt: 'Excerpt text',
            template: ExcerptShareTemplateEnum.elegantTemplate,
            font: FontModel(label: 'System', name: 'system', path: 'system'),
            textColor: palette.text,
            backgroundColor: palette.background,
            tokens: tokens,
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final sizes = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(ExcerptShareCard),
            matching: find.byType(Text),
          ))
          .map((text) => text.style?.fontSize)
          .whereType<double>()
          .toSet();

      expect(sizes, contains(tokens.bodyFontSize));
      expect(sizes, contains(tokens.captionFontSize));

      final allowed = <double>{
        tokens.bodyFontSize,
        tokens.accentFontSize,
        tokens.captionFontSize,
      };
      final strays = sizes.difference(allowed);
      expect(
        strays,
        isEmpty,
        reason: 'unexpected literal font sizes on Text widgets: $strays',
      );
    });
  });
}
