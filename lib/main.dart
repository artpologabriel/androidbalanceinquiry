import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'mqtt_service.dart';

/// Seconds the balance screen stays up after a message before returning to idle.
const idleTimeout = Duration(seconds: 15);

// Palette lifted from the new-lcd-pattern design: deep navy, neon blue, gold.
const _bgTop = Color(0xFF0A1633);
const _gold = Color(0xFFE8B84B);
const _blue = Color(0xFF4DA6FF);
const _blueDim = Color(0xFF1E3A66);
const _error = Color(0xFFE05252);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Kiosk display — hide status + nav bars (swipe briefly reveals, auto-hides).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const BalanceDisplayApp());
}

class BalanceDisplayApp extends StatelessWidget {
  const BalanceDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solaire Balance Display',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const BalanceDisplayPage(),
    );
  }
}

class BalanceDisplayPage extends StatefulWidget {
  const BalanceDisplayPage({super.key});

  @override
  State<BalanceDisplayPage> createState() => _BalanceDisplayPageState();
}

class _BalanceDisplayPageState extends State<BalanceDisplayPage> {
  final _mqtt = BalanceMqttService();
  StreamSubscription<BalanceInquiry>? _messagesSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _idleTimer;

  MqttConfig _config = MqttConfig.defaults;
  BalanceInquiry? _inquiry;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final config = await MqttConfig.load();
    if (!mounted) return;
    setState(() => _config = config);
    _messagesSub = _mqtt.messages.listen(_onInquiry);
    _connectionSub =
        _mqtt.connectionState.listen((v) => setState(() => _connected = v));
    await _mqtt.connect(config);
  }

  void _onInquiry(BalanceInquiry inquiry) {
    setState(() => _inquiry = inquiry);
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (mounted) setState(() => _inquiry = null);
    });
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<MqttConfig>(
      MaterialPageRoute(builder: (_) => SettingsPage(config: _config)),
    );
    if (saved == null || !mounted) return;
    setState(() => _config = saved);
    await saved.save();
    await _mqtt.connect(saved);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _messagesSub?.cancel();
    _connectionSub?.cancel();
    unawaited(_mqtt.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inquiry = _inquiry;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/lcd_bg_portrait.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              inquiry == null
                  ? const _IdleScreen()
                  : _ActiveScreen(inquiry: inquiry),
              Positioned(
                top: 4,
                right: 8,
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: _connected ? Colors.greenAccent : _error,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.settings,
                          color: Colors.white38, size: 20),
                      onPressed: _openSettings,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen saver — shown whenever no balance message is being displayed.
/// The background artwork already carries the Solaire branding.
class _IdleScreen extends StatelessWidget {
  const _IdleScreen();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

/// Active screen — shown for [idleTimeout] after a balanceinquiry/receive
/// message arrives.
class _ActiveScreen extends StatelessWidget {
  const _ActiveScreen({required this.inquiry});

  final BalanceInquiry inquiry;

  static String _fmt(int value) {
    final s = value.toString();
    return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = inquiry.isOk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Column(
        children: [
          // Clearance for the SOLAIRE logo baked into the background artwork.
          const SizedBox(height: 72),
          if (!ok)
            const Text(
              'CARD NOT RECOGNIZED',
              style: TextStyle(
                color: _error,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
              ),
            ),
          if (inquiry.patronName != null)
            Text(
              inquiry.patronName!.toUpperCase(),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          const SizedBox(height: 8),
          _HighlightBox(
            label: 'E-TICKETS WON',
            value: _fmt(inquiry.ticketsWon),
            icon: Icons.confirmation_num_outlined,
          ),
          const Spacer(),
          _BalanceCard(
            label: 'FUN CREDIT BALANCE',
            value: _fmt(inquiry.points),
            icon: Icons.paid_outlined,
            accent: _gold,
          ),
          const SizedBox(height: 12),
          _BalanceCard(
            label: 'E-TICKETS BALANCE',
            value: _fmt(inquiry.tickets),
            icon: Icons.confirmation_num_outlined,
            accent: _blue,
          ),
          const SizedBox(height: 12),
          const Text(
            'THANK YOU',
            style: TextStyle(
              color: _blue,
              fontSize: 18,
              letterSpacing: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightBox extends StatelessWidget {
  const _HighlightBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 48),
      decoration: BoxDecoration(
        color: _blueDim.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue, width: 2),
        boxShadow: [
          BoxShadow(color: _blue.withValues(alpha: 0.35), blurRadius: 24),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 72,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: _blue, size: 64),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: _bgTop,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 40),
              const SizedBox(width: 12),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Operator-facing settings for broker + topic coordinates.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.config});

  final MqttConfig config;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _floorId;
  late final TextEditingController _machineId;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.config.host);
    _port = TextEditingController(text: '${widget.config.port}');
    _username = TextEditingController(text: widget.config.username);
    _password = TextEditingController(text: widget.config.password);
    _floorId = TextEditingController(text: widget.config.floorId);
    _machineId = TextEditingController(text: widget.config.machineId);
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password, _floorId, _machineId]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_port.text.trim()) ?? widget.config.port;
    Navigator.of(context).pop(
      widget.config.copyWith(
        host: _host.text.trim(),
        port: port,
        username: _username.text.trim(),
        password: _password.text,
        floorId: _floorId.text.trim(),
        machineId: _machineId.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _field(_host, 'MQTT host'),
          _field(_port, 'MQTT port', numeric: true),
          _field(_username, 'Username (optional)'),
          _field(_password, 'Password (optional)', obscure: true),
          _field(_floorId, 'Floor ID'),
          _field(_machineId, 'Machine ID'),
          const SizedBox(height: 8),
          Text(
            'Subscribed topic: solaire/${_floorId.text}/${_machineId.text}'
            '/balanceinquiry/receive',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
