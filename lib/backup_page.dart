import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'backup_service.dart';
import 'backup_storage.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.service,
    this.initialMessage,
    this.onRestored,
  });

  final BackupService service;
  final String? initialMessage;
  final Future<void> Function()? onRestored;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _message;
  List<File> _backups = <File>[];
  List<ExternalBackupFile> _externalBackups = <ExternalBackupFile>[];
  BackupFolder? _backupFolder;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _refreshBackups();
  }

  Future<void> _refreshBackups() async {
    try {
      final files = await widget.service.listBackups();
      final folder = await widget.service.getBackupLocation();
      final externalFiles = await widget.service.listExternalBackups();
      final warning = widget.service.lastBackupWarning;
      if (mounted) {
        setState(() {
          _backups = files;
          _backupFolder = folder;
          _externalBackups = externalFiles;
          if (warning != null) {
            _message = warning;
          }
        });
      }
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
      if (mounted) {
        setState(() => _message = widget.service.lastBackupWarning ?? success);
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'عملیات انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runRestore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final restored = await widget.service.restoreFromFile();
      if (!restored) {
        if (mounted) {
          setState(() => _message = 'بازیابی لغو شد؛ اطلاعات فعلی بدون تغییر باقی ماند.');
        }
        return;
      }
      await widget.onRestored?.call();
      await _refreshBackups();
      if (mounted) {
        setState(() => _message = widget.service.lastBackupWarning ??
            (widget.onRestored == null
                ? 'بازیابی انجام شد. برای تازه‌سازی همه بخش‌ها برنامه را یک‌بار ببندید و دوباره باز کنید.'
                : 'بازیابی انجام شد و اطلاعات برنامه تازه‌سازی شد.'));
      }
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
    await _runRestore();
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


  Future<void> _chooseBackupFolder() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final selected = await widget.service.chooseBackupLocation();
      await _refreshBackups();
      if (mounted) {
        setState(() {
          _message = selected == null
              ? 'انتخاب پوشه لغو شد.'
              : 'محل ذخیرهٔ بیرونی روی «${selected.name}» تنظیم شد. نسخهٔ داخلی نیز حفظ می‌شود.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'انتخاب پوشه انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearBackupFolder() async {
    await _run(
      widget.service.clearBackupLocation,
      'ذخیرهٔ بیرونی غیرفعال شد؛ پشتیبان‌گیری داخلی ادامه دارد.',
    );
  }

  Future<void> _restoreExternal(ExternalBackupFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بازیابی نسخهٔ بیرونی'),
        content: Text(
          'اطلاعات فعلی این گوشی با فایل «${file.name}» جایگزین می‌شود. '
          'پیش از ادامه، نسخهٔ اضطراری از اطلاعات فعلی ساخته خواهد شد. ادامه می‌دهید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('بازیابی'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () async {
        await widget.service.restoreFromExternalBackup(file);
        await widget.onRestored?.call();
      },
      widget.onRestored == null
          ? 'بازیابی از پوشهٔ بیرونی انجام شد. برای تازه‌سازی همه بخش‌ها برنامه را یک‌بار ببندید و دوباره باز کنید.'
          : 'بازیابی از پوشهٔ بیرونی انجام شد و اطلاعات برنامه تازه‌سازی شد.',
    );
  }

  Future<void> _deleteExternal(ExternalBackupFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نسخهٔ بیرونی'),
        content: Text('فایل «${file.name}» از پوشهٔ انتخاب‌شده حذف شود؟'),
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
      () => widget.service.deleteExternalBackup(file),
      'نسخهٔ بیرونی حذف شد.',
    );
  }

  String _externalFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} مگابایت';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} کیلوبایت';
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('محل ذخیرهٔ بیرونی',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_backupFolder == null
                      ? 'پوشه‌ای انتخاب نشده؛ نسخه‌ها فقط در حافظهٔ داخلی برنامه نگهداری می‌شوند.'
                      : 'پوشهٔ انتخاب‌شده: ${_backupFolder!.name}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _chooseBackupFolder,
                        icon: const Icon(Icons.folder_open),
                        label: Text(_backupFolder == null ? 'انتخاب پوشه' : 'تغییر پوشه'),
                      ),
                      if (_backupFolder != null)
                        TextButton.icon(
                          onPressed: _busy ? null : _clearBackupFolder,
                          icon: const Icon(Icons.folder_off_outlined),
                          label: const Text('غیرفعال کردن'),
                        ),
                    ],
                  ),
                  const Text(
                    'نسخه ابتدا در حافظهٔ داخلی و پس از اعتبارسنجی در پوشهٔ انتخابی کپی می‌شود؛ '
                    'قطع دسترسی به پوشه، نسخهٔ داخلی را حذف نمی‌کند.',
                    style: TextStyle(fontSize: 12),
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

          if (_backupFolder != null) ...[
            const SizedBox(height: 18),
            Text(
              'نسخه‌های پوشهٔ بیرونی (${_externalBackups.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_externalBackups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('نسخه‌ای در پوشهٔ بیرونی پیدا نشد یا دسترسی آن در دسترس نیست.'),
                ),
              ),
            for (final file in _externalBackups)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: Text(file.name),
                  subtitle: Text(_externalFileSize(file.length)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'restore') _restoreExternal(file);
                      if (value == 'delete') _deleteExternal(file);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'restore', child: Text('بازیابی این نسخه')),
                      PopupMenuItem(value: 'delete', child: Text('حذف از پوشه')),
                    ],
                  ),
                ),
              ),
          ],

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
