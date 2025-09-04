import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';

void main() {
  runApp(const AppFocusTrackerApp());
}

class AppFocusTrackerApp extends StatelessWidget {
  const AppFocusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Focus Tracker Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyApp(),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformName = 'Unknown';
  bool _isSupported = false;
  bool _hasPermissions = false;
  bool _isTracking = false;
  String _currentApp = 'None';
  Duration _currentDuration = Duration.zero;
  List<FocusEvent> _recentEvents = [];
  StreamSubscription<FocusEvent>? _focusSubscription;
  AppInfo? _currentAppInfo;

  final _appFocusTracker = AppFocusTracker();

  @override
  void initState() {
    super.initState();
    _initializePlatform();
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  // Initialize platform information and check capabilities
  Future<void> _initializePlatform() async {
    try {
      final platformName = await _appFocusTracker.getPlatformName();
      final isSupported = await _appFocusTracker.isSupported();
      final hasPermissions = await _appFocusTracker.hasPermissions();

      setState(() {
        _platformName = platformName;
        _isSupported = isSupported;
        _hasPermissions = hasPermissions;
      });

      // Get current focused app info
      final currentApp = await _appFocusTracker.getCurrentFocusedApp();
      if (currentApp != null) {
        setState(() {
          _currentAppInfo = currentApp;
          _currentApp = currentApp.name;
        });
      }
    } catch (e) {
      setState(() {
        _platformName = 'Error: $e';
      });
    }
  }

  // Request permissions if needed
  Future<void> _requestPermissions() async {
    try {
      final granted = await _appFocusTracker.requestPermissions();
      setState(() {
        _hasPermissions = granted;
      });

      if (!granted) {
        // Show dialog asking user to open system settings
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text(
              'Accessibility permissions are required for focus tracking. '
              'Would you like to open System Settings to grant permissions?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await _appFocusTracker.openSystemSettings();
        }
      }
    } catch (e) {
      _showError('Failed to request permissions: $e');
    }
  }

  // Start focus tracking with event-driven approach
  Future<void> _startTracking() async {
    if (!_hasPermissions) {
      await _requestPermissions();
      if (!_hasPermissions) return;
    }

    try {
      // Configure for detailed tracking with real-time updates and browser tab tracking
      final config = FocusTrackerConfig.detailed().copyWith(
        updateIntervalMs: 1000, // Update every second
        includeMetadata: true,
        includeSystemApps: false,
        enableBrowserTabTracking: true, // Enable browser tab change detection
      );

      await _appFocusTracker.startTracking(config);

      // Listen to the focus event stream
      _focusSubscription = _appFocusTracker.focusStream.listen(
        (event) {
          setState(() {
            _currentApp = event.appName;
            _currentDuration = Duration(microseconds: event.durationMicroseconds);

            // Add to recent events (keep last 10)
            _recentEvents.insert(0, event);
            if (_recentEvents.length > 10) {
              _recentEvents.removeRange(10, _recentEvents.length);
            }
          });
        },
        onError: (error) {
          _showError('Focus tracking error: $error');
        },
      );

      setState(() {
        _isTracking = true;
      });
    } catch (e) {
      _showError('Failed to start tracking: $e');
    }
  }

  // Stop focus tracking
  Future<void> _stopTracking() async {
    try {
      await _focusSubscription?.cancel();
      _focusSubscription = null;

      if (_isTracking) {
        await _appFocusTracker.stopTracking();
      }

      setState(() {
        _isTracking = false;
        _currentApp = 'None';
        _currentDuration = Duration.zero;
      });
    } catch (e) {
      _showError('Failed to stop tracking: $e');
    }
  }

  // Get list of running applications
  Future<void> _getRunningApps() async {
    try {
      final apps = await _appFocusTracker.getRunningApplications(includeSystemApps: false);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Running Applications'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                return ListTile(
                  title: Text(app.name),
                  subtitle: Text('PID: ${app.processId} • ${app.identifier}'),
                  trailing: app.version != null ? Text('v${app.version}') : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Failed to get running apps: $e');
    }
  }

  // Show diagnostic information
  Future<void> _showDiagnostics() async {
    try {
      final diagnostics = await AppFocusTracker.getDiagnosticInfo();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Diagnostic Information'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: SingleChildScrollView(
              child: Text(
                diagnostics.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Failed to get diagnostics: $e');
    }
  }

  // Show URL extraction debug information
  Future<void> _showUrlDebug() async {
    try {
      final debugInfo = await AppFocusTracker.debugUrlExtraction();

      showDialog(
        context: context,
        barrierDismissible: false, // Prevent closing by tapping outside
        builder: (context) => AlertDialog(
          title: const Text('URL Extraction Debug'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug Information:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    debugInfo.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Instructions:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Switch to a browser window (this dialog will stay open)\n'
                    '2. Click "Refresh Debug Info" to capture the browser state\n'
                    '3. Check the output above for URL extraction results\n'
                    '4. Look for "unknown" or empty values to identify issues',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                // Close dialog and show refresh with delay
                Navigator.of(context).pop();
                _showUrlDebugWithDelay();
              },
              child: const Text('Refresh Debug Info'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Failed to get URL debug info: $e');
    }
  }

  // Show URL debug with a delay to allow user to switch to browser
  void _showUrlDebugWithDelay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Preparing Debug...'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Please switch to a browser window now.\n'
              'Debug info will be captured in 3 seconds.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Wait 3 seconds then capture debug info
    Future.delayed(const Duration(seconds: 3), () async {
      if (mounted) {
        try {
          final debugInfo = await AppFocusTracker.debugUrlExtraction();
          Navigator.of(context).pop(); // Close the "preparing" dialog
          _showUrlDebugWithData(debugInfo);
        } catch (e) {
          Navigator.of(context).pop(); // Close the "preparing" dialog
          _showError('Failed to get debug info: $e');
        }
      }
    });
  }

  // Helper method to show URL debug with specific data
  void _showUrlDebugWithData(Map<String, dynamic> debugInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('URL Extraction Debug'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debug Information:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  debugInfo.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  'Instructions:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Switch to a browser window (this dialog will stay open)\n'
                  '2. Click "Refresh Debug Info" to capture the browser state\n'
                  '3. Check the output above for URL extraction results\n'
                  '4. Look for "unknown" or empty values to identify issues',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              // Close dialog and show refresh with delay
              Navigator.of(context).pop();
              _showUrlDebugWithDelay();
            },
            child: const Text('Refresh Debug Info'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    // Only show error if widget is mounted and context is available
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      // Fallback: print to console if widget is not mounted
      print('Error: $message');
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
  }

  String _getEventTypeIcon(FocusEventType type) {
    switch (type) {
      case FocusEventType.gained:
        return '🟢';
      case FocusEventType.lost:
        return '🔴';
      case FocusEventType.durationUpdate:
        return '🔄';
      case FocusEventType.tabChange:
        return '🟦';
    }
  }

  String? _formatTabChangeDetails(FocusEvent event) {
    final meta = event.metadata;
    if (meta == null) return null;

    final titleChange = meta['titleChange'];
    if (titleChange is Map) {
      final from = titleChange['from'];
      final to = titleChange['to'];
      if (from is String || to is String) {
        final fromStr = (from is String && from.isNotEmpty) ? from : '—';
        final toStr = (to is String && to.isNotEmpty) ? to : '—';
        return 'Title: $fromStr → $toStr';
      }
    }

    final prevTab = meta['previousTab'];
    final currTab = meta['currentTab'];
    String? prevTitle;
    String? currTitle;
    if (prevTab is Map) {
      final t = prevTab['title'];
      if (t is String && t.isNotEmpty) prevTitle = t;
    }
    if (currTab is Map) {
      final t = currTab['title'];
      if (t is String && t.isNotEmpty) currTitle = t;
    }
    if (prevTitle != null || currTitle != null) {
      return 'Tab: ${prevTitle ?? '—'} → ${currTitle ?? '—'}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Focus Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Information',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Platform: $_platformName'),
                    Text('Supported: ${_isSupported ? "Yes" : "No"}'),
                    Text('Permissions: ${_hasPermissions ? "Granted" : "Required"}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Control Buttons
            Row(
              children: [
                if (!_hasPermissions)
                  ElevatedButton.icon(
                    onPressed: _requestPermissions,
                    icon: const Icon(Icons.security),
                    label: const Text('Request Permissions'),
                  ),
                if (_hasPermissions && !_isTracking)
                  ElevatedButton.icon(
                    onPressed: _startTracking,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Tracking'),
                  ),
                if (_isTracking)
                  ElevatedButton.icon(
                    onPressed: _stopTracking,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Tracking'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _getRunningApps,
                  icon: const Icon(Icons.apps),
                  label: const Text('Apps'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showDiagnostics,
                  icon: const Icon(Icons.info),
                  label: const Text('Diagnostics'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showUrlDebug,
                  icon: const Icon(Icons.bug_report),
                  label: const Text('URL Debug'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Current Focus Information
            if (_isTracking) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Focus',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'App: $_currentApp',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Duration: ${_formatDuration(_currentDuration)}'),
                      if (_currentAppInfo != null) ...[
                        Text('Process ID: ${_currentAppInfo!.processId ?? "N/A"}'),
                        Text('Identifier: ${_currentAppInfo!.identifier}'),
                        if (_currentAppInfo!.version != null) Text('Version: ${_currentAppInfo!.version}'),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Recent Events
              Text(
                'Recent Events',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: _recentEvents.isEmpty
                      ? const Center(
                          child: Text(
                            'No events yet...\nSwitch between applications to see events.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _recentEvents.length,
                          itemBuilder: (context, index) {
                            final event = _recentEvents[index];
                            return ListTile(
                              leading: Text(
                                _getEventTypeIcon(event.eventType),
                                style: const TextStyle(fontSize: 20),
                              ),
                              title: Text(event.appName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${event.eventType.name} • ${_formatDuration(Duration(microseconds: event.durationMicroseconds))}',
                                  ),
                                  if (event.eventType == FocusEventType.tabChange) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTabChangeDetails(event) ?? 'Tab/Title changed',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (event.isBrowser && event.browserTab != null) ...[
                                    Text(
                                      '🌐 ${event.browserTab!.browserType} • ${event.browserTab!.url ?? "Unknown"}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.blue,
                                          ),
                                    ),
                                    Text(
                                      event.browserTab!.title,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Text(
                                '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                                '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                                '${event.timestamp.second.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_off,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Focus tracking is not active',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Start tracking to see real-time focus events',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
