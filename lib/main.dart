import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const HoseinApp());

const yellow = Color(0xFFFFD400);
const black = Color(0xFF171717);
const cream = Color(0xFFFAF1E2);

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'خدمات فنی حسین',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: yellow),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: black,
          foregroundColor: yellow,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// توجه: اطلاعات کالاها و مشتریان در این نسخه هنوز موقت هستند.
class DemoStore {
  static final products = <Map<String, String>>[];
  static final customers = <Map<String, String>>[];
  static final repairs = <Map<String, String>>[];
  static final sales = <Map<String, String>>[];
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final pin = TextEditingController();
  String error = '';

  void login() {
    if (pin.text == '1234') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      setState(() => error = 'رمز نادرست است. رمز نمونه: 1234');
    }
  }

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: black,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: yellow,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/logo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.build, size: 72, color: black),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'خدمات فنی حسین',
                    style: TextStyle(
                      color: yellow,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'نسخه آزمایشی',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => login(),
                    decoration: const InputDecoration(
                      labelText: 'رمز ورود آزمایشی',
                      hintText: 'رمز را وارد کنید',
                    ),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: yellow,
                        foregroundColor: black,
                        padding: const EdgeInsets.all(15),
                      ),
                      onPressed: login,
                      child: const Text('ورود به برنامه'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'رمز ورود نمونه: 1234',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  final titles = const [
    'داشبورد',
    'انبار کالا',
    'مشتریان',
    'تعمیرات',
    'فروش و فاکتور',
    'گزارش‌ها',
  ];

  final productKey = GlobalKey<SimpleListPageState>();
  final customerKey = GlobalKey<SimpleListPageState>();
  final repairKey = GlobalKey<SimpleListPageState>();
  final salesKey = GlobalKey<SimpleListPageState>();

  Future<bool> onBack() async {
    if (tab != 0) {
      setState(() => tab = 0);
      return false;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خروج از برنامه'),
          content: const Text('آیا می‌خواهید از برنامه خارج شوید؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ادامه کار'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج'),
            ),
          ],
        ),
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Dashboard(onSelect: (i) => setState(() => tab = i)),
      SimpleListPage(
        key: productKey,
        title: 'کالا',
        data: DemoStore.products,
        fields: const [
          'نام کالا',
          'گروه اصلی',
          'زیرگروه',
          'کد کالا',
          'موجودی',
          'قیمت خرید',
          'قیمت فروش',
          'وضعیت کالا (نو/دسته‌دوم/خراب)',
        ],
        primary: 'نام کالا',
        isProduct: true,
        onChanged: () => setState(() {}),
      ),
      SimpleListPage(
        key: customerKey,
        title: 'مشتری',
        data: DemoStore.customers,
        fields: const ['نام مشتری', 'شماره تماس', 'آدرس', 'توضیحات'],
        primary: 'نام مشتری',
        onChanged: () => setState(() {}),
      ),
      SimpleListPage(
        key: repairKey,
        title: 'پذیرش تعمیر',
        data: DemoStore.repairs,
        fields: const [
          'نام مشتری',
          'نوع دستگاه',
          'شرح عیب',
          'اجرت',
          'وضعیت تعمیر',
        ],
        primary: 'نوع دستگاه',
        onChanged: () => setState(() {}),
      ),
      SimpleListPage(
        key: salesKey,
        title: 'فاکتور فروش',
        data: DemoStore.sales,
        fields: const [
          'نام مشتری',
          'شرح کالا/خدمت',
          'تعداد',
          'مبلغ کل',
          'تخفیف',
          'مبلغ دریافتی',
        ],
        primary: 'نام مشتری',
        onChanged: () => setState(() {}),
      ),
      const ReportsPage(),
    ];

    return WillPopScope(
      onWillPop: onBack,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(titles[tab]),
            actions: [
              IconButton(
                tooltip: 'خروج از حساب',
                icon: const Icon(Icons.logout),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
              ),
            ],
          ),
          body: IndexedStack(index: tab, children: pages),
          drawer: Drawer(
            child: ListView(
              children: [
                const DrawerHeader(
                  decoration: BoxDecoration(color: black),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.handyman, color: yellow, size: 44),
                      SizedBox(height: 8),
                      Text(
                        'خدمات فنی حسین',
                        style: TextStyle(
                          color: yellow,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'نسخه آزمایشی',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                for (int i = 0; i < titles.length; i++)
                  ListTile(
                    title: Text(titles[i]),
                    selected: tab == i,
                    leading: Icon([
                      Icons.dashboard,
                      Icons.inventory_2,
                      Icons.people,
                      Icons.build,
                      Icons.receipt_long,
                      Icons.bar_chart,
                    ][i]),
                    onTap: () {
                      setState(() => tab = i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          floatingActionButton: tab >= 1 && tab <= 4
              ? FloatingActionButton(
                  backgroundColor: yellow,
                  foregroundColor: black,
                  onPressed: () {
                    switch (tab) {
                      case 1:
                        productKey.currentState?.addItem();
                        break;
                      case 2:
                        customerKey.currentState?.addItem();
                        break;
                      case 3:
                        repairKey.currentState?.addItem();
                        break;
                      case 4:
                        salesKey.currentState?.addItem();
                        break;
                    }
                  },
                  child: const Icon(Icons.add),
                )
              : null,
        ),
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final ValueChanged<int> onSelect;

  const Dashboard({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('کالاهای ثبت‌شده', DemoStore.products.length.toString(), Icons.inventory_2),
      ('مشتریان', DemoStore.customers.length.toString(), Icons.people),
      ('پذیرش تعمیرات', DemoStore.repairs.length.toString(), Icons.build),
      ('فاکتورهای فروش', DemoStore.sales.length.toString(), Icons.receipt),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: black,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                backgroundColor: yellow,
                child: Icon(Icons.handyman, color: black),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'خدمات فنی حسین',
                      style: TextStyle(
                        color: yellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'مدیریت فروشگاه و تعمیرات',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.45,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            for (final s in stats)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s.$3, color: Colors.amber.shade800, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        s.$2,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(s.$1, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'دسترسی سریع',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        for (final e in [
          (1, 'ثبت کالا'),
          (2, 'ثبت مشتری'),
          (3, 'پذیرش تعمیر'),
          (4, 'صدور فاکتور'),
        ])
          Card(
            child: ListTile(
              title: Text(e.$2),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => onSelect(e.$1),
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'توجه: این نسخه آزمایشی است؛ اطلاعات فعلاً فقط در حافظه برنامه نگهداری می‌شوند و با بستن برنامه پاک می‌شوند.',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class SimpleListPage extends StatefulWidget {
  final String title;
  final List<Map<String, String>> data;
  final List<String> fields;
  final String primary;
  final bool isProduct;
  final VoidCallback? onChanged;

  const SimpleListPage({
    super.key,
    required this.title,
    required this.data,
    required this.fields,
    required this.primary,
    this.isProduct = false,
    this.onChanged,
  });

  @override
  SimpleListPageState createState() => SimpleListPageState();
}

class SimpleListPageState extends State<SimpleListPage> {
  final ImagePicker picker = ImagePicker();

  double _number(TextEditingController controller) {
    final value = controller.text.replaceAll(',', '').trim();
    return double.tryParse(value) ?? 0;
  }

  String _money(double value) {
    return value.round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }

  TextInputType _keyboardType(String label) {
    const numericWords = [
      'قیمت',
      'موجودی',
      'تعداد',
      'اجرت',
      'مبلغ',
      'تخفیف',
      'تماس',
      'هزینه',
      'درصد',
      'کد کالا',
    ];

    if (numericWords.any(label.contains)) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.text;
  }

  Future<String?> _pickAndCompressImage() async {
    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return null;

      // عکس فشرده‌شده در پوشه دائمی برنامه ذخیره می‌شود، نه پوشه موقت.
      final appDirectory = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory('${appDirectory.path}/product_images');
      if (!await imageDirectory.exists()) {
        await imageDirectory.create(recursive: true);
      }

      final outputPath =
          '${imageDirectory.path}/product_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        outputPath,
        quality: 55,
        minWidth: 700,
        minHeight: 700,
        format: CompressFormat.jpeg,
      );

      if (compressed != null) return compressed.path;

      final copied = await File(picked.path).copy(outputPath);
      return copied.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انتخاب یا فشرده‌سازی عکس انجام نشد.')),
        );
      }
      return null;
    }
  }

  Future<void> addItem() async {
    final controllers = <String, TextEditingController>{};
    final focusNodes = <String, FocusNode>{};

    for (final field in widget.fields) {
      controllers[field] = TextEditingController();
      focusNodes[field] = FocusNode();
    }

    const postKey = 'هزینه پست';
    const freightKey = 'هزینه حمل و باربری';
    const otherKey = 'سایر هزینه‌ها';
    const vatRateKey = 'درصد ارزش افزوده';

    if (widget.isProduct) {
      for (final key in [postKey, freightKey, otherKey, vatRateKey]) {
        controllers[key] = TextEditingController(text: key == vatRateKey ? '0' : '');
        focusNodes[key] = FocusNode();
      }
    }

    bool vatEnabled = false;
    String? imagePath;

    double purchasePrice() {
      return _number(controllers['قیمت خرید'] ?? TextEditingController());
    }

    double extraCosts() {
      return _number(controllers[postKey]!) +
          _number(controllers[freightKey]!) +
          _number(controllers[otherKey]!);
    }

    double vatAmount() {
      if (!vatEnabled) return 0;
      return (purchasePrice() + extraCosts()) *
          _number(controllers[vatRateKey]!) /
          100;
    }

    double finalCost() => purchasePrice() + extraCosts() + vatAmount();

    List<String> visibleFields() {
      final result = [...widget.fields];
      if (widget.isProduct) {
        result.addAll([postKey, freightKey, otherKey]);
        if (vatEnabled) result.add(vatRateKey);
      }
      return result;
    }

    Future<void> saveItem(BuildContext dialogContext) async {
      final item = <String, String>{};

      for (final field in widget.fields) {
        item[field] = controllers[field]!.text.trim();
      }

      if (widget.isProduct) {
        item[postKey] = controllers[postKey]!.text.trim();
        item[freightKey] = controllers[freightKey]!.text.trim();
        item[otherKey] = controllers[otherKey]!.text.trim();
        item['مشمول ارزش افزوده'] = vatEnabled ? 'بله' : 'خیر';
        item[vatRateKey] =
            vatEnabled ? controllers[vatRateKey]!.text.trim() : '0';
        item['مبلغ ارزش افزوده'] = vatAmount().toStringAsFixed(0);
        item['هزینه‌های جانبی'] = extraCosts().toStringAsFixed(0);
        item['بهای تمام‌شده'] = finalCost().toStringAsFixed(0);
        item['مسیر عکس'] = imagePath ?? '';
      }

      if (item.values.any((value) => value.trim().isNotEmpty)) {
        setState(() => widget.data.add(item));
        widget.onChanged?.call();
      }

      Navigator.pop(dialogContext);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refresh) {
            final fieldsNow = visibleFields();

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: cream,
                title: Text('ثبت ${widget.title}'),
                content: SizedBox(
                  width: 430,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < fieldsNow.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextField(
                              controller: controllers[fieldsNow[i]],
                              focusNode: focusNodes[fieldsNow[i]],
                              keyboardType: _keyboardType(fieldsNow[i]),
                              textInputAction: i == fieldsNow.length - 1
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              onChanged: (_) {
                                if (widget.isProduct) refresh(() {});
                              },
                              onSubmitted: (_) {
                                final currentIndex =
                                    fieldsNow.indexOf(fieldsNow[i]);
                                if (currentIndex < fieldsNow.length - 1) {
                                  FocusScope.of(context).requestFocus(
                                    focusNodes[fieldsNow[currentIndex + 1]],
                                  );
                                } else {
                                  FocusScope.of(context).unfocus();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: fieldsNow[i],
                              ),
                            ),
                          ),
                        if (widget.isProduct) ...[
                          const Divider(height: 24),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'مالیات و بهای تمام‌شده کالا',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: vatEnabled,
                            title: const Text('این کالا مشمول ارزش افزوده است'),
                            onChanged: (value) {
                              refresh(() => vatEnabled = value ?? false);
                            },
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'قیمت خرید: ${_money(purchasePrice())} تومان',
                                ),
                                Text(
                                  'هزینه‌های جانبی: ${_money(extraCosts())} تومان',
                                ),
                                if (vatEnabled)
                                  Text(
                                    'ارزش افزوده: ${_money(vatAmount())} تومان',
                                  ),
                                const Divider(),
                                Text(
                                  'بهای تمام‌شده: ${_money(finalCost())} تومان',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final path = await _pickAndCompressImage();
                              if (path != null) {
                                refresh(() => imagePath = path);
                              }
                            },
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              imagePath == null
                                  ? 'انتخاب عکس کالا (فشرده‌سازی خودکار)'
                                  : 'تغییر عکس کالا',
                            ),
                          ),
                          if (imagePath != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(imagePath!),
                                width: 130,
                                height: 110,
                                fit: BoxFit.cover,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  refresh(() => imagePath = null),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف عکس'),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('انصراف'),
                  ),
                  FilledButton(
                    onPressed: () => saveItem(dialogContext),
                    child: const Text('ذخیره'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final node in focusNodes.values) {
      node.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: addItem,
            icon: const Icon(Icons.add),
            label: const Text('ثبت مورد جدید'),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.data.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: Text('هنوز اطلاعاتی ثبت نشده است')),
          ),
        for (final item in widget.data.reversed)
          Card(
            child: ListTile(
              leading: item['مسیر عکس']?.isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(item['مسیر عکس']!),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.inventory_2),
                      ),
                    )
                  : const CircleAvatar(
                      child: Icon(Icons.description),
                    ),
              title: Text(
                item[widget.primary]?.isNotEmpty == true
                    ? item[widget.primary]!
                    : 'بدون عنوان',
              ),
              subtitle: Text(
                item.entries
                    .where(
                      (entry) =>
                          entry.value.isNotEmpty && entry.key != 'مسیر عکس',
                    )
                    .take(6)
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(' • '),
              ),
            ),
          ),
      ],
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'گزارش‌های اولیه',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        for (final report in [
          'تعداد کالاهای ثبت‌شده: ${DemoStore.products.length}',
          'تعداد مشتریان: ${DemoStore.customers.length}',
          'تعداد پذیرش‌های تعمیر: ${DemoStore.repairs.length}',
          'تعداد فاکتورهای فروش: ${DemoStore.sales.length}',
        ])
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: Text(report),
            ),
          ),
        const Text(
          'ذخیره دائمی اطلاعات، گزارش کامل، خروجی PDF/Excel و همگام‌سازی در مراحل بعدی اضافه می‌شوند.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
