import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayManager with TrayListener, WindowListener {
  static final SystemTrayManager _instance = SystemTrayManager._internal();

  factory SystemTrayManager() {
    return _instance;
  }

  SystemTrayManager._internal();

  VoidCallback? _onShow;
  VoidCallback? _onExit;

  /// Initialize system tray
  Future<void> initialize({
    required VoidCallback onShow,
    required VoidCallback onExit,
  }) async {
    _onShow = onShow;
    _onExit = onExit;

    try {
      // Initialize window manager (if not already initialized)
      try {
        await windowManager.ensureInitialized();
      } catch (e) {
        print('[SystemTray] Window manager already initialized');
      }
      windowManager.addListener(this);

      // Add tray listener
      trayManager.addListener(this);

      // Setup tray menu
      await _setupTray();

      print('[SystemTray] System tray initialized successfully');
    } catch (e) {
      print('[SystemTray] Failed to initialize system tray: $e');
    }
  }

  /// Setup tray menu and icon
  Future<void> _setupTray() async {
    try {
      // Set icon
      try {
        await trayManager.setIcon('assets/logo.jpg');
      } catch (e) {
        print('[SystemTray] Could not set icon: $e');
      }

      // Create menu items
      final menu = Menu(
        items: [
          MenuItem(
            key: 'show',
            label: 'Show Dashboard',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'status',
            label: 'Server Status: Running',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit',
            label: 'Exit',
          ),
        ],
      );

      // Set context menu
      await trayManager.setContextMenu(menu);

      // Set tooltip
      await trayManager.setToolTip('Verifikasi Server - Running');

      print('[SystemTray] Tray menu setup complete');
    } catch (e) {
      print('[SystemTray] Error setting up tray: $e');
      rethrow;
    }
  }

  /// Hide window (minimize to tray)
  Future<void> hideWindow() async {
    try {
      await windowManager.hide();
      print('[SystemTray] Window hidden to tray');
    } catch (e) {
      print('[SystemTray] Error hiding window: $e');
    }
  }

  /// Show window from tray
  Future<void> showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      print('[SystemTray] Window shown');
    } catch (e) {
      print('[SystemTray] Error showing window: $e');
    }
  }

  /// Update tooltip
  Future<void> setTooltip(String tooltip) async {
    try {
      await trayManager.setToolTip(tooltip);
      print('[SystemTray] Tooltip set: $tooltip');
    } catch (e) {
      print('[SystemTray] Error setting tooltip: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      print('[SystemTray] Resources disposed');
    } catch (e) {
      print('[SystemTray] Error disposing: $e');
    }
  }

  // TrayListener implementation
  @override
  void onTrayIconMouseDown() {
    print('[SystemTray] Tray icon left-clicked');
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    print('[SystemTray] Tray icon right-clicked - menu will show');
  }

  @override
  void onTrayIconMouseUp() {
    print('[SystemTray] Tray icon mouse up');
  }

  @override
  void onTrayRightMouseUp() {
    print('[SystemTray] Tray right mouse up');
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    print('[SystemTray] Menu item clicked: ${menuItem.key}');

    if (menuItem.key == 'show') {
      showWindow();
    } else if (menuItem.key == 'exit') {
      if (_onExit != null) {
        _onExit!();
      }
    } else if (menuItem.key == 'status') {
      print('[SystemTray] Server Status: Running on port 8080');
    }
  }

  // WindowListener implementation
  @override
  void onWindowEvent(String eventName) {
    print('[Window] Event: $eventName');
  }

  @override
  void onWindowClose() async {
    print('[Window] Window closing');
    try {
      // Minimize to tray instead of closing
      await hideWindow();
    } catch (e) {
      print('[Window] Error handling close: $e');
    }
  }

  @override
  void onWindowMinimize() {
    print('[Window] Minimized - hiding to tray');
    hideWindow();
  }

  @override
  void onWindowMaximize() {
    print('[Window] Maximized');
  }

  @override
  void onWindowRestore() {
    print('[Window] Restored');
  }

  @override
  void onWindowResized() {
    print('[Window] Resized');
  }

  @override
  void onWindowMoved() {
    print('[Window] Moved');
  }

  @override
  void onWindowFocusChanged(bool focused) {
    if (focused) {
      print('[Window] Focus gained');
    }
  }

  @override
  void onWindowEnterFullScreen() {
    print('[Window] Entered fullscreen');
  }

  @override
  void onWindowLeaveFullScreen() {
    print('[Window] Left fullscreen');
  }

  @override
  void onWindowBeforeClose() {
    print('[Window] Before close');
  }
}
