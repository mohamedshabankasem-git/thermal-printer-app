import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key, required this.preferences});
  final SharedPreferences preferences;

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  final PrinterManager _manager = PrinterManager();
  List<PrinterDevice> _devices = [];
  bool _scanning = false;
  String? _busyDevice;

  @override
  void dispose() {
    unawaited(_manager.dispose());
    super.dispose();
  }

  String _detail(PrinterDevice device) {
    if (device is BlePrinterDevice) return 'BLE • ${device.deviceId}';
    if (device is BluetoothPrinterDevice) return 'Bluetooth Classic • ${device.address}';
    if (device is UsbPrinterDevice) return 'USB • ${device.identifier}';
    if (device is NetworkPrinterDevice) return 'شبكة • ${device.host}:${device.port}';
    return device.connectionType.name;
  }

  String _stableId(PrinterDevice device) {
    if (device is BlePrinterDevice) return device.deviceId;
    if (device is BluetoothPrinterDevice) return device.address;
    if (device is UsbPrinterDevice) return device.identifier;
    if (device is NetworkPrinterDevice) return '${device.host}:${device.port}';
    return device.name;
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });
    try {
      final found = await _manager.scanPrinters(
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() => _devices = found);
      if (found.isEmpty) _message('لم يتم العثور على طابعات. تأكد من تشغيل الطابعة ومنح صلاحيات البلوتوث.');
    } catch (error) {
      _message('تعذر البحث عن الطابعات: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _select(PrinterDevice device) async {
    await widget.preferences.setString('saved_printer_id', _stableId(device));
    await widget.preferences.setString('saved_printer_name', device.name);
    await widget.preferences.setString('saved_printer_type', device.connectionType.name);
    if (!mounted) return;
    _message('تم حفظ الطابعة ${device.name}');
    Navigator.pop(context);
  }

  Future<void> _connectAndTest(PrinterDevice device) async {
    final id = _stableId(device);
    setState(() => _busyDevice = id);
    try {
      await _manager.connect(device);
      final width = widget.preferences.getString('paper_width') ?? '80';
      final paper = width == '58' ? PaperSize.mm58 : PaperSize.mm80;
      final ticket = await Ticket.create(paper);
      ticket.text('PrintEasy', align: PrintAlign.center,
          style: const PrintTextStyle(bold: true, height: TextSize.size2, width: TextSize.size2));
      ticket.separator(char: '=');
      await ticket.textRaster('اختبار الطباعة العربية', textDirection: TextDirection.rtl, align: PrintAlign.center);
      await ticket.textRaster('تم الاتصال بالطابعة بنجاح', textDirection: TextDirection.rtl, align: PrintAlign.center);
      ticket.emptyLines(3);
      ticket.cut();
      await _manager.printTicket(ticket);
      await _manager.disconnect();
      await _select(device);
      _message('تم إرسال صفحة الاختبار إلى ${device.name}');
    } catch (error) {
      try {
        await _manager.disconnect();
      } catch (_) {}
      _message('تعذر الاتصال أو الطباعة: $error');
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  IconData _icon(PrinterDevice device) {
    if (device is BlePrinterDevice) return Icons.bluetooth;
    if (device is BluetoothPrinterDevice) return Icons.bluetooth_audio;
    if (device is UsbPrinterDevice) return Icons.usb;
    if (device is NetworkPrinterDevice) return Icons.wifi;
    return Icons.print;
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
      body: _devices.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.print, size: 64, color: Colors.blueGrey),
                    const SizedBox(height: 14),
                    Text(_scanning ? 'جارٍ البحث عن الطابعات القريبة' : 'ابحث لاكتشاف الطابعات المتاحة',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('يدعم التطبيق BLE وBluetooth Classic وUSB والشبكة حسب نوع الطابعة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final device = _devices[index];
                final busy = _busyDevice == _stableId(device);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(child: Icon(_icon(device))),
                          title: Text(device.name.isEmpty ? 'طابعة بدون اسم' : device.name),
                          subtitle: Text(_detail(device)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy ? null : () => _select(device),
                                  child: const Text('حفظ الطابعة'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: busy ? null : () => _connectAndTest(device),
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
