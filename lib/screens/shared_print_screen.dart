import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_render_maintained/pdf_render.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

class SharedPrintScreen extends StatefulWidget {
  const SharedPrintScreen({
    super.key,
    required this.paths,
    required this.preferences,
  });

  final List<String> paths;
  final SharedPreferences preferences;

  @override
  State<SharedPrintScreen> createState() => _SharedPrintScreenState();
}

class _SharedPrintScreenState extends State<SharedPrintScreen> {
  bool _printing = false;
  String _status = 'راجع الملفات ثم اضغط طباعة';

  String _name(String path) => path.split(Platform.pathSeparator).last;

  Future<void> _print() async {
    if (_printing) return;
    final printerId = widget.preferences.getString('saved_printer_id');
    if (printerId == null || printerId.isEmpty) {
      setState(() => _status = 'اختر طابعة واحفظها أولاً من شاشة اختيار الطابعة');
      return;
    }

    setState(() {
      _printing = true;
      _status = 'جارٍ الاتصال بالطابعة...';
    });

    final manager = PrinterManager();
    var connected = false;
    try {
      final devices = await manager.scanPrinters(
        timeout: const Duration(seconds: 8),
      );
      PrinterDevice? target;
      for (final device in devices) {
        final id = device is BlePrinterDevice
            ? device.deviceId
            : device is BluetoothPrinterDevice
                ? device.address
                : device is UsbPrinterDevice
                    ? device.identifier
                    : device is NetworkPrinterDevice
                        ? '${device.host}:${device.port}'
                        : device.name;
        if (id == printerId) {
          target = device;
          break;
        }
      }
      if (target == null) {
        throw Exception('لم يتم العثور على الطابعة المحفوظة. أعد البحث واختر الطابعة مرة أخرى.');
      }

      await manager.connect(target);
      connected = true;
      final width = widget.preferences.getString('paper_width') ?? '80';
      final paper = width == '58' ? PaperSize.mm58 : PaperSize.mm80;
      final maxWidth = width == '58' ? 384 : 576;
      var printedFiles = 0;

      for (final path in widget.paths) {
        final file = File(path);
        if (!await file.exists()) {
          throw Exception('الملف غير متاح: ${_name(path)}');
        }
        final lower = path.toLowerCase();
        final ticket = await Ticket.create(paper);
        ticket.textRaster(_name(path),
            textDirection: TextDirection.rtl, align: PrintAlign.center);
        ticket.separator();

        if (lower.endsWith('.pdf')) {
          final document = await PdfDocument.openFile(path);
          try {
            for (var pageNumber = 1;
                pageNumber <= document.pageCount;
                pageNumber++) {
              final page = await document.getPage(pageNumber);
              try {
                final pageWidth = maxWidth;
                final pageHeight =
                    (page.height * pageWidth / page.width).round().clamp(1, 12000);
                final rendered = await page.render(
                  width: pageWidth,
                  height: pageHeight,
                );
                final decoded = img.decodeImage(rendered.bytes);
                if (decoded == null) {
                  throw Exception('تعذر تحويل صفحة $pageNumber من ملف PDF');
                }
                ticket.imageRaster(decoded,
                    align: PrintAlign.center, maxWidth: maxWidth);
              } finally {
                await page.close();
              }
            }
          } finally {
            await document.close();
          }
        } else if (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.bmp')) {
          final decoded = img.decodeImage(await file.readAsBytes());
          if (decoded == null) {
            throw Exception('صيغة الصورة غير مدعومة: ${_name(path)}');
          }
          ticket.imageRaster(decoded,
              align: PrintAlign.center, maxWidth: maxWidth);
        } else if (lower.endsWith('.txt')) {
          final text = await file.readAsString();
          for (final line in text.split(RegExp(r'\\r?\\n'))) {
            await ticket.textRaster(line,
                textDirection: TextDirection.rtl, align: PrintAlign.right);
          }
        } else {
          throw Exception('نوع الملف غير مدعوم حالياً: ${_name(path)}');
        }

        ticket.emptyLines(3);
        ticket.cut();
        await manager.printTicket(ticket);
        printedFiles++;
        if (mounted) {
          setState(() => _status = 'تم إرسال $printedFiles من ${widget.paths.length} ملف للطابعة');
        }
      }
      if (mounted) {
        setState(() => _status = 'اكتملت عملية إرسال الملفات للطابعة');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'فشلت الطباعة: $error');
    } finally {
      if (connected) {
        try {
          await manager.disconnect();
        } catch (_) {}
      }
      await manager.dispose();
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة الملفات للطباعة')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: widget.paths.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final path = widget.paths[index];
                  final lower = path.toLowerCase();
                  final icon = lower.endsWith('.pdf')
                      ? Icons.picture_as_pdf
                      : lower.endsWith('.txt')
                          ? Icons.description
                          : Icons.image;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(icon)),
                      title: Text(_name(path),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(path,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: Icon(_printing ? Icons.hourglass_top : Icons.print),
                    label: Text(_printing ? 'جارٍ الطباعة...' : 'طباعة الملفات'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
