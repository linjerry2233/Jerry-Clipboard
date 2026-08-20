class SyncStateEntry {
  final String digest;
  final DateTime syncedAt;

  const SyncStateEntry({required this.digest, required this.syncedAt});

  Map<String, dynamic> toJson() => {
    'digest': digest,
    'syncedAt': syncedAt.toUtc().toIso8601String(),
  };

  factory SyncStateEntry.fromJson(Map<String, dynamic> json) {
    final digest = _requiredString(json, 'digest');
    final syncedAt = _requiredDateTime(json, 'syncedAt');
    return SyncStateEntry(digest: digest, syncedAt: syncedAt.toUtc());
  }
}

class DeletedSyncRecord {
  final String dataType;
  final String fileName;
  final DateTime deletedAt;
  final String source;
  final DateTime? uploadedAt;

  const DeletedSyncRecord({
    required this.dataType,
    required this.fileName,
    required this.deletedAt,
    required this.source,
    this.uploadedAt,
  });

  DeletedSyncRecord copyWith({DateTime? uploadedAt}) => DeletedSyncRecord(
    dataType: dataType,
    fileName: fileName,
    deletedAt: deletedAt,
    source: source,
    uploadedAt: uploadedAt ?? this.uploadedAt,
  );

  Map<String, dynamic> toJson() => {
    'dataType': dataType,
    'fileName': fileName,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
    'source': source,
    'uploadedAt': uploadedAt?.toUtc().toIso8601String(),
  };

  factory DeletedSyncRecord.fromJson(Map<String, dynamic> json) {
    final fileName = _requiredString(json, 'fileName');
    final deletedAt = _requiredDateTime(json, 'deletedAt');
    final dataType = (json['dataType'] as String?)?.trim().isNotEmpty == true
        ? (json['dataType'] as String).trim()
        : _dataTypeFromFileName(fileName);
    if (dataType.isEmpty) {
      throw const FormatException(
        'Deleted sync record has an invalid dataType',
      );
    }
    final source = (json['source'] as String?)?.trim().isNotEmpty == true
        ? (json['source'] as String).trim()
        : 'remote';
    final rawUploadedAt = json['uploadedAt'];
    final uploadedAt = rawUploadedAt == null
        ? null
        : _parseDateTime(rawUploadedAt, 'uploadedAt');
    return DeletedSyncRecord(
      dataType: dataType,
      fileName: fileName,
      deletedAt: deletedAt.toUtc(),
      source: source,
      uploadedAt: uploadedAt?.toUtc(),
    );
  }

  static String _dataTypeFromFileName(String fileName) {
    final slash = fileName.indexOf('/');
    return slash > 0 ? fileName.substring(0, slash) : '';
  }
}

class SyncState {
  static const currentVersion = 1;

  final int version;
  final Map<String, SyncStateEntry> entries;
  final List<DeletedSyncRecord> deleted;

  SyncState({
    this.version = currentVersion,
    Map<String, SyncStateEntry> entries = const {},
    List<DeletedSyncRecord> deleted = const [],
  }) : entries = Map.unmodifiable(entries),
       deleted = List.unmodifiable(deleted);

  factory SyncState.empty() => SyncState();

  SyncState copyWith({
    int? version,
    Map<String, SyncStateEntry>? entries,
    List<DeletedSyncRecord>? deleted,
  }) => SyncState(
    version: version ?? this.version,
    entries: entries ?? this.entries,
    deleted: deleted ?? this.deleted,
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'entries': entries.map((key, value) => MapEntry(key, value.toJson())),
    'deleted': deleted.map((record) => record.toJson()).toList(),
  };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final rawEntries = _optionalMap(json, 'entries');
    final rawDeleted = _optionalList(json, 'deleted');
    final version = json['version'];
    if (version != null && version is! int) {
      throw const FormatException('Sync state version must be an integer');
    }
    return SyncState(
      version: version as int? ?? currentVersion,
      entries: rawEntries.map(
        (key, value) => MapEntry(
          _requiredKey(key, 'entries'),
          SyncStateEntry.fromJson(_nestedMap(value, 'entries.$key')),
        ),
      ),
      deleted: rawDeleted
          .map(
            (value) =>
                DeletedSyncRecord.fromJson(_nestedMap(value, 'deleted entry')),
          )
          .toList(),
    );
  }
}

class SyncIndexEntry {
  final String digest;
  final DateTime? updatedAt;

  const SyncIndexEntry({required this.digest, this.updatedAt});

  Map<String, dynamic> toJson() => {
    'digest': digest,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  factory SyncIndexEntry.fromJson(Map<String, dynamic> json) {
    final rawUpdatedAt = json['updatedAt'];
    return SyncIndexEntry(
      digest: _requiredString(json, 'digest'),
      updatedAt: rawUpdatedAt == null
          ? null
          : _parseDateTime(rawUpdatedAt, 'updatedAt'),
    );
  }
}

class SyncIndex {
  static const currentVersion = 1;

  final int version;
  final String generation;
  final DateTime? updatedAt;
  final Map<String, SyncIndexEntry> entries;
  final List<DeletedSyncRecord> deleted;

  SyncIndex({
    this.version = currentVersion,
    this.generation = '',
    this.updatedAt,
    Map<String, SyncIndexEntry> entries = const {},
    List<DeletedSyncRecord> deleted = const [],
  }) : entries = Map.unmodifiable(entries),
       deleted = List.unmodifiable(deleted);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Sync JSON field "$key" must be a non-empty string');
  }
  return value.trim();
}

String _requiredKey(String key, String path) {
  if (key.trim().isEmpty) {
    throw FormatException('Sync JSON field "$path" contains an empty ID');
  }
  return key;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  return _parseDateTime(value, key);
}

DateTime _parseDateTime(Object? value, String key) {
  if (value is! String) {
    throw FormatException('Sync JSON field "$key" must be an ISO date string');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Sync JSON field "$key" must be an ISO date string');
  }
  return parsed.toUtc();
}

Map<String, dynamic> _optionalMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  if (value is! Map) {
    throw FormatException('Sync JSON field "$key" must be an object');
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> _optionalList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('Sync JSON field "$key" must be an array');
  }
  return value;
}

Map<String, dynamic> _nestedMap(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('Sync JSON field "$path" must be an object');
  }
  return Map<String, dynamic>.from(value);
}
