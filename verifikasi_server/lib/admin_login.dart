import 'package:flutter/material.dart';

class AdminLoginPage extends StatefulWidget {
  final Function(bool) onLoginSuccess;

  const AdminLoginPage({required this.onLoginSuccess, super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _errorMessage;

  // Warna Tema (Sesuai Dashboard sebelumnya)
  static const Color primaryColor = Color(0xFF059669); // Emerald 600
  static const Color bgColor = Color(0xFFF0FDF4); // Green 50

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
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Username dan password wajib diisi');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Simulasi delay network agar UX lebih terasa
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    if (_usernameController.text == 'admin' &&
        _passwordController.text == 'admin123') {
      widget.onLoginSuccess(true);
    } else {
      setState(() => _errorMessage = 'Username atau password salah');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Latar belakang dengan gradient halus
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFECFDF5), // Emerald 50
              Color(0xFFD1FAE5), // Emerald 100
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header Logo di luar Card (Opsional, memberikan efek depth)
                _buildHeaderLogo(),
                const SizedBox(height: 32),
                
                // --- KARTU LOGIN UTAMA ---
                // ConstrainedBox membatasi lebar agar tidak "melebar" di Desktop
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome Back',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Masuk untuk mengelola verifikasi',
                          style: TextStyle(color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        
                        // Input Fields
                        _buildTextField(
                          controller: _usernameController,
                          label: 'Username',
                          icon: Icons.person_outline_rounded,
                          isLast: false,
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline_rounded,
                          isObscure: !_showPassword,
                          isLast: true,
                          onTogglePassword: () {
                            setState(() => _showPassword = !_showPassword);
                          },
                        ),
                        
                        // Error Message
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _errorMessage != null
                              ? Container(
                                  margin: const EdgeInsets.only(top: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.shade100),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline,
                                          size: 20, color: Colors.red.shade600),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.red.shade600),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Login Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              shadowColor: primaryColor.withOpacity(0.4),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Footer / Demo Credentials
                _buildDemoCredentials(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderLogo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.admin_panel_settings_rounded,
            size: 48,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SERVER MANAGEMENT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            color: primaryColor.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    bool isLast = false,
    VoidCallback? onTogglePassword,
  }) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(fontWeight: FontWeight.w500),
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onSubmitted: isLast ? (_) => _handleLogin() : null,
      onChanged: (_) {
        if (_errorMessage != null) setState(() => _errorMessage = null);
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 22),
        suffixIcon: onTogglePassword != null
            ? IconButton(
                icon: Icon(
                  isObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDemoCredentials() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Demo: ',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Text(
              'admin',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              ' / ',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const Text(
              'admin123',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}