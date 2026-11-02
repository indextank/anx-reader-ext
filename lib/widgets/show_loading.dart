import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart'
    show SmartDialog;

void showLoading() {
  SmartDialog.show(
    builder: (context) =>
        Center(child: FilledContainer(child: CircularProgressIndicator())),
  );
}

void _dismissLoading() {
  SmartDialog.dismiss();
}

/// 在 [body] 执行期间显示全局 loading；无论正常返回还是抛出都保证关闭，
/// 异常原样传播（无 catch）。
///
/// [show] / [dismiss] 默认为 [showLoading] / `SmartDialog.dismiss`，
/// 暴露为参数只是为了能在不依赖 SmartDialog overlay 的单元测试里验证异常路径。
Future<T> runWithLoading<T>(
  Future<T> Function() body, {
  void Function() show = showLoading,
  void Function() dismiss = _dismissLoading,
}) async {
  show();
  try {
    return await body();
  } finally {
    dismiss();
  }
}
