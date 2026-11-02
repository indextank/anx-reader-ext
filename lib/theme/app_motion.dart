class AppMotion {
  const AppMotion();

  static const tokens = AppMotion();

  Duration get fast => const Duration(milliseconds: 150);
  Duration get normal => const Duration(milliseconds: 200);
  Duration get emphasis => const Duration(milliseconds: 300);
}
