// lib/network/adb_manager.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';

/// Lightweight ADB Manager focused on USB port forwarding tunnel and wireless pairing.
class AdbManager {
  String _adbExecutable = 'adb';
  final List<Process> _activeSubprocesses = [];

  AdbManager() {
    _locateAdb();
  }

  void _locateAdb() {
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

  /// Cleanly terminates all spawned background ADB subprocesses.
  Future<void> cleanTerminateAdb() async {
    debugPrint('[ADB] Cleaning up background ADB processes...');
    for (final process in _activeSubprocesses) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _activeSubprocesses.clear();
  }
}
