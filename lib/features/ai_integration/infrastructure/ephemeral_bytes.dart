import 'dart:typed_data';

/// Best-effort zeroization for mutable, client-owned media buffers.
///
/// Dart strings, transport internals, TLS buffers, OS caches, and provider-side
/// copies are outside this process boundary and cannot be guaranteed erased by
/// this helper. Keep those values short-lived and never log them.
void wipeEphemeralBytes(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return;
  bytes.fillRange(0, bytes.length, 0);
}
