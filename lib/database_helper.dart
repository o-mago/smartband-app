import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

final String tableHeartBeat = 'heartbeat';
final String tablePressure = 'pressure';
final String tableSaturation = 'saturation';
final String tableTemperature = 'temperature';
final String tableUsers = 'users';
final String columnCpf = 'cpf';
final String columnValue = 'value';

class HeartBeat {
  String cpf;
  String value;

  HeartBeat();

  HeartBeat.fromMap(Map<String, dynamic> map) {
    cpf = map[columnCpf];
    value = map[columnValue];
  }

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{columnCpf: cpf, columnValue: value};
    return map;
  }
}

class Pressure {
  String cpf;
  String value;

  Pressure();

  Pressure.fromMap(Map<String, dynamic> map) {
    cpf = map[columnCpf];
    value = map[columnValue];
  }

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{columnCpf: cpf, columnValue: value};
    return map;
  }
}

class Saturation {
  String cpf;
  String value;

  Saturation();

  Saturation.fromMap(Map<String, dynamic> map) {
    cpf = map[columnCpf];
    value = map[columnValue];
  }

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{columnCpf: cpf, columnValue: value};
    return map;
  }
}

class Temperature {
  String cpf;
  String value;

  Temperature();

  Temperature.fromMap(Map<String, dynamic> map) {
    cpf = map[columnCpf];
    value = map[columnValue];
  }

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{columnCpf: cpf, columnValue: value};
    return map;
  }
}

class Users {
  String cpf;

  Users();

  Users.fromMap(Map<String, dynamic> map) {
    cpf = map[columnCpf];
  }

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{columnCpf: cpf};
    return map;
  }
}

class DatabaseHelper {
  static final _databaseName = "Smartband.db";
  static final _databaseVersion = 1;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // Only allow a single open connection to the database.
  static Database _database;
  Future<Database> get database async {
    if (_database != null) return _database;
    _database = await _initDatabase();
    return _database;
  }

  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
              CREATE TABLE $tableHeartBeat (
                $columnCpf TEXT NOT NULL,
                $columnValue TEXT NOT NULL
              )
              ''');
    await db.execute('''
              CREATE TABLE $tablePressure (
                $columnCpf TEXT NOT NULL,
                $columnValue TEXT NOT NULL
              )
              ''');
    await db.execute('''
              CREATE TABLE $tableSaturation (
                $columnCpf TEXT NOT NULL,
                $columnValue TEXT NOT NULL
              )
              ''');
    await db.execute('''
              CREATE TABLE $tableTemperature (
                $columnCpf TEXT NOT NULL,
                $columnValue TEXT NOT NULL
              )
              ''');
    await db.execute('''
              CREATE TABLE $tableUsers (
                $columnCpf TEXT NOT NULL,
              )
              ''');
  }

  Future<int> insertHeartBeat(HeartBeat heartBeat) async {
    Database db = await database;
    int id = await db.insert(tableHeartBeat, heartBeat.toMap());
    return id;
  }

  Future<int> insertPressure(Pressure pressure) async {
    Database db = await database;
    int id = await db.insert(tablePressure, pressure.toMap());
    return id;
  }

  Future<int> insertSaturation(Saturation saturation) async {
    Database db = await database;
    int id = await db.insert(tableSaturation, saturation.toMap());
    return id;
  }

  Future<int> insertTemperature(Temperature temperature) async {
    Database db = await database;
    int id = await db.insert(tableTemperature, temperature.toMap());
    return id;
  }

  Future<int> insertUsers(Users users) async {
    Database db = await database;
    int id = await db.insert(tableUsers, users.toMap());
    return id;
  }

  Future<HeartBeat> queryHeartBeat(int id) async {
    Database db = await database;
    List<Map> maps =
        await db.query(tableHeartBeat, columns: [columnCpf, columnValue]);
    if (maps.length > 0) {
      return HeartBeat.fromMap(maps.first);
    }
    return null;
  }

  Future<Pressure> queryPressure(int id) async {
    Database db = await database;
    List<Map> maps =
        await db.query(tablePressure, columns: [columnCpf, columnValue]);
    if (maps.length > 0) {
      return Pressure.fromMap(maps.first);
    }
    return null;
  }

  Future<Saturation> querySaturation(int id) async {
    Database db = await database;
    List<Map> maps =
        await db.query(tableSaturation, columns: [columnCpf, columnValue]);
    if (maps.length > 0) {
      return Saturation.fromMap(maps.first);
    }
    return null;
  }

  Future<Temperature> queryTemperature(int id) async {
    Database db = await database;
    List<Map> maps =
        await db.query(tableTemperature, columns: [columnCpf, columnValue]);
    if (maps.length > 0) {
      return Temperature.fromMap(maps.first);
    }
    return null;
  }

  Future<Users> queryUsers(int id) async {
    Database db = await database;
    List<Map> maps = await db.query(tableUsers, columns: [columnCpf]);
    if (maps.length > 0) {
      return Users.fromMap(maps.first);
    }
    return null;
  }
}
