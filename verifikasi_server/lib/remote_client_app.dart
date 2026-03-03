import 'package:flutter/material.dart';

import 'remote_api_service.dart';
import 'remote_server_home.dart';
import 'ui.dart';

class ClientServerApp extends StatefulWidget {
  const ClientServerApp({required this.apiBaseUrl, super.key});

  final String apiBaseUrl;

  @override
  State<ClientServerApp> createState() => _ClientServerAppState();
}

class _ClientServerAppState extends State<ClientServerApp> {
  late final RemoteApiService _api;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _api = RemoteApiService(widget.apiBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verifikasi Pulang - Server Client',
      theme: GreenTheme.getTheme(),
      home: _loggedIn
          ? RemoteServerHomePage(
              api: _api,
              onLogout: () {
                setState(() {
                  _loggedIn = false;
                });
              },
            )
          : _RemoteAdminLoginPage(
              api: _api,
              onLoginSuccess: () {
                setState(() {
                  _loggedIn = true;
                });
              },
            ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _RemoteAdminLoginPage extends StatefulWidget {
  const _RemoteAdminLoginPage({
    required this.api,
    required this.onLoginSuccess,
  });

  final RemoteApiService api;
  final VoidCallback onLoginSuccess;

  @override
  State<_RemoteAdminLoginPage> createState() => _RemoteAdminLoginPageState();
}

class _RemoteAdminLoginPageState extends State<_RemoteAdminLoginPage> {
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin123');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Username dan password wajib diisi';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.api.loginAdmin(username: username, password: password);
      if (!mounted) return;
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Server Interface (Remote)',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.api.baseUrl,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Colors.red.shade600)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
