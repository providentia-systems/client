import 'dart:io';

/// Removes only a camera-plugin temporary file whose ownership has explicitly
/// transferred to Providentia. Callers must never pass a user-selected path.
Future<void> discardCapturedFile(String path) async {
  if (path.trim().isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on Object {
    // Registered bytes remain safely available in memory. Failure to remove a
    // platform-owned temporary file is not a reason to expose its path or fail
    // the user's already-completed capture.
  }
}
