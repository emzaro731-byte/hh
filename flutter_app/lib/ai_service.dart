import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIGeneration {
  final String? taskId;
  final String? status;
  final String? url;
  final List<String> urls;
  final String? message;
  final String? model;
  final dynamic raw;

  const AIGeneration({this.taskId, this.status, this.url, this.urls = const [], this.message, this.model, this.raw});

  factory AIGeneration.fromMap(Map<String, dynamic> data) => AIGeneration(
        taskId: data['taskId']?.toString(),
        status: data['status']?.toString(),
        url: data['url']?.toString(),
        urls: ((data['urls'] as List?) ?? const []).map((e) => e.toString()).toList(),
        message: data['message']?.toString(),
        model: data['model']?.toString(),
        raw: data['raw'],
      );
}

class AIService {
  static final _client = Supabase.instance.client;

  static Future<AIGeneration> generate(String type, String prompt, Map<String, dynamic> options) async {
    final response = await _client.functions.invoke('ai-generate', body: {
      'type': type,
      'prompt': prompt,
      'options': options,
    });
    final data = Map<String, dynamic>.from((response.data as Map?) ?? {});
    if (data['error'] != null) throw Exception(data['error'].toString());
    return AIGeneration.fromMap(data);
  }

  static Future<AIGeneration> status(String type, String taskId, Map<String, dynamic> options) async {
    final response = await _client.functions.invoke('ai-generate', body: {
      'action': 'status',
      'type': type,
      'taskId': taskId,
      'options': options,
    });
    final data = Map<String, dynamic>.from((response.data as Map?) ?? {});
    if (data['error'] != null) throw Exception(data['error'].toString());
    return AIGeneration.fromMap(data);
  }

  static Future<AIGeneration> waitForResult(String type, String taskId, Map<String, dynamic> options, void Function(String) onStatus) async {
    final started = DateTime.now();
    var delay = const Duration(seconds: 1);
    while (DateTime.now().difference(started) < const Duration(minutes: 15)) {
      final value = await status(type, taskId, options);
      onStatus(value.status == null ? 'Generating…' : 'Generating… ${value.status}');
      final state = (value.status ?? '').toLowerCase();
      if (value.url != null || value.urls.isNotEmpty || ['success', 'succeeded', 'complete', 'completed', 'first_success'].contains(state)) return value;
      if (['fail', 'failed', 'create_task_failed', 'generate_audio_failed', 'sensitive_word_error'].contains(state)) {
        throw Exception((value.raw is Map ? value.raw['data']?['errorMessage'] : null)?.toString() ?? 'Generation failed');
      }
      await Future<void>.delayed(delay);
      delay = Duration(milliseconds: (delay.inMilliseconds * 1.2).round().clamp(1000, 5000));
    }
    throw Exception('Generation timed out. Please try again.');
  }

  static Future<void> save(String type, String prompt, AIGeneration result, String model) async {
    final urls = result.urls.isNotEmpty ? result.urls : (result.url == null ? <String>[] : [result.url!]);
    await _client.functions.invoke('ai-save', body: {
      'type': type,
      'prompt': prompt,
      'model': model,
      'taskId': result.taskId,
      'urls': urls,
      'resultText': result.message,
    });
  }
}
