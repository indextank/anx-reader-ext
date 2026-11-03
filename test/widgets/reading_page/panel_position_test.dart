import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/widgets/reading_page/panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiPanelPositionEnum', () {
    test('uses right for invalid or empty AI positions', () {
      expect(
        AiPanelPositionEnum.fromCode('invalid'),
        AiPanelPositionEnum.right,
      );
      expect(AiPanelPositionEnum.fromCode(''), AiPanelPositionEnum.right);
      expect(AiPanelPositionEnum.fromCode(null), AiPanelPositionEnum.right);
    });

    test('retains bottom and supports popup', () {
      expect(
        AiPanelPositionEnum.fromCode('bottom'),
        AiPanelPositionEnum.bottom,
      );
      expect(
        AiPanelPositionEnum.fromCode('popup'),
        AiPanelPositionEnum.popup,
      );
    });
  });

  group('readingToolPosition', () {
    test('maps notes and style positions independently', () {
      expect(
        readingToolPosition(
          ReadingToolPanelKind.notes,
          notesPosition: AiPanelPositionEnum.right,
          stylePosition: AiPanelPositionEnum.popup,
        ),
        AiPanelPositionEnum.right,
      );
      expect(
        readingToolPosition(
          ReadingToolPanelKind.style,
          notesPosition: AiPanelPositionEnum.right,
          stylePosition: AiPanelPositionEnum.popup,
        ),
        AiPanelPositionEnum.popup,
      );
      expect(
        readingToolPosition(
          ReadingToolPanelKind.notes,
          notesPosition: AiPanelPositionEnum.popup,
          stylePosition: AiPanelPositionEnum.right,
        ),
        AiPanelPositionEnum.popup,
      );
      expect(
        readingToolPosition(
          ReadingToolPanelKind.style,
          notesPosition: AiPanelPositionEnum.popup,
          stylePosition: AiPanelPositionEnum.right,
        ),
        AiPanelPositionEnum.right,
      );
    });

    test('always presents tts as popup', () {
      expect(
        readingToolPosition(
          ReadingToolPanelKind.tts,
          notesPosition: AiPanelPositionEnum.bottom,
          stylePosition: AiPanelPositionEnum.bottom,
        ),
        AiPanelPositionEnum.popup,
      );
    });
  });

  group('ReadingPanelActivity', () {
    test('opening a side tool replaces the previous activity', () {
      const initial = ReadingPanelActivity();
      final notes = initial.open(
        ReadingPanelTool.notes,
        presentation: ReadingPanelPresentation.side,
      );

      expect(notes.activeTool, ReadingPanelTool.notes);
      expect(notes.sidePanelTool, ReadingPanelTool.notes);
      expect(notes.popupTool, isNull);

      final ai = notes.open(
        ReadingPanelTool.ai,
        presentation: ReadingPanelPresentation.side,
      );

      expect(ai.activeTool, ReadingPanelTool.ai);
      expect(ai.sidePanelTool, ReadingPanelTool.ai);
      expect(ai.popupTool, isNull);
    });

    test('close is selective and reopening as popup clears side identity', () {
      final notes = const ReadingPanelActivity().open(
        ReadingPanelTool.notes,
        presentation: ReadingPanelPresentation.side,
      );
      final afterOtherClose = notes.close(ReadingPanelTool.ai);

      expect(afterOtherClose.activeTool, ReadingPanelTool.notes);
      expect(afterOtherClose.sidePanelTool, ReadingPanelTool.notes);
      expect(afterOtherClose.popupTool, isNull);

      final reopened = afterOtherClose.close(ReadingPanelTool.notes).open(
            ReadingPanelTool.notes,
            presentation: ReadingPanelPresentation.popup,
          );

      expect(reopened.activeTool, ReadingPanelTool.notes);
      expect(reopened.sidePanelTool, isNull);
      expect(reopened.popupTool, ReadingPanelTool.notes);
    });
  });

  group('safe panel position persistence', () {
    test('read falls back to popup when reading throws', () {
      expect(
        readPanelPosition(() => throw StateError('read failed')),
        AiPanelPositionEnum.popup,
      );
    });

    test('read returns a persisted right position', () {
      expect(
        readPanelPosition(() => 'right'),
        AiPanelPositionEnum.right,
      );
    });

    test('write returns false when persistence returns false', () async {
      expect(await writePanelPosition(() async => false), isFalse);
    });

    test('write catches synchronous and asynchronous exceptions', () async {
      expect(
        await writePanelPosition(() => throw StateError('sync failed')),
        isFalse,
      );
      expect(
        await writePanelPosition(
          () => Future<bool>.error(StateError('async failed')),
        ),
        isFalse,
      );
    });

    test('write returns true when persistence succeeds', () async {
      expect(await writePanelPosition(() async => true), isTrue);
    });
  });
}
