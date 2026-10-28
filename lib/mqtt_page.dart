import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const kelompok = 'kel4'; // Sesuaikan kelompokmu
const host = 'broker.emqx.io';
const tSensor = 'polnes/oit/$kelompok/sensor';
const tLed = 'polnes/oit/$kelompok/led';
const tLedState = 'polnes/oit/$kelompok/led/state';
const tStatus = 'polnes/oit/$kelompok/status';

class MqttPage extends StatefulWidget {
  const MqttPage({super.key});

  @override
  State<MqttPage> createState() => _MqttPageState();
}

class _MqttPageState extends State<MqttPage> {
  MqttServerClient? _client;
  bool _connected = false;
  bool _isOn = false;
  double _pwmValue = 128;
  String _suhu = '-', _hum = '-', _device = 'tidak diketahui';
  String _status = 'Belum terhubung';
  String _latMqtt = '-';
  Completer<void>? _waiting;
  String _expect = '';

  Future<void> _connect() async {
    final id = 'flutter-$kelompok-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient(host, id);
    c.port = 1883;
    c.keepAlivePeriod = 30;
    c.logging(on: false);
    c.onDisconnected = _onDisconnected;
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(id).startClean();

    setState(() => _status = 'Menghubungkan...');
    try {
      await c.connect();
    } catch (e) {
      c.disconnect();
      setState(() => _status = 'Gagal: $e');
      return;
    }

    c.updates!.listen(_onMessage);
    c.subscribe(tSensor, MqttQos.atMostOnce);
    c.subscribe(tLedState, MqttQos.atLeastOnce);
    c.subscribe(tStatus, MqttQos.atLeastOnce);

    setState(() {
      _client = c;
      _connected = true;
      _status = 'Terhubung ke $host';
    });
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    final msg = events[0].payload as MqttPublishMessage;
    final text = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
    final topic = events[0].topic;
    if (!mounted) return;

    setState(() {
      if (topic == tSensor) {
        final j = jsonDecode(text);
        _suhu = j['suhu'].toString();
        _hum = j['hum'].toString();
      } else if (topic == tLedState) {
        int val = int.tryParse(text) ?? 0;
        _pwmValue = val > 0 ? val.toDouble() : _pwmValue;
        _isOn = val > 0;
        if (_waiting != null && !_waiting!.isCompleted && text == _expect) {
          _waiting!.complete();
        }
      } else if (topic == tStatus) {
        _device = text;
      }
    });
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      _connected = false;
      _status = 'Terputus dari broker';
    });
  }

  void _publish(String topic, String text) {
    final b = MqttClientPayloadBuilder()..addString(text);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  Future<void> _togglePower(bool value) async {
    setState(() => _isOn = value);
    int target = _isOn ? _pwmValue.toInt() : 0;
    _publish(tLed, target.toString());
  }

  Future<void> _updateSlider(double val) async {
    setState(() {
      _pwmValue = val;
      _isOn = val > 0;
    });
    _publish(tLed, val.toInt().toString());
  }

  Future<void> _measureLatency() async {
    final samples = <int>[];
    for (var i = 0; i < 10; i++) {
      final cmd = (i.isEven ? '150' : '0');
      _expect = cmd;
      _waiting = Completer<void>();
      final sw = Stopwatch()..start();
      _publish(tLed, cmd);
      try {
        await _waiting!.future.timeout(const Duration(seconds: 3));
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      } on TimeoutException {}
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (samples.isEmpty) {
      setState(() => _latMqtt = 'tidak ada respons');
      return;
    }

    final avg = samples.reduce((a, b) => a + b) / samples.length;
    setState(() => _latMqtt = 'rata-rata ${avg.toStringAsFixed(0)} ms (min ${samples.reduce(min)}, maks ${samples.reduce(max)}, ${samples.length}/10 sampel)');
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MQTT Controller & PWM', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 12),
          if (!_connected)
            ElevatedButton(onPressed: _connect, child: const Text('Hubungkan'))
          else ...[
            Text('Perangkat: $_device'),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Status LED (On/Off)'),
              value: _isOn,
              onChanged: _togglePower,
            ),
            const SizedBox(height: 8),
            Text('Kecerahan PWM: ${_isOn ? _pwmValue.toInt() : 0}'),
            Slider(
              value: _isOn ? _pwmValue : 0,
              min: 0,
              max: 255,
              divisions: 255,
              label: (_isOn ? _pwmValue : 0).toInt().toString(),
              onChanged: (val) {
                if (_isOn) setState(() => _pwmValue = val);
              },
              onChangeEnd: (val) {
                if (_isOn) _updateSlider(val);
              },
            ),
            Card(
              child: ListTile(
                title: Text('Suhu: $_suhu °C'),
                subtitle: Text('Kelembapan: $_hum %'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _measureLatency, child: const Text('Ukur latensi (10 kali)')),
            Text('Latensi MQTT: $_latMqtt'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _client?.disconnect(),
              child: const Text('Putuskan'),
            ),
          ],
        ],
      ),
    );
  }
}