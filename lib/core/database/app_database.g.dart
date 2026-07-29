// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalRecordsTable extends LocalRecords
    with TableInfo<$LocalRecordsTable, LocalRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isTombstoneMeta = const VerificationMeta(
    'isTombstone',
  );
  @override
  late final GeneratedColumn<bool> isTombstone = GeneratedColumn<bool>(
    'is_tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _synchronizedAtMeta = const VerificationMeta(
    'synchronizedAt',
  );
  @override
  late final GeneratedColumn<DateTime> synchronizedAt =
      GeneratedColumn<DateTime>(
        'synchronized_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    homeId,
    entityType,
    entityId,
    payload,
    revision,
    isTombstone,
    updatedAt,
    synchronizedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('is_tombstone')) {
      context.handle(
        _isTombstoneMeta,
        isTombstone.isAcceptableOrUnknown(
          data['is_tombstone']!,
          _isTombstoneMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('synchronized_at')) {
      context.handle(
        _synchronizedAtMeta,
        synchronizedAt.isAcceptableOrUnknown(
          data['synchronized_at']!,
          _synchronizedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {homeId, entityType, entityId};
  @override
  LocalRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRecord(
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      isTombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_tombstone'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      synchronizedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synchronized_at'],
      ),
    );
  }

  @override
  $LocalRecordsTable createAlias(String alias) {
    return $LocalRecordsTable(attachedDatabase, alias);
  }
}

class LocalRecord extends DataClass implements Insertable<LocalRecord> {
  final String homeId;
  final String entityType;
  final String entityId;
  final String payload;
  final int revision;
  final bool isTombstone;
  final DateTime updatedAt;
  final DateTime? synchronizedAt;
  const LocalRecord({
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.revision,
    required this.isTombstone,
    required this.updatedAt,
    this.synchronizedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['home_id'] = Variable<String>(homeId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['payload'] = Variable<String>(payload);
    map['revision'] = Variable<int>(revision);
    map['is_tombstone'] = Variable<bool>(isTombstone);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || synchronizedAt != null) {
      map['synchronized_at'] = Variable<DateTime>(synchronizedAt);
    }
    return map;
  }

  LocalRecordsCompanion toCompanion(bool nullToAbsent) {
    return LocalRecordsCompanion(
      homeId: Value(homeId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      payload: Value(payload),
      revision: Value(revision),
      isTombstone: Value(isTombstone),
      updatedAt: Value(updatedAt),
      synchronizedAt: synchronizedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(synchronizedAt),
    );
  }

  factory LocalRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRecord(
      homeId: serializer.fromJson<String>(json['homeId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      payload: serializer.fromJson<String>(json['payload']),
      revision: serializer.fromJson<int>(json['revision']),
      isTombstone: serializer.fromJson<bool>(json['isTombstone']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      synchronizedAt: serializer.fromJson<DateTime?>(json['synchronizedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'homeId': serializer.toJson<String>(homeId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'payload': serializer.toJson<String>(payload),
      'revision': serializer.toJson<int>(revision),
      'isTombstone': serializer.toJson<bool>(isTombstone),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'synchronizedAt': serializer.toJson<DateTime?>(synchronizedAt),
    };
  }

  LocalRecord copyWith({
    String? homeId,
    String? entityType,
    String? entityId,
    String? payload,
    int? revision,
    bool? isTombstone,
    DateTime? updatedAt,
    Value<DateTime?> synchronizedAt = const Value.absent(),
  }) => LocalRecord(
    homeId: homeId ?? this.homeId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    payload: payload ?? this.payload,
    revision: revision ?? this.revision,
    isTombstone: isTombstone ?? this.isTombstone,
    updatedAt: updatedAt ?? this.updatedAt,
    synchronizedAt: synchronizedAt.present
        ? synchronizedAt.value
        : this.synchronizedAt,
  );
  LocalRecord copyWithCompanion(LocalRecordsCompanion data) {
    return LocalRecord(
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      payload: data.payload.present ? data.payload.value : this.payload,
      revision: data.revision.present ? data.revision.value : this.revision,
      isTombstone: data.isTombstone.present
          ? data.isTombstone.value
          : this.isTombstone,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      synchronizedAt: data.synchronizedAt.present
          ? data.synchronizedAt.value
          : this.synchronizedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecord(')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payload: $payload, ')
          ..write('revision: $revision, ')
          ..write('isTombstone: $isTombstone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('synchronizedAt: $synchronizedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    homeId,
    entityType,
    entityId,
    payload,
    revision,
    isTombstone,
    updatedAt,
    synchronizedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRecord &&
          other.homeId == this.homeId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.payload == this.payload &&
          other.revision == this.revision &&
          other.isTombstone == this.isTombstone &&
          other.updatedAt == this.updatedAt &&
          other.synchronizedAt == this.synchronizedAt);
}

class LocalRecordsCompanion extends UpdateCompanion<LocalRecord> {
  final Value<String> homeId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> payload;
  final Value<int> revision;
  final Value<bool> isTombstone;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> synchronizedAt;
  final Value<int> rowid;
  const LocalRecordsCompanion({
    this.homeId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payload = const Value.absent(),
    this.revision = const Value.absent(),
    this.isTombstone = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.synchronizedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRecordsCompanion.insert({
    required String homeId,
    required String entityType,
    required String entityId,
    required String payload,
    this.revision = const Value.absent(),
    this.isTombstone = const Value.absent(),
    required DateTime updatedAt,
    this.synchronizedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : homeId = Value(homeId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       payload = Value(payload),
       updatedAt = Value(updatedAt);
  static Insertable<LocalRecord> custom({
    Expression<String>? homeId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? payload,
    Expression<int>? revision,
    Expression<bool>? isTombstone,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? synchronizedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (homeId != null) 'home_id': homeId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (payload != null) 'payload': payload,
      if (revision != null) 'revision': revision,
      if (isTombstone != null) 'is_tombstone': isTombstone,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (synchronizedAt != null) 'synchronized_at': synchronizedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRecordsCompanion copyWith({
    Value<String>? homeId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? payload,
    Value<int>? revision,
    Value<bool>? isTombstone,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? synchronizedAt,
    Value<int>? rowid,
  }) {
    return LocalRecordsCompanion(
      homeId: homeId ?? this.homeId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      revision: revision ?? this.revision,
      isTombstone: isTombstone ?? this.isTombstone,
      updatedAt: updatedAt ?? this.updatedAt,
      synchronizedAt: synchronizedAt ?? this.synchronizedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (isTombstone.present) {
      map['is_tombstone'] = Variable<bool>(isTombstone.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (synchronizedAt.present) {
      map['synchronized_at'] = Variable<DateTime>(synchronizedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecordsCompanion(')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payload: $payload, ')
          ..write('revision: $revision, ')
          ..write('isTombstone: $isTombstone, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('synchronizedAt: $synchronizedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientOperationsTable extends ClientOperations
    with TableInfo<$ClientOperationsTable, ClientOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientTimestampMeta = const VerificationMeta(
    'clientTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> clientTimestamp =
      GeneratedColumn<DateTime>(
        'client_timestamp',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _payloadSchemaVersionMeta =
      const VerificationMeta('payloadSchemaVersion');
  @override
  late final GeneratedColumn<int> payloadSchemaVersion = GeneratedColumn<int>(
    'payload_schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSafeErrorMeta = const VerificationMeta(
    'lastSafeError',
  );
  @override
  late final GeneratedColumn<String> lastSafeError = GeneratedColumn<String>(
    'last_safe_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverCursorMeta = const VerificationMeta(
    'serverCursor',
  );
  @override
  late final GeneratedColumn<String> serverCursor = GeneratedColumn<String>(
    'server_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMeta = const VerificationMeta(
    'acknowledgedAt',
  );
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt =
      GeneratedColumn<DateTime>(
        'acknowledged_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    deviceId,
    homeId,
    entityType,
    entityId,
    operationType,
    baseRevision,
    clientTimestamp,
    payloadSchemaVersion,
    payload,
    retryCount,
    nextAttemptAt,
    lastSafeError,
    state,
    serverCursor,
    acknowledgedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    }
    if (data.containsKey('client_timestamp')) {
      context.handle(
        _clientTimestampMeta,
        clientTimestamp.isAcceptableOrUnknown(
          data['client_timestamp']!,
          _clientTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientTimestampMeta);
    }
    if (data.containsKey('payload_schema_version')) {
      context.handle(
        _payloadSchemaVersionMeta,
        payloadSchemaVersion.isAcceptableOrUnknown(
          data['payload_schema_version']!,
          _payloadSchemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_safe_error')) {
      context.handle(
        _lastSafeErrorMeta,
        lastSafeError.isAcceptableOrUnknown(
          data['last_safe_error']!,
          _lastSafeErrorMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('server_cursor')) {
      context.handle(
        _serverCursorMeta,
        serverCursor.isAcceptableOrUnknown(
          data['server_cursor']!,
          _serverCursorMeta,
        ),
      );
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
        _acknowledgedAtMeta,
        acknowledgedAt.isAcceptableOrUnknown(
          data['acknowledged_at']!,
          _acknowledgedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  ClientOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientOperation(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      ),
      clientTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_timestamp'],
      )!,
      payloadSchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_schema_version'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastSafeError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_safe_error'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      serverCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_cursor'],
      ),
      acknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}acknowledged_at'],
      ),
    );
  }

  @override
  $ClientOperationsTable createAlias(String alias) {
    return $ClientOperationsTable(attachedDatabase, alias);
  }
}

class ClientOperation extends DataClass implements Insertable<ClientOperation> {
  final String operationId;
  final String deviceId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;

  /// Introduced in schema v2. Existing pending operations are rebased to v1.
  final int payloadSchemaVersion;
  final String payload;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? lastSafeError;
  final String state;
  final String? serverCursor;
  final DateTime? acknowledgedAt;
  const ClientOperation({
    required this.operationId,
    required this.deviceId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required this.payload,
    required this.retryCount,
    this.nextAttemptAt,
    this.lastSafeError,
    required this.state,
    this.serverCursor,
    this.acknowledgedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['device_id'] = Variable<String>(deviceId);
    map['home_id'] = Variable<String>(homeId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation_type'] = Variable<String>(operationType);
    if (!nullToAbsent || baseRevision != null) {
      map['base_revision'] = Variable<int>(baseRevision);
    }
    map['client_timestamp'] = Variable<DateTime>(clientTimestamp);
    map['payload_schema_version'] = Variable<int>(payloadSchemaVersion);
    map['payload'] = Variable<String>(payload);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastSafeError != null) {
      map['last_safe_error'] = Variable<String>(lastSafeError);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || serverCursor != null) {
      map['server_cursor'] = Variable<String>(serverCursor);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    return map;
  }

  ClientOperationsCompanion toCompanion(bool nullToAbsent) {
    return ClientOperationsCompanion(
      operationId: Value(operationId),
      deviceId: Value(deviceId),
      homeId: Value(homeId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operationType: Value(operationType),
      baseRevision: baseRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevision),
      clientTimestamp: Value(clientTimestamp),
      payloadSchemaVersion: Value(payloadSchemaVersion),
      payload: Value(payload),
      retryCount: Value(retryCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastSafeError: lastSafeError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSafeError),
      state: Value(state),
      serverCursor: serverCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(serverCursor),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
    );
  }

  factory ClientOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientOperation(
      operationId: serializer.fromJson<String>(json['operationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      homeId: serializer.fromJson<String>(json['homeId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      baseRevision: serializer.fromJson<int?>(json['baseRevision']),
      clientTimestamp: serializer.fromJson<DateTime>(json['clientTimestamp']),
      payloadSchemaVersion: serializer.fromJson<int>(
        json['payloadSchemaVersion'],
      ),
      payload: serializer.fromJson<String>(json['payload']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastSafeError: serializer.fromJson<String?>(json['lastSafeError']),
      state: serializer.fromJson<String>(json['state']),
      serverCursor: serializer.fromJson<String?>(json['serverCursor']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'homeId': serializer.toJson<String>(homeId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operationType': serializer.toJson<String>(operationType),
      'baseRevision': serializer.toJson<int?>(baseRevision),
      'clientTimestamp': serializer.toJson<DateTime>(clientTimestamp),
      'payloadSchemaVersion': serializer.toJson<int>(payloadSchemaVersion),
      'payload': serializer.toJson<String>(payload),
      'retryCount': serializer.toJson<int>(retryCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastSafeError': serializer.toJson<String?>(lastSafeError),
      'state': serializer.toJson<String>(state),
      'serverCursor': serializer.toJson<String?>(serverCursor),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
    };
  }

  ClientOperation copyWith({
    String? operationId,
    String? deviceId,
    String? homeId,
    String? entityType,
    String? entityId,
    String? operationType,
    Value<int?> baseRevision = const Value.absent(),
    DateTime? clientTimestamp,
    int? payloadSchemaVersion,
    String? payload,
    int? retryCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastSafeError = const Value.absent(),
    String? state,
    Value<String?> serverCursor = const Value.absent(),
    Value<DateTime?> acknowledgedAt = const Value.absent(),
  }) => ClientOperation(
    operationId: operationId ?? this.operationId,
    deviceId: deviceId ?? this.deviceId,
    homeId: homeId ?? this.homeId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operationType: operationType ?? this.operationType,
    baseRevision: baseRevision.present ? baseRevision.value : this.baseRevision,
    clientTimestamp: clientTimestamp ?? this.clientTimestamp,
    payloadSchemaVersion: payloadSchemaVersion ?? this.payloadSchemaVersion,
    payload: payload ?? this.payload,
    retryCount: retryCount ?? this.retryCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastSafeError: lastSafeError.present
        ? lastSafeError.value
        : this.lastSafeError,
    state: state ?? this.state,
    serverCursor: serverCursor.present ? serverCursor.value : this.serverCursor,
    acknowledgedAt: acknowledgedAt.present
        ? acknowledgedAt.value
        : this.acknowledgedAt,
  );
  ClientOperation copyWithCompanion(ClientOperationsCompanion data) {
    return ClientOperation(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      clientTimestamp: data.clientTimestamp.present
          ? data.clientTimestamp.value
          : this.clientTimestamp,
      payloadSchemaVersion: data.payloadSchemaVersion.present
          ? data.payloadSchemaVersion.value
          : this.payloadSchemaVersion,
      payload: data.payload.present ? data.payload.value : this.payload,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastSafeError: data.lastSafeError.present
          ? data.lastSafeError.value
          : this.lastSafeError,
      state: data.state.present ? data.state.value : this.state,
      serverCursor: data.serverCursor.present
          ? data.serverCursor.value
          : this.serverCursor,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientOperation(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationType: $operationType, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('clientTimestamp: $clientTimestamp, ')
          ..write('payloadSchemaVersion: $payloadSchemaVersion, ')
          ..write('payload: $payload, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastSafeError: $lastSafeError, ')
          ..write('state: $state, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('acknowledgedAt: $acknowledgedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    deviceId,
    homeId,
    entityType,
    entityId,
    operationType,
    baseRevision,
    clientTimestamp,
    payloadSchemaVersion,
    payload,
    retryCount,
    nextAttemptAt,
    lastSafeError,
    state,
    serverCursor,
    acknowledgedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientOperation &&
          other.operationId == this.operationId &&
          other.deviceId == this.deviceId &&
          other.homeId == this.homeId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operationType == this.operationType &&
          other.baseRevision == this.baseRevision &&
          other.clientTimestamp == this.clientTimestamp &&
          other.payloadSchemaVersion == this.payloadSchemaVersion &&
          other.payload == this.payload &&
          other.retryCount == this.retryCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastSafeError == this.lastSafeError &&
          other.state == this.state &&
          other.serverCursor == this.serverCursor &&
          other.acknowledgedAt == this.acknowledgedAt);
}

class ClientOperationsCompanion extends UpdateCompanion<ClientOperation> {
  final Value<String> operationId;
  final Value<String> deviceId;
  final Value<String> homeId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operationType;
  final Value<int?> baseRevision;
  final Value<DateTime> clientTimestamp;
  final Value<int> payloadSchemaVersion;
  final Value<String> payload;
  final Value<int> retryCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastSafeError;
  final Value<String> state;
  final Value<String?> serverCursor;
  final Value<DateTime?> acknowledgedAt;
  final Value<int> rowid;
  const ClientOperationsCompanion({
    this.operationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.homeId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.clientTimestamp = const Value.absent(),
    this.payloadSchemaVersion = const Value.absent(),
    this.payload = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastSafeError = const Value.absent(),
    this.state = const Value.absent(),
    this.serverCursor = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientOperationsCompanion.insert({
    required String operationId,
    required String deviceId,
    required String homeId,
    required String entityType,
    required String entityId,
    required String operationType,
    this.baseRevision = const Value.absent(),
    required DateTime clientTimestamp,
    this.payloadSchemaVersion = const Value.absent(),
    required String payload,
    this.retryCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastSafeError = const Value.absent(),
    required String state,
    this.serverCursor = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       deviceId = Value(deviceId),
       homeId = Value(homeId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operationType = Value(operationType),
       clientTimestamp = Value(clientTimestamp),
       payload = Value(payload),
       state = Value(state);
  static Insertable<ClientOperation> custom({
    Expression<String>? operationId,
    Expression<String>? deviceId,
    Expression<String>? homeId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operationType,
    Expression<int>? baseRevision,
    Expression<DateTime>? clientTimestamp,
    Expression<int>? payloadSchemaVersion,
    Expression<String>? payload,
    Expression<int>? retryCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastSafeError,
    Expression<String>? state,
    Expression<String>? serverCursor,
    Expression<DateTime>? acknowledgedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (deviceId != null) 'device_id': deviceId,
      if (homeId != null) 'home_id': homeId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operationType != null) 'operation_type': operationType,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (clientTimestamp != null) 'client_timestamp': clientTimestamp,
      if (payloadSchemaVersion != null)
        'payload_schema_version': payloadSchemaVersion,
      if (payload != null) 'payload': payload,
      if (retryCount != null) 'retry_count': retryCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastSafeError != null) 'last_safe_error': lastSafeError,
      if (state != null) 'state': state,
      if (serverCursor != null) 'server_cursor': serverCursor,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? deviceId,
    Value<String>? homeId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operationType,
    Value<int?>? baseRevision,
    Value<DateTime>? clientTimestamp,
    Value<int>? payloadSchemaVersion,
    Value<String>? payload,
    Value<int>? retryCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastSafeError,
    Value<String>? state,
    Value<String?>? serverCursor,
    Value<DateTime?>? acknowledgedAt,
    Value<int>? rowid,
  }) {
    return ClientOperationsCompanion(
      operationId: operationId ?? this.operationId,
      deviceId: deviceId ?? this.deviceId,
      homeId: homeId ?? this.homeId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      baseRevision: baseRevision ?? this.baseRevision,
      clientTimestamp: clientTimestamp ?? this.clientTimestamp,
      payloadSchemaVersion: payloadSchemaVersion ?? this.payloadSchemaVersion,
      payload: payload ?? this.payload,
      retryCount: retryCount ?? this.retryCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastSafeError: lastSafeError ?? this.lastSafeError,
      state: state ?? this.state,
      serverCursor: serverCursor ?? this.serverCursor,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (clientTimestamp.present) {
      map['client_timestamp'] = Variable<DateTime>(clientTimestamp.value);
    }
    if (payloadSchemaVersion.present) {
      map['payload_schema_version'] = Variable<int>(payloadSchemaVersion.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastSafeError.present) {
      map['last_safe_error'] = Variable<String>(lastSafeError.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (serverCursor.present) {
      map['server_cursor'] = Variable<String>(serverCursor.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationType: $operationType, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('clientTimestamp: $clientTimestamp, ')
          ..write('payloadSchemaVersion: $payloadSchemaVersion, ')
          ..write('payload: $payload, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastSafeError: $lastSafeError, ')
          ..write('state: $state, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSyncCursorsTable extends LocalSyncCursors
    with TableInfo<$LocalSyncCursorsTable, LocalSyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedMeta = const VerificationMeta('feed');
  @override
  late final GeneratedColumn<String> feed = GeneratedColumn<String>(
    'feed',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('home_changes'),
  );
  static const VerificationMeta _protocolVersionMeta = const VerificationMeta(
    'protocolVersion',
  );
  @override
  late final GeneratedColumn<int> protocolVersion = GeneratedColumn<int>(
    'protocol_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _schemaGenerationMeta = const VerificationMeta(
    'schemaGeneration',
  );
  @override
  late final GeneratedColumn<int> schemaGeneration = GeneratedColumn<int>(
    'schema_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    homeId,
    feed,
    protocolVersion,
    schemaGeneration,
    cursor,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('feed')) {
      context.handle(
        _feedMeta,
        feed.isAcceptableOrUnknown(data['feed']!, _feedMeta),
      );
    }
    if (data.containsKey('protocol_version')) {
      context.handle(
        _protocolVersionMeta,
        protocolVersion.isAcceptableOrUnknown(
          data['protocol_version']!,
          _protocolVersionMeta,
        ),
      );
    }
    if (data.containsKey('schema_generation')) {
      context.handle(
        _schemaGenerationMeta,
        schemaGeneration.isAcceptableOrUnknown(
          data['schema_generation']!,
          _schemaGenerationMeta,
        ),
      );
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    homeId,
    feed,
    protocolVersion,
    schemaGeneration,
  };
  @override
  LocalSyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncCursor(
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      feed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feed'],
      )!,
      protocolVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_version'],
      )!,
      schemaGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_generation'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalSyncCursorsTable createAlias(String alias) {
    return $LocalSyncCursorsTable(attachedDatabase, alias);
  }
}

class LocalSyncCursor extends DataClass implements Insertable<LocalSyncCursor> {
  final String homeId;
  final String feed;
  final int protocolVersion;
  final int schemaGeneration;
  final String cursor;
  final DateTime updatedAt;
  const LocalSyncCursor({
    required this.homeId,
    required this.feed,
    required this.protocolVersion,
    required this.schemaGeneration,
    required this.cursor,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['home_id'] = Variable<String>(homeId);
    map['feed'] = Variable<String>(feed);
    map['protocol_version'] = Variable<int>(protocolVersion);
    map['schema_generation'] = Variable<int>(schemaGeneration);
    map['cursor'] = Variable<String>(cursor);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalSyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncCursorsCompanion(
      homeId: Value(homeId),
      feed: Value(feed),
      protocolVersion: Value(protocolVersion),
      schemaGeneration: Value(schemaGeneration),
      cursor: Value(cursor),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalSyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncCursor(
      homeId: serializer.fromJson<String>(json['homeId']),
      feed: serializer.fromJson<String>(json['feed']),
      protocolVersion: serializer.fromJson<int>(json['protocolVersion']),
      schemaGeneration: serializer.fromJson<int>(json['schemaGeneration']),
      cursor: serializer.fromJson<String>(json['cursor']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'homeId': serializer.toJson<String>(homeId),
      'feed': serializer.toJson<String>(feed),
      'protocolVersion': serializer.toJson<int>(protocolVersion),
      'schemaGeneration': serializer.toJson<int>(schemaGeneration),
      'cursor': serializer.toJson<String>(cursor),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalSyncCursor copyWith({
    String? homeId,
    String? feed,
    int? protocolVersion,
    int? schemaGeneration,
    String? cursor,
    DateTime? updatedAt,
  }) => LocalSyncCursor(
    homeId: homeId ?? this.homeId,
    feed: feed ?? this.feed,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    schemaGeneration: schemaGeneration ?? this.schemaGeneration,
    cursor: cursor ?? this.cursor,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalSyncCursor copyWithCompanion(LocalSyncCursorsCompanion data) {
    return LocalSyncCursor(
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      feed: data.feed.present ? data.feed.value : this.feed,
      protocolVersion: data.protocolVersion.present
          ? data.protocolVersion.value
          : this.protocolVersion,
      schemaGeneration: data.schemaGeneration.present
          ? data.schemaGeneration.value
          : this.schemaGeneration,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncCursor(')
          ..write('homeId: $homeId, ')
          ..write('feed: $feed, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('schemaGeneration: $schemaGeneration, ')
          ..write('cursor: $cursor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    homeId,
    feed,
    protocolVersion,
    schemaGeneration,
    cursor,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncCursor &&
          other.homeId == this.homeId &&
          other.feed == this.feed &&
          other.protocolVersion == this.protocolVersion &&
          other.schemaGeneration == this.schemaGeneration &&
          other.cursor == this.cursor &&
          other.updatedAt == this.updatedAt);
}

class LocalSyncCursorsCompanion extends UpdateCompanion<LocalSyncCursor> {
  final Value<String> homeId;
  final Value<String> feed;
  final Value<int> protocolVersion;
  final Value<int> schemaGeneration;
  final Value<String> cursor;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalSyncCursorsCompanion({
    this.homeId = const Value.absent(),
    this.feed = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.schemaGeneration = const Value.absent(),
    this.cursor = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncCursorsCompanion.insert({
    required String homeId,
    this.feed = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.schemaGeneration = const Value.absent(),
    required String cursor,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : homeId = Value(homeId),
       cursor = Value(cursor),
       updatedAt = Value(updatedAt);
  static Insertable<LocalSyncCursor> custom({
    Expression<String>? homeId,
    Expression<String>? feed,
    Expression<int>? protocolVersion,
    Expression<int>? schemaGeneration,
    Expression<String>? cursor,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (homeId != null) 'home_id': homeId,
      if (feed != null) 'feed': feed,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (schemaGeneration != null) 'schema_generation': schemaGeneration,
      if (cursor != null) 'cursor': cursor,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncCursorsCompanion copyWith({
    Value<String>? homeId,
    Value<String>? feed,
    Value<int>? protocolVersion,
    Value<int>? schemaGeneration,
    Value<String>? cursor,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalSyncCursorsCompanion(
      homeId: homeId ?? this.homeId,
      feed: feed ?? this.feed,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      schemaGeneration: schemaGeneration ?? this.schemaGeneration,
      cursor: cursor ?? this.cursor,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (feed.present) {
      map['feed'] = Variable<String>(feed.value);
    }
    if (protocolVersion.present) {
      map['protocol_version'] = Variable<int>(protocolVersion.value);
    }
    if (schemaGeneration.present) {
      map['schema_generation'] = Variable<int>(schemaGeneration.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncCursorsCompanion(')
          ..write('homeId: $homeId, ')
          ..write('feed: $feed, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('schemaGeneration: $schemaGeneration, ')
          ..write('cursor: $cursor, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecordTombstonesTable extends RecordTombstones
    with TableInfo<$RecordTombstonesTable, RecordTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    homeId,
    entityType,
    entityId,
    revision,
    cursor,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'record_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {homeId, entityType, entityId};
  @override
  RecordTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordTombstone(
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $RecordTombstonesTable createAlias(String alias) {
    return $RecordTombstonesTable(attachedDatabase, alias);
  }
}

class RecordTombstone extends DataClass implements Insertable<RecordTombstone> {
  final String homeId;
  final String entityType;
  final String entityId;
  final int revision;
  final String cursor;
  final DateTime deletedAt;
  const RecordTombstone({
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.revision,
    required this.cursor,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['home_id'] = Variable<String>(homeId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['revision'] = Variable<int>(revision);
    map['cursor'] = Variable<String>(cursor);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  RecordTombstonesCompanion toCompanion(bool nullToAbsent) {
    return RecordTombstonesCompanion(
      homeId: Value(homeId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      revision: Value(revision),
      cursor: Value(cursor),
      deletedAt: Value(deletedAt),
    );
  }

  factory RecordTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordTombstone(
      homeId: serializer.fromJson<String>(json['homeId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      revision: serializer.fromJson<int>(json['revision']),
      cursor: serializer.fromJson<String>(json['cursor']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'homeId': serializer.toJson<String>(homeId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'revision': serializer.toJson<int>(revision),
      'cursor': serializer.toJson<String>(cursor),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  RecordTombstone copyWith({
    String? homeId,
    String? entityType,
    String? entityId,
    int? revision,
    String? cursor,
    DateTime? deletedAt,
  }) => RecordTombstone(
    homeId: homeId ?? this.homeId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    revision: revision ?? this.revision,
    cursor: cursor ?? this.cursor,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  RecordTombstone copyWithCompanion(RecordTombstonesCompanion data) {
    return RecordTombstone(
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      revision: data.revision.present ? data.revision.value : this.revision,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordTombstone(')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('revision: $revision, ')
          ..write('cursor: $cursor, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(homeId, entityType, entityId, revision, cursor, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordTombstone &&
          other.homeId == this.homeId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.revision == this.revision &&
          other.cursor == this.cursor &&
          other.deletedAt == this.deletedAt);
}

class RecordTombstonesCompanion extends UpdateCompanion<RecordTombstone> {
  final Value<String> homeId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> revision;
  final Value<String> cursor;
  final Value<DateTime> deletedAt;
  final Value<int> rowid;
  const RecordTombstonesCompanion({
    this.homeId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.revision = const Value.absent(),
    this.cursor = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordTombstonesCompanion.insert({
    required String homeId,
    required String entityType,
    required String entityId,
    required int revision,
    required String cursor,
    required DateTime deletedAt,
    this.rowid = const Value.absent(),
  }) : homeId = Value(homeId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       revision = Value(revision),
       cursor = Value(cursor),
       deletedAt = Value(deletedAt);
  static Insertable<RecordTombstone> custom({
    Expression<String>? homeId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? revision,
    Expression<String>? cursor,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (homeId != null) 'home_id': homeId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (revision != null) 'revision': revision,
      if (cursor != null) 'cursor': cursor,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordTombstonesCompanion copyWith({
    Value<String>? homeId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? revision,
    Value<String>? cursor,
    Value<DateTime>? deletedAt,
    Value<int>? rowid,
  }) {
    return RecordTombstonesCompanion(
      homeId: homeId ?? this.homeId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      revision: revision ?? this.revision,
      cursor: cursor ?? this.cursor,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordTombstonesCompanion(')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('revision: $revision, ')
          ..write('cursor: $cursor, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMediaMetadataTable extends LocalMediaMetadata
    with TableInfo<$LocalMediaMetadataTable, LocalMediaMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMediaMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localReferenceMeta = const VerificationMeta(
    'localReference',
  );
  @override
  late final GeneratedColumn<String> localReference = GeneratedColumn<String>(
    'local_reference',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteLengthMeta = const VerificationMeta(
    'byteLength',
  );
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
    'byte_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<String> uploadState = GeneratedColumn<String>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    homeId,
    purpose,
    localReference,
    sha256,
    mimeType,
    byteLength,
    uploadState,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_media_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMediaMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    } else if (isInserting) {
      context.missing(_purposeMeta);
    }
    if (data.containsKey('local_reference')) {
      context.handle(
        _localReferenceMeta,
        localReference.isAcceptableOrUnknown(
          data['local_reference']!,
          _localReferenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localReferenceMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('byte_length')) {
      context.handle(
        _byteLengthMeta,
        byteLength.isAcceptableOrUnknown(data['byte_length']!, _byteLengthMeta),
      );
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  LocalMediaMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMediaMetadataData(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      localReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_reference'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      byteLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_length'],
      ),
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LocalMediaMetadataTable createAlias(String alias) {
    return $LocalMediaMetadataTable(attachedDatabase, alias);
  }
}

class LocalMediaMetadataData extends DataClass
    implements Insertable<LocalMediaMetadataData> {
  final String mediaId;
  final String homeId;
  final String purpose;
  final String localReference;
  final String? sha256;
  final String? mimeType;
  final int? byteLength;
  final String uploadState;
  final DateTime createdAt;
  const LocalMediaMetadataData({
    required this.mediaId,
    required this.homeId,
    required this.purpose,
    required this.localReference,
    this.sha256,
    this.mimeType,
    this.byteLength,
    required this.uploadState,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['home_id'] = Variable<String>(homeId);
    map['purpose'] = Variable<String>(purpose);
    map['local_reference'] = Variable<String>(localReference);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || byteLength != null) {
      map['byte_length'] = Variable<int>(byteLength);
    }
    map['upload_state'] = Variable<String>(uploadState);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalMediaMetadataCompanion toCompanion(bool nullToAbsent) {
    return LocalMediaMetadataCompanion(
      mediaId: Value(mediaId),
      homeId: Value(homeId),
      purpose: Value(purpose),
      localReference: Value(localReference),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      byteLength: byteLength == null && nullToAbsent
          ? const Value.absent()
          : Value(byteLength),
      uploadState: Value(uploadState),
      createdAt: Value(createdAt),
    );
  }

  factory LocalMediaMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMediaMetadataData(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      homeId: serializer.fromJson<String>(json['homeId']),
      purpose: serializer.fromJson<String>(json['purpose']),
      localReference: serializer.fromJson<String>(json['localReference']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      byteLength: serializer.fromJson<int?>(json['byteLength']),
      uploadState: serializer.fromJson<String>(json['uploadState']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'homeId': serializer.toJson<String>(homeId),
      'purpose': serializer.toJson<String>(purpose),
      'localReference': serializer.toJson<String>(localReference),
      'sha256': serializer.toJson<String?>(sha256),
      'mimeType': serializer.toJson<String?>(mimeType),
      'byteLength': serializer.toJson<int?>(byteLength),
      'uploadState': serializer.toJson<String>(uploadState),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalMediaMetadataData copyWith({
    String? mediaId,
    String? homeId,
    String? purpose,
    String? localReference,
    Value<String?> sha256 = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<int?> byteLength = const Value.absent(),
    String? uploadState,
    DateTime? createdAt,
  }) => LocalMediaMetadataData(
    mediaId: mediaId ?? this.mediaId,
    homeId: homeId ?? this.homeId,
    purpose: purpose ?? this.purpose,
    localReference: localReference ?? this.localReference,
    sha256: sha256.present ? sha256.value : this.sha256,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    byteLength: byteLength.present ? byteLength.value : this.byteLength,
    uploadState: uploadState ?? this.uploadState,
    createdAt: createdAt ?? this.createdAt,
  );
  LocalMediaMetadataData copyWithCompanion(LocalMediaMetadataCompanion data) {
    return LocalMediaMetadataData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      localReference: data.localReference.present
          ? data.localReference.value
          : this.localReference,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      byteLength: data.byteLength.present
          ? data.byteLength.value
          : this.byteLength,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMediaMetadataData(')
          ..write('mediaId: $mediaId, ')
          ..write('homeId: $homeId, ')
          ..write('purpose: $purpose, ')
          ..write('localReference: $localReference, ')
          ..write('sha256: $sha256, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteLength: $byteLength, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mediaId,
    homeId,
    purpose,
    localReference,
    sha256,
    mimeType,
    byteLength,
    uploadState,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMediaMetadataData &&
          other.mediaId == this.mediaId &&
          other.homeId == this.homeId &&
          other.purpose == this.purpose &&
          other.localReference == this.localReference &&
          other.sha256 == this.sha256 &&
          other.mimeType == this.mimeType &&
          other.byteLength == this.byteLength &&
          other.uploadState == this.uploadState &&
          other.createdAt == this.createdAt);
}

class LocalMediaMetadataCompanion
    extends UpdateCompanion<LocalMediaMetadataData> {
  final Value<String> mediaId;
  final Value<String> homeId;
  final Value<String> purpose;
  final Value<String> localReference;
  final Value<String?> sha256;
  final Value<String?> mimeType;
  final Value<int?> byteLength;
  final Value<String> uploadState;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalMediaMetadataCompanion({
    this.mediaId = const Value.absent(),
    this.homeId = const Value.absent(),
    this.purpose = const Value.absent(),
    this.localReference = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMediaMetadataCompanion.insert({
    required String mediaId,
    required String homeId,
    required String purpose,
    required String localReference,
    this.sha256 = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.uploadState = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       homeId = Value(homeId),
       purpose = Value(purpose),
       localReference = Value(localReference),
       createdAt = Value(createdAt);
  static Insertable<LocalMediaMetadataData> custom({
    Expression<String>? mediaId,
    Expression<String>? homeId,
    Expression<String>? purpose,
    Expression<String>? localReference,
    Expression<String>? sha256,
    Expression<String>? mimeType,
    Expression<int>? byteLength,
    Expression<String>? uploadState,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (homeId != null) 'home_id': homeId,
      if (purpose != null) 'purpose': purpose,
      if (localReference != null) 'local_reference': localReference,
      if (sha256 != null) 'sha256': sha256,
      if (mimeType != null) 'mime_type': mimeType,
      if (byteLength != null) 'byte_length': byteLength,
      if (uploadState != null) 'upload_state': uploadState,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMediaMetadataCompanion copyWith({
    Value<String>? mediaId,
    Value<String>? homeId,
    Value<String>? purpose,
    Value<String>? localReference,
    Value<String?>? sha256,
    Value<String?>? mimeType,
    Value<int?>? byteLength,
    Value<String>? uploadState,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LocalMediaMetadataCompanion(
      mediaId: mediaId ?? this.mediaId,
      homeId: homeId ?? this.homeId,
      purpose: purpose ?? this.purpose,
      localReference: localReference ?? this.localReference,
      sha256: sha256 ?? this.sha256,
      mimeType: mimeType ?? this.mimeType,
      byteLength: byteLength ?? this.byteLength,
      uploadState: uploadState ?? this.uploadState,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (localReference.present) {
      map['local_reference'] = Variable<String>(localReference.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<String>(uploadState.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMediaMetadataCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('homeId: $homeId, ')
          ..write('purpose: $purpose, ')
          ..write('localReference: $localReference, ')
          ..write('sha256: $sha256, ')
          ..write('mimeType: $mimeType, ')
          ..write('byteLength: $byteLength, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictRecordsTable extends SyncConflictRecords
    with TableInfo<$SyncConflictRecordsTable, SyncConflictRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conflictIdMeta = const VerificationMeta(
    'conflictId',
  );
  @override
  late final GeneratedColumn<String> conflictId = GeneratedColumn<String>(
    'conflict_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conflictKindMeta = const VerificationMeta(
    'conflictKind',
  );
  @override
  late final GeneratedColumn<String> conflictKind = GeneratedColumn<String>(
    'conflict_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPayloadMeta = const VerificationMeta(
    'localPayload',
  );
  @override
  late final GeneratedColumn<String> localPayload = GeneratedColumn<String>(
    'local_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remotePayloadMeta = const VerificationMeta(
    'remotePayload',
  );
  @override
  late final GeneratedColumn<String> remotePayload = GeneratedColumn<String>(
    'remote_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteRevisionMeta = const VerificationMeta(
    'remoteRevision',
  );
  @override
  late final GeneratedColumn<int> remoteRevision = GeneratedColumn<int>(
    'remote_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detectedAtMeta = const VerificationMeta(
    'detectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> detectedAt = GeneratedColumn<DateTime>(
    'detected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conflictId,
    operationId,
    homeId,
    entityType,
    entityId,
    conflictKind,
    localPayload,
    remotePayload,
    remoteRevision,
    detectedAt,
    resolvedAt,
    resolution,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflict_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflictRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conflict_id')) {
      context.handle(
        _conflictIdMeta,
        conflictId.isAcceptableOrUnknown(data['conflict_id']!, _conflictIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conflictIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('conflict_kind')) {
      context.handle(
        _conflictKindMeta,
        conflictKind.isAcceptableOrUnknown(
          data['conflict_kind']!,
          _conflictKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conflictKindMeta);
    }
    if (data.containsKey('local_payload')) {
      context.handle(
        _localPayloadMeta,
        localPayload.isAcceptableOrUnknown(
          data['local_payload']!,
          _localPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localPayloadMeta);
    }
    if (data.containsKey('remote_payload')) {
      context.handle(
        _remotePayloadMeta,
        remotePayload.isAcceptableOrUnknown(
          data['remote_payload']!,
          _remotePayloadMeta,
        ),
      );
    }
    if (data.containsKey('remote_revision')) {
      context.handle(
        _remoteRevisionMeta,
        remoteRevision.isAcceptableOrUnknown(
          data['remote_revision']!,
          _remoteRevisionMeta,
        ),
      );
    }
    if (data.containsKey('detected_at')) {
      context.handle(
        _detectedAtMeta,
        detectedAt.isAcceptableOrUnknown(data['detected_at']!, _detectedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_detectedAtMeta);
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conflictId};
  @override
  SyncConflictRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflictRecord(
      conflictId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      conflictKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_kind'],
      )!,
      localPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_payload'],
      )!,
      remotePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_payload'],
      ),
      remoteRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_revision'],
      ),
      detectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}detected_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
    );
  }

  @override
  $SyncConflictRecordsTable createAlias(String alias) {
    return $SyncConflictRecordsTable(attachedDatabase, alias);
  }
}

class SyncConflictRecord extends DataClass
    implements Insertable<SyncConflictRecord> {
  final String conflictId;
  final String operationId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String conflictKind;
  final String localPayload;
  final String? remotePayload;
  final int? remoteRevision;
  final DateTime detectedAt;
  final DateTime? resolvedAt;
  final String? resolution;
  const SyncConflictRecord({
    required this.conflictId,
    required this.operationId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.conflictKind,
    required this.localPayload,
    this.remotePayload,
    this.remoteRevision,
    required this.detectedAt,
    this.resolvedAt,
    this.resolution,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conflict_id'] = Variable<String>(conflictId);
    map['operation_id'] = Variable<String>(operationId);
    map['home_id'] = Variable<String>(homeId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['conflict_kind'] = Variable<String>(conflictKind);
    map['local_payload'] = Variable<String>(localPayload);
    if (!nullToAbsent || remotePayload != null) {
      map['remote_payload'] = Variable<String>(remotePayload);
    }
    if (!nullToAbsent || remoteRevision != null) {
      map['remote_revision'] = Variable<int>(remoteRevision);
    }
    map['detected_at'] = Variable<DateTime>(detectedAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    return map;
  }

  SyncConflictRecordsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictRecordsCompanion(
      conflictId: Value(conflictId),
      operationId: Value(operationId),
      homeId: Value(homeId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      conflictKind: Value(conflictKind),
      localPayload: Value(localPayload),
      remotePayload: remotePayload == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePayload),
      remoteRevision: remoteRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteRevision),
      detectedAt: Value(detectedAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
    );
  }

  factory SyncConflictRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflictRecord(
      conflictId: serializer.fromJson<String>(json['conflictId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      homeId: serializer.fromJson<String>(json['homeId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      conflictKind: serializer.fromJson<String>(json['conflictKind']),
      localPayload: serializer.fromJson<String>(json['localPayload']),
      remotePayload: serializer.fromJson<String?>(json['remotePayload']),
      remoteRevision: serializer.fromJson<int?>(json['remoteRevision']),
      detectedAt: serializer.fromJson<DateTime>(json['detectedAt']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      resolution: serializer.fromJson<String?>(json['resolution']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conflictId': serializer.toJson<String>(conflictId),
      'operationId': serializer.toJson<String>(operationId),
      'homeId': serializer.toJson<String>(homeId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'conflictKind': serializer.toJson<String>(conflictKind),
      'localPayload': serializer.toJson<String>(localPayload),
      'remotePayload': serializer.toJson<String?>(remotePayload),
      'remoteRevision': serializer.toJson<int?>(remoteRevision),
      'detectedAt': serializer.toJson<DateTime>(detectedAt),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'resolution': serializer.toJson<String?>(resolution),
    };
  }

  SyncConflictRecord copyWith({
    String? conflictId,
    String? operationId,
    String? homeId,
    String? entityType,
    String? entityId,
    String? conflictKind,
    String? localPayload,
    Value<String?> remotePayload = const Value.absent(),
    Value<int?> remoteRevision = const Value.absent(),
    DateTime? detectedAt,
    Value<DateTime?> resolvedAt = const Value.absent(),
    Value<String?> resolution = const Value.absent(),
  }) => SyncConflictRecord(
    conflictId: conflictId ?? this.conflictId,
    operationId: operationId ?? this.operationId,
    homeId: homeId ?? this.homeId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    conflictKind: conflictKind ?? this.conflictKind,
    localPayload: localPayload ?? this.localPayload,
    remotePayload: remotePayload.present
        ? remotePayload.value
        : this.remotePayload,
    remoteRevision: remoteRevision.present
        ? remoteRevision.value
        : this.remoteRevision,
    detectedAt: detectedAt ?? this.detectedAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    resolution: resolution.present ? resolution.value : this.resolution,
  );
  SyncConflictRecord copyWithCompanion(SyncConflictRecordsCompanion data) {
    return SyncConflictRecord(
      conflictId: data.conflictId.present
          ? data.conflictId.value
          : this.conflictId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      conflictKind: data.conflictKind.present
          ? data.conflictKind.value
          : this.conflictKind,
      localPayload: data.localPayload.present
          ? data.localPayload.value
          : this.localPayload,
      remotePayload: data.remotePayload.present
          ? data.remotePayload.value
          : this.remotePayload,
      remoteRevision: data.remoteRevision.present
          ? data.remoteRevision.value
          : this.remoteRevision,
      detectedAt: data.detectedAt.present
          ? data.detectedAt.value
          : this.detectedAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictRecord(')
          ..write('conflictId: $conflictId, ')
          ..write('operationId: $operationId, ')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('conflictKind: $conflictKind, ')
          ..write('localPayload: $localPayload, ')
          ..write('remotePayload: $remotePayload, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('resolution: $resolution')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conflictId,
    operationId,
    homeId,
    entityType,
    entityId,
    conflictKind,
    localPayload,
    remotePayload,
    remoteRevision,
    detectedAt,
    resolvedAt,
    resolution,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflictRecord &&
          other.conflictId == this.conflictId &&
          other.operationId == this.operationId &&
          other.homeId == this.homeId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.conflictKind == this.conflictKind &&
          other.localPayload == this.localPayload &&
          other.remotePayload == this.remotePayload &&
          other.remoteRevision == this.remoteRevision &&
          other.detectedAt == this.detectedAt &&
          other.resolvedAt == this.resolvedAt &&
          other.resolution == this.resolution);
}

class SyncConflictRecordsCompanion extends UpdateCompanion<SyncConflictRecord> {
  final Value<String> conflictId;
  final Value<String> operationId;
  final Value<String> homeId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> conflictKind;
  final Value<String> localPayload;
  final Value<String?> remotePayload;
  final Value<int?> remoteRevision;
  final Value<DateTime> detectedAt;
  final Value<DateTime?> resolvedAt;
  final Value<String?> resolution;
  final Value<int> rowid;
  const SyncConflictRecordsCompanion({
    this.conflictId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.homeId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.conflictKind = const Value.absent(),
    this.localPayload = const Value.absent(),
    this.remotePayload = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    this.detectedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.resolution = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictRecordsCompanion.insert({
    required String conflictId,
    required String operationId,
    required String homeId,
    required String entityType,
    required String entityId,
    required String conflictKind,
    required String localPayload,
    this.remotePayload = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    required DateTime detectedAt,
    this.resolvedAt = const Value.absent(),
    this.resolution = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conflictId = Value(conflictId),
       operationId = Value(operationId),
       homeId = Value(homeId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       conflictKind = Value(conflictKind),
       localPayload = Value(localPayload),
       detectedAt = Value(detectedAt);
  static Insertable<SyncConflictRecord> custom({
    Expression<String>? conflictId,
    Expression<String>? operationId,
    Expression<String>? homeId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? conflictKind,
    Expression<String>? localPayload,
    Expression<String>? remotePayload,
    Expression<int>? remoteRevision,
    Expression<DateTime>? detectedAt,
    Expression<DateTime>? resolvedAt,
    Expression<String>? resolution,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conflictId != null) 'conflict_id': conflictId,
      if (operationId != null) 'operation_id': operationId,
      if (homeId != null) 'home_id': homeId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (conflictKind != null) 'conflict_kind': conflictKind,
      if (localPayload != null) 'local_payload': localPayload,
      if (remotePayload != null) 'remote_payload': remotePayload,
      if (remoteRevision != null) 'remote_revision': remoteRevision,
      if (detectedAt != null) 'detected_at': detectedAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (resolution != null) 'resolution': resolution,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictRecordsCompanion copyWith({
    Value<String>? conflictId,
    Value<String>? operationId,
    Value<String>? homeId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? conflictKind,
    Value<String>? localPayload,
    Value<String?>? remotePayload,
    Value<int?>? remoteRevision,
    Value<DateTime>? detectedAt,
    Value<DateTime?>? resolvedAt,
    Value<String?>? resolution,
    Value<int>? rowid,
  }) {
    return SyncConflictRecordsCompanion(
      conflictId: conflictId ?? this.conflictId,
      operationId: operationId ?? this.operationId,
      homeId: homeId ?? this.homeId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      conflictKind: conflictKind ?? this.conflictKind,
      localPayload: localPayload ?? this.localPayload,
      remotePayload: remotePayload ?? this.remotePayload,
      remoteRevision: remoteRevision ?? this.remoteRevision,
      detectedAt: detectedAt ?? this.detectedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolution: resolution ?? this.resolution,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conflictId.present) {
      map['conflict_id'] = Variable<String>(conflictId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (conflictKind.present) {
      map['conflict_kind'] = Variable<String>(conflictKind.value);
    }
    if (localPayload.present) {
      map['local_payload'] = Variable<String>(localPayload.value);
    }
    if (remotePayload.present) {
      map['remote_payload'] = Variable<String>(remotePayload.value);
    }
    if (remoteRevision.present) {
      map['remote_revision'] = Variable<int>(remoteRevision.value);
    }
    if (detectedAt.present) {
      map['detected_at'] = Variable<DateTime>(detectedAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictRecordsCompanion(')
          ..write('conflictId: $conflictId, ')
          ..write('operationId: $operationId, ')
          ..write('homeId: $homeId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('conflictKind: $conflictKind, ')
          ..write('localPayload: $localPayload, ')
          ..write('remotePayload: $remotePayload, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('resolution: $resolution, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalRecordsTable localRecords = $LocalRecordsTable(this);
  late final $ClientOperationsTable clientOperations = $ClientOperationsTable(
    this,
  );
  late final $LocalSyncCursorsTable localSyncCursors = $LocalSyncCursorsTable(
    this,
  );
  late final $RecordTombstonesTable recordTombstones = $RecordTombstonesTable(
    this,
  );
  late final $LocalMediaMetadataTable localMediaMetadata =
      $LocalMediaMetadataTable(this);
  late final $SyncConflictRecordsTable syncConflictRecords =
      $SyncConflictRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localRecords,
    clientOperations,
    localSyncCursors,
    recordTombstones,
    localMediaMetadata,
    syncConflictRecords,
  ];
}

typedef $$LocalRecordsTableCreateCompanionBuilder =
    LocalRecordsCompanion Function({
      required String homeId,
      required String entityType,
      required String entityId,
      required String payload,
      Value<int> revision,
      Value<bool> isTombstone,
      required DateTime updatedAt,
      Value<DateTime?> synchronizedAt,
      Value<int> rowid,
    });
typedef $$LocalRecordsTableUpdateCompanionBuilder =
    LocalRecordsCompanion Function({
      Value<String> homeId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> payload,
      Value<int> revision,
      Value<bool> isTombstone,
      Value<DateTime> updatedAt,
      Value<DateTime?> synchronizedAt,
      Value<int> rowid,
    });

class $$LocalRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalRecordsTable> {
  $$LocalRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTombstone => $composableBuilder(
    column: $table.isTombstone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get synchronizedAt => $composableBuilder(
    column: $table.synchronizedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalRecordsTable> {
  $$LocalRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTombstone => $composableBuilder(
    column: $table.isTombstone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get synchronizedAt => $composableBuilder(
    column: $table.synchronizedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalRecordsTable> {
  $$LocalRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<bool> get isTombstone => $composableBuilder(
    column: $table.isTombstone,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get synchronizedAt => $composableBuilder(
    column: $table.synchronizedAt,
    builder: (column) => column,
  );
}

class $$LocalRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalRecordsTable,
          LocalRecord,
          $$LocalRecordsTableFilterComposer,
          $$LocalRecordsTableOrderingComposer,
          $$LocalRecordsTableAnnotationComposer,
          $$LocalRecordsTableCreateCompanionBuilder,
          $$LocalRecordsTableUpdateCompanionBuilder,
          (
            LocalRecord,
            BaseReferences<_$AppDatabase, $LocalRecordsTable, LocalRecord>,
          ),
          LocalRecord,
          PrefetchHooks Function()
        > {
  $$LocalRecordsTableTableManager(_$AppDatabase db, $LocalRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> homeId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<bool> isTombstone = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> synchronizedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordsCompanion(
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                payload: payload,
                revision: revision,
                isTombstone: isTombstone,
                updatedAt: updatedAt,
                synchronizedAt: synchronizedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String homeId,
                required String entityType,
                required String entityId,
                required String payload,
                Value<int> revision = const Value.absent(),
                Value<bool> isTombstone = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> synchronizedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRecordsCompanion.insert(
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                payload: payload,
                revision: revision,
                isTombstone: isTombstone,
                updatedAt: updatedAt,
                synchronizedAt: synchronizedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalRecordsTable,
      LocalRecord,
      $$LocalRecordsTableFilterComposer,
      $$LocalRecordsTableOrderingComposer,
      $$LocalRecordsTableAnnotationComposer,
      $$LocalRecordsTableCreateCompanionBuilder,
      $$LocalRecordsTableUpdateCompanionBuilder,
      (
        LocalRecord,
        BaseReferences<_$AppDatabase, $LocalRecordsTable, LocalRecord>,
      ),
      LocalRecord,
      PrefetchHooks Function()
    >;
typedef $$ClientOperationsTableCreateCompanionBuilder =
    ClientOperationsCompanion Function({
      required String operationId,
      required String deviceId,
      required String homeId,
      required String entityType,
      required String entityId,
      required String operationType,
      Value<int?> baseRevision,
      required DateTime clientTimestamp,
      Value<int> payloadSchemaVersion,
      required String payload,
      Value<int> retryCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastSafeError,
      required String state,
      Value<String?> serverCursor,
      Value<DateTime?> acknowledgedAt,
      Value<int> rowid,
    });
typedef $$ClientOperationsTableUpdateCompanionBuilder =
    ClientOperationsCompanion Function({
      Value<String> operationId,
      Value<String> deviceId,
      Value<String> homeId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operationType,
      Value<int?> baseRevision,
      Value<DateTime> clientTimestamp,
      Value<int> payloadSchemaVersion,
      Value<String> payload,
      Value<int> retryCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastSafeError,
      Value<String> state,
      Value<String?> serverCursor,
      Value<DateTime?> acknowledgedAt,
      Value<int> rowid,
    });

class $$ClientOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $ClientOperationsTable> {
  $$ClientOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSafeError => $composableBuilder(
    column: $table.lastSafeError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientOperationsTable> {
  $$ClientOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSafeError => $composableBuilder(
    column: $table.lastSafeError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientOperationsTable> {
  $$ClientOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSafeError => $composableBuilder(
    column: $table.lastSafeError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => column,
  );
}

class $$ClientOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientOperationsTable,
          ClientOperation,
          $$ClientOperationsTableFilterComposer,
          $$ClientOperationsTableOrderingComposer,
          $$ClientOperationsTableAnnotationComposer,
          $$ClientOperationsTableCreateCompanionBuilder,
          $$ClientOperationsTableUpdateCompanionBuilder,
          (
            ClientOperation,
            BaseReferences<
              _$AppDatabase,
              $ClientOperationsTable,
              ClientOperation
            >,
          ),
          ClientOperation,
          PrefetchHooks Function()
        > {
  $$ClientOperationsTableTableManager(
    _$AppDatabase db,
    $ClientOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<int?> baseRevision = const Value.absent(),
                Value<DateTime> clientTimestamp = const Value.absent(),
                Value<int> payloadSchemaVersion = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastSafeError = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> serverCursor = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientOperationsCompanion(
                operationId: operationId,
                deviceId: deviceId,
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                operationType: operationType,
                baseRevision: baseRevision,
                clientTimestamp: clientTimestamp,
                payloadSchemaVersion: payloadSchemaVersion,
                payload: payload,
                retryCount: retryCount,
                nextAttemptAt: nextAttemptAt,
                lastSafeError: lastSafeError,
                state: state,
                serverCursor: serverCursor,
                acknowledgedAt: acknowledgedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String deviceId,
                required String homeId,
                required String entityType,
                required String entityId,
                required String operationType,
                Value<int?> baseRevision = const Value.absent(),
                required DateTime clientTimestamp,
                Value<int> payloadSchemaVersion = const Value.absent(),
                required String payload,
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastSafeError = const Value.absent(),
                required String state,
                Value<String?> serverCursor = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClientOperationsCompanion.insert(
                operationId: operationId,
                deviceId: deviceId,
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                operationType: operationType,
                baseRevision: baseRevision,
                clientTimestamp: clientTimestamp,
                payloadSchemaVersion: payloadSchemaVersion,
                payload: payload,
                retryCount: retryCount,
                nextAttemptAt: nextAttemptAt,
                lastSafeError: lastSafeError,
                state: state,
                serverCursor: serverCursor,
                acknowledgedAt: acknowledgedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientOperationsTable,
      ClientOperation,
      $$ClientOperationsTableFilterComposer,
      $$ClientOperationsTableOrderingComposer,
      $$ClientOperationsTableAnnotationComposer,
      $$ClientOperationsTableCreateCompanionBuilder,
      $$ClientOperationsTableUpdateCompanionBuilder,
      (
        ClientOperation,
        BaseReferences<_$AppDatabase, $ClientOperationsTable, ClientOperation>,
      ),
      ClientOperation,
      PrefetchHooks Function()
    >;
typedef $$LocalSyncCursorsTableCreateCompanionBuilder =
    LocalSyncCursorsCompanion Function({
      required String homeId,
      Value<String> feed,
      Value<int> protocolVersion,
      Value<int> schemaGeneration,
      required String cursor,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalSyncCursorsTableUpdateCompanionBuilder =
    LocalSyncCursorsCompanion Function({
      Value<String> homeId,
      Value<String> feed,
      Value<int> protocolVersion,
      Value<int> schemaGeneration,
      Value<String> cursor,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalSyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feed => $composableBuilder(
    column: $table.feed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaGeneration => $composableBuilder(
    column: $table.schemaGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feed => $composableBuilder(
    column: $table.feed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaGeneration => $composableBuilder(
    column: $table.schemaGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get feed =>
      $composableBuilder(column: $table.feed, builder: (column) => column);

  GeneratedColumn<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaGeneration => $composableBuilder(
    column: $table.schemaGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalSyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSyncCursorsTable,
          LocalSyncCursor,
          $$LocalSyncCursorsTableFilterComposer,
          $$LocalSyncCursorsTableOrderingComposer,
          $$LocalSyncCursorsTableAnnotationComposer,
          $$LocalSyncCursorsTableCreateCompanionBuilder,
          $$LocalSyncCursorsTableUpdateCompanionBuilder,
          (
            LocalSyncCursor,
            BaseReferences<
              _$AppDatabase,
              $LocalSyncCursorsTable,
              LocalSyncCursor
            >,
          ),
          LocalSyncCursor,
          PrefetchHooks Function()
        > {
  $$LocalSyncCursorsTableTableManager(
    _$AppDatabase db,
    $LocalSyncCursorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> homeId = const Value.absent(),
                Value<String> feed = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<int> schemaGeneration = const Value.absent(),
                Value<String> cursor = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncCursorsCompanion(
                homeId: homeId,
                feed: feed,
                protocolVersion: protocolVersion,
                schemaGeneration: schemaGeneration,
                cursor: cursor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String homeId,
                Value<String> feed = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<int> schemaGeneration = const Value.absent(),
                required String cursor,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncCursorsCompanion.insert(
                homeId: homeId,
                feed: feed,
                protocolVersion: protocolVersion,
                schemaGeneration: schemaGeneration,
                cursor: cursor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSyncCursorsTable,
      LocalSyncCursor,
      $$LocalSyncCursorsTableFilterComposer,
      $$LocalSyncCursorsTableOrderingComposer,
      $$LocalSyncCursorsTableAnnotationComposer,
      $$LocalSyncCursorsTableCreateCompanionBuilder,
      $$LocalSyncCursorsTableUpdateCompanionBuilder,
      (
        LocalSyncCursor,
        BaseReferences<_$AppDatabase, $LocalSyncCursorsTable, LocalSyncCursor>,
      ),
      LocalSyncCursor,
      PrefetchHooks Function()
    >;
typedef $$RecordTombstonesTableCreateCompanionBuilder =
    RecordTombstonesCompanion Function({
      required String homeId,
      required String entityType,
      required String entityId,
      required int revision,
      required String cursor,
      required DateTime deletedAt,
      Value<int> rowid,
    });
typedef $$RecordTombstonesTableUpdateCompanionBuilder =
    RecordTombstonesCompanion Function({
      Value<String> homeId,
      Value<String> entityType,
      Value<String> entityId,
      Value<int> revision,
      Value<String> cursor,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });

class $$RecordTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $RecordTombstonesTable> {
  $$RecordTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecordTombstonesTable> {
  $$RecordTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecordTombstonesTable> {
  $$RecordTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$RecordTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecordTombstonesTable,
          RecordTombstone,
          $$RecordTombstonesTableFilterComposer,
          $$RecordTombstonesTableOrderingComposer,
          $$RecordTombstonesTableAnnotationComposer,
          $$RecordTombstonesTableCreateCompanionBuilder,
          $$RecordTombstonesTableUpdateCompanionBuilder,
          (
            RecordTombstone,
            BaseReferences<
              _$AppDatabase,
              $RecordTombstonesTable,
              RecordTombstone
            >,
          ),
          RecordTombstone,
          PrefetchHooks Function()
        > {
  $$RecordTombstonesTableTableManager(
    _$AppDatabase db,
    $RecordTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> homeId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> cursor = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordTombstonesCompanion(
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                revision: revision,
                cursor: cursor,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String homeId,
                required String entityType,
                required String entityId,
                required int revision,
                required String cursor,
                required DateTime deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecordTombstonesCompanion.insert(
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                revision: revision,
                cursor: cursor,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecordTombstonesTable,
      RecordTombstone,
      $$RecordTombstonesTableFilterComposer,
      $$RecordTombstonesTableOrderingComposer,
      $$RecordTombstonesTableAnnotationComposer,
      $$RecordTombstonesTableCreateCompanionBuilder,
      $$RecordTombstonesTableUpdateCompanionBuilder,
      (
        RecordTombstone,
        BaseReferences<_$AppDatabase, $RecordTombstonesTable, RecordTombstone>,
      ),
      RecordTombstone,
      PrefetchHooks Function()
    >;
typedef $$LocalMediaMetadataTableCreateCompanionBuilder =
    LocalMediaMetadataCompanion Function({
      required String mediaId,
      required String homeId,
      required String purpose,
      required String localReference,
      Value<String?> sha256,
      Value<String?> mimeType,
      Value<int?> byteLength,
      Value<String> uploadState,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$LocalMediaMetadataTableUpdateCompanionBuilder =
    LocalMediaMetadataCompanion Function({
      Value<String> mediaId,
      Value<String> homeId,
      Value<String> purpose,
      Value<String> localReference,
      Value<String?> sha256,
      Value<String?> mimeType,
      Value<int?> byteLength,
      Value<String> uploadState,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LocalMediaMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMediaMetadataTable> {
  $$LocalMediaMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localReference => $composableBuilder(
    column: $table.localReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMediaMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMediaMetadataTable> {
  $$LocalMediaMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localReference => $composableBuilder(
    column: $table.localReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMediaMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMediaMetadataTable> {
  $$LocalMediaMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<String> get localReference => $composableBuilder(
    column: $table.localReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalMediaMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMediaMetadataTable,
          LocalMediaMetadataData,
          $$LocalMediaMetadataTableFilterComposer,
          $$LocalMediaMetadataTableOrderingComposer,
          $$LocalMediaMetadataTableAnnotationComposer,
          $$LocalMediaMetadataTableCreateCompanionBuilder,
          $$LocalMediaMetadataTableUpdateCompanionBuilder,
          (
            LocalMediaMetadataData,
            BaseReferences<
              _$AppDatabase,
              $LocalMediaMetadataTable,
              LocalMediaMetadataData
            >,
          ),
          LocalMediaMetadataData,
          PrefetchHooks Function()
        > {
  $$LocalMediaMetadataTableTableManager(
    _$AppDatabase db,
    $LocalMediaMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMediaMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMediaMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMediaMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<String> localReference = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteLength = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMediaMetadataCompanion(
                mediaId: mediaId,
                homeId: homeId,
                purpose: purpose,
                localReference: localReference,
                sha256: sha256,
                mimeType: mimeType,
                byteLength: byteLength,
                uploadState: uploadState,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required String homeId,
                required String purpose,
                required String localReference,
                Value<String?> sha256 = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> byteLength = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalMediaMetadataCompanion.insert(
                mediaId: mediaId,
                homeId: homeId,
                purpose: purpose,
                localReference: localReference,
                sha256: sha256,
                mimeType: mimeType,
                byteLength: byteLength,
                uploadState: uploadState,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMediaMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMediaMetadataTable,
      LocalMediaMetadataData,
      $$LocalMediaMetadataTableFilterComposer,
      $$LocalMediaMetadataTableOrderingComposer,
      $$LocalMediaMetadataTableAnnotationComposer,
      $$LocalMediaMetadataTableCreateCompanionBuilder,
      $$LocalMediaMetadataTableUpdateCompanionBuilder,
      (
        LocalMediaMetadataData,
        BaseReferences<
          _$AppDatabase,
          $LocalMediaMetadataTable,
          LocalMediaMetadataData
        >,
      ),
      LocalMediaMetadataData,
      PrefetchHooks Function()
    >;
typedef $$SyncConflictRecordsTableCreateCompanionBuilder =
    SyncConflictRecordsCompanion Function({
      required String conflictId,
      required String operationId,
      required String homeId,
      required String entityType,
      required String entityId,
      required String conflictKind,
      required String localPayload,
      Value<String?> remotePayload,
      Value<int?> remoteRevision,
      required DateTime detectedAt,
      Value<DateTime?> resolvedAt,
      Value<String?> resolution,
      Value<int> rowid,
    });
typedef $$SyncConflictRecordsTableUpdateCompanionBuilder =
    SyncConflictRecordsCompanion Function({
      Value<String> conflictId,
      Value<String> operationId,
      Value<String> homeId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> conflictKind,
      Value<String> localPayload,
      Value<String?> remotePayload,
      Value<int?> remoteRevision,
      Value<DateTime> detectedAt,
      Value<DateTime?> resolvedAt,
      Value<String?> resolution,
      Value<int> rowid,
    });

class $$SyncConflictRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncConflictRecordsTable> {
  $$SyncConflictRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictKind => $composableBuilder(
    column: $table.conflictKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncConflictRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncConflictRecordsTable> {
  $$SyncConflictRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictKind => $composableBuilder(
    column: $table.conflictKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncConflictRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncConflictRecordsTable> {
  $$SyncConflictRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get conflictKind => $composableBuilder(
    column: $table.conflictKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );
}

class $$SyncConflictRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncConflictRecordsTable,
          SyncConflictRecord,
          $$SyncConflictRecordsTableFilterComposer,
          $$SyncConflictRecordsTableOrderingComposer,
          $$SyncConflictRecordsTableAnnotationComposer,
          $$SyncConflictRecordsTableCreateCompanionBuilder,
          $$SyncConflictRecordsTableUpdateCompanionBuilder,
          (
            SyncConflictRecord,
            BaseReferences<
              _$AppDatabase,
              $SyncConflictRecordsTable,
              SyncConflictRecord
            >,
          ),
          SyncConflictRecord,
          PrefetchHooks Function()
        > {
  $$SyncConflictRecordsTableTableManager(
    _$AppDatabase db,
    $SyncConflictRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncConflictRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncConflictRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SyncConflictRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> conflictId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> conflictKind = const Value.absent(),
                Value<String> localPayload = const Value.absent(),
                Value<String?> remotePayload = const Value.absent(),
                Value<int?> remoteRevision = const Value.absent(),
                Value<DateTime> detectedAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictRecordsCompanion(
                conflictId: conflictId,
                operationId: operationId,
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                conflictKind: conflictKind,
                localPayload: localPayload,
                remotePayload: remotePayload,
                remoteRevision: remoteRevision,
                detectedAt: detectedAt,
                resolvedAt: resolvedAt,
                resolution: resolution,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conflictId,
                required String operationId,
                required String homeId,
                required String entityType,
                required String entityId,
                required String conflictKind,
                required String localPayload,
                Value<String?> remotePayload = const Value.absent(),
                Value<int?> remoteRevision = const Value.absent(),
                required DateTime detectedAt,
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictRecordsCompanion.insert(
                conflictId: conflictId,
                operationId: operationId,
                homeId: homeId,
                entityType: entityType,
                entityId: entityId,
                conflictKind: conflictKind,
                localPayload: localPayload,
                remotePayload: remotePayload,
                remoteRevision: remoteRevision,
                detectedAt: detectedAt,
                resolvedAt: resolvedAt,
                resolution: resolution,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncConflictRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncConflictRecordsTable,
      SyncConflictRecord,
      $$SyncConflictRecordsTableFilterComposer,
      $$SyncConflictRecordsTableOrderingComposer,
      $$SyncConflictRecordsTableAnnotationComposer,
      $$SyncConflictRecordsTableCreateCompanionBuilder,
      $$SyncConflictRecordsTableUpdateCompanionBuilder,
      (
        SyncConflictRecord,
        BaseReferences<
          _$AppDatabase,
          $SyncConflictRecordsTable,
          SyncConflictRecord
        >,
      ),
      SyncConflictRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalRecordsTableTableManager get localRecords =>
      $$LocalRecordsTableTableManager(_db, _db.localRecords);
  $$ClientOperationsTableTableManager get clientOperations =>
      $$ClientOperationsTableTableManager(_db, _db.clientOperations);
  $$LocalSyncCursorsTableTableManager get localSyncCursors =>
      $$LocalSyncCursorsTableTableManager(_db, _db.localSyncCursors);
  $$RecordTombstonesTableTableManager get recordTombstones =>
      $$RecordTombstonesTableTableManager(_db, _db.recordTombstones);
  $$LocalMediaMetadataTableTableManager get localMediaMetadata =>
      $$LocalMediaMetadataTableTableManager(_db, _db.localMediaMetadata);
  $$SyncConflictRecordsTableTableManager get syncConflictRecords =>
      $$SyncConflictRecordsTableTableManager(_db, _db.syncConflictRecords);
}
