import 'package:material_ui/material_ui.dart';
import 'backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.service});

  final BackupService service;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } catch (error) {
      if (mounted) setState(() => _message = 'عملیات انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بازیابی نسخه پشتیبان'),
        content: const Text(
          'با بازیابی، اطلاعات فعلی این گوشی با اطلاعات داخل فایل پشتیبان جایگزین می‌شود. '
          'قبل از ادامه، یک نسخه پشتیبان از وضعیت فعلی ساخته و نزد خود نگه دارید. ادامه می‌دهید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بله، بازیابی کن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(widget.service.restoreFromFile, 'بازیابی انجام شد. برای تازه‌سازی همه بخش‌ها برنامه را یک‌بار ببندید و دوباره باز کنید.');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.backup, size: 38),
                  SizedBox(height: 8),
                  Text('پشتیبان‌گیری اطلاعات فروشگاه',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('یک کپی کامل از پایگاه داده محلی شامل کالاها، مشتریان، اسناد خرید و فروش، '
                      'دفتر حسابداری، چک‌ها و گزارش‌ها تهیه می‌شود.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(
              () async { await widget.service.shareLatestBackup(); },
              'نسخه پشتیبان آماده و برای اشتراک‌گذاری ارسال شد.',
            ),
            icon: const Icon(Icons.share),
            label: const Text('تهیه و ارسال نسخه پشتیبان'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('بازیابی از فایل پشتیبان'),
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text('نکات مهم', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('• فایل پشتیبان را در گوشی دیگر، حافظه جانبی یا فضای ابری شخصی خود نگهداری کنید.'),
          const Text('• بازیابی، اطلاعات فعلی برنامه را جایگزین می‌کند؛ فایل پشتیبان را فقط از منبع مطمئن انتخاب کنید.'),
          const Text('• این مرحله پشتیبان محلی/فایلی است و همگام‌سازی خودکار Google Drive یا چند گوشی هنوز فعال نیست.'),
        ],
      ),
    );
  }
}
