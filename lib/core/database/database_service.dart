import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'print_easy.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE templates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            paper_width_px INTEGER NOT NULL,
            content TEXT NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE print_jobs (
            id TEXT PRIMARY KEY,
            template_id TEXT,
            template_name TEXT NOT NULL,
            content TEXT NOT NULL,
            paper_width_px INTEGER NOT NULL,
            status TEXT NOT NULL,
            error_message TEXT,
            printed_at TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_print_jobs_date ON print_jobs(printed_at DESC)',
        );
      },
    );
  }
}
