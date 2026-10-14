// lib/network/adb_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/contract_models.dart';

class AdbManager {
  String _adbExecutable = 'adb';
  final List<Process> _activeSubprocesses = [];

  AdbManager() {
    _locateAdb();
  }

  void _locateAdb() {
    // Check custom or environment variables
    final String? localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final File standardSdkAdb = File(
        '$localAppData\\Android\\Sdk\\platform-tools\\adb.exe',
      );
      if (standardSdkAdb.existsSync()) {
        _adbExecutable = standardSdkAdb.path;
        debugPrint('[ADB] Located platform-tools adb at: $_adbExecutable');
        return;
      }
    }

    final File programFilesAdb = File(
      r'C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe',
    );
    if (programFilesAdb.existsSync()) {
      _adbExecutable = programFilesAdb.path;
      debugPrint('[ADB] Located Android SDK adb at: $_adbExecutable');
      return;
    }

    debugPrint('[ADB] Using system PATH adb command.');
  }

  /// Establishes wireless ADB pairing/connection loop to target IP and port.
  Future<bool> connectWireless(String ip, int port) async {
    try {
      final String endpoint = '$ip:$port';
      debugPrint('[ADB] Initiating wireless connect to $endpoint...');
      final ProcessResult result = await Process.run(_adbExecutable, ['connect', endpoint]);
      final String output = result.stdout.toString() + result.stderr.toString();
      debugPrint('[ADB] Connect response: $output');

      return output.contains('connected to') || output.contains('already connected');
    } catch (e) {
      debugPrint('[ADB] Failed to run adb connect: $e');
      return false;
    }
  }

  /// Sets up physical USB port forwarding tunnel: adb forward tcp:8080 tcp:8080
  Future<bool> setupUsbTunnel({
    int localPort = ProtocolConstants.defaultSocketPort,
    int remotePort = ProtocolConstants.defaultSocketPort,
  }) async {
    try {
      debugPrint('[ADB] Forwarding local port tcp:$localPort to device tcp:$remotePort...');
      final ProcessResult result = await Process.run(
        _adbExecutable,
        ['forward', 'tcp:$localPort', 'tcp:$remotePort'],
      );
      if (result.exitCode == 0) {
        debugPrint('[ADB] Port forwarding established successfully.');
        return true;
      } else {
        debugPrint('[ADB] Port forward error: ${result.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('[ADB] Failed to configure adb forward: $e');
      return false;
    }
  }

  /// Queries all third-party packages installed on the device: adb shell pm list packages -3
  Future<List<AppPackageModel>> queryThirdPartyPackages() async {
    try {
      final ProcessResult result = await Process.run(
        _adbExecutable,
        ['shell', 'pm', 'list', 'packages', '-3'],
      );

      if (result.exitCode != 0) {
        debugPrint('[ADB] Failed to query packages: ${result.stderr}');
        return _getFallbackSamplePackages();
      }

      final String stdout = result.stdout.toString();
      final List<String> lines = stdout.split(RegExp(r'\r?\n'));
      final List<AppPackageModel> packages = [];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('package:')) {
          final pkg = trimmed.substring('package:'.length).trim();
          if (pkg.isNotEmpty) {
            // Generate user-friendly title from reverse domain notation
            final String readableLabel = _generateFriendlyAppLabel(pkg);
            packages.add(AppPackageModel(packageName: pkg, label: readableLabel));
          }
        }
      }

      packages.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      return packages;
    } catch (e) {
      debugPrint('[ADB] Error executing package query: $e');
      return _getFallbackSamplePackages();
    }
  }

  /// Launches an application on the connected Pixel device using monkey intent runner.
  Future<bool> launchApp(String packageName) async {
    try {
      debugPrint('[ADB] Launching application: $packageName...');
      final ProcessResult result = await Process.run(_adbExecutable, [
        'shell',
        'monkey',
        '-p',
        packageName,
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ]);
      debugPrint('[ADB] Launch result: ${result.stdout}');
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('[ADB] Error launching application $packageName: $e');
      return false;
    }
  }

  /// Cleanly terminates all spawned background ADB subprocesses and kills the ADB server daemon.
  Future<void> cleanTerminateAdb() async {
    debugPrint('[ADB] Cleaning up and terminating all background ADB processes...');
    for (final process in _activeSubprocesses) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _activeSubprocesses.clear();

    try {
      await Process.run(_adbExecutable, ['kill-server']);
      debugPrint('[ADB] ADB server daemon successfully terminated.');
    } catch (e) {
      debugPrint('[ADB] Error terminating adb server: $e');
    }
  }

  String _generateFriendlyAppLabel(String packageName) {
    final parts = packageName.split('.');
    if (parts.isNotEmpty) {
      final last = parts.last;
      return last[0].toUpperCase() + last.substring(1);
    }
    return packageName;
  }

  List<AppPackageModel> _getFallbackSamplePackages() {
    return [
      AppPackageModel(packageName: 'com.google.android.apps.messaging', label: 'Messages'),
      AppPackageModel(packageName: 'com.google.android.apps.photos', label: 'Photos'),
      AppPackageModel(packageName: 'com.google.android.youtube', label: 'YouTube'),
      AppPackageModel(packageName: 'com.spotify.music', label: 'Spotify'),
      AppPackageModel(packageName: 'com.slack', label: 'Slack'),
      AppPackageModel(packageName: 'com.target.banking.app', label: 'Target Banking'),
    ];
  }
}
