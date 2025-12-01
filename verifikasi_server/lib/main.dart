import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'db.dart';
import 'handlers.dart';

Future<void> main() async {
  final db = await initDb('log.db');
  final router = await buildRouter(db);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
  stdout.writeln('Server jalan di http://${server.address.address}:${server.port}');
}
