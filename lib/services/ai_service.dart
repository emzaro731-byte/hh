import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const groqKey = String.fromEnvironment('GROQ_API_KEY');
  static const groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  const AiService();

  Future<String> chat({required List<Map<String, String>> messages}) async {
    if (groqKey.isEmpty) throw Exception('GROQ_API_KEY is not configured.');
    final response = await http.post(
      Uri.parse(groqEndpoint),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $groqKey'},
      body: jsonEncode({'model':'llama-3.3-70b-versatile','messages':messages,'temperature':0.7}),
    ).timeout(const Duration(seconds:60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Groq error ${response.statusCode}: ${response.body}');
    }
    final data=jsonDecode(response.body);
    return (data['choices']?[0]?['message']?['content'] ?? '').toString();
  }
}

class KieService {
  static const key = String.fromEnvironment('KIE_API_KEY');
  static const base = 'https://api.kie.ai';
  const KieService();

  Future<String> generateVideo(String prompt) async {
    if (key.isEmpty) throw Exception('KIE_API_KEY is not configured.');
    final r=await http.post(Uri.parse('$base/api/v1/runway/generate'),headers:_headers(),body:jsonEncode({'prompt':prompt,'duration':5,'quality':'720p','aspectRatio':'16:9'}));
    if(r.statusCode<200||r.statusCode>=300) throw Exception('KIE video error ${r.statusCode}: ${r.body}');
    final d=jsonDecode(r.body); return 'Video task created: ${d['data']?['taskId'] ?? 'unknown'}';
  }

  Future<String> generateImage(String prompt) async {
    if (key.isEmpty) throw Exception('KIE_API_KEY is not configured.');
    final r=await http.post(Uri.parse('$base/api/v1/4o-image/generate'),headers:_headers(),body:jsonEncode({'prompt':prompt}));
    if(r.statusCode<200||r.statusCode>=300) throw Exception('KIE image error ${r.statusCode}: ${r.body}');
    final d=jsonDecode(r.body); return 'Image task created: ${d['data']?['taskId'] ?? 'unknown'}';
  }

  Map<String,String> _headers()=>{'Content-Type':'application/json','Authorization':'Bearer $key'};
}
