import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const HoseinApp());
const yellow = Color(0xFFFFD400);
const black = Color(0xFF171717);

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'خدمات فنی حسین',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: yellow),
      scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      appBarTheme: const AppBarTheme(backgroundColor: black, foregroundColor: yellow),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
    ),
    home: const LoginPage(),
  );
}

// داده‌ها فعلاً موقت هستند و با بستن برنامه پاک می‌شوند.
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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } else {
      setState(() => error = 'رمز نادرست است. رمز نمونه: 1234');
    }
  }
  @override
  void dispose() { pin.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: black,
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 132, height: 132,
              decoration: BoxDecoration(color: yellow, borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/logo.jpg', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.build, size: 72, color: black)),
            ),
            const SizedBox(height: 18),
            const Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 28),
            TextField(
              controller: pin, keyboardType: TextInputType.number, obscureText: true,
              textAlign: TextAlign.center, textInputAction: TextInputAction.done,
              onSubmitted: (_) => login(),
              decoration: const InputDecoration(labelText: 'رمز ورود آزمایشی'),
            ),
            if (error.isNotEmpty) Padding(
              padding: const EdgeInsets.all(8),
              child: Text(error, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: black, padding: const EdgeInsets.all(15)),
              onPressed: login, child: const Text('ورود به برنامه'))),
            const SizedBox(height: 12),
            const Text('رمز ورود نمونه: 1234', style: TextStyle(color: Colors.white54)),
          ]),
        ),
      )),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  int tab = 0;
  final titles = const ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها'];
  final productKey = GlobalKey<SimpleListPageState>();
  final customerKey = GlobalKey<SimpleListPageState>();
  final repairKey = GlobalKey<SimpleListPageState>();
  final salesKey = GlobalKey<SimpleListPageState>();

  Future<bool> onBack() async {
    if (tab != 0) { setState(() => tab = 0); return false; }
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
        title: const Text('خروج از برنامه'),
        content: const Text('آیا می‌خواهید از برنامه خارج شوید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ادامه کار')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
        ],
      )),
    );
    return exit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      Dashboard(onSelect: (i) => setState(() => tab = i)),
      SimpleListPage(key: productKey, title: 'کالا', data: DemoStore.products,
        fields: const ['نام کالا','گروه اصلی','زیرگروه','کد کالا','موجودی','قیمت خرید','قیمت فروش','وضعیت کالا (نو/دسته‌دوم/خراب)'],
        primary: 'نام کالا', isProduct: true),
      SimpleListPage(key: customerKey, title: 'مشتری', data: DemoStore.customers,
        fields: const ['نام مشتری','شماره تماس','آدرس','توضیحات'], primary: 'نام مشتری'),
      SimpleListPage(key: repairKey, title: 'پذیرش تعمیر', data: DemoStore.repairs,
        fields: const ['نام مشتری','نوع دستگاه','شرح عیب','اجرت','وضعیت تعمیر'], primary: 'نوع دستگاه'),
      SimpleListPage(key: salesKey, title: 'فاکتور فروش', data: DemoStore.sales,
        fields: const ['نام مشتری','شرح کالا/خدمت','تعداد','مبلغ کل','تخفیف','مبلغ دریافتی'], primary: 'نام مشتری'),
      const ReportsPage(),
    ];
    return WillPopScope(
      onWillPop: onBack,
      child: Directionality(textDirection: TextDirection.rtl, child: Scaffold(
        appBar: AppBar(title: Text(titles[tab]), actions: [
          IconButton(tooltip: 'خروج از حساب', icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()))),
        ]),
        body: IndexedStack(index: tab, children: pages),
        drawer: Drawer(child: ListView(children: [
          const DrawerHeader(decoration: BoxDecoration(color: black), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Icon(Icons.handyman, color: yellow, size: 44), SizedBox(height: 8),
              Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
              Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
            ])),
          for (int i=0; i<titles.length; i++)
            ListTile(title: Text(titles[i]), selected: tab == i,
              leading: Icon([Icons.dashboard,Icons.inventory_2,Icons.people,Icons.build,Icons.receipt_long,Icons.bar_chart][i]),
              onTap: () { setState(() => tab=i); Navigator.pop(context); }),
        ])),
        floatingActionButton: tab >= 1 && tab <= 4 ? FloatingActionButton(
          backgroundColor: yellow, foregroundColor: black,
          onPressed: () {
            switch(tab) {
              case 1: productKey.currentState?.addItem(); break;
              case 2: customerKey.currentState?.addItem(); break;
              case 3: repairKey.currentState?.addItem(); break;
              case 4: salesKey.currentState?.addItem(); break;
            }
          }, child: const Icon(Icons.add),
        ) : null,
      )),
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
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: black, borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          CircleAvatar(backgroundColor: yellow, child: Icon(Icons.handyman, color: black)),
          SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontWeight: FontWeight.bold, fontSize: 20)),
            Text('مدیریت فروشگاه و تعمیرات', style: TextStyle(color: Colors.white70)),
          ])),
        ])),
      const SizedBox(height: 16),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, childAspectRatio: 1.45, crossAxisSpacing: 10, mainAxisSpacing: 10,
        children: [for (final s in stats) Card(child: Padding(padding: const EdgeInsets.all(10),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(s.$3, color: Colors.amber.shade800, size: 28), const SizedBox(height: 6),
            Text(s.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(s.$1, textAlign: TextAlign.center),
          ])))]),
      const SizedBox(height: 12),
      const Text('دسترسی سریع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      for (final e in [(1,'ثبت کالا'),(2,'ثبت مشتری'),(3,'پذیرش تعمیر'),(4,'صدور فاکتور')])
        Card(child: ListTile(title: Text(e.$2), trailing: const Icon(Icons.chevron_left), onTap: () => onSelect(e.$1))),
      const Padding(padding: EdgeInsets.all(8), child: Text(
        'توجه: این نسخه آزمایشی است؛ اطلاعات فعلاً فقط در حافظه برنامه نگهداری می‌شوند و با بستن برنامه پاک می‌شوند.',
        style: TextStyle(color: Colors.red, fontSize: 12))),
    ]);
  }
}

class SimpleListPage extends StatefulWidget {
  final String title;
  final List<Map<String,String>> data;
  final List<String> fields;
  final String primary;
  final bool isProduct;
  const SimpleListPage({super.key, required this.title, required this.data,
    required this.fields, required this.primary, this.isProduct = false});
  @override
  SimpleListPageState createState() => SimpleListPageState();
}

class SimpleListPageState extends State<SimpleListPage> {
  final picker = ImagePicker();

  Future<void> addItem() async {
    final ctrls = widget.fields.map((_) => TextEditingController()).toList();
    final nodes = widget.fields.map((_) => FocusNode()).toList();
    final post = TextEditingController();
    final freight = TextEditingController();
    final other = TextEditingController();
    final vatRate = TextEditingController(text: '0');
    bool vatEnabled = false;
    String? imagePath;

    double n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
    double base() => (ctrls.length > 5 ? n(ctrls[5]) : 0) + n(post) + n(freight) + n(other);
    double vat() => vatEnabled ? base() * n(vatRate) / 100 : 0;
    double total() => base() + vat();
    String money(double x) => x.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

    Future<void> selectImage(StateSetter refresh) async {
      try {
        final picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        final path = '${Directory.systemTemp.path}/hosein_${DateTime.now().microsecondsSinceEpoch}.jpg';
        final compressed = await FlutterImageCompress.compressAndGetFile(
          picked.path, path, quality: 60, minWidth: 800, minHeight: 800, format: CompressFormat.jpeg);
        refresh(() => imagePath = compressed?.path ?? picked.path);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انتخاب یا فشرده‌سازی عکس انجام نشد.')));
      }
    }

    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, refresh) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFFFAF1E2),
          title: Text('ثبت ${widget.title}'),
          content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              for (int i=0; i<widget.fields.length; i++)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
                  controller: ctrls[i], focusNode: nodes[i],
                  textInputAction: i == widget.fields.length-1 && !widget.isProduct
                    ? TextInputAction.done : TextInputAction.next,
                  keyboardType: _type(widget.fields[i]),
                  onSubmitted: (_) {
                    if (i < nodes.length-1) FocusScope.of(context).requestFocus(nodes[i+1]);
                    else FocusScope.of(context).unfocus();
                  },
                  decoration: InputDecoration(labelText: widget.fields[i]))),
              if (widget.isProduct) ...[
                const Divider(height: 24),
                const Align(alignment: Alignment.centerRight, child: Text('هزینه‌های تهیه کالا',
                  style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),
                _moneyField(post, 'هزینه پست', () => refresh(() {})),
                _moneyField(freight, 'هزینه حمل و باربری', () => refresh(() {})),
                _moneyField(other, 'سایر هزینه‌ها', () => refresh(() {})),
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: vatEnabled,
                  title: const Text('این کالا مشمول ارزش افزوده است'),
                  onChanged: (v) => refresh(() => vatEnabled = v ?? false)),
                if (vatEnabled) _moneyField(vatRate, 'درصد ارزش افزوده (قابل تنظیم)', () => refresh(() {})),
                Container(width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('هزینه‌های جانبی: ${money(n(post)+n(freight)+n(other))} تومان'),
                    if (vatEnabled) Text('ارزش افزوده: ${money(vat())} تومان'),
                    const Divider(),
                    Text('بهای تمام‌شده: ${money(total())} تومان',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ])),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () => selectImage(refresh),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(imagePath == null ? 'انتخاب عکس کالا (فشرده‌سازی خودکار)' : 'تغییر عکس کالا')),
                if (imagePath != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(imagePath!), width: 130, height: 110, fit: BoxFit.cover)),
                  TextButton.icon(onPressed: () => refresh(() => imagePath = null),
                    icon: const Icon(Icons.delete_outline), label: const Text('حذف عکس')),
                ],
              ],
            ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(onPressed: () {
              final item = <String,String>{};
              for (int i=0; i<widget.fields.length; i++) item[widget.fields[i]] = ctrls[i].text.trim();
              if (widget.isProduct) {
                item['هزینه پست'] = post.text;
                item['هزینه حمل و باربری'] = freight.text;
                item['سایر هزینه‌ها'] = other.text;
                item['مشمول ارزش افزوده'] = vatEnabled ? 'بله' : 'خیر';
                item['درصد ارزش افزوده'] = vatEnabled ? vatRate.text : '0';
                item['مبلغ ارزش افزوده'] = vat().toStringAsFixed(0);
                item['بهای تمام‌شده'] = total().toStringAsFixed(0);
                item['مسیر عکس'] = imagePath ?? '';
              }
              if (item.values.any((v) => v.trim().isNotEmpty)) setState(() => widget.data.add(item));
              Navigator.pop(dialogContext);
            }, child: const Text('ذخیره')),
          ],
        ),
      )),
    );

    for (final c in [...ctrls, post, freight, other, vatRate]) { c.dispose(); }
    for (final f in nodes) { f.dispose(); }
  }

  TextInputType _type(String label) {
    if (['قیمت','موجودی','تعداد','اجرت','مبلغ','تخفیف','تماس'].any(label.contains)) return TextInputType.number;
    return TextInputType.text;
  }

  Widget _moneyField(TextEditingController c, String label, VoidCallback changed) =>
    Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
      controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next, onChanged: (_) => changed(),
      decoration: InputDecoration(labelText: label)));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
      onPressed: addItem, icon: const Icon(Icons.add), label: const Text('ثبت مورد جدید'))),
    const SizedBox(height: 8),
    if (widget.data.isEmpty) const Padding(padding: EdgeInsets.all(28),
      child: Center(child: Text('هنوز اطلاعاتی ثبت نشده است'))),
    for (final item in widget.data.reversed)
      Card(child: ListTile(
        leading: item['مسیر عکس']?.isNotEmpty == true
          ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(
              File(item['مسیر عکس']!), width: 44, height: 44, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2)))
          : const CircleAvatar(child: Icon(Icons.description)),
        title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
        subtitle: Text(item.entries.where((e) => e.value.isNotEmpty && e.key != 'مسیر عکس')
          .take(5).map((e) => '${e.key}: ${e.value}').join(' • ')),
      )),
  ]);
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('گزارش‌های اولیه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
    for (final r in [
      'تعداد کالاهای ثبت‌شده: ${DemoStore.products.length}',
      'تعداد مشتریان: ${DemoStore.customers.length}',
      'تعداد پذیرش‌های تعمیر: ${DemoStore.repairs.length}',
      'تعداد فاکتورهای فروش: ${DemoStore.sales.length}',
    ]) Card(child: ListTile(leading: const Icon(Icons.analytics_outlined), title: Text(r))),
    const Text('ذخیره دائمی، گزارش کامل، خروجی PDF/Excel و همگام‌سازی در مراحل بعدی اضافه می‌شوند.',
      style: TextStyle(color: Colors.black54)),
  ]);
}
