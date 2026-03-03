import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqlite3/sqlite3.dart';

import 'handlers.dart';

Future<HttpServer> startServer({
  required Database db,
  InternetAddress? host,
  int port = 8080,
}) async {
  final router = await buildRouter(db);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await io.serve(handler, host ?? InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Server jalan di http://${server.address.address}:${server.port}',
  );

  // Keep behavior consistent with desktop server.
  startDailyResetScheduler(db);

  return server;
}

Future<void> shutdownServer(HttpServer server) async {
  await server.close(force: true);
}
