import 'package:flutter/foundation.dart';

/// Safely converts a dynamic object to Map<String, dynamic>.
///
/// Returns null if the conversion is not possible or if the input is null.
/// This is useful when dealing with platform channel data that may come
/// as different Map types.
Map<String, dynamic>? safeMapConversion(dynamic input) {
  if (input == null) return null;

  if (input is Map<String, dynamic>) {
    return input;
  }

  if (input is Map) {
    try {
      return Map<String, dynamic>.fromEntries(
        input.entries.map((entry) {
          final key = entry.key?.toString();
          if (key == null) {
            throw ArgumentError('Map entry has null key');
          }
          return MapEntry(key, entry.value);
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to convert Map to Map<String, dynamic>: $e');
      }
      return null;
    }
  }

  return null;
}
