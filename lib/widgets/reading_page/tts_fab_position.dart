import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 朗读悬浮播放器的归一化锚点。
///
/// 锚点描述播放器「右下角」在可用舞台（扣除安全区与边距后的矩形）中的相对
/// 位置：
/// - `x = 0` 贴舞台左侧，`x = 1` 贴舞台右侧；
/// - `y = 0` 贴舞台顶部，`y = 1` 贴舞台底部。
///
/// 因此历史默认位置（屏幕右下角）就是 `(1, 1)`，并且持久化的是比例而不是
/// 像素：窗口缩放、横竖屏切换、平板分栏、软键盘弹出后重新布局时，播放器
/// 仍会停留在用户大致放置的相对位置，不会跑到屏幕外。
///
/// 该类型不依赖 Flutter 的偏好/插件层，可独立做纯逻辑测试。
@immutable
class TtsFabAnchor {
  const TtsFabAnchor({required this.x, required this.y});

  /// 历史默认位置：右下角。
  static const TtsFabAnchor defaultAnchor = TtsFabAnchor(x: 1, y: 1);

  final double x;
  final double y;

  bool get isDefault =>
      (x - defaultAnchor.x).abs() < 0.001 &&
      (y - defaultAnchor.y).abs() < 0.001;

  /// 已夹取到 `[0, 1]` 的锚点；用于吸收历史偏好里的非法值。
  TtsFabAnchor get clamped => TtsFabAnchor(
        x: x.clamp(0.0, 1.0).toDouble(),
        y: y.clamp(0.0, 1.0).toDouble(),
      );

  /// 计算 [contentSize] 大小的播放器在 [stage] 内应放置的左上角像素坐标。
  ///
  /// 内容大于舞台时按舞台尺寸处理（不把内容推出可视区）。
  Offset resolve(Rect stage, Size contentSize) {
    final anchor = clamped;
    final width = math.min(contentSize.width, math.max(0.0, stage.width));
    final height = math.min(contentSize.height, math.max(0.0, stage.height));
    final freeX = math.max(0.0, stage.width - width);
    final freeY = math.max(0.0, stage.height - height);
    return Offset(
      stage.left + freeX * anchor.x,
      stage.top + freeY * anchor.y,
    );
  }

  /// 把像素左上角反解为归一化锚点（拖动时使用），结果夹取到 `[0, 1]`。
  static TtsFabAnchor fromPixel(
    Rect stage,
    Size contentSize,
    Offset topLeft,
  ) {
    final width = math.min(contentSize.width, math.max(0.0, stage.width));
    final height = math.min(contentSize.height, math.max(0.0, stage.height));
    final freeX = math.max(0.0, stage.width - width);
    final freeY = math.max(0.0, stage.height - height);
    return TtsFabAnchor(
      x: _normalize(topLeft.dx - stage.left, freeX),
      y: _normalize(topLeft.dy - stage.top, freeY),
    );
  }

  static double _normalize(double offset, double freeSpace) {
    if (freeSpace <= 0) return 0;
    return (offset / freeSpace).clamp(0.0, 1.0).toDouble();
  }

  TtsFabAnchor copyWith({double? x, double? y}) =>
      TtsFabAnchor(x: x ?? this.x, y: y ?? this.y);

  @override
  bool operator ==(Object other) =>
      other is TtsFabAnchor && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'TtsFabAnchor(x: ${x.toStringAsFixed(3)}, y: ${y.toStringAsFixed(3)})';
}
