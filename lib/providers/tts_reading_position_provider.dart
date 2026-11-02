import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tts_reading_position_provider.g.dart';

/// Central, observable store for the TTS reading position
/// ("last-read page token + in-page offset"). The playback service pushes
/// updates through the widget layer; the resume branching itself lives in
/// the pure [resolveResumeAction] function.
@riverpod
class TtsReadingPosition extends _$TtsReadingPosition {
  @override
  TtsReadingPositionState? build() {
    return null;
  }

  void update(TtsReadingPositionState position) {
    state = position;
  }

  void clear() {
    state = null;
  }
}
