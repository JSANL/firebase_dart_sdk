// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:io';

import 'package:dart_sqlite/dart_sqlite.dart' as sql;
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';

class DatabaseMock extends Database {
  DatabaseMock._(this.database, this.path);

  sql.Database database;
  File path;

  bool renamePath = true;

  static File pathForName(String name) {
    return File('${Directory.current.path}/build/test/$name');
  }

  static Future<DatabaseMock> create(String name,
      {int version,
      OnConfigure onConfigure,
      OnCreate onCreate,
      OnVersionChange onUpgrade,
      OnVersionChange onDowngrade,
      OnOpen onOpen}) async {
    version ??= 1;

    final File path = pathForName(name);
    final bool callOnCreate = !path.existsSync();
    path.createSync(recursive: true);

    final sql.Database database = sql.Database(path.path);
    final DatabaseMock mock = DatabaseMock._(database, path);

    await onConfigure?.call(mock);
    if (callOnCreate) {
      await onCreate?.call(mock, version);
      await database.execute('PRAGMA user_version = $version;');
    } else {
      final List<sql.Row> row = await database.query('PRAGMA user_version;').toList();
      final int currentVersion = row.first.toMap().values.first;

      if (currentVersion < version) {
        await onUpgrade?.call(mock, currentVersion, version);
        await database.execute('PRAGMA user_version = $version;');
      }

      if (currentVersion > version) {
        await database.execute('PRAGMA user_version = $version;');
        await onDowngrade?.call(mock, currentVersion, version);
      }
    }

    await onOpen?.call(mock);
    return mock;
  }

  @override
  Future<int> delete(String statement, [List<dynamic> arguments]) {
    return database.execute(statement, arguments ?? <dynamic>[]);
  }

  @override
  Future<void> execute(String statement, [List<dynamic> arguments]) async {
    await database.execute(statement, arguments ?? <dynamic>[]);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String statement, [List<void> arguments]) async {
    return database //
        .query(statement, arguments ?? <dynamic>[])
        .toList()
        .then((List<sql.Row> rows) => rows.map((sql.Row row) => row.toMap()).toList());
  }

  @override
  void close() {
    database.close();
    if (renamePath) {
      path.renameSync('${path.path}_');
    }
  }
}
