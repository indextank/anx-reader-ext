import 'package:flutter/foundation.dart';

/// 阅读正文字号的像素/em 换算与 Ctrl+↑ / Ctrl+↓ 调整逻辑（纯函数，可单测）。
///
/// 阅读器把 [BookStyle.fontSize] 以 em 写入 foliate-js：
/// `html { font-size: <em>em }`，WebView 根字号为浏览器默认的 16px，
/// 因此渲染出的像素字号 = em × [cssRootFontSizePx]。
///
/// 快捷键两侧的允许范围用像素表达（默认 10px – 30px，每次 1px），
/// 与样式面板中 0.5–3.0 的 em 滑块相互独立：区间内的调整始终落在
/// 10–30px；若当前字号因样式面板而超出该区间，则朝区间内调整会夹入
/// 10–30px、朝区间外调整保持不变（保证放大不变小、缩小不变大）。
abstract final class ReaderFontSize {
  static const double cssRootFontSizePx = 16.0;

  /// 快捷键允许的最小正文像素字号。
  static const double minPx = 10.0;

  /// 快捷键允许的最大正文像素字号。
  static const double maxPx = 30.0;

  /// 每次按下 Ctrl+↑ / Ctrl+↓ 调整的像素步长。
  static const double stepPx = 1.0;

  /// 阅读器 em 字号 → 渲染像素字号。
  static double pxForEm(double em) => em * cssRootFontSizePx;

  /// 渲染像素字号 → 阅读器 em 字号。
  static double emForPx(double px) => px / cssRootFontSizePx;

  /// 把像素字号夹到快捷键允许区间。
  static double clampPx(double px) =>
      px.clamp(minPx, maxPx).toDouble();

  /// 把 em 字号夹到快捷键允许区间。
  static double clampEm(double em) => emForPx(clampPx(pxForEm(em)));

  /// 计算一次 Ctrl+↑（[increase]）或 Ctrl+↓ 之后的 em 字号。
  ///
  /// 方向语义始终一致：放大（[increase]）不会让字号变小、缩小不会让字号
  /// 变大。已到边界时返回与输入等价的值（调用方据此跳过无变化的写入）。
  /// 当前字号可能因样式面板滑块（0.5–3.0em，即 8–48px）而落在快捷键区间
  /// 之外：此时朝区间内调整会一次夹入 10–30px，朝区间外调整则保持不变。
  static double adjustedEm(
    double currentEm, {
    required bool increase,
  }) {
    final currentPx = pxForEm(currentEm);
    if (increase) {
      if (currentPx >= maxPx) return currentEm;
      return emForPx(clampPx(currentPx + stepPx));
    }
    if (currentPx <= minPx) return currentEm;
    return emForPx(clampPx(currentPx - stepPx));
  }

  /// 当前字号是否已到（或超出）快捷键上限。
  static bool isAtMaxPx(double em) => pxForEm(em) >= maxPx - 1e-6;

  /// 当前字号是否已到（或低于）快捷键下限。
  static bool isAtMinPx(double em) => pxForEm(em) <= minPx + 1e-6;

  /// 该目标平台是否默认启用字号快捷键。
  ///
  /// 需求：Windows / macOS / Linux 默认支持；Web、移动端与 OHOS 不启用，
  /// 避免占用其它平台的系统/辅助功能快捷键。
  static bool supportsShortcutOn(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return false;
    // 用相等比较而非穷举 switch：未来新增平台（如 OHOS 枚举值）自然回落为
    // 不启用，不需要修改这里，也不会产生不穷尽的静态告警。
    return platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
  }
}
