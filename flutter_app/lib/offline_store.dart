import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  static String _key(String uid, String conversationId) => 'gg_chat_${uid}_$conversationId';
  static String _homeKey(String uid) => 'gg_home_$uid';

  static Future<void> saveMessages(String uid, String conversationId, List<Map<String, dynamic>> messages) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(uid, conversationId), jsonEncode(messages));
  }

  static Future<List<Map<String, dynamic>>> loadMessages(String uid, String conversationId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(uid, conversationId));
    if (raw == null) return [];
    try { return List<Map<String, dynamic>>.from(jsonDecode(raw).map((x) => Map<String, dynamic>.from(x))); } catch (_) { return []; }
  }

  static Future<void> saveHome(String uid, List<Map<String, dynamic>> chats) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_homeKey(uid), jsonEncode(chats));
  }

  static Future<List<Map<String, dynamic>>> loadHome(String uid) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_homeKey(uid));
    if (raw == null) return [];
    try { return List<Map<String, dynamic>>.from(jsonDecode(raw).map((x) => Map<String, dynamic>.from(x))); } catch (_) { return []; }
  }
}
