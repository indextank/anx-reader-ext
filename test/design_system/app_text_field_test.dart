import 'package:anx_reader/design_system/inputs/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppTextField', () {
    testWidgets('validates on user interaction and shows a nearby error',
        (tester) async {
      await pumpDesignSystem(
        tester,
        AppTextField(
          label: 'Email',
          helperText: 'Used for sync',
          validator: (value) => value != null && value.contains('@')
              ? null
              : 'Enter a valid email',
        ),
      );

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.autovalidateMode, AutovalidateMode.onUserInteraction);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Used for sync'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsNothing);

      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.pump();
      expect(find.text('Enter a valid email'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'reader@example.com');
      await tester.pump();
      expect(find.text('Enter a valid email'), findsNothing);
    });

    testWidgets('an external error replaces helper feedback', (tester) async {
      await pumpDesignSystem(
        tester,
        const AppTextField(
          label: 'Password',
          helperText: 'At least eight characters',
          errorText: 'Password is too short',
        ),
      );
      expect(find.text('Password is too short'), findsOneWidget);
    });

    testWidgets('grows instead of clipping at 1.3 text scale', (tester) async {
      const field = AppTextField(
        label: 'Server address',
        helperText: 'Include the protocol and port',
        errorText: 'The server address is invalid. Check it and try again.',
      );
      await pumpDesignSystem(
        tester,
        const SizedBox(width: 280, child: field),
      );
      final normalHeight = tester.getSize(find.byType(AppTextField)).height;
      expect(tester.takeException(), isNull);

      await pumpDesignSystem(
        tester,
        const SizedBox(width: 280, child: field),
        textScaler: const TextScaler.linear(1.3),
      );
      final scaledHeight = tester.getSize(find.byType(AppTextField)).height;
      expect(scaledHeight, greaterThan(normalHeight));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long helper and error text render every line at 1.3 scale',
        (tester) async {
      final feedback = List.filled(
        14,
        'Check the complete server address and authentication details.',
      ).join(' ');
      for (final useError in <bool>[false, true]) {
        await pumpDesignSystem(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: AppTextField(
                label: 'Server address',
                helperText: useError ? null : feedback,
                errorText: useError ? feedback : null,
              ),
            ),
          ),
          textScaler: const TextScaler.linear(1.3),
        );

        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.text(feedback),
        );
        expect(paragraphs, isNotEmpty);
        for (final paragraph in paragraphs) {
          expect(paragraph.maxLines, isNull);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason:
                '${useError ? 'Error' : 'Helper'} text must not be truncated',
          );
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('long validator errors also render every line', (tester) async {
      final error = List.filled(
        14,
        'The entered value is invalid. Review every segment and try again.',
      ).join(' ');
      await pumpDesignSystem(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: AppTextField(
              label: 'Server address',
              validator: (_) => error,
            ),
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );

      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.pump();
      final paragraph = tester.renderObject<RenderParagraph>(find.text(error));
      expect(paragraph.maxLines, isNull);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('suffix interaction remains available to config forms',
        (tester) async {
      var taps = 0;
      await pumpDesignSystem(
        tester,
        AppTextField(
          label: 'Password',
          suffixIcon: IconButton(
            onPressed: () => taps++,
            icon: const Icon(Icons.visibility),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.visibility));
      expect(taps, 1);
    });
  });
}
