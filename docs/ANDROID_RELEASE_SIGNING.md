# امضای پایدار نسخه‌های اندروید

این مخزن عمومی است؛ فایل keystore و رمزهای آن را هرگز در Git یا داخل کد قرار ندهید.

## ساخت کلید انتشار

روی رایانه‌ای که Java Keytool دارد، یک‌بار این فرمان را اجرا کنید:

```bash
keytool -genkeypair -v -keystore hosein-release.jks -storetype JKS -alias hosein-release -keyalg RSA -keysize 4096 -validity 10000
```

یک رمز قوی و ماندگار انتخاب کنید. برای جلوگیری از قفل‌شدن انتشارهای آینده، فایل `hosein-release.jks` و رمز آن را در دو محل امن و جداگانه پشتیبان‌گیری کنید. گم‌شدن کلید یعنی امکان به‌روزرسانی برنامه‌ای که با آن امضا شده از دست می‌رود.

## ثبت Secretها در GitHub

در مخزن به مسیر **Settings → Secrets and variables → Actions → New repository secret** بروید و چهار Secret زیر را بسازید:

| نام Secret | مقدار |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | محتوای Base64 فایل `hosein-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | رمز keystore |
| `ANDROID_KEY_ALIAS` | `hosein-release` |
| `ANDROID_KEY_PASSWORD` | رمز کلید (اگر هنگام ساخت جدا تعیین نکرده‌اید، همان رمز keystore) |

برای گرفتن مقدار Base64 در Linux/macOS:

```bash
base64 -w 0 hosein-release.jks
```

در Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\hosein-release.jks"))
```

مقدار Base64 را فقط در Secret مربوطه وارد کنید؛ آن را در فایل عمومی یا پیام commit قرار ندهید.

## ساخت و بررسی

پس از ثبت هر چهار Secret، commit انتشار با پیشوند `release: build APK` باعث ساخت APK یکپارچه و نسخه‌های معماری می‌شود. خط لوله، امضای هر APK را با Android SDK بررسی می‌کند و تا زمانی که همهٔ فایل‌ها گواهی یکسان نداشته باشند، آن‌ها را بارگذاری نمی‌کند. نبودن هر Secret نیز ساخت APK انتشار را متوقف می‌کند؛ دیگر از کلید موقت Android Debug برای خروجی انتشار استفاده نمی‌شود.

## مهاجرت یک‌باره از APKهای آزمایشی قدیمی

APKهای آزمایشی قبلی با کلیدهای موقت Runner امضا شده‌اند. اندروید اجازه نمی‌دهد نسخهٔ امضاشده با کلید جدید روی آن‌ها به‌صورت به‌روزرسانی نصب شود. پیش از حذف نسخهٔ قبلی، از داخل برنامه پشتیبان کامل بگیرید و فایل پشتیبان را خارج از فضای برنامه نگه دارید. پس از آن می‌توان نسخهٔ دارای امضای پایدار را نصب کرد؛ انتشارهای بعدی با همان keystore بدون تعویض برنامه به‌روزرسانی خواهند شد.
