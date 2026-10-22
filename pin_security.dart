import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../services/qanot_api.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _hashKey = 'qanot.pin.hash.v2';
const _saltKey = 'qanot.pin.salt.v2';
const _legacyHashKey = 'qanot.pin.hash.v1';
const _legacySaltKey = 'qanot.pin.salt.v1';
const _biometricKey = 'qanot.pin.biometric.enabled.v1';
const _failedAttemptsKey = 'qanot.pin.failed.attempts.v1';
const _lockedUntilKey = 'qanot.pin.locked.until.v1';
const _accountEmailKey = 'qanot.account.recovery.email.v1';
const _pbkdf2Iterations = 120000;

class PinSecurity {
  static List<int> _deriveKey(String pin, String saltHex) {
    final password = utf8.encode(pin);
    final salt = <int>[];
    for (var i = 0; i < saltHex.length; i += 2) {
      salt.add(int.parse(saltHex.substring(i, i + 2), radix: 16));
    }
    final hmac = Hmac(sha256, password);
    final first = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    var u = first;
    final result = List<int>.from(first);
    for (var i = 1; i < _pbkdf2Iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Future<bool> isConfigured() async {
    final current = await _secureStorage.read(key: _hashKey) != null &&
        await _secureStorage.read(key: _saltKey) != null;
    final legacy = await _secureStorage.read(key: _legacyHashKey) != null &&
        await _secureStorage.read(key: _legacySaltKey) != null;
    return current || legacy;
  }

  static Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('PIN-kod aynan 4 ta raqamdan iborat bo‘lishi kerak.');
    }
    final random = Random.secure();
    final salt = _hex(List<int>.generate(16, (_) => random.nextInt(256)));
    final derived = _hex(_deriveKey(pin, salt));
    await _secureStorage.write(key: _saltKey, value: salt);
    await _secureStorage.write(key: _hashKey, value: derived);
    await clearFailedAttempts();
  }

  static Future<bool> verifyPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    final salt = await _secureStorage.read(key: _saltKey);
    final expected = await _secureStorage.read(key: _hashKey);
    if (salt != null && expected != null) {
      final actual = _hex(_deriveKey(pin, salt));
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
      }
      return difference == 0;
    }
    // Migrate PINs created by the earlier starter build without bypassing them.
    final oldSalt = await _secureStorage.read(key: _legacySaltKey);
    final oldHash = await _secureStorage.read(key: _legacyHashKey);
    if (oldSalt == null || oldHash == null) return false;
    final oldActual = sha256.convert(utf8.encode('$oldSalt:$pin')).toString();
    if (oldActual.length != oldHash.length) return false;
    var oldDifference = 0;
    for (var i = 0; i < oldActual.length; i++) {
      oldDifference |= oldActual.codeUnitAt(i) ^ oldHash.codeUnitAt(i);
    }
    if (oldDifference != 0) return false;
    await setPin(pin);
    await _secureStorage.delete(key: _legacySaltKey);
    await _secureStorage.delete(key: _legacyHashKey);
    return true;
  }

  static Future<int> failedAttempts() async =>
      int.tryParse(await _secureStorage.read(key: _failedAttemptsKey) ?? '0') ?? 0;

  static Future<DateTime?> lockedUntil() async {
    final value = int.tryParse(await _secureStorage.read(key: _lockedUntilKey) ?? '');
    if (value == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(value);
    if (DateTime.now().isAfter(until)) {
      await _secureStorage.delete(key: _lockedUntilKey);
      return null;
    }
    return until;
  }

  static Future<int> registerFailedAttempt() async {
    final count = (await failedAttempts()) + 1;
    await _secureStorage.write(key: _failedAttemptsKey, value: '$count');
    if (count >= 5) {
      await _secureStorage.write(
        key: _lockedUntilKey,
        value: '${DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch}',
      );
    }
    return count;
  }

  static Future<void> clearFailedAttempts() async {
    await _secureStorage.delete(key: _failedAttemptsKey);
    await _secureStorage.delete(key: _lockedUntilKey);
  }

  static Future<bool> biometricEnabled() async =>
      await _secureStorage.read(key: _biometricKey) == 'true';

  static Future<void> setBiometricEnabled(bool enabled) =>
      _secureStorage.write(key: _biometricKey, value: enabled ? 'true' : 'false');

  static Future<bool> biometricAvailable() async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() &&
          await auth.canCheckBiometrics &&
          (await auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: 'QANOT ilovasini ochish uchun barmoq izingizni tasdiqlang',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> linkedAccountEmail() =>
      _secureStorage.read(key: _accountEmailKey);

  static Future<void> linkAccountEmail(String email) =>
      _secureStorage.write(key: _accountEmailKey, value: email.trim().toLowerCase());

  static Future<void> unlinkAccount() => _secureStorage.delete(key: _accountEmailKey);

  static Future<void> resetPinAfterAccountVerification(String email, String password) async {
    final linkedEmail = await linkedAccountEmail();
    if (linkedEmail == null || linkedEmail != email.trim().toLowerCase()) {
      throw const QanotApiException('Bu qurilmaga bog‘langan akkaunt emailini kiriting.');
    }
    await QanotApi.verifyAccount(email: email, password: password);
    await _secureStorage.delete(key: _hashKey);
    await _secureStorage.delete(key: _saltKey);
    await clearFailedAttempts();
  }
}

class PinSecurityGate extends StatefulWidget {
  final Widget child;
  const PinSecurityGate({super.key, required this.child});

  @override
  State<PinSecurityGate> createState() => _PinSecurityGateState();
}

class _PinSecurityGateState extends State<PinSecurityGate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _configured = false;
  bool _unlocked = false;
  bool _confirming = false;
  bool _biometricAvailable = false;
  bool _handlingBiometric = false;
  String _digits = '';
  String _firstPin = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_unlocked && mounted) {
        setState(() {
          _unlocked = false;
          _digits = '';
          _error = '';
        });
      }
    } else if (state == AppLifecycleState.resumed && !_loading && _configured && !_unlocked) {
      _tryBiometric();
    }
  }

  Future<void> _initialize() async {
    final configured = await PinSecurity.isConfigured();
    final available = await PinSecurity.biometricAvailable();
    if (!mounted) return;
    setState(() {
      _configured = configured;
      _biometricAvailable = available;
      _loading = false;
    });
    if (configured && available && await PinSecurity.biometricEnabled()) {
      await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    if (_handlingBiometric || !_biometricAvailable || !await PinSecurity.biometricEnabled()) return;
    _handlingBiometric = true;
    final ok = await PinSecurity.authenticateBiometric();
    _handlingBiometric = false;
    if (ok && mounted) {
      await PinSecurity.clearFailedAttempts();
      setState(() => _unlocked = true);
    }
  }

  Future<void> _tapDigit(String digit) async {
    if (_digits.length >= 4) return;
    setState(() { _digits += digit; _error = ''; });
    if (_digits.length == 4) await _submitPin();
  }

  Future<void> _submitPin() async {
    final entered = _digits;
    setState(() => _digits = '');
    if (!_configured) {
      if (!_confirming) {
        setState(() { _firstPin = entered; _confirming = true; _error = 'PIN-kodni yana bir marta kiriting'; });
      } else if (entered == _firstPin) {
        await PinSecurity.setPin(entered);
        final canUseBio = _biometricAvailable && await PinSecurity.biometricAvailable();
        await PinSecurity.setBiometricEnabled(canUseBio);
        if (mounted) setState(() { _configured = true; _unlocked = true; _error = ''; });
      } else {
        setState(() { _firstPin = ''; _confirming = false; _error = 'Kodlar mos kelmadi. Qaytadan kiriting.'; });
      }
      return;
    }
    final until = await PinSecurity.lockedUntil();
    if (until != null) {
      final seconds = until.difference(DateTime.now()).inSeconds.clamp(1, 30);
      setState(() => _error = 'Ko‘p noto‘g‘ri urinish. $seconds soniyadan keyin urinib ko‘ring.');
      return;
    }
    final valid = await PinSecurity.verifyPin(entered);
    if (!mounted) return;
    if (valid) {
      await PinSecurity.clearFailedAttempts();
      setState(() { _unlocked = true; _error = ''; });
    } else {
      final count = await PinSecurity.registerFailedAttempt();
      final nowLocked = await PinSecurity.lockedUntil();
      setState(() => _error = nowLocked != null
          ? '5 marta noto‘g‘ri kiritildi. 30 soniya kuting.'
          : 'PIN-kod noto‘g‘ri. Qolgan urinishlar: ${5 - count}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final title = !_configured
        ? (_confirming ? 'PIN-kodni tasdiqlang' : 'QANOT uchun PIN yarating')
        : 'PIN-kodni kiriting';
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 76, height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF43D9F5), Color(0xFF658BFF)]),
                borderRadius: BorderRadius.circular(24)),
              child: const Icon(Icons.air_rounded, color: Color(0xFF071426), size: 44)),
            const SizedBox(height: 24),
            const Text('QANOT', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3)),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(!_configured ? '4 xonali kod tanlang.' : 'Ilovani ochish uchun kodni kiriting.',
              style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 9), width: 15, height: 15,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: i < _digits.length ? const Color(0xFF43D9F5) : Colors.white24,
                border: Border.all(color: const Color(0xFF43D9F5).withOpacity(.65))),
            ))),
            const SizedBox(height: 12),
            SizedBox(height: 36, child: Text(_error, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF8585), fontSize: 12))),
            const SizedBox(height: 8),
            ...[['1','2','3'], ['4','5','6'], ['7','8','9'], ['', '0', '⌫']].map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map((d) => SizedBox(
                width: 76, height: 56,
                child: d.isEmpty ? const SizedBox.shrink() : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: FilledButton.tonal(
                    onPressed: d == '⌫'
                      ? () => setState(() { if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1); _error = ''; })
                      : () => _tapDigit(d),
                    child: Text(d, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  ),
                ),
              )).toList()),
            )),
            if (_configured && _biometricAvailable) TextButton.icon(
              onPressed: _tryBiometric, icon: const Icon(Icons.fingerprint),
              label: const Text('Barmoq izi bilan ochish')),
            if (_configured) TextButton(onPressed: _showRecoveryDialog, child: const Text('PIN-kodni unutdingizmi?')),
          ],
        )),
      ))),
    );
  }

  Future<void> _showRecoveryDialog() async {
    final emailController = TextEditingController(text: await PinSecurity.linkedAccountEmail() ?? '');
    final passwordController = TextEditingController();
    var loading = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Akkaunt orqali PIN tiklash'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Bu qurilmaga oldindan bog‘langan QANOT akkauntining emaili va parolini kiriting.'),
          const SizedBox(height: 12),
          TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: passwordController, obscureText: true,
            decoration: const InputDecoration(labelText: 'Akkaunt paroli')),
          if (loading) const Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()),
        ]),
        actions: [
          TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: const Text('Bekor qilish')),
          FilledButton(onPressed: loading ? null : () async {
            setDialogState(() => loading = true);
            try {
              await PinSecurity.resetPinAfterAccountVerification(emailController.text, passwordController.text);
              if (!mounted) return;
              setState(() { _configured = false; _unlocked = false; _confirming = false; _firstPin = ''; _digits = ''; _error = ''; });
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => loading = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is QanotApiException ? e.message : 'Akkauntni tasdiqlash amalga oshmadi.')));
              }
            }
          }, child: const Text('Tasdiqlash va tiklash')),
        ],
      )),
    );
    emailController.dispose();
    passwordController.dispose();
  }
}

class PinSettingsScreen extends StatefulWidget {
  const PinSettingsScreen({super.key});
  @override
  State<PinSettingsScreen> createState() => _PinSettingsScreenState();
}

class _PinSettingsScreenState extends State<PinSettingsScreen> {
  bool _available = false;
  bool _enabled = false;
  bool _loading = true;
  String? _linkedEmail;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final available = await PinSecurity.biometricAvailable();
    final enabled = await PinSecurity.biometricEnabled();
    final email = await PinSecurity.linkedAccountEmail();
    if (mounted) setState(() { _available = available; _enabled = enabled; _linkedEmail = email; _loading = false; });
  }

  Future<String?> _askPin(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, obscureText: true,
          keyboardType: TextInputType.number, maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(hintText: '4 xonali PIN-kod', counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor qilish')),
          FilledButton(onPressed: () { if (controller.text.length == 4) Navigator.pop(ctx, controller.text); }, child: const Text('Tasdiqlash')),
        ],
      ));
    controller.dispose();
    return value;
  }

  Future<void> _changePin() async {
    final oldPin = await _askPin('Eski PIN-kod');
    if (oldPin == null || !mounted) return;
    final lockUntil = await PinSecurity.lockedUntil();
    if (lockUntil != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ko‘p noto‘g‘ri urinish bo‘ldi. Biroz kuting.')));
      return;
    }
    if (!await PinSecurity.verifyPin(oldPin)) {
      final count = await PinSecurity.registerFailedAttempt();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        count >= 5 ? 'Ko‘p urinish bo‘ldi. 30 soniya kuting.' : 'Eski PIN-kod noto‘g‘ri. Qolgan urinishlar: ${5 - count}.')));
      return;
    }
    await PinSecurity.clearFailedAttempts();
    final newPin = await _askPin('Yangi PIN-kod');
    if (newPin == null || !mounted) return;
    final confirm = await _askPin('Yangi PIN-kodni tasdiqlang');
    if (confirm == null || !mounted) return;
    if (newPin != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yangi kodlar mos kelmadi.')));
      return;
    }
    await PinSecurity.setPin(newPin);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN-kod muvaffaqiyatli o‘zgartirildi.')));
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && !(await PinSecurity.authenticateBiometric())) return;
    await PinSecurity.setBiometricEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _linkAccount() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var createAccount = false;
    var busy = false;
    await showDialog<void>(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('QANOT akkauntini bog‘lash'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Akkaunt PIN-kodni unutganda tiklash uchun kerak. Avval serverda akkaunt yarating yoki mavjud akkaunt bilan kiring.'),
          const SizedBox(height: 12),
          TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: passwordController, obscureText: true,
            decoration: const InputDecoration(labelText: 'Parol (kamida 10 belgi)')),
          SwitchListTile(value: createAccount, onChanged: busy ? null : (v) => setDialogState(() => createAccount = v),
            title: const Text('Yangi akkaunt yaratish'), contentPadding: EdgeInsets.zero),
          if (createAccount) TextField(controller: confirmController, obscureText: true,
            decoration: const InputDecoration(labelText: 'Parolni takrorlang')),
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()),
        ])),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Bekor qilish')),
          FilledButton(onPressed: busy ? null : () async {
            final email = emailController.text.trim().toLowerCase();
            final password = passwordController.text;
            if (!email.contains('@') || password.length < 10 || (createAccount && password != confirmController.text)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email yoki parolni tekshiring. Parol kamida 10 belgi bo‘lsin.')));
              return;
            }
            setDialogState(() => busy = true);
            try {
              if (createAccount) {
                await QanotApi.registerAccount(email: email, password: password);
              } else {
                await QanotApi.verifyAccount(email: email, password: password);
              }
              await PinSecurity.linkAccountEmail(email);
              if (mounted) setState(() => _linkedEmail = email);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akkaunt ushbu qurilmaga bog‘landi.')));
            } catch (e) {
              if (ctx.mounted) setDialogState(() => busy = false);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is QanotApiException ? e.message : 'Akkauntni bog‘lab bo‘lmadi. Server manzilini tekshiring.')));
            }
          }, child: const Text('Akkauntni bog‘lash')),
        ],
      )),
    );
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: const Text('Xavfsizlik')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const ListTile(leading: Icon(Icons.lock_outline), title: Text('Ilovaga kirish kodi'),
          subtitle: Text('4 xonali PIN-kod ilova ochilganda va qayta ochilganda so‘raladi.')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _changePin, icon: const Icon(Icons.password), label: const Text('PIN-kodni o‘zgartirish')),
        const SizedBox(height: 12),
        if (_available) SwitchListTile(value: _enabled, onChanged: _toggleBiometric,
          secondary: const Icon(Icons.fingerprint), title: const Text('Barmoq izi bilan kirish'),
          subtitle: const Text('Qurilmada biometrik himoya mavjud bo‘lsa ishlaydi.'))
        else const ListTile(leading: Icon(Icons.fingerprint), title: Text('Barmoq izi mavjud emas'),
          subtitle: Text('Telefon sozlamalarida biometrik himoyani sozlang yoki PIN-koddan foydalaning.')),
        const Divider(height: 28),
        ListTile(leading: const Icon(Icons.verified_user_outlined), title: const Text('QANOT akkaunti'),
          subtitle: Text(_linkedEmail ?? 'PIN-kodni tiklash uchun akkaunt bog‘lanmagan.'),
          trailing: const Icon(Icons.chevron_right), onTap: _linkAccount),
        const SizedBox(height: 16),
        const Text('PIN-kod qurilmadagi Android himoyalangan omborida saqlanadi. Akkaunt orqali tiklash ishlashi uchun QANOT backendini HTTPS hostingga joylashtirish va ilovada server manzilini sozlash shart.',
          style: TextStyle(color: Colors.white70, height: 1.5)),
      ]));
  }
}
