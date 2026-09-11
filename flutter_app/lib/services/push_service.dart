import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is initialized by the application entry point before background use.
}

class PushService {
  final SupabaseClient sb;
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  PushService(this.sb);

  Future<void> initialize() async {
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final token = await messaging.getToken();
    await _saveToken(token);

    messaging.onTokenRefresh.listen(_saveToken);
  }

  Future<void> _saveToken(String? token) async {
    final user = sb.auth.currentUser;
    if (user == null || token == null || token.isEmpty) return;

    await sb.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }
}
