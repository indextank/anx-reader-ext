/// Observes and restores where TTS reading has reached.
///
/// The position consists of the cfi of the last-read sentence (the
/// in-page offset) and a page token identifying the page that was
/// displayed when it was read. On resume, the decision whether to continue
/// in place or restart from the current page start is made by
/// [resolveResumeAction].
class TtsReadingPositionState {
  const TtsReadingPositionState({
    required this.lastReadCfi,
    required this.pageToken,
  });

  /// Cfi of the sentence that was being read last.
  final String lastReadCfi;

  /// Identity of the page that was displayed at that time (the reader's
  /// current location cfi).
  final String pageToken;

  @override
  bool operator ==(Object other) =>
      other is TtsReadingPositionState &&
      other.lastReadCfi == lastReadCfi &&
      other.pageToken == pageToken;

  @override
  int get hashCode => Object.hash(lastReadCfi, pageToken);

  @override
  String toString() =>
      'TtsReadingPositionState(lastReadCfi: $lastReadCfi, pageToken: $pageToken)';
}

/// How playback should resume after a pause or engine switch.
enum TtsResumeAction {
  /// The last-read position is still on the displayed page: continue the
  /// paused audio exactly where it stopped.
  continueInPlace,

  /// The reader moved to a different page: discard the paused queue and
  /// start reading from the beginning of the currently displayed page.
  restartFromCurrentPageStart,
}

/// Decide how to resume.
///
/// Pure function so the branching rule stays testable:
/// - no recorded position (first run / new book) → restart from the
///   current page start;
/// - recorded position still visible on the current page → continue in
///   place (no jump back, no re-reading);
/// - reader has moved to another page → restart from the current page
///   start, never jump back to the old page.
TtsResumeAction resolveResumeAction({
  required String? lastReadCfi,
  required bool lastReadPositionVisible,
}) {
  if (lastReadCfi == null || lastReadCfi.isEmpty) {
    return TtsResumeAction.restartFromCurrentPageStart;
  }
  return lastReadPositionVisible
      ? TtsResumeAction.continueInPlace
      : TtsResumeAction.restartFromCurrentPageStart;
}
