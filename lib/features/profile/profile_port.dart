import 'dart:typed_data';

abstract interface class ProfilePort {
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  });
}

typedef ProfileRecord = Map<String, Object?>;
ProfileRecord profileRecord(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
List<ProfileRecord> profileRecords(Object? value) =>
    (profileRecord(value)['data'] as List? ?? <Object?>[])
        .map(profileRecord)
        .toList();
int profileInteger(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
Uint8List? profileBytes(Object? value) => value is Uint8List
    ? value
    : value is List<int>
    ? Uint8List.fromList(value)
    : null;

final class ProfileFailure implements Exception {
  const ProfileFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String profileError(Object error) => error is ProfileFailure
    ? error.message
    : 'This operation could not be completed. Please try again.';
