import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://vihbsfrwnslnmheowkhy.supabase.co');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_j8gV4-PeFte1RMgl759uQQ_KrM_3vzK');
  const AiService();
  Map<String, String> get _headers => {'Content-Type': 'application/json', 'apikey': anonKey, 'Authorization': 'Bearer $anonKey'};
  Uri _fn(String name) => Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/functions/v1/$name');

  Future<dynamic> _post(String fn, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 90)}) async {
    final r = await http.post(_fn(fn), headers: _headers, body: jsonEncode(body)).timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('VEYLORA $fn error ${r.statusCode}: ${r.body}');
    return jsonDecode(r.body);
  }

  Future<String> chat({required List<Map<String, String>> messages, String model = 'openai/gpt-oss-120b'}) async {
    final data = await _post('chat', {'messages': messages, 'model': model});
    return (data['choices']?[0]?['message']?['content'] ?? '').toString();
  }

  Future<String> generateImage(String prompt, {String size = '1:1', bool enhance = true}) async {
    final data = await _post('generate-image', {'prompt': prompt, 'size': size, 'nVariants': 1, 'isEnhance': enhance}, timeout: const Duration(seconds: 60));
    return (data['data']?['taskId'] ?? data['taskId'] ?? '').toString();
  }

  Future<String> generateMusic(String prompt, {String duration = '30'}) async {
    final data = await _post('generate-music', {'prompt': prompt, 'duration': duration}, timeout: const Duration(seconds: 90));
    return (data['data']?['taskId'] ?? data['taskId'] ?? data['url'] ?? '').toString();
  }

  Future<String> generateVideo(String prompt, {String ratio = '16:9', int duration = 5, String resolution = '1080p'}) async {
    final data = await _post('generate-video', {'prompt': prompt, 'ratio': ratio, 'duration': duration, 'resolution': resolution}, timeout: const Duration(seconds: 60));
    return (data['data']?['taskId'] ?? data['taskId'] ?? '').toString();
  }
}
