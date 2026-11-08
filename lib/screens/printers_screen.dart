import 'dart:async';
import 'dart:convert';

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
  String? _busyDevice;

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

  Future<bool> _requestPermissions() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return permissions.values.every((status) => status.isGranted || status.isLimited);
  }

  Future<void> _scan() async {
    if (!await _requestPermissions()) {
      _message('يرجى السماح بصلاحيات Bluetooth والموقع للبحث عن الأجهزة');
      return;
    }
    try {
      if (!await FlutterBluePlus.isSupported) {
        _message('هذا الجهاز لا يدعم Bluetooth LE');
        return;
      }
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _message('شغّل Bluetooth ثم حاول مرة أخرى');
        return;
      }
      setState(() {
        _results.clear();
        _scanning = true;
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(seconds: 12));
    } catch (error) {
      _message('تعذر البحث: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _select(ScanResult result) async {
    final device = result.device;
    final name = device.platformName.isEmpty ? device.remoteId.str : device.platformName;
    await widget.preferences.setString('saved_printer_id', device.remoteId.str);
    await widget.preferences.setString('saved_printer_name', name);
    if (!mounted) return;
    _message('تم حفظ $name كطابعة مفضلة');
    Navigator.pop(context);
  }

  Future<void> _connectAndTest(ScanResult result) async {
    final device = result.device;
    setState(() => _busyDevice = device.remoteId.str);
    try {
      if (!await _requestPermissions()) {
        _message('يلزم السماح بصلاحية الاتصال بالبلوتوث');
        return;
      }
      await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      final services = await device.discoverServices();
      BluetoothCharacteristic? writable;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            writable = characteristic;
            break;
          }
        }
        if (writable != null) break;
      }
      if (writable == null) {
        _message('تم الاتصال، لكن لم أجد منفذ كتابة متوافقًا. قد تكون الطابعة Bluetooth Classic وليست BLE.');
        return;
      }

      final name = device.platformName.isEmpty ? device.remoteId.str : device.platformName;
      await widget.preferences.setString('saved_printer_id', device.remoteId.str);
      await widget.preferences.setString('saved_printer_name', name);

      final bytes = <int>[
        0x1B, 0x40, // ESC @ initialize
        ...ascii.encode('PrintEasy\n'),
        ...ascii.encode('Bluetooth test print\n'),
        ...ascii.encode('------------------------------\n'),
        0x0A, 0x0A, 0x0A,
      ];
      final withoutResponse = writable.properties.writeWithoutResponse &&
          !writable.properties.write;
      const chunkSize = 180;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
        await writable.write(
          bytes.sublist(offset, end),
          withoutResponse: withoutResponse,
          timeout: 10,
        );
      }
      _message('تم إرسال اختبار الطباعة إلى $name');
    } catch (error) {
      _message('تعذر الاتصال أو الطباعة: $error');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
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
                    Text(_scanning ? 'جارٍ البحث عن الأجهزة القريبة' : 'اضغط على بحث لاكتشاف الطابعات BLE',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('ملاحظة: بعض الطابعات الحرارية تعمل عبر Bluetooth Classic ولا تظهر في بحث BLE.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final result = _results[index];
                final device = result.device;
                final name = device.platformName.isEmpty ? 'جهاز غير معروف' : device.platformName;
                final busy = _busyDevice == device.remoteId.str;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.print)),
                          title: Text(name),
                          subtitle: Text(device.remoteId.str),
                          trailing: Text('${result.rssi} dBm',
                              style: const TextStyle(color: Colors.black54)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy ? null : () => _select(result),
                                  child: const Text('حفظ الطابعة'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: busy ? null : () => _connectAndTest(result),
                                  icon: Icon(busy ? Icons.hourglass_top : Icons.print),
                                  label: Text(busy ? 'جارٍ الاتصال' : 'اختبار الطباعة'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
