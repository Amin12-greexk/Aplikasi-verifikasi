import 'package:flutter/material.dart';
import 'auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _selectedRole;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_selectedRole == null) {
      setState(() => _errorMessage = 'Pilih role terlebih dahulu');
      return;
    }

    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Username dan password tidak boleh kosong');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_selectedRole == 'pengawas') {
        await AuthService.loginPengawas(
          _usernameController.text,
          _passwordController.text,
        );
      } else {
        await AuthService.loginSecurity(
          _usernameController.text,
          _passwordController.text,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    size: 60,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Verifikasi Pulang',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Login Management System',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                // Role Selection
                Text(
                  'Pilih Role',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RoleButton(
                        label: 'Pengawas',
                        icon: Icons.badge,
                        isSelected: _selectedRole == 'pengawas',
                        onTap: () => setState(() => _selectedRole = 'pengawas'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleButton(
                        label: 'Security',
                        icon: Icons.security,
                        isSelected: _selectedRole == 'security',
                        onTap: () => setState(() => _selectedRole = 'security'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Username Field
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 16),
                // Password Field
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: !_showPassword,
                  onChanged: (_) => setState(() => _errorMessage = null),
                ),
                const SizedBox(height: 8),
                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade600),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                // Login Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green.shade600,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    'LOGIN',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
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

class _RoleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade100 : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? Colors.green.shade600 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.green.shade600 : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.green.shade700 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
