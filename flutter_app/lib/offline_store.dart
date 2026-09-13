import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineStore {
  static String _key(String uid, String conversationId) => 'gg_chat_${uid}_$conversationId';
  static String _homeKey(String uid) => 'gg_home_$uid';
  static String _dataKey(String uid, String name) => 'gg_data_${uid}_$name';
  static String _outboxKey(String uid) => 'gg_outbox_$uid';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<void> saveMessages(String uid, String conversationId, List<Map<String, dynamic>> messages) async {
    final p = await _prefs();
    await p.setString(_key(uid, conversationId), jsonEncode(messages));
  }

  static Future<List<Map<String, dynamic>>> loadMessages(String uid, String conversationId) async {
    final p = await _prefs();
    return _decodeList(p.getString(_key(uid, conversationId)));
  }

  static Future<void> saveHome(String uid, List<Map<String, dynamic>> chats) async {
    final p = await _prefs();
    await p.setString(_homeKey(uid), jsonEncode(chats));
  }

  static Future<List<Map<String, dynamic>>> loadHome(String uid) async {
    final p = await _prefs();
    return _decodeList(p.getString(_homeKey(uid)));
  }

  static Future<void> saveData(String uid, String name, dynamic data) async {
    final p = await _prefs();
    await p.setString(_dataKey(uid, name), jsonEncode(data));
  }

  static Future<dynamic> loadData(String uid, String name) async {
    final p = await _prefs();
    final raw = p.getString(_dataKey(uid, name));
    if (raw == null) return null;
    try { return jsonDecode(raw); } catch (_) { return null; }
  }

  // Generic persistent cache for any screen that needs to survive a lost connection.
  static Future<void> saveCachedList(String uid, String name, List<Map<String, dynamic>> data) =>
      saveData(uid, 'cache_$name', data);

  static Future<List<Map<String, dynamic>>> loadCachedList(String uid, String name) async {
    final data = await loadData(uid, 'cache_$name');
    if (data is! List) return [];
    return _decodeList(jsonEncode(data));
  }

  // Persistent outbox. Messages stay here until Supabase confirms delivery.
  static Future<void> addOutbox(String uid, Map<String, dynamic> message) async {
    final items = await loadOutbox(uid);
    items.removeWhere((x) => x['local_id'] == message['local_id']);
    items.add(message);
    final p = await _prefs();
    await p.setString(_outboxKey(uid), jsonEncode(items));
  }

  static Future<List<Map<String, dynamic>>> loadOutbox(String uid) async {
    final p = await _prefs();
    return _decodeList(p.getString(_outboxKey(uid)));
  }

  static Future<void> removeOutbox(String uid, String localId) async {
    final items = await loadOutbox(uid);
    items.removeWhere((x) => x['local_id'] == localId);
    final p = await _prefs();
    await p.setString(_outboxKey(uid), jsonEncode(items));
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
