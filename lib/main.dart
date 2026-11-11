import 'package:flutter/material.dart';

void main() => runApp(const HoseinApp());

const yellow = Color(0xFFFFD400);
const black = Color(0xFF171717);

class HoseinApp extends StatelessWidget {
  const HoseinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'خدمات فنی حسین',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: yellow, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        appBarTheme: const AppBarTheme(backgroundColor: black, foregroundColor: yellow),
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
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(labelText: 'رمز ورود آزمایشی', hintText: 'رمز را وارد کنید'),
                  ),
                  if (error.isNotEmpty) Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(error, style: const TextStyle(color: Colors.redAccent)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: black, padding: const EdgeInsets.all(15)),
                    onPressed: () {
                      if (pin.text == '1234') {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
                      } else {
                        setState(() => error = 'رمز آزمایشی نادرست است. رمز نمونه: 1234');
                      }
                    },
                    child: const Text('ورود به برنامه'),
                  )),
                  const SizedBox(height: 12),
                  const Text('رمز ورود نمونه: 1234', style: TextStyle(color: Colors.white54)),
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
  final titles = ['داشبورد', 'انبار کالا', 'مشتریان', 'تعمیرات', 'فروش و فاکتور', 'گزارش‌ها'];
  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(onSelect: (i) => setState(() => tab = i)),
      ProductPage(onChanged: () => setState(() {})),
      CustomerPage(onChanged: () => setState(() {})),
      RepairPage(onChanged: () => setState(() {})),
      SalesPage(onChanged: () => setState(() {})),
      const ReportsPage(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(titles[tab]), actions: [
          IconButton(tooltip: 'خروج', onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())), icon: const Icon(Icons.logout))
        ]),
        body: pages[tab],
        drawer: Drawer(
          child: ListView(children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: black),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(Icons.handyman, color: yellow, size: 44),
                SizedBox(height: 8),
                Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('نسخه آزمایشی', style: TextStyle(color: Colors.white70)),
              ]),
            ),
            for (int i = 0; i < titles.length; i++)
              ListTile(leading: Icon([Icons.dashboard, Icons.inventory_2, Icons.people, Icons.build, Icons.receipt_long, Icons.bar_chart][i]),
                title: Text(titles[i]), selected: tab == i, onTap: () { setState(() => tab = i); Navigator.pop(context); }),
          ]),
        ),
        floatingActionButton: tab == 1 || tab == 2 || tab == 3 || tab == 4
          ? FloatingActionButton(backgroundColor: yellow, foregroundColor: black, onPressed: () => (pages[tab] as dynamic).addItem(context), child: const Icon(Icons.add))
          : null,
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
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: black, borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          CircleAvatar(backgroundColor: yellow, child: Icon(Icons.handyman, color: black)),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('خدمات فنی حسین', style: TextStyle(color: yellow, fontWeight: FontWeight.bold, fontSize: 20)),
            Text('مدیریت فروشگاه و تعمیرات', style: TextStyle(color: Colors.white70)),
          ]))
        ]),
      ),
      const SizedBox(height: 16),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 10, mainAxisSpacing: 10,
        children: [for (final s in stats) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(s.$3, color: Colors.amber.shade800, size: 28), const SizedBox(height: 6),
          Text(s.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(s.$1, textAlign: TextAlign.center),
        ])))]),
      const SizedBox(height: 12),
      const Text('دسترسی سریع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      for (final e in [(1,'ثبت کالا'),(2,'ثبت مشتری'),(3,'پذیرش تعمیر'),(4,'صدور فاکتور')])
        Card(child: ListTile(title: Text(e.$2), trailing: const Icon(Icons.chevron_left), onTap: () => onSelect(e.$1))),
      const Padding(padding: EdgeInsets.all(8), child: Text('توجه: این نسخه نمونه است؛ اطلاعات فعلاً فقط در حافظه برنامه نگهداری می‌شوند و با بستن برنامه پاک می‌شوند.', style: TextStyle(color: Colors.red, fontSize: 12))),
    ]);
  }
}

class SimpleListPage extends StatefulWidget {
  final String title;
  final List<Map<String, String>> data;
  final List<String> fields;
  final String primary;
  const SimpleListPage({super.key, required this.title, required this.data, required this.fields, required this.primary});
  @override
  State<SimpleListPage> createState() => _SimpleListPageState();
  void addItem(BuildContext context) {}
}

class _SimpleListPageState extends State<SimpleListPage> {
  void addItem() {
    final ctrls = widget.fields.map((_) => TextEditingController()).toList();
    showDialog(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: Text('ثبت ${widget.title}'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(children: [
        for (int i=0;i<widget.fields.length;i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ctrls[i], decoration: InputDecoration(labelText: widget.fields[i])))
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: () {
          final item = <String,String>{};
          for (int i=0;i<widget.fields.length;i++) { item[widget.fields[i]] = ctrls[i].text; }
          if (ctrls.any((c) => c.text.trim().isNotEmpty)) setState(() => widget.data.add(item));
          Navigator.pop(context);
        }, child: const Text('ذخیره'))
      ],
    )));
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
    Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: addItem, icon: const Icon(Icons.add), label: const Text('ثبت مورد جدید'))),
    const SizedBox(height: 8),
    if (widget.data.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('هنوز اطلاعاتی ثبت نشده است'))),
    for (final item in widget.data.reversed)
      Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.description)), title: Text(item[widget.primary]?.isNotEmpty == true ? item[widget.primary]! : 'بدون عنوان'),
        subtitle: Text(item.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' • ')))),
  ]);
}

class ProductPage extends StatelessWidget {
  final VoidCallback onChanged;
  const ProductPage({super.key, required this.onChanged});
  void addItem(BuildContext context) {}
  @override
  Widget build(BuildContext context) => SimpleListPage(title: 'کالا', data: DemoStore.products, fields: const ['نام کالا','گروه اصلی','زیرگروه','کد کالا','موجودی','قیمت خرید','قیمت فروش'], primary: 'نام کالا');
}
class CustomerPage extends StatelessWidget {
  final VoidCallback onChanged;
  const CustomerPage({super.key, required this.onChanged});
  void addItem(BuildContext context) {}
  @override
  Widget build(BuildContext context) => SimpleListPage(title: 'مشتری', data: DemoStore.customers, fields: const ['نام مشتری','شماره تماس','آدرس','توضیحات'], primary: 'نام مشتری');
}
class RepairPage extends StatelessWidget {
  final VoidCallback onChanged;
  const RepairPage({super.key, required this.onChanged});
  void addItem(BuildContext context) {}
  @override
  Widget build(BuildContext context) => SimpleListPage(title: 'پذیرش تعمیر', data: DemoStore.repairs, fields: const ['نام مشتری','نوع دستگاه','شرح عیب','اجرت','وضعیت تعمیر'], primary: 'نوع دستگاه');
}
class SalesPage extends StatelessWidget {
  final VoidCallback onChanged;
  const SalesPage({super.key, required this.onChanged});
  void addItem(BuildContext context) {}
  @override
  Widget build(BuildContext context) => SimpleListPage(title: 'فاکتور فروش', data: DemoStore.sales, fields: const ['نام مشتری','شرح کالا/خدمت','تعداد','مبلغ کل','تخفیف','مبلغ دریافتی'], primary: 'نام مشتری');
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
    const Text('نمودارها، خروجی PDF/Excel/عکس، ذخیره دائمی و همگام‌سازی در نسخه‌های بعدی اضافه می‌شوند.', style: TextStyle(color: Colors.black54)),
  ]);
}
