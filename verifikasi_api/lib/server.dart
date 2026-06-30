import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqlite3/sqlite3.dart';

import 'fcm.dart';
import 'handlers.dart';

Future<HttpServer> startServer({
  required Database db,
  InternetAddress? host,
  int port = 8080,
}) async {
  final router = await buildRouter(db);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  final server = await io.serve(handler, host ?? InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Server jalan di http://${server.address.address}:${server.port}',
  );

  // Keep behavior consistent with desktop server.
  startDailyResetScheduler(db);

  // Server-side FCM push when a toilet permit expires (works even when the
  // mobile app is closed). No-op if FCM is not configured via env vars.
  startToiletExpiryPushScheduler(db, FcmSender.fromEnv());

  return server;
}

Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
        });
      }

      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
      });
    };
  };
}

Future<void> shutdownServer(HttpServer server) async {
  await server.close(force: true);
}
