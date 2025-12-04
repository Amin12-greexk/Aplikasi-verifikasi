import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqlite3/sqlite3.dart';
import 'handlers.dart';

/// Starts the HTTP server in headless mode (no UI)
/// Used when running as Windows Service
Future<HttpServer> startServerHeadless(Database db) async {
  try {
    final router = await buildRouter(db);
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    final server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
    stdout.writeln('Server jalan di http://${server.address.address}:${server.port}');
    stdout.writeln('[HEADLESS MODE] Server berjalan tanpa UI');
    return server;
  } catch (e) {
    stderr.writeln('Error starting server: $e');
    rethrow;
  }
}

/// Starts the HTTP server in background (with UI)
/// Returns immediately without blocking
Future<HttpServer> startServerBackground(Database db) async {
  try {
    final router = await buildRouter(db);
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    final server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
    stdout.writeln('Server jalan di http://${server.address.address}:${server.port}');
    stdout.writeln('[BACKGROUND MODE] Server berjalan bersama UI');
    return server;
  } catch (e) {
    stderr.writeln('Error starting server: $e');
    rethrow;
  }
}

/// Gracefully shutdown the server
Future<void> shutdownServer(HttpServer server) async {
  try {
    await server.close(force: true);
    stdout.writeln('Server shutdown gracefully');
  } catch (e) {
    stderr.writeln('Error shutting down server: $e');
  }
}
