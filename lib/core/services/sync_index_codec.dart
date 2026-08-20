import 'dart:convert';

import '../models/sync_state.dart';

/// JSON codec for the encrypted, lightweight remote sync index payload.
class SyncIndexCodec {
  static const remotePath = 'meta/sync_index.json';
  static const dataType = 'sync_index';
  static const syncId = 'sync_index';

  String encode(SyncIndex index) => jsonEncode({
    'version': index.version,
    'generation': index.generation,
    if (index.updatedAt != null)
      'updatedAt': index.updatedAt!.toUtc().toIso8601String(),
    'entries': index.entries.map((key, value) => MapEntry(key, value.toJson())),
    'deleted': index.deleted.map((record) => record.toJson()).toList(),
  });

  SyncIndex decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Sync index must be a JSON object');
    }
    final json = Map<String, dynamic>.from(decoded);
    final rawEntries = _optionalMap(json, 'entries');
    final rawDeleted = _optionalList(json, 'deleted');
    final version = json['version'];
    if (version != null && version is! int) {
      throw const FormatException('Sync index version must be an integer');
    }
    final generation = json['generation'];
    if (generation != null && generation is! String) {
      throw const FormatException('Sync index generation must be a string');
    }
    final rawUpdatedAt = json['updatedAt'];
    return SyncIndex(
      version: version as int? ?? SyncIndex.currentVersion,
      generation: generation as String? ?? '',
      updatedAt: rawUpdatedAt == null
          ? null
          : _parseDateTime(rawUpdatedAt, 'updatedAt'),
      entries: rawEntries.map(
        (key, entry) => MapEntry(
          _requiredKey(key),
          SyncIndexEntry.fromJson(_nestedMap(entry, 'entries.$key')),
        ),
      ),
      deleted: rawDeleted
          .map(
            (entry) =>
                DeletedSyncRecord.fromJson(_nestedMap(entry, 'deleted entry')),
          )
          .toList(),
    );
  }

  Map<String, dynamic> _optionalMap(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const {};
    if (value is! Map) {
      throw FormatException('Sync index field "$key" must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  List<dynamic> _optionalList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) {
      throw FormatException('Sync index field "$key" must be an array');
    }
    return value;
  }

  Map<String, dynamic> _nestedMap(Object? value, String path) {
    if (value is! Map) {
      throw FormatException('Sync index field "$path" must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  DateTime _parseDateTime(Object? value, String key) {
    if (value is! String) {
      throw FormatException(
        'Sync index field "$key" must be an ISO date string',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException(
        'Sync index field "$key" must be an ISO date string',
      );
    }
    return parsed.toUtc();
  }

  String _requiredKey(String key) {
    if (key.trim().isEmpty) {
      throw const FormatException('Sync index contains an empty file ID');
    }
    return key;
  }
}
