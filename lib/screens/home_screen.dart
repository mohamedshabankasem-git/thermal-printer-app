import 'package:flutter/material.dart';
import 'package:file_share_intent/file_share_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printers_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String get savedPrinter =>
      widget.preferences.getString('saved_printer_name') ?? 'لم يتم اختيار طابعة';

  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedMedia,
      onError: (Object error) {
        if (mounted) _showShareMessage('تعذر استقبال الملف: $error');
      },
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((media) {
      if (media.isNotEmpty) _handleSharedMedia(media);
      ReceiveSharingIntent.instance.reset();
    }).catchError((Object error) {
      if (mounted) _showShareMessage('تعذر قراءة المشاركة: $error');
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> media) {
    if (!mounted || media.isEmpty) return;
    final paths = media.map((item) => item.path).toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('محتوى مستلم للمشاركة'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: paths
                  .map((path) => ListTile(
                        leading: const Icon(Icons.insert_drive_file),
                        title: Text(path.split('/').last,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(path,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showShareMessage('تم استلام ${paths.length} ملف. سيتم ربطه بمحرك الطباعة في المرحلة التالية.');
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    });
  }

  void _showShareMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <_HomeAction>[
      _HomeAction('اختيار الطابعة', Icons.bluetooth_searching,
          const Color(0xFFE8F2FC), () => _openPrinters()),
      _HomeAction('طباعة مستند', Icons.print, const Color(0xFFEAF6EF),
          () => _showComingSoon('الطباعة')),
      _HomeAction('سجل الطباعة', Icons.history, const Color(0xFFFFF3E5),
          () => _showComingSoon('سجل الطباعة')),
      _HomeAction('الإعدادات', Icons.settings, const Color(0xFFF0EBFA),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => SettingsScreen(preferences: widget.preferences)))),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('PrintEasy | طباعة سريعة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 25,
                        backgroundColor: Color(0xFFE8F2FC),
                        child: Icon(Icons.print, color: Color(0xFF1769AA), size: 27),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الطابعة الحالية',
                                style: TextStyle(color: Colors.black54)),
                            const SizedBox(height: 5),
                            Text(savedPrinter,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'تغيير الطابعة',
                        onPressed: _openPrinters,
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text('الخدمات', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.12,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: item.onTap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 27,
                              backgroundColor: item.color,
                              child: Icon(item.icon, size: 28,
                                  color: const Color(0xFF1769AA)),
                            ),
                            const SizedBox(height: 12),
                            Text(item.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Text('اتصال Bluetooth • طباعة حرارية',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _openPrinters() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PrintersScreen(preferences: widget.preferences),
    )).then((_) => setState(() {}));
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: سيتم تفعيلها في المرحلة التالية')),
    );
  }
}

class _HomeAction {
  const _HomeAction(this.title, this.icon, this.color, this.onTap);
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
