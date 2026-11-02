import 'package:anx_reader/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardAsyncValue<T> extends StatelessWidget {
  const DashboardAsyncValue({
    super.key,
    required this.value,
    required this.mock,
    required this.builder,
    required this.onRetry,
  });

  final AsyncValue<T> value;
  final T mock;
  final Widget Function(T data, bool isDataReady) builder;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppAsyncValue<T>(
      value: value,
      skeleton: builder(mock, false),
      onRetry: onRetry,
      errorBuilder: (context, error, stackTrace) => AppErrorState(
        compact: true,
        onRetry: onRetry,
      ),
      dataBuilder: (context, data) => builder(data, true),
    );
  }
}
