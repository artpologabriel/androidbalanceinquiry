import 'package:shared_preferences/shared_preferences.dart';

/// MQTT connection + topic configuration for the balance display.
///
/// Defaults come from `--dart-define` at build time; an operator can override
/// them at runtime on the settings screen (persisted via SharedPreferences).
class MqttConfig {
  const MqttConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.floorId,
    required this.machineId,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String floorId;
  final String machineId;

  /// Topic this display subscribes to (backend publishes balance responses here).
  String get receiveTopic =>
      'solaire/$floorId/$machineId/balanceinquiry/receive';

  // Defaults mirror the ESP32 swipe station (swipe.ino): production broker is
  // mqtt.solaireresort.com:8883 (TLS).
  // TODO(security): broker credentials are baked in for now — move to
  // per-device settings or --dart-define before this repo stays public.
  static const defaults = MqttConfig(
    host: String.fromEnvironment('MQTT_HOST',
        defaultValue: 'mqtt.solaireresort.com'),
    port: int.fromEnvironment('MQTT_PORT', defaultValue: 8883),
    username: String.fromEnvironment('MQTT_USERNAME',
        defaultValue: 'mqttuser'),
    password: String.fromEnvironment('MQTT_PASSWORD',
        defaultValue: 'password1234'),
    floorId: String.fromEnvironment('FLOOR_ID', defaultValue: 'floor1'),
    machineId: String.fromEnvironment('MACHINE_ID', defaultValue: 'MACH-101'),
  );

  static const _keyHost = 'mqtt_host';
  static const _keyPort = 'mqtt_port';
  static const _keyUsername = 'mqtt_username';
  static const _keyPassword = 'mqtt_password';
  static const _keyFloorId = 'floor_id';
  static const _keyMachineId = 'machine_id';

  /// Saved overrides merged over the dart-define defaults.
  static Future<MqttConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MqttConfig(
      host: prefs.getString(_keyHost) ?? defaults.host,
      port: prefs.getInt(_keyPort) ?? defaults.port,
      username: prefs.getString(_keyUsername) ?? defaults.username,
      password: prefs.getString(_keyPassword) ?? defaults.password,
      floorId: prefs.getString(_keyFloorId) ?? defaults.floorId,
      machineId: prefs.getString(_keyMachineId) ?? defaults.machineId,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, host);
    await prefs.setInt(_keyPort, port);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyPassword, password);
    await prefs.setString(_keyFloorId, floorId);
    await prefs.setString(_keyMachineId, machineId);
  }

  MqttConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? floorId,
    String? machineId,
  }) {
    return MqttConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      floorId: floorId ?? this.floorId,
      machineId: machineId ?? this.machineId,
    );
  }
}
