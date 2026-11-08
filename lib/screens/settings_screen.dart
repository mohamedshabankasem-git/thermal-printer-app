import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.preferences});
  final SharedPreferences preferences;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _paperWidth;

  @override
  void initState() {
    super.initState();
    _paperWidth = widget.preferences.getString('paper_width') ?? '80';
  }

  Future<void> _setPaperWidth(String? value) async {
    if (value == null) return;
    await widget.preferences.setString('paper_width', value);
    setState(() => _paperWidth = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مقاس الورق',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '58', label: Text('58 مم')),
                      ButtonSegment(value: '80', label: Text('80 مم')),
                    ],
                    selected: {_paperWidth},
                    onSelectionChanged: (value) => _setPaperWidth(value.first),
                  ),
                ],
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.bluetooth),
              title: Text('نوع الاتصال'),
              subtitle: Text('BLE وBluetooth Classic وUSB والشبكة (حسب الطابعة)'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('PrintEasy'),
              subtitle: Text('الإصدار 1.0.0 — نسخة تأسيسية'),
            ),
          ),
        ],
      ),
    );
  }
}
