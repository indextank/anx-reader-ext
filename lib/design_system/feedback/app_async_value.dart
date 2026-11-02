import 'package:anx_reader/design_system/feedback/app_empty_state.dart';
import 'package:anx_reader/design_system/feedback/app_error_state.dart';
import 'package:anx_reader/design_system/feedback/app_loading_indicator.dart';
import 'package:anx_reader/design_system/feedback/app_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppAsyncValue<T> extends StatelessWidget {
  const AppAsyncValue({
    super.key,
    required this.value,
    required this.dataBuilder,
    this.skeleton,
    this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    this.errorBuilder,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) dataBuilder;
  final Widget? skeleton;
  final Future<void> Function()? onRetry;
  final bool Function(T data)? isEmpty;
  final WidgetBuilder? emptyBuilder;
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  )? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final data = value.requireValue;
      if (isEmpty?.call(data) ?? false) {
        return emptyBuilder?.call(context) ?? const AppEmptyState();
      }
      return dataBuilder(context, data);
    }

    if (value.hasError) {
      return errorBuilder?.call(context, value.error!, value.stackTrace) ??
          AppErrorState(onRetry: onRetry);
    }

    if (skeleton != null) return AppSkeleton(child: skeleton!);
    return const Center(child: AppLoadingIndicator());
  }
}
