import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'widgets and feature shells cannot access transport or SQLite directly',
    () {
      final violations = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final source = file.readAsStringSync();
        final isFeature = file.path.startsWith('lib/features/');
        final isWidget = source.contains('package:flutter/');
        final inspectsInfrastructure = isFeature || isWidget;
        if (!inspectsInfrastructure) {
          continue;
        }

        for (final forbidden in <String>[
          "package:http/",
          "package:drift/",
          "package:sqlite3/",
          "package:sqflite/",
          "dart:io",
          "dart:html",
          "providentia_api_client",
        ]) {
          if (source.contains(forbidden)) {
            violations.add('${file.path}: imports $forbidden');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'UI and feature boundaries must use application-owned ports:\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('generated API source carries the immutable generation marker', () {
    final generated = File(
      'contracts/generated/providentia_api_client/'
      'lib/providentia_api_client.dart',
    ).readAsStringSync();

    expect(generated, startsWith('// GENERATED FILE - DO NOT EDIT.'));
    expect(generated, contains('// Contract SHA-256:'));
  });
}
