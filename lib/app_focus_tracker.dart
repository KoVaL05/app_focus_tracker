import 'dart:async';
import 'package:flutter/services.dart';

class AppFocusTracker {
  static const EventChannel _channel = EventChannel('app_focus_tracker');

  Stream<Map<String, dynamic>>? _stream;

  Stream<Map<String, dynamic>> get focusStream {
    _stream ??= _channel.receiveBroadcastStream().map((event) {
      final Map<String, dynamic> eventMap = Map<String, dynamic>.from(event);
      return {
        'appName': eventMap['appName'] as String,
        'duration': eventMap['duration'] as int,
      };
    });
    return _stream!;
  }
}
