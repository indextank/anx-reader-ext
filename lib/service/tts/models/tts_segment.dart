import 'dart:typed_data';

import 'package:anx_reader/service/tts/models/tts_sentence.dart';

class TtsSegment {
  TtsSegment({required this.sentence, this.partIndex = 0});

  final TtsSentence sentence;

  /// Index of this segment when a long sentence was split into several
  /// engine-sized chunks; used to build unique buffer keys.
  final int partIndex;
  Uint8List? audio;
  bool isSilent = false;
  int fetchVersion =
      0; // Version to track if audio was fetched with current settings

  bool get isReady => isSilent || (audio != null && audio!.isNotEmpty);
}
