import 'dart:ui';

import 'package:anx_reader/widgets/reading_page/tts_fab_position.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-logic tests for the floating TTS player anchor: no widget tree, no
/// preference storage, no audio. The anchor is the durable contract that makes
/// the player survive window resizes, rotation and split-screen.
void main() {
  const stage = Rect.fromLTWH(0, 0, 1000, 800);
  const content = Size(120, 56);
  const maxDx = 880.0; // stage.width - content.width
  const maxDy = 744.0; // stage.height - content.height

  group('TtsFabAnchor basics', () {
    test('default anchor is the historical bottom-right corner', () {
      expect(TtsFabAnchor.defaultAnchor.x, 1);
      expect(TtsFabAnchor.defaultAnchor.y, 1);
      expect(TtsFabAnchor.defaultAnchor.isDefault, isTrue);
    });

    test('reports whether it sits at the default position', () {
      expect(const TtsFabAnchor(x: 1, y: 1).isDefault, isTrue);
      expect(const TtsFabAnchor(x: 1, y: 0.5).isDefault, isFalse);
      expect(const TtsFabAnchor(x: 0.5, y: 1).isDefault, isFalse);
      // Persisted doubles arrive with tiny drift; drift must not read as moved.
      expect(const TtsFabAnchor(x: 0.9995, y: 0.9995).isDefault, isTrue);
    });

    test('exposes the raw fractions and support value equality', () {
      const anchor = TtsFabAnchor(x: 0.25, y: 0.75);
      expect(anchor.x, 0.25);
      expect(anchor.y, 0.75);
      expect(anchor, const TtsFabAnchor(x: 0.25, y: 0.75));
      expect(
        anchor.hashCode,
        const TtsFabAnchor(x: 0.25, y: 0.75).hashCode,
      );
      expect(anchor.copyWith(x: 0.5), const TtsFabAnchor(x: 0.5, y: 0.75));
    });

    test('clamped absorbs invalid legacy preference values', () {
      const anchor = TtsFabAnchor(x: 4.2, y: -3.0);
      expect(anchor.clamped, const TtsFabAnchor(x: 1, y: 0));
      expect(TtsFabAnchor.defaultAnchor.clamped, TtsFabAnchor.defaultAnchor);
    });
  });

  group('TtsFabAnchor.resolve', () {
    test('default anchor resolves to the bottom-right of the stage', () {
      final position = TtsFabAnchor.defaultAnchor.resolve(stage, content);
      expect(position.dx, closeTo(maxDx, 1e-9));
      expect(position.dy, closeTo(maxDy, 1e-9));
    });

    test('origin anchor resolves to the top-left of the stage', () {
      expect(
        const TtsFabAnchor(x: 0, y: 0).resolve(stage, content),
        const Offset(0, 0),
      );
    });

    test('half anchor centres content in the available travel range', () {
      final position =
          const TtsFabAnchor(x: 0.5, y: 0.5).resolve(stage, content);
      expect(position.dx, closeTo(maxDx / 2, 1e-9));
      expect(position.dy, closeTo(maxDy / 2, 1e-9));
    });

    test('quarter anchors interpolate linearly over the travel range', () {
      final position =
          const TtsFabAnchor(x: 0.25, y: 0.75).resolve(stage, content);
      expect(position.dx, closeTo(maxDx * 0.25, 1e-9));
      expect(position.dy, closeTo(maxDy * 0.75, 1e-9));
    });

    test('every in-range fraction keeps the content inside the stage', () {
      for (var i = 0; i <= 10; i++) {
        final fraction = i / 10;
        final position =
            TtsFabAnchor(x: fraction, y: fraction).resolve(stage, content);
        expect(position.dx, inInclusiveRange(0, maxDx));
        expect(position.dy, inInclusiveRange(0, maxDy));
        expect(position.dx + content.width, lessThanOrEqualTo(stage.right));
        expect(position.dy + content.height, lessThanOrEqualTo(stage.bottom));
      }
    });

    test('out-of-range fractions are clamped instead of escaping the stage',
        () {
      expect(
        const TtsFabAnchor(x: 1.5, y: 1.5).resolve(stage, content),
        TtsFabAnchor.defaultAnchor.resolve(stage, content),
      );
      expect(
        const TtsFabAnchor(x: -0.5, y: -0.5).resolve(stage, content),
        const Offset(0, 0),
      );
    });

    test('resolves against the stage rectangle, not a zero-origin frame', () {
      const offsetStage = Rect.fromLTWH(37, 51, 1000, 800);
      final position =
          const TtsFabAnchor(x: 0.5, y: 0.5).resolve(offsetStage, content);
      expect(position.dx, closeTo(37 + maxDx / 2, 1e-9));
      expect(position.dy, closeTo(51 + maxDy / 2, 1e-9));
    });

    test('content equal to the stage size is pinned to the stage top-left', () {
      const tightStage = Rect.fromLTWH(12, 34, 200, 100);
      const tightContent = Size(200, 100);
      for (final fraction in <double>[0, 0.5, 1]) {
        expect(
          TtsFabAnchor(x: fraction, y: fraction)
              .resolve(tightStage, tightContent),
          const Offset(12, 34),
        );
      }
    });

    test('content larger than the stage is pinned to the stage top-left', () {
      const smallStage = Rect.fromLTWH(20, 40, 100, 80);
      const largeContent = Size(220, 180);
      final position =
          TtsFabAnchor.defaultAnchor.resolve(smallStage, largeContent);
      expect(position.dx, greaterThanOrEqualTo(0));
      expect(position.dy, greaterThanOrEqualTo(0));
      // The oversized child must start at (or before) the stage origin, never
      // be pushed further right/down than the visible area.
      expect(position.dx, lessThanOrEqualTo(20));
      expect(position.dy, lessThanOrEqualTo(40));
      expect(position.dx.isFinite, isTrue);
      expect(position.dy.isFinite, isTrue);
    });

    test('degenerate empty stage does not throw', () {
      final position =
          TtsFabAnchor.defaultAnchor.resolve(Rect.zero, const Size(40, 40));
      expect(position, Offset.zero);
    });
  });

  group('TtsFabAnchor.fromPixel', () {
    test('bottom-right pixel position maps to the default anchor', () {
      expect(
        TtsFabAnchor.fromPixel(stage, content, const Offset(maxDx, maxDy)),
        TtsFabAnchor.defaultAnchor,
      );
    });

    test('round-trips with resolve for representative anchors', () {
      const anchors = <TtsFabAnchor>[
        TtsFabAnchor(x: 0, y: 0),
        TtsFabAnchor(x: 0.25, y: 0.75),
        TtsFabAnchor(x: 0.5, y: 0.5),
        TtsFabAnchor.defaultAnchor,
      ];
      for (final anchor in anchors) {
        final pixel = anchor.resolve(stage, content);
        final roundTripped = TtsFabAnchor.fromPixel(stage, content, pixel);
        expect(roundTripped.x, closeTo(anchor.x, 1e-9));
        expect(roundTripped.y, closeTo(anchor.y, 1e-9));
      }
    });

    test('clamps pixels outside the travel range into [0, 1]', () {
      expect(
        TtsFabAnchor.fromPixel(stage, content, const Offset(-500, -500)),
        const TtsFabAnchor(x: 0, y: 0),
      );
      expect(
        TtsFabAnchor.fromPixel(stage, content, const Offset(5000, 5000)),
        TtsFabAnchor.defaultAnchor,
      );
    });

    test('zero free space maps to the zero anchor', () {
      const tightStage = Rect.fromLTWH(10, 10, 100, 100);
      expect(
        TtsFabAnchor.fromPixel(
          tightStage,
          const Size(100, 100),
          const Offset(10, 10),
        ),
        const TtsFabAnchor(x: 0, y: 0),
      );
      expect(
        TtsFabAnchor.fromPixel(
          tightStage,
          const Size(200, 200),
          const Offset(10, 10),
        ),
        const TtsFabAnchor(x: 0, y: 0),
      );
    });

    test('takes the stage offset into account', () {
      const offsetStage = Rect.fromLTWH(50, 60, 400, 300);
      const offsetContent = Size(100, 50);
      final pixel =
          const TtsFabAnchor(x: 0.5, y: 1).resolve(offsetStage, offsetContent);
      final anchor = TtsFabAnchor.fromPixel(offsetStage, offsetContent, pixel);
      expect(anchor.x, closeTo(0.5, 1e-9));
      expect(anchor.y, closeTo(1.0, 1e-9));
    });
  });
}
