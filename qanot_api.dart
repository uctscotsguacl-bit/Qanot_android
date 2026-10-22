import 'dart:convert';
import 'package:http/http.dart' as http;

/// QANOT backend client.
/// Configure the real HTTPS backend URL at build time:
/// flutter build apk --release --dart-define=QANOT_API_BASE_URL=https://your-domain.example
class QanotApi {
  QanotApi._();

  static const String baseUrl = String.fromEnvironment(
    'QANOT_API_BASE_URL',
    defaultValue: 'https://YOUR-API-DOMAIN',
  );

  static Uri _uri(String path) {
    if (baseUrl.contains('YOUR-API-DOMAIN')) {
      throw const QanotApiException(
        'Backend manzili sozlanmagan. README_UZ.md faylidagi ko‘rsatmani bajaring.',
      );
    }
    return Uri.parse('$baseUrl$path');
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path);
    late final http.Response response;
    try {
      if (method == 'POST') {
        response = await http
            .post(uri,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      } else {
        response = await http.get(uri).timeout(const Duration(seconds: 20));
      }
    } catch (_) {
      throw const QanotApiException(
        'Serverga ulanib bo‘lmadi. Internet va server manzilini tekshiring.',
      );
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Do not expose raw server output to the app user.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data['detail'];
      throw QanotApiException(
        detail is String ? detail : 'So‘rov bajarilmadi (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  static Future<Map<String, dynamic>> health() => _request('GET', '/health');

  static Future<void> registerAccount({required String email, required String password}) async {
    await _request('POST', '/auth/account/register', body: {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  static Future<void> verifyAccount({required String email, required String password}) async {
    await _request('POST', '/auth/account/verify', body: {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  static Future<List<Map<String, dynamic>>> getTariffs() async {
    final result = await _request('GET', '/tariffs');
    final items = result['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  static Future<Map<String, dynamic>> checkBalance({
    required String phone,
    required String operator,
  }) => _request('POST', '/balance', body: {
        'phone': phone,
        'operator': operator,
      });

  static Future<Map<String, dynamic>> startSmsVerification({
    required String phone,
  }) => _request('POST', '/auth/sms/start', body: {'phone': phone});

  static Future<Map<String, dynamic>> verifySms({
    required String phone,
    required String code,
  }) => _request('POST', '/auth/sms/verify', body: {
        'phone': phone,
        'code': code,
      });

  static Future<Map<String, dynamic>> createPayment({
    required String phone,
    required int amountUzs,
    required String provider,
  }) => _request('POST', '/payments/create', body: {
        'phone': phone,
        'amount_uzs': amountUzs,
        'provider': provider,
      });

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final result = await _request('GET', '/transactions');
    final items = result['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }
}

class QanotApiException implements Exception {
  final String message;
  final int? statusCode;
  const QanotApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
