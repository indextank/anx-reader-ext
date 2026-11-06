import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:flutter/material.dart';

/// 打开朗读引擎的完整设置面板（引擎服务、密钥、音色等）。
///
/// 阅读页的朗读面板和悬浮播放器共用同一入口，避免两处各写一份底部弹层
/// 参数。关闭后引擎可能已切换，调用方自行刷新播放状态。
Future<void> showTtsEngineSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.7,
      child: AppSafeArea(
        top: false,
        minimum: AppReadingTokens.contentPadding,
        child: const NarrateSettings(),
      ),
    ),
  );
}
