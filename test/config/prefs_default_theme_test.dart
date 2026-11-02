import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('empty prefs default theme color equals brand default', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    expect(Prefs().themeColor, AppColors.defaultBrand);
  });
}
