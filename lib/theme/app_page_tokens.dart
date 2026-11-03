import 'package:flutter/material.dart';

class AppNavigationTokens {
  AppNavigationTokens._();

  static const desktopBreakpoint = 1000.0;
  static const railBreakpoint = 600.0;
  static const railElevation = 3.0;
  static const logoSize = 32.0;
  static const bottomBarWidth = 330.0;
  static const bottomBarMinHeight = 64.0;
  static const bottomBarBlur = 10.0;
  static const bottomBarBorderWidth = 0.5;
}

class AppOnboardingTokens {
  AppOnboardingTokens._();

  static const dotSize = Size(10, 10);
  static const activeDotSize = Size(22, 10);
  static const heroIconSize = 120.0;
  static const heroIconPadding = EdgeInsets.all(40);
  static const controlsPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const bodyPadding = EdgeInsets.only(left: 16, right: 16, bottom: 96);
  static const imagePadding = EdgeInsets.symmetric(vertical: 40);
  static const dropdownPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 4,
  );
  static const colorGridCrossAxisCount = 6;
  static const colorSelectionBorderWidth = 2.0;
}

class AppSettingsTokens {
  AppSettingsTokens._();

  static const scrollPadding = EdgeInsets.only(bottom: 80);
  static const brandPadding = EdgeInsets.only(top: 60, bottom: 20);
  static const themeModePadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 8,
  );
  static const sectionTitlePadding = EdgeInsetsDirectional.only(
    start: 24,
    end: 24,
    top: 12,
    bottom: 8,
  );
  static const tileContentPadding = EdgeInsetsDirectional.only(
    start: 16,
    end: 8,
    top: 12,
    bottom: 12,
  );
  static const tileTrailingPadding = EdgeInsetsDirectional.only(end: 8);
  static const aboutMaxWidth = 500.0;
  static const aboutWidthFactor = 0.8;
  static const socialIconSize = 30.0;
  static const colorPickerHeightPercent = 0.8;
}

class AppMigrationTokens {
  AppMigrationTokens._();

  static const statusIconSize = 64.0;
}

class AppSettingsAiTokens {
  AppSettingsAiTokens._();

  static const pagePadding = EdgeInsets.all(16);
  static const sectionPadding = EdgeInsets.all(16);
  static const userPromptPadding = EdgeInsets.all(8);
  static const userPromptCardMargin = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );
  static const userPromptAnimationDuration = Duration(milliseconds: 200);
  static const chatPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
  static const advancedTilePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );
  static const apiKeyMargin = EdgeInsets.only(bottom: 8);
  static const rpmFieldWidth = 80.0;
  static const segmentedIconSize = 18.0;
  static const providerLogoSize = 32.0;
  static const advancedIconContainerSize = 34.0;
  static const modelPickerHeight = 360.0;
  static const cacheSliderMax = 1000.0;
  static const cacheSliderDivisions = 100;
}

class AppDeveloperTokens {
  AppDeveloperTokens._();

  static const pagePadding = EdgeInsets.all(16);
  static const listPadding = EdgeInsets.symmetric(vertical: 8);
  static const capabilityPadding = EdgeInsets.symmetric(vertical: 4);
  static const capabilityIconSize = 20.0;
}

class AppSettingsBatchTokens {
  AppSettingsBatchTokens._();

  static const narrateScrollPadding = EdgeInsets.only(bottom: 48);
  static const narrateConfigPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );
  static const narrateFormPadding = EdgeInsets.only(
    left: 16,
    right: 16,
    top: 8,
    bottom: 16,
  );
  static const narrateHighlightDuration = Duration(milliseconds: 1500);
  static const narrateScrollDuration = Duration(milliseconds: 500);
  static const voiceAvatarRadius = 24.0;
  static const storageDetailsHeightOffset = 140.0;
  static const syncHelpPadding = EdgeInsets.only(
    left: 40,
    right: 20,
    bottom: 12,
  );
  static const logLevelPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 2,
  );
}

class AppBookshelfTokens {
  AppBookshelfTokens._();

  static const filterBarHeight = 40.0;
  static const filterBarPadding = EdgeInsets.fromLTRB(12, 0, 12, 5);
  static const filterChipPadding = EdgeInsets.symmetric(horizontal: 4);
  static const filterChipLabelPadding = EdgeInsets.zero;
  static const filterChipTrailing = EdgeInsets.only(right: 8);
  static const selectedTagPadding = EdgeInsets.only(left: 8);
  static const tagMenuPadding = EdgeInsets.all(12);
  static const tagMenuMaxHeight = 360.0;
  static const tagMenuContentMaxHeight = 340.0;
  static const tagMenuWidthFactor = 0.8;
  static const tagMenuMinWidth = 500.0;
  static const gridPadding = EdgeInsets.fromLTRB(20, 12, 20, 80);
  static const hintMargin = EdgeInsets.fromLTRB(20, 0, 20, 5);
  static const gridAspectRatio = 1 / 2.1;
  static const gridMainSpacing = 30.0;
  static const gridCrossSpacing = 20.0;
  static const searchHeight = 34.0;
  static const searchMaxWidth = 400.0;
  static const searchPadding = EdgeInsets.symmetric(horizontal: 12);
  static const dragIconSize = 48.0;
  static const bottomSheetPadding = EdgeInsets.all(20);
  static const bottomSheetCoverWidth = 40.0;
  static const bottomSheetCoverHeight = 64.0;
  static const bottomSheetSpacing = 10.0;
  static const bookMetadataHeight = 76.0;
  static const bookSyncIconSize = 20.0;
  static const folderRadius = 10.0;
  static const folderPreviewPadding = EdgeInsets.all(6);
  static const folderPreviewAspectRatio = 1 / 1.6;
  static const folderPreviewMainSpacing = 16.0;
  static const folderPreviewCrossSpacing = 6.0;
  static const folderNameHeight = 64.0;
  static const folderDialogWidthFactor = 0.7;
  static const folderDialogAspectRatio = 1 / 2.2;
  static const folderDialogSpacing = 10.0;
  static const folderEditIconSize = 18.0;
  static const folderRemoveIconSize = 30.0;
  static const syncSheetPadding = EdgeInsets.all(16);
  static const syncTipIconSize = 16.0;
  static const syncChartHeight = 24.0;
  static const coverRadius = 8.0;
  static const coverTitleFactor = 0.12;
  static const coverAuthorFactor = 0.08;
  static const coverIconFactor = 0.8;
  static const coverPaddingFactor = 0.08;
  static const coverBorderWidth = 0.3;
  static const coverIconRotation = 15.0;
  static const skeletonItemCount = 6;

  static BorderRadius coverBorderRadius(double radius) =>
      BorderRadius.circular(radius);

  static EdgeInsets coverPadding(double padding) => EdgeInsets.all(padding);
}

class AppBookDetailTokens {
  AppBookDetailTokens._();

  static const backgroundHeightFactor = 0.8;
  static const backgroundScale = 1.1;
  static const backgroundBlur = 10.0;
  static const backgroundAlphaHigh = 200;
  static const backgroundAlphaMedium = 150;
  static const backgroundAlphaLow = 10;
  static const collapsedAppBarAlpha = 80;
  static const baseTop = 60.0;
  static const baseContentHeight = 280.0;
  static const baseCardTop = 150.0;
  static const baseCardHeight = 120.0;
  static const baseCardMargin = EdgeInsets.only(bottom: 3);
  static const progressPadding = EdgeInsets.all(20);
  static const progressSize = 100.0;
  static const progressStroke = 6.0;
  static const coverLeft = 20.0;
  static const coverWidth = 160.0;
  static const coverHeight = 230.0;
  static const coverRadius = 10.0;
  static const coverShadowAlpha = 128;
  static const coverShadowSpread = 6.0;
  static const coverShadowBlur = 30.0;
  static const coverShadowOffset = Offset(0, 3);
  static const ratingLeft = 30.0;
  static const ratingTop = 240.0;
  static const ratingItemSize = 20.0;
  static const ratingItemPadding = EdgeInsets.symmetric(horizontal: 4);
  static const titleLeft = 190.0;
  static const titleTop = 5.0;
  static const titleHeight = 140.0;
  static const titleSpacing = 5.0;
  static const editHintMargin = EdgeInsets.only(right: 10);
  static const editButtonSpacing = 5.0;
  static const statisticsHeight = 130.0;
  static const statisticsPadding = EdgeInsets.symmetric(horizontal: 10);
  static const statisticsItemPadding = EdgeInsets.symmetric(horizontal: 20);
  static const statisticsDividerThickness = 1.0;
  static const statisticsDividerIndent = 15.0;
  static const tagEditorMargin = EdgeInsets.symmetric(vertical: 10);
  static const tagEditorPadding = EdgeInsets.all(12);
  static const tagInputMaxWidth = 180.0;
  static const tagInputPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );
  static const moreDetailPadding = EdgeInsets.all(12);
  static const pagePadding = EdgeInsets.fromLTRB(20, 0, 20, 20);
  static const wideDetailPadding = EdgeInsets.symmetric(vertical: 20);
  static const wideBreakpoint = 600.0;
  static const wideSpacing = 20.0;
  static const sectionSpacing = 15.0;
}

class AppNotesTokens {
  AppNotesTokens._();

  static const infoPadding = EdgeInsets.all(10);
  static const infoWideBreakpoint = 500.0;
  static const infoCoverWidth = 120.0;
  static const infoCoverHeight = 180.0;
  static const infoCoverRadius = 20.0;
  static const infoCoverSpacing = 30.0;
  static const infoActionSpacing = 25.0;
  static const pagePadding = EdgeInsets.all(20);
  static const pageContentSpacing = 170.0;
  static const exportPadding = EdgeInsets.all(16);
  static const exportLoadingHeight = 120.0;
  static const exportSectionSpacing = 20.0;
  static const exportHintSpacing = 12.0;
  static const exportMergePadding = EdgeInsets.only(top: 12);
  static const exportSortPadding = EdgeInsets.only(right: 8);
  static const wideBreakpoint = 600.0;
  static const dividerSize = 1.0;
  static const statisticsPadding = EdgeInsets.all(10);
  static const listPadding = EdgeInsets.only(bottom: 80);
  static const listCardMargin = EdgeInsets.only(top: 8, left: 15, right: 15);
  static const listCardPadding = EdgeInsets.all(8);
  static const listCoverWidth = 90.0;
  static const listCoverHeight = 130.0;
  static const listCoverRadius = 20.0;
  static const metadataIconSize = 16.0;
}

class AppSearchTokens {
  AppSearchTokens._();

  static const debounce = Duration(milliseconds: 300);
  static const appBarPadding = EdgeInsets.only(right: 8);
  static const inputPadding = EdgeInsets.symmetric(horizontal: 12);
  static const bodyPadding = EdgeInsets.all(16);
  static const sectionSpacing = 24.0;
  static const titleSpacing = 6.0;
  static const cardPadding = EdgeInsets.all(12);
  static const manyBooksThreshold = 6;
  static const coverScale = 1.5;
  static const coverAspectRatio = 2.1;
  static const tileExtraHeight = 55.0;
  static const sectionExtraHeight = 32.0;
  static const gridSpacing = 16.0;
  static const gridPadding = EdgeInsets.only(bottom: 8);
  static const noteGroupSpacing = 18.0;
  static const noteTitleSpacing = 4.0;
  static const noteRadius = 16.0;
  static const notePadding = EdgeInsets.only(bottom: 12);
}

class AppTagTokens {
  AppTagTokens._();

  static const densePadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 2,
  );
  static const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  static const borderWidth = 1.0;
  static const selectedBackgroundAlpha = 46;
  static const borderAlpha = 102;
  static const foregroundAlpha = 179;
  static const opaqueAlpha = 0xFF;
}

class AppBookNotesTokens {
  AppBookNotesTokens._();

  static const loadingPadding = EdgeInsets.symmetric(vertical: 40);
  static const filterLoadingHeight = 160.0;
  static const hintMargin = EdgeInsets.only(bottom: 10);
  static const filterPadding = EdgeInsets.fromLTRB(20, 10, 20, 10);
  static const sortPadding = EdgeInsets.all(8);
  static const filterRowPadding = EdgeInsets.all(8);
  static const filterIconSize = 35.0;
  static const editColorIconSize = 30.0;
  static const editContentPadding = EdgeInsets.only(top: 8, bottom: 16);
  static const editNotePadding = EdgeInsets.only(top: 8);
  static const tileMargin = EdgeInsets.only(bottom: 8);
  static const tilePadding = EdgeInsets.all(8);
  static const tileIconPadding = EdgeInsets.only(left: 10, right: 10, top: 10);
  static const tileDividerThickness = 3.0;
  static const tileDividerIndent = 4.0;
  static const tileDividerHeight = 3.0;

  static Color filterColor(String color) => Color(int.parse('0x99$color'));

  static Color tileIconColor(String color) =>
      Color(int.tryParse('0xaa$color') ?? 0xaa555555);
}
