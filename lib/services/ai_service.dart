import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const AiService();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': anonKey,
    'Authorization': 'Bearer $anonKey',
  };

  Uri _fn(String name) {
    if (supabaseUrl.isEmpty) throw Exception('SUPABASE_URL is not configured.');
    return Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/functions/v1/$name');
  }

  Future<String> chat({required List<Map<String, String>> messages}) async {
    final response = await http.post(_fn('chat'), headers: _headers, body: jsonEncode({'messages': messages})).timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('VEYLORA chat error ${response.statusCode}: ${response.body}');
    final data = jsonDecode(response.body);
    return (data['choices']?[0]?['message']?['content'] ?? '').toString();
  }

  Future<String> generateImage(String prompt, {String size = '1:1'}) async {
    final response = await http.post(_fn('generate-image'), headers: _headers, body: jsonEncode({'prompt': prompt, 'size': size, 'nVariants': 1, 'isEnhance': true})).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('KIE image error ${response.statusCode}: ${response.body}');
    final data = jsonDecode(response.body);
    return (data['data']?['taskId'] ?? '').toString();
  }

  Future<String> generateVideo(String prompt, {String ratio = '16:9'}) async {
    final response = await http.post(_fn('generate-video'), headers: _headers, body: jsonEncode({'prompt': prompt, 'ratio': ratio, 'duration': 5, 'resolution': '1080p'})).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('KIE video error ${response.statusCode}: ${response.body}');
    final data = jsonDecode(response.body);
    return (data['data']?['taskId'] ?? '').toString();
  }
}
