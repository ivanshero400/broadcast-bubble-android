# فقاعة البث

تطبيق Android عربي لكتابة الأفكار وقراءتها أثناء البث. المشروع مستقل، ويحفظ الأفكار في مساحة التطبيق المحلية باستخدام Android `SharedPreferences`. لا يتصل التطبيق بالإنترنت ولا يحتاج إلى حساب.

## فتح المشروع وبناؤه

افتح هذا المجلد في Android Studio مع إضافة Flutter، أو ابنِ APK من PowerShell:

```powershell
flutter pub get
flutter build apk --release
```

ينتج ملف APK في:

```text
build\app\outputs\flutter-apk\app-release.apk
```

## تنزيل التطبيق

[تحميل APK لنظام Android](https://github.com/ivanshero400/broadcast-bubble-android/releases/download/v1.0.0/bubble-broadcast.apk)

## تشغيل الفقاعة

1. افتح التطبيق واضغط «منح الإذن وتشغيلها».
2. في إعداد Android، فعّل «السماح بالظهور فوق التطبيقات» لفقاعة البث.
3. ارجع إلى التطبيق؛ ستظهر الفقاعة فوق التطبيقات. اسحبها لتحريكها واضغطها لفتح لوحة القراءة.

تعمل الفقاعة عبر خدمة Android أمامية مع إشعار دائم. أوقفها من لوحة الفقاعة أو من إشعار الخدمة.
