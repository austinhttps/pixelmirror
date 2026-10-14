// lib/network/mdns_discovery.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../core/constants.dart';

class DiscoveredAdbDevice {
  final String ip;
  final int port;
  final String name;
  final DateTime discoveredAt;

  DiscoveredAdbDevice({
    required this.ip,
    required this.port,
    required this.name,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  String get endpoint => '$ip:$port';

  @override
  String toString() => 'DiscoveredAdbDevice($name @ $endpoint)';
}

/// Asynchronous mDNS Network Discovery targeting `_adb-tls-connect._tcp`.
/// Auto-discovers Pixel 10's Wireless Debugging service on local Wi-Fi.
class MdnsDiscoveryManager {
  final MDnsClient _mDnsClient = MDnsClient();
  bool _isSearching = false;
  Timer? _pollingTimer;

  final StreamController<DiscoveredAdbDevice> _deviceStreamController =
      StreamController<DiscoveredAdbDevice>.broadcast();

  Stream<DiscoveredAdbDevice> get onDeviceDiscovered => _deviceStreamController.stream;
  bool get isSearching => _isSearching;

  Future<void> startDiscovery({Duration pollInterval = const Duration(seconds: 10)}) async {
    if (_isSearching) return;
    _isSearching = true;

    try {
      await _mDnsClient.start();
      debugPrint('[mDNS] Multicast DNS client started. Querying for ${ProtocolConstants.mdnsAdbServiceType}...');

      // Run initial search and start recurring poll loop
      _searchOnce();
      _pollingTimer = Timer.periodic(pollInterval, (_) => _searchOnce());
    } catch (e) {
      debugPrint('[mDNS] Failed to start mDNS discovery client: $e');
      // Fallback UDP probe if mDNS client initialization fails
      _startFallbackProbe();
    }
  }

  Future<void> _searchOnce() async {
    if (!_isSearching) return;

    try {
      // 1. Query PTR records for Wireless Debugging service
      await for (final PtrResourceRecord ptr in _mDnsClient.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(
          '${ProtocolConstants.mdnsAdbServiceType}.local',
        ),
      )) {
        debugPrint('[mDNS] Discovered PTR record: ${ptr.domainName}');

        // 2. Query SRV records for port details
        await for (final SrvResourceRecord srv in _mDnsClient.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          final int port = srv.port;
          final String targetHost = srv.target;

          // 3. Resolve target host to IPv4 Address
          await for (final IPAddressResourceRecord ipRecord in _mDnsClient.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(targetHost),
          )) {
            final String ip = ipRecord.address.address;
            final String deviceName = ptr.domainName.split('.').first;

            final DiscoveredAdbDevice device = DiscoveredAdbDevice(
              ip: ip,
              port: port,
              name: deviceName.isEmpty ? ProtocolConstants.defaultDeviceName : deviceName,
            );

            debugPrint('[mDNS] Successfully resolved Pixel 10 Wireless Debugging endpoint: ${device.endpoint}');
            _deviceStreamController.add(device);
          }
        }
      }
    } catch (e) {
      debugPrint('[mDNS] Search cycle exception: $e');
    }
  }

  /// Fallback UDP broadcast scanner in case Multicast DNS routing is filtered on local AP.
  void _startFallbackProbe() {
    debugPrint('[mDNS] Starting fallback broadcast probe on local subnet...');
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      socket.broadcastEnabled = true;
      _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_isSearching) {
          socket.close();
          return;
        }
        // Ping local broadcast with query
        socket.send(
          Uint8List.fromList('PIXEL_MIRROR_MDNS_DISCOVERY'.codeUnits),
          InternetAddress('255.255.255.255'),
          ProtocolConstants.defaultSocketPort,
        );
      });
    }).catchError((err) {
      debugPrint('[mDNS] Fallback socket error: $err');
    });
  }

  void stopDiscovery() {
    _isSearching = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    try {
      _mDnsClient.stop();
    } catch (_) {}
    debugPrint('[mDNS] Multicast discovery stopped.');
  }

  void dispose() {
    stopDiscovery();
    _deviceStreamController.close();
  }
}
