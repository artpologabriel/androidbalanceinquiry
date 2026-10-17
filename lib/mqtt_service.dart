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
    this.rawPayload,
  });

  final String requestId;
  final String? cardId;
  final String? patronName;
  final int points;
  final int tickets;
  final int ticketsWon;
  final String status;
  final DateTime timestamp;

  /// Raw payload text as received on the wire — for on-device debugging.
  final String? rawPayload;

  bool get isOk => status == 'OK';

  factory BalanceInquiry.fromJson(Map<String, dynamic> json,
      {String? rawPayload}) {
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
      rawPayload: rawPayload,
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

  /// Human-readable reason for the last failed connect attempt.
  String? _lastError;
  String? get lastError => _lastError;

  /// Raw text of the last MQTT message received, before parsing.
  String? _lastRawMessage;
  String? get lastRawMessage => _lastRawMessage;

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
    // Private LAN broker — allow when connecting by IP literal (cert SAN
    // is *.solaireresort.com and won't match an IP) or a pinned CA chain.
    // Parameter must be Object: MqttServerClient internally casts this to
    // bool Function(Object) — a bool Function(X509Certificate) fails that cast
    // and the connect attempt dies with a CastError.
    // TODO(security): pin the CA chain once deployment settles.
    client.onBadCertificate = (Object cert) => true;
    _client = client;

    try {
      if (config.username.isEmpty) {
        await client.connect();
      } else {
        await client.connect(config.username, config.password);
      }
    } catch (e) {
      _connected = false;
      _lastError = e.toString();
      _connectionController.add(false);
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _connected = false;
      _lastError =
          'broker refused: ${client.connectionStatus?.returnCode ?? 'unknown'}';
      _connectionController.add(false);
      return;
    }

    _lastError = null;

    client.subscribe(config.receiveTopic, MqttQos.atMostOnce);
    _subscription = client.updates?.listen(_onUpdates);
  }

  /// Publish a test inquiry on `solaire/{floor}/{machine}/balanceinquiry/inquire`
  /// — used by the settings screen to verify the full round trip. The backend
  /// replies on the subscribed receive topic like a real swipe.
  /// Returns false when the client is not connected.
  bool publishTestInquiry(MqttConfig config, String cardId) {
    final client = _client;
    if (client?.connectionStatus?.state != MqttConnectionState.connected) {
      return false;
    }
    final payload = jsonEncode({
      'request_id': 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      'card_id': cardId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final builder = MqttClientPayloadBuilder()..addString(payload);
    client!.publishMessage(
      'solaire/${config.floorId}/${config.machineId}/balanceinquiry/inquire',
      MqttQos.atMostOnce,
      builder.payload!,
    );
    return true;
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final text =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      _lastRawMessage = text;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          // NestJS ClientMqtt.emit() wraps payloads as {pattern, data} —
          // unwrap the envelope when present.
          final payload = decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : decoded;
          _controller
              .add(BalanceInquiry.fromJson(payload, rawPayload: text));
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
