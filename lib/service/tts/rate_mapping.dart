/// Rate normalization between the UI slider and each engine's units.
///
/// The UI value follows flutter_tts semantics: 0.5 is the default normal
/// speaking rate, 1.0 is double speed. Cloud engines use a plain
/// multiplier instead (1.0 = normal), hence `multiplier = 2 * rate`.
///
/// - StepFun: `speed = multiplier`, clamped to the documented 0.5–2.0.
/// - Aliyun: `speech_rate = (multiplier - 1) * 500` clamped to -500..500
///   (unchanged from the existing `_toAliyunRate` implementation).
/// - MiMo has no numeric speed parameter; the multiplier is applied via
///   player playback rate.
/// - The system engine receives the raw flutter_tts value (its own
///   platform-specific mapping is done inside the plugin).
double ttsRateToMultiplier(double rate) {
  if (rate.isNaN || rate.isInfinite) return 1.0;
  return (rate * 2).clamp(0.5, 2.0);
}

/// Clamp a UI rate into the supported slider range, guarding against
/// NaN/infinite values.
double clampTtsRate(double rate) {
  if (rate.isNaN || rate.isInfinite) return 0.6;
  return rate.clamp(0.0, 2.0);
}
