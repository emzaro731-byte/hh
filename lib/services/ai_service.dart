import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  final String endpoint;
  final String? apiKey;
  const AiService({required this.endpoint, this.apiKey});

  Future<String> chat({required List<Map<String, String>> messages}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: jsonEncode({'model': 'gpt-4o-mini', 'messages': messages, 'temperature': 0.7}),
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI server error ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    final text = data['choices']?[0]?['message']?['content'] ?? data['reply'] ?? data['text'];
    if (text == null) throw Exception('The AI server returned no message.');
    return text.toString();
  }
}
