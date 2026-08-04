import 'dart:async';

import 'package:providentia/features/ai_integration/domain/media_intake.dart';

abstract interface class PreparedMediaCleanupPort {
  Future<void> discardPreparedMedia({
    required PreparedMediaEnvelope batch,
    required MediaCleanupTrigger trigger,
  });
}

final class MediaOperationCancelled implements Exception {
  const MediaOperationCancelled();
}

final class PreparedMediaCleanupFailure implements Exception {
  const PreparedMediaCleanupFailure({
    required this.trigger,
    required this.operationAlsoFailed,
  });

  final MediaCleanupTrigger trigger;
  final bool operationAlsoFailed;

  String get safeMessage =>
      'Temporary media cleanup failed. Keep the application open and retry cleanup.';
}

final class ExecuteWithPreparedMediaCleanup {
  const ExecuteWithPreparedMediaCleanup(this._cleanup);

  final PreparedMediaCleanupPort _cleanup;

  Future<T> execute<T>({
    required PreparedMediaEnvelope batch,
    required Future<T> Function() operation,
  }) async {
    Object? operationError;
    StackTrace? operationStackTrace;
    var trigger = MediaCleanupTrigger.success;
    late T value;
    try {
      value = await operation();
    } on TimeoutException catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
      trigger = MediaCleanupTrigger.timeout;
    } on MediaOperationCancelled catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
      trigger = MediaCleanupTrigger.cancellation;
    } on Object catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
      trigger = MediaCleanupTrigger.failure;
    }

    if (batch.retention.requiresCleanup(trigger)) {
      try {
        await _cleanup.discardPreparedMedia(batch: batch, trigger: trigger);
      } on Object {
        throw PreparedMediaCleanupFailure(
          trigger: trigger,
          operationAlsoFailed: operationError != null,
        );
      }
    }
    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
    return value;
  }
}
