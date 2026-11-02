import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppAiTokens {
  AppAiTokens._();

  static const defaultChatFontSize = 14.0;
  static const reasoningFontSize = 13.0;
  static const thinkingTitleFontSize = 12.0;
  static const minChatFontSize = 10.0;
  static const maxChatFontSize = 24.0;
  static const chatFontDivisions = 14;
  static const minReasoningFontSize = 11.0;
  static const reasoningFontDelta = 1.0;

  static const historyListPadding = AppSpacing.vertical8;
  static const historyCardMargin = AppSpacing.horizontal8;
  static const historyCardPadding = AppSpacing.all8;
  static const historyCardRadius = BorderRadius.all(Radius.circular(15));
  static const historySeparatorHeight = 6.0;
  static const historyStatusSize = 10.0;
  static const providerLogoSize = 20.0;
  static const providerIconSize = 16.0;
  static const providerSpacing = 6.0;
  static const inputPadding = AppSpacing.all4;
  static const inputRadius = BorderRadius.all(Radius.circular(15));
  static const compactSpacing = 4.0;
  static const contentSpacing = 8.0;
  static const chipSpacing = 6.0;
  static const quickPromptTopPadding = EdgeInsets.only(top: 8);
  static const quickPromptRight = 16.0;
  static const quickPromptBottom = 16.0;
  static const quickPromptHeightFactor = 0.3;
  static const quickPromptIconSize = 18.0;
  static const sendIconSize = 18.0;
  static const fontMenuPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );
  static const consentPadding = AppSpacing.all24;
  static const consentRadius = BorderRadius.all(Radius.circular(20));
  static const consentIconSize = 56.0;
  static const consentMaxWidth = 500.0;
  static const consentWidthFactor = 0.9;
  static const messagePadding = AppSpacing.all12;
  static const messageOuterSpacing = 8.0;
  static const messageUserRadius = BorderRadius.only(
    topLeft: Radius.circular(12),
    bottomRight: Radius.circular(12),
  );
  static const messageAssistantRadius = BorderRadius.only(
    topRight: Radius.circular(12),
    bottomLeft: Radius.circular(12),
  );
  static const collapsedPreviewLength = 300;
  static const collapsedFadeHeight = 40.0;
  static const longMessageThreshold = 300;
  static const thinkingPadding = EdgeInsets.fromLTRB(28, 2, 0, 8);
  static const thinkingMargin = EdgeInsets.only(left: 7);
  static const thinkingContentPadding = EdgeInsets.only(left: 12);
  static const thinkingIconSize = 15.0;
  static const thinkingAccentAlpha = 0.82;
  static const thinkingSubtleAlpha = 0.68;
  static const thinkingBorderAlpha = 0.55;
  static const thinkingBorderWidth = 1.0;
  static const thinkingOpacity = 0.9;
  static const scrollDuration = Duration(milliseconds: 300);

  static const streamLoadingWidth = 300.0;
  static const streamLoadingHeight = 60.0;
  static const codeHeaderPadding = EdgeInsets.only(left: 16);
  static const codeContentPadding = AppSpacing.all16;
  static const codeDividerHeight = 1.0;
  static const codeTextStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    package: 'gpt_markdown',
  );
  static const modelListHeightFactor = 0.35;
  static const modelSectionPadding = EdgeInsets.only(top: 12, bottom: 4);
  static const feedbackTopPadding = EdgeInsets.only(top: 8);

  static const toolCardPadding = EdgeInsets.symmetric(
    vertical: 4,
    horizontal: 12,
  );
  static const toolCardRadius = BorderRadius.all(Radius.circular(14));
  static const toolContentTopPadding = EdgeInsets.only(top: 6);
  static const toolContentPadding = AppSpacing.all8;
  static const toolContentRadius = BorderRadius.all(Radius.circular(6));
  static const toolOutputMaxHeight = 200.0;
  static const toolIconSize = 12.0;
  static const toolCopyIconSize = 12.0;
  static const toolActionIconSize = 14.0;
  static const toolStatusSize = 8.0;
  static const toolCardContentRadius = BorderRadius.all(Radius.circular(10));
  static const toolCardBottomMargin = EdgeInsets.only(bottom: 8);
  static const toolChipPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 2,
  );
  static const toolChipRadius = BorderRadius.all(Radius.circular(12));

  static const mindmapHeight = 360.0;
  static const mindmapRadius = BorderRadius.all(Radius.circular(12));
  static const mindmapFallbackWidth = 320.0;
  static const mindmapFallbackHeight = 320.0;
  static const mindmapMinScale = 0.4;
  static const mindmapMaxScale = 3.5;
  static const mindmapScrollScale = 400.0;
  static const mindmapMaxScaleDelta = 0.5;
  static const mindmapScaleEpsilon = 1e-4;
  static const mindmapNodeMaxWidth = 200.0;
  static const mindmapNodePadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );
  static const mindmapLightForegroundThreshold = 0.55;
  static const mindmapEdgeWidth = 2.0;
  static const mindmapHueStep = 32.0;
  static const mindmapSiblingSeparation = 10;
  static const mindmapLevelSeparation = 200;
  static const mindmapSubtreeSeparation = 20;
}
