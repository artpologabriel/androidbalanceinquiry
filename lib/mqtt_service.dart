import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'config.dart';

/// Payload received on `solaire/{floor_id}/{machine_id}/balanceinquiry/receive`.
class BalanceInquiry {
  const BalanceInquiry({
    required this.requestId,
    required this.cardId,
    required this.patronName,
    required this.points,
    required this.tickets,
    required this.ticketsWon,
    required this.status,
    required this.timestamp,
  });

  final String requestId;
  final String? cardId;
  final String? patronName;
  final int points;
  final int tickets;
  final int ticketsWon;
  final String status;
  final DateTime timestamp;

  bool get isOk => status == 'OK';

  factory BalanceInquiry.fromJson(Map<String, dynamic> json) {
    return BalanceInquiry(
      requestId: json['request_id'] as String? ?? '',
      cardId: json['card_id'] as String?,
      patronName: json['patron_name'] as String?,
      points: _toInt(json['points']),
      tickets: _toInt(json['tickets']),
      ticketsWon: _toInt(json['tickets_won']),
      status: json['status'] as String? ?? 'ERROR',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// Subscribe-only MQTT client. The app never publishes — machines/kiosks send
/// the inquiry and the backend publishes the response on [MqttConfig.receiveTopic].
class BalanceMqttService {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  final _controller = StreamController<BalanceInquiry>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Balance inquiry messages as they arrive.
  Stream<BalanceInquiry> get messages => _controller.stream;

  /// Connection state changes (true = connected + subscribed).
  Stream<bool> get connectionState => _connectionController.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  Future<void> connect(MqttConfig config) async {
    await disconnect();

    final client = MqttServerClient(
      config.host,
      'solaire-balance-display-${config.machineId}-${DateTime.now().millisecondsSinceEpoch}',
    );
    client
      ..port = config.port
      ..secure = config.port == 8883
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..logging(on: false)
      ..setProtocolV311()
      ..onConnected = () {
        _connected = true;
        _connectionController.add(true);
      }
      ..onDisconnected = () {
        _connected = false;
        _connectionController.add(false);
      };
    _client = client;

    try {
      if (config.username.isEmpty) {
        await client.connect();
      } else {
        await client.connect(config.username, config.password);
      }
    } catch (_) {
      _connected = false;
      _connectionController.add(false);
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _connected = false;
      _connectionController.add(false);
      return;
    }

    client.subscribe(config.receiveTopic, MqttQos.atMostOnce);
    _subscription = client.updates?.listen(_onUpdates);
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final text =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          _controller.add(BalanceInquiry.fromJson(decoded));
        }
      } catch (_) {
        // Malformed payload — ignore and keep listening.
      }
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _client?.disconnect();
    _client = null;
    _connected = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
    await _connectionController.close();
  }
}
