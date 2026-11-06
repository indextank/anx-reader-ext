import 'package:anx_reader/theme/app_spacing.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

class BatteryIndicator extends StatefulWidget {
  const BatteryIndicator({
    super.key,
    this.textStyle,
    this.batteryLevelLoader,
  });

  final TextStyle? textStyle;
  final Future<int> Function()? batteryLevelLoader;

  @override
  State<BatteryIndicator> createState() => _BatteryIndicatorState();
}

class _BatteryIndicatorState extends State<BatteryIndicator> {
  late final Future<int?> _batteryLevel = _loadBatteryLevel();

  Future<int?> _loadBatteryLevel() async {
    try {
      return await (widget.batteryLevelLoader?.call() ??
          Battery().batteryLevel);
    } catch (_) {
      // Desktop systems without a battery are reported as platform errors.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.textStyle;
    final iconColor = textStyle?.color;
    return FutureBuilder<int?>(
      future: _batteryLevel,
      builder: (context, snapshot) {
        final level = snapshot.data;
        if (level == null) return const SizedBox.shrink();
        return Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: AppSpacing.only(
                top: (textStyle?.fontSize ?? 10) * 0.08,
                right: 2,
              ),
              child: Text(
                '$level',
                style: textStyle?.copyWith(
                  fontSize: (textStyle.fontSize ?? 10) - 1,
                ),
              ),
            ),
            Icon(
              HeroIcons.battery_0,
              size: (textStyle?.fontSize ?? 10) * 2.7,
              color: iconColor,
            ),
          ],
        );
      },
    );
  }
}
