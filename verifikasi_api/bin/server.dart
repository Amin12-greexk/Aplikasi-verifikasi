import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:verifikasi_api/db.dart';
import 'package:verifikasi_api/handlers.dart';
import 'package:verifikasi_api/server.dart';

Future<void> main() async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '8080') ?? 8080;
  final dbPath = env['DB_PATH'] ?? p.join('data', 'log.db');

  await _ensureDbDirectory(dbPath);
  final db = await initDb(dbPath);
  final server = await startServer(db: db, port: port);

  stdout.writeln('[BOOT] DB path: $dbPath');
  stdout.writeln('[BOOT] Listening on port: $port');

  var shuttingDown = false;

  Future<void> shutdown(String signal) async {
    if (shuttingDown) return;
    shuttingDown = true;

    stdout.writeln('[SHUTDOWN] Signal received: $signal');
    stopDailyResetScheduler();
    await shutdownServer(server);
    db.dispose();
    stdout.writeln('[SHUTDOWN] Server closed gracefully');
  }

  final futures = <Future<void>>[
    ProcessSignal.sigint.watch().first.then((_) => shutdown('SIGINT')),
  ];

  if (!Platform.isWindows) {
    futures.add(
      ProcessSignal.sigterm.watch().first.then((_) => shutdown('SIGTERM')),
    );
  }

  await Future.any(futures);
}

Future<void> _ensureDbDirectory(String dbPath) async {
  final dirPath = p.dirname(dbPath);
  if (dirPath.isEmpty || dirPath == '.') return;
  await Directory(dirPath).create(recursive: true);
}
