import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading page uses the new toolbar and tool panel without legacy UI',
      () {
    final source = File('lib/page/reading_page.dart').readAsStringSync();

    expect(source, contains('ReadingToolbar('));
    expect(source, contains('ReadingToolPanel('));
    expect(source, contains('kind: ReadingToolPanelKind.notes'));
    expect(source, contains('kind: ReadingToolPanelKind.style'));
    expect(source, contains('kind: ReadingToolPanelKind.tts'));

    expect(source, isNot(contains('progress_widget.dart')));
    expect(source, isNot(contains('progressHandler')));
    expect(source, isNot(contains('Icons.data_usage')));
    expect(source, isNot(contains('StatefulBuilder(')));

    expect(source, contains('if (bottomBarOffstage)'));
    expect(source, contains('const TtsFab()'));
    expect(File('lib/widgets/reading_page/progress_widget.dart').existsSync(),
        isFalse);
  });
}
