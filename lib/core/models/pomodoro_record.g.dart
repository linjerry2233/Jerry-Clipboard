// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pomodoro_record.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPomodoroRecordCollection on Isar {
  IsarCollection<PomodoroRecord> get pomodoroRecords => this.collection();
}

const PomodoroRecordSchema = CollectionSchema(
  name: r'PomodoroRecord',
  id: -7024295366118405735,
  properties: {
    r'durationMinutes': PropertySchema(
      id: 0,
      name: r'durationMinutes',
      type: IsarType.long,
    ),
    r'endedAt': PropertySchema(
      id: 1,
      name: r'endedAt',
      type: IsarType.dateTime,
    ),
    r'isCompleted': PropertySchema(
      id: 2,
      name: r'isCompleted',
      type: IsarType.bool,
    ),
    r'startedAt': PropertySchema(
      id: 3,
      name: r'startedAt',
      type: IsarType.dateTime,
    ),
    r'syncId': PropertySchema(
      id: 4,
      name: r'syncId',
      type: IsarType.string,
    ),
    r'todoId': PropertySchema(
      id: 5,
      name: r'todoId',
      type: IsarType.long,
    ),
    r'todoSyncId': PropertySchema(
      id: 6,
      name: r'todoSyncId',
      type: IsarType.string,
    ),
    r'todoTitle': PropertySchema(
      id: 7,
      name: r'todoTitle',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 8,
      name: r'type',
      type: IsarType.string,
      enumMap: _PomodoroRecordtypeEnumValueMap,
    )
  },
  estimateSize: _pomodoroRecordEstimateSize,
  serialize: _pomodoroRecordSerialize,
  deserialize: _pomodoroRecordDeserialize,
  deserializeProp: _pomodoroRecordDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _pomodoroRecordGetId,
  getLinks: _pomodoroRecordGetLinks,
  attach: _pomodoroRecordAttach,
  version: '3.1.0+1',
);

int _pomodoroRecordEstimateSize(
  PomodoroRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.syncId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.todoSyncId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.todoTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.type.name.length * 3;
  return bytesCount;
}

void _pomodoroRecordSerialize(
  PomodoroRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.durationMinutes);
  writer.writeDateTime(offsets[1], object.endedAt);
  writer.writeBool(offsets[2], object.isCompleted);
  writer.writeDateTime(offsets[3], object.startedAt);
  writer.writeString(offsets[4], object.syncId);
  writer.writeLong(offsets[5], object.todoId);
  writer.writeString(offsets[6], object.todoSyncId);
  writer.writeString(offsets[7], object.todoTitle);
  writer.writeString(offsets[8], object.type.name);
}

PomodoroRecord _pomodoroRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PomodoroRecord();
  object.durationMinutes = reader.readLong(offsets[0]);
  object.endedAt = reader.readDateTimeOrNull(offsets[1]);
  object.id = id;
  object.isCompleted = reader.readBool(offsets[2]);
  object.startedAt = reader.readDateTime(offsets[3]);
  object.syncId = reader.readStringOrNull(offsets[4]);
  object.todoId = reader.readLongOrNull(offsets[5]);
  object.todoSyncId = reader.readStringOrNull(offsets[6]);
  object.todoTitle = reader.readStringOrNull(offsets[7]);
  object.type =
      _PomodoroRecordtypeValueEnumMap[reader.readStringOrNull(offsets[8])] ??
          SessionType.work;
  return object;
}

P _pomodoroRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (_PomodoroRecordtypeValueEnumMap[
              reader.readStringOrNull(offset)] ??
          SessionType.work) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _PomodoroRecordtypeEnumValueMap = {
  r'work': r'work',
  r'shortBreak': r'shortBreak',
  r'longBreak': r'longBreak',
};
const _PomodoroRecordtypeValueEnumMap = {
  r'work': SessionType.work,
  r'shortBreak': SessionType.shortBreak,
  r'longBreak': SessionType.longBreak,
};

Id _pomodoroRecordGetId(PomodoroRecord object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _pomodoroRecordGetLinks(PomodoroRecord object) {
  return [];
}

void _pomodoroRecordAttach(
    IsarCollection<dynamic> col, Id id, PomodoroRecord object) {
  object.id = id;
}

extension PomodoroRecordQueryWhereSort
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QWhere> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension PomodoroRecordQueryWhere
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QWhereClause> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension PomodoroRecordQueryFilter
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QFilterCondition> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      durationMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'durationMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      durationMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'durationMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      durationMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'durationMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      durationMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'durationMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'endedAt',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'endedAt',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      endedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      isCompletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isCompleted',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      startedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      startedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      startedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      startedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'syncId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'syncId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncId',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      syncIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncId',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'todoId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'todoId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'todoId',
        value: value,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'todoId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'todoSyncId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'todoSyncId',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'todoSyncId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'todoSyncId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'todoSyncId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoSyncId',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoSyncIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'todoSyncId',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'todoTitle',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'todoTitle',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'todoTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'todoTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'todoTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'todoTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      todoTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'todoTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeEqualTo(
    SessionType value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeGreaterThan(
    SessionType value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeLessThan(
    SessionType value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeBetween(
    SessionType lower,
    SessionType upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'type',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterFilterCondition>
      typeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'type',
        value: '',
      ));
    });
  }
}

extension PomodoroRecordQueryObject
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QFilterCondition> {}

extension PomodoroRecordQueryLinks
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QFilterCondition> {}

extension PomodoroRecordQuerySortBy
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QSortBy> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByDurationMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMinutes', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByDurationMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMinutes', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByEndedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endedAt', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByEndedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endedAt', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByIsCompletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByStartedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startedAt', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByStartedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startedAt', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortBySyncId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortBySyncIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByTodoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByTodoSyncId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoSyncId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByTodoSyncIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoSyncId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByTodoTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoTitle', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      sortByTodoTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoTitle', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension PomodoroRecordQuerySortThenBy
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QSortThenBy> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByDurationMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMinutes', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByDurationMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMinutes', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByEndedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endedAt', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByEndedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endedAt', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByIsCompletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByStartedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startedAt', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByStartedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startedAt', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenBySyncId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenBySyncIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByTodoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByTodoSyncId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoSyncId', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByTodoSyncIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoSyncId', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByTodoTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoTitle', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy>
      thenByTodoTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'todoTitle', Sort.desc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension PomodoroRecordQueryWhereDistinct
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> {
  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct>
      distinctByDurationMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'durationMinutes');
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctByEndedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endedAt');
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct>
      distinctByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isCompleted');
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct>
      distinctByStartedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startedAt');
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctBySyncId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctByTodoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'todoId');
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctByTodoSyncId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'todoSyncId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctByTodoTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'todoTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PomodoroRecord, PomodoroRecord, QDistinct> distinctByType(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type', caseSensitive: caseSensitive);
    });
  }
}

extension PomodoroRecordQueryProperty
    on QueryBuilder<PomodoroRecord, PomodoroRecord, QQueryProperty> {
  QueryBuilder<PomodoroRecord, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PomodoroRecord, int, QQueryOperations>
      durationMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'durationMinutes');
    });
  }

  QueryBuilder<PomodoroRecord, DateTime?, QQueryOperations> endedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endedAt');
    });
  }

  QueryBuilder<PomodoroRecord, bool, QQueryOperations> isCompletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isCompleted');
    });
  }

  QueryBuilder<PomodoroRecord, DateTime, QQueryOperations> startedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startedAt');
    });
  }

  QueryBuilder<PomodoroRecord, String?, QQueryOperations> syncIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncId');
    });
  }

  QueryBuilder<PomodoroRecord, int?, QQueryOperations> todoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'todoId');
    });
  }

  QueryBuilder<PomodoroRecord, String?, QQueryOperations> todoSyncIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'todoSyncId');
    });
  }

  QueryBuilder<PomodoroRecord, String?, QQueryOperations> todoTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'todoTitle');
    });
  }

  QueryBuilder<PomodoroRecord, SessionType, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }
}
