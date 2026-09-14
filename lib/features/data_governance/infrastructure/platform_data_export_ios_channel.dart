import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Transport for the owned iOS export picker. Files remain a native concern.
final class IosDataExportChannel {
  const IosDataExportChannel();
  static const _channel = MethodChannel('providentia/data-export');

  Future<bool?> save(String filename, Uint8List bytes) =>
      _channel.invokeMethod<bool>('save', <String, Object?>{
        'filename': filename,
        'bytes': bytes,
      });

  Future<void> discard() => _channel.invokeMethod<void>('discard');
}
