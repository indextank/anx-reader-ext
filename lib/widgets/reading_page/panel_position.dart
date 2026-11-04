import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';

enum ReadingPanelTool { ai, notes, style, tts }

enum ReadingPanelPresentation { side, popup }

class ReadingPanelActivity {
  const ReadingPanelActivity()
      : activeTool = null,
        sidePanelTool = null,
        popupTool = null;

  const ReadingPanelActivity._({
    required this.activeTool,
    required this.sidePanelTool,
    required this.popupTool,
  });

  final ReadingPanelTool? activeTool;
  final ReadingPanelTool? sidePanelTool;
  final ReadingPanelTool? popupTool;

  ReadingPanelActivity open(
    ReadingPanelTool tool, {
    required ReadingPanelPresentation presentation,
  }) {
    return ReadingPanelActivity._(
      activeTool: tool,
      sidePanelTool:
          presentation == ReadingPanelPresentation.side ? tool : null,
      popupTool: presentation == ReadingPanelPresentation.popup ? tool : null,
    );
  }

  ReadingPanelActivity close(ReadingPanelTool tool) {
    return ReadingPanelActivity._(
      activeTool: activeTool == tool ? null : activeTool,
      sidePanelTool: sidePanelTool == tool ? null : sidePanelTool,
      popupTool: popupTool == tool ? null : popupTool,
    );
  }
}

AiPanelPositionEnum readingToolPosition(
  ReadingToolPanelKind kind, {
  required AiPanelPositionEnum notesPosition,
  required AiPanelPositionEnum stylePosition,
}) {
  switch (kind) {
    case ReadingToolPanelKind.notes:
      return notesPosition;
    case ReadingToolPanelKind.style:
      return stylePosition;
    case ReadingToolPanelKind.tts:
      return AiPanelPositionEnum.popup;
    case ReadingToolPanelKind.none:
      throw ArgumentError.value(kind, 'kind', 'No active reading tool');
  }
}

AiPanelPositionEnum readPanelPosition(String? Function() read) {
  try {
    final position = AiPanelPositionEnum.fromCode(
      read(),
      fallback: AiPanelPositionEnum.popup,
    );
    return position == AiPanelPositionEnum.right ||
            position == AiPanelPositionEnum.popup
        ? position
        : AiPanelPositionEnum.popup;
  } catch (_) {
    return AiPanelPositionEnum.popup;
  }
}

Future<bool> writePanelPosition(Future<bool> Function() write) async {
  try {
    return await write();
  } catch (_) {
    return false;
  }
}
