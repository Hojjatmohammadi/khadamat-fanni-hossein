# راهنمای کلید امضای دائمی اندروید

این کار فقط یک‌بار برای انتشار اولیه انجام می‌شود. فایل کلید و رمزهای آن باید متعلق به صاحب برنامه بمانند؛ از دست رفتن کلید می‌تواند به‌روزرسانی نسخه‌ای را که با همان کلید منتشر شده است مختل کند.

## ۱. ساخت کلید JKS

روی رایانه‌ای که Java و ابزار `keytool` نصب دارد، در یک پوشهٔ امن و خارج از مخزن GitHub این دستور را اجرا کنید:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

برای رمز مخزن و رمز کلید، رمزهای قوی و قابل نگهداری انتخاب کنید. نام مستعار کلید را دقیقاً `upload` بگذارید، مگر اینکه مقدار دیگری را در Secret مربوطه ثبت کنید.

## ۲. تبدیل فایل کلید به Base64

در Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\\upload-keystore.jks")) | Set-Content -NoNewline ".\\upload-keystore.base64.txt"
```

در Linux یا macOS:

```bash
base64 upload-keystore.jks | tr -d '\\r\\n' > upload-keystore.base64.txt
```

محتوای فایل متنی Base64 را کپی کنید. خود فایل JKS و فایل Base64 را در مخزن کد یا چت ارسال نکنید.

## ۳. ثبت چهار Secret در GitHub

در مخزن GitHub به مسیر زیر بروید:

`Settings → Secrets and variables → Actions → New repository secret`

چهار Secret زیر را بسازید:

| نام Secret | مقدار |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | تمام محتوای فایل Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | رمز مخزن JKS |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | رمز کلید |

رمزها و فایل کلید را در پیام یا Issue عمومی قرار ندهید. از فایل اصلی JKS و رمزهای آن دو نسخهٔ پشتیبان امن و جداگانه نگهداری کنید.

## ۴. اگر انتشار از Codemagic انجام می‌شود

در تنظیمات برنامهٔ Codemagic، بخش **Environment variables** یک گروه با نام دقیق `android-release-signing` بسازید. چهار متغیر بالا را با همان نام‌ها و مقادیر وارد کنید و گزینهٔ **Secret** را برای فایل Base64 و رمزها فعال کنید. نام مستعار هم باید با مقدار Secret برابر باشد.

فایل `codemagic.yaml` این گروه را با همین نام بارگذاری می‌کند؛ بنابراین نام گروه در Codemagic باید دقیقاً یکسان باشد. تنظیمات Java 17 نیز در فایل انتشار مشخص شده است.


## ۴. قواعد مهم برای به‌روزرسانی‌ها

- شناسهٔ بستهٔ برنامه در کد فعلی `com.khadamatfanni.khadamat_fanni_hossein` است؛ پس از انتشار اولیه نباید تغییر کند.
- در هر انتشار جدید، شمارهٔ ساخت بعد از علامت `+` در `pubspec.yaml` باید از نسخهٔ قبلی بیشتر باشد.
- کلید تازه نسازید و کلید فعلی را جایگزین نکنید؛ همهٔ نسخه‌های بعدی باید با همان کلید امضا شوند.
- فرایند انتشار در صورت نبودن یا نامعتبر بودن هر یک از چهار Secret متوقف می‌شود.
- کلید و فایل `key.properties` فقط در محیط موقت GitHub Actions ساخته می‌شوند و نباید در Artifact خروجی قرار گیرند.
