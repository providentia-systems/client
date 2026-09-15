import 'dart:convert';

import 'package:crypto/crypto.dart';

/// RFC 4122 name-based UUID (URL namespace), scoped to home and intake target.
/// Used for reviewed intake entities only; ordinary manual IDs stay random.
String intakeEntityId(List<String> components) {
  if (components.any((value) => value.trim().isEmpty)) {
    throw ArgumentError('An intake identifier requires a complete scope.');
  }
  const namespace = <int>[
    0x6b,
    0xa7,
    0xb8,
    0x11,
    0x9d,
    0xad,
    0x11,
    0xd1,
    0x80,
    0xb4,
    0x00,
    0xc0,
    0x4f,
    0xd4,
    0x30,
    0xc8,
  ];
  final bytes = sha1
      .convert(<int>[
        ...namespace,
        ...utf8.encode(
          'urn:providentia:reviewed-intake:${jsonEncode(components)}',
        ),
      ])
      .bytes
      .take(16)
      .toList();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
