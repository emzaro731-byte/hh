import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  static String _key(String uid, String conversationId) => 'gg_chat_${uid}_$conversationId';
  static String _homeKey(String uid) => 'gg_home_$uid';
  static String _dataKey(String uid, String name) => 'gg_data_${uid}_$name';

  static Future<void> saveMessages(String uid, String conversationId, List<Map<String, dynamic>> messages) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(uid, conversationId), jsonEncode(messages));
  }

  static Future<List<Map<String, dynamic>>> loadMessages(String uid, String conversationId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(uid, conversationId));
    return _decodeList(raw);
  }

  static Future<void> saveHome(String uid, List<Map<String, dynamic>> chats) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_homeKey(uid), jsonEncode(chats));
  }

  static Future<List<Map<String, dynamic>>> loadHome(String uid) async {
    final p = await SharedPreferences.getInstance();
    return _decodeList(p.getString(_homeKey(uid)));
  }

  // Generic persistent cache for app data that should still be available offline.
  static Future<void> saveData(String uid, String name, dynamic data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_dataKey(uid, name), jsonEncode(data));
  }

  static Future<dynamic> loadData(String uid, String name) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_dataKey(uid, name));
    if (raw == null) return null;
    try { return jsonDecode(raw); } catch (_) { return null; }
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return List<Map<String, dynamic>>.from(
        decoded.map((x) => Map<String, dynamic>.from(x as Map)),
      );
    } catch (_) {
      return [];
    }
  }
}
