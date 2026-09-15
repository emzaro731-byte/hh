import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const publishableKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  const AiService();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': publishableKey,
    'Authorization': 'Bearer $publishableKey',
  };

  Uri _fn(String name) => Uri.parse(
    '${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/functions/v1/$name',
  );

  Future<dynamic> _post(
    String fn,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
      throw Exception('Missing Supabase configuration.');
    }
    final response = await http
        .post(_fn(fn), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('VEYLOLA $fn error ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<String> chat({
    required List<Map<String, String>> messages,
    String model = 'groq/compound',
  }) async {
    final data = await _post('chat', {'messages': messages, 'model': model});
    return (data['choices']?[0]?['message']?['content'] ?? '').toString();
  }

  Future<String> generateImage(
    String prompt, {
    String size = '1:1',
    bool enhance = true,
  }) async {
    final data = await _post(
      'generate-image',
      {'prompt': prompt, 'size': size, 'nVariants': 1, 'isEnhance': enhance},
      timeout: const Duration(seconds: 60),
    );
    return (data['data']?['taskId'] ?? data['taskId'] ?? '').toString();
  }

  Future<String> generateMusic(
    String prompt, {
    String duration = '30',
    bool customMode = false,
    bool instrumental = false,
    String style = 'Afrobeats, modern, polished, cinematic',
    String title = 'VEYLOLA',
    String model = 'V6',
  }) async {
    final data = await _post(
      'generate-music',
      {
        'prompt': prompt,
        'duration': int.tryParse(duration) ?? 30,
        'customMode': customMode,
        'instrumental': instrumental,
        'style': style,
        'title': title,
        'model': model,
      },
      timeout: const Duration(seconds: 90),
    );
    return (data['data']?['task_id'] ??
            data['data']?['taskId'] ??
            data['taskId'] ??
            data['url'] ??
            '')
        .toString();
  }

  Future<String> generateVideo(
    String prompt, {
    String ratio = '16:9',
    int duration = 5,
    String resolution = '1080p',
    String? imageUrl,
  }) async {
    final data = await _post(
      'generate-video',
      {
        'prompt': prompt,
        'ratio': ratio,
        'duration': duration,
        'resolution': resolution,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      },
      timeout: const Duration(seconds: 60),
    );
    return (data['data']?['task_id'] ??
            data['data']?['taskId'] ??
            data['taskId'] ??
            '')
        .toString();
  }
}
