import 'package:flutter_test/flutter_test.dart';
import 'package:app_focus_tracker/src/models/app_info.dart';

void main() {
  group('AppInfo', () {
    group('Constructor', () {
      test('creates AppInfo with required parameters', () {
        const appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        );

        expect(appInfo.name, equals('Test App'));
        expect(appInfo.identifier, equals('com.test.app'));
        expect(appInfo.processId, isNull);
        expect(appInfo.version, isNull);
        expect(appInfo.iconPath, isNull);
        expect(appInfo.executablePath, isNull);
        expect(appInfo.metadata, isNull);
      });

      test('creates AppInfo with all parameters', () {
        final metadata = {
          'bundleVersion': '1.0.1',
          'launchDate': 1234567890.0,
          'isHidden': false,
        };

        final appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
          version: '1.0.0',
          iconPath: '/path/to/icon.png',
          executablePath: '/path/to/executable',
          metadata: metadata,
        );

        expect(appInfo.name, equals('Test App'));
        expect(appInfo.identifier, equals('com.test.app'));
        expect(appInfo.processId, equals(1234));
        expect(appInfo.version, equals('1.0.0'));
        expect(appInfo.iconPath, equals('/path/to/icon.png'));
        expect(appInfo.executablePath, equals('/path/to/executable'));
        expect(appInfo.metadata, equals(metadata));
      });
    });

    group('JSON Serialization', () {
      test('converts to JSON correctly with all fields', () {
        final metadata = {
          'bundleVersion': '1.0.1',
          'launchDate': 1234567890.0,
        };

        final appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
          version: '1.0.0',
          iconPath: '/path/to/icon.png',
          executablePath: '/path/to/executable',
          metadata: metadata,
        );

        final json = appInfo.toJson();

        expect(json['name'], equals('Test App'));
        expect(json['identifier'], equals('com.test.app'));
        expect(json['processId'], equals(1234));
        expect(json['version'], equals('1.0.0'));
        expect(json['iconPath'], equals('/path/to/icon.png'));
        expect(json['executablePath'], equals('/path/to/executable'));
        expect(json['metadata'], equals(metadata));
      });

      test('converts to JSON correctly with minimal fields', () {
        const appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        );

        final json = appInfo.toJson();

        expect(json['name'], equals('Test App'));
        expect(json['identifier'], equals('com.test.app'));
        expect(json['processId'], isNull);
        expect(json['version'], isNull);
        expect(json['iconPath'], isNull);
        expect(json['executablePath'], isNull);
        expect(json['metadata'], isNull);
      });

      test('creates from JSON correctly', () {
        final json = {
          'name': 'Test App',
          'identifier': 'com.test.app',
          'processId': 1234,
          'version': '1.0.0',
          'iconPath': '/path/to/icon.png',
          'executablePath': '/path/to/executable',
          'metadata': {
            'bundleVersion': '1.0.1',
            'launchDate': 1234567890.0,
          },
        };

        final appInfo = AppInfo.fromJson(json);

        expect(appInfo.name, equals('Test App'));
        expect(appInfo.identifier, equals('com.test.app'));
        expect(appInfo.processId, equals(1234));
        expect(appInfo.version, equals('1.0.0'));
        expect(appInfo.iconPath, equals('/path/to/icon.png'));
        expect(appInfo.executablePath, equals('/path/to/executable'));
        expect(appInfo.metadata, equals(json['metadata']));
      });

      test('handles missing optional fields in JSON', () {
        final json = {
          'name': 'Test App',
          'identifier': 'com.test.app',
        };

        final appInfo = AppInfo.fromJson(json);

        expect(appInfo.name, equals('Test App'));
        expect(appInfo.identifier, equals('com.test.app'));
        expect(appInfo.processId, isNull);
        expect(appInfo.version, isNull);
        expect(appInfo.iconPath, isNull);
        expect(appInfo.executablePath, isNull);
        expect(appInfo.metadata, isNull);
      });

      test('handles null values in JSON', () {
        final json = {
          'name': 'Test App',
          'identifier': 'com.test.app',
          'processId': null,
          'version': null,
          'iconPath': null,
          'executablePath': null,
          'metadata': null,
        };

        final appInfo = AppInfo.fromJson(json);

        expect(appInfo.name, equals('Test App'));
        expect(appInfo.identifier, equals('com.test.app'));
        expect(appInfo.processId, isNull);
        expect(appInfo.version, isNull);
        expect(appInfo.iconPath, isNull);
        expect(appInfo.executablePath, isNull);
        expect(appInfo.metadata, isNull);
      });
    });

    group('Equality and HashCode', () {
      test('apps with same properties are equal', () {
        const appInfo1 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
          version: '1.0.0',
          iconPath: '/path/to/icon.png',
          executablePath: '/path/to/executable',
        );

        const appInfo2 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
          version: '1.0.0',
          iconPath: '/path/to/icon.png',
          executablePath: '/path/to/executable',
        );

        expect(appInfo1, equals(appInfo2));
        expect(appInfo1.hashCode, equals(appInfo2.hashCode));
      });

      test('apps with different names are not equal', () {
        const appInfo1 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        );

        const appInfo2 = AppInfo(
          name: 'Different App',
          identifier: 'com.test.app',
        );

        expect(appInfo1, isNot(equals(appInfo2)));
        expect(appInfo1.hashCode, isNot(equals(appInfo2.hashCode)));
      });

      test('apps with different identifiers are not equal', () {
        const appInfo1 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        );

        const appInfo2 = AppInfo(
          name: 'Test App',
          identifier: 'com.different.app',
        );

        expect(appInfo1, isNot(equals(appInfo2)));
        expect(appInfo1.hashCode, isNot(equals(appInfo2.hashCode)));
      });

      test('apps with different process IDs are not equal', () {
        const appInfo1 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
        );

        const appInfo2 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 5678,
        );

        expect(appInfo1, isNot(equals(appInfo2)));
        expect(appInfo1.hashCode, isNot(equals(appInfo2.hashCode)));
      });

      test('apps with different versions are not equal', () {
        const appInfo1 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          version: '1.0.0',
        );

        const appInfo2 = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          version: '2.0.0',
        );

        expect(appInfo1, isNot(equals(appInfo2)));
        expect(appInfo1.hashCode, isNot(equals(appInfo2.hashCode)));
      });
    });

    group('String Representation', () {
      test('toString includes key information', () {
        const appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 1234,
          version: '1.0.0',
        );

        final stringRepresentation = appInfo.toString();

        expect(stringRepresentation, contains('Test App'));
        expect(stringRepresentation, contains('com.test.app'));
        expect(stringRepresentation, contains('1234'));
        expect(stringRepresentation, contains('1.0.0'));
      });

      test('toString handles null values gracefully', () {
        const appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
        );

        final stringRepresentation = appInfo.toString();

        expect(stringRepresentation, contains('Test App'));
        expect(stringRepresentation, contains('com.test.app'));
        expect(stringRepresentation, contains('null')); // For null processId and version
      });
    });

    group('Edge Cases', () {
      test('handles empty strings', () {
        const appInfo = AppInfo(
          name: '',
          identifier: '',
          version: '',
          iconPath: '',
          executablePath: '',
        );

        expect(appInfo.name, equals(''));
        expect(appInfo.identifier, equals(''));
        expect(appInfo.version, equals(''));
        expect(appInfo.iconPath, equals(''));
        expect(appInfo.executablePath, equals(''));
      });

      test('handles special characters in strings', () {
        const appInfo = AppInfo(
          name: 'Test App (with special chars) & symbols!',
          identifier: 'com.test-app_with-symbols.app',
          version: '1.0.0-beta.1+build.123',
        );

        expect(appInfo.name, equals('Test App (with special chars) & symbols!'));
        expect(appInfo.identifier, equals('com.test-app_with-symbols.app'));
        expect(appInfo.version, equals('1.0.0-beta.1+build.123'));
      });

      test('handles Unicode characters', () {
        const appInfo = AppInfo(
          name: 'Test App 测试应用 🚀',
          identifier: 'com.test.app.unicode',
        );

        expect(appInfo.name, equals('Test App 测试应用 🚀'));
        expect(appInfo.identifier, equals('com.test.app.unicode'));
      });

      test('handles large process IDs', () {
        const appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          processId: 2147483647, // Max 32-bit signed integer
        );

        expect(appInfo.processId, equals(2147483647));
      });

      test('handles complex metadata', () {
        final complexMetadata = {
          'stringValue': 'test',
          'intValue': 123,
          'doubleValue': 45.67,
          'boolValue': true,
          'listValue': [1, 2, 3],
          'mapValue': {
            'nested': 'value',
            'number': 42,
          },
        };

        final appInfo = AppInfo(
          name: 'Test App',
          identifier: 'com.test.app',
          metadata: complexMetadata,
        );

        expect(appInfo.metadata, equals(complexMetadata));

        // Test JSON serialization with complex metadata
        final json = appInfo.toJson();
        expect(json['metadata'], equals(complexMetadata));

        final recreated = AppInfo.fromJson(json);
        expect(recreated.metadata, equals(complexMetadata));
      });
    });
  });
}
