import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'widgets and feature shells cannot access transport or SQLite directly',
    () {
      final violations = <String>[];
      for (final file in _dartSources()) {
        final source = file.readAsStringSync();
        final path = _normalizedPath(file);
        final isFeature = path.startsWith('lib/features/');
        final isWidget = source.contains('package:flutter/');
        if (!isFeature && !isWidget) {
          continue;
        }

        for (final forbidden in _infrastructureImports) {
          if (source.contains(forbidden)) {
            violations.add('$path: imports $forbidden');
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

  test('application controllers depend on ports, not concrete coordinators', () {
    final violations = <String>[];
    for (final file in _dartSources().where(
      (file) => _normalizedPath(file).startsWith('lib/app/'),
    )) {
      final source = file.readAsStringSync();
      final path = _normalizedPath(file);
      for (final forbidden in <String>[
        '/sync_coordinator.dart',
        '/database/',
        '/networking/',
      ]) {
        if (source.contains(forbidden)) {
          violations.add('$path: imports concrete boundary $forbidden');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Application presentation must depend inward:\n${violations.join('\n')}',
    );
  });

  test('synchronization domain and ports stay framework independent', () {
    final violations = <String>[];
    for (final path in <String>[
      'lib/core/synchronization/sync_models.dart',
      'lib/core/synchronization/sync_ports.dart',
      'lib/core/synchronization/sync_coordinator.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in <String>[
        'package:flutter/',
        'package:http/',
        'package:drift/',
        'providentia_api_client',
        '/database/',
        '/networking/',
      ]) {
        if (source.contains(forbidden)) {
          violations.add('$path: imports $forbidden');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Domain policy must not depend on frameworks:\n${violations.join('\n')}',
    );
  });

  test('generated transport is imported only by approved adapters', () {
    final violations = <String>[];
    const approved = <String>{
      'lib/core/networking/api_client_factory.dart',
      'lib/core/networking/generated_api_connectivity_probe.dart',
      'lib/core/synchronization/generated_sync_gateway.dart',
    };
    for (final file in _dartSources()) {
      final source = file.readAsStringSync();
      final path = _normalizedPath(file);
      if (source.contains('providentia_api_client') &&
          !approved.contains(path)) {
        violations.add(path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Generated transport leaked outside approved adapters:\n'
          '${violations.join('\n')}',
    );
  });

  test('generated API source carries the immutable generation marker', () {
    final generated = File(
      'contracts/generated/providentia_api_client/'
      'lib/providentia_api_client.dart',
    ).readAsStringSync();

    expect(generated, startsWith('// GENERATED FILE - DO NOT EDIT.'));
    expect(generated, contains('// Contract SHA-256:'));
  });
}

const List<String> _infrastructureImports = <String>[
  'package:http/',
  'package:drift/',
  'package:sqlite3/',
  'package:sqflite/',
  'dart:io',
  'dart:html',
  'providentia_api_client',
];

Iterable<File> _dartSources() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

String _normalizedPath(File file) => file.path.replaceAll('\\', '/');
