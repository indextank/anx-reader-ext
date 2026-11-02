import 'dart:async';

import 'package:anx_reader/design_system/feedback/app_async_value.dart';
import 'package:anx_reader/design_system/feedback/app_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'design_system_test_utils.dart';

void main() {
  group('AppAsyncValue', () {
    testWidgets('initial loading shows the supplied skeleton', (tester) async {
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: const AsyncValue.loading(),
          skeleton: const Text('Loading row', key: ValueKey('skeleton')),
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is Skeletonizer),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('skeleton')), findsOneWidget);
      expect(find.text('Count 0'), findsNothing);
    });

    testWidgets('error hides raw details and offers retry', (tester) async {
      var retries = 0;
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: AsyncValue.error(
              StateError('secret database details'), StackTrace.current),
          onRetry: () async => retries++,
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );

      expect(
          find.text("Content couldn't be loaded. Try again."), findsOneWidget);
      expect(find.textContaining('secret database details'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('retry is deduplicated while its Future is pending',
        (tester) async {
      final completer = Completer<void>();
      var attempts = 0;
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: AsyncValue.error(StateError('offline'), StackTrace.current),
          onRetry: () {
            attempts++;
            return completer.future;
          },
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(attempts, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(attempts, 2);
    });

    testWidgets('failed retry reports a safe error and can recover',
        (tester) async {
      var attempts = 0;
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: AsyncValue.error(StateError('offline'), StackTrace.current),
          onRetry: () async {
            attempts++;
            if (attempts == 1) throw StateError('retry secret');
          },
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Action failed. Try again.'), findsOneWidget);
      expect(find.textContaining('retry secret'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty data uses the localized empty state', (tester) async {
      await pumpDesignSystem(
        tester,
        AppAsyncValue<List<int>>(
          value: const AsyncValue.data(<int>[]),
          isEmpty: (data) => data.isEmpty,
          dataBuilder: (context, data) => Text('Count ${data.length}'),
        ),
      );

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Count 0'), findsNothing);
    });

    testWidgets('data builds content', (tester) async {
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: const AsyncValue.data(3),
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );
      expect(find.text('Count 3'), findsOneWidget);
    });

    testWidgets('refresh and an error with previous data preserve content',
        (tester) async {
      final previous = const AsyncValue<int>.data(7);
      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: const AsyncValue<int>.loading().copyWithPrevious(previous),
          skeleton: const Text('Skeleton'),
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );
      expect(find.text('Count 7'), findsOneWidget);
      expect(find.text('Skeleton'), findsNothing);

      await pumpDesignSystem(
        tester,
        AppAsyncValue<int>(
          value: AsyncValue<int>.error(
            StateError('offline'),
            StackTrace.current,
          ).copyWithPrevious(previous),
          dataBuilder: (context, data) => Text('Count $data'),
        ),
      );
      expect(find.text('Count 7'), findsOneWidget);
      expect(find.textContaining('offline'), findsNothing);
    });

    testWidgets('default error and empty states do not overflow at 1.3 scale',
        (tester) async {
      await pumpDesignSystem(
        tester,
        SizedBox(
          width: 280,
          child: AppAsyncValue<int>(
            value: AsyncValue.error(StateError('hidden'), StackTrace.current),
            onRetry: () async {},
            dataBuilder: (context, data) => Text('$data'),
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );
      expect(tester.takeException(), isNull);

      await pumpDesignSystem(
        tester,
        SizedBox(
          width: 280,
          child: AppAsyncValue<List<int>>(
            value: const AsyncValue.data(<int>[]),
            isEmpty: (data) => data.isEmpty,
            dataBuilder: (context, data) => Text('${data.length}'),
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
