import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:flutter/material.dart';

/// 样式面板中滑杆行的行首图标 + 标签。
///
/// 与 [IconAndText] 的固定 48dp 宽不同，这里宽度由内容决定、不缩放文字：
/// 保证英文等较长标签也以单行完整展示；宽度解析端按
/// `sliderLeading + label + labelGap + 控件` 计入同一度量。
class StylePanelSliderLabel extends StatelessWidget {
  const StylePanelSliderLabel({
    super.key,
    required this.icon,
    required this.text,
  });

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final metrics = StylePanelDensity.of(context);
    return SizedBox(
      height: StylePanelTokens.sliderLabelHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(width: metrics.labelGap),
          Text(
            text,
            style: StylePanelTokens.optionLabel(context),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}
