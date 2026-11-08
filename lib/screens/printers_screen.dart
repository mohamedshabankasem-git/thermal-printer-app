import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key, required this.preferences});
  final SharedPreferences preferences;

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(results);
      });
    });
  }

  Future<void> _scan() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (permissions.values.any((status) => status.isDenied || status.isPermanentlyDenied)) {
      _message('يرجى السماح بصلاحيات Bluetooth من إعدادات الهاتف');
      return;
    }

    try {
      if (await FlutterBluePlus.isSupported == false) {
        _message('هذا الجهاز لا يدعم Bluetooth LE');
        return;
      }
      setState(() {
        _results.clear();
        _scanning = true;
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(seconds: 12));
    } catch (error) {
      _message('تعذر البحث عن الطابعات: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _select(ScanResult result) async {
    final device = result.device;
    await widget.preferences.setString('saved_printer_id', device.remoteId.str);
    await widget.preferences.setString(
      'saved_printer_name',
      device.platformName.isEmpty ? device.remoteId.str : device.platformName,
    );
    if (!mounted) return;
    _message('تم حفظ الطابعة. الاتصال والطباعة سيتم استكمالهما في المرحلة التالية.');
    Navigator.pop(context);
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار الطابعة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _scan,
        icon: Icon(_scanning ? Icons.hourglass_top : Icons.bluetooth_searching),
        label: Text(_scanning ? 'جارٍ البحث...' : 'بحث عن الطابعات'),
      ),
      body: _results.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bluetooth, size: 64, color: Colors.blueGrey),
                    const SizedBox(height: 14),
                    Text(_scanning ? 'جارٍ البحث عن الأجهزة القريبة' : 'اضغط على بحث لاكتشاف الطابعات',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final result = _results[index];
                final name = result.device.platformName.isEmpty
                    ? 'جهاز غير معروف'
                    : result.device.platformName;
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.print)),
                    title: Text(name),
                    subtitle: Text(result.device.remoteId.str),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _select(result),
                  ),
                );
              },
            ),
    );
  }
}
