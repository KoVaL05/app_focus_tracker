import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/models/input_activity.dart';

void main() {
  group('InputActivity Models', () {
    test('InputActivityDelta zero factory', () {
      final d = InputActivityDelta.zero();
      expect(d.activeMs, 0);
      expect(d.idleMs, 0);
      expect(d.keystrokes, 0);
      expect(d.mouseClicks, 0);
      expect(d.scrollTicks, 0);
      expect(d.mouseMoveScreenUnits, 0.0);
    });

    test('InputActivityCumulative zero factory', () {
      final c = InputActivityCumulative.zero();
      expect(c.activeMs, 0);
      expect(c.idleMs, 0);
      expect(c.keystrokes, 0);
      expect(c.mouseClicks, 0);
      expect(c.scrollTicks, 0);
      expect(c.mouseMoveScreenUnits, 0.0);
    });

    test('InputActivityDelta JSON (de)serialization', () {
      final json = {
        'activeMs': 1000,
        'idleMs': 0,
        'keystrokes': 3,
        'mouseClicks': 2,
        'scrollTicks': 5,
        'mouseMoveScreenUnits': 0.123,
      };
      final d = InputActivityDelta.fromJson(json);
      expect(d.activeMs, 1000);
      expect(d.idleMs, 0);
      expect(d.keystrokes, 3);
      expect(d.mouseClicks, 2);
      expect(d.scrollTicks, 5);
      expect(d.mouseMoveScreenUnits, closeTo(0.123, 1e-9));
      expect(d.toJson(), json);
    });

    test('InputActivityCumulative JSON (de)serialization', () {
      final json = {
        'activeMs': 2000,
        'idleMs': 500,
        'keystrokes': 10,
        'mouseClicks': 4,
        'scrollTicks': 7,
        'mouseMoveScreenUnits': 0.987,
      };
      final c = InputActivityCumulative.fromJson(json);
      expect(c.activeMs, 2000);
      expect(c.idleMs, 500);
      expect(c.keystrokes, 10);
      expect(c.mouseClicks, 4);
      expect(c.scrollTicks, 7);
      expect(c.mouseMoveScreenUnits, closeTo(0.987, 1e-9));
      expect(c.toJson(), json);
    });

    test('InputActivity JSON (de)serialization', () {
      final json = {
        'supported': true,
        'permissionsGranted': true,
        'delta': {
          'activeMs': 1000,
          'idleMs': 0,
          'keystrokes': 2,
          'mouseClicks': 1,
          'scrollTicks': 3,
          'mouseMoveScreenUnits': 0.01,
        },
        'cumulative': {
          'activeMs': 5000,
          'idleMs': 1000,
          'keystrokes': 20,
          'mouseClicks': 5,
          'scrollTicks': 30,
          'mouseMoveScreenUnits': 0.25,
        }
      };

      final ia = InputActivity.fromJson(json);
      expect(ia.supported, isTrue);
      expect(ia.permissionsGranted, isTrue);
      expect(ia.delta.keystrokes, 2);
      expect(ia.cumulative.mouseClicks, 5);
      expect(ia.toJson(), json);
    });
  });
}
