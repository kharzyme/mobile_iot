import 'package:flutter/material.dart';
import 'ble_page.dart';
import 'mqtt_page.dart';

void main() => runApp(const MaterialApp(
      title: 'Mobile IoT Lab',
      home: Home(),
    ));

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile IoT Lab')),
      body: SafeArea(
        child: IndexedStack(
          index: _i,
          children: const [BlePage(), MqttPage()],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _i,
        onTap: (v) => setState(() => _i = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'BLE'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud), label: 'MQTT'),
        ],
      ),
    );
  }
}