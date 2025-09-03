/// Input activity tracking models.
///
/// These classes represent aggregated input activity over time and per-interval
/// deltas aligned with focus duration updates. They intentionally avoid storing
/// any content or scan codes; only counts and normalized magnitudes are kept.

class InputActivityDelta {
  final int activeMs;
  final int idleMs;
  final int keystrokes;
  final int mouseClicks;
  final int scrollTicks;
  final double mouseMoveScreenUnits;

  const InputActivityDelta({
    required this.activeMs,
    required this.idleMs,
    required this.keystrokes,
    required this.mouseClicks,
    required this.scrollTicks,
    required this.mouseMoveScreenUnits,
  });

  factory InputActivityDelta.zero() => const InputActivityDelta(
        activeMs: 0,
        idleMs: 0,
        keystrokes: 0,
        mouseClicks: 0,
        scrollTicks: 0,
        mouseMoveScreenUnits: 0.0,
      );

  factory InputActivityDelta.fromJson(Map<String, dynamic> json) {
    final mouseUnits = json['mouseMoveScreenUnits'];
    return InputActivityDelta(
      activeMs: (json['activeMs'] as int?) ?? 0,
      idleMs: (json['idleMs'] as int?) ?? 0,
      keystrokes: (json['keystrokes'] as int?) ?? 0,
      mouseClicks: (json['mouseClicks'] as int?) ?? 0,
      scrollTicks: (json['scrollTicks'] as int?) ?? 0,
      mouseMoveScreenUnits:
          mouseUnits is num ? mouseUnits.toDouble() : (mouseUnits is String ? double.tryParse(mouseUnits) ?? 0.0 : 0.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activeMs': activeMs,
      'idleMs': idleMs,
      'keystrokes': keystrokes,
      'mouseClicks': mouseClicks,
      'scrollTicks': scrollTicks,
      'mouseMoveScreenUnits': mouseMoveScreenUnits,
    };
  }
}

class InputActivityCumulative {
  final int activeMs;
  final int idleMs;
  final int keystrokes;
  final int mouseClicks;
  final int scrollTicks;
  final double mouseMoveScreenUnits;

  const InputActivityCumulative({
    required this.activeMs,
    required this.idleMs,
    required this.keystrokes,
    required this.mouseClicks,
    required this.scrollTicks,
    required this.mouseMoveScreenUnits,
  });

  factory InputActivityCumulative.zero() => const InputActivityCumulative(
        activeMs: 0,
        idleMs: 0,
        keystrokes: 0,
        mouseClicks: 0,
        scrollTicks: 0,
        mouseMoveScreenUnits: 0.0,
      );

  factory InputActivityCumulative.fromJson(Map<String, dynamic> json) {
    final mouseUnits = json['mouseMoveScreenUnits'];
    return InputActivityCumulative(
      activeMs: (json['activeMs'] as int?) ?? 0,
      idleMs: (json['idleMs'] as int?) ?? 0,
      keystrokes: (json['keystrokes'] as int?) ?? 0,
      mouseClicks: (json['mouseClicks'] as int?) ?? 0,
      scrollTicks: (json['scrollTicks'] as int?) ?? 0,
      mouseMoveScreenUnits:
          mouseUnits is num ? mouseUnits.toDouble() : (mouseUnits is String ? double.tryParse(mouseUnits) ?? 0.0 : 0.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activeMs': activeMs,
      'idleMs': idleMs,
      'keystrokes': keystrokes,
      'mouseClicks': mouseClicks,
      'scrollTicks': scrollTicks,
      'mouseMoveScreenUnits': mouseMoveScreenUnits,
    };
  }
}

class InputActivity {
  final InputActivityDelta delta;
  final InputActivityCumulative cumulative;
  final bool supported;
  final bool permissionsGranted;

  const InputActivity({
    required this.delta,
    required this.cumulative,
    required this.supported,
    required this.permissionsGranted,
  });

  factory InputActivity.zero({bool supported = false, bool permissionsGranted = false}) {
    return InputActivity(
      delta: InputActivityDelta.zero(),
      cumulative: InputActivityCumulative.zero(),
      supported: supported,
      permissionsGranted: permissionsGranted,
    );
  }

  factory InputActivity.fromJson(Map<String, dynamic> json) {
    final deltaJson = json['delta'];
    final cumulativeJson = json['cumulative'];
    return InputActivity(
      delta: deltaJson is Map<String, dynamic> ? InputActivityDelta.fromJson(deltaJson) : InputActivityDelta.zero(),
      cumulative: cumulativeJson is Map<String, dynamic>
          ? InputActivityCumulative.fromJson(cumulativeJson)
          : InputActivityCumulative.zero(),
      supported: (json['supported'] as bool?) ?? false,
      permissionsGranted: (json['permissionsGranted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'delta': delta.toJson(),
      'cumulative': cumulative.toJson(),
      'supported': supported,
      'permissionsGranted': permissionsGranted,
    };
  }
}
