# QANOT Android starter

Ushbu papka QANOT ilovasining Flutter manba kodidir. Hozirgi versiya — ishlaydigan UI prototipi; operator tizimlariga real ulanish hali mavjud emas.

## Talablar
- Flutter SDK
- Android Studio (Android SDK bilan)
- Android telefon yoki emulator

## APK loyihasini tayyorlash
1. ZIP faylni chiqarib oling.
2. Terminal/CMD orqali `qanot_android_starter` papkasiga kiring.
3. Flutter o'rnatilganini tekshiring: `flutter doctor`
4. Android loyiha skeletini yarating: `flutter create --platforms=android .`
5. `pubspec.yaml` va `lib/main.dart` fayllarini shu ZIP dagi versiyalar bilan almashtiring (agar so'ralganda).
6. Paketlarni o'rnating: `flutter pub get`
7. Ishga tushiring: `flutter run`
8. APK yarating: `flutter build apk --release`
9. APK odatda `build/app/outputs/flutter-apk/app-release.apk` manzilida bo'ladi.

## Hozir ishlaydigan qismlar
- Bosh sahifa va pastki navigatsiya
- 5 ta operatorni ko'rish/tanlash
- Telefon raqamini prototip holatida kiritish
- Tarif/paket bo'limi
- Profil va xizmatlar haqida eslatmalar

## Keyingi bosqichlar
- Dizayn va foydalanish qulayligini sinash
- Operatorlar bilan rasmiy API/hamkorlikni aniqlash
- Backend, foydalanuvchi autentifikatsiyasi va ma'lumotlar bazasi
- To'lov provayderi integratsiyasi
- Maxfiylik siyosati, xavfsizlik tekshiruvi va ishlab chiqarishga tayyorlash

**Muhim:** haqiqiy balans, tarif shartlari, paket faollashtirish yoki to'lov muvaffaqiyatli bo'lgani haqidagi ma'lumotni operator/to'lov provayderidan tasdiqlanmaguncha ko'rsatmang.
