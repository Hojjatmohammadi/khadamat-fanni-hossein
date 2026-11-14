import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.service,
    this.initialMessage,
  });

  final BackupService service;
  final String? initialMessage;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _message;
  List<File> _backups = <File>[];

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _refreshBackups();
  }

  Future<void> _refreshBackups() async {
    try {
      final files = await widget.service.listBackups();
      if (mounted) setState(() => _backups = files);
    } catch (error) {
      if (mounted) setState(() => _message = 'خواندن فهرست پشتیبان‌ها ناموفق بود: $error');
    }
  }

  Future<void> _run(
    Future<void> Function() action,
    String success,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _refreshBackups();
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
          'قبل از ادامه، از اطلاعات فعلی نسخه پشتیبان بگیرید. ادامه می‌دهید؟',
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
    await _run(
      widget.service.restoreFromFile,
      'بازیابی انجام شد. برای تازه‌سازی همه بخش‌ها برنامه را یک‌بار ببندید و دوباره باز کنید.',
    );
  }

  Future<void> _deleteBackup(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نسخه پشتیبان'),
        content: Text('این فایل حذف شود؟\n${file.uri.pathSegments.last}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.service.deleteBackup(file),
      'نسخه پشتیبان حذف شد.',
    );
  }

  String _fileSize(File file) {
    final bytes = file.lengthSync();
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} کیلوبایت';
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
                  Text(
                    'پشتیبان‌گیری اطلاعات فروشگاه',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'یک کپی از پایگاه داده شامل کالاها، مشتریان، اسناد خرید و فروش، '
                    'دفتر حسابداری، چک‌ها و گزارش‌ها تهیه می‌شود.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'پشتیبان روزانه هنگام باز شدن برنامه به‌صورت خودکار ساخته می‌شود. '
                'این کار در پس‌زمینه و هنگام بسته بودن برنامه اجرا نمی‌شود.',
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () async => widget.service.shareLatestBackup(),
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
          if (_busy)
            const Padding(
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
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'نسخه‌های ذخیره‌شده',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              IconButton(
                tooltip: 'تازه‌سازی',
                onPressed: _busy ? null : _refreshBackups,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_backups.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('هنوز نسخه پشتیبانی در حافظه داخلی برنامه وجود ندارد.'),
              ),
            ),
          for (final file in _backups)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  file.uri.pathSegments.last.contains('-daily-')
                      ? 'پشتیبان روزانه'
                      : 'پشتیبان دستی',
                ),
                subtitle: Text(
                  '${file.uri.pathSegments.last}\n${_fileSize(file)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'حذف نسخه پشتیبان',
                  onPressed: _busy ? null : () => _deleteBackup(file),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text('نکات مهم', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('• بهتر است یک نسخه را بیرون از گوشی، مانند حافظه جانبی یا فضای ابری شخصی، نگه دارید.'),
          const Text('• هنگام بازیابی، اطلاعات فعلی برنامه جایگزین می‌شود.'),
          const Text('• حداکثر ۳۰ نسخه پشتیبان آخر در حافظه داخلی برنامه نگهداری می‌شود.'),
          const Text('• این مرحله همگام‌سازی خودکار Google Drive یا چند گوشی را فعال نمی‌کند.'),
        ],
      ),
    );
  }
}
