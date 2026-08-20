// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetAppSettingsCollection on Isar {
  IsarCollection<AppSettings> get appSettings => this.collection();
}

const AppSettingsSchema = CollectionSchema(
  name: r'AppSettings',
  id: -5633561779022347008,
  properties: {
    r'autoCleanup': PropertySchema(
      id: 0,
      name: r'autoCleanup',
      type: IsarType.bool,
    ),
    r'cleanupDays': PropertySchema(
      id: 1,
      name: r'cleanupDays',
      type: IsarType.long,
    ),
    r'clipboardCapturedTotal': PropertySchema(
      id: 2,
      name: r'clipboardCapturedTotal',
      type: IsarType.long,
    ),
    r'clipboardDailyCountsJson': PropertySchema(
      id: 3,
      name: r'clipboardDailyCountsJson',
      type: IsarType.string,
    ),
    r'clipboardHourlyCountsJson': PropertySchema(
      id: 4,
      name: r'clipboardHourlyCountsJson',
      type: IsarType.string,
    ),
    r'clipboardSourceCountsJson': PropertySchema(
      id: 5,
      name: r'clipboardSourceCountsJson',
      type: IsarType.string,
    ),
    r'clipboardStatsInitialized': PropertySchema(
      id: 6,
      name: r'clipboardStatsInitialized',
      type: IsarType.bool,
    ),
    r'closeToTray': PropertySchema(
      id: 7,
      name: r'closeToTray',
      type: IsarType.bool,
    ),
    r'darkMode': PropertySchema(
      id: 8,
      name: r'darkMode',
      type: IsarType.bool,
    ),
    r'defaultPomodoroBreakMinutes': PropertySchema(
      id: 9,
      name: r'defaultPomodoroBreakMinutes',
      type: IsarType.long,
    ),
    r'defaultPomodoroLongBreakMinutes': PropertySchema(
      id: 10,
      name: r'defaultPomodoroLongBreakMinutes',
      type: IsarType.long,
    ),
    r'defaultPomodoroWorkMinutes': PropertySchema(
      id: 11,
      name: r'defaultPomodoroWorkMinutes',
      type: IsarType.long,
    ),
    r'hotkeyShowWindow': PropertySchema(
      id: 12,
      name: r'hotkeyShowWindow',
      type: IsarType.string,
    ),
    r'launchAtStartup': PropertySchema(
      id: 13,
      name: r'launchAtStartup',
      type: IsarType.bool,
    ),
    r'maxHistoryItems': PropertySchema(
      id: 14,
      name: r'maxHistoryItems',
      type: IsarType.long,
    ),
    r'minimizeToTray': PropertySchema(
      id: 15,
      name: r'minimizeToTray',
      type: IsarType.bool,
    ),
    r'ntpClockOffsetMs': PropertySchema(
      id: 16,
      name: r'ntpClockOffsetMs',
      type: IsarType.long,
    ),
    r'ntpCustomServersJson': PropertySchema(
      id: 17,
      name: r'ntpCustomServersJson',
      type: IsarType.string,
    ),
    r'ntpLastSyncAt': PropertySchema(
      id: 18,
      name: r'ntpLastSyncAt',
      type: IsarType.dateTime,
    ),
    r'ntpServer': PropertySchema(
      id: 19,
      name: r'ntpServer',
      type: IsarType.string,
    ),
    r'ntpSyncIntervalMinutes': PropertySchema(
      id: 20,
      name: r'ntpSyncIntervalMinutes',
      type: IsarType.long,
    ),
    r'pomodoroAutoStartBreaks': PropertySchema(
      id: 21,
      name: r'pomodoroAutoStartBreaks',
      type: IsarType.bool,
    ),
    r'pomodoroLongBreakInterval': PropertySchema(
      id: 22,
      name: r'pomodoroLongBreakInterval',
      type: IsarType.long,
    ),
    r'showInTaskbar': PropertySchema(
      id: 23,
      name: r'showInTaskbar',
      type: IsarType.bool,
    ),
    r'themeModePreference': PropertySchema(
      id: 24,
      name: r'themeModePreference',
      type: IsarType.string,
    ),
    r'windowHeight': PropertySchema(
      id: 25,
      name: r'windowHeight',
      type: IsarType.double,
    ),
    r'windowOpacity': PropertySchema(
      id: 26,
      name: r'windowOpacity',
      type: IsarType.double,
    ),
    r'windowWidth': PropertySchema(
      id: 27,
      name: r'windowWidth',
      type: IsarType.double,
    )
  },
  estimateSize: _appSettingsEstimateSize,
  serialize: _appSettingsSerialize,
  deserialize: _appSettingsDeserialize,
  deserializeProp: _appSettingsDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _appSettingsGetId,
  getLinks: _appSettingsGetLinks,
  attach: _appSettingsAttach,
  version: '3.1.0+1',
);

int _appSettingsEstimateSize(
  AppSettings object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.clipboardDailyCountsJson.length * 3;
  bytesCount += 3 + object.clipboardHourlyCountsJson.length * 3;
  bytesCount += 3 + object.clipboardSourceCountsJson.length * 3;
  bytesCount += 3 + object.hotkeyShowWindow.length * 3;
  bytesCount += 3 + object.ntpCustomServersJson.length * 3;
  bytesCount += 3 + object.ntpServer.length * 3;
  {
    final value = object.themeModePreference;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _appSettingsSerialize(
  AppSettings object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.autoCleanup);
  writer.writeLong(offsets[1], object.cleanupDays);
  writer.writeLong(offsets[2], object.clipboardCapturedTotal);
  writer.writeString(offsets[3], object.clipboardDailyCountsJson);
  writer.writeString(offsets[4], object.clipboardHourlyCountsJson);
  writer.writeString(offsets[5], object.clipboardSourceCountsJson);
  writer.writeBool(offsets[6], object.clipboardStatsInitialized);
  writer.writeBool(offsets[7], object.closeToTray);
  writer.writeBool(offsets[8], object.darkMode);
  writer.writeLong(offsets[9], object.defaultPomodoroBreakMinutes);
  writer.writeLong(offsets[10], object.defaultPomodoroLongBreakMinutes);
  writer.writeLong(offsets[11], object.defaultPomodoroWorkMinutes);
  writer.writeString(offsets[12], object.hotkeyShowWindow);
  writer.writeBool(offsets[13], object.launchAtStartup);
  writer.writeLong(offsets[14], object.maxHistoryItems);
  writer.writeBool(offsets[15], object.minimizeToTray);
  writer.writeLong(offsets[16], object.ntpClockOffsetMs);
  writer.writeString(offsets[17], object.ntpCustomServersJson);
  writer.writeDateTime(offsets[18], object.ntpLastSyncAt);
  writer.writeString(offsets[19], object.ntpServer);
  writer.writeLong(offsets[20], object.ntpSyncIntervalMinutes);
  writer.writeBool(offsets[21], object.pomodoroAutoStartBreaks);
  writer.writeLong(offsets[22], object.pomodoroLongBreakInterval);
  writer.writeBool(offsets[23], object.showInTaskbar);
  writer.writeString(offsets[24], object.themeModePreference);
  writer.writeDouble(offsets[25], object.windowHeight);
  writer.writeDouble(offsets[26], object.windowOpacity);
  writer.writeDouble(offsets[27], object.windowWidth);
}

AppSettings _appSettingsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = AppSettings();
  object.autoCleanup = reader.readBool(offsets[0]);
  object.cleanupDays = reader.readLong(offsets[1]);
  object.clipboardCapturedTotal = reader.readLong(offsets[2]);
  object.clipboardDailyCountsJson = reader.readString(offsets[3]);
  object.clipboardHourlyCountsJson = reader.readString(offsets[4]);
  object.clipboardSourceCountsJson = reader.readString(offsets[5]);
  object.clipboardStatsInitialized = reader.readBool(offsets[6]);
  object.closeToTray = reader.readBool(offsets[7]);
  object.darkMode = reader.readBool(offsets[8]);
  object.defaultPomodoroBreakMinutes = reader.readLong(offsets[9]);
  object.defaultPomodoroLongBreakMinutes = reader.readLong(offsets[10]);
  object.defaultPomodoroWorkMinutes = reader.readLong(offsets[11]);
  object.hotkeyShowWindow = reader.readString(offsets[12]);
  object.id = id;
  object.launchAtStartup = reader.readBool(offsets[13]);
  object.maxHistoryItems = reader.readLong(offsets[14]);
  object.minimizeToTray = reader.readBool(offsets[15]);
  object.ntpClockOffsetMs = reader.readLong(offsets[16]);
  object.ntpCustomServersJson = reader.readString(offsets[17]);
  object.ntpLastSyncAt = reader.readDateTimeOrNull(offsets[18]);
  object.ntpServer = reader.readString(offsets[19]);
  object.ntpSyncIntervalMinutes = reader.readLong(offsets[20]);
  object.pomodoroAutoStartBreaks = reader.readBool(offsets[21]);
  object.pomodoroLongBreakInterval = reader.readLong(offsets[22]);
  object.showInTaskbar = reader.readBool(offsets[23]);
  object.themeModePreference = reader.readStringOrNull(offsets[24]);
  object.windowHeight = reader.readDouble(offsets[25]);
  object.windowOpacity = reader.readDouble(offsets[26]);
  object.windowWidth = reader.readDouble(offsets[27]);
  return object;
}

P _appSettingsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readBool(offset)) as P;
    case 9:
      return (reader.readLong(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readBool(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readBool(offset)) as P;
    case 16:
      return (reader.readLong(offset)) as P;
    case 17:
      return (reader.readString(offset)) as P;
    case 18:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 19:
      return (reader.readString(offset)) as P;
    case 20:
      return (reader.readLong(offset)) as P;
    case 21:
      return (reader.readBool(offset)) as P;
    case 22:
      return (reader.readLong(offset)) as P;
    case 23:
      return (reader.readBool(offset)) as P;
    case 24:
      return (reader.readStringOrNull(offset)) as P;
    case 25:
      return (reader.readDouble(offset)) as P;
    case 26:
      return (reader.readDouble(offset)) as P;
    case 27:
      return (reader.readDouble(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _appSettingsGetId(AppSettings object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _appSettingsGetLinks(AppSettings object) {
  return [];
}

void _appSettingsAttach(
    IsarCollection<dynamic> col, Id id, AppSettings object) {
  object.id = id;
}

extension AppSettingsQueryWhereSort
    on QueryBuilder<AppSettings, AppSettings, QWhere> {
  QueryBuilder<AppSettings, AppSettings, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension AppSettingsQueryWhere
    on QueryBuilder<AppSettings, AppSettings, QWhereClause> {
  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idBetween(
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

extension AppSettingsQueryFilter
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {
  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      autoCleanupEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'autoCleanup',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      cleanupDaysEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cleanupDays',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      cleanupDaysGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cleanupDays',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      cleanupDaysLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cleanupDays',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      cleanupDaysBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cleanupDays',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardCapturedTotalEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardCapturedTotal',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardCapturedTotalGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'clipboardCapturedTotal',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardCapturedTotalLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'clipboardCapturedTotal',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardCapturedTotalBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'clipboardCapturedTotal',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'clipboardDailyCountsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'clipboardDailyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'clipboardDailyCountsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardDailyCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardDailyCountsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'clipboardDailyCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'clipboardHourlyCountsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'clipboardHourlyCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'clipboardHourlyCountsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardHourlyCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardHourlyCountsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'clipboardHourlyCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'clipboardSourceCountsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'clipboardSourceCountsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'clipboardSourceCountsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardSourceCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardSourceCountsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'clipboardSourceCountsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      clipboardStatsInitializedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clipboardStatsInitialized',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      closeToTrayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'closeToTray',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> darkModeEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'darkMode',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroBreakMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPomodoroBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroBreakMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPomodoroBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroBreakMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPomodoroBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroBreakMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPomodoroBreakMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroLongBreakMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPomodoroLongBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroLongBreakMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPomodoroLongBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroLongBreakMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPomodoroLongBreakMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroLongBreakMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPomodoroLongBreakMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroWorkMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPomodoroWorkMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroWorkMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPomodoroWorkMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroWorkMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPomodoroWorkMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      defaultPomodoroWorkMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPomodoroWorkMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hotkeyShowWindow',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hotkeyShowWindow',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hotkeyShowWindow',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hotkeyShowWindow',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      hotkeyShowWindowIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hotkeyShowWindow',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idBetween(
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

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      launchAtStartupEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'launchAtStartup',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      maxHistoryItemsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'maxHistoryItems',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      maxHistoryItemsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'maxHistoryItems',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      maxHistoryItemsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'maxHistoryItems',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      maxHistoryItemsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'maxHistoryItems',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      minimizeToTrayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'minimizeToTray',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpClockOffsetMsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpClockOffsetMs',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpClockOffsetMsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ntpClockOffsetMs',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpClockOffsetMsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ntpClockOffsetMs',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpClockOffsetMsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ntpClockOffsetMs',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ntpCustomServersJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ntpCustomServersJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ntpCustomServersJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpCustomServersJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpCustomServersJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ntpCustomServersJson',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ntpLastSyncAt',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ntpLastSyncAt',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpLastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ntpLastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ntpLastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpLastSyncAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ntpLastSyncAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ntpServer',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ntpServer',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ntpServer',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpServer',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpServerIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ntpServer',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpSyncIntervalMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ntpSyncIntervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpSyncIntervalMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ntpSyncIntervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpSyncIntervalMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ntpSyncIntervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      ntpSyncIntervalMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ntpSyncIntervalMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      pomodoroAutoStartBreaksEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pomodoroAutoStartBreaks',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      pomodoroLongBreakIntervalEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pomodoroLongBreakInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      pomodoroLongBreakIntervalGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pomodoroLongBreakInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      pomodoroLongBreakIntervalLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pomodoroLongBreakInterval',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      pomodoroLongBreakIntervalBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pomodoroLongBreakInterval',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      showInTaskbarEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'showInTaskbar',
        value: value,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'themeModePreference',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'themeModePreference',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'themeModePreference',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'themeModePreference',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'themeModePreference',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'themeModePreference',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      themeModePreferenceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'themeModePreference',
        value: '',
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowHeightEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'windowHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowHeightGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'windowHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowHeightLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'windowHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowHeightBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'windowHeight',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowOpacityEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'windowOpacity',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowOpacityGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'windowOpacity',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowOpacityLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'windowOpacity',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowOpacityBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'windowOpacity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowWidthEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'windowWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowWidthGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'windowWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowWidthLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'windowWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
      windowWidthBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'windowWidth',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension AppSettingsQueryObject
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {}

extension AppSettingsQueryLinks
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {}

extension AppSettingsQuerySortBy
    on QueryBuilder<AppSettings, AppSettings, QSortBy> {
  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByAutoCleanup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoCleanup', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByAutoCleanupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoCleanup', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCleanupDays() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupDays', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCleanupDaysDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupDays', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardCapturedTotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardCapturedTotal', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardCapturedTotalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardCapturedTotal', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardDailyCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardDailyCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardDailyCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardDailyCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardHourlyCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardHourlyCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardHourlyCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardHourlyCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardSourceCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardSourceCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardSourceCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardSourceCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardStatsInitialized() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardStatsInitialized', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByClipboardStatsInitializedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardStatsInitialized', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCloseToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'closeToTray', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCloseToTrayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'closeToTray', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByDarkMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'darkMode', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByDarkModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'darkMode', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroBreakMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroBreakMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroBreakMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroLongBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroLongBreakMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroLongBreakMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroLongBreakMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroWorkMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroWorkMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByDefaultPomodoroWorkMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroWorkMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByHotkeyShowWindow() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyShowWindow', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByHotkeyShowWindowDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyShowWindow', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByLaunchAtStartupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByMaxHistoryItems() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxHistoryItems', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByMaxHistoryItemsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxHistoryItems', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByMinimizeToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTray', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByMinimizeToTrayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTray', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpClockOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpClockOffsetMs', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpClockOffsetMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpClockOffsetMs', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpCustomServersJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpCustomServersJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpCustomServersJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpCustomServersJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByNtpLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpLastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpLastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByNtpServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpServer', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByNtpServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpServer', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpSyncIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpSyncIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByNtpSyncIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpSyncIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByPomodoroAutoStartBreaks() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroAutoStartBreaks', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByPomodoroAutoStartBreaksDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroAutoStartBreaks', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByPomodoroLongBreakInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroLongBreakInterval', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByPomodoroLongBreakIntervalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroLongBreakInterval', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByShowInTaskbar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'showInTaskbar', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByShowInTaskbarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'showInTaskbar', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByThemeModePreference() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModePreference', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByThemeModePreferenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModePreference', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByWindowHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowHeight', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByWindowHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowHeight', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByWindowOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowOpacity', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      sortByWindowOpacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowOpacity', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByWindowWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowWidth', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByWindowWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowWidth', Sort.desc);
    });
  }
}

extension AppSettingsQuerySortThenBy
    on QueryBuilder<AppSettings, AppSettings, QSortThenBy> {
  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByAutoCleanup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoCleanup', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByAutoCleanupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoCleanup', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCleanupDays() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupDays', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCleanupDaysDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cleanupDays', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardCapturedTotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardCapturedTotal', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardCapturedTotalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardCapturedTotal', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardDailyCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardDailyCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardDailyCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardDailyCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardHourlyCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardHourlyCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardHourlyCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardHourlyCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardSourceCountsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardSourceCountsJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardSourceCountsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardSourceCountsJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardStatsInitialized() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardStatsInitialized', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByClipboardStatsInitializedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clipboardStatsInitialized', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCloseToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'closeToTray', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCloseToTrayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'closeToTray', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByDarkMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'darkMode', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByDarkModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'darkMode', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroBreakMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroBreakMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroBreakMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroLongBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroLongBreakMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroLongBreakMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroLongBreakMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroWorkMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroWorkMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByDefaultPomodoroWorkMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPomodoroWorkMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByHotkeyShowWindow() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyShowWindow', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByHotkeyShowWindowDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyShowWindow', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByLaunchAtStartupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByMaxHistoryItems() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxHistoryItems', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByMaxHistoryItemsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxHistoryItems', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByMinimizeToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTray', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByMinimizeToTrayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTray', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpClockOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpClockOffsetMs', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpClockOffsetMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpClockOffsetMs', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpCustomServersJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpCustomServersJson', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpCustomServersJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpCustomServersJson', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByNtpLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpLastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpLastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByNtpServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpServer', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByNtpServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpServer', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpSyncIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpSyncIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByNtpSyncIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ntpSyncIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByPomodoroAutoStartBreaks() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroAutoStartBreaks', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByPomodoroAutoStartBreaksDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroAutoStartBreaks', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByPomodoroLongBreakInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroLongBreakInterval', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByPomodoroLongBreakIntervalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pomodoroLongBreakInterval', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByShowInTaskbar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'showInTaskbar', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByShowInTaskbarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'showInTaskbar', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByThemeModePreference() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModePreference', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByThemeModePreferenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModePreference', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByWindowHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowHeight', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByWindowHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowHeight', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByWindowOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowOpacity', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
      thenByWindowOpacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowOpacity', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByWindowWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowWidth', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByWindowWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'windowWidth', Sort.desc);
    });
  }
}

extension AppSettingsQueryWhereDistinct
    on QueryBuilder<AppSettings, AppSettings, QDistinct> {
  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByAutoCleanup() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'autoCleanup');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByCleanupDays() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cleanupDays');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByClipboardCapturedTotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clipboardCapturedTotal');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByClipboardDailyCountsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clipboardDailyCountsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByClipboardHourlyCountsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clipboardHourlyCountsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByClipboardSourceCountsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clipboardSourceCountsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByClipboardStatsInitialized() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clipboardStatsInitialized');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByCloseToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'closeToTray');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByDarkMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'darkMode');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByDefaultPomodoroBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPomodoroBreakMinutes');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByDefaultPomodoroLongBreakMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPomodoroLongBreakMinutes');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByDefaultPomodoroWorkMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPomodoroWorkMinutes');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByHotkeyShowWindow(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hotkeyShowWindow',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'launchAtStartup');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByMaxHistoryItems() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxHistoryItems');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByMinimizeToTray() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'minimizeToTray');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByNtpClockOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ntpClockOffsetMs');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByNtpCustomServersJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ntpCustomServersJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByNtpLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ntpLastSyncAt');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByNtpServer(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ntpServer', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByNtpSyncIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ntpSyncIntervalMinutes');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByPomodoroAutoStartBreaks() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pomodoroAutoStartBreaks');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByPomodoroLongBreakInterval() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pomodoroLongBreakInterval');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByShowInTaskbar() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'showInTaskbar');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
      distinctByThemeModePreference({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'themeModePreference',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByWindowHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'windowHeight');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByWindowOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'windowOpacity');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByWindowWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'windowWidth');
    });
  }
}

extension AppSettingsQueryProperty
    on QueryBuilder<AppSettings, AppSettings, QQueryProperty> {
  QueryBuilder<AppSettings, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> autoCleanupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'autoCleanup');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> cleanupDaysProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cleanupDays');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      clipboardCapturedTotalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clipboardCapturedTotal');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations>
      clipboardDailyCountsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clipboardDailyCountsJson');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations>
      clipboardHourlyCountsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clipboardHourlyCountsJson');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations>
      clipboardSourceCountsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clipboardSourceCountsJson');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations>
      clipboardStatsInitializedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clipboardStatsInitialized');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> closeToTrayProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'closeToTray');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> darkModeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'darkMode');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      defaultPomodoroBreakMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPomodoroBreakMinutes');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      defaultPomodoroLongBreakMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPomodoroLongBreakMinutes');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      defaultPomodoroWorkMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPomodoroWorkMinutes');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations>
      hotkeyShowWindowProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hotkeyShowWindow');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> launchAtStartupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'launchAtStartup');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> maxHistoryItemsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxHistoryItems');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> minimizeToTrayProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'minimizeToTray');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> ntpClockOffsetMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ntpClockOffsetMs');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations>
      ntpCustomServersJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ntpCustomServersJson');
    });
  }

  QueryBuilder<AppSettings, DateTime?, QQueryOperations>
      ntpLastSyncAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ntpLastSyncAt');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations> ntpServerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ntpServer');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      ntpSyncIntervalMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ntpSyncIntervalMinutes');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations>
      pomodoroAutoStartBreaksProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pomodoroAutoStartBreaks');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
      pomodoroLongBreakIntervalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pomodoroLongBreakInterval');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> showInTaskbarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'showInTaskbar');
    });
  }

  QueryBuilder<AppSettings, String?, QQueryOperations>
      themeModePreferenceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'themeModePreference');
    });
  }

  QueryBuilder<AppSettings, double, QQueryOperations> windowHeightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'windowHeight');
    });
  }

  QueryBuilder<AppSettings, double, QQueryOperations> windowOpacityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'windowOpacity');
    });
  }

  QueryBuilder<AppSettings, double, QQueryOperations> windowWidthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'windowWidth');
    });
  }
}
