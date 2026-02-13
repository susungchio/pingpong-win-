import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'models.dart';
import 'file_utils.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 경로 변경 시 DB 연결을 닫고 재연결하기 위한 메서드
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // DB 재연결 (경로 변경 후 사용)
  Future<void> reconnectDatabase() async {
    await closeDatabase();
    _database = await _initDatabase();
  }

  static const String _tableMasterPlayers = 'master_players';
  static const int _dbVersion = 3;

  Future<Database> _initDatabase() async {
    // FileUtils에서 설정된 동적 경로의 data 폴더를 사용합니다.
    final dataDirPath = await FileUtils.getDataDirPath();
    final path = p.join(dataDirPath, 'pingpong_master_v2.db');

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createMasterPlayersTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) await _migrateToV3(db);
      },
    );
  }

  Future<void> _createMasterPlayersTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_tableMasterPlayers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playerNumber TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        affiliation TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        gender TEXT NOT NULL DEFAULT '',
        tier TEXT NOT NULL DEFAULT '',
        points TEXT NOT NULL DEFAULT '',
        UNIQUE(name, affiliation)
      )
    ''');
  }

  Future<void> _migrateToV3(Database db) async {
    await db.execute('DROP TABLE IF EXISTS $_tableMasterPlayers');
    await _createMasterPlayersTable(db);
  }

  Future<List<MasterPlayer>> getAllPlayers() async {
    final db = await database;
    return (await db.query('master_players', orderBy: 'id DESC'))
        .map((json) => MasterPlayer.fromJson(json)).toList();
  }

  Future<int> updatePlayer(int id, MasterPlayer player) async {
    final db = await database;
    return await db.update('master_players', player.toJson(), where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePlayer(int id) async {
    final db = await database;
    return await db.delete('master_players', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, int>> insertMasterPlayers(List<MasterPlayer> players) async {
    final db = await database;
    int added = 0; int updated = 0; int duplicates = 0;

    await db.transaction((txn) async {
      for (var player in players) {
        final List<Map<String, dynamic>> existing = await txn.query(
          'master_players', where: 'name = ? AND affiliation = ?', whereArgs: [player.name, player.affiliation],
        );

        if (existing.isEmpty) {
          await txn.insert('master_players', player.toJson(), conflictAlgorithm: ConflictAlgorithm.ignore);
          added++;
        } else {
          final oldData = MasterPlayer.fromJson(existing.first);
          Map<String, dynamic> updateValues = {};
          if (oldData.playerNumber.isEmpty && player.playerNumber.isNotEmpty) updateValues['playerNumber'] = player.playerNumber;
          if (oldData.city.isEmpty && player.city.isNotEmpty) updateValues['city'] = player.city;
          if (oldData.gender.isEmpty && player.gender.isNotEmpty) updateValues['gender'] = player.gender;
          if (oldData.tier.isEmpty && player.tier.isNotEmpty) updateValues['tier'] = player.tier;
          if ((oldData.points.isEmpty || oldData.points == "0점") && player.points.isNotEmpty) updateValues['points'] = player.points;

          if (updateValues.isNotEmpty) {
            await txn.update('master_players', updateValues, where: 'id = ?', whereArgs: [oldData.id]);
            updated++;
          } else {
            duplicates++;
          }
        }
      }
    });
    return {'added': added, 'updated': updated, 'duplicates': duplicates};
  }

  Future<List<MasterPlayer>> searchPlayers(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('master_players', where: 'name LIKE ? OR affiliation LIKE ?', whereArgs: ['%$query%', '%$query%'], limit: 50);
    return maps.map((json) => MasterPlayer.fromJson(json)).toList();
  }

  Future<List<MasterPlayer>> searchPlayersExact(String name, String aff) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('master_players', where: 'name = ? AND affiliation = ?', whereArgs: [name, aff]);
    return maps.map((json) => MasterPlayer.fromJson(json)).toList();
  }

  Future<int> getPlayerCount() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM master_players')) ?? 0;
  }

  Future<Map<String, int>> getTierStats() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT CASE WHEN tier IS NULL OR tier = '' THEN '(미지정)' ELSE tier END AS tierName, COUNT(*) AS cnt FROM $_tableMasterPlayers GROUP BY CASE WHEN tier IS NULL OR tier = '' THEN '(미지정)' ELSE tier END ORDER BY cnt DESC",
    );
    final Map<String, int> result = {};
    for (final row in rows) {
      final name = row['tierName'] as String? ?? '(미지정)';
      result[name] = row['cnt'] as int? ?? 0;
    }
    return result;
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('master_players');
  }
}
