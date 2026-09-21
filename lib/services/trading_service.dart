import 'dart:convert';
import 'package:http/http.dart' as http;

class TradingService {
  static const baseUrl = String.fromEnvironment(
    'TRADING_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  const TradingService();

  Map<String, String> get _headers => const {
    'Content-Type': 'application/json',
  };

  Uri _uri(String path) => Uri.parse(
    '${baseUrl.replaceAll(RegExp(r'/$'), '')}$path',
  );

  Future<dynamic> _get(String path) async {
    final response = await http.get(_uri(path), headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Trading API error ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Trading API error ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<List<dynamic>> markets() async =>
      (await _get('/api/markets'))['markets'] as List<dynamic>;

  Future<List<dynamic>> positions() async =>
      (await _get('/api/account/positions'))['positions'] as List<dynamic>;

  Future<Map<String, dynamic>> account() async =>
      Map<String, dynamic>.from(await _get('/api/account'));

  Future<Map<String, dynamic>> quote(String symbol) async =>
      Map<String, dynamic>.from(await _get('/api/quote/${Uri.encodeComponent(symbol)}'));

  Future<Map<String, dynamic>> placeOrder({
    required String symbol,
    required String side,
    required String quantity,
    required String orderType,
    String timeInForce = 'day',
  }) async {
    return Map<String, dynamic>.from(await _post('/api/orders', {
      'symbol': symbol,
      'side': side,
      'quantity': quantity,
      'type': orderType,
      'timeInForce': timeInForce,
    }));
  }
}
