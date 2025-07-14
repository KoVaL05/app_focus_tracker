import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:app_focus_tracker/app_focus_tracker.dart';

void main() {
  runApp(const MyApp());
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
        _showError('Permissions were not granted. Focus tracking will not work.');
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
      // Configure for detailed tracking with real-time updates
      final config = FocusTrackerConfig.detailed().copyWith(
        updateIntervalMs: 1000, // Update every second
        includeMetadata: true,
        includeSystemApps: false,
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
      final diagnostics = await _appFocusTracker.getDiagnosticInfo();

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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Focus Tracker Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
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
                                subtitle: Text(
                                  '${event.eventType.name} • ${_formatDuration(Duration(microseconds: event.durationMicroseconds))}',
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
      ),
    );
  }
}
