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
      Map<String, dynamic> converted = {};
      for (final entry in input.entries) {
        final keyString = entry.key?.toString();
        if (keyString == null) {
          throw ArgumentError('Map entry has null key');
        }
        converted[keyString] = _convertValue(entry.value);
      }
      return converted;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to convert Map to Map<String, dynamic>: $e');
      }
      return null;
    }
  }

  return null;
}

// Recursively converts nested structures so that all Map keys are String and
// List elements are converted as well.
dynamic _convertValue(dynamic value) {
  if (value is Map) {
    return safeMapConversion(value);
  }
  if (value is List) {
    return value.map(_convertValue).toList();
  }
  return value;
}
